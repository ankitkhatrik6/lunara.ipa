import SwiftUI
import UIKit

extension Font {
    static func lunara(_ size: CGFloat,
                       _ weight: Font.Weight = .regular,
                       relativeTo style: UIFont.TextStyle = .body) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size),
                weight: weight)
    }
}
