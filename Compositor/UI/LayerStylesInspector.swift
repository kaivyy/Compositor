import SwiftUI

struct LayerStylesInspector: View {
    @Bindable var session: EditorSession

    @State private var selectedTab: StyleTab = .stroke

    enum StyleTab: String, CaseIterable, Identifiable {
        case stroke = "Stroke"
        case outerGlow = "Outer Glow"
        case dropShadow = "Drop Shadow"
        case colorOverlay = "Color Overlay"
        var id: String { rawValue }
    }

    private var activeStyles: LayerStyles {
        session.activeLayer?.styles ?? LayerStyles()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Layer Styles").font(.headline)
                Spacer()
                Button("Done") {
                    session.showsStylesInspector = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if !session.canEditAppearance {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Select an image, shape, or text layer to edit Layer Styles.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    // Sidebar listing effects with checkboxes
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(StyleTab.allCases) { tab in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { isEffectEnabled(tab) },
                                    set: { toggleEffect(tab, enabled: $0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                                Button {
                                    selectedTab = tab
                                } label: {
                                    Text(tab.rawValue)
                                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(4)
                        }

                        Spacer()

                        Divider()

                        // Quick Presets
                        Text("Presets").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)

                        Button("Neon Cyan") {
                            applyNeonPreset(color: PaletteColor(red: 0, green: 0.94, blue: 1))
                        }
                        .buttonStyle(.link).padding(.horizontal, 8)

                        Button("Neon Pink") {
                            applyNeonPreset(color: PaletteColor(red: 1, green: 0.08, blue: 0.58))
                        }
                        .buttonStyle(.link).padding(.horizontal, 8)

                        Button("Clear All Styles") {
                            session.clearLayerStyles()
                        }
                        .buttonStyle(.link).foregroundStyle(.red).padding(.horizontal, 8)
                    }
                    .frame(width: 150)
                    .padding(8)

                    Divider()

                    // Detail editor for selected tab
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            switch selectedTab {
                            case .stroke:
                                strokeEditor
                            case .outerGlow:
                                outerGlowEditor
                            case .dropShadow:
                                dropShadowEditor
                            case .colorOverlay:
                                colorOverlayEditor
                            }
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 520, height: 400)
    }

    // MARK: - Effect Editors

    private var strokeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stroke").font(.subheadline.weight(.semibold))

            let stroke = activeStyles.stroke ?? StrokeEffect()

            HStack {
                Text("Size:")
                Slider(value: Binding(
                    get: { Double(stroke.size) },
                    set: { newSize in
                        var s = activeStyles
                        var e = s.stroke ?? StrokeEffect()
                        e.size = CGFloat(newSize)
                        e.isEnabled = true
                        s.stroke = e
                        session.setLayerStyles(s, actionName: "Stroke Size")
                    }
                ), in: 1...50, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Stroke Size") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(stroke.size)) px").monospacedDigit().frame(width: 45)
            }

            HStack {
                Text("Position:")
                Picker("", selection: Binding(
                    get: { stroke.position },
                    set: { newPos in
                        var s = activeStyles
                        var e = s.stroke ?? StrokeEffect()
                        e.position = newPos
                        s.stroke = e
                        session.setLayerStyles(s, actionName: "Stroke Position")
                    }
                )) {
                    ForEach(StrokePosition.allCases, id: \.self) { pos in
                        Text(pos.rawValue).tag(pos)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("Opacity:")
                Slider(value: Binding(
                    get: { stroke.opacity },
                    set: { newOp in
                        var s = activeStyles
                        var e = s.stroke ?? StrokeEffect()
                        e.opacity = newOp
                        s.stroke = e
                        session.setLayerStyles(s, actionName: "Stroke Opacity")
                    }
                ), in: 0...1, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Stroke Opacity") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(stroke.opacity * 100))%").monospacedDigit().frame(width: 45)
            }

            ColorPicker("Color:", selection: Binding(
                get: { stroke.color.swiftUIForPicker },
                set: { newColor in
                    guard let nsCol = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                    let pc = PaletteColor(red: nsCol.redComponent, green: nsCol.greenComponent, blue: nsCol.blueComponent)
                    var s = activeStyles
                    var e = s.stroke ?? StrokeEffect()
                    e.color = pc
                    s.stroke = e
                    session.setLayerStyles(s, actionName: "Stroke Color")
                }
            ), supportsOpacity: false)
        }
    }

    private var outerGlowEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Outer Glow").font(.subheadline.weight(.semibold))

            let glow = activeStyles.outerGlow ?? OuterGlowEffect()

            HStack {
                Text("Size (Blur):")
                Slider(value: Binding(
                    get: { Double(glow.size) },
                    set: { newSize in
                        var s = activeStyles
                        var e = s.outerGlow ?? OuterGlowEffect()
                        e.size = CGFloat(newSize)
                        e.isEnabled = true
                        s.outerGlow = e
                        session.setLayerStyles(s, actionName: "Outer Glow Size")
                    }
                ), in: 1...100, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Outer Glow Size") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(glow.size)) px").monospacedDigit().frame(width: 45)
            }

            HStack {
                Text("Spread:")
                Slider(value: Binding(
                    get: { glow.spread },
                    set: { newSpread in
                        var s = activeStyles
                        var e = s.outerGlow ?? OuterGlowEffect()
                        e.spread = newSpread
                        s.outerGlow = e
                        session.setLayerStyles(s, actionName: "Outer Glow Spread")
                    }
                ), in: 0...1, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Outer Glow Spread") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(glow.spread * 100))%").monospacedDigit().frame(width: 45)
            }

            HStack {
                Text("Opacity:")
                Slider(value: Binding(
                    get: { glow.opacity },
                    set: { newOp in
                        var s = activeStyles
                        var e = s.outerGlow ?? OuterGlowEffect()
                        e.opacity = newOp
                        s.outerGlow = e
                        session.setLayerStyles(s, actionName: "Outer Glow Opacity")
                    }
                ), in: 0...1, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Outer Glow Opacity") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(glow.opacity * 100))%").monospacedDigit().frame(width: 45)
            }

            ColorPicker("Color:", selection: Binding(
                get: { glow.color.swiftUIForPicker },
                set: { newColor in
                    guard let nsCol = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                    let pc = PaletteColor(red: nsCol.redComponent, green: nsCol.greenComponent, blue: nsCol.blueComponent)
                    var s = activeStyles
                    var e = s.outerGlow ?? OuterGlowEffect()
                    e.color = pc
                    s.outerGlow = e
                    session.setLayerStyles(s, actionName: "Outer Glow Color")
                }
            ), supportsOpacity: false)
        }
    }

    private var dropShadowEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drop Shadow").font(.subheadline.weight(.semibold))

            let shadow = activeStyles.dropShadow ?? DropShadowEffect()

            HStack {
                Text("Distance:")
                Slider(value: Binding(
                    get: { Double(shadow.distance) },
                    set: { newDist in
                        var s = activeStyles
                        var e = s.dropShadow ?? DropShadowEffect()
                        e.distance = CGFloat(newDist)
                        e.isEnabled = true
                        s.dropShadow = e
                        session.setLayerStyles(s, actionName: "Shadow Distance")
                    }
                ), in: 0...100, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Shadow Distance") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(shadow.distance)) px").monospacedDigit().frame(width: 45)
            }

            HStack {
                Text("Size (Blur):")
                Slider(value: Binding(
                    get: { Double(shadow.size) },
                    set: { newSize in
                        var s = activeStyles
                        var e = s.dropShadow ?? DropShadowEffect()
                        e.size = CGFloat(newSize)
                        s.dropShadow = e
                        session.setLayerStyles(s, actionName: "Shadow Size")
                    }
                ), in: 0...100, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Shadow Size") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(shadow.size)) px").monospacedDigit().frame(width: 45)
            }

            HStack {
                Text("Spread:")
                Slider(value: Binding(
                    get: { shadow.spread },
                    set: { newSpread in
                        var s = activeStyles
                        var e = s.dropShadow ?? DropShadowEffect()
                        e.spread = newSpread
                        s.dropShadow = e
                        session.setLayerStyles(s, actionName: "Shadow Spread")
                    }
                ), in: 0...1, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Shadow Spread") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(shadow.spread * 100))%").monospacedDigit().frame(width: 45)
            }

            HStack {
                Text("Angle:")
                Slider(value: Binding(
                    get: { Double(shadow.angle) },
                    set: { newAngle in
                        var s = activeStyles
                        var e = s.dropShadow ?? DropShadowEffect()
                        e.angle = CGFloat(newAngle)
                        s.dropShadow = e
                        session.setLayerStyles(s, actionName: "Shadow Angle")
                    }
                ), in: 0...360, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Shadow Angle") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(shadow.angle))°").monospacedDigit().frame(width: 45)
            }

            HStack {
                Text("Opacity:")
                Slider(value: Binding(
                    get: { shadow.opacity },
                    set: { newOp in
                        var s = activeStyles
                        var e = s.dropShadow ?? DropShadowEffect()
                        e.opacity = newOp
                        s.dropShadow = e
                        session.setLayerStyles(s, actionName: "Shadow Opacity")
                    }
                ), in: 0...1, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Shadow Opacity") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(shadow.opacity * 100))%").monospacedDigit().frame(width: 45)
            }

            ColorPicker("Color:", selection: Binding(
                get: { shadow.color.swiftUIForPicker },
                set: { newColor in
                    guard let nsCol = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                    let pc = PaletteColor(red: nsCol.redComponent, green: nsCol.greenComponent, blue: nsCol.blueComponent)
                    var s = activeStyles
                    var e = s.dropShadow ?? DropShadowEffect()
                    e.color = pc
                    s.dropShadow = e
                    session.setLayerStyles(s, actionName: "Shadow Color")
                }
            ), supportsOpacity: false)
        }
    }

    private var colorOverlayEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color Overlay").font(.subheadline.weight(.semibold))

            let overlay = activeStyles.colorOverlay ?? ColorOverlayEffect()

            HStack {
                Text("Opacity:")
                Slider(value: Binding(
                    get: { overlay.opacity },
                    set: { newOp in
                        var s = activeStyles
                        var e = s.colorOverlay ?? ColorOverlayEffect()
                        e.opacity = newOp
                        e.isEnabled = true
                        s.colorOverlay = e
                        session.setLayerStyles(s, actionName: "Overlay Opacity")
                    }
                ), in: 0...1, onEditingChanged: { editing in
                    if editing { session.beginStyleEdit("Overlay Opacity") }
                    else { session.finishStyleEdit() }
                })
                Text("\(Int(overlay.opacity * 100))%").monospacedDigit().frame(width: 45)
            }

            ColorPicker("Color:", selection: Binding(
                get: { overlay.color.swiftUIForPicker },
                set: { newColor in
                    guard let nsCol = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                    let pc = PaletteColor(red: nsCol.redComponent, green: nsCol.greenComponent, blue: nsCol.blueComponent)
                    var s = activeStyles
                    var e = s.colorOverlay ?? ColorOverlayEffect()
                    e.color = pc
                    s.colorOverlay = e
                    session.setLayerStyles(s, actionName: "Overlay Color")
                }
            ), supportsOpacity: false)
        }
    }

    // MARK: - Helpers

    private func isEffectEnabled(_ tab: StyleTab) -> Bool {
        switch tab {
        case .stroke: return activeStyles.stroke?.isEnabled == true
        case .outerGlow: return activeStyles.outerGlow?.isEnabled == true
        case .dropShadow: return activeStyles.dropShadow?.isEnabled == true
        case .colorOverlay: return activeStyles.colorOverlay?.isEnabled == true
        }
    }

    private func toggleEffect(_ tab: StyleTab, enabled: Bool) {
        var s = activeStyles
        switch tab {
        case .stroke:
            var e = s.stroke ?? StrokeEffect()
            e.isEnabled = enabled
            s.stroke = e
        case .outerGlow:
            var e = s.outerGlow ?? OuterGlowEffect()
            e.isEnabled = enabled
            s.outerGlow = e
        case .dropShadow:
            var e = s.dropShadow ?? DropShadowEffect()
            e.isEnabled = enabled
            s.dropShadow = e
        case .colorOverlay:
            var e = s.colorOverlay ?? ColorOverlayEffect()
            e.isEnabled = enabled
            s.colorOverlay = e
        }
        session.setLayerStyles(s, actionName: "Toggle \(tab.rawValue)")
    }

    private func applyNeonPreset(color: PaletteColor) {
        let neonStyles = LayerStyles(
            isEnabled: true,
            stroke: StrokeEffect(isEnabled: true, size: 3, position: .outside, color: color, opacity: 1.0, blendMode: .normal),
            outerGlow: OuterGlowEffect(isEnabled: true, color: color, opacity: 0.85, blendMode: .screen, size: 24, spread: 0.15),
            dropShadow: DropShadowEffect(isEnabled: true, color: color, opacity: 0.5, blendMode: .screen, angle: 90, distance: 0, size: 60, spread: 0),
            colorOverlay: nil
        )
        session.setLayerStyles(neonStyles, actionName: "Apply Neon Preset")
    }
}

