import Foundation
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_13PersistentKindLifecycleCoverageTests: XCTestCase {
    private let candidateHead = "c5aaa2a6b6f4a1c900e5743648b66252d19f5ef7"

    func testV9_13G01ClosedUniverseAndCoverageManifestAreComplete() throws {
        let corpus = try Self.loadCorpus()
        let source = try CurrentSyncClassificationCatalogV1.current
        let catalog = try CurrentPersistentKindLifecycleCatalogV1.compile(
            candidateHead: candidateHead
        )
        try catalog.validate()

        let derivedUniverse = source.registrations.map(\.subject.canonicalKey).sorted()
        let manifest = catalog.coverageManifest
        let c35PersistentKindIDs = Set([
            "PERSISTENT_MODEL:AssetCompositionEdgeRow",
            "PERSISTENT_MODEL:AssetCompositionEventRow",
            "PERSISTENT_MODEL:AssetPlacementEventRow",
            "PERSISTENT_MODEL:LocationHierarchyEventRow",
            "PERSISTENT_MODEL:LocationMigrationReceiptRow",
            "PERSISTENT_MODEL:LocationNodeRow",
        ])
        XCTAssertEqual(corpus.declaredKindIDs, corpus.declaredKindIDs.sorted())
        XCTAssertEqual(Set(corpus.declaredKindIDs).count, corpus.declaredKindIDs.count)
        XCTAssertTrue(Set(corpus.declaredKindIDs).isSubset(of: Set(derivedUniverse)))
        XCTAssertEqual(
            Set(derivedUniverse).subtracting(corpus.declaredKindIDs),
            Set([
                "PERSISTENT_MODEL:AssetCompositionEdgeRow",
                "PERSISTENT_MODEL:AssetCompositionEventRow",
                "PERSISTENT_MODEL:AssetPlacementEventRow",
                "PERSISTENT_MODEL:LocationHierarchyEventRow",
                "PERSISTENT_MODEL:LocationMigrationReceiptRow",
                "PERSISTENT_MODEL:LocationNodeRow",
                "PROJECTION:StoreSemanticEnvelopeV6",
                "PROJECTION:V5BackupLocationRecordV1",
            ])
        )
        XCTAssertEqual(corpus.temporalProvenance.map(\.kindID), corpus.declaredKindIDs)
        XCTAssertEqual(
            Set(corpus.temporalProvenance.map(\.kindID)).count,
            corpus.declaredKindIDs.count
        )
        XCTAssertEqual(corpus.durableFirstWriteKindIDs, corpus.durableFirstWriteKindIDs.sorted())
        XCTAssertEqual(Set(corpus.durableFirstWriteKindIDs).count, 65)
        XCTAssertFalse(derivedUniverse.isEmpty)
        XCTAssertLessThanOrEqual(derivedUniverse.count, LifecycleCoverageManifestV1.maximumKindCount)
        XCTAssertEqual(manifest.universeKindIDs, derivedUniverse)
        XCTAssertEqual(manifest.descriptorKindIDs, derivedUniverse)
        XCTAssertEqual(manifest.lifecyclePolicyKindIDs, derivedUniverse)
        XCTAssertEqual(manifest.dataHandlingPolicyKindIDs, derivedUniverse)
        XCTAssertTrue(manifest.isComplete)
        XCTAssertEqual(manifest.missingKindIDs, [])
        XCTAssertEqual(manifest.duplicateKindIDs, [])
        XCTAssertEqual(manifest.conflictingKindIDs, [])
        XCTAssertEqual(manifest.unknownKindIDs, [])
        XCTAssertEqual(manifest.ownershipGapKindIDs, [])
        XCTAssertEqual(manifest.temporalConflictKindIDs, [])
        XCTAssertEqual(manifest.backupRestoreGapKindIDs, [])
        XCTAssertEqual(manifest.eraseGapKindIDs, [])
        XCTAssertEqual(manifest.exportReportGapKindIDs, [])
        XCTAssertEqual(manifest.searchAbsenceGapKindIDs, [])
        XCTAssertEqual(manifest.rebuildDependencyGapKindIDs, [])
        XCTAssertEqual(manifest.replayGapKindIDs, [])
        XCTAssertEqual(manifest.unresolvedAuthorityKindIDs, [])
        XCTAssertEqual(manifest.sourceDriftIDs, [])
        XCTAssertEqual(
            manifest.sourceEvidence.map(\.sourceID),
            corpus.universeSources.sorted()
        )
        XCTAssertTrue(manifest.provisionalKernelOnly)
        XCTAssertEqual(
            manifest.shippingBoundaryAdoption,
            LifecycleCoverageManifestV1.shippingBoundaryAdoption
        )

        let canonical = try manifest.canonicalData()
        XCTAssertEqual(try LifecycleCoverageManifestV1.decodeCanonical(canonical), manifest)
        XCTAssertEqual(try manifest.canonicalData(), canonical)

        for registration in source.registrations {
            let descriptor = try catalog.descriptor(for: registration.subject)
            let expectedProvenance = corpus.temporalProvenance.first {
                $0.kindID == descriptor.stableKindID
            }
            XCTAssertEqual(descriptor.replicationClassification, registration.classification)
            XCTAssertEqual(descriptor.stableKindID, registration.subject.canonicalKey)
            XCTAssertEqual(descriptor.declarationOwner, PersistentKindLifecycleRegistryV1.declarationOwner)
            XCTAssertNotEqual(descriptor.declarationOwner, descriptor.currentImplementationOwner)
            XCTAssertEqual(try catalog.lifecyclePolicy(for: registration.subject).kindID, descriptor.stableKindID)
            XCTAssertEqual(try catalog.dataHandlingPolicy(for: registration.subject).kindID, descriptor.stableKindID)
            if let expectedProvenance {
                XCTAssertEqual(
                    descriptor.temporalEvidence.representationSourceCard,
                    expectedProvenance.representationSourceCard
                )
                XCTAssertEqual(
                    descriptor.temporalEvidence.representationSourceOrdinal,
                    expectedProvenance.representationSourceOrdinal
                )
            } else {
                let isC35Persistent = c35PersistentKindIDs.contains(descriptor.stableKindID)
                XCTAssertEqual(
                    descriptor.temporalEvidence.representationSourceCard,
                    isC35Persistent ? "V23_P03_C35" : "PRE_V23_BASELINE"
                )
                XCTAssertEqual(
                    descriptor.temporalEvidence.representationSourceOrdinal,
                    isC35Persistent ? 41 : 0
                )
            }
            if descriptor.temporalEvidence.firstWriteVersion
                != PersistentKindTemporalEvidenceV1.notApplicable {
                XCTAssertEqual(
                    descriptor.temporalEvidence.firstWriteVersion,
                    descriptor.temporalEvidence.representationSourceCard
                )
                XCTAssertEqual(
                    descriptor.temporalEvidence.firstWriteOrdinal,
                    descriptor.temporalEvidence.representationSourceOrdinal
                )
            } else {
                XCTAssertEqual(
                    descriptor.temporalEvidence.firstWriteVersion,
                    PersistentKindTemporalEvidenceV1.notApplicable
                )
                XCTAssertEqual(descriptor.temporalEvidence.firstWriteOrdinal, 0)
            }
        }

        let provenancePartition = Dictionary(grouping: catalog.descriptors) {
            $0.temporalEvidence.representationSourceOrdinal
        }.mapValues(\.count)
        XCTAssertEqual(provenancePartition, [
            0: 56, 16: 6, 17: 1, 18: 1, 19: 3,
            22: 18, 24: 4, 27: 6, 28: 7, 41: 6,
        ])
        let durableFirstWrites = catalog.descriptors.filter {
            $0.temporalEvidence.firstWriteVersion != PersistentKindTemporalEvidenceV1.notApplicable
        }.map(\.stableKindID).sorted()
        XCTAssertTrue(Set(corpus.durableFirstWriteKindIDs).isSubset(of: Set(durableFirstWrites)))
        XCTAssertEqual(durableFirstWrites.count, 71)
        XCTAssertEqual(catalog.descriptors.count - durableFirstWrites.count, 37)
        XCTAssertTrue(Set([
            "PROJECTION:ReportSnapshotV1",
            "PROJECTION:entityMutationRevision",
            "PROJECTION:workspaceMutationState",
            "DIAGNOSTIC:DeviceOperationalSupportStoreV2",
            "DIAGNOSTIC:ScratchDataLeaseStoreV1",
            "DIAGNOSTIC:diagnosticCounters",
        ]).isSubset(of: Set(durableFirstWrites)))
        let provenanceAnchors: [(String, String, Int)] = [
            ("PERSISTENT_MODEL:Asset", "PRE_V23_BASELINE", 0),
            ("PERSISTENT_MODEL:PersistentSchemaReleaseMarker", "V23_P01_C03", 16),
            ("PROJECTION:StreamingArchiveIndexV1", "V23_P01_C04", 17),
            ("JOURNAL:CurrentGenerationPointerV3", "V23_P01_C05", 18),
            ("PERSISTENT_MODEL:DeletionLedgerRow", "V23_P01_C06", 19),
            ("PERSISTENT_MODEL:EntityMutationRevisionRow", "V23_P02_C02", 22),
            ("OWNED_FILE_CLASS:generationLeaseControl", "V23_P02_C04", 24),
            ("PERSISTENT_MODEL:ObservationAndTimeRow", "V23_P02_C07", 27),
            ("DIAGNOSTIC:DeviceOperationalSupportStoreV2", "V23_P02_C08", 28),
            ("PERSISTENT_MODEL:LocationNodeRow", "V23_P03_C35", 41),
            ("PROJECTION:StoreSemanticEnvelopeV6", "PRE_V23_BASELINE", 0),
        ]
        for (kindID, card, ordinal) in provenanceAnchors {
            let evidence = try XCTUnwrap(catalog.descriptors.first {
                $0.stableKindID == kindID
            }?.temporalEvidence)
            XCTAssertEqual(evidence.representationSourceCard, card, kindID)
            XCTAssertEqual(evidence.representationSourceOrdinal, ordinal, kindID)
        }

        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.authority.cardID, "V23-P02-C09")
        XCTAssertEqual(
            corpus.authority.contextDigest,
            "6f233d87250cb79dd3d435728e500f19bde24eb1cac5cccfa070a23df6b233c2"
        )
        XCTAssertEqual(Set(corpus.universeSources), Set([
            "ACCEPTED_FIXTURE_DECLARATION",
            "ARCHIVE_EXPORT_REPORT_PACKAGE_EXCHANGE_REGISTRY",
            "JOURNAL_CHECKPOINT_PROJECTION_REGISTRY",
            "OWNED_FILE_POLICY",
            "PERSISTENT_SCHEMA",
            "SYNC_CLASSIFICATION_CATALOG",
            "TEMPORAL_PROVENANCE_REGISTRY",
        ]))
    }

    func testV9_13A01EveryLifecycleActionAndDataHandlingClassificationIsExplicit() throws {
        let corpus = try Self.loadCorpus()
        let catalog = try CurrentPersistentKindLifecycleCatalogV1.compile(
            candidateHead: candidateHead
        )
        XCTAssertEqual(
            Set(catalog.descriptors.map(\.kindClassification.rawValue)),
            Set(corpus.classifications)
        )
        let allowedActions = Set(corpus.handlingActions)
        XCTAssertEqual(
            Set(PersistentLifecycleActionDispositionV1.allCases.map(\.rawValue)),
            allowedActions.union([PersistentLifecycleActionDispositionV1.ownerRequired.rawValue])
        )
        XCTAssertEqual(Set(corpus.classifications), Set([
            "CANONICAL", "CONTENT", "DECLARATION", "DERIVED", "IMMUTABLE",
            "NONPERSISTENT", "WIRE",
        ]))
        XCTAssertGreaterThan(
            Set(catalog.descriptors.map {
                $0.temporalEvidence.representationSourceCard
            }).count,
            1
        )
        XCTAssertEqual(
            catalog.descriptors.filter {
                $0.temporalEvidence.representationSourceCard == "V23_P02_C07"
            }.count,
            6
        )
        XCTAssertEqual(
            catalog.descriptors.filter {
                $0.temporalEvidence.representationSourceCard == "V23_P02_C08"
            }.count,
            7
        )
        XCTAssertEqual(Set(corpus.lifecycleDimensions), Set([
            "ACCESSIBILITY", "CANONICAL_QUERY", "CLONE", "COMPATIBILITY", "DELETE",
            "DOWNGRADE", "ERASE", "EXPORT", "FILESYSTEM_BACKUP", "FORK", "FORWARD_FIX",
            "FUTURE_REPLICATION", "IDEMPOTENT_RECEIPT", "IMPORT", "INTERRUPTION_RECOVERY",
            "JOURNAL", "LOCALIZATION", "MIGRATION", "PRIVACY", "REBUILD", "REPLACE_RESTORE",
            "REPLAY", "REPORT", "RETENTION", "SCHEMA_AND_VERSION", "SEARCH",
            "SEMANTIC_BACKUP", "WRITER_COMMAND",
        ]))
        XCTAssertEqual(
            corpus.lifecycleDimensions.sorted(),
            PersistentLifecycleActionV1.allCases.map(\.rawValue).sorted()
        )

        for descriptor in catalog.descriptors {
            let subject = descriptor.subject
            let policy = try catalog.lifecyclePolicy(for: subject)
            let handling = try catalog.dataHandlingPolicy(for: subject)
            let representative = try XCTUnwrap(corpus.representativePolicies.first {
                $0.classification == descriptor.kindClassification.rawValue
            })
            XCTAssertEqual(policy.actions.count, 28)
            XCTAssertEqual(policy.actions, PersistentLifecycleActionV1.allCases.map(\.rawValue)
                .sorted().compactMap(PersistentLifecycleActionV1.init(rawValue:)))
            XCTAssertFalse(policy.actionPolicies.contains { $0.disposition == .ownerRequired })
            XCTAssertNotEqual(handling.destructiveAuthority, .ownerRequired)
            XCTAssertFalse(handling.customerDataAllowedInDiagnostics)
            XCTAssertFalse(handling.secretsAllowedInDiagnostics)
            XCTAssertFalse(handling.automaticStoragePressureDeletionAllowed)

            switch descriptor.replicationClassification {
            case .replicated:
                XCTAssertEqual(descriptor.mutation, .workspaceWriter)
                XCTAssertEqual(descriptor.digest, .canonicalDigestRequired)
            case .contentBlob:
                XCTAssertEqual(descriptor.mutation, .immutableContentWriter)
                XCTAssertEqual(descriptor.digest, .immutableContentDigestRequired)
            case .derivedRebuildable:
                XCTAssertEqual(descriptor.mutation, .derivedOnly)
                XCTAssertEqual(descriptor.digest, .rebuildFromDependencies)
                XCTAssertEqual(
                    try policy.rebuild,
                    descriptor.kindClassification == .derived ? .rebuildable : .notApplicable
                )
            case .localOnly, .privateDeviceOnly:
                XCTAssertTrue(descriptor.mutation == .localDeviceOwner || descriptor.mutation == .none)
            }

            switch descriptor.kindClassification {
            case .canonical:
                XCTAssertEqual(representative.expectedErase, "SUPPORTED")
                XCTAssertEqual(try policy.erase, .supported)
            case .immutable, .declaration:
                XCTAssertEqual(representative.expectedErase, "IMMUTABLE")
                XCTAssertEqual(try policy.erase, .immutable)
            case .derived:
                XCTAssertEqual(representative.expectedRebuild, "REBUILDABLE")
                XCTAssertEqual(try policy.erase, .rebuildable)
            case .content:
                XCTAssertEqual(representative.expectedErase, "CONTENT_MANAGED")
                XCTAssertEqual(try policy.erase, .contentManaged)
                XCTAssertEqual(handling.destructiveAuthority, .immutableContentManager)
            case .wire:
                XCTAssertEqual(representative.expectedErase, "NOT_APPLICABLE")
                XCTAssertEqual(try policy.erase, .notApplicable)
            case .nonpersistent:
                XCTAssertEqual(try policy.erase, .notApplicable)
            }

            switch try policy.backup {
            case .supported:
                XCTAssertEqual(try policy.replaceRestore, .supported)
            case .immutable:
                XCTAssertEqual(try policy.replaceRestore, .immutable)
            case .rebuildable:
                XCTAssertEqual(try policy.replaceRestore, .rebuildable)
            case .denied:
                XCTAssertEqual(try policy.replaceRestore, .denied)
            case .contentManaged, .notApplicable, .ownerRequired:
                XCTFail("backup has no closed restore disposition for \(descriptor.stableKindID)")
            }
            if try policy.export == .denied {
                XCTAssertEqual(try policy.report, .denied)
            }
            if ["ReportSnapshotV1", "reportPDF", "reportSnapshot"]
                .contains(descriptor.subject.stableName) {
                XCTAssertEqual(try policy.localization, .supported)
                XCTAssertEqual(try policy.accessibility, .supported)
            }
        }

        let observedProfiles = Dictionary(uniqueKeysWithValues: corpus.representativePolicies.map {
            ($0.classification, $0)
        })
        XCTAssertEqual(observedProfiles.count, corpus.classifications.count)
        XCTAssertEqual(observedProfiles["IMMUTABLE"]?.expectedErase, "IMMUTABLE")
        XCTAssertEqual(observedProfiles["DERIVED"]?.expectedRebuild, "REBUILDABLE")
        XCTAssertEqual(observedProfiles["CONTENT"]?.expectedErase, "CONTENT_MANAGED")
    }

    func testV9_13H01DuplicateConflictingAndUnsafePoliciesFailClosed() throws {
        let corpus = try Self.loadCorpus()
        let source = try CurrentSyncClassificationCatalogV1.current
        let catalog = try CurrentPersistentKindLifecycleCatalogV1.compile(
            candidateHead: candidateHead
        )
        let firstDescriptor = try XCTUnwrap(catalog.descriptors.first)
        let firstPolicy = try XCTUnwrap(catalog.lifecyclePolicies.first)
        let firstHandling = try XCTUnwrap(catalog.dataHandlingPolicies.first)
        let sourceEvidence = catalog.coverageManifest.sourceEvidence
        func compileReplacing(
            policy replacement: PersistentLifecyclePolicyV1? = nil,
            descriptor descriptorReplacement: PersistentKindDescriptorV1? = nil
        ) throws {
            _ = try PersistentKindLifecycleRegistryV1.compileCoverage(
                candidateHead: candidateHead,
                sourceEvidence: sourceEvidence,
                universe: source.registrations.map(\.subject),
                descriptors: catalog.descriptors.map {
                    $0.stableKindID == descriptorReplacement?.stableKindID
                        ? descriptorReplacement! : $0
                },
                lifecyclePolicies: catalog.lifecyclePolicies.map {
                    $0.kindID == replacement?.kindID ? replacement! : $0
                },
                dataHandlingPolicies: catalog.dataHandlingPolicies
            )
        }

        XCTAssertThrowsError(try PersistentLifecyclePolicyV1(
            kindID: firstPolicy.kindID,
            policyRevision: firstPolicy.policyRevision,
            actionPolicies: Array(firstPolicy.actionPolicies.dropFirst())
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidLifecyclePolicy) }

        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: Array(sourceEvidence.dropFirst()),
            universe: source.registrations.map(\.subject),
            descriptors: catalog.descriptors,
            lifecyclePolicies: catalog.lifecyclePolicies,
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        let temporalSource = try XCTUnwrap(sourceEvidence.first {
            $0.sourceID == "TEMPORAL_PROVENANCE_REGISTRY"
        })
        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: sourceEvidence.filter { $0.sourceID != temporalSource.sourceID },
            universe: source.registrations.map(\.subject),
            descriptors: catalog.descriptors,
            lifecyclePolicies: catalog.lifecyclePolicies,
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }
        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: sourceEvidence + [temporalSource],
            universe: source.registrations.map(\.subject),
            descriptors: catalog.descriptors,
            lifecyclePolicies: catalog.lifecyclePolicies,
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        let completeEraseObservations = try catalog.descriptors.map { descriptor in
            try PersistentEraseObservationV1(
                kindID: descriptor.stableKindID,
                disposition: try Self.independentEraseDisposition(
                    descriptor: descriptor,
                    handling: catalog.dataHandlingPolicy(for: descriptor.subject)
                )
            )
        }
        XCTAssertThrowsError(try catalog.auditErase(
            observations: Array(completeEraseObservations.dropFirst())
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: sourceEvidence,
            universe: source.registrations.map(\.subject),
            descriptors: catalog.descriptors + [firstDescriptor],
            lifecyclePolicies: catalog.lifecyclePolicies,
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: sourceEvidence,
            universe: source.registrations.map(\.subject),
            descriptors: Array(catalog.descriptors.dropFirst()),
            lifecyclePolicies: catalog.lifecyclePolicies,
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        let conflictingPolicy = try Self.copy(firstPolicy, policyRevision: firstPolicy.policyRevision + 1)
        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: sourceEvidence,
            universe: source.registrations.map(\.subject),
            descriptors: catalog.descriptors,
            lifecyclePolicies: [conflictingPolicy] + Array(catalog.lifecyclePolicies.dropFirst()),
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        XCTAssertThrowsError(try PersistentKindDescriptorV1(
            subject: firstDescriptor.subject,
            storage: firstDescriptor.storage,
            revision: firstDescriptor.revision,
            mutation: firstDescriptor.mutation,
            digest: firstDescriptor.digest,
            kindClassification: firstDescriptor.kindClassification,
            replicationClassification: firstDescriptor.replicationClassification,
            temporalEvidence: firstDescriptor.temporalEvidence,
            declarationOwner: firstDescriptor.declarationOwner,
            currentImplementationOwner: firstDescriptor.declarationOwner
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidDescriptor) }

        XCTAssertThrowsError(try Self.copy(
            firstPolicy,
            action: .migration,
            disposition: .ownerRequired
        )) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidLifecyclePolicy)
        }

        let backupWithoutRestore = try Self.copy(
            try Self.copy(
                firstPolicy,
                action: .semanticBackup,
                disposition: .supported,
                evidence: .implementationRequired
            ),
            action: .replaceRestore,
            disposition: .denied,
            evidence: .absenceProved
        )
        XCTAssertThrowsError(try compileReplacing(policy: backupWithoutRestore)) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage)
        }

        let deniedExportLeak = try Self.copy(
            try Self.copy(
                firstPolicy,
                action: .export,
                disposition: .denied,
                evidence: .absenceProved
            ),
            action: .report,
            disposition: .supported,
            evidence: .implementationRequired
        )
        XCTAssertThrowsError(try compileReplacing(policy: deniedExportLeak)) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage)
        }

        let temporalDescriptor = try XCTUnwrap(catalog.descriptors.first {
            $0.temporalEvidence.disposition == .preexistingBoundForwardFix
        })
        let temporal = temporalDescriptor.temporalEvidence
        let driftedTemporal = try PersistentKindTemporalEvidenceV1(
            evidenceID: temporal.evidenceID,
            evidenceVersion: temporal.evidenceVersion,
            disposition: temporal.disposition,
            representationSourceCard: temporal.representationSourceCard,
            representationSourceOrdinal: temporal.representationSourceOrdinal,
            firstWriteVersion: temporal.firstWriteVersion,
            lifecycleEnrollmentVersion: temporal.lifecycleEnrollmentVersion,
            forwardFixVersion: "V23_P02_C10",
            firstWriteOrdinal: temporal.firstWriteOrdinal,
            lifecycleEnrollmentOrdinal: temporal.lifecycleEnrollmentOrdinal,
            forwardFixOrdinal: temporal.forwardFixOrdinal
        )
        XCTAssertThrowsError(try compileReplacing(
            descriptor: try Self.copy(temporalDescriptor, temporalEvidence: driftedTemporal)
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }
        XCTAssertThrowsError(try PersistentKindTemporalEvidenceV1(
            evidenceID: temporal.evidenceID,
            evidenceVersion: temporal.evidenceVersion,
            disposition: .preexistingBoundForwardFix,
            representationSourceCard: temporal.representationSourceCard,
            representationSourceOrdinal: temporal.representationSourceOrdinal,
            firstWriteVersion: temporal.firstWriteVersion,
            lifecycleEnrollmentVersion: temporal.lifecycleEnrollmentVersion,
            forwardFixVersion: temporal.forwardFixVersion,
            firstWriteOrdinal: temporal.firstWriteOrdinal,
            lifecycleEnrollmentOrdinal: temporal.firstWriteOrdinal,
            forwardFixOrdinal: temporal.forwardFixOrdinal
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidDescriptor) }

        let observationDescriptor = try XCTUnwrap(catalog.descriptors.first {
            $0.stableKindID == "PERSISTENT_MODEL:ObservationAndTimeRow"
        })
        let observationTemporal = observationDescriptor.temporalEvidence
        let wrongLaterCard = try PersistentKindTemporalEvidenceV1(
            evidenceID: observationTemporal.evidenceID,
            evidenceVersion: observationTemporal.evidenceVersion,
            disposition: observationTemporal.disposition,
            representationSourceCard: "V23_P02_C08",
            representationSourceOrdinal: 28,
            firstWriteVersion: "V23_P02_C08",
            lifecycleEnrollmentVersion: observationTemporal.lifecycleEnrollmentVersion,
            forwardFixVersion: observationTemporal.forwardFixVersion,
            firstWriteOrdinal: 28,
            lifecycleEnrollmentOrdinal: observationTemporal.lifecycleEnrollmentOrdinal,
            forwardFixOrdinal: observationTemporal.forwardFixOrdinal
        )
        XCTAssertThrowsError(try compileReplacing(
            descriptor: try Self.copy(observationDescriptor, temporalEvidence: wrongLaterCard)
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        let observationBytes = try CompatibilityCanonicalV1.encode(observationDescriptor)
        let observationJSON = try XCTUnwrap(String(data: observationBytes, encoding: .utf8))
        let missingProvenance = Data(observationJSON.replacingOccurrences(
            of: "\"representationSourceCard\":\"\(observationTemporal.representationSourceCard)\",",
            with: ""
        ).utf8)
        XCTAssertNotEqual(missingProvenance, observationBytes)
        XCTAssertThrowsError(try CompatibilityCanonicalV1.decode(
            PersistentKindDescriptorV1.self,
            from: missingProvenance
        ))

        let immutableDescriptor = try XCTUnwrap(catalog.descriptors.first {
            $0.kindClassification == .immutable
        })
        let immutablePolicy = try catalog.lifecyclePolicy(for: immutableDescriptor.subject)
        let destructiveImmutableErase = try Self.copy(
            immutablePolicy,
            action: .erase,
            disposition: .supported,
            evidence: .implementationRequired
        )
        XCTAssertThrowsError(try compileReplacing(policy: destructiveImmutableErase)) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage)
        }

        let descriptorBytes = try CompatibilityCanonicalV1.encode(firstDescriptor)
        let descriptorJSON = try XCTUnwrap(String(data: descriptorBytes, encoding: .utf8))
        let unknownClassification = Data(descriptorJSON.replacingOccurrences(
            of: "\"kindClassification\":\"\(firstDescriptor.kindClassification.rawValue)\"",
            with: "\"kindClassification\":\"UNKNOWN_FUTURE_CLASS\""
        ).utf8)
        XCTAssertThrowsError(try CompatibilityCanonicalV1.decode(
            PersistentKindDescriptorV1.self,
            from: unknownClassification
        )) { XCTAssertEqual($0 as? CompatibilityContractErrorV1, .invalidCanonicalValue) }
        XCTAssertThrowsError(try Self.copy(firstDescriptor, schemaVersion: 2)) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidDescriptor)
        }

        let policyBytes = try CompatibilityCanonicalV1.encode(firstPolicy)
        let policyJSON = try XCTUnwrap(String(data: policyBytes, encoding: .utf8))
        let firstAction = try XCTUnwrap(firstPolicy.actionPolicies.first).action.rawValue
        let unknownAction = Data(policyJSON.replacingOccurrences(
            of: "\"action\":\"\(firstAction)\"",
            with: "\"action\":\"UNKNOWN_FUTURE_ACTION\""
        ).utf8)
        XCTAssertThrowsError(try CompatibilityCanonicalV1.decode(
            PersistentLifecyclePolicyV1.self,
            from: unknownAction
        )) { XCTAssertEqual($0 as? CompatibilityContractErrorV1, .invalidCanonicalValue) }
        let futurePolicyVersion = Data(policyJSON.replacingOccurrences(
            of: "\"schemaVersion\":1",
            with: "\"schemaVersion\":2"
        ).utf8)
        XCTAssertThrowsError(try {
            let decoded = try CompatibilityCanonicalV1.decode(
                PersistentLifecyclePolicyV1.self,
                from: futurePolicyVersion
            )
            try decoded.validate()
        }()) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidLifecyclePolicy) }
        XCTAssertThrowsError(try DataHandlingPolicyV1(
            kindID: firstHandling.kindID,
            policyRevision: firstHandling.policyRevision,
            privacy: firstHandling.privacy,
            retention: firstHandling.retention,
            privacyAuthority: firstHandling.privacyAuthority,
            retentionAuthority: firstHandling.retentionAuthority,
            destructiveAuthority: .ownerRequired,
            destructiveAuthorityOwner: firstHandling.destructiveAuthorityOwner,
            secretHandling: firstHandling.secretHandling,
            telemetry: firstHandling.telemetry,
            fileProtection: firstHandling.fileProtection,
            localization: firstHandling.localization,
            accessibility: firstHandling.accessibility,
            customerWorkDataScope: firstHandling.customerWorkDataScope
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidDataHandlingPolicy) }

        let unknownSubject = try SyncSubjectIdentityV1(
            category: .diagnostic,
            stableName: "HostileUnknownPersistentKind"
        )
        let unknownDescriptor = try PersistentKindDescriptorV1(
            subject: unknownSubject,
            storage: .nonpersistentDeclaration,
            revision: .destinationLocal,
            mutation: .localDeviceOwner,
            digest: .notApplicable,
            kindClassification: .nonpersistent,
            replicationClassification: .privateDeviceOnly,
            temporalEvidence: try PersistentKindTemporalEvidenceV1(
                evidenceID: "temporal.DIAGNOSTIC:HostileUnknownPersistentKind",
                evidenceVersion: 1,
                disposition: .nonpersistentNoCanonicalWrite,
                firstWriteVersion: PersistentKindTemporalEvidenceV1.notApplicable,
                lifecycleEnrollmentVersion: "V23_P02_C09",
                forwardFixVersion: PersistentKindTemporalEvidenceV1.notApplicable,
                firstWriteOrdinal: 0,
                lifecycleEnrollmentOrdinal: 29,
                forwardFixOrdinal: 0
            ),
            declarationOwner: PersistentKindLifecycleRegistryV1.declarationOwner,
            currentImplementationOwner: "V23-P02-C09.HostileUnknownOwner"
        )
        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: sourceEvidence,
            universe: source.registrations.map(\.subject),
            descriptors: catalog.descriptors + [unknownDescriptor],
            lifecyclePolicies: catalog.lifecyclePolicies,
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        XCTAssertEqual(Set(corpus.hostileCases), Set([
            "BACKUP_WITHOUT_RESTORE", "DENIED_KIND_ENTERS_EXPORT", "DENIED_KIND_ENTERS_REPORT",
            "DUPLICATE_KIND", "DUPLICATE_OWNER", "ERASE_DESTROYS_IMMUTABLE_TRUTH",
            "ERASE_LEAVES_ERASABLE_ORPHAN", "MISSING_KIND", "OWNER_IMPLEMENTATION_CONFLICT",
            "TEMPORALLY_IMPOSSIBLE_WRITER", "UNKNOWN_ACTION", "UNKNOWN_CLASSIFICATION",
            "UNKNOWN_POLICY_VERSION", "MISSING_TEMPORAL_PROVENANCE",
            "DUPLICATE_TEMPORAL_PROVENANCE", "WRONG_LATER_CARD_PROVENANCE",
            "IMPOSSIBLE_TEMPORAL_CHRONOLOGY",
        ]))
    }

    func testV9_13I01InterruptedLifecycleTransitionsExposeNoPartialAcceptance() throws {
        let corpus = try Self.loadCorpus()
        let catalog = try CurrentPersistentKindLifecycleCatalogV1.compile(
            candidateHead: candidateHead
        )
        let boundaries: [(
            PersistentLifecycleInterruptionPointV1,
            PersistentLifecycleRecoveredEffectV1
        )] = [
            (.beforePolicyStaging, .noEffect),
            (.afterPolicyStagingBeforeActivation, .discardedUnpublishedStaging),
            (.afterActivationBeforeReceipt, .adoptedCompleteEffect),
            (.afterReceiptBeforeCleanup, .adoptedExistingReceipt),
        ]
        XCTAssertEqual(boundaries.map { $0.0.rawValue }, corpus.interruptionBoundaries)

        var observedStorage = Set<String>()
        var observedLifecycleClasses = Set<String>()
        for (descriptorIndex, descriptor) in catalog.descriptors.enumerated() {
            let policy = try catalog.lifecyclePolicy(for: descriptor.subject)
            observedStorage.insert(descriptor.storage.rawValue)
            observedLifecycleClasses.insert(descriptor.kindClassification.rawValue)
            for (boundaryIndex, boundary) in boundaries.enumerated() {
                let (point, recoveredEffect) = boundary
                let operationID = try XCTUnwrap(UUID(uuidString: String(
                    format: "91300000-0000-0000-0000-%012llx",
                    UInt64(descriptorIndex * boundaries.count + boundaryIndex + 1)
                )))
                let proposed = try PersistentLifecycleRecoveryReceiptV1(
                    operationID: operationID,
                    kindID: descriptor.stableKindID,
                    persistenceClass: descriptor.storage,
                    interruptionPoint: point,
                    recoveredEffect: recoveredEffect,
                    policyRevision: policy.policyRevision
                )
                let bytes = try CompatibilityCanonicalV1.encode(proposed)
                XCTAssertEqual(
                    try CompatibilityCanonicalV1.decode(
                        PersistentLifecycleRecoveryReceiptV1.self,
                        from: bytes
                    ),
                    proposed
                )
                let published = try PersistentLifecycleReceiptPublicationV1.publishOrAdopt(
                    proposed: proposed,
                    existing: nil
                )
                XCTAssertEqual(
                    try PersistentLifecycleReceiptPublicationV1.publishOrAdopt(
                        proposed: proposed,
                        existing: published
                    ),
                    proposed
                )
            }
        }
        XCTAssertEqual(
            observedStorage,
            Set(PersistentKindStorageDispositionV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            observedLifecycleClasses,
            Set(PersistentKindClassificationV1.allCases.map(\.rawValue))
        )

        let descriptor = try XCTUnwrap(catalog.descriptors.first)
        let policy = try catalog.lifecyclePolicy(for: descriptor.subject)
        XCTAssertThrowsError(try PersistentLifecycleRecoveryReceiptV1(
            operationID: UUID(uuidString: "91300000-0000-0000-0000-000000000005")!,
            kindID: descriptor.stableKindID,
            persistenceClass: descriptor.storage,
            interruptionPoint: .afterPolicyStagingBeforeActivation,
            recoveredEffect: .adoptedCompleteEffect,
            policyRevision: policy.policyRevision
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidLifecyclePolicy) }

        let priorDigest = String(repeating: "a", count: 64)
        let staged = try PersistentLifecyclePolicySuccessorReceiptV1(
            kindID: policy.kindID,
            activationState: .preActivation,
            priorPolicyRevision: policy.policyRevision,
            resultingPolicyRevision: policy.policyRevision,
            priorCanonicalDigest: priorDigest,
            resultingCanonicalDigest: priorDigest,
            disposition: .discardUnpublishedStaging
        )
        try staged.validate()
        XCTAssertEqual(staged.disposition, .discardUnpublishedStaging)
        XCTAssertEqual(staged.priorCanonicalDigest, staged.resultingCanonicalDigest)
    }

    func testV9_13R01EraseCompatibilityForwardFixAndFixtureBindingRemainClosed() throws {
        let corpus = try Self.loadCorpus()
        let catalog = try CurrentPersistentKindLifecycleCatalogV1.compile(
            candidateHead: candidateHead
        )
        let observations = try catalog.descriptors.map { descriptor in
            try PersistentEraseObservationV1(
                kindID: descriptor.stableKindID,
                disposition: try Self.independentEraseDisposition(
                    descriptor: descriptor,
                    handling: catalog.dataHandlingPolicy(for: descriptor.subject)
                )
            )
        }
        let eraseReceipt = try catalog.auditErase(observations: observations)
        XCTAssertTrue(eraseReceipt.isComplete)
        XCTAssertEqual(eraseReceipt.auditedKindIDs, catalog.coverageManifest.universeKindIDs)
        XCTAssertEqual(eraseReceipt.missingKindIDs.count, corpus.eraseExpectations.erasableSurvivorCount)
        XCTAssertEqual(eraseReceipt.duplicateKindIDs, [])
        XCTAssertEqual(eraseReceipt.unexpectedKindIDs.count, corpus.eraseExpectations.orphanCount)
        XCTAssertEqual(eraseReceipt.mismatchedKindIDs, [])
        XCTAssertTrue(corpus.eraseExpectations.immutableTruthPreserved)
        XCTAssertFalse(corpus.eraseExpectations.usesOneGlobalDestructiveRule)

        let contentDescriptor = try XCTUnwrap(catalog.descriptors.first {
            $0.kindClassification == .content
        })
        let contentPolicy = try catalog.lifecyclePolicy(for: contentDescriptor.subject)
        let wrongContentErase = try Self.copy(
            contentPolicy,
            action: .erase,
            disposition: .supported,
            evidence: .implementationRequired
        )
        let source = try CurrentSyncClassificationCatalogV1.current
        XCTAssertThrowsError(try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: catalog.coverageManifest.sourceEvidence,
            universe: source.registrations.map(\.subject),
            descriptors: catalog.descriptors,
            lifecyclePolicies: catalog.lifecyclePolicies.map {
                $0.kindID == wrongContentErase.kindID ? wrongContentErase : $0
            },
            dataHandlingPolicies: catalog.dataHandlingPolicies
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }

        let first = try XCTUnwrap(observations.first)
        XCTAssertThrowsError(try catalog.auditErase(observations: Array(observations.dropFirst()))) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage)
        }
        XCTAssertThrowsError(try catalog.auditErase(observations: observations + [first])) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage)
        }
        let wrongDisposition: PersistentEraseObservedDispositionV1 =
            first.disposition == .notApplicable ? .removed : .notApplicable
        let mismatch = try PersistentEraseObservationV1(
            kindID: first.kindID,
            disposition: wrongDisposition
        )
        XCTAssertThrowsError(try catalog.auditErase(
            observations: [mismatch] + Array(observations.dropFirst())
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage) }
        let unexpected = try PersistentEraseObservationV1(
            kindID: "DIAGNOSTIC:UnexpectedEraseKind",
            disposition: .removed
        )
        XCTAssertThrowsError(try catalog.auditErase(observations: observations + [unexpected])) {
            XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .incompleteCoverage)
        }

        let policy = try XCTUnwrap(catalog.lifecyclePolicies.first)
        let priorDigest = String(repeating: "1", count: 64)
        let successorDigest = String(repeating: "2", count: 64)
        let successor = try PersistentLifecyclePolicySuccessorReceiptV1(
            kindID: policy.kindID,
            activationState: .activated,
            priorPolicyRevision: policy.policyRevision,
            resultingPolicyRevision: policy.policyRevision + 1,
            priorCanonicalDigest: priorDigest,
            resultingCanonicalDigest: successorDigest,
            disposition: .appendForwardFixSuccessor
        )
        try successor.validate()
        XCTAssertNotEqual(successor.priorCanonicalDigest, successor.resultingCanonicalDigest)
        XCTAssertEqual(successor.resultingPolicyRevision, successor.priorPolicyRevision + 1)
        XCTAssertThrowsError(try PersistentLifecyclePolicySuccessorReceiptV1(
            kindID: policy.kindID,
            activationState: .activated,
            priorPolicyRevision: policy.policyRevision,
            resultingPolicyRevision: policy.policyRevision,
            priorCanonicalDigest: priorDigest,
            resultingCanonicalDigest: priorDigest,
            disposition: .discardUnpublishedStaging
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidLifecyclePolicy) }
        XCTAssertThrowsError(try PersistentLifecyclePolicySuccessorReceiptV1(
            schemaVersion: 2,
            kindID: policy.kindID,
            activationState: .activated,
            priorPolicyRevision: policy.policyRevision,
            resultingPolicyRevision: policy.policyRevision + 1,
            priorCanonicalDigest: priorDigest,
            resultingCanonicalDigest: successorDigest,
            disposition: .appendForwardFixSuccessor
        )) { XCTAssertEqual($0 as? PersistentKindLifecycleFailureV1, .invalidLifecyclePolicy) }

        try ReleasedDataCompatibilityPolicyV1.current.validate()
        let exactHeadCompatibility = ReleasedDataCompatibilityPolicyV1.exactHead(
            candidateHead: candidateHead
        )
        try exactHeadCompatibility.validate()
        let liveStore = try exactHeadCompatibility.dataManifest
            .path(for: .liveStore)
        XCTAssertEqual(liveStore.currentWriterVersion, "6.0.0")
        XCTAssertTrue(liveStore.readableVersions.contains("4.0.0"))
        XCTAssertTrue(liveStore.readableVersions.contains("5.0.0"))
        XCTAssertTrue(liveStore.readableVersions.contains("6.0.0"))
        XCTAssertTrue(try liveStore.supportsForwardUpgrade(
            fromVersion: "1.0.0",
            toVersion: liveStore.currentWriterVersion
        ))
        XCTAssertThrowsError(try liveStore.validateReadableVersion("999.0.0")) {
            XCTAssertEqual($0 as? CompatibilityContractErrorV1, .unsupportedVersion)
        }
        let backup = try exactHeadCompatibility.dataManifest.path(for: .backupPackage)
        XCTAssertEqual(backup.currentWriterVersion, "archive1-backup4-persistent6-records5")
        XCTAssertTrue(backup.readableVersions.contains("archive1-backup4-persistent5-records4"))

        XCTAssertEqual(corpus.fixtureIdentity, "V21-P02-C09-PERSISTENT-KIND-LIFECYCLE-COVERAGE-CORPUS-V1")
        XCTAssertEqual(
            corpus.authority.pathFenceDigest,
            "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171"
        )
        XCTAssertEqual(corpus.authority.provisionalUntil, "ACCEPTED_S10_6_RECONCILIATION")
        XCTAssertEqual(corpus.expectedAudit.missingCount, eraseReceipt.missingKindIDs.count)
        XCTAssertEqual(corpus.expectedAudit.duplicateCount, eraseReceipt.duplicateKindIDs.count)
        XCTAssertEqual(corpus.expectedAudit.conflictingCount, eraseReceipt.mismatchedKindIDs.count)
        XCTAssertEqual(corpus.expectedAudit.unknownCount, eraseReceipt.unexpectedKindIDs.count)
        XCTAssertEqual(corpus.brandImpact.manifestCount, 1)
        XCTAssertTrue(corpus.brandImpact.changedScreens.isEmpty)
        XCTAssertTrue(corpus.brandImpact.changedStates.isEmpty)
        XCTAssertEqual(Set(corpus.brandImpact.affectedConsumers), Set(["V23-P02-C10", "V23-P03-C01"]))
        XCTAssertTrue(corpus.compatibilityCases.allSatisfy { !$0.rewritesReleasedHistory })
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: corpus.compatibilityCases.map { ($0.caseID, $0.expectedDisposition) }),
            [
                "PRE_ACTIVATION_INTERRUPTION": "DISCARD_STAGING",
                "POST_ACTIVATION_INTERRUPTION": "APPEND_VERSIONED_SUCCESSOR_AND_FORWARD_FIX",
                "FUTURE_POLICY_VERSION": "QUARANTINE_AND_REQUIRE_FORWARD_FIX",
            ]
        )
    }
}

private extension V9_13PersistentKindLifecycleCoverageTests {
    nonisolated static func copy(
        _ value: PersistentLifecyclePolicyV1,
        policyRevision: Int? = nil,
        action: PersistentLifecycleActionV1? = nil,
        disposition: PersistentLifecycleActionDispositionV1? = nil,
        evidence: PersistentLifecycleEvidenceDispositionV1? = nil,
        dependencyKindIDs: [String]? = nil
    ) throws -> PersistentLifecyclePolicyV1 {
        let rows = try value.actionPolicies.map { row in
            guard row.action == action else { return row }
            return try PersistentLifecycleActionPolicyV1(
                action: row.action,
                disposition: disposition ?? row.disposition,
                authority: row.authority,
                reason: row.reason,
                dependencyKindIDs: dependencyKindIDs ?? row.dependencyKindIDs,
                evidence: evidence ?? row.evidence
            )
        }
        try PersistentLifecyclePolicyV1(
            kindID: value.kindID,
            policyRevision: policyRevision ?? value.policyRevision,
            actionPolicies: rows
        )
    }

    nonisolated static func copy(
        _ value: PersistentKindDescriptorV1,
        schemaVersion: Int? = nil,
        temporalEvidence: PersistentKindTemporalEvidenceV1? = nil
    ) throws -> PersistentKindDescriptorV1 {
        try PersistentKindDescriptorV1(
            schemaVersion: schemaVersion ?? value.schemaVersion,
            subject: value.subject,
            policyRevision: value.policyRevision,
            storage: value.storage,
            revision: value.revision,
            mutation: value.mutation,
            digest: value.digest,
            kindClassification: value.kindClassification,
            replicationClassification: value.replicationClassification,
            temporalEvidence: temporalEvidence ?? value.temporalEvidence,
            declarationOwner: value.declarationOwner,
            currentImplementationOwner: value.currentImplementationOwner
        )
    }

    nonisolated static func independentEraseDisposition(
        descriptor: PersistentKindDescriptorV1,
        handling: DataHandlingPolicyV1
    ) throws -> PersistentEraseObservedDispositionV1 {
        switch descriptor.kindClassification {
        case .canonical: return .removed
        case .immutable, .declaration: return .preservedImmutable
        case .derived: return .rebuiltEmpty
        case .wire: return .notApplicable
        case .content:
            guard handling.destructiveAuthority == .immutableContentManager else {
                throw PersistentKindLifecycleFailureV1.unresolvedAuthority
            }
            return .clearedByDeclaredOwner
        case .nonpersistent: return .notApplicable
        }
    }

    nonisolated static func loadCorpus() throws -> V913Corpus {
        let name = "V21P02C09PersistentKindLifecycleCoverageCorpusV1"
        let url = try XCTUnwrap(Bundle(for: V9_13PersistentKindLifecycleCoverageTests.self)
            .url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(V913Corpus.self, from: Data(contentsOf: url))
    }
}

private struct V913Corpus: Decodable {
    let schemaVersion: Int
    let fixtureIdentity: String
    let authority: Authority
    let declaredKindIDs: [String]
    let durableFirstWriteKindIDs: [String]
    let temporalProvenance: [TemporalProvenance]
    let universeSources: [String]
    let classifications: [String]
    let handlingActions: [String]
    let lifecycleDimensions: [String]
    let representativePolicies: [RepresentativePolicy]
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let compatibilityCases: [CompatibilityCase]
    let eraseExpectations: EraseExpectations
    let brandImpact: BrandImpact
    let expectedAudit: ExpectedAudit

    struct Authority: Decodable {
        let cardID: String
        let contextDigest: String
        let pathFenceDigest: String
        let provisionalUntil: String
    }

    struct RepresentativePolicy: Decodable {
        let classification: String
        let expectedErase: String
        let expectedRebuild: String
        let expectedRetention: String
    }

    struct TemporalProvenance: Decodable {
        let kindID: String
        let representationSourceCard: String
        let representationSourceOrdinal: Int
    }

    struct CompatibilityCase: Decodable {
        let caseID: String
        let expectedDisposition: String
        let rewritesReleasedHistory: Bool
    }

    struct EraseExpectations: Decodable {
        let erasableSurvivorCount: Int
        let orphanCount: Int
        let immutableTruthPreserved: Bool
        let usesOneGlobalDestructiveRule: Bool
    }

    struct BrandImpact: Decodable {
        let changedScreens: [String]
        let changedStates: [String]
        let affectedConsumers: [String]
        let manifestCount: Int
    }

    struct ExpectedAudit: Decodable {
        let missingCount: Int
        let duplicateCount: Int
        let conflictingCount: Int
        let unknownCount: Int
    }
}
