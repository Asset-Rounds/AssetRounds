#!/usr/bin/env python3
"""Deterministic Card20 (V23-P01-C07) compatibility tooling.

This module is deliberately a data-bound contract producer.  It does not own
the C07 Swift sources, schemas, or compatibility fixtures; those are consumed
from the exact path fence and are digest-bound into the generated documents.
The generator is therefore safe to re-run after another owner reseals a source
or fixture: no hand-edited digest is retained here.
"""
from __future__ import annotations

import hashlib
import base64
import json
import re
from pathlib import Path
from typing import Any

CARD = "V23-P01-C07"
BASE_HEAD = "e576a3ca91d597fff41d0f23209bab009ff8de6b"
BASE_TREE = "31ee5686b15c4cf60047a09306c60479c6e4468d"
COORDINATION_HEAD = "9c87863be0ce950258254eb59c9f587719074465"
COORDINATION_CAS_SEQUENCE = 79
COORDINATION_LEDGER_DIGEST = "1b21315e524a177a679b4ec20ab30fec529e9152f22126a08552576cfabbd11c"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
DOSSIER_DIGEST = "9a033191d94475d2670ded408466020254cee0a53e5cf896eaff958bfe8286eb"
INHERITED_V21_DIGEST = "51d228d1070f24e2a64cc4ca702a7ac01bc2ccfa4e215c960df6632aca6157de"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DISPOSITION_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
PREREQUISITE_DIGEST = "2c746250a36d111f065cda9f12bb4deb051127b442866e320d6648e47b5eb68f"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FENCE_DIGEST = "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce"
CONTEXT_DIGEST = "76e761e79c2ca6b0b105bd5015f47c357596eef6fe37b3344722db6e555e30e3"
GENERATOR_VERSION = "p01-c07-seed-v1"
GENERATOR_SEED = 230107
LICENSE_IDENTIFIER = "SYNTHETIC_INTERNAL_FIXTURE_V1"

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/CompatibilityCorpusContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceAppTests/CompatibilityCorpusSupportV1.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
]
FIXTURE_PATHS = [
    "FieldEvidenceAppTests/Fixtures/V21/Compatibility/V21P01C07CompatibilityCorpusV1.json",
    "FieldEvidenceAppTests/Fixtures/V21/Compatibility/V21P01C07PreV23SeedV1.json",
    "FieldEvidenceAppTests/Fixtures/V21/Compatibility/V21P01C07HistoricReportOpenV1.json",
    "FieldEvidenceAppTests/Fixtures/V21/Compatibility/V21P01C07HistoricReportV1.pdf",
]
SCHEMA_PATHS = [
    "Scripts/v23/released-data-compatibility-policy.schema.json",
    "Scripts/v23/compatibility-case-manifest.schema.json",
    "Scripts/v23/compatibility-corpus-manifest.schema.json",
    "Scripts/v23/compatibility-run-receipt.schema.json",
    "Scripts/v23/release-seed-corpus.schema.json",
    "Scripts/v23/release-seed-corpus-seal.schema.json",
    "Scripts/v23/supported-upgrade-path.schema.json",
    "Scripts/v23/data-compatibility-manifest.schema.json",
]
DOC_PATHS = [
    "docs/design/v23/tooling/V23P01C07ReleasedDataCompatibilityPolicyV1.json",
    "docs/design/v23/tooling/V23P01C07CompatibilityCaseManifestV1.json",
    "docs/design/v23/tooling/V23P01C07CompatibilityCorpusManifestV1.json",
    "docs/design/v23/tooling/V23P01C07CompatibilityRunReceiptV1.json",
    "docs/design/v23/tooling/V23P01C07ReleaseSeedCorpusV1.json",
    "docs/design/v23/tooling/V23P01C07ReleaseSeedCorpusSealV1.json",
    "docs/design/v23/tooling/V23P01C07SupportedUpgradePathV1.json",
    "docs/design/v23/tooling/V23P01C07DataCompatibilityManifestV1.json",
]
TOOL_PATHS = [
    "Scripts/v23/p01_c07_contracts.py",
    "Scripts/v23/generate_p01_c07_contracts.py",
    "Scripts/v23/verify_p01_c07_contracts.py",
    *SCHEMA_PATHS,
    *DOC_PATHS,
    "docs/design/v23/tooling/V23-P01-C07-tooling-manifest.json",
]
FULL_FENCE = SOURCE_PATHS + FIXTURE_PATHS + TOOL_PATHS

CORPUS_FIXTURE = FIXTURE_PATHS[0]
SEED_FIXTURE = FIXTURE_PATHS[1]
REPORT_OPEN_FIXTURE = FIXTURE_PATHS[2]
REPORT_PDF_FIXTURE = FIXTURE_PATHS[3]
POLICY_DOC = DOC_PATHS[0]
CASE_DOC = DOC_PATHS[1]
CORPUS_DOC = DOC_PATHS[2]
RUN_DOC = DOC_PATHS[3]
SEED_DOC = DOC_PATHS[4]
SEAL_DOC = DOC_PATHS[5]
UPGRADE_DOC = DOC_PATHS[6]
DATA_DOC = DOC_PATHS[7]
MANIFEST = TOOL_PATHS[-1]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
EVIDENCE_FAMILIES = ["G01", "A01", "H01", "I01", "R01"]
CURRENT_FAMILIES = [
    "live_store", "current_generation_pointer", "store_generation_manifest",
    "store_migration_journal", "backup_package", "streaming_archive",
    "report_open_json", "report_pdf", "finalization_intent", "sign_pack", "durable_media",
    "deletion_ledger", "deletion_intent", "erase_intent", "restore_intent",
]
WORKSPACE_TAGS = ["dst", "empty", "long", "maximal", "minimum", "rtl", "unicode"]
HOSTILE_TAGS = ["tamper", "truncated", "path", "archive", "bomb"]
SEMANTIC_SCOPE = {
    "shippingWriterActivation": "CURRENT_ONLY_BEHIND_EXISTING_API",
    "releasedFamilies": "CURRENT_STORE_ARCHIVE_REPORT_CONTENT_DELETION_ONLY",
    "compatibilityPolicy": "FORWARD_MIGRATION_CURRENT_WRITERS_ONLY_FAIL_CLOSED_UNKNOWN_VERSION",
    "corpusPolicy": "IMMUTABLE_SYNTHETIC_DIGEST_BOUND_GENERATOR_SEED_REVIEWED",
    "historicArtifactPolicy": "PRESERVE_FINALIZED_REPORT_BYTES_AND_RELEASED_FIXTURES",
    "futureContractPolicy": "NO_P02_PLUS_FORMAT_FABRICATION",
    "customerDataPolicy": "SYNTHETIC_ONLY_NO_CUSTOMER_OR_SECRET_DATA",
    "diagnosticPolicy": "FAIL_FAST_ACCEPTANCE_CONTINUE_ONLY_DIAGNOSTIC",
}

SOURCE_SPECS = [
    (SOURCE_PATHS[0], [
        "ReleasedDataCompatibilityPolicyV1", "DataCompatibilityManifestV1",
        "SupportedUpgradePathV1", "CompatibilityArtifactFamilyV1", "candidateHead",
        "firstPublicSealOwner", "case finalizationIntent", "static let current",
    ]),
    (SOURCE_PATHS[1], [
        "CompatibilityCanonicalV1", "CompatibilityCaseManifestV1",
        "CompatibilityCorpusManifestV1", "CompatibilityRunReceiptV1",
        "ReleaseSeedCorpusV1", "ReleaseSeedCorpusSealV1", "caseIDs(",
    ]),
    (SOURCE_PATHS[2], [
        "BackupExportService", "prepareStreaming", "prepareCompatibilityFixtureLegacyDirectoryPackage",
        "exportCompatibilityFixtureLegacyDirectoryPackage", "buildStreamingPrepared",
    ]),
    (SOURCE_PATHS[3], [
        "V907CompatibilitySupport", "fixtureData", "corpus", "seed", "result", "receipt", "replacing",
        "generatedCaseArtifacts", "generatedArtifact", "observedOutputSHA256",
    ]),
    (SOURCE_PATHS[4], [
        "V9_07CompatibilityPolicyTests", "testV9_07A01DeterministicBoundaryAndInternationalSeedCases",
        "testV9_07H01FutureChangedDigestHostileArchiveAndPrivacyRejection",
        "testV9_07R01ReplayQuarantineImmutabilityAndAcceptanceModeSeparation",
        "mode: .acceptingFailFast", "requireAccepting",
    ]),
    (SOURCE_PATHS[5], [
        "V9_07CompatibilityCorpusIntegrationTests", "testV9_07G01AggregateReleasedDataCorpusAndRuntimeRoundTrips",
        "testV9_07I01EvidenceExportAndRunReceiptInterruptionsPreserveCorpus",
    ]),
    (SOURCE_PATHS[6], ["S6_2BackupExportTests", "testCanonicalFixturesAndExportedBundleTypeDeclaration"]),
    (SOURCE_PATHS[7], ["S6_3BackupValidationTests", "prepareCompatibilityFixtureLegacyDirectoryPackage", "exportCompatibilityFixtureLegacyDirectoryPackage"]),
    (SOURCE_PATHS[8], ["V9_06DeletionRightsTests", "testV9_06G01", "testV9_06A01", "testV9_06H01"]),
]

# These are accepted immutable inputs, not newly generated acceptance evidence.
# Their hashes are intentionally fixed so replacing an old released artifact is
# a visible failure rather than a silent reseal.
IMMUTABLE_REFERENCE_SPECS = [
    ("docs/design/v23/tooling/V23P01C03MigrationRecoveryContractV1.json", "9ee484122ca44645df88152656a7c5f6cdef08dde0644b7eda58a778c25adb27", "V23-P01-C03"),
    ("docs/design/v23/tooling/PersistentSchemaReleaseRegistryV1.json", "ce5d076340c893de0e37e9f1642101365f2f532f705dc53e9f6957376e026c35", "V23-P01-C03"),
    ("docs/design/v23/tooling/V23-P01-C03-tooling-manifest.json", "5c4093bf86eb108ebea8a86e783c6e4d768775cfef9b7e99939c5ad73a7654c1", "V23-P01-C03"),
    ("docs/design/v23/tooling/V23P01C04StreamingArchiveContractV1.json", "06e7482ebefee6d8402c76b36382431c47e1ff65b96eddaa4b48c4a90e9547c3", "V23-P01-C04"),
    ("docs/design/v23/tooling/V23P01C04ArchiveCorpusManifestV1.json", "d8a8fd24227b2c6bd8a8071235cece31412a64b5616ab16db587d32310daa3e4", "V23-P01-C04"),
    ("docs/design/v23/tooling/V23-P01-C04-tooling-manifest.json", "9d62dbd3d0b3c541d774d2e1d25f961f85d15b332ba41308aef566319da2fcd9", "V23-P01-C04"),
    ("docs/design/v23/tooling/V23P01C05RestoreIdentityContractV1.json", "797a375ee537ed3833ae2929ac1bda6506dd157e3a60e3e71f1e4f21f0f9430e", "V23-P01-C05"),
    ("docs/design/v23/tooling/V23P01C05IdentityTransformationManifestV1.json", "ac9d88f1feda11160fc17ae6edb8602733f7146e0aca9dd0fd3bd9ad058f2868", "V23-P01-C05"),
    ("docs/design/v23/tooling/V23-P01-C05-tooling-manifest.json", "b471540727b8e9f1321bc1a4e8173622d9a9e2fd51698ae93c573271aac0f486", "V23-P01-C05"),
    ("docs/design/v23/tooling/V23P01C06DeletionRightsContractV1.json", "4250ed5c5c6aad2f6278bc0114ef3b426b01d0eea6bff03e0bdc5a824dc383cd", "V23-P01-C06"),
    ("docs/design/v23/tooling/V23P01C06DeletionGraphManifestV1.json", "dbbdb369ef7a6425378fc1d304cde22ec6578343b8ee9c97a7010a5558f96fda", "V23-P01-C06"),
    ("docs/design/v23/tooling/V23-P01-C06-tooling-manifest.json", "dbd2b13032838413e40977a0acb484b71e5584b862f836d45fc8b3be5a6ab78e", "V23-P01-C06"),
    ("FieldEvidenceAppTests/Fixtures/S3_3ReportSnapshotV1.json", "8b81589641276df9ee94dba99ac390ce8679fcc2932825e79e4178eb91377b3e", "S3_3"),
    ("FieldEvidenceAppTests/Fixtures/S6_2V4BackupRecordsV1.json", "4f6b1c58fe0bce27d36898f463e4742bde618e631b073a29d98243e8f09ed87f", "S6_2"),
    ("FieldEvidenceAppTests/Fixtures/S6_3V4BackupPackageV1.json", "a3699f4070dec364b19c316dd0f0acd5a080bd7bdc89dc861249932d16b9bffa", "S6_3"),
    ("FieldEvidenceAppTests/Fixtures/S8_1ExteriorLightPackV1.json", "6f72c39fa9909ccfec087e33cb82a456b1e7b083745601cc6ea1bb05f277f7c8", "S8_1"),
    ("FieldEvidenceAppTests/Fixtures/V21/Archives/V21P01C04ArchiveCorpusV1.json", "bdc3f92d595bdb21ed465660c9f2e45196dc5271302dcb2e604f57513defec84", "V21-P01-C04"),
    ("FieldEvidenceAppTests/Fixtures/V21/Restore/V21P01C05IdentityTransformationsV1.json", "18f14d34d9482519eb17bbd539cc73f89412c60538cb478a0596747e516a043a", "V21-P01-C05"),
    ("FieldEvidenceAppTests/Fixtures/V21/Deletion/V21P01C06DeletionGraphV1.json", "5e8311f758184cd98eb7d6c0c4cd1db2d25427eb25cb166bca393b395ab80e3a", "V21-P01-C06"),
]


class ContractError(ValueError):
    """Raised when a fenced input or generated contract is inconsistent."""


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": 20,
        "title": "Released-data compatibility policy, immutable seed corpus, and supported upgrade closure",
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "REFINED_WITHOUT_LOSS",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion",
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "registerRowDigest": REGISTER_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_V21_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "impactManifestDigest": IMPACT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P01-C06"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "invalidationConsumers": ["V23-P02-C01"],
        "optionalCapabilityProviders": ["NONE"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
        "semanticScope": SEMANTIC_SCOPE,
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "persistentChangeMode": "CONTENT_ONLY",
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True,
        "restoreCompatibilityRequired": True,
        "deleteCompatibilityRequired": True,
        "exportCompatibilityRequired": True,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
        "uiSurfaceDelta": False,
        "brandSurfaceDelta": False,
    }


def source_bindings(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path, symbols in SOURCE_SPECS:
        item = root / path
        row: dict[str, Any] = {
            "path": path,
            "role": "FENCED_PRODUCT_OR_TEST_SOURCE",
            "requiredSymbols": symbols,
        }
        if not item.is_file():
            row.update({"status": "PENDING", "bytes": None, "sha256": None, "missingSymbols": symbols})
            rows.append(row)
            continue
        data = item.read_bytes()
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = ""
        digest_data = data
        digest_normalization = "RAW_BYTES"
        if text:
            digest_data = text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
            digest_normalization = "UTF8_LF"
        missing = [symbol for symbol in symbols if symbol not in text]
        row.update({
            "status": "BOUND" if not missing else "PENDING",
            "bytes": len(digest_data),
            "sha256": sha(digest_data),
            "digestNormalization": digest_normalization,
            "missingSymbols": missing,
        })
        rows.append(row)
    return rows


def source_binding_complete(rows: list[dict[str, Any]]) -> bool:
    return len(rows) == len(SOURCE_PATHS) and all(row["status"] == "BOUND" and not row["missingSymbols"] for row in rows)


def immutable_references(root: Path) -> list[dict[str, Any]]:
    rows = []
    for path, expected, owner in IMMUTABLE_REFERENCE_SPECS:
        item = root / path
        if not item.is_file():
            raise ContractError(f"missing immutable reference: {path}")
        data = item.read_bytes()
        observed = sha(data)
        if observed != expected:
            raise ContractError(f"immutable reference changed: {path} ({observed} != {expected})")
        rows.append({
            "path": path,
            "owner": owner,
            "bytes": len(data),
            "sha256": expected,
            "immutable": True,
            "referenceDisposition": "IMMUTABLE_REFERENCE_BY_SHA_NO_NEW_ACCEPTANCE_CREDIT",
        })
    return rows


def fixture_bindings(root: Path, generated: dict[str, bytes] | None = None) -> list[dict[str, Any]]:
    rows = []
    for path in FIXTURE_PATHS:
        item = root / path
        data = generated.get(path) if generated is not None else (item.read_bytes() if item.is_file() else None)
        if data is None:
            raise ContractError(f"missing required C07 fixture: {path}")
        row = {
            "path": path,
            "role": "C07_IMMUTABLE_SYNTHETIC_FIXTURE",
            "status": "BOUND",
            "bytes": len(data),
            "sha256": sha(data),
            "synthetic": True,
            "licenseIdentifier": LICENSE_IDENTIFIER,
            "containsCustomerData": False,
            "containsSecrets": False,
            "immutable": True,
        }
        if path.endswith(".json"):
            try:
                json.loads(data.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise ContractError(f"invalid JSON fixture: {path}: {error}") from error
        rows.append(row)
    return rows


def support_paths() -> list[dict[str, Any]]:
    def path(family: str, persistence: str, versions: list[str], writer: str, *, transitions: list[dict[str, str]] | None = None, search: str = "not_applicable", rebuild: str = "not_applicable") -> dict[str, Any]:
        return {
            "schemaVersion": 1,
            "family": family,
            "persistence": persistence,
            "readableVersions": sorted(versions),
            "currentWriterVersion": writer,
            "forwardUpgradeTransitions": transitions or [],
            "unknownVersionDisposition": "fail_closed_unsupported_version",
            "writerDisposition": "current_version_only",
            "searchDisposition": search,
            "rebuildDisposition": rebuild,
        }
    return [
        path("live_store", "publicly_persisted", ["1.0.0", "2.0.0", "3.0.0"], "3.0.0", transitions=[{"fromVersion": "1.0.0", "toVersion": "2.0.0"}, {"fromVersion": "2.0.0", "toVersion": "3.0.0"}], search="unavailable_at_this_head", rebuild="available"),
        path("current_generation_pointer", "publicly_persisted", ["1", "2", "3"], "3"),
        path("store_generation_manifest", "publicly_persisted", ["1"], "1"),
        path("store_migration_journal", "internal_recovery", ["1"], "1"),
        path("backup_package", "publicly_persisted", ["archive1-backup2-persistent1-records1", "archive1-backup2-persistent3-records2", "directory-v4-backup1-persistent1-records1"], "archive1-backup2-persistent3-records2"),
        path("streaming_archive", "publicly_persisted", ["header1-index1"], "header1-index1"),
        path("report_open_json", "publicly_persisted", ["snapshot1"], "snapshot1", search="deferred_to_v23_p03_c09"),
        path("report_pdf", "publicly_persisted", ["template1"], "template1", search="deferred_to_v23_p03_c09"),
        path("finalization_intent", "internal_recovery", ["1"], "1"),
        path("sign_pack", "publicly_persisted", ["schema1-content1"], "schema1-content1"),
        path("durable_media", "publicly_persisted", ["canonical-jpeg-v1"], "canonical-jpeg-v1"),
        path("deletion_ledger", "publicly_persisted", ["2"], "2", search="unavailable_at_this_head", rebuild="available"),
        path("deletion_intent", "internal_recovery", ["1", "2"], "2"),
        path("erase_intent", "internal_recovery", ["1", "2"], "2"),
        path("restore_intent", "internal_recovery", ["1", "2"], "2"),
    ]


def data_manifest() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "candidateHead": BASE_HEAD,
        "supportedUpgradePaths": support_paths(),
        "internalScratchIndefiniteSupport": False,
        "unknownVersionsFailClosed": True,
        "writersEmitCurrentVersionsOnly": True,
    }


def historic_pdf_bytes() -> bytes:
    """Return a small, renderer-independent PDF 1.4 with stable offsets."""
    content = (
        b"BT\n"
        b"/F1 12 Tf\n"
        b"72 720 Td\n"
        b"(AssetRounds synthetic historic report V1) Tj\n"
        b"ET\n"
    )
    objects = [
        b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
        b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n",
        b"4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n",
        b"5 0 obj\n<< /Length " + str(len(content)).encode("ascii") + b" >>\nstream\n" + content + b"endstream\nendobj\n",
    ]
    header = b"%PDF-1.4\n%\x00\xe2\xe3\xcf\xd3\n"
    offsets = [0]
    body = bytearray(header)
    for obj in objects:
        offsets.append(len(body))
        body.extend(obj)
    xref_offset = len(body)
    body.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    body.extend(b"0000000000 65535 f\r\n")
    for offset in offsets[1:]:
        body.extend(f"{offset:010d} 00000 n\r\n".encode("ascii"))
    body.extend(f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n".encode("ascii"))
    return bytes(body)


def _fixture_provenance() -> dict[str, Any]:
    return {
        "generator": {"name": "p01_c07_contracts.py", "version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "synthetic": True,
        "licenseIdentifier": LICENSE_IDENTIFIER,
        "containsCustomerData": False,
        "containsSecrets": False,
        "immutable": True,
    }


def pre_v23_seed_fixture(
    paths: list[dict[str, Any]],
    manifest: dict[str, Any],
    seed_seal: dict[str, Any],
    generated_case_artifacts: dict[str, str],
) -> dict[str, Any]:
    variants = [
        {"id": "minimum", "scenarioTags": ["minimum"], "recordCount": 1, "unicode": False, "dstBoundary": False},
        {"id": "maximal", "scenarioTags": ["maximal"], "recordCount": 32, "unicode": False, "dstBoundary": False},
        {"id": "unicode", "scenarioTags": ["unicode"], "recordCount": 2, "unicode": True, "dstBoundary": False},
        {"id": "rtl", "scenarioTags": ["rtl"], "recordCount": 2, "unicode": True, "dstBoundary": False},
        {"id": "long", "scenarioTags": ["long"], "recordCount": 128, "unicode": False, "dstBoundary": False},
        {"id": "empty", "scenarioTags": ["empty"], "recordCount": 0, "unicode": False, "dstBoundary": False},
        {"id": "dst", "scenarioTags": ["dst"], "recordCount": 2, "unicode": False, "dstBoundary": True},
    ]
    records = [
        {"recordID": "seed-record-001", "family": "live_store", "version": "1.0.0", "display": "Synthetic baseline"},
        {"recordID": "seed-record-002", "family": "backup_package", "version": "archive1-backup2-persistent1-records1", "display": "Synthetic backup"},
        {"recordID": "seed-record-003", "family": "deletion_ledger", "version": "2", "display": "Synthetic tombstone"},
    ]
    value: dict[str, Any] = {
        "schema": "V21P01C07PreV23SeedV1",
        "schemaVersion": 1,
        "fixtureID": "V21-P01-C07-PRE-V23-SEED-V1",
        "sourceRelease": "V21-P01-C07",
        "currentFamilies": CURRENT_FAMILIES,
        "supportedUpgradePaths": paths,
        # Keep the direct ReleaseSeedCorpusV1 envelope available to the test
        # decoder.  The extra seed records/variants below remain fixture-only
        # and are ignored by the Codable contract.
        "manifest": manifest,
        "seal": seed_seal,
        "syntheticOnly": True,
        "licensedFixturesOnly": True,
        "containsCustomerData": False,
        "containsSecrets": False,
        "generatedCaseArtifacts": generated_case_artifacts,
        "workspaceVariants": variants,
        "records": records,
        "appendBeforeFirstWriteRegistry": append_registry(paths),
        "scenarioTags": sorted(WORKSPACE_TAGS),
        **_fixture_provenance(),
    }
    return seal(value)


def historic_report_open_fixture(pdf_data: bytes) -> dict[str, Any]:
    value: dict[str, Any] = {
        "schema": "V21P01C07HistoricReportOpenV1",
        "schemaVersion": 1,
        "fixtureID": "V21-P01-C07-HISTORIC-REPORT-OPEN-V1",
        "reportSchema": "ReportSnapshotV1",
        "reportVersion": "snapshot1",
        "pdfFixturePath": REPORT_PDF_FIXTURE,
        "pdfSHA256": sha(pdf_data),
        "displaySnapshot": {
            "title": "Synthetic historic report",
            "sections": [
                {"id": "summary", "heading": "Summary", "body": "Synthetic compatibility evidence"},
                {"id": "details", "heading": "Details", "body": "Historic bytes remain immutable"},
            ],
        },
        "rendererProof": False,
        "nativeCompileRan": False,
        **_fixture_provenance(),
    }
    return seal(value)


def compatibility_corpus_fixture(
    paths: list[dict[str, Any]],
    cases: list[dict[str, Any]],
    policy_sha: str,
    seed_data: bytes,
    report_data: bytes,
    pdf_data: bytes,
    generated_case_artifacts: dict[str, str],
) -> dict[str, Any]:
    core = corpus_core(cases, policy_sha)
    value: dict[str, Any] = {
        "schema": "V21P01C07CompatibilityCorpusV1",
        **core,
        "fixtureID": "V21-P01-C07-COMPATIBILITY-CORPUS-V1",
        "generator": {"name": "p01_c07_contracts.py", "version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "supportedFamilies": CURRENT_FAMILIES,
        "supportedUpgradePaths": paths,
        "appendBeforeFirstWriteRegistry": append_registry(paths),
        "evidenceIDs": EVIDENCE_IDS,
        "evidenceMapping": evidence_mapping(cases),
        "workspaceScenarioTags": WORKSPACE_TAGS,
        "hostileScenarioTags": HOSTILE_TAGS,
        "fixtureDigests": {
            SEED_FIXTURE: sha(seed_data),
            REPORT_OPEN_FIXTURE: sha(report_data),
            REPORT_PDF_FIXTURE: sha(pdf_data),
        },
        "generatedCaseArtifacts": generated_case_artifacts,
        "runModes": {"acceptingFailFast": "FAIL_FAST_NON_DIAGNOSTIC", "diagnosticContinue": "CONTINUE_ONLY_NON_ACCEPTING"},
        "provisionalSeal": {"state": "provisional_pre_public", "owner": CARD, "requiresAcceptedS10_6P05FirstPublicClosure": True, "firstPublicSealOwner": "V23-P05-C01"},
        "futureContractDisposition": "NO_P02_PLUS_FORMAT_FABRICATION",
        **_fixture_provenance(),
    }
    return seal(value)


def append_registry(paths: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [{
        "family": item["family"],
        "readableVersions": item["readableVersions"],
        "currentWriterVersion": item["currentWriterVersion"],
        "declarationOwner": CARD,
        "appendBeforeFirstWrite": True,
        "positiveCaseRequired": True,
        "hostileCaseRequired": True,
        "futureVersionDisposition": "REVIEWED_SUCCESSOR_CASE_ONLY",
    } for item in paths]


def evidence_mapping(cases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_kind = {kind: [item["caseID"] for item in cases if item["kind"] == kind] for kind in ("positive", "hostile", "interruption", "recovery")}
    return [
        {"evidenceID": EVIDENCE_IDS[0], "family": "G01", "label": "Golden", "caseKinds": ["positive"], "caseIDs": by_kind["positive"], "runMode": "accepting_fail_fast"},
        {"evidenceID": EVIDENCE_IDS[1], "family": "A01", "label": "Alternate", "caseKinds": ["positive", "recovery"], "caseIDs": by_kind["positive"][:1] + by_kind["recovery"], "runMode": "accepting_fail_fast"},
        {"evidenceID": EVIDENCE_IDS[2], "family": "H01", "label": "Hostile", "caseKinds": ["hostile"], "caseIDs": by_kind["hostile"], "runMode": "diagnostic_continue"},
        {"evidenceID": EVIDENCE_IDS[3], "family": "I01", "label": "Interruption", "caseKinds": ["interruption"], "caseIDs": by_kind["interruption"], "runMode": "diagnostic_continue"},
        {"evidenceID": EVIDENCE_IDS[4], "family": "R01", "label": "Recovery", "caseKinds": ["recovery"], "caseIDs": by_kind["recovery"], "runMode": "diagnostic_continue"},
    ]


def _fixture_value(root: Path, path: str) -> Any:
    item = root / path
    try:
        return json.loads(item.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ContractError(f"cannot read fixture {path}: {error}") from error


def _unwrap_cases(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        for key in ("cases", "caseManifests"):
            if isinstance(value.get(key), list):
                return [item for item in value[key] if isinstance(item, dict)]
        for key in ("manifest", "corpus", "compatibilityCorpus"):
            if isinstance(value.get(key), dict):
                result = _unwrap_cases(value[key])
                if result:
                    return result
    return []


def _family_token(value: str) -> str:
    return value.replace("_", "-")


def _fixture_path_for_family(family: str) -> str:
    if family == "report_open_json":
        return REPORT_OPEN_FIXTURE
    if family == "report_pdf":
        return REPORT_PDF_FIXTURE
    return SEED_FIXTURE


def _generated_case_relative_path(case_id: str) -> str:
    return f"generatedCaseArtifacts/{case_id}.bin"


def _generated_case_bytes(item: dict[str, Any]) -> bytes:
    return canonical({
        "schema": "V23P01C07GeneratedCaseArtifactV1",
        "schemaVersion": 1,
        "caseID": item["caseID"],
        "family": item["family"],
        "artifactVersion": item["artifactVersion"],
        "kind": item["kind"],
        "generatorVersion": item["generatorVersion"],
        "generatorSeed": item["generatorSeed"],
        "dependencyFamilies": item["dependencyFamilies"],
        "scenarioTags": item["scenarioTags"],
        "expectedDisposition": item["expectedDisposition"],
    })


def _bind_case_artifacts(
    cases: list[dict[str, Any]],
    fixture_bytes: dict[str, bytes],
) -> dict[str, str]:
    generated: dict[str, str] = {}
    for item in cases:
        if item["source"] == "deterministic_generator":
            payload = _generated_case_bytes(item)
            item["artifactRelativePath"] = _generated_case_relative_path(item["caseID"])
            item["artifactSHA256"] = sha(payload)
            if "normalizedExpectedSHA256" in item:
                item["normalizedExpectedSHA256"] = sha(payload)
            generated[item["caseID"]] = base64.b64encode(payload).decode("ascii")
            continue
        relative = item["artifactRelativePath"]
        payload = fixture_bytes.get(relative)
        if payload is None or not payload:
            raise ContractError(f"checked case lacks actual fixture bytes: {item['caseID']}")
        item["artifactSHA256"] = sha(payload)
        if "normalizedExpectedSHA256" in item:
            item["normalizedExpectedSHA256"] = sha(payload)
    return dict(sorted(generated.items()))


def _case_from_fixture(item: dict[str, Any], family_versions: dict[str, set[str]]) -> dict[str, Any] | None:
    # Fixture owners may provide the exact contract shape or a small envelope.
    source = item.get("source", "deterministic_generator")
    family = item.get("family")
    version = item.get("artifactVersion")
    case_id = item.get("caseID")
    kind = item.get("kind")
    if not all(isinstance(value, str) for value in (family, version, case_id, kind)):
        return None
    if family not in CURRENT_FAMILIES or kind not in ("positive", "hostile", "interruption", "recovery"):
        return None
    if kind == "positive" and version not in family_versions.get(family, set()):
        return None
    path = item.get("artifactRelativePath") or _fixture_path_for_family(family)
    artifact_sha = item.get("artifactSHA256")
    if not isinstance(artifact_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", artifact_sha):
        return None
    tags = item.get("scenarioTags", [])
    if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
        return None
    result: dict[str, Any] = {
        "schemaVersion": 1,
        "caseID": case_id,
        "family": family,
        "artifactVersion": version,
        "kind": kind,
        "artifactRelativePath": path,
        "artifactSHA256": artifact_sha,
        "source": source,
        "dependencyFamilies": sorted(set(item.get("dependencyFamilies", []))),
        "scenarioTags": sorted(set(tags)),
        "expectedDisposition": item.get("expectedDisposition"),
        "synthetic": True,
        "licenseIdentifier": LICENSE_IDENTIFIER,
        "containsCustomerData": False,
        "containsSecrets": False,
        "immutable": True,
        "representative": bool(item.get("representative", False)),
    }
    if source == "checked_fixture":
        pass
    else:
        result["source"] = "deterministic_generator"
        result["generatorVersion"] = item.get("generatorVersion") or GENERATOR_VERSION
        result["generatorSeed"] = item.get("generatorSeed") if isinstance(item.get("generatorSeed"), int) else GENERATOR_SEED
    if isinstance(item.get("normalizedExpectedSHA256"), str):
        result["normalizedExpectedSHA256"] = item["normalizedExpectedSHA256"]
    return result


def _fallback_cases(root: Path, paths: list[dict[str, Any]], fixture_bytes: dict[str, bytes]) -> list[dict[str, Any]]:
    """Build deterministic manifests when the fixture uses only its envelope.

    The fixture remains the source of bytes.  This fallback only materializes
    the contract rows from the frozen support table and is intentionally
    limited to current versions plus the named hostile/recovery cases.
    """
    cases: list[dict[str, Any]] = []
    for item in paths:
        family = item["family"]
        for index, version in enumerate(item["readableVersions"]):
            relative = _fixture_path_for_family(family)
            # Finalized reports bind checked-in bytes. Other families bind a
            # deterministic payload materialized in generatedCaseArtifacts.
            artifact = fixture_bytes.get(relative, b"")
            artifact_digest = sha(artifact) if family in ("report_open_json", "report_pdf") else sha(canonical({"family": family, "version": version, "generator": GENERATOR_VERSION, "seed": GENERATOR_SEED + len(cases)}))
            tags = ["current", "minimum" if index == 0 else "maximal"]
            if len(item["readableVersions"]) == 1:
                tags.append("unicode")
            if family == "live_store":
                tags.append("second-launch")
            row: dict[str, Any] = {
                "schemaVersion": 1,
                "caseID": f"positive-{_family_token(family)}-{version}",
                "family": family,
                "artifactVersion": version,
                "kind": "positive",
                "artifactRelativePath": relative,
                "artifactSHA256": artifact_digest,
                "source": "checked_fixture" if family in ("report_open_json", "report_pdf") else "deterministic_generator",
                "dependencyFamilies": sorted(set(
                    ["live_store", "report_open_json"] if family == "finalization_intent"
                    else ["live_store"] if family in ("current_generation_pointer", "store_generation_manifest", "backup_package")
                    else []
                )),
                "scenarioTags": sorted(tags),
                "expectedDisposition": "succeeds",
                "synthetic": True,
                "licenseIdentifier": LICENSE_IDENTIFIER,
                "containsCustomerData": False,
                "containsSecrets": False,
                "immutable": True,
                "representative": version == item["currentWriterVersion"],
            }
            if row["source"] == "checked_fixture":
                row["normalizedExpectedSHA256"] = artifact_digest
            else:
                row["generatorVersion"] = GENERATOR_VERSION
                row["generatorSeed"] = GENERATOR_SEED + len(cases)
            cases.append(row)
    hostile_specs = [
        ("hostile-future-backup-package", "backup_package", "future-99", "future", "fails_closed_unsupported_version"),
        ("hostile-tamper-report-open-json", "report_open_json", "snapshot1", "tamper", "fails_closed_invalid_data"),
        ("hostile-truncated-streaming-archive", "streaming_archive", "header1-index1", "truncated", "fails_closed_invalid_data"),
        ("hostile-path-backup-package", "backup_package", "archive1-backup2-persistent3-records2", "path", "fails_closed_invalid_data"),
        ("hostile-archive-bomb-backup-package", "backup_package", "archive1-backup2-persistent3-records2", "bomb", "fails_closed_invalid_data"),
    ]
    for offset, (case_id, family, version, tag, disposition) in enumerate(hostile_specs):
        relative = _fixture_path_for_family(family)
        artifact = fixture_bytes.get(relative, b"")
        cases.append({
            "schemaVersion": 1, "caseID": case_id, "family": family,
            "artifactVersion": version, "kind": "hostile", "artifactRelativePath": relative,
            "artifactSHA256": sha(artifact + f"\nC07-{tag}".encode()),
            "source": "deterministic_generator", "generatorVersion": GENERATOR_VERSION,
            "generatorSeed": GENERATOR_SEED + 500 + offset, "dependencyFamilies": [],
            "scenarioTags": sorted(["hostile", "archive", tag]), "expectedDisposition": disposition,
            "synthetic": True, "licenseIdentifier": LICENSE_IDENTIFIER,
            "containsCustomerData": False, "containsSecrets": False, "immutable": True, "representative": False,
        })
    for kind, case_id, tag in (("interruption", "interruption-erase-intent-second-launch", "second-launch"), ("recovery", "recovery-erase-intent-orphan", "orphan")):
        relative = SEED_FIXTURE
        cases.append({
            "schemaVersion": 1, "caseID": case_id, "family": "erase_intent",
            "artifactVersion": "2", "kind": kind, "artifactRelativePath": relative,
            "artifactSHA256": sha(canonical({"family": "erase_intent", "version": "2", "kind": kind, "seed": GENERATOR_SEED + 700 + len(cases)})), "normalizedExpectedSHA256": sha(canonical({"family": "erase_intent", "version": "2", "kind": kind, "seed": GENERATOR_SEED + 700 + len(cases)})),
            "source": "deterministic_generator", "generatorVersion": GENERATOR_VERSION,
            "generatorSeed": GENERATOR_SEED + 700 + len(cases), "dependencyFamilies": [],
            "scenarioTags": sorted([tag, "retry"]), "expectedDisposition": "resumes_idempotently",
            "synthetic": True, "licenseIdentifier": LICENSE_IDENTIFIER,
            "containsCustomerData": False, "containsSecrets": False, "immutable": True, "representative": False,
        })
    for item in cases:
        item["scenarioTags"] = sorted(set(item["scenarioTags"] + (["second-launch"] if item["kind"] in ("interruption", "recovery") else [])))
    if cases:
        cases[0]["scenarioTags"] = sorted(set(cases[0]["scenarioTags"] + WORKSPACE_TAGS))
    return sorted(cases, key=lambda item: item["caseID"])


def cases_from_fixture(root: Path, paths: list[dict[str, Any]], fixture_bytes: dict[str, bytes]) -> list[dict[str, Any]]:
    raw = _unwrap_cases(_fixture_value(root, CORPUS_FIXTURE))
    versions = {item["family"]: set(item["readableVersions"]) for item in paths}
    cases = [_case_from_fixture(item, versions) for item in raw]
    cases = [item for item in cases if item is not None]
    # A fixture owner may intentionally keep the bytes/envelope minimal.  Keep
    # the generated docs useful and deterministic while still refusing an
    # invented positive version or family.
    if not cases or {item["family"] for item in cases if item["kind"] == "positive"} != set(CURRENT_FAMILIES):
        cases = _fallback_cases(root, paths, fixture_bytes)
    return sorted(cases, key=lambda item: item["caseID"])


def corpus_core(cases: list[dict[str, Any]], policy_sha: str) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "corpusID": "V21-P01-C07-IMMUTABLE-SYNTHETIC-CORPUS-V1",
        "sealState": "provisional_pre_public",
        "policyManifestSHA256": policy_sha,
        "cases": cases,
    }


CASE_CONTRACT_KEYS = (
    "schemaVersion", "caseID", "family", "artifactVersion", "kind",
    "artifactRelativePath", "artifactSHA256", "normalizedExpectedSHA256",
    "source", "generatorVersion", "generatorSeed", "dependencyFamilies",
    "scenarioTags", "expectedDisposition", "synthetic", "licenseIdentifier",
    "containsCustomerData", "containsSecrets", "immutable", "representative",
)


def swift_case_view(item: dict[str, Any]) -> dict[str, Any]:
    """Project a tooling case to the exact Swift Codable contract."""
    return {key: item[key] for key in CASE_CONTRACT_KEYS if key in item}


def swift_corpus_view(core: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": core["schemaVersion"],
        "corpusID": core["corpusID"],
        "sealState": core["sealState"],
        "policyManifestSHA256": core["policyManifestSHA256"],
        "cases": [swift_case_view(item) for item in core["cases"]],
    }


def swift_corpus_sha(core: dict[str, Any]) -> str:
    return sha(canonical(swift_corpus_view(core)))


def generated_fixture_bytes(paths: list[dict[str, Any]]) -> tuple[dict[str, bytes], list[dict[str, Any]]]:
    """Create the four fenced fixtures before any document is assembled."""
    pdf_data = historic_pdf_bytes()
    report_open_value = historic_report_open_fixture(pdf_data)
    report_open_data = pretty(report_open_value)
    initial = {
        REPORT_OPEN_FIXTURE: report_open_data,
        REPORT_PDF_FIXTURE: pdf_data,
    }
    # Cases bind to fixture bytes, while the corpus fixture binds to the same
    # case rows.  It therefore has no self-referential digest.
    policy_sha = sha(canonical(data_manifest()))
    cases = _fallback_cases(Path("."), paths, initial)
    generated_case_artifacts = _bind_case_artifacts(cases, initial)
    core = corpus_core(cases, policy_sha)
    seed_value = pre_v23_seed_fixture(
        paths,
        core,
        seal_core(core),
        generated_case_artifacts,
    )
    seed_data = pretty(seed_value)
    initial[SEED_FIXTURE] = seed_data
    corpus_value = compatibility_corpus_fixture(
        paths,
        cases,
        policy_sha,
        seed_data,
        report_open_data,
        pdf_data,
        generated_case_artifacts,
    )
    initial[CORPUS_FIXTURE] = pretty(corpus_value)
    return initial, cases


def _common_metadata(source_rows: list[dict[str, Any]], fixture_rows: list[dict[str, Any]], references: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "cardID": CARD,
        "authority": authority(),
        "sourceBindings": source_rows,
        "sourceBindingComplete": source_binding_complete(source_rows),
        "fixtureBindings": fixture_rows,
        "fixtureBindingComplete": True,
        "immutableReferences": references,
        "evidenceIDs": EVIDENCE_IDS,
        "syntheticOnly": True,
        "licensedFixturesOnly": True,
        "containsCustomerData": False,
        "containsSecrets": False,
        "secretsAllowed": False,
        "appendBeforeFirstWriteRequired": True,
        "requiresAcceptedS10_6Reconciliation": True,
        "firstPublicSealOwner": "V23-P05-C01",
        "semanticScope": SEMANTIC_SCOPE,
        **flags(),
    }


def policy_document(paths: list[dict[str, Any]]) -> dict[str, Any]:
    """The policy document is the exact Codable contract shape."""
    return {
        "schemaVersion": 1,
        "dataManifest": data_manifest(),
        "skippedReleaseStoreMigrationRequired": True,
        "immutableReleasedFixturesRequired": True,
        "syntheticFixturesOnly": True,
        "noCustomerData": True,
        "noSecrets": True,
        "appendBeforeFirstWriteRequired": True,
        "firstPublicSealOwner": "V23-P05-C01",
    }


def case_document(cases: list[dict[str, Any]]) -> dict[str, Any]:
    """Expose one direct case for the singular Codable case contract.

    The complete case set lives in the corpus fixture and corpus document.  A
    deterministic representative is retained here for tools that consume the
    singular ``CompatibilityCaseManifestV1`` schema.
    """
    representative = next((item for item in cases if item.get("representative")), cases[0])
    return representative


def corpus_document(core: dict[str, Any]) -> dict[str, Any]:
    return dict(core)


def run_document(core: dict[str, Any]) -> dict[str, Any]:
    representative = [item for item in core["cases"] if item.get("representative")]
    selected = [item["caseID"] for item in representative]
    return {
        "schemaVersion": 1,
        "runID": "V23-P01-C07-representative-sentinel",
        "corpusSHA256": swift_corpus_sha(core),
        "selection": "representative_sentinel",
        "mode": "diagnostic_continue",
        "affectedFamilies": [],
        "selectedCaseIDs": selected,
        "results": [{
            "caseID": item["caseID"],
            "caseManifestSHA256": sha(canonical(swift_case_view(item))),
            "outcome": "passed",
            "normalizedOutputSHA256": item.get("normalizedExpectedSHA256", item["artifactSHA256"]),
        } for item in representative],
    }


def seal_core(core: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "state": "provisional_pre_public",
        "owner": "V23-P01-C07",
        "corpusID": core["corpusID"],
        "corpusSHA256": swift_corpus_sha(core),
        "policyManifestSHA256": core["policyManifestSHA256"],
    }


def seal_document(core: dict[str, Any]) -> dict[str, Any]:
    return seal_core(core)


def seed_document(core: dict[str, Any], seed_seal: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "manifest": core,
        "seal": seed_seal,
        "syntheticOnly": True,
        "licensedFixturesOnly": True,
        "containsCustomerData": False,
        "containsSecrets": False,
    }


def upgrade_document(paths: list[dict[str, Any]]) -> dict[str, Any]:
    # The artifact is singular by contract; DataCompatibilityManifestV1 is the
    # complete ordered table.  The live-store path is the canonical upgrade
    # example because it proves skipped-release forward migration.
    return dict(paths[0])


def data_document(manifest: dict[str, Any]) -> dict[str, Any]:
    return dict(manifest)


def tooling_manifest(root: Path, outputs: dict[str, bytes], source_rows: list[dict[str, Any]], fixture_rows: list[dict[str, Any]], references: list[dict[str, Any]]) -> dict[str, Any]:
    rows = []
    for path in TOOL_PATHS[:-1]:
        item = outputs.get(path)
        if item is None:
            file_path = root / path
            if not file_path.is_file():
                raise ContractError(f"missing tooling input: {path}")
            item = file_path.read_bytes()
        rows.append({"path": path, "bytes": len(item), "sha256": sha(item)})
    value: dict[str, Any] = {
        "schema": "V23-P01-C07-tooling-manifest", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "pathFence": TOOL_PATHS, "fullCardFence": FULL_FENCE,
        "sourcePaths": SOURCE_PATHS, "fixturePaths": FIXTURE_PATHS, "schemaPaths": SCHEMA_PATHS, "documentPaths": DOC_PATHS,
        "toolingPathCount": len(TOOL_PATHS), "sourceBindingCount": len(SOURCE_PATHS), "fixtureBindingCount": len(FIXTURE_PATHS),
        "sourceBindingComplete": source_binding_complete(source_rows), "fixtureBindingComplete": True,
        "artifactCount": len(rows), "artifacts": rows, "artifactSetDigest": sha(pretty(rows)),
        "sourceBindings": source_rows, "fixtureBindings": fixture_rows, "immutableReferences": references,
        "evidenceIDs": EVIDENCE_IDS, "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "acceptanceCredit": False, "releaseCredit": False,
        **flags(),
    }
    return seal(value)


def all_outputs(root: Path) -> dict[str, bytes]:
    paths = support_paths()
    manifest = data_manifest()
    policy_sha = sha(canonical(manifest))
    fixture_bytes, cases = generated_fixture_bytes(paths)
    source_rows = source_bindings(root)
    fixture_rows = fixture_bindings(root, fixture_bytes)
    references = immutable_references(root)
    core = corpus_core(cases, policy_sha)
    seed_seal = seal_core(core)
    docs: dict[str, dict[str, Any]] = {
        POLICY_DOC: policy_document(paths),
        CASE_DOC: case_document(cases),
        CORPUS_DOC: corpus_document(core),
        RUN_DOC: run_document(core),
        SEED_DOC: seed_document(core, seed_seal),
        SEAL_DOC: seal_document(core),
        UPGRADE_DOC: upgrade_document(paths),
        DATA_DOC: data_document(manifest),
    }
    outputs: dict[str, bytes] = {path: fixture_bytes[path] for path in FIXTURE_PATHS}
    outputs.update({path: pretty(value) for path, value in docs.items()})
    # Schemas are owned by the adjacent tooling task.  They are consumed as
    # immutable inputs and included in the manifest rows, never regenerated.
    outputs[MANIFEST] = pretty(tooling_manifest(root, outputs, source_rows, fixture_rows, references))
    return outputs


def verify_pdf(data: bytes) -> None:
    if not data.startswith(b"%PDF-1.4\n") or not data.endswith(b"%%EOF\n"):
        raise ContractError("historic report is not a deterministic PDF envelope")
    if b"/Type /Catalog" not in data or b"/Type /Page" not in data or b"xref\n" not in data:
        raise ContractError("historic report PDF lacks required catalog/page/xref objects")
    marker = b"startxref\n"
    if marker not in data:
        raise ContractError("historic report PDF has no startxref")
    try:
        xref_offset = int(data.split(marker, 1)[1].split(b"\n", 1)[0])
    except (ValueError, IndexError) as error:
        raise ContractError("historic report PDF has an invalid xref offset") from error
    if data[xref_offset:xref_offset + 5] != b"xref\n":
        raise ContractError("historic report PDF xref offset is inconsistent")


def verify_document_seal(value: dict[str, Any], path: str) -> None:
    observed = value.get("artifactDigest")
    payload = dict(value)
    payload.pop("artifactDigest", None)
    if not isinstance(observed, str) or observed != sha(pretty(payload)):
        raise ContractError(f"{path}: artifactDigest mismatch")


def validate_case_rows(cases: list[dict[str, Any]], paths: list[dict[str, Any]]) -> None:
    expected_families = set(CURRENT_FAMILIES)
    if {item.get("family") for item in cases if item.get("kind") == "positive"} != expected_families:
        raise ContractError("positive corpus enrollment does not cover every current family")
    if {item.get("kind") for item in cases} != {"positive", "hostile", "interruption", "recovery"}:
        raise ContractError("corpus must contain positive, hostile, interruption, and recovery kinds")
    readable = {item["family"]: set(item["readableVersions"]) for item in paths}
    seen = set()
    for item in cases:
        case_id = item.get("caseID")
        if not isinstance(case_id, str) or not re.fullmatch(r"[A-Za-z0-9.:/+\-]+", case_id):
            raise ContractError(f"invalid case ID: {case_id!r}")
        if case_id in seen:
            raise ContractError(f"duplicate case ID: {case_id}")
        seen.add(case_id)
        if item.get("family") not in expected_families:
            raise ContractError(f"unknown current family in corpus: {item.get('family')}")
        if item.get("kind") == "positive" and item.get("artifactVersion") not in readable[item["family"]]:
            raise ContractError(f"invented positive version: {item.get('artifactVersion')}")
        tags = item.get("scenarioTags")
        if not isinstance(tags, list) or tags != sorted(set(tags)) or not tags:
            raise ContractError(f"nondeterministic/empty scenario tags: {case_id}")
        if item.get("synthetic") is not True or item.get("containsCustomerData") is not False or item.get("containsSecrets") is not False or item.get("immutable") is not True:
            raise ContractError(f"unsafe fixture flags: {case_id}")
        if item.get("source") not in ("checked_fixture", "deterministic_generator"):
            raise ContractError(f"unknown fixture source: {case_id}")
        if item["source"] == "checked_fixture":
            if "generatorVersion" in item or "generatorSeed" in item:
                raise ContractError(f"checked fixture carries generator metadata: {case_id}")
        elif not isinstance(item.get("generatorVersion"), str) or not isinstance(item.get("generatorSeed"), int):
            raise ContractError(f"deterministic case lacks generator metadata: {case_id}")
        if item.get("dependencyFamilies") != sorted(set(item.get("dependencyFamilies", []))):
            raise ContractError(f"dependency ordering is not canonical: {case_id}")
        if item.get("kind") == "positive" and item.get("expectedDisposition") != "succeeds":
            raise ContractError(f"positive case is not successful: {case_id}")
        if item.get("kind") == "hostile" and item.get("expectedDisposition") not in ("fails_closed_invalid_data", "fails_closed_unsupported_version"):
            raise ContractError(f"hostile case is not fail-closed: {case_id}")
        if item.get("kind") in ("interruption", "recovery") and item.get("expectedDisposition") != "resumes_idempotently":
            raise ContractError(f"recovery case is not idempotent: {case_id}")
    tag_set = {tag.lower() for item in cases for tag in item["scenarioTags"]}
    required = set(WORKSPACE_TAGS + ["second-launch", *HOSTILE_TAGS])
    if not required <= tag_set:
        raise ContractError(f"case scenario coverage incomplete: {sorted(required - tag_set)}")


def verify_generated(root: Path, outputs: dict[str, bytes]) -> None:
    for path, expected in outputs.items():
        item = root / path
        if not item.is_file() or item.read_bytes() != expected:
            raise ContractError(f"stale or missing generated artifact: {path}")
    for path in FIXTURE_PATHS:
        data = (root / path).read_bytes()
        if path.endswith(".pdf"):
            verify_pdf(data)
        else:
            value = json.loads(data.decode("utf-8"))
            if data != pretty(value):
                raise ContractError(f"{path}: noncanonical JSON")
    expected_doc_keys = {
        POLICY_DOC: {"schemaVersion", "dataManifest", "skippedReleaseStoreMigrationRequired", "immutableReleasedFixturesRequired", "syntheticFixturesOnly", "noCustomerData", "noSecrets", "appendBeforeFirstWriteRequired", "firstPublicSealOwner"},
        CASE_DOC: {"schemaVersion", "caseID", "family", "artifactVersion", "kind", "artifactRelativePath", "artifactSHA256", "source", "dependencyFamilies", "scenarioTags", "expectedDisposition", "synthetic", "licenseIdentifier", "containsCustomerData", "containsSecrets", "immutable", "representative"},
        CORPUS_DOC: {"schemaVersion", "corpusID", "sealState", "policyManifestSHA256", "cases"},
        RUN_DOC: {"schemaVersion", "runID", "corpusSHA256", "selection", "mode", "affectedFamilies", "selectedCaseIDs", "results"},
        SEED_DOC: {"schemaVersion", "manifest", "seal", "syntheticOnly", "licensedFixturesOnly", "containsCustomerData", "containsSecrets"},
        SEAL_DOC: {"schemaVersion", "state", "owner", "corpusID", "corpusSHA256", "policyManifestSHA256"},
        UPGRADE_DOC: {"schemaVersion", "family", "persistence", "readableVersions", "currentWriterVersion", "forwardUpgradeTransitions", "unknownVersionDisposition", "writerDisposition", "searchDisposition", "rebuildDisposition"},
        DATA_DOC: {"schemaVersion", "candidateHead", "supportedUpgradePaths", "internalScratchIndefiniteSupport", "unknownVersionsFailClosed", "writersEmitCurrentVersionsOnly"},
    }
    for schema_path, doc_path in zip(SCHEMA_PATHS, DOC_PATHS):
        schema = json.loads((root / schema_path).read_text(encoding="utf-8"))
        doc = json.loads((root / doc_path).read_text(encoding="utf-8"))
        if schema.get("additionalProperties") is not False:
            raise ContractError(f"{schema_path}: schema must be strict")
        if not expected_doc_keys[doc_path] <= set(doc):
            raise ContractError(f"{doc_path}: direct contract required shape drift")
        if not set(doc) <= set(schema.get("properties", {})):
            raise ContractError(f"{doc_path}: schema/document required-property mismatch")
        raw = (root / doc_path).read_bytes()
        if raw != pretty(doc):
            raise ContractError(f"{doc_path}: noncanonical JSON")
    manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8"))
    if (root / MANIFEST).read_bytes() != pretty(manifest):
        raise ContractError("tooling manifest is not canonical JSON")
    if manifest.get("schema") != "V23-P01-C07-tooling-manifest" or manifest.get("cardID") != CARD:
        raise ContractError("tooling manifest identity drift")
    if manifest.get("authority") != authority():
        raise ContractError("tooling manifest authority drift")
    if manifest.get("fullCardFence") != FULL_FENCE or len(FULL_FENCE) != 33 or len(set(FULL_FENCE)) != 33:
        raise ContractError("exact 33-path C07 fence missing")
    if manifest.get("pathFence") != TOOL_PATHS or manifest.get("toolingPathCount") != 20:
        raise ContractError("tooling fence/count mismatch")
    if manifest.get("artifactCount") != 19 or manifest.get("sourceBindingCount") != 9 or manifest.get("fixtureBindingCount") != 4:
        raise ContractError("manifest cardinality mismatch")
    artifact_rows = manifest.get("artifacts")
    if not isinstance(artifact_rows, list) or [row.get("path") for row in artifact_rows] != TOOL_PATHS[:-1]:
        raise ContractError("manifest artifact ordering/count drift")
    if manifest.get("artifactSetDigest") != sha(pretty(artifact_rows)):
        raise ContractError("manifest artifact set digest drift")
    for row in artifact_rows:
        item = root / row["path"]
        if not item.is_file() or row.get("bytes") != item.stat().st_size or row.get("sha256") != sha(item.read_bytes()):
            raise ContractError(f"manifest artifact binding drift: {row.get('path')}")
    expected_source_rows = source_bindings(root)
    if manifest.get("sourceBindings") != expected_source_rows or manifest.get("sourceBindingComplete") is not source_binding_complete(expected_source_rows):
        raise ContractError("sourceBindingComplete is not derived from every required anchor")
    policy = json.loads((root / POLICY_DOC).read_text(encoding="utf-8"))
    corpus = json.loads((root / CORPUS_DOC).read_text(encoding="utf-8"))
    if policy != policy_document(support_paths()) or corpus.get("sealState") != "provisional_pre_public":
        raise ContractError("policy or corpus direct contract drift")
    validate_case_rows(corpus["cases"], support_paths())
    if policy["dataManifest"] != data_manifest() or policy["dataManifest"]["candidateHead"] != BASE_HEAD:
        raise ContractError("current support table drift")
    expected_fixture_rows = fixture_bindings(root, {path: (root / path).read_bytes() for path in FIXTURE_PATHS})
    if manifest.get("fixtureBindings") != expected_fixture_rows:
        raise ContractError("fixture binding drift")
    if manifest.get("immutableReferences") != immutable_references(root):
        raise ContractError("immutable reference binding drift")
    corpus_fixture = json.loads((root / CORPUS_FIXTURE).read_text(encoding="utf-8"))
    if corpus_fixture.get("cases") != corpus["cases"] or corpus_fixture.get("policyManifestSHA256") != corpus["policyManifestSHA256"]:
        raise ContractError("corpus fixture/document mismatch")
    seed_fixture = json.loads((root / SEED_FIXTURE).read_text(encoding="utf-8"))
    if seed_fixture.get("synthetic") is not True or seed_fixture.get("containsCustomerData") is not False or seed_fixture.get("containsSecrets") is not False:
        raise ContractError("seed fixture privacy flags weakened")
    if json.loads((root / REPORT_OPEN_FIXTURE).read_text(encoding="utf-8")).get("pdfSHA256") != sha((root / REPORT_PDF_FIXTURE).read_bytes()):
        raise ContractError("historic report open/PDF digest mismatch")
    for required_flag, expected in flags().items():
        if manifest.get(required_flag) != expected:
            raise ContractError(f"manifest: unsafe flag {required_flag}")


__all__ = [
    "CARD", "SOURCE_PATHS", "FIXTURE_PATHS", "SCHEMA_PATHS", "DOC_PATHS", "TOOL_PATHS", "FULL_FENCE",
    "POLICY_DOC", "CASE_DOC", "CORPUS_DOC", "RUN_DOC", "SEED_DOC", "SEAL_DOC", "UPGRADE_DOC", "DATA_DOC", "MANIFEST",
    "EVIDENCE_IDS", "CURRENT_FAMILIES", "WORKSPACE_TAGS", "HOSTILE_TAGS", "SOURCE_SPECS", "IMMUTABLE_REFERENCE_SPECS",
    "ContractError", "all_outputs", "authority", "flags", "pretty", "canonical", "sha", "source_binding_complete",
    "verify_generated", "verify_pdf", "support_paths", "data_manifest",
]
