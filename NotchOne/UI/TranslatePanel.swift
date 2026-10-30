import SwiftUI

/// Translate tab: pick the languages, type or paste on the left, read on the right.
/// ⌃⌥T fills it with the selection from any app.
struct TranslatePanel: View {
    @Bindable var store: TranslateStore
    let model: NotchViewModel
    @AppStorage(SettingsKey.translateFrom) private var from = SettingsDefault.translateFrom
    @AppStorage(SettingsKey.translateTo) private var to = SettingsDefault.translateTo
    @FocusState private var inputFocused: Bool
    @State private var copied = false

    var body: some View {
        VStack(spacing: Space.s) {
            if #unavailable(macOS 26.0) {
                if #available(macOS 15.0, *) { SessionTranslationHost() }
            }
            HStack(spacing: Space.s) {
                LanguageMenu(title: "From", selection: from, languages: store.languages, includesDetect: true) {
                    store.setFrom($0)
                }
                IconButton(symbol: "arrow.left.arrow.right", size: 11, frame: 26, label: "Swap languages") { store.swap() }
                    .help("Swap languages")
                LanguageMenu(title: "To", selection: to, languages: store.languages, includesDetect: false) {
                    store.setTo($0)
                }
                Spacer(minLength: 0)
                if !store.history.isEmpty {
                    historyMenu
                }
                if case .done = store.state {
                    PillButton(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc") {
                        store.copyResult()
                        copied = true
                    }
                }
                if !store.input.isEmpty {
                    IconButton(symbol: "xmark", size: 10, frame: 24, label: "Clear") {
                        store.clear()
                        inputFocused = true
                    }
                    .help("Clear")
                }
            }

            HStack(spacing: Space.s) {
                TextField("Type or paste text. \(HotKey.translate.display) translates the selection in any app.",
                          text: $store.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .focused($inputFocused)
                    .onSubmit { store.translateInput() }
                    .onKeyPress(.escape) {
                        model.close()
                        return .handled
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .glassCard()
                    .contentShape(Rectangle())
                    .onTapGesture { inputFocused = true }

                ResultView(state: store.state)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .glassCard()
            }
        }
        .task { await store.loadLanguages() }
        // Translates once typing pauses; Return does it right away.
        .task(id: store.input) {
            copied = false
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            store.translateInput()
        }
        .onChange(of: model.focusRequest) { inputFocused = true }
    }

    private var historyMenu: some View {
        Menu {
            ForEach(store.history) { entry in
                Button {
                    store.restore(entry)
                } label: {
                    Text("\(ClipboardLogic.preview(entry.source, limit: 40)) → \(ClipboardLogic.preview(entry.result, limit: 40))")
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(Typo.icon(11))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Recent translations")
    }
}

/// A language menu shaped like a pill: "From: Detect", "To: Türkçe".
private struct LanguageMenu: View {
    let title: LocalizedStringKey
    let selection: String
    let languages: [(id: String, name: String)]
    let includesDetect: Bool
    let choose: (String) -> Void

    var body: some View {
        Menu {
            if includesDetect {
                Button("Detect language") { choose(TranslateLogic.auto) }
                Divider()
            }
            ForEach(languages, id: \.id) { language in
                Button(language.name) { choose(language.id) }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text(title).foregroundStyle(.secondary)
                Text(TranslateLogic.displayName(selection))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .font(Typo.captionStrong)
            .padding(.horizontal, Space.s + 2)
            .frame(height: 26)
            .background(Palette.control, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("\(Text(title)) \(TranslateLogic.displayName(selection))"))
    }
}

private struct ResultView: View {
    let state: TranslationState?

    var body: some View {
        switch state {
        case nil:
            Text("The translation shows here.")
                .font(Typo.body)
                .foregroundStyle(.tertiary)
        case .reading:
            status("Reading the selection…")
        case .working:
            status("Translating…")
        case .done(_, let result, let from, let to):
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("\(from) → \(to)").font(Typo.micro).foregroundStyle(.secondary)
                ScrollView(.vertical, showsIndicators: false) {
                    Text(result)
                        .font(.system(size: 14, weight: .medium))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .needsDownload(_, let languages):
            VStack(alignment: .leading, spacing: Space.s) {
                Text("\(languages) need to be downloaded once for on-device translation.")
                    .font(Typo.body)
                PillButton(title: "Download in Settings…", symbol: "arrow.down.circle") {
                    SettingsOpener.open(page: .translate)
                }
            }
        case .failed(let message):
            Text(message).font(Typo.body).foregroundStyle(.secondary)
        }
    }

    private func status(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: Space.s) {
            SpinnerView(tint: .white).frame(width: 12, height: 12)
            Text(text).font(Typo.caption).foregroundStyle(.secondary)
        }
    }
}
