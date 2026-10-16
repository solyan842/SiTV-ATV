import CMAFKit
import Foundation
import XCTest
@testable import SiTVATV

final class DASHClearKeyLicenseSessionTests: XCTestCase {
    func testPrepareAcceptsOrgW3ClearKeyAndUsesLicenseServer() async throws {
        let kid = Data((0..<16).map(UInt8.init))
        let key = Data((16..<32).map(UInt8.init))
        let baseURL = URL(string: "https://example.com/live/")!
        let initURL = URL(string: "https://example.com/live/init-video.mp4")!
        let licenseURL = URL(string: "https://license.example/clearkey")!

        let template = DASHSegmentTemplate(
            initialization: "init-$RepresentationID$.mp4",
            media: "$Number$.m4s",
            timescale: 1,
            duration: 2,
            startNumber: 1,
            presentationTimeOffset: 0,
            timeline: []
        )
        let representation = DASHRepresentation(
            id: "video",
            bandwidth: 2_000_000,
            width: 1920,
            height: 1080,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: baseURL,
            segmentTemplate: template,
            contentProtections: []
        )
        let adaptation = DASHAdaptationSet(
            id: "v",
            mimeType: "video/mp4",
            contentType: "video",
            codecs: nil,
            language: nil,
            baseURL: baseURL,
            segmentTemplate: template,
            contentProtections: [],
            representations: [representation]
        )
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: baseURL,
            periods: [
                DASHPeriod(id: "p0", baseURL: baseURL, adaptationSets: [adaptation])
            ]
        )
        let source = StreamSource(
            url: "https://example.com/live/manifest.mpd",
            manifestType: "mpd",
            drmType: "org.w3.clearkey",
            drmKey: licenseURL.absoluteString,
            licenseURI: licenseURL.absoluteString,
            licenseHeaders: ["Authorization": "Bearer demo"]
        )
        let track = CENCTrackInfo(
            trackID: 1,
            kind: .video,
            scheme: .cenc,
            keyID: kid,
            perSampleIVSize: 8,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
        let session = DASHClearKeySession(
            loader: LicenseTestResourceLoader(
                manifest: manifest,
                dataByURL: [initURL: minimalLicenseInitSegment()]
            ),
            licenseClient: LicenseTestClient(
                expectedURL: licenseURL,
                expectedKeyID: kid,
                material: ClearKeyMaterial(keyID: kid, key: key)
            ),
            inspector: LicenseTestInspector(
                inspection: CENCInspection(tracks: [track])
            )
        )

        let prepared = try await session.prepare(source: source, segmentCount: 2)

        XCTAssertEqual(prepared.keyMaterial.keyID, kid)
        XCTAssertEqual(prepared.keyMaterial.key, key)
        XCTAssertEqual(prepared.video?.encryption.keyID, kid)
        XCTAssertEqual(prepared.video?.keyMaterial, ClearKeyMaterial(keyID: kid, key: key))
    }
}

private enum LicenseTestError: Error {
    case unexpectedRequest
}

private struct LicenseTestClient: ClearKeyLicenseLoading {
    let expectedURL: URL
    let expectedKeyID: Data
    let material: ClearKeyMaterial

    func material(
        from licenseURL: URL,
        keyID: Data,
        headers: [String: String]
    ) async throws -> ClearKeyMaterial {
        guard licenseURL == expectedURL,
              keyID == expectedKeyID,
              headers["Authorization"] == "Bearer demo" else {
            throw LicenseTestError.unexpectedRequest
        }
        return material
    }
}

private struct LicenseTestResourceLoader: DASHResourceLoading {
    let manifest: DASHManifest
    let dataByURL: [URL: Data]

    func loadManifest(from url: URL, headers: [String: String]) async throws -> DASHManifest {
        manifest
    }

    func loadData(from url: URL, headers: [String: String]) async throws -> Data {
        guard let data = dataByURL[url] else {
            throw DASHResourceLoaderError.httpStatus(404)
        }
        return data
    }
}

private struct LicenseTestInspector: CENCInspecting {
    let inspection: CENCInspection

    func inspect(initSegment data: Data) async throws -> CENCInspection {
        inspection
    }
}

private func minimalLicenseInitSegment() -> Data {
    Data([0x00, 0x00, 0x00, 0x08, 0x6d, 0x6f, 0x6f, 0x76])
}
