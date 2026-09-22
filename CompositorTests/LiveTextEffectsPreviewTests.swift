import AppKit
import Testing
@testable import Compositor

@MainActor
struct LiveTextEffectsPreviewTests {
    @Test func liveTextEffectsPreviewDoesNotPolluteHistory() throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)

        // Create an initial text layer with effects
        session.beginText(at: CGPoint(x: 20, y: 20), newLayer: true)
        var draft = try #require(session.textDraft)
        draft.style.content = "Test"
        draft.style.fontSize = 24
        session.applyText(draft)
        let layerID = try #require(session.activeLayerID)

        var effects = LayerEffects()
        effects.stroke = StrokeEffect(size: 3, position: .outside)
        effects.outerGlow = OuterGlowEffect(size: 10, opacity: 0.8)
        effects.shadow = ShadowEffect(distance: 5, blur: 8)
        session.setEffects(effects, on: layerID, name: "Set Effects")

        let baseUndoCount = session.history.undoCount

        // Begin editing text
        session.editActiveText()
        #expect(session.textDraft != nil)

        // Type keystrokes / update text content
        session.textDraft?.style.content = "Testing 1"
        session.updateLiveTextEffectsPreviewNow()
        #expect(session.liveTextEffectsPreview != nil)
        #expect(session.liveTextEffectsPreview?.layerID == layerID)
        #expect(session.history.undoCount == baseUndoCount)

        session.textDraft?.style.content = "Testing 1 2 3"
        session.updateLiveTextEffectsPreviewNow()
        #expect(session.liveTextEffectsPreview != nil)
        #expect(session.history.undoCount == baseUndoCount)
    }

    @Test func liveTextEffectsPreviewGeneratesPassesForEffects() throws {
        let session = EditorSession()
        session.createDocument(width: 300, height: 300)

        // Create initial text layer
        session.beginText(at: CGPoint(x: 20, y: 20), newLayer: true)
        var draft = try #require(session.textDraft)
        draft.style.content = "Hello"
        draft.style.fontSize = 32
        session.applyText(draft)
        let layerID = try #require(session.activeLayerID)

        var effects = LayerEffects()
        effects.stroke = StrokeEffect(size: 4, position: .outside)
        effects.outerGlow = OuterGlowEffect(size: 15, opacity: 0.9)
        effects.shadow = ShadowEffect(distance: 8, blur: 12)
        effects.colorOverlay = ColorOverlayEffect(red: 1, green: 0, blue: 0, opacity: 1)
        effects.innerShadow = InnerShadowEffect(distance: 3, blur: 4)
        session.setEffects(effects, on: layerID, name: "All Effects")

        // Edit text and generate preview
        session.editActiveText()
        session.textDraft?.style.content = "Compositor Text Preview"
        session.updateLiveTextEffectsPreviewNow()

        let preview = try #require(session.liveTextEffectsPreview)
        #expect(preview.layerID == layerID)
        #expect(preview.passes.count >= 2) // Shadow/Glow + Stroke + Content pass
        #expect(preview.image.width > 0 && preview.image.height > 0)
        #expect(preview.inset > 0)
    }

    @Test func commitRemainsAtomicAndClearsPreview() throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)

        session.beginText(at: CGPoint(x: 20, y: 20), newLayer: true)
        var draft = try #require(session.textDraft)
        draft.style.content = "Initial"
        draft.style.fontSize = 20
        session.applyText(draft)
        let layerID = try #require(session.activeLayerID)

        var effects = LayerEffects()
        effects.outerGlow = OuterGlowEffect(size: 12)
        session.setEffects(effects, on: layerID, name: "Add Glow")

        let preEditUndoCount = session.history.undoCount

        session.editActiveText()
        session.textDraft?.style.content = "Committed Final Text"
        session.updateLiveTextEffectsPreviewNow()
        #expect(session.liveTextEffectsPreview != nil)

        // Commit atomically
        let finished = session.finishText()
        #expect(finished)
        #expect(session.textDraft == nil)
        #expect(session.liveTextEffectsPreview == nil)
        #expect(session.history.undoCount == preEditUndoCount + 1)

        let committed = try #require(session.document?.layers.first(where: { $0.id == layerID }))
        #expect(committed.liveText?.style.content == "Committed Final Text")
        #expect(committed.effects?.outerGlow != nil)
    }

    @Test func cancelRestoresPreviousStateAndClearsPreview() throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)

        session.beginText(at: CGPoint(x: 20, y: 20), newLayer: true)
        var draft = try #require(session.textDraft)
        draft.style.content = "Preserved Original"
        draft.style.fontSize = 20
        session.applyText(draft)
        let layerID = try #require(session.activeLayerID)

        var effects = LayerEffects()
        effects.stroke = StrokeEffect(size: 2)
        session.setEffects(effects, on: layerID, name: "Add Stroke")

        let preEditUndoCount = session.history.undoCount

        session.editActiveText()
        session.textDraft?.style.content = "Discarded Draft While Typing"
        session.updateLiveTextEffectsPreviewNow()
        #expect(session.liveTextEffectsPreview != nil)

        // Cancel editing
        session.cancelText()
        #expect(session.textDraft == nil)
        #expect(session.liveTextEffectsPreview == nil)
        #expect(session.history.undoCount == preEditUndoCount)

        let layer = try #require(session.document?.layers.first(where: { $0.id == layerID }))
        #expect(layer.liveText?.style.content == "Preserved Original")
        #expect(layer.effects?.stroke != nil)
    }
}
