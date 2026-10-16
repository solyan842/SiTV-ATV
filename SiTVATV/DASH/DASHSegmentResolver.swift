import Foundation

enum DASHSegmentResolverError: Error, Equatable {
    case missingSegmentTemplate
    case missingInitializationTemplate
    case missingMediaTemplate
    case missingBandwidth
    case missingTime
    case unsupportedNegativeRepeat
    case invalidTemplateToken(String)
}

enum DASHSegmentSelection: Sendable, Equatable {
    case earliest
    case latest
}

struct DASHResolvedSegment: Sendable, Equatable {
    let number: UInt64
    let time: UInt64?
    let duration: UInt64?
    let url: URL
    let byteRange: DASHByteRange?

    init(
        number: UInt64,
        time: UInt64?,
        duration: UInt64?,
        url: URL,
        byteRange: DASHByteRange? = nil
    ) {
        self.number = number
        self.time = time
        self.duration = duration
        self.url = url
        self.byteRange = byteRange
    }
}

struct DASHSegmentResolver {
    func initializationURL(for representation: DASHRepresentation) throws -> URL {
        guard let template = representation.segmentTemplate else {
            throw DASHSegmentResolverError.missingSegmentTemplate
        }
        guard let initialization = template.initialization else {
            throw DASHSegmentResolverError.missingInitializationTemplate
        }

        let path = try render(
            initialization,
            representation: representation,
            number: template.startNumber,
            time: nil
        )
        return try resolve(path, against: representation.baseURL)
    }

    func mediaSegments(
        for representation: DASHRepresentation,
        maxCount: Int,
        selection: DASHSegmentSelection = .earliest
    ) throws -> [DASHResolvedSegment] {
        guard maxCount > 0 else { return [] }
        guard let template = representation.segmentTemplate else {
            throw DASHSegmentResolverError.missingSegmentTemplate
        }
        guard let media = template.media else {
            throw DASHSegmentResolverError.missingMediaTemplate
        }

        if !template.timeline.isEmpty {
            return try timelineSegments(
                template: template,
                media: media,
                representation: representation,
                maxCount: maxCount,
                selection: selection
            )
        }

        guard let duration = template.duration else {
            return []
        }

        // A duration-only dynamic template needs availability timing (for example
        // availabilityStartTime/publishTime) to derive the real live edge. Until
        // that timing is modeled, keep deterministic startNumber behavior rather
        // than pretending that the first generated window is the current live edge.
        return try (0..<maxCount).map { offset in
            let number = template.startNumber + UInt64(offset)
            let time = UInt64(offset) * duration
            let path = try render(
                media,
                representation: representation,
                number: number,
                time: time
            )
            return DASHResolvedSegment(
                number: number,
                time: time,
                duration: duration,
                url: try resolve(path, against: representation.baseURL)
            )
        }
    }

    private func timelineSegments(
        template: DASHSegmentTemplate,
        media: String,
        representation: DASHRepresentation,
        maxCount: Int,
        selection: DASHSegmentSelection
    ) throws -> [DASHResolvedSegment] {
        var result: [DASHResolvedSegment] = []
        var nextTime: UInt64 = 0
        var number = template.startNumber

        for entry in template.timeline {
            if entry.repeatCount < 0 {
                throw DASHSegmentResolverError.unsupportedNegativeRepeat
            }

            var currentTime = entry.startTime ?? nextTime
            let repetitions = entry.repeatCount + 1

            for _ in 0..<repetitions {
                let path = try render(
                    media,
                    representation: representation,
                    number: number,
                    time: currentTime
                )
                let segment = DASHResolvedSegment(
                    number: number,
                    time: currentTime,
                    duration: entry.duration,
                    url: try resolve(path, against: representation.baseURL)
                )

                switch selection {
                case .earliest:
                    result.append(segment)
                    if result.count == maxCount {
                        return result
                    }
                case .latest:
                    result.append(segment)
                    if result.count > maxCount {
                        result.removeFirst(result.count - maxCount)
                    }
                }

                currentTime += entry.duration
                number += 1
            }
            nextTime = currentTime
        }

        return result
    }

    private func render(
        _ template: String,
        representation: DASHRepresentation,
        number: UInt64,
        time: UInt64?
    ) throws -> String {
        let sentinel = "\u{0}DOLLAR\u{0}"
        var output = template.replacingOccurrences(of: "$$", with: sentinel)

        let pattern = #"\$(RepresentationID|Number|Time|Bandwidth)(%0([0-9]+)d)?\$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsOutput = output as NSString
        let matches = regex.matches(
            in: output,
            range: NSRange(location: 0, length: nsOutput.length)
        )

        for match in matches.reversed() {
            let token = nsOutput.substring(with: match.range(at: 1))
            let width: Int? = match.range(at: 3).location == NSNotFound
                ? nil
                : Int(nsOutput.substring(with: match.range(at: 3)))

            let replacement: String
            switch token {
            case "RepresentationID":
                replacement = representation.id
            case "Number":
                replacement = format(number, width: width)
            case "Time":
                guard let time else { throw DASHSegmentResolverError.missingTime }
                replacement = format(time, width: width)
            case "Bandwidth":
                guard let bandwidth = representation.bandwidth else {
                    throw DASHSegmentResolverError.missingBandwidth
                }
                replacement = format(UInt64(bandwidth), width: width)
            default:
                throw DASHSegmentResolverError.invalidTemplateToken(token)
            }

            output = (output as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        if let unresolvedRange = output.range(of: #"\$[^$]+\$"#, options: .regularExpression) {
            throw DASHSegmentResolverError.invalidTemplateToken(String(output[unresolvedRange]))
        }

        return output.replacingOccurrences(of: sentinel, with: "$")
    }

    private func format(_ value: UInt64, width: Int?) -> String {
        guard let width, width > 0 else { return String(value) }
        let raw = String(value)
        guard raw.count < width else { return raw }
        return String(repeating: "0", count: width - raw.count) + raw
    }

    private func resolve(_ path: String, against baseURL: URL) throws -> URL {
        if let url = URL(string: path, relativeTo: baseURL)?.absoluteURL {
            return url
        }
        throw DASHSegmentResolverError.invalidTemplateToken(path)
    }
}
