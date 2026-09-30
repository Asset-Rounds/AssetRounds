import Foundation

/// One caller-supplied source, project, dependency, settings, route, resource,
/// or manifest document for the C44 static conformance gate. This test-target
/// value performs no filesystem or runtime discovery.
struct ZeroSubscriberStaticDocumentV1: Equatable, Sendable {
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
            throw ZeroSubscriberTransmissionScannerFailureV1.invalidDocument
        }
        self.path = normalizedPath
        self.text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

typealias ZeroSubscriberTransmissionScannerInputV1 = ZeroSubscriberStaticDocumentV1

enum ZeroSubscriberStaticFindingKindV1: String, CaseIterable, Codable, Hashable,
    Sendable {
    case subscriberOrContactRepository = "SUBSCRIBER_OR_CONTACT_REPOSITORY"
    case providerSDKOrBinding = "PROVIDER_SDK_OR_BINDING"
    case providerCredentialOrEndpoint = "PROVIDER_CREDENTIAL_OR_ENDPOINT"
    case sendQueueOrBackgroundTask = "SEND_QUEUE_OR_BACKGROUND_TASK"
    case signupPreferenceRouteOrHandler = "SIGNUP_PREFERENCE_ROUTE_OR_HANDLER"
    case operationalContactConversion = "OPERATIONAL_CONTACT_CONVERSION"
    case mailingImportOrExport = "MAILING_IMPORT_OR_EXPORT"
    case plainAddressHash = "PLAIN_ADDRESS_HASH"
    case adAudienceOrTrackingIdentity = "AD_AUDIENCE_OR_TRACKING_IDENTITY"
}

struct ZeroSubscriberStaticFindingV1: Equatable, Hashable, Sendable {
    let kind: ZeroSubscriberStaticFindingKindV1
    let path: String
    let line: Int
    let matchedRuleID: String
}

enum ZeroSubscriberRecognizedExemptionKindV1: String, CaseIterable, Codable,
    Hashable, Sendable {
    case feedbackMessageUISupport = "FEEDBACK_MESSAGEUI_SUPPORT"
    case reviewedDiagnosticAttachment = "REVIEWED_DIAGNOSTIC_ATTACHMENT"
    case storeKitCommerce = "STOREKIT_COMMERCE"
    case metricKitOSSubscriber = "METRICKIT_OS_SUBSCRIBER"
    case notificationCenterOrLocalScheduling = "NOTIFICATION_CENTER_OR_LOCAL_SCHEDULING"
    case inertSchemaOrExampleURL = "INERT_SCHEMA_OR_EXAMPLE_URL"
    case dispatchConcurrency = "DISPATCH_CONCURRENCY"
    case localAuthentication = "LOCAL_AUTHENTICATION"
}

struct ZeroSubscriberRecognizedExemptionV1: Equatable, Hashable, Sendable {
    let kind: ZeroSubscriberRecognizedExemptionKindV1
    let path: String
    let line: Int
}

enum ZeroSubscriberEvidenceScopeV1: String, Codable, Sendable {
    case suppliedStaticDocumentsOnly = "SUPPLIED_STATIC_DOCUMENTS_ONLY"
}

struct ZeroSubscriberStaticConformanceEvidenceV1: Equatable, Sendable {
    let disposition: String
    let scope: ZeroSubscriberEvidenceScopeV1
    let scannedPaths: [String]
    let recognizedExemptions: [ZeroSubscriberRecognizedExemptionV1]
    let claimsReleaseArchiveInspection: Bool
    let claimsRuntimeNetworkObservation: Bool

    init(
        scannedPaths: [String],
        recognizedExemptions: [ZeroSubscriberRecognizedExemptionV1]
    ) throws {
        let orderedPaths = scannedPaths.sorted(by: Self.pathLess)
        guard !scannedPaths.isEmpty,
              scannedPaths == orderedPaths,
              Set(scannedPaths.map { $0.lowercased() }).count == scannedPaths.count,
              recognizedExemptions == recognizedExemptions.sorted(by: Self.exemptionLess)
        else {
            throw ZeroSubscriberTransmissionScannerFailureV1.invalidEvidence
        }
        disposition = "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION"
        scope = .suppliedStaticDocumentsOnly
        self.scannedPaths = scannedPaths
        self.recognizedExemptions = recognizedExemptions
        claimsReleaseArchiveInspection = false
        claimsRuntimeNetworkObservation = false
    }

    private static func pathLess(_ lhs: String, _ rhs: String) -> Bool {
        (lhs.lowercased(), lhs) < (rhs.lowercased(), rhs)
    }

    private static func exemptionLess(
        _ lhs: ZeroSubscriberRecognizedExemptionV1,
        _ rhs: ZeroSubscriberRecognizedExemptionV1
    ) -> Bool {
        (lhs.path, lhs.line, lhs.kind.rawValue)
            < (rhs.path, rhs.line, rhs.kind.rawValue)
    }
}

struct ZeroSubscriberTransmissionScanResultV1: Equatable, Sendable {
    let scannedPaths: [String]
    let findings: [ZeroSubscriberStaticFindingV1]
    let recognizedExemptions: [ZeroSubscriberRecognizedExemptionV1]
    let evidenceScope: ZeroSubscriberEvidenceScopeV1
    let claimsReleaseArchiveInspection: Bool
    let claimsRuntimeNetworkObservation: Bool

    var isStaticSourceConformant: Bool { findings.isEmpty }

    fileprivate init(
        scannedPaths: [String],
        findings: [ZeroSubscriberStaticFindingV1],
        recognizedExemptions: [ZeroSubscriberRecognizedExemptionV1]
    ) {
        self.scannedPaths = scannedPaths
        self.findings = findings
        self.recognizedExemptions = recognizedExemptions
        evidenceScope = .suppliedStaticDocumentsOnly
        claimsReleaseArchiveInspection = false
        claimsRuntimeNetworkObservation = false
    }

    func conformanceEvidence() throws -> ZeroSubscriberStaticConformanceEvidenceV1 {
        guard findings.isEmpty else {
            throw ZeroSubscriberTransmissionScannerFailureV1.prohibitedPathFound
        }
        return try ZeroSubscriberStaticConformanceEvidenceV1(
            scannedPaths: scannedPaths,
            recognizedExemptions: recognizedExemptions
        )
    }
}

enum ZeroSubscriberTransmissionScannerFailureV1: Error, Equatable, Sendable {
    case duplicatePath
    case emptyInput
    case inputLimitExceeded
    case invalidDocument
    case invalidEvidence
    case prohibitedPathFound
}

/// Deterministic test-target-only scanner for C44. Each exemption recognizes a
/// legitimate line; it never suppresses a distinct prohibited line in the same
/// file. The result is static supplied-document evidence only and cannot claim
/// Release archive inspection or runtime-network observation.
/// Recognized purposes are Feedback MessageUI composition/diagnostic attachment,
/// StoreKit commerce, MetricKit OS subscriber naming, NotificationCenter/local
/// scheduling, inert schema/example.invalid URLs, Dispatch concurrency, and
/// LocalAuthentication. None is a general exemption for another line.
enum ZeroSubscriberTransmissionConformanceScannerV1 {
    static let maximumDocumentCount = 20_000
    static let maximumAggregateTextBytes = 64 * 1_024 * 1_024
    static let maximumReportedFindingCount = 100_000
    static let maximumReportedExemptionCount = 100_000

    static func scan(
        _ documents: [ZeroSubscriberStaticDocumentV1]
    ) throws -> ZeroSubscriberTransmissionScanResultV1 {
        try scan(documents: documents)
    }

    static func scan(
        documents: [ZeroSubscriberStaticDocumentV1]
    ) throws -> ZeroSubscriberTransmissionScanResultV1 {
        guard !documents.isEmpty else {
            throw ZeroSubscriberTransmissionScannerFailureV1.emptyInput
        }
        guard documents.count <= maximumDocumentCount else {
            throw ZeroSubscriberTransmissionScannerFailureV1.inputLimitExceeded
        }
        let ordered = documents.sorted {
            ($0.path.lowercased(), $0.path) < ($1.path.lowercased(), $1.path)
        }
        guard Set(ordered.map { $0.path.lowercased() }).count == ordered.count else {
            throw ZeroSubscriberTransmissionScannerFailureV1.duplicatePath
        }

        var aggregateBytes = 0
        for document in ordered {
            let (next, overflow) = aggregateBytes.addingReportingOverflow(
                document.text.utf8.count
            )
            guard !overflow, next <= maximumAggregateTextBytes else {
                throw ZeroSubscriberTransmissionScannerFailureV1.inputLimitExceeded
            }
            aggregateBytes = next
        }

        var findings = Set<ZeroSubscriberStaticFindingV1>()
        var exemptions = Set<ZeroSubscriberRecognizedExemptionV1>()
        for document in ordered {
            inspect(document, findings: &findings, exemptions: &exemptions)
        }
        guard findings.count <= maximumReportedFindingCount,
              exemptions.count <= maximumReportedExemptionCount else {
            throw ZeroSubscriberTransmissionScannerFailureV1.inputLimitExceeded
        }
        return ZeroSubscriberTransmissionScanResultV1(
            scannedPaths: ordered.map(\.path),
            findings: findings.sorted(by: findingLess),
            recognizedExemptions: exemptions.sorted(by: exemptionLess)
        )
    }

    private static func inspect(
        _ document: ZeroSubscriberStaticDocumentV1,
        findings: inout Set<ZeroSubscriberStaticFindingV1>,
        exemptions: inout Set<ZeroSubscriberRecognizedExemptionV1>
    ) {
        let path = document.path
        let pathLower = path.lowercased()
        let documentLower = document.text.lowercased()
        let compactDocument = documentLower.filter { !$0.isWhitespace }
        let lines = document.text.split(separator: "\n", omittingEmptySubsequences: false)
        let hasCommunicationPurpose = containsAny(
            documentLower,
            tokens: communicationPurposeTokens
        )
        let hasOperationalContact = containsAny(
            documentLower,
            tokens: operationalContactTokens
        )
        var insideBlockComment = false

        if compactDocument.contains("<key>nsprivacytracking</key><true/>") {
            findings.insert(.init(
                kind: .adAudienceOrTrackingIdentity,
                path: path,
                line: firstLine(containing: "nsprivacytracking", in: documentLower),
                matchedRuleID: "PRIVACY_MANIFEST_TRACKING_TRUE"
            ))
        }
        if compactDocument.contains("nsprivacycollecteddatatypeemailaddress") {
            findings.insert(.init(
                kind: .subscriberOrContactRepository,
                path: path,
                line: firstLine(
                    containing: "nsprivacycollecteddatatypeemailaddress",
                    in: documentLower
                ),
                matchedRuleID: "PRIVACY_MANIFEST_EMAIL_COLLECTION"
            ))
        }

        for (offset, substring) in lines.enumerated() {
            let lineNumber = offset + 1
            let uncommented = removingBlockComments(
                from: String(substring),
                insideComment: &insideBlockComment
            )
            let trimmed = uncommented.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }
            let line = uncommented.lowercased()

            recognizeExemptions(
                line: line,
                path: path,
                pathLower: pathLower,
                lineNumber: lineNumber,
                exemptions: &exemptions
            )
            addFirstMatch(
                in: line, rules: repositoryRules,
                kind: .subscriberOrContactRepository,
                path: path, lineNumber: lineNumber, findings: &findings
            )
            if !isInertURLLine(line) {
                addFirstMatch(
                    in: line, rules: providerRules,
                    kind: .providerSDKOrBinding,
                    path: path, lineNumber: lineNumber, findings: &findings
                )
                addFirstMatch(
                    in: line, rules: credentialAndEndpointRules,
                    kind: .providerCredentialOrEndpoint,
                    path: path, lineNumber: lineNumber, findings: &findings
                )
            }
            if hasCommunicationPurpose,
               containsAny(line, tokens: ["urlsession", "nwconnection", "network.framework"]) {
                findings.insert(.init(
                    kind: .providerCredentialOrEndpoint,
                    path: path,
                    line: lineNumber,
                    matchedRuleID: "COMMUNICATIONS_NETWORK_CLIENT"
                ))
            }
            if hasCommunicationPurpose,
               containsAny(line, tokens: ["apikey", "api_key", "clientsecret", "bearer "]) {
                findings.insert(.init(
                    kind: .providerCredentialOrEndpoint,
                    path: path,
                    line: lineNumber,
                    matchedRuleID: "COMMUNICATIONS_CREDENTIAL_SOURCE"
                ))
            }
            if hasCommunicationPurpose {
                addFirstMatch(
                    in: line, rules: backgroundAndSendRules,
                    kind: .sendQueueOrBackgroundTask,
                    path: path, lineNumber: lineNumber, findings: &findings
                )
            }
            addFirstMatch(
                in: line, rules: routeAndResourceRules,
                kind: .signupPreferenceRouteOrHandler,
                path: path, lineNumber: lineNumber, findings: &findings
            )
            if hasCommunicationPurpose,
               containsAny(line, tokens: [
                   "cfbundleurlschemes", "onopenurl", "openurlcontexts",
                   "continue useractivity", "nsuseractivitytype",
               ]) {
                findings.insert(.init(
                    kind: .signupPreferenceRouteOrHandler,
                    path: path,
                    line: lineNumber,
                    matchedRuleID: "COMMUNICATIONS_URL_HANDLER"
                ))
            }
            if (pathLower.contains("/resources/") || pathLower.hasSuffix(".xcstrings")),
               containsAny(line, tokens: [
                   "newsletter", "subscribe", "unsubscribe", "research invitation",
                   "communication preferences",
               ]) {
                findings.insert(.init(
                    kind: .signupPreferenceRouteOrHandler,
                    path: path,
                    line: lineNumber,
                    matchedRuleID: "COMMUNICATIONS_SHIPPING_RESOURCE"
                ))
            }
            addFirstMatch(
                in: line, rules: conversionRules,
                kind: .operationalContactConversion,
                path: path, lineNumber: lineNumber, findings: &findings
            )
            if hasOperationalContact,
               containsAny(line, tokens: marketingOutputTokens),
               containsAny(line, tokens: conversionActionTokens) {
                findings.insert(.init(
                    kind: .operationalContactConversion,
                    path: path,
                    line: lineNumber,
                    matchedRuleID: "OPERATIONAL_CONTACT_TO_MARKETING_OUTPUT"
                ))
            }
            addFirstMatch(
                in: line, rules: mailingTransferRules,
                kind: .mailingImportOrExport,
                path: path, lineNumber: lineNumber, findings: &findings
            )
            addFirstMatch(
                in: line, rules: addressHashRules,
                kind: .plainAddressHash,
                path: path, lineNumber: lineNumber, findings: &findings
            )
            addFirstMatch(
                in: line, rules: audienceAndTrackingRules,
                kind: .adAudienceOrTrackingIdentity,
                path: path, lineNumber: lineNumber, findings: &findings
            )
        }
    }

    private static func recognizeExemptions(
        line: String,
        path: String,
        pathLower: String,
        lineNumber: Int,
        exemptions: inout Set<ZeroSubscriberRecognizedExemptionV1>
    ) {
        if containsAny(line, tokens: ["import messageui", "mfmailcomposeviewcontroller"]),
           pathLower.contains("/feedback/") {
            exemptions.insert(.init(
                kind: .feedbackMessageUISupport, path: path, line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["prepareddiagnosticexportv1", "diagnostic.canonicaldata", "feedbackmailattachmentv1"]),
           (pathLower.contains("/feedback/") || pathLower.contains("/settings/feedback")) {
            exemptions.insert(.init(
                kind: .reviewedDiagnosticAttachment, path: path, line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["import storekit", "product.products(", "transaction." ]),
           (pathLower.contains("/commerce/") || pathLower.contains("/subscription/")) {
            exemptions.insert(.init(
                kind: .storeKitCommerce, path: path, line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["metrickit", "mxmetricmanagersubscriber"]),
           pathLower.contains("/diagnostics/") {
            exemptions.insert(.init(
                kind: .metricKitOSSubscriber, path: path, line: lineNumber
            ))
        }
        if containsAny(line, tokens: [
            "notificationcenter.default", "import usernotifications",
            "unusernotificationcenter", "unnotificationrequest",
        ]) {
            exemptions.insert(.init(
                kind: .notificationCenterOrLocalScheduling,
                path: path,
                line: lineNumber
            ))
        }
        if isInertURLLine(line) {
            exemptions.insert(.init(
                kind: .inertSchemaOrExampleURL, path: path, line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["dispatchqueue", "dispatchgroup", "dispatchsemaphore"] ) {
            exemptions.insert(.init(
                kind: .dispatchConcurrency, path: path, line: lineNumber
            ))
        }
        if containsAny(line, tokens: ["import localauthentication", "lacontext", "lapolicy"] ) {
            exemptions.insert(.init(
                kind: .localAuthentication, path: path, line: lineNumber
            ))
        }
    }

    private static func addFirstMatch(
        in line: String,
        rules: [(id: String, tokens: [String])],
        kind: ZeroSubscriberStaticFindingKindV1,
        path: String,
        lineNumber: Int,
        findings: inout Set<ZeroSubscriberStaticFindingV1>
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

    private static func isInertURLLine(_ line: String) -> Bool {
        line.contains("http") && containsAny(line, tokens: [
            "json-schema.org/", "schemas.assetrounds.local/", "example.invalid/",
            "schemaid", "schema_id", "\"$id\"", "schemadialect",
        ]) && !containsAny(line, tokens: [
            "api.sendgrid.com", "api.mailchimp.com", "braze.com",
            "subscriberendpoint", "marketingendpoint",
            "import ", "package(", ".product(",
            "xcremoteswiftpackagereference",
        ])
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

    private static func findingLess(
        _ lhs: ZeroSubscriberStaticFindingV1,
        _ rhs: ZeroSubscriberStaticFindingV1
    ) -> Bool {
        (lhs.path, lhs.line, lhs.kind.rawValue, lhs.matchedRuleID)
            < (rhs.path, rhs.line, rhs.kind.rawValue, rhs.matchedRuleID)
    }

    private static func exemptionLess(
        _ lhs: ZeroSubscriberRecognizedExemptionV1,
        _ rhs: ZeroSubscriberRecognizedExemptionV1
    ) -> Bool {
        (lhs.path, lhs.line, lhs.kind.rawValue)
            < (rhs.path, rhs.line, rhs.kind.rawValue)
    }

    private static let repositoryRules: [(id: String, tokens: [String])] = [
        ("SUBSCRIBER_REPOSITORY", ["subscriberrepository"]),
        ("SUBSCRIBER_STORE", ["subscriberstore"]),
        ("MARKETING_CONTACT_REPOSITORY", ["marketingcontactrepository"]),
        ("MARKETING_CONTACT_ROW", ["marketingcontactrow"]),
        ("COMMUNICATION_CONSENT_STORE", ["communicationconsentstore"]),
        ("COMMUNICATION_PREFERENCE_STORE", ["communicationpreferencestore"]),
        ("COMMUNICATION_PREFERENCE_ROW", ["communicationpreferencerow"]),
        ("SUPPRESSION_RECORD_STORE", ["suppressionrecordstore"]),
        ("SUPPRESSION_RECORD_ROW", ["suppressionrecordrow"]),
        ("SUBSCRIBERS_TABLE", ["subscribers_table"]),
        ("MARKETING_CONTACTS_TABLE", ["marketing_contacts"]),
    ]

    private static let providerRules: [(id: String, tokens: [String])] = [
        ("SENDGRID", ["sendgrid"]),
        ("MAILCHIMP", ["mailchimp"]),
        ("BRAZE", ["import braze"]),
        ("ITERABLE_SDK", ["iterableappintegrations"]),
        ("CUSTOMER_IO", ["customerio"]),
        ("ONE_SIGNAL", ["onesignal"]),
        ("KLAVIYO", ["klaviyo"]),
        ("CAMPAIGN_MONITOR", ["campaignmonitor"]),
        ("MARKETING_CLOUD", ["marketingcloudsdk"]),
        ("HUBSPOT", ["hubspot"]),
        ("LIVE_EMAIL_PROVIDER_BINDING", ["emailserviceprovideradapterv1", ".live"]),
        ("EMAIL_PROVIDER_CONFORMANCE", [": emailserviceprovideradapterv1"]),
        ("EMAIL_PROVIDER_STORED_BINDING", ["private let provider:", "emailserviceprovideradapterv1"]),
        ("EMAIL_PROVIDER_INITIALIZER_BINDING", ["init(", "emailserviceprovideradapterv1"]),
    ]

    private static let credentialAndEndpointRules: [(id: String, tokens: [String])] = [
        ("SENDGRID_API_KEY", ["sendgrid_api_key"]),
        ("MAILCHIMP_API_KEY", ["mailchimp_api_key"]),
        ("EMAIL_PROVIDER_API_KEY", ["email_provider_api_key"]),
        ("EMAIL_PROVIDER_SECRET", ["emailprovider", "clientsecret"]),
        ("SENDGRID_ENDPOINT", ["api.sendgrid.com"]),
        ("MAILCHIMP_ENDPOINT", ["api.mailchimp.com"]),
        ("BRAZE_ENDPOINT", ["braze.com", "users/track"]),
        ("SUBSCRIBER_ENDPOINT", ["subscriberendpoint"]),
        ("MARKETING_ENDPOINT", ["marketingendpoint"]),
        ("HTTP_SUBSCRIBE", ["http", "/subscribe"]),
        ("HTTP_CONTACTS", ["http", "/marketing/contacts"]),
        ("HTTP_CAMPAIGN_SEND", ["http", "/campaigns/send"]),
    ]

    private static let backgroundAndSendRules: [(id: String, tokens: [String])] = [
        ("EMAIL_SEND_QUEUE", ["emailsendqueue"]),
        ("MARKETING_SEND_QUEUE", ["marketingsendqueue"]),
        ("NEWSLETTER_SEND_QUEUE", ["newslettersendqueue"]),
        ("CAMPAIGN_SEND_QUEUE", ["campaignsendqueue"]),
        ("BACKGROUND_SENDER", ["backgroundsender"]),
        ("BG_TASK_SCHEDULER", ["bgtaskscheduler"]),
        ("BG_PROCESSING_TASK", ["bgprocessingtask"]),
        ("BG_APP_REFRESH_TASK", ["bgapprefreshtask"]),
        ("BACKGROUND_URL_SESSION", ["urlsessionconfiguration.background"]),
    ]

    private static let routeAndResourceRules: [(id: String, tokens: [String])] = [
        ("NEWSLETTER_VIEW", ["newsletterview"]),
        ("SIGNUP_VIEW", ["signupview"]),
        ("PREFERENCE_CENTER_VIEW", ["preferencecenterview"]),
        ("MARKETING_SETTINGS", ["marketingsettings"]),
        ("NEWSLETTER_ROUTE", ["newsletterroute"]),
        ("SIGNUP_ROUTE", ["signuproute"]),
        ("PREFERENCE_CENTER_ROUTE", ["preferencecenterroute"]),
        ("MARKETING_URL_HANDLER", ["marketingurlhandler"]),
        ("SUBSCRIBE_URL_HANDLER", ["subscribeurlhandler"]),
        ("SUBSCRIBE_BUTTON", ["button(\"subscribe"]),
        ("NEWSLETTER_NAVIGATION", ["navigationlink(\"newsletter"]),
        ("PREFERENCES_NAVIGATION", ["navigationlink(\"communication preferences"]),
    ]

    private static let conversionRules: [(id: String, tokens: [String])] = [
        ("PARTY_TO_MARKETING_CONTACT", ["servicepartyreferencev1", "marketingcontactv1"]),
        ("CONTACT_POINT_TO_MARKETING", ["servicecontactpointv1", "marketingcontactv1"]),
        ("PARTY_TO_CONSENT", ["servicepartyreferencev1", "communicationconsentreceiptv1"]),
        ("SITE_CONTACT_PROJECTION", ["sitecontact", "subscriber"]),
        ("CONTACT_TO_SUBSCRIBER", ["contacttosubscriber"]),
        ("PARTY_CONSENT_ADAPTER", ["partyconsentadapter"]),
        ("SIGNOFF_TO_CONSENT", ["signoffsnapshotv1", "communicationconsentreceiptv1"]),
        ("SUPPORT_TO_MARKETING", ["feedbackmail", "marketingcontactv1"]),
        ("COMMERCE_TO_MARKETING", ["verifiedentitlementfactv1", "marketingcontactv1"]),
        ("CUSTOMER_LEARNING_TO_CONTACT", ["customerlearning", "marketingcontactv1"]),
        ("TRANSACTIONAL_CREATES_MARKETING", ["transactionalorsupport", "marketingcontactv1"]),
        ("TRANSACTIONAL_ENUM_CREATES_MARKETING", ["transactional_or_support", "marketingcontactv1"]),
        ("RESEARCH_PARTICIPANT_TO_CONTACT", ["researchparticipant", "marketingcontactv1"]),
    ]

    private static let mailingTransferRules: [(id: String, tokens: [String])] = [
        ("MAILING_LIST_IMPORT", ["mailinglistimport"]),
        ("MAILING_LIST_EXPORT", ["mailinglistexport"]),
        ("SUBSCRIBER_CSV", ["subscribercsv"]),
        ("CONTACT_LIST_UPLOAD", ["contactlistupload"]),
        ("AUDIENCE_EXPORT", ["audienceexport"]),
        ("PROVIDER_LIST_REPLACEMENT", ["providerlistreplacement"]),
        ("BULK_SUBSCRIBER_IMPORT", ["bulksubscriberimport"]),
    ]

    private static let addressHashRules: [(id: String, tokens: [String])] = [
        ("HASHED_EMAIL", ["hashedemail"]),
        ("EMAIL_HASH", ["emailhash"]),
        ("ADDRESS_HASH", ["addresshash"]),
        ("SHA256_EMAIL", ["sha256", "email"]),
        ("HASH_EMAIL", ["hash(email"]),
        ("HASH_ADDRESS", ["hash(address"]),
    ]

    private static let audienceAndTrackingRules: [(id: String, tokens: [String])] = [
        ("AD_AUDIENCE", ["adaudience"]),
        ("LOOKALIKE_AUDIENCE", ["lookalike"]),
        ("RETARGETING", ["retargeting"]),
        ("CUSTOMER_MATCH", ["customermatch"]),
        ("ADVERTISING_IDENTIFIER", ["advertisingidentifier"]),
        ("IDENTIFIER_FOR_VENDOR", ["identifierforvendor"]),
        ("AS_IDENTIFIER_MANAGER", ["asidentifiermanager"]),
        ("IDFA", ["idfa"]),
        ("TRACKING_CONSENT", ["trackingconsent"]),
        ("CAMPAIGN_AUDIENCE", ["campaignaudience"]),
    ]

    private static let communicationPurposeTokens = [
        "subscriber", "newsletter", "product update", "research invitation",
        "marketingcontact", "communicationconsent", "emailprovider", "campaign",
    ]

    private static let operationalContactTokens = [
        "servicecontactpointv1", "servicepartyreferencev1", "sitecontact",
        "site.address", "feedbackmail", "verifiedentitlementfactv1",
        "signoffsnapshotv1", "customerlearning",
    ]

    private static let marketingOutputTokens = [
        "marketingcontactv1", "communicationconsentreceiptv1",
        "communicationpreferencev1", "suppressionrecordv1", "subscriber",
    ]

    private static let conversionActionTokens = [
        "convert", "project", "create", "insert", "append", "upsert", "enroll",
    ]
}
