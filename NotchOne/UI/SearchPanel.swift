import SwiftUI

/// Search tab (⌃⌥K): one box over clipboard history, shelf files and tabs.
struct SearchPanel: View {
    let model: NotchViewModel

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        let activity = model.activity
        let results = PaletteLogic.results(
            query: query,
            clipboard: activity.clipboard.items,
            shelf: activity.shelf.items,
            tabs: model.tabs,
            keepAwakeIsOn: activity.keepAwake.isOn
        )
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard, shelf and tabs", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($focused)
                    .onSubmit { run(results) }
                    .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                        guard press.modifiers == .command,
                              let tab = press.characters.first.flatMap({ PaletteLogic.tab(forDigit: $0, in: model.barTabs) })
                        else { return .ignored }
                        withAnimation(Motion.tab) { model.show(tab) }
                        return .handled
                    }
                    .onKeyPress(.downArrow) { move(1, count: results.count) }
                    .onKeyPress(.upArrow) { move(-1, count: results.count) }
                    .onKeyPress(.escape) {
                        model.close()
                        return .handled
                    }
                Text(HotKey.palette.display).font(Typo.micro).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Space.m)
            .frame(height: 32)
            .glassCard(radius: Radius.s + 2)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        row(result, isSelected: index == selection)
                            .onTapGesture {
                                selection = index
                                run(results)
                            }
                    }
                    if results.isEmpty {
                        Text(query.isEmpty ? "Nothing copied yet" : "No matches")
                            .font(Typo.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, Space.s)
                    }
                }
            }
        }
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { focused = true }
        .onChange(of: query) { selection = 0 }
    }

    private func perform(_ command: PaletteCommand) {
        let activity = model.activity
        switch command {
        case .keepAwake: activity.toggleKeepAwake()
        case .playPause: activity.player?.perform(.playPause)
        case .nextTrack: activity.player?.perform(.next)
        case .clearClipboard: activity.clipboard.clear()
        case .editHome:
            model.show(.home)
            model.isEditingHome = true
        case .settings: model.openSettings(.general)
        }
    }

    private func row(_ result: PaletteResult, isSelected: Bool) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: result.symbol)
                .font(Typo.icon(11))
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(result.title).font(Typo.body).lineLimit(1)
            Spacer(minLength: Space.s)
            Text(result.subtitle).font(Typo.micro).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.horizontal, Space.s)
        .frame(height: 26)
        .background(isSelected ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }

    private func move(_ step: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .handled }
        selection = (selection + step + count) % count
        return .handled
    }

    private func run(_ results: [PaletteResult]) {
        guard results.indices.contains(selection) else { return }
        let activity = model.activity
        withAnimation(Motion.tab) {
            switch results[selection].kind {
            case .clipboard(let id):
                if let item = activity.clipboard.items.first(where: { $0.id == id }) {
                    activity.clipboard.copy(item)
                    activity.live.handle(.say(text: String(localized: "Copied")))
                }
            case .shelf(let url):
                activity.shelf.open(url)
                model.close()
            case .tab(let tab):
                model.show(tab)
            case .command(let command):
                perform(command)
            case .translateClipboard:
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    activity.translate.translate(text)
                    model.show(.translate)
                } else {
                    activity.live.handle(.say(text: String(localized: "The clipboard has no text")))
                }
            }
        }
    }
}
