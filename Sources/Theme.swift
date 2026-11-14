import SwiftUI
import UIKit

extension Image {
    init(bundleImage name: String) {
        self = Image(uiImage: UIImage(named: name) ?? UIImage())
    }
}

enum Lunara {
    static let green = Color(hex: 0x1DB954)
    static let neonGreen = Color(hex: 0x22C55E)
    static let greenDeep = Color(hex: 0x15803D)
    static let accent = green

    static let scaffold = Color(hex: 0x000000)
    static let surface = Color(hex: 0x121212)
    static let surfaceHigh = Color(hex: 0x181818)

    static let gradient = LinearGradient(
        colors: [green, neonGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [green, greenDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
