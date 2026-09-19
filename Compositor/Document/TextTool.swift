import AppKit
import CoreText
import SwiftUI

nonisolated enum LayerTextAlignment: String, CaseIterable, Codable, Sendable {
    case left = "Left"
    case center = "Center"
    case right = "Right"
    case justified = "Justified"

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }

    var icon: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        case .justified: return "text.justify"
        }
    }
}

/// What a text layer draws, kept so the text can be edited and re-rendered with new styles.
nonisolated struct LayerTextStyle: Codable, Equatable, Sendable {
    var text: String = "Sample Text"
    var fontFamily: String = "Helvetica Neue"
    var fontStyle: String = "Regular"
    var fontSize: CGFloat = 36
    /// Nil means Auto leading.
    var leading: CGFloat? = nil
    /// Tracking in 1/1000 em (Photoshop units: -100...100+).
    var tracking: CGFloat = 0
    /// Vertical scale percentage (100 = normal).
    var verticalScale: CGFloat = 100
    /// Horizontal scale percentage (100 = normal).
    var horizontalScale: CGFloat = 100
    /// Baseline shift in points (0 = normal).
    var baselineShift: CGFloat = 0
    /// Text color channels (sRGB).
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 1

    // Character toggle styles
    var isFauxBold: Bool = false
    var isFauxItalic: Bool = false
    var isAllCaps: Bool = false
    var isSmallCaps: Bool = false
    var isSuperscript: Bool = false
    var isSubscript: Bool = false
    var isUnderline: Bool = false
    var isStrikethrough: Bool = false

    // Paragraph
    var alignment: LayerTextAlignment = .left

    var color: PaletteColor {
        PaletteColor(red: red, green: green, blue: blue)
    }

    func makeAttributedString() -> NSAttributedString {
        var baseFont = FontHelper.font(family: fontFamily, style: fontStyle, size: fontSize)

        var traits: NSFontDescriptor.SymbolicTraits = []
        if isFauxBold { traits.insert(.bold) }
        if isFauxItalic { traits.insert(.italic) }
        if !traits.isEmpty {
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            baseFont = NSFont(descriptor: descriptor, size: fontSize) ?? baseFont
        }

        var effectiveSize = fontSize
        if isSuperscript || isSubscript {
            effectiveSize = max(4, fontSize * 0.65)
            baseFont = NSFont(descriptor: baseFont.fontDescriptor, size: effectiveSize) ?? baseFont
        }

        var renderedString = text.isEmpty ? " " : text
        if isAllCaps {
            renderedString = renderedString.uppercased()
        }

        var attributes: [NSAttributedString.Key: Any] = [:]
        attributes[.font] = baseFont
        attributes[.foregroundColor] = NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)

        if tracking != 0 {
            attributes[.kern] = (tracking * fontSize) / 1000.0
        }

        if isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        var totalBaselineShift = baselineShift
        if isSuperscript {
            totalBaselineShift += fontSize * 0.35
        } else if isSubscript {
            totalBaselineShift -= fontSize * 0.15
        }
        if totalBaselineShift != 0 {
            attributes[.baselineOffset] = totalBaselineShift
        }

        let para = NSMutableParagraphStyle()
        para.alignment = alignment.nsTextAlignment
        if let leading = leading, leading > 0 {
            para.minimumLineHeight = leading
            para.maximumLineHeight = leading
            para.lineSpacing = 0
        }
        attributes[.paragraphStyle] = para

        return NSAttributedString(string: renderedString, attributes: attributes)
    }
}

/// A layer made with the Text tool. Its pixels are an ordinary raster, so it clips, masks, blends and filters like
/// any layer; `image` is the raster the text drew.
nonisolated struct LayerText: Equatable, @unchecked Sendable {
    var style: LayerTextStyle
    let image: CGImage
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.style == rhs.style && lhs.image === rhs.image }
    static func loaded(_ style: LayerTextStyle?, image: CGImage?) -> LayerText? {
        guard let style, let image else { return nil }
        return LayerText(style: style, image: image)
    }
}

extension ImageLayer {
    /// The text this layer still is: nil once its pixels were edited some other way.
    var liveText: LayerText? {
        guard let text, let image = asset?.image, image === text.image else { return nil }
        return text
    }
}

nonisolated enum FontHelper {
    static var availableFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static func styles(for family: String) -> [String] {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family), !members.isEmpty else {
            return ["Regular"]
        }
        var results: [String] = []
        for member in members {
            if let array = member as? [AnyObject], array.count > 1, let styleName = array[1] as? String {
                results.append(styleName)
            }
        }
        return results.isEmpty ? ["Regular"] : results
    }

    static func font(family: String, style: String, size: CGFloat) -> NSFont {
        if let members = NSFontManager.shared.availableMembers(ofFontFamily: family) {
            for member in members {
                if let array = member as? [AnyObject], array.count > 1,
                   let postScriptName = array[0] as? String,
                   let styleName = array[1] as? String,
                   styleName.caseInsensitiveCompare(style) == .orderedSame {
                    if let font = NSFont(name: postScriptName, size: size) {
                        return font
                    }
                }
            }
        }
        if let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }
}

extension EditorSession {
    /// Text raster generation: creates a crisp CGImage of the rendered attributed text.
    static func textImage(for style: LayerTextStyle) throws -> (image: CGImage, size: CGSize) {
        let attrString = style.makeAttributedString()
        guard attrString.length > 0 else {
            let context = try BrushRaster.context(width: 1, height: 1, mask: false)
            guard let image = context.makeImage() else { throw ExportError.render }
            return (image, CGSize(width: 1, height: 1))
        }

        let bounds = attrString.boundingRect(with: CGSize(width: 10_000, height: 10_000),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading])

        let hScale = max(0.1, style.horizontalScale / 100.0)
        let vScale = max(0.1, style.verticalScale / 100.0)

        let padX: CGFloat = 8.0
        let padY: CGFloat = 8.0
        let rawW = ceil(bounds.width) + padX * 2
        let rawH = ceil(bounds.height) + padY * 2

        let scaledW = max(1, Int(ceil(rawW * hScale)))
        let scaledH = max(1, Int(ceil(rawH * vScale)))

        guard scaledW * scaledH <= Self.maxShapePixels else {
            throw ProjectError.tooLarge
        }

        let context = try BrushRaster.context(width: scaledW, height: scaledH, mask: false)

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        context.saveGState()
        context.scaleBy(x: hScale, y: vScale)

        let drawRect = CGRect(x: (padX - bounds.minX) / hScale, y: (padY - bounds.minY) / vScale, width: ceil(bounds.width), height: ceil(bounds.height))
        attrString.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else { throw ExportError.render }
        return (image, CGSize(width: CGFloat(scaledW), height: CGFloat(scaledH)))
    }

    /// Construct a `LayerTextStyle` from the session's active text tool settings.
    func currentTextStyle(overrideText: String? = nil) -> LayerTextStyle {
        var style = LayerTextStyle()
        style.text = overrideText ?? textContent
        style.fontFamily = textFontFamily
        style.fontStyle = textFontStyle
        style.fontSize = textFontSize
        style.leading = textLeadingAuto ? nil : textLeading
        style.tracking = textTracking
        style.verticalScale = textVerticalScale
        style.horizontalScale = textHorizontalScale
        style.baselineShift = textBaselineShift
        style.red = foregroundColor.red
        style.green = foregroundColor.green
        style.blue = foregroundColor.blue
        style.alpha = 1
        style.isFauxBold = textFauxBold
        style.isFauxItalic = textFauxItalic
        style.isAllCaps = textAllCaps
        style.isSmallCaps = textSmallCaps
        style.isSuperscript = textSuperscript
        style.isSubscript = textSubscript
        style.isUnderline = textUnderline
        style.isStrikethrough = textStrikethrough
        style.alignment = textAlignment
        return style
    }

    /// Sync session's text properties from an existing text layer.
    func loadTextStyleFromActiveLayer() {
        guard let layer = activeLayer, let text = layer.liveText else { return }
        let style = text.style
        textContent = style.text
        textFontFamily = style.fontFamily
        textFontStyle = style.fontStyle
        textFontSize = style.fontSize
        if let leading = style.leading {
            textLeadingAuto = false
            textLeading = leading
        } else {
            textLeadingAuto = true
        }
        textTracking = style.tracking
        textVerticalScale = style.verticalScale
        textHorizontalScale = style.horizontalScale
        textBaselineShift = style.baselineShift
        textFauxBold = style.isFauxBold
        textFauxItalic = style.isFauxItalic
        textAllCaps = style.isAllCaps
        textSmallCaps = style.isSmallCaps
        textSuperscript = style.isSuperscript
        textSubscript = style.isSubscript
        textUnderline = style.isUnderline
        textStrikethrough = style.isStrikethrough
        textAlignment = style.alignment
        foregroundColor = style.color
    }

    /// Begins inline canvas editing for the text layer with `layerID`.
    func beginTextEdit(layerID: UUID) {
        guard canEditLayers, let layer = document?.layers.first(where: { $0.id == layerID }), layer.liveText != nil else { return }
        if textEditingLayerID != layerID {
            endTextEdit(commitUndo: false)
        }
        selectLayer(layerID)
        loadTextStyleFromActiveLayer()
        textEditingLayerID = layerID
    }

    /// Ends inline text editing, optionally committing an undo transaction if edits occurred.
    func endTextEdit(commitUndo: Bool = true) {
        guard textEditingLayerID != nil else { return }
        textEditingLayerID = nil
        if commitUndo {
            beginEdit("Type Edit")
            endEdit()
        }
    }

    /// Adds a new text layer at `point` in document coordinates and starts inline editing.
    func addTextLayer(at point: CGPoint, content: String? = nil) {
        guard canEditLayers, document != nil else { return }
        let textString = content ?? (textContent.isEmpty ? "Sample Text" : textContent)
        var style = currentTextStyle(overrideText: textString)
        style.red = foregroundColor.red
        style.green = foregroundColor.green
        style.blue = foregroundColor.blue

        do {
            let rendered = try Self.textImage(for: style)
            let origin = CGPoint(x: point.x.rounded(), y: point.y.rounded())
            let name = nextTextName(for: textString)
            addPixelLayer(rendered.image, at: origin, name: name, editName: "Type Tool",
                          dropsSelection: false, text: LayerText(style: style, image: rendered.image))
            textContent = textString
            if let activeID = activeLayerID {
                beginTextEdit(layerID: activeID)
            }
        } catch {
            brushError = error.localizedDescription
        }
    }

    /// Updates the active layer's text style, re-renders the raster image, and commits the edit.
    func updateActiveText(registerUndo: Bool = true, mutate: (inout LayerTextStyle) -> Void) {
        guard let activeID = activeLayerID,
              let index = document?.layers.firstIndex(where: { $0.id == activeID }),
              let layer = document?.layers[index],
              let text = layer.liveText else { return }

        var newStyle = text.style
        mutate(&newStyle)

        do {
            let rendered = try Self.textImage(for: newStyle)
            guard let thumbnail = try? PixelInvert.thumbnail(of: rendered.image) else { return }

            if registerUndo {
                beginEdit("Type Edit")
            }

            var updatedLayer = layer
            updatedLayer.asset = ImportedImage(image: rendered.image, thumbnail: thumbnail, name: layer.name)
            updatedLayer.transform = LayerTransform(origin: layer.origin, size: rendered.size)
            updatedLayer.text = LayerText(style: newStyle, image: rendered.image)
            document?.layers[index] = updatedLayer

            if registerUndo {
                endEdit()
            }
        } catch {
            brushError = error.localizedDescription
        }
    }

    /// Returns a layer name based on the text content, e.g. "Sample Text" or "Text 1".
    func nextTextName(for content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let preview = String(trimmed.prefix(24))
            let names = Set(document?.layers.map(\.name) ?? [])
            if !names.contains(preview) { return preview }
            var number = 2
            while names.contains("\(preview) \(number)") { number += 1 }
            return "\(preview) \(number)"
        }
        let names = Set(document?.layers.map(\.name) ?? [])
        var number = 1
        while names.contains("Text \(number)") { number += 1 }
        return "Text \(number)"
    }
}
