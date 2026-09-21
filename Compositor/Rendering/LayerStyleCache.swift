import CoreGraphics
import Foundation

/// Fast in-memory cache for rendered layer styles, keyed by layer ID, image pointer, and style value.
final class LayerStyleCache: @unchecked Sendable {
    static let shared = LayerStyleCache()

    private struct Key: Hashable {
        let layerID: UUID
        let imagePointer: ObjectIdentifier
        let styles: LayerStyles
    }

    private var storage: [Key: (image: CGImage, padding: CGFloat)] = [:]
    private let lock = NSLock()

    func styledImage(for layer: ImageLayer, baseImage: CGImage? = nil) -> (image: CGImage, padding: CGFloat)? {
        guard let styles = layer.styles, styles.hasActiveEffects,
              let image = baseImage ?? layer.asset?.image else {
            return nil
        }
        let key = Key(layerID: layer.id, imagePointer: ObjectIdentifier(image), styles: styles)
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] {
            return cached
        }
        if let rendered = LayerStyleRenderer.render(image: image, styles: styles) {
            // Keep cache bounded to 50 active styled layers
            if storage.count > 50 {
                storage.removeAll(keepingCapacity: true)
            }
            storage[key] = rendered
            return rendered
        }
        return nil
    }

    func invalidate(layerID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        storage = storage.filter { $0.key.layerID != layerID }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
