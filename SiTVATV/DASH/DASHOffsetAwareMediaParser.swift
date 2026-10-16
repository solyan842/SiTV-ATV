import CMAFKit
import Foundation

enum DASHOffsetAwareMediaParserError: Error, Equatable {
    case finalized
    case invalidTopLevelBox
    case mismatchedFragmentDataBoxes(moof: Int, mdat: Int)
    case missingMovieFragmentHeader
    case missingTrackFragmentHeader
    case missingSampleSize(trackID: UInt32, sampleIndex: Int)
    case sampleRangeOutsideMDAT(trackID: UInt32, sampleIndex: Int)
    case unsupportedBaseDataOffset(UInt64)
}

/// ISO-BMFF/CMAF media parser used by SiTV for real broadcast DASH.
///
/// CMAFKit 0.1.2's internal sample resolver deliberately walks mdat from byte
/// zero and ignores `trun.dataOffset` / `tfhd.baseDataOffset`. That is fine for
/// fragments emitted by its own writer, but not for all DASH packagers used by
/// MyTV/SeeNow. This parser keeps CMAFKit's public box decoder while resolving
/// sample byte positions according to ISO/IEC 14496-12.
actor DASHOffsetAwareMediaParser {
    private struct TrackDefaults: Sendable {
        let duration: UInt32
        let size: UInt32
        let flags: UInt32
    }

    private struct RawTopLevelBox: Equatable {
        let type: String
        let start: Int
        let size: Int
        let headerSize: Int

        var payloadStart: Int { start + headerSize }
        var end: Int { start + size }
    }

    private struct FragmentWalk {
        let samples: [CMAFParsedSample]
        let sequenceNumber: UInt32
        let baseDecodeTimes: [UInt32: UInt64]
    }

    private let encryptionContexts: [UInt32: TrackEncryptionBox]
    private let trackDefaults: [UInt32: TrackDefaults]
    private var nextSegmentIndex = 0
    private var isFinalized = false

    init(initSegmentData: Data) async throws {
        let initReader = try await CMAFInitSegmentReader(bytes: initSegmentData)
        let tracks = initReader.tracks()

        var contexts: [UInt32: TrackEncryptionBox] = [:]
        for track in tracks {
            if let parameters = track.encryptionParameters {
                contexts[track.trackID] = parameters.makeTrackEncryptionBox()
            }
        }
        encryptionContexts = contexts

        let registry = await BoxRegistry.defaultRegistry()
        let boxes = try await ISOBoxReader().readBoxes(from: initSegmentData, using: registry)
        var defaults: [UInt32: TrackDefaults] = [:]
        if let moov = boxes.compactMap({ $0 as? MovieBox }).first,
           let mvex = moov.children.compactMap({ $0 as? MovieExtendsBox }).first {
            for trex in mvex.children.compactMap({ $0 as? TrackExtendsBox }) {
                defaults[trex.trackID] = TrackDefaults(
                    duration: trex.defaultSampleDuration,
                    size: trex.defaultSampleSize,
                    flags: trex.defaultSampleFlags
                )
            }
        }
        trackDefaults = defaults
    }

    /// Test-only/fixture initializer that avoids constructing a full init segment.
    init(
        encryptionContexts: [UInt32: TrackEncryptionBox] = [:],
        trackDefaults: [UInt32: (duration: UInt32, size: UInt32, flags: UInt32)] = [:]
    ) {
        self.encryptionContexts = encryptionContexts
        self.trackDefaults = trackDefaults.mapValues {
            TrackDefaults(duration: $0.duration, size: $0.size, flags: $0.flags)
        }
    }

    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment {
        guard !isFinalized else {
            throw DASHOffsetAwareMediaParserError.finalized
        }

        let registry = await BoxRegistry.defaultRegistry()
        let boxes = try await ISOBoxReader().readBoxes(from: bytes, using: registry)
        let rawBoxes = try Self.scanTopLevelBoxes(in: bytes)

        let moofs = boxes.compactMap { $0 as? MovieFragmentBox }
        let rawMoofs = rawBoxes.filter { $0.type == "moof" }
        let rawMdats = rawBoxes.filter { $0.type == "mdat" }
        guard moofs.count == rawMoofs.count, moofs.count == rawMdats.count, !moofs.isEmpty else {
            throw DASHOffsetAwareMediaParserError.mismatchedFragmentDataBoxes(
                moof: moofs.count,
                mdat: rawMdats.count
            )
        }

        var allSamples: [CMAFParsedSample] = []
        var sequenceNumbers: [UInt32] = []
        var baseDecodeTimes: [UInt32: UInt64] = [:]

        for index in moofs.indices {
            let walk = try await resolveFragment(
                moof: moofs[index],
                rawMoof: rawMoofs[index],
                rawMdat: rawMdats[index],
                bytes: bytes
            )
            allSamples.append(contentsOf: walk.samples)
            sequenceNumbers.append(walk.sequenceNumber)
            for (trackID, time) in walk.baseDecodeTimes where baseDecodeTimes[trackID] == nil {
                baseDecodeTimes[trackID] = time
            }
        }

        let segmentIndices = boxes.compactMap { $0 as? SegmentIndexBox }
        let eventMessages = boxes.compactMap { $0 as? EventMessageBox }
        let result = ParsedMediaSegment(
            segmentIndex: nextSegmentIndex,
            samples: allSamples,
            movieFragmentSequenceNumbers: sequenceNumbers,
            baseMediaDecodeTimes: baseDecodeTimes,
            hasSegmentIndex: !segmentIndices.isEmpty,
            hasProducerReferenceTime: boxes.contains { $0 is ProducerReferenceTimeBox },
            eventMessages: eventMessages,
            segmentIndices: segmentIndices,
            isChunkedSegment: moofs.count > 1,
            firstSampleIsSyncSample: allSamples.first?.flags.isSyncSample ?? false
        )
        nextSegmentIndex += 1
        return result
    }

    func finalize() {
        isFinalized = true
    }

    private func resolveFragment(
        moof: MovieFragmentBox,
        rawMoof: RawTopLevelBox,
        rawMdat: RawTopLevelBox,
        bytes: Data
    ) async throws -> FragmentWalk {
        guard let mfhd = moof.children.compactMap({ $0 as? MovieFragmentHeaderBox }).first else {
            throw DASHOffsetAwareMediaParserError.missingMovieFragmentHeader
        }

        var samples: [CMAFParsedSample] = []
        var baseDecodeTimes: [UInt32: UInt64] = [:]
        var implicitDataCursor = rawMdat.payloadStart

        for traf in moof.children.compactMap({ $0 as? TrackFragmentBox }) {
            guard let tfhd = traf.children.compactMap({ $0 as? TrackFragmentHeaderBox }).first else {
                throw DASHOffsetAwareMediaParserError.missingTrackFragmentHeader
            }

            let tfdt = traf.children.compactMap { $0 as? TrackFragmentDecodeTimeBox }.first
            let baseDecodeTime = tfdt?.baseMediaDecodeTime ?? 0
            baseDecodeTimes[tfhd.trackID] = baseDecodeTime
            let defaults = trackDefaults[tfhd.trackID]
            let encryptionEntries = try await sampleEncryptionEntries(
                in: traf,
                context: encryptionContexts[tfhd.trackID]
            )

            let baseDataOffset = try resolveBaseDataOffset(
                tfhd: tfhd,
                rawMoof: rawMoof,
                bytesCount: bytes.count
            )

            var samplesEmittedInTrack = 0
            var accumulatedDuration: UInt64 = 0

            for trun in traf.children.compactMap({ $0 as? TrackRunBox }) {
                var cursor: Int
                if let dataOffset = trun.dataOffset {
                    let resolved = Int64(baseDataOffset) + Int64(dataOffset)
                    guard resolved >= 0, resolved <= Int64(Int.max) else {
                        throw DASHOffsetAwareMediaParserError.sampleRangeOutsideMDAT(
                            trackID: tfhd.trackID,
                            sampleIndex: samplesEmittedInTrack
                        )
                    }
                    cursor = Int(resolved)
                } else {
                    cursor = implicitDataCursor
                }

                for entryIndex in 0..<trun.table.count {
                    let entry = trun.table[entryIndex]
                    let duration = entry.sampleDuration
                        ?? tfhd.defaultSampleDuration
                        ?? defaults?.duration
                        ?? 0
                    let size = entry.sampleSize
                        ?? tfhd.defaultSampleSize
                        ?? defaults?.size
                        ?? 0
                    guard size > 0 else {
                        throw DASHOffsetAwareMediaParserError.missingSampleSize(
                            trackID: tfhd.trackID,
                            sampleIndex: samplesEmittedInTrack
                        )
                    }

                    let sampleSize = Int(size)
                    guard cursor >= rawMdat.payloadStart,
                          cursor <= rawMdat.end,
                          sampleSize <= rawMdat.end - cursor else {
                        throw DASHOffsetAwareMediaParserError.sampleRangeOutsideMDAT(
                            trackID: tfhd.trackID,
                            sampleIndex: samplesEmittedInTrack
                        )
                    }

                    let sampleBytes = bytes.subdata(in: cursor..<(cursor + sampleSize))
                    let flagsRaw = resolveSampleFlags(
                        entryIndex: entryIndex,
                        entry: entry,
                        trun: trun,
                        tfhd: tfhd,
                        trexDefault: defaults?.flags
                    )
                    let encryption = encryptionEntries.indices.contains(samplesEmittedInTrack)
                        ? Self.encryptionMetadata(encryptionEntries[samplesEmittedInTrack])
                        : nil
                    let composition = Int32(
                        truncatingIfNeeded: entry.sampleCompositionTimeOffset ?? 0
                    )

                    samples.append(
                        CMAFParsedSample(
                            trackID: tfhd.trackID,
                            bytes: sampleBytes,
                            durationInTimescale: duration,
                            compositionTimeOffset: composition,
                            flags: SampleFlags(rawValue: flagsRaw),
                            encryption: encryption,
                            decodeTime: baseDecodeTime + accumulatedDuration
                        )
                    )

                    accumulatedDuration += UInt64(duration)
                    samplesEmittedInTrack += 1
                    cursor += sampleSize
                }
                implicitDataCursor = cursor
            }
        }

        return FragmentWalk(
            samples: samples,
            sequenceNumber: mfhd.sequenceNumber,
            baseDecodeTimes: baseDecodeTimes
        )
    }

    private func resolveBaseDataOffset(
        tfhd: TrackFragmentHeaderBox,
        rawMoof: RawTopLevelBox,
        bytesCount: Int
    ) throws -> Int {
        if let absolute = tfhd.baseDataOffset {
            guard absolute <= UInt64(Int.max) else {
                throw DASHOffsetAwareMediaParserError.unsupportedBaseDataOffset(absolute)
            }
            let value = Int(absolute)
            guard value >= 0, value < bytesCount else {
                throw DASHOffsetAwareMediaParserError.unsupportedBaseDataOffset(absolute)
            }
            return value
        }

        // CMAF requires default-base-is-moof for independently addressable
        // fragments. For older DASH packagers that omit the flag, the first
        // traf's implicit base is still the current moof in a standalone media
        // segment, so using moof.start is the safe compatible interpretation.
        return rawMoof.start
    }

    private func sampleEncryptionEntries(
        in traf: TrackFragmentBox,
        context: TrackEncryptionBox?
    ) async throws -> [SampleEncryptionBox.SampleEncryptionEntry] {
        guard let context else { return [] }
        guard let unknown = traf.children.compactMap({ $0 as? UnknownBox })
            .first(where: { $0.actualType == "senc" }) else {
            return []
        }

        var reader = BinaryReader(unknown.payload)
        let registry = await BoxRegistry.defaultRegistry()
        let box = try await SampleEncryptionBox.parse(
            reader: &reader,
            header: unknown.header,
            registry: registry,
            ivSize: context.defaultPerSampleIVSize
        )
        return box.samples
    }

    private func resolveSampleFlags(
        entryIndex: Int,
        entry: TrackRunEntry,
        trun: TrackRunBox,
        tfhd: TrackFragmentHeaderBox,
        trexDefault: UInt32?
    ) -> UInt32 {
        if let flags = entry.sampleFlags {
            return flags
        }
        if entryIndex == 0,
           (trun.flags & TrackRunBox.flagFirstSampleFlags) != 0,
           let flags = trun.firstSampleFlags {
            return flags
        }
        if let flags = tfhd.defaultSampleFlags {
            return flags
        }
        return trexDefault ?? 0
    }

    private static func encryptionMetadata(
        _ entry: SampleEncryptionBox.SampleEncryptionEntry
    ) -> CMAFSampleInput.EncryptionMetadata {
        CMAFSampleInput.EncryptionMetadata(
            initializationVector: entry.initializationVector,
            subsamples: entry.subsamples
        )
    }

    private static func scanTopLevelBoxes(in data: Data) throws -> [RawTopLevelBox] {
        var output: [RawTopLevelBox] = []
        var offset = 0

        while offset < data.count {
            guard data.count - offset >= 8,
                  let size32 = data.readUInt32BE(at: offset) else {
                throw DASHOffsetAwareMediaParserError.invalidTopLevelBox
            }
            let typeBytes = data.subdata(in: (offset + 4)..<(offset + 8))
            guard let type = String(data: typeBytes, encoding: .ascii) else {
                throw DASHOffsetAwareMediaParserError.invalidTopLevelBox
            }

            let size: Int
            let headerSize: Int
            if size32 == 1 {
                guard data.count - offset >= 16,
                      let size64 = data.readUInt64BE(at: offset + 8),
                      size64 <= UInt64(Int.max) else {
                    throw DASHOffsetAwareMediaParserError.invalidTopLevelBox
                }
                size = Int(size64)
                headerSize = 16
            } else if size32 == 0 {
                size = data.count - offset
                headerSize = 8
            } else {
                size = Int(size32)
                headerSize = 8
            }

            guard size >= headerSize, size <= data.count - offset else {
                throw DASHOffsetAwareMediaParserError.invalidTopLevelBox
            }
            output.append(
                RawTopLevelBox(
                    type: type,
                    start: offset,
                    size: size,
                    headerSize: headerSize
                )
            )
            offset += size
        }
        return output
    }
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, count - offset >= 4 else { return nil }
        return self[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func readUInt64BE(at offset: Int) -> UInt64? {
        guard offset >= 0, count - offset >= 8 else { return nil }
        return self[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
