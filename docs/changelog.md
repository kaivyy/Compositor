# Changelog

## Unreleased

### Fixed
- **Layer Effects Persistence and Export (Issue #50)**:
  - Passed `effects: layer.effects` through `EditorSession.projectSnapshot()` so that layer effects (`StrokeEffect`, `ShadowEffect`, `ColorOverlayEffect`, `InnerShadowEffect`) are preserved in `ProjectLayerRecord` during project save and export operations.
  - Restored `effects: $0.effects` in `EditorSession.installProject(_:from:)` so that layer effects are properly reconstructed on `ImageLayer` when reopening saved projects.
  - Added regression test `projectRoundTripPreservesAllLayerEffects()` in `ProjectTests.swift` covering save/load round-trips for stroke, drop shadow, color overlay, and inner shadow.
  - Added deterministic rendering regression test `layerEffectsAreRenderedInExport()` in `ProjectTests.swift` verifying that layer effects are rendered into exported images.
- **Toolchain and Test Suite Compatibility**:
  - Resolved Swift type-checker timeouts on Xcode 16 / macOS 15 in `ImageAdjustments.swift` (gradient map table generation) and `ContentView.swift` (view builder splitting).
  - Updated selection tool test assertion in `SelectionTests.swift` to reflect the Magic tool's Object mode (`NavigationTool.wand`).
