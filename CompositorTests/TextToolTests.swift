import Testing
import AppKit
@testable import Compositor

@Suite struct TextToolTests {
    @Test func defaultLayerTextStyleProperties() {
        let style = LayerTextStyle()
        #expect(style.text == "Sample Text")
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

    @Test func addTextLayerCreatesLayerAndRegistersUndo() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600)
        session.textContent = "New Heading"
        session.textFontSize = 48

        #expect(session.document?.layers.count == 0)
        session.addTextLayer(at: CGPoint(x: 100, y: 150))

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
        session.textContent = "Persistent Title"
        session.textFontSize = 40
        session.addTextLayer(at: CGPoint(x: 20, y: 30))

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
}
