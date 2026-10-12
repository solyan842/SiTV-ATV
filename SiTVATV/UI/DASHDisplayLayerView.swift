import AVFoundation
import SwiftUI
import UIKit

struct DASHDisplayLayerView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> DASHDisplayLayerContainerView {
        DASHDisplayLayerContainerView(displayLayer: displayLayer)
    }

    func updateUIView(
        _ uiView: DASHDisplayLayerContainerView,
        context: Context
    ) {
        uiView.attach(displayLayer)
    }

    static func dismantleUIView(
        _ uiView: DASHDisplayLayerContainerView,
        coordinator: ()
    ) {
        uiView.detachDisplayLayer()
    }
}

final class DASHDisplayLayerContainerView: UIView {
    private var displayLayer: AVSampleBufferDisplayLayer?

    init(displayLayer: AVSampleBufferDisplayLayer) {
        super.init(frame: .zero)
        attach(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ displayLayer: AVSampleBufferDisplayLayer) {
        guard self.displayLayer !== displayLayer else {
            setNeedsLayout()
            return
        }

        self.displayLayer?.removeFromSuperlayer()
        displayLayer.removeFromSuperlayer()
        self.displayLayer = displayLayer
        layer.addSublayer(displayLayer)
        setNeedsLayout()
    }

    func detachDisplayLayer() {
        displayLayer?.removeFromSuperlayer()
        displayLayer = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds
    }
}
