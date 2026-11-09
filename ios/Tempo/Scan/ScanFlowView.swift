import SwiftUI
import PhotosUI
import ChessCore

/// The scan sheet: pick a source → recognise → review → analyse.
struct ScanFlowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ScanReview] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showSamples = false
    @State private var processing: UIImage?
    @State private var failure: (image: UIImage, message: String)?
    @State private var clipboardHasImage = UIPasteboard.general.hasImages

    var body: some View {
        NavigationStack(path: $path) {
            options
                .navigationDestination(for: ScanReview.self) { review in
                    ScanReviewView(review: review, onBack: { path.removeLast() }, onClose: { dismiss() })
                        .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(Palette.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { recognize(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    recognize(image)
                }
                photoItem = nil
            }
        }
        .onAppear {
            if let image = app.pendingScanImage {
                app.pendingScanImage = nil
                recognize(image)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboardHasImage = UIPasteboard.general.hasImages
        }
    }

    // MARK: Options

    private var options: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SheetHeader(title: "Scan position", onClose: { dismiss() })
                        .padding(.bottom, 2)
                    Text("Capture the whole board — all four corners visible. Works with screens, screenshots and printed diagrams.")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.bottom, 10)

                    HStack(spacing: 12) {
                        Button { showCamera = true } label: {
                            SourceCard(icon: "camera", title: "Camera", subtitle: "Photograph a screen")
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            SourceCard(icon: "photo.on.rectangle.angled", title: "Photos", subtitle: "Screenshot or picture")
                        }
                        .buttonStyle(PressableStyle())
                    }

                    Button(action: pasteImage) {
                        SourceRow(icon: "doc.on.clipboard", title: "Paste image",
                                  subtitle: clipboardHasImage ? "Use the image on your clipboard" : "Copy a screenshot first")
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!clipboardHasImage)
                    .opacity(clipboardHasImage ? 1 : 0.5)

                    Button { showSamples = true } label: {
                        SourceRow(icon: "sparkles", title: "Try a sample", subtitle: "See how scanning works")
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        dismiss()
                        app.openSetup()
                    } label: {
                        SourceRow(icon: "square.grid.3x3", title: "Set up manually", subtitle: "Place pieces yourself or paste a FEN")
                    }
                    .buttonStyle(PressableStyle())

                    Label("Recognition and analysis run entirely on your iPhone. Photos never leave the device.",
                          systemImage: "lock.shield")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 10)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)

            if let processing {
                ProcessingOverlay(image: processing)
                    .transition(.opacity)
            }
            if let failure {
                FailureOverlay(image: failure.image, message: failure.message,
                               onRetry: { withAnimation { self.failure = nil } },
                               onManual: {
                                   dismiss()
                                   app.openSetup(position: Position(), orientation: .white)
                               })
                    .transition(.opacity)
            }
        }
        .confirmationDialog("Try a sample", isPresented: $showSamples) {
            ForEach(SampleImages.all) { sample in
                Button(sample.title) {
                    if let image = sample.image { recognize(image) }
                }
            }
        }
    }

    // MARK: Actions

    private func pasteImage() {
        guard let image = UIPasteboard.general.image else { return }
        recognize(image)
    }

    private func recognize(_ image: UIImage) {
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.2)) {
            failure = nil
            processing = image
        }
        Task {
            let started = Date()
            let result: Result<RecognitionResult, Error>
            do {
                result = .success(try await BoardRecognizer.shared.recognize(image))
            } catch {
                result = .failure(error)
            }
            // Keep the scanning animation on screen long enough to read as a deliberate step.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.55 { try? await Task.sleep(for: .seconds(0.55 - elapsed)) }
            withAnimation(.easeOut(duration: 0.2)) { processing = nil }
            switch result {
            case .success(let recognition):
                Haptics.success()
                path.append(ScanReview(result: recognition))
            case .failure(let error):
                Haptics.warning()
                withAnimation { failure = (image, error.localizedDescription) }
            }
        }
    }
}

/// Wrapper so a recognition result can live in a navigation path.
struct ScanReview: Hashable {
    let id = UUID()
    let result: RecognitionResult

    static func == (lhs: ScanReview, rhs: ScanReview) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Building blocks

private struct SourceCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconTile(systemName: icon, size: 52)
            Spacer(minLength: 34)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
        .card(padding: 18, radius: 24)
    }
}

private struct SourceRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: icon, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .card(padding: 14, radius: 20)
    }
}

/// Image with an animated scanning beam while recognition runs.
private struct ProcessingOverlay: View {
    let image: UIImage
    @State private var sweep = false

    var body: some View {
        ZStack {
            Palette.background.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .overlay {
                        GeometryReader { proxy in
                            LinearGradient(colors: [.clear, Palette.gold.opacity(0.55), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 90)
                                .offset(y: sweep ? proxy.size.height - 45 : -45)
                                .blendMode(.plusLighter)
                        }
                        .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.gold.opacity(0.5)))
                    .shadow(color: Palette.gold.opacity(0.2), radius: 30)
                HStack(spacing: 10) {
                    ProgressView().tint(Palette.gold)
                    Text("Reading the board…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(32)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

private struct FailureOverlay: View {
    let image: UIImage
    let message: String
    let onRetry: () -> Void
    let onManual: () -> Void

    var body: some View {
        ZStack {
            Palette.background.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(0.7)
                Image(systemName: "viewfinder.trianglebadge.exclamationmark")
                    .font(.system(size: 34))
                    .foregroundStyle(Palette.warning)
                Text(message)
                    .font(.system(size: 17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textPrimary)
                VStack(spacing: 10) {
                    Button("Try another image", action: onRetry).buttonStyle(GoldButtonStyle(height: 54))
                    Button("Set up manually", action: onManual).buttonStyle(OutlineButtonStyle())
                }
                .padding(.top, 6)
            }
            .padding(28)
        }
    }
}

/// System camera (UIImagePickerController) wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// Bundled sample images for "Try a sample".
struct SampleImages {
    struct Sample: Identifiable {
        let id: String
        let title: String
        var image: UIImage? {
            guard let url = Bundle.main.url(forResource: id, withExtension: "jpg") else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
    }

    static let all: [Sample] = [
        Sample(id: "sample-screenshot", title: "Screenshot of a game"),
        Sample(id: "sample-photo", title: "Photo of a monitor"),
    ]
}
