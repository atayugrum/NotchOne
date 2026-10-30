import AppKit
import SwiftUI
@preconcurrency import Translation

/// Whether a language pair can be used right away.
enum LanguageStatus: Equatable, Sendable {
    case installed
    case downloadable
    case unsupported
}

/// Downloads language packs. macOS shows its download prompt only for a regular window,
/// not for the notch panel, so a small window opens just for that and closes again.
@MainActor
enum LanguageDownloader {
    private static var window: NSWindow?

    static func status(_ pair: TranslationPair) async -> LanguageStatus {
        if TranslateLogic.isSame(pair.source, pair.target) { return .installed }
        return await Translator.availability(pair)
    }

    static func download(_ pair: TranslationPair, done: @escaping @MainActor () -> Void) {
        guard #available(macOS 15.0, *) else { return done() }
        window?.close()
        let view = LanguageDownloadView(pair: pair) {
            window?.close()
            window = nil
            done()
        }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 380, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Download Languages")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

@available(macOS 15.0, *)
private struct LanguageDownloadView: View {
    let pair: TranslationPair
    let finish: @MainActor () -> Void
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Getting \(TranslateLogic.displayName(pair.source)) and \(TranslateLogic.displayName(pair.target)) ready")
                .font(.headline)
            Text("macOS downloads these languages once, so translation works on this Mac without the internet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ProgressView().controlSize(.small)
                Spacer()
                Button("Cancel", role: .cancel) { finish() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 380)
        .onAppear {
            configuration = TranslationSession.Configuration(source: pair.source, target: pair.target)
        }
        .translationTask(configuration) { session in
            try? await session.prepareTranslation()
            finish()
        }
    }
}
