import AudioToolbox
import CMAFKit
import CoreMedia
import Foundation

struct DASHAudioCodecParameters: Sendable, Equatable {
    let sampleRate: UInt32
    let channelCount: UInt32
    let magicCookie: Data
}

enum DASHAudioFormatFactoryError: Error, Equatable {
    case notAudioTrack
    case unsupportedAudioCodec
    case missingDecoderSpecificInfo
    case invalidSampleRate
    case invalidChannelCount
    case coreMedia(OSStatus)
}

struct DASHAudioCodecParameterExtractor {
    func parameters(
        for track: CMAFTrackConfiguration
    ) throws -> DASHAudioCodecParameters {
        guard let audio = track.audioFields else {
            throw DASHAudioFormatFactoryError.notAudioTrack
        }
        guard audio.sampleRate > 0 else {
            throw DASHAudioFormatFactoryError.invalidSampleRate
        }
        guard audio.channelCount > 0 else {
            throw DASHAudioFormatFactoryError.invalidChannelCount
        }

        switch audio.codecConfiguration {
        case .mp4Audio(let descriptor):
            guard descriptor.decoderConfig.objectTypeIndication == .aac else {
                throw DASHAudioFormatFactoryError.unsupportedAudioCodec
            }
            guard let magicCookie = descriptor.decoderConfig.decoderSpecificInfo,
                  !magicCookie.isEmpty else {
                throw DASHAudioFormatFactoryError.missingDecoderSpecificInfo
            }
            return DASHAudioCodecParameters(
                sampleRate: audio.sampleRate,
                channelCount: UInt32(audio.channelCount),
                magicCookie: magicCookie
            )

        default:
            throw DASHAudioFormatFactoryError.unsupportedAudioCodec
        }
    }
}

struct DASHAudioFormatFactory {
    private let extractor = DASHAudioCodecParameterExtractor()

    func makeFormatDescription(
        for track: CMAFTrackConfiguration
    ) throws -> CMAudioFormatDescription {
        let parameters = try extractor.parameters(for: track)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(parameters.sampleRate),
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: parameters.channelCount,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let status = parameters.magicCookie.withUnsafeBytes { cookieBytes in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: parameters.magicCookie.count,
                magicCookie: cookieBytes.baseAddress,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        }

        guard status == noErr else {
            throw DASHAudioFormatFactoryError.coreMedia(status)
        }
        guard let formatDescription else {
            throw DASHAudioFormatFactoryError.coreMedia(
                kCMFormatDescriptionError_InvalidParameter
            )
        }
        return formatDescription
    }
}
