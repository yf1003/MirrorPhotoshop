import SwiftUI
import AVFoundation

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = "对准 Mac 上的 PSD Mirror 二维码，识别后自动连接。"
    @State private var cameraFailed = false
    @State private var needsSettings = false
    var onPairing: (MirrorPairing) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                QRScannerCamera(onCode: { text in
                    guard let pairing = MirrorPairing.decode(text) else {
                        message = "这不是有效的 PSD Mirror 连接码，请扫描 Mac 应用窗口中的二维码。"
                        return false
                    }
                    onPairing(pairing)
                    return true
                }, onReady: {
                    message = "对准 Mac 上的 PSD Mirror 二维码，识别后自动连接。"
                    cameraFailed = false; needsSettings = false
                }, onError: { text, settings in
                    message = text; cameraFailed = true; needsSettings = settings
                }).ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: cameraFailed ? "camera.fill" : "viewfinder")
                        .font(.system(size: cameraFailed ? 58 : 220, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.85)).allowsHitTesting(false)
                    Text(message).multilineTextAlignment(.center).font(.callout)
                        .padding(18).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    if needsSettings {
                        Button("打开设置，允许相机访问") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.borderedProminent).tint(.cyan)
                    }
                    Spacer()
                }.padding(28)
            }
            .navigationTitle("扫码连接 Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

private struct QRScannerCamera: UIViewControllerRepresentable {
    var onCode: (String) -> Bool
    var onReady: () -> Void
    var onError: (String, Bool) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode; controller.onReady = onReady; controller.onError = onError
        return controller
    }
    func updateUIViewController(_ controller: QRScannerController, context: Context) {
        controller.onCode = onCode; controller.onReady = onReady; controller.onError = onError
    }
}

private final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Bool)?
    var onReady: (() -> Void)?
    var onError: ((String, Bool) -> Void)?
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "local.psdmirror.qr-camera")
    private var preview: AVCaptureVideoPreviewLayer!
    private var configured = false // Access only on captureQueue.
    private var visible = false // Access only on the main queue.
    private var didScan = false
    private var lastRejectedCode: String?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visible = true; didScan = false
        resume()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        pause()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func resume() {
        guard visible && !didScan else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.visible else { return }
                    if allowed { self.startCapture() }
                    else { self.onError?("请允许相机访问，以扫描 Mac 的连接二维码。", true) }
                }
            }
        case .denied, .restricted:
            onError?("相机访问未开启。请在系统设置中允许 PSD Mirror 使用相机，然后重新扫码。", true)
        @unknown default: onError?("当前无法访问相机，请稍后重新扫码。", false)
        }
    }

    @objc private func pause() {
        captureQueue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    private func startCapture() {
        captureQueue.async { [self] in
            if !configured {
                do {
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    session.sessionPreset = .high
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw ScannerError.unavailable
                    }
                    let input = try AVCaptureDeviceInput(device: camera)
                    let output = AVCaptureMetadataOutput()
                    guard session.canAddInput(input), session.canAddOutput(output) else { throw ScannerError.unavailable }
                    session.addInput(input); session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    guard output.availableMetadataObjectTypes.contains(.qr) else { throw ScannerError.unavailable }
                    output.metadataObjectTypes = [.qr]
                    configured = true
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.onError?("当前设备无法启动相机。请在实体 iPhone 上重新打开扫码。", false)
                    }
                    return
                }
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visible else { return }
                self.onReady?()
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard visible && !didScan else { return }
        for item in metadataObjects {
            guard let code = (item as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  code != lastRejectedCode else { continue }
            if onCode?(code) == true {
                didScan = true
                pause()
                return
            }
            lastRejectedCode = code
        }
    }

    private enum ScannerError: Error { case unavailable }
}
