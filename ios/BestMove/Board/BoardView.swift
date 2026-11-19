import SwiftUI
import ChessCore

struct BoardArrow: Hashable {
    let from: Square
    let to: Square
    var color: Color = Palette.gold
    var opacity: Double = 0.85

    static func path(from: CGPoint, to: CGPoint, squareSize s: CGFloat) -> Path {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        let ux = dx / length, uy = dy / length
        let shaft = s * 0.16, headWidth = s * 0.44, headLength = s * 0.42
        let start = CGPoint(x: from.x + ux * s * 0.18, y: from.y + uy * s * 0.18)
        let tip = CGPoint(x: to.x - ux * s * 0.12, y: to.y - uy * s * 0.12)
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        let px = -uy, py = ux
        var path = Path()
        path.move(to: CGPoint(x: start.x + px * shaft / 2, y: start.y + py * shaft / 2))
        path.addLine(to: CGPoint(x: base.x + px * shaft / 2, y: base.y + py * shaft / 2))
        path.addLine(to: CGPoint(x: base.x + px * headWidth / 2, y: base.y + py * headWidth / 2))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: base.x - px * headWidth / 2, y: base.y - py * headWidth / 2))
        path.addLine(to: CGPoint(x: base.x - px * shaft / 2, y: base.y - py * shaft / 2))
        path.addLine(to: CGPoint(x: start.x - px * shaft / 2, y: start.y - py * shaft / 2))
        path.closeSubpath()
        return path
    }
}

enum SquareMark: Hashable {
    /// Recognition wasn't confident about this square.
    case uncertain
}

/// Interactive chess board. Draws squares in a single Canvas, pieces as individually animated views.
struct BoardView: View {
    enum Mode { case display, play, edit }

    let position: Position
    var orientation: PieceColor = .white
    var lastMove: Move?
    var arrows: [BoardArrow] = []
    var marks: [Square: SquareMark] = [:]
    var mode: Mode = .display
    var showsCoordinates = true
    var cornerRadius: CGFloat = 14
    /// Play mode: a legal move was made.
    var onMove: ((Move) -> Void)?
    /// Edit mode: a square was tapped.
    var onSquareTap: ((Square) -> Void)?
    /// Edit mode: a piece was dragged from a square to another square (nil = dropped off the board).
    var onPieceDrag: ((Square, Square?) -> Void)?

    @Environment(\.boardTheme) private var theme
    @Environment(\.pieceSet) private var pieceSet

    @State private var layout = PieceLayout()
    @State private var selected: Square?
    @State private var drag: DragState?
    @State private var droppedPieceID: Int?
    @State private var promotion: (from: Square, to: Square)?

    private struct DragState {
        let from: Square
        let piece: Piece
        var location: CGPoint
        var isDragging = false
        let wasSelected: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            let geo = BoardGeometry(size: min(proxy.size.width, proxy.size.height), orientation: orientation)
            ZStack(alignment: .topLeading) {
                squaresLayer(geo)
                piecesLayer(geo)
                arrowsLayer(geo)
                dragLayer(geo)
                if let promotion { promotionLayer(geo, from: promotion.from, to: promotion.to) }
            }
            .frame(width: geo.size, height: geo.size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .gesture(boardGesture(geo), including: mode == .display || promotion != nil ? .subviews : .all)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { layout.update(to: position) }
        .onChange(of: position) { _, newValue in
            layout.update(to: newValue, move: lastMove)
            selected = nil
            promotion = nil
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chess board")
        .accessibilityIdentifier("board")
        .accessibilityValue(position.boardFEN)
    }

    // MARK: Layers

    private func squaresLayer(_ geo: BoardGeometry) -> some View {
        let targets: [Move] = selected.map { position.legalMoves(from: $0) } ?? []
        let checkedKing: Square? = position.isCheck ? position.kingSquare(of: position.sideToMove) : nil
        return Canvas { context, _ in
            let s = geo.squareSize
            for square in Square.all {
                let rect = geo.rect(of: square)
                context.fill(Path(rect), with: .color(square.isLight ? theme.light : theme.dark))
            }
            if let lastMove {
                for square in [lastMove.from, lastMove.to] {
                    context.fill(Path(geo.rect(of: square)), with: .color(theme.highlight))
                }
            }
            if let selected {
                context.fill(Path(geo.rect(of: selected)), with: .color(Palette.gold.opacity(0.42)))
            }
            if let checkedKing {
                let rect = geo.rect(of: checkedKing)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -s * 0.1, dy: -s * 0.1)),
                             with: .radialGradient(Gradient(colors: [Color(hex: 0xFF3B30, opacity: 0.9), Color(hex: 0xFF3B30, opacity: 0)]),
                                                   center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: s * 0.62))
            }
            for move in targets where move.promotion == nil || move.promotion == .queen {
                let center = geo.center(of: move.to)
                if position[move.to] != nil || position.isEnPassant(move) {
                    let ring = Path(ellipseIn: CGRect(x: center.x - s * 0.46, y: center.y - s * 0.46, width: s * 0.92, height: s * 0.92))
                    context.stroke(ring, with: .color(.black.opacity(0.22)), lineWidth: s * 0.08)
                } else {
                    let r = s * 0.15
                    context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.black.opacity(0.22)))
                }
            }
            for (square, mark) in marks where mark == .uncertain {
                let rect = geo.rect(of: square).insetBy(dx: s * 0.06, dy: s * 0.06)
                context.stroke(Path(roundedRect: rect, cornerRadius: s * 0.14),
                               with: .color(Palette.warning),
                               style: StrokeStyle(lineWidth: max(2, s * 0.05), dash: [s * 0.12, s * 0.08]))
            }
            if showsCoordinates {
                let font = Font.system(size: max(8, s * 0.2), weight: .bold)
                for i in 0..<8 {
                    let rankSquare = Square(file: orientation == .white ? 0 : 7, rank: orientation == .white ? 7 - i : i)
                    let rankRect = geo.rect(of: rankSquare)
                    context.draw(Text(String(rankSquare.rankDigit)).font(font)
                        .foregroundColor(rankSquare.isLight ? theme.dark : theme.light),
                                 at: CGPoint(x: rankRect.minX + s * 0.06, y: rankRect.minY + s * 0.05), anchor: .topLeading)
                    let fileSquare = Square(file: orientation == .white ? i : 7 - i, rank: orientation == .white ? 0 : 7)
                    let fileRect = geo.rect(of: fileSquare)
                    context.draw(Text(String(fileSquare.fileLetter)).font(font)
                        .foregroundColor(fileSquare.isLight ? theme.dark : theme.light),
                                 at: CGPoint(x: fileRect.maxX - s * 0.06, y: fileRect.maxY - s * 0.03), anchor: .bottomTrailing)
                }
            }
        }
    }

    private func piecesLayer(_ geo: BoardGeometry) -> some View {
        ForEach(layout.pieces) { placed in
            let isDragged = drag?.isDragging == true && drag?.from == placed.square
            Image(pieceSet.imageName(placed.piece))
                .resizable()
                .interpolation(.high)
                .frame(width: geo.squareSize, height: geo.squareSize)
                .position(geo.center(of: placed.square))
                .opacity(isDragged ? 0.25 : 1)
                .animation(placed.id == droppedPieceID ? nil : .spring(response: 0.26, dampingFraction: 0.88),
                           value: placed.square)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .animation(.easeOut(duration: 0.18), value: layout.pieces.map(\.id))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: orientation)
        .allowsHitTesting(false)
    }

    private func arrowsLayer(_ geo: BoardGeometry) -> some View {
        Canvas { context, _ in
            for arrow in arrows where arrow.from != arrow.to {
                context.fill(BoardArrow.path(from: geo.center(of: arrow.from), to: geo.center(of: arrow.to), squareSize: geo.squareSize),
                             with: .color(arrow.color.opacity(arrow.opacity)))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: arrows)
    }

    @ViewBuilder
    private func dragLayer(_ geo: BoardGeometry) -> some View {
        if let drag, drag.isDragging {
            if let target = geo.square(at: drag.location) {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: geo.squareSize * 1.9, height: geo.squareSize * 1.9)
                    .position(geo.center(of: target))
                    .allowsHitTesting(false)
            }
            Image(pieceSet.imageName(drag.piece))
                .resizable()
                .interpolation(.high)
                .frame(width: geo.squareSize * 1.25, height: geo.squareSize * 1.25)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
                .position(x: drag.location.x, y: drag.location.y - geo.squareSize * 0.35)
                .allowsHitTesting(false)
        }
    }

    private func promotionLayer(_ geo: BoardGeometry, from: Square, to: Square) -> some View {
        let color = position[from]?.color ?? position.sideToMove
        let topDown = geo.row(of: to) == 0
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.55)
                .onTapGesture { promotion = nil }
            ForEach(Array(PieceKind.promotionChoices.enumerated()), id: \.offset) { index, kind in
                let row = topDown ? index : 7 - index
                Button {
                    promotion = nil
                    if let move = position.legalMove(from: from, to: to, promotion: kind) {
                        Haptics.move()
                        onMove?(move)
                    }
                } label: {
                    Image(pieceSet.imageName(Piece(color, kind)))
                        .resizable()
                        .padding(geo.squareSize * 0.08)
                        .frame(width: geo.squareSize, height: geo.squareSize)
                        .background(Circle().fill(Palette.surfaceHigh).overlay(Circle().strokeBorder(Palette.gold.opacity(0.6))))
                }
                .buttonStyle(PressableStyle())
                .position(x: (CGFloat(geo.column(of: to)) + 0.5) * geo.squareSize,
                          y: (CGFloat(row) + 0.5) * geo.squareSize)
            }
        }
        .transition(.opacity)
    }

    // MARK: Interaction

    private func boardGesture(_ geo: BoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if var current = drag {
                    current.location = value.location
                    if !current.isDragging, hypot(value.translation.width, value.translation.height) > 6 {
                        current.isDragging = true
                    }
                    drag = current
                    return
                }
                guard let square = geo.square(at: value.startLocation), let piece = position[square] else { return }
                switch mode {
                case .play:
                    guard piece.color == position.sideToMove else { return }
                    let wasSelected = selected == square
                    if selected != square {
                        // Tapping another own piece while one is selected re-selects; legal capture targets are handled on end.
                        if let selected, position.legalMove(from: selected, to: square) != nil { return }
                        selected = square
                    }
                    drag = DragState(from: square, piece: piece, location: value.location, wasSelected: wasSelected)
                case .edit:
                    drag = DragState(from: square, piece: piece, location: value.location, wasSelected: false)
                case .display:
                    break
                }
            }
            .onEnded { value in
                defer { drag = nil }
                let target = geo.square(at: value.location)
                if let current = drag, current.isDragging {
                    switch mode {
                    case .play:
                        if let target, target != current.from {
                            attemptMove(from: current.from, to: target, dropped: true)
                        }
                    case .edit:
                        onPieceDrag?(current.from, target)
                    case .display:
                        break
                    }
                    return
                }
                guard let target else { return }
                switch mode {
                case .play:
                    if let selected, selected != target, position.legalMoves(from: selected).contains(where: { $0.to == target }) {
                        attemptMove(from: selected, to: target, dropped: false)
                    } else if let current = drag, current.from == target, current.wasSelected {
                        selected = nil
                    } else if position[target]?.color != position.sideToMove {
                        selected = nil
                    }
                case .edit:
                    onSquareTap?(target)
                case .display:
                    break
                }
            }
    }

    private func attemptMove(from: Square, to: Square, dropped: Bool) {
        if position.isPromotion(from: from, to: to) {
            withAnimation(.easeOut(duration: 0.15)) { promotion = (from, to) }
            return
        }
        guard let move = position.legalMove(from: from, to: to) else {
            if dropped { Haptics.warning() }
            return
        }
        droppedPieceID = dropped ? layout.pieces.first { $0.square == from }?.id : nil
        selected = nil
        Haptics.move()
        onMove?(move)
    }
}

/// Lightweight non-interactive board drawn in a single Canvas — for thumbnails and lists.
struct MiniBoardView: View {
    let position: Position
    var orientation: PieceColor = .white
    var lastMove: Move?
    var arrows: [BoardArrow] = []
    var cornerRadius: CGFloat = 8

    @Environment(\.boardTheme) private var theme
    @Environment(\.pieceSet) private var pieceSet

    var body: some View {
        Canvas { context, size in
            let geo = BoardGeometry(size: min(size.width, size.height), orientation: orientation)
            for square in Square.all {
                context.fill(Path(geo.rect(of: square)), with: .color(square.isLight ? theme.light : theme.dark))
            }
            if let lastMove {
                for square in [lastMove.from, lastMove.to] {
                    context.fill(Path(geo.rect(of: square)), with: .color(theme.highlight))
                }
            }
            for (square, piece) in position.pieces {
                let image = context.resolve(Image(pieceSet.imageName(piece)))
                context.draw(image, in: geo.rect(of: square))
            }
            for arrow in arrows where arrow.from != arrow.to {
                context.fill(BoardArrow.path(from: geo.center(of: arrow.from), to: geo.center(of: arrow.to), squareSize: geo.squareSize),
                             with: .color(arrow.color.opacity(arrow.opacity)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .environment(\.layoutDirection, .leftToRight)
    }
}
