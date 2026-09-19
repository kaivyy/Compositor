import Testing
import AppKit
@testable import Compositor

@Suite struct TextToolTests {
    @Test func defaultLayerTextStyleProperties() {
        let style = LayerTextStyle()
        #expect(style.text == "")
        #expect(style.fontFamily == "Helvetica Neue")
        #expect(style.fontStyle == "Regular")
        #expect(style.fontSize == 36)
        #expect(style.leading == nil)
        #expect(style.tracking == 0)
        #expect(style.verticalScale == 100)
        #expect(style.horizontalScale == 100)
        #expect(style.baselineShift == 0)
        #expect(style.isFauxBold == false)
        #expect(style.isFauxItalic == false)
        #expect(style.isAllCaps == false)
        #expect(style.isUnderline == false)
        #expect(style.isStrikethrough == false)
        #expect(style.alignment == .left)
    }

    @Test func fontHelperReturnsInstalledFonts() {
        let families = FontHelper.availableFamilies
        #expect(!families.isEmpty)
        #expect(families.contains("Helvetica") || families.contains("Helvetica Neue") || families.contains("Arial"))

        let styles = FontHelper.styles(for: "Helvetica")
        #expect(!styles.isEmpty)
    }

    @Test func attributedStringFormatting() {
        var style = LayerTextStyle()
        style.text = "Hello World"
        style.fontSize = 24
        style.isAllCaps = true
        style.isUnderline = true
        style.isStrikethrough = true
        style.tracking = 50
        style.baselineShift = 4
        style.alignment = .center

        let attrString = style.makeAttributedString()
        #expect(attrString.string == "HELLO WORLD")

        let attrs = attrString.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attrs[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attrs[.baselineOffset] as? CGFloat == 4)
        #expect(attrs[.kern] as? CGFloat == (50 * 24) / 1000.0)

        let para = attrs[.paragraphStyle] as? NSParagraphStyle
        #expect(para?.alignment == .center)
    }

    @Test func textRasterRenderingProducesValidCGImage() throws {
        var style = LayerTextStyle()
        style.text = "Compositor Type"
        style.fontSize = 32
        style.red = 1
        style.green = 0
        style.blue = 0

        let result = try EditorSession.textImage(for: style)
        #expect(result.image.width > 0)
        #expect(result.image.height > 0)
        #expect(result.size.width > 0)
        #expect(result.size.height > 0)
    }

    @Test func textRasterOrientationIsRightSideUpAndLeftToRight() throws {
        var style = LayerTextStyle()
        style.text = "L"
        style.fontFamily = "Helvetica"
        style.fontStyle = "Bold"
        style.fontSize = 64
        style.red = 0
        style.green = 0
        style.blue = 0
        style.alpha = 1.0

        let (image, size) = try EditorSession.textImage(for: style)
        let w = image.width
        let h = image.height
        #expect(w > 20 && h > 20)

        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            Issue.record("Failed to read image data")
            return
        }

        let bytesPerRow = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8

        func alphaAt(x: Int, y: Int) -> UInt8 {
            guard x >= 0, x < w, y >= 0, y < h else { return 0 }
            let offset = y * bytesPerRow + x * bpp
            return ptr[offset + 3]
        }

        var hasTopLeft = false
        var hasTopRight = false
        var hasBottomLeft = false
        var hasBottomRight = false

        for y in 0..<(h / 3) {
            for x in 0..<(w / 2) {
                if alphaAt(x: x, y: y) > 100 { hasTopLeft = true }
            }
            for x in (w / 2)..<w {
                if alphaAt(x: x, y: y) > 100 { hasTopRight = true }
            }
        }

        for y in (2 * h / 3)..<h {
            for x in 0..<(w / 2) {
                if alphaAt(x: x, y: y) > 100 { hasBottomLeft = true }
            }
            for x in (w / 2)..<(w - 8) {
                if alphaAt(x: x, y: y) > 100 { hasBottomRight = true }
            }
        }

        #expect(hasTopLeft, "Top of stem should be present")
        #expect(!hasTopRight, "Top right of 'L' should be empty (not upside down)")
        #expect(hasBottomLeft, "Corner of 'L' should be present")
        #expect(hasBottomRight, "Foot of 'L' should be present on bottom right (not mirrored or upside down)")
    }

    @Test func addTextLayerCreatesLayerAndRegistersUndo() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        session.textFontSize = 48

        #expect(session.document?.layers.count == 0)
        session.addTextLayer(at: CGPoint(x: 100, y: 150), content: "New Heading")

        #expect(session.document?.layers.count == 1)
        let layer = try #require(session.document?.layers.first)
        #expect(layer.liveText != nil)
        #expect(layer.liveText?.style.text == "New Heading")
        #expect(layer.liveText?.style.fontSize == 48)
        #expect(session.activeLayerID == layer.id)
        #expect(session.history.canUndo)
        #expect(session.history.undoName == "Type Tool")

        session.undo()
        #expect(session.document?.layers.isEmpty == true)

        session.redo()
        #expect(session.document?.layers.count == 1)
    }

    @Test func updateActiveTextLayerMutatesStyleAndReRenders() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        session.addTextLayer(at: CGPoint(x: 50, y: 50), content: "Before")

        let layer = try #require(session.activeLayer)
        let originalImage = try #require(layer.asset?.image)

        session.updateActiveText { style in
            style.text = "After Longer Text"
            style.fontSize = 60
            style.isFauxBold = true
        }

        let updatedLayer = try #require(session.activeLayer)
        #expect(updatedLayer.liveText?.style.text == "After Longer Text")
        #expect(updatedLayer.liveText?.style.fontSize == 60)
        #expect(updatedLayer.liveText?.style.isFauxBold == true)
        #expect(updatedLayer.asset?.image !== originalImage)
    }

    @Test func textLayerProjectPersistence() throws {
        let session = EditorSession()
        session.createDocument(width: 600, height: 400)
        session.textFontSize = 40
        session.addTextLayer(at: CGPoint(x: 20, y: 30), content: "Persistent Title")

        let snapshot = try #require(session.projectSnapshot())
        let record = try #require(snapshot.manifest.layers.first)
        #expect(record.text != nil)
        #expect(record.text?.text == "Persistent Title")
        #expect(record.text?.fontSize == 40)

        let newSession = EditorSession()
        newSession.installProject(snapshot, from: URL(fileURLWithPath: "/tmp/test.compositor"))
        let loadedLayer = try #require(newSession.document?.layers.first)
        #expect(loadedLayer.liveText != nil)
        #expect(loadedLayer.liveText?.style.text == "Persistent Title")
        #expect(loadedLayer.liveText?.style.fontSize == 40)
    }

    @Test func inlineTextEditingLifecycle() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        session.addTextLayer(at: CGPoint(x: 100, y: 100), content: "Interactive Layer")

        let layer = try #require(session.activeLayer)
        #expect(session.isEditingText)
        #expect(session.textEditingLayerID == layer.id)

        session.endTextEdit()
        #expect(!session.isEditingText)
        #expect(session.textEditingLayerID == nil)

        session.beginTextEdit(layerID: layer.id)
        #expect(session.isEditingText)
        #expect(session.textEditingLayerID == layer.id)
        #expect(session.textContent == "Interactive Layer")

        session.selectTool(.brush)
        #expect(!session.isEditingText)
        #expect(session.textEditingLayerID == nil)
        #expect(session.textContent == "")
    }

    @Test func cancelTextEditRevertsExistingLayerAndCleansUpNewLayer() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)

        // Case 1: Cancel on newly added layer cleans it up
        session.addTextLayer(at: CGPoint(x: 100, y: 100), content: "Temporary")
        #expect(session.document?.layers.count == 1)
        #expect(session.isEditingText)

        session.cancelTextEdit()
        #expect(!session.isEditingText)
        #expect(session.document?.layers.count == 0)
        #expect(session.textContent == "")

        // Case 2: Cancel on existing layer reverts to pre-edit text
        session.addTextLayer(at: CGPoint(x: 50, y: 50), content: "Original Title")
        session.commitTextEdit()
        #expect(session.document?.layers.count == 1)

        let layer = try #require(session.activeLayer)
        session.beginTextEdit(layerID: layer.id)
        session.updateActiveText(registerUndo: false) { $0.text = "Changed Unwanted" }
        session.textContent = "Changed Unwanted"

        session.cancelTextEdit()
        #expect(!session.isEditingText)
        #expect(session.activeLayer?.liveText?.style.text == "Original Title")
        #expect(session.textContent == "")
    }

    @Test func newTextLayerIsEmptyByDefaultAndDoesNotLeakPreviousText() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)

        // 1. First text layer starts empty
        session.addTextLayer(at: CGPoint(x: 50, y: 50))
        let first = try #require(session.activeLayer)
        #expect(first.liveText?.style.text == "")
        #expect(session.isEditingText)

        // User types something and hits ESC
        session.updateActiveText(registerUndo: false) { $0.text = "Typed then Cancelled" }
        session.textContent = "Typed then Cancelled"
        session.cancelTextEdit()
        #expect(!session.isEditingText)
        #expect(session.textContent == "")
        #expect(session.document?.layers.count == 0)

        // 2. Click again: Second text layer MUST start completely empty
        session.addTextLayer(at: CGPoint(x: 100, y: 100))
        let second = try #require(session.activeLayer)
        #expect(second.liveText?.style.text == "")
        #expect(session.textContent == "")
    }

    @Test func beginEditingExistingTextPreservesTextImmediately() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        session.addTextLayer(at: CGPoint(x: 100, y: 100), content: "Existing Text")
        session.commitTextEdit()

        let layer = try #require(session.activeLayer)
        session.beginTextEdit(layerID: layer.id)
        #expect(session.isEditingText)
        #expect(session.activeLayer?.liveText?.style.text == "Existing Text")
        #expect(session.textContent == "Existing Text")
    }

    @Test func textStrokeConfigurationAndRendering() throws {
        var style = LayerTextStyle()
        style.text = "STROKED"
        style.fontSize = 48
        style.strokeWidth = 6
        style.strokePosition = .outside
        style.strokeRed = 1
        style.strokeGreen = 1
        style.strokeBlue = 0
        style.strokeAlpha = 1

        let strokeAttr = style.makeAttributedString(scale: 1.0, forStroke: true)
        let strokeAttrs = strokeAttr.attributes(at: 0, effectiveRange: nil)
        #expect(strokeAttrs[.strokeWidth] as? CGFloat == 12) // Outside stroke uses 2x width
        #expect(strokeAttrs[.strokeColor] as? NSColor != nil)

        let centerAttr = {
            var cStyle = style
            cStyle.strokePosition = .center
            return cStyle.makeAttributedString(scale: 1.0, forStroke: false)
        }()
        let centerAttrs = centerAttr.attributes(at: 0, effectiveRange: nil)
        #expect(centerAttrs[.strokeWidth] as? CGFloat == -6) // Negative stroke width for stroke+fill

        let (image, size) = try EditorSession.textImage(for: style)
        #expect(image.width > 0)
        #expect(image.height > 0)
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    @Test func realTimeStyleUpdatesTriggerCanvasRefresh() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        var previewRefreshed = false
        session.refreshCanvasPreview = { previewRefreshed = true }

        session.addTextLayer(at: CGPoint(x: 50, y: 50), content: "Live Text")
        previewRefreshed = false

        session.updateActiveText(registerUndo: false) {
            $0.fontSize = 72
            $0.strokeWidth = 4
            $0.strokePosition = .outside
        }

        #expect(previewRefreshed)
        #expect(session.activeLayer?.liveText?.style.fontSize == 72)
        #expect(session.activeLayer?.liveText?.style.strokeWidth == 4)
        #expect(session.activeLayer?.liveText?.style.strokePosition == .outside)
    }
}
