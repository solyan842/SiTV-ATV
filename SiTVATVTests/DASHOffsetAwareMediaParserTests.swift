import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHOffsetAwareMediaParserTests: XCTestCase {
    func testUsesTrunDataOffsetInsteadOfBeginningOfMDAT() async throws {
        let expectedSample = Data([0x11, 0x22, 0x33, 0x44])
        let padding = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x77])

        let placeholderMoof = makeMoof(dataOffset: 0, sampleSize: expectedSample.count)
        let dataOffset = Int32(placeholderMoof.count + 8 + padding.count)
        let moof = makeMoof(dataOffset: dataOffset, sampleSize: expectedSample.count)
        XCTAssertEqual(moof.count, placeholderMoof.count)

        let mdat = box("mdat", payload: padding + expectedSample)
        let parser = DASHOffsetAwareMediaParser()
        let parsed = try await parser.appendSegmentBytes(moof + mdat)

        let sample = try XCTUnwrap(parsed.samples.first)
        XCTAssertEqual(parsed.samples.count, 1)
        XCTAssertEqual(sample.trackID, 7)
        XCTAssertEqual(sample.bytes, expectedSample)
        XCTAssertEqual(sample.durationInTimescale, 3_000)
        XCTAssertEqual(sample.decodeTime, 9_000)
        XCTAssertTrue(sample.flags.isSyncSample)
    }

    func testUsesTrexDefaultsWhenTrunOmitsSizeAndDuration() async throws {
        let expectedSample = Data([0x51, 0x52, 0x53])
        let placeholderMoof = makeMoofUsingDefaults(dataOffset: 0)
        let dataOffset = Int32(placeholderMoof.count + 8)
        let moof = makeMoofUsingDefaults(dataOffset: dataOffset)

        let parser = DASHOffsetAwareMediaParser(
            trackDefaults: [7: (duration: 1_024, size: UInt32(expectedSample.count), flags: 0)]
        )
        let parsed = try await parser.appendSegmentBytes(moof + box("mdat", payload: expectedSample))
        let sample = try XCTUnwrap(parsed.samples.first)
        XCTAssertEqual(sample.bytes, expectedSample)
        XCTAssertEqual(sample.durationInTimescale, 1_024)
    }

    private func makeMoof(dataOffset: Int32, sampleSize: Int) -> Data {
        let mfhd = fullBox("mfhd", version: 0, flags: 0, body: u32(17))
        let tfhd = fullBox("tfhd", version: 0, flags: 0x020000, body: u32(7))
        let tfdt = fullBox("tfdt", version: 1, flags: 0, body: u64(9_000))

        var trunBody = Data()
        trunBody.append(u32(1))
        trunBody.append(i32(dataOffset))
        trunBody.append(u32(3_000))
        trunBody.append(u32(UInt32(sampleSize)))
        trunBody.append(u32(0))
        let trun = fullBox(
            "trun",
            version: 0,
            flags: 0x000001 | 0x000100 | 0x000200 | 0x000400,
            body: trunBody
        )
        let traf = box("traf", payload: tfhd + tfdt + trun)
        return box("moof", payload: mfhd + traf)
    }

    private func makeMoofUsingDefaults(dataOffset: Int32) -> Data {
        let mfhd = fullBox("mfhd", version: 0, flags: 0, body: u32(18))
        let tfhd = fullBox("tfhd", version: 0, flags: 0x020000, body: u32(7))
        let tfdt = fullBox("tfdt", version: 1, flags: 0, body: u64(12_000))

        var trunBody = Data()
        trunBody.append(u32(1))
        trunBody.append(i32(dataOffset))
        let trun = fullBox("trun", version: 0, flags: 0x000001, body: trunBody)
        let traf = box("traf", payload: tfhd + tfdt + trun)
        return box("moof", payload: mfhd + traf)
    }

    private func fullBox(_ type: String, version: UInt8, flags: UInt32, body: Data) -> Data {
        var payload = Data([version])
        payload.append(UInt8((flags >> 16) & 0xff))
        payload.append(UInt8((flags >> 8) & 0xff))
        payload.append(UInt8(flags & 0xff))
        payload.append(body)
        return box(type, payload: payload)
    }

    private func box(_ type: String, payload: Data) -> Data {
        var output = u32(UInt32(payload.count + 8))
        output.append(contentsOf: type.utf8)
        output.append(payload)
        return output
    }

    private func u32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    private func i32(_ value: Int32) -> Data {
        u32(UInt32(bitPattern: value))
    }

    private func u64(_ value: UInt64) -> Data {
        Data([
            UInt8((value >> 56) & 0xff),
            UInt8((value >> 48) & 0xff),
            UInt8((value >> 40) & 0xff),
            UInt8((value >> 32) & 0xff),
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}
