import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The app's colour system: warm near-black surfaces, ivory text and a single gold accent.
enum Palette {
    static let background = Color(hex: 0x0A0B0E)
    static let surface = Color(hex: 0x131519)
    static let surfaceRaised = Color(hex: 0x1A1D23)
    static let surfaceHigh = Color(hex: 0x23262E)
    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.13)

    static let textPrimary = Color(hex: 0xF4EFE6)
    static let textSecondary = Color(hex: 0xA19E98)
    static let textTertiary = Color(hex: 0x6B6964)

    static let gold = Color(hex: 0xE6B85C)
    static let goldLight = Color(hex: 0xF3D08C)
    static let goldDeep = Color(hex: 0xC48E33)
    static let onGold = Color(hex: 0x1B1408)

    static let positive = Color(hex: 0x8CC98A)
    static let warning = Color(hex: 0xEFA24E)
    static let danger = Color(hex: 0xE76A5E)

    static let goldGradient = LinearGradient(colors: [goldLight, gold, goldDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Font {
    /// Editorial serif used for headlines.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small, widely tracked caps used above sections.
    static let eyebrow = Font.system(size: 11.5, weight: .bold).width(.expanded)
    static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
}

extension View {
    func eyebrowStyle(_ color: Color = Palette.textTertiary) -> some View {
        // No letter spacing for right-to-left scripts: it would break Arabic's joined letters apart.
        font(.eyebrow).tracking(isRightToLeft ? 0 : 1.6).textCase(.uppercase).foregroundStyle(color)
    }

    /// Standard card container: raised surface with a hairline stroke.
    func card(padding: CGFloat = 18, radius: CGFloat = 22, fill: Color = Palette.surface) -> some View {
        self.padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.stroke))
    }
}

@MainActor
enum Haptics {
    static var isEnabled = true
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    static func tap() { if isEnabled { light.impactOccurred() } }
    static func move() { if isEnabled { medium.impactOccurred(intensity: 0.7) } }
    static func success() { if isEnabled { notification.notificationOccurred(.success) } }
    static func warning() { if isEnabled { notification.notificationOccurred(.warning) } }
}

/// The app's language is written right to left (Arabic). Boards, move lists and move navigation stay
/// left to right regardless; chess notation reads that way everywhere.
let isRightToLeft = Locale.current.language.characterDirection == .rightToLeft
