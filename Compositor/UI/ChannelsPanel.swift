import SwiftUI

/// Panel for inspecting, viewing, and editing individual RGBA color and alpha channels.
struct ChannelsPanel: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { session.activeChannel }, set: { session.selectChannel($0) })) {
                ForEach(EditChannel.allCases) { channel in
                    channelRow(channel)
                        .tag(channel)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 180)

            Divider()

            HStack(spacing: 0) {
                Button { session.loadChannelAsSelection() } label: {
                    Image(systemName: "lasso").footerHitArea()
                }
                .help("Load channel as selection")
                .accessibilityLabel("Load channel as selection")
                .disabled(session.activeLayer == nil)

                Button { session.copyChannel() } label: {
                    Image(systemName: "doc.on.doc").footerHitArea()
                }
                .help("Copy channel to clipboard")
                .accessibilityLabel("Copy channel")
                .disabled(session.activeLayer == nil)

                Button { session.pasteChannel() } label: {
                    Image(systemName: "doc.on.clipboard").footerHitArea()
                }
                .help("Paste grayscale into channel")
                .accessibilityLabel("Paste into channel")
                .disabled(session.activeLayer == nil || session.activeChannel == .rgb)

                Button { session.invertChannel() } label: {
                    Image(systemName: "circle.righthalf.filled").footerHitArea()
                }
                .help("Invert channel")
                .accessibilityLabel("Invert channel")
                .disabled(session.activeLayer == nil || session.activeChannel == .rgb)

                Spacer()

                Menu {
                    Button("Fill Black (0)") { session.fillChannel(value: 0) }
                    Button("Fill 50% Gray (128)") { session.fillChannel(value: 128) }
                    Button("Fill White (255)") { session.fillChannel(value: 255) }
                } label: {
                    Image(systemName: "drop.fill").footerHitArea()
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Fill channel")
                .accessibilityLabel("Fill channel")
                .disabled(session.activeLayer == nil || session.activeChannel == .rgb)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private func channelRow(_ channel: EditChannel) -> some View {
        let isSelected = session.activeChannel == channel
        HStack(spacing: 10) {
            Image(systemName: channelIcon(channel))
                .foregroundStyle(channelColor(channel))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text(shortcutText(for: channel))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectChannel(channel)
        }
    }

    private func channelIcon(_ channel: EditChannel) -> String {
        switch channel {
        case .rgb: return "square.stack.3d.down.right.fill"
        case .red: return "r.square.fill"
        case .green: return "g.square.fill"
        case .blue: return "b.square.fill"
        case .alpha: return "a.square.fill"
        }
    }

    private func channelColor(_ channel: EditChannel) -> Color {
        switch channel {
        case .rgb: return .primary
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .alpha: return .secondary
        }
    }

    private func shortcutText(for channel: EditChannel) -> String {
        switch channel {
        case .rgb: return "⌘2"
        case .red: return "⌘3"
        case .green: return "⌘4"
        case .blue: return "⌘5"
        case .alpha: return "⌘6"
        }
    }
}
