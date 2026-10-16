import XCTest
@testable import SiTVATV

final class DASHISOBMFFValidatorTests: XCTestCase {
    private let validator = DASHISOBMFFValidator()

    func testAcceptsInitializationSegmentContainingMoov() throws {
        let data = box(type: "ftyp") + box(type: "moov", payload: Data([0x01]))
        XCTAssertNoThrow(try validator.validateInitializationSegment(data))
    }

    func testRejectsShortInitializationErrorBody() {
        let data = Data(repeating: 0x41, count: 74)
        XCTAssertThrowsError(try validator.validateInitializationSegment(data)) { error in
            XCTAssertEqual(
                error as? DASHISOBMFFValidationError,
                .invalidInitializationSegment(bytes: 74)
            )
        }
    }

    func testAcceptsMediaSegmentContainingMoofAndMdat() throws {
        let data = box(type: "styp")
            + box(type: "moof", payload: Data([0x01]))
            + box(type: "mdat", payload: Data([0x02, 0x03]))
        XCTAssertNoThrow(try validator.validateMediaSegment(data))
    }

    func testRejectsMediaSegmentMissingMdat() {
        let data = box(type: "moof", payload: Data([0x01]))
        XCTAssertThrowsError(try validator.validateMediaSegment(data)) { error in
            XCTAssertEqual(
                error as? DASHISOBMFFValidationError,
                .invalidMediaSegment(bytes: data.count)
            )
        }
    }

    func testRejectsTruncatedBoxEvenWhenTypeLooksValid() {
        var data = Data([0x00, 0x00, 0x00, 0x20])
        data.append(Data("moof".utf8))
        data.append(Data(repeating: 0x00, count: 4))

        XCTAssertThrowsError(try validator.validateMediaSegment(data)) { error in
            XCTAssertEqual(
                error as? DASHISOBMFFValidationError,
                .invalidMediaSegment(bytes: data.count)
            )
        }
    }

    private func box(type: String, payload: Data = Data()) -> Data {
        precondition(type.utf8.count == 4)
        let size = UInt32(8 + payload.count)
        var result = Data([
            UInt8((size >> 24) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8(size & 0xff)
        ])
        result.append(Data(type.utf8))
        result.append(payload)
        return result
    }
}
