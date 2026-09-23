import AppKit

/// Transient in-progress drawing state for the Pen tool.
/// Held purely in memory during an active drawing gesture; not saved to CanvasDocument or DocumentHistory.
struct PenDraft: Equatable, Sendable {
    var subpath: VectorSubpath
    var activeAnchorIndex: Int?
    var isDragging: Bool
    var pointer: CGPoint?

    init(subpath: VectorSubpath = VectorSubpath(), activeAnchorIndex: Int? = nil, isDragging: Bool = false, pointer: CGPoint? = nil) {
        self.subpath = subpath
        self.activeAnchorIndex = activeAnchorIndex
        self.isDragging = isDragging
        self.pointer = pointer
    }

    var isClosed: Bool { subpath.isClosed }
}

extension EditorSession {
    /// Begins or extends a pen path at `point` in document coordinates.
    func beginPen(at point: CGPoint) {
        guard tool == .pen, canEditLayers, point.x.isFinite, point.y.isFinite, document != nil else { return }

        if var draft = penDraft {
            // Append a new anchor point
            let newPoint = VectorPoint(anchor: point)
            draft.subpath.points.append(newPoint)
            draft.activeAnchorIndex = draft.subpath.points.count - 1
            draft.isDragging = true
            draft.pointer = point
            penDraft = draft
        } else {
            // Start a new draft
            var subpath = VectorSubpath()
            subpath.points.append(VectorPoint(anchor: point))
            penDraft = PenDraft(subpath: subpath, activeAnchorIndex: 0, isDragging: true, pointer: point)
        }
    }

    /// Drags symmetric Bézier handles from the active anchor to `point` in document coordinates.
    func dragPen(to point: CGPoint) {
        guard var draft = penDraft, draft.isDragging,
              let index = draft.activeAnchorIndex,
              draft.subpath.points.indices.contains(index),
              point.x.isFinite, point.y.isFinite else { return }

        let P = draft.subpath.points[index].anchor
        let dx = point.x - P.x
        let dy = point.y - P.y

        if hypot(dx, dy) >= 1 {
            draft.subpath.points[index].nextControl = CGPoint(x: P.x + dx, y: P.y + dy)
            draft.subpath.points[index].previousControl = CGPoint(x: P.x - dx, y: P.y - dy)
        } else {
            draft.subpath.points[index].nextControl = nil
            draft.subpath.points[index].previousControl = nil
        }

        draft.pointer = point
        penDraft = draft
    }

    /// Ends dragging handles on the active anchor.
    func endPenDrag() {
        guard var draft = penDraft else { return }
        draft.isDragging = false
        penDraft = draft
    }

    /// Updates the live preview pointer position in document coordinates.
    func movePen(to point: CGPoint?) {
        guard var draft = penDraft else { return }
        guard let point else {
            draft.pointer = nil
            penDraft = draft
            return
        }
        guard point.x.isFinite, point.y.isFinite else { return }
        draft.pointer = point
        penDraft = draft
    }

    /// Closes the current subpath and commits the vector layer.
    func closePen() {
        guard var draft = penDraft, draft.subpath.points.count >= 2 else { return }
        draft.subpath.isClosed = true
        penDraft = nil
        commitPen(subpath: draft.subpath)
    }

    /// Finishes an open path (e.g. via Enter/Return) and commits if valid.
    func finishPen() {
        guard let draft = penDraft else { return }
        penDraft = nil
        if draft.subpath.points.count >= 2 || draft.subpath.isClosed {
            commitPen(subpath: draft.subpath)
        }
    }

    /// Cancels the in-progress Pen gesture without committing any layer or modifying history.
    func cancelPen() {
        if penDraft != nil {
            penDraft = nil
        }
    }

    /// Commits a completed VectorSubpath into a new ImageLayer with canonical VectorModel and derived raster cache.
    func commitPen(subpath: VectorSubpath) {
        guard canEditLayers, document != nil, subpath.isValid, !subpath.points.isEmpty else { return }

        let strokeWidth = CGFloat(penStrokeWidth)
        let stroke = VectorStrokeStyle(color: foregroundColor, width: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10, isEnabled: true)
        let fill = subpath.isClosed ? VectorFillStyle(color: foregroundColor, fillRule: .nonZero, isEnabled: true) : nil

        // Compute document-space bounding box of the subpath
        let modelForBounds = VectorModel(subpaths: [subpath], fill: fill, stroke: stroke)
        let pathForBounds = VectorBridge.cgPath(from: modelForBounds)
        let rawBounds = pathForBounds.boundingBoxOfPath

        guard rawBounds.origin.x.isFinite, rawBounds.origin.y.isFinite,
              rawBounds.width.isFinite, rawBounds.height.isFinite else { return }

        let padding = max(2, ceil(strokeWidth / 2) + 2)
        let docRect = rawBounds.insetBy(dx: -padding, dy: -padding).integral
        let layerOrigin = docRect.origin
        let layerSize = CGSize(width: max(1, docRect.width), height: max(1, docRect.height))

        guard Int(layerSize.width) * Int(layerSize.height) <= Self.maxShapePixels else {
            brushError = "That vector path is too large. A vector path can cover up to 100 megapixels."
            return
        }

        // Translate subpath into layer-local coordinates
        let localSubpath = subpath.translated(by: CGPoint(x: -layerOrigin.x, y: -layerOrigin.y))
        let localModel = VectorModel(subpaths: [localSubpath], fill: fill, stroke: stroke)

        do {
            let image = try VectorRenderer.render(localModel, in: layerSize)
            addPixelLayer(image, at: layerOrigin, name: nextVectorName(), editName: "New Vector Layer",
                          dropsSelection: false, vector: localModel)
        } catch {
            brushError = error.localizedDescription
        }
    }

    func nextVectorName() -> String {
        let names = Set(document?.layers.map(\.name) ?? [])
        var number = 1
        while names.contains("Vector \(number)") { number += 1 }
        return "Vector \(number)"
    }
}

extension VectorSubpath {
    /// Translates all anchor and control points in this subpath by delta.
    func translated(by delta: CGPoint) -> VectorSubpath {
        var result = self
        result.points = points.map { pt in
            let anchor = CGPoint(x: pt.anchor.x + delta.x, y: pt.anchor.y + delta.y)
            let prev = pt.previousControl.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            let next = pt.nextControl.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            return VectorPoint(anchor: anchor, previousControl: prev, nextControl: next)
        }
        return result
    }
}
