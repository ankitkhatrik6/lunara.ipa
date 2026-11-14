import CoreGraphics
import SwiftUI

enum VectorPath {
    static func tokens(_ data: String) -> [(command: Character, values: [Double])] {
        var out: [(Character, [Double])] = []
        var command: Character?
        var numbers: [Double] = []
        var current = ""

        func takeNumber() {
            if let value = Double(current) { numbers.append(value) }
            current = ""
        }
        func takeCommand() {
            takeNumber()
            if let command { out.append((command, numbers)) }
            numbers = []
        }

        for ch in data {
            if ch.isLetter {
                takeCommand()
                command = ch
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" {
                takeNumber()
            } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") {
                takeNumber()
                current = "-"
            } else {
                current.append(ch)
            }
        }
        takeCommand()
        return out
    }

    static func path(_ data: String, side: CGFloat, viewport: CGFloat = 24) -> Path {
        let scale = side / viewport
        var path = Path()
        var point = CGPoint.zero
        var lastControl: CGPoint?
        var start = CGPoint.zero

        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale)
        }

        for (command, values) in tokens(data) {
            let relative = command.isLowercase
            switch Character(command.lowercased()) {
            case "m":
                for i in stride(from: 0, to: values.count - 1, by: 2) {
                    let next = relative
                        ? CGPoint(x: point.x + CGFloat(values[i]) * scale,
                                  y: point.y + CGFloat(values[i + 1]) * scale)
                        : p(values[i], values[i + 1])
                    if i == 0 {
                        path.move(to: next)
                        start = next
                    } else {
                        path.addLine(to: next)
                    }
                    point = next
                }
                lastControl = nil

            case "l":
                for i in stride(from: 0, to: values.count - 1, by: 2) {
                    let next = relative
                        ? CGPoint(x: point.x + CGFloat(values[i]) * scale,
                                  y: point.y + CGFloat(values[i + 1]) * scale)
                        : p(values[i], values[i + 1])
                    path.addLine(to: next)
                    point = next
                }
                lastControl = nil

            case "c":
                for i in stride(from: 0, to: values.count - 5, by: 6) {
                    let base = relative ? point : .zero
                    let c1 = CGPoint(x: base.x + CGFloat(values[i]) * scale,
                                     y: base.y + CGFloat(values[i + 1]) * scale)
                    let c2 = CGPoint(x: base.x + CGFloat(values[i + 2]) * scale,
                                     y: base.y + CGFloat(values[i + 3]) * scale)
                    let end = CGPoint(x: base.x + CGFloat(values[i + 4]) * scale,
                                      y: base.y + CGFloat(values[i + 5]) * scale)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    lastControl = c2
                    point = end
                }

            case "s":
                for i in stride(from: 0, to: values.count - 3, by: 4) {
                    let base = relative ? point : .zero
                    let mirrored = lastControl.map {
                        CGPoint(x: point.x * 2 - $0.x, y: point.y * 2 - $0.y)
                    } ?? point
                    let c2 = CGPoint(x: base.x + CGFloat(values[i]) * scale,
                                     y: base.y + CGFloat(values[i + 1]) * scale)
                    let end = CGPoint(x: base.x + CGFloat(values[i + 2]) * scale,
                                      y: base.y + CGFloat(values[i + 3]) * scale)
                    path.addCurve(to: end, control1: mirrored, control2: c2)
                    lastControl = c2
                    point = end
                }

            case "z":
                path.closeSubpath()
                point = start
                lastControl = nil

            default:
                continue
            }
        }
        return path
    }
}
