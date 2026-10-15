import CMAFKit
import Foundation

protocol DASHClearKeyMediaProcessing {
    func process(segmentData: Data) async throws -> ParsedMediaSegment
    func finalize() async throws
}

extension DASHClearKeyMediaProcessor: DASHClearKeyMediaProcessing {}

enum DASHClearKeyTrackPipelineError: Error, Equatable {
    case segmentIndexOutOfRange(Int)
}

struct DASHClearKeyTrackPipeline {
    private let loader: any DASHResourceLoading
    private let processor: any DASHClearKeyMediaProcessing
    private let plan: DASHTrackPlan
    private let headers: [String: String]
    private let incompleteSegmentRetryCount: Int

    init(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        headers: [String: String],
        loader: any DASHResourceLoading = DASHResourceLoader(),
        incompleteSegmentRetryCount: Int = 3
    ) async throws {
        self.loader = loader
        self.processor = try await DASHClearKeyMediaProcessor(
            preparedTrack: preparedTrack,
            material: material
        )
        self.plan = preparedTrack.plan
        self.headers = headers
        self.incompleteSegmentRetryCount = max(0, incompleteSegmentRetryCount)
    }

    init(
        plan: DASHTrackPlan,
        headers: [String: String],
        loader: any DASHResourceLoading,
        processor: any DASHClearKeyMediaProcessing,
        incompleteSegmentRetryCount: Int = 3
    ) {
        self.plan = plan
        self.headers = headers
        self.loader = loader
        self.processor = processor
        self.incompleteSegmentRetryCount = max(0, incompleteSegmentRetryCount)
    }

    var segmentCount: Int {
        plan.mediaSegments.count
    }

    func processSegment(at index: Int) async throws -> ParsedMediaSegment {
        guard plan.mediaSegments.indices.contains(index) else {
            throw DASHClearKeyTrackPipelineError.segmentIndexOutOfRange(index)
        }
        return try await process(segment: plan.mediaSegments[index])
    }

    func process(segment: DASHResolvedSegment) async throws -> ParsedMediaSegment {
        var retry = 0
        while true {
            try Task.checkCancellation()
            let data = try await loader.loadData(from: segment.url, headers: headers)
            do {
                return try await processor.process(segmentData: data)
            } catch let error as BinaryIOError {
                guard case .insufficientData = error,
                      retry < incompleteSegmentRetryCount else {
                    throw error
                }

                // A live CMAF URL can become visible before its moof/mdat payload
                // is complete. CMAFMediaSegmentReader does not commit its
                // cross-segment state until parsing succeeds, so it is safe to
                // fetch the same segment again before giving up.
                retry += 1
                let delayMilliseconds = 150 * retry
                try await Task.sleep(
                    nanoseconds: UInt64(delayMilliseconds) * 1_000_000
                )
            }
        }
    }

    func processPlannedSegments() async throws -> [ParsedMediaSegment] {
        var output: [ParsedMediaSegment] = []
        output.reserveCapacity(plan.mediaSegments.count)
        for segment in plan.mediaSegments {
            output.append(try await process(segment: segment))
        }
        return output
    }

    func finalize() async throws {
        try await processor.finalize()
    }
}
