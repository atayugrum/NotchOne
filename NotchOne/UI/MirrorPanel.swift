import AVFoundation
import SwiftUI

/// Mirror tab: a live camera preview. The camera runs only while this tab is on screen;
/// permission is asked the first time it's opened.
struct MirrorPanel: View {
    let activity: ActivityState
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch status {
            case .authorized:
                CameraPreview { running in activity.isUsingCamera = running }
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notDetermined:
                message("Check yourself before a call.", button: "Turn On Camera") {
                    Task {
                        SystemPromptWatcher.expectPrompt()
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        status = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            default:
                message("NotchOne doesn't have camera access.", button: "Open Privacy Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func message(_ text: LocalizedStringKey, button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: Space.s) {
            Image(systemName: "person.crop.square")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text).font(Typo.body).foregroundStyle(.secondary)
            PillButton(title: button, action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
}

/// AVFoundation preview layer that starts when shown and stops when removed.
private struct CameraPreview: NSViewRepresentable {
    let onRunningChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.onRunningChange = onRunningChange
        return view
    }

    func updateNSView(_ view: CameraPreviewNSView, context: Context) {}
}

/// Owns the capture session; all session calls happen on its own queue.
private final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.atayug.notchone.camera")
    private var configured = false

    func start(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if !configured {
                configured = true
                session.beginConfiguration()
                session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
            }
            guard !session.inputs.isEmpty else {
                completion(false)
                return
            }
            session.startRunning()
            completion(session.isRunning)
        }
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            session.stopRunning()
            completion()
        }
    }
}

private final class CameraPreviewNSView: NSView {
    var onRunningChange: (@MainActor (Bool) -> Void)?
    private let camera = CameraSession()
    private let preview: AVCaptureVideoPreviewLayer

    override init(frame frameRect: NSRect) {
        preview = AVCaptureVideoPreviewLayer(session: camera.session)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        // A mirror shows you flipped, like a real one.
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Mark the camera as ours before it starts, so meeting mode ignores it.
            onRunningChange?(true)
            let callback = onRunningChange
            camera.start { running in
                guard !running else { return }
                Task { @MainActor in callback?(false) }
            }
        } else {
            let callback = onRunningChange
            camera.stop {
                Task { @MainActor in callback?(false) }
            }
        }
    }
}
