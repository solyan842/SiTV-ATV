import CMAFKit
import CoreMedia
import Foundation

enum DASHSampleBufferBuilderError: Error, Equatable {
    case invalidTimescale(UInt32)
    case decodeTimeOverflow(UInt64)
    case presentationTimeOverflow
    case blockBuffer(OSStatus)
    case sampleBuffer(OSStatus)
}

struct DASHSampleBufferBuilder {
    func makeSampleBuffer(
        sample: CMAFParsedSample,
        track: CMAFTrackConfiguration,
        formatDescription: CMFormatDescription
    ) throws -> CMSampleBuffer {
        guard track.timescale > 0,
              track.timescale <= UInt32(Int32.max) else {
            throw DASHSampleBufferBuilderError.invalidTimescale(track.timescale)
        }
        guard sample.decodeTime <= UInt64(Int64.max) else {
            throw DASHSampleBufferBuilderError.decodeTimeOverflow(sample.decodeTime)
        }

        let decodeValue = Int64(sample.decodeTime)
        let (presentationValue, overflow) = decodeValue.addingReportingOverflow(
            Int64(sample.compositionTimeOffset)
        )
        guard !overflow else {
            throw DASHSampleBufferBuilderError.presentationTimeOverflow
        }

        let timescale = CMTimeScale(track.timescale)
        var timing = CMSampleTimingInfo(
            duration: CMTime(
                value: CMTimeValue(sample.durationInTimescale),
                timescale: timescale
            ),
            presentationTimeStamp: CMTime(
                value: presentationValue,
                timescale: timescale
            ),
            decodeTimeStamp: CMTime(
                value: decodeValue,
                timescale: timescale
            )
        )

        let blockBuffer = try makeBlockBuffer(from: sample.bytes)
        var sampleSize = sample.bytes.count
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw DASHSampleBufferBuilderError.sampleBuffer(status)
        }
        return sampleBuffer
    }

    private func makeBlockBuffer(from data: Data) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard createStatus == noErr, let blockBuffer else {
            throw DASHSampleBufferBuilderError.blockBuffer(createStatus)
        }
        guard !data.isEmpty else {
            return blockBuffer
        }

        let copyStatus = data.withUnsafeBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        guard copyStatus == noErr else {
            throw DASHSampleBufferBuilderError.blockBuffer(copyStatus)
        }
        return blockBuffer
    }
}
