import AVFoundation
import CoreMedia
import Foundation

@MainActor
final class DASHSynchronizedRenderer {
    let displayLayer: AVSampleBufferDisplayLayer

    private let synchronizer: AVSampleBufferRenderSynchronizer
    private let audioRenderer: AVSampleBufferAudioRenderer
    private let videoReceiver: AVSampleBufferVideoRenderer.Receiver
    private let audioReceiver: AVSampleBufferAudioRenderer.Receiver

    init() {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect

        let synchronizer = AVSampleBufferRenderSynchronizer()
        let audioRenderer = AVSampleBufferAudioRenderer()
        let videoReceiver = synchronizer.sampleBufferReceiver(
            adding: displayLayer.sampleBufferRenderer
        )
        let audioReceiver = synchronizer.sampleBufferReceiver(
            adding: audioRenderer
        )

        self.displayLayer = displayLayer
        self.synchronizer = synchronizer
        self.audioRenderer = audioRenderer
        self.videoReceiver = videoReceiver
        self.audioReceiver = audioReceiver
    }

    var rate: Float {
        synchronizer.rate
    }

    func start(at sourceTime: CMTime = .zero) {
        synchronizer.setRate(1, time: sourceTime)
    }

    func pause() {
        synchronizer.rate = 0
    }

    func enqueueVideo(_ sampleBuffer: CMSampleBuffer) async throws {
        let ready = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sampleBuffer
        )
        _ = try await videoReceiver.enqueue(ready)
    }

    func enqueueAudio(_ sampleBuffer: CMSampleBuffer) async throws {
        let ready = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sampleBuffer
        )
        _ = try await audioReceiver.enqueue(ready)
    }

    func flush() async {
        videoReceiver.flush()
        audioReceiver.flush()
    }
}
