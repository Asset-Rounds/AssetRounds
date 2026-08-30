import XCTest
@testable import FieldEvidenceApp

final class V9_56WorkResourceTests: XCTestCase {
    private let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "49000000-0000-0000-0000-000000000001")!)
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private let digest = String(repeating: "a", count: 64)

    func testG01ExactManualValuesAndFrozenPartReferenceAreCanonical() throws {
        XCTAssertEqual(try ManualDurationV1(minutes: 1).minutes, 1)
        XCTAssertEqual(try ManualDurationV1(minutes: 10_080).minutes, 10_080)
        XCTAssertThrowsError(try ManualDurationV1(minutes: 0))
        XCTAssertThrowsError(try ManualDurationV1(minutes: 10_081))

        let quantity = try ExactDecimalQuantityV1(mantissa: 1_250, scale: 3)
        XCTAssertEqual(quantity.mantissa, 1_250)
        XCTAssertEqual(quantity.scale, 3)
        XCTAssertThrowsError(try ExactDecimalQuantityV1(mantissa: 0, scale: 0))
        XCTAssertThrowsError(try ExactDecimalQuantityV1(mantissa: 1, scale: 4))

        XCTAssertEqual(try ExactMoneyAmountV1(mantissa: 12_34, currencyCode: "USD", minorUnitScale: 2).currencyCode, "USD")
        XCTAssertEqual(try ExactMoneyAmountV1(mantissa: 12, currencyCode: "JPY", minorUnitScale: 0).minorUnitScale, 0)
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "USD", minorUnitScale: 3))
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "usd", minorUnitScale: 2))

        let part = try LocalPartReferenceSnapshotV1(
            partID: UUID(uuidString: "49000000-0000-0000-0000-000000000010")!,
            partRevision: 7,
            partSHA256: digest,
            displayName: "Frozen conduit revision"
        )
        let line = try ManualMaterialLineV1(description: "Conduit", quantity: quantity, unit: "m", localPartReference: part)
        XCTAssertEqual(line.localPartReference, part)
        XCTAssertFalse(C49WorkResourceContractBoundaryV1.liveInventoryReference)
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertEqual(C49WorkResourceContractBoundaryV1.soleWriter, "WorkspaceWriterV1")
    }

    func testA01BothSubjectsAndAppendOnlySuccessorStates() throws {
        let initial = try makeEntry(kind: .workPacket)
        try initial.validate()
        let successor = try makeEntry(
            kind: .workPacket,
            disposition: .superseded,
            expectedRevision: initial.revision,
            revision: initial.revision + 1,
            supersedes: initial
        )
        try successor.validateSuccessor(of: initial)
        let voided = try makeEntry(
            kind: .workPacket,
            disposition: .voidedWithReason,
            voidReason: "Entered against the wrong subject",
            expectedRevision: initial.revision,
            revision: initial.revision + 1,
            supersedes: initial
        )
        try voided.validateSuccessor(of: initial)
        let reversed = try makeEntry(
            kind: .workPacket,
            disposition: .reversed,
            expectedRevision: initial.revision,
            revision: initial.revision + 1,
            supersedes: initial
        )
        try reversed.validateSuccessor(of: initial)
        XCTAssertEqual(Set(WorkResourceDispositionV1.allCases), [.active, .superseded, .voidedWithReason, .reversed])
        XCTAssertEqual(WorkResourceDispositionV1.active.rawValue, "ACTIVE")
        XCTAssertEqual(WorkResourceDispositionV1.voidedWithReason.rawValue, "VOIDED_WITH_REASON")
        XCTAssertEqual(Set(WorkResourceSubjectKindV1.allCases), [.workPacket, .correctiveWork])
        XCTAssertNotEqual(initial.entrySHA256, successor.entrySHA256)
    }

    func testH01BoundsDuplicatesRevisionAndEmptyEntryFailClosed() throws {
        let q = try ExactDecimalQuantityV1(mantissa: 1, scale: 0)
        let id = UUID(uuidString: "49000000-0000-0000-0000-000000000020")!
        let duplicate = try ManualMaterialLineV1(lineID: id, description: "Bolt", quantity: q)
        XCTAssertThrowsError(try makeEntry(materials: [duplicate, duplicate]))
        XCTAssertThrowsError(try makeEntry(duration: nil, materials: [], directCost: nil))
        XCTAssertThrowsError(try makeEntry(expectedRevision: 1, revision: 3, supersedes: try makeEntry()))
        XCTAssertThrowsError(try ManualMaterialLineV1(description: String(repeating: "x", count: 161), quantity: q))
        XCTAssertThrowsError(try DirectCostEntryV1(amount: ExactMoneyAmountV1(mantissa: 1, currencyCode: "USD", minorUnitScale: 2), note: String(repeating: "x", count: 1025)))
    }

    func testR01SnapshotAndCloneRebindPreserveFrozenManualTruth() throws {
        let source = try makeEntry(kind: .correctiveWork)
        let snapshot = try WorkResourceSnapshotV1(entry: source)
        XCTAssertEqual(snapshot.entry.entrySHA256, source.entrySHA256)
        XCTAssertEqual(snapshot.snapshotSHA256.count, 64)

        let target = WorkspaceID(rawValue: UUID(uuidString: "49000000-0000-0000-0000-000000000099")!)
        let rebound = try source.rebound(
            to: target,
            mappedSubject: try subject(workspaceID: target, kind: .correctiveWork),
            mappedActor: try actor(workspaceID: target),
            mappedSupersedesEntrySHA256: nil,
            mutationID: try MutationIDV1(rawValue: UUID(uuidString: "49000000-0000-0000-0000-000000000098")!)
        )
        XCTAssertEqual(rebound.workspaceID, target)
        XCTAssertEqual(rebound.materials, source.materials)
        XCTAssertEqual(rebound.directCost, source.directCost)
        XCTAssertNotEqual(rebound.entrySHA256, source.entrySHA256)
    }

    @MainActor
    func testV23P03C49I01EffectBeforeReceiptAndJournalInterruptionsRetryDeterministically() throws {
        XCTAssertEqual(C49WorkResourceRecoveryBoundaryV1.commandKind, .applyWorkResource)
        XCTAssertTrue(C49WorkResourceRecoveryBoundaryV1.effectBeforeReceiptRecoveryUsesCanonicalPostimage)
        XCTAssertTrue(C49WorkResourceRecoveryBoundaryV1.divergentSameMutationIsQuarantined)
        XCTAssertTrue(C49WorkResourceRecoveryBoundaryV1.noSecondCostLedger)

        XCTAssertEqual(
            MutationJournalFaultBoundaryV1.allCases,
            [.afterEffectBeforeReceipt, .afterReceiptBeforeSave, .afterSaveBeforeReturn]
        )
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let failOnce = MutationJournalFailureInjectionV1(failOnceAt: boundary)
            XCTAssertThrowsError(try failOnce.reach(boundary)) { error in
                XCTAssertEqual(error as? MutationJournalFailureV1, .injected(boundary))
            }
            XCTAssertNoThrow(try failOnce.reach(boundary), "retry must not inject the same interruption twice")
        }
    }

    func testV23P03C49I01ReplaceRestoreAndCloneForkRecoveryChainIsExplicit() {
        XCTAssertTrue(C49WorkResourceRestoreIdentityPolicyV1.preservesCanonicalBytes(.emptyInstall))
        XCTAssertTrue(C49WorkResourceRestoreIdentityPolicyV1.preservesCanonicalBytes(.replaceExisting))
        XCTAssertFalse(C49WorkResourceRestoreIdentityPolicyV1.preservesCanonicalBytes(.clone))
        XCTAssertFalse(C49WorkResourceRestoreIdentityPolicyV1.preservesCanonicalBytes(.fork))
        XCTAssertTrue(C49WorkResourceRestoreIdentityPolicyV1.requiresHistoricRebinding(.clone))
        XCTAssertTrue(C49WorkResourceRestoreIdentityPolicyV1.requiresHistoricRebinding(.fork))
        XCTAssertTrue(C49WorkResourceLifecycleBoundaryV1.backupRestoreCloneForkDeleteAndEraseAreExplicit)
        XCTAssertTrue(C49WorkResourceStreamingArchiveBoundaryV1.totalsSearchDraftsAndLiveStockAreExcluded)
    }

    func testV23P03C49H01CustomerSafeProjectionNeverLeaksInternalDirectCost() throws {
        let snapshot = try WorkResourceSnapshotV1(entry: makeEntry())
        let defaultProjection = try C49WorkResourceReportProjectionV1(
            workspaceID: workspaceID,
            snapshots: [snapshot],
            audience: .customerSafe
        )
        XCTAssertFalse(defaultProjection.directCostPreview.optedIn)
        XCTAssertFalse(defaultProjection.directCostPreview.included)
        XCTAssertTrue(defaultProjection.directCostPreview.totalsByCurrency.isEmpty)
        XCTAssertTrue(defaultProjection.directCostsAreInternalOnly)

        let explicitPreview = try C49WorkResourceReportProjectionV1(
            workspaceID: workspaceID,
            snapshots: [snapshot],
            audience: .customerSafe,
            includeDirectCostPreview: true
        )
        XCTAssertTrue(explicitPreview.directCostPreview.optedIn)
        XCTAssertFalse(explicitPreview.directCostPreview.included, "internal-only source cost must remain absent")
        XCTAssertTrue(explicitPreview.directCostPreview.totalsByCurrency.isEmpty)
    }

    func testV23P03C49H01CSVNeutralizesFormulaPrefixesAndCanonicalizesControls() {
        for hostile in ["=2+2", "+SUM(A1:A2)", "-1", "@cmd"] {
            XCTAssertEqual(C49FormulaSafeCSVV1.safeCell(hostile), "'" + hostile)
        }
        XCTAssertEqual(C49FormulaSafeCSVV1.safeCell("line1\r\nline2\rline3"), "line1\nline2\nline3")
        XCTAssertEqual(
            C49FormulaSafeCSVV1.encode(rows: [["=2+2", "tab\tvalue", "line1\rline2"]]),
            "\"'=2+2\",\"tab\tvalue\",\"line1\nline2\"\n"
        )
    }

    func testV23P03C49G01ExactIntegerAndMaterialCardinalityBoundaries() throws {
        XCTAssertEqual(try ExactDecimalQuantityV1(mantissa: Int64.max, scale: 3).mantissa, Int64.max)
        XCTAssertEqual(
            try ExactMoneyAmountV1(mantissa: Int64.max, currencyCode: "USD", minorUnitScale: 2).mantissa,
            Int64.max
        )
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 0, currencyCode: "USD", minorUnitScale: 2))
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: -1, currencyCode: "USD", minorUnitScale: 2))

        let fifty = try (0..<50).map { offset in
            try ManualMaterialLineV1(
                lineID: UUID(uuidString: String(format: "49000000-0000-0000-0000-%012d", offset + 100))!,
                description: "Material \(offset)",
                quantity: ExactDecimalQuantityV1(mantissa: 1, scale: 0)
            )
        }
        XCTAssertEqual(try makeEntry(duration: nil, materials: fifty, directCost: nil).materials.count, 50)
        XCTAssertThrowsError(try makeEntry(duration: nil, materials: fifty + [
            ManualMaterialLineV1(
                lineID: UUID(uuidString: "49000000-0000-0000-0000-000000000999")!,
                description: "Too many",
                quantity: ExactDecimalQuantityV1(mantissa: 1, scale: 0)
            )
        ], directCost: nil))
    }

    func testV23P03C49G01PinnedISO4217ListOneUniverseAndMinorUnitScales() throws {
        for code in ["BHD", "KWD"] {
            let amount = try ExactMoneyAmountV1(mantissa: 1, currencyCode: code, minorUnitScale: 3)
            XCTAssertEqual(amount.minorUnitScale, 3)
        }
        for code in ["CLF", "UYW"] {
            let amount = try ExactMoneyAmountV1(mantissa: 1, currencyCode: code, minorUnitScale: 4)
            XCTAssertEqual(amount.minorUnitScale, 4)
        }
        XCTAssertEqual(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "JPY", minorUnitScale: 0).minorUnitScale, 0)
        XCTAssertEqual(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "USD", minorUnitScale: 2).minorUnitScale, 2)

        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "BHD", minorUnitScale: 2))
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "CLF", minorUnitScale: 3))
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "ZZZ", minorUnitScale: 2))
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "usd", minorUnitScale: 2))

        XCTAssertEqual(
            C49WorkResourceContractBoundaryV1.iso4217ListOneSourceURL,
            "https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml"
        )
        XCTAssertEqual(C49WorkResourceContractBoundaryV1.iso4217ListOnePublished, "2026-01-01")
        XCTAssertEqual(C49WorkResourceContractBoundaryV1.iso4217ListOneRawByteCount, 47_463)
        XCTAssertEqual(
            C49WorkResourceContractBoundaryV1.iso4217ListOneSHA256,
            "838dfb991648cf36df939edd5fe3811737962b75a32252847d239cedd1e291c9"
        )
        XCTAssertEqual(C49WorkResourceContractBoundaryV1.iso4217ListOneNumericMinorUnitCodeCount, 165)
    }

    func testV23P03C49R01FrozenAndAbsentPartReferencesRoundTripRowsAndBackup() throws {
        let frozen = try LocalPartReferenceSnapshotV1(
            partID: UUID(uuidString: "49000000-0000-0000-0000-000000000070")!,
            partRevision: 11,
            partSHA256: digest,
            displayName: "Frozen coupling"
        )
        let quantity = try ExactDecimalQuantityV1(mantissa: 2, scale: 0)
        let referenced = try ManualMaterialLineV1(
            lineID: UUID(uuidString: "49000000-0000-0000-0000-000000000071")!,
            description: "Coupling",
            quantity: quantity,
            unit: "each",
            localPartReference: frozen
        )
        let untracked = try ManualMaterialLineV1(
            lineID: UUID(uuidString: "49000000-0000-0000-0000-000000000072")!,
            description: "Untracked sealant",
            quantity: quantity
        )
        let entry = try makeEntry(duration: nil, materials: [referenced, untracked], directCost: nil)

        let rowValue = try ManualWorkResourceRecordRow(entry).value()
        XCTAssertEqual(rowValue, entry)
        XCTAssertEqual(rowValue.materials.first(where: { $0.lineID == referenced.lineID })?.localPartReference, frozen)
        XCTAssertNil(rowValue.materials.first(where: { $0.lineID == untracked.lineID })?.localPartReference)

        let transport = try V37BackupWorkResourceRecordV1(entry)
        XCTAssertEqual(try transport.value(), entry)
        let bundle = try WorkResourceAtomicBundleV1(entry: entry)
        let backup = try WorkResourceBackupSnapshotV1(workspaceID: workspaceID, bundles: [bundle])
        try backup.validate()
        XCTAssertEqual(backup.entries, [entry])
        let deterministicRetry = try WorkResourceBackupSnapshotV1(workspaceID: workspaceID, bundles: [bundle])
        XCTAssertEqual(deterministicRetry, backup)

        let target = WorkspaceID(rawValue: UUID(uuidString: "49000000-0000-0000-0000-000000000079")!)
        let rebound = try entry.rebound(
            to: target,
            mappedSubject: try subject(workspaceID: target),
            mappedActor: try actor(workspaceID: target),
            mappedSupersedesEntrySHA256: nil,
            mutationID: try MutationIDV1(rawValue: UUID(uuidString: "49000000-0000-0000-0000-000000000078")!)
        )
        XCTAssertEqual(rebound.materials.first(where: { $0.lineID == referenced.lineID })?.localPartReference, frozen)
        XCTAssertNil(rebound.materials.first(where: { $0.lineID == untracked.lineID })?.localPartReference)
        XCTAssertEqual(try V37BackupWorkResourceRecordV1(rebound).value(), rebound)

        for cloneOrFork in [false, true] {
            let receipt = try WorkResourceRestoreReceiptV1(
                operationID: UUID(uuidString: cloneOrFork
                    ? "49000000-0000-0000-0000-000000000081"
                    : "49000000-0000-0000-0000-000000000080")!,
                sourceWorkspaceID: workspaceID,
                targetWorkspaceID: cloneOrFork ? target : workspaceID,
                snapshotSHA256: backup.snapshotSHA256, effectSHA256: entry.entrySHA256,
                cloneOrFork: cloneOrFork, completedAt: instant
            )
            XCTAssertEqual(receipt.cloneOrFork, cloneOrFork)
            XCTAssertEqual(receipt.snapshotSHA256, backup.snapshotSHA256)
        }
    }

    func testV23P03C49G01CanonicalProjectionSeparatesCurrenciesAndDetectsOverflow() throws {
        let usd = try makeEntry(directCost: DirectCostEntryV1(
            amount: ExactMoneyAmountV1(mantissa: 125, currencyCode: "USD", minorUnitScale: 2)
        ))
        let eur = try makeEntry(directCost: DirectCostEntryV1(
            amount: ExactMoneyAmountV1(mantissa: 250, currencyCode: "EUR", minorUnitScale: 2)
        ))
        let projection = try C49WorkResourceReportProjectionV1(
            workspaceID: workspaceID,
            snapshots: [WorkResourceSnapshotV1(entry: usd), WorkResourceSnapshotV1(entry: eur)]
        )
        XCTAssertEqual(projection.directCostPreview.totalsByCurrency.map(\.currencyCode), ["EUR", "USD"])
        XCTAssertEqual(projection.directCostPreview.totalsByCurrency.map(\.mantissa), [250, 125])

        let maximum = try makeEntry(directCost: DirectCostEntryV1(
            amount: ExactMoneyAmountV1(mantissa: Int64.max, currencyCode: "USD", minorUnitScale: 2)
        ))
        let one = try makeEntry(directCost: DirectCostEntryV1(
            amount: ExactMoneyAmountV1(mantissa: 1, currencyCode: "USD", minorUnitScale: 2)
        ))
        XCTAssertThrowsError(try C49WorkResourceReportProjectionV1(
            workspaceID: workspaceID,
            snapshots: [WorkResourceSnapshotV1(entry: maximum), WorkResourceSnapshotV1(entry: one)]
        )) { error in
            XCTAssertEqual(error as? C49WorkResourceProjectionFailureV1, .arithmeticOverflow)
        }
    }

    func testV23P03C49G01MaterialTotalsUseExactDescriptionUnitAndNormalizeScale() throws {
        let lines = try [
            ManualMaterialLineV1(description: "Cable", quantity: ExactDecimalQuantityV1(mantissa: 1, scale: 0), unit: "m"),
            ManualMaterialLineV1(description: "Cable", quantity: ExactDecimalQuantityV1(mantissa: 250, scale: 3), unit: "m"),
            ManualMaterialLineV1(description: "Cable", quantity: ExactDecimalQuantityV1(mantissa: 1, scale: 0), unit: "ft"),
            ManualMaterialLineV1(description: "cable", quantity: ExactDecimalQuantityV1(mantissa: 1, scale: 0), unit: "m")
        ]
        let totals = try WorkResourceTotalsProjectionV1(
            snapshots: [WorkResourceSnapshotV1(entry: makeEntry(duration: nil, materials: lines, directCost: nil))]
        )
        XCTAssertEqual(totals.materialLineCount, 4)
        XCTAssertEqual(totals.materialTotals.count, 3)
        let meters = try XCTUnwrap(totals.materialTotals.first { $0.description == "Cable" && $0.unit == "m" })
        XCTAssertEqual(meters.quantityMantissa, 1_250)
        XCTAssertEqual(meters.quantityScale, 3)
        XCTAssertNotNil(totals.materialTotals.first { $0.description == "Cable" && $0.unit == "ft" })
        XCTAssertNotNil(totals.materialTotals.first { $0.description == "cable" && $0.unit == "m" })

        let overflowing = try ManualMaterialLineV1(
            description: "Overflow",
            quantity: ExactDecimalQuantityV1(mantissa: Int64.max, scale: 0)
        )
        XCTAssertThrowsError(try WorkResourceTotalsProjectionV1(
            snapshots: [WorkResourceSnapshotV1(entry: makeEntry(duration: nil, materials: [overflowing], directCost: nil))]
        ))
    }

    func testV23P03C49H01SearchAndDiagnosticExportsAreDerivedAndCostSafe() throws {
        let report = try C49WorkResourceReportProjectionV1(
            workspaceID: workspaceID,
            snapshots: [WorkResourceSnapshotV1(entry: makeEntry())],
            audience: .customerSafe
        )
        let search = try C49WorkResourceSearchBoundaryV1.projection(report)
        XCTAssertEqual(search.workspaceID, workspaceID)
        XCTAssertTrue(search.terms.contains("Conduit"))
        XCTAssertFalse(search.terms.contains("USD"))
        try search.validate()

        let diagnostic = try C49WorkResourceDiagnosticBoundaryV1.metadata(report)
        XCTAssertFalse(diagnostic.directCostPreviewIncluded)
        XCTAssertTrue(diagnostic.currencies.isEmpty)
        XCTAssertFalse(diagnostic.rawStockClaims)
        XCTAssertFalse(diagnostic.liveInventoryClaims)
        let bytes = try C49WorkResourceDiagnosticBoundaryV1.encode(report)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(text.contains("2500"))
        XCTAssertFalse(text.contains("Conduit"), "diagnostics carry counts and hashes, not source material text")
    }

    func testV23P03C49CurrentHeadProjectionNeverDoubleCountsReferencedPredecessor() throws {
        let predecessorLine = try ManualMaterialLineV1(
            lineID: UUID(uuidString: "49000000-0000-0000-0000-000000000090")!,
            description: "Cable",
            quantity: ExactDecimalQuantityV1(mantissa: 1, scale: 0),
            unit: "m"
        )
        let predecessor = try makeEntry(
            duration: ManualDurationV1(minutes: 10),
            materials: [predecessorLine],
            directCost: DirectCostEntryV1(
                amount: ExactMoneyAmountV1(mantissa: 100, currencyCode: "USD", minorUnitScale: 2)
            )
        )
        let successorLine = try ManualMaterialLineV1(
            lineID: UUID(uuidString: "49000000-0000-0000-0000-000000000091")!,
            description: "Cable",
            quantity: ExactDecimalQuantityV1(mantissa: 2, scale: 0),
            unit: "m"
        )
        let successor = try makeEntry(
            disposition: .superseded,
            duration: ManualDurationV1(minutes: 20),
            materials: [successorLine],
            directCost: DirectCostEntryV1(
                amount: ExactMoneyAmountV1(mantissa: 200, currencyCode: "USD", minorUnitScale: 2)
            ),
            expectedRevision: predecessor.revision,
            revision: predecessor.revision + 1,
            supersedes: predecessor
        )
        try successor.validateSuccessor(of: predecessor)
        let replaced = try C49WorkResourceReportProjectionV1(
            workspaceID: workspaceID,
            snapshots: [WorkResourceSnapshotV1(entry: predecessor), WorkResourceSnapshotV1(entry: successor)]
        )
        XCTAssertEqual(replaced.sourceRecordIDs, [successor.entryID])
        XCTAssertEqual(replaced.durationMinutes, 20)
        XCTAssertEqual(replaced.materials.map(\.quantity.mantissa), [2_000])
        XCTAssertEqual(replaced.directCostPreview.totalsByCurrency.map(\.mantissa), [200])

        for terminalDisposition in [WorkResourceDispositionV1.voidedWithReason, .reversed] {
            let terminal = try makeEntry(
                disposition: terminalDisposition,
                voidReason: terminalDisposition == .voidedWithReason ? "Recorded in error" : nil,
                duration: predecessor.duration,
                materials: predecessor.materials,
                directCost: predecessor.directCost,
                expectedRevision: predecessor.revision,
                revision: predecessor.revision + 1,
                supersedes: predecessor
            )
            try terminal.validateSuccessor(of: predecessor)
            let projection = try C49WorkResourceReportProjectionV1(
                workspaceID: workspaceID,
                snapshots: [WorkResourceSnapshotV1(entry: predecessor), WorkResourceSnapshotV1(entry: terminal)]
            )
            XCTAssertTrue(projection.sourceRecordIDs.isEmpty)
            XCTAssertEqual(projection.durationMinutes, 0)
            XCTAssertTrue(projection.materials.isEmpty)
            XCTAssertTrue(projection.directCostPreview.totalsByCurrency.isEmpty)
        }
    }

    private func subject(workspaceID: WorkspaceID? = nil, kind: WorkResourceSubjectKindV1 = .workPacket) throws -> WorkResourceSubjectV1 {
        try WorkResourceSubjectV1(
            workspaceID: workspaceID ?? self.workspaceID,
            kind: kind,
            subjectID: "49000000-0000-0000-0000-000000000030",
            subjectRevision: 1,
            subjectSHA256: digest
        )
    }

    private func actor(workspaceID: WorkspaceID? = nil) throws -> ActorSnapshotV1 {
        let workspaceID = workspaceID ?? self.workspaceID
        let reference = try LocalActorReferenceV1(
            actorReferenceID: UUID(uuidString: "49000000-0000-0000-0000-000000000040")!,
            workspaceID: workspaceID,
            displayName: "Recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: UUID(uuidString: "49000000-0000-0000-0000-000000000041")!,
            workspaceID: workspaceID,
            actor: reference,
            responsibility: .recordedBy,
            displayNameAtTime: "Recorder",
            capturedAt: instant
        )
    }

    private func makeEntry(
        kind: WorkResourceSubjectKindV1 = .workPacket,
        disposition: WorkResourceDispositionV1 = .active,
        voidReason: String? = nil,
        duration: ManualDurationV1? = try? ManualDurationV1(minutes: 45),
        materials: [ManualMaterialLineV1]? = nil,
        directCost: DirectCostEntryV1? = try? DirectCostEntryV1(amount: ExactMoneyAmountV1(mantissa: 2_500, currencyCode: "USD", minorUnitScale: 2)),
        visibility: WorkResourceVisibilityPolicyV1 = .internalOnly,
        expectedRevision: UInt64 = 0,
        revision: UInt64 = 1,
        supersedes: WorkResourceEntryV1? = nil
    ) throws -> WorkResourceEntryV1 {
        let material = try ManualMaterialLineV1(
            description: "Conduit",
            quantity: ExactDecimalQuantityV1(mantissa: 1_250, scale: 3),
            unit: "m"
        )
        return try WorkResourceEntryV1(
            entryID: UUID(),
            workspaceID: workspaceID,
            subject: try subject(kind: kind),
            actor: try actor(),
            duration: duration,
            materials: materials ?? [material],
            directCost: directCost,
            visibility: visibility,
            disposition: disposition,
            voidReason: voidReason,
            recordedAt: instant,
            expectedRevision: expectedRevision,
            revision: revision,
            supersedesEntryID: supersedes?.entryID,
            supersedesEntrySHA256: supersedes?.entrySHA256,
            mutationID: try MutationIDV1(rawValue: UUID())
        )
    }
}
