#!/usr/bin/env python3
"""Deterministic portable-review contract tooling for V23-P03-C48.

The module is deliberately source-regression heavy.  It is the only producer
of the C48 schema and four tooling receipts, while the verifier consumes the
same functions in a fresh Python process.
"""
from __future__ import annotations

import ast
import base64
import hashlib
import importlib.util
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

CARD = "V23-P03-C48"
TITLE = "Integrity-bound cleartext portable review, bearer-capability lifecycle, out-of-band response recording, and immutable reconciliation"
REGISTER_ORDINAL = 78
BASE_HEAD = "ba45022b454f557dcd4d3a5bdaf1cd441022c027"
BASE_TREE = "1230fefc208a4ae79217f4a2008ebabf6e920b46"
COORDINATION_HEAD = "1857c11d7b1aed873d9ace8f88c1ff8d9222ec45"
COORDINATION_TREE = "eeee7ab38db3bf975160e3abb4e7344f22dfc879"
COORDINATION_CAS_SEQUENCE = 331
HYDRATION_REVISION = 2

PREREQUISITE_DIGEST = "30697ca3fb54b086b1e526b55cd3d8aeb80b8198c68cf6a241524f271dfd070c"
CONTEXT_DIGEST = "6bb2ef2e652995ac84afad1bf7c07cd5faf8bbe27aba0e3707bc9514c2aad235"
FENCE_DIGEST = "1abe6ceebd594bee60bdec5fd19b8758c18e585dc7dd35a5757e500b75673027"
CORRECTION_RECEIPT_DIGEST = "4dfc9dba685fa60019e70ed624b8e60527687821cf064dc9eb7245d5cc2715c0"
HYDRATION_TRANSITION_DIGEST = "da575439d9e84a2a455e9130253720e7780948633fefe4ae0156704757c00908"
COORDINATION_LEDGER_DIGEST = "4f510bb701e747ab57555e4af632f6b51bd2c4d6cb21e1f8fd5b2ddf35cdcba7"
COORDINATION_PROJECTION_DIGEST = "10da3964262dfe56f050e1074810bee67144ac3123d05ce98675e0703d6a503c"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
AUTHORIZED_OVERLAP_COUNT = 0
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
S10_RESERVED_PATH_COUNT = 86

SCHEMA_PATH = "Scripts/v23/portable-review.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C48PortableReviewContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C48PortableReviewEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C48BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C48-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c48_contracts.py",
    "Scripts/v23/generate_p03_c48_contracts.py",
    "Scripts/v23/verify_p03_c48_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)

# C48's six newly-created implementation/test rows.  The source lane owns
# the bytes; this lane only audits them.
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/ReviewExchange/PortableReviewContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/PortableReviewPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/ReviewExchange/PortableReviewCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/ReviewExchange/PortableExchangeSessionStoreV2.swift",
    "FieldEvidenceAppTests/V9_55PortableReviewTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/ReviewExchange/V22P03C48PortableReviewCorpusV1.json",
)

# The corrected C48 fence begins with C24's exact 105-path existing inventory,
# followed by the 20 explicitly hydrated C48 prerequisite/integration rows.
_C24_PATH = Path(__file__).with_name("p03_c24_contracts.py")
_C24_SHA256 = "9f80c6bb01de473897b7ccd0fec3ef275e76741368921873600ae91fbdfae2b4"
_C48_ADDITIONAL_EXISTING_PATHS = (
    "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AccessibleDocumentPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Reporting/AccessibleDocumentCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/AccessibleDocumentLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/AccessibleDocuments/V22P03C24AccessibleDocumentCorpusV1.json",
    "FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceAppTests/V9_04StreamingArchiveTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Archives/V21P01C04ArchiveCorpusV1.json",
    "FieldEvidenceApp/Domain/InspectionKernel/InspectionReviewContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/ReviewAndCorrectiveActionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Review/InspectionReviewCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Review/InspectionReviewLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_28InspectionReviewCorrectiveActionTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/ReviewAndCorrectiveAction/V21P03C14ReviewAndCorrectiveActionCorpusV1.json",
    "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Info.plist",
    "FieldEvidenceAppTests/V9_02FileAuthorityTests.swift",
)


def _c24_existing_paths() -> tuple[str, ...]:
    if not _C24_PATH.is_file() or hashlib.sha256(_C24_PATH.read_bytes()).hexdigest() != _C24_SHA256:
        raise ValueError("sealed C24 tooling inventory differs")
    spec = importlib.util.spec_from_file_location("_sealed_p03_c24_contracts", _C24_PATH)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load sealed C24 tooling inventory")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return tuple(module.EXISTING_PATHS)


EXISTING_PATHS = _c24_existing_paths() + _C48_ADDITIONAL_EXISTING_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = (
    "PortableReviewProtocolReleaseV1",
    "BearerResponseCapabilityV1",
    "ReviewCapabilityProofV1",
    "ReviewResponseAcquisitionKindV1",
    "OriginRecordedReviewResponseV1",
    "ReviewRequestManifestV1",
    "ReviewSubjectSnapshotBindingV1",
    "ReviewRequestPurposeV1",
    "ReviewRequestFileEntryV1",
    "ReviewResponseEnvelopeV1",
    "ReviewResponseBodyV1",
    "ReviewResponseItemV1",
    "ResponseAuthorAssertionV1",
    "RecipientReviewRequestEventV1",
    "ReviewRequestExportReceiptV1",
    "ExternalReviewResponseRecordV1",
    "ExternalReviewImportPlanV1",
    "ExternalReviewImportDecisionV1",
    "ExternalReviewImportReceiptV1",
    "ReviewRequestStateProjectionV1",
    "ReviewExchangeBudgetV1",
    "PortableExchangeSessionStoreV2",
)
TEST_METHODS = (
    "testV23P03C48G01GoldenRequestResponseAndNormativeVectorUseTypedContracts",
    "testV23P03C48A01OriginRecordedElsewhereKeepsUnverifiedHistorySeparateFromEligibility",
    "testV23P03C48H01TamperReplayDivergenceHostileArchiveAndLeakageCanariesFailClosed",
    "testV23P03C48I01PreviewIsZeroWriteAndEveryCrashBoundaryConvergesToZeroOrComplete",
    "testV23P03C48R01RestoreCloneForkEraseAndReplayPreserveHistoricBytesAndInvalidateActiveCapability",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
FLAGS = {
    key: False
    for key in (
        "native",
        "hosted",
        "physical",
        "adoption",
        "acceptance",
        "release",
        "nativeAcceptance",
        "hostedAcceptance",
        "physicalAcceptance",
        "adoptionEvidence",
        "acceptanceCredit",
        "releaseReadiness",
        "phase10PollingDuringParallelExecution",
    )
}

PROTOCOL = {
    "releaseID": "portable-review-v1",
    "releaseDigestHex": "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
    "hmacAlgorithm": "HMAC-SHA256-CRYPTOKIT",
    "transcriptDomainASCII": "AssetRounds.ReviewCapabilityProof.V1",
    "transcriptDomainNULTerminated": True,
    "lengthPrefix": "UInt32BE",
    "digestEncoding": "RAW_32_BYTES",
    "requestIDEncoding": "CANONICAL_ASCII_NO_NUL",
    "constantTimeVerification": True,
    "proofCarriesCapability": False,
    "proofValidityIndependentOfApplicationEligibility": True,
    "proofValidButStaleCanBeHistoryOnly": True,
    "capabilityByteCount": 32,
}
REQUEST_MEMBERS = (
    "manifest.json",
    "review-request.json",
    "response-capability.bin",
    "report/report.pdf",
    "report/report.txt",
)
REQUEST_STATES = (
    "OPEN_UNEXPORTED",
    "EXPORTED_AWAITING_RESPONSE",
    "ACKNOWLEDGED_AWAITING_DECISION",
    "APPROVAL_RESPONSE_RECORDED",
    "CHANGES_RESPONSE_RECORDED",
    "SUPERSEDED",
    "CLOSED_WITHOUT_RESPONSE",
)
CAPABILITY_STATES = (
    "ISSUED_NOT_EXPORTED",
    "EXPORTED_ACCEPTING",
    "RESPONSE_PENDING_DECISION",
    "HISTORY_ONLY_TERMINAL",
    "HISTORY_ONLY_SUPERSEDED",
    "HISTORY_ONLY_CLONED_OR_FORKED",
    "UNAVAILABLE_CORRUPT_OR_MISSING",
    "ERASE_PENDING",
    "ERASED",
)
RESTORE_MODES = (
    "REPLACE_PRESERVES_OPEN_CAPABILITY",
    "CLONE_HISTORY_ONLY_INVALIDATES_ACTIVE_CAPABILITY",
    "FORK_HISTORY_ONLY_INVALIDATES_ACTIVE_CAPABILITY",
    "OLDER_RESTORE_REQUIRES_RECONCILIATION",
)
IMPORT_DISPOSITIONS = (
    "EXACT_PENDING_DECISION",
    "DUPLICATE_ALREADY_APPLIED",
    "STALE_LOCAL_REVISION",
    "SUPERSEDED_REQUEST",
    "UNKNOWN_REQUEST",
    "REQUEST_DIGEST_MISMATCH",
    "CAPABILITY_PROOF_INVALID",
    "UNSUPPORTED_PROTOCOL",
    "ITEM_MAPPING_FAILED",
    "POLICY_BLOCKED",
    "DIVERGENT_SAME_RESPONSE_ID",
)
IMPORT_DECISIONS = (
    "ACCEPT_AND_APPLY",
    "RECORD_AS_HISTORY_ONLY",
    "DISCARD_UNIMPORTED",
    "KEEP_QUARANTINED",
)
PROOF_MUTATION_CASES = (
    "DOMAIN_BIT_FLIP",
    "DOMAIN_NUL_REMOVED",
    "LENGTH_PREFIX_BIT_FLIP",
    "PROTOCOL_DIGEST_BIT_FLIP",
    "REQUEST_ID_BIT_FLIP",
    "REQUEST_ID_ALTERNATE_UUID_SPELLING",
    "REQUEST_MANIFEST_DIGEST_BIT_FLIP",
    "INNER_PACKAGE_DIGEST_BIT_FLIP",
    "RESPONSE_BODY_DIGEST_BIT_FLIP",
    "RAW_DIGEST_REPLACED_WITH_HEX_ASCII",
    "CAPABILITY_BIT_FLIP",
    "PROOF_BIT_FLIP",
    "TRUNCATED_TRANSCRIPT",
    "EXTENDED_TRANSCRIPT",
    "REORDERED_FIELDS",
)
HOSTILE_ARCHIVE_CASES = (
    "PATH_TRAVERSAL",
    "ABSOLUTE_PATH",
    "DUPLICATE_MEMBER",
    "CASE_COLLISION",
    "SYMLINK_MEMBER",
    "HARDLINK_MEMBER",
    "ZIP_BOMB",
    "OVERSIZE_MEMBER",
    "UNSUPPORTED_CONTENT",
    "ACTIVE_HTML",
    "ACTIVE_SCRIPT",
    "FORM",
    "MACRO",
    "UNKNOWN_PROTOCOL_VERSION",
    "WRONG_REQUEST",
    "WRONG_REPORT",
    "WRONG_ITEM",
    "FORWARDED_PACKET",
    "TWO_TERMINAL_RESPONSES",
    "LOW_STORAGE",
    "PROTECTED_DATA_LOCK",
    "CONCURRENT_LOCAL_AMENDMENT",
)
LEAKAGE_CANARIES = (
    "capability bytes",
    "response capability",
    "WorkspaceID",
    "ReplicaID",
    "filesystem path",
    "local sequence",
    "PartyID",
    "internal stable key",
    "diagnostic",
    "private note",
    "verified customer",
    "authenticated response",
    "secure response",
    "signed",
    "tamperproof",
    "delivered",
    "customer approved",
)
FORBIDDEN_TRUST_CLAIMS = (
    "Customer approved",
    "verified customer",
    "authenticated response",
    "secure response",
    "signed",
    "tamperproof",
    "delivered",
    "legal signature",
    "nonrepudiation",
)
INTERRUPTION_BOUNDARIES = (
    "REQUEST_RENDER",
    "REQUEST_SEAL",
    "REQUEST_SHARE",
    "RESPONSE_SEAL",
    "QUARANTINE_VALIDATION",
    "PREVIEW",
    "CONTENT_PROMOTION",
    "CANONICAL_EFFECT",
    "RECEIPT",
)
NAMESPACE_VALUES = ("REVIEW", "SERVICE_REQUEST")


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key:" + key)
        result[key] = value
    return result


def _json(root: Path, relative: str) -> dict[str, Any]:
    try:
        value = json.loads((root / relative).read_text(encoding="utf-8"), object_pairs_hook=_strict_pairs)
    except FileNotFoundError as exc:
        raise ValueError("JSON path absent:" + relative) from exc
    except json.JSONDecodeError as exc:
        raise ValueError("malformed JSON:" + relative) from exc
    if not isinstance(value, dict):
        raise ValueError("JSON root must be object:" + relative)
    return value


def _base_exists(root: Path, relative: str) -> bool:
    completed = subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{relative}"],
        capture_output=True,
        text=True,
    )
    return completed.returncode == 0


def _git_blob(root: Path, relative: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"],
        check=True,
        capture_output=True,
    )
    return completed.stdout


def _normalized_path(value: str) -> str:
    return value.replace("\\", "/")


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    paths: set[str] = set()
    status = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    for line in status:
        if len(line) < 4:
            continue
        value = line[3:]
        if " -> " in value:
            value = value.split(" -> ", 1)[1]
        paths.add(_normalized_path(value))
    for args in (("diff", "--name-only", BASE_HEAD), ("diff", "--cached", "--name-only", BASE_HEAD)):
        output = subprocess.run(
            ["git", "-C", str(root), *args], check=True, capture_output=True, text=True
        ).stdout
        paths.update(_normalized_path(line) for line in output.splitlines() if line)
    return tuple(sorted(paths))


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(label + " missing:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.S) is None]
    if missing:
        raise ValueError(label + " missing:" + " | ".join(missing))


def _require_order(text: str, first: str, second: str, label: str) -> None:
    left, right = text.find(first), text.find(second)
    if left < 0 or right < 0 or left >= right:
        raise ValueError(label + " order differs:" + first + " -> " + second)


def _swift_decl_block(text: str, declaration: str) -> str:
    start = text.find(declaration)
    if start < 0:
        raise ValueError("Swift declaration absent:" + declaration)
    opening = text.find("{", start)
    if opening < 0:
        raise ValueError("Swift declaration body absent:" + declaration)
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]
    raise ValueError("Swift declaration body unterminated:" + declaration)


def _hex32(value: str, label: str) -> bytes:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ValueError(label + " must be lowercase raw-32 hex")
    return bytes.fromhex(value)


def _expect_keys(value: dict[str, Any], keys: Iterable[str], label: str) -> None:
    expected = set(keys)
    if set(value) != expected:
        raise ValueError(label + " keys differ; missing=" + ",".join(sorted(expected - set(value))) + "; extra=" + ",".join(sorted(set(value) - expected)))


def _expect_exact(value: Any, expected: Any, label: str) -> None:
    if value != expected:
        raise ValueError(label + " differs")


def _closed_corpus(root: Path) -> dict[str, Any]:
    corpus = _json(root, IMPLEMENTATION_PATHS[-1])
    _expect_keys(
        corpus,
        (
            "schema",
            "schemaVersion",
            "cardID",
            "corpusID",
            "testOnly",
            "synthetic",
            "immutable",
            "containsCustomerData",
            "containsSecrets",
            "contracts",
            "protocol",
            "normativeVectors",
            "requestArchive",
            "responseArchive",
            "acquisition",
            "import",
            "proofMutationCases",
            "hostileArchiveCases",
            "leakageCanaries",
            "interruption",
            "lifecycle",
            "compatibility",
        ),
        "C48 closed corpus",
    )
    _expect_exact(corpus["schema"], "V22P03C48PortableReviewCorpusV1", "C48 corpus schema")
    _expect_exact(corpus["schemaVersion"], 1, "C48 corpus schema version")
    _expect_exact(corpus["cardID"], CARD, "C48 corpus card")
    _expect_exact(corpus["corpusID"], "v23-p03-c48-portable-review-v1", "C48 corpus identity")
    for key in ("testOnly", "synthetic", "immutable"):
        _expect_exact(corpus[key], True, "C48 corpus " + key)
    for key in ("containsCustomerData", "containsSecrets"):
        _expect_exact(corpus[key], False, "C48 corpus " + key)
    _expect_exact(corpus["contracts"], list(CONTRACT_NAMES), "C48 contract-name inventory")
    _assert_protocol(corpus["protocol"])
    _assert_normative_vectors(corpus["normativeVectors"])
    _assert_request_archive(corpus["requestArchive"])
    _assert_response_archive(corpus["responseArchive"])
    _assert_acquisition(corpus["acquisition"])
    _assert_import(corpus["import"])
    _expect_exact(corpus["proofMutationCases"], list(PROOF_MUTATION_CASES), "C48 proof mutation cases")
    _expect_exact(corpus["hostileArchiveCases"], list(HOSTILE_ARCHIVE_CASES), "C48 hostile archive cases")
    _expect_exact(corpus["leakageCanaries"], list(LEAKAGE_CANARIES), "C48 leakage canaries")
    _assert_interruption(corpus["interruption"])
    _assert_lifecycle(corpus["lifecycle"])
    _assert_compatibility(corpus["compatibility"])
    return corpus


def _assert_protocol(protocol: Any) -> None:
    if not isinstance(protocol, dict):
        raise ValueError("C48 protocol must be an object")
    _expect_keys(protocol, PROTOCOL, "C48 protocol")
    _expect_exact(protocol, PROTOCOL, "C48 protocol profile")
    _hex32(protocol["releaseDigestHex"], "C48 release digest")


def _frame(value: bytes) -> bytes:
    return struct.pack(">I", len(value)) + value


def _normative_transcript(vector: dict[str, Any]) -> bytes:
    domain = PROTOCOL["transcriptDomainASCII"].encode("ascii") + b"\x00"
    request_id = vector["requestPublicID"].encode("ascii")
    return b"".join(
        (
            domain,
            _frame(bytes.fromhex(PROTOCOL["releaseDigestHex"])),
            _frame(request_id),
            _frame(bytes.fromhex(vector["requestManifestDigestHex"])),
            _frame(bytes.fromhex(vector["innerRequestPackageDigestHex"])),
            _frame(bytes.fromhex(vector["canonicalResponseBodyDigestHex"])),
        )
    )


def _assert_normative_vectors(vectors: Any) -> None:
    if not isinstance(vectors, list) or len(vectors) != 1 or not isinstance(vectors[0], dict):
        raise ValueError("C48 normative vector inventory must contain exactly RV1-001")
    vector = vectors[0]
    _expect_keys(
        vector,
        (
            "vectorID",
            "capabilityHex",
            "requestPublicID",
            "requestManifestDigestHex",
            "innerRequestPackageDigestHex",
            "canonicalResponseBodyDigestHex",
            "transcriptByteCount",
            "transcriptHex",
            "transcriptSHA256",
            "expectedHMACHex",
        ),
        "C48 RV1-001 vector",
    )
    _expect_exact(vector["vectorID"], "RV1-001", "C48 vector ID")
    if not re.fullmatch(r"[0-9a-f]{64}", vector["capabilityHex"]):
        raise ValueError("C48 capability vector must be 32 raw bytes")
    if len(bytes.fromhex(vector["capabilityHex"])) != PROTOCOL["capabilityByteCount"]:
        raise ValueError("C48 capability vector byte count differs")
    if "capability" in vector.get("transcriptHex", "").lower():
        raise ValueError("C48 proof transcript must not carry capability material")
    for key in (
        "requestManifestDigestHex",
        "innerRequestPackageDigestHex",
        "canonicalResponseBodyDigestHex",
    ):
        _hex32(vector[key], "C48 vector " + key)
    if not re.fullmatch(r"[0-9a-f]{64}", vector["expectedHMACHex"]):
        raise ValueError("C48 vector HMAC must be raw 32-byte hex")
    transcript = _normative_transcript(vector)
    _expect_exact(vector["transcriptByteCount"], len(transcript), "C48 transcript length")
    _expect_exact(vector["transcriptHex"], transcript.hex(), "C48 transcript framing")
    _expect_exact(vector["transcriptSHA256"], sha256_bytes(transcript), "C48 transcript digest")
    expected_hmac = hashlib.sha256  # marker keeps the HMAC construction explicit below
    del expected_hmac
    import hmac

    computed = hmac.new(bytes.fromhex(vector["capabilityHex"]), transcript, hashlib.sha256).hexdigest()
    _expect_exact(vector["expectedHMACHex"], computed, "C48 vector HMAC")
    _expect_exact(vector["transcriptByteCount"], 236, "C48 normative transcript byte count")
    _expect_exact(vector["transcriptSHA256"], "5ab5c377885c524b13b17985b5782c34937ada353916c7861a7da97a23c0f0e6", "C48 normative transcript SHA-256")
    _expect_exact(vector["expectedHMACHex"], "fb0b14df9c1bdbf6f19222ab40954b07a5c847eca3c5095a3cc379ff6fa5501d", "C48 normative HMAC-SHA-256")


def _assert_request_archive(value: Any) -> None:
    if not isinstance(value, dict):
        raise ValueError("C48 request archive must be an object")
    _expect_keys(
        value,
        (
            "uti",
            "fileExtension",
            "members",
            "optionalMemberPrefix",
            "customerSafeReportRevision",
            "requestPublicID",
            "itemPublicIDs",
            "projectionStates",
            "excludedFromExchange",
        ),
        "C48 request archive",
    )
    _expect_exact(value["uti"], "com.assetrounds.review-request", "C48 request UTI")
    _expect_exact(value["fileExtension"], ".arreviewrequest", "C48 request extension")
    _expect_exact(value["members"], list(REQUEST_MEMBERS), "C48 request archive members")
    _expect_exact(value["optionalMemberPrefix"], "media/", "C48 optional media prefix")
    if not isinstance(value["customerSafeReportRevision"], int) or value["customerSafeReportRevision"] <= 0:
        raise ValueError("C48 customer-safe report revision must be positive")
    request_id = "review-request-00000000-0000-0000-0000-000000000001"
    _expect_exact(value["requestPublicID"], request_id, "C48 request public ID")
    _expect_exact(
        value["itemPublicIDs"],
        [
            "review-item-00000000-0000-0000-0000-000000000001",
            "review-item-00000000-0000-0000-0000-000000000002",
        ],
        "C48 item public IDs",
    )
    _expect_exact(value["projectionStates"], list(REQUEST_STATES), "C48 request projection states")
    _expect_exact(
        value["excludedFromExchange"],
        [
            "WorkspaceID",
            "ReplicaID",
            "filesystem identity",
            "local sequence",
            "PartyID",
            "internal stable keys",
            "raw originals",
            "internal notes",
            "contacts",
            "diagnostics",
            "local paths",
            "scripts",
            "forms",
            "macros",
        ],
        "C48 request exclusion inventory",
    )


def _assert_response_archive(value: Any) -> None:
    if not isinstance(value, dict):
        raise ValueError("C48 response archive must be an object")
    _expect_keys(
        value,
        (
            "uti",
            "fileExtension",
            "canonicalDocumentCount",
            "textOnly",
            "attachmentsAllowed",
            "executableContentAllowed",
            "requestPublicID",
            "responsePublicID",
            "responseItemPublicIDs",
            "authorAssertion",
            "dispositions",
        ),
        "C48 response archive",
    )
    _expect_exact(value["uti"], "com.assetrounds.review-response", "C48 response UTI")
    _expect_exact(value["fileExtension"], ".arreviewresponse", "C48 response extension")
    _expect_exact(value["canonicalDocumentCount"], 1, "C48 response canonical document count")
    _expect_exact(value["textOnly"], True, "C48 response text-only boundary")
    _expect_exact(value["attachmentsAllowed"], False, "C48 response attachments")
    _expect_exact(value["executableContentAllowed"], False, "C48 response executable content")
    _expect_exact(value["requestPublicID"], "review-request-00000000-0000-0000-0000-000000000001", "C48 response request ID")
    _expect_exact(value["responsePublicID"], "review-response-00000000-0000-0000-0000-000000000002", "C48 response ID")
    _expect_exact(
        value["responseItemPublicIDs"],
        [
            "review-item-00000000-0000-0000-0000-000000000001",
            "review-item-00000000-0000-0000-0000-000000000002",
        ],
        "C48 response item IDs",
    )
    author = value["authorAssertion"]
    _expect_keys(author, ("displayName", "organization", "source", "identityVerified", "responseTimeInformational", "disclosureRelease"), "C48 author assertion")
    _expect_exact(author, {"displayName": "External reviewer", "organization": "Example organization", "source": "SELF_ENTERED_IN_RESPONDER", "identityVerified": False, "responseTimeInformational": True, "disclosureRelease": "portable-review-disclosure-v1"}, "C48 author assertion")
    dispositions = value["dispositions"]
    expected = [
        {"kind": "ACKNOWLEDGED", "terminal": False, "requiresChangeItems": False, "projectionAfter": "ACKNOWLEDGED_AWAITING_DECISION"},
        {"kind": "APPROVED", "terminal": True, "requiresChangeItems": False, "forbidsChangeItems": True, "projectionAfter": "APPROVAL_RESPONSE_RECORDED"},
        {"kind": "CHANGES_REQUESTED", "terminal": True, "requiresChangeItems": True, "projectionAfter": "CHANGES_RESPONSE_RECORDED"},
    ]
    _expect_exact(dispositions, expected, "C48 response dispositions")


def _assert_acquisition(value: Any) -> None:
    _expect_keys(value, ("kinds", "originRecordedElsewhereSource", "requiresExistingExportedRequest", "fabricatesCapabilityProof", "fabricatesResponseFile", "trustClaims", "forbiddenTrustClaims"), "C48 acquisition")
    _expect_exact(value["kinds"], ["PORTABLE_FILE", "ORIGIN_RECORDED_ELSEWHERE"], "C48 acquisition kinds")
    _expect_exact(value["originRecordedElsewhereSource"], "ORIGIN_USER_ASSERTION_UNVERIFIED", "C48 origin source")
    _expect_exact(value["requiresExistingExportedRequest"], True, "C48 existing request requirement")
    _expect_exact(value["fabricatesCapabilityProof"], False, "C48 proof fabrication")
    _expect_exact(value["fabricatesResponseFile"], False, "C48 response fabrication")
    _expect_exact(value["trustClaims"], ["Response recorded", "Not verified by AssetRounds", "Response proof verified for this request"], "C48 allowed trust claims")
    _expect_exact(value["forbiddenTrustClaims"], list(FORBIDDEN_TRUST_CLAIMS), "C48 forbidden trust claims")


def _assert_import(value: Any) -> None:
    _expect_keys(value, ("dispositions", "decisions", "preview", "acceptAndApply", "staleResponseDisposition", "sameResponseIDExactReplayIdempotent", "divergentSameResponseIDQuarantined", "noOverwriteOnDivergence", "conflictsPreserved"), "C48 import")
    _expect_exact(value["dispositions"], list(IMPORT_DISPOSITIONS), "C48 import dispositions")
    _expect_exact(value["decisions"], list(IMPORT_DECISIONS), "C48 import decisions")
    preview = value["preview"]
    _expect_keys(preview, ("zeroWrite", "repeatable", "canonicalWriteCount", "receiptCount", "projectionChanges", "quarantineIsCanonical"), "C48 import preview")
    _expect_exact(preview, {"zeroWrite": True, "repeatable": True, "canonicalWriteCount": 0, "receiptCount": 0, "projectionChanges": 0, "quarantineIsCanonical": False}, "C48 import preview")
    apply = value["acceptAndApply"]
    _expect_keys(apply, ("rechecksCurrentRevision", "promotesExactResponseBytes", "recordsExternalResponse", "recordsDecisionReceipt", "invokesExistingReviewTruth", "recordsSelfAssertedActorSnapshot", "updatesProjectionAtomically", "automaticFinalization"), "C48 accept-and-apply")
    _expect_exact(apply, {"rechecksCurrentRevision": True, "promotesExactResponseBytes": True, "recordsExternalResponse": True, "recordsDecisionReceipt": True, "invokesExistingReviewTruth": True, "recordsSelfAssertedActorSnapshot": True, "updatesProjectionAtomically": True, "automaticFinalization": False}, "C48 accept-and-apply")
    _expect_exact(value["staleResponseDisposition"], "RECORD_AS_HISTORY_ONLY", "C48 stale response disposition")
    for key in ("sameResponseIDExactReplayIdempotent", "divergentSameResponseIDQuarantined", "noOverwriteOnDivergence", "conflictsPreserved"):
        _expect_exact(value[key], True, "C48 import " + key)


def _assert_interruption(value: Any) -> None:
    _expect_keys(value, ("boundaries", "disposition", "retryDisposition"), "C48 interruption")
    _expect_exact(value["boundaries"], list(INTERRUPTION_BOUNDARIES), "C48 interruption boundaries")
    _expect_exact(value["disposition"], "ZERO_OR_COMPLETE", "C48 interruption disposition")
    _expect_exact(value["retryDisposition"], "EXACT_EFFECT_AND_RECEIPT_OR_NO_EFFECT", "C48 interruption retry")


def _assert_lifecycle(value: Any) -> None:
    _expect_keys(value, ("capabilityStates", "restoreModes", "historicReadExport", "exactBytesImmutableAfterAcceptance", "eraseRemoves", "eraseCannotRecallSharedFiles", "namespaces", "namespaceQuotasIndependent", "searchIncludesSecrets", "diagnosticsIncludeSecrets", "accessibilitySpeechIncludesSecrets"), "C48 lifecycle")
    _expect_exact(value["capabilityStates"], list(CAPABILITY_STATES), "C48 capability lifecycle")
    _expect_exact(value["restoreModes"], list(RESTORE_MODES), "C48 restore lifecycle")
    _expect_exact(value["historicReadExport"], True, "C48 historic read/export")
    _expect_exact(value["exactBytesImmutableAfterAcceptance"], True, "C48 immutable accepted bytes")
    _expect_exact(value["eraseRemoves"], ["local mappings", "capability secrets", "quarantine scratch", "exchange sessions"], "C48 erase inventory")
    _expect_exact(value["eraseCannotRecallSharedFiles"], True, "C48 escaped-file boundary")
    _expect_exact(value["namespaces"], list(NAMESPACE_VALUES), "C48 namespace inventory")
    _expect_exact(value["namespaceQuotasIndependent"], True, "C48 namespace quota isolation")
    for key in ("searchIncludesSecrets", "diagnosticsIncludeSecrets", "accessibilitySpeechIncludesSecrets"):
        _expect_exact(value[key], False, "C48 secret surface " + key)


def _assert_compatibility(value: Any) -> None:
    _expect_keys(value, ("releasedV1BytesPreserved", "historicReaderRequired", "historicBytesMigratedInPlace", "successorRequestGetsNewID", "successorRequestGetsNewCapability", "successorRequestGetsNewDigest"), "C48 compatibility")
    _expect_exact(value, {"releasedV1BytesPreserved": True, "historicReaderRequired": True, "historicBytesMigratedInPlace": False, "successorRequestGetsNewID": True, "successorRequestGetsNewCapability": True, "successorRequestGetsNewDigest": True}, "C48 compatibility")


def _sealed(body: dict[str, Any], field: str = "artifactDigest") -> dict[str, Any]:
    result = dict(body)
    result[field] = sha256_bytes(pretty(body))
    return result


def _row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    path = root / relative
    if relative in rendered:
        raw, state = rendered[relative], "GENERATED"
    elif path.is_file():
        raw, state = path.read_bytes(), "WORKTREE"
    elif relative in EXISTING_PATHS:
        raw, state = _git_blob(root, relative), "BASE_HEAD"
    else:
        raw, state = b"", "MISSING_NEW_PATH"
    return {"path": relative, "state": state, "bytes": len(raw), "sha256": sha256_bytes(raw)}


def _assert_contract_sources(root: Path) -> None:
    contracts = _text(root, IMPLEMENTATION_PATHS[0])
    persistence = _text(root, IMPLEMENTATION_PATHS[1])
    coordinator = _text(root, IMPLEMENTATION_PATHS[2])
    store = _text(root, IMPLEMENTATION_PATHS[3])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    joined = "\n".join((contracts, persistence, coordinator, store, tests))
    _require_tokens(joined, CONTRACT_NAMES, "C48 typed contract inventory")
    _require_tokens(tests, TEST_METHODS, "C48 deterministic test selectors")
    _require_tokens(
        contracts,
        (
            "HMAC<SHA256>", "SymmetricKey", "constantTimeEqual", "unsupportedProtocol",
            "ORIGIN_RECORDED_ELSEWHERE", "proofValidity", "applicationEligibility",
            "canonicalResponseBodyDigest", "requestManifestDigest", "innerRequestPackageDigest",
        ),
        "C48 proof and acquisition contracts",
    )
    _require_patterns(
        contracts,
        (
            r"AssetRounds\.ReviewCapabilityProof\.V1",
            r"capabilityByteCount\s*=\s*32",
            r"UInt32\(value\.count\)\.bigEndian",
            r"case\s+originRecordedElsewhere",
            r"case\s+unsupportedProtocol",
        ),
        "C48 exact protocol framing",
    )
    _require_tokens(
        persistence,
        (
            "sessionStoreIsNonpersistent", "canonicalAcceptedResponseOwner", "C14",
            "rawCapabilityIsNeverAWorkspaceRow", "quarantineIsExcludedFromBackup",
            "cloneOrForkInvalidatesActiveCapabilities", "eraseCannotRecallEscapedFiles",
            "PortableExchangeSessionEnvelopeV1", "PortableExchangeSessionEnvelopeV2",
            "PortableExchangeBackupSnapshotV2", "PortableExchangeRestoreReceiptV2",
            "PortableExchangeCloneForkReceiptV2", "PortableExchangeEraseReceiptV2",
        ),
        "C48 lifecycle persistence boundary",
    )
    if re.search(r"@Model\s+(?:final\s+)?class\s+PortableExchange", persistence):
        raise ValueError("C48 exchange session gained a SwiftData row")
    _require_tokens(
        coordinator,
        (
            "prepareAcceptAndApply", "finalizeAcceptAndApply", "recoverAcceptAndApply",
            "PortableReviewC14ReconciliationV1", "commitPortableReview",
            "portableReviewReceipt", "finalizeSessionOnly",
        ),
        "C48 two-plane C14 reconciliation",
    )
    _require_patterns(
        coordinator,
        (r"sessions\.prepareAcceptAndApply.*?writer\.commitPortableReview.*?sessions\.finalizeAcceptAndApply",),
        "C48 session stage then C14 then session finalization",
    )
    _require_tokens(
        store,
        (
            "snapshotForBackup", "replaceRestore", "markClonedOrForked", "eraseAll",
            "recoverPendingJournal", "prepareAcceptAndApply", "finalizeAcceptAndApply",
            "recoverAcceptAndApply", "removeCapability", "writeAtomically",
            "quarantine", "previewImport", "applyImport", "recordOriginResponse",
        ),
        "C48 session lifecycle and recovery store",
    )
    _require_patterns(
        store,
        (
            r"case\s+\.clone\s*,\s*\.fork|cloneOrFork",
            r"capabilityState\s*=\s*\.historyOnlyClonedOrForked",
            r"protectedCapability\s*=\s*nil",
            r"pendingMutationID.*?pendingEffectSHA256.*?pendingImportReceiptSHA256",
        ),
        "C48 clone/fork and two-plane recovery",
    )
    _require_tokens(
        tests,
        (
            "RV1-001", "rv1001TranscriptSHA256Hex", "rv1001HMACSHA256Hex",
            "snapshotForBackup", "replaceRestore", "markClonedOrForked", ".erase(",
            "searchIncludesSecrets", "diagnosticsIncludeSecrets",
            "accessibilitySpeechIncludesSecrets", "unsupportedProtocol",
        ),
        "C48 golden hostile recovery tests",
    )


def _assert_integration_sources(root: Path) -> None:
    checks = {
        "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift": (
            "PortableExchangeBackupSnapshotV2", "portableExchange", "protectedCapabilityArtifacts",
        ),
        "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift": (
            "PortableExchangeBackupSnapshotV2", "portableExchangeSnapshot", ".clone", ".fork",
        ),
        "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift": (
            "portableExchange", "erase",
        ),
        "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift": (
            "C48PortableReviewLocalSearchBoundaryV1", "capabilityBytesIndexed = false",
        ),
        "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift": (
            "C48PortableReviewDiagnosticPrivacyBoundaryV1", "capabilityBytesEmitted = false",
        ),
        "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift": (
            "C48PortableReviewReportRenderBoundaryV1", "capabilityBytesRendered = false",
        ),
        "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift": (
            "C48PortableReviewReleasedDataCompatibilityBoundaryV1", "historic",
        ),
        "FieldEvidenceApp/Domain/Models/ReviewAndCorrectiveActionPersistenceModelsV1.swift": (
            "C48PortableReviewC14PersistenceBoundaryV1", "createsPortableReviewSwiftDataRow = false",
        ),
        "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift": (
            "portableExchangeSessionFile", "PortableExchangeProtectedFilePolicyV2", ".complete",
        ),
    }
    for path, tokens in checks.items():
        _require_tokens(_text(root, path), tokens, "C48 integration " + path)
    plist = _text(root, "FieldEvidenceApp/Info.plist")
    _require_tokens(plist, ("com.assetrounds.review-request", "com.assetrounds.review-response"), "C48 document types")


def assert_source_regressions(root: Path) -> None:
    _closed_corpus(root)
    _assert_contract_sources(root)
    _assert_integration_sources(root)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (125, 14, 139):
        raise ValueError("C48 fence must be exactly 139=125+14")
    if len(set(PATH_FENCE)) != 139:
        raise ValueError("C48 fence contains duplicates")
    if tuple(PATH_FENCE[-8:]) != (*SCRIPT_PATHS, *GENERATED_PATHS):
        raise ValueError("C48 tooling ownership rows differ")
    tree = subprocess.run(
        ["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C48 base tree differs")
    for path in EXISTING_PATHS:
        if not _base_exists(root, path):
            raise ValueError("C48 existing path absent at base:" + path)
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError("C48 new path existed at base:" + path)
    if AUTHORIZED_OVERLAP_COUNT != 0 or UNAUTHORIZED_OVERLAP_COUNT != 0:
        raise ValueError("C48 overlap authority differs")
    if S10_RESERVATION_OVERLAP_COUNT != 0 or S10_RESERVED_PATH_COUNT != 86:
        raise ValueError("C48 S10 reservation proof differs")
    if any(FLAGS.values()):
        raise ValueError("C48 provisional status flags differ")


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "title": TITLE, "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION,
        "authorityCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "allowedPathCount": 139, "existingPathCount": 125, "newPathCount": 14,
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0, "s10ReservedPathCount": 86,
        "directPrerequisiteCards": ["V23-P03-C24"],
        "requiresAcceptedS10_6Reconciliation": True,
    }


def schema_document(root: Path) -> dict[str, Any]:
    corpus = _closed_corpus(root)
    properties = {key: {"const": value} for key, value in corpus.items()}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/portable-review.schema.json",
        "title": "V23 P03 C48 Portable Review Corpus V1",
        "type": "object", "additionalProperties": False,
        "properties": properties, "required": list(corpus),
    }


def contract_document(root: Path) -> dict[str, Any]:
    corpus = _closed_corpus(root)
    semantics = {
        "contractNames": list(CONTRACT_NAMES), "protocol": corpus["protocol"],
        "normativeVector": corpus["normativeVectors"][0],
        "requestArchive": corpus["requestArchive"], "responseArchive": corpus["responseArchive"],
        "acquisition": corpus["acquisition"], "import": corpus["import"],
        "interruption": corpus["interruption"], "lifecycle": corpus["lifecycle"],
        "compatibility": corpus["compatibility"],
        "soleSessionOwner": "PortableExchangeSessionStoreV2",
        "canonicalAcceptedResponseOwner": "EXISTING_C14_INSPECTION_REVIEW_CANONICAL_WRITER_AND_RECEIPTS",
        "twoPlaneRecoveryIsZeroOrComplete": True,
        "archiveBackupRestoreCloneForkEraseSearchReportExcludeSecrets": True,
        "unsupportedClaimsFailClosed": True,
        "noSecondArchiveParserWriterPersistenceStoreNetworkAccountLegalDeliveryOrUIClaim": True,
    }
    return _sealed({
        "artifact": "V23P03C48PortableReviewContractV1", "schemaVersion": 1,
        "cardID": CARD, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "authority": authority(), "requiredSemantics": semantics,
        "evidenceIDs": list(EVIDENCE_IDS), "testSelectors": list(TEST_METHODS),
        "statusFlags": FLAGS, "requiresAcceptedS10_6Reconciliation": True,
    })


def evidence_document(root: Path, contract: dict[str, Any]) -> dict[str, Any]:
    rows = [_row(root, path, {}) for path in IMPLEMENTATION_PATHS]
    return _sealed({
        "artifact": "V23P03C48PortableReviewEvidenceReceiptV1", "schemaVersion": 1,
        "cardID": CARD, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "authority": authority(), "sourceArtifacts": rows,
        "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]),
        "deterministicEvidenceIDs": list(EVIDENCE_IDS), "testSelectors": list(TEST_METHODS),
        "nativeEvidenceState": "PENDING_NOT_ACCEPTING",
        "physicalEvidenceState": "REQUIRED_PENDING_OWNER",
        "adoptionState": "PENDING_NOT_ACCEPTING", "acceptanceState": "PENDING_NOT_ACCEPTING",
        "releaseState": "PENDING_NOT_ACCEPTING", "statusFlags": FLAGS,
        "requiresAcceptedS10_6Reconciliation": True,
    })


def brand_document(contract: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "artifact": "V23P03C48BrandImpactManifestV1", "schemaVersion": 1,
        "cardID": CARD, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "brandSurfaceDelta": True, "uiSurfaceDelta": False, "publicClaimDelta": False,
        "impact": "PORTABLE_REVIEW_FILES_REMAIN_CUSTOMER_SAFE_CLEAR_TEXT_WITH_EXPLICIT_UNVERIFIED_OR_PROOF_VERIFIED_WORDING",
        "forbiddenTrustClaims": list(FORBIDDEN_TRUST_CLAIMS),
        "s10FenceOverlapPaths": [], "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "contractDigest": contract["artifactDigest"], "statusFlags": FLAGS,
        "requiresAcceptedS10_6Reconciliation": True,
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    assert_source_regressions(root)
    schema = pretty(schema_document(root))
    contract = contract_document(root)
    evidence = evidence_document(root, contract)
    rendered = {
        SCHEMA_PATH: schema, CONTRACT_PATH: pretty(contract),
        EVIDENCE_PATH: pretty(evidence), BRAND_PATH: pretty(brand_document(contract)),
    }
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(_sealed({
        "artifact": "V23P03C48ToolingManifestV1", "schemaVersion": 1,
        "cardID": CARD, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "authority": authority(), "pathFence": list(PATH_FENCE), "pathFenceDigest": FENCE_DIGEST,
        "pathFenceCount": 139, "existingPathCount": 125, "newPathCount": 14,
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "artifacts": rows, "artifactSetDigest": sha256_value(rows),
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0, "s10ReservedPathCount": 86,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "evidenceDigest": evidence["artifactDigest"], "testSelectors": list(TEST_METHODS),
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
        "requiresAcceptedS10_6Reconciliation": True,
    }))
    return rendered
