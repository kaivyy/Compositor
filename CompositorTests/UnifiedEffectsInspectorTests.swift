import AppKit
import Testing
@testable import Compositor

@MainActor
struct UnifiedEffectsInspectorTests {
    @Test func inspectorOrderContainsAllSixEffects() {
        #expect(EffectsSheet.inspectorOrder.count == 6)
        #expect(EffectsSheet.inspectorOrder == [
            .stroke, .outerGlow, .shadow, .innerGlow, .colorOverlay, .innerShadow
        ])
    }

    @Test func openEffectsInspectorCapturesOriginalSnapshot() throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        session.insert(try makeImage())
        let layerID = try #require(session.activeLayerID)

        #expect(session.effectsEditing == nil)
        #expect(session.effectsEditingOriginal == nil)

        session.openEffectsInspector(for: layerID, selecting: .stroke)
        #expect(session.effectsEditing?.layerID == layerID)
        #expect(session.effectsEditing?.kind == .stroke)
        #expect(session.effectsEditingOriginal != nil)
        #expect(session.effectsEditingOriginal?.isEmpty == true)
    }

    @Test func multiEffectEditingAndCommit() throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        session.insert(try makeImage())
        let layerID = try #require(session.activeLayerID)

        session.openEffectsInspector(for: layerID, selecting: .stroke)

        // Enable and configure Stroke
        session.changeEffects { effects in
            effects.stroke = StrokeEffect(size: 4, position: .center)
            effects.outerGlow = OuterGlowEffect(size: 15, opacity: 0.8)
            effects.shadow = ShadowEffect(distance: 6, blur: 10)
        }

        let layerEffects = try #require(session.document?.layers.first(where: { $0.id == layerID })?.effects)
        #expect(layerEffects.stroke?.size == 4)
        #expect(layerEffects.stroke?.position == .center)
        #expect(layerEffects.outerGlow?.size == 15)
        #expect(layerEffects.shadow?.distance == 6)

        session.finishEffectsEditing(commit: true)
        #expect(session.effectsEditing == nil)
        #expect(session.effectsEditingOriginal == nil)

        let committed = try #require(session.document?.layers.first(where: { $0.id == layerID })?.effects)
        #expect(committed.stroke?.size == 4)
        #expect(committed.outerGlow?.size == 15)
        #expect(committed.shadow?.distance == 6)
    }

    @Test func transactionalCancelRevertsAllModifiedEffects() throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        session.insert(try makeImage())
        let layerID = try #require(session.activeLayerID)

        // Pre-configure layer with an initial stroke
        var initial = LayerEffects()
        initial.stroke = StrokeEffect(size: 2, position: .outside)
        session.setEffects(initial, on: layerID, name: "Initial Stroke")

        // Open inspector and make multiple edits
        session.openEffectsInspector(for: layerID, selecting: .outerGlow)
        session.changeEffects { effects in
            effects.stroke?.size = 10
            effects.outerGlow = OuterGlowEffect(size: 25)
            effects.colorOverlay = ColorOverlayEffect(opacity: 0.5)
        }

        // Verify edited state during session
        let duringEdit = try #require(session.document?.layers.first(where: { $0.id == layerID })?.effects)
        #expect(duringEdit.stroke?.size == 10)
        #expect(duringEdit.outerGlow != nil)
        #expect(duringEdit.colorOverlay != nil)

        // Cancel editing session
        session.finishEffectsEditing(commit: false)
        #expect(session.effectsEditing == nil)

        // Verify all effects were reverted back to initial snapshot
        let reverted = try #require(session.document?.layers.first(where: { $0.id == layerID })?.effects)
        #expect(reverted.stroke?.size == 2)
        #expect(reverted.stroke?.position == .outside)
        #expect(reverted.outerGlow == nil)
        #expect(reverted.colorOverlay == nil)
    }

    @Test func switchingActiveLayerSwitchesInspectorTarget() throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        session.insert(try makeImage())
        let layer1 = try #require(session.activeLayerID)
        session.insert(try makeImage())
        let layer2 = try #require(session.activeLayerID)

        // Open on layer 1
        session.openEffectsInspector(for: layer1, selecting: .stroke)
        #expect(session.effectsEditing?.layerID == layer1)

        // Switch to layer 2
        session.openEffectsInspector(for: layer2, selecting: .innerGlow)
        #expect(session.effectsEditing?.layerID == layer2)
        #expect(session.effectsEditing?.kind == .innerGlow)

        session.finishEffectsEditing(commit: true)
        #expect(session.effectsEditing == nil)
    }

    private func makeImage() throws -> ImportedImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 128, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: space, components: [0.5, 0.5, 0.5, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try #require(context.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Test")
    }
}
