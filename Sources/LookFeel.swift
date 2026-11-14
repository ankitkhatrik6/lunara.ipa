import SwiftUI
import Combine

// MARK: - Options

enum LyricsPosition: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: String(localized: "Left")
        case .center: String(localized: "Center")
        case .right: String(localized: "Right")
        }
    }
    var scaleAnchor: UnitPoint {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var alignment: HorizontalAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
    var frameAlignment: Alignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}

enum SliderStyle: String, CaseIterable, Identifiable {
    case capsule, wavy, slim
    var id: String { rawValue }

    func title(squiggly: Bool) -> String {
        switch self {
        case .capsule: "Capsule"
        case .wavy: squiggly ? "Squiggly" : "Wavy"
        case .slim: "Slim"
        }
    }
}

enum NavBarStyle: String, CaseIterable, Identifiable {
    case pill, gradient, underline, outlined
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pill: String(localized: "Pill")
        case .gradient: String(localized: "Gradient")
        case .underline: String(localized: "Underline")
        case .outlined: String(localized: "Outlined")
        }
    }
}

enum GridItemSize: String, CaseIterable, Identifiable {
    case small, big
    var id: String { rawValue }
    var title: String { self == .small ? "Small" : "Big" }
    var cardWidth: CGFloat { self == .small ? 140 : 176 }
}

enum MiniPlayerDesign: String, CaseIterable, Identifiable {
    case flat, modern, rounded, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flat: String(localized: "Flat")
        case .modern: String(localized: "Modern")
        case .rounded: String(localized: "Rounded")
        case .floating: String(localized: "Floating")
        }
    }
    var subtitle: String {
        switch self {
        case .flat: "Edge-to-edge bar"
        case .modern: "Rounded pill, tap art to play"
        case .rounded: "Pill with previous / play / next"
        case .floating: "Boxy floating card"
        }
    }
    var usesArtBackground: Bool { self != .flat }
}

enum MiniPlayerBackground: String, CaseIterable, Identifiable {
    case followTheme, transparent, blur, gradient, pureBlack
    var id: String { rawValue }
    var title: String {
        switch self {
        case .followTheme: String(localized: "Follow theme")
        case .transparent: String(localized: "Transparent")
        case .blur: String(localized: "Blur")
        case .gradient: String(localized: "Gradient")
        case .pureBlack: String(localized: "Pure black")
        }
    }
}

enum DefaultTab: String, CaseIterable, Identifiable {
    case home, explore, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .explore: String(localized: "Search")
        case .library: String(localized: "Library")
        }
    }
    var tab: LunaraTab {
        switch self {
        case .home: .home
        case .explore: .explore
        case .library: .library
        }
    }
}

// MARK: - Store

final class LookFeel: ObservableObject {
    static let shared = LookFeel()

    @Published var lyricsPosition: LyricsPosition { didSet { save(lyricsPosition.rawValue, "lyricsPosition") } }
    @Published var sliderStyle: SliderStyle { didSet { save(sliderStyle.rawValue, "sliderStyle") } }
    @Published var squigglySlider: Bool { didSet { save(squigglySlider, "squigglySlider") } }
    @Published var navBarStyle: NavBarStyle { didSet { save(navBarStyle.rawValue, "navBarStyle") } }
    @Published var slimNavBar: Bool { didSet { save(slimNavBar, "slimNavBar") } }
    @Published var gridItemSize: GridItemSize { didSet { save(gridItemSize.rawValue, "gridItemSize") } }
    @Published var showHomeGreeting: Bool { didSet { save(showHomeGreeting, "showHomeGreeting") } }
    @Published var showHomeSearchBar: Bool { didSet { save(showHomeSearchBar, "showHomeSearchBar") } }
    @Published var defaultTab: DefaultTab { didSet { save(defaultTab.rawValue, "defaultOpenTab") } }
    @Published var swipeThumbnail: Bool { didSet { save(swipeThumbnail, "enableSwipeThumbnail") } }
    @Published var cropAlbumArt: Bool { didSet { save(cropAlbumArt, "cropAlbumArt") } }
    @Published var hidePlayerThumbnail: Bool { didSet { save(hidePlayerThumbnail, "hidePlayerThumbnail") } }
    @Published var miniPlayerDesign: MiniPlayerDesign { didSet { save(miniPlayerDesign.rawValue, "miniPlayerDesign") } }
    @Published var miniPlayerBackground: MiniPlayerBackground { didSet { save(miniPlayerBackground.rawValue, "miniPlayerBackground") } }

    private let defaults = UserDefaults.standard

    private init() {
        func read<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            guard let raw = UserDefaults.standard.string(forKey: key) else { return fallback }
            return T(rawValue: raw) ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
        }

        lyricsPosition = read("lyricsPosition", .center)
        sliderStyle = read("sliderStyle", .wavy)
        squigglySlider = flag("squigglySlider", true)
        navBarStyle = read("navBarStyle", .pill)
        slimNavBar = flag("slimNavBar", false)
        gridItemSize = read("gridItemSize", .small)
        showHomeGreeting = flag("showHomeGreeting", false)
        showHomeSearchBar = flag("showHomeSearchBar", false)
        defaultTab = read("defaultOpenTab", .home)
        swipeThumbnail = flag("enableSwipeThumbnail", true)
        cropAlbumArt = flag("cropAlbumArt", true)
        hidePlayerThumbnail = flag("hidePlayerThumbnail", false)
        miniPlayerDesign = read("miniPlayerDesign", .modern)
        miniPlayerBackground = read("miniPlayerBackground", .gradient)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
