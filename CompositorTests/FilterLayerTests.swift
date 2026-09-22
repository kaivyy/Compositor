import Foundation
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct FilterLayerTests {
    @Test func filterLayerModelDefaultsAndValidation() throws {
        let gaussian = LayerFilter(kind: .gaussianBlur)
        #expect(gaussian.kind == .gaussianBlur)
        #expect(gaussian.settings.radius == 10)
        #expect(gaussian.isValid)

        let motion = LayerFilter(kind: .motionBlur)
        #expect(motion.kind == .motionBlur)
        #expect(motion.settings.angle == 0)
        #expect(motion.settings.distance == 10)
        #expect(motion.isValid)

        let noise = LayerFilter(kind: .addNoise)
        #expect(noise.kind == .addNoise)
        #expect(noise.settings.amount == 10)
        #expect(!noise.settings.gaussian)
        #expect(!noise.settings.monochromatic)
        #expect(noise.isValid)

        let lens = LayerFilter(kind: .lensCorrection)
        #expect(lens.kind == .lensCorrection)
        #expect(lens.settings.distortion == 0)
        #expect(lens.isValid)

        let invert = LayerFilter(kind: .invert)
        #expect(invert.kind == .invert)
        #expect(invert.isValid)
        #expect(!invert.kind.isEditable)

        var invalid = gaussian
        invalid.settings.radius = -5
        #expect(!invalid.isValid)
    }

    @Test func filterSettingsConversion() {
        var s = FilterSettings()
        s.radius = 25
        s.angle = 45
        s.distance = 150
        s.amount = 75
        s.gaussian = true
        s.monochromatic = true
        s.distortion = -20

        let layerSettings = LayerFilterSettings(from: s, seed: 42)
        #expect(layerSettings.radius == 25)
        #expect(layerSettings.angle == 45)
        #expect(layerSettings.distance == 150)
        #expect(layerSettings.amount == 75)
        #expect(layerSettings.gaussian)
        #expect(layerSettings.monochromatic)
        #expect(layerSettings.distortion == -20)
        #expect(layerSettings.seed == 42)

        let back = layerSettings.toFilterSettings()
        #expect(back.radius == 25)
        #expect(back.angle == 45)
        #expect(back.distance == 150)
        #expect(back.amount == 75)
        #expect(back.gaussian)
        #expect(back.monochromatic)
        #expect(back.distortion == -20)
    }

    @Test func layerFilterCodableRoundTrip() throws {
        let filter = LayerFilter(kind: .motionBlur, settings: LayerFilterSettings(from: FilterSettings(angle: 30, distance: 80)))
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(LayerFilter.self, from: data)
        #expect(decoded == filter)
        #expect(decoded.kind == .motionBlur)
        #expect(decoded.settings.angle == 30)
        #expect(decoded.settings.distance == 80)
    }

    @Test func imageLayerFilterInvariants() {
        var layer = ImageLayer(name: "Blur Filter", blankSize: CGSize(width: 100, height: 100))
        layer.filter = LayerFilter(kind: .gaussianBlur)
        #expect(layer.isFilterLayer)

        // Having an asset violates the invariant
        layer.asset = ImportedImage(image: CGImage.makeSolidColor(width: 1, height: 1, color: .black)!, thumbnail: CGImage.makeSolidColor(width: 1, height: 1, color: .black)!, name: "test")
        #expect(!layer.isFilterLayer)

        layer.asset = nil
        #expect(layer.isFilterLayer)

        // Having an adjustment violates the invariant
        layer.adjustment = LayerAdjustment(kind: .curves)
        #expect(!layer.isFilterLayer)

        layer.adjustment = nil
        #expect(layer.isFilterLayer)

        // Being a group violates the invariant
        layer.isGroup = true
        #expect(!layer.isFilterLayer)
    }

    private func rendered(_ session: EditorSession) async throws -> [UInt8] {
        let snapshot = try #require(session.projectSnapshot())
        let raster = try await ImageExporter.shared.render(snapshot)
        let image = raster.image
        let ctx = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: ctx)
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    private func makeImage(width: Int, height: Int, color: PaletteColor, alpha: [UInt8]) throws -> ImportedImage {
        let bytes = alpha.flatMap { a in [UInt8((color.red * CGFloat(a)).rounded()), UInt8((color.green * CGFloat(a)).rounded()), UInt8((color.blue * CGFloat(a)).rounded()), a] }
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return ImportedImage(image: image, thumbnail: image, name: "Fixture")
    }

    @Test func globalFilterAffectsBelowButNotAbove() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        s.insert(try makeImage(width: 2, height: 2, color: .white, alpha: [255, 255, 255, 255]))

        var filterLayer = ImageLayer(name: "Invert Filter", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .invert)
        s.document?.layers.append(filterLayer)

        let inverted = try await rendered(s)
        #expect(inverted == [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255])

        // Add layer above filter: red in top-left pixel only
        s.insert(try makeImage(width: 2, height: 2, color: PaletteColor(red: 1, green: 0, blue: 0), alpha: [255, 0, 0, 0]))
        let withTop = try await rendered(s)
        #expect(Array(withTop[0..<4]) == [255, 0, 0, 255])
        #expect(Array(withTop[4..<8]) == [0, 0, 0, 255])
    }

    @Test func gaussianBlurRendersOnComposite() async throws {
        let s = EditorSession(); s.createDocument(width: 10, height: 2)
        // Left 5 columns black, right 5 columns white
        var alpha = [UInt8]()
        for _ in 0..<2 {
            for _ in 0..<5 { alpha.append(0) }
            for _ in 0..<5 { alpha.append(255) }
        }
        s.insert(try makeImage(width: 10, height: 2, color: .white, alpha: alpha))

        var filterLayer = ImageLayer(name: "Blur Filter", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .gaussianBlur, settings: LayerFilterSettings(from: FilterSettings(radius: 2)))
        s.document?.layers.append(filterLayer)

        let blurred = try await rendered(s)
        // Near column 5 (boundary between 4 and 5), pixels should have intermediate values
        let col4Alpha = blurred[(0 * 10 + 4) * 4 + 3]
        let col5Alpha = blurred[(0 * 10 + 5) * 4 + 3]
        #expect(col4Alpha > 10 && col4Alpha < 240, "Hard edge is softened by blur: alpha was \(col4Alpha)")
        #expect(col5Alpha > 10 && col5Alpha < 240, "Hard edge is softened by blur: alpha was \(col5Alpha)")
    }

    @Test func filterLayerOpacityAndMask() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        s.insert(try makeImage(width: 2, height: 2, color: .white, alpha: [255, 255, 255, 255]))

        var filterLayer = ImageLayer(name: "Invert Filter", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .invert)
        filterLayer.opacity = 0.5
        s.document?.layers.append(filterLayer)

        let semi = try await rendered(s)
        #expect(abs(Int(semi[0]) - 128) <= 2)
        #expect(abs(Int(semi[1]) - 128) <= 2)
        #expect(abs(Int(semi[2]) - 128) <= 2)
        #expect(semi[3] == 255)

        // Full opacity, but masked out (revealing: false)
        s.document?.layers[1].opacity = 1.0
        s.document?.layers[1].mask = LayerMask.solid(revealing: false)
        let masked = try await rendered(s)
        #expect(masked == [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255])
    }
}

private extension CGImage {
    static func makeSolidColor(width: Int, height: Int, color: CGColor) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
