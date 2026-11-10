import SwiftUI
import ChessCore

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeroView()
                    .frame(height: 440)
                    .overlay(alignment: .bottomLeading) { headline }

                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        Haptics.tap()
                        app.startScan()
                    } label: {
                        Label("Scan position", systemImage: "viewfinder")
                    }
                    .buttonStyle(GoldButtonStyle(height: 62))

                    HStack(spacing: 12) {
                        Button { app.openBoard() } label: {
                            ActionTile(icon: "checkerboard.rectangle", title: "Analysis board", subtitle: "Start from the opening")
                        }
                        .buttonStyle(PressableStyle())
                        Button { app.openSetup() } label: {
                            ActionTile(icon: "square.and.pencil", title: "Set up position", subtitle: "Place pieces or paste FEN")
                        }
                        .buttonStyle(PressableStyle())
                    }

                    recent
                        .padding(.top, 18)

                    footer
                        .padding(.top, 26)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topTrailing) {
            CircleIconButton(systemName: "gearshape", label: "Settings") { app.isSettingsPresented = true }
                .padding(.trailing, 20)
                .padding(.top, 4)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best Move").eyebrowStyle(Palette.gold)
            Text("Find the move\nthat matters.")
                .font(.display(42, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(-4)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var recent: some View {
        let entries = app.history.entries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent positions").eyebrowStyle()
                    Spacer()
                    Menu {
                        Button("Clear history", role: .destructive) { withAnimation { app.history.clear() } }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 32, height: 24)
                    }
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(entries) { entry in
                            Button { app.open(entry) } label: { RecentCard(entry: entry) }
                                .buttonStyle(PressableStyle())
                                .contextMenu {
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        withAnimation { app.history.remove(entry.id) }
                                    }
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .foregroundStyle(Palette.gold)
            Text("Stockfish 19 runs entirely on your iPhone — no account, no upload, works offline.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

private struct ActionTile: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconTile(systemName: icon, size: 42)
            Spacer(minLength: 16)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .card(padding: 16, radius: 22)
    }
}

private struct RecentCard: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MiniBoardView(position: entry.position, orientation: entry.orientation)
                .frame(width: 136, height: 136)
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.gold)
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let evaluation = entry.evaluation {
                    Text(evaluation)
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                }
            }
        }
        .frame(width: 136)
        .card(padding: 10, radius: 18)
    }

    private var icon: String {
        switch entry.source {
        case .scan: "viewfinder"
        case .setup: "square.and.pencil"
        case .board: "checkerboard.rectangle"
        }
    }
}
