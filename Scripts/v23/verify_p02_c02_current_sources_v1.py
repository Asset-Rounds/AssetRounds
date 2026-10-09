#!/usr/bin/env python3
"""Versioned current Source reader for the C02 persistence seams.

Source inspection only: no generator, historical card rebind, native execution,
receipt qualification, schema activation or product eligibility decision.
Historical verify_p02_c02_contracts.py and its generated artifacts remain intact.
This reader admits the explicit current (archive, persistent, records) tuple;
it never interprets a schema number as authorization for a new backup pair.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Mapping

sys.dont_write_bytecode = True

from p02_c02_contracts import (
    CARD, COMMAND_KINDS, EVIDENCE_IDS, LIFECYCLE_DOC, PROHIBITED_FIELDS,
    SOURCE_PATHS, ContractError, lifecycle_contract,
)

READER_VERSION = "p02-c02-current-sources-v4"
CURRENT_TUPLE = (4, 53, 52)
HISTORICAL_TUPLE = (3, 4, 3)
HISTORICAL_READER = "Scripts/v23/verify_p02_c02_contracts.py"
HISTORICAL_READER_SHA256 = "263ad480ed2b58d431d00a1b1d1b22cdf74242c04bf46c5079c7278b1cd7b3b5"
HISTORICAL_CONTRACT = "Scripts/v23/p02_c02_contracts.py"
HISTORICAL_CONTRACT_SHA256 = "f0ce0f0950bc3dc3dcaa1c5e8f47ec1efa121e41b04ecacab180ad981d1950da"
CURRENT_AUTHORITY = "docs/design/v23/tooling/V23P04C18LightingNightWorkflowContractV1.json"
RELEASE_AUTHORITY = "docs/design/v23/tooling/PersistentSchemaReleaseRegistryV1.json"
FIXTURE = "FieldEvidenceAppTests/Fixtures/V21/Mutation/V21P02C02MutationEnvelopeReceiptCorpusV1.json"
READER_PATH = "Scripts/v23/verify_p02_c02_current_sources_v1.py"
TEST_PATH = "Scripts/v23/test_verify_p02_c02_current_sources_v1.py"
JOURNAL = "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift"
CATALOG = "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift"
CHECKPOINT_CONTRACTS = "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift"
CHECKPOINT_TESTS = "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift"
EXTRA_SOURCE_PATHS = (JOURNAL, CATALOG, CHECKPOINT_CONTRACTS, CHECKPOINT_TESTS)
# Closed dependency roster for this reader, including its historical provenance.
# The historical generator and card manifest are not executed or regenerated.
INPUT_PATHS = tuple(SOURCE_PATHS) + EXTRA_SOURCE_PATHS + (
    HISTORICAL_READER, HISTORICAL_CONTRACT, LIFECYCLE_DOC, CURRENT_AUTHORITY,
    RELEASE_AUTHORITY, READER_PATH, TEST_PATH,
)

HISTORICAL_TESTS = (
    "testV10_02G01CanonicalEnvelopeReceiptBytesAndAtomicCommit",
    "testV10_02A01RestartReplayChangedHashQuarantineAndSequence",
    "testV10_02H01StaleForeignUnknownTamperedSequenceAndReversalRejection",
    "testV10_02I01EveryAtomicCrashBoundaryRecoversExactlyOnce",
    "testV10_02R01MigrationLifecycleAndReplicaIdentityMatrix",
)
CURRENT_TESTS = (
    HISTORICAL_TESTS[0],
    "testV10_02G01TemporalReceiptRetainsPortableGenerationAndRevisionAuthority",
    *HISTORICAL_TESTS[1:],
)

CURRENT_COMMANDS = (
    'create_first_sign',
    'begin_check_draft',
    'capture_evidence',
    'confirm_site_timezone',
    'delete_asset',
    'delete_site',
    'erase_workspace',
    'finalize_check',
    'finalize_correction',
    'transition_report_pdf',
    'record_work',
    'restore_workspace',
    'archive_entities_preview_compensation',
    'apply_location_hierarchy_change',
    'apply_asset_placement_change',
    'apply_asset_composition_change',
    'apply_saved_smart_view',
    'apply_requirement_assurance',
    'apply_party_accountability',
    'apply_party_contact_site_role_import',
    'apply_asset_semantics',
    'apply_authority_criterion',
    'apply_functional_relationship',
    'apply_evidence_assurance',
    'apply_inspection_review',
    'apply_work_packet',
    'apply_field_draft',
    'apply_package_promotion',
    'apply_measurement_integrity',
    'apply_privacy_transform',
    'apply_evidence_metadata_v1',
    'apply_client_capability',
    'apply_field_reference',
    'apply_accessible_document_assessment',
    'apply_survey_definition',
    'apply_survey_session',
    'apply_asset_locator',
    'apply_schedule',
    'apply_plan',
    'apply_placement_pose',
    'apply_evidence_context',
    'apply_lighting',
    'apply_lighting_day_inventory',
    'apply_lighting_night_workflow',
    'apply_assistance_acceptance',
    'apply_temporal_evidence',
    'apply_asset_label',
    'apply_operational_contact',
    'apply_activity_contract_v2',
    'apply_portable_review_v1',
    'apply_work_resource_v1',
    'apply_parts_stock_v1',
    'apply_my_day_v1',
    'apply_service_request_v1',
    'apply_service_reliability_v1',
    'apply_shop_report_profile_v1',
    'apply_round_session_v1',
    'apply_import_bulk_v1',
    'apply_evidence_quality_v1',
    'apply_fast_survey_inbox_v1',
    'apply_reinspection_exception_v1',
    'apply_entity_identity_resolution_v1',
    'apply_workspace_experience_v1',
)

CURRENT_RECORD_FIELDS = (
    'acceptedLabelGenerationSnapshots',
    'accessibleDocumentAssessments',
    'activityContracts',
    'assetCompositionEdges',
    'assetCompositionEvents',
    'assetLocators',
    'assetPlacementEvents',
    'assetSemantics',
    'assets',
    'assistanceAcceptanceReceipts',
    'authorityCriterion',
    'bulkCommitReceipts',
    'bulkSessions',
    'clientCapabilities',
    'deletionLedger',
    'entityIdentityResolution',
    'evidenceAssociationEvents',
    'evidenceAssurance',
    'evidenceContexts',
    'evidenceFiles',
    'evidenceQuality',
    'evidenceSequenceRevisions',
    'fastSurveyInbox',
    'fieldDrafts',
    'fieldReferences',
    'functionalRelationships',
    'guidedSurveys',
    'importMappingProfiles',
    'inspectionReview',
    'issues',
    'lighting',
    'lightingDayInventoryWorkflows',
    'lightingNightWorkflows',
    'locationHierarchyEvents',
    'locationMigrationReceipts',
    'locationNodes',
    'measurementIntegrity',
    'mutationHistory',
    'myDayCarryoverReceipts',
    'myDayPlans',
    'nonactivePlanReferences',
    'operationalContacts',
    'packageEvolution',
    'packets',
    'pairedObservationLinks',
    'partsStockSnapshot',
    'partyAccountability',
    'placementPoses',
    'plans',
    'practiceWorkspaceProvenance',
    'privacyTransforms',
    'qualifiedServiceExposures',
    'recordsSchemaVersion',
    'recoverabilityReceipts',
    'reinspectionExceptionQueue',
    'reports',
    'requirementAssurance',
    'roundSessions',
    'savedSmartViews',
    'schedules',
    'serviceCauseAssertions',
    'serviceImpactSegments',
    'serviceReliabilityIncidents',
    'serviceReliabilityReceipts',
    'serviceRemedyAssertions',
    'serviceRepairIntervals',
    'serviceRequestDispositionEvents',
    'serviceRequestWorkLinkEvents',
    'serviceRequests',
    'serviceRestorationAssertions',
    'shopReportProfiles',
    'sites',
    'surveyDefinitions',
    'temporalEvidence',
    'workPackets',
    'workResources',
    'workflowRecords',
)

CURRENT_V4_PAIR_EXPRESSIONS = '(5,4),(6,5),(7,6),(8,7),(9,8),(10,9),(11,10),(12,11),(13,12),(14,13),(15,14),(16,15),(17,16),(18,17),(19,18),(20,19),(21,20),(22,21),(23,22),(24,23),(25,24),(26,25),(27,26),(28,27),(29,28),(30,29),(31,30),(32,31),(33,32),(34,33),(35,34),(36,35),(C49WorkResourcePersistenceBoundaryV1.persistentSchemaVersion,C49BackupEnrollmentV1.recordsSchemaVersion),(38,37),(C52ServiceRequestBackupEnrollmentV1.persistentSchemaVersion,C52ServiceRequestBackupEnrollmentV1.recordsSchemaVersion),(C53ServiceReliabilityBackupEnrollmentV1.persistentSchemaVersion,C53ServiceReliabilityBackupEnrollmentV1.recordsSchemaVersion),(C55PartsStockBackupEnrollmentV1.persistentSchemaVersion,C55PartsStockBackupEnrollmentV1.recordsSchemaVersion),(C57MyDayBackupEnrollmentV1.persistentSchemaVersion,C57MyDayBackupEnrollmentV1.recordsSchemaVersion),(C05EvidenceMetadataBackupEnrollmentV1.persistentSchemaVersion,C05EvidenceMetadataBackupEnrollmentV1.recordsSchemaVersion),(C04ShopReportProfileBackupEnrollmentV1.persistentSchemaVersion,C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion),(C05RoundSessionBackupEnrollmentV1.persistentSchemaVersion,C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion),(46,C08ImportBulkBackupEnrollmentV1.legacyRecordsSchemaVersion),(C08ImportBulkBackupEnrollmentV1.persistentSchemaVersion,C08ImportBulkBackupEnrollmentV1.recordsSchemaVersion),(FastSurveyInboxBackupEnrollmentV1.persistentSchemaVersion,FastSurveyInboxBackupEnrollmentV1.recordsSchemaVersion),(ReinspectionExceptionQueueBackupEnrollmentV1.persistentSchemaVersion,ReinspectionExceptionQueueBackupEnrollmentV1.recordsSchemaVersion),(EntityIdentityResolutionBackupEnrollmentV1.persistentSchemaVersion,EntityIdentityResolutionBackupEnrollmentV1.recordsSchemaVersion),(PracticeWorkspaceBackupEnrollmentV1.persistentSchemaVersion,PracticeWorkspaceBackupEnrollmentV1.recordsSchemaVersion),(LightingDayInventoryBackupEnrollmentV1.persistentSchemaVersion,LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion),(LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion),'


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def swift_masks(text: str) -> tuple[str, str]:
    """Keep offsets; ignore comments for pins and strings for balanced scopes.

    This is a bounded lexical reader, not a Swift compiler. It handles nested
    block comments and ordinary/triple/raw strings, rejecting unterminated input.
    """
    code, structure = list(text), list(text)
    i = 0
    while i < len(text):
        start = i
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            for j in range(start, i):
                code[j] = structure[j] = " "
        elif text.startswith("/*", i):
            depth = 1
            i += 2
            while i < len(text) and depth:
                if text.startswith("/*", i):
                    depth += 1
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            require(depth == 0, "unterminated Swift block comment")
            for j in range(start, i):
                if text[j] != "\n":
                    code[j] = structure[j] = " "
        else:
            raw = re.compile(r'(#+)?("""|")').match(text, i) if text[i] in '#"' else None
            if raw is not None:
                hashes = raw.group(1) or ""
                quote = raw.group(2)
                delimiter = quote + hashes
                i += len(raw.group(0))
                while i < len(text):
                    if text.startswith(delimiter, i):
                        i += len(delimiter)
                        break
                    if not hashes and text[i] == "\\":
                        i += 2
                    else:
                        i += 1
                else:
                    raise ContractError("unterminated Swift string")
                for j in range(start, i):
                    if text[j] != "\n":
                        structure[j] = " "
            else:
                i += 1
    return "".join(code), "".join(structure)


def block(text: str, declaration: str) -> str:
    code, structure = swift_masks(text)
    matches = [m.start() for m in re.finditer(re.escape(declaration), structure)]
    require(len(matches) == 1, f"unique declaration missing: {declaration}")
    start = structure.find("{", matches[0] + len(declaration))
    require(start >= 0, f"declaration body missing: {declaration}")
    depth = 1
    for end in range(start + 1, len(structure)):
        depth += (structure[end] == "{") - (structure[end] == "}")
        if depth == 0:
            return code[start + 1:end]
    raise ContractError(f"unclosed declaration body: {declaration}")


def compact(text: str) -> str:
    return ''.join(swift_tokens(text))


def swift_tokens(text: str) -> tuple[str, ...]:
    """Executable tokens and atomic literal operands; literal contents are never code."""
    code, structure = swift_masks(text)
    result = []
    i = 0
    identifier = re.compile(r'[A-Za-z_$][A-Za-z0-9_$]*|[0-9]+|===|!==|==|!=|>=|<=|&&|\|\||\.\.\.|->|\?\?')
    string_start = re.compile(r'(#+)?("""|")')
    while i < len(code):
        if code[i].isspace():
            i += 1
            continue
        literal = string_start.match(code, i) if structure[i] == ' ' else None
        if literal is not None:
            start = i
            hashes, quote = literal.group(1) or '', literal.group(2)
            delimiter = quote + hashes
            i = literal.end()
            while i < len(code):
                if code.startswith(delimiter, i):
                    i += len(delimiter)
                    break
                i += 2 if not hashes and code[i] == '\\' else 1
            else:
                raise ContractError('unterminated atomic Swift literal')
            result.append('LITERAL:' + code[start:i])
        else:
            match = identifier.match(code, i)
            if match is not None:
                result.append(match.group(0))
                i = match.end()
            else:
                result.append(code[i])
                i += 1
    return tuple(result)


def token_position(text: str, needle: str) -> int:
    actual, expected = swift_tokens(text), swift_tokens(needle)
    for start in range(len(actual) - len(expected) + 1):
        if actual[start:start + len(expected)] == expected:
            return start
    return -1


def pins(text: str, required: tuple[str, ...], label: str) -> None:
    for token in required:
        require(token_position(text, token) >= 0, f"{label}: missing {token}")


def ordered(text: str, tokens: tuple[str, ...], label: str) -> None:
    positions = [token_position(text, token) for token in tokens]
    require(all(p >= 0 for p in positions) and positions == sorted(set(positions)),
            f"{label}: required ordered seam differs")


def exact_body(actual: str, expected: str, label: str) -> None:
    require(swift_tokens(actual) == swift_tokens(expected), f'{label}: complete executable body differs')


def production(text: str) -> str:
    """Closed current DEBUG/else grammar; unsupported directives always refuse."""
    code, structural = swift_masks(text)
    raw_lines = text.splitlines(True)
    code_lines, structural_lines = code.splitlines(True), structural.splitlines(True)
    result = []
    stack = []
    for raw, coded, masked in zip(raw_lines, code_lines, structural_lines):
        directive = re.match(r'^\s*#([A-Za-z_][A-Za-z0-9_]*)\b(.*)', masked)
        if directive:
            kind, value = directive.group(1), directive.group(2).strip()
            if kind == 'if':
                require(value == 'DEBUG' and re.fullmatch(r'\s*#if\s+DEBUG\s*', coded) is not None,
                        'supported Swift conditional grammar: only exact #if DEBUG is admitted')
                stack.append({'enabled': False, 'sawElse': False})
            elif kind == 'else':
                require(value == '' and re.fullmatch(r'\s*#else\s*', coded) is not None
                        and bool(stack) and not stack[-1]['sawElse'],
                        'supported Swift conditional grammar: unmatched, duplicate or malformed #else')
                stack[-1] = {'enabled': True, 'sawElse': True}
            elif kind == 'endif':
                require(value == '' and re.fullmatch(r'\s*#endif\s*', coded) is not None and bool(stack),
                        'supported Swift conditional grammar: unmatched or malformed #endif')
                stack.pop()
            else:
                raise ContractError('supported Swift conditional grammar: unsupported #' + kind)
            continue
        if all(frame['enabled'] for frame in stack):
            result.append(raw)
    require(not stack, 'supported Swift conditional grammar: unclosed #if DEBUG scope')
    return ''.join(result)


def delimited(text: str, declaration: str, opening: str, closing: str) -> str:
    code, structure = swift_masks(text)
    matches = list(re.finditer(re.escape(declaration), structure))
    require(len(matches) == 1, f'unique executable declaration missing: {declaration}')
    start = structure.find(opening, matches[0].end())
    require(start >= 0, f'executable delimiter missing: {declaration}')
    return delimiter_body(code, structure, start, opening, closing)


def delimiter_body(code: str, structure: str, start: int, opening: str, closing: str) -> str:
    depth = 1
    for end in range(start + 1, len(structure)):
        depth += (structure[end] == opening) - (structure[end] == closing)
        if depth == 0:
            return code[start + 1:end]
    raise ContractError('unclosed executable delimiter')


def exact_call(text: str, callee: str, arguments: str, label: str) -> None:
    code, structure = swift_masks(text)
    matches = list(re.finditer(re.escape(callee) + r'\s*\(', structure))
    require(len(matches) == 1, f'{label}: unique production call missing: {callee}')
    actual = delimiter_body(code, structure, matches[0].end() - 1, '(', ')')
    require(swift_tokens(actual) == swift_tokens(arguments), f'{label}: bound call arguments differ: {callee}')


def branch_pair(text: str, declaration: str) -> tuple[str, str]:
    code, structure = swift_masks(text)
    matches = list(re.finditer(re.escape(declaration), structure))
    require(len(matches) == 1, f'unique real branch missing: {declaration}')
    start = structure.find('{', matches[0].end())
    require(start >= 0, f'real branch body missing: {declaration}')
    first = delimiter_body(code, structure, start, '{', '}')
    end = start + len(first) + 2
    alternate = re.match(r'\s*else\s*\{', structure[end:])
    require(alternate is not None, f'real alternate branch missing: {declaration}')
    return first, delimiter_body(code, structure, end + alternate.end() - 1, '{', '}')


def between(text: str, start: str, end: str) -> str:
    code, structure = swift_masks(text)
    starts = list(re.finditer(re.escape(start), structure))
    ends = list(re.finditer(re.escape(end), structure))
    require(len(starts) == len(ends) == 1 and starts[0].end() <= ends[0].start(),
            'unique executable ordered boundaries missing')
    return code[starts[0].end():ends[0].start()]


def literal_array(text: str, declaration: str, expected: tuple[str, ...], label: str) -> None:
    actual = delimited(text, declaration, '[', ']')
    wanted = ','.join(json.dumps(value) for value in expected)
    tokens = swift_tokens(actual)
    if tokens and tokens[-1] == ',':
        tokens = tokens[:-1]
    require(tokens == swift_tokens(wanted), f'{label}: bound literal array differs')


def exact_initializer(text: str, declaration: str, expected: str, label: str) -> None:
    code, structure = swift_masks(text)
    matches = list(re.finditer(re.escape(declaration), structure))
    require(len(matches) == 1, f'{label}: unique real value declaration missing')
    assignment = re.match(r'\s*=\s*', structure[matches[0].end():])
    require(assignment is not None, f'{label}: value initializer missing')
    start = matches[0].end() + assignment.end()
    depth = 0
    end = start
    while end < len(structure):
        if depth == 0 and structure[end] in ';\n':
            break
        depth += (structure[end] in '([{') - (structure[end] in ')]}')
        end += 1
    require(swift_tokens(code[start:end]) == swift_tokens(expected), f'{label}: concrete initializer differs')


def raw_enum_values(text: str) -> list[str]:
    code, structure = swift_masks(text)
    values = []
    for case in re.finditer(r'^\s*case\s+[A-Za-z_][A-Za-z0-9_]*\s*=', structure, re.M):
        operands = swift_tokens(code[case.end():])
        require(bool(operands) and operands[0].startswith('LITERAL:"'), 'enum real literal operand missing')
        literal = operands[0][len('LITERAL:'):]
        require(re.fullmatch(r'"(?:[^"\\]|\\.)*"', literal) is not None, 'enum plain literal operand differs')
        values.append(json.loads(literal))
    return values


def owned_depth(text: str, head: str, label: str, *, braces: int = 0) -> tuple[str, str, int]:
    """Bind the real current owner path after the closed production projection."""
    code, structural = swift_masks(production(text))
    matches = list(re.finditer(re.escape(head), structural))
    require(len(matches) == 1, f'{label}: unique real owned seam missing')
    start = matches[0].start()
    depth = {'{': 0, '(': 0, '[': 0}
    closing = {'}': '{', ')': '(', ']': '['}
    for character in structural[:start]:
        if character in depth:
            depth[character] += 1
        elif character in closing:
            opening = closing[character]
            depth[opening] -= 1
            require(depth[opening] >= 0, f'{label}: malformed current owner nesting')
    require(depth == {'{': braces, '(': 0, '[': 0}, f'{label}: current control-flow ownership differs')
    return code, structural, start


def exact_guard(text: str, head: str, condition: str, failure: str, label: str) -> None:
    code, structural, start = owned_depth(text, head, label)
    tail = structural[start:]
    else_match = re.search(r'\belse\s*\{', tail)
    require(else_match is not None, f'{label}: guard rejection branch missing')
    else_at = start + else_match.start()
    require(swift_tokens(code[start:else_at]) == swift_tokens('guard ' + condition),
            f'{label}: complete guard condition differs')
    brace = start + else_match.end() - 1
    rejected = delimiter_body(code, structural, brace, '{', '}')
    exact_body(rejected, failure, label + ' rejection')


def no_return_before(text: str, seam: str, label: str) -> None:
    guard_at = token_position(text, seam)
    require(guard_at >= 0 and 'return' not in swift_tokens(text)[:guard_at],
            f'{label}: early success before required seam')


def exact_current_case(text: str, expected: str, label: str) -> None:
    actual = swift_tokens(text)
    require(actual[:3] == ('switch', 'self', '{') and actual[-1:] == ('}',),
            f'{label}: closed dispatch body differs')
    _, structure = swift_masks(text)
    cases = re.findall(r'\bcase\s+\.v([0-9]+)\s*:', structure)
    require(cases == [str(v) for v in range(1, 54)], f'{label}: closed dispatch roster differs')
    at = token_position(text, 'case .v53:')
    require(at >= 0 and actual[at:-1] == swift_tokens(expected), f'{label}: concrete .v53 dispatch differs')


def verify_concrete_v53(schemas: str) -> None:
    concrete = block(schemas, 'enum PersistentSchemaV53:')
    exact_body(concrete, '''
        static let versionIdentifier = Schema.Version(53, 0, 0);
        static var models: [any PersistentModel.Type] {
            PersistentSchemaV52.models + [LightingNightWorkflowRowV1.self]
        }
    ''', 'concrete current V53 schema/version/models')
    release = block(schemas, 'enum PersistentSchemaReleaseV1:')
    for declaration, expected in (
        ('var compatibilityID: String', 'case .v53: return "LIGHTING_NIGHT_WORKFLOW_V1"'),
        ('var versionIdentifier: Schema.Version', 'case .v53: return PersistentSchemaV53.versionIdentifier'),
        ('var predecessorVersionIdentifier: Schema.Version?', 'case .v53: return PersistentSchemaV52.versionIdentifier'),
        ('var models: [any PersistentModel.Type]', 'case .v53: return PersistentSchemaV53.models'),
    ):
        exact_current_case(block(release, declaration), expected, 'genuine current persistent release')
    exact_body(block(schemas, 'static func activeSchema()'), '''
        try validate()
        return Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
    ''', 'genuine current active schema construction')


def load_inputs(root: Path) -> dict[str, str]:
    require(len(INPUT_PATHS) == len(set(INPUT_PATHS)), "reader input roster duplicated")
    inputs = {path: (root / path).read_bytes().decode("utf-8") for path in INPUT_PATHS}
    return inputs


def verify_authorities(inputs: Mapping[str, str]) -> dict[str, Any]:
    for path, digest in ((HISTORICAL_READER, HISTORICAL_READER_SHA256),
                         (HISTORICAL_CONTRACT, HISTORICAL_CONTRACT_SHA256)):
        require(hashlib.sha256(inputs[path].encode("utf-8")).hexdigest() == digest,
                f"historical reader/contract changed: {path}")
    lifecycle = json.loads(inputs[LIFECYCLE_DOC])
    require(lifecycle == lifecycle_contract(), "frozen C02 lifecycle changed")
    require(lifecycle["backup"]["manifestSchemaVersion"] == HISTORICAL_TUPLE[0]
            and lifecycle["schemaActivation"]["persistentSchemaVersion"] == HISTORICAL_TUPLE[1]
            and lifecycle["backup"]["recordsSchemaVersion"] == HISTORICAL_TUPLE[2],
            "historical archive/persistent/records tuple changed")
    require(lifecycle["evidenceIDs"] == EVIDENCE_IDS, "historical evidence IDs changed")
    current = json.loads(inputs[CURRENT_AUTHORITY])
    require(isinstance(current, dict), "current frozen authority must be an object")
    require(current.get("schema") == "V23P04C18LightingNightWorkflowContractV1"
            and current.get("schemaVersion") == 1 and current.get("cardID") == "V23-P04-C18",
            "current frozen authority identity differs")
    semantics = current.get("semantics", {})
    require(isinstance(semantics, dict), "current frozen semantics must be an object")
    require(semantics.get("persistentSchema") == "V53"
            and semantics.get("recordsSchemaVersion") == 52
            and semantics.get("activeModelCount") == 168
            and semantics.get("durableRecordFamilyCount") == 1
            and semantics.get("separateBackupFamily") == "V53BackupLightingNightWorkflowRecordV1",
            "current frozen schema/family census differs")
    expected_flags = {name: False for name in (
        "acceptance", "activation", "adoption", "hosted", "hostedAcceptance", "native",
        "nativeAcceptance", "phase10PollingDuringParallelExecution", "physicalEvidence", "publish", "release",
    )}
    observed_flags = semantics.get("statusFlags")
    require(isinstance(observed_flags, dict) and set(observed_flags) == set(expected_flags)
            and all(observed_flags[name] is False for name in expected_flags),
            "frozen authority credit flags differ")
    registry = json.loads(inputs[RELEASE_AUTHORITY])
    require(isinstance(registry, dict) and isinstance(registry.get("lifecycle"), dict),
            "historical registry/lifecycle must be objects")
    require(registry.get("lifecycle", {}).get("supersession") == "APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT"
            and "SOURCE_CHANGE" in registry["lifecycle"].get("successorTriggers", [])
            and "SCHEMA_RELEASE_CHANGE" in registry["lifecycle"].get("successorTriggers", []),
            "historical registry successor law differs")
    return json.loads(inputs[FIXTURE])

# Current transient Foundation dictionaries are conversion/comparison locals,
# not stored mutation effects. Each exact declaration, typed result, complete
# body and DEBUG projection is bound below; no file-wide exemption is granted.
TRANSIENT_JSON_PROOFS = (
    (
        'FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift',
        'private extension BackupCanonicalEncoderV1',
        'static func canonicalPartsStockJSON(',
        r'''static func canonicalPartsStockJSON(_ value: Any) throws -> CanonicalJSONValueV1''',
        r'''
        if value is NSNull { return .null }
        if let value = value as? [String: Any] {
            return .object(try value.mapValues(canonicalPartsStockJSON))
        }
        if let value = value as? [Any] { return .array(try value.map(canonicalPartsStockJSON)) }
        if let value = value as? String { return .string(value) }
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return .bool(value.boolValue)
            }
            let representation = value.stringValue
            guard !representation.contains("."),
                  !representation.contains("e"),
                  !representation.contains("E"),
                  let integer = Int(representation) else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            return .integer(integer)
        }
        throw BackupCanonicalEncodingErrorV1.invalidRecords''',
        1, False,
    ),
    (
        'FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift',
        'private extension BackupRestoreService',
        'func replacingPartsStockSnapshot(',
        r'''func replacingPartsStockSnapshot(
        in records: V4BackupRecordsV1,
        with snapshot: PartsStockBackupSnapshotV1
    ) throws -> V4BackupRecordsV1''',
        r'''
        try snapshot.validate()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var object = try JSONSerialization.jsonObject(
            with: encoder.encode(records), options: []
        ) as? [String: Any] ?? [:]
        guard !object.isEmpty else { throw attributedRestoreAuthorityFailureV1(line: #line) }
        object["partsStockSnapshot"] = try JSONSerialization.jsonObject(
            with: encoder.encode(snapshot), options: []
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try decoder.decode(V4BackupRecordsV1.self, from: data)''',
        1, False,
    ),
    (
        'FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift',
        'private extension BackupRestoreService',
        'private func readPhotoBindingLeaf(',
        r'''private func readPhotoBindingLeaf(_ requestedName: String, parent: Int32,
        allowLegacy: Bool = false, verify: () throws -> Void) throws -> PhotoBindingLeaf?''',
        r'''
        let name = try resolvedRemovalClaimName(requestedName, parent: parent)
        guard try itemExists(parent: parent, name: name) else { return nil }
        let identity = try itemIdentity(parent: parent, name: name)
        guard identity.type == UInt32(S_IFREG), identity.linkCount == 1 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let fd = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw BackupRestoreServiceError.invalidRestoreAuthority }
        defer { _ = Darwin.close(fd) }
        var before = stat()
        let maximum = FieldDraftLimitsV1.maximumCanonicalBytes * (FieldDraftLimitsV1.maximumStageItems + 4)
        guard Darwin.fstat(fd, &before) == 0, PinnedIdentity(before) == identity,
              before.st_size > 0, before.st_size <= maximum else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let snapshot = photoBindingSnapshot(before)
        let url = applicationSupportURL.appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent(name)
        try verify()
        try ProtectedFilePolicyV1.verify(.stagingFile, at: url)
        try verify()
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                guard data.count <= maximum - count else { throw BackupRestoreServiceError.invalidRestoreAuthority }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 { break }
            else if errno != EINTR { throw BackupRestoreServiceError.invalidRestoreAuthority }
        }
        var after = stat()
        guard Darwin.fstat(fd, &after) == 0, photoBindingSnapshot(after) == snapshot,
              data.count == before.st_size, try itemIdentity(parent: parent, name: name) == identity else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        try verify()
        if allowLegacy, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["schemaVersion"] as? Int == 1 {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            let legacy = try decoder.decode(DraftRestorePublicationBindingV1.self, from: data)
            try legacy.validate()
            return nil
        }
        let value = try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            CheckRunnerPhotoRestorePublicationBindingV2.self, from: data, validate: { try $0.validate() })
        return .init(value: value, data: data, identity: identity)''',
        1, False,
    ),
    (
        'FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift',
        'private extension BackupRestoreService',
        'private func traceRestoreRecordDifferences(',
        r'''private func traceRestoreRecordDifferences(
        actual: V4BackupRecordsV1,
        expected: V4BackupRecordsV1,
        phase: String
    )''',
        r'''
#if DEBUG
        guard let diagnostic = restorePhaseDiagnosticForTesting else { return }
        diagnostic("\(phase).schema.actual.\(actual.recordsSchemaVersion).expected.\(expected.recordsSchemaVersion)")
        if let actualData = try? JSONEncoder().encode(actual),
           let expectedData = try? JSONEncoder().encode(expected),
           let actualObject = (try? JSONSerialization.jsonObject(with: actualData)) as? [String: Any],
           let expectedObject = (try? JSONSerialization.jsonObject(with: expectedData)) as? [String: Any] {
            for key in Set(actualObject.keys).union(expectedObject.keys).sorted() {
                let actualValue = actualObject[key] as? NSObject
                let expectedValue = expectedObject[key] as? NSObject
                let equal = actualValue?.isEqual(expectedValue) ?? (expectedValue == nil)
                if !equal { diagnostic("\(phase).different.\(key)") }
            }
        } else { diagnostic("\(phase).comparison.unavailable") }
        guard let actualHistory = actual.mutationHistory,
              let expectedHistory = expected.mutationHistory else {
            if (actual.mutationHistory == nil) != (expected.mutationHistory == nil) {
                diagnostic("\(phase).history.presence.different")
            }
            return
        }
        if actualHistory.workspaceRevision != expectedHistory.workspaceRevision {
            diagnostic("\(phase).history.workspaceRevision.different")
        }
        if actualHistory.lastLocalSequence != expectedHistory.lastLocalSequence {
            diagnostic("\(phase).history.lastLocalSequence.different")
        }
        if actualHistory.receipts != expectedHistory.receipts {
            diagnostic("\(phase).history.receipts.different")
            // Report only shape and equality results. Receipt identities and
            // canonical bytes remain private even in DEBUG diagnostics.
            func keyedReceipts(
                _ records: [MutationHistoryReceiptRecordV1]
            ) -> (order: [String], byIdentity: [String: MutationHistoryReceiptRecordV1])? {
                var order: [String] = []
                var byIdentity: [String: MutationHistoryReceiptRecordV1] = [:]
                order.reserveCapacity(records.count)
                for record in records {
                    guard let receipt = try? MutationReceiptV1.decodeCanonical(
                        from: record.receiptData
                    ) else { return nil }
                    let key = receipt.identity.stableKey
                    guard byIdentity.updateValue(record, forKey: key) == nil else {
                        return nil
                    }
                    order.append(key)
                }
                return (order, byIdentity)
            }
            diagnostic("\(phase).history.receipts.actualCount.\(actualHistory.receipts.count).expectedCount.\(expectedHistory.receipts.count)")
            if let actual = keyedReceipts(actualHistory.receipts),
               let expected = keyedReceipts(expectedHistory.receipts) {
                diagnostic("\(phase).history.receipts.identitySetEqual.\(Set(actual.order) == Set(expected.order))")
                diagnostic("\(phase).history.receipts.identityKeyedBytesEqual.\(actual.byIdentity == expected.byIdentity)")
                diagnostic("\(phase).history.receipts.orderEqual.\(actual.order == expected.order)")
            } else {
                diagnostic("\(phase).history.receipts.identityKeyingUnavailable")
            }
        }
        if actualHistory.quarantines != expectedHistory.quarantines {
            diagnostic("\(phase).history.quarantines.different")
        }
        let actualRevisions = actualHistory.entityRevisions
        let expectedRevisions = expectedHistory.entityRevisions
        if actualRevisions.count != expectedRevisions.count {
            diagnostic("\(phase).history.entityRevisions.count.different")
        }
        var identityDiffers = false
        var revisionDiffers = false
        var projectionDiffers = false
        var projectionFamilies: Set<String> = []
        diagnostic("\(phase).history.entityRevisions.actualCount.\(actualRevisions.count).expectedCount.\(expectedRevisions.count)")
        for (left, right) in zip(actualRevisions, expectedRevisions) {
            if left.identity != right.identity { identityDiffers = true }
            if left.revision != right.revision { revisionDiffers = true }
            if left.externalProjectionSHA256 != right.externalProjectionSHA256 {
                projectionDiffers = true
                let actualShape: String = left.externalProjectionSHA256 == nil ? "nil" : "set"
                let expectedShape: String = right.externalProjectionSHA256 == nil ? "nil" : "set"
                let identityShape: String = left.identity == right.identity ? "sameIdentity" : "differentIdentity"
                let revisionShape: String = left.revision == right.revision ? "sameRevision" : "differentRevision"
                let family: String = "\(left.identity.kind.rawValue).to.\(right.identity.kind.rawValue)"
                let detail: String = "\(family).\(actualShape).to.\(expectedShape).\(identityShape).\(revisionShape)"
                projectionFamilies.insert(detail)
            }
        }
        if identityDiffers { diagnostic("\(phase).history.entityRevisions.identityOrOrder.different") }
        if revisionDiffers { diagnostic("\(phase).history.entityRevisions.revision.different") }
        for family in projectionFamilies.sorted().prefix(12) {
            diagnostic("\(phase).history.entityRevisions.projectionFamily.\(family)")
        }
        if projectionDiffers { diagnostic("\(phase).history.entityRevisions.projection.different") }
#endif''',
        2, True,
    ),
)


def current_json_function(
    code: str, structural: str, declaration: str, owner: str, header: str, label: str,
) -> tuple[str, int, int]:
    """One real top-level member of the exact current extension and signature."""
    matches = list(re.finditer(re.escape(declaration), structural))
    require(len(matches) == 1, f'{label}: unique typed declaration missing')
    position = matches[0].start()
    ancestors = []
    for index, character in enumerate(structural[:position]):
        if character == '{':
            ancestors.append(index)
        elif character == '}':
            require(bool(ancestors), f'{label}: malformed declaration ownership')
            ancestors.pop()
    require(len(ancestors) == 1, f'{label}: declaration control-flow ownership differs')
    owner_header = structural[:ancestors[0]].rstrip().rsplit('\n', 1)[-1]
    exact_body(owner_header, owner, label + ' owner declaration')
    opening = structural.find('{', matches[0].end())
    require(opening >= 0, f'{label}: declaration body missing')
    exact_body(code[position:opening], header, label + ' typed signature')
    body = delimiter_body(code, structural, opening, '{', '}')
    return body, opening + 1, opening + len(body) + 1


def verify_current_transient_json(source: Mapping[str, str], scan_paths: tuple[str, ...]) -> None:
    """Admit only the five actual typed/canonical/legacy/DEBUG dictionary uses."""
    # Raw sightings retain the old strict refusal of dictionary-looking comments
    # and literals; structural sightings also catch whitespace/comment spelling
    # and an executable cast hidden among otherwise harmless literal decoys.
    dictionary_type = re.compile(
        r'\[\s*(?:Swift\s*\.\s*)?`?String`?\s*:\s*(?:Swift\s*\.\s*)?`?Any`?\s*\??\s*\]'
        r'|\b(?:Swift\s*\.\s*)?Dictionary\s*<\s*(?:Swift\s*\.\s*)?`?String`?\s*,\s*'
        r'(?:Swift\s*\.\s*)?`?Any`?\s*\??\s*>'
    )
    raw_masks = {path: swift_masks(source[path]) for path in scan_paths if 'Any' in source[path]}
    proof_paths = {row[0] for row in TRANSIENT_JSON_PROOFS}
    require(proof_paths <= set(scan_paths), 'current transient JSON proof input omitted')
    production_masks = {path: swift_masks(production(source[path])) for path in proof_paths}
    permitted = {path: [] for path in scan_paths}
    for path, owner, declaration, header, expected_body, count, debug_only in TRANSIENT_JSON_PROOFS:
        label = 'current transient JSON ' + declaration.rstrip('(')
        require(path in raw_masks, label + ': current dictionary proof missing')
        body, begin, end = current_json_function(
            *raw_masks[path], declaration, owner, header, label)
        exact_body(body, expected_body, label + ' complete conversion/comparison proof')
        production_body, _, _ = current_json_function(
            *production_masks[path], declaration, owner, header, label + ' production')
        exact_body(production_body, '' if debug_only else expected_body,
                   label + ' DEBUG-only proof' if debug_only else label + ' production proof')
        permitted[path].append((begin, end, count))
    observed_count = 0
    for path in scan_paths:
        if path not in raw_masks:
            continue
        _, structural = raw_masks[path]
        sightings = sorted({(m.start(), m.end())
                            for view in (source[path], structural)
                            for m in dictionary_type.finditer(view)})
        expected_count = sum(row[2] for row in permitted[path])
        require(len(sightings) == expected_count,
                'current transient JSON use census differs: ' + path)
        for begin, end in sightings:
            require(sum(low <= begin and end <= high for low, high, _ in permitted[path]) == 1,
                    'current transient JSON use outside exact declaration: ' + path)
        for low, high, count in permitted[path]:
            require(sum(low <= begin and end <= high for begin, end in sightings) == count,
                    'current transient JSON declaration cast census differs: ' + path)
        observed_count += len(sightings)
    require(observed_count == 5, 'current transient JSON complete five-use census differs')


def verify_inherited_sources(source: Mapping[str, str], fixture: dict[str, Any]) -> None:
    """Historical Source predicates; six current seams are re-proved below."""
    required = {
        "FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift": ["MutationEnvelopeV1", "canonicalData", "contentDependencyIDs", "reversalPlanDigest", "semanticReversalReplayIdentitySHA256", "SemanticReversalReplayIdentityV1", "semanticReversalExecution", "commandBodySHA256"],
        "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift": ["MutationReceiptIdentityV1", "MutationWorkspaceKeyV1", "MutationQuarantineIdentityDomainV1", 'case mutationEnvelope = "MUTATION_ENVELOPE"', 'case semanticReversalReplayIdentity = "SEMANTIC_REVERSAL_REPLAY_IDENTITY"', "init(from decoder: Decoder) throws", "MutationReceiptV1", "localSequence", "resultingRevision", "postImages", "contentDependencyIDs", "acceptedIdentitySHA256", "conflictingIdentitySHA256"],
        "FieldEvidenceApp/Domain/Mutation/SemanticReversalContractsV1.swift": ["SemanticReversalReplayIdentityV1", "ReversalBasisV1", "SemanticReversalExecutionV1", "SemanticReversalReceiptV1", "decodeCanonical", "reversesMutationID"],
        "FieldEvidenceApp/Domain/Models/MutationPersistenceModelsV1.swift": ["MutationReceiptRow", "MutationQuarantineRow", "workspaceMutationKey", "identityDomain", "acceptedIdentitySHA256", "conflictingIdentitySHA256", "mutableSemanticSHA256", "externalProjectionSHA256"],
        "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift": ["MutationJournalStoreV1", "MutationJournalFaultBoundaryV1", "afterEffectBeforeReceipt", "afterReceiptBeforeSave", "afterSaveBeforeReturn", "resolveReplay", "resolveSemanticReversalReplay", "semanticReversalReplayIdentitySHA256", "workspaceMutationKey", "contentDependencyIDs == envelope.contentDependencyIDs", "maximumPostImageRevisionByEntity", "projectionRevisionByEntity", "currentPostImage", "PersistedTombstoneDigestBasis", "ABSENT_AFTER_MUTATION", "mutableSemanticSHA256", "externalProjectionSHA256", "exportSnapshot", "validateImportedSnapshot", "replaceHistory", "stageMutableSemanticStateAfterAuthorizedExternalMutation", "clearForErase", "quarant"],
        "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift": ["MutationReceiptRecoveryServiceV1", "recover"],
        "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift": ["WorkspaceWriterV1", "executeSemanticReversal", "reversalPlanDigest", "semanticReversalExecution", "targets.allSatisfy"],
        "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift": ["PersistentSchemaV4", "MutationReceiptRow.self", "MutationQuarantineRow.self", "WorkspaceMutationStateRow.self", "EntityMutationRevisionRow.self"],
        "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift": ["case (.v3, .v4)", "makeV4Container", "semanticExportV3", "backfillV4MutationState", "requireV4Marker"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift": ["mutationReceiptRecord", '"receipts"', "validateImportedSnapshot"],
        "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift": ["currentIdentity == incomingIdentity", "max(current.lastLocalSequence, incoming.lastLocalSequence)", "MutationJournalStoreV1.validateImportedSnapshot"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift": ["MutationJournalStoreV1", "exportSnapshot"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift": ["records.mutationHistory", "validateImportedSnapshot"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift": ["recordsSchemaVersion <= 2", "MutationHistorySnapshotV1", "receipts: []", "quarantines: []", "replaceHistory"],
        "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift": ["stageMutableSemanticStateAfterAuthorizedExternalMutation"],
        "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift": [],
    }
    for path, tokens in required.items():
        require(path in source and all(token in source[path] for token in tokens), f"{path}: required C02 source binding missing")
    contracts = source["FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift"]
    command_match = re.search(r"enum\s+WorkspaceCommandKindV1\s*:[^{]+\{(?P<body>.*?)\n\}", contracts, re.DOTALL)
    require(command_match is not None, "Swift command-kind registry missing")
    swift_commands = re.findall(r'^\s*case\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"([^"]+)"\s*$',
                                command_match.group("body"), re.MULTILINE)
    require(tuple(swift_commands) == CURRENT_COMMANDS
            and len(swift_commands) == len(set(swift_commands))
            and set(COMMAND_KINDS).issubset(swift_commands),
            f"Swift closed command-kind set differs: {swift_commands}")
    envelope_source = source["FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift"]
    source_kind_match = re.search(r"enum\s+MutationSourceKindV1\s*:[^{]+\{(?P<body>.*?)\n\}", envelope_source, re.DOTALL)
    require(source_kind_match is not None, "MutationSourceKindV1 registry missing")
    source_kinds = re.findall(r'^\s*case\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"([A-Z_]+)"\s*$',
                              source_kind_match.group("body"), re.MULTILINE)
    require(source_kinds == ["LOCAL_USER", "LOCAL_RECOVERY", "IMPORTED_HISTORY", "SEMANTIC_REVERSAL"],
            f"mutation source-kind registry differs: {source_kinds}")
    receipt_source = source["FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift"]
    require(re.search(r"struct\s+MutationReceiptIdentityV1[\s\S]*?init\(from decoder: Decoder\) throws[\s\S]*?try validate\(\)", receipt_source) is not None,
            "receipt identity decode does not validate workspace/replica/sequence")
    require(r'"\(workspaceID.rawValue.uuidString.lowercased()):\(mutationID.rawValue.uuidString.lowercased())"' in receipt_source,
            "workspace+MutationID composite key encoding drift")
    contracts_source = source["FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift"]
    require(re.search(r"struct\s+MutationIDV1[\s\S]*?init\(from decoder: Decoder\) throws[\s\S]*?try self\.init", contracts_source) is not None,
            "MutationID decode bypasses throwing initializer")
    require(re.search(r"struct\s+WorkspaceEntityIdentityV1[\s\S]*?init\(from decoder: Decoder\) throws[\s\S]*?try self\.init", contracts_source) is not None,
            "entity identity decode bypasses throwing initializer")
    writer_source = source["FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift"]
    require("plan.compensatingCommands.count == 1" in writer_source
            and "compensatingMutationIDs == [request.mutationID]" in writer_source
            and "basis.compensatingCommandKinds == plan.compensatingCommands.map(\\.kind)" in writer_source,
            "single-command reversal fail-closed guard drift")
    require("targets.allSatisfy({ expectedByID[$0] != nil })" in writer_source,
            "strict affected-target revision token guard drift")
    replay_probe = writer_source.find("resolveSemanticReversalReplay")
    target_validation = writer_source.find("plan.mutationID == targetMutationID")
    require(0 <= replay_probe < target_validation,
            "semantic reversal durable replay probe no longer precedes target/plan validation")
    require("semanticReversalReplayIdentitySHA256: replayIdentitySHA256" in writer_source,
            "semantic reversal replay digest is not carried into canonical envelope")
    models_source = source["FieldEvidenceApp/Domain/Models/MutationPersistenceModelsV1.swift"]
    require(models_source.count("@Attribute(.unique) var workspaceMutationKey") == 2,
            "receipt/quarantine composite uniqueness drift")
    journal_source = source["FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift"]
    require("reversal.resultingRevision == reversalMutationReceipt.resultingRevision" in journal_source
            and "reversal.compensatingMutationIDs == [reversalMutationReceipt.mutationID]" in journal_source,
            "semantic reversal receipt execution linkage drift")
    require("acceptedReplayIdentity == replayIdentitySHA256" in journal_source
            and "identityDomain: .semanticReversalReplayIdentity" in journal_source
            and "acceptedIdentitySHA256: acceptedReplayIdentity" in journal_source
            and "conflictingIdentitySHA256: replayIdentitySHA256" in journal_source,
            "durable SemanticReversalReplayIdentity quarantine linkage drift")
    require("identityDomain: .mutationEnvelope" in journal_source
            and "acceptedIdentitySHA256: row.envelopeSHA256" in journal_source
            and "MutationQuarantineIdentityDomainV1(rawValue: quarantine.identityDomain)" in journal_source,
            "closed truthful quarantine hash-domain linkage drift")
    replay_validate = journal_source.find("try validateAll()", journal_source.find("func resolveSemanticReversalReplay"))
    replay_return = journal_source.find("return receipt", journal_source.find("func resolveSemanticReversalReplay"))
    require(0 <= replay_validate < replay_return,
            "accepted semantic replay does not reprove the full bounded journal before return")
    require("projectionRevisionByEntity[entity].map { $0 >= maximumRevision } ?? false" in journal_source,
            "imported projection-to-post-image revision linkage drift")
    replacement_source = source["FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift"]
    require("currentIdentity == incomingIdentity" in replacement_source
            and "max(current.lastLocalSequence, incoming.lastLocalSequence)" in replacement_source
            and ": current.lastLocalSequence" in replacement_source,
            "identity-aware merged local sequence drift")
    restore_source = source["FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift"]
    require("validatedPackage.manifest.source.recordsSchemaVersion <= 2" in restore_source
            and "expectedRecords.mutationHistory == nil" in restore_source
            and "receipts: []" in restore_source and "quarantines: []" in restore_source,
            "legacy schema1/schema2 empty V4 journal bootstrap drift")
    migration_source = source["FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift"]
    require("retry after" in migration_source and "marker.schemaVersion == 4" in migration_source
            and "semanticExportV3(in: context, purpose: purpose)" in migration_source,
            "crash-retry-idempotent V3 to V4 migration proof drift")
    new_sources = "\n".join(source[path] for path in required if path in source)
    for prohibited in PROHIBITED_FIELDS:
        require(re.search(rf"\b{re.escape(prohibited)}\b", new_sources) is None,
                f"prohibited remote/account field present in C02 source: {prohibited}")
    require("JSONPatch" not in new_sources,
            "generic JSON or JSON Patch persistence introduced")
    verify_current_transient_json(source, tuple(required))
    test_path = "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift"
    tests = source[test_path]
    observed = re.findall(r"func (testV10_02[A-Za-z0-9_]+)\s*\(", tests)
    require(tuple(observed) == CURRENT_TESTS,
            f"{test_path}: exact six current evidence tests differ: {observed}")
    require([name for name in observed if name != CURRENT_TESTS[1]] == list(HISTORICAL_TESTS),
            "historical five evidence tests no longer form the unchanged ordered projection")
    fixture_path = "FieldEvidenceAppTests/Fixtures/V21/Mutation/V21P02C02MutationEnvelopeReceiptCorpusV1.json"
    require(isinstance(fixture, dict), "fixture root must be object")
    require(fixture.get("schema") == "V21P02C02MutationEnvelopeReceiptCorpusV1" and fixture.get("schemaVersion") == 1,
            "fixture schema identity drift")
    require(fixture.get("cardID") == CARD, "fixture card identity drift")
    privacy = fixture.get("privacy", {})
    require(privacy.get("containsCustomerData") is False and privacy.get("containsSecrets") is False,
            "fixture privacy declaration weakened")
    require(fixture.get("interruptionBoundaries") == [
        "before_effect_transaction", "after_effect_before_envelope_insert",
        "after_envelope_before_basis_insert", "after_basis_before_receipt_insert",
        "after_receipt_before_transaction_commit", "after_transaction_commit_before_return",
        "after_quarantine_commit_before_return",
    ], "fixture atomic boundary matrix drift")
    require([row.get("mode") for row in fixture.get("restoreMatrix", [])] == ["empty", "replace", "clone", "fork"],
            "fixture restore matrix drift")
    hostile = set(fixture.get("hostileCases", []))
    require({"unknown_schema_version", "unknown_command_kind", "stale_workspace_revision",
             "stale_entity_revision", "foreign_workspace", "source_replica_reuse",
             "tampered_envelope_hash", "tampered_receipt_hash", "sequence_collision",
             "missing_reversal_basis", "tampered_reversal_plan"} == hostile,
            "fixture hostile matrix drift")



def verify_recovery(source: Mapping[str, str]) -> None:
    coordinator = source['FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift']
    writer = block(coordinator, 'private static func constructWriter(')
    ordered(writer, (
        'let journalStore = try MutationJournalStoreV1(',
        'let recovery = MutationReceiptRecoveryServiceV1(store: journalStore)',
        'try recovery.recoverBeforeWriterActivation()',
        'let writer = try WorkspaceWriterV1(',
    ), 'recovery before ordinary writer')
    pins(writer, (
        'modelContext: session.modelContext', 'identity: session.workspaceIdentity',
        'generationID: session.generationID', 'allowStateBootstrap: false',
        'staleWriterFence: staleWriterFence', 'expectedGenerationEpoch: generationEpoch',
        'writerLeaseToken: writerLeaseToken', 'registry: registry',
        '} else { try recovery.recoverBeforeWriterActivation() }',
        'owner.operation.failOriginalEraseWriterRecovery()', 'throw error',
    ), 'current recovery identity/lease/branch')
    ordered(writer, (
        '.recoverBeforeOriginalEraseTargetWriterActivation(',
        'try owner.operation.finishOriginalEraseWriterRecovery(',
        'let writer = try WorkspaceWriterV1(',
    ), 'recovery before original Erase target writer')
    pins(writer, ('activity: owner.activity, operation: owner.operation',
                  'targetAllocation: owner.targetAllocation', 'targetHandle: leaseHandle'),
         'retained original Erase recovery ownership')
    real_writer = production(writer)
    no_return_before(real_writer, 'let writer = try WorkspaceWriterV1(', 'current recovery identity/lease/branch')
    exact_initializer(real_writer, 'let writerLeaseToken', 'leaseHandle.token',
                      'current recovery identity/lease/branch')
    exact_call(real_writer, 'MutationJournalStoreV1', '''
        modelContext: session.modelContext, identity: session.workspaceIdentity,
        generationID: session.generationID, failureInjection: mutationJournalFailureInjection,
        allowStateBootstrap: false, staleWriterFence: staleWriterFence
    ''', 'current recovery identity/lease/branch')
    exact_call(real_writer, 'generationFactory.makeWriterFenceForSchema2ColdCompletedStartup', '''
        expectedGenerationEpoch: generationEpoch, writerLeaseToken: writerLeaseToken,
        registry: registry, owner: owner
    ''', 'current recovery identity/lease/branch')
    exact_call(real_writer, 'generationFactory.makeWriterFence', '''
        expectedGenerationEpoch: generationEpoch, writerLeaseToken: writerLeaseToken, registry: registry
    ''', 'current recovery identity/lease/branch')
    owner_branch, ordinary_branch = branch_pair(real_writer, 'if let owner = originalEraseRecovery')
    exact_body(ordinary_branch, 'try recovery.recoverBeforeWriterActivation()',
               'current recovery identity/lease/branch')
    owner_expected = '''
        try owner.operation.beginOriginalEraseWriterRecovery(
            registry: registry, activity: owner.activity,
            targetAllocation: owner.targetAllocation, targetHandle: leaseHandle)
        do {
            let receipt = try recovery.recoverBeforeOriginalEraseTargetWriterActivation(
                activity: owner.activity, operation: owner.operation,
                targetAllocation: owner.targetAllocation, targetHandle: leaseHandle)
            try owner.operation.finishOriginalEraseWriterRecovery(
                receipt, registry: registry, activity: owner.activity,
                targetAllocation: owner.targetAllocation, targetHandle: leaseHandle)
        } catch {
            owner.operation.failOriginalEraseWriterRecovery()
            throw error
        }
    '''
    exact_body(owner_branch, owner_expected, 'current recovery identity/lease/branch')
    before_revision = token_position(real_writer, 'let revision = try WorkspaceRevisionV1(')
    require(before_revision >= 0 and swift_tokens(real_writer)[:before_revision] == swift_tokens('''
        let writerLeaseToken = leaseHandle.token
        let staleWriterFence: StaleWriterFenceV1
        if let owner = completedSchema2StartupOwner {
            staleWriterFence = try generationFactory.makeWriterFenceForSchema2ColdCompletedStartup(
                expectedGenerationEpoch: generationEpoch, writerLeaseToken: writerLeaseToken,
                registry: registry, owner: owner)
        } else {
            staleWriterFence = try generationFactory.makeWriterFence(
                expectedGenerationEpoch: generationEpoch, writerLeaseToken: writerLeaseToken, registry: registry)
        }
        let journalStore = try MutationJournalStoreV1(
            modelContext: session.modelContext, identity: session.workspaceIdentity,
            generationID: session.generationID, failureInjection: mutationJournalFailureInjection,
            allowStateBootstrap: false, staleWriterFence: staleWriterFence)
        let recovery = MutationReceiptRecoveryServiceV1(store: journalStore)
        if let owner = originalEraseRecovery {
    ''' + owner_expected + '''
        } else { try recovery.recoverBeforeWriterActivation() }
    '''), 'current recovery identity/lease/branch: closed production activation prefix differs')
    recovery = source['FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift']
    ordinary = block(recovery, 'func recoverBeforeWriterActivation()')
    pins(ordinary, ('guard C50IncumbentFileExchangeRecoveryBoundaryV1.validate() else',
                    'try store.withAuthorizedRecovery { try recoverCanonicalJournal() }'),
         'authorized ordinary recovery')
    exact_body(ordinary, '''
        guard C50IncumbentFileExchangeRecoveryBoundaryV1.validate() else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try store.withAuthorizedRecovery { try recoverCanonicalJournal() }
    ''', 'authorized ordinary recovery')
    original = block(recovery, 'func recoverBeforeOriginalEraseTargetWriterActivation(')
    pins(original, ('guard C50IncumbentFileExchangeRecoveryBoundaryV1.validate() else',
                    'return try store.withAuthorizedOriginalEraseWriterRecovery(',
                    'activity: activity, operation: operation',
                    'targetAllocation: targetAllocation, targetHandle: targetHandle',
                    'try recoverCanonicalJournal()'), 'authorized original Erase recovery')
    exact_body(original, '''
        guard C50IncumbentFileExchangeRecoveryBoundaryV1.validate() else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try store.withAuthorizedOriginalEraseWriterRecovery(
            activity: activity, operation: operation,
            targetAllocation: targetAllocation, targetHandle: targetHandle) {
            try recoverCanonicalJournal()
        }
    ''', 'authorized original Erase recovery')
    canonical = block(recovery, 'private func recoverCanonicalJournal()')
    ordered(canonical, ('try store.validateAll()',
                        'try validateLightingNightWorkflowRecoveryParity()',
                        'try store.restageValidatedLegacyCheckpointIfNeeded()'),
            'validated current canonical recovery')
    exact_body(canonical, '''
        try store.validateAll()
        try validateFastSurveyInboxRecoveryParity()
        try validateReinspectionExceptionRecoveryParity()
        try validateEntityIdentityResolutionRecoveryParity()
        try validateWorkspaceExperienceRecoveryParity()
        try validateLightingDayInventoryRecoveryParity()
        try validateLightingNightWorkflowRecoveryParity()
        try validatePartyContactSiteRoleImportRecoveryParity()
        try store.restageValidatedLegacyCheckpointIfNeeded()
    ''', 'validated current canonical recovery')


def verify_current_backup(source: Mapping[str, str]) -> None:
    contracts = source['FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift']
    enrollment = block(contracts, 'enum LightingNightWorkflowBackupEnrollmentV1')
    pins(enrollment, ('static let persistentSchemaVersion = 53',
                      'static let recordsSchemaVersion = 52',
                      'static let durableFamilyCount = 1'), 'current tuple enrollment')
    for declaration, expected in (
        ('static let persistentSchemaVersion', '53'),
        ('static let recordsSchemaVersion', '52'),
        ('static let durableFamilyCount', '1'),
    ):
        exact_initializer(enrollment, declaration, expected, 'current tuple enrollment')
    admission = block(contracts, 'enum BackupSchemaAdmissionV1')
    admission_code, admission_structure = swift_masks(admission)
    pair_match = re.search(r'private static let v4Pairs:[^=]+ = \[(.*?)\n\s*\]', admission_structure, re.S)
    require(pair_match is not None
            and compact(admission_code[pair_match.start(1):pair_match.end(1)]) == CURRENT_V4_PAIR_EXPRESSIONS,
            'closed exact 49 enrolled archive4 pairs differ')
    supports = block(admission, 'static func supports(backup: Int, persistent: Int, records: Int)')
    require(compact(supports) == compact('''
        switch (backup, persistent, records) {
        case (1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 4, 3):
            return true
        default:
            return backup == 4 && v4Pairs.contains {
                $0.persistent == persistent && $0.records == records
            }
        }
    '''), 'historical/current tuple admission must remain exact and fail closed')
    exact_body(block(admission, 'static func matches('), '''
        manifest.source.recordsSchemaVersion == records.recordsSchemaVersion
            && supports(backup: manifest.backupSchemaVersion,
                        persistent: manifest.source.persistentSchemaVersion,
                        records: records.recordsSchemaVersion)
    ''', 'manifest actual record version matching')
    schemas = source['FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift']
    require(compact(block(schemas, 'static var activeRelease: PersistentSchemaReleaseV1')) == '.v53',
            'active current persistent release is not exactly53')
    pins(swift_masks(schemas)[0], ('case .v53:return "LIGHTING_NIGHT_WORKFLOW_V1"',
                                  'static let activeVersionIdentifier=PersistentSchemaV53.versionIdentifier'),
         'current compatibility identity')
    verify_concrete_v53(schemas)
    registry = block(schemas, 'enum PersistentSchemaReleaseRegistryV1')
    for declaration, expected in (
        ('static let v53CompatibilityID', 'PersistentSchemaReleaseV1.v53.compatibilityID'),
        ('static let activeVersionIdentifier', 'PersistentSchemaV53.versionIdentifier'),
        ('static let activeCompatibilityID', 'v53CompatibilityID'),
    ):
        exact_initializer(registry, declaration, expected, 'genuine current registry bindings')
    exporter = source['FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift']
    streaming = block(exporter, 'private func buildStreamingPrepared(')
    ordered(streaming, ('mutationHistory = try MutationJournalStoreV1(',
                        ').exportSnapshot()', 'let records = try makeRecords(',
                        'let source = V4BackupSourceV1(', 'let manifest = V4BackupManifestV1(',
                        'let checkpointBasis = BackupCanonicalCheckpointBasisV1('),
            'genuine archive4 history/export/basis order')
    pins(streaming, (
        'modelContext: modelContext, identity: sourceIdentity, generationID: generationID',
        'deletionLedger: deletionLedger, mutationHistory: mutationHistory',
        'persistentSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion',
        'recordsSchemaVersion: records.recordsSchemaVersion', 'backupSchemaVersion: 4',
        'replicaID: sourceIdentity.replicaID.rawValue',
        'sourceGenerationID: generationID, workspaceID: sourceIdentity.workspaceID.rawValue',
        'persistentSchemaVersion: manifest.source.persistentSchemaVersion',
        'recordsSchemaVersion: manifest.source.recordsSchemaVersion',
        'workspaceRevision: mutationHistory.workspaceRevision',
        'lastLocalSequence: mutationHistory.lastLocalSequence',
        'recordsData: recordsData, semanticRecordsData: semanticRecordsData, memberInventory: entries',
        'recordsData = try BackupCanonicalEncoderV1().encodeRecords(records).data',
        'semanticRecordsData = try BackupCanonicalEncoderV1().encodeSemanticRecords(records).data',
    ), 'actual current export tuple/history/basis')
    records = block(exporter, 'private func makeRecords(')
    pins(records, (
        'guard history.schemaVersion == MutationHistorySnapshotV1.schemaVersion else',
        'return try BackupCanonicalEncoderV1.archiveOrderedMutationHistory(history)',
        'mutationHistory: archiveMutationHistory',
        'recordsSchemaVersion: mutationHistory == nil ? (deletionLedger == nil ? 1 : 2) : LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion',
    ), 'archive history preservation and explicit legacy/current projection')
    basis = block(exporter, 'func canonicalCheckpointBasis()')
    ordered(basis, ('try validateGenerationLease()', 'guard !modelContext.hasChanges else',
                    'let value = try buildStreamingPrepared('), 'current checkpoint basis admission')
    require(compact(basis).count('tryvalidateGenerationLease()') == 2
            and compact(basis).count('guard!modelContext.hasChangeselse') == 2,
            'checkpoint basis must reprove clean context and generation lease after export')
    exact_body(basis, '''
        try validateGenerationLease()
        guard !modelContext.hasChanges else { throw BackupExportServiceError.contextHasChanges }
        let value = try buildStreamingPrepared(
            previewID: Self.checkpointBasisPreviewID, exportedAt: Self.checkpointBasisExportedAt)
        guard !modelContext.hasChanges else { throw BackupExportServiceError.contextHasChanges }
        try validateGenerationLease()
        return value.checkpointBasis
    ''', 'current checkpoint clean context and generation lease')
    validator = source['FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift']
    bounds = block(validator, 'func validateManifestBounds(')
    pins(bounds, (
        'let schemaPairIsValid = BackupSchemaAdmissionV1.supports(',
        'backup: manifest.backupSchemaVersion, persistent: manifest.source.persistentSchemaVersion, records: manifest.source.recordsSchemaVersion',
        'guard sourceIdentityIsValid, sourceGenerationIsValid, schemaPairIsValid,',
    ), 'package current/historical tuple and identity rejection')
    exact_body(bounds, '''
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let sourceIdentityIsValid: Bool
        switch (manifest.backupSchemaVersion, manifest.source.workspaceID, manifest.source.replicaID) {
        case (1, nil, nil): sourceIdentityIsValid = true
        case (2, let workspaceID?, let replicaID?),
             (3, let workspaceID?, let replicaID?),
             (4, let workspaceID?, let replicaID?):
            sourceIdentityIsValid = workspaceID != zero && replicaID != zero && workspaceID != replicaID
        default: sourceIdentityIsValid = false
        }
        let sourceGenerationIsValid: Bool
        if manifest.source.recordsSchemaVersion >= 5 {
            sourceGenerationIsValid = manifest.source.sourceGenerationID.map {
                $0 != zero && $0 != manifest.source.workspaceID && $0 != manifest.source.replicaID
            } ?? false
        } else { sourceGenerationIsValid = manifest.source.sourceGenerationID == nil }
        let schemaPairIsValid = BackupSchemaAdmissionV1.supports(
            backup: manifest.backupSchemaVersion, persistent: manifest.source.persistentSchemaVersion,
            records: manifest.source.recordsSchemaVersion)
        guard sourceIdentityIsValid, sourceGenerationIsValid, schemaPairIsValid,
              manifest.entries.count <= limits.maximumEntryCount, manifest.declaredPayloadByteCount >= 0 else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        var aggregate: Int64 = 0
        var foldedPaths = Set<String>()
        for entry in manifest.entries {
            guard validRelativePath(entry.path), entry.path.utf8.count <= limits.maximumPathUTF8ByteCount,
                  entry.byteCount >= 0, Int64(entry.byteCount) <= limits.maximumUncompressedEntryByteCount,
                  lowercaseHash(entry.sha256), foldedPaths.insert(fold(entry.path)).inserted else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            let (next, overflow) = aggregate.addingReportingOverflow(Int64(entry.byteCount))
            guard !overflow, next <= limits.maximumUncompressedAggregateByteCount else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            aggregate = next
        }
        guard aggregate == Int64(manifest.declaredPayloadByteCount) else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    ''', 'package current/historical tuple and identity rejection')
    pins(swift_masks(validator)[0], ('BackupSchemaAdmissionV1.matches(manifest, records: records)',),
         'package actual record schema matching')


def verify_current_rosters(source: Mapping[str, str]) -> None:
    contracts = block(source['FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift'],
                      'enum WorkspaceCommandKindV1:')
    commands = raw_enum_values(contracts)
    _, command_structure = swift_masks(contracts)
    require(tuple(commands) == CURRENT_COMMANDS and len(commands) == 63
            and len(re.findall(r'^\s*case\b', command_structure, re.M)) == 63
            and len(set(commands)) == 63 and set(COMMAND_KINDS).issubset(commands),
            'closed ordered63 commands must include historical12 exactly')
    tests = swift_masks(source['FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift'])[1]
    names = re.findall(r'func (testV10_02[A-Za-z0-9_]+)\s*\(', tests)
    require(tuple(names) == CURRENT_TESTS and len(names) == 6,
            'six actual current test declarations differ')
    for name in CURRENT_TESTS:
        require(bool(block(tests, 'func ' + name + '(').strip()),
                f'empty current test declaration: {name}')


def verify_checkpoint_history(source: Mapping[str, str]) -> None:
    journal = source[JOURNAL]
    schema = block(journal, 'private static func validateCurrentCheckpointSchema(')
    require(compact(schema) == compact('''
        guard persistent == LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,
              records == LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
              BackupSchemaAdmissionV1.supports(backup: 4, persistent: persistent, records: records) else {
            throw ChangeJournalFailureV1.incompatibleVersion
        }
    '''), 'shared exact53/52 checkpoint admission differs')
    code, journal_structure = swift_masks(journal)
    descriptor = re.search(r'private static let v52BackupRecordFields = \[(.*?)\]\.sorted\(\)', journal_structure, re.S)
    require(descriptor is not None, 'complete current checkpoint descriptor missing')
    fields = re.findall(r'"([A-Za-z][A-Za-z0-9]+)"', code[descriptor.start(1):descriptor.end(1)])
    require(tuple(fields) == CURRENT_RECORD_FIELDS and len(fields) == len(set(fields)) == 77,
            'value independent77 checkpoint record fields differ')
    literal_array(journal, 'private static let v52BackupRecordFields =', CURRENT_RECORD_FIELDS,
                  'value independent77 checkpoint record fields')
    records = block(source['FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift'], 'struct V4BackupRecordsV1:')
    properties = re.findall(r'^    (?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:',
                            swift_masks(records)[1].split('    init(', 1)[0], re.M)
    require(tuple(sorted(properties)) == CURRENT_RECORD_FIELDS
            and len(properties) == len(set(properties)) == 77,
            'actual records52 stored field census differs from checkpoint descriptor')
    fields_for_version = block(journal, 'private static func backupRecordFields(')
    pins(fields_for_version, ('if version == 52 { return v52BackupRecordFields }',
                             'guard (1...15).contains(version) else',
                             'throw ChangeJournalFailureV1.incompatibleVersion'),
         'explicit current descriptor and historical version guard')
    exact_body(fields_for_version, '''
        if version == 52 { return v52BackupRecordFields }
        guard (1...15).contains(version) else { throw ChangeJournalFailureV1.incompatibleVersion }
        if version <= 4 { return v4BackupRecordFields }
        if version == 5 { return v5BackupRecordFields }
        if version == 6 { return v6BackupRecordFields }
        var fields = v7BackupRecordFields
        if version >= 8 { fields.append("partyAccountability") }
        if version >= 9 { fields.append("assetSemantics") }
        if version >= 10 { fields.append("authorityCriterion") }
        if version >= 11 { fields.append("functionalRelationships") }
        if version >= 12 { fields.append("evidenceAssurance") }
        if version >= 13 { fields.append("inspectionReview") }
        if version >= 14 { fields.append("workPackets") }
        if version >= 15 { fields.append("fieldDrafts") }
        return fields.sorted()
    ''', 'explicit current descriptor and historical version guard')
    compatibility = block(journal, 'private func persistentCompatibilityID(')
    cases = re.findall(r'case (\d+): return PersistentSchemaReleaseV1\.v(\d+)\.compatibilityID', compatibility)
    require(cases == [(str(v), str(v)) for v in (*range(1, 17), 53)]
            and 'default: throw ChangeJournalFailureV1.incompatibleVersion' in compatibility,
            'historical/current checkpoint compatibility cases differ')
    exact_body(compatibility, 'switch version {\n' + '\n'.join(
        f'case {version}: return PersistentSchemaReleaseV1.v{version}.compatibilityID'
        for version in (*range(1, 17), 53)
    ) + '\ndefault: throw ChangeJournalFailureV1.incompatibleVersion\n}',
        'historical/current checkpoint compatibility cases')
    installed = block(journal, 'func installImportedCheckpoint(')
    require(installed.count('try Self.validateCurrentCheckpointSchema(') == 2,
            'checkpoint import must reprove incoming and destination current schemas')
    ordered(installed, ('try checkpoint.validate(limits: limits)',
                        'try Self.validateCurrentCheckpointSchema(',
                        'let destination = try backupExport.canonicalCheckpointBasis()',
                        'guard destination.workspaceIdentity == identity,',
                        'state.checkpoints.append(checkpoint)'), 'checkpoint import before state mutation')
    pins(installed, (
        'try Self.validateCurrentCheckpointSchema(persistent: checkpoint.manifest.persistentSchemaVersion, records: checkpoint.manifest.recordSchemaVersion)',
        'try Self.validateCurrentCheckpointSchema(persistent: destination.persistentSchemaVersion, records: destination.recordsSchemaVersion)',
        'export.packageByteCount == Int64(packageData.count)',
        'export.packageSHA256 == Self.rawSHA256(packageData)',
        'guard try WorkspaceMutationCanonicalV1.data(checkpoint) == packageData,',
        'checkpoint.manifest.workspaceID == identity.workspaceID',
        'checkpoint.manifest.sourceReplicaID != identity.replicaID',
        'checkpoint.manifest.checkpointID == export.checkpointID',
        'checkpoint.manifest.manifestSHA256 == export.manifestSHA256',
        'destination.generationID == generationID',
        'destination.workspaceRevision == history.workspaceRevision',
        'destination.lastLocalSequence == history.lastLocalSequence',
        'destination.persistentSchemaVersion == checkpoint.manifest.persistentSchemaVersion',
        'destination.recordsSchemaVersion == checkpoint.manifest.recordSchemaVersion',
        'persistentSchemaSHA256 == checkpoint.manifest.persistentSchemaSHA256',
        'recordSchemaSHA256 == checkpoint.manifest.recordSchemaSHA256',
        'destinationPackages == checkpoint.manifest.packages',
        'destinationFrontier == checkpoint.manifest.frontier',
        'destinationTombstones == checkpoint.tombstoneIdentities',
        'destinationMutationIDs == checkpointMutationIDs',
        'Self.rawSHA256(destination.semanticRecordsData) == checkpoint.manifest.normalizedRecordsSHA256',
        'orderedFields: Self.backupRecordFields(for: destination.recordsSchemaVersion)',
    ), 'checkpoint destination identity/generation/frontier/schema/content guards')
    exact_guard(installed, 'guard export.workspaceID', '''
        export.workspaceID == identity.workspaceID,
        export.packageByteCount == Int64(packageData.count),
        export.packageSHA256 == Self.rawSHA256(packageData)
    ''', 'throw ChangeJournalFailureV1.tamperedBatch', 'checkpoint imported raw binding')
    exact_guard(installed, 'guard try WorkspaceMutationCanonicalV1.data', '''
        try WorkspaceMutationCanonicalV1.data(checkpoint) == packageData,
        checkpoint.manifest.workspaceID == identity.workspaceID,
        checkpoint.manifest.sourceReplicaID != identity.replicaID,
        checkpoint.manifest.checkpointID == export.checkpointID,
        checkpoint.manifest.manifestSHA256 == export.manifestSHA256
    ''', 'throw ChangeJournalFailureV1.tamperedBatch', 'checkpoint imported canonical binding')
    no_return_before(installed, 'guard destination.workspaceIdentity == identity,', 'checkpoint destination integrity')
    exact_guard(installed, 'guard destination.workspaceIdentity', '''
        destination.workspaceIdentity == identity,
        destination.generationID == generationID,
        destination.workspaceRevision == history.workspaceRevision,
        destination.lastLocalSequence == history.lastLocalSequence,
        destination.persistentSchemaVersion == checkpoint.manifest.persistentSchemaVersion,
        destination.recordsSchemaVersion == checkpoint.manifest.recordSchemaVersion,
        persistentSchemaSHA256 == checkpoint.manifest.persistentSchemaSHA256,
        recordSchemaSHA256 == checkpoint.manifest.recordSchemaSHA256,
        destinationPackages == checkpoint.manifest.packages,
        destinationFrontier == checkpoint.manifest.frontier,
        destinationTombstones == checkpoint.tombstoneIdentities,
        destinationMutationIDs == checkpointMutationIDs,
        Self.rawSHA256(destination.semanticRecordsData) == checkpoint.manifest.normalizedRecordsSHA256
    ''', 'throw ChangeJournalFailureV1.incompleteCheckpoint', 'checkpoint destination integrity')
    created = block(journal, 'private func makeCheckpoint(')
    ordered(created, ('guard basis.workspaceIdentity == identity, basis.generationID == generationID else',
                      'try Self.validateCurrentCheckpointSchema(',
                      'guard basis.memberInventory.map(\\.path)',
                      'let manifest = try WorkspaceSnapshotManifestV1('), 'checkpoint creation admission')
    pins(created, (
        'Set(basis.memberInventory.map(\\.path)).count == basis.memberInventory.count',
        'recordsEntry.byteCount == basis.recordsData.count',
        'recordsEntry.sha256 == Self.rawSHA256(basis.recordsData)',
        'basis.workspaceRevision == history.workspaceRevision',
        'basis.lastLocalSequence == history.lastLocalSequence',
        'checkpointLocalSequence(currentFrontier) == basis.lastLocalSequence',
        'Set(supplement.reversalEligibility.map(\\.targetMutationID)) == expectedMutationIDs',
        'expectedContentIDs.isSubset(of: suppliedContentIDs)',
        'entry.path == contentEntry.archiveRelativePath',
        'entry.byteCount == Int(contentEntry.reference.byteLength)',
        'entry.sha256 == contentEntry.reference.digests.digest(for: .sha256)?.hexadecimalValue',
        'orderedFields: Self.backupRecordFields(for: basis.recordsSchemaVersion)',
        'normalizedRecordsSHA256: Self.rawSHA256(basis.semanticRecordsData)',
        'normalizedRecordData: basis.semanticRecordsData',
        'reversalEligibilitySHA256: try Self.sha256(supplement.reversalEligibility)',
    ), 'checkpoint creation raw/schema/frontier/reversal/content guards')
    exact_guard(created, 'guard basis.workspaceIdentity',
                'basis.workspaceIdentity == identity, basis.generationID == generationID',
                'throw ChangeJournalFailureV1.wrongGeneration', 'checkpoint creation identity')
    exact_guard(created, 'guard basis.memberInventory.map', r'''
        basis.memberInventory.map(\.path) == basis.memberInventory.map(\.path).sorted(),
        Set(basis.memberInventory.map(\.path)).count == basis.memberInventory.count,
        let recordsEntry = basis.memberInventory.first(where: { $0.path == "records.json" }),
        recordsEntry.byteCount == basis.recordsData.count,
        recordsEntry.sha256 == Self.rawSHA256(basis.recordsData)
    ''', 'throw ChangeJournalFailureV1.invalidDigest', 'checkpoint creation raw digest')
    exact_guard(created, 'guard basis.workspaceRevision', '''
        basis.workspaceRevision == history.workspaceRevision,
        basis.lastLocalSequence == history.lastLocalSequence,
        checkpointLocalSequence(currentFrontier) == basis.lastLocalSequence
    ''', 'throw ChangeJournalFailureV1.incompleteCheckpoint', 'checkpoint creation frontier')
    exact_guard(created, 'guard Set(supplement.reversalEligibility', r'''
        Set(supplement.reversalEligibility.map(\.targetMutationID)) == expectedMutationIDs
    ''', 'throw ChangeJournalFailureV1.invalidReversal', 'checkpoint creation reversal')
    exact_guard(created, 'guard expectedContentIDs.isSubset', '''
        expectedContentIDs.isSubset(of: suppliedContentIDs),
        supplement.contentEntries.allSatisfy({ contentEntry in
            contentEntry.reference.workspaceID == identity.workspaceID.rawValue.uuidString.lowercased()
                && basis.memberInventory.contains(where: { entry in
                    entry.path == contentEntry.archiveRelativePath
                        && entry.byteCount == Int(contentEntry.reference.byteLength)
                        && entry.sha256 == contentEntry.reference.digests.digest(for: .sha256)?.hexadecimalValue
                })
        })
    ''', 'throw ChangeJournalFailureV1.missingContent', 'checkpoint creation complete content')
    no_return_before(created, 'let manifest = try WorkspaceSnapshotManifestV1(', 'checkpoint creation integrity')
    encoder = source['FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift']
    semantic = block(encoder, 'func encodeSemanticRecords(')
    ordered(semantic, (
        'if records.recordsSchemaVersion == LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion',
        'guard Self.valid(records) else', 'var fields = try Self.recordFields(records)',
        'guard fields.removeValue(forKey: "mutationHistory") != nil else',
        'return try encoded(.object(fields))', 'guard Self.validSemantic(records) else',
    ), 'current semantic records validate full history then exclude value only')
    exact_body(semantic, '''
        if records.recordsSchemaVersion == LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion {
            guard Self.valid(records) else { throw BackupCanonicalEncodingErrorV1.invalidRecords }
            var fields = try Self.recordFields(records)
            guard fields.removeValue(forKey: "mutationHistory") != nil else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            return try encoded(.object(fields))
        }
        guard Self.validSemantic(records) else { throw BackupCanonicalEncodingErrorV1.invalidRecords }
        return try encoded(.object(Self.recordFields(records)))
    ''', 'current semantic history integrity')
    transport = block(encoder, 'private static func recordFields(\n        _ records: V4BackupRecordsV1,')
    pins(transport, ('if let mutationHistory = records.mutationHistory {',
                     'fields["mutationHistory"] = try Self.mutationHistory('),
         'ordinary backup transport retains mutation history')
    exact_body(block(transport, 'if let mutationHistory = records.mutationHistory'), '''
        fields["mutationHistory"] = try Self.mutationHistory(
            mutationHistory, receiptStableKeys: ordinaryValidation?.receiptStableKeys)
    ''', 'ordinary backup transport retains mutation history')
    owned_depth(transport, 'if let mutationHistory = records.mutationHistory',
                'ordinary backup transport retains mutation history')
    legacy = block(encoder, 'func encodeLegacyEmptyServiceRequestRecords(')
    pins(legacy, ('case 48, 49, 50, 51, 52:',
                  'guard records.serviceRequests.isEmpty, records.serviceRequestDispositionEvents.isEmpty, records.serviceRequestWorkLinkEvents.isEmpty else',
                  'let validation = try Self.ordinaryValidationFacts(records)',
                  'guard Self.valid(validation) else',
                  'guard fields.removeValue(forKey: key) == .array([]) else'),
         'retained exact historical empty service-request shape')
    decoder = block(source['FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift'],
                    'func decodeRecordsWithFacts(')
    ordered(decoder, ('try Self.validateLightingDayInventory(value)',
                      'let canonical = try BackupCanonicalEncoderV1().encodeRecords(value).data',
                      'if canonical != data', '.encodeLegacyEmptyServiceRequestRecords(value)',
                      'guard legacy == data else'), 'strict full backup canonical decode history seam')
    real_decoder = production(decoder)
    owned_depth(real_decoder, 'do ', 'strict full backup canonical decode history seam')
    owned_depth(block(real_decoder, 'do '), 'if canonical != data',
                'strict full backup canonical decode history seam')
    no_return_before(real_decoder, 'if canonical != data', 'strict full backup canonical decode history seam')
    exact_body(block(real_decoder, 'if canonical != data'), '''
        let legacy = try BackupCanonicalEncoderV1().encodeLegacyEmptyServiceRequestRecords(value)
        guard legacy == data else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
    ''', 'strict full backup canonical decode history seam')
    exact_body(block(real_decoder, 'catch'), 'throw BackupCanonicalDecodingErrorV1.invalidRecords',
               'strict full backup canonical decode history seam')
    require('BackupCanonicalDecoderV1' not in installed and 'BackupCanonicalDecoderV1' not in created,
            'checkpoint semantic bytes cannot use ordinary backup decoder')
    catalog, catalog_structure = swift_masks(source[CATALOG])
    pins(catalog, ('static let v53PersistentModelNames=["LightingNightWorkflowRowV1"]',
                   '+ v53PersistentModelNames).sorted()',
                   'CurrentSyncClassificationCatalogV1.activePersistentModelNames.count == 168'),
         'current checkpoint persistent model census')
    inventory = re.search(r'static let activePersistentModelNames\s*=\s*\((.*?)\)\.sorted\(\)', catalog_structure, re.S)
    terms = ('persistentModelNames', *(f'v{v}PersistentModelNames' for v in range(6, 54)))
    require(inventory is not None and compact(inventory.group(1)) == '+'.join(terms),
            'current checkpoint exact model inventory composition differs')
    model_names = []
    for term in terms:
        array = delimited(catalog, 'static let ' + term, '[', ']')
        names = re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"', array)
        require(re.sub(r'"[A-Za-z_][A-Za-z0-9_]*"|[,\s]', '', array) == '',
                f'current model inventory is not closed literal names: {term}')
        literal_array(catalog, 'static let ' + term, tuple(names), 'current model literal inventory')
        model_names.extend(names)
    require(len(model_names) == len(set(model_names)) == 168,
            'actual current168 persistent model census differs')


def verify_v3_retry(source: Mapping[str, str]) -> None:
    factory = source['FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift']
    adjacent = block(factory, 'private func performAdjacentCloneMigration(')
    branch = between(adjacent, 'case (.v3, .v4):', 'case (.v4, .v5):')
    ordered(branch, (
        'let container = try makeV4Container(at: modelStoreURL, migrate: true)',
        'guard (try adjacentSemanticDigest(in: context, release: .v3, aggregate: aggregate)) == expectedSemanticDigest else',
        'throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)',
        'try backfillV4MutationState(in: context, migrationID: migrationID)',
        'return (try adjacentSemanticDigest(in: context, release: .v4, aggregate: aggregate))',
    ), 'V3 retry shared source projection before marker mutation')
    exact_body(branch, '''
        return try autoreleasepool { () throws -> String in
            let container = try makeV4Container(at: modelStoreURL, migrate: true)
            let context = container.mainContext
            guard (try adjacentSemanticDigest(in: context, release: .v3, aggregate: aggregate)) == expectedSemanticDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
            try backfillV4MutationState(in: context, migrationID: migrationID)
            let identity = try migrationTransitionIdentity(sourceVersion: 3, aggregate: aggregate)
            if let aggregate {
                let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                guard states.count <= 1,
                      try context.fetch(FetchDescriptor<MutationReceiptRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<MutationQuarantineRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<EntityMutationRevisionRow>()).isEmpty else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                if let state = states.first {
                    guard state.workspaceID == identity.workspaceID.rawValue,
                          state.activeReplicaID == identity.replicaID.rawValue,
                          state.generationID == aggregate.sourceGenerationID,
                          state.workspaceRevision == 0, state.lastLocalSequence == 0,
                          state.mutableSemanticSHA256 == nil else {
                        throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                    }
                } else {
                    context.insert(WorkspaceMutationStateRow(workspaceID: identity.workspaceID.rawValue,
                        generationID: aggregate.sourceGenerationID, activeReplicaID: identity.replicaID.rawValue))
                    try context.save()
                }
            }
            return (try adjacentSemanticDigest(in: context, release: .v4, aggregate: aggregate))
        }
    ''', 'V3 retry complete migration admission')
    projection = block(factory, 'private func semanticProjection(in context: ModelContext,')
    pins(projection, ('if release == .v3 { return try semanticExportV3(in: context, purpose: purpose) }',),
         'current V3 projection helper dispatch')
    exact_body(block(projection, 'if release == .v3 '),
               'return try semanticExportV3(in: context, purpose: purpose)', 'current V3 projection helper dispatch')
    owned_depth(projection, 'if release == .v3 ', 'current V3 projection helper dispatch')
    digest = block(factory, 'private func adjacentSemanticDigest(')
    require(compact(digest) == compact('''
        guard aggregate != nil else {
            return StoreMigrationCanonicalJSONV1.sha256(try semanticProjection(in: context, release: release))
        }
        return try aggregateSemanticDigest(in: context, release: release)
    '''), 'historical nested digest/current aggregate split differs')
    aggregate = block(factory, 'private func aggregateSemanticDigest(')
    pins(aggregate, ('guard release.versionIdentifier.major >= 3 else',
                     'return StoreMigrationCanonicalJSONV1.sha256(try semanticProjection(in: context, release: release))',
                     'return try framedSemanticDigest(in: context, release: release)'),
         'aggregate schema2 framed projection')
    exact_body(aggregate, '''
        guard release.versionIdentifier.major >= 3 else {
            return StoreMigrationCanonicalJSONV1.sha256(try semanticProjection(in: context, release: release))
        }
        return try framedSemanticDigest(in: context, release: release)
    ''', 'aggregate schema2 framed projection')
    backfill = block(factory, 'private func backfillV4MutationState(')
    ordered(backfill, ('if marker.schemaVersion == 4',
                       '_ = try requireV4Marker(in: context, expectedMigrationID: migrationID)',
                       'return', '_ = try requireV3Marker(in: context, expectedMigrationID: migrationID)',
                       'marker.schemaVersion = 4', 'try context.save()'), 'idempotent V4 marker retry')
    exact_body(backfill, '''
        let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
        guard markers.count == 1, let marker = markers.first else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        if marker.schemaVersion == 4 {
            _ = try requireV4Marker(in: context, expectedMigrationID: migrationID)
            return
        }
        _ = try requireV3Marker(in: context, expectedMigrationID: migrationID)
        marker.schemaVersion = 4
        marker.releaseID = PersistentSchemaReleaseRegistryV1.v4CompatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseRegistryV1.v3CompatibilityID
        try context.save()
        _ = try requireV4Marker(in: context, expectedMigrationID: migrationID)
    ''', 'idempotent V4 marker retry')
    marker = block(factory, 'private func requireV4Marker(')
    pins(marker, ('guard markers.count == 1, let marker = markers.first,',
                  'marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID',
                  'marker.schemaVersion == 4',
                  'marker.releaseID == PersistentSchemaReleaseRegistryV1.v4CompatibilityID',
                  'marker.predecessorReleaseID == PersistentSchemaReleaseRegistryV1.v3CompatibilityID',
                  'marker.migrationID != nil',
                  'expectedMigrationID.map({ marker.migrationID == $0 }) ?? true else'),
         'V4 frozen marker and migration identity')
    exact_body(marker, '''
        let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 4,
              marker.releaseID == PersistentSchemaReleaseRegistryV1.v4CompatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseRegistryV1.v3CompatibilityID,
              marker.migrationID != nil,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? true else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    ''', 'V4 frozen marker and migration identity')


def verify_erase(source: Mapping[str, str]) -> None:
    erase = source['FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift']
    published = block(erase, 'internal static func requireEmptyErasePublishedGraph(')
    pins(published, (
        'identity: identity, generationID: generationID, allowStateBootstrap: false).exportSnapshot()',
        'guard history.workspaceRevision == 0, history.lastLocalSequence == 0,',
        'history.receipts.isEmpty, history.quarantines.isEmpty, history.entityRevisions.isEmpty, !context.hasChanges else',
    ), 'published empty current generation history')
    exact_call(published, 'MutationJournalStoreV1', '''
        modelContext: context, identity: identity, generationID: generationID, allowStateBootstrap: false
    ''', 'published empty current generation history')
    no_return_before(published, 'guard history.workspaceRevision', 'published empty current generation history')
    exact_guard(published, 'guard history.workspaceRevision', '''
        history.workspaceRevision == 0, history.lastLocalSequence == 0,
        history.receipts.isEmpty, history.quarantines.isEmpty,
        history.entityRevisions.isEmpty, !context.hasChanges
    ''', 'throw EraseAllServiceError.invalidAuthority', 'published empty current generation history')
    empty = block(erase, 'func validateEmptyGenerationRows(')
    pins(empty, ('if let identity {', 'generationID: id, allowStateBootstrap: allowStateBootstrap',
                 'guard history.workspaceRevision == 0, history.lastLocalSequence == 0,',
                 'history.receipts.isEmpty, history.quarantines.isEmpty, history.entityRevisions.isEmpty else'),
         'all empty generation history dimensions')
    no_return_before(empty, 'if let identity', 'all empty generation history dimensions')
    owned_depth(empty, 'if let identity', 'all empty generation history dimensions')
    exact_body(block(empty, 'if let identity'), r'''
        let history = try MutationJournalStoreV1(
            modelContext: modelContext, identity: identity,
            generationID: id, allowStateBootstrap: allowStateBootstrap).exportSnapshot()
        guard history.workspaceRevision == 0, history.lastLocalSequence == 0,
              history.receipts.isEmpty, history.quarantines.isEmpty, history.entityRevisions.isEmpty else {
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
    ''', 'all empty generation history dimensions')
    cleanup = block(erase, 'func cleanupGenerations(')
    ordered(cleanup, (
        'guard try generationFactory.currentGenerationID(authority: authority) == intent.newGenerationID else',
        'let initialRetired = try authority.retiredGenerationIDs()',
        'for id in intent.generationIDsToDelete',
        'try generationFactory.removeInstalledGeneration(',
        'guard Set(try authority.installedGenerationNames()) == [Self.canonical(intent.newGenerationID)] else',
        'try generationFactory.replaceRetiredGenerationIDs(',
    ), 'whole generation Erase disposal and inventory closure')
    pins(cleanup, ('initialRetired == intent.generationIDsToDelete || initialRetired.isEmpty else',
                   '.isSubset(of: allowedNames)', 'keeping: intent.newGenerationID',
                   'expected: initialRetired, with: [], currentID: intent.newGenerationID, authority: authority'),
         'whole generation Erase current/retired target authority')
    exact_body(cleanup, '''
        guard try generationFactory.currentGenerationID(authority: authority) == intent.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        let initialRetired = try authority.retiredGenerationIDs()
        guard initialRetired == intent.generationIDsToDelete || initialRetired.isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        let allowedNames = Set((intent.generationIDsToDelete + [intent.newGenerationID]).map(Self.canonical))
        guard Set(try authority.installedGenerationNames()).isSubset(of: allowedNames),
              try authority.installedGenerationNames().contains(Self.canonical(intent.newGenerationID)) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for id in intent.generationIDsToDelete {
            let name = Self.canonical(id)
            if try authority.installedGenerationNames().contains(name) {
                try generationFactory.removeInstalledGeneration(id: id, keeping: intent.newGenerationID, authority: authority)
            }
        }
        guard Set(try authority.installedGenerationNames()) == [Self.canonical(intent.newGenerationID)] else {
            throw EraseAllServiceError.invalidAuthority
        }
        if initialRetired == intent.generationIDsToDelete {
            try generationFactory.replaceRetiredGenerationIDs(
                expected: initialRetired, with: [], currentID: intent.newGenerationID, authority: authority)
        } else if !initialRetired.isEmpty { throw EraseAllServiceError.invalidAuthority }
    ''', 'whole generation Erase disposal and inventory closure')
    # This is the single retained retirement owner, not the separate cold
    # preparation advance(operation:) method.
    retirement = block(erase, 'func advance() async throws -> Bool')
    ordered(retirement, (
        'let retired = try factory.retiredGenerationIDsForEraseRetirement(',
        'for id in intent.generationIDsToDelete',
        'try authority.removeInstalledGenerationForEraseRetirement(id: id,',
        'guard Set(try authority.installedGenerationNames()) == [intent.newGenerationID.uuidString.lowercased()] else',
        'try authority.clearRetiredGenerationsForEraseRetirement(',
        'guard try factory.retiredGenerationIDsForEraseRetirement(',
        'phase = .generationsRemoved',
    ), 'retained original Erase installed and retired disposal')
    pins(retirement, ('keeping: intent.newGenerationID, retirement: proof',
                      'expected: intent.generationIDsToDelete, currentID: intent.newGenerationID).isEmpty else'),
         'retained Erase exact frozen old root inventory')
    real_retirement = production(retirement)
    prepared_at = token_position(real_retirement, 'if phase == .prepared')
    require(prepared_at >= 0 and swift_tokens(real_retirement)[:prepared_at] == swift_tokens('''
        guard !running, let retirement else { throw EraseAllServiceError.invalidAuthority }
        guard phase != .closeUncertain else { throw EraseAllServiceError.invalidAuthority }
        if phase == .released { return true }
        running = true
        defer { running = false }
        if proof == nil {
            guard let actual = try await retirement.validateAndAdvance(factory: factory,
                authority: authority, targetReader: targetReader, manifestScope: manifestScope) else { return false }
            proof = actual
        }
        guard let proof, retirement.ownsProof(proof) else { throw EraseAllServiceError.invalidAuthority }
        let completed = intent.advancing(to: .cleanupComplete)
    '''), 'retained original Erase: closed production retirement admission differs')
    exact_body(block(real_retirement, 'if phase == .prepared'), '''
        try inject(.afterSessionRetirementBeforeCleanup)
        guard try factory.currentGenerationIDForEraseRetirement(authority: authority,
            retirement: proof, manifestScope: manifestScope) == intent.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        let retired = try factory.retiredGenerationIDsForEraseRetirement(
            authority: authority, retirement: proof,
            expected: intent.generationIDsToDelete, currentID: intent.newGenerationID)
        guard retired == intent.generationIDsToDelete || retired.isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        let allowed = Set((intent.generationIDsToDelete + [intent.newGenerationID]).map { $0.uuidString.lowercased() })
        let actual = Set(try authority.installedGenerationNames())
        guard actual.isSubset(of: allowed), actual.contains(intent.newGenerationID.uuidString.lowercased()) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if retired.isEmpty {
            guard actual == [intent.newGenerationID.uuidString.lowercased()] else { throw EraseAllServiceError.invalidAuthority }
        }
        for id in intent.generationIDsToDelete {
            if try authority.installedGenerationNames().contains(id.uuidString.lowercased()) {
                try authority.removeInstalledGenerationForEraseRetirement(id: id,
                    keeping: intent.newGenerationID, retirement: proof)
            }
        }
        guard Set(try authority.installedGenerationNames()) == [intent.newGenerationID.uuidString.lowercased()] else {
            throw EraseAllServiceError.invalidAuthority
        }
        try authority.clearRetiredGenerationsForEraseRetirement(
            expected: intent.generationIDsToDelete, currentID: intent.newGenerationID, retirement: proof)
        guard try factory.retiredGenerationIDsForEraseRetirement(
            authority: authority, retirement: proof,
            expected: intent.generationIDsToDelete, currentID: intent.newGenerationID).isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        phase = .generationsRemoved
    ''', 'retained original Erase installed and retired disposal')
    operation = block(erase, 'private func erase(')
    ordered(operation, ('try await operation.removeOriginalC05DrainedRoot(',
                        '.recordingC05RootRemoved()',
                        'try await operation.retireOriginalC05EffectsAfterRootRemoved('),
            'original C05 old root disposed before effect retirement')
    # clearForErase remains the historical journal API. The current service
    # disposes complete old generations rather than calling it on old history.
    journal = source['FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift']
    require('func clearForErase(' in swift_masks(journal)[0], 'historical journal clear API removed')


def verify_inputs(inputs: Mapping[str, str]) -> None:
    require(set(inputs) == set(INPUT_PATHS), 'current reader input closure differs')
    fixture = verify_authorities(inputs)
    source = {path: inputs[path] for path in (*SOURCE_PATHS, *EXTRA_SOURCE_PATHS) if path.endswith('.swift')}
    verify_inherited_sources(source, fixture)
    verify_recovery(source)
    verify_current_backup(source)
    verify_current_rosters(source)
    verify_checkpoint_history(source)
    verify_v3_retry(source)
    verify_erase(source)


def verify_current_sources(root: Path) -> None:
    verify_inputs(load_inputs(root))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    try:
        verify_current_sources(args.root)
    except (ContractError, OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError) as error:
        print(f'{READER_VERSION}: REFUSED: {error}', file=sys.stderr)
        return 1
    print(f'{READER_VERSION}: current Source predicates verified; tuple=4/53/52 commands=63 tests=6 recordFields=77; '
          'Source-only, no card rebind/native/acceptance credit')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
