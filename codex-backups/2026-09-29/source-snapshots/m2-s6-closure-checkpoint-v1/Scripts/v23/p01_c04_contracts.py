#!/usr/bin/env python3
"""Deterministic, source-bound contracts for V23-P01-C04.

Generated artifacts describe the repository's bounded archive surface.  They
are provisional static evidence and deliberately confer no compile,
acceptance, physical-evidence, hosted-dispatch, or release credit.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


CARD = "V23-P01-C04"
BASE_HEAD = "989d73460e4614e3bbea6c1dc20a9da0a1e5f660"
BASE_TREE = "8759c54dec2273b0e22a8caefb06cb0e0141657a"
COORDINATION_HEAD = "c7b9eaa18849af12b21ceddcaa14cd07596edc43"
CONTEXT_DIGEST = "b0a25f7dbfa1d1f6120f3fb7c5531b23189c26754c599cbf7e134d78755dbe29"
FENCE_DIGEST = "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f"
TRANSITION_DIGEST = "0240584c291d45fbd15b750ca9070f02aed10b5f132f8c963498e081f2f3f0fe"
LEDGER_DIGEST = "cf2376b9b9cc71f6fc15cbba80e8063dac9e8b3558ce95fbe074a567e0ffe045"
PREREQUISITE_DIGEST = "96436edd25b1792b918b4869b28e4cd6786dc2d6628285f56efea694e5d7d7b6"
REGISTER_DIGEST = "f7c40a2bf9ea670923489e8f0aec0d1dfae1cf9a9bcad2bf20d2ce4f5bad5556"
DOSSIER_DIGEST = "ec8ddc55bc2aec1cdeb41722004482ca345bd12b009032f3dadf29d297e56c5f"
INHERITED_DIGEST = "3ff603dbc402208da26a1adb455028e82afb69de5e1d05874e6a8a58a8749414"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceAppTests/V9_04StreamingArchiveTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Archives/V21P01C04ArchiveCorpusV1.json",
]
TOOL_PATHS = [
    "Scripts/v23/p01_c04_contracts.py",
    "Scripts/v23/generate_p01_c04_contracts.py",
    "Scripts/v23/verify_p01_c04_contracts.py",
    "Scripts/v23/streaming-archive.schema.json",
    "Scripts/v23/archive-corpus.schema.json",
    "docs/design/v23/tooling/V23P01C04StreamingArchiveContractV1.json",
    "docs/design/v23/tooling/V23P01C04ArchiveCorpusManifestV1.json",
    "docs/design/v23/tooling/V23-P01-C04-tooling-manifest.json",
]
FULL_FENCE = SOURCE_PATHS + TOOL_PATHS

ARCHIVE_SCHEMA = TOOL_PATHS[3]
CORPUS_SCHEMA = TOOL_PATHS[4]
ARCHIVE_ARTIFACT = TOOL_PATHS[5]
CORPUS_ARTIFACT = TOOL_PATHS[6]
MANIFEST = TOOL_PATHS[7]

SOURCE_SPECS = [
    (SOURCE_PATHS[0], ["StreamingArchiveLimitsV1", "static let card17", "StreamingArchiveFormatV1", "StreamingArchiveFailureV1"]),
    (SOURCE_PATHS[1], ["struct StreamingArchiveService", "func write(", "func extract(", "validateWritePlan", "validateIndex"]),
    (SOURCE_PATHS[2], ["BackupExportService", "prepareStreaming", "exportStreaming", "StreamingArchiveWritePlanV1"]),
    (SOURCE_PATHS[3], ["BackupImportService", "stageAndValidate(", "stageAndValidateStreamingArchive", "StreamingArchiveService.hasFormatMagic", "archiveService.extract"]),
    (SOURCE_PATHS[4], ["BackupPackageValidatorV1", "ValidatedV4BackupPackageV1", "ValidatedV4BackupMembersV1", "maximumIndexByteCount", "maximumUncompressedEntryByteCount"]),
    (SOURCE_PATHS[5], ["V9_04StreamingArchiveTests", "test"]),
    (SOURCE_PATHS[6], ['"schemaVersion"', '"authority"', '"limits"', '"cases"']),
]

LIMITS = {
    "maximumIndexByteCount": 4194304,
    "maximumEntryCount": 10000,
    "maximumPathUTF8ByteCount": 512,
    "maximumStoredEntryByteCount": 536870912,
    "maximumUncompressedEntryByteCount": 536870912,
    "maximumStoredAggregateByteCount": 4294967296,
    "maximumUncompressedAggregateByteCount": 4294967296,
    "maximumCompressionRatio": 100,
    "bufferByteCount": 65536,
    "stagingReserveByteCount": 67108864,
}

SOURCE_LIMIT_LITERALS = [
    "maximumIndexByteCount: 4 * 1_048_576",
    "maximumEntryCount: 10_000",
    "maximumPathUTF8ByteCount: 512",
    "maximumStoredEntryByteCount: 512 * 1_048_576",
    "maximumUncompressedEntryByteCount: 512 * 1_048_576",
    "maximumStoredAggregateByteCount: 4 * 1_073_741_824",
    "maximumUncompressedAggregateByteCount: 4 * 1_073_741_824",
    "maximumCompressionRatio: 100",
    "bufferByteCount: 64 * 1_024",
    "stagingReserveByteCount: 64 * 1_048_576",
]

HOSTILE_CASES = [
    ("ABSOLUTE_PATH", "absolute member path", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("TRAVERSAL_PATH", "dot-dot traversal after normalization", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("BACKSLASH_OR_DRIVE_PATH", "Windows separator, drive, or UNC path", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("LINK_OR_REPARSE", "symbolic, hard-link, device, socket, or reparse member", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("DUPLICATE_PATH", "exact duplicate normalized member", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("CASE_COLLISION", "case-folded normalized collision", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("UNICODE_COLLISION", "NFC-normalized member collision", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("ACTIVE_CONTENT", "executable or unsupported active member", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("ENTRY_COUNT_LIMIT", "declared or observed entry count exceeds limit", "REJECT_AND_CLEAN_OWNED_STAGING"),
    ("PATH_BYTE_LIMIT", "normalized UTF-8 path exceeds limit", "REJECT_AND_CLEAN_OWNED_STAGING"),
    ("ENTRY_SIZE_LIMIT", "single entry exceeds uncompressed limit", "REJECT_AND_CLEAN_OWNED_STAGING"),
    ("COMPRESSED_AGGREGATE_LIMIT", "compressed aggregate exceeds limit", "REJECT_AND_CLEAN_OWNED_STAGING"),
    ("UNCOMPRESSED_AGGREGATE_LIMIT", "uncompressed aggregate exceeds limit", "REJECT_AND_CLEAN_OWNED_STAGING"),
    ("COMPRESSION_BOMB", "ratio or expanded-byte bound exceeds limit", "REJECT_DURING_STREAM_AND_CLEAN_OWNED_STAGING"),
    ("TAMPERED_DIGEST", "member or manifest digest mismatch", "REJECT_BEFORE_CANONICAL_MUTATION"),
    ("CHANGING_SOURCE", "source identity, size, or digest changes while exporting", "ABORT_NO_SUCCESS_RECEIPT"),
    ("CANCELLATION", "cancellation before or during streaming", "ABORT_AND_CLEAN_OWNED_STAGING"),
    ("LOW_STORAGE", "reserve cannot be maintained", "FAIL_VISIBLE_AND_CLEAN_OWNED_STAGING"),
    ("PERMISSION_DENIAL", "source or destination access denied", "FAIL_VISIBLE_NO_UNOWNED_CLEANUP"),
    ("UNKNOWN_VERSION", "archive version has no explicit reader", "REJECT_WITHOUT_LEGACY_FALLTHROUGH"),
]


class ContractError(ValueError):
    """Raised when a source-bound contract cannot be reproduced."""


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "physicalEvidenceComplete": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseReady": False,
        "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "phase10PollingDuringParallelExecution": False,
    }


def authority() -> dict[str, Any]:
    return {
        "branch": "phase/v23-expansion",
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationCASSequence": 66,
        "coordinationLedgerSequence": 66,
        "coordinationLedgerDigest": LEDGER_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "registerRowDigest": REGISTER_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "reservationOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "lineage": "REFINED_WITHOUT_LOSS",
        "directPrerequisite": {
            "cardID": "V23-P01-C03",
            "candidateHead": BASE_HEAD,
            "candidateTree": BASE_TREE,
            "toolingManifestDigest": "3b921b3e300623df01d8dce1fbe219570afa6f48d50741834174fca877dda1d9",
            "migrationRecoveryContractDigest": "47b94e525443d748f01daf806dcfb4644533cb37cc98e0ce29f19e322333305e",
            "persistentSchemaReleaseRegistryDigest": "e3223bf2f3b71095386ff5190d95d94aece9ead8ae9655ba8a0d6e843466733c",
            "disposition": "CURRENT_CANDIDATE_COMPATIBLE_PROVISIONAL",
        },
        "authorizedPriorFenceOverlap": {
            "cardID": "V23-P01-C02",
            "path": SOURCE_PATHS[3],
            "pathFenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809",
            "disposition": "DIRECT_INVALIDATION_AND_REPROOF",
        },
        "activeS10OverlapCount": 0,
        "deterministicEvidenceIDs": [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")],
        "invalidationConsumer": "V23-P01-C05",
        "conformanceSubjectSet": "KernelConformanceSubjectSetV1",
        "acceptedS10_6BaselineDigest": None,
    }


def source_bindings(root: Path) -> list[dict[str, Any]]:
    rows = []
    for path, symbols in SOURCE_SPECS:
        item = root / path
        if not item.is_file():
            raise ContractError(f"missing source binding: {path}")
        data = item.read_bytes()
        text = data.decode("utf-8")
        missing = [symbol for symbol in symbols if symbol not in text]
        if missing:
            raise ContractError(f"missing source symbols in {path}: {missing}")
        rows.append({
            "path": path,
            "role": "FENCED_PRODUCT_OR_TEST_SOURCE",
            "status": "BOUND",
            "bytes": len(data),
            "sha256": sha(data),
            "requiredSymbols": symbols,
        })
    return rows


def archive_schema() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "urn:assetrounds:v23:p01:c04:streaming-archive-contract:v1",
        "title": "V23P01C04StreamingArchiveContractV1",
        "type": "object",
        "additionalProperties": False,
        "required": ["schema", "schemaVersion", "cardID", "authority", "limits", "versionDispatch", "pathPolicy", "determinism", "lifecycle", "sourceBindings", "hostileCases", "fullCardFence", *flags().keys(), "artifactDigest"],
        "properties": {
            "schema": {"const": "V23P01C04StreamingArchiveContractV1"},
            "schemaVersion": {"const": 1},
            "cardID": {"const": CARD},
            "authority": {"type": "object"},
            "limits": {"type": "object", "additionalProperties": False, "required": list(LIMITS), "properties": {key: {"type": "integer", "minimum": 1, "const": value} for key, value in LIMITS.items()}},
            "versionDispatch": {"type": "object"},
            "pathPolicy": {"type": "object"},
            "determinism": {"type": "object"},
            "lifecycle": {"type": "object"},
            "sourceBindings": {"type": "array", "minItems": 7, "maxItems": 7, "items": {"type": "object"}},
            "hostileCases": {"type": "array", "minItems": len(HOSTILE_CASES), "uniqueItems": True, "items": {"type": "object", "required": ["id", "condition", "expectedOutcome"]}},
            "fullCardFence": {"type": "array", "minItems": 15, "maxItems": 15, "prefixItems": [{"const": path} for path in FULL_FENCE], "items": False},
            "nativeCompileRan": {"const": False}, "hostedDispatchRan": {"const": False},
            "physicalEvidenceComplete": {"const": False}, "acceptanceEnabled": {"const": False},
            "acceptanceCredit": {"const": False}, "releaseReady": {"const": False},
            "releaseCredit": {"const": False}, "requiresAcceptedS10_6Reconciliation": {"const": True},
            "phase10PollingDuringParallelExecution": {"const": False},
            "artifactDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        },
    }


def corpus_schema() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "urn:assetrounds:v23:p01:c04:archive-corpus-manifest:v1",
        "title": "V23P01C04ArchiveCorpusManifestV1",
        "type": "object",
        "additionalProperties": False,
        "required": ["schema", "schemaVersion", "cardID", "authority", "fixtureBinding", "limits", "cases", "coverage", *flags().keys(), "artifactDigest"],
        "properties": {
            "schema": {"const": "V23P01C04ArchiveCorpusManifestV1"}, "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
            "authority": {"type": "object"}, "fixtureBinding": {"type": "object", "required": ["path", "sha256", "bytes"]},
            "limits": {"const": LIMITS},
            "cases": {
                "type": "array",
                "minItems": len(HOSTILE_CASES) + 4,
                "uniqueItems": True,
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["id", "class", "expectedOutcome", "evidenceID"],
                    "properties": {
                        "id": {"type": "string", "minLength": 1},
                        "class": {"enum": ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"]},
                        "expectedOutcome": {"type": "string", "minLength": 1},
                        "evidenceID": {"pattern": "^V23-P01-C04-[GAHIR]01$"},
                    },
                },
            },
            "coverage": {"type": "object"},
            "nativeCompileRan": {"const": False}, "hostedDispatchRan": {"const": False}, "physicalEvidenceComplete": {"const": False},
            "acceptanceEnabled": {"const": False}, "acceptanceCredit": {"const": False}, "releaseReady": {"const": False}, "releaseCredit": {"const": False},
            "requiresAcceptedS10_6Reconciliation": {"const": True}, "phase10PollingDuringParallelExecution": {"const": False},
            "artifactDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        },
    }


def archive_contract(root: Path) -> dict[str, Any]:
    value: dict[str, Any] = {
        "schema": "V23P01C04StreamingArchiveContractV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "limits": LIMITS,
        "versionDispatch": {"streamingFormat": "ASRBA1", "streamingFormatVersion": 1, "portablePackageVersion": 4, "legacyV4ReaderRetained": True, "unknownVersionDisposition": "FAIL_CLOSED", "wholeArchiveMemoryLoading": False},
        "pathPolicy": {"normalization": "RELATIVE_NFC_FORWARD_SLASH", "caseCollisionKey": "UNICODE_CASE_FOLD_OF_NFC", "ownedStagingRequired": True, "reject": ["ABSOLUTE", "TRAVERSAL", "BACKSLASH", "DRIVE_OR_UNC", "SYMLINK", "HARD_LINK", "REPARSE", "DEVICE", "SOCKET", "DUPLICATE", "CASE_COLLISION", "UNICODE_COLLISION", "ACTIVE_CONTENT"]},
        "determinism": {"entryOrder": "NORMALIZED_UTF8_BYTEWISE_ASCENDING", "metadata": "CANONICAL_FIXED_FIELDS_ONLY", "repeatExportByteIdentical": True, "preReadValidation": ["COUNT", "PATH", "ENTRY", "COMPRESSED_AGGREGATE", "UNCOMPRESSED_AGGREGATE", "STORAGE_RESERVE"], "sourceReproof": ["IDENTITY", "SIZE", "DIGEST"]},
        "lifecycle": {"mode": "CONTENT_ONLY", "schemaDelta": False, "migrationRequired": False, "backupCompatibilityRequired": True, "replaceRestoreRequired": True, "cloneForkRequired": False, "importExportRequired": True, "journalReplay": "OWNED_STAGING_ONLY_NO_CANONICAL_RECEIPT", "searchRebuild": "NOT_APPLICABLE_ARCHIVE_CONTAINER", "deleteErase": "OWNED_STAGING_CLEANUP_ONLY", "retention": "CALLER_OWNED_EXPORTED_FILE", "downgradePolicy": "CONTENT_ROLLBACK_ONLY", "interruption": "CANCEL_AND_CLEAN_OWNED_STAGING", "recovery": "INVALIDATE_STREAMING_WRITER_RETAIN_VERIFIED_V4_READER_EXPORT", "supersession": "APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT"},
        "sourceBindings": source_bindings(root),
        "hostileCases": [{"id": case_id, "condition": condition, "expectedOutcome": outcome} for case_id, condition, outcome in HOSTILE_CASES],
        "fullCardFence": FULL_FENCE,
        **flags(),
    }
    return seal(value)


def corpus_manifest(root: Path) -> dict[str, Any]:
    fixture = root / SOURCE_PATHS[6]
    fixture_data = fixture.read_bytes()
    cases = [
        {"id": "VALID_STREAMING_DETERMINISTIC_REPEAT", "class": "GOLDEN", "expectedOutcome": "BYTE_IDENTICAL_EXPORTS_AND_VALID_IMPORT", "evidenceID": f"{CARD}-G01"},
        {"id": "VALID_V4_LEGACY_DISPATCH", "class": "GOLDEN", "expectedOutcome": "VALIDATED_BY_EXPLICIT_V4_READER", "evidenceID": f"{CARD}-G01"},
        {"id": "BOUNDED_MAXIMUM_FIXTURE", "class": "ALTERNATE", "expectedOutcome": "SUCCEED_WITHIN_ALL_DECLARED_LIMITS", "evidenceID": f"{CARD}-A01"},
        {"id": "WRITER_INVALIDATION_READER_RETENTION", "class": "RECOVERY", "expectedOutcome": "STREAMING_WRITER_DISABLED_V4_READ_EXPORT_RETAINED", "evidenceID": f"{CARD}-R01"},
    ]
    for case_id, _, outcome in HOSTILE_CASES:
        cls = "INTERRUPTION" if case_id in {"CHANGING_SOURCE", "CANCELLATION", "LOW_STORAGE", "PERMISSION_DENIAL"} else "HOSTILE"
        suffix = "I01" if cls == "INTERRUPTION" else "H01"
        cases.append({"id": case_id, "class": cls, "expectedOutcome": outcome, "evidenceID": f"{CARD}-{suffix}"})
    value: dict[str, Any] = {
        "schema": "V23P01C04ArchiveCorpusManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(),
        "fixtureBinding": {"path": SOURCE_PATHS[6], "bytes": len(fixture_data), "sha256": sha(fixture_data)},
        "limits": LIMITS, "cases": cases,
        "coverage": {"caseCount": len(cases), "hostileCaseCount": len(HOSTILE_CASES) - 4, "interruptionCaseCount": 4, "goldenCaseCount": 2, "alternateCaseCount": 1, "recoveryCaseCount": 1, "allLimitDimensionsCovered": True, "allPathClassesCovered": True, "legacyV4Covered": True, "deterministicRepeatCovered": True},
        **flags(),
    }
    return seal(value)


def base_outputs(root: Path) -> dict[str, bytes]:
    return {
        ARCHIVE_SCHEMA: pretty(archive_schema()), CORPUS_SCHEMA: pretty(corpus_schema()),
        ARCHIVE_ARTIFACT: pretty(archive_contract(root)), CORPUS_ARTIFACT: pretty(corpus_manifest(root)),
    }


def tooling_manifest(root: Path, outputs: dict[str, bytes]) -> dict[str, Any]:
    artifact_paths = TOOL_PATHS[:-1]
    rows = []
    for path in artifact_paths:
        data = outputs[path] if path in outputs else (root / path).read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    value: dict[str, Any] = {
        "schema": "V23P01C04ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "pathFence": TOOL_PATHS, "fullCardFence": FULL_FENCE,
        "toolingPathCount": 8, "sourceBindingCount": 7, "sourceBindingComplete": True,
        "artifactCount": len(rows), "artifacts": rows,
        "artifactSetDigest": sha(pretty(rows)),
        **flags(),
    }
    return seal(value)


def all_outputs(root: Path) -> dict[str, bytes]:
    outputs = base_outputs(root)
    outputs[MANIFEST] = pretty(tooling_manifest(root, outputs))
    return outputs
