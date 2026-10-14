import Foundation

protocol ClearKeyLicenseLoading: Sendable {
    func material(
        from licenseURL: URL,
        keyID: Data,
        headers: [String: String]
    ) async throws -> ClearKeyMaterial
}

enum ClearKeyLicenseError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case keyNotReturned
}

struct URLSessionClearKeyLicenseClient: ClearKeyLicenseLoading {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func material(
        from licenseURL: URL,
        keyID: Data,
        headers: [String: String]
    ) async throws -> ClearKeyMaterial {
        let kid = ClearKeyJWKParser.encodeBase64URL(keyID)
        let payload: [String: Any] = [
            "kids": [kid],
            "type": "temporary"
        ]

        var request = URLRequest(url: licenseURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SiTV/0.1 tvOS", forHTTPHeaderField: "User-Agent")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClearKeyLicenseError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClearKeyLicenseError.httpStatus(httpResponse.statusCode)
        }

        let materials = try ClearKeyJWKParser.materials(from: data)
        guard let material = materials.first(where: { $0.keyID == keyID }) else {
            throw ClearKeyLicenseError.keyNotReturned
        }
        return material
    }
}
