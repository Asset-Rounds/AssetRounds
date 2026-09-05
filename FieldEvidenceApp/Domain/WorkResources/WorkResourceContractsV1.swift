import Foundation

/// C49's canonical fact is append-only manual work-resource truth. It has no
/// inventory, timer, payroll, accounting, tax, estimate, invoice, or currency
/// conversion authority.
enum WorkResourceContractFailureV1: Error, Equatable, Sendable { case invalidValue, invalidDigest, invalidRevision, invalidTransition, crossWorkspace }

private enum WorkResourceCanonicalV1 {
    static func digest<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
    static func nonzero(_ id: UUID) throws { guard id != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) else { throw WorkResourceContractFailureV1.invalidValue } }
    static func digest(_ value: String) throws { guard value.count == 64 && value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw WorkResourceContractFailureV1.invalidDigest } }
}

private protocol WorkResourceCanonicalValidating {
    func validate() throws
}

/// Shared canonical byte route for persistence, backup, tests, and tooling.
/// It deliberately delegates to the established mutation canonicalizer rather
/// than creating a second JSON encoding policy.
enum WorkResourceCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        if let validating = value as? any WorkResourceCanonicalValidating {
            try validating.validate()
        }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}

enum WorkResourceSubjectKindV1: String, Codable, CaseIterable, Hashable, Sendable { case workPacket = "WORK_PACKET", correctiveWork = "CORRECTIVE_WORK" }

struct WorkResourceSubjectV1: Codable, Equatable, Hashable, Sendable, WorkResourceCanonicalValidating {
    let workspaceID: WorkspaceID; let kind: WorkResourceSubjectKindV1; let subjectID: String; let subjectRevision: UInt64; let subjectSHA256: String
    init(workspaceID: WorkspaceID, kind: WorkResourceSubjectKindV1, subjectID: String, subjectRevision: UInt64, subjectSHA256: String) throws {
        guard UUID(uuidString: subjectID) != nil, subjectRevision > 0 else { throw WorkResourceContractFailureV1.invalidValue }; try WorkResourceCanonicalV1.digest(subjectSHA256)
        self.workspaceID=workspaceID; self.kind=kind; self.subjectID=subjectID.lowercased(); self.subjectRevision=subjectRevision; self.subjectSHA256=subjectSHA256
    }
    func validate() throws { _ = try Self(workspaceID:workspaceID,kind:kind,subjectID:subjectID,subjectRevision:subjectRevision,subjectSHA256:subjectSHA256) }
}

struct ManualDurationV1: Codable, Equatable, Hashable, Sendable, WorkResourceCanonicalValidating { let minutes: Int; init(minutes: Int) throws { guard (1...10_080).contains(minutes) else { throw WorkResourceContractFailureV1.invalidValue }; self.minutes=minutes }; func validate() throws { _=try Self(minutes:minutes) } }
struct ExactDecimalQuantityV1: Codable, Equatable, Hashable, Sendable, WorkResourceCanonicalValidating { let mantissa: Int64; let scale: Int; init(mantissa: Int64, scale: Int) throws { guard mantissa > 0 && (0...3).contains(scale) else { throw WorkResourceContractFailureV1.invalidValue }; self.mantissa=mantissa; self.scale=scale }; func validate() throws { _=try Self(mantissa:mantissa,scale:scale) } }
struct ExactMoneyAmountV1: Codable, Equatable, Hashable, Sendable, WorkResourceCanonicalValidating {
    /// SIX ISO 4217 List One, published 2026-01-01.  This deliberately is a
    /// checked-in table: canonical validation must not depend on locale or a
    /// network response.  Only alphabetic codes with numeric minor units are
    /// present; List One `N.A.` units are intentionally absent.
    private static let iso4217MinorScales: [String: Int] = [
        "AED": 2, "AFN": 2, "ALL": 2, "AMD": 2, "AOA": 2, "ARS": 2,
        "AUD": 2, "AWG": 2, "AZN": 2, "BAM": 2, "BBD": 2, "BDT": 2,
        "BHD": 3, "BIF": 0, "BMD": 2, "BND": 2, "BOB": 2, "BOV": 2,
        "BRL": 2, "BSD": 2, "BTN": 2, "BWP": 2, "BYN": 2, "BZD": 2,
        "CAD": 2, "CDF": 2, "CHE": 2, "CHF": 2, "CHW": 2, "CLF": 4,
        "CLP": 0, "CNY": 2, "COP": 2, "COU": 2, "CRC": 2, "CUP": 2,
        "CVE": 2, "CZK": 2, "DJF": 0, "DKK": 2, "DOP": 2, "DZD": 2,
        "EGP": 2, "ERN": 2, "ETB": 2, "EUR": 2, "FJD": 2, "FKP": 2,
        "GBP": 2, "GEL": 2, "GHS": 2, "GIP": 2, "GMD": 2, "GNF": 0,
        "GTQ": 2, "GYD": 2, "HKD": 2, "HNL": 2, "HTG": 2, "HUF": 2,
        "IDR": 2, "ILS": 2, "INR": 2, "IQD": 3, "IRR": 2, "ISK": 0,
        "JMD": 2, "JOD": 3, "JPY": 0, "KES": 2, "KGS": 2, "KHR": 2,
        "KMF": 0, "KPW": 2, "KRW": 0, "KWD": 3, "KYD": 2, "KZT": 2,
        "LAK": 2, "LBP": 2, "LKR": 2, "LRD": 2, "LSL": 2, "LYD": 3,
        "MAD": 2, "MDL": 2, "MGA": 2, "MKD": 2, "MMK": 2, "MNT": 2,
        "MOP": 2, "MRU": 2, "MUR": 2, "MVR": 2, "MWK": 2, "MXN": 2,
        "MXV": 2, "MYR": 2, "MZN": 2, "NAD": 2, "NGN": 2, "NIO": 2,
        "NOK": 2, "NPR": 2, "NZD": 2, "OMR": 3, "PAB": 2, "PEN": 2,
        "PGK": 2, "PHP": 2, "PKR": 2, "PLN": 2, "PYG": 0, "QAR": 2,
        "RON": 2, "RSD": 2, "RUB": 2, "RWF": 0, "SAR": 2, "SBD": 2,
        "SCR": 2, "SDG": 2, "SEK": 2, "SGD": 2, "SHP": 2, "SLE": 2,
        "SOS": 2, "SRD": 2, "SSP": 2, "STN": 2, "SVC": 2, "SYP": 2,
        "SZL": 2, "THB": 2, "TJS": 2, "TMT": 2, "TND": 3, "TOP": 2,
        "TRY": 2, "TTD": 2, "TWD": 2, "TZS": 2, "UAH": 2, "UGX": 0,
        "USD": 2, "USN": 2, "UYI": 0, "UYU": 2, "UYW": 4, "UZS": 2,
        "VED": 2, "VES": 2, "VND": 0, "VUV": 0, "WST": 2, "XAD": 2,
        "XAF": 0, "XCD": 2, "XCG": 2, "XOF": 0, "XPF": 0, "YER": 2,
        "ZAR": 2, "ZMW": 2, "ZWG": 2
    ]
    let mantissa: Int64; let currencyCode: String; let minorUnitScale: Int
    init(mantissa: Int64, currencyCode: String, minorUnitScale: Int) throws {
        let utf8 = Array(currencyCode.utf8)
        guard mantissa > 0,
              utf8.count == 3,
              utf8.allSatisfy({ (65...90).contains($0) }),
              Self.iso4217MinorScales[currencyCode] == minorUnitScale else {
            throw WorkResourceContractFailureV1.invalidValue
        }
        self.mantissa=mantissa; self.currencyCode=currencyCode; self.minorUnitScale=minorUnitScale
    }
    func validate() throws { _=try Self(mantissa:mantissa,currencyCode:currencyCode,minorUnitScale:minorUnitScale) }
}
private func validWorkResourceText(_ text: String, min: Int, max: Int) -> Bool { text.count >= min && text.count <= max && text.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f && ![0x202a,0x202b,0x202c,0x202d,0x202e,0x2066,0x2067,0x2068,0x2069].contains($0.value) } }
struct ManualMaterialLineV1: Codable, Equatable, Hashable, Sendable { let lineID: UUID; let description: String; let quantity: ExactDecimalQuantityV1; let unit: String?; let localPartReference: LocalPartReferenceSnapshotV1?; init(lineID: UUID = UUID(), description: String, quantity: ExactDecimalQuantityV1, unit: String? = nil, localPartReference: LocalPartReferenceSnapshotV1? = nil) throws { try WorkResourceCanonicalV1.nonzero(lineID); try quantity.validate(); try localPartReference?.validate(); guard validWorkResourceText(description,min:1,max:160), unit.map({validWorkResourceText($0,min:1,max:24)}) ?? true else { throw WorkResourceContractFailureV1.invalidValue }; self.lineID=lineID; self.description=description; self.quantity=quantity; self.unit=unit; self.localPartReference=localPartReference }; func validate() throws { _=try Self(lineID:lineID,description:description,quantity:quantity,unit:unit,localPartReference:localPartReference) } }

/// Immutable local reference captured at entry time; never a live stock row.
struct LocalPartReferenceSnapshotV1: Codable, Equatable, Hashable, Sendable { let partID: UUID; let partRevision: UInt64; let partSHA256: String; let displayName: String; init(partID: UUID, partRevision: UInt64, partSHA256: String, displayName: String) throws { try WorkResourceCanonicalV1.nonzero(partID); guard partRevision > 0 && validWorkResourceText(displayName,min:1,max:160) else { throw WorkResourceContractFailureV1.invalidValue }; try WorkResourceCanonicalV1.digest(partSHA256); self.partID=partID; self.partRevision=partRevision; self.partSHA256=partSHA256; self.displayName=displayName }; func validate() throws { _=try Self(partID:partID,partRevision:partRevision,partSHA256:partSHA256,displayName:displayName) } }

enum WorkResourceVisibilityPolicyV1: String, Codable, CaseIterable, Hashable, Sendable { case internalOnly = "INTERNAL_ONLY", customerSafe = "CUSTOMER_SAFE" }
typealias WorkResourceVisibilityV1 = WorkResourceVisibilityPolicyV1
enum WorkResourceDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case active = "ACTIVE"
    case superseded = "SUPERSEDED"
    case voidedWithReason = "VOIDED_WITH_REASON"
    case reversed = "REVERSED"
}
struct DirectCostEntryV1: Codable, Equatable, Hashable, Sendable { let amount: ExactMoneyAmountV1; let note: String?; init(amount: ExactMoneyAmountV1, note: String? = nil) throws { try amount.validate(); guard note.map({validWorkResourceText($0,min:1,max:1024)}) ?? true else { throw WorkResourceContractFailureV1.invalidValue }; self.amount=amount; self.note=note }; func validate() throws { _=try Self(amount:amount,note:note) } }
extension ManualMaterialLineV1: WorkResourceCanonicalValidating {}
extension LocalPartReferenceSnapshotV1: WorkResourceCanonicalValidating {}
extension DirectCostEntryV1: WorkResourceCanonicalValidating {}

struct WorkResourceEntryV1: Codable, Equatable, Hashable, Sendable, WorkResourceCanonicalValidating {
    static let schemaVersion=1
    let schemaVersion:Int; let entryID: UUID; let workspaceID: WorkspaceID; let subject: WorkResourceSubjectV1; let actor: ActorSnapshotV1
    let duration: ManualDurationV1?; let materials:[ManualMaterialLineV1]; let directCost: DirectCostEntryV1?
    let visibility:WorkResourceVisibilityPolicyV1; let disposition:WorkResourceDispositionV1; let voidReason:String?; let recordedAt:Date; let expectedRevision:UInt64; let revision:UInt64; let supersedesEntryID:UUID?; let supersedesEntrySHA256:String?; let mutationID:MutationIDV1; let entrySHA256:String
    init(entryID: UUID, workspaceID: WorkspaceID, subject: WorkResourceSubjectV1, actor: ActorSnapshotV1, duration: ManualDurationV1? = nil, materials:[ManualMaterialLineV1]=[], directCost:DirectCostEntryV1?=nil, visibility:WorkResourceVisibilityPolicyV1 = .internalOnly, disposition:WorkResourceDispositionV1 = .active, voidReason:String?=nil, recordedAt:Date, expectedRevision:UInt64, revision:UInt64, supersedesEntryID:UUID?=nil, supersedesEntrySHA256:String?=nil, mutationID:MutationIDV1) throws {
        try WorkResourceCanonicalV1.nonzero(entryID); try actor.validate(); guard actor.workspaceID == workspaceID, subject.workspaceID == workspaceID, recordedAt.timeIntervalSinceReferenceDate.isFinite, mutationID.rawValue != UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)), materials.count <= 50 else { throw WorkResourceContractFailureV1.invalidValue }; if let supersedesEntryID { try WorkResourceCanonicalV1.nonzero(supersedesEntryID) }; if let supersedesEntrySHA256 { try WorkResourceCanonicalV1.digest(supersedesEntrySHA256) }; let (next,overflow)=expectedRevision.addingReportingOverflow(1); guard !overflow && revision == next, Set(materials.map(\.lineID)).count == materials.count, duration != nil || !materials.isEmpty || directCost != nil, (voidReason.map{validWorkResourceText($0,min:1,max:1024)} ?? true) else { throw WorkResourceContractFailureV1.invalidValue }; guard disposition == .voidedWithReason ? voidReason != nil : voidReason == nil, expectedRevision == 0 ? (supersedesEntryID == nil && supersedesEntrySHA256 == nil) : (supersedesEntryID != nil && supersedesEntrySHA256 != nil) else { throw WorkResourceContractFailureV1.invalidTransition }
        self.schemaVersion=Self.schemaVersion; self.entryID=entryID; self.workspaceID=workspaceID; self.subject=subject; self.actor=actor; self.duration=duration; self.materials=materials.sorted{$0.lineID.uuidString<$1.lineID.uuidString}; self.directCost=directCost; self.visibility=visibility; self.disposition=disposition; self.voidReason=voidReason; self.recordedAt=recordedAt; self.expectedRevision=expectedRevision; self.revision=revision; self.supersedesEntryID=supersedesEntryID; self.supersedesEntrySHA256=supersedesEntrySHA256; self.mutationID=mutationID; self.entrySHA256=try WorkResourceCanonicalV1.digest(Basis(schemaVersion:Self.schemaVersion,entryID:entryID,workspaceID:workspaceID,subject:subject,actor:actor,duration:duration,materials:self.materials,directCost:directCost,visibility:visibility,disposition:disposition,voidReason:voidReason,recordedAt:recordedAt,expectedRevision:expectedRevision,revision:revision,supersedesEntryID:supersedesEntryID,supersedesEntrySHA256:supersedesEntrySHA256,mutationID:mutationID))
    }
    func validate() throws { try subject.validate(); try actor.validate(); try duration?.validate(); try materials.forEach { try $0.validate() }; try directCost?.validate(); let rebuilt=try Self(entryID:entryID,workspaceID:workspaceID,subject:subject,actor:actor,duration:duration,materials:materials,directCost:directCost,visibility:visibility,disposition:disposition,voidReason:voidReason,recordedAt:recordedAt,expectedRevision:expectedRevision,revision:revision,supersedesEntryID:supersedesEntryID,supersedesEntrySHA256:supersedesEntrySHA256,mutationID:mutationID); guard rebuilt.entrySHA256==entrySHA256 && schemaVersion==Self.schemaVersion else { throw WorkResourceContractFailureV1.invalidDigest } }
    func validateSuccessor(of predecessor: Self) throws { try validate(); try predecessor.validate(); guard workspaceID==predecessor.workspaceID && subject==predecessor.subject && expectedRevision==predecessor.revision && supersedesEntryID==predecessor.entryID && supersedesEntrySHA256==predecessor.entrySHA256 else { throw WorkResourceContractFailureV1.invalidTransition } }
    /// Clone/restore callers must bind the target predecessor digest explicitly.
    /// A source-workspace predecessor digest is never implicitly reusable after
    /// subject or actor mapping; embedded local-part snapshots stay frozen.
    func rebound(
        to workspaceID: WorkspaceID,
        mappedSubject: WorkResourceSubjectV1,
        mappedActor: ActorSnapshotV1,
        mappedSupersedesEntrySHA256: String?,
        mutationID: MutationIDV1
    ) throws -> Self {
        guard mappedSubject.workspaceID == workspaceID,
              mappedActor.workspaceID == workspaceID,
              expectedRevision == 0 ? mappedSupersedesEntrySHA256 == nil : mappedSupersedesEntrySHA256 != nil else {
            throw WorkResourceContractFailureV1.crossWorkspace
        }
        if let mappedSupersedesEntrySHA256 {
            try WorkResourceCanonicalV1.digest(mappedSupersedesEntrySHA256)
        }
        return try .init(
            entryID: entryID,
            workspaceID: workspaceID,
            subject: mappedSubject,
            actor: mappedActor,
            duration: duration,
            materials: materials,
            directCost: directCost,
            visibility: visibility,
            disposition: disposition,
            voidReason: voidReason,
            recordedAt: recordedAt,
            expectedRevision: expectedRevision,
            revision: revision,
            supersedesEntryID: supersedesEntryID,
            supersedesEntrySHA256: mappedSupersedesEntrySHA256,
            mutationID: mutationID
        )
    }
    private struct Basis:Codable { let schemaVersion:Int;let entryID:UUID;let workspaceID:WorkspaceID;let subject:WorkResourceSubjectV1;let actor:ActorSnapshotV1;let duration:ManualDurationV1?;let materials:[ManualMaterialLineV1];let directCost:DirectCostEntryV1?;let visibility:WorkResourceVisibilityPolicyV1;let disposition:WorkResourceDispositionV1;let voidReason:String?;let recordedAt:Date;let expectedRevision:UInt64;let revision:UInt64;let supersedesEntryID:UUID?;let supersedesEntrySHA256:String?;let mutationID:MutationIDV1 }
}

struct WorkResourceSnapshotV1: Codable, Equatable, Sendable {
    let entry: WorkResourceEntryV1
    let snapshotSHA256: String

    init(entry: WorkResourceEntryV1) throws {
        try entry.validate()
        self.entry = entry
        snapshotSHA256 = try WorkResourceCanonicalCodecV1.sha256(entry)
    }

    func validate() throws {
        try entry.validate()
        guard snapshotSHA256 == (try WorkResourceCanonicalCodecV1.sha256(entry)) else {
            throw WorkResourceContractFailureV1.invalidDigest
        }
    }
}
extension WorkResourceSnapshotV1: WorkResourceCanonicalValidating {}

enum WorkResourceTotalsVisibilityV1: String, Codable, Sendable { case internalFull = "INTERNAL_FULL", customerSafe = "CUSTOMER_SAFE" }
struct WorkResourceMaterialTotalV1: Codable, Equatable, Sendable {
    let description: String
    let unit: String?
    let quantityMantissa: Int64
    let quantityScale: Int
}
struct WorkResourceTotalsProjectionV1: Codable, Equatable, Sendable {
    let durationMinutes: Int
    let materialLineCount: Int
    let materialTotals: [WorkResourceMaterialTotalV1]
    let directCostByCurrency: [String: Int64]

    init(snapshots: [WorkResourceSnapshotV1], visibility: WorkResourceTotalsVisibilityV1 = .internalFull) throws {
        var entriesByID: [UUID: WorkResourceEntryV1] = [:]
        for snapshot in snapshots {
            try snapshot.validate()
            guard entriesByID[snapshot.entry.entryID] == nil else {
                throw WorkResourceContractFailureV1.invalidTransition
            }
            entriesByID[snapshot.entry.entryID] = snapshot.entry
        }

        var referencedPredecessorIDs = Set<UUID>()
        for entry in entriesByID.values {
            guard let predecessorID = entry.supersedesEntryID else { continue }
            guard referencedPredecessorIDs.insert(predecessorID).inserted else {
                throw WorkResourceContractFailureV1.invalidTransition
            }
            if let predecessor = entriesByID[predecessorID] {
                try entry.validateSuccessor(of: predecessor)
            }
        }

        var duration = 0
        var materialLines = 0
        var costs: [String: Int64] = [:]
        var materials: [String: (description: String, unit: String?, mantissa: Int64)] = [:]
        for entry in entriesByID.values {
            guard !referencedPredecessorIDs.contains(entry.entryID) else { continue }
            guard entry.disposition == .active || entry.disposition == .superseded else { continue }
            guard visibility == .internalFull || entry.visibility == .customerSafe else { continue }
            let (nextDuration, durationOverflow) = duration.addingReportingOverflow(
                entry.duration?.minutes ?? 0
            )
            let (nextLines, linesOverflow) = materialLines.addingReportingOverflow(
                entry.materials.count
            )
            guard !durationOverflow, !linesOverflow else {
                throw WorkResourceContractFailureV1.invalidValue
            }
            duration = nextDuration
            materialLines = nextLines
            for line in entry.materials {
                let scaleMultiplier: Int64
                switch line.quantity.scale {
                case 0: scaleMultiplier = 1_000
                case 1: scaleMultiplier = 100
                case 2: scaleMultiplier = 10
                case 3: scaleMultiplier = 1
                default: throw WorkResourceContractFailureV1.invalidValue
                }
                let (normalized, normalizeOverflow) = line.quantity.mantissa.multipliedReportingOverflow(by: scaleMultiplier)
                guard !normalizeOverflow else { throw WorkResourceContractFailureV1.invalidValue }
                let key = line.description + "\u{0}" + (line.unit ?? "")
                let current = materials[key]?.mantissa ?? 0
                let (next, additionOverflow) = current.addingReportingOverflow(normalized)
                guard !additionOverflow else { throw WorkResourceContractFailureV1.invalidValue }
                materials[key] = (line.description, line.unit, next)
            }
            if visibility == .internalFull, let cost = entry.directCost {
                let current = costs[cost.amount.currencyCode, default: 0]
                let (nextCost, costOverflow) = current.addingReportingOverflow(cost.amount.mantissa)
                guard !costOverflow else { throw WorkResourceContractFailureV1.invalidValue }
                costs[cost.amount.currencyCode] = nextCost
            }
        }
        durationMinutes = duration
        materialLineCount = materialLines
        materialTotals = materials.values.map {
            WorkResourceMaterialTotalV1(description: $0.description, unit: $0.unit, quantityMantissa: $0.mantissa, quantityScale: 3)
        }.sorted {
            ($0.description, $0.unit ?? "") < ($1.description, $1.unit ?? "")
        }
        directCostByCurrency = costs
    }
}
typealias WorkResourceTotalsV1 = WorkResourceTotalsProjectionV1
/// The C50 adapter receives this derived customer-safe material summary only.
/// Direct costs, notes, actor/subject identities, local-part snapshots, and
/// canonical entry/mutation fields are deliberately absent.
struct C50WorkResourceAdapterProjectionV1: Codable, Equatable, Sendable {
    let durationMinutes: Int
    let materialLineCount: Int
    let materialTotals: [WorkResourceMaterialTotalV1]
    /// The exact workspace-scoped approval for the privacy derivative that
    /// authorized these customer-safe totals.
    let privacyApproval: C50PrivacyPreviewApprovalReferenceV1

    init(
        customerSafeTotals: WorkResourceTotalsProjectionV1,
        privacyApproval: C50PrivacyPreviewApprovalReferenceV1
    ) throws {
        guard customerSafeTotals.directCostByCurrency.isEmpty else {
            throw WorkResourceContractFailureV1.invalidValue
        }
        try privacyApproval.validate(workspaceID: privacyApproval.workspaceID)
        try privacyApproval.requireAuthoritativelyBound()
        durationMinutes = customerSafeTotals.durationMinutes
        materialLineCount = customerSafeTotals.materialLineCount
        materialTotals = customerSafeTotals.materialTotals
        self.privacyApproval = privacyApproval
    }
}

enum C50WorkResourceAdapterDelegationV1 {
    static let requiresCustomerSafePrivacyPreview = true
    static let allowlistedDerivedFields = ["durationMinutes", "materialLineCount", "materialTotals"]
    static let directCostAndNotesAreExcluded = true
    static let hiddenPrivateAndFrozenPartFieldsAreExcluded = true
    static let adapterOwnsNoCanonicalWriter = true
    static let adapterOwnsNoPersistentProfileOrSession = true

    static func validate(_ projection: C50WorkResourceAdapterProjectionV1) throws {
        try projection.privacyApproval.validate(workspaceID: projection.privacyApproval.workspaceID)
        try projection.privacyApproval.requireAuthoritativelyBound()
        guard projection.durationMinutes >= 0, projection.materialLineCount >= 0,
              projection.materialTotals.count <= projection.materialLineCount,
              requiresCustomerSafePrivacyPreview, directCostAndNotesAreExcluded,
              hiddenPrivateAndFrozenPartFieldsAreExcluded, adapterOwnsNoCanonicalWriter,
              adapterOwnsNoPersistentProfileOrSession else {
            throw WorkResourceContractFailureV1.invalidValue
        }
    }
}
enum C49WorkResourceContractBoundaryV1 {
    static let appendOnly=true
    static let directCostIsEmbedded=true
    static let liveInventoryReference=false
    static let soleWriter="WorkspaceWriterV1"
    static let iso4217ListOneSourceURL="https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml"
    static let iso4217ListOnePublished="2026-01-01"
    static let iso4217ListOneRawByteCount=47_463
    static let iso4217ListOneSHA256="838dfb991648cf36df939edd5fe3811737962b75a32252847d239cedd1e291c9"
    static let iso4217ListOneNumericMinorUnitCodeCount=165
}
