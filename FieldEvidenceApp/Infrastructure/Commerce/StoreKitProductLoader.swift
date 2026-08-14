import Foundation
import StoreKit

enum StoreKitProductLoaderError: Error, Equatable, Sendable {
    case unavailable
    case invalidProduct
}

struct StoreKitProductContractV1: Equatable, Sendable {
    enum ProductKind: Equatable, Sendable {
        case autoRenewableSubscription
        case other
    }

    enum PeriodUnit: Equatable, Sendable {
        case day
        case week
        case month
        case year
        case other
    }

    enum IntroductoryPaymentMode: Equatable, Sendable {
        case freeTrial
        case other
    }

    let productID: String
    let kind: ProductKind
    let periodValue: Int
    let periodUnit: PeriodUnit
    let isFamilyShareable: Bool
    let introductoryPeriodValue: Int?
    let introductoryPeriodUnit: PeriodUnit?
    let introductoryPaymentMode: IntroductoryPaymentMode?
}

/// Loads only the frozen monthly product and validates structural StoreKit
/// facts. Localized display name, duration text, price, and eligibility remain
/// StoreKit-owned values and are never reconstructed here.
struct StoreKitProductLoader: Sendable {
    typealias ProductsProvider = @Sendable ([String]) async throws -> [Product]

    private let productsProvider: ProductsProvider

    init(
        productsProvider: @escaping ProductsProvider = { identifiers in
            try await Product.products(for: identifiers)
        }
    ) {
        self.productsProvider = productsProvider
    }

    func loadMonthlyProduct() async throws -> Product {
        let products = try await productsProvider([
            EntitlementReducerV1.productID,
        ])
        guard products.count == 1,
              let product = products.first else {
            throw StoreKitProductLoaderError.unavailable
        }
        try Self.validate(Self.contract(product))
        return product
    }

    static func validate(_ contract: StoreKitProductContractV1) throws {
        guard contract.productID == EntitlementReducerV1.productID,
              contract.kind == .autoRenewableSubscription,
              contract.periodValue == 1,
              contract.periodUnit == .month,
              contract.isFamilyShareable == false,
              contract.introductoryPeriodValue == 2,
              contract.introductoryPeriodUnit == .week,
              contract.introductoryPaymentMode == .freeTrial else {
            throw StoreKitProductLoaderError.invalidProduct
        }
    }
}

private extension StoreKitProductLoader {
    static func contract(_ product: Product) -> StoreKitProductContractV1 {
        let subscription = product.subscription
        let introductory = subscription?.introductoryOffer
        return StoreKitProductContractV1(
            productID: product.id,
            kind: product.type == .autoRenewable
                ? .autoRenewableSubscription
                : .other,
            periodValue: subscription?.subscriptionPeriod.value ?? 0,
            periodUnit: periodUnit(subscription?.subscriptionPeriod.unit),
            isFamilyShareable: product.isFamilyShareable,
            introductoryPeriodValue: introductory?.period.value,
            introductoryPeriodUnit: introductory.map {
                periodUnit($0.period.unit)
            },
            introductoryPaymentMode: introductory.map {
                $0.paymentMode == .freeTrial ? .freeTrial : .other
            }
        )
    }

    static func periodUnit(
        _ value: Product.SubscriptionPeriod.Unit?
    ) -> StoreKitProductContractV1.PeriodUnit {
        guard let value else { return .other }
        switch value {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        @unknown default: .other
        }
    }
}
