import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject private var look = LookFeel.shared
    @ObservedObject private var lyricsPrefs = LyricsPrefs.shared
    @ObservedObject private var playback = PlaybackPrefs.shared

    let onComplete: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Lunara.green.opacity(0.22),
                    Lunara.greenDeep.opacity(0.06),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 10,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    lyricsPlayerPage.tag(1)
                    audioThemePage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: page)

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                LunaraMark(size: 34, accent: Lunara.green)
                Text("Lunara")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            if page < 2 {
                Button {
                    onComplete()
                } label: {
                    Text("Skip")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(hex: 0x181818))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 16) {
                    LunaraMark(size: 76, accent: Lunara.green, animated: true)
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        Text("Music, uninterrupted.")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("Stream millions of tracks, save offline, and sing along — no account required.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .background(
                    ZStack {
                        Color(hex: 0x121212)
                        RadialGradient(
                            colors: [Lunara.green.opacity(0.16), .clear],
                            center: .top,
                            startRadius: 8,
                            endRadius: 210
                        )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                VStack(spacing: 10) {
                    featureCard(
                        icon: "bolt.fill",
                        title: "Instant streaming",
                        subtitle: "Search songs, albums, artists, and endless radio mixes right away."
                    )
                    featureCard(
                        icon: "arrow.down.circle.fill",
                        title: "Offline & local music",
                        subtitle: "Download tracks for flights or play audio saved on your device."
                    )
                    featureCard(
                        icon: "lock.shield.fill",
                        title: "Private by design",
                        subtitle: "Playlists, favorites, and Spotify imports stay locally on your phone."
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Lunara.green.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Lunara.neonGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(hex: 0x121212))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Page 2: Lyrics & Player Look

    private var lyricsPlayerPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Feel every beat and word.")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Synced word-by-word lyrics paired with an expressive neon-green player.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineSpacing(2)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        LunaraMark(size: 42, accent: Lunara.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Midnight Signals")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Lunara Radio")
                                .font(.system(size: 12))
                                .foregroundStyle(Lunara.neonGreen)
                        }
                        Spacer()
                        PlayingBars(color: Lunara.neonGreen, barWidth: 3, spacing: 3, height: 16)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Glowing through the dark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Lunara.neonGreen)
                        Text("Every note lands right on time")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x181818))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    OnboardingWavePreview(squiggly: look.sliderStyle == .wavy && look.squigglySlider)
                }
                .padding(16)
                .background(Color(hex: 0x121212))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Lunara.green.opacity(0.24), lineWidth: 1)
                )

                VStack(spacing: 0) {
                    onboardingToggle(
                        icon: "waveform.path",
                        title: "Squiggly scrubber",
                        subtitle: "Animated neon-green wave progress bar",
                        isOn: Binding(
                            get: { look.sliderStyle == .wavy && look.squigglySlider },
                            set: { enabled in
                                look.sliderStyle = enabled ? .wavy : .capsule
                                look.squigglySlider = enabled
                            }
                        )
                    )
                    Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                    onboardingToggle(
                        icon: "quote.bubble.fill",
                        title: "Word-by-word lyrics",
                        subtitle: "Highlight each syllable as the song plays",
                        isOn: $lyricsPrefs.lunaraStyle
                    )
                }
                .background(Color(hex: 0x121212))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Page 3: Audio & Theme

    private var audioThemePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tuned to your ears.")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                    Text("AMOLED true black and Spotify green, built for clean listening.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineSpacing(2)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dark & Neon Green")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Pure black OLED canvas with vibrant green controls")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.60))
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(Color.black).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            Circle().fill(Color(hex: 0x121212)).frame(width: 18, height: 18)
                            Circle().fill(Lunara.green).frame(width: 18, height: 18)
                            Circle().fill(Lunara.neonGreen).frame(width: 18, height: 18)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    Toggle(isOn: Binding(
                        get: { theme.pureBlack },
                        set: { theme.setPureBlack($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pure AMOLED black")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("True #000000 background across all tabs")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.60))
                        }
                    }
                    .tint(Lunara.green)
                }
                .padding(16)
                .background(Color(hex: 0x121212))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("AUDIO QUALITY")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.55))

                    HStack(spacing: 8) {
                        ForEach(AudioQuality.allCases) { q in
                            let selected = playback.quality == q
                            Button {
                                playback.quality = q
                            } label: {
                                Text(q.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(selected ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(selected ? Lunara.green : Color(hex: 0x181818))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(playback.quality.blurb)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.60))

                    Divider().overlay(Color.white.opacity(0.06))

                    onboardingToggle(
                        icon: "infinity",
                        title: "Gapless playback",
                        subtitle: "Seamless transitions between album tracks",
                        isOn: $playback.gapless
                    )
                }
                .padding(16)
                .background(Color(hex: 0x121212))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func onboardingToggle(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Lunara.neonGreen)
                .frame(width: 34, height: 34)
                .background(Lunara.green.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
            }
            .tint(Lunara.green)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Lunara.green : Color.white.opacity(0.24))
                        .frame(width: index == page ? 24 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }

            Button {
                if page < 2 {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        page += 1
                    }
                } else {
                    onComplete()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(page < 2 ? "Continue" : "Start Listening")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: page < 2 ? "arrow.right" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Lunara.green, Lunara.neonGreen],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Lunara.green.opacity(0.32), radius: 14, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        .padding(.top, 10)
        .padding(.bottom, 22)
    }
}

private struct OnboardingWavePreview: View {
    let squiggly: Bool
    @State private var start = Date()

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                Canvas { gc, size in
                    let midY = size.height / 2
                    let progressX = size.width * 0.62

                    var track = Path()
                    track.move(to: CGPoint(x: progressX, y: midY))
                    track.addLine(to: CGPoint(x: size.width, y: midY))
                    gc.stroke(track, with: .color(Color.white.opacity(0.18)),
                              style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

                    var active = Path()
                    if squiggly {
                        let steps = max(16, Int(progressX / 2))
                        for step in 0...steps {
                            let x = progressX * CGFloat(step) / CGFloat(steps)
                            let phase = Double(x) * 0.17 - elapsed * 4.5
                            let y = midY + CGFloat(sin(phase)) * 3.5
                            if step == 0 {
                                active.move(to: CGPoint(x: x, y: y))
                            } else {
                                active.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    } else {
                        active.move(to: CGPoint(x: 0, y: midY))
                        active.addLine(to: CGPoint(x: progressX, y: midY))
                    }

                    gc.stroke(
                        active,
                        with: .linearGradient(
                            Gradient(colors: [Lunara.green, Lunara.neonGreen]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: progressX, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )

                    let thumbRect = CGRect(x: progressX - 6, y: midY - 6, width: 12, height: 12)
                    gc.fill(Path(ellipseIn: thumbRect), with: .color(Lunara.neonGreen))
                }
            }
            .frame(height: 18)

            HStack {
                Text("1:42")
                Spacer()
                Text("3:08")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.55))
        }
    }
}
