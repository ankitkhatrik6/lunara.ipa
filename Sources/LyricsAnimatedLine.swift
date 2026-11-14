import SwiftUI

struct LyricsAnimatedLine: View {
    let line: LyricLine
    let position: Double
    let style: LyricsAnimation
    let isActive: Bool
    let size: Double
    let spacing: Double
    let alignment: TextAlignment
    let frameAlignment: Alignment
    let color: Color
    var secondary: String?
    var secondaryAsMain = false

    private var font: Font { .system(size: size, weight: .bold) }
    private var leading: CGFloat { size * (spacing - 1) }
    private var displayText: String {
        if secondaryAsMain, let secondary, !secondary.isEmpty { return secondary }
        return line.text.isEmpty ? "♪" : line.text
    }

    private var animating: Bool {
        isActive && line.hasWordTimings && style != .none && !secondaryAsMain
    }

    var body: some View {
        VStack(alignment: frameAlignment.horizontal, spacing: 4) {
            primary
            if let secondary, !secondary.isEmpty, !secondaryAsMain {
                Text(secondary)
                    .font(.system(size: size * 0.6, weight: .medium))
                    .multilineTextAlignment(alignment)
                    .foregroundStyle(color.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
    }

    @ViewBuilder private var primary: some View {
        if !animating {
            plain
        } else {
            Group {
                switch style {
                case .karaoke: wipe(soft: false)
                case .apple: wipe(soft: true)
                case .fade, .glow, .slide: perWord
                case .none: plain
                }
            }
            .scaleEffect(bounce)
        }
    }

    private var bounce: Double {
        let fill = line.progress(at: position)
        guard fill < 0.3 else { return 1 }
        return 1 + sin(fill * 3.33 * .pi) * 0.03
    }

    // MARK: Flat

    private var plain: some View {
        Text(displayText)
            .font(font)
            .tracking(-0.5)
            .lineSpacing(leading)
            .multilineTextAlignment(alignment)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: Karaoke / Apple — a wipe across the whole line

    private func wipe(soft: Bool) -> some View {
        WordFlow(spacing: 0, lineSpacing: leading, alignment: frameAlignment) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                syllable(word.text + " ", progress: reveal(word), soft: soft)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func syllable(_ text: String, progress: Double, soft: Bool) -> some View {
        Text(text)
            .font(font)
            .tracking(-0.5)
            .foregroundStyle(color.opacity(0.35))
            .overlay {
                GeometryReader { geo in
                    Text(text)
                        .font(font)
                        .tracking(-0.5)
                        .foregroundStyle(color)
                        .shadow(color: soft ? color.opacity(0.5) : .clear, radius: 10)
                        .frame(width: geo.size.width, height: geo.size.height,
                               alignment: .leading)
                        .mask(alignment: .leading) {
                            if soft {
                                LinearGradient(stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: max(progress - 0.25, 0)),
                                    .init(color: .clear, location: min(progress + 0.25, 1)),
                                    .init(color: .clear, location: 1),
                                ], startPoint: .leading, endPoint: .trailing)
                            } else {
                                Rectangle().frame(width: geo.size.width * progress)
                            }
                        }
                }
            }
            .animation(.linear(duration: 0.12), value: progress)
    }

    // MARK: Fade / Glow / Slide — a view per word

    private var perWord: some View {
        WordFlow(spacing: 0, lineSpacing: leading, alignment: frameAlignment) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                let sung = reveal(word)
                Text(word.text + " ")
                    .font(font)
                    .tracking(-0.5)
                    .foregroundStyle(color.opacity(style == .fade ? 0.35 + 0.65 * sung : 1))
                    .opacity(style == .fade ? 1 : (0.4 + 0.6 * sung))
                    .shadow(color: style == .glow ? color.opacity(0.6 * sung) : .clear,
                            radius: 8 * sung)
                    .offset(y: style == .slide ? -3 * sung : 0)
                    .animation(.easeOut(duration: 0.18), value: sung)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func reveal(_ word: LyricWord) -> Double {
        guard word.end > word.start else { return position >= word.start ? 1 : 0 }
        return min(max((position - word.start) / (word.end - word.start), 0), 1)
    }
}

struct WordFlow: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 0
    var alignment: Alignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } +
            max(0, CGFloat(rows.count - 1)) * lineSpacing
        return CGSize(width: maxWidth == .infinity ? rows.map(\.width).max() ?? 0 : maxWidth,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            switch alignment.horizontal {
            case .trailing: x += bounds.width - row.width
            case .center: x += (bounds.width - row.width) / 2
            default: break
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.width == 0 ? size.width : row.width + spacing + size.width
            if next > maxWidth, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

struct IntervalIndicator: View {
    let start: Double
    let end: Double
    let position: Double
    let active: Bool
    let tint: Color

    private var progress: Double {
        let span = end - 0.65 - start
        guard span > 0 else { return 0 }
        return min(max((position - start) / span, 0), 1)
    }

    private var phase: Double {
        let loop = 2.6
        let t = position.truncatingRemainder(dividingBy: loop) / loop
        return t < 0 ? t + 1 : t
    }

    var body: some View {
        ZStack {
            floatingNotes
            glyph(breathe: 1 + 0.06 * abs(sin(phase * .pi)))
        }
        .opacity(active ? 1 : 0.25)
        .animation(.easeInOut(duration: 0.35), value: active)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: Self.height)
    }

    static let height: CGFloat = 118

    private func glyph(breathe: Double) -> some View {
        let size: CGFloat = 54
        return ZStack {
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint.opacity(0.26))
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, tint.opacity(0.95)],
                                                startPoint: .top, endPoint: .bottom))
                .mask(alignment: .bottom) {
                    GeometryReader { g in
                        Rectangle()
                            .frame(height: g.size.height * progress)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
        }
        .scaleEffect(breathe)
        .animation(.linear(duration: 0.12), value: progress)
    }

    private var floatingNotes: some View {
        ForEach(Self.notes, id: \.x) { note in
            let p = (phase + note.phase).truncatingRemainder(dividingBy: 1)
            let fade = sin(p * .pi) * sin(p * .pi) * 0.55
            Image(systemName: "music.note")
                .font(.system(size: note.size, weight: .medium))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(8 * sin((p + note.phase) * 2 * .pi)))
                .opacity(fade)
                .offset(x: note.x + note.drift * sin(p * 2 * .pi),
                        y: 30 - 84 * p)
        }
    }

    private struct Note {
        let x: CGFloat, size: CGFloat, phase: Double, drift: CGFloat
    }

    private static let notes: [Note] = [
        Note(x: -78, size: 13, phase: 0.00, drift: -7),
        Note(x: -50, size: 10, phase: 0.42, drift: 6),
        Note(x: 52, size: 12, phase: 0.68, drift: 7),
        Note(x: 82, size: 14, phase: 0.20, drift: -6),
        Note(x: -26, size: 9, phase: 0.85, drift: 5),
        Note(x: 30, size: 9, phase: 0.55, drift: -5),
    ]
}
