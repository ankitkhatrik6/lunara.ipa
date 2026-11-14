import SwiftUI

struct LunaraMark: View {
    var size: CGFloat = 44
    var accent: Color = Lunara.green
    var animated: Bool = false

    @State private var pulse = false

    var body: some View {
        ZStack {
            if animated {
                Circle()
                    .stroke(accent.opacity(pulse ? 0.0 : 0.40), lineWidth: max(1.5, size * 0.03))
                    .frame(width: size * (pulse ? 1.48 : 1.0), height: size * (pulse ? 1.48 : 1.0))
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }

            Image(bundleImage: "icon")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .task(id: animated) {
            guard animated else { return }
            try? await Task.sleep(for: .milliseconds(60))
            pulse = true
        }
    }
}

struct LunaraLoader: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 44
    var tint: Color?

    @State private var start = Date()

    var body: some View {
        let accent = tint ?? palette.accent
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let angle = (elapsed * 260).truncatingRemainder(dividingBy: 360)
            let ringWidth = max(2.5, size * 0.085)

            ZStack {
                Circle()
                    .fill(Color(hex: 0x121212).opacity(0.85))

                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: ringWidth)

                Circle()
                    .trim(from: 0.06, to: 0.68)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                accent.opacity(0.08),
                                accent,
                                Lunara.neonGreen,
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(angle))

                HStack(alignment: .bottom, spacing: max(1.5, size * 0.055)) {
                    ForEach(0..<3, id: \.self) { index in
                        let wave = (sin(elapsed * (3.6 + Double(index) * 1.1) + Double(index) * 1.1) + 1) / 2
                        Capsule()
                            .fill(index == 1 ? Lunara.neonGreen : accent)
                            .frame(
                                width: max(2, size * 0.07),
                                height: max(size * 0.14, size * 0.34 * CGFloat(wave))
                            )
                    }
                }
                .frame(height: size * 0.36, alignment: .bottom)
            }
            .padding(ringWidth * 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Loading")
    }
}

struct LunaraDownloadLoader: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 44
    var tint: Color?

    @State private var start = Date()

    var body: some View {
        let accent = tint ?? palette.accent
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let phase = elapsed.truncatingRemainder(dividingBy: 1.2) / 1.2
            let angle = (elapsed * 220).truncatingRemainder(dividingBy: 360)
            let ringWidth = max(2, size * 0.09)
            let arrowOffset = sin(phase * .pi * 2) * (size * 0.07)

            ZStack {
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: ringWidth)

                Circle()
                    .trim(from: 0, to: 0.42)
                    .stroke(
                        LinearGradient(
                            colors: [accent, Lunara.neonGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(angle))

                Image(systemName: "arrow.down")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Lunara.neonGreen)
                    .offset(y: arrowOffset)
            }
            .padding(ringWidth * 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Downloading")
    }
}
