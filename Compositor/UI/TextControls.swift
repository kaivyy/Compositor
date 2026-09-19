import SwiftUI
import AppKit

struct TextControls: View {
    @Bindable var session: EditorSession
    @State private var showingCharacterPanel = false

    private let standardFontSizes: [Double] = [6, 8, 9, 10, 11, 12, 14, 18, 24, 30, 36, 48, 60, 72, 96, 120, 150, 200]

    var body: some View {
        HStack(spacing: 12) {
            Text("Type").font(ToolHeaderStyle.titleFont)

            // Searchable Font Family Picker
            SearchableFontPicker(selectedFamily: Binding(
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
            ))
            .frame(width: 140)
            .help("Font family; click to search and select")

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

            // Stroke popover button
            StrokeToolbarButton(session: session)

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

            if session.isEditingText {
                Divider().frame(height: 16)

                HStack(spacing: 6) {
                    Button {
                        session.cancelTextEdit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 20)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Cancel text edit (Esc)")

                    Button {
                        session.commitTextEdit()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(width: 22, height: 20)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Commit text edit (⌘-Return)")
                }
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
                SearchableFontPicker(selectedFamily: Binding(
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
                ))
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

            Divider()

            // Stroke Section
            VStack(spacing: 8) {
                HStack {
                    Text("Stroke").font(.caption.bold())
                    Spacer()
                    if session.textStrokeWidth > 0 {
                        Button("None") {
                            session.textStrokeWidth = 0
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.strokeWidth = 0 }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Width:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)

                        HStack(spacing: 4) {
                            TextField("0", value: Binding(
                                get: { session.textStrokeWidth },
                                set: { val in
                                    let v = max(0, min(100, val ?? 0))
                                    session.textStrokeWidth = v
                                    if session.activeLayer?.liveText != nil {
                                        session.updateActiveText { $0.strokeWidth = v }
                                    }
                                }
                            ), format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .unitSuffix("px")

                            Stepper("", value: Binding(
                                get: { session.textStrokeWidth },
                                set: { v in
                                    session.textStrokeWidth = v
                                    if session.activeLayer?.liveText != nil {
                                        session.updateActiveText { $0.strokeWidth = v }
                                    }
                                }
                            ), in: 0...100, step: 1)
                            .labelsHidden()
                        }
                    }

                    GridRow {
                        Text("Position:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("", selection: Binding(
                            get: { session.textStrokePosition },
                            set: { newPos in
                                session.textStrokePosition = newPos
                                if session.activeLayer?.liveText != nil {
                                    session.updateActiveText { $0.strokePosition = newPos }
                                }
                            }
                        )) {
                            ForEach(TextStrokePosition.allCases, id: \.self) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    GridRow {
                        Text("Color:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ColorPicker("", selection: Binding(
                                get: { Color(red: session.textStrokeRed, green: session.textStrokeGreen, blue: session.textStrokeBlue) },
                                set: { newColor in
                                    if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
                                        session.textStrokeRed = nsColor.redComponent
                                        session.textStrokeGreen = nsColor.greenComponent
                                        session.textStrokeBlue = nsColor.blueComponent
                                        if session.activeLayer?.liveText != nil {
                                            session.updateActiveText {
                                                $0.strokeRed = nsColor.redComponent
                                                $0.strokeGreen = nsColor.greenComponent
                                                $0.strokeBlue = nsColor.blueComponent
                                            }
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            Spacer()
                        }
                    }
                }
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

/// Popover toolbar button for quick stroke configuration (width, position, color).
struct StrokeToolbarButton: View {
    @Bindable var session: EditorSession
    @State private var showingStrokePopover = false

    var body: some View {
        Button {
            showingStrokePopover.toggle()
        } label: {
            let swatch = RoundedRectangle(cornerRadius: 3, style: .continuous)
            ZStack {
                if session.textStrokeWidth > 0 {
                    swatch
                        .strokeBorder(Color(red: session.textStrokeRed, green: session.textStrokeGreen, blue: session.textStrokeBlue), lineWidth: 3)
                        .background(swatch.fill(Color.black.opacity(0.2)))
                } else {
                    swatch
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                        .background(swatch.fill(Color.black.opacity(0.2)))
                        .overlay {
                            // Red diagonal slash for "No Stroke"
                            Path { p in
                                p.move(to: CGPoint(x: 4, y: 14))
                                p.addLine(to: CGPoint(x: 26, y: 4))
                            }
                            .stroke(Color.red.opacity(0.85), lineWidth: 1.5)
                        }
                }
            }
            .frame(width: 30, height: 18)
        }
        .buttonStyle(.plain)
        .help("Text stroke; click to configure width, position, and color")
        .popover(isPresented: $showingStrokePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Text Stroke").font(.headline)
                    Spacer()
                    if session.textStrokeWidth > 0 {
                        Button("None") {
                            session.textStrokeWidth = 0
                            if session.activeLayer?.liveText != nil {
                                session.updateActiveText { $0.strokeWidth = 0 }
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Width:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)

                        HStack(spacing: 4) {
                            TextField("0", value: Binding(
                                get: { session.textStrokeWidth },
                                set: { val in
                                    let v = max(0, min(100, val ?? 0))
                                    session.textStrokeWidth = v
                                    if session.activeLayer?.liveText != nil {
                                        session.updateActiveText { $0.strokeWidth = v }
                                    }
                                }
                            ), format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .unitSuffix("px")

                            Stepper("", value: Binding(
                                get: { session.textStrokeWidth },
                                set: { v in
                                    session.textStrokeWidth = v
                                    if session.activeLayer?.liveText != nil {
                                        session.updateActiveText { $0.strokeWidth = v }
                                    }
                                }
                            ), in: 0...100, step: 1)
                            .labelsHidden()
                        }
                    }

                    GridRow {
                        Text("Position:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("", selection: Binding(
                            get: { session.textStrokePosition },
                            set: { newPos in
                                session.textStrokePosition = newPos
                                if session.activeLayer?.liveText != nil {
                                    session.updateActiveText { $0.strokePosition = newPos }
                                }
                            }
                        )) {
                            ForEach(TextStrokePosition.allCases, id: \.self) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    GridRow {
                        Text("Color:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ColorPicker("", selection: Binding(
                                get: { Color(red: session.textStrokeRed, green: session.textStrokeGreen, blue: session.textStrokeBlue) },
                                set: { newColor in
                                    if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
                                        session.textStrokeRed = nsColor.redComponent
                                        session.textStrokeGreen = nsColor.greenComponent
                                        session.textStrokeBlue = nsColor.blueComponent
                                        if session.activeLayer?.liveText != nil {
                                            session.updateActiveText {
                                                $0.strokeRed = nsColor.redComponent
                                                $0.strokeGreen = nsColor.greenComponent
                                                $0.strokeBlue = nsColor.blueComponent
                                            }
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            Spacer()
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 270)
        }
    }
}

/// Searchable Font Family Picker popover that filters available system font families in real-time.
struct SearchableFontPicker: View {
    @Binding var selectedFamily: String
    var onSelect: ((String) -> Void)?

    @State private var isPresented = false
    @State private var searchQuery = ""

    private var filteredFamilies: [String] {
        let all = FontHelper.availableFamilies
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return all
        }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(selectedFamily)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 22)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 6) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    TextField("Search fonts...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

                Divider()

                // List of filtered fonts
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredFamilies, id: \.self) { family in
                            Button {
                                selectedFamily = family
                                isPresented = false
                                onSelect?(family)
                            } label: {
                                HStack {
                                    Text(family)
                                        .font(.custom(family, size: 13, relativeTo: .body))
                                        .lineLimit(1)
                                    Spacer()
                                    if family == selectedFamily {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(family == selectedFamily ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(width: 220, height: 260)
            }
            .padding(8)
            .onAppear {
                searchQuery = ""
            }
        }
    }
}

