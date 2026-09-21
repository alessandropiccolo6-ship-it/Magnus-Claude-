import SwiftUI
import UIKit

/// Palette "da palestra": nero, azzurro scuro e rosso.
enum Theme {
    static let background = Color(hex: 0x070709)        // nero
    static let surface = Color(hex: 0x121419)           // nero rialzato
    static let surfaceElevated = Color(hex: 0x1B1F27)
    static let navy = Color(hex: 0x0E2A4C)              // azzurro scuro
    static let navyLight = Color(hex: 0x1D4E89)
    static let red = Color(hex: 0xE0322E)               // rosso
    static let redDark = Color(hex: 0x9E1F1C)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.68)
    static let success = Color(hex: 0x37C56F)

    static var navyGradient: LinearGradient {
        LinearGradient(colors: [navyLight, navy], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var redGradient: LinearGradient {
        LinearGradient(colors: [red, redDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Barre di navigazione e tab bar nere.
    static func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(background)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(background)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Modificatori riutilizzabili

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
    func screenBackground() -> some View { modifier(ScreenBackground()) }

    /// Rende una List/Form coerente con il tema scuro.
    func themedList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.redGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.navyGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Etichetta compatta (es. "4 × 10", "90''").
struct Chip: View {
    enum Style { case navy, red, neutral, success }

    let text: String
    var systemImage: String? = nil
    var style: Style = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch style {
        case .navy: return Theme.navyLight
        case .red: return Theme.red
        case .neutral: return Theme.surfaceElevated
        case .success: return Theme.success.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .navy, .red: return .white
        case .neutral: return Theme.textSecondary
        case .success: return Theme.success
        }
    }
}
