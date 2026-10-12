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

    init(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        headers: [String: String],
        loader: any DASHResourceLoading = DASHResourceLoader()
    ) async throws {
        self.loader = loader
        self.processor = try await DASHClearKeyMediaProcessor(
            preparedTrack: preparedTrack,
            material: material
        )
        self.plan = preparedTrack.plan
        self.headers = headers
    }

    init(
        plan: DASHTrackPlan,
        headers: [String: String],
        loader: any DASHResourceLoading,
        processor: any DASHClearKeyMediaProcessing
    ) {
        self.plan = plan
        self.headers = headers
        self.loader = loader
        self.processor = processor
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
        let data = try await loader.loadData(from: segment.url, headers: headers)
        return try await processor.process(segmentData: data)
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
