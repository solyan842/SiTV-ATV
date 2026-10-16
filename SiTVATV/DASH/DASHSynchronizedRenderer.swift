import AVFoundation
import Combine
import CoreMedia
import Foundation

enum DASHSynchronizedRendererError: Error, Equatable {
    case notRunning
}

@MainActor
final class DASHSynchronizedRenderer: ObservableObject {
    @Published private(set) var displayLayer: AVSampleBufferDisplayLayer

    private var synchronizer: AVSampleBufferRenderSynchronizer
    private var videoRenderer: AVSampleBufferVideoRenderer
    private var audioRenderer: AVSampleBufferAudioRenderer
    private(set) var rendererGeneration: UInt64 = 0

    init() {
        let graph = Self.makeRendererGraph()
        self.displayLayer = graph.displayLayer
        self.synchronizer = graph.synchronizer
        self.videoRenderer = graph.videoRenderer
        self.audioRenderer = graph.audioRenderer
    }

    var rate: Float {
        synchronizer.rate
    }

    func start(at sourceTime: CMTime = .zero) {
        ensureVideoRendererIsUsable()
        synchronizer.setRate(1, time: sourceTime)
    }

    func pause() {
        synchronizer.rate = 0
    }

    func primeVideo(_ sampleBuffer: CMSampleBuffer) {
        ensureVideoRendererIsUsable()
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
        // A failed AVSampleBufferVideoRenderer cannot be made reusable merely by
        // flushing it. More importantly, failed/ended live sessions can leave the
        // synchronizer timeline and decoder graph in a state that is unsuitable for
        // the next channel. Rebuild the complete render graph on every session stop
        // while keeping this observable host object stable for SwiftUI.
        rebuildRendererGraph()
    }

    private func ensureVideoRendererIsUsable() {
        if videoRenderer.status == .failed {
            rebuildRendererGraph()
            return
        }
        if videoRenderer.requiresFlushToResumeDecoding {
            videoRenderer.flush()
        }
    }

    private func rebuildRendererGraph() {
        synchronizer.rate = 0
        videoRenderer.flush()
        audioRenderer.flush()
        displayLayer.flushAndRemoveImage()

        let graph = Self.makeRendererGraph()
        synchronizer = graph.synchronizer
        videoRenderer = graph.videoRenderer
        audioRenderer = graph.audioRenderer
        displayLayer = graph.displayLayer
        rendererGeneration &+= 1
    }

    private func waitUntilVideoReady() async throws {
        while !videoRenderer.isReadyForMoreMediaData {
            guard synchronizer.rate != 0 else {
                throw DASHSynchronizedRendererError.notRunning
            }
            if videoRenderer.status == .failed {
                throw DASHSynchronizedRendererError.notRunning
            }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        guard synchronizer.rate != 0, videoRenderer.status != .failed else {
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

    private static func makeRendererGraph() -> (
        displayLayer: AVSampleBufferDisplayLayer,
        synchronizer: AVSampleBufferRenderSynchronizer,
        videoRenderer: AVSampleBufferVideoRenderer,
        audioRenderer: AVSampleBufferAudioRenderer
    ) {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect

        let synchronizer = AVSampleBufferRenderSynchronizer()
        let videoRenderer = displayLayer.sampleBufferRenderer
        let audioRenderer = AVSampleBufferAudioRenderer()
        synchronizer.addRenderer(videoRenderer)
        synchronizer.addRenderer(audioRenderer)

        return (displayLayer, synchronizer, videoRenderer, audioRenderer)
    }
}
