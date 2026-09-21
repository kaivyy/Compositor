import Foundation
import CoreGraphics

nonisolated enum StrokePosition: String, Codable, Hashable, CaseIterable, Sendable {
    case outside = "Outside"
    case inside = "Inside"
    case center = "Center"
}

nonisolated struct StrokeEffect: Codable, Hashable, Equatable, Sendable {
    var isEnabled: Bool = true
    var size: CGFloat = 3
    var position: StrokePosition = .outside
    var color: PaletteColor = .black
    var opacity: Double = 1.0
    var blendMode: LayerBlendMode = .normal

    init(isEnabled: Bool = true, size: CGFloat = 3, position: StrokePosition = .outside,
         color: PaletteColor = .black, opacity: Double = 1.0, blendMode: LayerBlendMode = .normal) {
        self.isEnabled = isEnabled
        self.size = size
        self.position = position
        self.color = color
        self.opacity = opacity
        self.blendMode = blendMode
    }
}

nonisolated struct OuterGlowEffect: Codable, Hashable, Equatable, Sendable {
    var isEnabled: Bool = true
    var color: PaletteColor = PaletteColor(red: 0, green: 0.94, blue: 1) // Neon Cyan
    var opacity: Double = 0.8
    var blendMode: LayerBlendMode = .screen
    var size: CGFloat = 20
    var spread: Double = 0.1

    init(isEnabled: Bool = true, color: PaletteColor = PaletteColor(red: 0, green: 0.94, blue: 1),
         opacity: Double = 0.8, blendMode: LayerBlendMode = .screen, size: CGFloat = 20, spread: Double = 0.1) {
        self.isEnabled = isEnabled
        self.color = color
        self.opacity = opacity
        self.blendMode = blendMode
        self.size = size
        self.spread = spread
    }
}

nonisolated struct DropShadowEffect: Codable, Hashable, Equatable, Sendable {
    var isEnabled: Bool = true
    var color: PaletteColor = .black
    var opacity: Double = 0.75
    var blendMode: LayerBlendMode = .multiply
    var angle: CGFloat = 90
    var distance: CGFloat = 8
    var size: CGFloat = 12
    var spread: Double = 0.0

    init(isEnabled: Bool = true, color: PaletteColor = .black, opacity: Double = 0.75,
         blendMode: LayerBlendMode = .multiply, angle: CGFloat = 90, distance: CGFloat = 8,
         size: CGFloat = 12, spread: Double = 0.0) {
        self.isEnabled = isEnabled
        self.color = color
        self.opacity = opacity
        self.blendMode = blendMode
        self.angle = angle
        self.distance = distance
        self.size = size
        self.spread = spread
    }
}

nonisolated struct ColorOverlayEffect: Codable, Hashable, Equatable, Sendable {
    var isEnabled: Bool = true
    var color: PaletteColor = PaletteColor(red: 1, green: 0, blue: 0)
    var opacity: Double = 1.0
    var blendMode: LayerBlendMode = .normal

    init(isEnabled: Bool = true, color: PaletteColor = PaletteColor(red: 1, green: 0, blue: 0), opacity: Double = 1.0, blendMode: LayerBlendMode = .normal) {
        self.isEnabled = isEnabled
        self.color = color
        self.opacity = opacity
        self.blendMode = blendMode
    }
}

/// A non-destructive, reusable collection of layer effects attached to an ImageLayer.
nonisolated struct LayerStyles: Codable, Hashable, Equatable, Sendable {
    var isEnabled: Bool = true
    var stroke: StrokeEffect? = nil
    var outerGlow: OuterGlowEffect? = nil
    var dropShadow: DropShadowEffect? = nil
    var colorOverlay: ColorOverlayEffect? = nil

    init(isEnabled: Bool = true,
         stroke: StrokeEffect? = nil,
         outerGlow: OuterGlowEffect? = nil,
         dropShadow: DropShadowEffect? = nil,
         colorOverlay: ColorOverlayEffect? = nil) {
        self.isEnabled = isEnabled
        self.stroke = stroke
        self.outerGlow = outerGlow
        self.dropShadow = dropShadow
        self.colorOverlay = colorOverlay
    }

    var hasActiveEffects: Bool {
        guard isEnabled else { return false }
        return (stroke?.isEnabled == true && (stroke?.size ?? 0) > 0)
            || (outerGlow?.isEnabled == true && (outerGlow?.size ?? 0) > 0)
            || (dropShadow?.isEnabled == true && ((dropShadow?.size ?? 0) > 0 || (dropShadow?.distance ?? 0) > 0))
            || (colorOverlay?.isEnabled == true && (colorOverlay?.opacity ?? 0) > 0)
    }

    /// Additional margin in layer pixels required so outer effects (Stroke outside/center, Outer Glow, Drop Shadow)
    /// render completely without clipping at the original layer bounds.
    var contentPadding: CGFloat {
        guard hasActiveEffects else { return 0 }
        var padding: CGFloat = 0
        if let stroke, stroke.isEnabled {
            let strokeMargin: CGFloat = stroke.position == .outside ? stroke.size : (stroke.position == .center ? stroke.size / 2 : 0)
            padding = max(padding, strokeMargin)
        }
        if let glow = outerGlow, glow.isEnabled {
            padding = max(padding, glow.size * 2)
        }
        if let shadow = dropShadow, shadow.isEnabled {
            padding = max(padding, shadow.distance + shadow.size * 2)
        }
        return ceil(padding)
    }
}
