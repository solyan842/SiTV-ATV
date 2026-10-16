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
    let availabilityStartTime: Date?
    let publishTime: Date?
    let timeShiftBufferDepth: TimeInterval?
    let suggestedPresentationDelay: TimeInterval?

    init(
        type: ManifestType,
        minimumUpdatePeriod: TimeInterval?,
        baseURL: URL,
        periods: [DASHPeriod],
        availabilityStartTime: Date? = nil,
        publishTime: Date? = nil,
        timeShiftBufferDepth: TimeInterval? = nil,
        suggestedPresentationDelay: TimeInterval? = nil
    ) {
        self.type = type
        self.minimumUpdatePeriod = minimumUpdatePeriod
        self.baseURL = baseURL
        self.periods = periods
        self.availabilityStartTime = availabilityStartTime
        self.publishTime = publishTime
        self.timeShiftBufferDepth = timeShiftBufferDepth
        self.suggestedPresentationDelay = suggestedPresentationDelay
    }
}

struct DASHPeriod: Sendable, Equatable {
    let id: String?
    let baseURL: URL
    let adaptationSets: [DASHAdaptationSet]
    let start: TimeInterval?

    init(
        id: String?,
        baseURL: URL,
        adaptationSets: [DASHAdaptationSet],
        start: TimeInterval? = nil
    ) {
        self.id = id
        self.baseURL = baseURL
        self.adaptationSets = adaptationSets
        self.start = start
    }
}

struct DASHAdaptationSet: Sendable, Equatable {
    let id: String?
    let mimeType: String?
    let contentType: String?
    let codecs: String?
    let language: String?
    let baseURL: URL
    let segmentTemplate: DASHSegmentTemplate?
    let segmentBase: DASHSegmentBase?
    let contentProtections: [DASHContentProtection]
    let representations: [DASHRepresentation]

    init(
        id: String?,
        mimeType: String?,
        contentType: String?,
        codecs: String?,
        language: String?,
        baseURL: URL,
        segmentTemplate: DASHSegmentTemplate?,
        segmentBase: DASHSegmentBase? = nil,
        contentProtections: [DASHContentProtection],
        representations: [DASHRepresentation]
    ) {
        self.id = id
        self.mimeType = mimeType
        self.contentType = contentType
        self.codecs = codecs
        self.language = language
        self.baseURL = baseURL
        self.segmentTemplate = segmentTemplate
        self.segmentBase = segmentBase
        self.contentProtections = contentProtections
        self.representations = representations
    }
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
    let segmentBase: DASHSegmentBase?
    let contentProtections: [DASHContentProtection]

    init(
        id: String,
        bandwidth: Int?,
        width: Int?,
        height: Int?,
        mimeType: String?,
        codecs: String?,
        baseURL: URL,
        segmentTemplate: DASHSegmentTemplate?,
        segmentBase: DASHSegmentBase? = nil,
        contentProtections: [DASHContentProtection]
    ) {
        self.id = id
        self.bandwidth = bandwidth
        self.width = width
        self.height = height
        self.mimeType = mimeType
        self.codecs = codecs
        self.baseURL = baseURL
        self.segmentTemplate = segmentTemplate
        self.segmentBase = segmentBase
        self.contentProtections = contentProtections
    }

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
}

struct DASHSegmentTimelineEntry: Sendable, Equatable {
    let startTime: UInt64?
    let duration: UInt64
    let repeatCount: Int
}

struct DASHByteRange: Sendable, Equatable {
    let start: UInt64
    let end: UInt64

    init(start: UInt64, end: UInt64) {
        self.start = start
        self.end = end
    }

    var length: UInt64 {
        end >= start ? (end - start + 1) : 0
    }

    var httpHeaderValue: String {
        "bytes=\(start)-\(end)"
    }

    static func parse(_ value: String?) -> DASHByteRange? {
        guard let value else { return nil }
        let parts = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let start = UInt64(parts[0]),
              let end = UInt64(parts[1]),
              end >= start else {
            return nil
        }
        return DASHByteRange(start: start, end: end)
    }
}

struct DASHSegmentBase: Sendable, Equatable {
    let indexRange: DASHByteRange?
    let initializationRange: DASHByteRange?
    let initializationSourceURL: String?

    init(
        indexRange: DASHByteRange?,
        initializationRange: DASHByteRange?,
        initializationSourceURL: String? = nil
    ) {
        self.indexRange = indexRange
        self.initializationRange = initializationRange
        self.initializationSourceURL = initializationSourceURL
    }
}
