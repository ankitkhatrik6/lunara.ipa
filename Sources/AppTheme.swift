import SwiftUI
import UIKit

enum DarkMode: String, CaseIterable {
    case auto, on, off

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .on: String(localized: "Dark")
        case .off: String(localized: "Light")
        }
    }
}

final class AppTheme: ObservableObject {
    static let shared = AppTheme()

    @Published private(set) var pureBlack: Bool
    @Published private(set) var dynamicTheme: Bool
    @Published private(set) var darkMode: DarkMode
    @Published private(set) var seed: Color

    private var artSeed: Color?
    private(set) var chosenSeed: Color

    private init() {
        pureBlack = UserDefaults.standard.object(forKey: "pureBlack") as? Bool ?? true
        dynamicTheme = UserDefaults.standard.object(forKey: "dynamicTheme") as? Bool ?? false
        darkMode = DarkMode(rawValue: UserDefaults.standard.string(forKey: "darkMode") ?? "") ?? .on
        let saved = UserDefaults.standard.object(forKey: "seedColor") as? Int
        chosenSeed = saved.map { Color(hex: UInt($0)) } ?? Lunara.green
        seed = chosenSeed
    }

    // MARK: Settings

    func setPureBlack(_ on: Bool) {
        pureBlack = on
        UserDefaults.standard.set(on, forKey: "pureBlack")
    }

    func setDynamicTheme(_ on: Bool) {
        dynamicTheme = on
        UserDefaults.standard.set(on, forKey: "dynamicTheme")
        recomputeSeed()
    }

    func setDarkMode(_ mode: DarkMode) {
        darkMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "darkMode")
    }

    func setSeedColor(_ color: Color) {
        chosenSeed = color
        UserDefaults.standard.set(Int(color.rgbHex), forKey: "seedColor")
        recomputeSeed()
    }

    func setArtworkSeed(_ color: Color?) {
        artSeed = color
        recomputeSeed()
    }

    private func recomputeSeed() {
        let next = (dynamicTheme ? artSeed : nil) ?? chosenSeed
        if next != seed { seed = next }
    }

    // MARK: Resolved scheme

    func isDark(_ scheme: ColorScheme) -> Bool {
        switch darkMode {
        case .auto: scheme == .dark
        case .on: true
        case .off: false
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch darkMode {
        case .auto: nil
        case .on: .dark
        case .off: .light
        }
    }

    var resolvedDark: Bool {
        switch darkMode {
        case .auto: UITraitCollection.current.userInterfaceStyle == .dark
        case .on: true
        case .off: false
        }
    }

    var scaffold: Color { scaffold(resolvedDark) }
    var surface: Color { surface(resolvedDark) }
    var surfaceHigh: Color { surfaceHigh(resolvedDark) }
    var accent: Color { accent(resolvedDark) }
    var onSurface: Color { onSurface(resolvedDark) }
    var onSurfaceVariant: Color { onSurfaceVariant(resolvedDark) }

    func scaffold(_ dark: Bool) -> Color {
        if dark && pureBlack { return .black }
        return dark ? seed.tone(4, chroma: 0.06) : seed.tone(98, chroma: 0.02)
    }

    func surface(_ dark: Bool) -> Color {
        if dark && pureBlack { return Color(hex: 0x121212) }
        return dark ? seed.tone(9, chroma: 0.08) : seed.tone(94, chroma: 0.03)
    }

    func surfaceHigh(_ dark: Bool) -> Color {
        if dark && pureBlack { return Color(hex: 0x181818) }
        return dark ? seed.tone(12, chroma: 0.10) : seed.tone(92, chroma: 0.04)
    }

    func accent(_ dark: Bool) -> Color {
        dark ? seed.tone(80, chroma: 0.62) : seed.tone(40, chroma: 0.70)
    }

    func onSurface(_ dark: Bool) -> Color { dark ? .white : Color(hex: 0x1A1A1A) }
    func onSurfaceVariant(_ dark: Bool) -> Color {
        dark ? .white.opacity(0.68) : Color(hex: 0x1A1A1A).opacity(0.62)
    }
}

extension Color {
    func tone(_ tone: Double, chroma: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let brightness = max(0, min(1, tone / 100))
        let sat = min(1, max(0, s * chroma * (tone < 50 ? 1.25 : 1.0)))
        return Color(hue: Double(h), saturation: Double(sat), brightness: brightness)
    }

    var rgbHex: UInt {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt(r * 255) << 16) | (UInt(g * 255) << 8) | UInt(b * 255)
    }
}

struct Palette: Equatable {
    let dark: Bool
    let scaffold: Color
    let surface: Color
    let surfaceHigh: Color
    let accent: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let onAccent: Color

    init(dark: Bool, theme: AppTheme = .shared) {
        self.dark = dark
        scaffold = theme.scaffold(dark)
        surface = theme.surface(dark)
        surfaceHigh = theme.surfaceHigh(dark)
        accent = theme.accent(dark)
        onSurface = theme.onSurface(dark)
        onSurfaceVariant = theme.onSurfaceVariant(dark)
        onAccent = dark ? theme.seed.tone(20, chroma: 0.5) : .white
    }

    var heroGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.tone(dark ? 55 : 48, chroma: 0.95)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var separator: Color { onSurface.opacity(0.08) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(dark: true)
}

private struct PlayerInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var playerBottomInset: CGFloat {
        get { self[PlayerInsetKey.self] }
        set { self[PlayerInsetKey.self] = newValue }
    }
}

private struct PlayerBottomPadding: ViewModifier {
    @Environment(\.playerBottomInset) private var inset

    func body(content: Content) -> some View {
        content.padding(.bottom, inset + 12)
    }
}

private struct PlayerBottomInsetArea: ViewModifier {
    @Environment(\.playerBottomInset) private var inset

    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, inset + 12)
    }
}

extension View {
    func playerBottomPadding() -> some View { modifier(PlayerBottomPadding()) }

    func playerBottomInsetArea() -> some View { modifier(PlayerBottomInsetArea()) }
}
