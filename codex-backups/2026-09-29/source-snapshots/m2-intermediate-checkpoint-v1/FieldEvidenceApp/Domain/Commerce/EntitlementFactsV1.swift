import Foundation

enum VerifiedSubscriptionStateV1: String, Codable, CaseIterable, Sendable {
    case active
    case grace
    case billingRetry = "billing_retry"
    case expired
    case refunded
    case revoked
}

/// One already-verified, internally consistent StoreKit transaction/status/
/// renewal tuple. StoreKit verification belongs to the infrastructure adapter;
/// this value deliberately contains no receipt, JWS, transaction ID, or buyer
/// identity.
struct VerifiedEntitlementFactV1: Equatable, Sendable {
    let productID: String
    let purchaseAt: Date
    let expirationAt: Date?
    let graceExpirationAt: Date?
    let revocationAt: Date?
    let verifiedAt: Date
    let state: VerifiedSubscriptionStateV1
    let isIntroductoryOffer: Bool
    let willAutoRenew: Bool

    init(
        productID: String,
        purchaseAt: Date,
        expirationAt: Date?,
        graceExpirationAt: Date? = nil,
        revocationAt: Date? = nil,
        verifiedAt: Date,
        state: VerifiedSubscriptionStateV1,
        isIntroductoryOffer: Bool = false,
        willAutoRenew: Bool = true
    ) {
        self.productID = productID
        self.purchaseAt = purchaseAt
        self.expirationAt = expirationAt
        self.graceExpirationAt = graceExpirationAt
        self.revocationAt = revocationAt
        self.verifiedAt = verifiedAt
        self.state = state
        self.isIntroductoryOffer = isIntroductoryOffer
        self.willAutoRenew = willAutoRenew
    }
}

enum EntitlementInactiveReasonV1: String, Codable, CaseIterable, Sendable {
    case billingRetry = "billing_retry"
    case expired
    case refunded
    case revoked
}

enum EntitlementKindV1: String, Codable, CaseIterable, Sendable {
    case active
    case grace
}

enum EntitlementAccessStateV1: Equatable, Sendable {
    case loading
    case entitled(EntitlementKindV1, until: Date)
    case neverPaid
    case formerPaidInactive(reason: EntitlementInactiveReasonV1)
}

/// Closed on-disk state vocabulary. Dates remain separate fields so the
/// canonical entitlement file can retain its exact eight-key shape.
enum CachedEntitlementStateV1: String, Codable, CaseIterable, Sendable {
    case active
    case grace
    case neverPaid = "never_paid"
    case billingRetry = "billing_retry"
    case expired
    case refunded
    case revoked
}

struct EntitlementCacheV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let productID: String
    let state: CachedEntitlementStateV1
    let expirationAt: Date?
    let graceExpirationAt: Date?
    let revocationAt: Date?
    let verifiedAt: Date
    let hasEverVerifiedPaid: Bool

    init(
        schemaVersion: Int = Self.schemaVersion,
        productID: String,
        state: CachedEntitlementStateV1,
        expirationAt: Date?,
        graceExpirationAt: Date?,
        revocationAt: Date?,
        verifiedAt: Date,
        hasEverVerifiedPaid: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.productID = productID
        self.state = state
        self.expirationAt = expirationAt
        self.graceExpirationAt = graceExpirationAt
        self.revocationAt = revocationAt
        self.verifiedAt = verifiedAt
        self.hasEverVerifiedPaid = hasEverVerifiedPaid
    }
}

struct EntitlementReductionV1: Equatable, Sendable {
    let state: EntitlementAccessStateV1
    /// Nonnil only when verified authority produced a durable replacement, or
    /// when an existing cache is being interpreted without mutation.
    let cache: EntitlementCacheV1?
}

enum EntitlementReductionErrorV1: Error, Equatable, Sendable {
    case invalidFact
    case invalidCache
    case wrongProduct
    case unresolvedTie
}
