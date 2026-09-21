# Changelog

All changes to the repository are documented here chronologically with categories, files, rationale, behavior impact, and verification.

---

## 2026-09-19

### Production Fix
- File: `Compositor/Document/ImageAdjustments.swift`
- Change: Split gradient-map lookup table generation from a nested `flatMap` + `map` closure into an explicit `for` loop with a local `byte` clamping helper.
- Reason: The Swift compiler failed with a type-checking timeout (`the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions`).
- Behavior impact: None. The numerical output for all 256 entries in the 3-channel RGB table matches the original mathematical formula (`dark + (light - dark) * t`).
- Verification: Clean debug build passed (`xcodebuild ... build`).

### Production Fix
- File: `Compositor/ContentView.swift`
- Change: Extracted the central editor layout `VStack` (toolbars, tool rail, canvas, layer panel, status bar) from `var body: some View` into `private var editorLayout: some View`.
- Reason: The 180+ line chained view builder exceeded the Swift compiler's type-checking time limit on macOS 15+ SDK / Xcode 16+.
- Behavior impact: None. View hierarchy, styling, bindings, and layout behavior remain completely unchanged.
- Verification: Clean debug build passed (`xcodebuild ... build`).

### Test Maintenance
- File: `CompositorTests/LayerTests.swift`
- Change: Replaced calls to obsolete method `coordinator.moveLayer(...)` with the existing production session reordering API `session.placeLayer(...)`.
- Reason: `moveLayer` was deleted from production code in commit `77a3018` when Cocoa drag-and-drop table delegates were adopted, leaving `LayerTests.swift` unable to compile.
- Behavior impact: None on production code. Validates that `session.placeLayer` updates document layer order and that subsequent `coordinator.update(table)` calls preserve table selection and layer identity.
- Verification: Unit test suite compiled and `LayerTests` passed all 12 tests (`100% passed`).

### Test Maintenance
- File: `CompositorTests/SelectionTests.swift`
- Change: Replaced the obsolete cursor collection reference and updated the stale cursor assertion in `cursorBadgeFollowsModifiersButKeepsAnOutlinesStartingMode` to validate `CanvasView.selectionCursors[.freehandLasso]` across all three selection modes.
- Reason: The production implementation already uses composite selection cursors (base crosshair plus tool badge for all modes, including `.replace`), as established in initial commit `2dae6a2`. However, the test originally referenced an obsolete cursor collection name (`lassoCursors`) and contained a stale expectation comparing the `.replace` mode cursor against the singleton `NSCursor.crosshair`.
- Behavior impact: No production behavior was changed. The test now correctly verifies that the current composite cursor dictionary provides distinct, non-nil cursors for `.replace`, `.add`, and `.subtract`.
- Verification: Focused test `SelectionTests/cursorBadgeFollowsModifiersButKeepsAnOutlinesStartingMode()` passed cleanly (`** TEST SUCCEEDED **`, exit code 0).

### Test Maintenance
- File: `CompositorTests/SmartEditTests.swift`
- Change: Updated `SubjectRemoval.run(image)` to `SubjectRemoval.run(image, settings: FilterSettings())`.
- Reason: In commit `958bb01`, `SubjectRemoval.run` was updated to require a `settings: FilterSettings` parameter, but `SmartEditTests.swift:75` was not updated, preventing test compilation.
- Behavior impact: None on production code. Fixes test target compilation failure.
- Verification: Test target `CompositorTests` compiles successfully.

### Documentation
- File: `docs/architecture-audit.md`
- Change: Created comprehensive architectural audit and contribution readiness report covering repository structure, core models, rendering pipeline, upstream PR #8 analysis, and issue dependency order.
- Reason: Repository policy requires recording the architecture audit performed before feature implementation.
- Behavior impact: None. Documentation only; does not modify production behavior or participate in baseline code fixes.
- Verification: Document content verified against upstream source code and Git archaeology.

---

## 2026-09-20

### Feature Integration: Upstream Text Tool (PR #27) & Layer Styles
- Branch: `feature/text-tool-layer-styles`
- Baseline Ancestry: Created directly from upstream PR #27 current head `a397e74` (`bfayers:feature/text-tool`, 13 commits on top of `upstream/main`), incorporating verified baseline maintenance fixes for Xcode 16 / macOS 15+ SDK compatibility, and integrating our clean Layer Styles architecture.
- Files Added / Modified:
  - `Compositor/Document/LayerStyles.swift` (New)
  - `Compositor/Rendering/LayerStyleRenderer.swift` (New)
  - `Compositor/Rendering/LayerStyleCache.swift` (New)
  - `Compositor/UI/LayerStylesInspector.swift` (New)
  - `CompositorTests/LayerStyleTests.swift` (New)
  - `Compositor/Document/ColorPalette.swift`
  - `Compositor/Document/EditorSession.swift`
  - `Compositor/Document/LayerAppearance.swift`
  - `Compositor/Document/EditorSession+Projects.swift`
  - `Compositor/Document/ProjectWorkspace.swift`
  - `Compositor/Document/SelectionClipboard.swift`
  - `Compositor/IO/ProjectStore.swift`
  - `Compositor/IO/ImageExporter.swift`
  - `Compositor/Rendering/EditorCanvas.swift`
  - `Compositor/Rendering/LayerRenderer.swift`
  - `Compositor/UI/LayersPanel.swift`
  - `Compositor/Document/ImageAdjustments.swift` (Baseline compiler fix)
  - `Compositor/ContentView.swift` (Baseline compiler fix with PR #27 TextControls preserved)
  - `docs/changelog.md`
- Architectural Highlights:
  - **Upstream Text Tool as Baseline**: PR #27 provides the official Text Tool implementation (`LayerText`, `LayerTextStyle`, `CharacterParagraphPanel`, `SearchableFontPicker`, inline editing `CanvasInlineTextView`, Cmd+Enter commit, Esc cancel, text stroke, rotation handling). Our previous local competing Text Tool (`TextTool.swift`, `TextControls.swift`, `CanvasTextOverlay`) is NOT revived on this branch.
  - **Universal Layer Styles Model**: Strongly typed, `Codable`, `Hashable`, `Equatable`, `Sendable` `LayerStyles` model attached to `ImageLayer.styles: LayerStyles?`. Supports Stroke (`.outside`, `.center`, `.inside`), Outer Glow, Drop Shadow, and Color Overlay.
  - **Universal Content Surface**: Layer Styles operate generically on the raster surface produced by the layer (`layer.asset?.image`), applying identically across text layers, shape layers, and pixel layers without duplicate text-specific style logic.
  - **Symmetric Bounds Expansion**: Dynamically calculates `contentPadding` from outer stroke, glow radius, and directional shadow displacement. Expanded bounds are drawn via `LayerRenderer.draw(..., padding: padding)` while leaving logical `LayerTransform` and interactive transform bounding boxes unshifted.
  - **Non-destructive Rendering Pipeline**: Applied in Photoshop-compatible order (`Drop Shadow -> Outer Glow -> Outside/Center Stroke -> Base Image + Color Overlay -> Inside Stroke`) across both real-time canvas display (`EditorCanvas.swift`) and flat project export (`ImageExporter.swift`).
  - **Performance Caching**: `LayerStyleCache` keys rendered composites by layer ID, image memory identity (`ObjectIdentifier`), and style hash, ensuring rapid pan/zoom performance and instant invalidation on style changes.
  - **Full Document Integration**: Complete undo/redo via `DocumentHistory`, duplicate layer / copy-paste propagation, and backwards-compatible JSON project persistence (`ProjectLayerRecord.styles: LayerStyles?`).
  - **Presets**: Neon Cyan and Neon Pink are implemented purely as composition presets of generic Stroke, Glow, and Shadow effects without special-case renderers.
- Verification:
  - Build: `** BUILD SUCCEEDED **` with zero errors.
  - Text Tool: `TextToolTests` passed all 16 tests (`100% passed`, 0 failed).
  - Layer Styles: `LayerStyleTests` passed all 20 tests (`100% passed`, 0 failed).
  - Core Regression Suites: `ProjectTests` (6/6), `HistoryTests` (7/7), `SelectionClipboardTests` (9/9), `CanvasSizeTests` (4/4), `GroupTests` (4/4), `LayerTests` (11/11), `SmartEditTests` (4/4) all passed (`100% passed`).

### Bug Fixes & Refinements: Integration Testing Issues
- Files Modified:
  - `Compositor/Document/ColorPalette.swift`
  - `Compositor/Document/TextTool.swift`
  - `Compositor/Document/EditorSession.swift`
  - `Compositor/UI/TextControls.swift`
  - `Compositor/Rendering/EditorCanvas.swift`
  - `Compositor/Rendering/SeparableBlend.swift`
  - `Compositor/ContentView.swift`
  - `Compositor/UI/LayersPanel.swift`
  - `Compositor/UI/LayerStylesInspector.swift`
  - `CompositorTests/TextToolTests.swift`
  - `CompositorTests/LayerStyleTests.swift`
- Bug 1 (Default Text Color Is Black):
  - Changed default new text color from black to existing project constant `PaletteColor.white` in `LayerTextStyle` and `EditorSession.addTextLayer`.
  - Added `PaletteColor.white` abstraction constant (`Color(red: 1, green: 1, blue: 1)`) without hardcoding arbitrary RGB magic numbers.
  - Preserved user-selected color persistence, color changing workflows, and existing project deserialization without unexpected recoloring.
  - Added regression tests `defaultLayerTextStyleProperties()` and `persistedSavedTextColorIsNotRecolored()` in `TextToolTests.swift`.
- Bug 2 (Layer Styles Do Not Affect PR #27 Text Layers):
  - Root Cause: PR #27 dual rendering path bypassed `LayerStyleRenderer` by drawing vector text directly on canvas via `LayerRenderer.drawText` when `layer.text != nil`.
  - Fix: When `layer.styles?.hasActiveEffects == true`, text layers generate/retrieve their text CGImage content surface and route through `LayerStyleCache.shared.styledImage(for:baseImage:)` with padding and effects, rendering styled raster to canvas and export. When styles are inactive, PR #27 pure vector text rendering is fully preserved.
  - Canvas editing visibility: `EditorCanvas` permits rendering styled raster during live text editing if styles are active.
  - Cache Invalidation: Integrated `LayerStyleCache.shared.invalidate(layerID:)` inside `EditorSession.updateActiveText`, `commitTextEdit`, `cancelTextEdit`, and `addTextLayer`, ensuring changing text content, font family, font size, or color never reuses a stale pre-edit cached image.
  - Added deterministic rendering regression tests in `LayerStyleTests.swift` for text + Stroke, text + Outer Glow, text + Drop Shadow, text + Color Overlay, cache invalidation across text changes ("ABC" -> "ABCDEF"), and export raster pipeline.
- Bug 3 (FX Inspector Movable & Live Preview):
  - Replaced modal SwiftUI `.sheet` presentation in `LayersPanel.swift` with a native AppKit `NSPanel` / utility window hosted via `FloatingPanelController(name: "layerStylesPanel")` in `ContentView.swift`.
  - Movable, non-blocking, remains visible while adjusting styles, closes cleanly without duplicates, and maintains continuous live preview on the underlying canvas.
  - Connected `onEditingChanged` on all effect sliders to bracket dragging with `session.beginStyleEdit()` and `session.finishStyleEdit()`, providing continuous canvas updates while recording exactly one undo step in `DocumentHistory` per slider drag.
  - Added `layerStylesInspectorLifecycleAndUndoRedo()` unit test in `LayerStyleTests.swift`.
- SeparableBlend Working Color Space:
  - Fixed `SeparableBlend.swift` by explicitly specifying `.workingColorSpace: space` for `CIContext` and passing `.colorSpace: space` in `CIImage` options. Prevents linear color space mismatch and ensures `.colorBurn` and `.colorDodge` blend modes match PDF/Photoshop specification (passing `LayerAppearanceTests.blendModesAndOpacityMatchKnownPixels`).
- Verification:
  - `TextToolTests`: 18/18 passed (100%).
  - `LayerStyleTests`: 27/27 passed (100%).
  - Core regressions: `ProjectTests` (6/6), `HistoryTests` (7/7), `SelectionClipboardTests` (9/9), `CanvasSizeTests` (4/4), `GroupTests` (4/4), `LayerTests` (11/11), `SmartEditTests` (4/4), `SelectionEditTests` (19/19), `LayerAppearanceTests` (5/5) all passed.
  - Full `CompositorTests`: 344 passed out of 354 test runs (10 remaining failures are pre-existing baseline failures in unrelated tools: sliders, marquee/lasso keys, transform press).
  - Manual GUI validation: Launched Compositor.app on macOS, verified new canvas, text tool selection, floating `Layer Styles` NSPanel positioning, moving panel to (200, 200), slider scrubbing (Stroke size 3px -> 8px), and clean panel closing.

---

## 2026-09-21

### UI & Color Picker Improvement: Native macOS Color Wheel & Black Wheel Fix
- Files Modified:
  - `Compositor/Document/ColorPalette.swift`
  - `Compositor/UI/TextControls.swift`
  - `Compositor/UI/LayerStylesInspector.swift`
- Changes:
  - **Native macOS Color Wheel Integration**: Replaced custom swatch circles and single-row preset popovers across the Text Tool (toolbar text color well, Character & Paragraph panel text color well, and dedicated stroke popover color rows) and Layer Styles Inspector (Stroke, Outer Glow, Drop Shadow, and Color Overlay effect controls) with native SwiftUI `ColorPicker` backed by macOS `NSColorPanel`.
  - **Black Color Wheel Bug Fix (`swiftUIForPicker`)**: Added `PaletteColor.swiftUIForPicker: Color` computed property and helper `PickerHSB`. In macOS Cocoa `NSColorPanel`, selecting a color with brightness = 0 (pure black) renders the native Color Wheel as a solid pitch-black disk, preventing users from selecting any other hue. `swiftUIForPicker` automatically lifts brightness to a minimum display threshold of 15% when presenting the color to the picker while preserving hue, saturation, and the actual stored color model (`PaletteColor`).
  - **Live Verification**:
    - Text Tool toolbar color well opens native macOS `NSColorPanel` with Color Wheel tab active and interactive.
    - Dragging brightness to 0% (pure black) and reopening confirms the Color Wheel remains visible and other hues can be selected.
    - Dedicated Text Stroke popover and Character & Paragraph popovers display native `ColorPicker` wells and connect to `NSColorPanel`.
    - Layer Styles inspector effect color wells connect to `NSColorPanel` and update live.
- Verification:
  - Clean build: `** BUILD SUCCEEDED **`.
  - `TextToolTests`: 18/18 passed (100%).
  - `LayerStyleTests`: 27/27 passed (100%).
  - Live GUI verification on macOS with screen capture validation.

