import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

enum DASHManifestParserError: Error, Equatable {
    case invalidDocument
    case missingRepresentationID
    case invalidTimelineEntry
}

struct DASHManifestParser {
    func parse(data: Data, manifestURL: URL) throws -> DASHManifest {
        let delegate = ParserDelegate(manifestURL: manifestURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse(), delegate.error == nil else {
            throw delegate.error ?? DASHManifestParserError.invalidDocument
        }
        guard let manifest = delegate.manifest else {
            throw DASHManifestParserError.invalidDocument
        }
        return manifest
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    private struct SegmentTemplateBuilder {
        var initialization: String?
        var media: String?
        var timescale: UInt64?
        var duration: UInt64?
        var startNumber: UInt64?
        var presentationTimeOffset: UInt64?
        var timeline: [DASHSegmentTimelineEntry] = []

        func resolved(over parent: SegmentTemplateBuilder?) -> DASHSegmentTemplate {
            DASHSegmentTemplate(
                initialization: initialization ?? parent?.initialization,
                media: media ?? parent?.media,
                timescale: timescale ?? parent?.timescale ?? 1,
                duration: duration ?? parent?.duration,
                startNumber: startNumber ?? parent?.startNumber ?? 1,
                presentationTimeOffset: presentationTimeOffset ?? parent?.presentationTimeOffset ?? 0,
                timeline: timeline.isEmpty ? (parent?.timeline ?? []) : timeline
            )
        }
    }

    private struct RepresentationBuilder {
        var id: String?
        var bandwidth: Int?
        var width: Int?
        var height: Int?
        var mimeType: String?
        var codecs: String?
        var baseURLText: String?
        var segmentTemplate: SegmentTemplateBuilder?
        var contentProtections: [DASHContentProtection] = []
    }

    private struct AdaptationBuilder {
        var id: String?
        var mimeType: String?
        var contentType: String?
        var codecs: String?
        var language: String?
        var baseURLText: String?
        var segmentTemplate: SegmentTemplateBuilder?
        var contentProtections: [DASHContentProtection] = []
        var representations: [RepresentationBuilder] = []
    }

    private struct PeriodBuilder {
        var id: String?
        var baseURLText: String?
        var adaptations: [AdaptationBuilder] = []
    }

    private enum TemplateOwner {
        case adaptation
        case representation
    }

    let manifestURL: URL
    var manifest: DASHManifest?
    var error: DASHManifestParserError?

    private var manifestType: DASHManifest.ManifestType = .static
    private var minimumUpdatePeriod: TimeInterval?
    private var manifestBaseURLText: String?
    private var periods: [PeriodBuilder] = []

    private var currentPeriod: PeriodBuilder?
    private var currentAdaptation: AdaptationBuilder?
    private var currentRepresentation: RepresentationBuilder?
    private var currentSegmentTemplate: SegmentTemplateBuilder?
    private var currentTemplateOwner: TemplateOwner?

    private var collectingBaseURL = false
    private var baseURLBuffer = ""

    init(manifestURL: URL) {
        self.manifestURL = manifestURL
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard error == nil else { return }
        let name = Self.localName(elementName)

        switch name {
        case "MPD":
            if attributeDict["type"]?.lowercased() == "dynamic" {
                manifestType = .dynamic
            }
            if let raw = attributeDict["minimumUpdatePeriod"] {
                minimumUpdatePeriod = Self.parseISODuration(raw)
            }

        case "Period":
            currentPeriod = PeriodBuilder(id: attributeDict["id"])

        case "AdaptationSet":
            currentAdaptation = AdaptationBuilder(
                id: attributeDict["id"],
                mimeType: attributeDict["mimeType"],
                contentType: attributeDict["contentType"],
                codecs: attributeDict["codecs"],
                language: attributeDict["lang"]
            )

        case "Representation":
            currentRepresentation = RepresentationBuilder(
                id: attributeDict["id"],
                bandwidth: Self.int(attributeDict["bandwidth"]),
                width: Self.int(attributeDict["width"]),
                height: Self.int(attributeDict["height"]),
                mimeType: attributeDict["mimeType"],
                codecs: attributeDict["codecs"]
            )

        case "BaseURL":
            collectingBaseURL = true
            baseURLBuffer = ""

        case "SegmentTemplate":
            currentSegmentTemplate = SegmentTemplateBuilder(
                initialization: attributeDict["initialization"],
                media: attributeDict["media"],
                timescale: Self.uint64(attributeDict["timescale"]),
                duration: Self.uint64(attributeDict["duration"]),
                startNumber: Self.uint64(attributeDict["startNumber"]),
                presentationTimeOffset: Self.uint64(attributeDict["presentationTimeOffset"])
            )
            currentTemplateOwner = currentRepresentation == nil ? .adaptation : .representation

        case "S":
            guard currentSegmentTemplate != nil,
                  let duration = Self.uint64(attributeDict["d"]) else {
                error = .invalidTimelineEntry
                return
            }
            let entry = DASHSegmentTimelineEntry(
                startTime: Self.uint64(attributeDict["t"]),
                duration: duration,
                repeatCount: Self.int(attributeDict["r"]) ?? 0
            )
            currentSegmentTemplate?.timeline.append(entry)

        case "ContentProtection":
            let kid = attributeDict.first { key, _ in
                Self.localName(key).lowercased() == "default_kid"
            }?.value
            let protection = DASHContentProtection(
                schemeIDURI: attributeDict["schemeIdUri"] ?? attributeDict["schemeIDURI"],
                value: attributeDict["value"],
                defaultKeyID: kid.flatMap(Self.parseUUID)
            )
            if currentRepresentation != nil {
                currentRepresentation?.contentProtections.append(protection)
            } else {
                currentAdaptation?.contentProtections.append(protection)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingBaseURL {
            baseURLBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard error == nil else { return }
        let name = Self.localName(elementName)

        switch name {
        case "BaseURL":
            collectingBaseURL = false
            let value = baseURLBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { break }
            if currentRepresentation != nil {
                currentRepresentation?.baseURLText = value
            } else if currentAdaptation != nil {
                currentAdaptation?.baseURLText = value
            } else if currentPeriod != nil {
                currentPeriod?.baseURLText = value
            } else {
                manifestBaseURLText = value
            }

        case "SegmentTemplate":
            if let template = currentSegmentTemplate {
                switch currentTemplateOwner {
                case .representation:
                    currentRepresentation?.segmentTemplate = template
                case .adaptation:
                    currentAdaptation?.segmentTemplate = template
                case .none:
                    break
                }
            }
            currentSegmentTemplate = nil
            currentTemplateOwner = nil

        case "Representation":
            guard let representation = currentRepresentation else { break }
            guard representation.id != nil else {
                error = .missingRepresentationID
                return
            }
            currentAdaptation?.representations.append(representation)
            currentRepresentation = nil

        case "AdaptationSet":
            if let adaptation = currentAdaptation {
                currentPeriod?.adaptations.append(adaptation)
            }
            currentAdaptation = nil

        case "Period":
            if let period = currentPeriod {
                periods.append(period)
            }
            currentPeriod = nil

        case "MPD":
            manifest = buildManifest()

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil {
            error = .invalidDocument
        }
    }

    private func buildManifest() -> DASHManifest {
        let documentDirectory = manifestURL.deletingLastPathComponent()
        let rootBaseURL = Self.resolve(manifestBaseURLText, against: documentDirectory)

        let resolvedPeriods = periods.map { period in
            let periodBaseURL = Self.resolve(period.baseURLText, against: rootBaseURL)
            let adaptations = period.adaptations.map { adaptation in
                let adaptationBaseURL = Self.resolve(adaptation.baseURLText, against: periodBaseURL)
                let adaptationTemplate = adaptation.segmentTemplate?.resolved(over: nil)

                let representations = adaptation.representations.compactMap { representation -> DASHRepresentation? in
                    guard let id = representation.id else { return nil }
                    let representationBaseURL = Self.resolve(representation.baseURLText, against: adaptationBaseURL)
                    let effectiveTemplate = representation.segmentTemplate?.resolved(over: adaptation.segmentTemplate)
                        ?? adaptationTemplate
                    return DASHRepresentation(
                        id: id,
                        bandwidth: representation.bandwidth,
                        width: representation.width,
                        height: representation.height,
                        mimeType: representation.mimeType ?? adaptation.mimeType,
                        codecs: representation.codecs ?? adaptation.codecs,
                        baseURL: representationBaseURL,
                        segmentTemplate: effectiveTemplate,
                        contentProtections: adaptation.contentProtections + representation.contentProtections
                    )
                }

                return DASHAdaptationSet(
                    id: adaptation.id,
                    mimeType: adaptation.mimeType,
                    contentType: adaptation.contentType,
                    codecs: adaptation.codecs,
                    language: adaptation.language,
                    baseURL: adaptationBaseURL,
                    segmentTemplate: adaptationTemplate,
                    contentProtections: adaptation.contentProtections,
                    representations: representations
                )
            }
            return DASHPeriod(id: period.id, baseURL: periodBaseURL, adaptationSets: adaptations)
        }

        return DASHManifest(
            type: manifestType,
            minimumUpdatePeriod: minimumUpdatePeriod,
            baseURL: rootBaseURL,
            periods: resolvedPeriods
        )
    }

    private static func resolve(_ child: String?, against parent: URL) -> URL {
        guard let child, !child.isEmpty else { return parent }
        return URL(string: child, relativeTo: parent)?.absoluteURL ?? parent
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    private static func uint64(_ value: String?) -> UInt64? {
        value.flatMap(UInt64.init)
    }

    private static func int(_ value: String?) -> Int? {
        value.flatMap(Int.init)
    }

    private static func parseUUID(_ raw: String) -> UUID? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let uuid = UUID(uuidString: cleaned) {
            return uuid
        }
        let compact = cleaned.replacingOccurrences(of: "-", with: "")
        guard compact.count == 32 else { return nil }
        let parts = [8, 4, 4, 4, 12]
        var cursor = compact.startIndex
        var groups: [String] = []
        for length in parts {
            let end = compact.index(cursor, offsetBy: length)
            groups.append(String(compact[cursor..<end]))
            cursor = end
        }
        return UUID(uuidString: groups.joined(separator: "-"))
    }

    private static func parseISODuration(_ value: String) -> TimeInterval? {
        guard value.hasPrefix("P") else { return nil }
        var text = String(value.dropFirst())
        var days = 0.0
        var hours = 0.0
        var minutes = 0.0
        var seconds = 0.0

        if let tIndex = text.firstIndex(of: "T") {
            let datePart = String(text[..<tIndex])
            text = String(text[text.index(after: tIndex)...])
            days = component(in: datePart, suffix: "D") ?? 0
            hours = component(in: text, suffix: "H") ?? 0
            minutes = component(in: text, suffix: "M") ?? 0
            seconds = component(in: text, suffix: "S") ?? 0
        } else {
            days = component(in: text, suffix: "D") ?? 0
        }

        return days * 86_400 + hours * 3_600 + minutes * 60 + seconds
    }

    private static func component(in text: String, suffix: Character) -> Double? {
        guard let end = text.firstIndex(of: suffix) else { return nil }
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            let char = text[previous]
            if !(char.isNumber || char == ".") { break }
            start = previous
        }
        guard start < end else { return nil }
        return Double(text[start..<end])
    }
}
