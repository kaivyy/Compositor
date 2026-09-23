import AppKit
import Testing
@testable import Compositor

@MainActor
struct PenToolTests {
    private func makeSession() -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200, emptyLayer: true)
        session.selectTool(.pen)
        session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
        session.penStrokeWidth = 2
        return session
    }

    @Test func activatingPenToolCreatesTransientStateOnly() {
        let session = makeSession()
        let count = session.history.undoCount
        let layerCount = session.document?.layers.count ?? 0

        #expect(session.tool == .pen)
        #expect(session.penDraft == nil)
        #expect(session.history.undoCount == count)
        #expect(session.document?.layers.count == layerCount)
    }

    @Test func firstClickCreatesOneAnchorWithoutCreatingDocumentLayer() {
        let session = makeSession()
        let initialLayers = session.document?.layers.count ?? 0
        let count = session.history.undoCount

        session.beginPen(at: CGPoint(x: 20, y: 30))
        session.endPenDrag()

        #expect(session.penDraft != nil)
        #expect(session.penDraft?.subpath.points.count == 1)
        #expect(session.penDraft?.subpath.points[0].anchor == CGPoint(x: 20, y: 30))
        #expect(session.penDraft?.subpath.points[0].previousControl == nil)
        #expect(session.penDraft?.subpath.points[0].nextControl == nil)
        #expect(session.document?.layers.count == initialLayers)
        #expect(session.history.undoCount == count)
    }

    @Test func secondClickCreatesAStraightSegment() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 30))
        session.endPenDrag()

        session.beginPen(at: CGPoint(x: 60, y: 70))
        session.endPenDrag()

        guard let draft = session.penDraft else {
            Issue.record("penDraft should exist")
            return
        }

        #expect(draft.subpath.points.count == 2)
        #expect(draft.subpath.points[0].anchor == CGPoint(x: 20, y: 30))
        #expect(draft.subpath.points[0].nextControl == nil)
        #expect(draft.subpath.points[1].anchor == CGPoint(x: 60, y: 70))
        #expect(draft.subpath.points[1].previousControl == nil)
        #expect(draft.subpath.points[1].nextControl == nil)
    }

    @Test func multipleClicksCreateMultipleAnchors() {
        let session = makeSession()
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 40), CGPoint(x: 60, y: 20), CGPoint(x: 90, y: 80)]

        for p in points {
            session.beginPen(at: p)
            session.endPenDrag()
        }

        guard let draft = session.penDraft else {
            Issue.record("penDraft should exist")
            return
        }

        #expect(draft.subpath.points.count == 4)
        for (i, p) in points.enumerated() {
            #expect(draft.subpath.points[i].anchor == p)
        }
    }

    @Test func clickDragCreatesSymmetricalBezierHandles() {
        let session = makeSession()
        let anchor = CGPoint(x: 50, y: 50)
        let dragTarget = CGPoint(x: 70, y: 60)

        session.beginPen(at: anchor)
        session.dragPen(to: dragTarget)
        session.endPenDrag()

        guard let draft = session.penDraft, draft.subpath.points.count == 1 else {
            Issue.record("penDraft should have 1 point")
            return
        }

        let pt = draft.subpath.points[0]
        #expect(pt.anchor == anchor)

        // D = dragTarget - anchor = (20, 10)
        // nextControl = P + D = (70, 60)
        // previousControl = P - D = (30, 40)
        #expect(pt.nextControl == CGPoint(x: 70, y: 60))
        #expect(pt.previousControl == CGPoint(x: 30, y: 40))
    }

    @Test func bezierHandlesAreStoredInDocumentCoordinates() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 100, y: 100))
        session.dragPen(to: CGPoint(x: 120, y: 110))
        session.endPenDrag()

        guard let draft = session.penDraft, let pt = draft.subpath.points.first else {
            Issue.record("Expected point")
            return
        }

        #expect(pt.anchor.x == 100 && pt.anchor.y == 100)
        #expect(pt.nextControl?.x == 120 && pt.nextControl?.y == 110)
        #expect(pt.previousControl?.x == 80 && pt.previousControl?.y == 90)
    }

    @Test func livePreviewDoesNotMutateCanvasDocument() {
        let session = makeSession()
        let initialLayers = session.document?.layers.count ?? 0
        let historyCount = session.history.undoCount

        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        session.movePen(to: CGPoint(x: 70, y: 80))

        #expect(session.penDraft?.pointer == CGPoint(x: 70, y: 80))
        #expect(session.document?.layers.count == initialLayers)
        #expect(session.history.undoCount == historyCount)

        session.movePen(to: CGPoint(x: 90, y: 100))
        #expect(session.penDraft?.pointer == CGPoint(x: 90, y: 100))
        #expect(session.document?.layers.count == initialLayers)
        #expect(session.history.undoCount == historyCount)
    }

    @Test func clickingTheFirstAnchorClosesThePathWithoutDuplicate() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 50))
        session.endPenDrag()

        #expect(session.penDraft?.subpath.points.count == 3)

        // Close path directly
        session.closePen()

        #expect(session.penDraft == nil)
        #expect(session.document?.layers.count == 2) // Initial blank layer + committed vector layer

        guard let layer = session.activeLayer, let vector = layer.vector else {
            Issue.record("Committed layer must have vector model")
            return
        }

        #expect(vector.subpaths.count == 1)
        #expect(vector.subpaths[0].isClosed == true)
        #expect(vector.subpaths[0].points.count == 3, "Closing must not duplicate the initial anchor")
        #expect(vector.fill != nil && vector.fill?.isEnabled == true)
        #expect(vector.stroke != nil && vector.stroke?.isEnabled == true)
    }

    @Test func enterCommitsAnOpenPath() {
        let session = makeSession()
        let count = session.history.undoCount

        session.beginPen(at: CGPoint(x: 20, y: 30))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 80, y: 50))
        session.endPenDrag()

        session.finishPen() // Enter / Return

        #expect(session.penDraft == nil)
        #expect(session.document?.layers.count == 2)
        #expect(session.history.undoCount == count + 1)

        guard let layer = session.activeLayer, let vector = layer.vector else {
            Issue.record("Layer should have vector model")
            return
        }

        #expect(vector.subpaths.count == 1)
        #expect(vector.subpaths[0].isClosed == false)
        #expect(vector.subpaths[0].points.count == 2)
        #expect(vector.stroke != nil)
        #expect(layer.asset != nil)
    }

    @Test func escapeCancelsWithoutChangingDocumentHistory() {
        let session = makeSession()
        let count = session.history.undoCount
        let layerCount = session.document?.layers.count ?? 0

        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()

        #expect(session.penDraft != nil)
        session.cancelPen() // Escape

        #expect(session.penDraft == nil)
        #expect(session.history.undoCount == count)
        #expect(session.document?.layers.count == layerCount)
    }

    @Test func emptyEnterDoesNothing() {
        let session = makeSession()
        let count = session.history.undoCount
        let layerCount = session.document?.layers.count ?? 0

        // Enter with no draft
        session.finishPen()
        #expect(session.history.undoCount == count)
        #expect(session.document?.layers.count == layerCount)

        // Enter with 1 anchor only (cannot form valid open path)
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.finishPen()

        #expect(session.penDraft == nil)
        #expect(session.history.undoCount == count)
        #expect(session.document?.layers.count == layerCount)
    }

    @Test func committedLayerContainsExpectedVectorModelAndRenderedAsset() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.dragPen(to: CGPoint(x: 30, y: 25))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 80, y: 40))
        session.dragPen(to: CGPoint(x: 90, y: 45))
        session.endPenDrag()

        session.finishPen()

        guard let layer = session.activeLayer, let vector = layer.vector, let asset = layer.asset else {
            Issue.record("Layer must have vector and asset")
            return
        }

        #expect(layer.name == "Vector 1")
        #expect(vector.subpaths.count == 1)
        #expect(vector.subpaths[0].points.count == 2)
        #expect(vector.stroke?.color == session.foregroundColor)
        #expect(vector.stroke?.width == 2)
        #expect(asset.image.width > 0 && asset.image.height > 0)
        #expect(layer.transform.size.width >= 1 && layer.transform.size.height >= 1)
    }

    @Test func undoRemovesAndRestoresCommittedVectorLayerThroughHistory() {
        let session = makeSession()
        let initialLayers = session.document?.layers.count ?? 0

        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()
        session.finishPen()

        #expect(session.document?.layers.count == initialLayers + 1)
        let vectorModel = session.activeLayer?.vector

        // Undo
        session.undo()
        #expect(session.document?.layers.count == initialLayers)
        #expect(session.activeLayer?.vector == nil)

        // Redo
        session.redo()
        #expect(session.document?.layers.count == initialLayers + 1)
        #expect(session.activeLayer?.vector == vectorModel)
    }

    @Test func zoomIndependencePreservesLogicalCoordinates() {
        let session = makeSession()
        let docSize = CGSize(width: 200, height: 200)

        // Test at 50% zoom
        session.zoom(to: 0.5)
        let docPoint1 = CGPoint(x: 40, y: 60)
        let viewPoint1 = session.viewport.viewPoint(from: docPoint1, documentSize: docSize)
        let backToDoc1 = session.viewport.documentPoint(from: viewPoint1, documentSize: docSize)
        #expect(abs(backToDoc1.x - docPoint1.x) < 0.001)
        #expect(abs(backToDoc1.y - docPoint1.y) < 0.001)

        // Test at 100% zoom
        session.zoom(to: 1.0)
        let viewPoint2 = session.viewport.viewPoint(from: docPoint1, documentSize: docSize)
        let backToDoc2 = session.viewport.documentPoint(from: viewPoint2, documentSize: docSize)
        #expect(abs(backToDoc2.x - docPoint1.x) < 0.001)
        #expect(abs(backToDoc2.y - docPoint1.y) < 0.001)

        // Test at 200% zoom
        session.zoom(to: 2.0)
        let viewPoint3 = session.viewport.viewPoint(from: docPoint1, documentSize: docSize)
        let backToDoc3 = session.viewport.documentPoint(from: viewPoint3, documentSize: docSize)
        #expect(abs(backToDoc3.x - docPoint1.x) < 0.001)
        #expect(abs(backToDoc3.y - docPoint1.y) < 0.001)
    }

    @Test func controlPointsOutsideAnchorBoundsExpandLayerBoundsSafely() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 100, y: 100))
        session.dragPen(to: CGPoint(x: 150, y: 100))
        session.endPenDrag()

        session.beginPen(at: CGPoint(x: 100, y: 200))
        session.endPenDrag()

        session.finishPen()

        guard let layer = session.activeLayer, let vector = layer.vector, let asset = layer.asset else {
            Issue.record("Layer must have vector and asset")
            return
        }

        // Both anchors are at X=100, but the Bézier control point pulls the curve outward to X ≈ 122.22.
        // The layer bounds must expand beyond the anchors to safely contain the curve extrema plus stroke padding.
        #expect(layer.transform.origin.x <= 100 - 3)
        #expect(layer.transform.origin.x + layer.transform.size.width >= 122.22 + 3)
        #expect(asset.image.width == Int(layer.transform.size.width))
        #expect(asset.image.height == Int(layer.transform.size.height))

        // Reconstituting document coordinates from layer-local coordinates + origin matches original
        let origin = layer.transform.origin
        let pt0 = vector.subpaths[0].points[0]
        #expect(pt0.anchor.x + origin.x == 100)
        #expect(pt0.anchor.y + origin.y == 100)
        #expect((pt0.previousControl?.x ?? 0) + origin.x == 50)
        #expect((pt0.previousControl?.y ?? 0) + origin.y == 100)
        #expect((pt0.nextControl?.x ?? 0) + origin.x == 150)
        #expect((pt0.nextControl?.y ?? 0) + origin.y == 100)

        let pt1 = vector.subpaths[0].points[1]
        #expect(pt1.anchor.x + origin.x == 100)
        #expect(pt1.anchor.y + origin.y == 200)
    }

    @Test func movingLayerPreservesLayerLocalVectorModel() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()
        session.finishPen()

        guard let layerIndex = session.document?.layers.firstIndex(where: { $0.id == session.activeLayerID }) else {
            Issue.record("Layer expected")
            return
        }

        let originalVector = session.document!.layers[layerIndex].vector
        #expect(originalVector != nil)

        // Simulate moving layer with Move tool (mutating layer.transform.origin)
        session.document!.layers[layerIndex].transform.origin.x += 40
        session.document!.layers[layerIndex].transform.origin.y += 30

        #expect(session.document!.layers[layerIndex].vector == originalVector)
        let newOrigin = session.document!.layers[layerIndex].transform.origin
        let localPt = session.document!.layers[layerIndex].vector!.subpaths[0].points[0].anchor
        #expect(localPt.x + newOrigin.x == 60)
        #expect(localPt.y + newOrigin.y == 50)
    }

    @Test func projectClearCancelsActivePenDraft() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        #expect(session.penDraft != nil)

        session.clearProject()
        #expect(session.penDraft == nil)
    }

    @Test func penDraftUndoRemovesLastAnchorAcrossThreeTwoOneSequence() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()

        guard let draft3 = session.penDraft else {
            Issue.record("penDraft expected")
            return
        }
        #expect(draft3.subpath.points.count == 3)
        #expect(session.canUndo)

        // 1. Undo third anchor -> 2 anchors remain
        session.undo()
        guard let draft2 = session.penDraft else {
            Issue.record("penDraft expected with 2 points")
            return
        }
        #expect(draft2.subpath.points.count == 2)
        #expect(draft2.activeAnchorIndex == 1)
        #expect(draft2.subpath.points[0].anchor == CGPoint(x: 10, y: 10))
        #expect(draft2.subpath.points[1].anchor == CGPoint(x: 30, y: 30))
        #expect(session.tool == .pen)

        // 2. Undo second anchor -> 1 anchor remains
        session.undo()
        guard let draft1 = session.penDraft else {
            Issue.record("penDraft expected with 1 point")
            return
        }
        #expect(draft1.subpath.points.count == 1)
        #expect(draft1.activeAnchorIndex == 0)
        #expect(draft1.subpath.points[0].anchor == CGPoint(x: 10, y: 10))
        #expect(session.tool == .pen)

        // 3. Undo first anchor -> cancels draft
        session.undo()
        #expect(session.penDraft == nil)
        #expect(session.tool == .pen)
    }

    @Test func penDraftUndoDoesNotMutateOrConsumeDocumentHistory() {
        let session = makeSession()
        session.addBlankLayer()
        let initialUndoCount = session.history.undoCount
        let initialDoc = session.document

        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()

        // 3 anchors active
        session.undo()
        #expect(session.history.undoCount == initialUndoCount)
        #expect(session.document == initialDoc)

        session.undo()
        #expect(session.history.undoCount == initialUndoCount)
        #expect(session.document == initialDoc)

        session.undo()
        #expect(session.history.undoCount == initialUndoCount)
        #expect(session.document == initialDoc)
        #expect(session.penDraft == nil)

        // With penDraft canceled, the next Undo operates on committed document history
        session.undo()
        #expect(session.history.undoCount == initialUndoCount - 1)
    }

    @Test func cmdShiftZRedoDuringPenDraftIsNoOp() {
        let session = makeSession()
        session.addBlankLayer()
        session.addBlankLayer()
        session.undo()
        #expect(session.canRedo)
        let redoName = session.history.redoName

        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()

        #expect(session.penDraft != nil)
        #expect(!session.canRedo)

        let layerCount = session.document?.layers.count ?? 0
        session.redo()

        // Redo was a no-op: document history was not redone
        #expect(session.document?.layers.count == layerCount)
        #expect(session.penDraft != nil)
        #expect(session.penDraft?.subpath.points.count == 2)

        // Cancel pen draft
        session.cancelPen()
        #expect(session.canRedo)
        #expect(session.history.redoName == redoName)
        session.redo()
        #expect(session.document?.layers.count == layerCount + 1)
    }

    @Test func canContinueDrawingAfterUndoingAnAnchor() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()

        // Undo 3rd anchor
        session.undo()
        #expect(session.penDraft?.subpath.points.count == 2)

        // Continue drawing: add a new 3rd anchor at (70, 70)
        session.beginPen(at: CGPoint(x: 70, y: 70))
        session.endPenDrag()
        #expect(session.penDraft?.subpath.points.count == 3)
        #expect(session.penDraft?.subpath.points[2].anchor == CGPoint(x: 70, y: 70))

        // Finish pen path
        session.finishPen()
        #expect(session.penDraft == nil)

        guard let layer = session.activeLayer, let vector = layer.vector else {
            Issue.record("Layer with vector expected")
            return
        }
        #expect(vector.subpaths[0].points.count == 3)
    }

    @Test func afterPenCommitNormalUndoRedoResumes() {
        let session = makeSession()
        let initialLayers = session.document?.layers.count ?? 0
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 40))
        session.endPenDrag()
        session.finishPen()

        #expect(session.penDraft == nil)
        #expect((session.document?.layers.count ?? 0) == initialLayers + 1)

        // Undo committed vector layer
        session.undo()
        #expect((session.document?.layers.count ?? 0) == initialLayers)

        // Redo committed vector layer
        session.redo()
        #expect((session.document?.layers.count ?? 0) == initialLayers + 1)
        #expect(session.activeLayer?.vector != nil)
    }

    @Test func historyIsolationBetweenCommittedVectorsAndPenDraft() {
        let session = makeSession()

        // Commit Vector A
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.finishPen()
        guard let vectorAID = session.activeLayerID else { Issue.record("Vector A ID"); return }

        // Commit Vector B
        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 40))
        session.endPenDrag()
        session.finishPen()
        guard let vectorBID = session.activeLayerID else { Issue.record("Vector B ID"); return }

        // Begin third Pen draft with 3 anchors
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 70, y: 70))
        session.endPenDrag()

        // 3 Undos must only affect the third draft
        session.undo()
        session.undo()
        session.undo()
        #expect(session.penDraft == nil)

        // Both Vector A and Vector B are preserved
        let layerIDs = session.document?.layers.map(\.id) ?? []
        #expect(layerIDs.contains(vectorAID))
        #expect(layerIDs.contains(vectorBID))

        // Next Undo removes Vector B
        session.undo()
        let layerIDsAfterUndoB = session.document?.layers.map(\.id) ?? []
        #expect(layerIDsAfterUndoB.contains(vectorAID))
        #expect(!layerIDsAfterUndoB.contains(vectorBID))

        // Next Undo removes Vector A
        session.undo()
        let layerIDsAfterUndoA = session.document?.layers.map(\.id) ?? []
        #expect(!layerIDsAfterUndoA.contains(vectorAID))
    }
}
