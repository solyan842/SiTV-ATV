import AVKit
import SwiftUI

struct PlayerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: model.avPlayerEngine.player)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 6) {
                if let channel = model.activeChannel {
                    Text(channel.name)
                        .font(.title2.bold())
                    if let attempt = model.activeAttempt {
                        Text("\(attempt.engine.rawValue) · nguồn \(attempt.sourceIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(36)
        }
        .onExitCommand {
            Task { await model.stopPlayback() }
        }
    }
}
