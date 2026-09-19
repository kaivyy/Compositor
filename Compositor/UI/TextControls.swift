import SwiftUI
import AppKit

struct TextControls: View {
    @Bindable var session: EditorSession
    @State private var showingCharacterPanel = false

    private let standardFontSizes: [Double] = [6, 8, 9, 10, 11, 12, 14, 18, 24, 30, 36, 48, 60, 72, 96, 120, 150, 200]

    var body: some View {
        HStack(spacing: 12) {
            Text("Type").font(ToolHeaderStyle.titleFont)

            // Text content input
            HStack(spacing: 4) {
                TextField("Text", text: Binding(
                    get: { session.textContent },
                    set: { newText in
                        session.textContent = newText
                        if session.activeLayer?.liveText != nil {
                            session.updateActiveText(registerUndo: false) { $0.text = newText }
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            }
            .help("Edit text for the active text layer")

            // Font Family Picker
            Picker("Font Family", selection: Binding(
                get: { session.textFontFamily },
                set: { newFamily in
                    session.textFontFamily = newFamily
                    let styles = FontHelper.styles(for: newFamily)
                    if !styles.contains(session.textFontStyle) {
                        session.textFontStyle = styles.first ?? "Regular"
                    }
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText {
                            $0.fontFamily = newFamily
                            $0.fontStyle = session.textFontStyle
                        }
                    }
                }
            )) {
                ForEach(FontHelper.availableFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .frame(width: 130)
            .labelsHidden()
            .help("Font family")

            // Font Style / Weight Picker
            Picker("Font Style", selection: Binding(
                get: { session.textFontStyle },
                set: { newStyle in
                    session.textFontStyle = newStyle
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.fontStyle = newStyle }
                    }
                }
            )) {
                ForEach(FontHelper.styles(for: session.textFontFamily), id: \.self) { style in
                    Text(style).tag(style)
                }
            }
            .frame(width: 95)
            .labelsHidden()
            .help("Font style / weight")

            // Font Size
            HStack(spacing: 4) {
                TextField("Size", value: Binding(
                    get: { session.textFontSize },
                    set: { newSize in
                        let val = newSize ?? session.textFontSize
                        let clamped = min(500, max(1, val))
                        session.textFontSize = clamped
                        if session.activeLayer?.liveText != nil {
                            session.updateActiveText { $0.fontSize = clamped }
                        }
                    }
                ), format: .number.precision(.fractionLength(0)))
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .arrowSteps(value: { Double(session.textFontSize) },
                            change: {
                                let clamped = min(500, max(1, CGFloat($0)))
                                session.textFontSize = clamped
                                if session.activeLayer?.liveText != nil {
                                    session.updateActiveText { $0.fontSize = clamped }
                                }
                            })
                .unitSuffix("pt")

                Menu {
                    ForEach(standardFontSizes, id: \.self) { size in
                        Button("\(Int(size)) pt") {
                            session.textFontSize = CGFloat(size)
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.fontSize = CGFloat(size) }
                            }
                        }
                    }
                } label: {
                    EmptyView()
                }
                .menuStyle(.borderlessButton)
                .frame(width: 14)
            }
            .help("Font size in points")

            // Alignment
            Picker("Alignment", selection: Binding(
                get: { session.textAlignment },
                set: { newAlign in
                    session.textAlignment = newAlign
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.alignment = newAlign }
                    }
                }
            )) {
                ForEach(LayerTextAlignment.allCases, id: \.self) { align in
                    Image(systemName: align.icon).tag(align)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Text alignment")

            // Color Swatch
            HStack(spacing: 4) {
                Button {
                    session.openColorPicker(background: false)
                } label: {
                    let swatch = RoundedRectangle(cornerRadius: 3, style: .continuous)
                    swatch.fill(Color(nsColor: session.foregroundColor.nsColor))
                        .overlay { swatch.strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                        .frame(width: 30, height: 18)
                }
                .buttonStyle(.plain)
                .help("Text color; click to change")
            }

            // Button to open Photoshop Character & Paragraph Panel
            Button {
                showingCharacterPanel.toggle()
            } label: {
                Image(systemName: "character.textbox")
                    .font(.system(size: 14))
                    .frame(width: 24, height: 20)
                    .background(showingCharacterPanel ? Color.white.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Character & Paragraph panel")
            .popover(isPresented: $showingCharacterPanel, arrowEdge: .bottom) {
                CharacterParagraphPanel(session: session)
                    .frame(width: 280)
                    .padding(12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
        .onAppear {
            if session.activeLayer?.liveText != nil {
                session.loadTextStyleFromActiveLayer()
            }
        }
        .onChange(of: session.activeLayerID) { _, _ in
            if session.activeLayer?.liveText != nil {
                session.loadTextStyleFromActiveLayer()
            }
        }
        .onChange(of: session.foregroundColor) { _, newColor in
            if session.activeLayer?.liveText != nil {
                session.updateActiveText {
                    $0.red = newColor.red
                    $0.green = newColor.green
                    $0.blue = newColor.blue
                }
            }
        }
    }
}

/// Floating panel that replicates Photoshop's Character and Paragraph panel.
struct CharacterParagraphPanel: View {
    @Bindable var session: EditorSession
    @State private var selectedTab = 0

    private let standardFontSizes: [Double] = [6, 8, 9, 10, 11, 12, 14, 18, 24, 30, 36, 48, 60, 72, 96, 120, 150, 200]
    private let trackingPresets: [Double] = [-100, -75, -50, -25, -10, -5, 0, 5, 10, 25, 50, 75, 100, 200]

    var body: some View {
        VStack(spacing: 10) {
            // Header Tab: Character / Paragraph
            Picker("", selection: $selectedTab) {
                Text("Character").tag(0)
                Text("Paragraph").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            if selectedTab == 0 {
                characterTab
            } else {
                paragraphTab
            }
        }
    }

    private var characterTab: some View {
        VStack(spacing: 8) {
            // Font Family & Style pickers
            HStack(spacing: 6) {
                Picker("Family", selection: Binding(
                    get: { session.textFontFamily },
                    set: { newFamily in
                        session.textFontFamily = newFamily
                        let styles = FontHelper.styles(for: newFamily)
                        if !styles.contains(session.textFontStyle) {
                            session.textFontStyle = styles.first ?? "Regular"
                        }
                        if session.activeLayer?.liveText != nil {
                            session.updateActiveText {
                                $0.fontFamily = newFamily
                                $0.fontStyle = session.textFontStyle
                            }
                        }
                    }
                )) {
                    ForEach(FontHelper.availableFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Picker("Style", selection: Binding(
                    get: { session.textFontStyle },
                    set: { newStyle in
                        session.textFontStyle = newStyle
                        if session.activeLayer?.liveText != nil {
                            session.updateActiveText { $0.fontStyle = newStyle }
                        }
                    }
                )) {
                    ForEach(FontHelper.styles(for: session.textFontFamily), id: \.self) { style in
                        Text(style).tag(style)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Divider()

            // Row 1: Font Size (TT) & Leading (A/A)
            HStack(spacing: 12) {
                // Font Size
                HStack(spacing: 4) {
                    Text("Tᴛ").font(.system(size: 13, weight: .bold)).frame(width: 22)
                    TextField("Size", value: Binding(
                        get: { session.textFontSize },
                        set: { newSize in
                            let val = newSize ?? session.textFontSize
                            let clamped = min(500, max(1, val))
                            session.textFontSize = clamped
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.fontSize = clamped }
                            }
                        }
                    ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .unitSuffix("pt")
                }

                // Leading
                HStack(spacing: 4) {
                    Text("↕A").font(.system(size: 12, weight: .bold)).frame(width: 22)
                    if session.textLeadingAuto {
                        Button("(Auto)") {
                            session.textLeadingAuto = false
                            session.textLeading = ceil(session.textFontSize * 1.2)
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.leading = session.textLeading }
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    } else {
                        TextField("Leading", value: Binding(
                            get: { session.textLeading },
                            set: { val in
                                let v = val ?? session.textLeading
                                session.textLeading = v
                                if session.activeLayer?.liveText != nil {
                                    session.updateActiveText { $0.leading = v }
                                }
                            }
                        ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .unitSuffix("pt")
                        .contextMenu {
                            Button("Auto") {
                                session.textLeadingAuto = true
                                if session.activeLayer?.liveText != nil {
                                    session.updateActiveText { $0.leading = nil }
                                }
                            }
                        }
                    }
                }
            }

            // Row 2: Tracking (VA) & Kerning
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("V/A").font(.system(size: 11, weight: .bold)).frame(width: 22)
                    Text("Metrics").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 4) {
                    Text("VA").font(.system(size: 11, weight: .bold)).frame(width: 22)
                    TextField("Tracking", value: Binding(
                        get: { session.textTracking },
                        set: { val in
                            let v = val ?? 0
                            session.textTracking = v
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.tracking = v }
                            }
                        }
                    ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                }
            }

            // Row 3: Vertical Scale & Horizontal Scale
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("↕T").font(.system(size: 11, weight: .bold)).frame(width: 22)
                    TextField("V-Scale", value: Binding(
                        get: { session.textVerticalScale },
                        set: { val in
                            let v = val ?? 100
                            let clamped = min(500, max(10, v))
                            session.textVerticalScale = clamped
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.verticalScale = clamped }
                            }
                        }
                    ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .unitSuffix("%")
                }

                HStack(spacing: 4) {
                    Text("↔T").font(.system(size: 11, weight: .bold)).frame(width: 22)
                    TextField("H-Scale", value: Binding(
                        get: { session.textHorizontalScale },
                        set: { val in
                            let v = val ?? 100
                            let clamped = min(500, max(10, v))
                            session.textHorizontalScale = clamped
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.horizontalScale = clamped }
                            }
                        }
                    ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .unitSuffix("%")
                }
            }

            // Row 4: Baseline Shift & Color
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Aª").font(.system(size: 11, weight: .bold)).frame(width: 22)
                    TextField("Shift", value: Binding(
                        get: { session.textBaselineShift },
                        set: { val in
                            let v = val ?? 0
                            session.textBaselineShift = v
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.baselineShift = v }
                            }
                        }
                    ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .unitSuffix("pt")
                }

                HStack(spacing: 4) {
                    Text("Color:").font(.caption).foregroundStyle(.secondary)
                    Button {
                        session.openColorPicker(background: false)
                    } label: {
                        let swatch = RoundedRectangle(cornerRadius: 3, style: .continuous)
                        swatch.fill(Color(nsColor: session.foregroundColor.nsColor))
                            .overlay { swatch.strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                            .frame(height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Character style buttons row (Photoshop Toggles)
            HStack(spacing: 2) {
                styleToggleButton(title: "T", isSelected: session.textFauxBold, tooltip: "Faux Bold") {
                    session.textFauxBold.toggle()
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.isFauxBold = session.textFauxBold }
                    }
                }
                .font(.system(size: 12, weight: .bold))

                styleToggleButton(title: "T", isSelected: session.textFauxItalic, tooltip: "Faux Italic") {
                    session.textFauxItalic.toggle()
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.isFauxItalic = session.textFauxItalic }
                    }
                }
                .font(.system(size: 12, weight: .regular).italic())

                styleToggleButton(title: "TT", isSelected: session.textAllCaps, tooltip: "All Caps") {
                    session.textAllCaps.toggle()
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.isAllCaps = session.textAllCaps }
                    }
                }
                .font(.system(size: 11, weight: .bold))

                styleToggleButton(title: "Tᴛ", isSelected: session.textSmallCaps, tooltip: "Small Caps") {
                    session.textSmallCaps.toggle()
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.isSmallCaps = session.textSmallCaps }
                    }
                }
                .font(.system(size: 11, weight: .bold))

                styleToggleButton(title: "T¹", isSelected: session.textSuperscript, tooltip: "Superscript") {
                    session.textSuperscript.toggle()
                    if session.textSuperscript { session.textSubscript = false }
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText {
                            $0.isSuperscript = session.textSuperscript
                            $0.isSubscript = session.textSubscript
                        }
                    }
                }
                .font(.system(size: 11, weight: .regular))

                styleToggleButton(title: "T₁", isSelected: session.textSubscript, tooltip: "Subscript") {
                    session.textSubscript.toggle()
                    if session.textSubscript { session.textSuperscript = false }
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText {
                            $0.isSuperscript = session.textSuperscript
                            $0.isSubscript = session.textSubscript
                        }
                    }
                }
                .font(.system(size: 11, weight: .regular))

                styleToggleButton(title: "T", isSelected: session.textUnderline, tooltip: "Underline") {
                    session.textUnderline.toggle()
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.isUnderline = session.textUnderline }
                    }
                }
                .underline()
                .font(.system(size: 12, weight: .regular))

                styleToggleButton(title: "T", isSelected: session.textStrikethrough, tooltip: "Strikethrough") {
                    session.textStrikethrough.toggle()
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.isStrikethrough = session.textStrikethrough }
                    }
                }
                .strikethrough()
                .font(.system(size: 12, weight: .regular))
            }
        }
    }

    private var paragraphTab: some View {
        VStack(spacing: 8) {
            Text("Alignment").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Picker("Alignment", selection: Binding(
                get: { session.textAlignment },
                set: { newAlign in
                    session.textAlignment = newAlign
                    if session.activeLayer?.liveText != nil {
                        session.updateActiveText { $0.alignment = newAlign }
                    }
                }
            )) {
                ForEach(LayerTextAlignment.allCases, id: \.self) { align in
                    Image(systemName: align.icon).tag(align)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func styleToggleButton(title: String, isSelected: Bool, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(isSelected ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
