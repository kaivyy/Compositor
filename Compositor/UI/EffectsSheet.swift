import SwiftUI

/// Unified Layer Effects inspector displaying all effects in one panel with enable/disable toggles,
/// controls, and live canvas preview.
struct EffectsSheet: View {
    @Bindable var session: EditorSession
    var kind: LayerEffectKind? = nil
    @State private var selectedKind: LayerEffectKind = .stroke

    static let inspectorOrder: [LayerEffectKind] = [
        .stroke, .outerGlow, .shadow, .innerGlow, .colorOverlay, .innerShadow
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Layer Effects").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.inspectorOrder, id: \.self) { effectKind in
                        effectSection(effectKind)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 480)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { session.finishEffectsEditing(commit: false) }
                    .configuredNativeShortcut(.escape)
                Button("OK") { session.finishEffectsEditing(commit: true) }
                    .configuredNativeShortcut(.return)
            }
        }
        .padding(18)
        .frame(width: 360)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            if let initial = kind ?? session.effectsEditing?.kind {
                selectedKind = initial
            }
        }
        // The picker previews its working color on the layer while it is open.
        .onChange(of: session.colorPicker?.color) { _, _ in session.previewEffectColor() }
    }

    @ViewBuilder private func effectSection(_ kind: LayerEffectKind) -> some View {
        let isEnabled = session.editingEffects.isEnabled(kind)
        let isSelected = selectedKind == kind

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: {
                    session.editingEffects.isEnabled(kind)
                }, set: { active in
                    toggleEffect(kind, enabled: active)
                }))
                .labelsHidden()
                .toggleStyle(.checkbox)

                Text(kind.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                Spacer()

                if isEnabled {
                    swatch(kind)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedKind = kind
                if !session.editingEffects.contains(kind) {
                    toggleEffect(kind, enabled: true)
                }
            }

            if isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    switch kind {
                    case .stroke: strokeControls
                    case .outerGlow: outerGlowControls
                    case .shadow: shadowControls
                    case .innerGlow: innerGlowControls
                    case .colorOverlay: colorOverlayControls
                    case .innerShadow: innerShadowControls
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 4)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }

    private func toggleEffect(_ kind: LayerEffectKind, enabled: Bool) {
        selectedKind = kind
        session.changeEffects { effects in
            if !effects.contains(kind) {
                switch kind {
                case .stroke:
                    var new = StrokeEffect()
                    new.red = session.backgroundColor.red
                    new.green = session.backgroundColor.green
                    new.blue = session.backgroundColor.blue
                    effects.stroke = new
                case .shadow:
                    effects.shadow = ShadowEffect()
                case .colorOverlay:
                    var new = ColorOverlayEffect()
                    new.red = session.backgroundColor.red
                    new.green = session.backgroundColor.green
                    new.blue = session.backgroundColor.blue
                    effects.colorOverlay = new
                case .innerShadow:
                    effects.innerShadow = InnerShadowEffect()
                case .outerGlow:
                    effects.outerGlow = OuterGlowEffect()
                case .innerGlow:
                    effects.innerGlow = InnerGlowEffect()
                }
            } else {
                effects.setEnabled(enabled, for: kind)
            }
        }
    }

    @ViewBuilder private var strokeControls: some View {
        if let effect = session.editingEffects.stroke {
            Picker("Position", selection: Binding(get: { effect.position }, set: { position in
                session.changeEffects { $0.stroke?.position = position }
            })) {
                Text("Outside").tag(StrokePosition.outside)
                Text("Center").tag(StrokePosition.center)
                Text("Inside").tag(StrokePosition.inside)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()

            blendModePicker(selection: Binding(get: { effect.blendMode }, set: { mode in
                session.changeEffects { $0.stroke?.blendMode = mode }
            }))
            slider("Size", value: Binding(get: { effect.size }, set: { size in
                session.changeEffects { $0.stroke?.size = size }
            }), range: 0...20, inputRange: 0...StrokeEffect.maxSize, unit: "px")
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.stroke?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    @ViewBuilder private var shadowControls: some View {
        if let effect = session.editingEffects.shadow {
            blendModePicker(selection: Binding(get: { effect.blendMode }, set: { mode in
                session.changeEffects { $0.shadow?.blendMode = mode }
            }))
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.shadow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            slider("Angle", value: Binding(get: { effect.angle }, set: { angle in
                session.changeEffects { $0.shadow?.angle = angle }
            }), range: -180...180, unit: "°")
            slider("Distance", value: Binding(get: { effect.distance }, set: { distance in
                session.changeEffects { $0.shadow?.distance = distance }
            }), range: 0...100, inputRange: 0...5000, unit: "px")
            slider("Spread", value: Binding(get: { effect.spread }, set: { spread in
                session.changeEffects { $0.shadow?.spread = spread }
            }), range: 0...50, inputRange: 0...500, unit: "px")
            slider("Blur", value: Binding(get: { effect.blur }, set: { blur in
                session.changeEffects { $0.shadow?.blur = blur }
            }), range: 0...100, inputRange: 0...500, unit: "px")
        }
    }

    @ViewBuilder private var colorOverlayControls: some View {
        if let effect = session.editingEffects.colorOverlay {
            blendModePicker(selection: Binding(get: { effect.blendMode }, set: { mode in
                session.changeEffects { $0.colorOverlay?.blendMode = mode }
            }))
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.colorOverlay?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    @ViewBuilder private var innerShadowControls: some View {
        if let effect = session.editingEffects.innerShadow {
            blendModePicker(selection: Binding(get: { effect.blendMode }, set: { mode in
                session.changeEffects { $0.innerShadow?.blendMode = mode }
            }))
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.innerShadow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            slider("Angle", value: Binding(get: { effect.angle }, set: { angle in
                session.changeEffects { $0.innerShadow?.angle = angle }
            }), range: -180...180, unit: "°")
            slider("Distance", value: Binding(get: { effect.distance }, set: { distance in
                session.changeEffects { $0.innerShadow?.distance = distance }
            }), range: 0...50, inputRange: 0...5000, unit: "px")
            slider("Choke", value: Binding(get: { effect.choke }, set: { choke in
                session.changeEffects { $0.innerShadow?.choke = choke }
            }), range: 0...50, inputRange: 0...500, unit: "px")
            slider("Blur", value: Binding(get: { effect.blur }, set: { blur in
                session.changeEffects { $0.innerShadow?.blur = blur }
            }), range: 0...100, inputRange: 0...500, unit: "px")
        }
    }

    @ViewBuilder private var outerGlowControls: some View {
        if let effect = session.editingEffects.outerGlow {
            blendModePicker(selection: Binding(get: { effect.blendMode }, set: { mode in
                session.changeEffects { $0.outerGlow?.blendMode = mode }
            }))
            slider("Size", value: Binding(get: { effect.size }, set: { size in
                session.changeEffects { $0.outerGlow?.size = size }
            }), range: 0...100, inputRange: 0...500, unit: "px")
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.outerGlow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    @ViewBuilder private var innerGlowControls: some View {
        if let effect = session.editingEffects.innerGlow {
            blendModePicker(selection: Binding(get: { effect.blendMode }, set: { mode in
                session.changeEffects { $0.innerGlow?.blendMode = mode }
            }))
            slider("Size", value: Binding(get: { effect.size }, set: { size in
                session.changeEffects { $0.innerGlow?.size = size }
            }), range: 0...100, inputRange: 0...500, unit: "px")
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.innerGlow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    private func blendModePicker(title: String = "Mode", selection: Binding<LayerBlendMode>) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 64, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(LayerBlendMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The effect's color, opened in the app's own picker.
    private func swatch(_ kind: LayerEffectKind) -> some View {
        let color = session.editingEffects.color(kind)
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Button { session.openEffectColorPicker(kind) } label: {
            shape.fill(Color(red: Double(color?.red ?? 0), green: Double(color?.green ?? 0), blue: Double(color?.blue ?? 0)))
                .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1) }
                .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                .frame(width: 36, height: 18)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(kind.rawValue + " color")
        .accessibilityLabel(kind.rawValue + " color")
    }

    private func slider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>,
                        inputRange: ClosedRange<CGFloat>? = nil, unit: String) -> some View {
        let limits = inputRange ?? range
        let setAmount: (Double) -> Void = { amount in
            guard amount.isFinite else { return }
            value.wrappedValue = min(limits.upperBound, max(limits.lowerBound, CGFloat(amount)))
        }
        return HStack(spacing: 10) {
            Text(title).frame(width: 64, alignment: .leading)
            // A manually entered larger value stays intact; only the thumb is pinned
            // to the end of the slider until the user drags it again.
            Slider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, value.wrappedValue)) },
                                  set: { value.wrappedValue = $0 }), in: range).frame(width: 130)
            TextField(title, value: Binding(get: { Double(value.wrappedValue) },
                                            set: setAmount),
                      format: .number.precision(.fractionLength(0)))
                .frame(width: 48).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .arrowSteps(value: { Double(value.wrappedValue) },
                            change: setAmount)
                .unitSuffix(unit)
        }
    }
}
