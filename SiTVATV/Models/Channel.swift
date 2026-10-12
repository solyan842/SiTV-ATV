import Foundation

struct StreamSource: Hashable, Codable, Sendable {
    let url: String
    let headers: [String: String]
    let manifestType: String?
    let drmType: String?
    let drmKey: String?
    let licenseURI: String?
    let licenseHeaders: [String: String]

    init(
        url: String,
        headers: [String: String] = [:],
        manifestType: String? = nil,
        drmType: String? = nil,
        drmKey: String? = nil,
        licenseURI: String? = nil,
        licenseHeaders: [String: String] = [:]
    ) {
        self.url = url
        self.headers = headers
        self.manifestType = manifestType
        self.drmType = drmType
        self.drmKey = drmKey
        self.licenseURI = licenseURI
        self.licenseHeaders = licenseHeaders
    }
}

struct Channel: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let group: String
    let logoURL: String?
    let sources: [StreamSource]
}
