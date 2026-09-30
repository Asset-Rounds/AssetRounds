#!/usr/bin/env python3
"""Deterministic nonpersistent incumbent-file-adapter tooling for V23-P03-C50."""
from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

CARD = "V23-P03-C50"
TITLE = "Provider-neutral versioned file-adapter port, closed profile registry, mapping manifest, and quarantine"
REGISTER_ORDINAL = 80
BASE_HEAD = "bdb4b61e2e148fb10f35f4536ac65119697b1133"
BASE_TREE = "9f81756d95e9d397f3dc56fd13fd544850645ac1"
COORDINATION_HEAD = "de38be916f88f5999e961a74d1daf9aa9502f439"
COORDINATION_TREE = "801ea5867896da24c1359e85d03c51bcafdfaf41"
COORDINATION_CAS_SEQUENCE = 339
CONTEXT_DIGEST = "04061e30aaf4968b271b9657af03e71152ae446bdf84f24730d06e1b8cf129e1"
FENCE_DIGEST = "43add5f59574b0686a74dd09f9379e6dc4b07cb93ad6578d8e0910d6947e6800"
PREREQUISITE_DIGEST = "7eff4ff26f7c4332e7399e81a514877157137353f786743a21cccc54d7431da1"
HYDRATION_TRANSITION_DIGEST = "d4f5d40659734ebce4339d70009ff6414904dafa0d0c2d11b43b7fdb760a5cdf"
COORDINATION_LEDGER_DIGEST = "cba53f0dda6cc72621f889718861e2da9d318a0d1fd8f6dc9782d61aed3407e8"
COORDINATION_PROJECTION_DIGEST = "066d98d840e5a333a28698b38f240ebdf668f03d61d0b445b12a5babaf17592c"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

DOSSIER_SHA256 = "c781c26ba72bb3cd72098d77f6f121c34f3893d19568b7d954398f0f1473feef"
DOSSIER_BYTES = 7436
INHERITED_SHA256 = "04ddfcf4166f40c2965132d9de302d90ea2c9eb0a4765073f225f9809d2ffb88"
INHERITED_BYTES = 5709
REGISTER_ROW_SHA256 = "6aefbc2025c54881b633cf0aea54f54ba240e4ab38f866d2ed5b27c0976d5736"
REGISTER_ROW_BYTES = 292
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217

SCHEMA_PATH = "Scripts/v23/incumbent-file-adapter.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C50IncumbentFileAdapterContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C50IncumbentFileAdapterEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C50BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C50-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c50_contracts.py",
    "Scripts/v23/generate_p03_c50_contracts.py",
    "Scripts/v23/verify_p03_c50_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Integrations/FileAdapters/IncumbentFileAdapterContractsV1.swift",
    "FieldEvidenceApp/Domain/Integrations/FileAdapters/IncumbentFileAdapterProfileContractsV1.swift",
    "FieldEvidenceApp/Application/Integrations/IncumbentFileExchangeCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/FileExchange/IncumbentFileExchangeLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_57IncumbentFileAdapterTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/IncumbentExchange/V22P03C50IncumbentFileAdapterCorpusV1.json",
)

_C49_PATH = Path(__file__).with_name("p03_c49_contracts.py")
_C49_SHA256 = "cda5bf8cd344cf7c95c55fa4ea30629948f0a7e43278b9968a0ea7304014b246"


def _c49_existing() -> tuple[str, ...]:
    if not _C49_PATH.is_file() or hashlib.sha256(_C49_PATH.read_bytes()).hexdigest() != _C49_SHA256:
        raise ValueError("sealed C49 tooling inventory differs")
    spec = importlib.util.spec_from_file_location("_sealed_p03_c49_contracts", _C49_PATH)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load sealed C49 tooling inventory")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return tuple(module.EXISTING_PATHS) + tuple(module.IMPLEMENTATION_PATHS)


EXISTING_PATHS = _c49_existing()
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
FLAGS = {name: False for name in (
    "native", "hosted", "physical", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalAcceptance", "adoptionEvidence",
    "acceptanceCredit", "releaseReadiness", "phase10PollingDuringParallelExecution",
)}
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
DISALLOWED_SOURCE_PATTERNS = (
    # C50 is an offline, provider-neutral file boundary.  Keep the list at
    # symbols rather than prose so its own negative-policy comments remain legal.
    r"\b(?:URLSession|URLRequest|URLComponents|NWConnection|WebSocket|HTTPClient|Alamofire)\b",
    r"\b(?:Keychain\w*|SecurityScopedBookmark\w*|URLCredential\w*|OAuth\w*|Credential\w*|TokenStore\w*|SecItem\w*|ASAuthorization\w*)\b",
    r"\b(?:NSFileProvider\w*|FileProvider\w*|UIDocumentPicker\w*|DocumentProvider\w*|CloudKit\w*|CKContainer\w*)\b",
    r"\b(?:WorkspaceWriterV1|ModelContainer|ModelContext)\b", r"@Model\b",
    r"\b(?:Incumbent\w*(?:Durable|Persistent|Stored)Session\w*|C50(?:Durable|Persistent|Stored)Session\w*)\b",
)
PRIVACY_EXCLUSIONS = ("contact", "email", "note", "gps", "media", "evidence", "qualification", "direct cost")


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"


def pretty(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


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
    value = json.loads(_text(root, relative), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + relative)
    return value


def _base_exists(root: Path, relative: str) -> bool:
    return subprocess.run(["git", "cat-file", "-e", f"{BASE_HEAD}:{relative}"], cwd=root,
                          capture_output=True).returncode == 0


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed = set()
    command = ["git", "diff", "--name-only", BASE_HEAD, "--"]
    for raw in subprocess.run(command, cwd=root, check=True, capture_output=True, text=True).stdout.splitlines():
        if raw.strip():
            changed.add(raw.strip().replace("\\", "/"))
    for raw in subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=root,
                              check=True, capture_output=True, text=True).stdout.splitlines():
        if raw.strip():
            changed.add(raw.strip().replace("\\", "/"))
    return tuple(sorted(changed))


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"{label} missing tokens:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.I | re.S) is None]
    if missing:
        raise ValueError(f"{label} missing patterns:" + ",".join(missing))


def _swift_function_bodies(text: str, name: str) -> tuple[str, ...]:
    """Return named Swift methods without pretending to fully parse Swift."""
    matches = list(re.finditer(rf"(?m)^\s*func\s+{re.escape(name)}\s*\(", text))
    if not matches:
        raise ValueError("C50 required function absent:" + name)
    all_functions = list(re.finditer(r"(?m)^\s*func\s+\w+\s*\(", text))
    bodies: list[str] = []
    for match in matches:
        next_start = next((candidate.start() for candidate in all_functions
                           if candidate.start() > match.start()), len(text))
        bodies.append(text[match.start():next_start])
    return tuple(bodies)


def _require_function_tokens(text: str, name: str, tokens: Iterable[str], label: str) -> None:
    expected = tuple(tokens)
    bodies = _swift_function_bodies(text, name)
    if any(all(token in body for token in expected) for body in bodies):
        return
    missing = [token for token in expected if not any(token in body for body in bodies)]
    detail = ",".join(missing) if missing else "tokens split across overloads"
    raise ValueError(f"{label}:{name} missing:" + detail)


def _assert_privacy_authority_binding(profile: str, adapter: str, tests: str) -> None:
    """Require the C20-derived approval to be bound, value-exact, and frontier-exact."""
    _require_tokens(profile, (
        "canonicalProjectionValues", "canonicalProjectionSHA256", "workspaceFrontier",
        "bindingSHA256", "authorityBinding = .unbound", "requireAuthoritativelyBound",
    ), "C50 privacy authority binding")
    _require_function_tokens(profile, "validate", (
        "workspaceFrontier", "canonicalProjectionValues", "canonicalProjectionSHA256",
        "requireAuthoritativelyBound", "privacyApprovalRequired",
    ), "C50 privacy authority validation")
    _require_function_tokens(profile, "revalidated", (
        "workspaceFrontier", "canonicalProjectionValues", "canonicalProjectionSHA256",
        "guard self == authoritative", "privacyApprovalRequired",
    ), "C50 privacy authority revalidation")
    _require_tokens(adapter, (
        "expectedProjection: IncumbentAdapterProjectionPayloadV1",
        "expectedCanonicalProjectionValues", "expectedCanonicalProjectionSHA256",
        "expectedWorkspaceFrontier", "expectedWorkspaceRevision",
        "expectedAllowedCanonicalFields", "revalidatedPrivacyAuthority",
    ), "C50 scope privacy authority")
    _require_tokens(tests, (
        "structurallyValidUnboundAdapterApproval", "JSONDecoder().decode",
        "canonicalProjectionValues", "canonicalProjectionSHA256", "workspaceFrontier",
        "wrongWorkspaceFrontier", "XCTAssertThrowsError", ".privacyApprovalRequired",
    ), "C50 privacy authority adversarial tests")


def _assert_export_manifest_lifecycle(adapter: str, coordinator: str, lifecycle: str, tests: str) -> None:
    """Require the coordinator manifest to remain bound through every export lifecycle stage."""
    _require_tokens(adapter, (
        "IncumbentFileExportManifestV1", "releaseSHA256", "outputSHA256", "manifestSHA256",
        "func validate(scope: IncumbentExchangeScopeV1, release: IncumbentFileProfileReleaseV1",
    ), "C50 export manifest contract")
    _require_tokens(coordinator, (
        "func render", "IncumbentFileExportManifestV1(", "scope: scope, release: release, output: first",
    ), "C50 coordinator export manifest")
    _require_tokens(lifecycle, (
        "IncumbentFileExportManifestV1", "exportManifestSHA256", "manifest.manifestSHA256",
        "manifest.outputSHA256", "manifest.releaseSHA256", "manifest.validate(",
    ), "C50 export lifecycle manifest binding")
    # Acquisition validates the complete artifact and transfers its digest into
    # the lease initializer.  It must not duplicate that digest as a loose local.
    _require_function_tokens(lifecycle, "acquireExport", (
        "manifest: IncumbentFileExportManifestV1", "validateExportArtifact(",
        "IncumbentFileExchangeScratchLeaseV1(", "manifest: manifest",
    ), "C50 export lifecycle acquire manifest continuity")
    acquire_bodies = _swift_function_bodies(lifecycle, "acquireExport")
    if not any(re.search(
        r"validateExportArtifact\s*\([\s\S]*?IncumbentFileExchangeScratchLeaseV1\s*\([\s\S]*?manifest\s*:\s*manifest",
        body,
    ) for body in acquire_bodies):
        raise ValueError("C50 export acquire must validate then bind manifest into lease")
    for function in ("stageExport", "finishExport"):
        _require_function_tokens(lifecycle, function, (
            "manifest: IncumbentFileExportManifestV1", "exportManifestSHA256",
        ), "C50 export lifecycle manifest continuity")
    _require_function_tokens(lifecycle, "stageExport", (
        "manifest.outputSHA256", "binding.inputSHA256",
    ), "C50 export lifecycle stage validation")
    _require_function_tokens(lifecycle, "finishExport", (
        "manifest.releaseSHA256", "binding.releaseSHA256",
    ), "C50 export lifecycle finish validation")
    _require_tokens(tests, (
        "IncumbentFileExportManifestV1", "acquireExport", "stageExport", "finishExport",
        "manifest:", "manifestSHA256", "outputSHA256", "releaseSHA256",
        "XCTAssertThrowsError", "wrongExportManifest",
    ), "C50 export lifecycle adversarial tests")


def _assert_privacy_bound_export_entrypoint(coordinator: str, tests: str) -> None:
    """Keep arbitrary adapter rows behind the coordinator's privacy-bound projection entrypoint."""
    _require_patterns(coordinator, (
        r"(?m)^\s*private\s+func\s+render\s*\(\s*rows:",
        r"(?m)^\s*func\s+render\s*\(\s*projections:",
    ), "C50 coordinator export entrypoint visibility")
    _require_function_tokens(coordinator, "render", (
        "projections:", "scope:", "try scope.validate(release: release)",
        "IncumbentFileRowV1(", "try render(rows: rows, scope: scope, at: date)",
    ), "C50 privacy-bound projection export entrypoint")
    coordinator_raw_render = r"\b(?:coordinator|exportCoordinator|disabledCoordinator|[A-Za-z_]\w*Coordinator)\.render\s*\(\s*rows\s*:"
    if re.search(coordinator_raw_render, tests) is not None:
        raise ValueError("C50 tests expose coordinator raw-row export path")
    _require_patterns(tests, (
        r"XCTAssertTrue\s*\(\s*rowValueBypassRejected\b[\s\S]{0,256}?XCTAssertThrowsError\s*\(\s*try\s+\w+\.render\s*\(\s*projections\s*:",
    ), "C50 raw-row export bypass adversarial test")


def _assert_binding_free_cold_start(lifecycle: str, tests: str) -> None:
    """Cold-start recovery may clean scratch aggregate state, never rehydrate a lease binding."""
    _require_function_tokens(lifecycle, "recoverColdStart", (
        "coordinator: IncumbentFileExchangeCoordinatorV1",
        "plan: IncumbentExchangeRecoveryPlanV1",
        "observedSourceSHA256: String",
        "canonicalReceipt: MutationReceiptV1?",
        "scratch.recoverScratchLeases()",
        "coordinator.recover(",
        "ScratchDataLeaseRecoverySummaryV1",
    ), "C50 binding-free cold-start recovery")
    for body in _swift_function_bodies(lifecycle, "recoverColdStart"):
        if "IncumbentFileExchangeScratchLeaseV1" in body or "IncumbentFileExchangeScratchLifecycleReceiptV1" in body:
            raise ValueError("C50 cold-start recovery must not accept or return a lease/lifecycle receipt")
        cleanup_then_reconcile = (
            "scratch.recoverScratchLeases()", "plan.validate()",
            "canonicalReceipt.map", "coordinator.recover(",
        )
        positions = [body.find(token) for token in cleanup_then_reconcile]
        if any(position < 0 for position in positions) or positions != sorted(positions):
            raise ValueError("C50 cold-start must clean scratch before plan/receipt reconciliation")
    _require_patterns(tests, (
        r"coldStartWithoutBinding[\s\S]{0,4096}?relaunchedLifecycle\.recoverColdStart\s*\((?:(?!coldBinding)[\s\S])*?\)",
        r"coldStartWithoutBinding[\s\S]{0,4096}?XCTAssertEqual\s*\([\s\S]{0,256}?recoveredExpiredLeaseCount",
        r"coldStartWithoutBinding[\s\S]{0,4096}?XCTAssertFalse\s*\([\s\S]{0,256}?canonicalReapplyOccurred",
        r"coldStartDivergentAuthorityStillCleans[\s\S]{0,4096}?recoverColdStart\s*\(",
        r"coldStartDivergentAuthorityStillCleans[\s\S]{0,4096}?XCTAssertEqual\s*\([\s\S]{0,256}?recoveryCallCount[\s\S]{0,128}?,\s*1\s*\)",
        r"coldStartDivergentAuthorityStillCleans[\s\S]{0,4096}?XCTAssertFalse\s*\([\s\S]{0,256}?canonicalReapplyOccurred",
    ), "C50 binding-free cold-start adversarial tests")
    divergent_segment = re.search(
        r"coldStartDivergentAuthorityStillCleans[\s\S]{0,4096}", tests
    )
    if divergent_segment is None or not (
        re.search(r"XCTAssertThrowsError", divergent_segment.group())
        or re.search(r"\.divergentQuarantined", divergent_segment.group())
    ):
        raise ValueError("C50 cold-start divergent authority must throw or quarantine after cleanup")


def _assert_sources(root: Path) -> None:
    adapter = _text(root, IMPLEMENTATION_PATHS[0])
    profile = _text(root, IMPLEMENTATION_PATHS[1])
    coordinator = _text(root, IMPLEMENTATION_PATHS[2])
    lifecycle = _text(root, IMPLEMENTATION_PATHS[3])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    fixture = canonical(_json(root, IMPLEMENTATION_PATHS[5])).decode()
    all_source = "\n".join((adapter, profile, coordinator, lifecycle))

    _require_tokens(adapter, (
        "IncumbentFileAdapterV1", "IncumbentExchangeScopeV1", "IncumbentFileExportManifestV1",
        "IncumbentFileExchangeReceiptV1",
    ), "C50 adapter contracts")
    _require_tokens(adapter + profile, (
        "uniformTypeIdentifiers", "filenameExtensions", "IncumbentFileEncodingV1", "delimiter",
        "orderedHeaders", "versionHeader", "versionValue", "maximumByteCount", "maximumRowCount",
        "maximumColumnCount", "maximumScalarCountPerCell", "IncumbentMappingManifestV1",
        "externalKeyPolicy", "timeZonePolicy", "func parse", "func render",
    ), "C50 adapter boundary")
    _require_tokens(profile, (
        "ClosedIncumbentAdapterRegistryV1", "IncumbentFileProfileReleaseV1",
        "IncumbentSelectionReceiptV1", "DISABLED_NO_SELECTED_PROFILE",
        "IMPORT_ONLY", "EXPORT_ONLY", "BIDIRECTIONAL_FILES",
        "IncumbentAdapterProjectionKindV1", "IncumbentPrivacyApprovalReferenceV1",
        "bindingSHA256", "authorityBinding = .unbound", "expectedAllowedCanonicalFields",
    ), "C50 profile contracts")
    _require_tokens(profile, (
        "currentProductionReleases.count <= 1", "ENABLED_NAMED_PROFILE",
        "sanitizedFixtureProvenance", "termsDisposition", "evidenceDate", "evidenceExpiresAt",
    ), "C50 closed profile registry")
    _require_tokens(adapter + coordinator + lifecycle, (
        "PREVIEWED_ZERO_WRITE", "EXTERNAL_AVAILABILITY_UNKNOWN", "SOURCE_CHANGED",
        "UNSUPPORTED_VERSION", "HEADER_MISMATCH", "canonicalReapplyOccurred",
    ), "C50 exchange lifecycle")
    _require_tokens(lifecycle, (
        "IncumbentFileExchangeScratchLeaseV1", "IncumbentFileExchangeScratchLifecycleReceiptV1",
        "scratchDeleted", "terminals[binding.operationID]", "return terminal",
        "func quarantine", "func cancel", "func acquireExport", "func stageExport",
        "func finishExport", "func invalidateForPlanChange", ".supportExport",
        "func recoverAfterInterruption", "unknownAfterCallbackLoss", "securityScopeIsOperationScoped",
        "formulaAndControlSafeDelimitedOutput", "rehydrates only ephemeral cleanup",
    ), "C50 exchange lifecycle")
    _assert_privacy_authority_binding(profile, adapter, tests)
    _assert_export_manifest_lifecycle(adapter, coordinator, lifecycle, tests)
    _assert_privacy_bound_export_entrypoint(coordinator, tests)
    _assert_binding_free_cold_start(lifecycle, tests)
    for pattern in DISALLOWED_SOURCE_PATTERNS:
        if re.search(pattern, all_source) is not None:
            raise ValueError("C50 prohibited source capability:" + pattern)
    _require_tokens(profile, ("requiresExplicitPrivacyApproval", "CONTACT", "EVIDENCE", "MEDIA", "QUALIFICATION", "DIRECT_COST"), "C50 privacy classes")
    _require_tokens(adapter, (
        "privacyApproval", "allowedCanonicalFields", "omittedFields", "privacyApprovalRequired",
        "expectedProjection: IncumbentAdapterProjectionPayloadV1",
        "expectedWorkspaceFrontier", "expectedWorkspaceRevision", "workspaceRevision",
        "expectedAllowedCanonicalFields",
        "IncumbentCanonicalMutationReceiptReferenceV1", "expectedPlanSHA256",
        "authorityBinding = .unbound", "requireAuthoritativelyBound",
    ), "C50 privacy and mutation authority gate")
    _require_tokens(tests, (
        "testV23P03C50G01GoldenProfileRegistryAndDeterministicPreviewRender",
        "testV23P03C50A01HistoricReadExportAndNewStartRemainSeparated",
        "testV23P03C50H01StrictHeadersEncodingBudgetsAndPrivacyFailClosed",
        "testV23P03C50I01InterruptionCleanupAndLostCallbackAreIdempotent",
        "testV23P03C50R01HistoricRebindCloneForkEraseAndPrivacyBoundaries",
    ), "C50 evidence tests")
    _require_tokens(tests, (
        "DISABLED_NO_SELECTED_PROFILE", "ClosedIncumbentAdapterRegistryV1",
        "currentProductionReleases: []", "XCTAssertEqual(disabled.currentProductionReleases.count, 0)",
        '"UNKNOWN_VERSION"', '"REORDERED_HEADERS"', '"DUPLICATE_HEADERS"',
        '"UTF8_INVALID_SEQUENCE"', '"NFC_NONCANONICAL_TEXT"', '"CRLF_INPUT"', '"LF_INPUT"',
        '"FORMULA_PREFIX"', '"OVERSIZE_BYTES"', '"OVERSIZE_ROWS"', '"OVERSIZE_SCALAR"',
        '"TWO_CURRENT_PROFILES"', '"DIVERGENT_SAME_OPERATION"',
        "structurallyValidUnboundAdapterApproval", "revalidatedProjectionScope",
        "acquireExport", "stageExport", "relaunchedLifecycle.recover",
        "C20PrivacyTransformTestSupport.makeCanonicalMutationReceipt",
    ), "C50 tests")
    _require_tokens(fixture, EVIDENCE_IDS, "C50 fixture evidence")
    _require_tokens(fixture, (
        '"disabledStatus":"DISABLED_NO_SELECTED_PROFILE"', '"zeroOrOneProductionProfile":true',
        '"previewCanonicalWriteCount":0', '"previewReceiptCount":0',
        '"noProviderClaim":true', '"networkEndpoints":false', '"credentialsOrBookmarks":false',
        '"providerSDK":false', '"cloneForkCopySelection":false',
        '"eraseRemovesAppOwnedScratch":true', '"diagnosticsContainSourceBytes":false',
    ), "C50 fixture")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (137, 14, 151):
        raise ValueError("C50 fence cardinality")
    if len(set(PATH_FENCE)) != len(PATH_FENCE):
        raise ValueError("C50 duplicate fence path")
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C50 new path exists at base")
    if any(not _base_exists(root, path) for path in EXISTING_PATHS):
        raise ValueError("C50 existing path absent at base")
    for path in SCRIPT_PATHS:
        ast.parse(_text(root, path), filename=path)
    if any(FLAGS.values()):
        raise ValueError("C50 provisional flag true")
    _assert_sources(root)


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "directPrerequisites": ["V23-P03-C20"],
    }


def schema_document() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "urn:assetrounds:v23:p03:c50:incumbent-selection-receipt:v1",
        "title": "IncumbentSelectionReceiptV1", "type": "object", "additionalProperties": False,
        "required": ["schemaVersion", "receiptID", "disposition", "selectedReleaseID",
                     "selectedReleaseSHA256", "sanitizedFixtureProvenance", "targetWorkflow",
                     "fileVersion", "direction", "stableKeyMeaning", "termsDisposition",
                     "evidenceDate", "evidenceExpiresAt", "receiptSHA256"],
        "properties": {
            "schemaVersion": {"const": 1},
            "receiptID": {"type": "string", "format": "uuid", "not": {"const": "00000000-0000-0000-0000-000000000000"}},
            "disposition": {"const": "DISABLED_NO_SELECTED_PROFILE"},
            "selectedReleaseID": {"type": "null"}, "selectedReleaseSHA256": {"type": "null"},
            "sanitizedFixtureProvenance": {"type": "string", "minLength": 1, "maxLength": 1024,
                "pattern": "^[^\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]+$"},
            "targetWorkflow": {"type": "string", "minLength": 1, "maxLength": 160,
                "pattern": "^(?!.*[\\\"'\\\\])[!-~]+$"},
            "fileVersion": {"type": "null"}, "direction": {"type": "null"},
            "stableKeyMeaning": {"type": "string", "minLength": 1, "maxLength": 1024,
                "pattern": "^[^\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]+$"},
            "termsDisposition": {"enum": ["UNAVAILABLE", "EXPIRED"]},
            "evidenceDate": {"type": "number"},
            "evidenceExpiresAt": {"type": ["number", "null"]},
            "receiptSHA256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        },
        "$comment": "Constructor invariants not expressible here: Date values must be finite; optional expiry must be later than evidenceDate; Swift UTF-8 byte bounds and trimming are authoritative; receiptSHA256 must equal canonical constructor recomputation. The closed Release registry separately enforces zero current production releases for this disabled receipt and no TestSupport adapters in the Release binary.",
    }


def _file_inventory(root: Path, outputs: dict[str, bytes]) -> list[dict[str, Any]]:
    inventory = []
    for relative in MANIFEST_INPUT_PATHS:
        data = outputs.get(relative)
        if data is None:
            data = (root / relative).read_bytes()
        inventory.append({"path": relative, "byteCount": len(data), "sha256": sha256_bytes(data)})
    return inventory


def contract_document() -> dict[str, Any]:
    return {
        "schema": "V23P03C50IncumbentFileAdapterContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "registerOrdinal": REGISTER_ORDINAL,
        "authority": authority(),
        "sourceAuthority": {"dossier": {"byteCount": DOSSIER_BYTES, "sha256": DOSSIER_SHA256},
                            "inheritedV21": {"byteCount": INHERITED_BYTES, "sha256": INHERITED_SHA256},
                            "registerRow": {"byteCount": REGISTER_ROW_BYTES, "sha256": REGISTER_ROW_SHA256},
                            "registerSection": {"byteCount": REGISTER_SECTION_BYTES, "sha256": REGISTER_SECTION_SHA256}},
        "persistence": {"mode": "NONPERSISTENT", "schemaBump": False, "store": False, "writer": False,
                        "scratchExcludedFromBackup": True, "scratchDeletedAfterOutcome": True},
        "releaseRegistry": {"enabledProductionProfileMinimum": 0, "enabledProductionProfileMaximum": 1,
                            "selectedProfileCount": 0, "status": "DISABLED_NO_SELECTED_PROFILE",
                            "releaseTestAdaptersPresent": False, "publicProviderClaim": False},
        "adapterBoundary": {"providerNeutral": True, "exactVersionDetection": True, "failClosedHeaderMatching": True,
                            "budgetBounded": True, "deterministicParseMapRender": True,
                            "network": False, "credential": False, "bookmark": False, "secondWriter": False},
        "privacy": {"closedFieldAllowlist": True, "explicitPreview": True, "excludedByDefault": list(PRIVACY_EXCLUSIONS)},
        "recovery": {"sameInputPlanIdempotent": True, "changedDigestInvalidates": True,
                     "cancelledExportClaimsExternalAvailability": False,
                     "lostCallbackDisposition": "EXTERNAL_AVAILABILITY_UNKNOWN",
                     "forwardFix": "DISABLE_PROFILE_PRESERVE_OLD_READERS_PUBLISH_SUCCESSOR_NEVER_REINTERPRET"},
        "evidenceIDs": list(EVIDENCE_IDS), "statusFlags": FLAGS,
    }


def evidence_document() -> dict[str, Any]:
    cases = {key: {"evidenceID": evidence, "status": "STATIC_CONTRACT_BOUND"}
             for key, evidence in zip(("golden", "alternate", "hostile", "interruption", "recovery"), EVIDENCE_IDS)}
    return {"schema": "V23P03C50IncumbentFileAdapterEvidenceReceiptV1", "schemaVersion": 1,
            "cardID": CARD, "authority": authority(), "cases": cases,
            "selectedProfileCount": 0, "selectionStatus": "DISABLED_NO_SELECTED_PROFILE",
            "nativeCompileRan": False, "hostedDispatchEnabled": False,
            "physicalLockedState": "REQUIRED_PENDING_OWNER", "acceptanceCredit": False,
            "releaseCredit": False, "statusFlags": FLAGS}


def brand_document() -> dict[str, Any]:
    return {"schema": "V23P03C50BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
            "brandSurfaceDelta": True, "uiSurfaceDelta": False, "providerClaim": None,
            "presentation": "DISABLED_NO_SELECTED_PROFILE",
            "truthfulDisclosure": "No incumbent file profile is selected or enabled.",
            "prohibitedClaims": ["integrated", "connected", "synced", "supported provider", "verified provider"],
            "statusFlags": FLAGS}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    outputs = {SCHEMA_PATH: pretty(schema_document()), CONTRACT_PATH: pretty(contract_document()),
               EVIDENCE_PATH: pretty(evidence_document()), BRAND_PATH: pretty(brand_document())}
    manifest = {"schema": "V23P03C50ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
                "authority": authority(), "fencePathCount": 151, "existingPathCount": 137,
                "newPathCount": 14, "s10ReservedPathCount": 86, "s10ReservationOverlapCount": 0,
                "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0,
                "s10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
                "nonpersistent": True, "selectedProfileCount": 0,
                "selectionStatus": "DISABLED_NO_SELECTED_PROFILE", "statusFlags": FLAGS,
                "files": _file_inventory(root, outputs)}
    outputs[MANIFEST_PATH] = pretty(manifest)
    return outputs
