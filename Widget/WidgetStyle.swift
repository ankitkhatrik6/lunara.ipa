import SwiftUI

enum Sleeve {
    static func paper(_ dark: Bool) -> Color {
        dark ? .black
             : Color(red: 0.98, green: 0.99, blue: 0.98)
    }
    static func tile(_ dark: Bool) -> Color {
        dark ? Color(red: 0.08, green: 0.08, blue: 0.08)
             : Color(red: 0.94, green: 0.96, blue: 0.95)
    }
    static func ink(_ dark: Bool) -> Color {
        dark ? .white : Color(red: 0.08, green: 0.09, blue: 0.08)
    }

    static let green = Color(red: 0.114, green: 0.725, blue: 0.329)
    static let neonGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

    static var gradient: LinearGradient {
        LinearGradient(colors: [green, neonGreen], startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }
}

struct SleeveHeader: View {
    var dark: Bool
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.34) {
            ZStack {
                Image("icon")
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: size, height: size)

            Text("Lunara")
                .font(.system(size: size * 0.68, weight: .bold))
                .foregroundStyle(Sleeve.ink(dark))
                .lineLimit(1)
        }
    }
}

struct SleeveTile: View {
    var symbol: String
    var title: LocalizedStringKey
    var url: URL
    var dark: Bool
    var icon: CGFloat
    var label: CGFloat

    var body: some View {
        Link(destination: url) {
            VStack(spacing: icon * 0.28) {
                Image(systemName: symbol)
                    .font(.system(size: icon, weight: .semibold))
                    .foregroundStyle(Sleeve.green)
                Text(title)
                    .font(.system(size: label, weight: .semibold))
                    .foregroundStyle(Sleeve.ink(dark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Sleeve.tile(dark))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
