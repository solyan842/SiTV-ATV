import SwiftUI
import UIKit

struct VLCPlayerSurface: UIViewRepresentable {
    let engine: VLCPlayerEngine

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        engine.attachDrawable(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        engine.attachDrawable(uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Void) {
        // The engine is stopped by AppModel/PlayerCoordinator when playback closes.
    }
}
