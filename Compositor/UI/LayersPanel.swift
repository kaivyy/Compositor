import SwiftUI

struct LayersPanel: View {
    @Bindable var session: EditorSession
    /// Dragging the panel's left edge sets it, within `widths`.
    var width: CGFloat = 252
    static let widths: ClosedRange<Double> = 202...352

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(session.document?.layers.count ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    .accessibilityIdentifier("layerCount")
            }.padding(18)
            Divider()
            LayerAppearanceControls(session: session, layerID: session.activeLayerID).id(session.activeLayerID)
            Divider()
            if let layers = session.document?.layers, !layers.isEmpty {
                NativeLayerList(session: session)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.3.layers.3d").font(.system(size: 25, weight: .light))
                    Text("No layers yet").font(.callout.weight(.medium))
                    Text(session.document == nil ? "Create a canvas or import an image." : "Import an image or add a blank layer.")
                        .font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary).padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            // No spacing: each button's hit area supplies it (8 pt either side makes the 16 pt gap).
            HStack(spacing: 0) {
                Button { session.addBlankLayer() } label: { Image(systemName: "plus.square").footerHitArea() }
                    .help("New blank layer (⇧⌘N)").accessibilityLabel("New blank layer")
                    .accessibilityIdentifier("addBlankLayer").disabled(!session.canEditLayers)
                Button { session.groupSelectedLayers() } label: { Image(systemName: "folder.badge.plus").footerHitArea() }
                    .help("Group selected layers (⌘G)").accessibilityLabel("New folder").disabled(!session.canEditLayers)
                LayerMaskMenu(session: session)
                Menu {
                    ForEach(AdjustmentKind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) { session.addAdjustment(kind) }
                    }
                } label: { Image(systemName: "circle.lefthalf.filled").footerHitArea() }
                    .menuStyle(.borderlessButton).fixedSize().help("New adjustment layer").disabled(!session.canEditLayers)
                Menu {
                    Button("Layer Styles...") { session.showsStylesInspector = true }
                    Divider()
                    Button("Neon Cyan Preset") {
                        let neonStyles = LayerStyles(
                            isEnabled: true,
                            stroke: StrokeEffect(isEnabled: true, size: 3, position: .outside, color: PaletteColor(red: 0, green: 0.94, blue: 1), opacity: 1.0, blendMode: .normal),
                            outerGlow: OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0.94, blue: 1), opacity: 0.85, blendMode: .screen, size: 24, spread: 0.15),
                            dropShadow: DropShadowEffect(isEnabled: true, color: PaletteColor(red: 0, green: 0.94, blue: 1), opacity: 0.5, blendMode: .screen, angle: 90, distance: 0, size: 60, spread: 0)
                        )
                        session.setLayerStyles(neonStyles, actionName: "Apply Neon Preset")
                    }
                    Button("Neon Pink Preset") {
                        let neonStyles = LayerStyles(
                            isEnabled: true,
                            stroke: StrokeEffect(isEnabled: true, size: 3, position: .outside, color: PaletteColor(red: 1, green: 0.08, blue: 0.58), opacity: 1.0, blendMode: .normal),
                            outerGlow: OuterGlowEffect(isEnabled: true, color: PaletteColor(red: 1, green: 0.08, blue: 0.58), opacity: 0.85, blendMode: .screen, size: 24, spread: 0.15),
                            dropShadow: DropShadowEffect(isEnabled: true, color: PaletteColor(red: 1, green: 0.08, blue: 0.58), opacity: 0.5, blendMode: .screen, angle: 90, distance: 0, size: 60, spread: 0)
                        )
                        session.setLayerStyles(neonStyles, actionName: "Apply Neon Preset")
                    }
                    Divider()
                    Button("Copy Layer Style") { session.copyLayerStyles() }.disabled(session.activeLayer?.styles == nil)
                    Button("Paste Layer Style") { session.pasteLayerStyles() }.disabled(session.copiedStyles == nil)
                    Button("Clear Layer Style") { session.clearLayerStyles() }.disabled(session.activeLayer?.styles == nil)
                } label: {
                    Text("fx").font(.system(size: 13, weight: .bold, design: .serif)).footerHitArea()
                }
                .menuStyle(.borderlessButton).fixedSize().help("Add a layer style (fx)").disabled(!session.canEditAppearance)
                Spacer()
                Button { session.deleteLayerOrMask() } label: { Image(systemName: "trash").footerHitArea() }
                    .help(session.isMaskSelected ? "Delete layer mask" : session.selectedLayerIDs.count > 1 ? "Delete selected layers" : "Delete selected layer")
                    .accessibilityLabel(session.isMaskSelected ? "Delete layer mask" : session.selectedLayerIDs.count > 1 ? "Delete selected layers" : "Delete selected layer")
                    .accessibilityIdentifier("deleteLayer")
                    .disabled(!session.canEditLayers || session.activeLayer == nil)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4) // Plus the hit areas' 8 and 12: the original 16.

        }
        .frame(width: width)
        .task(id: session.adjustmentEditingID) {
            if let id = session.adjustmentEditingID { await session.beginAdjustmentEditing(id) }
        }
    }

}

extension View {
    /// Makes a small footer icon easier to click. The padding is the clickable area, so the
    /// footer's own spacing is reduced to match and every icon keeps its old position.
    /// (Negative padding to hand the space back does not work: the button then only answers
    /// clicks inside its shrunken frame.)
    func footerHitArea() -> some View {
        padding(.horizontal, 8).padding(.vertical, 12)
            .contentShape(Rectangle())
    }
}

