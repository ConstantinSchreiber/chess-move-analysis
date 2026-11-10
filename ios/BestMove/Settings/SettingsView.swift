import SwiftUI
import ChessCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    SheetHeader(title: "Settings", onClose: { dismiss() })

                    section("Board") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(BoardTheme.all) { theme in
                                    Button {
                                        Haptics.tap()
                                        settings.boardThemeID = theme.id
                                    } label: {
                                        VStack(spacing: 8) {
                                            MiniBoardView(position: .start)
                                                .environment(\.boardTheme, theme)
                                                .frame(width: 92, height: 92)
                                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(settings.boardThemeID == theme.id ? Palette.gold : .clear, lineWidth: 2.5))
                                            Text(theme.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(settings.boardThemeID == theme.id ? Palette.gold : Palette.textSecondary)
                                        }
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()

                        HStack(spacing: 10) {
                            ForEach(PieceSet.allCases) { set in
                                Button {
                                    Haptics.tap()
                                    settings.pieceSetID = set.rawValue
                                } label: {
                                    VStack(spacing: 6) {
                                        HStack(spacing: -6) {
                                            Image(set.imageName(Piece(.white, .knight))).resizable().frame(width: 40, height: 40)
                                            Image(set.imageName(Piece(.black, .queen))).resizable().frame(width: 40, height: 40)
                                        }
                                        Text(set.name).font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(settings.pieceSetID == set.rawValue ? Palette.gold : Palette.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(settings.pieceSetID == set.rawValue ? Palette.gold : Palette.stroke,
                                                      lineWidth: settings.pieceSetID == set.rawValue ? 1.5 : 1))
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    section("Analysis") {
                        VStack(spacing: 0) {
                            stepperRow("Engine lines", value: $settings.engineLines, range: 1...5,
                                       caption: "Alternative moves shown")
                            Divider().overlay(Palette.stroke)
                            stepperRow("Search depth", value: $settings.maxDepth, range: 16...50, step: 2,
                                       caption: "Pauses there to save battery")
                            Divider().overlay(Palette.stroke)
                            toggleRow("Best-move arrow", isOn: $settings.showBestMoveArrow)
                            Divider().overlay(Palette.stroke)
                            toggleRow("Haptics", isOn: $settings.haptics)
                        }
                        .card(padding: 0, radius: 20)
                    }

                    section("About") {
                        VStack(spacing: 0) {
                            NavigationLink { LicensesView() } label: {
                                linkRow("Licenses & acknowledgements", icon: "doc.text")
                            }
                            Divider().overlay(Palette.stroke)
                            Link(destination: URL(string: "https://github.com/ConstantinSchreiber/chess-move-analysis")!) {
                                linkRow("Source code", icon: "chevron.left.forwardslash.chevron.right")
                            }
                        }
                        .card(padding: 0, radius: 20)
                        Text("Best Move \(Bundle.main.appVersion) · Stockfish 19 · All processing happens on this device.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(Palette.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).eyebrowStyle()
            content()
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, caption: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.textPrimary)
                Text(caption).font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.gold)
                .frame(minWidth: 28)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.textPrimary)
        }
        .tint(Palette.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func linkRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.gold).frame(width: 22)
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.textPrimary)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textTertiary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}

struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    CircleIconButton(systemName: "chevron.left", label: "Back") { dismiss() }
                    Spacer()
                }
                Text("Licenses").font(.display(30)).foregroundStyle(Palette.textPrimary)
                block("Best Move", "Best Move is free software, released under the GNU General Public License v3. Its complete source code is available at github.com/ConstantinSchreiber/chess-move-analysis.")
                block("Stockfish 19", "Copyright © the Stockfish developers (see AUTHORS). Licensed under the GNU General Public License v3. stockfishchess.org — github.com/official-stockfish/Stockfish")
                block("Piece sets", PieceSet.allCases.map { "\($0.name): \($0.credit)" }.joined(separator: "\n"))
                block("Board recognition", "Neural networks trained for Best Move on synthetic boards rendered from openly licensed piece sets and positions from the lichess.org open database (CC0).")
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textPrimary)
            Text(body).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 18)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
