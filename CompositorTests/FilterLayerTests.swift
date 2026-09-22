import Foundation
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct FilterLayerTests {
    @Test func filterLayerModelDefaultsAndValidation() throws {
        let gaussian = LayerFilter(kind: .gaussianBlur)
        #expect(gaussian.kind == .gaussianBlur)
        #expect(gaussian.settings.radius == 10)
        #expect(gaussian.isValid)

        let motion = LayerFilter(kind: .motionBlur)
        #expect(motion.kind == .motionBlur)
        #expect(motion.settings.angle == 0)
        #expect(motion.settings.distance == 10)
        #expect(motion.isValid)

        let noise = LayerFilter(kind: .addNoise)
        #expect(noise.kind == .addNoise)
        #expect(noise.settings.amount == 10)
        #expect(!noise.settings.gaussian)
        #expect(!noise.settings.monochromatic)
        #expect(noise.isValid)

        let lens = LayerFilter(kind: .lensCorrection)
        #expect(lens.kind == .lensCorrection)
        #expect(lens.settings.distortion == 0)
        #expect(lens.isValid)

        let invert = LayerFilter(kind: .invert)
        #expect(invert.kind == .invert)
        #expect(invert.isValid)
        #expect(!invert.kind.isEditable)

        var invalid = gaussian
        invalid.settings.radius = -5
        #expect(!invalid.isValid)
    }

    @Test func filterSettingsConversion() {
        var s = FilterSettings()
        s.radius = 25
        s.angle = 45
        s.distance = 150
        s.amount = 75
        s.gaussian = true
        s.monochromatic = true
        s.distortion = -20

        let layerSettings = LayerFilterSettings(from: s, seed: 42)
        #expect(layerSettings.radius == 25)
        #expect(layerSettings.angle == 45)
        #expect(layerSettings.distance == 150)
        #expect(layerSettings.amount == 75)
        #expect(layerSettings.gaussian)
        #expect(layerSettings.monochromatic)
        #expect(layerSettings.distortion == -20)
        #expect(layerSettings.seed == 42)

        let back = layerSettings.toFilterSettings()
        #expect(back.radius == 25)
        #expect(back.angle == 45)
        #expect(back.distance == 150)
        #expect(back.amount == 75)
        #expect(back.gaussian)
        #expect(back.monochromatic)
        #expect(back.distortion == -20)
    }

    @Test func layerFilterCodableRoundTrip() throws {
        let filter = LayerFilter(kind: .motionBlur, settings: LayerFilterSettings(from: FilterSettings(angle: 30, distance: 80)))
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(LayerFilter.self, from: data)
        #expect(decoded == filter)
        #expect(decoded.kind == .motionBlur)
        #expect(decoded.settings.angle == 30)
        #expect(decoded.settings.distance == 80)
    }

    @Test func imageLayerFilterInvariants() {
        var layer = ImageLayer(name: "Blur Filter", blankSize: CGSize(width: 100, height: 100))
        layer.filter = LayerFilter(kind: .gaussianBlur)
        #expect(layer.isFilterLayer)

        // Having an asset violates the invariant
        layer.asset = ImportedImage(image: CGImage.makeSolidColor(width: 1, height: 1, color: .black)!, thumbnail: CGImage.makeSolidColor(width: 1, height: 1, color: .black)!, name: "test")
        #expect(!layer.isFilterLayer)

        layer.asset = nil
        #expect(layer.isFilterLayer)

        // Having an adjustment violates the invariant
        layer.adjustment = LayerAdjustment(kind: .curves)
        #expect(!layer.isFilterLayer)

        layer.adjustment = nil
        #expect(layer.isFilterLayer)

        // Being a group violates the invariant
        layer.isGroup = true
        #expect(!layer.isFilterLayer)
    }

    private func rendered(_ session: EditorSession) async throws -> [UInt8] {
        let snapshot = try #require(session.projectSnapshot())
        let raster = try await ImageExporter.shared.render(snapshot)
        let image = raster.image
        let ctx = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: ctx)
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    private func makeImage(width: Int, height: Int, color: PaletteColor, alpha: [UInt8]) throws -> ImportedImage {
        let bytes = alpha.flatMap { a in [UInt8((color.red * CGFloat(a)).rounded()), UInt8((color.green * CGFloat(a)).rounded()), UInt8((color.blue * CGFloat(a)).rounded()), a] }
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return ImportedImage(image: image, thumbnail: image, name: "Fixture")
    }

    @Test func globalFilterAffectsBelowButNotAbove() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        s.insert(try makeImage(width: 2, height: 2, color: .white, alpha: [255, 255, 255, 255]))

        var filterLayer = ImageLayer(name: "Invert Filter", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .invert)
        s.document?.layers.append(filterLayer)

        let inverted = try await rendered(s)
        #expect(inverted == [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255])

        // Add layer above filter: red in top-left pixel only
        s.insert(try makeImage(width: 2, height: 2, color: PaletteColor(red: 1, green: 0, blue: 0), alpha: [255, 0, 0, 0]))
        let withTop = try await rendered(s)
        #expect(Array(withTop[0..<4]) == [255, 0, 0, 255])
        #expect(Array(withTop[4..<8]) == [0, 0, 0, 255])
    }

    @Test func gaussianBlurRendersOnComposite() async throws {
        let s = EditorSession(); s.createDocument(width: 10, height: 2)
        // Left 5 columns black, right 5 columns white
        var alpha = [UInt8]()
        for _ in 0..<2 {
            for _ in 0..<5 { alpha.append(0) }
            for _ in 0..<5 { alpha.append(255) }
        }
        s.insert(try makeImage(width: 10, height: 2, color: .white, alpha: alpha))

        var filterLayer = ImageLayer(name: "Blur Filter", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .gaussianBlur, settings: LayerFilterSettings(from: FilterSettings(radius: 2)))
        s.document?.layers.append(filterLayer)

        let blurred = try await rendered(s)
        // Near column 5 (boundary between 4 and 5), pixels should have intermediate values
        let col4Alpha = blurred[(0 * 10 + 4) * 4 + 3]
        let col5Alpha = blurred[(0 * 10 + 5) * 4 + 3]
        #expect(col4Alpha > 10 && col4Alpha < 240, "Hard edge is softened by blur: alpha was \(col4Alpha)")
        #expect(col5Alpha > 10 && col5Alpha < 240, "Hard edge is softened by blur: alpha was \(col5Alpha)")
    }

    @Test func filterLayerOpacityAndMask() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        s.insert(try makeImage(width: 2, height: 2, color: .white, alpha: [255, 255, 255, 255]))

        var filterLayer = ImageLayer(name: "Invert Filter", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .invert)
        filterLayer.opacity = 0.5
        s.document?.layers.append(filterLayer)

        let semi = try await rendered(s)
        #expect(abs(Int(semi[0]) - 128) <= 2)
        #expect(abs(Int(semi[1]) - 128) <= 2)
        #expect(abs(Int(semi[2]) - 128) <= 2)
        #expect(semi[3] == 255)

        // Full opacity, but masked out (revealing: false)
        s.document?.layers[1].opacity = 1.0
        s.document?.layers[1].mask = LayerMask.solid(revealing: false)
        let masked = try await rendered(s)
        #expect(masked == [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255])
    }

    @Test func addFilterLayerAndUndoRedo() throws {
        let s = EditorSession(); s.createDocument(width: 10, height: 10)
        s.addFilterLayer(.gaussianBlur)
        let id = try #require(s.activeLayerID)
        let layer = try #require(s.activeLayer)
        #expect(layer.filter?.kind == .gaussianBlur)
        #expect(layer.isFilterLayer)
        #expect(s.filterEditingID == id)

        var updated = layer.filter!
        updated.settings.radius = 25
        s.beginEdit("Change Blur Radius")
        s.updateFilterLayer(id, value: updated)
        s.endEdit()

        #expect(s.activeLayer?.filter?.settings.radius == 25)

        s.undo()
        #expect(s.activeLayer?.filter?.settings.radius == 10)

        s.redo()
        #expect(s.activeLayer?.filter?.settings.radius == 25)

        // Undo back to empty document
        s.undo() // undo parameter edit
        s.undo() // undo layer creation
        #expect(s.document?.layers.isEmpty == true)

        s.redo() // redo layer creation
        #expect(s.document?.layers.count == 1)
        #expect(s.activeLayer?.filter?.kind == .gaussianBlur)
    }

    @Test func duplicateFilterLayer() throws {
        let s = EditorSession(); s.createDocument(width: 10, height: 10)
        s.addFilterLayer(.motionBlur)
        let id = try #require(s.activeLayerID)

        var custom = LayerFilter(kind: .motionBlur)
        custom.settings.angle = 45
        custom.settings.distance = 60
        s.updateFilterLayer(id, value: custom)
        s.filterEditingID = nil

        s.duplicateActiveLayer()
        #expect(s.document?.layers.count == 2)
        let duplicate = try #require(s.activeLayer)
        #expect(duplicate.id != id)
        #expect(duplicate.name == "Motion Blur copy")
        #expect(duplicate.isFilterLayer)
        #expect(duplicate.filter == custom)
        #expect(duplicate.filter?.settings.angle == 45)
        #expect(duplicate.filter?.settings.distance == 60)
    }

    @Test func filterLayerProjectSaveLoadRoundTrip() async throws {
        let s = EditorSession(); s.createDocument(width: 10, height: 10)
        s.addFilterLayer(.gaussianBlur)
        let id = try #require(s.activeLayerID)
        var custom = LayerFilter(kind: .gaussianBlur)
        custom.settings.radius = 18.5
        s.updateFilterLayer(id, value: custom)
        s.filterEditingID = nil

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FilterLayer-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try #require(s.projectSnapshot())
        #expect(snapshot.manifest.version == 9)
        try await ProjectStore.shared.save(snapshot, to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.manifest.version == 9)
        #expect(loaded.manifest.layers.last?.filter == custom)

        let restored = EditorSession()
        restored.installProject(loaded, from: url)
        #expect(restored.document?.layers.last?.filter == custom)
        #expect(restored.document?.layers.last?.isFilterLayer == true)
    }

    @Test func filterLayerLegacyManifestDecodesWithoutFilter() throws {
        let record = ProjectLayerRecord(
            id: UUID(),
            name: "Legacy Layer",
            isVisible: true,
            transform: LayerTransform(origin: .zero, size: CGSize(width: 100, height: 100)),
            imageFile: "test.png"
        )
        var manifest = ProjectManifest(documentID: UUID(), width: 100, height: 100, activeLayerID: nil, layers: [record])
        manifest.version = 8

        let data = try JSONEncoder().encode(manifest)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var layers = dict["layers"] as! [[String: Any]]
        layers[0].removeValue(forKey: "filter")
        dict["layers"] = layers
        let legacyData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(ProjectManifest.self, from: legacyData)
        #expect(decoded.version == 8)
        #expect(decoded.layers.first?.filter == nil)
    }

    @Test func filterLayerInvalidManifestRejects() async throws {
        let s = EditorSession(); s.createDocument(width: 10, height: 10)
        s.addFilterLayer(.gaussianBlur)
        s.filterEditingID = nil

        let snapshot = try #require(s.projectSnapshot())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FilterInvalid-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }

        // Test 1: Filter layer in older manifest version (< 9) is rejected
        var v8Manifest = snapshot.manifest
        v8Manifest.version = 8
        await #expect(throws: (any Error).self) {
            try await ProjectStore.shared.save(ProjectSnapshot(manifest: v8Manifest, images: [:]), to: url)
        }

        // Test 2: Invalid filter settings (negative radius) is rejected
        var invalidSettingsManifest = snapshot.manifest
        invalidSettingsManifest.layers[0].filter?.settings.radius = -10
        await #expect(throws: (any Error).self) {
            try await ProjectStore.shared.save(ProjectSnapshot(manifest: invalidSettingsManifest, images: [:]), to: url)
        }
    }

    @Test func filterLayerUIEditingLifecycleAndCancel() async throws {
        let s = EditorSession(); s.createDocument(width: 10, height: 10)
        s.addFilterLayer(.gaussianBlur)
        let id = try #require(s.activeLayerID)
        #expect(s.filterEditingID == id)

        // Begin UI editing session
        await s.beginFilterEditing(id)
        #expect(s.filterEdit != nil)
        #expect(s.filterEditingOriginal?.kind == .gaussianBlur)
        #expect(s.filterEdit?.kind == .gaussianBlur)

        // Update settings via UI filter edit
        var newSettings = FilterSettings()
        newSettings.radius = 42
        s.updateFilter(newSettings, preview: true)
        #expect(s.activeLayer?.filter?.settings.radius == 42)

        // Commit filter editing
        await s.commitFilter()
        #expect(s.filterEdit == nil)
        #expect(s.filterEditingID == nil)
        #expect(s.filterEditingOriginal == nil)
        #expect(s.activeLayer?.filter?.settings.radius == 42)

        // Re-open for editing
        s.filterEditingID = id
        await s.beginFilterEditing(id)
        #expect(s.filterEdit != nil)
        #expect(s.filterEdit?.settings.radius == 42)

        // Modify and cancel
        var cancelSettings = FilterSettings()
        cancelSettings.radius = 88
        s.updateFilter(cancelSettings, preview: true)
        #expect(s.activeLayer?.filter?.settings.radius == 88)

        s.cancelFilter()
        #expect(s.filterEdit == nil)
        #expect(s.filterEditingID == nil)
        #expect(s.filterEditingOriginal == nil)
        #expect(s.activeLayer?.filter?.settings.radius == 42) // Restored original!

        // Undo edit: reverts back to initial radius (10)
        s.undo()
        #expect(s.activeLayer?.filter?.settings.radius == 10)

        // Redo edit: restores 42
        s.redo()
        #expect(s.activeLayer?.filter?.settings.radius == 42)
    }

    @Test func filterLayerClippedToBaseSilhouette() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        // Base layer: only top-left pixel is opaque white, other 3 pixels transparent
        let baseAsset = try makeImage(width: 2, height: 2, color: .white, alpha: [255, 0, 0, 0])
        s.insert(baseAsset)
        let baseID = try #require(s.activeLayerID)

        // Filter layer clipped to base
        var filterLayer = ImageLayer(name: "Invert Filter", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .invert)
        filterLayer.maskSourceID = baseID
        s.document?.layers.append(filterLayer)

        let out = try await rendered(s)
        // Top-left pixel is inverted to black (0, 0, 0, 255)
        #expect(Array(out[0..<4]) == [0, 0, 0, 255])
        // Other 3 pixels remain transparent (alpha == 0)
        #expect(out[7] == 0)
        #expect(out[11] == 0)
        #expect(out[15] == 0)
    }

    @Test func filterLayerInsideGroupVisibilityToggle() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        s.insert(try makeImage(width: 2, height: 2, color: .white, alpha: [255, 255, 255, 255]))

        s.addGroup()
        let groupID = try #require(s.activeLayerID)

        s.addFilterLayer(.invert)
        s.filterEditingID = nil
        #expect(s.activeLayer?.parentID == groupID)

        // When group is visible, filter inverts white to black
        let inverted = try await rendered(s)
        #expect(inverted == [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255])

        // Hide group: filter should not be rendered, canvas returns to white
        s.toggleLayerVisibility(groupID)
        let original = try await rendered(s)
        #expect(original == [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255])

        // Show group again: filter is active again
        s.toggleLayerVisibility(groupID)
        let backToInverted = try await rendered(s)
        #expect(backToInverted == [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255])
    }

    @Test func multipleStackedFiltersSequential() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        s.insert(try makeImage(width: 2, height: 2, color: PaletteColor(red: 1, green: 0, blue: 0), alpha: [255, 255, 255, 255]))

        var filter1 = ImageLayer(name: "Invert 1", blankSize: s.document!.size)
        filter1.filter = LayerFilter(kind: .invert)
        s.document?.layers.append(filter1)

        // After one invert: red becomes cyan (0, 255, 255, 255)
        let cyan = try await rendered(s)
        #expect(Array(cyan[0..<4]) == [0, 255, 255, 255])

        var filter2 = ImageLayer(name: "Invert 2", blankSize: s.document!.size)
        filter2.filter = LayerFilter(kind: .invert)
        s.document?.layers.append(filter2)

        // After second invert: cyan becomes red again (255, 0, 0, 255)
        let redAgain = try await rendered(s)
        #expect(Array(redAgain[0..<4]) == [255, 0, 0, 255])
    }

    @Test func filterLayerBlendModeMultiply() async throws {
        let s = EditorSession(); s.createDocument(width: 2, height: 2)
        s.insert(try makeImage(width: 2, height: 2, color: PaletteColor(red: 0.5, green: 0.5, blue: 0.5), alpha: [255, 255, 255, 255]))

        var filterLayer = ImageLayer(name: "Invert Multiply", blankSize: s.document!.size)
        filterLayer.filter = LayerFilter(kind: .invert)
        filterLayer.blendMode = .multiply
        s.document?.layers.append(filterLayer)

        let out = try await rendered(s)
        // 128 inverted is 127; 128 * 127 / 255 ≈ 64
        #expect(abs(Int(out[0]) - 64) <= 2)
        #expect(abs(Int(out[1]) - 64) <= 2)
        #expect(abs(Int(out[2]) - 64) <= 2)
        #expect(out[3] == 255)
    }

    @Test func allElevenFilterKindsApplySmokeTest() throws {
        let baseImage = try #require(CGImage.makeSolidColor(width: 8, height: 8, color: CGColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1.0)))
        for kind in FilterLayerKind.allCases {
            var filter = LayerFilter(kind: kind)
            if kind == .grain { filter.settings.grain.seed = 12345 }
            let result = try filter.apply(baseImage)
            #expect(result.width == 8)
            #expect(result.height == 8)
        }
    }

    @Test func filterLayerPaintingGuardsAndMaskPainting() throws {
        let s = EditorSession()
        s.createDocument(width: 20, height: 20)
        s.addFilterLayer(.gaussianBlur)
        s.filterEditingID = nil
        let originalFilter = try #require(s.activeLayer?.filter)

        // 1. Without mask selected: cannot enter normal raster painting path
        s.isMaskSelected = false
        #expect(!s.canPaint)
        #expect(!s.canEditPixels)

        // Attempting to begin a brush does nothing
        s.tool = .brush
        s.beginBrush(at: CGPoint(x: 10, y: 10))
        #expect(s.brushStroke == nil)

        // Filter metadata remains intact, layer is not rasterized
        #expect(s.activeLayer?.filter == originalFilter)
        #expect(s.activeLayer?.asset == nil)
        #expect(s.activeLayer?.isFilterLayer == true)

        // 2. With a mask added and selected: mask painting is allowed through the mask path
        s.addLayerMask()
        s.isMaskSelected = true
        #expect(s.canPaint)
        #expect(s.canEditPixels)

        s.beginBrush(at: CGPoint(x: 10, y: 10))
        #expect(s.brushStroke != nil)
        s.cancelBrush()

        // Filter metadata still intact
        #expect(s.activeLayer?.filter == originalFilter)
        #expect(s.activeLayer?.asset == nil)
        #expect(s.activeLayer?.isFilterLayer == true)
    }

    @Test func filterLayerCannotBeClippingBase() throws {
        let s = EditorSession()
        s.createDocument(width: 20, height: 20)
        s.addBlankLayer()
        let baseID = try #require(s.activeLayerID)

        s.addFilterLayer(.invert)
        let filterID = try #require(s.activeLayerID)

        s.addBlankLayer()
        let topID = try #require(s.activeLayerID)

        // 1. Filter Layer can be clipped to a normal base layer
        #expect(s.canLinkMask(source: baseID, target: filterID))

        // 2. Filter Layer CANNOT be linked as the clipping source/base for top layer
        #expect(!s.canLinkMask(source: filterID, target: topID))

        // 3. canToggleClippingMask when top layer is above filter layer returns false
        s.selectLayer(topID)
        #expect(!s.canToggleClippingMask(topID))

        // 4. LiveMaskGraph validation rejects records with filter as source
        var records = s.document!.layers.map(\.hierarchyRecord)
        let topIndex = try #require(records.firstIndex(where: { $0.id == topID }))
        records[topIndex].maskSourceID = filterID
        #expect(throws: ProjectError.self) {
            try LiveMaskGraph.validate(records)
        }

        // 5. Existing Adjustment Layer restrictions remain unchanged
        s.addAdjustment(.levels)
        s.adjustmentEditingID = nil
        let adjID = try #require(s.activeLayerID)
        #expect(!s.canLinkMask(source: adjID, target: topID))

        // 6. Existing valid clipping relationships still work (top layer clipped to base layer)
        #expect(s.canLinkMask(source: baseID, target: topID))
    }
}

private extension CGImage {
    static func makeSolidColor(width: Int, height: Int, color: CGColor) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
