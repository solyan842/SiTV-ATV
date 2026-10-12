import Foundation

struct DASHManifest: Sendable, Equatable {
    enum ManifestType: String, Sendable {
        case `static`
        case dynamic
    }

    let type: ManifestType
    let minimumUpdatePeriod: TimeInterval?
    let baseURL: URL
    let periods: [DASHPeriod]
}

struct DASHPeriod: Sendable, Equatable {
    let id: String?
    let baseURL: URL
    let adaptationSets: [DASHAdaptationSet]
}

struct DASHAdaptationSet: Sendable, Equatable {
    let id: String?
    let mimeType: String?
    let contentType: String?
    let codecs: String?
    let language: String?
    let baseURL: URL
    let segmentTemplate: DASHSegmentTemplate?
    let contentProtections: [DASHContentProtection]
    let representations: [DASHRepresentation]
}

struct DASHRepresentation: Sendable, Equatable {
    let id: String
    let bandwidth: Int?
    let width: Int?
    let height: Int?
    let mimeType: String?
    let codecs: String?
    let baseURL: URL
    let segmentTemplate: DASHSegmentTemplate?
    let contentProtections: [DASHContentProtection]

    var defaultKeyID: UUID? {
        contentProtections.compactMap(\.defaultKeyID).first
    }
}

struct DASHContentProtection: Sendable, Equatable {
    let schemeIDURI: String?
    let value: String?
    let defaultKeyID: UUID?
}

struct DASHSegmentTemplate: Sendable, Equatable {
    let initialization: String?
    let media: String?
    let timescale: UInt64
    let duration: UInt64?
    let startNumber: UInt64
    let presentationTimeOffset: UInt64
    let timeline: [DASHSegmentTimelineEntry]

    func inheriting(from parent: DASHSegmentTemplate?) -> DASHSegmentTemplate {
        guard let parent else { return self }
        return DASHSegmentTemplate(
            initialization: initialization ?? parent.initialization,
            media: media ?? parent.media,
            timescale: timescale == 1 ? parent.timescale : timescale,
            duration: duration ?? parent.duration,
            startNumber: startNumber == 1 ? parent.startNumber : startNumber,
            presentationTimeOffset: presentationTimeOffset == 0 ? parent.presentationTimeOffset : presentationTimeOffset,
            timeline: timeline.isEmpty ? parent.timeline : timeline
        )
    }
}

struct DASHSegmentTimelineEntry: Sendable, Equatable {
    let startTime: UInt64?
    let duration: UInt64
    let repeatCount: Int
}
