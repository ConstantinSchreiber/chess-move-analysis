import SwiftUI

/// The gold call-to-action used for the single most important action on a screen.
struct GoldButtonStyle: ButtonStyle {
    var height: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Palette.onGold)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.goldGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                         startPoint: .top, endPoint: .center), lineWidth: 1)
                    )
                    .shadow(color: Palette.gold.opacity(configuration.isPressed ? 0.15 : 0.32), radius: 22, y: 8)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary outlined button.
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Palette.surface.opacity(configuration.isPressed ? 1 : 0.6),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.strokeStrong))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Subtle press feedback for custom tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Square glyph tile used on cards (gold symbol on a raised chip).
struct IconTile: View {
    let systemName: String
    var size: CGFloat = 48
    var tint: Color = Palette.gold

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Palette.surfaceHigh, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Palette.stroke))
    }
}

/// Round, glassy icon button used in headers.
struct CircleIconButton: View {
    let systemName: String
    var label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Palette.stroke))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Two-option segmented control in the app's style.
struct SegmentedPicker<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringKey)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    guard !selected else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Palette.gold : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Palette.surfaceHigh)
                                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Palette.gold.opacity(0.55)))
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Palette.stroke))
    }
}

/// Pill-shaped toggle chip.
struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        Button {
            Haptics.tap()
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isOn ? Palette.gold : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isOn ? Palette.gold.opacity(0.12) : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Palette.gold.opacity(0.45) : Palette.stroke))
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// Header used at the top of sheets: optional back button, title, close button.
struct SheetHeader: View {
    let title: LocalizedStringKey
    var onBack: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let onBack {
                CircleIconButton(systemName: "chevron.left", label: "Back", action: onBack)
            }
            Text(title)
                .font(.display(30))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            CircleIconButton(systemName: "xmark", label: "Close", action: onClose)
        }
    }
}

extension View {
    /// iPad: a page-sized sheet instead of the small form sheet, so boards stay large. iPhone sheets
    /// are full width either way.
    @ViewBuilder
    func largeSheetOnPad() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
