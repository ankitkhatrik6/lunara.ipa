import SwiftUI
import UIKit

struct SlimSlider: View {
    @Binding var value: Double
    let active: Color
    var duration: Double = 0
    var isPlaying: Bool = true
    let onCommit: (Double) -> Void

    @ObservedObject private var look = LookFeel.shared

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Group {
                switch look.sliderStyle {
                case .slim:
                    SlimTrack(fraction: value, active: active)
                case .capsule:
                    CapsuleTrack(fraction: value, active: active,
                                 label: timeLabel, compact: false)
                case .wavy:
                    WavyTrack(fraction: value, active: active,
                              squiggly: look.squigglySlider, isPlaying: isPlaying)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in value = clamp(g.location.x / w) }
                    .onEnded { g in
                        let v = clamp(g.location.x / w)
                        value = v
                        onCommit(v)
                    },
            )
        }
        .frame(height: look.sliderStyle == .capsule ? 24 : 24)
    }

    private var timeLabel: String {
        guard duration > 0 else { return "•" }
        return "\(clock(value * duration)) / \(clock(duration))"
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

// MARK: - Slim

struct SlimTrack: View {
    let fraction: Double
    let active: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let filled = fraction.isFinite ? min(max(w * fraction, 8), w) : 8
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24)).frame(height: 8)
                Capsule().fill(active).frame(width: filled, height: 8)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Capsule

struct CapsuleTrack: View {
    let fraction: Double
    let active: Color
    let label: String
    var compact: Bool

    private var pillHeight: CGFloat { compact ? 14 : 20 }
    private var trackHeight: CGFloat { compact ? 2.5 : 3 }
    private var labelSize: CGFloat { compact ? 7 : 10 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pillWidth = min(templateWidth + (compact ? 16 : 28), w)
            let travel = max(w - pillWidth, 0)
            let x = travel * fraction

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24))
                    .frame(height: trackHeight)
                Capsule().fill(active)
                    .frame(width: x + pillWidth / 2, height: trackHeight)
                Capsule().fill(active)
                    .frame(width: pillWidth, height: pillHeight)
                    .overlay(
                        Text(label)
                            .font(.system(size: labelSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(active.isLight ? .black : .white)
                            .lineLimit(1),
                    )
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private var templateWidth: CGFloat {
        let template = String(label.map { $0.isNumber ? "8" : $0 })
        let font = UIFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .semibold)
        return (template as NSString).size(withAttributes: [.font: font]).width
    }
}

// MARK: - Wavy / Squiggly

struct WavyTrack: View {
    let fraction: Double
    let active: Color
    let squiggly: Bool
    let isPlaying: Bool
    var compact = false

    private var s: CGFloat { compact ? 0.66 : 1 }
    private var wavelength: CGFloat { (squiggly ? 28 : 40) * s }
    private var amplitude: CGFloat { (squiggly ? 3.8 : 5) * s }
    private var stroke: CGFloat { (squiggly ? 4.0 : 4.0) * s }
    private var speed: CGFloat { (squiggly ? 16 : 40) * s }
    private var gap: CGFloat { 4 * s }
    private var thumbRadius: CGFloat { 7 * s }

    private var inactive: Color { .white.opacity(0.28) }

    private var lineHeight: CGFloat { (amplitude + stroke) * 2 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            GeometryReader { geo in
                let w = geo.size.width
                let x = w * max(0, min(1, fraction))
                let phase = isPlaying
                    ? CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                        .truncatingRemainder(dividingBy: 10_000) * speed
                    : 0
                let amp = isPlaying ? amplitude : 0

                ZStack(alignment: .leading) {
                    if squiggly {
                        WavePath(amplitude: amp, wavelength: wavelength, phase: phase)
                            .stroke(active, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                            .mask(alignment: .leading) { Rectangle().frame(width: max(x - gap, 0)) }

                        Capsule().fill(inactive)
                            .frame(width: max(w - x - gap, 0), height: 3 * s)
                            .offset(x: min(x + gap, w))

                        Circle().fill(active)
                            .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                            .offset(x: min(max(x - thumbRadius, 0), max(w - thumbRadius * 2, 0)))
                    } else {
                        WavePath(amplitude: amp, wavelength: wavelength, phase: phase)
                            .stroke(active, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                            .mask(alignment: .leading) { Rectangle().frame(width: max(x - 12 * s, 0)) }

                        Capsule().fill(inactive)
                            .frame(width: max(w - x - 12 * s, 0), height: stroke)
                            .offset(x: min(x + 12 * s, w))

                        Circle().fill(active)
                            .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                            .offset(x: min(max(x - thumbRadius, 0), max(w - thumbRadius * 2, 0)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
                .frame(width: w, height: geo.size.height, alignment: .leading)
            }
        }
        .frame(height: max(lineHeight, thumbRadius * 2))
    }
}

struct WavePath: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat
    var phase: CGFloat
    var fadeFrom: CGFloat = .infinity
    var fadeLength: CGFloat = 1

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, wavelength > 0 else { return path }
        let mid = rect.midY

        func amp(at x: CGFloat, _ sign: CGFloat) -> CGFloat {
            guard fadeFrom.isFinite else { return sign * amplitude }
            let coeff = min(max((fadeFrom + fadeLength / 2 - x) / fadeLength, 0), 1)
            return sign * amplitude * coeff
        }

        let step = wavelength / 2
        var x = -phase.truncatingRemainder(dividingBy: wavelength) - step
        var sign: CGFloat = 1
        var current = amp(at: x, sign)
        path.move(to: CGPoint(x: x, y: mid + current))

        while x < rect.width {
            sign = -sign
            let nextX = x + step
            let midX = x + step / 2
            let next = amp(at: nextX, sign)
            path.addCurve(to: CGPoint(x: nextX, y: mid + next),
                          control1: CGPoint(x: midX, y: mid + current),
                          control2: CGPoint(x: midX, y: mid + next))
            current = next
            x = nextX
        }
        return path
    }
}
