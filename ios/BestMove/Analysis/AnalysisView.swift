import SwiftUI
import StoreKit
import ChessCore
import StockfishKit

struct AnalysisView: View {
    @Bindable var model: AnalysisModel
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing = false
    @State private var copiedFEN = false

    var body: some View {
        GeometryReader { proxy in
            if Self.isWide(proxy.size) {
                wideLayout(proxy.size)
            } else {
                compactLayout
                    // iPad portrait: a column as wide as the height leaves room for, not wall to wall.
                    .frame(maxWidth: Self.columnWidth(proxy.size))
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .task(id: model.hasSolidResult) { await considerReviewPrompt() }
        #if DEBUG
        .task(id: model.hasSolidResult) {
            // -demoShareCard: write the share image to tmp/share-card.png once the result is solid.
            guard model.hasSolidResult, ProcessInfo.processInfo.arguments.contains("-demoShareCard") else { return }
            try? shareImage.card.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("share-card.png"))
        }
        #endif
        .sheet(isPresented: $editing) {
            PositionEditorSheet(initial: model.position, orientation: model.orientation, title: "Edit position") { position, orientation in
                editing = false
                app.replaceAnalysis(model, with: position, orientation: orientation)
            }
        }
    }

    // MARK: Layouts

    /// Landscape iPad (and other wide windows): board left, engine panel right.
    static func isWide(_ size: CGSize) -> Bool { size.width >= 700 && size.width > size.height * 1.15 }

    /// Portrait column: the board grows with the window height while header, panel and move bar
    /// (about 540 pt) stay fully visible below it.
    static func columnWidth(_ size: CGSize) -> CGFloat { min(820, max(640, size.height - 540)) }

    /// iPhone and narrow windows: header, board, scrolling panel, move bar.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 14)
            boardSection
                .padding(.horizontal, 12)
            ScrollView {
                panel
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            bottomBar
        }
    }

    private func wideLayout(_ size: CGSize) -> some View {
        let headerHeight: CGFloat = 64
        let side = max(240, min(size.height - headerHeight - 28, size.width * 0.58))
        return VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 14)
            HStack(alignment: .top, spacing: 24) {
                boardSection
                    .frame(width: side + 18)   // + eval bar and its spacing
                VStack(spacing: 0) {
                    ScrollView {
                        panel.padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    bottomBar
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
        }
    }

    private var panel: some View {
        VStack(spacing: 14) {
            statusRow
            bestMoveCard
            linesSection
        }
    }

    // MARK: Header

    /// The rating moment: a clean scan has just produced a solid best move. Asks a couple of seconds
    /// later, while the result is on screen, unless the person has moved on (see `ReviewPrompter`).
    private func considerReviewPrompt() async {
        guard model.isCleanScan, model.hasSolidResult, !model.reviewMomentHandled else { return }
        model.reviewMomentHandled = true
        guard app.reviewPrompter.recordCleanScanSuccess() else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled, scenePhase == .active, !editing, model.isAtStart else { return }
        app.reviewPrompter.didRequestReview()
        requestReview()
    }

    private var header: some View {
        HStack(spacing: 8) {
            CircleIconButton(systemName: "chevron.left", label: "Back") { dismiss() }
                .padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Analysis")
                    .font(.display(24))
                    .foregroundStyle(Palette.textPrimary)
                Text(model.subtitle)
                    .font(.mono)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Palette.textSecondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            CircleIconButton(systemName: "arrow.up.arrow.down", label: "Flip board") {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.flip() }
            }
            ShareLink(item: shareImage, message: Text(shareMessage),
                      preview: SharePreview(shareTitle, image: Image("Logo"))) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.stroke))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Share")
            Menu {
                Button { editing = true } label: { Label("Edit position", systemImage: "square.and.pencil") }
                Button {
                    UIPasteboard.general.string = model.position.fen
                    Haptics.success()
                } label: { Label("Copy FEN", systemImage: "doc.on.doc") }
                ShareLink(item: lichessURL) { Label("Open on lichess.org", systemImage: "safari") }
                Divider()
                Button { app.startScan() } label: { Label("New scan", systemImage: "viewfinder") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.stroke))
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: Sharing

    private var shareImage: ShareCardImage {
        let line = model.displayLines.first
        return ShareCardImage(card: ShareCard(position: model.position, orientation: model.orientation, lastMove: model.lastMove,
                                              best: model.bestMove, san: line?.tokens.first?.san, score: line?.score,
                                              theme: app.settings.boardTheme, pieceSet: app.settings.pieceSet))
    }

    private var shareTitle: String {
        if let san = model.displayLines.first?.tokens.first?.san { return String(localized: "Best move: \(san)") }
        return String(localized: "Chess position")
    }

    private var shareMessage: String {
        let link = AppStoreLinks.app.absoluteString
        if let line = model.displayLines.first, let san = line.tokens.first?.san {
            return String(localized: "Best move: \(san) (\(line.score.shortText)). Found with Best Move, the free chess scanner: \(link)")
        }
        return String(localized: "Find the best move in any chess position with Best Move: \(link)")
    }

    private var lichessURL: URL {
        let fen = model.position.fen.replacingOccurrences(of: " ", with: "_")
        return URL(string: "https://lichess.org/analysis/standard/\(fen)") ?? URL(string: "https://lichess.org/analysis")!
    }

    // MARK: Board

    private var boardSection: some View {
        HStack(spacing: 8) {
            EvalBar(whiteChance: model.whiteChance, orientation: model.orientation)
                .frame(maxHeight: .infinity)
            BoardView(position: model.position,
                      orientation: model.orientation,
                      lastMove: model.lastMove,
                      arrows: arrows,
                      mode: .play,
                      onMove: { model.play($0) })
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var arrows: [BoardArrow] {
        guard app.settings.showBestMoveArrow else { return [] }
        var result: [BoardArrow] = []
        let lines = model.displayLines
        if lines.count > 1, let uci = lines[1].uci.first, let move = Move(uci: uci) {
            result.append(BoardArrow(from: move.from, to: move.to, color: Palette.textPrimary, opacity: 0.28))
        }
        if let best = model.bestMove {
            result.append(BoardArrow(from: best.from, to: best.to))
        }
        return result
    }

    // MARK: Engine status

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(statusTint)
                .symbolEffect(.pulse, isActive: model.status == .running || model.status == .starting)
            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText())
                .lineLimit(2)
            Spacer(minLength: 8)
            if let action = statusAction {
                Button(action.title) {
                    Haptics.tap()
                    action.run()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.gold)
            }
        }
        .padding(.horizontal, 4)
        .animation(.default, value: statusText)
    }

    private var statusTint: Color {
        switch model.status {
        case .unavailable: Palette.danger
        case .paused, .finished, .gameOver: Palette.textTertiary
        default: Palette.gold
        }
    }

    private var statusText: String {
        let snapshot = model.currentSnapshot
        switch model.status {
        case .starting:
            return model.engineBooted ? String(localized: "Stockfish is thinking…") : String(localized: "Starting Stockfish…")
        case .running:
            guard let snapshot, snapshot.depth > 0 else { return String(localized: "Stockfish is thinking…") }
            let depth = snapshot.depth, speed = Self.formatNPS(snapshot.nps)
            return String(localized: "Depth \(depth) · \(speed)")
        case .paused:
            guard let depth = snapshot?.depth else { return String(localized: "Paused") }
            return String(localized: "Paused at depth \(depth)")
        case .finished:
            let depth = snapshot?.depth ?? model.targetDepth
            return String(localized: "Depth \(depth) reached")
        case .gameOver(let text), .unavailable(let text):
            return text
        }
    }

    private var statusAction: (title: LocalizedStringKey, run: () -> Void)? {
        switch model.status {
        case .running, .starting: ("Pause", { model.togglePause() })
        case .paused: ("Resume", { model.togglePause() })
        case .finished: ("Go deeper", { model.goDeeper() })
        default: nil
        }
    }

    static func formatNPS(_ nps: Int) -> String {
        if nps >= 1_000_000 {
            let millions = (Double(nps) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
            return String(localized: "\(millions)M nodes/s")
        }
        if nps >= 1_000 { return String(localized: "\(nps / 1_000)k nodes/s") }
        return String(localized: "\(nps) nodes/s")
    }

    // MARK: Best move

    @ViewBuilder
    private var bestMoveCard: some View {
        if let best = model.bestMove, let line = model.displayLines.first, let san = line.tokens.first?.san {
            let description = MoveDescriber.describe(best, in: model.position)
            Button {
                Haptics.move()
                model.play(best)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text("Best move").eyebrowStyle(Palette.gold)
                        Spacer()
                        ScoreChip(score: line.score, large: true)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(san)
                            .font(.display(34, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .contentTransition(.opacity)
                        Text(description.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.gold)
                            .accessibilityLabel("Play it")
                    }
                    Text("\(description.detail) \(line.score.verdict).")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
            }
            .buttonStyle(PressableStyle())
            .animation(.easeInOut(duration: 0.2), value: san)
        } else if case .gameOver(let text) = model.status {
            VStack(alignment: .leading, spacing: 8) {
                Text("Game over").eyebrowStyle(Palette.gold)
                Text(text).font(.display(28)).foregroundStyle(Palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else if case .unavailable(let text) = model.status {
            VStack(alignment: .leading, spacing: 8) {
                Text("Can't analyse").eyebrowStyle(Palette.danger)
                Text(text).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                Button("Edit position") { editing = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.gold)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Best move").eyebrowStyle(Palette.gold)
                RoundedRectangle(cornerRadius: 8).fill(Palette.surfaceHigh).frame(width: 120, height: 38)
                RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceHigh).frame(height: 14)
                RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceHigh).frame(width: 180, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 18)
            .phaseAnimator([0.45, 1]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.8) }
        }
    }

    // MARK: Lines

    @ViewBuilder
    private var linesSection: some View {
        let lines = model.displayLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Engine lines").eyebrowStyle()
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { Divider().overlay(Palette.stroke) }
                        LineRow(line: line) { tokenIndex in
                            Haptics.move()
                            model.play(line: line, through: tokenIndex)
                        }
                    }
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.stroke))
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            MoveStrip(model: model)
            HStack(spacing: 10) {
                navButton("backward.end.fill", "First move", enabled: model.canGoBack) { model.toStart() }
                navButton("chevron.left", "Previous move", enabled: model.canGoBack) { model.back() }
                navButton("chevron.right", "Next move", enabled: model.canGoForward) { model.forward() }
                navButton("forward.end.fill", "Last move", enabled: model.canGoForward) { model.toEnd() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Palette.background.shadow(.drop(color: .black.opacity(0.5), radius: 12, y: -4)))
        .overlay(alignment: .top) { Rectangle().fill(Palette.stroke).frame(height: 1) }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func navButton(_ icon: String, _ label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? Palette.textPrimary : Palette.textTertiary.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.stroke))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// One engine line: score chip followed by a horizontally scrolling list of tappable moves.
private struct LineRow: View {
    let line: DisplayLine
    let onTapMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ScoreChip(score: line.score)
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(line.tokens, id: \.index) { token in
                        Button { onTapMove(token.index) } label: {
                            HStack(spacing: 3) {
                                if let label = token.label {
                                    Text(label).foregroundStyle(Palette.textTertiary)
                                }
                                Text(token.san)
                                    .foregroundStyle(token.index == 0 ? Palette.textPrimary : Palette.textSecondary)
                                    .fontWeight(token.index == 0 ? .semibold : .regular)
                            }
                            .font(.system(size: 15))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.leading, 12)
        .padding(.vertical, 8)
        .environment(\.layoutDirection, .leftToRight)   // chess notation reads left to right
    }
}

/// The current line of moves, scrolling to keep the selected move in view.
private struct MoveStrip: View {
    let model: AnalysisModel

    var body: some View {
        let nodes = Array(model.line.dropFirst())
        let currentPath = Set(model.tree.path(to: model.current))
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    if nodes.isEmpty {
                        Text("Move pieces on the board to explore")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(height: 34)
                    }
                    ForEach(nodes, id: \.self) { id in
                        let node = model.tree[id]
                        let isCurrent = id == model.current
                        let isWhiteMove = node.parent.map { model.tree[$0].position.sideToMove == .white } ?? false
                        HStack(spacing: 3) {
                            if isWhiteMove || id == nodes.first {
                                Text(model.tree.moveNumberLabel(for: id))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Button {
                                Haptics.tap()
                                model.select(id)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(node.san ?? "")
                                        .fontWeight(isCurrent ? .bold : .medium)
                                    if let parent = node.parent, model.tree[parent].children.count > 1 {
                                        Circle().fill(Palette.gold.opacity(0.7)).frame(width: 4, height: 4)
                                    }
                                }
                                .foregroundStyle(isCurrent ? Palette.onGold : currentPath.contains(id) ? Palette.textPrimary : Palette.textSecondary)
                                .padding(.horizontal, 9)
                                .frame(height: 32)
                                .background(isCurrent ? AnyShapeStyle(Palette.goldGradient) : AnyShapeStyle(Color.clear),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { model.select(id) } label: { Label("Go to move", systemImage: "arrow.right.circle") }
                                Button(role: .destructive) { model.deleteVariation(id) } label: {
                                    Label("Delete from here", systemImage: "trash")
                                }
                            }
                        }
                        .font(.system(size: 15))
                        .id(id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 36)
            .onChange(of: model.current) { _, current in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .overlay(alignment: .trailing) { alternatives }
    }

    @ViewBuilder
    private var alternatives: some View {
        let children = model.tree[model.current].children
        if children.count > 1 {
            Menu {
                ForEach(children, id: \.self) { child in
                    Button(model.tree[child].san ?? "") { model.select(child) }
                }
            } label: {
                Label("\(children.count)", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Palette.surfaceHigh, in: Capsule())
            }
            .accessibilityLabel("Variations")
        }
    }
}
