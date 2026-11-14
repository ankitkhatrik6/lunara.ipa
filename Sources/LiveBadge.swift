import SwiftUI

struct LiveBadge: View {
    static let red = Color(hex: 0xE53935)

    var color: Color = LiveBadge.red

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.18))
        .clipShape(Capsule())
    }
}
