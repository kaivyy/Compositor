import AppKit
import Testing
@testable import Compositor

@Suite struct CenterStrokeTests {
    private func solidSquare(size: Int = 40, color: PaletteColor = PaletteColor(red: 1, green: 1, blue: 1)) throws -> CGImage {
        let context = try BrushRaster.context(width: size, height: size, mask: false)
        context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try #require(context.makeImage())
    }

    @Test func strokePositionDefaultsAndToggles() {
        var stroke = StrokeEffect()
        #expect(stroke.position == .outside)
        #expect(stroke.inside == false)

        stroke.position = .center
        #expect(stroke.position == .center)
        #expect(stroke.inside == false)

        stroke.inside = true
        #expect(stroke.position == .inside)
        #expect(stroke.inside == true)

        stroke.inside = false
        #expect(stroke.position == .outside)
        #expect(stroke.inside == false)
    }

    @Test func strokeCodableBackwardAndForwardCompatibility() throws {
        // 1. Legacy JSON with only `inside: true`
        let legacyInsideJSON = """
        { "size": 6, "red": 1, "green": 0, "blue": 0, "opacity": 1.0, "inside": true }
        """.data(using: .utf8)!
        let decodedInside = try JSONDecoder().decode(StrokeEffect.self, from: legacyInsideJSON)
        #expect(decodedInside.position == .inside)
        #expect(decodedInside.inside == true)

        // 2. Legacy JSON with only `inside: false`
        let legacyOutsideJSON = """
        { "size": 6, "red": 1, "green": 0, "blue": 0, "opacity": 1.0, "inside": false }
        """.data(using: .utf8)!
        let decodedOutside = try JSONDecoder().decode(StrokeEffect.self, from: legacyOutsideJSON)
        #expect(decodedOutside.position == .outside)
        #expect(decodedOutside.inside == false)

        // 3. New JSON with `position: "center"`
        let centerJSON = """
        { "size": 6, "red": 0, "green": 1, "blue": 0, "opacity": 0.8, "position": "center" }
        """.data(using: .utf8)!
        let decodedCenter = try JSONDecoder().decode(StrokeEffect.self, from: centerJSON)
        #expect(decodedCenter.position == .center)
        #expect(decodedCenter.inside == false)

        // 4. Forward compatibility: encoding a center stroke outputs both position and inside: false
        let centerStroke = StrokeEffect(size: 8, red: 0, green: 0, blue: 1, opacity: 0.9, position: .center)
        let encodedData = try JSONEncoder().encode(centerStroke)
        let roundTripped = try JSONDecoder().decode(StrokeEffect.self, from: encodedData)
        #expect(roundTripped == centerStroke)
        #expect(roundTripped.position == .center)

        let encodedObj = try #require(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        #expect(encodedObj["position"] as? String == "center")
        #expect(encodedObj["inside"] as? Bool == false)
    }

    @Test func strokeMarginCalculationForPositions() {
        var outsideEffects = LayerEffects()
        outsideEffects.stroke = StrokeEffect(size: 10, position: .outside)
        #expect(LayerEffectsRenderer.margin(for: outsideEffects) == 12) // 10 + 2

        var insideEffects = LayerEffects()
        insideEffects.stroke = StrokeEffect(size: 10, position: .inside)
        #expect(LayerEffectsRenderer.margin(for: insideEffects) == 2) // 0 + 2

        var centerEffects = LayerEffects()
        centerEffects.stroke = StrokeEffect(size: 10, position: .center)
        #expect(LayerEffectsRenderer.margin(for: centerEffects) == 7) // ceil(10/2) + 2 = 7

        var oddCenterEffects = LayerEffects()
        oddCenterEffects.stroke = StrokeEffect(size: 7, position: .center)
        #expect(LayerEffectsRenderer.margin(for: oddCenterEffects) == 6) // ceil(7/2) + 2 = 4 + 2 = 6
    }

    @Test func centerStrokeCoverageGeometry() throws {
        let size = 60
        let innerSize = 40
        let offset = (size - innerSize) / 2 // 10..50 is the square
        let square = try solidSquare(size: innerSize)

        let placed = CGRect(x: offset, y: offset, width: innerSize, height: innerSize)
        let canvasSize = CGSize(width: size, height: size)

        let outsideStroke = StrokeEffect(size: 4, position: .outside)
        let insideStroke = StrokeEffect(size: 4, position: .inside)
        let centerStroke = StrokeEffect(size: 4, position: .center)

        let outsideCoverage = try LayerEffectsRenderer.strokeCoverage(square, placed: placed, size: canvasSize, stroke: outsideStroke)
        let insideCoverage = try LayerEffectsRenderer.strokeCoverage(square, placed: placed, size: canvasSize, stroke: insideStroke)
        let centerCoverage = try LayerEffectsRenderer.strokeCoverage(square, placed: placed, size: canvasSize, stroke: centerStroke)

        let outRep = NSBitmapImageRep(cgImage: outsideCoverage)
        let inRep = NSBitmapImageRep(cgImage: insideCoverage)
        let centerRep = NSBitmapImageRep(cgImage: centerCoverage)

        // 1px outside the square (x = 9, y = 30)
        let outAt9 = try #require(outRep.colorAt(x: 9, y: 30)).whiteComponent
        let inAt9 = try #require(inRep.colorAt(x: 9, y: 30)).whiteComponent
        let centerAt9 = try #require(centerRep.colorAt(x: 9, y: 30)).whiteComponent
        #expect(outAt9 > 0.8)
        #expect(inAt9 < 0.1)
        #expect(centerAt9 > 0.8, "Center stroke must cover 1px outside the boundary")

        // 1px inside the square (x = 11, y = 30)
        let outAt11 = try #require(outRep.colorAt(x: 11, y: 30)).whiteComponent
        let inAt11 = try #require(inRep.colorAt(x: 11, y: 30)).whiteComponent
        let centerAt11 = try #require(centerRep.colorAt(x: 11, y: 30)).whiteComponent
        #expect(outAt11 < 0.1)
        #expect(inAt11 > 0.8)
        #expect(centerAt11 > 0.8, "Center stroke must cover 1px inside the boundary")

        // 3px outside the square (x = 7, y = 30)
        let outAt7 = try #require(outRep.colorAt(x: 7, y: 30)).whiteComponent
        let centerAt7 = try #require(centerRep.colorAt(x: 7, y: 30)).whiteComponent
        #expect(outAt7 > 0.8, "Outside stroke of 4 reaches x=7")
        #expect(centerAt7 < 0.1, "Center stroke of 4 only reaches 2px outside (x=8..9)")

        // 3px inside the square (x = 13, y = 30)
        let inAt13 = try #require(inRep.colorAt(x: 13, y: 30)).whiteComponent
        let centerAt13 = try #require(centerRep.colorAt(x: 13, y: 30)).whiteComponent
        #expect(inAt13 > 0.8, "Inside stroke of 4 reaches x=13")
        #expect(centerAt13 < 0.1, "Center stroke of 4 only reaches 2px inside (x=10..11)")
    }

    @Test func centerStrokeCPUAndMetalParity() throws {
        guard let metal = MetalLayerEffects.shared else { return }

        let source = try solidSquare(size: 40, color: PaletteColor(red: 1, green: 1, blue: 1))
        let stroke = StrokeEffect(size: 6, red: 1, green: 0, blue: 0, opacity: 1, position: .center)
        var effects = LayerEffects()
        effects.stroke = stroke

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

        // Test sample 1px outside the square boundary
        let sampleOutX = Int(inset) - 1
        let sampleY = Int(inset) + 20
        let metalOutColor = try #require(metalBitmap.colorAt(x: sampleOutX, y: sampleY))
        let cpuOutColor = try #require(cpuBitmap.colorAt(x: sampleOutX, y: sampleY))

        #expect(abs(metalOutColor.alphaComponent - cpuOutColor.alphaComponent) < 0.15)
        #expect(abs(metalOutColor.redComponent - cpuOutColor.redComponent) < 0.15)

        // Test sample 1px inside the square boundary
        let sampleInX = Int(inset) + 1
        let metalInColor = try #require(metalBitmap.colorAt(x: sampleInX, y: sampleY))
        let cpuInColor = try #require(cpuBitmap.colorAt(x: sampleInX, y: sampleY))

        #expect(abs(metalInColor.alphaComponent - cpuInColor.alphaComponent) < 0.15)
        #expect(abs(metalInColor.redComponent - cpuInColor.redComponent) < 0.15)
    }

    @Test func centerStrokePreservedInExport() async throws {
        let image = try solidSquare(size: 30, color: PaletteColor(red: 1, green: 1, blue: 1))
        let id = UUID()
        let transform = LayerTransform(origin: CGPoint(x: 20, y: 20), size: CGSize(width: 30, height: 30))
        let stroke = StrokeEffect(size: 6, red: 0, green: 0, blue: 1, opacity: 1, position: .center)

        let effects = LayerEffects(stroke: stroke)
        let record = ProjectLayerRecord(id: id, name: "CenterStrokeLayer", isVisible: true, transform: transform,
                                        imageFile: "\(id).png", effects: effects)
        let manifest = ProjectManifest(documentID: UUID(), width: 100, height: 100, activeLayerID: id, layers: [record])
        let snapshot = ProjectSnapshot(manifest: manifest, images: [id: ImportedImage(image: image, thumbnail: image, name: "CenterStrokeLayer")])

        let pngData = try await ImageExporter.shared.pngData(snapshot)
        let rep = try #require(NSBitmapImageRep(data: pngData))

        // Center stroke extends 3px outside and 3px inside the 30x30 square placed at (20, 20).
        // 1px outside left edge is at x = 19, y = 35
        let outsidePixel = try #require(rep.colorAt(x: 19, y: 35))
        #expect(outsidePixel.alphaComponent > 0.8)
        #expect(outsidePixel.blueComponent > 0.8)
        #expect(outsidePixel.redComponent < 0.2)

        // 1px inside left edge is at x = 21, y = 35 (drawn on top of the white square, so it is blue)
        let insidePixel = try #require(rep.colorAt(x: 21, y: 35))
        #expect(insidePixel.alphaComponent > 0.8)
        #expect(insidePixel.blueComponent > 0.8)
        #expect(insidePixel.redComponent < 0.2)

        // Center of square (35, 35) is beyond the 3px stroke reach, remaining white
        let centerPixel = try #require(rep.colorAt(x: 35, y: 35))
        #expect(centerPixel.redComponent > 0.8 && centerPixel.greenComponent > 0.8 && centerPixel.blueComponent > 0.8)
    }

    @Test func centerStrokeCombinedWithShadowAndGlow() throws {
        let source = try solidSquare(size: 40, color: PaletteColor(red: 1, green: 1, blue: 1))
        var effects = LayerEffects()
        effects.stroke = StrokeEffect(size: 4, red: 0, green: 0, blue: 0, opacity: 1, position: .center)
        effects.outerGlow = OuterGlowEffect(size: 8, red: 1, green: 0, blue: 0, opacity: 1)
        effects.shadow = ShadowEffect(angle: 180, distance: 15, blur: 4, red: 0, green: 0, blue: 1, opacity: 1)

        let rendered = try LayerEffectsRenderer.render(source, mask: nil, effects: effects)
        let bitmap = NSBitmapImageRep(cgImage: rendered.image)
        let inset = Int(rendered.inset)

        // Center pixel is white
        let centerColor = try #require(bitmap.colorAt(x: inset + 20, y: inset + 20))
        #expect(centerColor.redComponent > 0.8 && centerColor.greenComponent > 0.8 && centerColor.blueComponent > 0.8)

        // Stroke at 1px inside the edge (black)
        let strokeInside = try #require(bitmap.colorAt(x: inset + 1, y: inset + 20))
        #expect(strokeInside.alphaComponent > 0.8)
        #expect(strokeInside.redComponent < 0.2 && strokeInside.greenComponent < 0.2 && strokeInside.blueComponent < 0.2)

        // Stroke at 1px outside the edge (black)
        let strokeOutside = try #require(bitmap.colorAt(x: inset - 1, y: inset + 20))
        #expect(strokeOutside.alphaComponent > 0.8)
        #expect(strokeOutside.redComponent < 0.2 && strokeOutside.greenComponent < 0.2 && strokeOutside.blueComponent < 0.2)
    }
}
