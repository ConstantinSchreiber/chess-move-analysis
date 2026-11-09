import SwiftUI
import AVFoundation

/// Full-screen camera with a live board outline. Capturing hands the photo straight to recognition.
struct CameraScannerView: View {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var camera = CameraController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .overlay { BoardOutline(quad: camera.quad, frameAspect: camera.frameAspect) }
                .opacity(camera.isRunning ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: camera.isRunning)

            VStack {
                HStack {
                    CircleIconButton(systemName: "xmark", label: "Close", action: onCancel)
                    Spacer()
                    if camera.hasTorch {
                        CircleIconButton(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                         label: "Torch") { camera.toggleTorch() }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                Text(hint)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(camera.quad == nil ? Palette.textPrimary : Palette.onGold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(camera.quad == nil ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Palette.gold), in: Capsule())
                    .animation(.easeInOut(duration: 0.2), value: camera.quad == nil)
                    .padding(.bottom, 22)

                Button {
                    Haptics.move()
                    camera.capture { image in
                        if let image { onCapture(image) }
                    }
                } label: {
                    ZStack {
                        Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(camera.quad == nil ? Color.white : Palette.gold).frame(width: 64, height: 64)
                    }
                }
                .buttonStyle(PressableStyle())
                .disabled(camera.isCapturing)
                .accessibilityLabel("Take photo")
                .padding(.bottom, 24)
            }

            if case .denied = camera.authorization {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 34)).foregroundStyle(Palette.gold)
                    Text("Camera access is off")
                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text("Allow camera access in Settings to photograph a board, or choose a screenshot from Photos instead.")
                        .font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(Palette.textSecondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(GoldButtonStyle(height: 50))
                    .frame(maxWidth: 240)
                }
                .padding(32)
            }
        }
        .statusBarHidden()
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var hint: String {
        camera.quad == nil ? "Fit the whole board in view" : "Board found — tap to scan"
    }
}

/// Gold outline of the detected board. `quad` is normalised (0…1) to the camera frame, which the
/// preview shows with aspect-fill, so map through the same crop.
private struct BoardOutline: View {
    let quad: [CGPoint]?
    let frameAspect: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if let quad, quad.count == 4 {
                let size = proxy.size
                let scale = max(size.width / frameAspect, size.height)   // displayed frame height
                let frame = CGSize(width: scale * frameAspect, height: scale)
                let origin = CGPoint(x: (size.width - frame.width) / 2, y: (size.height - frame.height) / 2)
                let points = quad.map { CGPoint(x: origin.x + $0.x * frame.width, y: origin.y + $0.y * frame.height) }
                ZStack {
                    Path { path in
                        path.addLines(points)
                        path.closeSubpath()
                    }
                    .fill(Palette.gold.opacity(0.10))
                    Path { path in
                        path.addLines(points)
                        path.closeSubpath()
                    }
                    .stroke(Palette.gold, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                    .shadow(color: Palette.gold.opacity(0.7), radius: 8)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: quad)
        .allowsHitTesting(false)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Owns the capture session, runs the board detector on preview frames and captures photos.
@Observable
final class CameraController: NSObject, @unchecked Sendable {
    enum Authorization { case unknown, authorized, denied }

    @ObservationIgnored let session = AVCaptureSession()
    // UI state — only mutated on the main queue.
    private(set) var quad: [CGPoint]?
    private(set) var frameAspect: CGFloat = 3.0 / 4.0
    private(set) var isRunning = false
    private(set) var isCapturing = false
    private(set) var authorization = Authorization.unknown
    private(set) var hasTorch = false
    private(set) var torchOn = false

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "tempo.camera.session")
    @ObservationIgnored private let frameQueue = DispatchQueue(label: "tempo.camera.frames", qos: .userInitiated)
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var lastDetection = Date.distantPast
    @ObservationIgnored private var missedFrames = 0
    @ObservationIgnored private var photoCompletion: ((UIImage?) -> Void)?
    @ObservationIgnored private let ciContext = CIContext()
    @ObservationIgnored private var configured = false

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
        case .notDetermined:
            authorization = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        default:
            authorization = .denied
        }
        guard authorization == .authorized else { return }
        let started: Bool = await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.configureIfNeeded()
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.session.isRunning)
            }
        }
        isRunning = started
        hasTorch = device?.hasTorch ?? false
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func toggleTorch() {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        torchOn.toggle()
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
    }

    func capture(_ completion: @escaping (UIImage?) -> Void) {
        guard !isCapturing, isRunning else { return }
        isCapturing = true
        photoCompletion = completion
        sessionQueue.async {
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // Runs on sessionQueue.
    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .photo
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        self.device = device
        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            if (try? device.lockForConfiguration()) != nil {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                device.unlockForConfiguration()
            }
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        session.commitConfiguration()
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // ~8 detections per second is plenty for a steady outline.
        guard Date().timeIntervalSince(lastDetection) > 0.12,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDetection = Date()
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent),
              let frame = RGBAImage(image: UIImage(cgImage: cgImage), maxSide: 640) else { return }
        let corners = BoardRecognizer.shared.detectCornersForPreview(in: frame)
        let normalised = corners?.map { CGPoint(x: $0.x / CGFloat(frame.width), y: $0.y / CGFloat(frame.height)) }
        let aspect = CGFloat(frame.width) / CGFloat(frame.height)
        DispatchQueue.main.async {
            self.frameAspect = aspect
            if let normalised {
                self.missedFrames = 0
                self.quad = normalised
            } else {
                self.missedFrames += 1
                if self.missedFrames > 2 { self.quad = nil }
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            self.isCapturing = false
            self.photoCompletion?(image)
            self.photoCompletion = nil
        }
    }
}
