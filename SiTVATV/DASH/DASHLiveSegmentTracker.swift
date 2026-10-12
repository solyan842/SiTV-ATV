import Foundation

struct DASHLiveSegmentTracker: Sendable, Equatable {
    private(set) var latestTime: UInt64?
    private(set) var latestNumber: UInt64?

    init(seed segments: [DASHResolvedSegment] = []) {
        for segment in segments {
            mark(segment)
        }
    }

    mutating func unseenSegments(
        from segments: [DASHResolvedSegment]
    ) -> [DASHResolvedSegment] {
        var unseen: [DASHResolvedSegment] = []
        unseen.reserveCapacity(segments.count)

        for segment in segments {
            guard isNew(segment) else { continue }
            unseen.append(segment)
            mark(segment)
        }
        return unseen
    }

    mutating func mark(_ segment: DASHResolvedSegment) {
        latestNumber = max(latestNumber ?? segment.number, segment.number)
        if let time = segment.time {
            latestTime = max(latestTime ?? time, time)
        }
    }

    private func isNew(_ segment: DASHResolvedSegment) -> Bool {
        if let time = segment.time, let latestTime {
            return time > latestTime
        }
        if segment.time != nil, latestTime == nil {
            return segment.number > (latestNumber ?? 0)
        }
        return segment.number > (latestNumber ?? 0)
    }
}
