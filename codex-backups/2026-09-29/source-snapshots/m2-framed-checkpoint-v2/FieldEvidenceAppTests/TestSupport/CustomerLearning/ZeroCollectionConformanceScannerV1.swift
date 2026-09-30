import Foundation

/// Test-target input for the C43 static zero-collection audit. The scanner is
/// deliberately filesystem-free: callers choose the exact Release source and
/// project documents, then pass their bytes here.
struct ZeroCollectionStaticDocumentV1: Equatable, Sendable {
    static let maximumPathBytes = 1_024
    static let maximumTextBytes = 4 * 1_024 * 1_024

    let path: String
    let text: String

    init(path: String, text: String) throws {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalizedPath.isEmpty,
              normalizedPath.utf8.count <= Self.maximumPathBytes,
              normalizedPath == normalizedPath.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedPath.hasPrefix("/"),
              !normalizedPath.contains(":"),
              !normalizedPath.split(separator: "/").contains(".."),
              text.utf8.count <= Self.maximumTextBytes,
              !text.contains("\0") else {
            throw ZeroCollectionConformanceScannerFailureV1.invalidDocument
        }
        self.path = normalizedPath
        self.text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

typealias ZeroCollectionScannerInputV1 = ZeroCollectionStaticDocumentV1

enum ZeroCollectionStaticFindingKindV1: String, CaseIterable, Codable, Hashable,
    Sendable {
    case analyticsAttributionOrAdSDK = "ANALYTICS_ATTRIBUTION_OR_AD_SDK"
    case productEventStore = "PRODUCT_EVENT_STORE"
    case productMeasurementEndpoint = "PRODUCT_MEASUREMENT_ENDPOINT"
    case backgroundProductUpload = "BACKGROUND_PRODUCT_UPLOAD"
    case campaignTokenHandler = "CAMPAIGN_TOKEN_HANDLER"
    case trackingOrIdentityJoin = "TRACKING_OR_IDENTITY_JOIN"
}

struct ZeroCollectionStaticFindingV1: Equatable, Hashable, Sendable {
    let kind: ZeroCollectionStaticFindingKindV1
    let path: String
    let line: Int
    let matchedRuleID: String
}

enum ZeroCollectionRecognizedExemptionKindV1: String, CaseIterable, Codable,
    Hashable, Sendable {
    case localMetricKitSupportDiagnostics = "LOCAL_METRICKIT_SUPPORT_DIAGNOSTICS"
    case storeKitCommerce = "STOREKIT_COMMERCE"
    case inertSchemaURL = "INERT_SCHEMA_URL"
    case dispatchConcurrency = "DISPATCH_CONCURRENCY"
    case localAuthentication = "LOCAL_AUTHENTICATION"
}

struct ZeroCollectionRecognizedExemptionV1: Equatable, Hashable, Sendable {
    let kind: ZeroCollectionRecognizedExemptionKindV1
    let path: String
    let line: Int
}

enum ZeroCollectionEvidenceScopeV1: String, Codable, Sendable {
    /// Source, resource, package manifest, and Xcode project text supplied by
    /// the test. This is intentionally weaker than archive or runtime proof.
    case suppliedStaticDocumentsOnly = "SUPPLIED_STATIC_DOCUMENTS_ONLY"
}

struct ZeroCollectionStaticConformanceEvidenceV1: Equatable, Sendable {
    let scope: ZeroCollectionEvidenceScopeV1
    let scannedPaths: [String]
    let recognizedExemptions: [ZeroCollectionRecognizedExemptionV1]
    let claimsReleaseArchiveInspection: Bool
    let claimsRuntimeNetworkObservation: Bool

    init(
        scannedPaths: [String],
        recognizedExemptions: [ZeroCollectionRecognizedExemptionV1]
    ) throws {
        guard !scannedPaths.isEmpty,
              scannedPaths == scannedPaths.sorted(by: {
                  ($0.lowercased(), $0) < ($1.lowercased(), $1)
              }),
              Set(scannedPaths.map { $0.lowercased() }).count == scannedPaths.count,
              recognizedExemptions == recognizedExemptions.sorted(by: Self.less)
        else {
            throw ZeroCollectionConformanceScannerFailureV1.invalidEvidence
        }
        scope = .suppliedStaticDocumentsOnly
        self.scannedPaths = scannedPaths
        self.recognizedExemptions = recognizedExemptions
        claimsReleaseArchiveInspection = false
        claimsRuntimeNetworkObservation = false
    }

    private static func less(
        _ lhs: ZeroCollectionRecognizedExemptionV1,
        _ rhs: ZeroCollectionRecognizedExemptionV1
    ) -> Bool {
        (lhs.path, lhs.line, lhs.kind.rawValue)
            < (rhs.path, rhs.line, rhs.kind.rawValue)
    }
}

struct ZeroCollectionConformanceScanResultV1: Equatable, Sendable {
    let scannedPaths: [String]
    let findings: [ZeroCollectionStaticFindingV1]
    let recognizedExemptions: [ZeroCollectionRecognizedExemptionV1]
    let evidenceScope: ZeroCollectionEvidenceScopeV1
    let claimsReleaseArchiveInspection: Bool
    let claimsRuntimeNetworkObservation: Bool

    var isStaticSourceConformant: Bool { findings.isEmpty }

    fileprivate init(
        scannedPaths: [String],
        findings: [ZeroCollectionStaticFindingV1],
        recognizedExemptions: [ZeroCollectionRecognizedExemptionV1]
    ) {
        self.scannedPaths = scannedPaths
        self.findings = findings
        self.recognizedExemptions = recognizedExemptions
        evidenceScope = .suppliedStaticDocumentsOnly
        claimsReleaseArchiveInspection = false
        claimsRuntimeNetworkObservation = false
    }

    func conformanceEvidence() throws -> ZeroCollectionStaticConformanceEvidenceV1 {
        guard findings.isEmpty else {
            throw ZeroCollectionConformanceScannerFailureV1.prohibitedPathFound
        }
        return try ZeroCollectionStaticConformanceEvidenceV1(
            scannedPaths: scannedPaths,
            recognizedExemptions: recognizedExemptions
        )
    }
}

enum ZeroCollectionConformanceScannerFailureV1: Error, Equatable, Sendable {
    case duplicatePath
    case emptyInput
    case inputLimitExceeded
    case invalidDocument
    case invalidEvidence
    case prohibitedPathFound
}

/// Deterministic, purpose-aware scanner for C43's static source/project gate.
/// Supplied documents may include package and dependency manifests, but the
/// result supports only the `DISABLED_NO_COLLECTION` static-source decision.
/// It does not read the filesystem, inspect an app archive, launch the app, or
/// observe network traffic, and therefore cannot issue evidence for those
/// stronger gates or activate collection.
enum ZeroCollectionConformanceScannerV1 {
    static let maximumDocumentCount = 20_000
    static let maximumAggregateTextBytes = 64 * 1_024 * 1_024
    static let maximumReportedFindingCount = 100_000
    static let maximumReportedExemptionCount = 100_000

    static func scan(
        _ documents: [ZeroCollectionStaticDocumentV1]
    ) throws -> ZeroCollectionConformanceScanResultV1 {
        try scan(documents: documents)
    }

    static func scan(
        documents: [ZeroCollectionStaticDocumentV1]
    ) throws -> ZeroCollectionConformanceScanResultV1 {
        guard !documents.isEmpty else {
            throw ZeroCollectionConformanceScannerFailureV1.emptyInput
        }
        guard documents.count <= maximumDocumentCount else {
            throw ZeroCollectionConformanceScannerFailureV1.inputLimitExceeded
        }
        let ordered = documents.sorted {
            ($0.path.lowercased(), $0.path) < ($1.path.lowercased(), $1.path)
        }
        guard Set(ordered.map { $0.path.lowercased() }).count == ordered.count else {
            throw ZeroCollectionConformanceScannerFailureV1.duplicatePath
        }
        var aggregateBytes = 0
        for document in ordered {
            let (next, overflow) = aggregateBytes.addingReportingOverflow(
                document.text.utf8.count
            )
            guard !overflow, next <= maximumAggregateTextBytes else {
                throw ZeroCollectionConformanceScannerFailureV1.inputLimitExceeded
            }
            aggregateBytes = next
        }

        var findings = Set<ZeroCollectionStaticFindingV1>()
        var exemptions = Set<ZeroCollectionRecognizedExemptionV1>()
        for document in ordered {
            inspect(document, findings: &findings, exemptions: &exemptions)
        }
        guard findings.count <= maximumReportedFindingCount,
              exemptions.count <= maximumReportedExemptionCount else {
            throw ZeroCollectionConformanceScannerFailureV1.inputLimitExceeded
        }
        let sortedFindings = findings.sorted(by: findingLess)
        let sortedExemptions = exemptions.sorted(by: exemptionLess)
        return ZeroCollectionConformanceScanResultV1(
            scannedPaths: ordered.map(\.path),
            findings: sortedFindings,
            recognizedExemptions: sortedExemptions
        )
    }

    private static func inspect(
        _ document: ZeroCollectionStaticDocumentV1,
        findings: inout Set<ZeroCollectionStaticFindingV1>,
        exemptions: inout Set<ZeroCollectionRecognizedExemptionV1>
    ) {
        let path = document.path
        let pathLower = path.lowercased()
        let lines = document.text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let documentLower = document.text.lowercased()
        let compactDocument = documentLower.filter { !$0.isWhitespace }
        let documentHasProductUploadPurpose = containsAny(
            documentLower,
            tokens: productUploadPurposeTokens
        )

        if compactDocument.contains("<key>nsprivacytracking</key><true/>") {
            findings.insert(.init(
                kind: .trackingOrIdentityJoin,
                path: path,
                line: firstLine(containing: "nsprivacytracking", in: documentLower),
                matchedRuleID: "PRIVACY_MANIFEST_TRACKING_TRUE"
            ))
        }
        if compactDocument.contains(
            "<key>nsprivacytrackingdomains</key><array><string>"
        ) {
            findings.insert(.init(
                kind: .productMeasurementEndpoint,
                path: path,
                line: firstLine(
                    containing: "nsprivacytrackingdomains",
                    in: documentLower
                ),
                matchedRuleID: "PRIVACY_MANIFEST_TRACKING_DOMAIN"
            ))
        }

        var insideBlockComment = false
        for (offset, substring) in lines.enumerated() {
            let lineNumber = offset + 1
            let rawLine = String(substring)
            let uncommented = removingBlockComments(
                from: rawLine,
                insideComment: &insideBlockComment
            )
            let trimmed = uncommented.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else {
                continue
            }
            let line = uncommented.lowercased()

            recognizeExemptions(
                line: line,
                path: path,
                pathLower: pathLower,
                lineNumber: lineNumber,
                exemptions: &exemptions
            )

            addFirstMatch(
                in: line,
                rules: sdkRules,
                kind: .analyticsAttributionOrAdSDK,
                path: path,
                lineNumber: lineNumber,
                findings: &findings
            )
            addFirstMatch(
                in: line,
                rules: eventStoreRules,
                kind: .productEventStore,
                path: path,
                lineNumber: lineNumber,
                findings: &findings
            )
            if !isInertSchemaLine(line) {
                addFirstMatch(
                    in: line,
                    rules: endpointRules,
                    kind: .productMeasurementEndpoint,
                    path: path,
                    lineNumber: lineNumber,
                    findings: &findings
                )
            }
            if documentHasProductUploadPurpose {
                addFirstMatch(
                    in: line,
                    rules: backgroundUploadRules,
                    kind: .backgroundProductUpload,
                    path: path,
                    lineNumber: lineNumber,
                    findings: &findings
                )
            }
            addFirstMatch(
                in: line,
                rules: campaignRules,
                kind: .campaignTokenHandler,
                path: path,
                lineNumber: lineNumber,
                findings: &findings
            )
            addFirstMatch(
                in: line,
                rules: identityRules,
                kind: .trackingOrIdentityJoin,
                path: path,
                lineNumber: lineNumber,
                findings: &findings
            )
            if containsAny(line, tokens: contextualIdentityTokens),
               containsAny(line, tokens: measurementPurposeTokens) {
                findings.insert(.init(
                    kind: .trackingOrIdentityJoin,
                    path: path,
                    line: lineNumber,
                    matchedRuleID: "IDENTITY_IN_MEASUREMENT_CONTEXT"
                ))
            }
        }
    }

    private static func recognizeExemptions(
        line: String,
        path: String,
        pathLower: String,
        lineNumber: Int,
        exemptions: inout Set<ZeroCollectionRecognizedExemptionV1>
    ) {
        if containsAny(line, tokens: ["metrickit", "mxmetricmanager"]),
           pathLower.contains("/diagnostics/") {
            exemptions.insert(.init(
                kind: .localMetricKitSupportDiagnostics,
                path: path,
                line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["import storekit", "product.products(", "transaction." ]),
           (pathLower.contains("/commerce/") || pathLower.contains("/subscription/")) {
            exemptions.insert(.init(
                kind: .storeKitCommerce,
                path: path,
                line: lineNumber
            ))
        }
        if isInertSchemaLine(line), line.contains("http") {
            exemptions.insert(.init(
                kind: .inertSchemaURL,
                path: path,
                line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["dispatchqueue", "dispatchgroup", "dispatchsemaphore"] ) {
            exemptions.insert(.init(
                kind: .dispatchConcurrency,
                path: path,
                line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["import localauthentication", "lacontext", "lapolicy"] ) {
            exemptions.insert(.init(
                kind: .localAuthentication,
                path: path,
                line: lineNumber
            ))
        }
    }

    private static func addFirstMatch(
        in line: String,
        rules: [(id: String, tokens: [String])],
        kind: ZeroCollectionStaticFindingKindV1,
        path: String,
        lineNumber: Int,
        findings: inout Set<ZeroCollectionStaticFindingV1>
    ) {
        for rule in rules where rule.tokens.allSatisfy({ line.contains($0) }) {
            findings.insert(.init(
                kind: kind,
                path: path,
                line: lineNumber,
                matchedRuleID: rule.id
            ))
            return
        }
    }

    private static func containsAny(_ value: String, tokens: [String]) -> Bool {
        tokens.contains(where: { value.contains($0) })
    }

    private static func firstLine(containing token: String, in text: String) -> Int {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return (lines.firstIndex(where: { $0.contains(token) }) ?? 0) + 1
    }

    private static func removingBlockComments(
        from line: String,
        insideComment: inout Bool
    ) -> String {
        var remainder = line[...]
        var result = ""
        while !remainder.isEmpty {
            if insideComment {
                guard let end = remainder.range(of: "*/") else { return result }
                remainder = remainder[end.upperBound...]
                insideComment = false
            } else if let start = remainder.range(of: "/*") {
                result.append(contentsOf: remainder[..<start.lowerBound])
                remainder = remainder[start.upperBound...]
                insideComment = true
            } else {
                result.append(contentsOf: remainder)
                remainder = remainder[remainder.endIndex...]
            }
        }
        return result
    }

    private static func isInertSchemaLine(_ line: String) -> Bool {
        containsAny(line, tokens: [
            "json-schema.org/", "schemas.assetrounds.local/", "schemaid",
            "schema_id", "\"$id\"", "schema dialect", "schemadialect",
        ])
    }

    private static func findingLess(
        _ lhs: ZeroCollectionStaticFindingV1,
        _ rhs: ZeroCollectionStaticFindingV1
    ) -> Bool {
        (lhs.path, lhs.line, lhs.kind.rawValue, lhs.matchedRuleID)
            < (rhs.path, rhs.line, rhs.kind.rawValue, rhs.matchedRuleID)
    }

    private static func exemptionLess(
        _ lhs: ZeroCollectionRecognizedExemptionV1,
        _ rhs: ZeroCollectionRecognizedExemptionV1
    ) -> Bool {
        (lhs.path, lhs.line, lhs.kind.rawValue)
            < (rhs.path, rhs.line, rhs.kind.rawValue)
    }

    private static let sdkRules: [(id: String, tokens: [String])] = [
        ("FIREBASE_ANALYTICS", ["firebaseanalytics"]),
        ("GOOGLE_MOBILE_ADS", ["googlemobileads"]),
        ("IMPORT_AMPLITUDE", ["import amplitude"]),
        ("PACKAGE_AMPLITUDE_PRODUCT", ["amplitude-swift"]),
        ("MIXPANEL_SDK", ["mixpanel"]),
        ("APPSFLYER_SDK", ["appsflyer"]),
        ("IMPORT_ADJUST", ["import adjust"]),
        ("IMPORT_FACEBOOK_SDK", ["import facebookcore"]),
        ("IMPORT_FBSDK", ["import fbsdk"]),
        ("IMPORT_AD_SUPPORT", ["import adsupport"]),
        ("IMPORT_TRACKING_TRANSPARENCY", ["import apptrackingtransparency"]),
        ("IMPORT_AD_SERVICES", ["import adservices"]),
        ("PACKAGE_FIREBASE_ANALYTICS", ["firebase-ios-sdk", "analytics"]),
        ("PACKAGE_AMPLITUDE", ["amplitude-swift"]),
        ("PACKAGE_MIXPANEL", ["mixpanel-swift"]),
        ("PACKAGE_SEGMENT", ["segmentio", "analytics-swift"]),
        ("PACKAGE_SEGMENT_ANALYTICS", ["analytics-swift"]),
        ("PACKAGE_APPSFLYER", ["appsflyerframework"]),
        ("PACKAGE_ADJUST", ["adjust-ios-sdk"]),
        ("PACKAGE_BRANCH", ["branch-sdk-ios"]),
        ("PACKAGE_GOOGLE_MOBILE_ADS", ["googlemobileadssdk"]),
        ("PACKAGE_APPLOVIN", ["applovin"]),
        ("SENTRY_REMOTE_DIAGNOSTICS", ["import sentry"]),
        ("DATADOG_REMOTE_DIAGNOSTICS", ["import datadog"]),
        ("NEW_RELIC_REMOTE_DIAGNOSTICS", ["newrelic"]),
        ("TELEMETRY_DECK", ["telemetrydeck"]),
        ("POSTHOG", ["posthog"]),
        ("HEAP_ANALYTICS", ["heapanalytics"]),
        ("RUDDERSTACK", ["rudderstack"]),
        ("SNOWPLOW", ["snowplow"]),
        ("COUNTLY", ["countly"]),
        ("APP_CENTER_ANALYTICS", ["appcenteranalytics"]),
        ("AD_ATTRIBUTION_KIT", ["adattributionkit"]),
        ("SK_AD_NETWORK", ["skadnetwork"]),
    ]

    private static let eventStoreRules: [(id: String, tokens: [String])] = [
        ("ANALYTICS_EVENT_STORE", ["analyticseventstore"]),
        ("PRODUCT_EVENT_STORE", ["producteventstore"]),
        ("MEASUREMENT_EVENT_STORE", ["measurementeventstore"]),
        ("ANALYTICS_EVENT_ROW", ["analyticseventrow"]),
        ("PRODUCT_EVENT_ROW", ["producteventrow"]),
        ("ANALYTICS_EVENTS_TABLE", ["analytics_events"]),
        ("PRODUCT_EVENTS_TABLE", ["product_events"]),
        ("MEASUREMENT_EVENTS_TABLE", ["measurement_events"]),
    ]

    private static let endpointRules: [(id: String, tokens: [String])] = [
        ("ANALYTICS_ENDPOINT", ["analyticsendpoint"]),
        ("EVENT_ENDPOINT", ["eventendpoint"]),
        ("ATTRIBUTION_ENDPOINT", ["attributionendpoint"]),
        ("MEASUREMENT_ENDPOINT", ["measurementendpoint"]),
        ("HTTP_ANALYTICS_PATH", ["http", "/analytics"]),
        ("HTTP_TRACK_PATH", ["http", "/track"]),
        ("HTTP_EVENTS_PATH", ["http", "/events"]),
        ("HTTP_COLLECT_PATH", ["http", "/collect"]),
        ("HTTP_IDENTIFY_PATH", ["http", "/identify"]),
        ("HTTP_ATTRIBUTION_PATH", ["http", "/attribution"]),
        ("KNOWN_GOOGLE_ANALYTICS_HOST", ["google-analytics.com"]),
        ("KNOWN_GOOGLE_MEASUREMENT_HOST", ["googletagmanager.com"]),
        ("KNOWN_SEGMENT_HOST", ["api.segment.io"]),
        ("KNOWN_AMPLITUDE_HOST", ["api2.amplitude.com"]),
        ("KNOWN_MIXPANEL_HOST", ["api.mixpanel.com"]),
        ("KNOWN_APPSFLYER_HOST", ["appsflyer.com"]),
    ]

    private static let backgroundUploadRules: [(id: String, tokens: [String])] = [
        ("BG_TASK_SCHEDULER", ["bgtaskscheduler"]),
        ("BG_PROCESSING_TASK", ["bgprocessingtask"]),
        ("BG_APP_REFRESH_TASK", ["bgapprefreshtask"]),
        ("BACKGROUND_URL_SESSION", ["urlsessionconfiguration.background"]),
        ("BACKGROUND_UPLOAD", ["backgroundupload"]),
        ("BACKGROUND_UPLOADER", ["backgrounduploader"]),
    ]

    private static let campaignRules: [(id: String, tokens: [String])] = [
        ("CAMPAIGN_TOKEN", ["campaigntoken"]),
        ("ATTRIBUTION_TOKEN", ["attributiontoken"]),
        ("REFERRER_TOKEN", ["referrertoken"]),
        ("UTM_SOURCE", ["utm_source"]),
        ("UTM_MEDIUM", ["utm_medium"]),
        ("UTM_CAMPAIGN", ["utm_campaign"]),
        ("INSTALL_REFERRER", ["installreferrer"]),
        ("AD_SERVICES_TOKEN", ["aaattribution", "attributiontoken"]),
    ]

    private static let identityRules: [(id: String, tokens: [String])] = [
        ("ADVERTISING_IDENTIFIER", ["advertisingidentifier"]),
        ("IDENTIFIER_FOR_VENDOR", ["identifierforvendor"]),
        ("AS_IDENTIFIER_MANAGER", ["asidentifiermanager"]),
        ("DEVICE_FINGERPRINT", ["devicefingerprint"]),
        ("HASHED_EMAIL", ["hashedemail"]),
        ("EMAIL_HASH", ["emailhash"]),
        ("IDENTITY_JOIN", ["identityjoin"]),
        ("CROSS_SOURCE_JOIN", ["crosssourcejoin"]),
        ("CROSS_DEVICE_ID", ["crossdeviceid"]),
        ("ANALYTICS_USER_ID", ["analyticsuserid"]),
        ("MEASUREMENT_USER_ID", ["measurementuserid"]),
    ]

    private static let productUploadPurposeTokens = [
        "analytics", "attribution", "productevent", "measurement event",
        "telemetry upload", "campaign token", "event endpoint",
    ]

    private static let contextualIdentityTokens = [
        "userid", "user_id", "personid", "person_id", "deviceid", "device_id",
        "emailhash", "hashedemail",
    ]

    private static let measurementPurposeTokens = [
        "analytics", "attribution", "acquisition", "campaign", "measurement",
        "tracking", "telemetry",
    ]
}
