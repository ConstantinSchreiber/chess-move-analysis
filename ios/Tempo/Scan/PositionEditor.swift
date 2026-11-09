import SwiftUI
import Observation
import ChessCore

/// Editable position used by the scan review and the manual setup screen.
@Observable
@MainActor
final class PositionEditorModel {
    enum Tool: Hashable {
        case hand
        case piece(Piece)
        case eraser
    }

    var position: Position
    var orientation: PieceColor
    var tool: Tool = .hand
    /// Squares the recogniser wasn't sure about; cleared as the user edits them.
    var uncertain: Set<Square>
    /// Last move inferred from the photo's highlight, shown on the board.
    var detectedLastMove: Move?

    init(position: Position, orientation: PieceColor, uncertain: Set<Square> = [], detectedLastMove: Move? = nil) {
        var position = position
        position.castling.formIntersection(position.possibleCastling)
        self.position = position
        self.orientation = orientation
        self.uncertain = uncertain
        self.detectedLastMove = detectedLastMove
    }

    var sideToMove: PieceColor {
        get { position.sideToMove }
        set { position.sideToMove = newValue; position.enPassant = nil }
    }

    var issues: [SetupIssue] { position.setupIssues() }

    /// The position to analyse: castling and en-passant made consistent with the board.
    var finalPosition: Position { position.sanitized() }

    func castlingBinding(_ right: CastlingRights) -> Binding<Bool> {
        Binding(get: { self.position.castling.contains(right) },
                set: { on in if on { self.position.castling.insert(right) } else { self.position.castling.remove(right) } })
    }

    func tap(_ square: Square) {
        switch tool {
        case .hand:
            return
        case .eraser:
            set(nil, at: square)
        case .piece(let piece):
            set(position[square] == piece ? nil : piece, at: square)
        }
        Haptics.tap()
    }

    func drag(from: Square, to: Square?) {
        let piece = position[from]
        set(nil, at: from)
        if let to { set(piece, at: to) }
        Haptics.tap()
    }

    private func set(_ piece: Piece?, at square: Square) {
        position[square] = piece
        uncertain.remove(square)
        detectedLastMove = nil
        position.enPassant = nil
        position.castling.formIntersection(position.possibleCastling)
    }

    func clearBoard() {
        position = Position()
        position.sideToMove = sideToMove
        uncertain = []
        detectedLastMove = nil
    }

    func resetToStart() {
        position = .start
        uncertain = []
        detectedLastMove = nil
    }

    /// The photo was taken from the other side: rotate the position 180° but keep the picture the same.
    func swapSides() {
        var rotated = Position()
        for (square, piece) in position.pieces { rotated[Square(63 - square.index)] = piece }
        rotated.sideToMove = position.sideToMove
        rotated.castling = rotated.possibleCastling
        position = rotated
        uncertain = Set(uncertain.map { Square(63 - $0.index) })
        detectedLastMove = detectedLastMove.map {
            Move(from: Square(63 - $0.from.index), to: Square(63 - $0.to.index))
        }
        orientation = orientation.opposite
    }
}

/// Board + tools for editing a position.
struct PositionEditorBoard: View {
    @Bindable var editor: PositionEditorModel

    var body: some View {
        BoardView(position: editor.position,
                  orientation: editor.orientation,
                  lastMove: editor.detectedLastMove,
                  marks: Dictionary(uniqueKeysWithValues: editor.uncertain.map { ($0, SquareMark.uncertain) }),
                  mode: .edit,
                  onSquareTap: { editor.tap($0) },
                  onPieceDrag: { editor.drag(from: $0, to: $1) })
    }
}

/// Piece palette and edit actions.
struct PiecePalette: View {
    @Bindable var editor: PositionEditorModel
    @Environment(\.pieceSet) private var pieceSet

    var body: some View {
        VStack(spacing: 8) {
            ForEach(PieceColor.allCases, id: \.self) { color in
                HStack(spacing: 6) {
                    ForEach([PieceKind.king, .queen, .rook, .bishop, .knight, .pawn], id: \.self) { kind in
                        let piece = Piece(color, kind)
                        toolButton(.piece(piece), label: piece.description) {
                            Image(pieceSet.imageName(piece)).resizable().padding(4)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                toolButton(.hand, label: "Move pieces") {
                    Image(systemName: "hand.point.up.left").font(.system(size: 18, weight: .medium))
                }
                toolButton(.eraser, label: "Erase") {
                    Image(systemName: "eraser").font(.system(size: 18, weight: .medium))
                }
                actionButton("arrow.triangle.2.circlepath", "Swap sides") { withAnimation { editor.swapSides() } }
                actionButton("arrow.counterclockwise", "Start position") { withAnimation { editor.resetToStart() } }
                actionButton("trash", "Clear board") { withAnimation { editor.clearBoard() } }
            }
        }
    }

    private func toolButton<Content: View>(_ tool: PositionEditorModel.Tool, label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        let selected = editor.tool == tool
        return Button {
            Haptics.tap()
            editor.tool = selected && tool != .hand ? .hand : tool
        } label: {
            content()
                .foregroundStyle(selected ? Palette.gold : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(selected ? Palette.gold.opacity(0.14) : Palette.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Palette.gold.opacity(0.7) : Palette.stroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func actionButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.stroke))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Side to move, castling rights and validation messages.
struct PositionSettingsSection: View {
    @Bindable var editor: PositionEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SegmentedPicker(options: [(PieceColor.white, "White to move"), (PieceColor.black, "Black to move")],
                            selection: $editor.sideToMove)

            let possible = editor.position.possibleCastling
            if !possible.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Castling rights").eyebrowStyle()
                    Text("Keep a right only if that king and rook have never moved.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                    ForEach(PieceColor.allCases, id: \.self) { color in
                        let rights = [(title: "O-O", right: CastlingRights.kingside(color)),
                                      (title: "O-O-O", right: CastlingRights.queenside(color))]
                            .filter { possible.contains($0.right) }
                        if !rights.isEmpty {
                            HStack(spacing: 8) {
                                Text(color.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.textSecondary)
                                    .frame(width: 56, alignment: .leading)
                                ForEach(rights, id: \.title) { option in
                                    ToggleChip(title: option.title, isOn: editor.castlingBinding(option.right))
                                }
                            }
                        }
                    }
                }
            }

            let issues = editor.issues
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue.description, systemImage: "exclamationmark.octagon.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14, radius: 16, fill: Palette.danger.opacity(0.08))
            }
        }
    }
}

/// Manual setup / edit sheet.
struct PositionEditorSheet: View {
    let title: String
    let onDone: (Position, PieceColor) -> Void
    @State private var editor: PositionEditorModel
    @State private var fenText = ""
    @State private var fenError = false
    @Environment(\.dismiss) private var dismiss

    init(initial: Position, orientation: PieceColor, title: String, onDone: @escaping (Position, PieceColor) -> Void) {
        self.title = title
        self.onDone = onDone
        _editor = State(initialValue: PositionEditorModel(position: initial, orientation: orientation))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, onClose: { dismiss() })
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)
            PositionEditorBoard(editor: editor)
                .padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PiecePalette(editor: editor)
                    PositionSettingsSection(editor: editor)
                    fenField
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            Button {
                Haptics.success()
                onDone(editor.finalPosition, editor.orientation)
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
        .presentationBackground(Palette.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private var fenField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste FEN").eyebrowStyle()
            HStack(spacing: 8) {
                TextField("rnbqkbnr/pppppppp/8/…", text: $fenText)
                    .font(.mono)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(fenError ? Palette.danger : Palette.stroke))
                    .onSubmit(loadFEN)
                Button("Load", action: loadFEN)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func loadFEN() {
        let text = fenText.isEmpty ? (UIPasteboard.general.string ?? "") : fenText
        guard let position = try? Position(fen: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            fenError = true
            Haptics.warning()
            return
        }
        fenError = false
        fenText = position.fen
        withAnimation { editor.position = position }
        Haptics.success()
    }
}
