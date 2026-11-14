import SwiftUI

struct PlayingBars: View {
    var color: Color = .white
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var height: CGFloat = 18

    private let speeds: [Double] = [3.1, 4.7, 2.3]
    private let phases: [Double] = [0, 1.3, 2.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0 ..< 3, id: \.self) { bar in
                    let wave = (sin(t * speeds[bar] + phases[bar]) + 1) / 2
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(0.2, wave) * height)
                }
            }
            .frame(height: height, alignment: .bottom)
        }
    }
}
