import SwiftUI

struct CollageSheet: View {
    let canvasSize: CGSize
    let finish: (CollageOptions?) -> Void

    @State private var preset: CollagePreset = .grid2x2
    @State private var rows: Int = 2
    @State private var columns: Int = 2
    @State private var spacing: Double = 12
    @State private var margin: Double = 12
    @State private var groupPerCell: Bool = true

    private var currentOptions: CollageOptions {
        CollageOptions(
            preset: preset,
            rows: rows,
            columns: columns,
            spacing: CGFloat(spacing),
            margin: CGFloat(margin),
            groupPerCell: groupPerCell
        )
    }

    private var cells: [CollageCellGeometry] {
        CollageGenerator.computeCells(for: canvasSize, options: currentOptions)
    }

    var body: some View { sheet.roundedControls() }

    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Collage Grid").font(.title2.bold())

            // Interactive Layout Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    GeometryReader { geo in
                        let scale = min((geo.size.width - 16) / canvasSize.width, (geo.size.height - 16) / canvasSize.height)
                        let renderW = canvasSize.width * scale
                        let renderH = canvasSize.height * scale
                        let offsetX = (geo.size.width - renderW) / 2
                        let offsetY = (geo.size.height - renderH) / 2

                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .border(Color.secondary.opacity(0.3), width: 1)

                            ForEach(cells, id: \.index) { cell in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.25))
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 1))
                                    .overlay(
                                        Text("\(cell.index)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                    )
                                    .frame(width: max(1, cell.rect.width * scale), height: max(1, cell.rect.height * scale))
                                    .offset(x: cell.rect.minX * scale, y: cell.rect.minY * scale)
                            }
                        }
                        .frame(width: renderW, height: renderH)
                        .offset(x: offsetX, y: offsetY)
                    }
                }
                .frame(height: 120)
            }

            Divider()

            Picker("Layout Preset", selection: $preset) {
                ForEach(CollagePreset.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }

            if preset == .customGrid {
                HStack(spacing: 20) {
                    Stepper("Rows: \(rows)", value: $rows, in: 1...10)
                    Stepper("Columns: \(columns)", value: $columns, in: 1...10)
                }
            }

            HStack {
                Text("Spacing").frame(width: 60, alignment: .leading)
                Slider(value: $spacing, in: 0...64, step: 1)
                Text("\(Int(spacing)) px").frame(width: 45, alignment: .trailing).foregroundStyle(.secondary)
            }

            HStack {
                Text("Margin").frame(width: 60, alignment: .leading)
                Slider(value: $margin, in: 0...64, step: 1)
                Text("\(Int(margin)) px").frame(width: 45, alignment: .trailing).foregroundStyle(.secondary)
            }

            Toggle("Group each cell (ready for photo clipping)", isOn: $groupPerCell)
                .font(.callout)

            Divider()

            HStack {
                Button("Cancel") { finish(nil) }
                    .configuredNativeShortcut(.escape)
                Spacer()
                Button("Create Collage") {
                    finish(currentOptions)
                }
                .configuredNativeShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
