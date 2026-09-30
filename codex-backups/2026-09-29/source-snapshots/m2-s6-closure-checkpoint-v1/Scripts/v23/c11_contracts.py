#!/usr/bin/env python3
"""Deterministic V23-P00-C11 concurrency-preparation contracts."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

from c07_contracts import (
    DEPENDENCY_DISPOSITION_DIGEST,
    GRAPH_DIGEST,
    OVERRIDE_RECEIPT_DIGEST,
    PACKAGE_DIGEST,
    REGISTER_DIGEST,
    RELATION_DIGEST,
    RESERVATION_DIGEST,
    SELECTOR_DIGEST,
    ContractError,
    digest,
    load_reservation,
    pretty_bytes,
    seal,
    sha256_bytes,
    validate_frozen_authority,
)


CARD_ID = "V23-P00-C11"
BASE_HEAD = "fad0ca2711ec891a13ca51f68c54bc934e1ca8d8"
BASE_TREE = "a49abf914a26c99e4efe284a7d2c3ba04f7933f6"
CONTEXT_DIGEST = "97c5d75eaaf3419ed74148c287050a47bee417cc2074bc3821d10caf2a9cf220"
BOOTSTRAP_FENCE_DIGEST = "560b3bd0401d0da46bcedc9f7184c8041e198db8cbe8af3011731fc0ad6cc8b1"
HYDRATED_SPEC_DIGEST = "5ff0da398f4ddecad4ca7a815b772bc830e7267e53629a5dee69d705d2f5fffb"
HYDRATED_FENCE_DIGEST = "99386013a49cc8ac6b8c1fa94f474898cce3d1812679fd1ed118c10585b1a8ed"
PROVISIONAL_PREREQUISITE_DIGEST = "635f08847548049ea43b6aa82caecfb0d962569171787b8598eabb47392012d7"
LEDGER_DIGEST = "83ec06eee415745899c939ea1b4629e2da75ceb1b73ebe3bd2ade187d85e9171"
LEDGER_CAS_SEQUENCE = 31
DOSSIER_DIGEST = "e3c9b8153149009205e9d01b6355808723b24e281a162488cfa7774f8d8bae63"
C07_ALLOCATION_DIGEST = "a3974f7989a5efe5674af12e5d73710be06a87ac5c609a8dd504ee00c38d4a0a"
C07_MANIFEST_DIGEST = "1d339540d38e8378b861ef827713d0347197219b0d133c13a8b8de5949608619"

PORT_PATH = "FieldEvidenceApp/Application/Ports/DeterministicAsyncPorts.swift"
ADAPTER_PATH = "FieldEvidenceApp/Infrastructure/System/SystemAsyncAdapters.swift"
MAIL_PATH = "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift"
ERASE_PATH = "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift"
MAIL_TEST_PATH = "FieldEvidenceAppTests/V23_P00_C11MailComposerConcurrencyTests.swift"
ASYNC_TEST_PATH = "FieldEvidenceAppTests/V23_P00_C11DeterministicAsyncTests.swift"

SCHEMA_PATHS = [
    "Scripts/v23/concurrency-isolation-inventory.schema.json",
    "Scripts/v23/unsafe-boundary-disposition.schema.json",
    "Scripts/v23/deterministic-async-port.schema.json",
    "Scripts/v23/concurrency-closure-receipt.schema.json",
    "Scripts/v23/concurrency-migration-plan.schema.json",
    "Scripts/v23/platform-adapter-concurrency-receipt.schema.json",
]
ARTIFACT_PATHS = [
    "docs/design/v23/tooling/ConcurrencyIsolationInventoryV1.json",
    "docs/design/v23/tooling/UnsafeBoundaryDispositionV1.json",
    "docs/design/v23/tooling/DeterministicAsyncPortV1.json",
    "docs/design/v23/tooling/ConcurrencyClosureReceiptV1.json",
    "docs/design/v23/tooling/ConcurrencyMigrationPlanV1.json",
    "docs/design/v23/tooling/PlatformAdapterConcurrencyReceiptV1.json",
]
MANIFEST_PATH = "docs/design/v23/tooling/V23-P00-C11-tooling-manifest.json"
FENCED_PATHS = [
    PORT_PATH,
    ADAPTER_PATH,
    MAIL_PATH,
    ERASE_PATH,
    MAIL_TEST_PATH,
    ASYNC_TEST_PATH,
    "Scripts/v23/c11_contracts.py",
    "Scripts/v23/generate_c11_contracts.py",
    "Scripts/v23/verify_c11_contracts.py",
    *SCHEMA_PATHS,
    *ARTIFACT_PATHS,
    MANIFEST_PATH,
]

PATTERNS = {
    "explicitActorDeclaration": re.compile(r"\bactor\s+[A-Za-z_][A-Za-z0-9_]*"),
    "mainActorIsolation": re.compile(r"@MainActor\b"),
    "uncheckedSendable": re.compile(r"@unchecked\s+Sendable\b"),
    "nonisolatedUnsafe": re.compile(r"nonisolated\s*\(\s*unsafe\s*\)"),
    "detachedTask": re.compile(r"\bTask\s*\.\s*detached\b"),
    "preconcurrency": re.compile(r"@preconcurrency\b"),
    "assumeIsolated": re.compile(r"\bMainActor\s*\.\s*assumeIsolated\b"),
    "unstructuredTask": re.compile(r"\bTask\s*\{"),
    "taskSleep": re.compile(r"\bTask(?:\s*<[^\n>]+>)?\s*\.\s*sleep\b"),
    "notificationCenter": re.compile(r"\bNotificationCenter\b"),
    "directClock": re.compile(r"\bDate\s*(?:\(|\.init\b)"),
    "directID": re.compile(r"\bUUID\s*(?:\(|\.init\b)"),
    "fileSystem": re.compile(r"\bFileManager\b|\bDarwin\.(?:open|close|read|write|unlink|rename)\b"),
    "randomSource": re.compile(r"\bSystemRandomNumberGenerator\b|\.random\s*\("),
}


def authority_binding() -> dict[str, Any]:
    return {
        "attemptID": 1,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "candidateBinding": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED",
        "packageDigest": PACKAGE_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "canonicalRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "ownerOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "bootstrapContextDigest": CONTEXT_DIGEST,
        "bootstrapPathFenceDigest": BOOTSTRAP_FENCE_DIGEST,
        "hydratedSpecDigest": HYDRATED_SPEC_DIGEST,
        "hydratedPathFenceDigest": HYDRATED_FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PROVISIONAL_PREREQUISITE_DIGEST,
        "writerAuthority": {
            "ownerID": "A00_BOOTSTRAP_CONTROLLER",
            "writerGeneration": 0,
        },
        "ledgerDigest": LEDGER_DIGEST,
        "ledgerCASSequence": LEDGER_CAS_SEQUENCE,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceEnabled": False,
        "hostedDispatchEnabled": False,
        "adoptionEnabled": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "releaseCredit": False,
    }


def git(root: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=check,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return result.stdout


def read_at_head(root: Path, relative: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return result.stdout if result.returncode == 0 else ""


def production_paths(root: Path) -> list[str]:
    current = {
        path.relative_to(root).as_posix()
        for path in (root / "FieldEvidenceApp").rglob("*.swift")
        if path.is_file()
    }
    baseline = {
        line.strip()
        for line in git(root, "ls-tree", "-r", "--name-only", BASE_HEAD, "--", "FieldEvidenceApp").splitlines()
        if line.strip().endswith(".swift")
    }
    return sorted(current | baseline)


def findings_for(path: str, source: str, reserved: set[str]) -> dict[str, list[dict[str, Any]]]:
    result = {name: [] for name in PATTERNS}
    for line_number, line in enumerate(source.splitlines(), start=1):
        for name, pattern in PATTERNS.items():
            if pattern.search(line):
                result[name].append({
                    "path": path,
                    "line": line_number,
                    "snippetSHA256": hashlib.sha256(line.strip().encode()).hexdigest(),
                    "reservedByActiveS10": path in reserved,
                })
    return result


def source_inventory(root: Path, *, baseline: bool) -> dict[str, Any]:
    reservation = load_reservation(root)
    reserved = set(reservation["reservedPaths"])
    findings = {name: [] for name in PATTERNS}
    files = production_paths(root)
    for relative in files:
        source = read_at_head(root, relative) if baseline else (
            (root / relative).read_text(encoding="utf-8")
            if (root / relative).is_file() else ""
        )
        for name, rows in findings_for(relative, source, reserved).items():
            findings[name].extend(rows)
    for rows in findings.values():
        rows.sort(key=lambda item: (item["path"], item["line"], item["snippetSHA256"]))
    return {
        "productionSwiftFileCount": len(files),
        "reservedProductionSwiftFileCount": len([path for path in files if path in reserved]),
        "nonreservedProductionSwiftFileCount": len([path for path in files if path not in reserved]),
        "findingCounts": {name: len(rows) for name, rows in findings.items()},
        "findings": findings,
    }


def validate_c07_allocation(root: Path) -> list[dict[str, Any]]:
    allocation = json.loads((root / "docs/design/v23/tooling/V21C07RequirementAllocationV1.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "docs/design/v23/tooling/V23-P00-C07-tooling-manifest.json").read_text(encoding="utf-8"))
    if allocation.get("artifactDigest") != C07_ALLOCATION_DIGEST:
        raise ContractError("C07 allocation digest differs")
    if manifest.get("artifactDigest") != C07_MANIFEST_DIGEST:
        raise ContractError("C07 manifest digest differs")
    rows = [row for row in allocation["rows"] if row["soleOwner"] == CARD_ID]
    if len(rows) != 10 or len({row["atomicClauseID"] for row in rows}) != 10:
        raise ContractError("C11 must own exactly ten unique C07 clauses")
    return rows


def validate_fence(root: Path) -> None:
    reservation = load_reservation(root)
    if len(FENCED_PATHS) != 22 or len(set(FENCED_PATHS)) != 22:
        raise ContractError("C11 fence cardinality differs")
    overlap = set(FENCED_PATHS) & set(reservation["reservedPaths"])
    if overlap:
        raise ContractError(f"C11 overlaps frozen Phase10 ownership: {sorted(overlap)}")
    changed = {
        line.replace("\\", "/")
        for line in git(root, "diff", "--name-only", BASE_HEAD).splitlines()
        if line
    }
    if not changed <= set(FENCED_PATHS):
        raise ContractError(f"C11 out-of-fence delta: {sorted(changed - set(FENCED_PATHS))}")
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    for line in status.splitlines():
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"C11 contains delete or rename: {line}")
        relative = raw.replace("\\", "/")
        if relative not in FENCED_PATHS:
            raise ContractError(f"C11 contains untracked/out-of-fence work: {relative}")


def validate_swift_delta(root: Path) -> dict[str, Any]:
    port = (root / PORT_PATH).read_text(encoding="utf-8")
    adapter = (root / ADAPTER_PATH).read_text(encoding="utf-8")
    mail = (root / MAIL_PATH).read_text(encoding="utf-8")
    erase = (root / ERASE_PATH).read_text(encoding="utf-8")
    mail_tests = (root / MAIL_TEST_PATH).read_text(encoding="utf-8")
    async_tests = (root / ASYNC_TEST_PATH).read_text(encoding="utf-8")
    if port.count("protocol ApplicationSleeper: Sendable") != 1 or "func sleep(for duration: Duration) async throws" not in port:
        raise ContractError("deterministic async port differs")
    if adapter.count("struct SystemApplicationSleeper: ApplicationSleeper") != 1 or "Task<Never, Never>.sleep(for: duration)" not in adapter:
        raise ContractError("system async adapter differs")
    required_mail = (
        "nonisolated func mailComposeController",
        "nonisolated static func outcome",
        "MainActor.assumeIsolated",
        "guard !didFinish else { return }",
        "complete(outcome)",
    )
    if any(value not in mail for value in required_mail):
        raise ContractError("MailComposer actor or exactly-once repair differs")
    if any(value in mail for value in ("Task {", "@preconcurrency", "@unchecked Sendable", "nonisolated(unsafe)")):
        raise ContractError("MailComposer contains an unsafe or unstructured escape")
    required_erase = (
        "private let sleeper: any ApplicationSleeper",
        "sleeper: any ApplicationSleeper = SystemApplicationSleeper()",
        "guard try await waitForDrain(drainProof)",
        "func waitForDrain(_ proof: EraseGenerationDrainProof) async throws -> Bool",
        "try await sleeper.sleep(for: .milliseconds(10))",
        "catch is CancellationError",
    )
    if any(value not in erase for value in required_erase) or "Task.sleep(nanoseconds: 10_000_000)" in erase:
        raise ContractError("Erase deterministic delay or failure propagation differs")
    required_tests = (
        "testEveryMailOutcomeCompletesExactlyOnceOnMainActor",
        "testErrorOverridesMessageUIResultAndDuplicateCompletionIsIgnored",
        "testResultMappingDoesNotCrossMessageUIValuesIntoMainActor",
    )
    if any(value not in mail_tests for value in required_tests):
        raise ContractError("Mail platform callback tests differ")
    required_async_tests = (
        "testInjectedSleeperRecordsExactDurationWithoutWallClockDelay",
        "testSystemSleeperPreservesCancellation",
        "testInjectedSleeperRejectsCancellationBeforeRecording",
        "try Task.checkCancellation()",
    )
    if any(value not in async_tests for value in required_async_tests):
        raise ContractError("deterministic async tests differ")
    baseline = source_inventory(root, baseline=True)
    candidate = source_inventory(root, baseline=False)
    for hostile in ("uncheckedSendable", "nonisolatedUnsafe", "detachedTask", "preconcurrency"):
        if candidate["findingCounts"][hostile] > baseline["findingCounts"][hostile]:
            raise ContractError(f"C11 introduced forbidden concurrency debt: {hostile}")
    if candidate["findingCounts"]["assumeIsolated"] != baseline["findingCounts"]["assumeIsolated"] + 1:
        raise ContractError("C11 Mail boundary must add exactly one owned synchronous actor assertion")
    return {"baseline": baseline, "candidate": candidate}


def boundary_key(row: dict[str, Any], kind: str) -> str:
    return f"{kind}:{row['path']}:{row['line']}:{row['snippetSHA256']}"


def unsafe_dispositions(inventory: dict[str, Any]) -> list[dict[str, Any]]:
    baseline_keys = {
        boundary_key(row, kind)
        for kind in ("uncheckedSendable", "nonisolatedUnsafe", "detachedTask", "preconcurrency", "assumeIsolated")
        for row in inventory["baseline"]["findings"][kind]
    }
    rows = []
    for kind in ("uncheckedSendable", "nonisolatedUnsafe", "detachedTask", "preconcurrency", "assumeIsolated"):
        for finding in inventory["candidate"]["findings"][kind]:
            key = boundary_key(finding, kind)
            is_mail_assertion = kind == "assumeIsolated" and finding["path"] == MAIL_PATH
            rows.append({
                "boundaryID": key,
                "kind": kind,
                **finding,
                "baselineBoundary": key in baseline_keys,
                "owner": CARD_ID if is_mail_assertion else (
                    "ACTIVE_S10_OWNER_REPROOF_REQUIRED" if finding["reservedByActiveS10"]
                    else "DECLARED_FUTURE_WRITER_OR_C12_REPROOF"
                ),
                "disposition": (
                    "OWNED_SYNCHRONOUS_MAIN_ACTOR_PLATFORM_HANDOFF"
                    if is_mail_assertion else "RETAINED_BASELINE_NOT_MODIFIED_BY_C11_FENCE"
                ),
                "rationale": (
                    "MessageUI main-thread delegate guarantee is asserted synchronously after mapping only Sendable app outcome data."
                    if is_mail_assertion else "Pre-existing boundary is inventoried without broad writer or reserved-path mutation."
                ),
                "expiryOrReproofGate": "V23-P00-C12_EXACT_CANDIDATE_NATIVE_REPROOF",
                "targetedEvidence": (
                    "V23_P00_C11MailComposerConcurrencyTests"
                    if is_mail_assertion else "REQUIRED_BEFORE_C11_ACCEPTANCE_OR_C12_CLOSURE"
                ),
            })
    return sorted(rows, key=lambda item: item["boundaryID"])


def build_artifacts(root: Path) -> dict[str, dict[str, Any]]:
    validate_frozen_authority(root)
    validate_fence(root)
    c07_rows = validate_c07_allocation(root)
    inventory = validate_swift_delta(root)
    authority = authority_binding()
    baseline = inventory["baseline"]
    candidate = inventory["candidate"]
    isolation = seal({
        "schema": "ConcurrencyIsolationInventoryV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "authority": authority,
        "scanScope": "ALL_PRODUCTION_SWIFT_WITH_EXACT_FROZEN_S10_RESERVATION_CLASSIFICATION",
        "baseline": baseline,
        "candidate": candidate,
        "newForbiddenDebtCount": sum(max(0, candidate["findingCounts"][name] - baseline["findingCounts"][name]) for name in (
            "uncheckedSendable", "nonisolatedUnsafe", "detachedTask", "preconcurrency"
        )),
        "nativeCompleteDiagnostics": "NOT_RUN_RESERVED_PROJECT_AND_HOSTED_WORKFLOW",
        "provisionalDisposition": "STATIC_INVENTORY_COMPLETE_NATIVE_ZERO_WARNING_CHECKPOINT_DEFERRED",
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
    dispositions = unsafe_dispositions(inventory)
    unsafe = seal({
        "schema": "UnsafeBoundaryDispositionV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "authority": authority,
        "boundaries": dispositions,
        "baselineUncheckedCount": baseline["findingCounts"]["uncheckedSendable"],
        "candidateUncheckedCount": candidate["findingCounts"]["uncheckedSendable"],
        "newUncheckedCount": max(0, candidate["findingCounts"]["uncheckedSendable"] - baseline["findingCounts"]["uncheckedSendable"]),
        "newUnsafeIsolationCount": max(0, candidate["findingCounts"]["nonisolatedUnsafe"] - baseline["findingCounts"]["nonisolatedUnsafe"]),
        "newDetachedTaskCount": max(0, candidate["findingCounts"]["detachedTask"] - baseline["findingCounts"]["detachedTask"]),
        "newPreconcurrencyCount": max(0, candidate["findingCounts"]["preconcurrency"] - baseline["findingCounts"]["preconcurrency"]),
        "ownedAssumeIsolatedCount": len([row for row in dispositions if row["owner"] == CARD_ID and row["kind"] == "assumeIsolated"]),
        "hostileRatchetStatus": "PASS_NO_NEW_UNCHECKED_UNSAFE_DETACHED_OR_PRECONCURRENCY_ESCAPE",
        "nativeRaceEvidence": "NOT_RUN_HOSTED_DISPATCH_DISABLED",
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
    deterministic = seal({
        "schema": "DeterministicAsyncPortV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "authority": authority,
        "ports": [
            {
                "dependency": "CLOCK",
                "port": "ApplicationClock",
                "adapter": "SystemApplicationClock",
                "declarationPath": "FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift",
                "status": "IMPLEMENTED_BY_DIRECT_C10_PREREQUISITE",
            },
            {
                "dependency": "UUID",
                "port": "ApplicationIDSource",
                "adapter": "SystemApplicationIDSource",
                "declarationPath": "FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift",
                "status": "IMPLEMENTED_BY_DIRECT_C10_PREREQUISITE",
            },
            {
                "dependency": "ASYNC_DELAY",
                "port": "ApplicationSleeper",
                "adapter": "SystemApplicationSleeper",
                "declarationPath": PORT_PATH,
                "consumerPath": ERASE_PATH,
                "status": "IMPLEMENTED_CANCELLATION_PRESERVING_AND_FAILURE_PROPAGATING",
            },
            {
                "dependency": "RANDOM",
                "port": None,
                "adapter": None,
                "status": "NOT_APPLICABLE_NO_PRODUCTION_RANDOM_CALLSITE",
            },
            {
                "dependency": "FILESYSTEM",
                "port": "EXISTING_NARROW_FILEMANAGER_CLOSURE_AND_DESCRIPTOR_AUTHORITIES",
                "adapter": "DEFERRED_TO_DECLARED_WRITER_OWNERS_NO_SPECULATIVE_GLOBAL_FACADE",
                "status": "INVENTORIED_REPROOF_REQUIRED_BEFORE_ACCEPTANCE",
            },
        ],
        "baselineDirectDependencyCounts": {
            key: baseline["findingCounts"][key]
            for key in ("directClock", "directID", "fileSystem", "randomSource", "taskSleep")
        },
        "candidateDirectDependencyCounts": {
            key: candidate["findingCounts"][key]
            for key in ("directClock", "directID", "fileSystem", "randomSource", "taskSleep")
        },
        "declaredTests": [
            "V23_P00_C11DeterministicAsyncTests.testInjectedSleeperRecordsExactDurationWithoutWallClockDelay",
            "V23_P00_C11DeterministicAsyncTests.testSystemSleeperPreservesCancellation",
            "V23_P00_C11DeterministicAsyncTests.testInjectedSleeperRejectsCancellationBeforeRecording",
        ],
        "nativeTestsRan": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
    migration = seal({
        "schema": "ConcurrencyMigrationPlanV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "authority": authority,
        "orderedStages": [
            {
                "ordinal": 1,
                "stage": "C11_DISJOINT_PLATFORM_AND_ASYNC_SEAM",
                "status": "IMPLEMENTED_STATIC_REVIEW_PENDING_NATIVE_PROOF",
                "scope": [MAIL_PATH, PORT_PATH, ADAPTER_PATH, ERASE_PATH],
            },
            {
                "ordinal": 2,
                "stage": "SWIFT5_COMPLETE_TARGET_CHECKPOINT",
                "status": "DEFERRED_FROZEN_S10_PROJECT_AND_WORKFLOW_OWNERSHIP",
                "scope": ["APP_DEBUG_RELEASE", "UNIT_TESTS", "UI_TESTS"],
            },
            {
                "ordinal": 3,
                "stage": "REMAINING_WRITER_OWNED_CLOCK_ID_FILESYSTEM_AND_TASK_SEAMS",
                "status": "DEFERRED_TO_FRESH_DIGEST_BOUND_FENCES_AND_DECLARED_WRITER_OWNERS",
                "scope": ["P02_WRITER", "COMMERCE", "REPORT_RECOVERY", "FINALIZATION", "MEDIA"],
            },
            {
                "ordinal": 4,
                "stage": "C12_SWIFT6_LANGUAGE_MODE_CLOSURE",
                "status": "NOT_STARTED_DIRECT_CONSUMER_MUST_REPROVE_C11",
                "scope": ["V23-P00-C12"],
            },
        ],
        "requiredCompilerOverrides": [
            "SWIFT_VERSION=5",
            "SWIFT_STRICT_CONCURRENCY=complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
        ],
        "writerTruthPreserved": True,
        "languageModeChangedByC11": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
    platform = seal({
        "schema": "PlatformAdapterConcurrencyReceiptV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "authority": authority,
        "mailBoundary": {
            "adapterPath": MAIL_PATH,
            "delegateWitnessIsolation": "NONISOLATED_MAP_THEN_SYNCHRONOUS_MAIN_ACTOR_ASSERTION",
            "messageUIValuesCrossActorBoundary": False,
            "unstructuredTaskCreated": False,
            "terminalOutcomes": ["cancelled", "failed", "saved", "sent"],
            "errorPrecedence": "ERROR_ALWAYS_MAPS_TO_FAILED",
            "exactlyOnceGuard": "FIRST_TERMINAL_CALLBACK_WINS_ON_MAIN_ACTOR",
            "declaredTests": [
                "testEveryMailOutcomeCompletesExactlyOnceOnMainActor",
                "testErrorOverridesMessageUIResultAndDuplicateCompletionIsIgnored",
                "testResultMappingDoesNotCrossMessageUIValuesIntoMainActor",
            ],
        },
        "systemAsyncBoundary": {
            "adapterPath": ADAPTER_PATH,
            "portPath": PORT_PATH,
            "consumerPath": ERASE_PATH,
            "cancellationPreserved": True,
            "nonCancellationErrorsPropagate": True,
        },
        "nativePlatformTestsRan": False,
        "nativeCompileRan": False,
        "provisionalDisposition": "STATIC_PLATFORM_CONTRACT_GREEN_NATIVE_CALLBACK_REPROOF_DEFERRED",
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
    closure = seal({
        "schema": "ConcurrencyClosureReceiptV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "authority": authority,
        "c07AllocatedClauseIDs": [row["atomicClauseID"] for row in c07_rows],
        "c07AllocatedClauseCount": len(c07_rows),
        "isolationInventoryDigest": isolation["artifactDigest"],
        "unsafeDispositionDigest": unsafe["artifactDigest"],
        "deterministicAsyncPortDigest": deterministic["artifactDigest"],
        "migrationPlanDigest": migration["artifactDigest"],
        "platformAdapterDigest": platform["artifactDigest"],
        "staticContractStatus": "PASS",
        "swift5CompleteZeroWarningStatus": "NOT_RUN_RESERVED_PROJECT_AND_HOSTED_WORKFLOW",
        "nativeTargetConfigurationCountProved": 0,
        "mailCallbackNativeEvidenceStatus": "NOT_RUN_HOSTED_DISPATCH_DISABLED",
        "retainedUnsafeRaceEvidenceStatus": "NOT_RUN_HOSTED_DISPATCH_DISABLED",
        "interruptionRecoveryEvidenceStatus": "DECLARED_NOT_NATIVE_EXECUTED",
        "closureSatisfied": False,
        "provisionalDisposition": "TARGETED_STATIC_GREEN_NOT_ACCEPTABLE",
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
    values = [isolation, unsafe, deterministic, closure, migration, platform]
    return dict(zip(ARTIFACT_PATHS, values, strict=True))


def json_type(value: Any) -> str:
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    raise ContractError(f"Unsupported schema value: {type(value)}")


def schema_for(artifact: dict[str, Any]) -> dict[str, Any]:
    properties: dict[str, Any] = {}
    for key, value in artifact.items():
        if key in ("schema", "schemaVersion", "cardID", "authority", "acceptanceCredit", "releaseCredit"):
            properties[key] = {"const": value}
        elif key == "artifactDigest":
            properties[key] = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        else:
            properties[key] = {"type": json_type(value)}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{artifact['schema']}.schema.json",
        "title": artifact["schema"],
        "type": "object",
        "additionalProperties": False,
        "required": list(artifact.keys()),
        "properties": properties,
    }


def build_outputs(root: Path) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    artifacts = build_artifacts(root)
    schemas = {
        path: schema_for(artifacts[ARTIFACT_PATHS[index]])
        for index, path in enumerate(SCHEMA_PATHS)
    }
    return schemas, artifacts


def build_manifest(root: Path) -> dict[str, Any]:
    rows = []
    for relative in FENCED_PATHS:
        if relative == MANIFEST_PATH:
            continue
        path = root / relative
        if not path.is_file():
            raise ContractError(f"C11 manifest input missing: {relative}")
        rows.append({
            "path": relative,
            "sha256": sha256_bytes(path.read_bytes()),
            "bytes": path.stat().st_size,
        })
    return seal({
        "schema": "V23P00C11ToolingManifestV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "authority": authority_binding(),
        "pathFence": FENCED_PATHS,
        "artifacts": rows,
        "artifactCount": len(rows),
        "nativeCompileRan": False,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
