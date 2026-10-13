import XCTest
@testable import SiTVATV

final class PlayerEngineErrorTests: XCTestCase {
    func testUnsupportedHasUsefulLocalizedDescription() {
        let error = PlayerEngineError.unsupported
        XCTAssertEqual(
            error.localizedDescription,
            "Luồng này chưa được SiTV hỗ trợ trên Apple TV."
        )
    }

    func testFailedToStartIncludesReason() {
        let error = PlayerEngineError.failedToStart("HTTP 403")
        XCTAssertEqual(
            error.localizedDescription,
            "Không thể bắt đầu phát kênh: HTTP 403"
        )
    }

    func testFailedToStartWithoutReasonUsesFallbackMessage() {
        let error = PlayerEngineError.failedToStart("   ")
        XCTAssertEqual(
            error.localizedDescription,
            "Không thể bắt đầu phát kênh."
        )
    }

    func testStoppedHasUsefulLocalizedDescription() {
        let error = PlayerEngineError.stopped
        XCTAssertEqual(
            error.localizedDescription,
            "Phát kênh đã dừng."
        )
    }
}
