import AppKit
import Testing
@testable import Compositor

@Suite struct ShadowSpreadTests {
    private func solidSquare(size: Int = 40, color: PaletteColor = PaletteColor(red: 1, green: 1, blue: 1)) throws -> CGImage {
        let context = try BrushRaster.context(width: size, height: size, mask: false)
        context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try #require(context.makeImage())
    }

    @Test func shadowSpreadDefaultsAndValidation() {
        var shadow = ShadowEffect()
        #expect(shadow.spread == 0)
        #expect(shadow.isValid)

        shadow.spread = 25
        #expect(shadow.isValid)

        shadow.spread = -1
        #expect(!shadow.isValid)

        var innerShadow = InnerShadowEffect()
        #expect(innerShadow.choke == 0)
        #expect(innerShadow.isValid)

        innerShadow.choke = 15
        #expect(innerShadow.isValid)

        innerShadow.choke = -5
        #expect(!innerShadow.isValid)
    }

    @Test func shadowSpreadAndChokeCodableBackwardCompatibility() throws {
        // 1. Older JSON without spread
        let olderShadowJSON = """
        { "angle": 90, "distance": 15, "blur": 20, "red": 0, "green": 0, "blue": 0, "opacity": 0.6 }
        """.data(using: .utf8)!
        let decodedShadow = try JSONDecoder().decode(ShadowEffect.self, from: olderShadowJSON)
        #expect(decodedShadow.spread == 0)
        #expect(decodedShadow.distance == 15)

        // 2. Older JSON without choke
        let olderInnerJSON = """
        { "angle": 90, "distance": 10, "blur": 15, "red": 0, "green": 0, "blue": 0, "opacity": 0.5 }
        """.data(using: .utf8)!
        let decodedInner = try JSONDecoder().decode(InnerShadowEffect.self, from: olderInnerJSON)
        #expect(decodedInner.choke == 0)

        // 3. New JSON with spread and choke
        var newShadow = ShadowEffect(angle: 45, distance: 20, blur: 10, spread: 8, red: 0, green: 0, blue: 0, opacity: 0.7)
        let shadowData = try JSONEncoder().encode(newShadow)
        let roundTrippedShadow = try JSONDecoder().decode(ShadowEffect.self, from: shadowData)
        #expect(roundTrippedShadow.spread == 8)
        #expect(roundTrippedShadow == newShadow)

        var newInner = InnerShadowEffect(angle: 90, distance: 5, blur: 8, choke: 6, red: 0, green: 0, blue: 0, opacity: 0.5)
        let innerData = try JSONEncoder().encode(newInner)
        let roundTrippedInner = try JSONDecoder().decode(InnerShadowEffect.self, from: innerData)
        #expect(roundTrippedInner.choke == 6)
        #expect(roundTrippedInner == newInner)
    }

    @Test func shadowSpreadMarginExpansion() {
        var baseEffects = LayerEffects()
        baseEffects.shadow = ShadowEffect(distance: 10, blur: 10, spread: 0)
        let baseMargin = LayerEffectsRenderer.margin(for: baseEffects)
        // 10 + 0 + 30 = 40 -> ceil(40) + 2 = 42
        #expect(baseMargin == 42)

        var spreadEffects = LayerEffects()
        spreadEffects.shadow = ShadowEffect(distance: 10, blur: 10, spread: 15)
        let spreadMargin = LayerEffectsRenderer.margin(for: spreadEffects)
        // 10 + 15 + 30 = 55 -> ceil(55) + 2 = 57
        #expect(spreadMargin == 57)
        #expect(spreadMargin - baseMargin == 15)
    }

    @Test func shadowSpreadExpandsSilhouette() throws {
        let size = 60
        let innerSize = 20
        let offset = (size - innerSize) / 2 // Square is at x: 20..40, y: 20..40
        let square = try solidSquare(size: innerSize)
        let placed = CGRect(x: offset, y: offset, width: innerSize, height: innerSize)
        let canvasSize = CGSize(width: size, height: size)

        let noSpread = ShadowEffect(distance: 0, blur: 0, spread: 0)
        let withSpread = ShadowEffect(distance: 0, blur: 0, spread: 6)

        let noSpreadCoverage = try LayerEffectsRenderer.shadowCoverage(square, placed: placed, size: canvasSize, shadow: noSpread)
        let withSpreadCoverage = try LayerEffectsRenderer.shadowCoverage(square, placed: placed, size: canvasSize, shadow: withSpread)

        let noSpreadRep = NSBitmapImageRep(cgImage: noSpreadCoverage)
        let withSpreadRep = NSBitmapImageRep(cgImage: withSpreadCoverage)

        // Point at x = 16, y = 30 (4px outside the square):
        // Without spread, this is completely outside (whiteComponent = 0)
        // With spread = 6, this is inside the expanded silhouette (whiteComponent > 0.8)
        let valNoSpread = try #require(noSpreadRep.colorAt(x: 16, y: 30)).whiteComponent
        let valWithSpread = try #require(withSpreadRep.colorAt(x: 16, y: 30)).whiteComponent

        #expect(valNoSpread < 0.1)
        #expect(valWithSpread > 0.8)
    }

    @Test func innerShadowChokeIntensifiesCoverage() throws {
        let size = 60
        let innerSize = 40
        let offset = (size - innerSize) / 2 // 10..50
        let square = try solidSquare(size: innerSize)
        let placed = CGRect(x: offset, y: offset, width: innerSize, height: innerSize)
        let canvasSize = CGSize(width: size, height: size)

        let noChoke = InnerShadowEffect(angle: 180, distance: 0, blur: 12, choke: 0)
        let withChoke = InnerShadowEffect(angle: 180, distance: 0, blur: 12, choke: 6)

        let noChokeCoverage = try LayerEffectsRenderer.innerCoverage(square, placed: placed, size: canvasSize, shadow: noChoke)
        let withChokeCoverage = try LayerEffectsRenderer.innerCoverage(square, placed: placed, size: canvasSize, shadow: withChoke)

        let noChokeRep = NSBitmapImageRep(cgImage: noChokeCoverage)
        let withChokeRep = NSBitmapImageRep(cgImage: withChokeCoverage)

        // Sample 4px inside the edge at x = 14, y = 30
        let noChokeVal = try #require(noChokeRep.colorAt(x: 14, y: 30)).whiteComponent
        let withChokeVal = try #require(withChokeRep.colorAt(x: 14, y: 30)).whiteComponent

        #expect(withChokeVal > noChokeVal + 0.1, "Choke must intensify shadow coverage inside the shape")
    }

    @Test func shadowSpreadCPUAndMetalParity() throws {
        guard let metal = MetalLayerEffects.shared else { return }

        let source = try solidSquare(size: 30, color: PaletteColor(red: 1, green: 1, blue: 1))
        let shadow = ShadowEffect(angle: 90, distance: 10, blur: 6, spread: 8, red: 0, green: 0, blue: 0, opacity: 0.8)
        var effects = LayerEffects()
        effects.shadow = shadow

        let inset = LayerEffectsRenderer.margin(for: effects)
        let width = source.width + Int(inset) * 2
        let height = source.height + Int(inset) * 2
        let placed = CGRect(x: inset, y: inset, width: CGFloat(source.width), height: CGFloat(source.height))

        let padded = try BrushRaster.context(width: width, height: height, mask: false)
        BrushRaster.draw(source, in: placed, mask: false, context: padded)
        let room = try #require(padded.makeImage())

        let metalImage = try metal.render(room, effects: effects)
        let metalBitmap = NSBitmapImageRep(cgImage: metalImage)

        let rendered = try LayerEffectsRenderer.render(source, mask: nil, effects: effects)
        let cpuBitmap = NSBitmapImageRep(cgImage: rendered.image)

        // Compare sample in the shadow spread region outside the source
        let sampleX = Int(inset) - 4
        let sampleY = Int(inset) + 15
        let metalColor = try #require(metalBitmap.colorAt(x: sampleX, y: sampleY))
        let cpuColor = try #require(cpuBitmap.colorAt(x: sampleX, y: sampleY))

        #expect(metalColor.alphaComponent > 0.3)
        #expect(cpuColor.alphaComponent > 0.3)
        #expect(abs(metalColor.alphaComponent - cpuColor.alphaComponent) < 0.15)
    }

    @Test func shadowSpreadPreservedInExport() async throws {
        let image = try solidSquare(size: 20, color: PaletteColor(red: 1, green: 1, blue: 1))
        let id = UUID()
        let transform = LayerTransform(origin: CGPoint(x: 40, y: 40), size: CGSize(width: 20, height: 20))
        // Shadow with 0 distance, 0 blur, 10 spread -> shadow becomes a 40x40 black square centered on the 20x20 white square
        let shadow = ShadowEffect(distance: 0, blur: 0, spread: 10, red: 0, green: 0, blue: 0, opacity: 1.0)

        let effects = LayerEffects(shadow: shadow)
        let record = ProjectLayerRecord(id: id, name: "ShadowSpreadLayer", isVisible: true, transform: transform,
                                        imageFile: "\(id).png", effects: effects)
        let manifest = ProjectManifest(documentID: UUID(), width: 100, height: 100, activeLayerID: id, layers: [record])
        let snapshot = ProjectSnapshot(manifest: manifest, images: [id: ImportedImage(image: image, thumbnail: image, name: "ShadowSpreadLayer")])

        let pngData = try await ImageExporter.shared.pngData(snapshot)
        let rep = try #require(NSBitmapImageRep(data: pngData))

        // Center of square (50, 50) is white source
        let centerPixel = try #require(rep.colorAt(x: 50, y: 50))
        #expect(centerPixel.redComponent > 0.8)

        // 5px outside the 20x20 square (e.g. at x = 35, y = 50):
        // Within the 10px spread, so it must be black shadow!
        let spreadPixel = try #require(rep.colorAt(x: 35, y: 50))
        #expect(spreadPixel.alphaComponent > 0.8)
        #expect(spreadPixel.redComponent < 0.2 && spreadPixel.greenComponent < 0.2 && spreadPixel.blueComponent < 0.2)
    }
}
