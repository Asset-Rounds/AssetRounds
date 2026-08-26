import Foundation

struct SystemApplicationClock: ApplicationClock {
    func now() -> Date {
        Date()
    }
}

struct SystemApplicationIDSource: ApplicationIDSource {
    func makeID() -> UUID {
        UUID()
    }
}

struct SystemApplicationFileAuthorityV1: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        let normalized = component
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !normalized.isEmpty,
              normalized.unicodeScalars.allSatisfy(allowed.contains),
              !normalized.contains(".."),
              !normalized.hasPrefix(".") else {
            throw ApplicationFileAuthorityErrorV1.invalidComponent
        }
        return "mutation-\(mutationID.rawValue.uuidString.lowercased())-\(normalized)"
    }
}
