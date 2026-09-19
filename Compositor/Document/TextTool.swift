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

nonisolated enum TextStrokePosition: String, CaseIterable, Codable, Sendable {
    case outside = "Outside"
    case center = "Center"
    case inside = "Inside"
}

/// What a text layer draws, kept so the text can be edited and re-rendered with new styles.
nonisolated struct LayerTextStyle: Codable, Equatable, Sendable {
    var text: String = ""
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

    // Stroke
    var strokeWidth: CGFloat = 0
    var strokePosition: TextStrokePosition = .outside
    var strokeRed: CGFloat = 0
    var strokeGreen: CGFloat = 0
    var strokeBlue: CGFloat = 0
    var strokeAlpha: CGFloat = 1

    var color: PaletteColor {
        PaletteColor(red: red, green: green, blue: blue)
    }

    var strokeColor: PaletteColor {
        PaletteColor(red: strokeRed, green: strokeGreen, blue: strokeBlue)
    }

    enum CodingKeys: String, CodingKey {
        case text, fontFamily, fontStyle, fontSize, leading, tracking
        case verticalScale, horizontalScale, baselineShift
        case red, green, blue, alpha
        case isFauxBold, isFauxItalic, isAllCaps, isSmallCaps
        case isSuperscript, isSubscript, isUnderline, isStrikethrough
        case alignment
        case strokeWidth, strokePosition, strokeRed, strokeGreen, strokeBlue, strokeAlpha
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "Helvetica Neue"
        fontStyle = try container.decodeIfPresent(String.self, forKey: .fontStyle) ?? "Regular"
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 36
        leading = try container.decodeIfPresent(CGFloat.self, forKey: .leading)
        tracking = try container.decodeIfPresent(CGFloat.self, forKey: .tracking) ?? 0
        verticalScale = try container.decodeIfPresent(CGFloat.self, forKey: .verticalScale) ?? 100
        horizontalScale = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalScale) ?? 100
        baselineShift = try container.decodeIfPresent(CGFloat.self, forKey: .baselineShift) ?? 0
        red = try container.decodeIfPresent(CGFloat.self, forKey: .red) ?? 0
        green = try container.decodeIfPresent(CGFloat.self, forKey: .green) ?? 0
        blue = try container.decodeIfPresent(CGFloat.self, forKey: .blue) ?? 0
        alpha = try container.decodeIfPresent(CGFloat.self, forKey: .alpha) ?? 1
        isFauxBold = try container.decodeIfPresent(Bool.self, forKey: .isFauxBold) ?? false
        isFauxItalic = try container.decodeIfPresent(Bool.self, forKey: .isFauxItalic) ?? false
        isAllCaps = try container.decodeIfPresent(Bool.self, forKey: .isAllCaps) ?? false
        isSmallCaps = try container.decodeIfPresent(Bool.self, forKey: .isSmallCaps) ?? false
        isSuperscript = try container.decodeIfPresent(Bool.self, forKey: .isSuperscript) ?? false
        isSubscript = try container.decodeIfPresent(Bool.self, forKey: .isSubscript) ?? false
        isUnderline = try container.decodeIfPresent(Bool.self, forKey: .isUnderline) ?? false
        isStrikethrough = try container.decodeIfPresent(Bool.self, forKey: .isStrikethrough) ?? false
        alignment = try container.decodeIfPresent(LayerTextAlignment.self, forKey: .alignment) ?? .left
        strokeWidth = try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokePosition = try container.decodeIfPresent(TextStrokePosition.self, forKey: .strokePosition) ?? .outside
        strokeRed = try container.decodeIfPresent(CGFloat.self, forKey: .strokeRed) ?? 0
        strokeGreen = try container.decodeIfPresent(CGFloat.self, forKey: .strokeGreen) ?? 0
        strokeBlue = try container.decodeIfPresent(CGFloat.self, forKey: .strokeBlue) ?? 0
        strokeAlpha = try container.decodeIfPresent(CGFloat.self, forKey: .strokeAlpha) ?? 1
    }

    func makeAttributedString(scale: CGFloat = 1.0, overrideText: String? = nil, forStroke: Bool = false) -> NSAttributedString {
        let textToUse = overrideText ?? text
        let effectiveFontSize = max(1, fontSize * scale)
        var baseFont = FontHelper.font(family: fontFamily, style: fontStyle, size: effectiveFontSize)

        var traits: NSFontDescriptor.SymbolicTraits = []
        if isFauxBold { traits.insert(.bold) }
        if isFauxItalic { traits.insert(.italic) }
        if !traits.isEmpty {
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            baseFont = NSFont(descriptor: descriptor, size: effectiveFontSize) ?? baseFont
        }

        var effectiveSize = effectiveFontSize
        if isSuperscript || isSubscript {
            effectiveSize = max(4, effectiveFontSize * 0.65)
            baseFont = NSFont(descriptor: baseFont.fontDescriptor, size: effectiveSize) ?? baseFont
        }

        var renderedString = textToUse
        if isAllCaps {
            renderedString = renderedString.uppercased()
        }

        var attributes: [NSAttributedString.Key: Any] = [:]
        attributes[.font] = baseFont
        attributes[.foregroundColor] = NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)

        if tracking != 0 {
            attributes[.kern] = (tracking * effectiveFontSize) / 1000.0
        }

        if isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        var totalBaselineShift = baselineShift * scale
        if isSuperscript {
            totalBaselineShift += effectiveFontSize * 0.35
        } else if isSubscript {
            totalBaselineShift -= effectiveFontSize * 0.15
        }
        if totalBaselineShift != 0 {
            attributes[.baselineOffset] = totalBaselineShift
        }

        let para = NSMutableParagraphStyle()
        para.alignment = alignment.nsTextAlignment
        if let leading = leading, leading > 0 {
            let scaledLeading = leading * scale
            para.minimumLineHeight = scaledLeading
            para.maximumLineHeight = scaledLeading
            para.lineSpacing = 0
        }
        attributes[.paragraphStyle] = para

        if strokeWidth > 0 {
            let strokeColor = NSColor(srgbRed: strokeRed, green: strokeGreen, blue: strokeBlue, alpha: strokeAlpha)
            if forStroke {
                let strokeW = (strokePosition == .outside ? strokeWidth * 2 : strokeWidth) * scale
                attributes[.strokeWidth] = strokeW
                attributes[.strokeColor] = strokeColor
                attributes[.foregroundColor] = strokeColor
            } else if strokePosition == .center || strokePosition == .inside {
                attributes[.strokeWidth] = -(strokeWidth * scale)
                attributes[.strokeColor] = strokeColor
            }
        }

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
        let hScale = max(0.1, style.horizontalScale / 100.0)
        let vScale = max(0.1, style.verticalScale / 100.0)
        let defaultW = max(1, Int(ceil(max(120, style.fontSize * 3) * hScale)))
        let defaultH = max(1, Int(ceil(max(32, style.fontSize * 1.3) * vScale)))

        if style.text.isEmpty {
            let context = try BrushRaster.context(width: defaultW, height: defaultH, mask: false)
            guard let image = context.makeImage() else { throw ExportError.render }
            return (image, CGSize(width: CGFloat(defaultW), height: CGFloat(defaultH)))
        }

        let attrString = style.makeAttributedString()
        guard attrString.length > 0 else {
            let context = try BrushRaster.context(width: defaultW, height: defaultH, mask: false)
            guard let image = context.makeImage() else { throw ExportError.render }
            return (image, CGSize(width: CGFloat(defaultW), height: CGFloat(defaultH)))
        }

        let extraPad = max(0, style.strokeWidth)
        let padX: CGFloat = 8.0 + extraPad
        let padY: CGFloat = 8.0 + extraPad
        let bounds = attrString.boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textW = ceil(bounds.width)
        let textH = ceil(bounds.height)
        let rawW = textW + padX * 2
        let rawH = textH + padY * 2

        let scaledW = max(1, Int(ceil(rawW * hScale)))
        let scaledH = max(1, Int(ceil(rawH * vScale)))

        guard scaledW * scaledH <= Self.maxShapePixels else {
            throw ProjectError.tooLarge
        }

        let context = try BrushRaster.context(width: scaledW, height: scaledH, mask: false)

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(true)
        context.setShouldSubpixelQuantizeFonts(true)
        context.interpolationQuality = .high

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        nsContext.imageInterpolation = .high
        nsContext.shouldAntialias = true
        NSGraphicsContext.current = nsContext

        context.saveGState()
        context.scaleBy(x: hScale, y: vScale)

        let originX = ((padX - bounds.minX) / hScale).rounded()
        let originY = ((padY - bounds.minY) / vScale).rounded()
        let drawRect = CGRect(x: originX, y: originY, width: textW + 4, height: textH + 4)

        if style.strokeWidth > 0 && style.strokePosition == .outside {
            let strokeAttr = style.makeAttributedString(forStroke: true)
            strokeAttr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        let fillAttr = style.makeAttributedString(forStroke: false)
        fillAttr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

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
        style.strokeWidth = textStrokeWidth
        style.strokePosition = textStrokePosition
        style.strokeRed = textStrokeRed
        style.strokeGreen = textStrokeGreen
        style.strokeBlue = textStrokeBlue
        style.strokeAlpha = textStrokeAlpha
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
        textStrokeWidth = style.strokeWidth
        textStrokePosition = style.strokePosition
        textStrokeRed = style.strokeRed
        textStrokeGreen = style.strokeGreen
        textStrokeBlue = style.strokeBlue
        textStrokeAlpha = style.strokeAlpha
        foregroundColor = style.color
    }

    /// Begins inline canvas editing for the text layer with `layerID`.
    func beginTextEdit(layerID: UUID, isNewLayer: Bool = false) {
        guard canEditLayers, let layer = document?.layers.first(where: { $0.id == layerID }), layer.liveText != nil else { return }
        if textEditingLayerID != layerID {
            commitTextEdit()
        }
        selectLayer(layerID)
        loadTextStyleFromActiveLayer()
        textEditingLayerID = layerID
        initialEditingText = layer.liveText?.style.text
        textEditIsNewLayer = isNewLayer
    }

    /// Commits inline text editing, finalizing the raster and registering an undo transaction if modified.
    func commitTextEdit() {
        guard let editingID = textEditingLayerID else { return }
        textEditingLayerID = nil

        let trimmed = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && textEditIsNewLayer {
            deleteLayer(editingID)
        } else {
            if let index = document?.layers.firstIndex(where: { $0.id == editingID }) {
                let currentName = document?.layers[index].name ?? ""
                if (currentName.hasPrefix("Text ") || textEditIsNewLayer) && !trimmed.isEmpty {
                    document?.layers[index].name = String(trimmed.prefix(24))
                }
            }
            if initialEditingText != textContent {
                beginEdit("Type Edit")
                endEdit()
            }
        }
        initialEditingText = nil
        textEditIsNewLayer = false
        textContent = ""
    }

    /// Cancels inline text editing, restoring previous text or removing the layer if it was freshly created.
    func cancelTextEdit() {
        guard let editingID = textEditingLayerID else { return }
        textEditingLayerID = nil

        if textEditIsNewLayer {
            deleteLayer(editingID)
        } else if let initial = initialEditingText {
            updateActiveText(registerUndo: false) { $0.text = initial }
        }
        initialEditingText = nil
        textEditIsNewLayer = false
        textContent = ""
    }

    /// Ends inline text editing, committing by default or cancelling if requested.
    func endTextEdit(commitUndo: Bool = true) {
        if commitUndo {
            commitTextEdit()
        } else {
            cancelTextEdit()
        }
    }

    /// Adds a new text layer at `point` in document coordinates and starts inline editing.
    func addTextLayer(at point: CGPoint, content: String = "") {
        guard canEditLayers, document != nil else { return }
        let textString = content
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
                beginTextEdit(layerID: activeID, isNewLayer: true)
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
            refreshCanvasPreview?()
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
