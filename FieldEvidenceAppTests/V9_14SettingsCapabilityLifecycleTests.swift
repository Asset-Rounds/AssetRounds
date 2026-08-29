import Foundation
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_14SettingsCapabilityLifecycleTests: XCTestCase {
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV9_14G01TypedSettingsScopesMigrationAndLifecycle() throws {
        let corpus = try Self.loadCorpus()
        let registry = try SettingsRegistryV1.current()
        XCTAssertEqual(registry.descriptors.map(\.key), corpus.settingKeys)
        XCTAssertEqual(Set(SettingScopeV1.allCases.map(\.rawValue)), Set(corpus.settingScopes))

        let haptic = try registry.descriptor(for: HapticFeedbackPreferenceV1.key)
        let recent = try registry.descriptor(for: "device.recentInputMemory")
        for descriptor in [haptic, recent] {
            try descriptor.validate()
            XCTAssertEqual(descriptor.scope, .deviceLocal)
            XCTAssertEqual(descriptor.storage, .soleDevicePreferencesAdapter)
            XCTAssertEqual(descriptor.backup, .excludedDeviceLocal)
            XCTAssertEqual(descriptor.reset, .restoreDefault)
            XCTAssertEqual(descriptor.erase, .restoreDefault)
            XCTAssertFalse(descriptor.changesHistoricOutput)
        }
        XCTAssertEqual(
            try CompatibilityCanonicalV1.decode(Bool.self, from: haptic.defaultCanonicalValue),
            HapticFeedbackPreferenceV1.logicalDefault.isEnabled
        )

        let workspace = try SettingDescriptorV1(
            key: "workspace.displayMode",
            valueKind: .boundedString,
            scope: .workspaceCanonical,
            storage: .workspaceWriter,
            defaultCanonicalValue: try CompatibilityCanonicalV1.encode("STANDARD"),
            maximumCanonicalBytes: 32,
            migrationVersion: 1,
            backup: .canonicalWorkspaceBackup,
            reset: .preserveAcknowledgement,
            erase: .clearCanonical,
            privacy: .workspaceCanonical,
            localizationKey: "settings.workspace.displayMode"
        )
        let derived = try SettingDescriptorV1(
            key: "derived.captureReady",
            valueKind: .boolean,
            scope: .derived,
            storage: .nonpersistentDerived,
            defaultCanonicalValue: Data("false".utf8),
            maximumCanonicalBytes: 8,
            migrationVersion: 1,
            backup: .notApplicable,
            reset: .rebuild,
            erase: .rebuild,
            privacy: .derivedNoPersistence,
            localizationKey: "settings.derived.captureReady"
        )
        let complete = try SettingsRegistryV1(descriptors: registry.descriptors + [workspace, derived])
        XCTAssertEqual(Set(complete.descriptors.map(\.scope)), Set(SettingScopeV1.allCases))
        XCTAssertThrowsError(try SettingDescriptorV1(
            key: "workspace.invalidUntypedDefault",
            valueKind: .boundedString,
            scope: .workspaceCanonical,
            storage: .workspaceWriter,
            defaultCanonicalValue: Data("STANDARD".utf8),
            maximumCanonicalBytes: 32,
            migrationVersion: 1,
            backup: .canonicalWorkspaceBackup,
            reset: .preserveAcknowledgement,
            erase: .clearCanonical,
            privacy: .workspaceCanonical,
            localizationKey: "settings.workspace.invalidUntypedDefault"
        )) { XCTAssertEqual($0 as? SettingsContractFailureV1, .invalidDescriptor) }
        XCTAssertThrowsError(try SettingsRegistryV1(descriptors: [haptic, haptic])) {
            XCTAssertEqual($0 as? SettingsContractFailureV1, .duplicateKey)
        }
        XCTAssertThrowsError(try SettingDescriptorV1(
            key: "hostile.scopeLeak",
            valueKind: .boolean,
            scope: .deviceLocal,
            storage: .workspaceWriter,
            defaultCanonicalValue: Data("true".utf8),
            maximumCanonicalBytes: 8,
            migrationVersion: 1,
            backup: .canonicalWorkspaceBackup,
            reset: .restoreDefault,
            erase: .restoreDefault,
            privacy: .workspaceCanonical,
            localizationKey: "settings.hostile.scopeLeak"
        )) { XCTAssertEqual($0 as? SettingsContractFailureV1, .scopeMismatch) }

        let digest = CompatibilityCanonicalV1.sha256(haptic.defaultCanonicalValue)
        let initialized = try SettingsMigrationReceiptV1(
            operationID: Self.uuid(30),
            key: haptic.key,
            migrationVersion: haptic.migrationVersion,
            disposition: .initializedFromAbsence,
            canonicalValueDigest: digest
        )
        let adopted = try SettingsMigrationReceiptV1(
            operationID: Self.uuid(31),
            key: haptic.key,
            migrationVersion: haptic.migrationVersion,
            disposition: .adoptedCurrentValue,
            canonicalValueDigest: digest
        )
        XCTAssertEqual(initialized.canonicalValueDigest, adopted.canonicalValueDigest)
        XCTAssertFalse(initialized.disposition == adopted.disposition)

        let suiteName = "V9_14.SettingsCapabilityLifecycle"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let adapter = PreferencesAdapterV1(defaults: defaults)
        XCTAssertEqual(try adapter.readCanonicalValue(for: haptic), haptic.defaultCanonicalValue)
        XCTAssertThrowsError(try adapter.migrate(
            descriptor: haptic,
            legacyKeys: [PreferencesAdapterV1.storagePrefix + haptic.key],
            operationID: Self.uuid(35)
        )) { XCTAssertEqual($0 as? PreferencesAdapterFailureV1, .ambiguousLegacyKeys) }
        let disabledBytes = try CompatibilityCanonicalV1.encode(false)
        defaults.set(disabledBytes, forKey: "legacy.haptics")
        let migrated = try adapter.migrate(
            descriptor: haptic,
            legacyKeys: ["legacy.haptics"],
            operationID: Self.uuid(32)
        )
        XCTAssertEqual(migrated.disposition, .migratedLegacyValue)
        XCTAssertEqual(try adapter.readCanonicalValue(for: haptic), disabledBytes)
        XCTAssertNil(defaults.object(forKey: "legacy.haptics"))
        XCTAssertEqual(try adapter.migrate(
            descriptor: haptic,
            legacyKeys: ["legacy.haptics"],
            operationID: Self.uuid(32)
        ), migrated)
        defaults.set(disabledBytes, forKey: "legacy.haptics")
        XCTAssertEqual(try adapter.migrate(
            descriptor: haptic,
            legacyKeys: ["legacy.haptics"],
            operationID: Self.uuid(32)
        ), migrated)
        XCTAssertNil(defaults.object(forKey: "legacy.haptics"))
        defaults.set(try CompatibilityCanonicalV1.encode(true), forKey: "legacy.haptics")
        XCTAssertThrowsError(try adapter.migrate(
            descriptor: haptic,
            legacyKeys: ["legacy.haptics"],
            operationID: Self.uuid(32)
        )) { XCTAssertEqual($0 as? PreferencesAdapterFailureV1, .conflictingOperation) }
        defaults.removeObject(forKey: "legacy.haptics")
        let writeID = UUID(uuidString: "91400000-0000-0000-0000-000000000002")!
        try adapter.writeCanonicalValue(disabledBytes, descriptor: haptic, operationID: writeID)
        try adapter.writeCanonicalValue(disabledBytes, descriptor: haptic, operationID: writeID)
        XCTAssertThrowsError(try adapter.writeCanonicalValue(
            haptic.defaultCanonicalValue,
            descriptor: haptic,
            operationID: writeID
        )) { XCTAssertEqual($0 as? PreferencesAdapterFailureV1, .conflictingOperation) }
        try adapter.writeCanonicalValue(
            haptic.defaultCanonicalValue,
            descriptor: haptic,
            operationID: Self.uuid(34)
        )
        XCTAssertEqual(
            try adapter.readCanonicalValue(for: haptic),
            haptic.defaultCanonicalValue
        )
        XCTAssertThrowsError(try adapter.migrate(
            descriptor: haptic,
            legacyKeys: ["legacy.haptics"],
            operationID: Self.uuid(32)
        )) { XCTAssertEqual($0 as? PreferencesAdapterFailureV1, .conflictingOperation) }
        try adapter.reset(descriptors: registry.descriptors, operationID: Self.uuid(3))
        XCTAssertEqual(try adapter.readCanonicalValue(for: haptic), haptic.defaultCanonicalValue)
        try adapter.writeCanonicalValue(
            disabledBytes,
            descriptor: haptic,
            operationID: Self.uuid(4)
        )
        try adapter.erase(descriptors: registry.descriptors, operationID: Self.uuid(5))
        XCTAssertEqual(try adapter.readCanonicalValue(for: haptic), haptic.defaultCanonicalValue)
        let persistedKeys = defaults.persistentDomain(forName: suiteName)
            .map { Array($0.keys) } ?? []
        XCTAssertTrue(persistedKeys.allSatisfy {
            $0.hasPrefix(PreferencesAdapterV1.storagePrefix)
        })

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data([0xFF]), forKey: "legacy.haptics")
        let repaired = try adapter.migrate(
            descriptor: haptic,
            legacyKeys: ["legacy.haptics"],
            operationID: Self.uuid(33)
        )
        XCTAssertEqual(repaired.disposition, .replacedInvalidLegacyWithDefault)
        XCTAssertEqual(try adapter.readCanonicalValue(for: haptic), haptic.defaultCanonicalValue)
        for operation in SettingsLifecycleOperationV1.allCases {
            for descriptor in complete.descriptors {
                _ = descriptor.lifecycleDisposition(for: operation)
            }
            let receipt = try SettingsLifecycleReceiptV1(
                operationID: UUID(uuidString: "91400000-0000-0000-0000-000000000001")!,
                operation: operation,
                affectedKeys: registry.descriptors.map(\.key),
                preservedWorkspaceCanonicalTruth: ![.erase, .delete].contains(operation)
            )
            XCTAssertEqual(receipt.affectedKeys, corpus.settingKeys)
            XCTAssertEqual(
                try CompatibilityCanonicalV1.decode(
                    SettingsLifecycleReceiptV1.self,
                    from: CompatibilityCanonicalV1.encode(receipt)
                ),
                receipt
            )
        }
    }

    func testV9_14A01AvailabilityReasonsPreserveHistoricEssentialOperations() throws {
        let corpus = try Self.loadCorpus()
        let policy = FeatureAvailabilityPolicyV1()
        XCTAssertEqual(
            corpus.availabilityScenarios.map(\.reason),
            FeatureAvailabilityReasonV1.allCases.map(\.rawValue).sorted()
        )
        XCTAssertEqual(corpus.availabilityReasons, corpus.availabilityScenarios.map(\.reason))
        XCTAssertEqual(
            corpus.essentialOperations,
            EssentialOperationV1.allCases.map(\.rawValue).sorted()
        )
        for scenario in corpus.availabilityScenarios {
            let reason = try XCTUnwrap(FeatureAvailabilityReasonV1(rawValue: scenario.reason))
            let permission = try XCTUnwrap(CapabilityPermissionStateV1(rawValue: scenario.permission))
            let expectedAction = try XCTUnwrap(
                FeatureAvailabilityNextActionV1(rawValue: scenario.nextAction)
            )
            let decision = policy.evaluate(
                FeatureAvailabilityInputsV1(
                    packageEnabled: scenario.packageEnabled,
                    entitled: scenario.entitled,
                    osAndDeviceSupported: scenario.osAndDeviceSupported,
                    permission: permission,
                    offlineContentAvailable: scenario.offlineContentAvailable,
                    recoveryReady: scenario.recoveryReady,
                    workspacePolicyEnabled: scenario.workspacePolicyEnabled,
                    packageRetired: scenario.packageRetired,
                    temporarilyAvailable: scenario.temporarilyAvailable
                ),
                manualFallbackCapabilityID: .filesAndShare
            )
            XCTAssertEqual(decision.reason, reason)
            XCTAssertEqual(decision.nextAction, expectedAction)
            XCTAssertEqual(decision.mayStartNewOperation, reason == .available)
            XCTAssertTrue(decision.preservesEssentialOperations)
            for operation in EssentialOperationV1.allCases {
                XCTAssertNoThrow(try policy.requireEssentialOperationVisible(operation, decision: decision))
            }
            let receipt = try TypedAvailabilityAndFallbackReceiptV1(
                candidateHead: "1c8b3d99826a207d3b18b3e0429231c31804f317",
                candidateTree: "3107903158238e5e5eaed78322c3564b06c648e2",
                providerID: "SYSTEM_CAPABILITY_ADAPTER",
                providerSliceDigest: "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6",
                consumerID: "CHECK_RUNNER",
                capabilityID: .filesAndShare,
                availabilityReason: reason,
                mandatoryCoreComplete: true,
                visibleFallback: reason == .available ? .noFallback : .saveLocally,
                persistenceDisposition: .noCanonicalEffectUntilAcceptance,
                dataDisposition: .priorHistoryPreserved,
                reentryTrigger: .capabilityStateChanged,
                localizedVisibleStateKey: "availability.\(reason.rawValue).state",
                localizedVisibleCopyKey: "availability.\(reason.rawValue).copy",
                localizedNextActionKey: "availability.\(reason.rawValue).action",
                fallbackTestArtifactIDs: ["V23-P02-C10-A01-FALLBACK"],
                evidenceArtifactIDs: ["V23-P02-C10-A01-RECEIPT"],
                zeroUnsupportedPublicClaim: true
            )
            try receipt.validate()
            XCTAssertEqual(
                try CompatibilityCanonicalV1.decode(
                    TypedAvailabilityAndFallbackReceiptV1.self,
                    from: CompatibilityCanonicalV1.encode(receipt)
                ),
                receipt
            )
            XCTAssertEqual(receipt.candidateHead, "1c8b3d99826a207d3b18b3e0429231c31804f317")
            XCTAssertEqual(receipt.availabilityReason, reason)
        }
        XCTAssertThrowsError(try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: "1c8b3d99826a207d3b18b3e0429231c31804f317",
            candidateTree: "3107903158238e5e5eaed78322c3564b06c648e2",
            providerID: "SYSTEM_CAPABILITY_ADAPTER",
            providerSliceDigest: "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6",
            consumerID: "CHECK_RUNNER",
            capabilityID: .camera,
            availabilityReason: .permissionDenied,
            mandatoryCoreComplete: true,
            visibleFallback: .chooseExistingPhoto,
            persistenceDisposition: .noCanonicalEffectUntilAcceptance,
            dataDisposition: .priorHistoryPreserved,
            reentryTrigger: .permissionChanged,
            localizedVisibleStateKey: "availability.permissionDenied.state",
            localizedVisibleCopyKey: "availability.permissionDenied.copy",
            localizedNextActionKey: "availability.permissionDenied.action",
            fallbackTestArtifactIDs: [],
            evidenceArtifactIDs: ["V23-P02-C10-A01-RECEIPT"],
            zeroUnsupportedPublicClaim: true
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidValue) }
        XCTAssertThrowsError(try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: "1c8b3d99826a207d3b18b3e0429231c31804f317",
            candidateTree: "3107903158238e5e5eaed78322c3564b06c648e2",
            providerID: "SYSTEM_CAPABILITY_ADAPTER",
            providerSliceDigest: "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6",
            consumerID: "CHECK_RUNNER",
            capabilityID: .camera,
            availabilityReason: .available,
            mandatoryCoreComplete: true,
            visibleFallback: .chooseExistingPhoto,
            persistenceDisposition: .noCanonicalEffectUntilAcceptance,
            dataDisposition: .priorHistoryPreserved,
            reentryTrigger: .permissionChanged,
            localizedVisibleStateKey: "availability.available.state",
            localizedVisibleCopyKey: "availability.available.copy",
            localizedNextActionKey: "availability.available.action",
            fallbackTestArtifactIDs: ["V23-P02-C10-H01-FALLBACK"],
            evidenceArtifactIDs: ["V23-P02-C10-H01"],
            zeroUnsupportedPublicClaim: true
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidValue) }
        let unavailableHaptics = try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: "1c8b3d99826a207d3b18b3e0429231c31804f317",
            candidateTree: "3107903158238e5e5eaed78322c3564b06c648e2",
            providerID: "SYSTEM_CAPABILITY_ADAPTER",
            providerSliceDigest: "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6",
            consumerID: "CHECK_RUNNER",
            capabilityID: .haptics,
            availabilityReason: .temporarilyUnavailable,
            mandatoryCoreComplete: true,
            visibleFallback: .noFallback,
            persistenceDisposition: .deviceLocalOnly,
            dataDisposition: .priorHistoryPreserved,
            reentryTrigger: .capabilityStateChanged,
            localizedVisibleStateKey: "availability.haptics.state",
            localizedVisibleCopyKey: "availability.haptics.copy",
            localizedNextActionKey: "availability.haptics.action",
            fallbackTestArtifactIDs: ["V23-P02-C10-H01-HAPTICS"],
            evidenceArtifactIDs: ["V23-P02-C10-H01"],
            zeroUnsupportedPublicClaim: true
        )
        XCTAssertEqual(unavailableHaptics.visibleFallback, .noFallback)
        XCTAssertThrowsError(try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: "1c8b3d99826a207d3b18b3e0429231c31804f317",
            candidateTree: "3107903158238e5e5eaed78322c3564b06c648e2",
            providerID: "SYSTEM_CAPABILITY_ADAPTER",
            providerSliceDigest: "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6",
            consumerID: "CHECK_RUNNER",
            capabilityID: .camera,
            availabilityReason: .permissionDenied,
            mandatoryCoreComplete: true,
            visibleFallback: .noFallback,
            persistenceDisposition: .noCanonicalEffectUntilAcceptance,
            dataDisposition: .priorHistoryPreserved,
            reentryTrigger: .permissionChanged,
            localizedVisibleStateKey: "availability.camera.state",
            localizedVisibleCopyKey: "availability.camera.copy",
            localizedNextActionKey: "availability.camera.action",
            fallbackTestArtifactIDs: ["V23-P02-C10-H01-CAMERA"],
            evidenceArtifactIDs: ["V23-P02-C10-H01"],
            zeroUnsupportedPublicClaim: true
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidValue) }
        let entitlementLapse = try XCTUnwrap(corpus.availabilityScenarios.first {
            $0.reason == FeatureAvailabilityReasonV1.notEntitled.rawValue
        })
        XCTAssertFalse(entitlementLapse.entitled)
        XCTAssertTrue(corpus.essentialOperations.contains(EssentialOperationV1.priorRead.rawValue))
        XCTAssertTrue(corpus.essentialOperations.contains(EssentialOperationV1.erase.rawValue))
    }

    func testV9_14H01CapabilityPermissionsConsentFallbackAndScratchAreClosed() async throws {
        let corpus = try Self.loadCorpus()
        let matrix = try CapabilityPermissionMatrixV1.current()
        let fallback = PermissionFallbackRegistryV1(matrix: matrix)
        XCTAssertEqual(matrix.descriptors.map(\.capabilityID.rawValue), corpus.capabilityIDs)
        XCTAssertEqual(
            CapabilityPermissionStateV1.allCases.map(\.rawValue).sorted(),
            corpus.permissionStates
        )
        for descriptor in matrix.descriptors {
            XCTAssertFalse(descriptor.platformAPI.isEmpty)
            XCTAssertFalse(descriptor.privacyDisclosureKey.isEmpty)
            XCTAssertEqual(
                descriptor.requestTiming,
                [.notifications, .camera, .speechDictation, .microphone, .audioCapture,
                 .videoCapture, .location, .reminders].contains(descriptor.capabilityID)
                    ? .explicitUserInitiatedFeatureBoundary : .neverRequested
            )
            for permission in CapabilityPermissionStateV1.allCases {
                let action = try fallback.fallback(
                    for: descriptor.capabilityID,
                    permission: permission
                )
                if permission == .authorized || permission == .notRequired {
                    XCTAssertEqual(action, .noFallback)
                } else {
                    XCTAssertEqual(action, descriptor.manualFallback)
                }
            }
        }
        XCTAssertThrowsError(try CapabilityPermissionMatrixV1(
            descriptors: Array(matrix.descriptors.dropFirst())
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .duplicateCapability) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let counter = V914PermissionCounter()
        var probes: [CapabilityIDV1: SystemCapabilityRuntimeAdapterV1.StateProbe] = [:]
        var requesters: [CapabilityIDV1: SystemCapabilityRuntimeAdapterV1.PermissionRequester] = [:]
        for descriptor in matrix.descriptors {
            let capabilityID = descriptor.capabilityID
            let probedState = try CapabilityStateV1(
                capabilityID: capabilityID,
                permission: descriptor.requestTiming == .neverRequested
                    ? .notRequired : .notDetermined,
                runtime: .available,
                observedAt: now
            )
            probes[capabilityID] = { probedState }
            if descriptor.requestTiming == .explicitUserInitiatedFeatureBoundary {
                requesters[capabilityID] = {
                    await counter.record(capabilityID)
                    return try CapabilityStateV1(
                        capabilityID: capabilityID,
                        permission: .authorized,
                        runtime: .available,
                        observedAt: now
                    )
                }
            }
        }
        let runtime = try SystemCapabilityRuntimeAdapterV1(
            probes: probes,
            requesters: requesters
        )
        for (descriptorIndex, descriptor) in matrix.descriptors.enumerated() {
            let before = try await runtime.state(for: descriptor.capabilityID)
            if descriptor.requestTiming == .neverRequested {
                XCTAssertEqual(before.permission, .notRequired)
            } else {
                XCTAssertEqual(before.permission, .notDetermined)
                let boundary = try PermissionRequestBoundaryV1(
                    operationID: Self.uuid(20 + descriptorIndex),
                    capabilityID: descriptor.capabilityID,
                    trigger: .explicitUserInitiatedFeatureBoundary,
                    userInitiatedAt: now
                )
                let after = try await runtime.requestPermission(
                    for: descriptor.capabilityID,
                    boundary: boundary
                )
                XCTAssertEqual(after.permission, .authorized)
            }
        }
        let requestedCapabilityIDs = await counter.requestedCapabilityIDs()
        XCTAssertEqual(
            requestedCapabilityIDs,
            Set(matrix.descriptors.filter {
                $0.requestTiming == .explicitUserInitiatedFeatureBoundary
            }.map(\.capabilityID))
        )
        do {
            _ = try await runtime.requestPermission(
                for: .camera,
                boundary: PermissionRequestBoundaryV1(
                    operationID: Self.uuid(40),
                    capabilityID: .microphone,
                    trigger: .explicitUserInitiatedFeatureBoundary,
                    userInitiatedAt: now
                )
            )
            XCTFail("mismatched permission boundary unexpectedly requested")
        } catch {
            XCTAssertEqual(error as? CapabilityContractFailureV1, .permissionRequestNotUserInitiated)
        }
        XCTAssertThrowsError(try PermissionRequestBoundaryV1(
            operationID: SettingsValidationV1.zeroUUID,
            capabilityID: .camera,
            trigger: .explicitUserInitiatedFeatureBoundary,
            userInitiatedAt: now
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .permissionRequestNotUserInitiated) }
        do {
            _ = try await runtime.requestPermission(
                for: .haptics,
                boundary: PermissionRequestBoundaryV1(
                    operationID: Self.uuid(41),
                    capabilityID: .haptics,
                    trigger: .explicitUserInitiatedFeatureBoundary,
                    userInitiatedAt: now
                )
            )
            XCTFail("capability with no permission request path unexpectedly prompted")
        } catch {
            XCTAssertEqual(error as? CapabilityContractFailureV1, .permissionRequestNotUserInitiated)
        }

        let state = try CapabilityStateV1(
            capabilityID: .camera,
            permission: .authorized,
            runtime: .available,
            observedAt: now
        )
        XCTAssertThrowsError(try CapabilityUseReceiptV1(
            operationID: UUID(uuidString: "91400000-0000-0000-0000-000000000010")!,
            capabilityID: .camera,
            state: state,
            userInitiated: false,
            explicitConsent: true,
            fallbackUsed: nil,
            createdCanonicalEffect: true
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidValue) }
        let revokedState = try CapabilityStateV1(
            capabilityID: .camera,
            permission: .denied,
            runtime: .interrupted,
            observedAt: now
        )
        let revoked = try CapabilityUseReceiptV1(
            operationID: Self.uuid(42),
            capabilityID: .camera,
            state: revokedState,
            userInitiated: true,
            explicitConsent: true,
            fallbackUsed: .chooseExistingPhoto,
            createdCanonicalEffect: false
        )
        XCTAssertFalse(revoked.createdCanonicalEffect)
        XCTAssertEqual(revoked.fallbackUsed, .chooseExistingPhoto)
        XCTAssertThrowsError(try CapabilityUseReceiptV1(
            operationID: Self.uuid(43),
            capabilityID: .camera,
            state: revokedState,
            userInitiated: true,
            explicitConsent: true,
            fallbackUsed: .chooseExistingPhoto,
            createdCanonicalEffect: true
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidValue) }

        XCTAssertEqual(ActiveCaptureKindV1.allCases.map(\.rawValue).sorted(), corpus.captureKinds)
        for (kindIndex, kind) in ActiveCaptureKindV1.allCases.enumerated() {
            let phases: [(ActiveCapturePhaseV1, Bool, Bool)] = [
                (.awaitingExplicitConsent, false, false),
                (.consentedNotCapturing, true, false),
                (.capturingIndicatorVisible, true, true),
                (.stopped, true, false),
                (.interrupted, true, false),
            ]
            for (phaseIndex, phaseRow) in phases.enumerated() {
                let (phase, consent, indicator) = phaseRow
                let value = try ActiveCapturePresentationContractV1(
                    captureID: Self.uuid(50 + kindIndex * 10 + phaseIndex),
                    kind: kind,
                    phase: phase,
                    explicitConsentRecorded: consent,
                    indicatorVisibleOrAudible: indicator,
                    indicatorAccessibilityLabelKey: indicator
                        ? "capture.\(kind.rawValue).active" : nil,
                    indicatorPersistsAcrossSceneInactivity: indicator
                )
                XCTAssertEqual(value.indicatorVisibleOrAudible, phase == .capturingIndicatorVisible)
            }
            let active = try ActiveCapturePresentationContractV1(
                captureID: UUID(uuidString: "91400000-0000-0000-0000-000000000011")!,
                kind: kind,
                phase: .capturingIndicatorVisible,
                explicitConsentRecorded: true,
                indicatorVisibleOrAudible: true,
                indicatorAccessibilityLabelKey: "capture.\(kind.rawValue).active",
                indicatorPersistsAcrossSceneInactivity: true
            )
            XCTAssertTrue(active.indicatorVisibleOrAudible)
            XCTAssertEqual(
                try CompatibilityCanonicalV1.decode(
                    ActiveCapturePresentationContractV1.self,
                    from: CompatibilityCanonicalV1.encode(active)
                ),
                active
            )
            XCTAssertThrowsError(try ActiveCapturePresentationContractV1(
                captureID: active.captureID,
                kind: kind,
                phase: .capturingIndicatorVisible,
                explicitConsentRecorded: false,
                indicatorVisibleOrAudible: true,
                indicatorAccessibilityLabelKey: "capture.\(kind.rawValue).active",
                indicatorPersistsAcrossSceneInactivity: true
            )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidCaptureTransition) }
            XCTAssertThrowsError(try ActiveCapturePresentationContractV1(
                captureID: active.captureID,
                kind: kind,
                phase: .awaitingExplicitConsent,
                explicitConsentRecorded: true,
                indicatorVisibleOrAudible: false,
                indicatorAccessibilityLabelKey: nil,
                indicatorPersistsAcrossSceneInactivity: false
            )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidCaptureTransition) }
            XCTAssertThrowsError(try ActiveCapturePresentationContractV1(
                captureID: active.captureID,
                kind: kind,
                phase: .stopped,
                explicitConsentRecorded: false,
                indicatorVisibleOrAudible: false,
                indicatorAccessibilityLabelKey: nil,
                indicatorPersistsAcrossSceneInactivity: false
            )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidCaptureTransition) }
            XCTAssertThrowsError(try ActiveCapturePresentationContractV1(
                captureID: active.captureID,
                kind: kind,
                phase: .stopped,
                explicitConsentRecorded: true,
                indicatorVisibleOrAudible: true,
                indicatorAccessibilityLabelKey: nil,
                indicatorPersistsAcrossSceneInactivity: false
            )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidCaptureTransition) }
            let sequenceID = Self.uuid(500 + kindIndex)
            let awaiting = try ActiveCapturePresentationContractV1(
                captureID: sequenceID,
                kind: kind,
                phase: .awaitingExplicitConsent,
                explicitConsentRecorded: false,
                indicatorVisibleOrAudible: false,
                indicatorAccessibilityLabelKey: nil,
                indicatorPersistsAcrossSceneInactivity: false
            )
            let consented = try ActiveCapturePresentationContractV1(
                captureID: sequenceID,
                kind: kind,
                phase: .consentedNotCapturing,
                explicitConsentRecorded: true,
                indicatorVisibleOrAudible: false,
                indicatorAccessibilityLabelKey: nil,
                indicatorPersistsAcrossSceneInactivity: false
            )
            let capturing = try ActiveCapturePresentationContractV1(
                captureID: sequenceID,
                kind: kind,
                phase: .capturingIndicatorVisible,
                explicitConsentRecorded: true,
                indicatorVisibleOrAudible: true,
                indicatorAccessibilityLabelKey: "capture.\(kind.rawValue).active",
                indicatorPersistsAcrossSceneInactivity: true
            )
            let stopped = try ActiveCapturePresentationContractV1(
                captureID: sequenceID,
                kind: kind,
                phase: .stopped,
                explicitConsentRecorded: true,
                indicatorVisibleOrAudible: false,
                indicatorAccessibilityLabelKey: nil,
                indicatorPersistsAcrossSceneInactivity: false
            )
            XCTAssertEqual(try awaiting.transition(to: consented), consented)
            XCTAssertEqual(try consented.transition(to: capturing), capturing)
            XCTAssertEqual(try capturing.transition(to: stopped), stopped)
            XCTAssertThrowsError(try capturing.transition(to: consented)) {
                XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidCaptureTransition)
            }
        }

        let digest = String(repeating: "a", count: 64)
        for raw in corpus.scratchTerminalDispositions {
            let disposition = try XCTUnwrap(ScratchPublicationDispositionV1(rawValue: raw))
            let accepted = disposition == .acceptedIntoImmutableContent
            let receipt = try ScratchPublicationLinkageReceiptV1(
                operationID: UUID(uuidString: "91400000-0000-0000-0000-000000000012")!,
                leaseID: UUID(uuidString: "91400000-0000-0000-0000-000000000013")!,
                purpose: .capture,
                disposition: disposition,
                immutableContentReceiptDigest: accepted ? digest : nil,
                scratchDeleted: true
            )
            XCTAssertEqual(receipt.immutableContentReceiptDigest != nil, accepted)
            XCTAssertTrue(receipt.scratchDeleted)
        }
        XCTAssertThrowsError(try ScratchPublicationLinkageReceiptV1(
            operationID: UUID(uuidString: "91400000-0000-0000-0000-000000000012")!,
            leaseID: UUID(uuidString: "91400000-0000-0000-0000-000000000013")!,
            purpose: .source,
            disposition: .acceptedIntoImmutableContent,
            immutableContentReceiptDigest: nil,
            scratchDeleted: false
        )) { XCTAssertEqual($0 as? CapabilityContractFailureV1, .invalidScratchLinkage) }
        XCTAssertEqual(Set(corpus.scratchSourcePurposes), Set(["CAPTURE", "IMPORT", "SOURCE"]))
        XCTAssertFalse(corpus.scratchSourcePurposes.contains("SUPPORT_EXPORT"))

        let provider = BundleFeaturePolicyDataProviderV1(bundle: .main)
        let policyBytes = try provider.canonicalFeaturePolicyData()
        let policyDigest = try provider.buildArtifactDigest()
        let featureRegistry = try FeaturePolicyLoaderV1(
            provider: BundleFeaturePolicyDataProviderV1(
                bundle: .main,
                expectedDigest: policyDigest
            )
        ).load()
        XCTAssertEqual(featureRegistry.features.map(\.featureID), corpus.featureIDs)
        let loader = FeaturePolicyLoaderV1(provider: provider)
        for feature in featureRegistry.features {
            let resolution = try loader.resolve(featureID: feature.featureID)
            XCTAssertEqual(resolution.policyState, feature.state)
            XCTAssertEqual(resolution.requiredPackageIDs, feature.requiredPackageIDs)
            XCTAssertEqual(resolution.requiredCapabilities, feature.requiredCapabilities)
            XCTAssertEqual(resolution.minimumPlatformMajorVersion, feature.minimumPlatformMajorVersion)
            XCTAssertEqual(resolution.safeFallback, feature.safeFallback)
        }
        let policyText = try XCTUnwrap(String(data: policyBytes, encoding: .utf8)).lowercased()
        for forbidden in ["remote", "co" + "hort", "account", "server", "ttl", "url"] {
            XCTAssertFalse(policyText.contains("\"\(forbidden)"))
        }
        XCTAssertThrowsError(try FeaturePolicyLoaderV1(
            provider: V914FeaturePolicyProvider(data: policyBytes + Data(" ".utf8))
        ).load()) { XCTAssertEqual($0 as? FeaturePolicyLoaderFailureV1, .noncanonicalResource) }
        XCTAssertThrowsError(try FeaturePolicyLoaderV1(
            provider: V914FeaturePolicyProvider(error: .missingResource)
        ).load()) { XCTAssertEqual($0 as? FeaturePolicyLoaderFailureV1, .missingResource) }
        XCTAssertThrowsError(try FeaturePolicyLoaderV1(
            provider: V914FeaturePolicyProvider(error: .duplicateResource)
        ).load()) { XCTAssertEqual($0 as? FeaturePolicyLoaderFailureV1, .duplicateResource) }
        XCTAssertThrowsError(try FeaturePolicyLoaderV1(
            provider: V914FeaturePolicyProvider(data: Data("{}".utf8))
        ).load()) { XCTAssertEqual($0 as? FeaturePolicyLoaderFailureV1, .malformedResource) }
        XCTAssertThrowsError(try loader.resolve(featureID: "unknownFeature")) {
            XCTAssertEqual($0 as? CapabilityContractFailureV1, .unknownFeature)
        }
        XCTAssertEqual(
            featureRegistry.features.filter { $0.state == .preparedDisabled }.count,
            3
        )
        XCTAssertEqual(
            Set(corpus.scratchExcludedConsumers),
            Set(["BACKUP", "DIAGNOSTICS", "REPORT", "SEARCH", "SUPPORT_EXPORT"])
        )
        let isolation = ScratchIsolationPolicyV1()
        for purpose in [CapabilityScratchPurposeV1.capture, .importData, .source] {
            XCTAssertTrue(isolation.mayExpose(
                purpose: purpose,
                to: .canonicalContentAcceptance
            ))
            for consumer in [ScratchDataConsumerV1.backup, .diagnostics, .report, .search, .supportExport] {
                XCTAssertFalse(isolation.mayExpose(purpose: purpose, to: consumer))
            }
        }
        XCTAssertTrue(isolation.mayExpose(purpose: .supportExport, to: .supportExport))
        XCTAssertEqual(corpus.hostileCases.count, 16)
        XCTAssertEqual(Set(corpus.hostileCases).count, corpus.hostileCases.count)
    }

    func testV9_14I01InterruptionRecoveryIsIdempotentAndCreatesNoCanonicalLeak() async throws {
        let corpus = try Self.loadCorpus()
        XCTAssertEqual(Set(corpus.interruptionBoundaries), Set([
            "BEFORE_SCRATCH_STAGING",
            "AFTER_SCRATCH_STAGING_BEFORE_ACCEPTANCE",
            "BEFORE_CANONICAL_PUBLICATION",
            "AFTER_CANONICAL_EFFECT_BEFORE_RECEIPT",
            "DURING_SUPPORT_EXPORT",
        ]))
        XCTAssertEqual(Set(corpus.scratchFaultEvents), Set([
            "ACCEPT", "REJECT", "CANCEL", "EXPIRY", "CRASH_RECOVERY",
            "PROTECTED_DATA_LOSS", "FAILED_PUBLICATION",
        ]))

        let interruptedState = try CapabilityStateV1(
            capabilityID: .videoCapture,
            permission: .authorized,
            runtime: .interrupted,
            observedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let interrupted = try CapabilityUseReceiptV1(
            operationID: UUID(uuidString: "91400000-0000-0000-0000-000000000020")!,
            capabilityID: .videoCapture,
            state: interruptedState,
            userInitiated: true,
            explicitConsent: true,
            fallbackUsed: .chooseExistingPhoto,
            createdCanonicalEffect: false
        )
        XCTAssertFalse(interrupted.createdCanonicalEffect)
        XCTAssertEqual(interrupted.fallbackUsed, .chooseExistingPhoto)

        let workspaceDescriptor = try SettingDescriptorV1(
            key: "workspace.displayMode",
            valueKind: .boundedString,
            scope: .workspaceCanonical,
            storage: .workspaceWriter,
            defaultCanonicalValue: try CompatibilityCanonicalV1.encode("STANDARD"),
            maximumCanonicalBytes: 32,
            migrationVersion: 1,
            backup: .canonicalWorkspaceBackup,
            reset: .preserveAcknowledgement,
            erase: .clearCanonical,
            privacy: .workspaceCanonical,
            localizationKey: "settings.workspace.displayMode"
        )
        let command = try WorkspaceSettingWriteCommandV1(
            workspaceID: UUID(uuidString: "91400000-0000-0000-0000-000000000021")!,
            descriptor: workspaceDescriptor,
            canonicalValue: try CompatibilityCanonicalV1.encode("STANDARD"),
            expectedRevision: 3,
            mutationID: UUID(uuidString: "91400000-0000-0000-0000-000000000022")!
        )
        let digest = CompatibilityCanonicalV1.sha256(command.canonicalValue)
        let original = try WorkspaceSettingWriteReceiptV1(
            mutationID: command.mutationID,
            workspaceID: command.workspaceID,
            key: command.key,
            resultingRevision: 4,
            canonicalValueDigest: digest,
            adoptedExistingEffect: false
        )
        let adopted = try WorkspaceSettingWriteReceiptV1(
            mutationID: command.mutationID,
            workspaceID: command.workspaceID,
            key: command.key,
            resultingRevision: original.resultingRevision,
            canonicalValueDigest: original.canonicalValueDigest,
            adoptedExistingEffect: true
        )
        XCTAssertEqual(original.canonicalValueDigest, adopted.canonicalValueDigest)
        XCTAssertEqual(original.resultingRevision, adopted.resultingRevision)
        XCTAssertTrue(adopted.adoptedExistingEffect)
        XCTAssertThrowsError(try WorkspaceSettingWriteCommandV1(
            workspaceID: command.workspaceID,
            descriptor: workspaceDescriptor,
            canonicalValue: try CompatibilityCanonicalV1.encode("CHANGED"),
            expectedRevision: command.expectedRevision,
            mutationID: SettingsValidationV1.zeroUUID
        )) { XCTAssertEqual($0 as? SettingsContractFailureV1, .invalidValue) }

        let scratch = V914ScratchSpy()
        let scratchAdapter = CapabilityScratchLeaseAdapterV1(scratch: scratch)
        let createdAt = Date(timeIntervalSince1970: 1_800_000_200)
        for (index, purpose) in [
            CapabilityScratchPurposeV1.capture,
            .importData,
            .source,
            .supportExport,
        ].enumerated() {
            let request = try CapabilityScratchLeaseRequestV1(
                leaseID: UUID(uuidString: String(
                    format: "91400000-0000-0000-0000-%012d", 100 + index
                ))!,
                operationID: UUID(uuidString: String(
                    format: "91400000-0000-0000-0000-%012d", 200 + index
                ))!,
                purpose: purpose,
                requestedByteCount: 64,
                createdAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(60)
            )
            let lease = try await scratchAdapter.acquire(request)
            _ = try await scratchAdapter.write(Data("synthetic".utf8), named: "input.bin", lease: lease)
            let dispositions: [ScratchPublicationDispositionV1] = [
                .acceptedIntoImmutableContent, .rejected, .expired, .cancelled,
            ]
            let disposition = dispositions[index]
            let receipt = try await scratchAdapter.finish(
                lease: lease,
                disposition: disposition,
                immutableContentReceiptDigest: disposition == .acceptedIntoImmutableContent
                    ? String(repeating: "b", count: 64) : nil
            )
            XCTAssertTrue(receipt.scratchDeleted)
            XCTAssertEqual(
                try CompatibilityCanonicalV1.decode(
                    ScratchPublicationLinkageReceiptV1.self,
                    from: CompatibilityCanonicalV1.encode(receipt)
                ),
                receipt
            )
            do {
                _ = try await scratchAdapter.finish(
                    lease: lease,
                    disposition: .failed,
                    immutableContentReceiptDigest: nil
                )
                XCTFail("terminal scratch replay unexpectedly succeeded")
            } catch {
                XCTAssertEqual(error as? CapabilityContractFailureV1, .invalidScratchLinkage)
            }
        }
        let mappedRequests = await scratch.requests()
        XCTAssertEqual(mappedRequests.count, 4)
        XCTAssertTrue(mappedRequests.allSatisfy {
            $0.protection == .complete && $0.backupPolicy == .excluded
        })
        XCTAssertEqual(
            Set(mappedRequests.map(\.purpose.rawValue)),
            Set(["CAPTURE", "IMPORT", "SOURCE", "SUPPORT_EXPORT"])
        )

        let failingRequest = try CapabilityScratchLeaseRequestV1(
            leaseID: UUID(uuidString: "91400000-0000-0000-0000-000000000300")!,
            operationID: UUID(uuidString: "91400000-0000-0000-0000-000000000301")!,
            purpose: .source,
            requestedByteCount: 64,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(60)
        )
        let failingLease = try await scratchAdapter.acquire(failingRequest)
        await scratch.failNextWrite()
        do {
            _ = try await scratchAdapter.write(
                Data("interrupted".utf8),
                named: "source.bin",
                lease: failingLease
            )
            XCTFail("injected staging interruption unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? V914InjectedFailure, .stagingInterrupted)
        }
        let failed = try await scratchAdapter.finish(
            lease: failingLease,
            disposition: .failed,
            immutableContentReceiptDigest: nil
        )
        XCTAssertTrue(failed.scratchDeleted)

        let recoveryRequest = try CapabilityScratchLeaseRequestV1(
            leaseID: UUID(uuidString: "91400000-0000-0000-0000-000000000302")!,
            operationID: UUID(uuidString: "91400000-0000-0000-0000-000000000303")!,
            purpose: .capture,
            requestedByteCount: 64,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(60)
        )
        let recoveryLease = try await scratchAdapter.acquire(recoveryRequest)
        _ = try await scratchAdapter.write(
            Data("accepted".utf8),
            named: "capture.bin",
            lease: recoveryLease
        )
        await scratch.failNextRelease()
        do {
            _ = try await scratchAdapter.finish(
                lease: recoveryLease,
                disposition: .acceptedIntoImmutableContent,
                immutableContentReceiptDigest: String(repeating: "c", count: 64)
            )
            XCTFail("injected effect-before-receipt interruption unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? V914InjectedFailure, .releaseInterrupted)
        }
        let recovered = try await scratchAdapter.finish(
            lease: recoveryLease,
            disposition: .acceptedIntoImmutableContent,
            immutableContentReceiptDigest: String(repeating: "c", count: 64)
        )
        XCTAssertTrue(recovered.scratchDeleted)
        XCTAssertNotNil(recovered.immutableContentReceiptDigest)
        let remainingLeaseCount = await scratch.activeLeaseCount()
        XCTAssertEqual(remainingLeaseCount, 0)
        let terminalEvents = await scratch.terminals()
        XCTAssertEqual(terminalEvents.filter { $0 == .completed }.count, 2)
        XCTAssertEqual(terminalEvents.filter { $0 == .cancelled }.count, 2)
        XCTAssertEqual(terminalEvents.filter { $0 == .recoveredExpired }.count, 1)
        XCTAssertEqual(terminalEvents.filter { $0 == .failed }.count, 1)

        let concurrentRequest = try CapabilityScratchLeaseRequestV1(
            leaseID: Self.uuid(700),
            operationID: Self.uuid(701),
            purpose: .source,
            requestedByteCount: 64,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(60)
        )
        let acquisitionResults = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        _ = try await scratchAdapter.acquire(concurrentRequest)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(acquisitionResults.filter { $0 }.count, 1)
        let recoverySummary = try await scratchAdapter.recoverAfterInterruption()
        XCTAssertEqual(recoverySummary.recoveredExpiredLeaseCount, 1)
        let activeAfterRecovery = await scratch.activeLeaseCount()
        XCTAssertEqual(activeAfterRecovery, 0)
    }

    func testV9_14R01HapticsAndEntryAssistRemainPrivateBoundedAndRecoverable() async throws {
        let corpus = try Self.loadCorpus()
        XCTAssertEqual(corpus.entryAssist.maximumVisiblePerField, EntryAssistPolicyV1.maximumSuggestionsPerField)
        XCTAssertEqual(corpus.entryAssist.maximumEntries, EntryAssistPolicyV1.maximumEntries)
        XCTAssertEqual(
            TimeInterval(corpus.entryAssist.retentionDays * 24 * 60 * 60),
            EntryAssistPolicyV1.retentionSeconds
        )

        let enabled = HapticFeedbackPreferenceV1.logicalDefault
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.effectiveEmission(runtimeAvailable: true, safeContext: true))
        XCTAssertFalse(enabled.effectiveEmission(runtimeAvailable: false, safeContext: true))
        XCTAssertFalse(enabled.effectiveEmission(runtimeAvailable: true, safeContext: false))
        XCTAssertFalse(HapticFeedbackPreferenceV1(isEnabled: false)
            .effectiveEmission(runtimeAvailable: true, safeContext: true))
        let unavailableRuntime = NoOpHapticRuntimeAdapterV1()
        let runtimeAvailable = await unavailableRuntime.isAvailable()
        XCTAssertFalse(runtimeAvailable)
        XCTAssertTrue(enabled.isEnabled)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let workspace = UUID(uuidString: "91400000-0000-0000-0000-000000000030")!
        var memory = try RecentInputMemoryV1()
        for index in 0..<(EntryAssistPolicyV1.maximumEntries + 2) {
            try memory.remember(try SuggestedInputV1(
                workspaceID: workspace,
                semanticFieldID: "surface.finish",
                kind: .optionID,
                valueID: "option:" + CompatibilityCanonicalV1.sha256(
                    Data("OPTION_\(index)".utf8)
                ),
                source: .reviewedRecentOption,
                packageReleaseID: "illuminated-sign-v1",
                expectedRevision: 9,
                lastAcceptedAt: now.addingTimeInterval(TimeInterval(index))
            ))
        }
        XCTAssertEqual(memory.entries.count, EntryAssistPolicyV1.maximumEntries)
        let allowed = Set(memory.entries.map(\.valueID))
        let context = SuggestionValidationContextV1(
            workspaceID: workspace,
            packageReleaseID: "illuminated-sign-v1",
            semanticFieldID: "surface.finish",
            currentRevision: 9,
            allowedValueIDs: allowed,
            isVisibleAndWritable: true,
            permissionAndAvailabilitySatisfied: true,
            now: now.addingTimeInterval(200)
        )
        XCTAssertEqual(memory.suggestions(context: context).count, 3)
        let first = try XCTUnwrap(memory.entries.first)
        XCTAssertEqual(first.privacy, .referenceOnlyNoRawCustomerData)
        XCTAssertEqual(
            EntryAssistPolicyV1().validate(first, context: context, forAcceptance: true),
            .validForExplicitAcceptance
        )
        let stale = SuggestionValidationContextV1(
            workspaceID: workspace,
            packageReleaseID: context.packageReleaseID,
            semanticFieldID: context.semanticFieldID,
            currentRevision: 10,
            allowedValueIDs: allowed,
            isVisibleAndWritable: true,
            permissionAndAvailabilitySatisfied: true,
            now: context.now
        )
        XCTAssertEqual(
            EntryAssistPolicyV1().validate(first, context: stale, forAcceptance: true),
            .staleRevision
        )
        let expired = SuggestionValidationContextV1(
            workspaceID: workspace,
            packageReleaseID: context.packageReleaseID,
            semanticFieldID: context.semanticFieldID,
            currentRevision: 9,
            allowedValueIDs: allowed,
            isVisibleAndWritable: true,
            permissionAndAvailabilitySatisfied: true,
            now: first.lastAcceptedAt.addingTimeInterval(EntryAssistPolicyV1.retentionSeconds + 1)
        )
        XCTAssertEqual(
            EntryAssistPolicyV1().validate(first, context: expired, forAcceptance: false),
            .expired
        )
        let unavailable = SuggestionValidationContextV1(
            workspaceID: workspace,
            packageReleaseID: context.packageReleaseID,
            semanticFieldID: context.semanticFieldID,
            currentRevision: context.currentRevision,
            allowedValueIDs: allowed,
            isVisibleAndWritable: true,
            permissionAndAvailabilitySatisfied: false,
            now: context.now
        )
        XCTAssertEqual(
            EntryAssistPolicyV1().validate(first, context: unavailable, forAcceptance: true),
            .permissionOrAvailabilityChanged
        )
        let canonicalMemory = try CompatibilityCanonicalV1.encode(memory)
        XCTAssertEqual(
            try CompatibilityCanonicalV1.decode(RecentInputMemoryV1.self, from: canonicalMemory),
            memory
        )
        XCTAssertThrowsError(try CompatibilityCanonicalV1.decode(
            RecentInputMemoryV1.self,
            from: Data("{\"entries\":[],\"schemaVersion\":2}".utf8)
        ))
        let canonicalText = try XCTUnwrap(String(data: canonicalMemory, encoding: .utf8))
        let firstReference = try XCTUnwrap(memory.entries.first?.valueID)
        let rawCustomerText = canonicalText.replacingOccurrences(
            of: firstReference,
            with: "option:rawcustomertext"
        )
        XCTAssertNotEqual(canonicalText, rawCustomerText)
        XCTAssertThrowsError(try CompatibilityCanonicalV1.decode(
            RecentInputMemoryV1.self,
            from: Data(rawCustomerText.utf8)
        ))
        let otherWorkspace = UUID(uuidString: "91400000-0000-0000-0000-000000000031")!
        try memory.remember(try SuggestedInputV1(
            workspaceID: otherWorkspace,
            semanticFieldID: "surface.finish",
            kind: .optionID,
            valueID: "option:" + CompatibilityCanonicalV1.sha256(Data("OPTION_OTHER".utf8)),
            source: .reviewedRecentOption,
            packageReleaseID: "illuminated-sign-v1",
            expectedRevision: 1,
            lastAcceptedAt: now.addingTimeInterval(300)
        ))
        memory.clear(workspaceID: workspace)
        XCTAssertEqual(memory.entries.count, 1)
        XCTAssertEqual(memory.entries.first?.workspaceID, otherWorkspace)
        XCTAssertThrowsError(try SuggestedInputV1(
            workspaceID: workspace,
            semanticFieldID: "surface.finish",
            kind: .optionID,
            valueID: "raw customer free text",
            source: .reviewedRecentOption,
            packageReleaseID: "illuminated-sign-v1",
            expectedRevision: 1,
            lastAcceptedAt: now
        )) { XCTAssertEqual($0 as? SettingsContractFailureV1, .invalidValue) }
        XCTAssertThrowsError(try SuggestedInputV1(
            workspaceID: workspace,
            semanticFieldID: "surface.finish",
            kind: .optionID,
            valueID: "option:JohnSmith",
            source: .reviewedRecentOption,
            packageReleaseID: "illuminated-sign-v1",
            expectedRevision: 1,
            lastAcceptedAt: now
        )) { XCTAssertEqual($0 as? SettingsContractFailureV1, .invalidValue) }
    }
}

private struct V914FeaturePolicyProvider: BundledFeaturePolicyDataPortV1 {
    private let data: Data?
    private let error: FeaturePolicyLoaderFailureV1?

    init(data: Data) {
        self.data = data
        error = nil
    }

    init(error: FeaturePolicyLoaderFailureV1) {
        data = nil
        self.error = error
    }

    func canonicalFeaturePolicyData() throws -> Data {
        if let error { throw error }
        guard let data else { throw FeaturePolicyLoaderFailureV1.missingResource }
        return data
    }

    func buildArtifactDigest() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalFeaturePolicyData())
    }
}

private enum V914InjectedFailure: Error, Equatable, Sendable {
    case stagingInterrupted
    case releaseInterrupted
}

private actor V914PermissionCounter {
    private var values: Set<CapabilityIDV1> = []

    func record(_ capabilityID: CapabilityIDV1) { values.insert(capabilityID) }
    func requestedCapabilityIDs() -> Set<CapabilityIDV1> { values }
}

private actor V914ScratchSpy: ScratchDataLeasePortV1 {
    private var recordedRequests: [ScratchDataLeaseRequestV1] = []
    private var active: [UUID: ScratchDataLeaseV1] = [:]
    private var terminalEvents: [ScratchDataLeaseTerminalV1] = []
    private var shouldFailNextWrite = false
    private var shouldFailNextRelease = false

    func acquireScratchLease(
        _ request: ScratchDataLeaseRequestV1
    ) async throws -> ScratchDataLeaseV1 {
        try request.validate()
        let lease = try ScratchDataLeaseV1(
            request: request,
            relativeDirectory: "lease-" + request.leaseID.uuidString.lowercased()
        )
        recordedRequests.append(request)
        active[request.leaseID] = lease
        return lease
    }

    func writeScratchData(
        _ data: Data,
        named: String,
        lease: ScratchDataLeaseV1
    ) async throws -> URL {
        guard active[lease.request.leaseID] == lease, !data.isEmpty, !named.isEmpty else {
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
        if shouldFailNextWrite {
            shouldFailNextWrite = false
            throw V914InjectedFailure.stagingInterrupted
        }
        return URL(fileURLWithPath: "/synthetic/" + lease.relativeDirectory)
            .appendingPathComponent(named)
    }

    func releaseScratchLease(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        if shouldFailNextRelease {
            shouldFailNextRelease = false
            throw V914InjectedFailure.releaseInterrupted
        }
        guard active.removeValue(forKey: lease.request.leaseID) != nil else {
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
        terminalEvents.append(terminal)
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        let count = active.count
        active.removeAll()
        return try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: count,
            removedByteCount: 0
        )
    }

    func resetScratchData() async throws { active.removeAll() }
    func eraseScratchData() async throws { active.removeAll() }
    func failNextWrite() { shouldFailNextWrite = true }
    func failNextRelease() { shouldFailNextRelease = true }
    func requests() -> [ScratchDataLeaseRequestV1] { recordedRequests }
    func terminals() -> [ScratchDataLeaseTerminalV1] { terminalEvents }
    func activeLeaseCount() -> Int { active.count }
}

private extension V9_14SettingsCapabilityLifecycleTests {
    nonisolated static func uuid(_ index: Int) -> UUID {
        UUID(uuid: (
            0x91, 0x40, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, UInt8(index / 256), UInt8(index % 256)
        ))
    }

    nonisolated static func loadCorpus() throws -> V914Corpus {
        let name = "V21P02C10SettingsCapabilityCorpusV1"
        let url = try XCTUnwrap(Bundle(for: V9_14SettingsCapabilityLifecycleTests.self)
            .url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(V914Corpus.self, from: Data(contentsOf: url))
    }
}

private struct V914Corpus: Decodable {
    let schemaVersion: Int
    let fixtureIdentity: String
    let authority: Authority
    let settingKeys: [String]
    let settingScopes: [String]
    let availabilityReasons: [String]
    let availabilityScenarios: [AvailabilityScenario]
    let essentialOperations: [String]
    let capabilityIDs: [String]
    let permissionStates: [String]
    let captureKinds: [String]
    let scratchSourcePurposes: [String]
    let scratchTerminalDispositions: [String]
    let scratchFaultEvents: [String]
    let scratchExcludedConsumers: [String]
    let featureIDs: [String]
    let entryAssist: EntryAssist
    let interruptionBoundaries: [String]
    let hostileCases: [String]

    struct Authority: Decodable {
        let cardID: String
        let contextDigest: String
        let pathFenceDigest: String
    }

    struct AvailabilityScenario: Decodable {
        let reason: String
        let nextAction: String
        let packageEnabled: Bool
        let entitled: Bool
        let osAndDeviceSupported: Bool
        let permission: String
        let offlineContentAvailable: Bool
        let recoveryReady: Bool
        let workspacePolicyEnabled: Bool
        let packageRetired: Bool
        let temporarilyAvailable: Bool
    }

    struct EntryAssist: Decodable {
        let maximumVisiblePerField: Int
        let maximumEntries: Int
        let retentionDays: Int
    }
}

extension V9_14SettingsCapabilityLifecycleTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
