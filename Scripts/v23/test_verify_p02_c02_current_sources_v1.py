#!/usr/bin/env python3
"""Hostile tests of the current C02 Source reader against real Source inputs.

Mutations exist only in memory. No Swift, frozen artifact or historical reader
is rewritten, and no native/runtime behavior is claimed by this suite.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path
from typing import Callable

sys.dont_write_bytecode = True

import verify_p02_c02_current_sources_v1 as reader

PERSISTENCE = 'FieldEvidenceApp/Infrastructure/Persistence/'
BACKUP = 'FieldEvidenceApp/Infrastructure/Backup/'
BACKUP_CONTRACTS = 'FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift'
MUTATION_CONTRACTS = 'FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift'
EVIDENCE_TESTS = 'FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift'
ERASE = 'FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift'


class CurrentC02SourceReaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.inputs = reader.load_inputs(cls.root)
        cls.source = {path: value for path, value in cls.inputs.items() if path.endswith('.swift')}
        cls.fixture = json.loads(cls.inputs[reader.FIXTURE])

    def changed(self, path: str, old: str, new: str, *, all_occurrences: bool = False) -> dict[str, str]:
        source = dict(self.source)
        self.assertIn(old, source[path], f'hostile mutation anchor absent: {path}: {old}')
        source[path] = source[path].replace(old, new) if all_occurrences else source[path].replace(old, new, 1)
        self.assertNotEqual(source[path], self.source[path])
        return source

    def rejects(self, check: Callable[[dict[str, str]], None], source: dict[str, str], reason: str) -> None:
        with self.assertRaisesRegex(reader.ContractError, reason):
            check(source)

    def test_real_current_source_bundle_preserves_historical_and_current_predicates(self) -> None:
        reader.verify_inputs(self.inputs)

    def test_missing_and_comment_only_recovery_are_refused(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        call = 'try recovery.recoverBeforeWriterActivation()'
        for replacement in ('', '// ' + call):
            with self.subTest(replacement=replacement):
                self.rejects(reader.verify_recovery, self.changed(path, call, replacement),
                             'recovery before ordinary writer')

    def test_recovery_after_writer_construction_is_refused(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        source = self.changed(path, 'try recovery.recoverBeforeWriterActivation()', '')
        anchor = 'let writer = try WorkspaceWriterV1('
        source[path] = source[path].replace(anchor, anchor + '\n try recovery.recoverBeforeWriterActivation()\n', 1)
        self.rejects(reader.verify_recovery, source, 'recovery before ordinary writer')

    def test_bootstrap_or_foreign_generation_recovery_is_refused(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        for old, new in (
            ('allowStateBootstrap: false,\n            staleWriterFence: staleWriterFence',
             'allowStateBootstrap: true,\n            staleWriterFence: staleWriterFence'),
            ('identity: session.workspaceIdentity,\n            generationID: session.generationID,\n            failureInjection:',
             'identity: session.workspaceIdentity,\n            generationID: UUID(),\n            failureInjection:'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_recovery, self.changed(path, old, new), 'current recovery identity/lease/branch')

    def test_original_erase_recovery_and_authorized_validation_are_required(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        self.rejects(reader.verify_recovery,
                     self.changed(path, '.recoverBeforeOriginalEraseTargetWriterActivation(', '.recoverDifferentTarget('),
                     'recovery before original Erase target writer')
        recovery_path = PERSISTENCE + 'MutationJournal/MutationReceiptRecoveryServiceV1.swift'
        self.rejects(reader.verify_recovery,
                     self.changed(recovery_path, 'try store.validateAll()', '// try store.validateAll()'),
                     'validated current canonical recovery')
        self.rejects(reader.verify_recovery,
                     self.changed(recovery_path, 'try store.withAuthorizedRecovery {', 'try store.withUnfencedRecovery {'),
                     'authorized ordinary recovery')

    def test_explicit_current_tuple_does_not_allow_archive3_schema53_or_future_pairs(self) -> None:
        for old, new, reason in (
            ('static let persistentSchemaVersion = 53', 'static let persistentSchemaVersion = 54', 'current tuple enrollment'),
            ('static let recordsSchemaVersion = 52', 'static let recordsSchemaVersion = 53', 'current tuple enrollment'),
            ('return backup == 4 && v4Pairs.contains', 'return backup >= 3 && v4Pairs.contains', 'tuple admission'),
            ('case (1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 4, 3):',
             'case (1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 53, 52):', 'tuple admission'),
            ('        (5, 4),', '        (54, 53),\n        (5, 4),', '49 enrolled archive4 pairs'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_current_backup, self.changed(BACKUP_CONTRACTS, old, new), reason)

    def test_active_schema_or_compatibility_identity_drift_is_refused(self) -> None:
        path = PERSISTENCE + 'PersistentSchemas.swift'
        self.rejects(reader.verify_current_backup,
                     self.changed(path, 'static var activeRelease: PersistentSchemaReleaseV1 {\n        .v53',
                                  'static var activeRelease: PersistentSchemaReleaseV1 {\n        .v52'),
                     'active current persistent release')
        self.rejects(reader.verify_current_backup,
                     self.changed(path, 'case .v53:return "LIGHTING_NIGHT_WORKFLOW_V1"',
                                  'case .v53:return "UNENROLLED_SCHEMA"'), 'current compatibility identity')

    def test_current_export_must_use_real_history_and_actual_records_version(self) -> None:
        path = BACKUP + 'BackupExportService.swift'
        for old, new in (
            ('deletionLedger: deletionLedger,\n            mutationHistory: mutationHistory',
             'deletionLedger: deletionLedger,\n            mutationHistory: nil'),
            ('persistentSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,',
             'persistentSchemaVersion: 4,'),
            ('recordsSchemaVersion: records.recordsSchemaVersion,\n            sourceGenerationID: generationID, workspaceID: sourceIdentity.workspaceID.rawValue)',
             'recordsSchemaVersion: 3,\n            sourceGenerationID: generationID, workspaceID: sourceIdentity.workspaceID.rawValue)'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_current_backup, self.changed(path, old, new), 'actual current export tuple/history/basis')
        self.rejects(reader.verify_current_backup,
                     self.changed(path, ': LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,', ': 3,'),
                     'explicit legacy/current projection')

    def test_missing_package_tuple_validation_is_refused(self) -> None:
        path = BACKUP + 'BackupPackageValidatorV1.swift'
        self.rejects(reader.verify_current_backup,
                     self.changed(path, 'let schemaPairIsValid = BackupSchemaAdmissionV1.supports(',
                                  'let schemaPairIsValid = permissiveSchemaAdmission('),
                     'package current/historical tuple')

    def test_closed_command_roster_rejects_missing_extra_duplicate_and_reorder(self) -> None:
        text = self.source[MUTATION_CONTRACTS]
        body = reader.block(text, 'enum WorkspaceCommandKindV1:')
        rows = re.findall(r'^\s*case\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"[^\"]+"\s*$', body, re.M)
        self.assertEqual(len(rows), 63)
        for old, new in (
            (rows[0], ''),
            (rows[0], rows[0] + '\n    case invented = "invented"'),
            (rows[0], rows[0] + '\n' + rows[0]),
        ):
            with self.subTest(mutation=new):
                self.rejects(reader.verify_current_rosters, self.changed(MUTATION_CONTRACTS, old, new), 'ordered63 commands')
        source = dict(self.source)
        source[MUTATION_CONTRACTS] = text.replace(rows[0], '__ROW_SWAP__', 1).replace(rows[1], rows[0], 1).replace('__ROW_SWAP__', rows[1], 1)
        self.rejects(reader.verify_current_rosters, source, 'ordered63 commands')

    def test_six_test_roster_rejects_missing_duplicate_reordered_or_comment_only_declaration(self) -> None:
        first, second = reader.CURRENT_TESTS[:2]
        for old, new in (
            ('func ' + second + '(', 'func testDifferentTemporalReceipt('),
            ('func ' + second + '(', 'func ' + first + '('),
            ('func ' + second + '(', '// func ' + second + '('),
        ):
            with self.subTest(mutation=new):
                self.rejects(reader.verify_current_rosters, self.changed(EVIDENCE_TESTS, old, new), 'six actual current test')
        source = self.changed(EVIDENCE_TESTS, 'func ' + first + '(', 'func __SWAP__(')
        source[EVIDENCE_TESTS] = source[EVIDENCE_TESTS].replace('func ' + second + '(', 'func ' + first + '(', 1).replace('func __SWAP__(', 'func ' + second + '(', 1)
        self.rejects(reader.verify_current_rosters, source, 'six actual current test')

    def test_checkpoint_record_descriptor_includes_optional_and_history_fields_without_duplicates(self) -> None:
        for old, new in (
            ('"locationMigrationReceipts", "locationNodes", "measurementIntegrity", "mutationHistory",',
             '"locationMigrationReceipts", "locationNodes", "measurementIntegrity",'),
            ('"packageEvolution", "packets", "pairedObservationLinks", "partsStockSnapshot",',
             '"packageEvolution", "packets", "pairedObservationLinks",'),
            ('"assetSemantics", "assets", "assistanceAcceptanceReceipts", "authorityCriterion",',
             '"assetSemantics", "assets", "assets", "authorityCriterion",'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_checkpoint_history, self.changed(reader.JOURNAL, old, new), 'independent77 checkpoint')
        self.rejects(reader.verify_checkpoint_history,
                     self.changed(BACKUP_CONTRACTS, '    var evidenceQuality: EvidenceQualityBackupSnapshotV1?', ''),
                     'stored field census')

    def test_checkpoint_shared_admission_and_destination_integrity_are_required(self) -> None:
        for old, new, reason in (
            ('BackupSchemaAdmissionV1.supports(backup: 4, persistent: persistent, records: records)',
             'BackupSchemaAdmissionV1.supports(backup: 3, persistent: persistent, records: records)', 'exact53/52'),
            ('persistent: destination.persistentSchemaVersion,\n            records: destination.recordsSchemaVersion',
             'persistent: checkpoint.manifest.persistentSchemaVersion,\n            records: checkpoint.manifest.recordSchemaVersion',
             'checkpoint destination|incoming and destination'),
            ('recordSchemaSHA256 == checkpoint.manifest.recordSchemaSHA256,', '', 'checkpoint destination'),
            ('destinationFrontier == checkpoint.manifest.frontier,', '', 'checkpoint destination'),
            ('== checkpoint.manifest.normalizedRecordsSHA256 else', '== "unbound" else', 'checkpoint destination'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_checkpoint_history, self.changed(reader.JOURNAL, old, new), reason)

    def test_actual_model_census_cannot_be_replaced_by_the_retained_168_literal(self) -> None:
        self.rejects(reader.verify_checkpoint_history,
                     self.changed(reader.CATALOG, '"Asset", "DeletionLedgerRow",', '"DeletionLedgerRow",'),
                     'actual current168 persistent model census')
        self.rejects(reader.verify_checkpoint_history,
                     self.changed(reader.CATALOG, '"Asset", "DeletionLedgerRow",', '"Asset", "Asset",'),
                     'actual current168 persistent model census')
        self.rejects(reader.verify_checkpoint_history,
                     self.changed(reader.CATALOG, '+ v52PersistentModelNames + v53PersistentModelNames).sorted()',
                                  '+ v53PersistentModelNames).sorted()'),
                     'model inventory composition')

    def test_checkpoint_raw_reversal_and_content_guards_cannot_disappear(self) -> None:
        for old, new in (
            ('recordsEntry.sha256 == Self.rawSHA256(basis.recordsData)', 'true'),
            ('Set(supplement.reversalEligibility.map(\\.targetMutationID)) == expectedMutationIDs', 'true'),
            ('entry.byteCount == Int(contentEntry.reference.byteLength)', 'true'),
            ('entry.sha256 == contentEntry.reference.digests.digest(for: .sha256)?.hexadecimalValue', 'true'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_checkpoint_history, self.changed(reader.JOURNAL, old, new), 'checkpoint creation')

    def test_semantic_and_transport_history_have_distinct_strict_seams(self) -> None:
        path = BACKUP + 'BackupCanonicalEncoderV1.swift'
        for old, new, reason in (
            ('guard fields.removeValue(forKey: "mutationHistory") != nil else',
             'guard fields.removeValue(forKey: "deletionLedger") != nil else', 'semantic records'),
            ('fields["mutationHistory"] = try Self.mutationHistory(',
             'fields["ignoredHistory"] = try Self.mutationHistory(', 'transport retains'),
            ('case 48, 49, 50, 51, 52:', 'case 47, 48, 49, 50, 51, 52:', 'historical empty'),
        ):
            with self.subTest(mutation=old):
                source = (self.scoped_changed(path,
                    'private static func recordFields(\n        _ records: V4BackupRecordsV1,', old, new)
                    if old == 'fields["mutationHistory"] = try Self.mutationHistory('
                    else self.changed(path, old, new))
                self.rejects(reader.verify_checkpoint_history, source, reason)
        self.rejects(reader.verify_checkpoint_history,
                     self.changed(BACKUP + 'BackupCanonicalDecoderV1.swift', 'guard legacy == data else', 'guard true else'),
                     'strict full backup canonical decode')

    def test_aggregate_and_historical_v3_retry_projections_remain_bound(self) -> None:
        path = PERSISTENCE + 'StoreGenerationFactory.swift'
        for old, new, reason in (
            ('guard (try adjacentSemanticDigest(in: context, release: .v3, aggregate: aggregate)) == expectedSemanticDigest else',
             'guard (try adjacentSemanticDigest(in: context, release: .v4, aggregate: aggregate)) == expectedSemanticDigest else', 'V3 retry'),
            ('if release == .v3 { return try semanticExportV3(in: context, purpose: purpose) }',
             'if release == .v3 { return try semanticExportV4(in: context, purpose: purpose) }', 'V3 projection'),
            ('guard aggregate != nil else {', 'guard aggregate == nil else {', 'nested digest/current aggregate'),
            ('marker.predecessorReleaseID == PersistentSchemaReleaseRegistryV1.v3CompatibilityID,',
             'marker.predecessorReleaseID == PersistentSchemaReleaseRegistryV1.v2CompatibilityID,', 'V4 frozen marker'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_v3_retry, self.changed(path, old, new), reason)

    def test_whole_generation_erase_requires_empty_history_and_all_root_inventories(self) -> None:
        for old, new, reason in (
            ('history.entityRevisions.isEmpty, !context.hasChanges else', '!context.hasChanges else', 'published empty'),
            ('keeping: intent.newGenerationID,\n                    authority: authority',
             'keeping: intent.workspaceID,\n                    authority: authority', 'whole generation Erase'),
            ('guard Set(try authority.installedGenerationNames())\n                == [Self.canonical(intent.newGenerationID)] else',
             'guard true else', 'whole generation Erase disposal'),
            ('expected: initialRetired,\n                with: [],',
             'expected: initialRetired,\n                with: initialRetired,', 'current/retired target authority'),
            ('try authority.clearRetiredGenerationsForEraseRetirement(', 'try authority.leaveRetiredGenerations(', 'retained original Erase'),
            ('expected: intent.generationIDsToDelete, currentID: intent.newGenerationID).isEmpty else',
             'expected: intent.generationIDsToDelete, currentID: intent.newGenerationID).count >= 0 else', 'retained Erase exact frozen old root inventory'),
            ('try await operation.removeOriginalC05DrainedRoot(', 'try await operation.keepOriginalC05DrainedRoot(', 'original C05 old root'),
        ):
            with self.subTest(mutation=old):
                self.rejects(reader.verify_erase, self.changed(ERASE, old, new), reason)

    def test_applicable_historical_reversal_replay_and_prohibited_field_guards_remain(self) -> None:
        check = lambda source: reader.verify_inherited_sources(source, self.fixture)
        for path, old, new, reason in (
            ('FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift',
             'plan.compensatingCommands.count == 1', 'plan.compensatingCommands.count >= 1', 'single-command reversal'),
            (PERSISTENCE + 'MutationJournal/MutationJournalStoreV1.swift',
             'projectionRevisionByEntity[entity].map { $0 >= maximumRevision } ?? false',
             'projectionRevisionByEntity[entity].map { $0 >= maximumRevision } ?? true', 'projection-to-post-image'),
            (ERASE, 'import Foundation', 'import Foundation\n// accountID', 'prohibited remote/account'),
        ):
            with self.subTest(mutation=old):
                self.rejects(check, self.changed(path, old, new, all_occurrences=True), reason)

    def test_historical_fixture_and_authority_cannot_be_rewritten_as_current(self) -> None:
        fixture = dict(self.fixture)
        fixture['restoreMatrix'] = fixture['restoreMatrix'][:-1]
        with self.assertRaisesRegex(reader.ContractError, 'fixture restore matrix'):
            reader.verify_inherited_sources(self.source, fixture)
        inputs = dict(self.inputs)
        lifecycle = json.loads(inputs[reader.LIFECYCLE_DOC])
        lifecycle['backup']['manifestSchemaVersion'] = 4
        lifecycle['backup']['recordsSchemaVersion'] = 52
        lifecycle['schemaActivation']['persistentSchemaVersion'] = 53
        inputs[reader.LIFECYCLE_DOC] = json.dumps(lifecycle)
        with self.assertRaisesRegex(reader.ContractError, 'frozen C02 lifecycle changed'):
            reader.verify_authorities(inputs)
        inputs = dict(self.inputs)
        authority = json.loads(inputs[reader.CURRENT_AUTHORITY])
        authority['semantics']['activeModelCount'] = 167
        inputs[reader.CURRENT_AUTHORITY] = json.dumps(authority)
        with self.assertRaisesRegex(reader.ContractError, 'current frozen schema/family census'):
            reader.verify_authorities(inputs)

    def test_input_omission_and_historical_reader_movement_are_refused(self) -> None:
        inputs = dict(self.inputs)
        del inputs[reader.JOURNAL]
        with self.assertRaisesRegex(reader.ContractError, 'input closure'):
            reader.verify_inputs(inputs)
        inputs = dict(self.inputs)
        inputs[reader.HISTORICAL_READER] += '\n'
        with self.assertRaisesRegex(reader.ContractError, 'historical reader/contract changed'):
            reader.verify_inputs(inputs)

    def test_scoped_reader_ignores_nested_comments_and_string_braces(self) -> None:
        example = '''// func target() { bogus }
        func target() { let text = "}"; /* { /* nested } */ } */ let raw = #"{"#; real() }
        '''
        result = reader.block(example, 'func target()')
        self.assertIn('real()', result)
        self.assertNotIn('bogus', result)
        self.assertNotIn('nested', result)
        with self.assertRaisesRegex(reader.ContractError, 'unterminated Swift block comment'):
            reader.block('func target() { /*', 'func target()')

    def scoped_changed(self, path: str, declaration: str, old: str, new: str) -> dict[str, str]:
        """Change exactly one real owner scope; unrelated matching operands stay intact."""
        original = self.source[path]
        _, structure = reader.swift_masks(original)
        self.assertEqual(structure.count(declaration), 1, 'real mutation owner must be unique')
        start = structure.index('{', structure.index(declaration) + len(declaration))
        end = start + len(reader.block(original, declaration)) + 1
        actual = original[start + 1:end]
        self.assertIn(old, actual, f'hostile scoped anchor absent: {declaration}: {old}')
        changed = actual.replace(old, new, 1)
        self.assertNotEqual(actual, changed)
        source = dict(self.source)
        source[path] = original[:start + 1] + changed + original[end:]
        return source

    def full_refusal(self, source: dict[str, str], reason: str) -> None:
        inputs = dict(self.inputs)
        inputs.update(source)
        with self.assertRaisesRegex(reader.ContractError, reason):
            reader.verify_inputs(inputs)

    def test_full_reader_rejects_ordinary_raw_and_multiline_recovery_string_decoys(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        call = 'try recovery.recoverBeforeWriterActivation()'
        decoys = (
            '_ = "} else { try recovery.recoverBeforeWriterActivation() }"',
            '_ = #"} else { try recovery.recoverBeforeWriterActivation() }"#',
            '_ = """\n} else { try recovery.recoverBeforeWriterActivation() }\n"""',
            '_ = #"""\n} else { try recovery.recoverBeforeWriterActivation() }\n"""#',
        )
        for decoy in decoys:
            with self.subTest(decoy=decoy):
                self.full_refusal(self.changed(path, call, decoy), 'recovery before ordinary writer')

    def test_full_reader_uses_the_real_descriptor_despite_raw_multiline_declaration_decoy(self) -> None:
        path = reader.JOURNAL
        text = self.source[path]
        head = 'private static let v52BackupRecordFields = ['
        declaration = re.search(re.escape(head) + r'.*?\]\.sorted\(\)', text, re.S)
        self.assertIsNotNone(declaration)
        genuine = declaration.group(0)
        damaged = genuine.replace('"mutationHistory",', '', 1)
        self.assertNotEqual(genuine, damaged)
        source = self.changed(path, genuine,
                              'private static let descriptorDecoy = #"""\n' + genuine + '\n"""#\n' + damaged)
        self.full_refusal(source, 'value independent77 checkpoint record fields')

    def test_full_reader_ignores_fake_enrollment_and_current_schema_declarations_inside_strings(self) -> None:
        source = self.scoped_changed(BACKUP_CONTRACTS, 'enum LightingNightWorkflowBackupEnrollmentV1',
                                     'static let recordsSchemaVersion = 52',
                                     'static let valueDecoy = #"static let recordsSchemaVersion = 52"#\n'
                                     '    static let recordsSchemaVersion = 51')
        self.full_refusal(source, 'current tuple enrollment')
        path = PERSISTENCE + 'PersistentSchemas.swift'
        source = self.scoped_changed(path, 'enum PersistentSchemaV53:',
                                     'Schema.Version(53,0,0)', 'Schema.Version(52,0,0)')
        source[path] = 'private let schemaDecoy = #"""\n' + \
                       'enum PersistentSchemaV53: VersionedSchema { static let versionIdentifier = Schema.Version(53,0,0) }' + \
                       '\n"""#\n' + source[path]
        self.full_refusal(source, 'concrete current V53 schema/version/models')

    def test_full_reader_binds_every_actual_journal_operand_despite_other_matching_calls(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        declaration = 'private static func constructWriter('
        for old, new in (
            ('modelContext: session.modelContext,\n            identity: session.workspaceIdentity,',
             'modelContext: ModelContext(session.modelContext.container),\n            identity: session.workspaceIdentity,'),
            ('identity: session.workspaceIdentity,\n            generationID: session.generationID,\n            failureInjection:',
             'identity: differentIdentity,\n            generationID: session.generationID,\n            failureInjection:'),
            ('identity: session.workspaceIdentity,\n            generationID: session.generationID,\n            failureInjection:',
             'identity: session.workspaceIdentity,\n            generationID: UUID(),\n            failureInjection:'),
            ('allowStateBootstrap: false,\n            staleWriterFence: staleWriterFence',
             'allowStateBootstrap: true,\n            staleWriterFence: staleWriterFence'),
            ('allowStateBootstrap: false,\n            staleWriterFence: staleWriterFence',
             'allowStateBootstrap: false,\n            staleWriterFence: differentFence'),
            ('MutationReceiptRecoveryServiceV1(store: journalStore)',
             'MutationReceiptRecoveryServiceV1(store: differentJournal)'),
        ):
            with self.subTest(mutation=new):
                reason = ('recovery before ordinary writer'
                          if old == 'MutationReceiptRecoveryServiceV1(store: journalStore)'
                          else 'current recovery identity/lease/branch')
                self.full_refusal(self.scoped_changed(path, declaration, old, new),
                                  reason)

    def test_full_reader_binds_each_production_fence_epoch_token_registry_and_owner(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        declaration = 'private static func constructWriter('
        for old, new in (
            ('let writerLeaseToken = leaseHandle.token', 'let writerLeaseToken = otherHandle.token'),
            ('expectedGenerationEpoch: generationEpoch, writerLeaseToken: writerLeaseToken,',
             'expectedGenerationEpoch: otherEpoch, writerLeaseToken: writerLeaseToken,'),
            ('expectedGenerationEpoch: generationEpoch, writerLeaseToken: writerLeaseToken,',
             'expectedGenerationEpoch: generationEpoch, writerLeaseToken: otherToken,'),
            ('registry: registry, owner: owner)', 'registry: otherRegistry, owner: owner)'),
            ('registry: registry, owner: owner)', 'registry: registry, owner: differentOwner)'),
            ('expectedGenerationEpoch: generationEpoch,\n                writerLeaseToken: writerLeaseToken,',
             'expectedGenerationEpoch: otherEpoch,\n                writerLeaseToken: writerLeaseToken,'),
            ('writerLeaseToken: writerLeaseToken,\n                registry: registry',
             'writerLeaseToken: otherToken,\n                registry: registry'),
            ('writerLeaseToken: writerLeaseToken,\n                registry: registry',
             'writerLeaseToken: writerLeaseToken,\n                registry: otherRegistry'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(path, declaration, old, new),
                                  'current recovery identity/lease/branch')

    def test_full_reader_binds_original_erase_owner_begin_recovery_finish_and_failure(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        declaration = 'private static func constructWriter('
        for old, new in (
            ('try owner.operation.beginOriginalEraseWriterRecovery(\n                registry: registry, activity: owner.activity,\n                targetAllocation: owner.targetAllocation,\n                targetHandle: leaseHandle)',
             'try anotherOperation.beginOriginalEraseWriterRecovery(\n                registry: registry, activity: owner.activity,\n                targetAllocation: owner.targetAllocation,\n                targetHandle: leaseHandle)'),
            ('try owner.operation.beginOriginalEraseWriterRecovery(\n                registry: registry, activity: owner.activity,',
             'try owner.operation.beginOriginalEraseWriterRecovery(\n                registry: registry, activity: differentActivity,'),
            ('.recoverBeforeOriginalEraseTargetWriterActivation(\n                    activity: owner.activity, operation: owner.operation,\n                    targetAllocation: owner.targetAllocation,',
             '.recoverBeforeOriginalEraseTargetWriterActivation(\n                    activity: owner.activity, operation: owner.operation,\n                    targetAllocation: differentAllocation,'),
            ('try owner.operation.finishOriginalEraseWriterRecovery(\n                    receipt,',
             'try owner.operation.finishOriginalEraseWriterRecovery(\n                    anotherReceipt,'),
            ('owner.operation.failOriginalEraseWriterRecovery()\n                throw error',
             'owner.operation.failOriginalEraseWriterRecovery()\n                return differentBinding'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(path, declaration, old, new),
                                  'current recovery identity/lease/branch')

    def test_full_reader_rejects_alternate_branch_and_early_recovery_success(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        call = 'try recovery.recoverBeforeWriterActivation()'
        for replacement in ('if false { ' + call + ' }', 'if true { return differentBinding }; ' + call):
            with self.subTest(replacement=replacement):
                self.full_refusal(self.changed(path, call, replacement), 'current recovery identity/lease/branch')
        recovery = PERSISTENCE + 'MutationJournal/MutationReceiptRecoveryServiceV1.swift'
        for declaration, old, replacement, reason in (
            ('func recoverBeforeWriterActivation()', 'guard C50IncumbentFileExchangeRecoveryBoundaryV1.validate() else',
             'if true { return }; guard C50IncumbentFileExchangeRecoveryBoundaryV1.validate() else', 'authorized ordinary recovery'),
            ('func recoverBeforeOriginalEraseTargetWriterActivation(', 'activity: activity, operation: operation,',
             'activity: activity, operation: differentOperation,', 'authorized original Erase recovery'),
            ('private func recoverCanonicalJournal()', 'try store.validateAll()',
             'if true { return }; try store.validateAll()', 'validated current canonical recovery'),
        ):
            with self.subTest(declaration=declaration):
                self.full_refusal(self.scoped_changed(recovery, declaration, old, replacement), reason)

    def test_full_reader_rejects_concrete_v53_version_model_and_each_release_dispatch_drift(self) -> None:
        path = PERSISTENCE + 'PersistentSchemas.swift'
        for old, new in (
            ('Schema.Version(53,0,0)', 'Schema.Version(53,1,0)'),
            ('PersistentSchemaV52.models+[LightingNightWorkflowRowV1.self]',
             'PersistentSchemaV51.models+[LightingNightWorkflowRowV1.self]'),
            ('PersistentSchemaV52.models+[LightingNightWorkflowRowV1.self]', 'PersistentSchemaV52.models'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(path, 'enum PersistentSchemaV53:', old, new),
                                  'concrete current V53 schema/version/models')
        for declaration, old, new in (
            ('var versionIdentifier: Schema.Version', 'case .v53:return PersistentSchemaV53.versionIdentifier',
             'case .v53:return PersistentSchemaV52.versionIdentifier'),
            ('var predecessorVersionIdentifier: Schema.Version?', 'case .v53:return PersistentSchemaV52.versionIdentifier',
             'case .v53:return PersistentSchemaV51.versionIdentifier'),
            ('var models: [any PersistentModel.Type]', 'case .v53:return PersistentSchemaV53.models',
             'case .v53:return PersistentSchemaV52.models'),
            ('static func activeSchema()', 'Schema(PersistentSchemaV53.models,version:PersistentSchemaV53.versionIdentifier)',
             'Schema(PersistentSchemaV52.models,version:PersistentSchemaV53.versionIdentifier)'),
        ):
            with self.subTest(declaration=declaration):
                # Property names repeat in the file; bind the real release enum first.
                owner = 'enum PersistentSchemaReleaseV1:' if declaration.startswith('var ') else declaration
                self.full_refusal(self.scoped_changed(path, owner, old, new), 'genuine current')

    def test_full_reader_rejects_permissive_schema_admission_or_fallback_and_early_success(self) -> None:
        for old, new in (
            ('records: records.recordsSchemaVersion)', 'records: records.recordsSchemaVersion) || true'),
            ('manifest.source.recordsSchemaVersion == records.recordsSchemaVersion',
             'true || manifest.source.recordsSchemaVersion == records.recordsSchemaVersion'),
            ('manifest.source.recordsSchemaVersion == records.recordsSchemaVersion',
             'if true { return true }; return manifest.source.recordsSchemaVersion == records.recordsSchemaVersion'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(BACKUP_CONTRACTS, 'static func matches(', old, new),
                                  'manifest actual record version matching')
        validator = BACKUP + 'BackupPackageValidatorV1.swift'
        for old, new in (
            ('schemaPairIsValid,', 'schemaPairIsValid || true,'),
            ('} ?? false', '} ?? true'),
            ('let zero = UUID', 'if true { return }; let zero = UUID'),
            ('throw BackupPackageValidationErrorV1.invalidPackage', 'return'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(validator, 'func validateManifestBounds(', old, new),
                                  'package current/historical tuple and identity rejection')

    def test_full_reader_rejects_digest_condition_bypass_rejection_fallback_and_checkpoint_early_success(self) -> None:
        for declaration, old, new, reason in (
            ('func installImportedCheckpoint(', 'Self.rawSHA256(destination.semanticRecordsData)\n                == checkpoint.manifest.normalizedRecordsSHA256 else',
             'Self.rawSHA256(destination.semanticRecordsData)\n                == checkpoint.manifest.normalizedRecordsSHA256 || true else', 'checkpoint destination integrity'),
            ('func installImportedCheckpoint(', 'export.packageSHA256 == Self.rawSHA256(packageData) else',
             'export.packageSHA256 == Self.rawSHA256(packageData) || true else', 'checkpoint imported raw binding'),
            ('func installImportedCheckpoint(', 'throw ChangeJournalFailureV1.tamperedBatch',
             'return', 'checkpoint imported raw binding'),
            ('func installImportedCheckpoint(', 'try export.validate()',
             'if true { return differentReceipt }; try export.validate()', 'checkpoint destination integrity'),
            ('private func makeCheckpoint(', 'recordsEntry.sha256 == Self.rawSHA256(basis.recordsData) else',
             'recordsEntry.sha256 == Self.rawSHA256(basis.recordsData) || true else', 'checkpoint creation raw digest'),
            ('private func makeCheckpoint(', 'throw ChangeJournalFailureV1.invalidDigest',
             'return differentCheckpoint', 'checkpoint creation integrity|checkpoint creation raw digest'),
            ('private func makeCheckpoint(', 'let basis = try backupExport.canonicalCheckpointBasis()',
             'if true { return differentCheckpoint }; let basis = try backupExport.canonicalCheckpointBasis()', 'checkpoint creation integrity'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(reader.JOURNAL, declaration, old, new), reason)

    def test_full_reader_rejects_retry_source_digest_or_marker_permissive_success(self) -> None:
        path = PERSISTENCE + 'StoreGenerationFactory.swift'
        for declaration, old, new, reason in (
            ('private func performAdjacentCloneMigration(',
             'guard (try adjacentSemanticDigest(in: context, release: .v3, aggregate: aggregate)) == expectedSemanticDigest else',
             'guard (try adjacentSemanticDigest(in: context, release: .v3, aggregate: aggregate)) == expectedSemanticDigest || true else', 'V3 retry'),
            ('private func requireV4Marker(',
             'expectedMigrationID.map({ marker.migrationID == $0 }) ?? true else',
             '(expectedMigrationID.map({ marker.migrationID == $0 }) ?? true) || true else', 'V4 frozen marker'),
            ('private func backfillV4MutationState(', 'let markers = try context.fetch(',
             'if true { return }; let markers = try context.fetch(', 'idempotent V4 marker retry'),
        ):
            with self.subTest(declaration=declaration):
                self.full_refusal(self.scoped_changed(path, declaration, old, new), reason)

    def test_full_reader_rejects_erase_string_only_history_and_disposal_decoys(self) -> None:
        published = 'internal static func requireEmptyErasePublishedGraph('
        guard = 'guard history.workspaceRevision == 0, history.lastLocalSequence == 0,'
        source = self.scoped_changed(ERASE, published, guard,
                                     'let historyDecoy = #"guard history.workspaceRevision == 0, history.lastLocalSequence == 0,"#\n'
                                     '        guard true,')
        self.full_refusal(source, 'published empty current generation history')
        old = '''try generationFactory.removeInstalledGeneration(
                    id: id,
                    keeping: intent.newGenerationID,
                    authority: authority
                )'''
        for replacement in ('_ = "try generationFactory.removeInstalledGeneration(id: id, keeping: intent.newGenerationID, authority: authority)"',
                            '_ = #"""\n' + old + '\n"""#'):
            with self.subTest(replacement=replacement):
                self.full_refusal(self.scoped_changed(ERASE, 'func cleanupGenerations(', old, replacement),
                                  'whole generation Erase disposal and inventory closure')

    def test_full_reader_binds_erase_history_calls_and_complete_rejection_and_disposal(self) -> None:
        for declaration, old, new, reason in (
            ('internal static func requireEmptyErasePublishedGraph(', 'identity: identity, generationID: generationID,',
             'identity: identity, generationID: UUID(),', 'published empty current generation history'),
            ('internal static func requireEmptyErasePublishedGraph(', 'history.entityRevisions.isEmpty, !context.hasChanges else',
             'history.entityRevisions.isEmpty, !context.hasChanges || true else', 'published empty current generation history'),
            ('internal static func requireEmptyErasePublishedGraph(', 'try requireEmptyEraseContent(',
             'if true { return }; try requireEmptyEraseContent(', 'published empty current generation history'),
            ('func validateEmptyGenerationRows(', 'generationID: id, allowStateBootstrap: allowStateBootstrap',
             'generationID: UUID(), allowStateBootstrap: allowStateBootstrap', 'all empty generation history dimensions'),
            ('func cleanupGenerations(', 'let initialRetired = try authority.retiredGenerationIDs()',
             'if true { return }; let initialRetired = try authority.retiredGenerationIDs()', 'whole generation Erase disposal'),
            ('func cleanupGenerations(', 'initialRetired.isEmpty else',
             'initialRetired.isEmpty || true else', 'whole generation Erase current/retired target authority'),
            ('func advance() async throws -> Bool', 'keeping: intent.newGenerationID, retirement: proof)',
             'keeping: intent.newGenerationID, retirement: differentProof)', 'retained Erase exact frozen old root inventory|retained original Erase'),
            ('func advance() async throws -> Bool', 'if phase == .prepared {',
             'if true { return true }; if phase == .prepared {', 'retained original Erase'),
            ('func advance() async throws -> Bool', 'guard retired == intent.generationIDsToDelete || retired.isEmpty else',
             'guard retired == intent.generationIDsToDelete || retired.isEmpty || true else', 'retained original Erase'),
        ):
            with self.subTest(declaration=declaration, mutation=new):
                self.full_refusal(self.scoped_changed(ERASE, declaration, old, new), reason)

    def test_full_reader_refuses_implicit_extra_command_and_schema_support_success_bypasses(self) -> None:
        source = self.scoped_changed(MUTATION_CONTRACTS, 'enum WorkspaceCommandKindV1:',
                                     'case createFirstSign = "create_first_sign"',
                                     'case implicitExtraCommand\n    case createFirstSign = "create_first_sign"')
        self.full_refusal(source, 'closed ordered63 commands')
        for old, new in (
            ('return backup == 4 && v4Pairs.contains {', 'return true || backup == 4 && v4Pairs.contains {'),
            ('switch (backup, persistent, records) {', 'if true { return true }; switch (backup, persistent, records) {'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(BACKUP_CONTRACTS,
                                  'static func supports(backup: Int, persistent: Int, records: Int)', old, new),
                                  'tuple admission must remain exact and fail closed')

    def test_full_reader_refuses_history_transport_and_canonical_decode_rejection_fallbacks(self) -> None:
        path = BACKUP + 'BackupCanonicalEncoderV1.swift'
        source = self.scoped_changed(path, 'private static func recordFields(\n        _ records: V4BackupRecordsV1,',
                                     'mutationHistory,\n                receiptStableKeys: ordinaryValidation?.receiptStableKeys',
                                     'differentHistory,\n                receiptStableKeys: ordinaryValidation?.receiptStableKeys')
        self.full_refusal(source, 'ordinary backup transport retains mutation history')
        path = BACKUP + 'BackupCanonicalDecoderV1.swift'
        for old, new in (
            ('guard legacy == data else', 'guard legacy == data || true else'),
            ('guard legacy == data else {\n                    throw BackupCanonicalDecodingErrorV1.invalidRecords',
             'guard legacy == data else {\n                    return (value, BackupCanonicalRecordsValidationFactsV1(records: value, canonicalData: data))'),
        ):
            with self.subTest(mutation=new):
                self.full_refusal(self.scoped_changed(path, 'func decodeRecordsWithFacts(', old, new),
                                  'strict full backup canonical decode history seam')

    def wrapped_owned_seam(self, path: str, declaration: str, head: str, *,
                           guard: bool = False, alternate: bool = False,
                           wrapper: str = 'if false') -> dict[str, str]:
        """Retain the actual complete seam, changing only its execution ancestor."""
        original = self.source[path]
        _, structural = reader.swift_masks(original)
        self.assertEqual(structural.count(declaration), 1)
        owner = structural.index('{', structural.index(declaration) + len(declaration))
        owner_end = owner + len(reader.block(original, declaration)) + 1
        scope = structural[owner + 1:owner_end]
        self.assertEqual(scope.count(head), 1, f'actual owned seam must be unique: {head}')
        start = owner + 1 + scope.index(head)
        if guard:
            rejection = re.search(r'\belse\s*\{', structural[start:owner_end])
            self.assertIsNotNone(rejection)
            brace = start + rejection.end() - 1
        else:
            brace = structural.index('{', start + len(head), owner_end)

        def end_of_body(opening: int) -> int:
            depth = 1
            for position in range(opening + 1, owner_end):
                depth += (structural[position] == '{') - (structural[position] == '}')
                if depth == 0:
                    return position + 1
            self.fail('hostile baseline body must close inside its owner')

        end = end_of_body(brace)
        if alternate:
            other = re.match(r'\s*else\s*\{', structural[end:owner_end])
            self.assertIsNotNone(other)
            end = end_of_body(end + other.end() - 1)
        actual = original[start:end]
        if wrapper.startswith('#'):
            replacement = wrapper + '\n' + actual + '\n#endif'
        elif wrapper == 'unused closure':
            replacement = 'let ignoredCurrentValidation = { () throws -> Void in\n' + actual + '\n}'
        elif wrapper == 'unused projection closure':
            replacement = 'let ignoredCurrentProjection = { () throws -> Data? in\n' + actual + '\nreturn nil\n}'
        else:
            self.assertEqual(wrapper, 'if false')
            replacement = 'if false {\n' + actual + '\n}'
        source = dict(self.source)
        source[path] = original[:start] + replacement + original[end:]
        self.assertNotEqual(source[path], original)
        return source

    def test_full_reader_refuses_false_conditional_original_erase_recovery_branch(self) -> None:
        source = self.wrapped_owned_seam(PERSISTENCE + 'StoreSessionCoordinator.swift',
                                        'private static func constructWriter(',
                                        'if let owner = originalEraseRecovery',
                                        alternate=True, wrapper='#if false')
        self.full_refusal(source, 'supported Swift conditional grammar')

    def test_full_reader_refuses_unsupported_directives_even_inside_excluded_debug(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        declaration = 'private static func constructWriter('
        for replacement in (
            '#if true\n', '#if canImport(Foundation)\n', '#if !DEBUG\n',
            '#if DEBUG || OTHER_FLAG\n', '#if DEBUG #"extra operand"#\n',
            '#if DEBUG\n#if false\n#endif\n',
            '#if DEBUG\n#elseif false\n', '#if DEBUG\n#elseif DEBUG\n',
            '#if DEBUG\n#elseif canImport(Foundation)\n',
            '#if DEBUG\n#else DEBUG\n', '#if DEBUG\n#else\n#else\n',
            '#if DEBUG\n#warning("unused diagnostic directive")\n',
        ):
            with self.subTest(directive=replacement):
                self.full_refusal(self.scoped_changed(path, declaration, '#if DEBUG\n', replacement),
                                  'supported Swift conditional grammar')
        self.full_refusal(self.scoped_changed(path, declaration, '#endif\n', '#endif DEBUG\n'),
                          'supported Swift conditional grammar')

    def test_full_reader_refuses_false_or_unused_closure_standalone_guard_owners(self) -> None:
        cases = (
            (reader.JOURNAL, 'private func makeCheckpoint(', 'guard basis.workspaceIdentity',
             'checkpoint creation identity'),
            (reader.JOURNAL, 'private func makeCheckpoint(', 'guard basis.memberInventory.map',
             'checkpoint creation raw digest'),
            (reader.JOURNAL, 'private func makeCheckpoint(', 'guard basis.workspaceRevision',
             'checkpoint creation frontier'),
            (reader.JOURNAL, 'private func makeCheckpoint(', 'guard Set(supplement.reversalEligibility',
             'checkpoint creation reversal'),
            (reader.JOURNAL, 'private func makeCheckpoint(', 'guard expectedContentIDs.isSubset',
             'checkpoint creation complete content'),
            (reader.JOURNAL, 'func installImportedCheckpoint(', 'guard export.workspaceID',
             'checkpoint imported raw binding'),
            (reader.JOURNAL, 'func installImportedCheckpoint(', 'guard try WorkspaceMutationCanonicalV1.data',
             'checkpoint imported canonical binding'),
            (reader.JOURNAL, 'func installImportedCheckpoint(', 'guard destination.workspaceIdentity',
             'checkpoint destination integrity'),
            (ERASE, 'internal static func requireEmptyErasePublishedGraph(', 'guard history.workspaceRevision',
             'published empty current generation history'),
        )
        for path, declaration, head, reason in cases:
            for wrapper in ('if false', 'unused closure'):
                with self.subTest(owner=declaration, seam=head, wrapper=wrapper):
                    source = self.wrapped_owned_seam(path, declaration, head, guard=True, wrapper=wrapper)
                    self.full_refusal(source, reason + ': current control-flow ownership differs')

    def test_full_reader_refuses_false_or_unused_closure_critical_subblock_owners(self) -> None:
        cases = (
            (PERSISTENCE + 'StoreGenerationFactory.swift', 'private func semanticProjection(in context: ModelContext,',
             'if release == .v3 ', 'current V3 projection helper dispatch', 'unused projection closure'),
            (BACKUP + 'BackupCanonicalEncoderV1.swift', 'private static func recordFields(\n        _ records: V4BackupRecordsV1,',
             'if let mutationHistory = records.mutationHistory',
             'ordinary backup transport retains mutation history', 'unused closure'),
            (BACKUP + 'BackupCanonicalDecoderV1.swift', 'func decodeRecordsWithFacts(',
             'if canonical != data', 'strict full backup canonical decode history seam', 'unused closure'),
            (ERASE, 'func validateEmptyGenerationRows(', 'if let identity',
             'all empty generation history dimensions', 'unused closure'),
        )
        for path, declaration, head, reason, unused in cases:
            for wrapper in ('if false', unused):
                with self.subTest(owner=declaration, seam=head, wrapper=wrapper):
                    source = self.wrapped_owned_seam(path, declaration, head, wrapper=wrapper)
                    self.full_refusal(source, reason + ': current control-flow ownership differs')

    def test_debug_only_probe_operand_change_preserves_actual_production_source_admission(self) -> None:
        path = PERSISTENCE + 'StoreSessionCoordinator.swift'
        original = '''try owner.operation.beginOriginalEraseWriterRecovery(
                            registry: registry, activity: owner.activity,
                            targetAllocation: foreign, targetHandle: leaseHandle)'''
        replacement = original.replace('targetAllocation: foreign,', 'targetAllocation: owner.targetAllocation,')
        source = self.scoped_changed(path, 'private static func constructWriter(', original, replacement)
        inputs = dict(self.inputs)
        inputs.update(source)
        reader.verify_inputs(inputs)


    def test_full_reader_rejects_generic_dictionary_uses_outside_exact_transient_declarations(self) -> None:
        spellings = ('[String: Any]', '[ String : Any ]',
                     '[String /* typed spelling */: Any]', 'Dictionary<String, Any>')
        paths = (BACKUP + 'BackupCanonicalEncoderV1.swift',
                 BACKUP + 'BackupRestoreService.swift', ERASE,
                 'FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift')
        for path in paths:
            for spelling in spellings:
                with self.subTest(path=path, spelling=spelling):
                    source = dict(self.source)
                    source[path] += '\nprivate func c69UnboundDictionary(_ value: Any) -> Bool {\n'
                    source[path] += '    value is ' + spelling + '\n}\n'
                    self.full_refusal(source, 'current transient JSON use census differs')

    def test_full_reader_rejects_extra_casts_inside_every_permitted_transient_scope(self) -> None:
        cases = (
            (BACKUP + 'BackupCanonicalEncoderV1.swift', 'static func canonicalPartsStockJSON(',
             'if value is NSNull { return .null }'),
            (BACKUP + 'BackupRestoreService.swift', 'func replacingPartsStockSnapshot(',
             'try snapshot.validate()'),
            (BACKUP + 'BackupRestoreService.swift', 'private func readPhotoBindingLeaf(',
             'let name = try resolvedRemovalClaimName(requestedName, parent: parent)'),
            (BACKUP + 'BackupRestoreService.swift', 'private func traceRestoreRecordDifferences(', '#if DEBUG'),
        )
        for path, declaration, anchor in cases:
            extra = '\n        let unbound: [String: Any] = [:]\n        _ = unbound\n'
            new = anchor + extra if anchor == '#if DEBUG' else extra + anchor
            with self.subTest(declaration=declaration):
                self.full_refusal(self.scoped_changed(path, declaration, anchor, new),
                                  'current transient JSON .*complete conversion/comparison proof')

    def test_full_reader_rejects_canonical_and_typed_transient_conversion_drift(self) -> None:
        cases = (
            (BACKUP + 'BackupCanonicalEncoderV1.swift', 'static func canonicalPartsStockJSON(',
             'return .object(try value.mapValues(canonicalPartsStockJSON))', 'return .object([:])'),
            (BACKUP + 'BackupCanonicalEncoderV1.swift', 'static func canonicalPartsStockJSON(',
             'guard CFGetTypeID(value) != CFBooleanGetTypeID() else', 'guard true else'),
            (BACKUP + 'BackupCanonicalEncoderV1.swift', 'static func canonicalPartsStockJSON(',
             '!representation.contains("e"),', 'true,'),
            (BACKUP + 'BackupRestoreService.swift', 'func replacingPartsStockSnapshot(',
             'try snapshot.validate()', '_ = snapshot'),
            (BACKUP + 'BackupRestoreService.swift', 'func replacingPartsStockSnapshot(',
             'object["partsStockSnapshot"]', 'object["ignoredPartsStock"]'),
            (BACKUP + 'BackupRestoreService.swift', 'func replacingPartsStockSnapshot(',
             'return try decoder.decode(V4BackupRecordsV1.self, from: data)', 'return records'),
        )
        for path, declaration, old, new in cases:
            with self.subTest(declaration=declaration, mutation=old):
                self.full_refusal(self.scoped_changed(path, declaration, old, new),
                                  'current transient JSON .*complete conversion/comparison proof')

    def test_full_reader_rejects_legacy_photo_metadata_dictionary_boundary_drift(self) -> None:
        path = BACKUP + 'BackupRestoreService.swift'
        declaration = 'private func readPhotoBindingLeaf('
        for old, new in (
            ('if allowLegacy, let object', 'if true, let object'),
            ('object["schemaVersion"] as? Int == 1', 'object["schemaVersion"] as? Int != nil'),
            ('try legacy.validate()', '_ = legacy'),
            ('before.st_size > 0, before.st_size <= maximum else', 'before.st_size > 0, true else'),
            ('return nil\n        }\n        let value',
             'return try readPhotoBindingLeaf(requestedName, parent: parent, allowLegacy: false, verify: verify)\n        }\n        let value'),
        ):
            with self.subTest(mutation=old):
                self.full_refusal(self.scoped_changed(path, declaration, old, new),
                                  'current transient JSON .*complete conversion/comparison proof')
        self.full_refusal(self.changed(path,
            'allowLegacy: Bool = false, verify: () throws -> Void) throws -> PhotoBindingLeaf?',
            'allowLegacy: Bool = true, verify: () throws -> Void) throws -> PhotoBindingLeaf?'),
            'current transient JSON .*typed signature')

    def test_full_reader_rejects_debug_dictionary_comparison_scope_or_equality_drift(self) -> None:
        path = BACKUP + 'BackupRestoreService.swift'
        declaration = 'private func traceRestoreRecordDifferences('
        original = self.source[path]
        _, structural = reader.swift_masks(original)
        start = structural.index('{', structural.index(declaration) + len(declaration))
        end = start + len(reader.block(original, declaration)) + 1
        actual = original[start + 1:end]
        self.assertEqual(actual.count('#if DEBUG'), 1)
        self.assertEqual(actual.count('#endif'), 1)
        moved = actual.replace('#if DEBUG', '', 1).replace('#endif', '', 1)
        self.full_refusal(self.scoped_changed(path, declaration, actual, moved),
                          'current transient JSON .*complete conversion/comparison proof')
        for old, new in (
            ('let equal = actualValue?.isEqual(expectedValue) ?? (expectedValue == nil)', 'let equal = true'),
            ('let actualObject = (try? JSONSerialization.jsonObject(with: actualData))',
             'let actualObject = (try? JSONSerialization.jsonObject(with: expectedData))'),
        ):
            with self.subTest(mutation=old):
                self.full_refusal(self.scoped_changed(path, declaration, old, new),
                                  'current transient JSON .*complete conversion/comparison proof')

    def test_full_reader_rejects_transient_declaration_literal_decoys_and_false_scope(self) -> None:
        path = BACKUP + 'BackupCanonicalEncoderV1.swift'
        original = self.source[path]
        declaration = 'static func canonicalPartsStockJSON('
        _, structural = reader.swift_masks(original)
        position = structural.index(declaration)
        start = structural.index('{', position + len(declaration))
        end = start + len(reader.block(original, declaration)) + 2
        complete = original[position:end]
        source = self.changed(path, declaration, 'static func unboundPartsStockJSON(')
        source[path] += '\nprivate let c69IgnoredDeclaration = #"""\n' + complete + '\n"""#\n'
        self.full_refusal(source, 'current transient JSON .*unique typed declaration missing')
        # Keep the genuine signature/body but exclude its whole private extension
        # with an unsupported Swift conditional. Its raw dictionary count stays1.
        owner = structural.rfind('private extension BackupCanonicalEncoderV1', 0, position)
        self.assertGreaterEqual(owner, 0)
        body_start = structural.index('{', owner)
        owner_end = body_start + len(reader.delimiter_body(
            original, structural, body_start, '{', '}')) + 2
        source = dict(self.source)
        source[path] = original[:owner] + '#if false\n' + original[owner:owner_end] + '\n#endif' + original[owner_end:]
        self.full_refusal(source, 'supported Swift conditional grammar')

    def test_full_reader_keeps_absolute_json_patch_and_prohibited_field_scans_in_transient_and_erase_scopes(self) -> None:
        for path in (BACKUP + 'BackupCanonicalEncoderV1.swift', BACKUP + 'BackupRestoreService.swift', ERASE):
            with self.subTest(path=path, forbidden='JSONPatch'):
                source = dict(self.source)
                source[path] += '\nprivate let c69ForbiddenPatch = "JSONPatch"\n'
                self.full_refusal(source, 'generic JSON or JSON Patch persistence introduced')
            for prohibited in reader.PROHIBITED_FIELDS:
                with self.subTest(path=path, forbidden=prohibited):
                    source = dict(self.source)
                    source[path] += '\n// ' + prohibited + '\n'
                    self.full_refusal(source, 'prohibited remote/account field present in C02 source: ' + prohibited)

if __name__ == '__main__':
    unittest.main()
