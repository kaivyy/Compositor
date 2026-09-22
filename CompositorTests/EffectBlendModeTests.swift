import AppKit
import Testing
@testable import Compositor

@Suite struct EffectBlendModeTests {
    private func solidSquare(size: Int = 40, color: PaletteColor = PaletteColor(red: 1, green: 1, blue: 1)) throws -> CGImage {
        let context = try BrushRaster.context(width: size, height: size, mask: false)
        context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try #require(context.makeImage())
    }

    private func pixelColor(in image: CGImage, x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    @Test func effectBlendModeDefaults() {
        let stroke = StrokeEffect()
        #expect(stroke.blendMode == .normal)

        let shadow = ShadowEffect()
        #expect(shadow.blendMode == .multiply)

        let overlay = ColorOverlayEffect()
        #expect(overlay.blendMode == .normal)

        let innerShadow = InnerShadowEffect()
        #expect(innerShadow.blendMode == .multiply)

        let outerGlow = OuterGlowEffect()
        #expect(outerGlow.blendMode == .screen)

        let innerGlow = InnerGlowEffect()
        #expect(innerGlow.blendMode == .screen)
    }

    @Test func codableBackwardCompatibilityDefaults() throws {
        // Older JSON without blendMode should decode to respective default blend modes
        let strokeJSON = """
        { "size": 6, "red": 0, "green": 0, "blue": 0, "opacity": 1.0, "position": "outside" }
        """.data(using: .utf8)!
        let decodedStroke = try JSONDecoder().decode(StrokeEffect.self, from: strokeJSON)
        #expect(decodedStroke.blendMode == .normal)

        let shadowJSON = """
        { "angle": 90, "distance": 15, "blur": 10, "spread": 0, "red": 0, "green": 0, "blue": 0, "opacity": 0.5 }
        """.data(using: .utf8)!
        let decodedShadow = try JSONDecoder().decode(ShadowEffect.self, from: shadowJSON)
        #expect(decodedShadow.blendMode == .multiply)

        let overlayJSON = """
        { "red": 1.0, "green": 0.0, "blue": 0.0, "opacity": 0.8 }
        """.data(using: .utf8)!
        let decodedOverlay = try JSONDecoder().decode(ColorOverlayEffect.self, from: overlayJSON)
        #expect(decodedOverlay.blendMode == .normal)

        let innerShadowJSON = """
        { "angle": 90, "distance": 5, "blur": 4, "choke": 0, "red": 0, "green": 0, "blue": 0, "opacity": 0.5 }
        """.data(using: .utf8)!
        let decodedInnerShadow = try JSONDecoder().decode(InnerShadowEffect.self, from: innerShadowJSON)
        #expect(decodedInnerShadow.blendMode == .multiply)

        let outerGlowJSON = """
        { "size": 15, "red": 1.0, "green": 0.8, "blue": 0.0, "opacity": 0.75 }
        """.data(using: .utf8)!
        let decodedOuterGlow = try JSONDecoder().decode(OuterGlowEffect.self, from: outerGlowJSON)
        #expect(decodedOuterGlow.blendMode == .screen)

        let innerGlowJSON = """
        { "size": 10, "red": 1.0, "green": 1.0, "blue": 1.0, "opacity": 0.75 }
        """.data(using: .utf8)!
        let decodedInnerGlow = try JSONDecoder().decode(InnerGlowEffect.self, from: innerGlowJSON)
        #expect(decodedInnerGlow.blendMode == .screen)
    }

    @Test func codableCustomBlendModesRoundTrip() throws {
        var effects = LayerEffects()
        effects.stroke = StrokeEffect(size: 4, blendMode: .screen)
        effects.shadow = ShadowEffect(blendMode: .colorBurn)
        effects.colorOverlay = ColorOverlayEffect(blendMode: .multiply)
        effects.innerShadow = InnerShadowEffect(blendMode: .darken)
        effects.outerGlow = OuterGlowEffect(blendMode: .overlay)
        effects.innerGlow = InnerGlowEffect(blendMode: .softLight)

        let data = try JSONEncoder().encode(effects)
        let decoded = try JSONDecoder().decode(LayerEffects.self, from: data)

        #expect(decoded.stroke?.blendMode == .screen)
        #expect(decoded.shadow?.blendMode == .colorBurn)
        #expect(decoded.colorOverlay?.blendMode == .multiply)
        #expect(decoded.innerShadow?.blendMode == .darken)
        #expect(decoded.outerGlow?.blendMode == .overlay)
        #expect(decoded.innerGlow?.blendMode == .softLight)
    }

    @Test func renderPassesGeneration() throws {
        let square = try solidSquare(size: 30)
        var effects = LayerEffects()
        effects.shadow = ShadowEffect(distance: 10, blur: 5, blendMode: .multiply)
        effects.outerGlow = OuterGlowEffect(size: 10, blendMode: .screen)
        effects.stroke = StrokeEffect(size: 4, position: .outside, blendMode: .normal)

        let rendered = try LayerEffectsRenderer.renderPasses(square, mask: nil, effects: effects)
        // Passes should be: 1. Drop Shadow, 2. Outer Glow, 3. Outside Stroke, 4. Layer Content
        #expect(rendered.passes.count == 4)
        #expect(rendered.passes[0].blendMode == .multiply)
        #expect(rendered.passes[1].blendMode == .screen)
        #expect(rendered.passes[2].blendMode == .normal)
        #expect(rendered.passes[3].blendMode == nil) // Content inherits layer's blend mode
    }

    @Test func dropShadowMultiplyCompositingOnBackdrop() throws {
        let size = 40
        let square = try solidSquare(size: size, color: PaletteColor(red: 1, green: 1, blue: 1))
        var effects = LayerEffects()
        // Sharp pure red shadow dropped 20px straight down
        effects.shadow = ShadowEffect(angle: 90, distance: 20, blur: 0, spread: 0,
                                      red: 1, green: 0, blue: 0, opacity: 1.0, blendMode: .multiply)

        let rendered = try LayerEffectsRenderer.renderPasses(square, mask: nil, effects: effects)
        let canvasW = 100, canvasH = 100
        let canvasCtx = try BrushRaster.context(width: canvasW, height: canvasH, mask: false)

        // Fill backdrop with 80% gray (0.8, 0.8, 0.8)
        canvasCtx.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1.0))
        canvasCtx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

        // Composite passes into canvas
        let transform = LayerTransform(origin: CGPoint(x: 30, y: 20), size: CGSize(width: size, height: size))
        let grown = LayerEffectsRenderer.placed(transform, image: rendered.image, inset: rendered.inset)
        for pass in rendered.passes {
            let mode = pass.blendMode ?? .normal
            LayerRenderer.draw(pass.image, transform: grown, center: grown.center,
                               opacity: 1.0, blendMode: mode, mask: nil, in: canvasCtx)
        }

        let canvasImage = try #require(canvasCtx.makeImage())
        // Inspect a point in the shadow region below the square (e.g. x = 50, y = 70)
        // Square is at y: 20...60, shadow is at y: 40...80.
        // At y = 70, it is outside the square and inside the shadow.
        // With Multiply on 0.8 gray backdrop:
        // Red = 0.8 * 1.0 = 0.8
        // Green = 0.8 * 0.0 = 0.0
        // Blue = 0.8 * 0.0 = 0.0
        let shadowPixel = try #require(pixelColor(in: canvasImage, x: 50, y: 70))
        #expect(abs(shadowPixel.r - 0.8) < 0.1)
        #expect(shadowPixel.g < 0.2)
        #expect(shadowPixel.b < 0.2)
    }

    @Test func outerGlowScreenCompositingOnBackdrop() throws {
        let size = 40
        let square = try solidSquare(size: size, color: PaletteColor(red: 0, green: 0, blue: 0))
        var effects = LayerEffects()
        // Pure green outer glow
        effects.outerGlow = OuterGlowEffect(size: 15, red: 0, green: 1, blue: 0, opacity: 1.0, blendMode: .screen)

        let rendered = try LayerEffectsRenderer.renderPasses(square, mask: nil, effects: effects)
        let canvasW = 120, canvasH = 120
        let canvasCtx = try BrushRaster.context(width: canvasW, height: canvasH, mask: false)

        // Fill backdrop with deep blue (0.0, 0.0, 0.6)
        canvasCtx.setFillColor(CGColor(srgbRed: 0.0, green: 0.0, blue: 0.6, alpha: 1.0))
        canvasCtx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

        // Composite passes into canvas
        let transform = LayerTransform(origin: CGPoint(x: 40, y: 40), size: CGSize(width: size, height: size))
        let grown = LayerEffectsRenderer.placed(transform, image: rendered.image, inset: rendered.inset)
        for pass in rendered.passes {
            let mode = pass.blendMode ?? .normal
            LayerRenderer.draw(pass.image, transform: grown, center: grown.center,
                               opacity: 1.0, blendMode: mode, mask: nil, in: canvasCtx)
        }

        let canvasImage = try #require(canvasCtx.makeImage())
        // Inspect a point in the glow region just outside the square (e.g. x = 35, y = 60)
        // With Screen on blue backdrop:
        // Green is blended in, while Blue from the backdrop is preserved!
        let glowPixel = try #require(pixelColor(in: canvasImage, x: 35, y: 60))
        #expect(glowPixel.g > 0.1)
        #expect(glowPixel.b > 0.4)
    }

    @Test func colorOverlayNormalVsMultiplyOnContent() throws {
        let size = 30
        // Red square
        let square = try solidSquare(size: size, color: PaletteColor(red: 1, green: 0, blue: 0))

        // 1. Normal overlay with pure blue -> Result should be pure Blue (0, 0, 1)
        var normalEffects = LayerEffects()
        normalEffects.colorOverlay = ColorOverlayEffect(red: 0, green: 0, blue: 1, opacity: 1.0, blendMode: .normal)
        let normalRendered = try LayerEffectsRenderer.renderPasses(square, mask: nil, effects: normalEffects)
        let normalContentPass = try #require(normalRendered.passes.last)
        let normalPixel = try #require(pixelColor(in: normalContentPass.image, x: Int(normalRendered.inset) + 15, y: Int(normalRendered.inset) + 15))
        #expect(normalPixel.r < 0.05)
        #expect(normalPixel.b > 0.95)

        // 2. Multiply overlay with pure blue over red source -> Result should be Black (1*0, 0*0, 0*1 = 0, 0, 0)
        var multiplyEffects = LayerEffects()
        multiplyEffects.colorOverlay = ColorOverlayEffect(red: 0, green: 0, blue: 1, opacity: 1.0, blendMode: .multiply)
        let multiplyRendered = try LayerEffectsRenderer.renderPasses(square, mask: nil, effects: multiplyEffects)
        let multiplyContentPass = try #require(multiplyRendered.passes.last)
        let multiplyPixel = try #require(pixelColor(in: multiplyContentPass.image, x: Int(multiplyRendered.inset) + 15, y: Int(multiplyRendered.inset) + 15))
        #expect(multiplyPixel.r < 0.05)
        #expect(multiplyPixel.g < 0.05)
        #expect(multiplyPixel.b < 0.05)
    }
}
