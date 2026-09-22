import AppKit

extension EditorSession {
    /// Uses the ordinary filter editors, but sends their changes to layer metadata.
    /// The source is only for the preview; it never replaces layer pixels.
    func beginFilterEditing(_ id: UUID) async {
        guard filterEditingID == id, filterEditingOriginal == nil,
              filterEdit == nil,
              let snapshot = projectSnapshot(),
              let index = snapshot.manifest.layers.firstIndex(where: { $0.id == id }),
              let original = snapshot.manifest.layers[index].filter,
              original.kind.isEditable,
              let fKind = original.kind.filterKind else {
            filterEditingID = nil
            return
        }
        var manifest = snapshot.manifest
        // Keep records for live-mask references and group ancestry, but exclude the
        // filter layer itself and everything above it from the sampling image.
        let underneath = Set(LayerHierarchy.entries(manifest.layers).prefix { $0.layer.id != id }.map { $0.layer.id })
        for i in manifest.layers.indices where manifest.layers[i].isGroup != true && !underneath.contains(manifest.layers[i].id) {
            manifest.layers[i].isVisible = false
        }
        let source = ProjectSnapshot(manifest: manifest, images: snapshot.images, masks: snapshot.masks)
        do {
            let raster = try await ImageExporter.shared.render(source)
            guard !Task.isCancelled, filterEditingID == id, filterEditingOriginal == nil else { return }
            let asset = ImportedImage(image: raster.image, thumbnail: try PixelAdjust.thumbnail(of: raster.image), name: "Filter input")
            let layer = ImageLayer(asset: asset, origin: .zero)
            let settings = original.settings.toFilterSettings()
            filterEdit = try FilterEdit(kind: fKind, layer: layer, selection: nil, settings: settings)
            filterEditingOriginal = original
            beginEdit("Edit \(original.kind.rawValue) Filter")
        } catch {
            guard filterEditingID == id else { return }
            filterEditingID = nil
            brushError = error.localizedDescription
        }
    }

    private var editedFilter: LayerFilter? {
        guard var value = filterEditingOriginal, let filterEdit else { return nil }
        value.settings = LayerFilterSettings(from: filterEdit.settings, seed: value.settings.seed)
        return value
    }

    @discardableResult
    func previewFilterEditing(preview: Bool) -> Bool {
        guard let id = filterEditingID, let original = filterEditingOriginal,
              let value = editedFilter else { return false }
        updateFilterLayer(id, value: preview ? value : original)
        return true
    }

    /// OK keeps editable settings; Cancel (including the window close button) restores them.
    @discardableResult
    func finishFilterEditing(commit: Bool) -> Bool {
        guard let id = filterEditingID, let original = filterEditingOriginal else { return false }
        updateFilterLayer(id, value: commit ? (editedFilter ?? original) : original)
        filterEdit?.previewTask?.cancel()
        filterEdit = nil
        endEdit()
        filterEditingOriginal = nil
        filterEditingID = nil
        canvasFocusRequest += 1
        brushRevision += 1
        return true
    }
}
