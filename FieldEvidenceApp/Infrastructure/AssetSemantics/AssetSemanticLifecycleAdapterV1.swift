import Foundation

enum AssetSemanticsScheduleLifecycleBoundaryV1 { static let noSecondScheduleWriter = true }

extension AssetSemanticLifecycleAdapterV1 {
    func validateLocatorLifecycle(_ closure: AssetLocatorLifecycleClosureV1) throws {
        try closure.validate()
    }
}
import SwiftData

/// Immutable, in-memory authority for the package-qualified semantic catalog
/// releases admitted by C39.  Catalog bytes are never synthesized by the
/// persistence adapter: a binding must resolve to one exact release and
/// digest already present in this registry.
struct AssetSemanticCatalogRegistryV1: Equatable, Sendable {
    static let maximumCatalogCount = 512

    let catalogs: [AssetSemanticCatalogReleaseV1]
    private let catalogsByReference:
        [AssetSemanticCatalogReleaseReferenceV1: AssetSemanticCatalogReleaseV1]

    static let empty = Self(
        uncheckedCatalogs: [],
        catalogsByReference: [:]
    )

    init(_ catalogs: [AssetSemanticCatalogReleaseV1]) throws {
        guard catalogs.count <= Self.maximumCatalogCount else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        let ordered = catalogs.sorted { lhs, rhs in
            if lhs.releaseID != rhs.releaseID {
                return lhs.releaseID.uuidString < rhs.releaseID.uuidString
            }
            if lhs.packageRelease != rhs.packageRelease {
                return lhs.packageRelease < rhs.packageRelease
            }
            return lhs.catalogSHA256 < rhs.catalogSHA256
        }
        guard Set(ordered.map(\.releaseID)).count == ordered.count,
              Set(ordered.map(\.reference)).count == ordered.count else {
            throw AssetSemanticContractFailureV1.duplicateValue
        }
        try ordered.forEach { try $0.validate() }

        var lookup: [AssetSemanticCatalogReleaseReferenceV1: AssetSemanticCatalogReleaseV1] = [:]
        for catalog in ordered {
            lookup[catalog.reference] = catalog
        }
        self.init(uncheckedCatalogs: ordered, catalogsByReference: lookup)
    }

    init(catalogs: [AssetSemanticCatalogReleaseV1]) throws {
        try self.init(catalogs)
    }

    init(release: AssetSemanticCatalogReleaseV1) throws {
        try self.init([release])
    }

    var orderedCatalogs: [AssetSemanticCatalogReleaseV1] { catalogs }

    func resolve(
        _ reference: AssetSemanticCatalogReleaseReferenceV1
    ) throws -> AssetSemanticCatalogReleaseV1 {
        try reference.validate()
        guard let catalog = catalogsByReference[reference] else {
            throw AssetSemanticContractFailureV1.incompatibleRelease
        }
        try catalog.validate()
        guard catalog.reference == reference else {
            throw AssetSemanticContractFailureV1.incompatibleRelease
        }
        return catalog
    }

    private init(
        uncheckedCatalogs: [AssetSemanticCatalogReleaseV1],
        catalogsByReference: [AssetSemanticCatalogReleaseReferenceV1: AssetSemanticCatalogReleaseV1]
    ) {
        catalogs = uncheckedCatalogs
        self.catalogsByReference = catalogsByReference
    }
}

/// Canonical, workspace-scoped semantic rows that contribute to an Asset's
/// post-image.  The arrays are immutable history; no current row is rewritten
/// when a kind, identifier, lifecycle event, or work subject changes.
struct AssetSemanticPersistentSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let assetID: UUID
    let kindBindings: [AssetKindBindingEventV1]
    let workflowCapabilityBindings: [AssetWorkflowCapabilityBindingEventV1]
    let productIdentities: [AssetProductIdentityV1]
    let lifecycleEvents: [AssetLifecycleEventV1]
    let successorLinks: [AssetSuccessorLinkV1]
    let workSubjectScopes: [WorkSubjectScopeSnapshotV1]

    init(
        workspaceID: WorkspaceID,
        assetID: UUID,
        kindBindings: [AssetKindBindingEventV1],
        workflowCapabilityBindings: [AssetWorkflowCapabilityBindingEventV1],
        productIdentities: [AssetProductIdentityV1],
        lifecycleEvents: [AssetLifecycleEventV1],
        successorLinks: [AssetSuccessorLinkV1],
        workSubjectScopes: [WorkSubjectScopeSnapshotV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.assetID = assetID
        self.kindBindings = kindBindings.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        self.workflowCapabilityBindings = workflowCapabilityBindings.sorted {
            $0.eventID.uuidString < $1.eventID.uuidString
        }
        self.productIdentities = productIdentities.sorted {
            $0.identityID.uuidString < $1.identityID.uuidString
        }
        self.lifecycleEvents = lifecycleEvents.sorted {
            $0.record.eventID.uuidString < $1.record.eventID.uuidString
        }
        self.successorLinks = successorLinks.sorted {
            $0.linkID.uuidString < $1.linkID.uuidString
        }
        self.workSubjectScopes = workSubjectScopes.sorted {
            $0.snapshotID.uuidString < $1.snapshotID.uuidString
        }
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != Self.zeroUUID,
              assetID != Self.zeroUUID,
              Set(kindBindings.map(\.eventID)).count == kindBindings.count,
              Set(workflowCapabilityBindings.map(\.eventID)).count
                  == workflowCapabilityBindings.count,
              Set(productIdentities.map(\.identityID)).count == productIdentities.count,
              Set(lifecycleEvents.map { $0.record.eventID }).count == lifecycleEvents.count,
              Set(successorLinks.map(\.linkID)).count == successorLinks.count,
              Set(workSubjectScopes.map(\.snapshotID)).count == workSubjectScopes.count else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
        try kindBindings.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID, $0.assetID == assetID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try workflowCapabilityBindings.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID, $0.assetID == assetID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try productIdentities.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID, $0.assetID == assetID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try lifecycleEvents.forEach {
            try $0.validate()
            guard $0.record.workspaceID == workspaceID,
                  $0.record.assetID == assetID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try successorLinks.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID,
                  $0.predecessorAssetID == assetID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try workSubjectScopes.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID,
                  $0.subjects.contains(where: { subject in
                      subject.kind == .asset && subject.subjectID == assetID
                          || subject.ownerAssetID == assetID
                  }) || $0.semanticBindings.contains(where: { $0.assetID == assetID }) else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try AssetSuccessorLinkV1.validateAcyclic(successorLinks)
    }

    static func load(
        workspaceID: WorkspaceID,
        assetID: UUID,
        in modelContext: ModelContext
    ) throws -> Self {
        let workspace = workspaceID.rawValue
        let kinds = try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.assetID == assetID }
        )).map { try $0.value() }
        let capabilities = try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.assetID == assetID }
        )).map { try $0.value() }
        let products = try modelContext.fetch(FetchDescriptor<AssetProductIdentityRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.assetID == assetID }
        )).map { try $0.value() }
        let lifecycles = try modelContext.fetch(FetchDescriptor<AssetLifecycleEventRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.assetID == assetID }
        )).map { try $0.value() }
        let links = try modelContext.fetch(FetchDescriptor<AssetSuccessorLinkRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.predecessorAssetID == assetID }
        )).map { try $0.value() }
        let allScopes = try modelContext.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        )).map { try $0.value() }
        let scopes = allScopes.filter { value in
            value.subjects.contains(where: { subject in
                (subject.kind == .asset && subject.subjectID == assetID)
                    || subject.ownerAssetID == assetID
            }) || value.semanticBindings.contains(where: { $0.assetID == assetID })
        }
        return try Self(
            workspaceID: workspaceID,
            assetID: assetID,
            kindBindings: kinds,
            workflowCapabilityBindings: capabilities,
            productIdentities: products,
            lifecycleEvents: lifecycles,
            successorLinks: links,
            workSubjectScopes: scopes
        )
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// Read/validation and sole-write adapter for the six C39 semantic row
/// families.  It never saves: WorkspaceWriterV1 and MutationJournalStoreV1
/// own the single transaction containing rows, revision, and receipt.
@MainActor
final class AssetSemanticLifecycleAdapterV1: AssetSemanticLifecyclePortV1 {
    let workspaceID: WorkspaceID?
    private let modelContext: ModelContext
    private let catalogRegistry: AssetSemanticCatalogRegistryV1

    init(
        modelContext: ModelContext,
        workspaceID: WorkspaceID? = nil,
        catalogRegistry: AssetSemanticCatalogRegistryV1? = nil
    ) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.catalogRegistry = catalogRegistry ?? .empty
    }

    convenience init(
        modelContext: ModelContext,
        workspaceID: WorkspaceID? = nil,
        semanticCatalogRegistry: AssetSemanticCatalogRegistryV1
    ) {
        self.init(
            modelContext: modelContext,
            workspaceID: workspaceID,
            catalogRegistry: semanticCatalogRegistry
        )
    }

    func validate(_ mutation: AssetSemanticsMutationV1) throws {
        try mutation.validate()
        if let workspaceID {
            guard mutation.workspaceID == workspaceID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try requireAsset(mutation.assetID)
        switch mutation.operation {
        case .appendKindBinding:
            guard let binding = mutation.kindBinding else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            _ = try resolveCatalog(for: binding)
            if let predecessor = mutation.kindBinding?.predecessorEventID {
                let value = try requireKind(predecessor)
                guard value.workspaceID == mutation.workspaceID,
                      value.assetID == mutation.assetID else {
                    throw AssetSemanticContractFailureV1.invalidAtomicReference
                }
            }
        case .appendWorkflowCapabilityBinding:
            guard let binding = mutation.workflowCapabilityBinding else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            let kind = try requireKind(binding.kindBindingEventID)
            let catalog = try resolveCatalog(for: kind)
            guard kind.workspaceID == mutation.workspaceID,
                  kind.assetID == mutation.assetID,
                  kind.revision == binding.kindBindingRevision else {
                throw AssetSemanticContractFailureV1.invalidAtomicReference
            }
            try AssetSemanticPackageCompatibilityRegistryV1.validate(
                kindBinding: kind,
                catalog: catalog,
                workflowBinding: binding
            )
            if let predecessor = binding.predecessorEventID {
                let prior = try requireCapability(predecessor)
                guard prior.workspaceID == mutation.workspaceID,
                      prior.assetID == mutation.assetID else {
                    throw AssetSemanticContractFailureV1.invalidAtomicReference
                }
            }
        case .appendProductIdentity:
            if let predecessor = mutation.productIdentity?.predecessorIdentityID {
                let value = try requireProduct(predecessor)
                guard value.workspaceID == mutation.workspaceID,
                      value.assetID == mutation.assetID else {
                    throw AssetSemanticContractFailureV1.invalidAtomicReference
                }
            }
        case .appendLifecycle:
            if let predecessor = mutation.lifecycleEvent?.record.predecessorEventID {
                let value = try requireLifecycle(predecessor)
                guard value.record.workspaceID == mutation.workspaceID,
                      value.record.assetID == mutation.assetID else {
                    throw AssetSemanticContractFailureV1.invalidAtomicReference
                }
            }
        case .classifyKindAndLifecycle:
            guard let kind = mutation.kindBinding,
                  let lifecycle = mutation.lifecycleEvent else {
                throw AssetSemanticContractFailureV1.invalidAtomicReference
            }
            _ = try resolveCatalog(for: kind)
            try lifecycle.validateAtomicReference(kindBinding: kind)
        case .replaceWithSuccessor:
            guard let link = mutation.successorLink else {
                throw AssetSemanticContractFailureV1.invalidAtomicReference
            }
            try requireAsset(link.successorAssetID)
            if let predecessor = link.predecessorLinkID {
                let value = try requireSuccessor(predecessor)
                guard value.workspaceID == mutation.workspaceID else {
                    throw AssetSemanticContractFailureV1.invalidAtomicReference
                }
            }
            let workspace = mutation.workspaceID.rawValue
            let links = try modelContext.fetch(FetchDescriptor<AssetSuccessorLinkRow>(
                predicate: #Predicate { $0.workspaceID == workspace }
            )).map { try $0.value() }
            try AssetSuccessorLinkV1.validateAcyclic(links + [link])
            guard !links.contains(where: {
                $0.predecessorAssetID == link.predecessorAssetID
            }) else {
                throw AssetSemanticContractFailureV1.duplicateValue
            }
        case .captureWorkSubjectScope:
            guard let scope = mutation.workSubjectScope else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            let siteID = scope.siteID
            let sites = try modelContext.fetch(FetchDescriptor<Site>(
                predicate: #Predicate { $0.id == siteID }
            ))
            guard sites.count == 1 else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            try validateSemanticBindings(in: scope)
            try validateFunctionalRelationshipBindings(in: scope)
        }
    }

    func apply(
        _ mutation: AssetSemanticsMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try validate(mutation)
            try rejectDuplicateIDs(mutation)
            switch mutation.operation {
            case .appendKindBinding:
                guard let value = mutation.kindBinding else { throw AssetSemanticContractFailureV1.invalidValue }
                modelContext.insert(try AssetKindBindingEventRow(value))
            case .appendWorkflowCapabilityBinding:
                guard let value = mutation.workflowCapabilityBinding else { throw AssetSemanticContractFailureV1.invalidValue }
                modelContext.insert(try AssetWorkflowCapabilityBindingEventRow(value))
            case .appendProductIdentity:
                guard let value = mutation.productIdentity else { throw AssetSemanticContractFailureV1.invalidValue }
                modelContext.insert(try AssetProductIdentityRow(value))
            case .appendLifecycle:
                guard let value = mutation.lifecycleEvent else { throw AssetSemanticContractFailureV1.invalidValue }
                modelContext.insert(try AssetLifecycleEventRow(value))
            case .classifyKindAndLifecycle:
                guard let kind = mutation.kindBinding,
                      let lifecycle = mutation.lifecycleEvent else {
                    throw AssetSemanticContractFailureV1.invalidAtomicReference
                }
                // Both rows are inserted only after every pair/reference
                // guard above succeeds, so a classification can never leave
                // an orphan event in the context.
                modelContext.insert(try AssetKindBindingEventRow(kind))
                modelContext.insert(try AssetLifecycleEventRow(lifecycle))
            case .replaceWithSuccessor:
                guard let link = mutation.successorLink,
                      let lifecycle = mutation.lifecycleEvent else {
                    throw AssetSemanticContractFailureV1.invalidAtomicReference
                }
                modelContext.insert(try AssetSuccessorLinkRow(link))
                modelContext.insert(try AssetLifecycleEventRow(lifecycle))
            case .captureWorkSubjectScope:
                guard let value = mutation.workSubjectScope else { throw AssetSemanticContractFailureV1.invalidValue }
                modelContext.insert(try WorkSubjectScopeSnapshotRow(value))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: [try mutation.affectedIdentity],
                temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch let failure as AssetSemanticContractFailureV1 {
            modelContext.rollback()
            switch failure {
            case .duplicateValue:
                throw WorkspaceMutationFailureV1.sequenceCollision
            default:
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
    }

    func snapshot(for assetID: UUID) throws -> AssetSemanticPersistentSnapshotV1 {
        guard let workspaceID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return try Self.snapshot(
            workspaceID: workspaceID,
            assetID: assetID,
            in: modelContext
        )
    }

    func functionalRelationshipProjection(
        boundary: FunctionalRelationshipReadinessBoundaryV1? = nil
    ) throws -> CurrentFunctionalRelationshipProjectionV1 {
        guard let workspaceID else {
            throw AssetSemanticContractFailureV1.crossWorkspaceReference
        }
        return try functionalRelationshipProjection(
            workspaceID: workspaceID,
            boundary: boundary
        )
    }

    private func functionalRelationshipProjection(
        workspaceID: WorkspaceID,
        boundary: FunctionalRelationshipReadinessBoundaryV1? = nil
    ) throws -> CurrentFunctionalRelationshipProjectionV1 {
        let workspace = workspaceID.rawValue
        let descriptors = try modelContext.fetch(
            FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(
                predicate: #Predicate { $0.workspaceID == workspace }
            )
        ).map { try $0.value() }
        let events = try modelContext.fetch(
            FetchDescriptor<AssetFunctionalRelationshipEventRow>(
                predicate: #Predicate { $0.workspaceID == workspace }
            )
        ).map { try $0.value() }
        return try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            events: events,
            descriptors: descriptors,
            boundary: boundary
        )
    }

    func functionalRelationshipPreview(
        change: FunctionalRelationshipEndpointChangeV1,
        relationshipID: UUID,
        currentSiteID: UUID,
        proposedSiteID: UUID? = nil
    ) throws -> FunctionalRelationshipDispositionPreviewV1 {
        let projection = try functionalRelationshipProjection()
        guard let relationship = projection.currentRelationships.first(where: {
            $0.relationshipID == relationshipID
        }) else {
            throw FunctionalRelationshipFailureV1.invalidValue
        }
        let descriptorID = relationship.descriptor.descriptorReleaseID
        let rows = try modelContext.fetch(
            FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(
                predicate: #Predicate { $0.descriptorReleaseID == descriptorID }
            )
        )
        guard rows.count == 1, let descriptor = try rows.first?.value() else {
            throw FunctionalRelationshipFailureV1.unknownDescriptor
        }
        return try FunctionalRelationshipDispositionPreviewEngineV1.preview(
            change: change,
            relationship: relationship,
            descriptor: descriptor,
            currentSiteID: currentSiteID,
            proposedSiteID: proposedSiteID
        )
    }

    func validate(
        _ scope: WorkSubjectScopeSnapshotV1,
        against snapshot: CompletedFunctionalRelationshipSnapshotV1
    ) throws {
        if let workspaceID {
            guard scope.workspaceID == workspaceID,
                  snapshot.workspaceID == workspaceID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
        }
        try scope.validate(); try snapshot.validate()
        guard scope.workspaceID == snapshot.workspaceID else {
            throw AssetSemanticContractFailureV1.crossWorkspaceReference
        }
        if scope.subjects.contains(where: { $0.functionalRelationship != nil }) {
            try scope.validateFunctionalRelationshipSnapshot(snapshot)
        }
    }

    static func snapshot(
        workspaceID: WorkspaceID,
        assetID: UUID,
        in modelContext: ModelContext
    ) throws -> AssetSemanticPersistentSnapshotV1 {
        try AssetSemanticPersistentSnapshotV1.load(
            workspaceID: workspaceID,
            assetID: assetID,
            in: modelContext
        )
    }

    /// SwiftData rollback is owned by WorkspaceWriterAdapterV1.  This hook is
    /// intentionally empty so no second persistence transaction can occur.
    func rollback() {}

    private func rejectDuplicateIDs(_ mutation: AssetSemanticsMutationV1) throws {
        switch mutation.operation {
        case .appendKindBinding, .classifyKindAndLifecycle:
            if let id = mutation.kindBinding?.eventID {
                let rows = try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>(
                    predicate: #Predicate { $0.eventID == id }
                ))
                guard rows.isEmpty else { throw AssetSemanticContractFailureV1.duplicateValue }
            }
        default: break
        }
        switch mutation.operation {
        case .appendWorkflowCapabilityBinding:
            if let id = mutation.workflowCapabilityBinding?.eventID {
                let rows = try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>(
                    predicate: #Predicate { $0.eventID == id }
                ))
                guard rows.isEmpty else { throw AssetSemanticContractFailureV1.duplicateValue }
            }
        default: break
        }
        switch mutation.operation {
        case .appendProductIdentity:
            if let id = mutation.productIdentity?.identityID {
                let rows = try modelContext.fetch(FetchDescriptor<AssetProductIdentityRow>(
                    predicate: #Predicate { $0.identityID == id }
                ))
                guard rows.isEmpty else { throw AssetSemanticContractFailureV1.duplicateValue }
            }
        default: break
        }
        if let id = mutation.lifecycleEvent?.record.eventID {
            let rows = try modelContext.fetch(FetchDescriptor<AssetLifecycleEventRow>(
                predicate: #Predicate { $0.eventID == id }
            ))
            guard rows.isEmpty else { throw AssetSemanticContractFailureV1.duplicateValue }
        }
        if let id = mutation.successorLink?.linkID {
            let rows = try modelContext.fetch(FetchDescriptor<AssetSuccessorLinkRow>(
                predicate: #Predicate { $0.linkID == id }
            ))
            guard rows.isEmpty else { throw AssetSemanticContractFailureV1.duplicateValue }
        }
        if let id = mutation.workSubjectScope?.snapshotID {
            let rows = try modelContext.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>(
                predicate: #Predicate { $0.snapshotID == id }
            ))
            guard rows.isEmpty else { throw AssetSemanticContractFailureV1.duplicateValue }
        }
    }

    private func resolveCatalog(
        for binding: AssetKindBindingEventV1
    ) throws -> AssetSemanticCatalogReleaseV1 {
        let catalog = try catalogRegistry.resolve(binding.catalogRelease)
        try binding.validate(against: catalog)
        return catalog
    }

    private func validateSemanticBindings(
        in scope: WorkSubjectScopeSnapshotV1
    ) throws {
        for semanticBinding in scope.semanticBindings {
            let catalog = try catalogRegistry.resolve(semanticBinding.catalogRelease)
            let definition = try catalog.definition(semanticID: semanticBinding.semanticID)
            let kind = try requireKind(semanticBinding.kindBindingEventID)
            guard kind.workspaceID == scope.workspaceID,
                  kind.assetID == semanticBinding.assetID,
                  kind.revision == semanticBinding.kindBindingRevision,
                  kind.semanticID == semanticBinding.semanticID,
                  kind.catalogRelease == semanticBinding.catalogRelease else {
                throw AssetSemanticContractFailureV1.invalidAtomicReference
            }
            try kind.validate(against: catalog)
            let compatibleReleases = Set(
                [catalog.packageRelease] + definition.compatibleWorkflowPackageReleases
            )
            guard semanticBinding.workflowPackageReleases.allSatisfy({
                compatibleReleases.contains($0)
            }) else {
                throw AssetSemanticContractFailureV1.incompatibleRelease
            }
        }
    }

    private func validateFunctionalRelationshipBindings(
        in scope: WorkSubjectScopeSnapshotV1
    ) throws {
        let references = scope.subjects.compactMap(\.functionalRelationship)
        guard !references.isEmpty else { return }
        if let workspaceID, scope.workspaceID != workspaceID {
            throw AssetSemanticContractFailureV1.crossWorkspaceReference
        }
        let projection = try functionalRelationshipProjection(
            workspaceID: scope.workspaceID
        )
        let descriptorIDs = Set(references.map(\.descriptorReleaseID))
        let workspace = scope.workspaceID.rawValue
        let descriptors = try modelContext.fetch(
            FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(
                predicate: #Predicate { $0.workspaceID == workspace }
            )
        ).map { try $0.value() }.filter {
            descriptorIDs.contains($0.descriptorReleaseID)
        }
        guard Set(descriptors.map(\.descriptorReleaseID)) == descriptorIDs else {
            throw AssetSemanticContractFailureV1.invalidAtomicReference
        }
        let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map {
            ($0.descriptorReleaseID, $0)
        })
        let currentByID = Dictionary(uniqueKeysWithValues:
            projection.currentRelationships.map { ($0.relationshipID, $0) }
        )
        for reference in references {
            guard let event = currentByID[reference.relationshipID],
                  let descriptor = descriptorByID[reference.descriptorReleaseID],
                  try FrozenFunctionalRelationshipReferenceV1(
                    event: event, descriptor: descriptor
                  ) == reference else {
                throw AssetSemanticContractFailureV1.invalidAtomicReference
            }
        }
    }

    private func requireAsset(_ assetID: UUID) throws {
        let rows = try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        ))
        guard rows.count == 1 else { throw AssetSemanticContractFailureV1.invalidValue }
    }

    private func requireKind(_ eventID: UUID) throws -> AssetKindBindingEventV1 {
        let rows = try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>(
            predicate: #Predicate { $0.eventID == eventID }
        ))
        guard rows.count == 1, let row = rows.first else { throw AssetSemanticContractFailureV1.invalidValue }
        return try row.value()
    }

    private func requireCapability(_ eventID: UUID) throws -> AssetWorkflowCapabilityBindingEventV1 {
        let rows = try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>(
            predicate: #Predicate { $0.eventID == eventID }
        ))
        guard rows.count == 1, let row = rows.first else { throw AssetSemanticContractFailureV1.invalidValue }
        return try row.value()
    }

    private func requireProduct(_ identityID: UUID) throws -> AssetProductIdentityV1 {
        let rows = try modelContext.fetch(FetchDescriptor<AssetProductIdentityRow>(
            predicate: #Predicate { $0.identityID == identityID }
        ))
        guard rows.count == 1, let row = rows.first else { throw AssetSemanticContractFailureV1.invalidValue }
        return try row.value()
    }

    private func requireLifecycle(_ eventID: UUID) throws -> AssetLifecycleEventV1 {
        let rows = try modelContext.fetch(FetchDescriptor<AssetLifecycleEventRow>(
            predicate: #Predicate { $0.eventID == eventID }
        ))
        guard rows.count == 1, let row = rows.first else { throw AssetSemanticContractFailureV1.invalidValue }
        return try row.value()
    }

    private func requireSuccessor(_ linkID: UUID) throws -> AssetSuccessorLinkV1 {
        let rows = try modelContext.fetch(FetchDescriptor<AssetSuccessorLinkRow>(
            predicate: #Predicate { $0.linkID == linkID }
        ))
        guard rows.count == 1, let row = rows.first else { throw AssetSemanticContractFailureV1.invalidValue }
        return try row.value()
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_AssetSemantics_AssetSemanticLifecycleAdapterV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetSemanticLifecycleAdapterV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_AssetSemantics_AssetSemanticLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetSemanticLifecycleAdapterV1.swift", role: .asset)
}

enum C31LightingConsumerBoundary_Infrastructure_AssetSemantics_AssetSemanticLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/asset-semantic-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_AssetSemantics_AssetSemanticLifecycleAdapterV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetSemanticLifecycleAdapterV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

/// C45 restore and reprint revalidate the frozen asset and locator binding.
enum C45AssetLabelBoundary_AssetSemanticLifecycleAdapterV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let reprintRevalidatesCurrentBinding = true
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetSemanticLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}
