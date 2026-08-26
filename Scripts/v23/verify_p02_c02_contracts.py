#!/usr/bin/env python3
"""Hostile, schema, source-binding, and closure verifier for V23-P02-C02."""
from __future__ import annotations

import ast
import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

sys.dont_write_bytecode = True

from p02_c02_contracts import (
    CARD, COMMAND_KINDS, CONTRACT_SCRIPT, ENVELOPE_DOC, ENVELOPE_SCHEMA,
    EVIDENCE_IDS, GENERATED_PATHS, GENERATOR_SCRIPT, HASH_FIELDS,
    LIFECYCLE_DOC, LIFECYCLE_SCHEMA, MANIFEST, MANIFEST_INPUT_PATHS,
    OPERATIONAL_COMMAND_KINDS, PATH_FENCE, PREVIEW_ONLY_COMMAND_KINDS,
    PROHIBITED_FIELDS, RECEIPT_DOC, RECEIPT_FIELDS, RECEIPT_SCHEMA,
    RECOVERY_DOC, REVERSAL_SCHEMA, SOURCE_PATHS, TOOL_PATHS, VERIFIER_SCRIPT,
    ContractError, all_outputs, authority, envelope_contract, flags,
    lifecycle_contract, pretty, receipt_contract, recovery_contract, sha,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load(root: Path, path: str) -> dict[str, Any]:
    data = (root / path).read_bytes()
    value = json.loads(data)
    require(isinstance(value, dict), f"{path}: root must be object")
    require(data == pretty(value), f"{path}: JSON is not canonical pretty form")
    return value


def verify_seal(value: dict[str, Any], path: str) -> None:
    payload = dict(value)
    observed = payload.pop("artifactDigest", None)
    require(isinstance(observed, str) and observed == sha(pretty(payload)), f"{path}: artifactDigest mismatch")


def verify_flags(value: dict[str, Any], path: str) -> None:
    for key, expected in flags().items():
        require(value.get(key) is expected, f"{path}: false-credit flag {key} drift")
    require(value.get("provisional") is True, f"{path}: provisional flag missing")


def verify_authority(value: dict[str, Any], path: str) -> None:
    require(value.get("authority") == authority(), f"{path}: authority drift")
    for key, item in value["authority"].items():
        if key.endswith("Digest"):
            require(isinstance(item, str) and re.fullmatch(r"[0-9a-f]{64}", item) is not None,
                    f"{path}: malformed authority digest {key}")


def verify_envelope(value: dict[str, Any]) -> None:
    require(value == envelope_contract(), "envelope registry drift")
    verify_seal(value, ENVELOPE_DOC); verify_flags(value, ENVELOPE_DOC); verify_authority(value, ENVELOPE_DOC)
    require(value["registryClosed"] is True, "command registry opened")
    require(value["commandKinds"] == COMMAND_KINDS, "command registry differs")
    require(value["operationalCommandKinds"] == OPERATIONAL_COMMAND_KINDS, "operational commands differ")
    require(value["previewOnlyCommandKinds"] == PREVIEW_ONLY_COMMAND_KINDS, "preview commands differ")
    require([row["commandKind"] for row in value["payloadRegistry"]] == COMMAND_KINDS,
            "payload registry does not close command registry")
    require(all(row["envelopeSchemaVersion"] == 1 for row in value["payloadRegistry"]), "payload version drift")
    require(value["unknownCommandOrPayloadVersion"] == "FAIL_CLOSED_NO_EFFECT_NO_RECEIPT",
            "unknown command/version became permissive")
    require(value["previewOnlyDisposition"] == "NO_CANONICAL_EFFECT_AND_NO_DURABLE_RECEIPT",
            "preview-only command became durable effect")
    require(value["entityEffects"] == "CANONICAL_POST_IMAGE_OR_TYPED_TOMBSTONE_NEVER_STORAGE_DIFF_OR_JSON_PATCH",
            "storage diff or JSON Patch admitted")
    require(value["bounds"] == {"maximumContentDependencyCount": 256, "maximumContentDependencyIDUTF8Bytes": 512},
            "envelope bounds drift")
    replay = value["reversalReplayIdentity"]
    require(replay["originalPlanBinding"] == "reversalPlanDigest"
            and replay["executionBinding"] == "semanticReversalExecution"
            and replay["durableReplayDigestBinding"] == "semanticReversalReplayIdentitySHA256"
            and replay["mutuallyExclusive"]
            and replay["canonicalEnvelopeHashIncludesBoth"]
            and replay["replayProbeBeforeTargetPlanValidation"],
            "reversal envelope replay identity weakened")
    require(replay["sameMutationIDChangedPlanOrExecution"] == "DURABLE_COMPOSITE_QUARANTINE_NO_EFFECT",
            "changed reversal replay identity no longer quarantines")
    require(value["strictTargetTokens"] == {
        "affectedCommandTargets": "EVERY_TARGET_EXPLICITLY_PRESENT_IN_EXPECTED_ENTITY_REVISIONS",
        "missingTarget": "FAIL_CLOSED_INVALID_COMMAND_NO_EFFECT_NO_RECEIPT",
        "implicitOrUntypedTargetAllowed": False,
    }, "strict command target-token contract drift")
    require(value["identityDecodeHardening"]["mutationID"] == "THROWING_NONZERO_DECODE"
            and value["identityDecodeHardening"]["entityIdentity"] == "THROWING_NONZERO_DECODE"
            and value["identityDecodeHardening"]["receiptIdentity"].startswith("THROWING_POSITIVE_SEQUENCE"),
            "identity decode hardening drift")
    require(value["prohibitedFields"] == PROHIBITED_FIELDS, "prohibited envelope fields drift")


def verify_receipt(value: dict[str, Any]) -> None:
    require(value == receipt_contract(), "receipt contract drift")
    verify_seal(value, RECEIPT_DOC); verify_flags(value, RECEIPT_DOC); verify_authority(value, RECEIPT_DOC)
    require(value["persistentSchema"] == "MUTATION_RECEIPT_V1", "receipt schema identity drift")
    require(value["requiredReceiptFields"] == RECEIPT_FIELDS, "receipt field set drift")
    require(value["hashFields"] == HASH_FIELDS, "hash field set drift")
    require(value["bounds"] == {"maximumPostImageCount": 1024}, "receipt bounds drift")
    atomic = value["atomicity"]
    require(atomic["receiptCardinalityPerAcceptedMutation"] == 1, "receipt cardinality weakened")
    require(not atomic["effectWithoutReceiptAllowed"] and not atomic["receiptWithoutEffectAllowed"],
            "effect/receipt atomicity weakened")
    require(not atomic["failedAttemptReceiptAllowed"], "failed attempt represented as receipt")
    idem = value["durableIdempotency"]
    require(idem["sameIDSameEnvelopeHash"] == "RETURN_BYTE_IDENTICAL_PRIOR_RECEIPT_AFTER_RESTART",
            "restart idempotency weakened")
    require(idem["sameIDDifferentEnvelopeHash"] == "DURABLE_QUARANTINE_NO_EFFECT",
            "changed-hash quarantine weakened")
    require(idem["lookupKey"] == ["workspaceID", "mutationID"]
            and idem["receiptAndQuarantineBothUseCompositeKey"]
            and idem["sameMutationIDDifferentWorkspace"] == "DISTINCT_HISTORY",
            "workspace-scoped receipt/quarantine identity weakened")
    require(value["contentDependencyBinding"] ==
            "RECEIPT_CONTENT_DEPENDENCY_IDS_BYTE_SEMANTICALLY_EQUAL_ENVELOPE",
            "receipt content dependency binding drift")
    quarantine = value["quarantineIdentityContract"]
    require(quarantine["closedDomains"] == ["MUTATION_ENVELOPE", "SEMANTIC_REVERSAL_REPLAY_IDENTITY"]
            and quarantine["fields"] == ["identityDomain", "acceptedIdentitySHA256", "conflictingIdentitySHA256"]
            and quarantine["acceptedAndConflictingMustDiffer"],
            "closed quarantine identity/hash domains drift")
    order = value["ordering"]
    require(order["key"] == ["workspaceID", "replicaID", "localSequence"], "local ordering key drift")
    require(not order["bareSequenceIsGlobalOrder"] and not order["committedAtOrdersReceipts"],
            "false global or wall-clock order introduced")
    require(value["prohibitedFields"] == PROHIBITED_FIELDS, "prohibited receipt fields drift")


def verify_recovery(value: dict[str, Any]) -> None:
    require(value == recovery_contract(), "recovery matrix drift")
    verify_seal(value, RECOVERY_DOC); verify_flags(value, RECOVERY_DOC); verify_authority(value, RECOVERY_DOC)
    boundaries = value["atomicFaultBoundaries"]
    require(len(boundaries) == 7 and len({row["boundary"] for row in boundaries}) == 7,
            "atomic crash boundary matrix incomplete")
    require(all(row["relaunchDisposition"] == "EXACTLY_PRIOR_RECEIPT_OR_NO_EFFECT_NEVER_PARTIAL" for row in boundaries),
            "partial crash result admitted")
    require(value["implementationFaultInjectionPoints"] == ["afterEffectBeforeReceipt", "afterReceiptBeforeSave", "afterSaveBeforeReturn"],
            "implementation fault injection points drift")
    require(value["bounds"] == {"maximumReceiptValidationCount": 100000,
                                "maximumMutableContentValidationCount": 100000,
                                "maximumReversalItemCount": 256},
            "recovery bounds drift")
    persisted = value["persistedStateRecovery"]
    require(persisted["postImageBasis"] == "ACTUAL_PERSISTED_V4_DTO_OR_TYPED_TOMBSTONE"
            and persisted["tombstoneDisposition"] == "ABSENT_AFTER_MUTATION"
            and persisted["mutableSemantic"] == "BOUNDED_CURRENT_CONTENT_PLUS_DELETION_LEDGER"
            and persisted["importedProjectionRevisionLinkage"].startswith("EVERY_MAXIMUM_IMPORTED_POST_IMAGE_REVISION")
            and "EXTERNAL_PROJECTIONS" in persisted["relaunchValidation"],
            "actual persisted-state recovery contract drift")
    replay_reproof = value["acceptedSemanticReplayReproof"]
    require(replay_reproof["beforeReturningPriorReceipt"] == "BOUNDED_FULL_JOURNAL_VALIDATE_ALL"
            and replay_reproof["missingOrTamperedLink"] == "FAIL_CLOSED_AS_CORRUPT_HISTORY"
            and replay_reproof["requiredChain"] == [
                "targetReceipt", "reversalBasis", "basisDigestAndPlan",
                "semanticReversalExecution", "semanticReceiptResultingRevision",
                "singleCompensatingReceipt", "quarantineDomains", "persistedState",
            ], "accepted semantic replay chain reproof drift")
    hostile = value["hostileCases"]
    require(set(hostile) == {"unknownSchemaOrCommand", "staleRevision", "crossWorkspace",
                             "sourceReplicaAsDestination", "tamperedEnvelopeOrReceiptHash",
                             "sequenceCollision", "missingReversalBasis"}, "hostile matrix drift")
    reversal = value["reversalLinkage"]
    require(reversal["forwardHistoryOnly"] and reversal["originalReceiptImmutable"],
            "reversal rewrites history")
    require(not reversal["largeEvidenceBytesDuplicated"], "unbounded evidence copied into reversal basis")
    require(not reversal["mayRecallEraseExternalDeliveryOrFinalizedArtifact"], "irreversible effect recall claimed")
    require(reversal["sameIDChangedTargetPlanOrCommands"] == "DURABLE_QUARANTINE_NO_EFFECT",
            "reversal replay identity weakened")
    require(reversal["singleCommandExecutionRequired"]
            and reversal["compensatingMutationIDsExactlyCurrentMutation"]
            and reversal["basisCommandKindMustEqualExecutedCommandKind"]
            and reversal["semanticReceiptResultingRevisionMustEqualExecutionReceipt"]
            and reversal["durableReplayProbeBeforeTargetValidation"],
            "single-command reversal linkage weakened")


def verify_lifecycle(value: dict[str, Any]) -> None:
    require(value == lifecycle_contract(), "lifecycle contract drift")
    verify_seal(value, LIFECYCLE_DOC); verify_flags(value, LIFECYCLE_DOC); verify_authority(value, LIFECYCLE_DOC)
    activation = value["schemaActivation"]
    require(activation["persistentChangeMode"] == "NEW_SCHEMA_VERSION", "schema activation mode drift")
    require(activation["downgradeDisposition"] == "FORWARD_FIX_ONLY", "downgrade weakened")
    require(not activation["receiptDeletionToHideDefectAllowed"], "receipt deletion admitted")
    migration = value["v3ToV4Migration"]
    require(migration["stage"] == "LIGHTWEIGHT_V3_TO_V4"
            and not migration["historicReceiptsFabricated"]
            and migration["crashRetryIdempotent"]
            and migration["postMigrationRecoveryValidationRequired"],
            "V3 to V4 crash-retry migration contract drift")
    matrix = value["restoreReplicaMatrix"]
    require([row["mode"] for row in matrix] == ["empty", "replace", "clone", "fork"], "restore mode matrix drift")
    require(all(not row["sourceReplicaMayBecomeDestination"] for row in matrix), "source replica reused")
    require(not value["rawRecordUUIDsRemappedForCloneOrFork"], "clone/fork raw UUID remap introduced")
    require(not value["networkOrProviderArtifactsAllowed"], "network/provider artifacts admitted")
    require(value["backup"]["legacySchema1Or2JournalBootstrap"] ==
            "EMPTY_SCHEMA3_MUTATION_HISTORY_BEFORE_V4_MATERIALIZATION",
            "legacy backup journal bootstrap drift")
    require(value["mergedHistorySequence"] == {
        "sameWorkspaceAndReplica": "MAX_CURRENT_AND_INCOMING_LOCAL_SEQUENCE",
        "differentIdentity": "PRESERVE_CURRENT_SEQUENCE_UNTIL_DESTINATION_POLICY_RESETS",
        "newDestinationReplica": "RESET_TO_ZERO",
        "nextWrite": "STRICTLY_GREATER_THAN_RETAINED_LOCAL_SEQUENCE",
    }, "identity-aware merged sequence drift")
    require(value["journalLifecycleAPIs"] == ["exportSnapshot", "validateImportedSnapshot", "replaceHistory",
                                               "stageMutableSemanticStateAfterAuthorizedExternalMutation", "clearForErase"],
            "journal lifecycle API registry drift")
    require(value["verifiedErase"].startswith("REMOVE_WORKSPACE_DATA_ENVELOPES_RECEIPTS"), "Erase receipt lifecycle weakened")


def verify_manifest(value: dict[str, Any], root: Path) -> None:
    verify_seal(value, MANIFEST); verify_flags(value, MANIFEST); verify_authority(value, MANIFEST)
    require(value["pathFence"] == PATH_FENCE and value["pathFenceCount"] == 50, "exact 50-path fence drift")
    require(value["toolingPaths"] == TOOL_PATHS and value["toolingPathCount"] == 12, "tooling fence drift")
    require(value["sourcePaths"] == SOURCE_PATHS and value["sourcePathCount"] == 38, "source fence drift")
    require(value["generatedPaths"] == GENERATED_PATHS, "generated path list drift")
    require(not value["persistentSchemaActivatedByTooling"], "tooling claimed schema activation")
    require(not value["nativeOrHostedEvidenceClaimed"] and not value["acceptanceOrReleaseClaimed"],
            "manifest claimed unavailable evidence")
    rows = value["artifacts"]
    require([row["path"] for row in rows] == MANIFEST_INPUT_PATHS, "manifest input order drift")
    require(value["artifactCount"] == 49 and len(rows) == 49, "manifest closure count drift")
    for row in rows:
        data = (root / row["path"]).read_bytes()
        require(row["bytes"] == len(data) and row["sha256"] == sha(data),
                f"{row['path']}: manifest source/tool binding drift")
    require(value["artifactSetDigest"] == sha(pretty(rows)), "artifact set digest mismatch")


def hostile_checks(function: Callable[[dict[str, Any]], None], value: dict[str, Any], edits: list[Callable[[dict[str, Any]], None]], name: str) -> None:
    for index, edit in enumerate(edits):
        candidate = copy.deepcopy(value); edit(candidate)
        try:
            function(candidate)
        except ContractError:
            continue
        raise ContractError(f"hostile {name} mutation {index} accepted")


def validate_instance(value: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        require(value == schema["const"], f"{path}: const mismatch")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(value, dict), f"{path}: expected object")
        properties = schema.get("properties")
        required = schema.get("required")
        require(isinstance(properties, dict) and isinstance(required, list), f"{path}: malformed object schema")
        require(all(key in value for key in required), f"{path}: required property missing")
        if schema.get("additionalProperties") is False:
            require(set(value) <= set(properties), f"{path}: additional property")
        for key, child in properties.items():
            if key in value:
                require(isinstance(child, dict), f"{path}.{key}: malformed child schema")
                validate_instance(value[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(value, list), f"{path}: expected array")
        require(len(value) >= schema.get("minItems", 0), f"{path}: too few items")
        require(len(value) <= schema.get("maxItems", len(value)), f"{path}: too many items")
        prefix = schema.get("prefixItems", [])
        require(isinstance(prefix, list), f"{path}: malformed prefixItems")
        for index, child in enumerate(prefix):
            require(index < len(value) and isinstance(child, dict), f"{path}[{index}]: prefix item missing")
            validate_instance(value[index], child, f"{path}[{index}]")
        require(schema.get("items") is not False or len(value) == len(prefix), f"{path}: additional array item")
    elif kind == "string":
        require(isinstance(value, str), f"{path}: expected string")
        if "pattern" in schema:
            require(re.fullmatch(schema["pattern"], value) is not None, f"{path}: pattern mismatch")
    elif kind is not None:
        raise ContractError(f"{path}: unsupported emitted schema type {kind}")


def check_emitted_schema(schema: dict[str, Any], path: str = "$") -> None:
    if path == "$":
        require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
                "schema does not declare Draft 2020-12")
        require(isinstance(schema.get("$id"), str) and isinstance(schema.get("title"), str),
                "schema identity metadata missing")
    kind = schema.get("type")
    if kind == "object":
        properties = schema.get("properties")
        required = schema.get("required")
        require(schema.get("additionalProperties") is False, f"{path}: object schema is not strict")
        require(isinstance(properties, dict) and isinstance(required, list), f"{path}: malformed object schema")
        require(len(required) == len(set(required)) and set(required) == set(properties),
                f"{path}: required/property closure differs")
        for key, child in properties.items():
            require(isinstance(child, dict), f"{path}.{key}: child schema malformed")
            check_emitted_schema(child, f"{path}.{key}")
    elif kind == "array":
        prefix = schema.get("prefixItems")
        require(isinstance(prefix, list) and schema.get("items") is False,
                f"{path}: array schema is not exact")
        require(schema.get("minItems") == len(prefix) == schema.get("maxItems"),
                f"{path}: array cardinality is not exact")
        for index, child in enumerate(prefix):
            check_emitted_schema(child, f"{path}[{index}]")
    elif kind == "string":
        require(schema.get("pattern") == "^[0-9a-f]{64}$", f"{path}: unexpected string schema")
    else:
        require("const" in schema, f"{path}: emitted leaf lacks const")


def verify_schemas(root: Path, documents: list[tuple[str, str]]) -> None:
    for document_path, schema_path in documents:
        document = load(root, document_path); schema_value = load(root, schema_path)
        check_emitted_schema(schema_value)
        validate_instance(document, schema_value)
        extra = copy.deepcopy(document); extra["unexpected"] = True
        rejected = False
        try:
            validate_instance(extra, schema_value)
        except ContractError:
            rejected = True
        require(rejected, f"{schema_path}: strict additionalProperties rejection missing")


def verify_scripts(root: Path) -> None:
    for path in (CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT):
        ast.parse((root / path).read_text(encoding="utf-8"), filename=path)
    result = subprocess.run([sys.executable, "-B", str(root / GENERATOR_SCRIPT), "--check", "--root", str(root)],
                            cwd=root, capture_output=True, text=True)
    require(result.returncode == 0, f"generator --check failed: {result.stderr.strip()}")
    require("verified 9 generated artifacts" in result.stdout, "generator check output drift")


def verify_sources(root: Path) -> None:
    source = {path: (root / path).read_text(encoding="utf-8") for path in SOURCE_PATHS if path.endswith(".swift")}
    required = {
        "FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift": ["MutationEnvelopeV1", "canonicalData", "contentDependencyIDs", "reversalPlanDigest", "semanticReversalReplayIdentitySHA256", "SemanticReversalReplayIdentityV1", "semanticReversalExecution", "commandBodySHA256"],
        "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift": ["MutationReceiptIdentityV1", "MutationWorkspaceKeyV1", "MutationQuarantineIdentityDomainV1", 'case mutationEnvelope = "MUTATION_ENVELOPE"', 'case semanticReversalReplayIdentity = "SEMANTIC_REVERSAL_REPLAY_IDENTITY"', "init(from decoder: Decoder) throws", "MutationReceiptV1", "localSequence", "resultingRevision", "postImages", "contentDependencyIDs", "acceptedIdentitySHA256", "conflictingIdentitySHA256"],
        "FieldEvidenceApp/Domain/Mutation/SemanticReversalContractsV1.swift": ["SemanticReversalReplayIdentityV1", "ReversalBasisV1", "SemanticReversalExecutionV1", "SemanticReversalReceiptV1", "decodeCanonical", "reversesMutationID"],
        "FieldEvidenceApp/Domain/Models/MutationPersistenceModelsV1.swift": ["MutationReceiptRow", "MutationQuarantineRow", "workspaceMutationKey", "identityDomain", "acceptedIdentitySHA256", "conflictingIdentitySHA256", "mutableSemanticSHA256", "externalProjectionSHA256"],
        "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift": ["MutationJournalStoreV1", "MutationJournalFaultBoundaryV1", "afterEffectBeforeReceipt", "afterReceiptBeforeSave", "afterSaveBeforeReturn", "resolveReplay", "resolveSemanticReversalReplay", "semanticReversalReplayIdentitySHA256", "workspaceMutationKey", "contentDependencyIDs == envelope.contentDependencyIDs", "maximumPostImageRevisionByEntity", "projectionRevisionByEntity", "currentPostImage", "PersistedTombstoneDigestBasis", "ABSENT_AFTER_MUTATION", "mutableSemanticSHA256", "externalProjectionSHA256", "exportSnapshot", "validateImportedSnapshot", "replaceHistory", "stageMutableSemanticStateAfterAuthorizedExternalMutation", "clearForErase", "quarant"],
        "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift": ["MutationReceiptRecoveryServiceV1", "recover"],
        "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift": ["WorkspaceWriterV1", "executeSemanticReversal", "reversalPlanDigest", "semanticReversalExecution", "targets.allSatisfy"],
        "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift": ["PersistentSchemaV4", "MutationReceiptRow.self", "MutationQuarantineRow.self", "WorkspaceMutationStateRow.self", "EntityMutationRevisionRow.self"],
        "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift": ["case (.v3, .v4)", "makeV4Container", "semanticExportV3", "backfillV4MutationState", "requireV4Marker", "recoverBeforeWriterActivation"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift": ["mutationReceiptRecord", '"receipts"', "validateImportedSnapshot"],
        "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift": ["currentIdentity == incomingIdentity", "max(current.lastLocalSequence, incoming.lastLocalSequence)", "MutationJournalStoreV1.validateImportedSnapshot"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift": ["MutationJournalStoreV1", "exportSnapshot", "recordsSchemaVersion: 3"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift": ["records.mutationHistory", "validateImportedSnapshot"],
        "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift": ["recordsSchemaVersion <= 2", "MutationHistorySnapshotV1", "receipts: []", "quarantines: []", "replaceHistory"],
        "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift": ["stageMutableSemanticStateAfterAuthorizedExternalMutation"],
        "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift": ["clearForErase"],
    }
    for path, tokens in required.items():
        require(path in source and all(token in source[path] for token in tokens), f"{path}: required C02 source binding missing")
    contracts = source["FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift"]
    command_match = re.search(r"enum\s+WorkspaceCommandKindV1\s*:[^{]+\{(?P<body>.*?)\n\}", contracts, re.DOTALL)
    require(command_match is not None, "Swift command-kind registry missing")
    swift_commands = re.findall(r'^\s*case\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"([^"]+)"\s*$',
                                command_match.group("body"), re.MULTILINE)
    require(len(swift_commands) == len(set(swift_commands)) and set(swift_commands) == set(COMMAND_KINDS),
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
            and "semanticExportV3(in: context)" in migration_source,
            "crash-retry-idempotent V3 to V4 migration proof drift")
    new_sources = "\n".join(source[path] for path in required if path in source)
    for prohibited in PROHIBITED_FIELDS:
        require(re.search(rf"\b{re.escape(prohibited)}\b", new_sources) is None,
                f"prohibited remote/account field present in C02 source: {prohibited}")
    require("JSONPatch" not in new_sources and "[String: Any]" not in new_sources,
            "generic JSON or JSON Patch persistence introduced")
    test_path = "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift"
    tests = (root / test_path).read_text(encoding="utf-8")
    expected_tests = [
        "testV10_02G01CanonicalEnvelopeReceiptBytesAndAtomicCommit",
        "testV10_02A01RestartReplayChangedHashQuarantineAndSequence",
        "testV10_02H01StaleForeignUnknownTamperedSequenceAndReversalRejection",
        "testV10_02I01EveryAtomicCrashBoundaryRecoversExactlyOnce",
        "testV10_02R01MigrationLifecycleAndReplicaIdentityMatrix",
    ]
    observed = re.findall(r"func (testV10_02[A-Za-z0-9_]+)\s*\(", tests)
    require(observed == expected_tests, f"{test_path}: exact five evidence tests differ: {observed}")
    fixture_path = "FieldEvidenceAppTests/Fixtures/V21/Mutation/V21P02C02MutationEnvelopeReceiptCorpusV1.json"
    fixture = json.loads((root / fixture_path).read_bytes())
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


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        expected = all_outputs(root)
        for path, data in expected.items():
            require((root / path).is_file() and (root / path).read_bytes() == data, f"stale generated artifact: {path}")
        envelope = load(root, ENVELOPE_DOC); receipt = load(root, RECEIPT_DOC)
        recovery = load(root, RECOVERY_DOC); lifecycle = load(root, LIFECYCLE_DOC)
        manifest = load(root, MANIFEST)
        verify_schemas(root, [(ENVELOPE_DOC, ENVELOPE_SCHEMA), (RECEIPT_DOC, RECEIPT_SCHEMA),
                              (RECOVERY_DOC, REVERSAL_SCHEMA), (LIFECYCLE_DOC, LIFECYCLE_SCHEMA)])
        verify_envelope(envelope); verify_receipt(receipt); verify_recovery(recovery); verify_lifecycle(lifecycle)
        verify_manifest(manifest, root)
        require(envelope["evidenceIDs"] == receipt["evidenceIDs"] == recovery["evidenceIDs"] == lifecycle["evidenceIDs"] == manifest["evidenceIDs"] == EVIDENCE_IDS,
                "evidence ID closure drift")
        hostile_checks(verify_envelope, envelope, [
            lambda x: x.update(registryClosed=False),
            lambda x: x["payloadRegistry"].pop(),
            lambda x: x["prohibitedFields"].remove("serverCursor"),
        ], "envelope")
        hostile_checks(verify_receipt, receipt, [
            lambda x: x["atomicity"].update(effectWithoutReceiptAllowed=True),
            lambda x: x["durableIdempotency"].update(sameIDDifferentEnvelopeHash="RETRY"),
            lambda x: x["ordering"].update(committedAtOrdersReceipts=True),
        ], "receipt")
        hostile_checks(verify_recovery, recovery, [
            lambda x: x["atomicFaultBoundaries"].pop(),
            lambda x: x["reversalLinkage"].update(originalReceiptImmutable=False),
        ], "recovery")
        hostile_checks(verify_lifecycle, lifecycle, [
            lambda x: x["schemaActivation"].update(downgradeDisposition="ROLLBACK"),
            lambda x: x["restoreReplicaMatrix"][0].update(sourceReplicaMayBecomeDestination=True),
            lambda x: x.update(networkOrProviderArtifactsAllowed=True),
        ], "lifecycle")
        verify_scripts(root); verify_sources(root)
    except (ContractError, OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError,
            ValueError, SyntaxError, subprocess.SubprocessError) as error:
        print(f"V23-P02-C02 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P02-C02 strict Draft 2020-12 schemas, hostile contracts, source bindings, and 49-input manifest closure verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
