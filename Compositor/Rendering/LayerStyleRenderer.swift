import CoreGraphics
import CoreImage
import Foundation

nonisolated enum LayerStyleRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                         bytesPerRow: width * 4, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    }

    /// Renders a layer's styles over its raster content.
    /// Returns the padded composite image and the padding amount in pixels.
    static func render(image: CGImage, styles: LayerStyles) -> (image: CGImage, padding: CGFloat)? {
        guard styles.hasActiveEffects else { return (image, 0) }

        let padding = styles.contentPadding
        let width = image.width + Int(padding * 2)
        let height = image.height + Int(padding * 2)

        guard let context = makeContext(width: width, height: height) else { return nil }
        let contentRect = CGRect(x: padding, y: padding, width: CGFloat(image.width), height: CGFloat(image.height))
        let targetBounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

        // 1. Drop Shadow (bottom-most effect)
        if let shadow = styles.dropShadow, shadow.isEnabled, shadow.opacity > 0 {
            drawDropShadow(shadow, sourceImage: image, contentRect: contentRect, in: context, bounds: targetBounds)
        }

        // 2. Outer Glow
        if let glow = styles.outerGlow, glow.isEnabled, glow.opacity > 0, glow.size > 0 {
            drawOuterGlow(glow, sourceImage: image, contentRect: contentRect, in: context, bounds: targetBounds)
        }

        // 3. Stroke (Outside or Center)
        if let stroke = styles.stroke, stroke.isEnabled, stroke.size > 0, stroke.position != .inside {
            drawStroke(stroke, sourceImage: image, contentRect: contentRect, in: context, bounds: targetBounds)
        }

        // 4. Content fill + Color Overlay
        drawContent(image, overlay: styles.colorOverlay, contentRect: contentRect, in: context)

        // 5. Stroke (Inside)
        if let stroke = styles.stroke, stroke.isEnabled, stroke.size > 0, stroke.position == .inside {
            drawInsideStroke(stroke, sourceImage: image, contentRect: contentRect, in: context)
        }

        guard let output = context.makeImage() else { return nil }
        return (output, padding)
    }

    private static func drawContent(_ image: CGImage, overlay: ColorOverlayEffect?, contentRect: CGRect, in context: CGContext) {
        context.saveGState()
        context.draw(image, in: contentRect)
        if let overlay, overlay.isEnabled, overlay.opacity > 0 {
            context.setAlpha(overlay.opacity)
            context.setBlendMode(overlay.blendMode.cgMode)
            context.clip(to: contentRect, mask: image)
            context.setFillColor(overlay.color.cgColor)
            context.fill(contentRect)
        }
        context.restoreGState()
    }

    private static func alphaSilhouette(of ciImage: CIImage) -> CIImage {
        // Transform any image into a solid white silhouette with the original alpha,
        // so morphology and blur filters operate purely on alpha geometry regardless of content color.
        ciImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    private static func drawDropShadow(_ shadow: DropShadowEffect, sourceImage: CGImage, contentRect: CGRect, in context: CGContext, bounds: CGRect) {
        let radians = shadow.angle * .pi / 180
        let dx = shadow.distance * cos(radians)
        // In standard CGContext, y increases upwards. A positive angle of 90 degrees points down in screen space.
        let dy = -shadow.distance * sin(radians)

        let ciInput = CIImage(cgImage: sourceImage)
        let silhouette = alphaSilhouette(of: ciInput)
        guard let colorGen = CIFilter(name: "CIConstantColorGenerator", parameters: [
            kCIInputColorKey: CIColor(cgColor: shadow.color.cgColor)
        ]), let colorImg = colorGen.outputImage else { return }

        let masked = colorImg.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: silhouette,
            kCIInputBackgroundImageKey: CIImage.empty()
        ]).cropped(to: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))

        let blurRadius = max(0.1, shadow.size)
        let blurred = masked.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: blurRadius
        ])

        let transform = CGAffineTransform(translationX: contentRect.minX + dx, y: contentRect.minY + dy)
        let translated = blurred.transformed(by: transform).cropped(to: bounds)

        context.saveGState()
        context.setAlpha(shadow.opacity)
        context.setBlendMode(shadow.blendMode.cgMode)
        if let cgShadow = ciContext.createCGImage(translated, from: bounds) {
            context.draw(cgShadow, in: bounds)
        }
        context.restoreGState()
    }

    private static func drawOuterGlow(_ glow: OuterGlowEffect, sourceImage: CGImage, contentRect: CGRect, in context: CGContext, bounds: CGRect) {
        let ciInput = CIImage(cgImage: sourceImage)
        let silhouette = alphaSilhouette(of: ciInput)
        guard let colorGen = CIFilter(name: "CIConstantColorGenerator", parameters: [
            kCIInputColorKey: CIColor(cgColor: glow.color.cgColor)
        ]), let colorImg = colorGen.outputImage else { return }

        let masked = colorImg.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: silhouette,
            kCIInputBackgroundImageKey: CIImage.empty()
        ]).cropped(to: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))

        let blurRadius = max(0.1, glow.size)
        let blurred = masked.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: blurRadius
        ])

        let transform = CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY)
        let translated = blurred.transformed(by: transform).cropped(to: bounds)

        context.saveGState()
        context.setAlpha(glow.opacity)
        context.setBlendMode(glow.blendMode.cgMode)
        if let cgGlow = ciContext.createCGImage(translated, from: bounds) {
            context.draw(cgGlow, in: bounds)
        }
        context.restoreGState()
    }

    private static func drawStroke(_ stroke: StrokeEffect, sourceImage: CGImage, contentRect: CGRect, in context: CGContext, bounds: CGRect) {
        let ciInput = CIImage(cgImage: sourceImage)
        let silhouette = alphaSilhouette(of: ciInput)
        guard let colorGen = CIFilter(name: "CIConstantColorGenerator", parameters: [
            kCIInputColorKey: CIColor(cgColor: stroke.color.cgColor)
        ]), let colorImg = colorGen.outputImage else { return }

        let strokeRadius = stroke.position == .center ? max(1, stroke.size / 2) : stroke.size
        let dilated = silhouette.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: strokeRadius
        ])

        let maskedStroke = colorImg.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: dilated,
            kCIInputBackgroundImageKey: CIImage.empty()
        ])

        let transform = CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY)
        let translated = maskedStroke.transformed(by: transform).cropped(to: bounds)

        context.saveGState()
        context.setAlpha(stroke.opacity)
        context.setBlendMode(stroke.blendMode.cgMode)
        if let cgStroke = ciContext.createCGImage(translated, from: bounds) {
            context.draw(cgStroke, in: bounds)
        }
        context.restoreGState()
    }

    private static func drawInsideStroke(_ stroke: StrokeEffect, sourceImage: CGImage, contentRect: CGRect, in context: CGContext) {
        let ciInput = CIImage(cgImage: sourceImage)
        let silhouette = alphaSilhouette(of: ciInput)
        guard let colorGen = CIFilter(name: "CIConstantColorGenerator", parameters: [
            kCIInputColorKey: CIColor(cgColor: stroke.color.cgColor)
        ]), let colorImg = colorGen.outputImage else { return }

        let eroded = silhouette.applyingFilter("CIMorphologyMinimum", parameters: [
            kCIInputRadiusKey: stroke.size
        ])

        // Inside stroke = original alpha minus eroded alpha
        let strokeArea = silhouette.applyingFilter("CISubtractBlendMode", parameters: [
            kCIInputBackgroundImageKey: eroded
        ])

        let maskedStroke = colorImg.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: strokeArea,
            kCIInputBackgroundImageKey: CIImage.empty()
        ]).cropped(to: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))

        context.saveGState()
        context.setAlpha(stroke.opacity)
        context.setBlendMode(stroke.blendMode.cgMode)
        if let cgStroke = ciContext.createCGImage(maskedStroke, from: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)) {
            context.draw(cgStroke, in: contentRect)
        }
        context.restoreGState()
    }
}
