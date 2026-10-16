import Foundation

enum DASHSegmentBasePlannerError: Error, Equatable {
    case missingPeriod
    case noPlayableRepresentations
    case missingSegmentBase
    case missingIndexRange
    case invalidSIDX
    case unsupportedSIDXVersion(UInt8)
    case unsupportedNestedSIDX
}

struct DASHSegmentBasePlanner {
    private let loader: any DASHResourceLoading

    init(loader: any DASHResourceLoading = DASHResourceLoader()) {
        self.loader = loader
    }

    func makePlan(
        from manifest: DASHManifest,
        headers: [String: String],
        maxVideoHeight: Int? = nil,
        segmentCount: Int = 6
    ) async throws -> DASHPlaybackPlan {
        let selected = try selectedPeriod(in: manifest)

        let videoCandidates = selected.period.adaptationSets
            .filter(isVideo)
            .flatMap(\.representations)
            .filter { $0.segmentBase?.indexRange != nil }
            .filter(isSupportedVideo)
            .filter { representation in
                guard let maxVideoHeight else { return true }
                guard let height = representation.height else { return true }
                return height <= maxVideoHeight
            }

        let audioCandidates = selected.period.adaptationSets
            .filter(isAudio)
            .flatMap(\.representations)
            .filter { $0.segmentBase?.indexRange != nil }
            .filter(isSupportedAudio)

        async let videoPlan = makeTrackPlan(
            representation: selectBest(videoCandidates),
            headers: headers,
            segmentCount: segmentCount
        )
        async let audioPlan = makeTrackPlan(
            representation: selectBest(audioCandidates),
            headers: headers,
            segmentCount: segmentCount
        )

        let plan = try await DASHPlaybackPlan(
            video: videoPlan,
            audio: audioPlan,
            periodIdentity: selected.identity
        )
        guard !plan.isEmpty else {
            throw DASHSegmentBasePlannerError.noPlayableRepresentations
        }
        return plan
    }

    private func makeTrackPlan(
        representation: DASHRepresentation?,
        headers: [String: String],
        segmentCount: Int
    ) async throws -> DASHTrackPlan? {
        guard let representation else { return nil }
        guard let segmentBase = representation.segmentBase else {
            throw DASHSegmentBasePlannerError.missingSegmentBase
        }
        guard let indexRange = segmentBase.indexRange else {
            throw DASHSegmentBasePlannerError.missingIndexRange
        }

        let mediaURL = representation.baseURL
        let indexData = try await loader.loadData(
            from: mediaURL,
            headers: headers,
            byteRange: indexRange
        )
        let mediaSegments = try parseSIDX(
            indexData,
            mediaURL: mediaURL,
            absoluteRangeStart: indexRange.start,
            maxCount: max(segmentCount, 1)
        )
        guard !mediaSegments.isEmpty else {
            throw DASHSegmentBasePlannerError.invalidSIDX
        }

        let initializationURL: URL
        if let sourceURL = segmentBase.initializationSourceURL,
           let resolved = URL(string: sourceURL, relativeTo: representation.baseURL)?.absoluteURL {
            initializationURL = resolved
        } else {
            initializationURL = representation.baseURL
        }

        let initializationRange: DASHByteRange?
        if let explicit = segmentBase.initializationRange {
            initializationRange = explicit
        } else if segmentBase.initializationSourceURL == nil, indexRange.start > 0 {
            initializationRange = DASHByteRange(start: 0, end: indexRange.start - 1)
        } else {
            initializationRange = nil
        }

        return DASHTrackPlan(
            representation: representation,
            initializationURL: initializationURL,
            initializationRange: initializationRange,
            mediaSegments: mediaSegments
        )
    }

    private func parseSIDX(
        _ data: Data,
        mediaURL: URL,
        absoluteRangeStart: UInt64,
        maxCount: Int
    ) throws -> [DASHResolvedSegment] {
        let bytes = [UInt8](data)
        var boxOffset = 0

        while boxOffset + 8 <= bytes.count {
            let size32 = readUInt32(bytes, at: boxOffset)
            let type = String(bytes: bytes[(boxOffset + 4)..<(boxOffset + 8)], encoding: .ascii)

            let headerSize: Int
            let boxSize: UInt64
            if size32 == 1 {
                guard boxOffset + 16 <= bytes.count else {
                    throw DASHSegmentBasePlannerError.invalidSIDX
                }
                headerSize = 16
                boxSize = readUInt64(bytes, at: boxOffset + 8)
            } else if size32 == 0 {
                headerSize = 8
                boxSize = UInt64(bytes.count - boxOffset)
            } else {
                headerSize = 8
                boxSize = UInt64(size32)
            }

            guard boxSize >= UInt64(headerSize),
                  boxSize <= UInt64(bytes.count - boxOffset),
                  boxSize <= UInt64(Int.max) else {
                throw DASHSegmentBasePlannerError.invalidSIDX
            }

            if type == "sidx" {
                return try parseSIDXBox(
                    bytes,
                    boxOffset: boxOffset,
                    headerSize: headerSize,
                    boxSize: boxSize,
                    mediaURL: mediaURL,
                    absoluteRangeStart: absoluteRangeStart,
                    maxCount: maxCount
                )
            }

            boxOffset += Int(boxSize)
        }

        throw DASHSegmentBasePlannerError.invalidSIDX
    }

    private func parseSIDXBox(
        _ bytes: [UInt8],
        boxOffset: Int,
        headerSize: Int,
        boxSize: UInt64,
        mediaURL: URL,
        absoluteRangeStart: UInt64,
        maxCount: Int
    ) throws -> [DASHResolvedSegment] {
        var cursor = boxOffset + headerSize
        guard cursor + 12 <= bytes.count else {
            throw DASHSegmentBasePlannerError.invalidSIDX
        }

        let version = bytes[cursor]
        cursor += 4 // version + flags
        _ = readUInt32(bytes, at: cursor) // reference_ID
        cursor += 4
        let timescale = readUInt32(bytes, at: cursor)
        cursor += 4
        guard timescale > 0 else {
            throw DASHSegmentBasePlannerError.invalidSIDX
        }

        let earliestPresentationTime: UInt64
        let firstOffset: UInt64
        switch version {
        case 0:
            guard cursor + 8 <= bytes.count else {
                throw DASHSegmentBasePlannerError.invalidSIDX
            }
            earliestPresentationTime = UInt64(readUInt32(bytes, at: cursor))
            cursor += 4
            firstOffset = UInt64(readUInt32(bytes, at: cursor))
            cursor += 4
        case 1:
            guard cursor + 16 <= bytes.count else {
                throw DASHSegmentBasePlannerError.invalidSIDX
            }
            earliestPresentationTime = readUInt64(bytes, at: cursor)
            cursor += 8
            firstOffset = readUInt64(bytes, at: cursor)
            cursor += 8
        default:
            throw DASHSegmentBasePlannerError.unsupportedSIDXVersion(version)
        }

        guard cursor + 4 <= bytes.count else {
            throw DASHSegmentBasePlannerError.invalidSIDX
        }
        cursor += 2 // reserved
        let referenceCount = Int(readUInt16(bytes, at: cursor))
        cursor += 2

        let absoluteSIDXEnd = try checkedAdd(
            absoluteRangeStart,
            UInt64(boxOffset),
            boxSize,
            firstOffset
        )
        var mediaOffset = absoluteSIDXEnd
        var presentationTime = earliestPresentationTime
        var number: UInt64 = 1
        var output: [DASHResolvedSegment] = []
        output.reserveCapacity(min(referenceCount, maxCount))

        for _ in 0..<referenceCount {
            guard cursor + 12 <= bytes.count else {
                throw DASHSegmentBasePlannerError.invalidSIDX
            }
            let referenceWord = readUInt32(bytes, at: cursor)
            cursor += 4
            let durationTicks = readUInt32(bytes, at: cursor)
            cursor += 4
            _ = readUInt32(bytes, at: cursor) // SAP data
            cursor += 4

            let isNestedIndex = (referenceWord & 0x8000_0000) != 0
            let referencedSize = UInt64(referenceWord & 0x7fff_ffff)
            guard referencedSize > 0 else {
                throw DASHSegmentBasePlannerError.invalidSIDX
            }
            if isNestedIndex {
                throw DASHSegmentBasePlannerError.unsupportedNestedSIDX
            }

            let end = try checkedAdd(mediaOffset, referencedSize - 1)
            output.append(
                DASHResolvedSegment(
                    number: number,
                    time: presentationTime,
                    duration: UInt64(durationTicks),
                    url: mediaURL,
                    byteRange: DASHByteRange(start: mediaOffset, end: end)
                )
            )
            if output.count == maxCount {
                return output
            }

            mediaOffset = try checkedAdd(mediaOffset, referencedSize)
            presentationTime = try checkedAdd(presentationTime, UInt64(durationTicks))
            number &+= 1
        }

        return output
    }

    private func selectedPeriod(
        in manifest: DASHManifest
    ) throws -> (period: DASHPeriod, identity: String) {
        guard !manifest.periods.isEmpty else {
            throw DASHSegmentBasePlannerError.missingPeriod
        }
        let index = manifest.type == .dynamic ? manifest.periods.count - 1 : 0
        let period = manifest.periods[index]
        let identity = period.id.map { "id:\($0)" }
            ?? "index:\(index)|base:\(period.baseURL.absoluteString)"
        return (period, identity)
    }

    private func selectBest(_ representations: [DASHRepresentation]) -> DASHRepresentation? {
        representations.max { lhs, rhs in
            let lhsBandwidth = lhs.bandwidth ?? 0
            let rhsBandwidth = rhs.bandwidth ?? 0
            if lhsBandwidth != rhsBandwidth {
                return lhsBandwidth < rhsBandwidth
            }
            let lhsPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
            let rhsPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
            return lhsPixels < rhsPixels
        }
    }

    private func isVideo(_ adaptation: DASHAdaptationSet) -> Bool {
        adaptation.contentType?.lowercased() == "video"
            || adaptation.mimeType?.lowercased().hasPrefix("video/") == true
            || adaptation.representations.contains {
                $0.mimeType?.lowercased().hasPrefix("video/") == true
            }
    }

    private func isAudio(_ adaptation: DASHAdaptationSet) -> Bool {
        adaptation.contentType?.lowercased() == "audio"
            || adaptation.mimeType?.lowercased().hasPrefix("audio/") == true
            || adaptation.representations.contains {
                $0.mimeType?.lowercased().hasPrefix("audio/") == true
            }
    }

    private func isSupportedVideo(_ representation: DASHRepresentation) -> Bool {
        let mime = representation.mimeType?.lowercased() ?? ""
        if mime.contains("webm") { return false }
        let codec = representation.codecs?.lowercased() ?? ""
        guard !codec.isEmpty else { return true }
        return codec.contains("avc1")
            || codec.contains("avc3")
            || codec.contains("hvc1")
            || codec.contains("hev1")
    }

    private func isSupportedAudio(_ representation: DASHRepresentation) -> Bool {
        let mime = representation.mimeType?.lowercased() ?? ""
        if mime.contains("webm") { return false }
        let codec = representation.codecs?.lowercased() ?? ""
        guard !codec.isEmpty else { return true }
        return codec.contains("mp4a") || codec.contains("aac")
    }

    private func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    private func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        UInt64(readUInt32(bytes, at: offset)) << 32
            | UInt64(readUInt32(bytes, at: offset + 4))
    }

    private func checkedAdd(_ values: UInt64...) throws -> UInt64 {
        var result: UInt64 = 0
        for value in values {
            let (next, overflow) = result.addingReportingOverflow(value)
            guard !overflow else {
                throw DASHSegmentBasePlannerError.invalidSIDX
            }
            result = next
        }
        return result
    }
}
