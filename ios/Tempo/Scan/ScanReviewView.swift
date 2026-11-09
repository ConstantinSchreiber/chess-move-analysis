import SwiftUI
import ChessCore

/// Shows the recognised position next to the photo so the user can confirm or fix it.
struct ScanReviewView: View {
    let review: ScanReview
    let onBack: () -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @State private var editor: PositionEditorModel
    @State private var showPhoto = false
    @State private var showFullPhoto = false

    init(review: ScanReview, onBack: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.review = review
        self.onBack = onBack
        self.onClose = onClose
        let result = review.result
        var lastMove: Move?
        if case .highlight(_, let move) = result.evidence { lastMove = move }
        _editor = State(initialValue: PositionEditorModel(position: result.position, orientation: result.orientation,
                                                          uncertain: result.uncertainSquares, detectedLastMove: lastMove))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Review position", onBack: onBack, onClose: onClose)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            photoToggle
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ZStack {
                PositionEditorBoard(editor: editor)
                    .opacity(showPhoto ? 0 : 1)
                if showPhoto {
                    Image(uiImage: review.result.boardImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.opacity)
                        .onTapGesture { showFullPhoto = true }
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: showPhoto)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    PiecePalette(editor: editor)
                    PositionSettingsSection(editor: editor)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)

            Button {
                Haptics.success()
                app.analyze(position: editor.finalPosition, orientation: editor.orientation, source: .scan)
            } label: {
                Label("Analyze", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(GoldButtonStyle())
            .disabled(!editor.issues.isEmpty)
            .opacity(editor.issues.isEmpty ? 1 : 0.45)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Palette.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showFullPhoto) {
            PhotoViewer(image: review.result.image, corners: review.result.corners) { showFullPhoto = false }
        }
    }

    private var photoToggle: some View {
        HStack {
            Button {
                Haptics.tap()
                showPhoto.toggle()
            } label: {
                Label(showPhoto ? "Show recognised board" : "Compare with photo",
                      systemImage: showPhoto ? "square.grid.3x3.fill" : "photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.gold)
            }
            Spacer()
            Button {
                showFullPhoto = true
            } label: {
                Text("Full photo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var summaryCard: some View {
        let uncertain = editor.uncertain.count
        return VStack(alignment: .leading, spacing: 12) {
            if uncertain == 0 {
                infoLine(icon: "checkmark.seal.fill", tint: Palette.positive,
                         text: "Every square read confidently. Still, give the board a quick look against the photo.")
            } else {
                infoLine(icon: "exclamationmark.triangle.fill", tint: Palette.warning,
                         text: "\(uncertain) \(uncertain == 1 ? "square looks" : "squares look") uncertain — outlined on the board. Tap a piece below, then a square to fix it.")
            }
            switch review.result.evidence {
            case .highlight(let mover, let move):
                let moveText = move.map { " (\($0.from.name) → \($0.to.name))" } ?? ""
                infoLine(icon: "arrow.right.circle.fill", tint: Palette.gold,
                         text: "\(mover.name) just moved\(moveText), so it's \(mover.opposite.name)'s turn.")
            case .check(let color):
                infoLine(icon: "bolt.circle.fill", tint: Palette.gold,
                         text: "\(color.name)'s king is in check, so it's \(color.name)'s move.")
            case .unknown:
                infoLine(icon: "questionmark.circle.fill", tint: Palette.warning,
                         text: "No last-move highlight found. Please check who is to move.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 20)
    }

    private func infoLine(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Full-screen photo with the detected board outline.
private struct PhotoViewer: View {
    let image: UIImage
    let corners: [CGPoint]
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { proxy in
                        let sx = proxy.size.width / image.size.width
                        let sy = proxy.size.height / image.size.height
                        Path { path in
                            guard corners.count == 4 else { return }
                            path.addLines(corners.map { CGPoint(x: $0.x * sx, y: $0.y * sy) })
                            path.closeSubpath()
                        }
                        .stroke(Palette.gold, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                        .shadow(color: Palette.gold.opacity(0.6), radius: 6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            CircleIconButton(systemName: "xmark", label: "Close", action: onClose)
                .padding(20)
        }
    }
}
