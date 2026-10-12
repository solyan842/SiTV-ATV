import CMAFKit
import CoreMedia
import Foundation

struct DASHVideoCodecParameters: Sendable, Equatable {
    enum Codec: Sendable, Equatable {
        case avc
        case hevc
    }

    let codec: Codec
    let parameterSets: [Data]
    let nalUnitHeaderLength: Int32
}

enum DASHVideoFormatFactoryError: Error, Equatable {
    case notVideoTrack
    case unsupportedVideoCodec
    case missingParameterSets
    case invalidNALUnitHeaderLength(Int)
    case coreMedia(OSStatus)
}

struct DASHVideoCodecParameterExtractor {
    func parameters(
        for track: CMAFTrackConfiguration
    ) throws -> DASHVideoCodecParameters {
        guard let video = track.videoFields else {
            throw DASHVideoFormatFactoryError.notVideoTrack
        }

        switch video.codecConfiguration {
        case .avc(let configuration):
            let sets = configuration.sequenceParameterSets.map(\.rbspBytes)
                + configuration.pictureParameterSets.map(\.rbspBytes)
            guard !configuration.sequenceParameterSets.isEmpty,
                  !configuration.pictureParameterSets.isEmpty else {
                throw DASHVideoFormatFactoryError.missingParameterSets
            }
            return try makeParameters(
                codec: .avc,
                parameterSets: sets,
                nalUnitHeaderLength: Int(configuration.lengthSize.rawValue)
            )

        case .hevc(let configuration):
            let requiredTypes: [UInt8] = [32, 33, 34] // VPS, SPS, PPS
            var sets: [Data] = []
            for type in requiredTypes {
                let matching = configuration.parameterSetArrays
                    .filter { $0.nalUnitType.rawValue == type }
                    .flatMap { $0.parameterSets.map(\.rbspBytes) }
                guard !matching.isEmpty else {
                    throw DASHVideoFormatFactoryError.missingParameterSets
                }
                sets.append(contentsOf: matching)
            }
            return try makeParameters(
                codec: .hevc,
                parameterSets: sets,
                nalUnitHeaderLength: Int(configuration.lengthSize.rawValue)
            )

        default:
            throw DASHVideoFormatFactoryError.unsupportedVideoCodec
        }
    }

    private func makeParameters(
        codec: DASHVideoCodecParameters.Codec,
        parameterSets: [Data],
        nalUnitHeaderLength: Int
    ) throws -> DASHVideoCodecParameters {
        guard (1...4).contains(nalUnitHeaderLength) else {
            throw DASHVideoFormatFactoryError.invalidNALUnitHeaderLength(
                nalUnitHeaderLength
            )
        }
        return DASHVideoCodecParameters(
            codec: codec,
            parameterSets: parameterSets,
            nalUnitHeaderLength: Int32(nalUnitHeaderLength)
        )
    }
}

struct DASHVideoFormatFactory {
    private let extractor = DASHVideoCodecParameterExtractor()

    func makeFormatDescription(
        for track: CMAFTrackConfiguration
    ) throws -> CMVideoFormatDescription {
        let parameters = try extractor.parameters(for: track)
        let storage = parameters.parameterSets.map { $0 as NSData }
        let pointers = storage.map {
            $0.bytes.assumingMemoryBound(to: UInt8.self)
        }
        let sizes = storage.map(\.length)

        var formatDescription: CMFormatDescription?
        let status = pointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                guard let pointerBase = pointerBuffer.baseAddress,
                      let sizeBase = sizeBuffer.baseAddress else {
                    return kCMFormatDescriptionError_InvalidParameter
                }

                switch parameters.codec {
                case .avc:
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: parameters.parameterSets.count,
                        parameterSetPointers: pointerBase,
                        parameterSetSizes: sizeBase,
                        nalUnitHeaderLength: parameters.nalUnitHeaderLength,
                        formatDescriptionOut: &formatDescription
                    )

                case .hevc:
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: parameters.parameterSets.count,
                        parameterSetPointers: pointerBase,
                        parameterSetSizes: sizeBase,
                        nalUnitHeaderLength: parameters.nalUnitHeaderLength,
                        extensions: nil,
                        formatDescriptionOut: &formatDescription
                    )
                }
            }
        }

        guard status == noErr else {
            throw DASHVideoFormatFactoryError.coreMedia(status)
        }
        guard let formatDescription else {
            throw DASHVideoFormatFactoryError.coreMedia(
                kCMFormatDescriptionError_InvalidParameter
            )
        }
        return formatDescription
    }
}
