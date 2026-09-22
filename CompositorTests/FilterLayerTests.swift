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
