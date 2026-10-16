import AVKit
import SwiftUI

struct PlayerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.activeAttempt?.engine {
            case .dashClearKey:
                DASHRendererSurface(renderer: model.dashRenderer)
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

            if model.isPlaybackStarting, let channel = model.activeChannel {
                playbackStartingOverlay(channel)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isPlaybackStarting)
    }

    private func playbackStartingOverlay(_ channel: Channel) -> some View {
        HStack(spacing: 20) {
            AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "tv")
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .frame(width: 108, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                Text(channel.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(channel.group)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.orange)
                    Text("Đang mở kênh…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 520, alignment: .leading)
        .background(
            Color.black.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 110)
    }
}

private struct DASHRendererSurface: View {
    @ObservedObject var renderer: DASHSynchronizedRenderer

    var body: some View {
        DASHDisplayLayerView(displayLayer: renderer.displayLayer)
            .id(renderer.rendererGeneration)
    }
}
