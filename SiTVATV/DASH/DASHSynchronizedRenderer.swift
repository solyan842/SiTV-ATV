import AVFoundation
import CoreMedia
import Foundation

@MainActor
final class DASHSynchronizedRenderer {
    let displayLayer: AVSampleBufferDisplayLayer

    private let synchronizer: AVSampleBufferRenderSynchronizer
    private let videoRenderer: AVSampleBufferVideoRenderer
    private let audioRenderer: AVSampleBufferAudioRenderer

    init() {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect

        let synchronizer = AVSampleBufferRenderSynchronizer()
        let videoRenderer = displayLayer.sampleBufferRenderer
        let audioRenderer = AVSampleBufferAudioRenderer()
        synchronizer.addRenderer(videoRenderer)
        synchronizer.addRenderer(audioRenderer)

        self.displayLayer = displayLayer
        self.synchronizer = synchronizer
        self.videoRenderer = videoRenderer
        self.audioRenderer = audioRenderer
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
        videoRenderer.enqueue(sampleBuffer)
    }

    func enqueueAudio(_ sampleBuffer: CMSampleBuffer) async throws {
        audioRenderer.enqueue(sampleBuffer)
    }

    func flush() async {
        videoRenderer.flush()
        audioRenderer.flush()
    }
}
