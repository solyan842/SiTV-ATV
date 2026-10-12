import Foundation

struct M3UParser: Sendable {
    func parse(_ text: String) -> [Channel] {
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard lines.contains(where: { $0.uppercased().hasPrefix("#EXTM3U") }) else { return [] }

        var channels: [Channel] = []
        var metadata: Metadata?
        var sources: [StreamSource] = []
        var manifestType: String?
        var drmType: String?
        var drmKey: String?
        var licenseURI: String?
        var licenseHeaders: [String: String] = [:]
        var vlcReferrer: String?
        var vlcUserAgent: String?

        func flush() {
            guard let meta = metadata else { return }
            if !sources.isEmpty {
                let id = meta.id.isEmpty ? slug(meta.name) : meta.id
                channels.append(
                    Channel(
                        id: id,
                        name: meta.name.isEmpty ? "Kênh" : meta.name,
                        group: meta.group.isEmpty ? "Khác" : meta.group,
                        logoURL: meta.logo.isEmpty ? nil : meta.logo,
                        sources: sources
                    )
                )
            }
            metadata = nil
            sources = []
            manifestType = nil
            drmType = nil
            drmKey = nil
            licenseURI = nil
            licenseHeaders = [:]
            vlcReferrer = nil
            vlcUserAgent = nil
        }

        for line in lines {
            if line.lowercased().hasPrefix("#extinf") {
                flush()
                metadata = parseEXTINF(line)
                continue
            }

            if line.lowercased().hasPrefix("#kodiprop:") {
                let property = String(line.dropFirst("#KODIPROP:".count))
                let lower = property.lowercased()

                if lower.hasPrefix("inputstream.adaptive.manifest_type=") {
                    manifestType = value(afterEqualsIn: property)
                } else if lower.hasPrefix("inputstream.adaptive.drm_legacy=") {
                    let parsed = parseDRMLegacySpec(value(afterEqualsIn: property))
                    if let value = parsed.drmType, !value.isEmpty { drmType = value }
                    if let value = parsed.licenseOrKey, !value.isEmpty {
                        drmKey = value
                        if isHTTPURI(value) { licenseURI = value }
                    }
                    licenseHeaders.merge(parsed.headers) { _, new in new }
                } else if lower.hasPrefix("inputstream.adaptive.license_type=") {
                    drmType = value(afterEqualsIn: property)
                } else if lower.hasPrefix("inputstream.adaptive.license_key=") {
                    drmKey = value(afterEqualsIn: property)
                    let parsed = parseLegacyLicenseSpec(drmKey ?? "")
                    if licenseURI == nil { licenseURI = parsed.uri }
                    licenseHeaders.merge(parsed.headers) { _, new in new }
                } else if lower.hasPrefix("inputstream.adaptive.license_url=") {
                    let raw = value(afterEqualsIn: property)
                    let parsed = parseLegacyLicenseSpec(raw)
                    licenseURI = parsed.uri ?? (isHTTPURI(raw) ? raw : nil)
                    licenseHeaders.merge(parsed.headers) { _, new in new }
                }
                continue
            }

            if line.lowercased().hasPrefix("#extvlcopt:http-referrer=") {
                vlcReferrer = value(afterEqualsIn: line)
                continue
            }

            if line.lowercased().hasPrefix("#extvlcopt:http-user-agent=") {
                vlcUserAgent = value(afterEqualsIn: line)
                continue
            }

            if !line.isEmpty, !line.hasPrefix("#"), metadata != nil {
                let source = parseStreamSource(
                    raw: line,
                    manifestType: manifestType,
                    drmType: drmType,
                    drmKey: drmKey,
                    licenseURI: licenseURI,
                    licenseHeaders: licenseHeaders,
                    vlcReferrer: vlcReferrer,
                    vlcUserAgent: vlcUserAgent
                )
                if !source.url.isEmpty { sources.append(source) }
            }
        }

        flush()

        var seen = Set<String>()
        return channels.filter { channel in
            guard let firstURL = channel.sources.first?.url else { return false }
            let key = "\(channel.id)|\(channel.name)|\(firstURL)"
            return seen.insert(key).inserted
        }
    }

    private func parseEXTINF(_ line: String) -> Metadata {
        let attributes = parseQuotedAttributes(line)
        let fallbackName = attributes["tvg-name"] ?? ""
        let name: String
        if let comma = line.firstIndex(of: ",") {
            name = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            name = fallbackName
        }

        return Metadata(
            id: attributes["tvg-id"] ?? "",
            name: name.isEmpty ? fallbackName : name,
            group: attributes["group-title"] ?? "",
            logo: attributes["tvg-logo"] ?? ""
        )
    }

    private func parseQuotedAttributes(_ line: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "([A-Za-z0-9_-]+)=\\\"([^\\\"]*)\\\"") else {
            return [:]
        }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result: [String: String] = [:]
        for match in regex.matches(in: line, range: range) where match.numberOfRanges >= 3 {
            result[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2))
        }
        return result
    }

    private func parseStreamSource(
        raw: String,
        manifestType: String?,
        drmType: String?,
        drmKey: String?,
        licenseURI: String?,
        licenseHeaders: [String: String],
        vlcReferrer: String?,
        vlcUserAgent: String?
    ) -> StreamSource {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        var rawURL = String(parts[0])
        let suffix = parts.count > 1 ? String(parts[1]) : ""

        var headers: [String: String] = [:]
        if let vlcReferrer, !vlcReferrer.isEmpty { headers["Referer"] = vlcReferrer }
        if let vlcUserAgent, !vlcUserAgent.isEmpty { headers["User-Agent"] = vlcUserAgent }
        headers.merge(parseHeaderPairs(suffix)) { _, new in new }

        if rawURL.hasSuffix("?") { rawURL.removeLast() }

        return StreamSource(
            url: rawURL.trimmingCharacters(in: .whitespacesAndNewlines),
            headers: headers,
            manifestType: manifestType,
            drmType: drmType,
            drmKey: drmKey,
            licenseURI: licenseURI,
            licenseHeaders: licenseHeaders
        )
    }

    private func parseDRMLegacySpec(_ value: String) -> DRMLegacySpec {
        let parts = value.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        return DRMLegacySpec(
            drmType: nonEmpty(parts[safe: 0]?.trimmingCharacters(in: .whitespacesAndNewlines)),
            licenseOrKey: nonEmpty(parts[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines)),
            headers: parseHeaderPairs(parts[safe: 2] ?? "")
        )
    }

    private func parseLegacyLicenseSpec(_ value: String) -> LicenseSpec {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let candidate = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LicenseSpec(
            uri: isHTTPURI(candidate) ? candidate : nil,
            headers: parseHeaderPairs(parts[safe: 1] ?? "")
        )
    }

    private func parseHeaderPairs(_ value: String) -> [String: String] {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        var headers: [String: String] = [:]
        for pair in value.split(separator: "&", omittingEmptySubsequences: true) {
            let text = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let equals = text.firstIndex(of: "=") else { continue }
            let rawKey = String(text[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = rawKey.removingPercentEncoding ?? rawKey
            let decoded = rawValue.removingPercentEncoding ?? rawValue
            if !key.isEmpty, !decoded.isEmpty { headers[normalizeHeader(key)] = decoded }
        }
        return headers
    }

    private func isHTTPURI(_ value: String) -> Bool {
        guard let scheme = URLComponents(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func normalizeHeader(_ value: String) -> String {
        switch value.lowercased() {
        case "referer", "referrer": return "Referer"
        case "user-agent", "useragent": return "User-Agent"
        default: return value
        }
    }

    private func value(afterEqualsIn value: String) -> String {
        guard let index = value.firstIndex(of: "=") else { return "" }
        return String(value[value.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func slug(_ value: String) -> String {
        let lower = value.lowercased()
        let mapped = lower.map { character -> Character in
            (character.isASCII && (character.isLetter || character.isNumber)) ? character : "-"
        }
        let pieces = String(mapped).split(separator: "-", omittingEmptySubsequences: true)
        return pieces.isEmpty ? "channel" : pieces.joined(separator: "-")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private struct DRMLegacySpec {
    let drmType: String?
    let licenseOrKey: String?
    let headers: [String: String]
}

private struct LicenseSpec {
    let uri: String?
    let headers: [String: String]
}

private struct Metadata {
    let id: String
    let name: String
    let group: String
    let logo: String
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
