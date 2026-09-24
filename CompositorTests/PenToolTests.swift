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
        #expect(vector.fill == nil, "Pen closed path must be transparent by default")
        #expect(vector.stroke == nil, "Pen path must have no stroke by default")
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
        #expect(vector.stroke == nil, "Open Pen path has no stroke by default")
        #expect(vector.fill == nil, "Open Pen path has no fill by default")
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
        #expect(vector.stroke == nil, "Pen path has no stroke by default")
        #expect(vector.fill == nil, "Pen path has no fill by default")
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

    // MARK: - Phase 2B-6: Path Continuation & Endpoint Hit-Testing

    @Test func hitTestPenEndpointFindsEndpointsOnOpenVectorLayer() {
        let session = makeSession()
        // Draw an open path: (20, 20) -> (60, 60)
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()
        session.finishPen()

        guard let layer = session.activeLayer, layer.vector != nil else {
            Issue.record("Committed layer expected")
            return
        }

        let docSize = session.document!.size
        let firstDoc = CGPoint(x: 20, y: 20)
        let lastDoc = CGPoint(x: 60, y: 60)
        let firstView = session.viewport.viewPoint(from: firstDoc, documentSize: docSize)
        let lastView = session.viewport.viewPoint(from: lastDoc, documentSize: docSize)

        // Hit first endpoint
        let hitFirst = session.hitTestPenEndpoint(at: firstView, tolerance: 10)
        #expect(hitFirst != nil)
        #expect(hitFirst?.layerID == layer.id)
        #expect(hitFirst?.isLast == false)
        #expect(abs((hitFirst?.point.x ?? 0) - firstDoc.x) < 0.001)
        #expect(abs((hitFirst?.point.y ?? 0) - firstDoc.y) < 0.001)

        // Hit last endpoint
        let hitLast = session.hitTestPenEndpoint(at: lastView, tolerance: 10)
        #expect(hitLast != nil)
        #expect(hitLast?.layerID == layer.id)
        #expect(hitLast?.isLast == true)
        #expect(abs((hitLast?.point.x ?? 0) - lastDoc.x) < 0.001)
        #expect(abs((hitLast?.point.y ?? 0) - lastDoc.y) < 0.001)

        // Miss (far away)
        let farView = session.viewport.viewPoint(from: CGPoint(x: 150, y: 150), documentSize: docSize)
        let hitFar = session.hitTestPenEndpoint(at: farView, tolerance: 10)
        #expect(hitFar == nil)
    }

    @Test func hitTestPenEndpointIgnoresClosedPathsAndHiddenLayers() {
        let session = makeSession()
        // Draw a closed path
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 50))
        session.endPenDrag()
        session.closePen()

        let docSize = session.document!.size
        let viewPt = session.viewport.viewPoint(from: CGPoint(x: 20, y: 20), documentSize: docSize)
        #expect(session.hitTestPenEndpoint(at: viewPt, tolerance: 10) == nil)

        // Hidden layer test: Draw an open path, hide the layer
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        session.finishPen()

        guard let layerID = session.activeLayerID,
              let idx = session.document?.layers.firstIndex(where: { $0.id == layerID }) else {
            Issue.record("Layer expected")
            return
        }
        session.document?.layers[idx].isVisible = false

        let hiddenViewPt = session.viewport.viewPoint(from: CGPoint(x: 10, y: 10), documentSize: docSize)
        #expect(session.hitTestPenEndpoint(at: hiddenViewPt, tolerance: 10) == nil)
    }

    @Test func beginPenContinuationResumesFromLastEndpoint() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()
        session.finishPen()

        guard session.activeLayer != nil, let layerID = session.activeLayerID else {
            Issue.record("Initial layer expected")
            return
        }
        let initialLayerCount = session.document?.layers.count ?? 0

        let docSize = session.document!.size
        let lastView = session.viewport.viewPoint(from: CGPoint(x: 60, y: 60), documentSize: docSize)
        guard let hit = session.hitTestPenEndpoint(at: lastView, tolerance: 10) else {
            Issue.record("Hit expected")
            return
        }

        session.beginPenContinuation(from: hit)

        #expect(session.penDraft != nil)
        #expect(session.penDraft?.continuingLayerID == layerID)
        #expect(session.penDraft?.continuingReversed == false)
        #expect(session.penDraft?.subpath.points.count == 2)

        // Add 3rd point and finish
        session.beginPen(at: CGPoint(x: 100, y: 60))
        session.endPenDrag()
        session.finishPen()

        #expect(session.penDraft == nil)
        #expect(session.document?.layers.count == initialLayerCount) // In-place replacement
        guard let continuedLayer = session.document?.layers.first(where: { $0.id == layerID }),
              let vector = continuedLayer.vector else {
            Issue.record("Continued layer vector expected")
            return
        }
        #expect(vector.subpaths[0].points.count == 3)
    }

    @Test func beginPenContinuationFromFirstEndpointReversesSubpath() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()
        session.finishPen()

        guard let layerID = session.activeLayerID else {
            Issue.record("Initial layer expected")
            return
        }
        let initialLayerCount = session.document?.layers.count ?? 0

        let docSize = session.document!.size
        let firstView = session.viewport.viewPoint(from: CGPoint(x: 20, y: 20), documentSize: docSize)
        guard let hit = session.hitTestPenEndpoint(at: firstView, tolerance: 10) else {
            Issue.record("Hit expected")
            return
        }

        #expect(hit.isLast == false)
        session.beginPenContinuation(from: hit)

        #expect(session.penDraft != nil)
        #expect(session.penDraft?.continuingLayerID == layerID)
        #expect(session.penDraft?.continuingReversed == true)
        // Because reversed, point 0 is original (60, 60), point 1 is original (20, 20)
        let draftPoints = session.penDraft!.subpath.points
        #expect(abs(draftPoints[0].anchor.x - 60) < 0.001)
        #expect(abs(draftPoints[1].anchor.x - 20) < 0.001)

        // Extend from the original start point
        session.beginPen(at: CGPoint(x: 10, y: 40))
        session.endPenDrag()
        session.finishPen()

        #expect(session.document?.layers.count == initialLayerCount)
        guard let continuedLayer = session.document?.layers.first(where: { $0.id == layerID }),
              let vector = continuedLayer.vector else {
            Issue.record("Continued layer vector expected")
            return
        }
        #expect(vector.subpaths[0].points.count == 3)
    }

    @Test func continuationPreservesStrokeSettings() {
        let session = makeSession()
        let subpath = VectorSubpath(points: [
            VectorPoint(anchor: CGPoint(x: 10, y: 10)),
            VectorPoint(anchor: CGPoint(x: 50, y: 50))
        ], isClosed: false)
        let stroke = VectorStrokeStyle(color: PaletteColor(red: 0, green: 0, blue: 1), width: 8)
        let model = VectorModel(subpaths: [subpath], fill: nil, stroke: stroke)
        let image = try! VectorRenderer.render(model, in: CGSize(width: 60, height: 60))
        session.addPixelLayer(image, at: .zero, name: "InitialVector", editName: "Add Vector", vector: model)

        guard let layerID = session.activeLayerID,
              let vectorBefore = session.activeLayer?.vector else {
            Issue.record("Vector expected")
            return
        }
        #expect(vectorBefore.stroke?.width == 8)

        // Change current tool settings to something else
        session.penStrokeWidth = 2
        session.foregroundColor = PaletteColor(red: 1, green: 1, blue: 0)

        // Continue the layer
        let docSize = session.document!.size
        let lastView = session.viewport.viewPoint(from: CGPoint(x: 50, y: 50), documentSize: docSize)
        guard let hit = session.hitTestPenEndpoint(at: lastView, tolerance: 10) else {
            Issue.record("Hit expected")
            return
        }
        session.beginPenContinuation(from: hit)
        session.beginPen(at: CGPoint(x: 90, y: 90))
        session.endPenDrag()
        session.finishPen()

        guard let vectorAfter = session.document?.layers.first(where: { $0.id == layerID })?.vector else {
            Issue.record("Vector after expected")
            return
        }
        // Should preserve original stroke width 8
        #expect(vectorAfter.stroke?.width == 8)
    }

    // MARK: - Phase 2B-7: Closed Vector Path Interaction, Selection & Hit Testing

    @Test func hitTestPenVectorLayerFindsInsideClosedPath() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 60))
        session.endPenDrag()
        session.closePen()

        guard let layerID = session.activeLayerID else {
            Issue.record("Committed layer expected")
            return
        }

        let docSize = session.document!.size
        // (40, 30) is inside the triangle (20,20)-(60,20)-(40,60)
        let insideView = session.viewport.viewPoint(from: CGPoint(x: 40, y: 30), documentSize: docSize)
        let hit = session.hitTestPenVectorLayer(at: insideView)
        #expect(hit != nil)
        #expect(hit?.layerID == layerID)
    }

    @Test func hitTestPenVectorLayerReturnsNilForOutsidePoint() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 60))
        session.endPenDrag()
        session.closePen()

        let docSize = session.document!.size
        // (150, 150) is well outside the triangle
        let outsideView = session.viewport.viewPoint(from: CGPoint(x: 150, y: 150), documentSize: docSize)
        let hit = session.hitTestPenVectorLayer(at: outsideView)
        #expect(hit == nil)
    }

    @Test func hitTestPenVectorLayerPrefersTopmostLayerWhenOverlapping() {
        let session = makeSession()
        // Bottom layer: (10, 10) to (100, 100)
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 100, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 100, y: 100))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 10, y: 100))
        session.endPenDrag()
        session.closePen()
        guard let bottomLayerID = session.activeLayerID else {
            Issue.record("Bottom layer expected")
            return
        }

        // Top layer: (20, 20) to (80, 80)
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 80, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 80, y: 80))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 20, y: 80))
        session.endPenDrag()
        session.closePen()
        guard let topLayerID = session.activeLayerID else {
            Issue.record("Top layer expected")
            return
        }

        #expect(bottomLayerID != topLayerID)

        let docSize = session.document!.size
        // (50, 50) is inside both shapes; topmost layer should win
        let centerView = session.viewport.viewPoint(from: CGPoint(x: 50, y: 50), documentSize: docSize)
        let hit = session.hitTestPenVectorLayer(at: centerView)
        #expect(hit?.layerID == topLayerID)
    }

    @Test func makeSelectionFromVectorCreatesDocumentSelectionForClosedPath() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 60))
        session.endPenDrag()
        session.closePen()

        guard let layerID = session.activeLayerID else {
            Issue.record("Committed layer expected")
            return
        }

        #expect(session.selection == nil)

        session.makeSelectionFromVector(layerID: layerID)

        #expect(session.selection != nil)
        #expect(session.selection?.isEmpty == false)

        let bounds = session.selection!.path.boundingBoxOfPath
        #expect(bounds.minX >= 19 && bounds.minX <= 21)
        #expect(bounds.maxX >= 59 && bounds.maxX <= 61)
        #expect(bounds.minY >= 19 && bounds.minY <= 21)
        #expect(bounds.maxY >= 59 && bounds.maxY <= 61)
    }

    @Test func makeSelectionFromVectorIgnoresOpenSubpaths() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()
        session.finishPen()

        guard let layerID = session.activeLayerID else {
            Issue.record("Committed layer expected")
            return
        }

        #expect(session.selection == nil)

        session.makeSelectionFromVector(layerID: layerID)

        // Open path should NOT create a selection
        #expect(session.selection == nil)
    }

    @Test func hitTestPenVectorLayerIgnoresHiddenLayers() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 60))
        session.endPenDrag()
        session.closePen()

        guard let layerIndex = session.document?.layers.firstIndex(where: { $0.id == session.activeLayerID }) else {
            Issue.record("Layer index expected")
            return
        }

        // Hide the layer
        session.document?.layers[layerIndex].isVisible = false

        let docSize = session.document!.size
        let insideView = session.viewport.viewPoint(from: CGPoint(x: 40, y: 30), documentSize: docSize)
        let hit = session.hitTestPenVectorLayer(at: insideView)
        #expect(hit == nil)
    }

    // MARK: - Phase 2B-7: Closed Anchor Hit-Testing & Priority

    @Test func closedStartAnchorHitResolvesExactAnchorIndexZero() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 60))
        session.endPenDrag()
        session.closePen()

        guard let layerID = session.activeLayerID else {
            Issue.record("Committed layer expected")
            return
        }

        let docSize = session.document!.size
        let startView = session.viewport.viewPoint(from: CGPoint(x: 20, y: 20), documentSize: docSize)
        guard let anchorHit = session.hitTestPenClosedAnchor(at: startView) else {
            Issue.record("Anchor hit expected at start anchor")
            return
        }

        #expect(anchorHit.layerID == layerID)
        #expect(anchorHit.anchorIndex.subpathIndex == 0)
        #expect(anchorHit.anchorIndex.anchorIndex == 0)
        #expect(anchorHit.kind == .anchor)
    }

    @Test func closedNonStartAnchorsResolveCorrectIndices() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20)) // index 0
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20)) // index 1
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 60)) // index 2
        session.endPenDrag()
        session.closePen()

        guard let layerID = session.activeLayerID else {
            Issue.record("Committed layer expected")
            return
        }

        let docSize = session.document!.size

        // Test Anchor B (index 1)
        let bView = session.viewport.viewPoint(from: CGPoint(x: 60, y: 20), documentSize: docSize)
        guard let hitB = session.hitTestPenClosedAnchor(at: bView) else {
            Issue.record("Anchor hit expected at anchor B")
            return
        }
        #expect(hitB.layerID == layerID)
        #expect(hitB.anchorIndex.subpathIndex == 0)
        #expect(hitB.anchorIndex.anchorIndex == 1)

        // Test Anchor C (index 2)
        let cView = session.viewport.viewPoint(from: CGPoint(x: 40, y: 60), documentSize: docSize)
        guard let hitC = session.hitTestPenClosedAnchor(at: cView) else {
            Issue.record("Anchor hit expected at anchor C")
            return
        }
        #expect(hitC.layerID == layerID)
        #expect(hitC.anchorIndex.subpathIndex == 0)
        #expect(hitC.anchorIndex.anchorIndex == 2)
    }

    @Test func closedAnchorHitResolvesCorrectSubpathIndexForMultipleSubpaths() throws {
        let session = makeSession()
        // Subpath 0
        let subpath0 = VectorSubpath(points: [
            VectorPoint(anchor: CGPoint(x: 10, y: 10)),
            VectorPoint(anchor: CGPoint(x: 40, y: 10)),
            VectorPoint(anchor: CGPoint(x: 25, y: 40))
        ], isClosed: true)

        // Subpath 1
        let subpath1 = VectorSubpath(points: [
            VectorPoint(anchor: CGPoint(x: 60, y: 60)),
            VectorPoint(anchor: CGPoint(x: 90, y: 60)),
            VectorPoint(anchor: CGPoint(x: 75, y: 90))
        ], isClosed: true)

        let vector = VectorModel(subpaths: [subpath0, subpath1], fill: nil, stroke: VectorStrokeStyle(color: PaletteColor(red: 0, green: 0, blue: 0), width: 2))
        let image = try VectorRenderer.render(vector, in: CGSize(width: 200, height: 200))
        session.addPixelLayer(image, at: .zero, name: "Multi-Subpath", editName: "Add Vector", vector: vector)
        let layerID = session.activeLayerID!

        let docSize = session.document!.size

        // Query anchor on Subpath 0
        let sp0View = session.viewport.viewPoint(from: CGPoint(x: 40, y: 10), documentSize: docSize)
        let hit0 = session.hitTestPenClosedAnchor(at: sp0View)
        #expect(hit0?.anchorIndex.subpathIndex == 0)
        #expect(hit0?.anchorIndex.anchorIndex == 1)

        // Query anchor on Subpath 1
        let sp1View = session.viewport.viewPoint(from: CGPoint(x: 75, y: 90), documentSize: docSize)
        let hit1 = session.hitTestPenClosedAnchor(at: sp1View)
        #expect(hit1?.anchorIndex.subpathIndex == 1)
        #expect(hit1?.anchorIndex.anchorIndex == 2)
    }

    @Test func closedAnchorHitPrioritizesTopmostLayer() {
        let session = makeSession()
        // Bottom layer with anchor at (50, 50)
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 10, y: 90))
        session.endPenDrag()
        session.closePen()
        guard let bottomLayerID = session.activeLayerID else {
            Issue.record("Bottom layer expected")
            return
        }

        // Top layer also with anchor at (50, 50)
        session.beginPen(at: CGPoint(x: 90, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 90, y: 90))
        session.endPenDrag()
        session.closePen()
        guard let topLayerID = session.activeLayerID else {
            Issue.record("Top layer expected")
            return
        }

        #expect(bottomLayerID != topLayerID)

        let docSize = session.document!.size
        let viewPoint = session.viewport.viewPoint(from: CGPoint(x: 50, y: 50), documentSize: docSize)
        let hit = session.hitTestPenClosedAnchor(at: viewPoint)
        #expect(hit?.layerID == topLayerID)
    }

    @Test func topLayerPathOccludesLowerLayerAnchor() {
        let session = makeSession()
        // Bottom layer with anchor at (50, 50)
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 50))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 10, y: 90))
        session.endPenDrag()
        session.closePen()

        // Top layer is a rectangle covering (30, 30) to (70, 70), with NO anchor at (50, 50)
        session.beginPen(at: CGPoint(x: 30, y: 30))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 70, y: 30))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 70, y: 70))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 70))
        session.endPenDrag()
        session.closePen()
        guard let topLayerID = session.activeLayerID else {
            Issue.record("Top layer expected")
            return
        }

        let docSize = session.document!.size
        let centerView = session.viewport.viewPoint(from: CGPoint(x: 50, y: 50), documentSize: docSize)

        // At (50, 50), top layer has NO anchor, but its path covers (50, 50).
        // The bottom layer's anchor at (50, 50) must NOT win over top layer's path.
        let anchorHit = session.hitTestPenClosedAnchor(at: centerView)
        #expect(anchorHit == nil)

        // Path-level hit resolves to the top layer
        let pathHit = session.hitTestPenVectorLayer(at: centerView)
        #expect(pathHit?.layerID == topLayerID)
    }

    @Test func clickingClosedAnchorDoesNotCreateNewDraftOrLayer() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 40, y: 60))
        session.endPenDrag()
        session.closePen()

        guard let layerID = session.activeLayerID else {
            Issue.record("Layer expected")
            return
        }
        let initialLayerCount = session.document?.layers.count ?? 0

        let docSize = session.document!.size
        let startView = session.viewport.viewPoint(from: CGPoint(x: 20, y: 20), documentSize: docSize)
        guard let anchorHit = session.hitTestPenClosedAnchor(at: startView) else {
            Issue.record("Anchor hit expected")
            return
        }

        // Simulate click on closed anchor
        session.selectLayer(anchorHit.layerID)

        #expect(session.activeLayerID == layerID)
        #expect(session.penDraft == nil)
        #expect(session.document?.layers.count == initialLayerCount)
    }

    // MARK: - Phase 2B-8 Tests

    @Test func newlyCreatedPenPathHasNoFillAndNoStroke() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 20, y: 20))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 60, y: 60))
        session.endPenDrag()
        session.finishPen()

        guard let layer = session.activeLayer, let vector = layer.vector else {
            Issue.record("Layer should have vector")
            return
        }

        #expect(vector.fill == nil)
        #expect(vector.stroke == nil)
        #expect(vector.subpaths.count == 1)
        #expect(vector.subpaths[0].isClosed == false)
        #expect(vector.subpaths[0].points.count == 2)
    }

    @Test func closingPenPathLeavesFillAndStrokeNil() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 40))
        session.endPenDrag()
        session.closePen()

        guard let layer = session.activeLayer, let vector = layer.vector else {
            Issue.record("Layer should have vector")
            return
        }

        #expect(vector.fill == nil)
        #expect(vector.stroke == nil)
        #expect(vector.subpaths.count == 1)
        #expect(vector.subpaths[0].isClosed == true)
        #expect(vector.subpaths[0].points.count == 3)
    }

    @Test func closedPathPreservesAllAnchorsAndClosingAnchorIdentified() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 40))
        session.endPenDrag()
        session.closePen()

        guard let layerID = session.activeLayerID,
              let vector = session.activeLayer?.vector else {
            Issue.record("Layer should have vector")
            return
        }

        #expect(vector.subpaths[0].points.count == 3)
        // Closing anchor is identified in transient state
        #expect(session.penHoverAnchor != nil)
        #expect(session.penHoverAnchor?.layerID == layerID)
        #expect(session.penHoverAnchor?.anchorIndex.subpathIndex == 0)
        #expect(session.penHoverAnchor?.anchorIndex.anchorIndex == 0)

        // All anchors are resolvable
        let docSize = session.document!.size
        let p0View = session.viewport.viewPoint(from: CGPoint(x: 10, y: 10), documentSize: docSize)
        let p1View = session.viewport.viewPoint(from: CGPoint(x: 50, y: 10), documentSize: docSize)
        let p2View = session.viewport.viewPoint(from: CGPoint(x: 30, y: 40), documentSize: docSize)

        #expect(session.hitTestPenClosedAnchor(at: p0View)?.anchorIndex.anchorIndex == 0)
        #expect(session.hitTestPenClosedAnchor(at: p1View)?.anchorIndex.anchorIndex == 1)
        #expect(session.hitTestPenClosedAnchor(at: p2View)?.anchorIndex.anchorIndex == 2)
    }

    @Test func vectorRendererRendersTransparentImageWhenFillAndStrokeAreNil() throws {
        let subpath = VectorSubpath(points: [
            VectorPoint(anchor: CGPoint(x: 10, y: 10)),
            VectorPoint(anchor: CGPoint(x: 50, y: 10)),
            VectorPoint(anchor: CGPoint(x: 30, y: 40))
        ], isClosed: true)
        let model = VectorModel(subpaths: [subpath], fill: nil, stroke: nil)
        let image = try VectorRenderer.render(model, in: CGSize(width: 60, height: 50))
        #expect(image.width == 60)
        #expect(image.height == 50)
    }

    @Test func explicitlyStyledVectorLayerPreservesStyleWhenContinued() {
        let session = makeSession()
        let subpath = VectorSubpath(points: [
            VectorPoint(anchor: CGPoint(x: 10, y: 10)),
            VectorPoint(anchor: CGPoint(x: 50, y: 50))
        ], isClosed: false)
        let stroke = VectorStrokeStyle(color: PaletteColor(red: 1, green: 0, blue: 0), width: 6)
        let model = VectorModel(subpaths: [subpath], fill: nil, stroke: stroke)
        let image = try! VectorRenderer.render(model, in: CGSize(width: 60, height: 60))
        session.addPixelLayer(image, at: .zero, name: "StyledVector", editName: "Add Vector", vector: model)
        let layerID = session.activeLayerID!

        let docSize = session.document!.size
        let endView = session.viewport.viewPoint(from: CGPoint(x: 50, y: 50), documentSize: docSize)
        guard let hit = session.hitTestPenEndpoint(at: endView) else {
            Issue.record("Endpoint hit expected")
            return
        }

        session.beginPenContinuation(from: hit)
        session.beginPen(at: CGPoint(x: 90, y: 90))
        session.endPenDrag()
        session.finishPen()

        guard let layer = session.document?.layers.first(where: { $0.id == layerID }),
              let continuedVector = layer.vector else {
            Issue.record("Continued layer vector expected")
            return
        }

        #expect(continuedVector.stroke?.width == 6)
        #expect(continuedVector.stroke?.color.red == 1)
        #expect(continuedVector.subpaths[0].points.count == 3)
    }

    @Test func closedPathPersistenceRoundTripPreservesNoFillNoStrokeAndAllAnchors() throws {
        let subpath = VectorSubpath(points: [
            VectorPoint(anchor: CGPoint(x: 10, y: 10), previousControl: nil, nextControl: CGPoint(x: 20, y: 15)),
            VectorPoint(anchor: CGPoint(x: 50, y: 20), previousControl: CGPoint(x: 40, y: 25), nextControl: nil),
            VectorPoint(anchor: CGPoint(x: 30, y: 60))
        ], isClosed: true)
        let original = VectorModel(subpaths: [subpath], fill: nil, stroke: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VectorModel.self, from: data)

        #expect(decoded.fill == nil)
        #expect(decoded.stroke == nil)
        #expect(decoded.subpaths.count == 1)
        #expect(decoded.subpaths[0].isClosed == true)
        #expect(decoded.subpaths[0].points.count == 3)
        #expect(decoded.subpaths[0].points[0].nextControl == CGPoint(x: 20, y: 15))
        #expect(decoded.subpaths[0].points[1].previousControl == CGPoint(x: 40, y: 25))
    }

    @Test func closedAnchorClickDoesNotCreateNewDraftOrHistory() {
        let session = makeSession()
        session.beginPen(at: CGPoint(x: 10, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 50, y: 10))
        session.endPenDrag()
        session.beginPen(at: CGPoint(x: 30, y: 40))
        session.endPenDrag()
        session.closePen()

        let undoCount = session.history.undoCount
        let layerCount = session.document?.layers.count ?? 0
        let layerID = session.activeLayerID!

        let docSize = session.document!.size
        let anchorView = session.viewport.viewPoint(from: CGPoint(x: 50, y: 10), documentSize: docSize)
        guard let anchorHit = session.hitTestPenClosedAnchor(at: anchorView) else {
            Issue.record("Anchor hit expected")
            return
        }

        #expect(anchorHit.anchorIndex.anchorIndex == 1)

        // Simulate click
        session.selectLayer(anchorHit.layerID)

        #expect(session.activeLayerID == layerID)
        #expect(session.penDraft == nil)
        #expect(session.document?.layers.count == layerCount)
        #expect(session.history.undoCount == undoCount)
    }
}
