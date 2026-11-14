import AVKit
import SwiftUI

struct RoutePicker: UIViewRepresentable {
    var tint: UIColor
    var activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = activeTint
    }
}
