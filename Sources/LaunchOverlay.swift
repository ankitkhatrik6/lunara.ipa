import SwiftUI

struct LaunchSplashOverlay: View {
    let onFinished: () -> Void

    @State private var emblemScale: CGFloat = 0.84
    @State private var emblemOpacity: Double = 0
    @State private var ringScale1: CGFloat = 0.72
    @State private var ringOpacity1: Double = 0.55
    @State private var ringScale2: CGFloat = 0.72
    @State private var ringOpacity2: Double = 0.35
    @State private var textOpacity: Double = 0
    @State private var barProgress: CGFloat = 0.08

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Lunara.green.opacity(0.22),
                    Lunara.greenDeep.opacity(0.08),
                    .clear,
                ],
                center: .center,
                startRadius: 10,
                endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Lunara.green.opacity(ringOpacity1), lineWidth: 2)
                        .frame(width: 112, height: 112)
                        .scaleEffect(ringScale1)

                    Circle()
                        .stroke(Lunara.neonGreen.opacity(ringOpacity2), lineWidth: 1.5)
                        .frame(width: 112, height: 112)
                        .scaleEffect(ringScale2)

                    LunaraMark(size: 96, accent: Lunara.green)
                        .shadow(color: Lunara.green.opacity(0.38), radius: 26, y: 4)
                        .scaleEffect(emblemScale)
                        .opacity(emblemOpacity)
                }

                VStack(spacing: 8) {
                    Text("Lunara")
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(.white)

                    Text("Pure music. Zero noise.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
                .padding(.top, 24)
                .opacity(textOpacity)

                Spacer()

                VStack(spacing: 14) {
                    PlayingBars(color: Lunara.neonGreen, barWidth: 3.5, spacing: 4, height: 18)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(hex: 0x181818))
                            .frame(width: 164, height: 4)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Lunara.green, Lunara.neonGreen],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 164 * barProgress, height: 4)
                    }
                }
                .opacity(textOpacity)
                .padding(.bottom, 54)
            }
            .padding(.horizontal, 24)
        }
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                emblemScale = 1.0
                emblemOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.12)) {
                textOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                ringScale1 = 1.65
                ringOpacity1 = 0
            }
            withAnimation(.easeOut(duration: 1.15).delay(0.35).repeatForever(autoreverses: false)) {
                ringScale2 = 1.95
                ringOpacity2 = 0
            }
            withAnimation(.easeInOut(duration: 0.95)) {
                barProgress = 1.0
            }
            try? await Task.sleep(for: .milliseconds(1050))
            onFinished()
        }
    }
}
