import Foundation

enum PartsStockFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, incompatibleVersion, staleRevision
    case unknownBalance, insufficientStock, crossWorkspace, duplicateMutation
    case invalidTransition, returnFrontierExceeded, unavailable, writesDisabled
}

enum PartsStockFeaturePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case enabled = "ENABLED"
    case readExportRecoveryOnly = "READ_EXPORT_RECOVERY_ONLY"

    var allowsWrites: Bool { self == .enabled }
}

enum PartsStockLimitsV1 {
    static let maximumCatalogNameBytes = 160
    static let maximumProductCodeBytes = 64
    static let maximumStorageLabelBytes = 80
    static let maximumBinLabelBytes = 40
    static let maximumReasonBytes = 1_024
    static let maximumSearchQueryBytes = 256
    static let maximumSnapshotRows = 100_000
}

protocol PartsStockCanonicalValidatingV1 { func validate() throws }

enum PartsStockDateValidationV1 {
    /// Canonical backup dates are integral milliseconds since 1970. Restrict
    /// the intermediate to Double's exact-integer range, then require an exact
    /// Date round trip so no sub-millisecond value can be silently truncated.
    static func requireMillisecond(_ date: Date) throws {
        let seconds = date.timeIntervalSince1970
        let milliseconds = seconds * 1_000
        let integralMilliseconds = milliseconds.rounded(.toNearestOrAwayFromZero)
        let maximumExactInteger = 9_007_199_254_740_991.0
        guard seconds.isFinite, milliseconds.isFinite,
              abs(integralMilliseconds) <= maximumExactInteger,
              Date(timeIntervalSince1970: integralMilliseconds / 1_000) == date else {
            throw PartsStockFailureV1.invalidValue
        }
    }
    static func requireActor(_ actor: ActorSnapshotV1) throws {
        try actor.validate(); try requireMillisecond(actor.capturedAt)
    }
    static func requireWorkResource(_ entry: WorkResourceEntryV1) throws {
        try entry.validate(); try requireActor(entry.actor); try requireMillisecond(entry.recordedAt)
    }
}

enum PartsStockCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }
    static func decode<T: Decodable & PartsStockCanonicalValidatingV1>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data); try value.validate(); return value
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

private enum PartsStockValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) -> Bool { value != zeroUUID }
    static func text(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes && value.unicodeScalars.allSatisfy {
            $0.value >= 0x20 && $0.value != 0x7f && ![0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069].contains($0.value)
        }
    }
    static func finiteMillisecond(_ date: Date) -> Bool { (try? PartsStockDateValidationV1.requireMillisecond(date)) != nil }
    static func scaled(_ value: StockQuantityV1, to scale: Int) -> Int64? {
        let (difference, differenceOverflow) = scale.subtractingReportingOverflow(value.scale)
        guard !differenceOverflow, difference >= 0, difference <= 3 else { return nil }
        let factor: Int64 = [1, 10, 100, 1_000][difference]
        let (result, overflow) = value.mantissa.multipliedReportingOverflow(by: factor)
        return overflow ? nil : result
    }
    static func movementResult(kind: StockMovementKindV1, quantity: StockQuantityV1, preBalance: StockBalanceV1, postBalance: StockQuantityV1) -> Bool {
        if kind == .openingCount || kind == .physicalCount { return quantity == postBalance }
        guard case .known(let pre) = preBalance else { return false }
        let scale = max(pre.scale, max(quantity.scale, postBalance.scale))
        guard let lhs = scaled(pre, to: scale), let rhs = scaled(quantity, to: scale), let actual = scaled(postBalance, to: scale) else { return false }
        let subtract = [.adjustmentDecrease, .useOnWork, .transferOut].contains(kind)
        let (expected, overflow) = subtract ? lhs.subtractingReportingOverflow(rhs) : lhs.addingReportingOverflow(rhs)
        return !overflow && expected >= 0 && expected == actual
    }
}

enum StockUnitFamilyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case each = "EACH", length = "LENGTH", mass = "MASS", volume = "VOLUME"
}

enum StockUnitV1: String, Codable, CaseIterable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    case each = "EACH"
    case millimeter = "MILLIMETER", centimeter = "CENTIMETER", meter = "METER", inch = "INCH", foot = "FOOT"
    case gram = "GRAM", kilogram = "KILOGRAM", ounce = "OUNCE", pound = "POUND"
    case milliliter = "MILLILITER", liter = "LITER", fluidOunce = "FLUID_OUNCE", gallon = "GALLON"

    var family: StockUnitFamilyV1 {
        switch self {
        case .each: return .each
        case .millimeter, .centimeter, .meter, .inch, .foot: return .length
        case .gram, .kilogram, .ounce, .pound: return .mass
        case .milliliter, .liter, .fluidOunce, .gallon: return .volume
        }
    }
    func validate() throws {}
}

/// Nonnegative exact stock quantity. It follows C49's mantissa/scale convention,
/// while permitting zero for balances and physical counts.
struct StockQuantityV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let mantissa: Int64
    let scale: Int
    init(mantissa: Int64, scale: Int, unit: StockUnitV1) throws {
        guard mantissa >= 0, (0...3).contains(scale), unit.family != .each || scale == 0 else { throw PartsStockFailureV1.invalidValue }
        self.mantissa = mantissa; self.scale = scale
    }
    func validate(for unit: StockUnitV1) throws { _ = try Self(mantissa: mantissa, scale: scale, unit: unit) }
    func validate() throws { guard mantissa >= 0, (0...3).contains(scale) else { throw PartsStockFailureV1.invalidValue } }
}

enum StockStorageKindV1: String, Codable, CaseIterable, Hashable, Sendable { case shop = "SHOP", vehicle = "VEHICLE", kit = "KIT", other = "OTHER" }

struct StockStorageLocationV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let locationID: UUID; let workspaceID: WorkspaceID
    let kind: StockStorageKindV1; let label: String; let binLabel: String?
    let revision: UInt64; let archived: Bool
    init(locationID: UUID, workspaceID: WorkspaceID, kind: StockStorageKindV1, label: String, binLabel: String? = nil, revision: UInt64, archived: Bool = false) throws {
        guard PartsStockValidationV1.id(locationID), PartsStockValidationV1.text(label, maximumBytes: PartsStockLimitsV1.maximumStorageLabelBytes), binLabel.map({ PartsStockValidationV1.text($0, maximumBytes: PartsStockLimitsV1.maximumBinLabelBytes) }) ?? true, revision > 0 else { throw PartsStockFailureV1.invalidValue }
        schemaVersion = Self.schemaVersion; self.locationID = locationID; self.workspaceID = workspaceID; self.kind = kind; self.label = label; self.binLabel = binLabel; self.revision = revision; self.archived = archived
    }
    func validate() throws { guard schemaVersion == Self.schemaVersion else { throw PartsStockFailureV1.incompatibleVersion }; _ = try Self(locationID: locationID, workspaceID: workspaceID, kind: kind, label: label, binLabel: binLabel, revision: revision, archived: archived) }
}

enum StockProductCodeKindV1: String, Codable, CaseIterable, Hashable, Sendable { case sku = "SKU", manufacturer = "MANUFACTURER", manualScan = "STOCK_MANUAL_SCAN", opaqueScan = "STOCK_OPAQUE_SCAN" }
struct StockProductIdentityV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let kind: StockProductCodeKindV1; let value: String
    init(kind: StockProductCodeKindV1, value: String) throws {
        guard PartsStockValidationV1.text(value, maximumBytes: PartsStockLimitsV1.maximumProductCodeBytes), !value.hasPrefix("asset:") else { throw PartsStockFailureV1.invalidValue }
        self.kind = kind; self.value = value
    }
    var locatorKey: ExternalKeyV1 { get throws { try ExternalKeyV1(namespaceID: "stock.part.v1.\(kind.rawValue)", normalization: .exactNFC, suppliedValue: value) } }
    func validate() throws { _ = try Self(kind: kind, value: value); _ = try locatorKey }
}

struct LocalPartDefinitionV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let partID: UUID; let workspaceID: WorkspaceID; let displayName: String
    let canonicalUnit: StockUnitV1; let productIdentities: [StockProductIdentityV1]
    let preferredMinimum: StockQuantityV1?; let archived: Bool; let revision: UInt64
    let mutationID: MutationIDV1; let partSHA256: String
    init(partID: UUID, workspaceID: WorkspaceID, displayName: String, canonicalUnit: StockUnitV1, productIdentities: [StockProductIdentityV1] = [], preferredMinimum: StockQuantityV1? = nil, archived: Bool = false, revision: UInt64, mutationID: MutationIDV1) throws {
        guard PartsStockValidationV1.id(partID), PartsStockValidationV1.text(displayName, maximumBytes: PartsStockLimitsV1.maximumCatalogNameBytes), productIdentities.count <= 16, Set(productIdentities).count == productIdentities.count, revision > 0 else { throw PartsStockFailureV1.invalidValue }
        try productIdentities.forEach { try $0.validate() }; try preferredMinimum?.validate(for: canonicalUnit)
        schemaVersion = Self.schemaVersion; self.partID = partID; self.workspaceID = workspaceID; self.displayName = displayName; self.canonicalUnit = canonicalUnit; self.productIdentities = productIdentities.sorted { ($0.kind.rawValue, $0.value) < ($1.kind.rawValue, $1.value) }; self.preferredMinimum = preferredMinimum; self.archived = archived; self.revision = revision; self.mutationID = mutationID
        partSHA256 = try PartsStockCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, partID: partID, workspaceID: workspaceID, displayName: displayName, canonicalUnit: canonicalUnit, productIdentities: self.productIdentities, preferredMinimum: preferredMinimum, archived: archived, revision: revision, mutationID: mutationID))
    }
    func validate() throws { guard schemaVersion == Self.schemaVersion else { throw PartsStockFailureV1.incompatibleVersion }; let rebuilt = try Self(partID: partID, workspaceID: workspaceID, displayName: displayName, canonicalUnit: canonicalUnit, productIdentities: productIdentities, preferredMinimum: preferredMinimum, archived: archived, revision: revision, mutationID: mutationID); guard rebuilt.partSHA256 == partSHA256 else { throw PartsStockFailureV1.invalidDigest } }
    func frozenReference() throws -> LocalPartReferenceSnapshotV1 { try .init(partID: partID, partRevision: revision, partSHA256: partSHA256, displayName: displayName) }
    private struct Basis: Codable { let schemaVersion: Int; let partID: UUID; let workspaceID: WorkspaceID; let displayName: String; let canonicalUnit: StockUnitV1; let productIdentities: [StockProductIdentityV1]; let preferredMinimum: StockQuantityV1?; let archived: Bool; let revision: UInt64; let mutationID: MutationIDV1 }
}

enum StockBalanceV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    case unknown
    case known(StockQuantityV1)
    private enum CodingKeys: String, CodingKey { case state, quantity }
    private enum State: String, Codable { case unknown = "UNKNOWN", known = "KNOWN" }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); switch try c.decode(State.self, forKey: .state) { case .unknown: guard !c.contains(.quantity) else { throw PartsStockFailureV1.invalidValue }; self = .unknown; case .known: self = .known(try c.decode(StockQuantityV1.self, forKey: .quantity)) }; try validate() }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); switch self { case .unknown: try c.encode(State.unknown, forKey: .state); case .known(let value): try c.encode(State.known, forKey: .state); try c.encode(value, forKey: .quantity) } }
    func validate() throws { if case .known(let value) = self { try value.validate() } }
}

enum StockMovementKindV1: String, Codable, CaseIterable, Hashable, Sendable { case openingCount = "OPENING_COUNT", physicalCount = "PHYSICAL_COUNT", adjustmentIncrease = "ADJUSTMENT_INCREASE", adjustmentDecrease = "ADJUSTMENT_DECREASE", useOnWork = "USE_ON_WORK", returnAgainstUse = "RETURN_AGAINST_USE", transferOut = "TRANSFER_OUT", transferIn = "TRANSFER_IN", reverseUse = "REVERSE_USE" }

struct StockMovementEventV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let movementID: UUID; let workspaceID: WorkspaceID; let part: LocalPartReferenceSnapshotV1
    let locationID: UUID; let kind: StockMovementKindV1; let quantity: StockQuantityV1
    let unit: StockUnitV1; let preBalance: StockBalanceV1; let postBalance: StockQuantityV1
    let relatedMovementID: UUID?; let reason: String?; let actor: ActorSnapshotV1
    let occurredAt: Date; let recordedAt: Date; let expectedLocationRevision: UInt64; let locationRevision: UInt64
    let mutationID: MutationIDV1; let eventSHA256: String
    init(movementID: UUID, workspaceID: WorkspaceID, part: LocalPartReferenceSnapshotV1, locationID: UUID, kind: StockMovementKindV1, quantity: StockQuantityV1, unit: StockUnitV1, preBalance: StockBalanceV1, postBalance: StockQuantityV1, relatedMovementID: UUID? = nil, reason: String? = nil, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date, expectedLocationRevision: UInt64, mutationID: MutationIDV1) throws {
        let (next, overflow) = expectedLocationRevision.addingReportingOverflow(1)
        guard !overflow, PartsStockValidationV1.id(movementID), PartsStockValidationV1.id(locationID), relatedMovementID.map(PartsStockValidationV1.id) ?? true, relatedMovementID != movementID, PartsStockValidationV1.finiteMillisecond(occurredAt), PartsStockValidationV1.finiteMillisecond(recordedAt), occurredAt <= recordedAt, reason.map({ PartsStockValidationV1.text($0, maximumBytes: PartsStockLimitsV1.maximumReasonBytes) }) ?? true else { throw PartsStockFailureV1.invalidValue }
        try part.validate(); try quantity.validate(for: unit); try preBalance.validate(); try postBalance.validate(for: unit); try PartsStockDateValidationV1.requireActor(actor)
        guard actor.workspaceID == workspaceID else { throw PartsStockFailureV1.crossWorkspace }
        let needsReason = [.adjustmentIncrease, .adjustmentDecrease, .reverseUse].contains(kind)
        let needsRelation = [.returnAgainstUse, .transferOut, .transferIn, .reverseUse].contains(kind)
        guard needsReason == (reason != nil), needsRelation == (relatedMovementID != nil), (kind == .openingCount || kind == .physicalCount || quantity.mantissa > 0), PartsStockValidationV1.movementResult(kind: kind, quantity: quantity, preBalance: preBalance, postBalance: postBalance) else { throw PartsStockFailureV1.invalidTransition }
        schemaVersion = Self.schemaVersion; self.movementID = movementID; self.workspaceID = workspaceID; self.part = part; self.locationID = locationID; self.kind = kind; self.quantity = quantity; self.unit = unit; self.preBalance = preBalance; self.postBalance = postBalance; self.relatedMovementID = relatedMovementID; self.reason = reason; self.actor = actor; self.occurredAt = occurredAt; self.recordedAt = recordedAt; self.expectedLocationRevision = expectedLocationRevision; locationRevision = next; self.mutationID = mutationID
        eventSHA256 = try PartsStockCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, movementID: movementID, workspaceID: workspaceID, part: part, locationID: locationID, kind: kind, quantity: quantity, unit: unit, preBalance: preBalance, postBalance: postBalance, relatedMovementID: relatedMovementID, reason: reason, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: expectedLocationRevision, locationRevision: next, mutationID: mutationID))
    }
    func validate() throws { guard schemaVersion == Self.schemaVersion else { throw PartsStockFailureV1.incompatibleVersion }; let rebuilt = try Self(movementID: movementID, workspaceID: workspaceID, part: part, locationID: locationID, kind: kind, quantity: quantity, unit: unit, preBalance: preBalance, postBalance: postBalance, relatedMovementID: relatedMovementID, reason: reason, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: expectedLocationRevision, mutationID: mutationID); guard rebuilt.eventSHA256 == eventSHA256, rebuilt.locationRevision == locationRevision else { throw PartsStockFailureV1.invalidDigest } }
    private struct Basis: Codable { let schemaVersion: Int; let movementID: UUID; let workspaceID: WorkspaceID; let part: LocalPartReferenceSnapshotV1; let locationID: UUID; let kind: StockMovementKindV1; let quantity: StockQuantityV1; let unit: StockUnitV1; let preBalance: StockBalanceV1; let postBalance: StockQuantityV1; let relatedMovementID: UUID?; let reason: String?; let actor: ActorSnapshotV1; let occurredAt: Date; let recordedAt: Date; let expectedLocationRevision: UInt64; let locationRevision: UInt64; let mutationID: MutationIDV1 }
}

struct StockBalanceProjectionV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let workspaceID: WorkspaceID; let partID: UUID; let locationID: UUID; let unit: StockUnitV1
    let balance: StockBalanceV1; let locationRevision: UInt64; let lastMovementID: UUID?
    func validate() throws { guard PartsStockValidationV1.id(partID), PartsStockValidationV1.id(locationID), lastMovementID.map(PartsStockValidationV1.id) ?? true else { throw PartsStockFailureV1.invalidValue }; try balance.validate(); if case .known(let q) = balance { try q.validate(for: unit) } }
}

struct StockAttentionProjectionV1: Codable, Equatable, Hashable, Sendable {
    let partID: UUID; let locationID: UUID; let isBelowPreferred: Bool; let balance: StockBalanceV1
}

struct StockUseOnWorkReceiptV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let movement: StockMovementEventV1
    let workResourceSuccessor: WorkResourceEntryV1; let frozenMaterialLineID: UUID; let mutationID: MutationIDV1; let receiptSHA256: String
    init(receiptID: UUID, movement: StockMovementEventV1, workResourceSuccessor: WorkResourceEntryV1, frozenMaterialLineID: UUID, mutationID: MutationIDV1) throws {
        guard movement.kind == .useOnWork, PartsStockValidationV1.id(receiptID), PartsStockValidationV1.id(frozenMaterialLineID), movement.mutationID == mutationID, workResourceSuccessor.mutationID == mutationID, movement.workspaceID == workResourceSuccessor.workspaceID, workResourceSuccessor.materials.contains(where: { $0.lineID == frozenMaterialLineID && $0.localPartReference == movement.part && $0.quantity.mantissa == movement.quantity.mantissa && $0.quantity.scale == movement.quantity.scale && $0.unit == movement.unit.rawValue }) else { throw PartsStockFailureV1.invalidTransition }
        try movement.validate(); try PartsStockDateValidationV1.requireWorkResource(workResourceSuccessor); schemaVersion = Self.schemaVersion; self.receiptID = receiptID; workspaceID = movement.workspaceID; self.movement = movement; self.workResourceSuccessor = workResourceSuccessor; self.frozenMaterialLineID = frozenMaterialLineID; self.mutationID = mutationID
        receiptSHA256 = try PartsStockCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, receiptID: receiptID, workspaceID: workspaceID, movement: movement, workResourceSuccessor: workResourceSuccessor, frozenMaterialLineID: frozenMaterialLineID, mutationID: mutationID))
    }
    func validate() throws { guard schemaVersion == Self.schemaVersion else { throw PartsStockFailureV1.incompatibleVersion }; let rebuilt = try Self(receiptID: receiptID, movement: movement, workResourceSuccessor: workResourceSuccessor, frozenMaterialLineID: frozenMaterialLineID, mutationID: mutationID); guard rebuilt.receiptSHA256 == receiptSHA256 else { throw PartsStockFailureV1.invalidDigest } }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let movement: StockMovementEventV1; let workResourceSuccessor: WorkResourceEntryV1; let frozenMaterialLineID: UUID; let mutationID: MutationIDV1 }
}

struct StockUseReversalReceiptV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let receiptID: UUID; let workspaceID: WorkspaceID; let sourceUse: StockUseOnWorkReceiptV1
    let reversalMovement: StockMovementEventV1; let workResourceSuccessor: WorkResourceEntryV1
    let reason: String; let mutationID: MutationIDV1; let receiptSHA256: String
    init(receiptID: UUID, sourceUse: StockUseOnWorkReceiptV1, reversalMovement: StockMovementEventV1, workResourceSuccessor: WorkResourceEntryV1, reason: String, mutationID: MutationIDV1) throws {
        try sourceUse.validate(); try reversalMovement.validate(); try PartsStockDateValidationV1.requireWorkResource(sourceUse.workResourceSuccessor); try PartsStockDateValidationV1.requireWorkResource(workResourceSuccessor); try workResourceSuccessor.validateSuccessor(of: sourceUse.workResourceSuccessor)
        let removesMaterial = !workResourceSuccessor.materials.contains(where: { $0.lineID == sourceUse.frozenMaterialLineID })
        let reversesWholeEntry = workResourceSuccessor.disposition == .reversed && workResourceSuccessor.materials == sourceUse.workResourceSuccessor.materials
        guard PartsStockValidationV1.id(receiptID), PartsStockValidationV1.text(reason, maximumBytes: PartsStockLimitsV1.maximumReasonBytes), reversalMovement.kind == .reverseUse, reversalMovement.reason == reason, reversalMovement.relatedMovementID == sourceUse.movement.movementID, reversalMovement.workspaceID == sourceUse.workspaceID, reversalMovement.part == sourceUse.movement.part, reversalMovement.quantity == sourceUse.movement.quantity, reversalMovement.unit == sourceUse.movement.unit, reversalMovement.mutationID == mutationID, workResourceSuccessor.workspaceID == sourceUse.workspaceID, workResourceSuccessor.mutationID == mutationID, removesMaterial || reversesWholeEntry else { throw PartsStockFailureV1.invalidTransition }
        self.receiptID = receiptID; workspaceID = sourceUse.workspaceID; self.sourceUse = sourceUse; self.reversalMovement = reversalMovement; self.workResourceSuccessor = workResourceSuccessor; self.reason = reason; self.mutationID = mutationID
        receiptSHA256 = try PartsStockCanonicalCodecV1.sha256(Basis(receiptID: receiptID, workspaceID: workspaceID, sourceUse: sourceUse, reversalMovement: reversalMovement, workResourceSuccessor: workResourceSuccessor, reason: reason, mutationID: mutationID))
    }
    func validate() throws {
        try sourceUse.validate(); try reversalMovement.validate(); try PartsStockDateValidationV1.requireWorkResource(sourceUse.workResourceSuccessor); try PartsStockDateValidationV1.requireWorkResource(workResourceSuccessor); try workResourceSuccessor.validateSuccessor(of: sourceUse.workResourceSuccessor)
        let removesMaterial = !workResourceSuccessor.materials.contains(where: { $0.lineID == sourceUse.frozenMaterialLineID })
        let reversesWholeEntry = workResourceSuccessor.disposition == .reversed && workResourceSuccessor.materials == sourceUse.workResourceSuccessor.materials
        guard reversalMovement.kind == .reverseUse, reversalMovement.reason == reason, reversalMovement.relatedMovementID == sourceUse.movement.movementID, reversalMovement.workspaceID == workspaceID, reversalMovement.part == sourceUse.movement.part, reversalMovement.quantity == sourceUse.movement.quantity, reversalMovement.unit == sourceUse.movement.unit, reversalMovement.mutationID == mutationID, workResourceSuccessor.workspaceID == workspaceID, workResourceSuccessor.mutationID == mutationID, removesMaterial || reversesWholeEntry, receiptSHA256 == (try PartsStockCanonicalCodecV1.sha256(Basis(receiptID: receiptID, workspaceID: workspaceID, sourceUse: sourceUse, reversalMovement: reversalMovement, workResourceSuccessor: workResourceSuccessor, reason: reason, mutationID: mutationID))) else { throw PartsStockFailureV1.invalidDigest }
    }
    private struct Basis: Codable { let receiptID: UUID; let workspaceID: WorkspaceID; let sourceUse: StockUseOnWorkReceiptV1; let reversalMovement: StockMovementEventV1; let workResourceSuccessor: WorkResourceEntryV1; let reason: String; let mutationID: MutationIDV1 }
}

struct StockReturnFrontierSnapshotV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let returnReceiptID: UUID; let returnReceiptSHA256: String; let sourceUseReceiptID: UUID
    let resultingReturnedMantissa: Int64; let workResourceSuccessorID: UUID
    let workResourceSuccessorRevision: UInt64; let workResourceSuccessorSHA256: String; let frontierSHA256: String
    init(returnReceiptID: UUID, returnReceiptSHA256: String, sourceUseReceiptID: UUID, resultingReturnedMantissa: Int64, workResourceSuccessor: WorkResourceEntryV1) throws {
        guard PartsStockValidationV1.id(returnReceiptID), PartsStockValidationV1.id(sourceUseReceiptID), PartsStockCanonicalCodecV1.isDigest(returnReceiptSHA256), resultingReturnedMantissa > 0 else { throw PartsStockFailureV1.invalidValue }
        try PartsStockDateValidationV1.requireWorkResource(workResourceSuccessor)
        self.returnReceiptID = returnReceiptID; self.returnReceiptSHA256 = returnReceiptSHA256; self.sourceUseReceiptID = sourceUseReceiptID; self.resultingReturnedMantissa = resultingReturnedMantissa; workResourceSuccessorID = workResourceSuccessor.entryID; workResourceSuccessorRevision = workResourceSuccessor.revision; workResourceSuccessorSHA256 = workResourceSuccessor.entrySHA256
        frontierSHA256 = try PartsStockCanonicalCodecV1.sha256(Basis(returnReceiptID: returnReceiptID, returnReceiptSHA256: returnReceiptSHA256, sourceUseReceiptID: sourceUseReceiptID, resultingReturnedMantissa: resultingReturnedMantissa, workResourceSuccessorID: workResourceSuccessor.entryID, workResourceSuccessorRevision: workResourceSuccessor.revision, workResourceSuccessorSHA256: workResourceSuccessor.entrySHA256))
    }
    func validate() throws { guard PartsStockValidationV1.id(returnReceiptID), PartsStockValidationV1.id(sourceUseReceiptID), PartsStockCanonicalCodecV1.isDigest(returnReceiptSHA256), PartsStockCanonicalCodecV1.isDigest(workResourceSuccessorSHA256), resultingReturnedMantissa > 0, workResourceSuccessorRevision > 0, frontierSHA256 == (try PartsStockCanonicalCodecV1.sha256(Basis(returnReceiptID: returnReceiptID, returnReceiptSHA256: returnReceiptSHA256, sourceUseReceiptID: sourceUseReceiptID, resultingReturnedMantissa: resultingReturnedMantissa, workResourceSuccessorID: workResourceSuccessorID, workResourceSuccessorRevision: workResourceSuccessorRevision, workResourceSuccessorSHA256: workResourceSuccessorSHA256))) else { throw PartsStockFailureV1.invalidDigest } }
    private struct Basis: Codable { let returnReceiptID: UUID; let returnReceiptSHA256: String; let sourceUseReceiptID: UUID; let resultingReturnedMantissa: Int64; let workResourceSuccessorID: UUID; let workResourceSuccessorRevision: UInt64; let workResourceSuccessorSHA256: String }
}

struct StockReturnAgainstUseReceiptV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let sourceUseReceiptID: UUID; let sourceUseReceiptSHA256: String
    let sourceUse: StockUseOnWorkReceiptV1
    let predecessorFrontier: StockReturnFrontierSnapshotV1?; let expectedReturnedMantissa: Int64; let resultingReturnedMantissa: Int64; let returnMovement: StockMovementEventV1
    let workResourcePredecessor: WorkResourceEntryV1
    let workResourceSuccessor: WorkResourceEntryV1; let mutationID: MutationIDV1; let receiptSHA256: String
    init(receiptID: UUID, sourceUse: StockUseOnWorkReceiptV1, predecessorFrontier: StockReturnFrontierSnapshotV1?, returnMovement: StockMovementEventV1, workResourcePredecessor: WorkResourceEntryV1, workResourceSuccessor: WorkResourceEntryV1, mutationID: MutationIDV1) throws {
        try sourceUse.validate(); try returnMovement.validate(); try PartsStockDateValidationV1.requireWorkResource(sourceUse.workResourceSuccessor); try PartsStockDateValidationV1.requireWorkResource(workResourcePredecessor); try PartsStockDateValidationV1.requireWorkResource(workResourceSuccessor); try workResourceSuccessor.validateSuccessor(of: workResourcePredecessor)
        try predecessorFrontier?.validate(); let expectedReturnedMantissa = predecessorFrontier?.resultingReturnedMantissa ?? 0
        let (resulting, overflow) = expectedReturnedMantissa.addingReportingOverflow(returnMovement.quantity.mantissa)
        let (priorRemaining, priorRemainingOverflow) = sourceUse.movement.quantity.mantissa.subtractingReportingOverflow(expectedReturnedMantissa)
        let (resultingRemaining, resultingRemainingOverflow) = sourceUse.movement.quantity.mantissa.subtractingReportingOverflow(resulting)
        let predecessorLine = workResourcePredecessor.materials.first(where: { $0.lineID == sourceUse.frozenMaterialLineID })
        let successorLine = workResourceSuccessor.materials.first(where: { $0.lineID == sourceUse.frozenMaterialLineID })
        guard !overflow, !priorRemainingOverflow, !resultingRemainingOverflow,
              PartsStockValidationV1.id(receiptID), expectedReturnedMantissa >= 0, resulting <= sourceUse.movement.quantity.mantissa, sourceUse.movement.quantity.scale == returnMovement.quantity.scale, returnMovement.kind == .returnAgainstUse, returnMovement.relatedMovementID == sourceUse.movement.movementID, returnMovement.workspaceID == sourceUse.workspaceID, returnMovement.part == sourceUse.movement.part, returnMovement.unit == sourceUse.movement.unit, returnMovement.mutationID == mutationID, workResourceSuccessor.workspaceID == sourceUse.workspaceID, workResourceSuccessor.mutationID == mutationID else { throw PartsStockFailureV1.returnFrontierExceeded }
        let predecessorMatches = predecessorFrontier == nil
            ? workResourcePredecessor == sourceUse.workResourceSuccessor
            : predecessorFrontier?.sourceUseReceiptID == sourceUse.receiptID && predecessorFrontier?.workResourceSuccessorID == workResourcePredecessor.entryID && predecessorFrontier?.workResourceSuccessorRevision == workResourcePredecessor.revision && predecessorFrontier?.workResourceSuccessorSHA256 == workResourcePredecessor.entrySHA256
        guard predecessorMatches,
              predecessorLine?.quantity.mantissa == priorRemaining,
              predecessorLine?.quantity.scale == sourceUse.movement.quantity.scale,
              predecessorLine?.unit == sourceUse.movement.unit.rawValue,
              (resultingRemaining == 0 ? (successorLine == nil || (workResourceSuccessor.disposition == .reversed && workResourceSuccessor.materials == workResourcePredecessor.materials)) : (successorLine?.quantity.mantissa == resultingRemaining && successorLine?.quantity.scale == sourceUse.movement.quantity.scale && successorLine?.localPartReference == sourceUse.movement.part && successorLine?.unit == sourceUse.movement.unit.rawValue)) else { throw PartsStockFailureV1.returnFrontierExceeded }
        schemaVersion = Self.schemaVersion; self.receiptID = receiptID; workspaceID = sourceUse.workspaceID; sourceUseReceiptID = sourceUse.receiptID; sourceUseReceiptSHA256 = sourceUse.receiptSHA256; self.sourceUse = sourceUse; self.predecessorFrontier = predecessorFrontier; self.expectedReturnedMantissa = expectedReturnedMantissa; resultingReturnedMantissa = resulting; self.returnMovement = returnMovement; self.workResourcePredecessor = workResourcePredecessor; self.workResourceSuccessor = workResourceSuccessor; self.mutationID = mutationID
        receiptSHA256 = try PartsStockCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, receiptID: receiptID, workspaceID: workspaceID, sourceUseReceiptID: sourceUseReceiptID, sourceUseReceiptSHA256: sourceUseReceiptSHA256, sourceUse: sourceUse, predecessorFrontier: predecessorFrontier, expectedReturnedMantissa: expectedReturnedMantissa, resultingReturnedMantissa: resulting, returnMovement: returnMovement, workResourcePredecessor: workResourcePredecessor, workResourceSuccessor: workResourceSuccessor, mutationID: mutationID))
    }
    func validate() throws {
        try sourceUse.validate(); try returnMovement.validate(); try PartsStockDateValidationV1.requireWorkResource(sourceUse.workResourceSuccessor); try PartsStockDateValidationV1.requireWorkResource(workResourcePredecessor); try PartsStockDateValidationV1.requireWorkResource(workResourceSuccessor); try workResourceSuccessor.validateSuccessor(of: workResourcePredecessor)
        let (resulting, overflow) = expectedReturnedMantissa.addingReportingOverflow(returnMovement.quantity.mantissa)
        let (priorRemaining, priorRemainingOverflow) = sourceUse.movement.quantity.mantissa.subtractingReportingOverflow(expectedReturnedMantissa)
        let (resultingRemaining, resultingRemainingOverflow) = sourceUse.movement.quantity.mantissa.subtractingReportingOverflow(resulting)
        let predecessorLine = workResourcePredecessor.materials.first(where: { $0.lineID == sourceUse.frozenMaterialLineID })
        let successorLine = workResourceSuccessor.materials.first(where: { $0.lineID == sourceUse.frozenMaterialLineID })
        guard schemaVersion == Self.schemaVersion, !overflow, !priorRemainingOverflow, !resultingRemainingOverflow,
              PartsStockCanonicalCodecV1.isDigest(sourceUseReceiptSHA256), sourceUseReceiptID == sourceUse.receiptID, sourceUseReceiptSHA256 == sourceUse.receiptSHA256, sourceUse.workspaceID == workspaceID, expectedReturnedMantissa == (predecessorFrontier?.resultingReturnedMantissa ?? 0), expectedReturnedMantissa >= 0, resulting == resultingReturnedMantissa, resultingReturnedMantissa <= sourceUse.movement.quantity.mantissa, returnMovement.kind == .returnAgainstUse, returnMovement.relatedMovementID == sourceUse.movement.movementID, returnMovement.part == sourceUse.movement.part, returnMovement.unit == sourceUse.movement.unit, returnMovement.workspaceID == workspaceID, workResourceSuccessor.workspaceID == workspaceID, returnMovement.mutationID == mutationID, workResourceSuccessor.mutationID == mutationID else { throw PartsStockFailureV1.invalidValue }
        try predecessorFrontier?.validate()
        let predecessorMatches = predecessorFrontier == nil ? workResourcePredecessor == sourceUse.workResourceSuccessor : predecessorFrontier?.sourceUseReceiptID == sourceUse.receiptID && predecessorFrontier?.workResourceSuccessorID == workResourcePredecessor.entryID && predecessorFrontier?.workResourceSuccessorRevision == workResourcePredecessor.revision && predecessorFrontier?.workResourceSuccessorSHA256 == workResourcePredecessor.entrySHA256
        guard predecessorMatches else { throw PartsStockFailureV1.returnFrontierExceeded }
        guard predecessorLine?.quantity.mantissa == priorRemaining, predecessorLine?.quantity.scale == sourceUse.movement.quantity.scale,
              predecessorLine?.unit == sourceUse.movement.unit.rawValue,
              (resultingRemaining == 0 ? (successorLine == nil || (workResourceSuccessor.disposition == .reversed && workResourceSuccessor.materials == workResourcePredecessor.materials)) : (successorLine?.quantity.mantissa == resultingRemaining && successorLine?.quantity.scale == sourceUse.movement.quantity.scale && successorLine?.localPartReference == sourceUse.movement.part && successorLine?.unit == sourceUse.movement.unit.rawValue)) else { throw PartsStockFailureV1.returnFrontierExceeded }
        let expected = try PartsStockCanonicalCodecV1.sha256(Basis(schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID, sourceUseReceiptID: sourceUseReceiptID, sourceUseReceiptSHA256: sourceUseReceiptSHA256, sourceUse: sourceUse, predecessorFrontier: predecessorFrontier, expectedReturnedMantissa: expectedReturnedMantissa, resultingReturnedMantissa: resultingReturnedMantissa, returnMovement: returnMovement, workResourcePredecessor: workResourcePredecessor, workResourceSuccessor: workResourceSuccessor, mutationID: mutationID)); guard expected == receiptSHA256 else { throw PartsStockFailureV1.invalidDigest }
    }
    func frontierSnapshot() throws -> StockReturnFrontierSnapshotV1 { try validate(); return try .init(returnReceiptID: receiptID, returnReceiptSHA256: receiptSHA256, sourceUseReceiptID: sourceUseReceiptID, resultingReturnedMantissa: resultingReturnedMantissa, workResourceSuccessor: workResourceSuccessor) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let sourceUseReceiptID: UUID; let sourceUseReceiptSHA256: String; let sourceUse: StockUseOnWorkReceiptV1; let predecessorFrontier: StockReturnFrontierSnapshotV1?; let expectedReturnedMantissa: Int64; let resultingReturnedMantissa: Int64; let returnMovement: StockMovementEventV1; let workResourcePredecessor: WorkResourceEntryV1; let workResourceSuccessor: WorkResourceEntryV1; let mutationID: MutationIDV1 }
}

struct StockTransferReceiptV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let workspaceID: WorkspaceID; let outbound: StockMovementEventV1; let inbound: StockMovementEventV1; let mutationID: MutationIDV1
    func validate() throws { try outbound.validate(); try inbound.validate(); guard outbound.workspaceID == workspaceID, inbound.workspaceID == workspaceID, outbound.kind == .transferOut, inbound.kind == .transferIn, outbound.locationID != inbound.locationID, outbound.part == inbound.part, outbound.quantity == inbound.quantity, outbound.unit == inbound.unit, outbound.mutationID == mutationID, inbound.mutationID == mutationID, outbound.relatedMovementID == inbound.movementID, inbound.relatedMovementID == outbound.movementID else { throw PartsStockFailureV1.invalidTransition } }
}

struct AbandonUnverifiedStockDispositionV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let dispositionID: UUID; let workspaceID: WorkspaceID; let partID: UUID; let locationID: UUID
    let actor: ActorSnapshotV1; let reason: String; let lastMovementID: UUID?; let lastLocationRevision: UInt64
    let quantityRemainsUnknown: Bool; let recordedAt: Date; let mutationID: MutationIDV1
    init(dispositionID: UUID, workspaceID: WorkspaceID, partID: UUID, locationID: UUID, actor: ActorSnapshotV1, reason: String, lastMovementID: UUID?, lastLocationRevision: UInt64, recordedAt: Date, mutationID: MutationIDV1, currentBalance: StockBalanceV1) throws {
        guard case .unknown = currentBalance, PartsStockValidationV1.id(dispositionID), PartsStockValidationV1.id(partID), PartsStockValidationV1.id(locationID), lastMovementID.map(PartsStockValidationV1.id) ?? true, actor.workspaceID == workspaceID, PartsStockValidationV1.text(reason, maximumBytes: PartsStockLimitsV1.maximumReasonBytes), PartsStockValidationV1.finiteMillisecond(recordedAt) else { throw PartsStockFailureV1.invalidTransition }
        try PartsStockDateValidationV1.requireActor(actor); schemaVersion = Self.schemaVersion; self.dispositionID = dispositionID; self.workspaceID = workspaceID; self.partID = partID; self.locationID = locationID; self.actor = actor; self.reason = reason; self.lastMovementID = lastMovementID; self.lastLocationRevision = lastLocationRevision; quantityRemainsUnknown = true; self.recordedAt = recordedAt; self.mutationID = mutationID
    }
    func validate() throws { guard schemaVersion == Self.schemaVersion, quantityRemainsUnknown, PartsStockValidationV1.id(dispositionID), PartsStockValidationV1.id(partID), PartsStockValidationV1.id(locationID), actor.workspaceID == workspaceID, PartsStockValidationV1.text(reason, maximumBytes: PartsStockLimitsV1.maximumReasonBytes), PartsStockValidationV1.finiteMillisecond(recordedAt) else { throw PartsStockFailureV1.invalidValue }; try PartsStockDateValidationV1.requireActor(actor) }
}

/// Atomic abandonment payload: the audit fact and catalog archive successor are
/// inseparable. The incumbent writer must additionally prove its complete
/// part/location projection contains no KNOWN-positive balance before commit.
struct StockAbandonmentReceiptV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let dispositions: [AbandonUnverifiedStockDispositionV1]
    let predecessorPart: LocalPartDefinitionV1; let archivedPartSuccessor: LocalPartDefinitionV1
    init(dispositions: [AbandonUnverifiedStockDispositionV1], archivedPartSuccessor: LocalPartDefinitionV1, predecessor: LocalPartDefinitionV1) throws {
        try dispositions.forEach { try $0.validate() }; try predecessor.validate(); try archivedPartSuccessor.validate()
        let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
        guard !overflow, !dispositions.isEmpty, Set(dispositions.map(\.locationID)).count == dispositions.count,
              !predecessor.archived, archivedPartSuccessor.archived,
              dispositions.allSatisfy({ $0.workspaceID == predecessor.workspaceID && $0.partID == predecessor.partID && $0.mutationID == archivedPartSuccessor.mutationID }),
              archivedPartSuccessor.workspaceID == predecessor.workspaceID,
              archivedPartSuccessor.partID == predecessor.partID,
              archivedPartSuccessor.displayName == predecessor.displayName,
              archivedPartSuccessor.canonicalUnit == predecessor.canonicalUnit,
              archivedPartSuccessor.productIdentities == predecessor.productIdentities,
              archivedPartSuccessor.preferredMinimum == predecessor.preferredMinimum,
              archivedPartSuccessor.revision == next else { throw PartsStockFailureV1.invalidTransition }
        self.dispositions = dispositions.sorted { $0.locationID.uuidString < $1.locationID.uuidString }; predecessorPart = predecessor; self.archivedPartSuccessor = archivedPartSuccessor
    }
    func validate() throws {
        try dispositions.forEach { try $0.validate() }; try predecessorPart.validate(); try archivedPartSuccessor.validate()
        let (next, overflow) = predecessorPart.revision.addingReportingOverflow(1)
        guard !overflow, !dispositions.isEmpty, Set(dispositions.map(\.locationID)).count == dispositions.count,
              !predecessorPart.archived,
              archivedPartSuccessor.archived,
              archivedPartSuccessor.workspaceID == predecessorPart.workspaceID, archivedPartSuccessor.partID == predecessorPart.partID,
              archivedPartSuccessor.displayName == predecessorPart.displayName, archivedPartSuccessor.canonicalUnit == predecessorPart.canonicalUnit,
              archivedPartSuccessor.productIdentities == predecessorPart.productIdentities, archivedPartSuccessor.preferredMinimum == predecessorPart.preferredMinimum,
              archivedPartSuccessor.revision == next,
              dispositions.allSatisfy({ $0.workspaceID == predecessorPart.workspaceID && $0.partID == predecessorPart.partID && $0.mutationID == archivedPartSuccessor.mutationID }) else { throw PartsStockFailureV1.invalidTransition }
    }
}

struct StockPartRetirementReceiptV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let predecessorPart: LocalPartDefinitionV1; let archivedPartSuccessor: LocalPartDefinitionV1; let verifiedBalances: [StockBalanceProjectionV1]
    init(archivedPartSuccessor: LocalPartDefinitionV1, predecessor: LocalPartDefinitionV1, verifiedBalances: [StockBalanceProjectionV1]) throws {
        try predecessor.validate(); try archivedPartSuccessor.validate(); try verifiedBalances.forEach { try $0.validate() }
        let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
        guard !overflow, !verifiedBalances.isEmpty, !predecessor.archived, archivedPartSuccessor.archived, archivedPartSuccessor.workspaceID == predecessor.workspaceID, archivedPartSuccessor.partID == predecessor.partID, archivedPartSuccessor.displayName == predecessor.displayName, archivedPartSuccessor.canonicalUnit == predecessor.canonicalUnit, archivedPartSuccessor.productIdentities == predecessor.productIdentities, archivedPartSuccessor.preferredMinimum == predecessor.preferredMinimum, archivedPartSuccessor.revision == next, Set(verifiedBalances.map(\.locationID)).count == verifiedBalances.count, verifiedBalances.allSatisfy({ value in guard value.workspaceID == predecessor.workspaceID, value.partID == predecessor.partID, case .known(let quantity) = value.balance else { return false }; return quantity.mantissa == 0 }) else { throw PartsStockFailureV1.invalidTransition }
        predecessorPart = predecessor; self.archivedPartSuccessor = archivedPartSuccessor; self.verifiedBalances = verifiedBalances.sorted { $0.locationID.uuidString < $1.locationID.uuidString }
    }
    func validate() throws {
        try predecessorPart.validate(); try archivedPartSuccessor.validate(); try verifiedBalances.forEach { try $0.validate() }
        let (next, overflow) = predecessorPart.revision.addingReportingOverflow(1)
        guard !overflow, !predecessorPart.archived, archivedPartSuccessor.archived, archivedPartSuccessor.workspaceID == predecessorPart.workspaceID, archivedPartSuccessor.partID == predecessorPart.partID, archivedPartSuccessor.displayName == predecessorPart.displayName, archivedPartSuccessor.canonicalUnit == predecessorPart.canonicalUnit, archivedPartSuccessor.productIdentities == predecessorPart.productIdentities, archivedPartSuccessor.preferredMinimum == predecessorPart.preferredMinimum, archivedPartSuccessor.revision == next, !verifiedBalances.isEmpty, Set(verifiedBalances.map(\.locationID)).count == verifiedBalances.count, verifiedBalances.allSatisfy({ value in guard value.workspaceID == predecessorPart.workspaceID, value.partID == predecessorPart.partID, case .known(let quantity) = value.balance else { return false }; return quantity.mantissa == 0 }) else { throw PartsStockFailureV1.invalidTransition }
    }
}

enum PartsStockMutationV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    case upsertPart(LocalPartDefinitionV1)
    case upsertLocation(StockStorageLocationV1, mutationID: MutationIDV1)
    case appendMovement(StockMovementEventV1)
    case transfer(StockTransferReceiptV1)
    case use(StockUseOnWorkReceiptV1)
    case reverseUse(StockUseReversalReceiptV1)
    case returnAgainstUse(StockReturnAgainstUseReceiptV1)
    case retirePart(StockPartRetirementReceiptV1)
    case abandon(StockAbandonmentReceiptV1)
    var workspaceID: WorkspaceID { switch self { case .upsertPart(let v): return v.workspaceID; case .upsertLocation(let v, _): return v.workspaceID; case .appendMovement(let v): return v.workspaceID; case .transfer(let v): return v.workspaceID; case .use(let v): return v.workspaceID; case .reverseUse(let v): return v.workspaceID; case .returnAgainstUse(let v): return v.workspaceID; case .retirePart(let v): return v.archivedPartSuccessor.workspaceID; case .abandon(let v): return v.archivedPartSuccessor.workspaceID } }
    var mutationID: MutationIDV1 { switch self { case .upsertPart(let v): return v.mutationID; case .upsertLocation(_, let id): return id; case .appendMovement(let v): return v.mutationID; case .transfer(let v): return v.mutationID; case .use(let v): return v.mutationID; case .reverseUse(let v): return v.mutationID; case .returnAgainstUse(let v): return v.mutationID; case .retirePart(let v): return v.archivedPartSuccessor.mutationID; case .abandon(let v): return v.archivedPartSuccessor.mutationID } }
    func validate() throws { switch self { case .upsertPart(let v): try v.validate(); case .upsertLocation(let v, _): try v.validate(); case .appendMovement(let v): try v.validate(); case .transfer(let v): try v.validate(); case .use(let v): try v.validate(); case .reverseUse(let v): try v.validate(); case .returnAgainstUse(let v): try v.validate(); case .retirePart(let v): try v.validate(); case .abandon(let v): try v.validate() } }
}

struct PartsStockMutationReceiptV1: Codable, Equatable, Hashable, Sendable, PartsStockCanonicalValidatingV1 {
    let workspaceID: WorkspaceID; let mutationID: MutationIDV1; let mutationSHA256: String; let committedAt: Date
    init(workspaceID: WorkspaceID, mutationID: MutationIDV1, mutationSHA256: String, committedAt: Date) throws {
        self.workspaceID = workspaceID; self.mutationID = mutationID; self.mutationSHA256 = mutationSHA256; self.committedAt = committedAt; try validate()
    }
    func validate() throws { guard PartsStockCanonicalCodecV1.isDigest(mutationSHA256), PartsStockValidationV1.finiteMillisecond(committedAt) else { throw PartsStockFailureV1.invalidValue } }
}

struct PartsStockReportV1: Codable, Equatable, Sendable {
    /// Reviewed catalog/material truth only. Balances and storage labels are deliberately absent.
    let workspaceID: WorkspaceID; let parts: [LocalPartReferenceSnapshotV1]
}

enum PartsStockSnapshotTopologyV1 {
    private struct BalanceKey: Hashable { let partID: UUID; let locationID: UUID }
    private struct ReplayedTip {
        let balance: StockBalanceV1; let locationRevision: UInt64; let lastMovementID: UUID?
    }

    static func validate(parts: [LocalPartDefinitionV1], locations: [StockStorageLocationV1], movements: [StockMovementEventV1], uses: [StockUseOnWorkReceiptV1], reversals: [StockUseReversalReceiptV1], returns: [StockReturnAgainstUseReceiptV1], abandonments: [AbandonUnverifiedStockDispositionV1]) throws {
        guard Set(parts.map(\.partID)).count == parts.count, Set(locations.map(\.locationID)).count == locations.count, Set(movements.map(\.movementID)).count == movements.count, Set(uses.map(\.receiptID)).count == uses.count, Set(reversals.map(\.receiptID)).count == reversals.count, Set(returns.map(\.receiptID)).count == returns.count else { throw PartsStockFailureV1.invalidValue }
        let catalog = Dictionary(uniqueKeysWithValues: parts.map { ($0.partID, $0) })
        let locationIDs = Set(locations.map(\.locationID)); var historical: [String: LocalPartReferenceSnapshotV1] = [:]
        for movement in movements {
            guard let current = catalog[movement.part.partID], locationIDs.contains(movement.locationID), movement.unit == current.canonicalUnit, movement.part.partRevision <= current.revision else { throw PartsStockFailureV1.invalidValue }
            if movement.part.partRevision == current.revision { guard movement.part == (try current.frozenReference()) else { throw PartsStockFailureV1.invalidDigest } }
            let key = "\(movement.part.partID.uuidString)|\(movement.part.partRevision)"
            if let prior = historical[key] { guard prior == movement.part else { throw PartsStockFailureV1.invalidDigest } } else { historical[key] = movement.part }
        }
        let replayed = try replay(movements: movements)
        let movementByID = Dictionary(uniqueKeysWithValues: movements.map { ($0.movementID, $0) })
        for movement in movements where movement.kind == .transferOut || movement.kind == .transferIn {
            guard let relatedID = movement.relatedMovementID, let peer = movementByID[relatedID], peer.relatedMovementID == movement.movementID, (movement.kind == .transferOut ? peer.kind == .transferIn : peer.kind == .transferOut), peer.part == movement.part, peer.unit == movement.unit, peer.quantity == movement.quantity, peer.mutationID == movement.mutationID, peer.locationID != movement.locationID else { throw PartsStockFailureV1.invalidValue }
        }
        let usesByMovement = Dictionary(grouping: uses, by: { $0.movement.movementID })
        let reversalsByMovement = Dictionary(grouping: reversals, by: { $0.reversalMovement.movementID })
        let returnsByMovement = Dictionary(grouping: returns, by: { $0.returnMovement.movementID })
        guard movements.allSatisfy({ movement in
            switch movement.kind {
            case .useOnWork: return usesByMovement[movement.movementID]?.count == 1 && usesByMovement[movement.movementID]?.first?.movement == movement
            case .reverseUse: return reversalsByMovement[movement.movementID]?.count == 1 && reversalsByMovement[movement.movementID]?.first?.reversalMovement == movement
            case .returnAgainstUse: return returnsByMovement[movement.movementID]?.count == 1 && returnsByMovement[movement.movementID]?.first?.returnMovement == movement
            default: return usesByMovement[movement.movementID] == nil && reversalsByMovement[movement.movementID] == nil && returnsByMovement[movement.movementID] == nil
            }
        }), uses.allSatisfy({ movementByID[$0.movement.movementID] == $0.movement }), reversals.allSatisfy({ movementByID[$0.reversalMovement.movementID] == $0.reversalMovement }), returns.allSatisfy({ movementByID[$0.returnMovement.movementID] == $0.returnMovement }), uses.count == usesByMovement.count, reversals.count == reversalsByMovement.count, returns.count == returnsByMovement.count else { throw PartsStockFailureV1.invalidValue }
        let useByID = Dictionary(uniqueKeysWithValues: uses.map { ($0.receiptID, $0) })
        guard reversals.allSatisfy({ useByID[$0.sourceUse.receiptID] == $0.sourceUse }), returns.allSatisfy({ useByID[$0.sourceUseReceiptID] == $0.sourceUse }) else { throw PartsStockFailureV1.invalidValue }
        let reversalsByUse = Dictionary(grouping: reversals, by: { $0.sourceUse.receiptID })
        let returnsByUse = Dictionary(grouping: returns, by: { $0.sourceUseReceiptID })
        for use in uses {
            let chain = (returnsByUse[use.receiptID] ?? []).sorted { $0.expectedReturnedMantissa < $1.expectedReturnedMantissa }
            guard (reversalsByUse[use.receiptID]?.count ?? 0) <= 1, chain.isEmpty || reversalsByUse[use.receiptID] == nil else { throw PartsStockFailureV1.invalidValue }
            var prior: StockReturnAgainstUseReceiptV1?
            for value in chain {
                try value.validate()
                if let prior { guard value.predecessorFrontier == (try prior.frontierSnapshot()), value.expectedReturnedMantissa == prior.resultingReturnedMantissa else { throw PartsStockFailureV1.invalidValue } }
                else { guard value.predecessorFrontier == nil, value.expectedReturnedMantissa == 0 else { throw PartsStockFailureV1.invalidValue } }
                prior = value
            }
        }
        guard abandonments.allSatisfy({ catalog[$0.partID]?.archived == true && locationIDs.contains($0.locationID) }),
              Set(abandonments.map { "\($0.partID.uuidString)|\($0.locationID.uuidString)" }).count == abandonments.count else { throw PartsStockFailureV1.invalidValue }
        let archivedParts = parts.filter(\.archived)
        let (coverageCount, coverageOverflow) = archivedParts.count.multipliedReportingOverflow(by: locations.count)
        guard !coverageOverflow, coverageCount <= PartsStockLimitsV1.maximumSnapshotRows,
              archivedParts.isEmpty || !locations.isEmpty else { throw PartsStockFailureV1.invalidValue }
        let abandonmentsByPart = Dictionary(grouping: abandonments, by: \.partID)
        for part in archivedParts {
            let dispositions = abandonmentsByPart[part.partID] ?? []
            var unknownLocationIDs = Set<UUID>()
            var allKnownZero = true
            for location in locations {
                let tip = replayed[BalanceKey(partID: part.partID, locationID: location.locationID)]
                    ?? ReplayedTip(balance: .unknown, locationRevision: 0, lastMovementID: nil)
                switch tip.balance {
                case .unknown:
                    unknownLocationIDs.insert(location.locationID); allKnownZero = false
                case .known(let quantity):
                    guard quantity.mantissa == 0 else { throw PartsStockFailureV1.invalidTransition }
                }
            }
            if dispositions.isEmpty {
                guard allKnownZero else { throw PartsStockFailureV1.invalidTransition }
            } else {
                guard Set(dispositions.map(\.locationID)) == unknownLocationIDs else { throw PartsStockFailureV1.invalidTransition }
                for disposition in dispositions {
                    let tip = replayed[BalanceKey(partID: part.partID, locationID: disposition.locationID)]
                        ?? ReplayedTip(balance: .unknown, locationRevision: 0, lastMovementID: nil)
                    guard case .unknown = tip.balance,
                          disposition.lastLocationRevision == tip.locationRevision,
                          disposition.lastMovementID == tip.lastMovementID else { throw PartsStockFailureV1.invalidTransition }
                }
            }
        }
    }

    private static func replay(movements: [StockMovementEventV1]) throws -> [BalanceKey: ReplayedTip] {
        let grouped = Dictionary(grouping: movements) { BalanceKey(partID: $0.part.partID, locationID: $0.locationID) }
        var result: [BalanceKey: ReplayedTip] = [:]
        for (key, unordered) in grouped {
            let stream = unordered.sorted { ($0.locationRevision, $0.movementID.uuidString) < ($1.locationRevision, $1.movementID.uuidString) }
            var expectedRevision: UInt64 = 0
            var expectedBalance: StockBalanceV1 = .unknown
            var lastMovementID: UUID?
            for event in stream {
                let (nextRevision, overflow) = expectedRevision.addingReportingOverflow(1)
                guard !overflow, event.expectedLocationRevision == expectedRevision,
                      event.locationRevision == nextRevision,
                      event.preBalance == expectedBalance else { throw PartsStockFailureV1.staleRevision }
                if expectedRevision == 0 {
                    guard event.kind == .openingCount || event.kind == .physicalCount,
                          event.preBalance == .unknown else { throw PartsStockFailureV1.invalidTransition }
                } else {
                    guard event.kind != .openingCount else { throw PartsStockFailureV1.invalidTransition }
                }
                expectedRevision = nextRevision
                expectedBalance = .known(event.postBalance)
                lastMovementID = event.movementID
            }
            result[key] = ReplayedTip(balance: expectedBalance, locationRevision: expectedRevision, lastMovementID: lastMovementID)
        }
        return result
    }
}
