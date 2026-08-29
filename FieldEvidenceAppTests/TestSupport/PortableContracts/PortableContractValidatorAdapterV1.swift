import Foundation
import CryptoKit
import CoreFoundation

enum PortableContractExpectedClassV1: String, Decodable, Hashable, Sendable {
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
}

struct PortableContractCaseV1: Decodable, Equatable, Sendable {
    let id: String
    let input: String
    let expectedClass: PortableContractExpectedClassV1
    let instancePath: String
    let schemaPath: String
    let goldenUTF8Hex: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, input, expectedClass, instancePath, schemaPath, goldenUTF8Hex
    }

    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        input = try values.decode(String.self, forKey: .input)
        expectedClass = try values.decode(PortableContractExpectedClassV1.self, forKey: .expectedClass)
        instancePath = try values.decode(String.self, forKey: .instancePath)
        schemaPath = try values.decode(String.self, forKey: .schemaPath)
        goldenUTF8Hex = try values.decode(String.self, forKey: .goldenUTF8Hex)
        try validate()
    }

    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 256,
              !input.isEmpty, input.utf8.count <= 1_048_576,
              goldenUTF8Hex == Data(input.utf8).hexStringV1,
              goldenUTF8Hex.allSatisfy({ $0.isNumber || ("a"..."f").contains(String($0)) }),
              Self.isJSONPointer(instancePath), Self.isJSONPointer(schemaPath) else {
            throw PortableContractValidationFailureV1.invalidCorpus
        }
        switch expectedClass {
        case .accepted:
            guard instancePath.isEmpty, schemaPath.isEmpty else {
                throw PortableContractValidationFailureV1.invalidCorpus
            }
        case .rejected:
            guard !instancePath.isEmpty, !schemaPath.isEmpty else {
                throw PortableContractValidationFailureV1.invalidCorpus
            }
        }
        _ = try JSONSerialization.jsonObject(
            with: Data(input.utf8),
            options: [.fragmentsAllowed]
        )
    }

    private static func isJSONPointer(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        guard value.first == "/" else { return false }
        var cursor = value.startIndex
        while let tilde = value[cursor...].firstIndex(of: "~") {
            let escape = value.index(after: tilde)
            guard escape < value.endIndex,
                  value[escape] == "0" || value[escape] == "1" else {
                return false
            }
            cursor = value.index(after: escape)
        }
        return true
    }
}

struct PortableContractObservedResultV1: Equatable, Sendable {
    let classification: PortableContractExpectedClassV1
    let instancePath: String
    let schemaPath: String
}

struct PortableContractValidationReceiptV1: Equatable, Sendable {
    let caseID: String
    let inputSHA256: String
    let toolDistributionSHA256: String
    let classification: PortableContractExpectedClassV1
    let instancePath: String
    let schemaPath: String
}

enum PortableContractValidationFailureV1: Error, Equatable {
    case invalidCorpus
    case invalidToolLock
    case resultMismatch
}

/// Normalizes results from the independently pinned non-Swift validator.
/// It deliberately does not execute or download a tool from the XCTest host.
struct PortableContractValidatorAdapterV1: Sendable {
    let toolLock: PortableContractToolLockV1

    init(toolLock: PortableContractToolLockV1) throws {
        try toolLock.validate()
        self.toolLock = toolLock
    }

    func validate(
        _ contractCase: PortableContractCaseV1,
        observed: PortableContractObservedResultV1
    ) throws -> PortableContractValidationReceiptV1 {
        try contractCase.validate()
        guard observed.classification == contractCase.expectedClass,
              observed.instancePath == contractCase.instancePath,
              observed.schemaPath == contractCase.schemaPath else {
            throw PortableContractValidationFailureV1.resultMismatch
        }
        return PortableContractValidationReceiptV1(
            caseID: contractCase.id,
            inputSHA256: Data(input: contractCase.input).sha256V1,
            toolDistributionSHA256: toolLock.distributionSHA256,
            classification: observed.classification,
            instancePath: observed.instancePath,
            schemaPath: observed.schemaPath
        )
    }

    /// Executes the closed portable-envelope contract independently of the
    /// expectation carried by the corpus row. The expectation is consulted
    /// only after the observed classification and paths have been derived.
    func validate(_ contractCase: PortableContractCaseV1) throws -> PortableContractValidationReceiptV1 {
        try validate(contractCase, observed: try observe(contractCase.input))
    }

    /// Validates the entire immutable C42 slice through the same independently
    /// pinned portable-envelope boundary used by kernel conformance.  Corpus
    /// order is receipt order, so same bytes always produce the same receipts.
    func validateCrossMarketCorpus(
        _ cases: [PortableContractCaseV1]
    ) throws -> [PortableContractValidationReceiptV1] {
        guard !cases.isEmpty,
              cases.count <= 128,
              Set(cases.map(\.id)).count == cases.count,
              Set(cases.map(\.expectedClass)) == [.accepted, .rejected] else {
            throw PortableContractValidationFailureV1.invalidCorpus
        }
        return try cases.map(validate)
    }

    private func observe(_ input: String) throws -> PortableContractObservedResultV1 {
        guard let object = try JSONSerialization.jsonObject(
            with: Data(input.utf8), options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            throw PortableContractValidationFailureV1.invalidCorpus
        }
        let allowedTop = Set(["schema", "schemaVersion", "kind", "payload"])
        if let unknown = Set(object.keys).subtracting(allowedTop).sorted().first {
            return .init(
                classification: .rejected,
                instancePath: "/\(unknown)",
                schemaPath: "/additionalProperties"
            )
        }
        guard object["schema"] as? String == "KernelPortableEnvelopeV1" else {
            return .init(classification: .rejected, instancePath: "/schema", schemaPath: "/properties/schema/const")
        }
        guard let schemaVersion = object["schemaVersion"] as? NSNumber,
              CFGetTypeID(schemaVersion) != CFBooleanGetTypeID(),
              schemaVersion.doubleValue == 1 else {
            return .init(classification: .rejected, instancePath: "/schemaVersion", schemaPath: "/properties/schemaVersion/const")
        }
        guard let kind = object["kind"] as? String, ["CHECK", "MEASUREMENT"].contains(kind) else {
            return .init(classification: .rejected, instancePath: "/kind", schemaPath: "/properties/kind/enum")
        }
        guard let payload = object["payload"] as? [String: Any] else {
            return .init(classification: .rejected, instancePath: "/payload", schemaPath: "/properties/payload/type")
        }
        let permittedPayload = kind == "CHECK"
            ? Set(["id", "status", "label"])
            : Set(["id", "status", "value", "unit"])
        if let unknown = Set(payload.keys).subtracting(permittedPayload).sorted().first {
            return .init(classification: .rejected, instancePath: "/payload/\(unknown)", schemaPath: "/properties/payload/additionalProperties")
        }
        guard let id = payload["id"] as? String,
              !id.isEmpty,
              id.unicodeScalars.count <= 256 else {
            return .init(classification: .rejected, instancePath: "/payload/id", schemaPath: "/properties/payload/properties/id/type")
        }
        let statuses = kind == "CHECK" ? Set(["OPEN", "COMPLETE"]) : Set(["OPEN", "COMPLETE"])
        guard let status = payload["status"] as? String, statuses.contains(status) else {
            return .init(classification: .rejected, instancePath: "/payload/status", schemaPath: "/properties/payload/properties/status/enum")
        }
        if payload.keys.contains("label") {
            guard let label = payload["label"] as? String else {
                return .init(
                    classification: .rejected,
                    instancePath: "/payload/label",
                    schemaPath: "/properties/payload/properties/label/type"
                )
            }
            let containsForbiddenScalar = label.unicodeScalars.contains {
                (0x0000...0x001F).contains($0.value)
                    || (0x007F...0x009F).contains($0.value)
                    || (0x202A...0x202E).contains($0.value)
                    || (0x2066...0x2069).contains($0.value)
            }
            if containsForbiddenScalar {
                return .init(
                    classification: .rejected,
                    instancePath: "/payload/label",
                    schemaPath: "/properties/payload/properties/label/pattern"
                )
            }
        }
        if kind == "MEASUREMENT" {
            guard let value = payload["value"] as? String,
                  value.range(
                    of: #"^-?[0-9]+(?:\.[0-9]+)?$"#,
                    options: .regularExpression
                  ) != nil else {
                return .init(
                    classification: .rejected,
                    instancePath: "/payload/value",
                    schemaPath: "/properties/payload/properties/value/pattern"
                )
            }
            guard payload["unit"] as? String == "mm" else {
                return .init(
                    classification: .rejected,
                    instancePath: "/payload/unit",
                    schemaPath: "/properties/payload/properties/unit/enum"
                )
            }
        }
        return .init(classification: .accepted, instancePath: "", schemaPath: "")
    }
}

enum StrictPortableContractCodingV1 {
    static func requireExactKeys<K: CodingKey & CaseIterable>(
        _ decoder: any Decoder,
        _ keyType: K.Type
    ) throws where K.AllCases: Collection {
        let values = try decoder.container(keyedBy: AnyPortableContractCodingKeyV1.self)
        let observed = Set(values.allKeys.map(\.stringValue))
        let expected = Set(K.allCases.map(\.stringValue))
        guard observed == expected else {
            throw PortableContractValidationFailureV1.invalidCorpus
        }
    }
}

private struct AnyPortableContractCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension Data {
    init(input: String) { self = Data(input.utf8) }

    var hexStringV1: String { map { String(format: "%02x", $0) }.joined() }

    var sha256V1: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
