import SwiftUI
import UIKit

struct VLCPlayerSurface: UIViewRepresentable {
    let engine: VLCPlayerEngine

    func makeUIView(context: Context) -> UIView {
        engine.renderView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
