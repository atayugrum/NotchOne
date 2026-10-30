import SwiftUI
@preconcurrency import Translation

/// macOS 15 hands out a translation session only to a SwiftUI view; macOS 26 can make one
/// anywhere. On 15…25 requests wait here for `SessionTranslationHost` in the Translate tab.
@MainActor
@Observable
final class SessionTranslation {
    struct Request: Identifiable {
        let id = UUID()
        let text: String
        let pair: TranslationPair
    }

    static let shared = SessionTranslation()

    private(set) var request: Request?
    @ObservationIgnored private var continuation: CheckedContinuation<String, Error>?
    /// The Translate tab can be closed before an answer comes.
    private static let timeout: Duration = .seconds(20)

    func translate(_ text: String, pair: TranslationPair) async throws -> String {
        finish(.failure(CancellationError()))
        let request = Request(text: text, pair: pair)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.request = request
            Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                if self?.request?.id == request.id { self?.finish(.failure(CancellationError())) }
            }
        }
    }

    func finish(_ result: Result<String, Error>) {
        request = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}

/// Invisible. Runs the waiting request with the session its view is given.
@available(macOS 15.0, *)
struct SessionTranslationHost: View {
    private let queue = SessionTranslation.shared
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: queue.request?.id, initial: true) { prepare() }
            .translationTask(configuration) { session in
                guard let request = queue.request else { return }
                do {
                    let response = try await session.translate(request.text)
                    queue.finish(.success(response.targetText))
                } catch {
                    queue.finish(.failure(error))
                }
            }
    }

    private func prepare() {
        guard let pair = queue.request?.pair else { return }
        if configuration?.source == pair.source, configuration?.target == pair.target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: pair.source, target: pair.target)
        }
    }
}
