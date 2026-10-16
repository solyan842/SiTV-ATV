import AVFoundation
import CoreMedia
import Foundation

enum DASHSynchronizedRendererError: Error, Equatable {
    case notRunning
}

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
        // AVSampleBufferDisplayLayer can remain in a failed state after malformed
        // or incomplete media. Recover it before a later channel reuses this
        // long-lived renderer instance.
        if displayLayer.status == .failed {
            displayLayer.flushAndRemoveImage()
        }
        synchronizer.setRate(1, time: sourceTime)
    }

    func pause() {
        synchronizer.rate = 0
    }

    func primeVideo(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flushAndRemoveImage()
        }
        videoRenderer.enqueue(sampleBuffer)
    }

    func primeAudio(_ sampleBuffer: CMSampleBuffer) {
        audioRenderer.enqueue(sampleBuffer)
    }

    func enqueueVideo(_ sampleBuffer: CMSampleBuffer) async throws {
        try await waitUntilVideoReady()
        videoRenderer.enqueue(sampleBuffer)
    }

    func enqueueAudio(_ sampleBuffer: CMSampleBuffer) async throws {
        try await waitUntilAudioReady()
        audioRenderer.enqueue(sampleBuffer)
    }

    func flush() async {
        synchronizer.rate = 0
        videoRenderer.flush()
        audioRenderer.flush()
        displayLayer.flushAndRemoveImage()
    }

    private func waitUntilVideoReady() async throws {
        while !videoRenderer.isReadyForMoreMediaData {
            guard synchronizer.rate != 0 else {
                throw DASHSynchronizedRendererError.notRunning
            }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        guard synchronizer.rate != 0 else {
            throw DASHSynchronizedRendererError.notRunning
        }
    }

    private func waitUntilAudioReady() async throws {
        while !audioRenderer.isReadyForMoreMediaData {
            guard synchronizer.rate != 0 else {
                throw DASHSynchronizedRendererError.notRunning
            }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        guard synchronizer.rate != 0 else {
            throw DASHSynchronizedRendererError.notRunning
        }
    }
}
