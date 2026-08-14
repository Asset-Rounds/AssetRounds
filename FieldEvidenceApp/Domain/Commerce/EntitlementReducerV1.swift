import Foundation

enum EntitlementReducerV1 {
    static let productID = "com.palatis3.fieldrecord.sub.solo.monthly.v1"

    static func reduce(
        verifiedFacts: [VerifiedEntitlementFactV1],
        priorCache: EntitlementCacheV1?,
        now: Date
    ) throws -> EntitlementReductionV1 {
        guard validDate(now) else {
            throw EntitlementReductionErrorV1.invalidFact
        }
        guard !verifiedFacts.isEmpty else {
            let state = try offlineState(cache: priorCache, now: now)
            return EntitlementReductionV1(state: state, cache: priorCache)
        }

        for fact in verifiedFacts {
            try validate(fact)
        }
        let selected = try selectLatest(verifiedFacts)
        if let priorCache {
            try validate(priorCache)
            guard selected.verifiedAt >= priorCache.verifiedAt else {
                throw EntitlementReductionErrorV1.invalidFact
            }
        }

        let normalized = normalize(selected, now: now)
        let cache = EntitlementCacheV1(
            productID: productID,
            state: normalized.cacheState,
            expirationAt: selected.expirationAt,
            graceExpirationAt: normalized.cacheState == .grace
                ? selected.graceExpirationAt
                : nil,
            revocationAt: (
                normalized.cacheState == .refunded
                    || normalized.cacheState == .revoked
            )
                ? selected.revocationAt
                : nil,
            verifiedAt: selected.verifiedAt,
            hasEverVerifiedPaid: true
        )
        try validate(cache)
        return EntitlementReductionV1(state: normalized.access, cache: cache)
    }

    static func offlineState(
        cache: EntitlementCacheV1?,
        now: Date
    ) throws -> EntitlementAccessStateV1 {
        guard validDate(now) else {
            throw EntitlementReductionErrorV1.invalidCache
        }
        guard let cache else { return .neverPaid }
        try validate(cache)

        switch cache.state {
        case .active:
            guard let expirationAt = cache.expirationAt else {
                throw EntitlementReductionErrorV1.invalidCache
            }
            return now < expirationAt
                ? .entitled(.active, until: expirationAt)
                : .formerPaidInactive(reason: .expired)
        case .grace:
            guard let graceExpirationAt = cache.graceExpirationAt else {
                throw EntitlementReductionErrorV1.invalidCache
            }
            return now < graceExpirationAt
                ? .entitled(.grace, until: graceExpirationAt)
                : .formerPaidInactive(reason: .expired)
        case .neverPaid:
            return .neverPaid
        case .billingRetry:
            return .formerPaidInactive(reason: .billingRetry)
        case .expired:
            return .formerPaidInactive(reason: .expired)
        case .refunded:
            return .formerPaidInactive(reason: .refunded)
        case .revoked:
            return .formerPaidInactive(reason: .revoked)
        }
    }

    static func loadingState(
        cache: EntitlementCacheV1?,
        now: Date
    ) throws -> EntitlementAccessStateV1 {
        guard let cache else { return .neverPaid }
        let offline = try offlineState(cache: cache, now: now)
        switch offline {
        case .entitled, .neverPaid:
            return offline
        case .formerPaidInactive, .loading:
            return .loading
        }
    }
}

private extension EntitlementReducerV1 {
    struct Normalized {
        let access: EntitlementAccessStateV1
        let cacheState: CachedEntitlementStateV1
    }

    static func normalize(
        _ fact: VerifiedEntitlementFactV1,
        now: Date
    ) -> Normalized {
        if fact.state == .refunded {
            return Normalized(
                access: .formerPaidInactive(reason: .refunded),
                cacheState: .refunded
            )
        }
        if fact.state == .revoked {
            return Normalized(
                access: .formerPaidInactive(reason: .revoked),
                cacheState: .revoked
            )
        }
        if fact.state == .grace,
           let until = fact.graceExpirationAt,
           now < until {
            return Normalized(
                access: .entitled(.grace, until: until),
                cacheState: .grace
            )
        }
        if fact.state == .active,
           let until = fact.expirationAt,
           now < until {
            return Normalized(
                access: .entitled(.active, until: until),
                cacheState: .active
            )
        }
        if fact.state == .billingRetry {
            return Normalized(
                access: .formerPaidInactive(reason: .billingRetry),
                cacheState: .billingRetry
            )
        }
        return Normalized(
            access: .formerPaidInactive(reason: .expired),
            cacheState: .expired
        )
    }

    static func selectLatest(
        _ facts: [VerifiedEntitlementFactV1]
    ) throws -> VerifiedEntitlementFactV1 {
        let ordered = facts.sorted {
            if $0.purchaseAt != $1.purchaseAt {
                return $0.purchaseAt > $1.purchaseAt
            }
            return expirationRank($0.expirationAt) > expirationRank($1.expirationAt)
        }
        guard let selected = ordered.first else {
            throw EntitlementReductionErrorV1.invalidFact
        }
        let tied = ordered.filter {
            $0.purchaseAt == selected.purchaseAt
                && $0.expirationAt == selected.expirationAt
        }
        guard tied.allSatisfy({ $0 == selected }) else {
            throw EntitlementReductionErrorV1.unresolvedTie
        }
        return selected
    }

    static func validate(_ fact: VerifiedEntitlementFactV1) throws {
        guard fact.productID == productID else {
            throw EntitlementReductionErrorV1.wrongProduct
        }
        guard validDate(fact.purchaseAt),
              validDate(fact.verifiedAt),
              fact.verifiedAt >= fact.purchaseAt,
              validOptionalDate(fact.expirationAt),
              validOptionalDate(fact.graceExpirationAt),
              validOptionalDate(fact.revocationAt),
              fact.expirationAt.map({ $0 > fact.purchaseAt }) ?? true,
              fact.graceExpirationAt.map({ grace in
                  fact.expirationAt.map { grace >= $0 } ?? false
              }) ?? true else {
            throw EntitlementReductionErrorV1.invalidFact
        }

        switch fact.state {
        case .active:
            guard let expirationAt = fact.expirationAt,
                  expirationAt > fact.verifiedAt,
                  fact.graceExpirationAt == nil,
                  fact.revocationAt == nil else {
                throw EntitlementReductionErrorV1.invalidFact
            }
        case .grace:
            guard fact.expirationAt != nil,
                  let graceExpirationAt = fact.graceExpirationAt,
                  graceExpirationAt > fact.verifiedAt,
                  fact.revocationAt == nil else {
                throw EntitlementReductionErrorV1.invalidFact
            }
        case .billingRetry, .expired:
            guard fact.expirationAt != nil,
                  fact.graceExpirationAt == nil,
                  fact.revocationAt == nil else {
                throw EntitlementReductionErrorV1.invalidFact
            }
        case .refunded, .revoked:
            guard let revocationAt = fact.revocationAt,
                  revocationAt >= fact.purchaseAt,
                  revocationAt <= fact.verifiedAt,
                  fact.graceExpirationAt == nil else {
                throw EntitlementReductionErrorV1.invalidFact
            }
        }
    }

    static func validate(_ cache: EntitlementCacheV1) throws {
        guard cache.schemaVersion == EntitlementCacheV1.schemaVersion,
              cache.productID == productID,
              validDate(cache.verifiedAt),
              validOptionalDate(cache.expirationAt),
              validOptionalDate(cache.graceExpirationAt),
              validOptionalDate(cache.revocationAt) else {
            throw EntitlementReductionErrorV1.invalidCache
        }
        switch cache.state {
        case .active:
            guard cache.hasEverVerifiedPaid,
                  let expirationAt = cache.expirationAt,
                  expirationAt > cache.verifiedAt,
                  cache.graceExpirationAt == nil,
                  cache.revocationAt == nil else {
                throw EntitlementReductionErrorV1.invalidCache
            }
        case .grace:
            guard cache.hasEverVerifiedPaid,
                  let expirationAt = cache.expirationAt,
                  let graceExpirationAt = cache.graceExpirationAt,
                  graceExpirationAt >= expirationAt,
                  graceExpirationAt > cache.verifiedAt,
                  cache.revocationAt == nil else {
                throw EntitlementReductionErrorV1.invalidCache
            }
        case .neverPaid:
            guard !cache.hasEverVerifiedPaid,
                  cache.expirationAt == nil,
                  cache.graceExpirationAt == nil,
                  cache.revocationAt == nil else {
                throw EntitlementReductionErrorV1.invalidCache
            }
        case .billingRetry, .expired:
            guard cache.hasEverVerifiedPaid,
                  cache.expirationAt != nil,
                  cache.graceExpirationAt == nil,
                  cache.revocationAt == nil else {
                throw EntitlementReductionErrorV1.invalidCache
            }
        case .refunded, .revoked:
            guard cache.hasEverVerifiedPaid,
                  cache.graceExpirationAt == nil,
                  cache.revocationAt != nil,
                  cache.revocationAt! <= cache.verifiedAt else {
                throw EntitlementReductionErrorV1.invalidCache
            }
        }
    }

    static func expirationRank(_ value: Date?) -> TimeInterval {
        value?.timeIntervalSinceReferenceDate ?? -Double.greatestFiniteMagnitude
    }

    static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }

    static func validOptionalDate(_ value: Date?) -> Bool {
        value.map(validDate) ?? true
    }
}
