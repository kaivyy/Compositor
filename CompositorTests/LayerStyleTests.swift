import AppKit
import CoreGraphics
import CoreText
import Testing
@testable import Compositor

@MainActor
struct LayerStyleTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CompositorLayerStyleTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeTestImage(width: Int = 100, height: Int = 100) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: width * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        // Draw a filled white circle in the center
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let radius = CGFloat(min(width, height)) * 0.3
        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return context.makeImage()!
    }

    private func makeTestTextImage(text: String = "Test", width: Int = 120, height: Int = 60) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: width * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        let attrString = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: 10, y: 15)
        CTLineDraw(line, context)
        return context.makeImage()!
    }

    // MARK: - 1. Model & Codable Tests

    @Test func layerStylesDefaultIsInactive() {
        let styles = LayerStyles()
        #expect(!styles.hasActiveEffects)
        #expect(styles.contentPadding == 0)
        #expect(styles.stroke == nil)
        #expect(styles.outerGlow == nil)
        #expect(styles.dropShadow == nil)
        #expect(styles.colorOverlay == nil)
    }

    @Test func layerStylesCodableRoundtrip() throws {
        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 4, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0), opacity: 0.8)
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 1, blue: 1), opacity: 0.9, size: 15, spread: 0.3)
        styles.dropShadow = DropShadowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0, blue: 0), opacity: 0.75, angle: 45, distance: 10, size: 8, spread: 0.2)
        styles.colorOverlay = ColorOverlayEffect(isEnabled: true, color: PaletteColor(red: 1, green: 0.5, blue: 0), opacity: 1.0)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(styles)
        let decoded = try decoder.decode(LayerStyles.self, from: data)

        #expect(decoded == styles)
        #expect(decoded.stroke?.size == 4)
        #expect(decoded.stroke?.position == .outside)
        #expect(decoded.stroke?.color.red == 1)
        #expect(decoded.outerGlow?.size == 15)
        #expect(decoded.dropShadow?.distance == 10)
        #expect(decoded.dropShadow?.angle == 45)
        #expect(decoded.colorOverlay?.color.red == 1)
        #expect(decoded.hasActiveEffects)
        #expect(decoded.contentPadding > 15)
    }

    @Test func individualEffectParametersEquality() {
        let stroke1 = StrokeEffect(isEnabled: true, size: 5, position: .outside, color: .black, opacity: 1.0, blendMode: .normal)
        let stroke2 = StrokeEffect(isEnabled: true, size: 5, position: .outside, color: .black, opacity: 1.0, blendMode: .normal)
        let stroke3 = StrokeEffect(isEnabled: true, size: 3, position: .inside, color: .white, opacity: 0.5, blendMode: .multiply)
        #expect(stroke1 == stroke2)
        #expect(stroke1 != stroke3)

        let glow1 = OuterGlowEffect(isEnabled: true, color: .white, opacity: 0.8, blendMode: .screen, size: 20, spread: 0.1)
        let glow2 = OuterGlowEffect(isEnabled: true, color: .white, opacity: 0.8, blendMode: .screen, size: 20, spread: 0.1)
        #expect(glow1 == glow2)

        let shadow1 = DropShadowEffect(isEnabled: true, color: .black, opacity: 0.75, blendMode: .multiply, angle: 90, distance: 8, size: 12, spread: 0.0)
        let shadow2 = DropShadowEffect(isEnabled: true, color: .black, opacity: 0.75, blendMode: .multiply, angle: 90, distance: 8, size: 12, spread: 0.0)
        #expect(shadow1 == shadow2)

        let overlay1 = ColorOverlayEffect(isEnabled: true, color: .white, opacity: 1.0, blendMode: .normal)
        let overlay2 = ColorOverlayEffect(isEnabled: true, color: .white, opacity: 1.0, blendMode: .normal)
        #expect(overlay1 == overlay2)
    }

    // MARK: - 2. Bounds Expansion & Geometry Tests

    @Test func strokePaddingCalculation() {
        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 8, position: .outside)
        #expect(styles.contentPadding >= 8)

        styles.stroke = StrokeEffect(isEnabled: true, size: 8, position: .center)
        #expect(styles.contentPadding >= 4)

        styles.stroke = StrokeEffect(isEnabled: true, size: 8, position: .inside)
        #expect(styles.contentPadding == 0)
    }

    @Test func outerGlowPaddingCalculation() {
        var styles = LayerStyles()
        styles.outerGlow = OuterGlowEffect(isEnabled: true, size: 20)
        #expect(styles.contentPadding >= 20)
    }

    @Test func dropShadowPaddingCalculation() {
        var styles = LayerStyles()
        styles.dropShadow = DropShadowEffect(isEnabled: true, angle: 90, distance: 15, size: 10)
        #expect(styles.contentPadding >= 25)
    }

    @Test func combinedEffectsPaddingTakesMaximumRequired() {
        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 5, position: .outside)
        styles.outerGlow = OuterGlowEffect(isEnabled: true, size: 30)
        styles.dropShadow = DropShadowEffect(isEnabled: true, angle: 90, distance: 10, size: 15)
        #expect(styles.contentPadding >= 40)
    }

    // MARK: - 3. Rendering Tests on Universal Content Surface (Raster, Shape, Text)

    @Test func strokeRenderingExpandsBoundsAndDrawsOutline() throws {
        let source = makeTestImage(width: 80, height: 80)
        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 6, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0), opacity: 1.0)

        let result = try #require(LayerStyleRenderer.render(image: source, styles: styles))
        let styled = result.image
        let padding = result.padding

        #expect(padding >= 6)
        #expect(styled.width == source.width + Int(padding * 2))
        #expect(styled.height == source.height + Int(padding * 2))

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let centerX = 40 + Int(padding)
        let centerY = 40 + Int(padding)
        let testX = centerX + 28
        let testY = centerY
        let offset = testY * styled.bytesPerRow + testX * 4
        let red = ptr[offset]
        let alpha = ptr[offset + 3]
        #expect(alpha > 50, "Stroke should produce non-zero alpha in outside region")
        #expect(red > 100, "Stroke should be red")
    }

    @Test func outerGlowRenderingProducesSoftAlphaAroundContent() throws {
        let source = makeTestImage(width: 80, height: 80)
        var styles = LayerStyles()
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 1, blue: 1), opacity: 1.0, size: 12)

        let result = try #require(LayerStyleRenderer.render(image: source, styles: styles))
        let styled = result.image
        let padding = result.padding

        #expect(padding >= 12)
        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let centerX = 40 + Int(padding)
        let centerY = 40 + Int(padding)
        let testX = centerX + 30
        let testY = centerY
        let offset = testY * styled.bytesPerRow + testX * 4
        let alpha = ptr[offset + 3]
        #expect(alpha > 0, "Outer glow must illuminate pixels outside original circle")
    }

    @Test func dropShadowRenderingDisplacesShadowAlongAxes() throws {
        let source = makeTestImage(width: 80, height: 80)
        var styles = LayerStyles()
        // Angle 0 degrees = points to the right (+X)
        styles.dropShadow = DropShadowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0, blue: 0), opacity: 1.0, angle: 0, distance: 20, size: 4)

        let result = try #require(LayerStyleRenderer.render(image: source, styles: styles))
        let styled = result.image
        let padding = result.padding

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let centerX = 40 + Int(padding)
        let centerY = 40 + Int(padding)
        // Check shadow on the right (+X direction)
        let rightX = centerX + 35
        let rightOffset = centerY * styled.bytesPerRow + rightX * 4
        let rightAlpha = ptr[rightOffset + 3]

        // Check opposite direction (-X direction) at same distance
        let leftX = centerX - 35
        let leftOffset = centerY * styled.bytesPerRow + leftX * 4
        let leftAlpha = ptr[leftOffset + 3]

        #expect(rightAlpha > leftAlpha, "Shadow cast to the right must produce higher alpha on the right than on the left")
    }

    @Test func dropShadowDiagonalAndNegativeAxes() throws {
        let source = makeTestImage(width: 80, height: 80)
        var styles = LayerStyles()
        // Angle 180 degrees = points to the left (-X)
        styles.dropShadow = DropShadowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0, blue: 0), opacity: 1.0, angle: 180, distance: 20, size: 4)

        let result = try #require(LayerStyleRenderer.render(image: source, styles: styles))
        let styled = result.image
        let padding = result.padding

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let centerX = 40 + Int(padding)
        let centerY = 40 + Int(padding)
        let leftX = centerX - 35
        let leftOffset = centerY * styled.bytesPerRow + leftX * 4
        let leftAlpha = ptr[leftOffset + 3]

        let rightX = centerX + 35
        let rightOffset = centerY * styled.bytesPerRow + rightX * 4
        let rightAlpha = ptr[rightOffset + 3]

        #expect(leftAlpha > rightAlpha, "Shadow cast to the left (angle 180) must produce higher alpha on the left than on the right")
    }

    @Test func colorOverlayReplacesSourceColorsNonDestructively() throws {
        let source = makeTestImage(width: 80, height: 80)
        var styles = LayerStyles()
        styles.colorOverlay = ColorOverlayEffect(isEnabled: true, color: PaletteColor(red: 0, green: 1, blue: 0), opacity: 1.0)

        let result = try #require(LayerStyleRenderer.render(image: source, styles: styles))
        let styled = result.image

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let offset = 40 * styled.bytesPerRow + 40 * 4
        let red = ptr[offset]
        let green = ptr[offset + 1]
        let blue = ptr[offset + 2]
        let alpha = ptr[offset + 3]

        #expect(alpha > 200)
        #expect(green > 200, "Green color overlay should make content green")
        #expect(red < 50)
        #expect(blue < 50)
    }

    @Test func textSurfaceStylesRendering() throws {
        let textSource = makeTestTextImage(text: "Style", width: 100, height: 50)
        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 3, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0))
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 1, blue: 1), size: 10)

        let result = try #require(LayerStyleRenderer.render(image: textSource, styles: styles))
        #expect(result.padding > 0)
        #expect(result.image.width > textSource.width)
        #expect(result.image.height > textSource.height)
    }

    @Test func textWithStrokeRendering() throws {
        var style = LayerTextStyle()
        style.text = "StrokeText"
        style.fontSize = 36
        let (textImg, _) = try EditorSession.textImage(for: style)

        var styles = LayerStyles()
        let redColor = PaletteColor(red: 1, green: 0, blue: 0)
        styles.stroke = StrokeEffect(isEnabled: true, size: 6, position: .outside, color: redColor, opacity: 1.0)

        let result = try #require(LayerStyleRenderer.render(image: textImg, styles: styles))
        let styled = result.image
        let padding = result.padding

        #expect(padding >= 6)
        #expect(styled.width == textImg.width + Int(padding * 2))
        #expect(styled.height == textImg.height + Int(padding * 2))

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let len = CFDataGetLength(data)

        // 1. Transparent corner margin must remain transparent (0 alpha)
        #expect(ptr[3] == 0, "Outer corner margin must remain transparent")

        // 2. Stroke red pixels must exist in the output image
        var foundRedStroke = false
        for i in stride(from: 0, to: len, by: 4) {
            let r = ptr[i]
            let g = ptr[i + 1]
            let b = ptr[i + 2]
            let a = ptr[i + 3]
            if a > 150 && r > 200 && g < 50 && b < 50 {
                foundRedStroke = true
                break
            }
        }
        #expect(foundRedStroke, "Rendered text with red stroke must contain red stroke pixels")
    }

    @Test func textWithOuterGlowRendering() throws {
        var style = LayerTextStyle()
        style.text = "GlowText"
        style.fontSize = 36
        let (textImg, _) = try EditorSession.textImage(for: style)

        var styles = LayerStyles()
        let cyanColor = PaletteColor(red: 0, green: 0.94, blue: 1)
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: cyanColor, opacity: 0.9, size: 16)

        let result = try #require(LayerStyleRenderer.render(image: textImg, styles: styles))
        let styled = result.image
        let padding = result.padding

        #expect(padding >= 16)
        #expect(styled.width > textImg.width)
        #expect(styled.height > textImg.height)

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let len = CFDataGetLength(data)

        // Far corner remains transparent
        #expect(ptr[3] == 0)

        // Cyan glow pixels exist
        var foundCyanGlow = false
        for i in stride(from: 0, to: len, by: 4) {
            let r = ptr[i]
            let g = ptr[i + 1]
            let b = ptr[i + 2]
            let a = ptr[i + 3]
            if a > 20 && b > 20 && g > 18 && r < b / 2 {
                foundCyanGlow = true
                break
            }
        }
        #expect(foundCyanGlow, "Rendered text with cyan glow must contain soft semi-transparent cyan glow pixels")
    }

    @Test func textWithDropShadowRendering() throws {
        var style = LayerTextStyle()
        style.text = "ShadowText"
        style.fontSize = 36
        let (textImg, _) = try EditorSession.textImage(for: style)

        var styles = LayerStyles()
        styles.dropShadow = DropShadowEffect(isEnabled: true, color: .black, opacity: 0.8, angle: 0, distance: 20, size: 4)

        let result = try #require(LayerStyleRenderer.render(image: textImg, styles: styles))
        let styled = result.image
        let padding = result.padding

        #expect(padding >= 20)
        #expect(styled.width > textImg.width)

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!

        let midY = styled.height / 2
        let centerX = styled.width / 2
        let rightX = min(styled.width - 2, centerX + Int(padding) + 15)
        let leftX = max(1, centerX - Int(padding) - 15)

        let rightOffset = midY * styled.bytesPerRow + rightX * 4
        let leftOffset = midY * styled.bytesPerRow + leftX * 4

        let rightAlpha = ptr[rightOffset + 3]
        let leftAlpha = ptr[leftOffset + 3]

        #expect(rightAlpha >= leftAlpha, "Drop shadow cast to right must produce alpha on right side >= left side")
    }

    @Test func textWithColorOverlayRendering() throws {
        var style = LayerTextStyle()
        style.text = "OverlayText"
        style.fontSize = 36
        let (textImg, _) = try EditorSession.textImage(for: style)

        var styles = LayerStyles()
        let orangeColor = PaletteColor(red: 1, green: 0.5, blue: 0)
        styles.colorOverlay = ColorOverlayEffect(isEnabled: true, color: orangeColor, opacity: 1.0)

        let result = try #require(LayerStyleRenderer.render(image: textImg, styles: styles))
        let styled = result.image

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let len = CFDataGetLength(data)

        #expect(ptr[3] == 0)

        var foundOrange = false
        for i in stride(from: 0, to: len, by: 4) {
            let r = ptr[i]
            let g = ptr[i + 1]
            let b = ptr[i + 2]
            let a = ptr[i + 3]
            if a > 200 && r > 200 && g > 80 && g < 180 && b < 50 {
                foundOrange = true
                break
            }
        }
        #expect(foundOrange, "Color overlay must tint text pixels orange")
    }

    @Test func textLiveEditInvalidatesLayerStyleCache() throws {
        let session = EditorSession()
        session.createDocument(width: 400, height: 200, emptyLayer: false)
        session.addTextLayer(at: CGPoint(x: 50, y: 50), content: "ABC")
        session.endTextEdit(commitUndo: true)

        var styles = LayerStyles()
        styles.outerGlow = OuterGlowEffect(isEnabled: true, size: 10)
        session.setLayerStyles(styles)

        let textLayer = try #require(session.activeLayer)
        let firstStyled = try #require(LayerStyleCache.shared.styledImage(for: textLayer))
        let firstWidth = firstStyled.image.width

        session.updateActiveText { $0.text = "ABCDEF" }

        let updatedLayer = try #require(session.activeLayer)
        let secondStyled = try #require(LayerStyleCache.shared.styledImage(for: updatedLayer))
        let secondWidth = secondStyled.image.width

        #expect(secondStyled.image !== firstStyled.image, "Cache must invalidate and produce new image on text change")
        #expect(secondWidth > firstWidth, "New styled image for longer text must have greater width")
    }

    @Test func textLayerWithStylesExportsCorrectly() async throws {
        let session = EditorSession()
        session.createDocument(width: 300, height: 200, emptyLayer: false)
        session.addTextLayer(at: CGPoint(x: 30, y: 30), content: "ExportText")
        session.endTextEdit(commitUndo: true)

        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 4, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0))
        session.setLayerStyles(styles)

        let snapshot = try #require(session.projectSnapshot())
        let exportRaster = try await ImageExporter.shared.render(snapshot)

        #expect(exportRaster.image.width == 300)
        #expect(exportRaster.image.height == 200)

        let data = try #require(exportRaster.image.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        let len = CFDataGetLength(data)

        var foundRedStroke = false
        for i in stride(from: 0, to: len, by: 4) {
            let r = ptr[i]
            let g = ptr[i + 1]
            let b = ptr[i + 2]
            let a = ptr[i + 3]
            if a > 150 && r > 200 && g < 50 && b < 50 {
                foundRedStroke = true
                break
            }
        }
        #expect(foundRedStroke, "Exported canvas must contain red stroke pixels from styled text")
    }

    @Test func layerStylesInspectorLifecycleAndUndoRedo() throws {
        let session = EditorSession()
        session.createDocument(width: 300, height: 200, emptyLayer: false)
        session.addTextLayer(at: CGPoint(x: 20, y: 20), content: "InspectorTest")
        session.endTextEdit(commitUndo: true)

        // 1. Open inspector
        session.showsStylesInspector = true
        #expect(session.showsStylesInspector == true)

        // 2. Modify styles via slider drag pattern
        session.beginStyleEdit("Stroke Size")
        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 8, position: .outside, color: .black)
        session.setLayerStyles(styles, actionName: "Stroke Size")
        session.finishStyleEdit()

        #expect(session.activeLayer?.styles?.stroke?.size == 8)

        // 3. Close inspector
        session.showsStylesInspector = false
        #expect(session.showsStylesInspector == false)
        #expect(session.activeLayer?.styles?.stroke?.size == 8, "Styles must be preserved when inspector closes")

        // 4. Reopen inspector
        session.showsStylesInspector = true
        #expect(session.showsStylesInspector == true)
        #expect(session.activeLayer?.styles?.stroke?.size == 8, "Styles must be present when inspector reopens")

        // 5. Test undo and redo
        #expect(session.history.canUndo)
        session.undo()
        #expect(session.activeLayer?.styles == nil, "Undo must revert styles")

        #expect(session.history.canRedo)
        session.redo()
        #expect(session.activeLayer?.styles?.stroke?.size == 8, "Redo must restore styles")
    }

    @Test func transparentRegionsDoNotIndependentlyGlow() throws {
        // Completely transparent 50x50 image
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 200,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let blank = context.makeImage()!

        var styles = LayerStyles()
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 1, green: 1, blue: 0), size: 15)
        let result = try #require(LayerStyleRenderer.render(image: blank, styles: styles))
        let styled = result.image

        let data = try #require(styled.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        var maxAlpha: UInt8 = 0
        for i in stride(from: 3, to: CFDataGetLength(data), by: 4) {
            if ptr[i] > maxAlpha { maxAlpha = ptr[i] }
        }
        #expect(maxAlpha == 0, "A completely transparent layer must not generate glow pixels")
    }

    @Test func tinyAndExtremeImageValues() throws {
        // Tiny 2x2 image
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let tiny = context.makeImage()!

        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 10, position: .outside)
        let result = try #require(LayerStyleRenderer.render(image: tiny, styles: styles))
        #expect(result.image.width >= 22)
    }

    // MARK: - 4. Persistence Tests

    @Test func layerStylesPersistAcrossSaveAndLoad() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = EditorSession()
        session.createDocument(width: 300, height: 200, emptyLayer: true)
        let testImg = makeTestImage(width: 60, height: 60)
        let thumbnail = try #require(try PixelInvert.thumbnail(of: testImg))
        var layer = ImageLayer(asset: ImportedImage(image: testImg, thumbnail: thumbnail, name: "Styled Layer"), origin: CGPoint(x: 30, y: 30))

        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 5, position: .outside, color: PaletteColor(red: 0, green: 0, blue: 1))
        styles.dropShadow = DropShadowEffect(isEnabled: true, angle: 45, distance: 8, size: 6)
        layer.styles = styles

        session.document?.layers.append(layer)
        session.activeLayerID = layer.id

        let projectURL = folder.appendingPathComponent("TestStyles.comp")
        let snapshot = try #require(session.projectSnapshot())
        try await ProjectStore.shared.save(snapshot, to: projectURL)

        let loaded = try await ProjectStore.shared.load(from: projectURL)
        let newSession = EditorSession()
        newSession.installProject(loaded, from: projectURL)

        let loadedLayer = try #require(newSession.document?.layers.first(where: { $0.id == layer.id }))
        let loadedStyles = try #require(loadedLayer.styles)
        #expect(loadedStyles.stroke?.isEnabled == true)
        #expect(loadedStyles.stroke?.size == 5)
        #expect(loadedStyles.stroke?.color.blue == 1)
        #expect(loadedStyles.dropShadow?.isEnabled == true)
        #expect(loadedStyles.dropShadow?.distance == 8)
        #expect(loadedStyles.dropShadow?.angle == 45)
    }

    @Test func legacyProjectsWithoutStylesLoadWithNilStyles() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Construct a snapshot with ProjectLayerRecord having styles = nil
        let layerID = UUID()
        let testImg = makeTestImage(width: 40, height: 40)
        let thumbnail = try #require(try PixelInvert.thumbnail(of: testImg))
        let record = ProjectLayerRecord(id: layerID, name: "Legacy Layer", isVisible: true,
                                        transform: LayerTransform(origin: .zero, size: CGSize(width: 40, height: 40)),
                                        imageFile: "\(layerID.uuidString).png", styles: nil)
        let manifest = ProjectManifest(resolution: 72, documentID: UUID(), width: 200, height: 200, activeLayerID: layerID, layers: [record])
        let snapshot = ProjectSnapshot(manifest: manifest, images: [layerID: ImportedImage(image: testImg, thumbnail: thumbnail, name: "Legacy Layer")])

        let projectURL = folder.appendingPathComponent("Legacy.comp")
        try await ProjectStore.shared.save(snapshot, to: projectURL)

        let loaded = try await ProjectStore.shared.load(from: projectURL)
        let session = EditorSession()
        session.installProject(loaded, from: projectURL)

        let loadedLayer = try #require(session.document?.layers.first(where: { $0.id == layerID }))
        #expect(loadedLayer.styles == nil, "Legacy project layers without styles must load with nil styles")
    }

    // MARK: - 5. Undo / Redo & Session Management Tests

    @Test func layerStylesUndoRedoCycle() throws {
        let session = EditorSession()
        session.createDocument(width: 300, height: 200, emptyLayer: true)
        let testImg = makeTestImage(width: 40, height: 40)
        let thumbnail = try #require(try PixelInvert.thumbnail(of: testImg))
        let layer = ImageLayer(asset: ImportedImage(image: testImg, thumbnail: thumbnail, name: "Layer 1"), origin: CGPoint(x: 20, y: 20))
        session.document?.layers.append(layer)
        session.activeLayerID = layer.id

        #expect(session.activeLayer?.styles == nil)

        // 1. Add styles
        var styles = LayerStyles()
        styles.outerGlow = OuterGlowEffect(isEnabled: true, size: 10)
        session.setLayerStyles(styles, actionName: "Add Glow")
        #expect(session.activeLayer?.styles?.outerGlow?.isEnabled == true)

        // 2. Undo
        #expect(session.history.canUndo)
        session.undo()
        #expect(session.activeLayer?.styles == nil)

        // 3. Redo
        #expect(session.history.canRedo)
        session.redo()
        #expect(session.activeLayer?.styles?.outerGlow?.isEnabled == true)

        // 4. Modify styles
        styles.outerGlow?.size = 25
        session.setLayerStyles(styles, actionName: "Increase Glow")
        #expect(session.activeLayer?.styles?.outerGlow?.size == 25)

        // 5. Clear styles
        session.clearLayerStyles()
        #expect(session.activeLayer?.styles == nil)

        session.undo()
        #expect(session.activeLayer?.styles?.outerGlow?.size == 25)
    }

    @Test func layerStylesCopyAndPaste() throws {
        let session = EditorSession()
        session.createDocument(width: 300, height: 200, emptyLayer: true)
        let img1 = makeTestImage(width: 40, height: 40)
        let thumb1 = try #require(try PixelInvert.thumbnail(of: img1))
        var layer1 = ImageLayer(asset: ImportedImage(image: img1, thumbnail: thumb1, name: "Layer 1"), origin: .zero)
        layer1.styles = LayerStyles(stroke: StrokeEffect(isEnabled: true, size: 8, position: .outside, color: .black))

        let img2 = makeTestImage(width: 40, height: 40)
        let thumb2 = try #require(try PixelInvert.thumbnail(of: img2))
        let layer2 = ImageLayer(asset: ImportedImage(image: img2, thumbnail: thumb2, name: "Layer 2"), origin: CGPoint(x: 50, y: 50))

        session.document?.layers = [layer1, layer2]

        // Copy styles from layer 1
        session.activeLayerID = layer1.id
        session.copyLayerStyles()
        #expect(session.copiedStyles?.stroke?.size == 8)

        // Paste styles onto layer 2
        session.activeLayerID = layer2.id
        session.pasteLayerStyles()
        #expect(session.activeLayer?.styles?.stroke?.size == 8)
    }

    // MARK: - 6. Presets Composition Tests

    @Test func neonPresetCompositionRendersSuccessfully() throws {
        let source = makeTestImage(width: 100, height: 60)
        let cyan = PaletteColor(red: 0, green: 0.94, blue: 1)
        let neonStyles = LayerStyles(
            isEnabled: true,
            stroke: StrokeEffect(isEnabled: true, size: 3, position: .outside, color: cyan, opacity: 1.0, blendMode: .normal),
            outerGlow: OuterGlowEffect(isEnabled: true, color: cyan, opacity: 0.85, blendMode: .screen, size: 24, spread: 0.15),
            dropShadow: DropShadowEffect(isEnabled: true, color: cyan, opacity: 0.5, blendMode: .screen, angle: 90, distance: 0, size: 60, spread: 0)
        )

        #expect(neonStyles.hasActiveEffects)
        #expect(neonStyles.contentPadding >= 24)

        let result = try #require(LayerStyleRenderer.render(image: source, styles: neonStyles))
        let styled = result.image
        let padding = result.padding

        #expect(styled.width > source.width)
        #expect(styled.height > source.height)
        #expect(padding >= 24)
    }

    // MARK: - 7. CanvasView Integration & Live Rendering Tests

    private func renderCanvas(_ view: CanvasView, size: CGSize) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: view.isFlipped)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        view.draw(CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return try #require(ctx.makeImage())
    }

    @Test func textLayerWithStylesRendersOnCanvasView() throws {
        let session = EditorSession()
        let size = CGSize(width: 400, height: 300)
        session.createDocument(width: Int(size.width), height: Int(size.height), emptyLayer: true)
        session.addTextLayer(at: CGPoint(x: 100, y: 100), content: "TEST")
        session.endTextEdit(commitUndo: true)

        let view = CanvasView(session: session)
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: size, backingScale: 1, documentSize: size)
        view.synchronizeDisplay()

        // 1. Initial text on canvas (white text)
        let baseCanvas = try renderCanvas(view, size: size)
        let baseData = try #require(baseCanvas.dataProvider?.data)
        let basePtr = CFDataGetBytePtr(baseData)!
        var foundWhite = false
        for i in stride(from: 0, to: CFDataGetLength(baseData), by: 4) {
            if basePtr[i] > 200 && basePtr[i+1] > 200 && basePtr[i+2] > 200 && basePtr[i+3] > 200 {
                foundWhite = true
                break
            }
        }
        #expect(foundWhite, "Unstyled text must render white pixels on canvas")

        // 2. Apply red Stroke
        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 8, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0), opacity: 1.0)
        session.setLayerStyles(styles)
        view.displayIfNeeded()

        let strokeCanvas = try renderCanvas(view, size: size)
        let strokeData = try #require(strokeCanvas.dataProvider?.data)
        let strokePtr = CFDataGetBytePtr(strokeData)!
        var foundRedStroke = false
        for i in stride(from: 0, to: CFDataGetLength(strokeData), by: 4) {
            if strokePtr[i] > 200 && strokePtr[i+1] < 60 && strokePtr[i+2] < 60 && strokePtr[i+3] > 180 {
                foundRedStroke = true
                break
            }
        }
        #expect(foundRedStroke, "CanvasView must visibly render red stroke pixels around text")

        // 3. Apply cyan Outer Glow
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0.94, blue: 1), opacity: 0.9, size: 16)
        session.setLayerStyles(styles)
        view.displayIfNeeded()

        let glowCanvas = try renderCanvas(view, size: size)
        let glowData = try #require(glowCanvas.dataProvider?.data)
        let glowPtr = CFDataGetBytePtr(glowData)!
        var foundCyanGlow = false
        for i in stride(from: 0, to: CFDataGetLength(glowData), by: 4) {
            let r = glowPtr[i], g = glowPtr[i+1], b = glowPtr[i+2], a = glowPtr[i+3]
            if a > 20 && b > r + 15 && g > r + 15 {
                foundCyanGlow = true
                break
            }
        }
        #expect(foundCyanGlow, "CanvasView must visibly render cyan glow pixels around styled text")

        // 4. Apply orange Color Overlay
        styles.colorOverlay = ColorOverlayEffect(isEnabled: true, color: PaletteColor(red: 1, green: 0.5, blue: 0), opacity: 1.0)
        session.setLayerStyles(styles)
        view.displayIfNeeded()

        let overlayCanvas = try renderCanvas(view, size: size)
        let overlayData = try #require(overlayCanvas.dataProvider?.data)
        let overlayPtr = CFDataGetBytePtr(overlayData)!
        var foundOrange = false
        for i in stride(from: 0, to: CFDataGetLength(overlayData), by: 4) {
            let r = overlayPtr[i], g = overlayPtr[i+1], b = overlayPtr[i+2], a = overlayPtr[i+3]
            if a > 200 && r > 200 && g > 80 && g < 180 && b < 60 {
                foundOrange = true
                break
            }
        }
        #expect(foundOrange, "CanvasView must visibly render orange text fill with color overlay")

        // 5. Test Live Text Editing with styles active
        session.updateActiveText { $0.text = "TESTING LIVE STYLES" }
        view.displayIfNeeded()

        let liveCanvas = try renderCanvas(view, size: size)
        let liveData = try #require(liveCanvas.dataProvider?.data)
        let livePtr = CFDataGetBytePtr(liveData)!
        var liveStrokePixels = 0
        for i in stride(from: 0, to: CFDataGetLength(liveData), by: 4) {
            if livePtr[i] > 200 && livePtr[i+1] < 60 && livePtr[i+2] < 60 && livePtr[i+3] > 180 {
                liveStrokePixels += 1
            }
        }
        #expect(liveStrokePixels > 20, "Longer text must maintain stroke across the full new text span")

        // 6. Test Disabling Styles restores normal vector rendering
        session.setLayerStyles(nil)
        view.displayIfNeeded()

        let noStylesCanvas = try renderCanvas(view, size: size)
        let noStylesData = try #require(noStylesCanvas.dataProvider?.data)
        let noStylesPtr = CFDataGetBytePtr(noStylesData)!
        var hasRedAfterClear = false
        for i in stride(from: 0, to: CFDataGetLength(noStylesData), by: 4) {
            if noStylesPtr[i] > 200 && noStylesPtr[i+1] < 60 && noStylesPtr[i+2] < 60 && noStylesPtr[i+3] > 180 {
                hasRedAfterClear = true
                break
            }
        }
        #expect(!hasRedAfterClear, "Clearing styles must revert canvas to normal vector text without stroke")
    }

    @Test func shapeLayerWithStylesRendersOnCanvasView() throws {
        let session = EditorSession()
        let size = CGSize(width: 300, height: 200)
        session.createDocument(width: Int(size.width), height: Int(size.height), emptyLayer: true)
        let shapeImg = try EditorSession.shapeImage(.rectangle, size: CGSize(width: 80, height: 60), color: PaletteColor(red: 0, green: 0, blue: 0), cornerRadius: 4)
        let thumb = try #require(try PixelInvert.thumbnail(of: shapeImg))
        let style = LayerShapeStyle(kind: .rectangle, red: 0, green: 0, blue: 0, cornerRadius: 4)
        var layer = ImageLayer(asset: ImportedImage(image: shapeImg, thumbnail: thumb, name: "Rectangle 1"), origin: CGPoint(x: 50, y: 50))
        layer.shape = LayerShape(style: style, image: shapeImg)
        session.document?.layers.append(layer)
        session.activeLayerID = layer.id

        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 6, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0), opacity: 1.0)
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0.94, blue: 1), opacity: 0.8, size: 12)
        session.setLayerStyles(styles)

        let view = CanvasView(session: session)
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: size, backingScale: 1, documentSize: size)
        view.synchronizeDisplay()

        let canvas = try renderCanvas(view, size: size)
        let data = try #require(canvas.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!

        var foundRed = false
        for i in stride(from: 0, to: CFDataGetLength(data), by: 4) {
            if ptr[i] > 200 && ptr[i+1] < 60 && ptr[i+2] < 60 && ptr[i+3] > 180 {
                foundRed = true
                break
            }
        }
        #expect(foundRed, "Shape layer with layer styles must render stroke on CanvasView")
    }

    @Test func rasterLayerWithStylesRendersOnCanvasView() throws {
        let session = EditorSession()
        let size = CGSize(width: 300, height: 200)
        session.createDocument(width: Int(size.width), height: Int(size.height), emptyLayer: true)
        let img = makeTestImage(width: 60, height: 60)
        let thumb = try #require(try PixelInvert.thumbnail(of: img))
        let layer = ImageLayer(asset: ImportedImage(image: img, thumbnail: thumb, name: "Raster"), origin: CGPoint(x: 50, y: 50))
        session.document?.layers.append(layer)
        session.activeLayerID = layer.id

        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 6, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0), opacity: 1.0)
        session.setLayerStyles(styles)

        let view = CanvasView(session: session)
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: size, backingScale: 1, documentSize: size)
        view.synchronizeDisplay()

        let canvas = try renderCanvas(view, size: size)
        let data = try #require(canvas.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!

        var foundRed = false
        for i in stride(from: 0, to: CFDataGetLength(data), by: 4) {
            if ptr[i] > 200 && ptr[i+1] < 60 && ptr[i+2] < 60 && ptr[i+3] > 180 {
                foundRed = true
                break
            }
        }
        #expect(foundRed, "Raster layer with layer styles must render stroke on CanvasView")
    }

    @Test func textStylesEffectBoundsNearEdges() throws {
        let session = EditorSession()
        let size = CGSize(width: 400, height: 300)
        session.createDocument(width: Int(size.width), height: Int(size.height), emptyLayer: true)

        // Text placed near top-left edge
        session.addTextLayer(at: CGPoint(x: 5, y: 5), content: "EDGE")
        session.endTextEdit(commitUndo: true)

        let initialOrigin = try #require(session.activeLayer?.transform.origin)

        var styles = LayerStyles()
        styles.outerGlow = OuterGlowEffect(isEnabled: true, size: 30)
        styles.dropShadow = DropShadowEffect(isEnabled: true, angle: 45, distance: 40, size: 25)
        session.setLayerStyles(styles)

        let styledLayer = try #require(session.activeLayer)
        #expect(styledLayer.transform.origin == initialOrigin, "Applying large glow and shadow must not shift layer logical transform origin")

        let view = CanvasView(session: session)
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: size, backingScale: 1, documentSize: size)
        view.synchronizeDisplay()

        // Canvas draws without crash or clipping exception
        let canvas = try renderCanvas(view, size: size)
        #expect(canvas.width == 400 && canvas.height == 300)
    }

    @Test func textLayerWithStylesCanvasVsExportParity() async throws {
        let session = EditorSession()
        let size = CGSize(width: 300, height: 200)
        session.createDocument(width: Int(size.width), height: Int(size.height), emptyLayer: true)
        session.addTextLayer(at: CGPoint(x: 40, y: 40), content: "PARITY")
        session.endTextEdit(commitUndo: true)

        var styles = LayerStyles()
        styles.stroke = StrokeEffect(isEnabled: true, size: 4, position: .outside, color: PaletteColor(red: 1, green: 0, blue: 0), opacity: 1.0)
        styles.outerGlow = OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0.94, blue: 1), opacity: 0.8, size: 10)
        session.setLayerStyles(styles)

        // 1. Render on CanvasView
        let view = CanvasView(session: session)
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: size, backingScale: 1, documentSize: size)
        view.synchronizeDisplay()
        let canvas = try renderCanvas(view, size: size)

        // 2. Render via ImageExporter
        let snapshot = try #require(session.projectSnapshot())
        let export = try await ImageExporter.shared.render(snapshot)

        #expect(canvas.width == export.image.width)
        #expect(canvas.height == export.image.height)

        let exportData = try #require(export.image.dataProvider?.data)
        let exportPtr = CFDataGetBytePtr(exportData)!

        // Verify export image also contains red stroke pixels
        var exportFoundRed = false
        for i in stride(from: 0, to: CFDataGetLength(exportData), by: 4) {
            if exportPtr[i] > 200 && exportPtr[i+1] < 60 && exportPtr[i+2] < 60 && exportPtr[i+3] > 180 {
                exportFoundRed = true
                break
            }
        }
        #expect(exportFoundRed, "Exported image must contain red stroke pixels matching canvas rendering")
    }
}

