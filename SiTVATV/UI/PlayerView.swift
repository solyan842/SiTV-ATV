import AVKit
import SwiftUI

struct PlayerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.activeAttempt?.engine {
            case .dashClearKey:
                DASHDisplayLayerView(displayLayer: model.dashRenderer.displayLayer)
                    .ignoresSafeArea()
                    .task(id: model.activeAttempt) {
                        await model.resumeDASHPlayback()
                    }
            case .vlc:
                VLCPlayerSurface(engine: model.vlcPlayerEngine)
                    .ignoresSafeArea()
            default:
                VideoPlayer(player: model.avPlayerEngine.player)
                    .ignoresSafeArea()
            }
        }
    }
}
