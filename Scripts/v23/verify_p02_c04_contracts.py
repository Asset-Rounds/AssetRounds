#!/usr/bin/env python3
"""Hostile static verifier for V23-P02-C04."""
from __future__ import annotations

import ast
import copy
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

from p02_c04_contracts import (
    CONTRACT_SCRIPT, CORPUS_DOC, CORPUS_SCHEMA, EVIDENCE_IDS, FENCE_DOC,
    FENCE_SCHEMA, GENERATED_PATHS, LEASE_DOC, LEASE_SCHEMA, MANIFEST,
    MANIFEST_INPUT_PATHS, PATH_FENCE, PRUNE_DOC, PRUNE_SCHEMA, PROHIBITED_TOKENS,
    SOURCE_PATHS, TEST_METHODS, TOOL_PATHS, all_outputs, authority, canonical,
    pretty, sha,
)

ROOT = Path(__file__).resolve().parents[2]


class VerificationError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition: raise VerificationError(message)


def load(relative: str) -> Any:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def verify_seal(document: dict[str, Any], name: str) -> None:
    digest = document.get("artifactDigest"); require(isinstance(digest, str), f"{name}: missing artifactDigest")
    unsealed = dict(document); del unsealed["artifactDigest"]
    require(digest == sha(pretty(unsealed)), f"{name}: artifactDigest mismatch")


def verify_flags(document: dict[str, Any], name: str) -> None:
    for key in ("nativeCompileRan", "hostedDispatchRan", "physicalEvidenceComplete", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit", "phase10PollingDuringParallelExecution"):
        require(document.get(key) is False, f"{name}: false-credit flag {key}")
    require(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{name}: missing S10.6 gate")
    require(document.get("provisional") is True, f"{name}: not provisional")


def validate_instance(instance: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema: require(instance == schema["const"], f"{path}: const mismatch")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(instance, dict), f"{path}: expected object")
        require(set(schema.get("required", [])).issubset(instance), f"{path}: missing required")
        if schema.get("additionalProperties") is False: require(set(instance).issubset(schema.get("properties", {})), f"{path}: additional property")
        for key, child in schema.get("properties", {}).items():
            if key in instance: validate_instance(instance[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(instance, list), f"{path}: expected array")
        require(schema.get("minItems", 0) <= len(instance) <= schema.get("maxItems", len(instance)), f"{path}: array bounds")
        for index, child in enumerate(schema.get("prefixItems", [])): validate_instance(instance[index], child, f"{path}[{index}]")
        require(not (schema.get("items") is False and len(instance) > len(schema.get("prefixItems", []))), f"{path}: additional item")
    elif kind == "string":
        require(isinstance(instance, str), f"{path}: expected string")
        if schema.get("pattern") == "^[0-9a-f]{64}$": require(len(instance) == 64 and all(ch in "0123456789abcdef" for ch in instance), f"{path}: invalid digest")


def verify_generated() -> None:
    expected = all_outputs(ROOT); require(list(expected) == GENERATED_PATHS, "generated path order mismatch")
    for relative, data in expected.items():
        path = ROOT / relative; require(path.is_file(), f"missing generated artifact: {relative}")
        require(path.read_bytes() == data, f"stale generated artifact: {relative}")
        value = load(relative); require(path.read_bytes() == pretty(value), f"{relative}: noncanonical pretty JSON")


def verify_contracts() -> None:
    docs = {path: load(path) for path in (LEASE_DOC, FENCE_DOC, PRUNE_DOC, CORPUS_DOC)}
    for name, document in docs.items():
        verify_seal(document, name); verify_flags(document, name)
        require(document["authority"] == authority(), f"{name}: authority mismatch")
        require(document["evidenceIDs"] == EVIDENCE_IDS, f"{name}: evidence mismatch")
        encoded = canonical(document).decode("utf-8")
        for token in PROHIBITED_TOKENS: require(token not in encoded or token in document.get("prohibitedTokens", []), f"{name}: prohibited behavior leak")
    lease = docs[LEASE_DOC]
    require(lease["leaseRoles"] == ["READER", "WRITER"], "closed lease roles mismatch")
    require(lease["registry"]["boundedLeaseCountRequired"] is True and lease["registry"]["maximumActiveLeaseCount"] == 256 and lease["registry"]["maximumOwnerCount"] == 64 and lease["registry"]["maximumControlFileBytes"] == 4194304, "lease bounds absent")
    require(lease["liveness"]["unknownOrUncertain"] == "RETAIN_AND_FAIL_CLOSED", "uncertain liveness not retained")
    crash = lease["registry"]["controlFileCrashSafety"]
    require(crash["initialPublication"] == "PROTECTED_FSYNCED_TEMPORARY_THEN_RENAME_EXCL" and crash["protectionAppliedBeforeControlBytes"] is True and crash["loadReverifiesPolicyAndStableDescriptorSnapshot"] is True and crash["failedCreateCleanupRequiresExactCreatedIdentity"] is True and crash["partialCanonicalFileCanBecomeAuthority"] is False, "control-file crash safety incomplete")
    fence = docs[FENCE_DOC]
    commit = fence["canonicalCommitFence"]
    require(commit["requiredExpectedValues"] == ["expectedGenerationEpoch", "writerLeaseToken"] and commit["allMustMatch"] is True, "epoch+lease commit fence incomplete")
    require(fence["api"] == "StaleWriterFenceV1.withAuthorizedCommit(_:)", "commit-fence API mismatch")
    require(fence["commitLockDurability"] == {"rootAuthorityProvedBeforeClosure": True, "epochAndActiveWriterLeaseProvedInsideSameLock": True, "postCommitPathReproofMayReportOrdinaryFailure": False, "nextOperationPerformsNormalPrevalidation": True}, "commit-lock durability mismatch")
    require(fence["coveredCommitters"] == ["WorkspaceWriterAdapterV1", "MutationJournalStoreV1.commit", "MutationReceiptRecoveryServiceV1", "WholeSignDeletionService.commitCanonicalMutation"], "canonical committer closure mismatch")
    require(fence["failureAtomicity"] == "NO_CANONICAL_MODEL_EFFECT_ENVELOPE_RECEIPT_OR_SEQUENCE_ADVANCE", "stale failure atomicity absent")
    prune = docs[PRUNE_DOC]
    require(prune["eligibility"]["onlyState"] == "KNOWN_INACTIVE_ACCEPTED" and prune["eligibility"]["allLeasesReleased"] is True, "unsafe prune eligibility")
    require(prune["retention"]["unknownCorruptOrUncertainOwnership"] == "RETAIN_BYTES_FAIL_CLOSED", "unknown/corrupt ownership not retained")
    require(prune["retention"]["retainedInactiveAcceptedGenerationCount"] == 2, "inactive generation retention mismatch")
    require(prune["abandonedProcessRecovery"]["liveOrUncertainLeaseReleased"] is False, "live/uncertain lease release permitted")
    require(prune["pruneTransaction"]["intentPhases"] == ["PREPARED", "BYTES_REMOVED", "RETIRED_POINTER_PUBLISHED", "RECEIPT_PUBLISHED"], "prune intent phase closure mismatch")
    require(prune["pruneTransaction"]["receiptDispositions"] == ["PRUNED", "NO_ELIGIBLE_GENERATIONS", "DISABLED_RETAIN_ALL", "UNCERTAIN_RETAIN_ALL"], "prune disposition closure mismatch")
    require("ownerLivenessUncertain" in prune["pruneTransaction"]["receiptFields"], "owner-liveness receipt field absent")
    require(prune["pruneTransaction"]["receiptDispositionInvariants"] == {
        "PRUNED": "PRUNED_EPOCHS_NONEMPTY_AND_OWNER_LIVENESS_CERTAIN_AND_UNCERTAIN_IDS_EMPTY",
        "NO_ELIGIBLE_GENERATIONS": "NO_PRUNING_AND_OWNER_LIVENESS_CERTAIN",
        "DISABLED_RETAIN_ALL": "NO_PRUNING_AND_OWNER_LIVENESS_CERTAIN",
        "UNCERTAIN_RETAIN_ALL": "NO_PRUNING_AND_OWNER_LIVENESS_UNCERTAIN_OR_UNCERTAIN_IDS_NONEMPTY",
    }, "owner-liveness disposition semantics mismatch")
    bounded = prune["pruneTransaction"]["boundedCollections"]
    require(bounded == {
        "maximumEntries": 256,
        "boundSource": "GenerationLeaseRegistryV1.maximumActiveLeaseCount",
        "receipt": ["retainedEpochs+prunedEpochs", "activeRetainedEpochs", "uncertainRetainedGenerationIDs"],
        "intent": ["candidateEpochs+retainedEpochs", "activeRetainedEpochs", "uncertainRetainedGenerationIDs", "expectedRetiredGenerationIDs", "desiredRetiredGenerationIDs"],
    }, "receipt/intent collection bounds mismatch")
    require(prune["pruneTransaction"]["receiptPublication"]["directAPI"] == "publishPruneReceipt(_:)" and prune["pruneTransaction"]["receiptPublication"]["intentBoundAPI"] == "publishPruneReceipt(_:completing:)", "prune receipt publication split mismatch")
    require(prune["backupReplaceRestore"]["sourceLeaseMayBecomeDestinationLiveLease"] is False, "source lease imported as live")
    require(prune["backupReplaceRestore"]["startupReconciliationBeforeValidatedSessionActivation"] is True and prune["backupReplaceRestore"]["validatedCoordinatorConstructionAndReplacementRequired"] is True, "startup session activation is not fail-closed")
    require(prune["backupReplaceRestore"]["restoreWithoutLeaseDrainProof"] == "DISABLE_PRUNING_UNTIL_NEXT_COLD_LAUNCH", "restore-without-drain prune hold absent")
    require(prune["lifecycle"] == {"schemaMigrationDelta": False, "deleteBehaviorDelta": False, "openExportOfLeaseState": False, "backgroundDaemon": False, "serverOrRemoteProvider": False, "vectorClock": False, "downgradeDisposition": "FORWARD_FIX_ONLY"}, "lifecycle scope mismatch")
    corpus = docs[CORPUS_DOC]
    require([row["testMethod"] for row in corpus["evidence"]] == TEST_METHODS and corpus["exactFiveTestMethods"] is True, "five evidence mapping mismatch")
    for doc_path, schema_path in ((LEASE_DOC, LEASE_SCHEMA), (FENCE_DOC, FENCE_SCHEMA), (PRUNE_DOC, PRUNE_SCHEMA), (CORPUS_DOC, CORPUS_SCHEMA)):
        validate_instance(docs[doc_path], load(schema_path))


def verify_manifest() -> None:
    manifest = load(MANIFEST); verify_seal(manifest, MANIFEST); verify_flags(manifest, MANIFEST)
    require(manifest["authority"] == authority(), "manifest authority mismatch")
    require(manifest["pathFence"] == PATH_FENCE and manifest["pathFenceCount"] == 24, "exact 24-path fence mismatch")
    require(manifest["sourcePaths"] == SOURCE_PATHS and manifest["sourcePathCount"] == 12, "exact 12-source closure mismatch")
    require(manifest["toolingPaths"] == TOOL_PATHS and manifest["toolingPathCount"] == 12, "exact 12-tool closure mismatch")
    require(manifest["artifactCount"] == 23 and [row["path"] for row in manifest["artifacts"]] == MANIFEST_INPUT_PATHS, "exact 23-input closure mismatch")
    require(manifest["artifactSetDigest"] == sha(pretty(manifest["artifacts"])), "artifact set mismatch")
    for row in manifest["artifacts"]:
        data = (ROOT / row["path"]).read_bytes(); require((row["bytes"], row["sha256"]) == (len(data), sha(data)), f"manifest binding mismatch: {row['path']}")


def require_tokens(relative: str, tokens: list[str]) -> None:
    text = (ROOT / relative).read_text(encoding="utf-8")
    for token in tokens: require(token in text, f"{relative}: missing source token {token!r}")


def verify_sources() -> None:
    # Final source-specific token bindings are deliberately exact and kept in
    # one table so future renames cannot silently retain tooling credit.
    bindings = {
        SOURCE_PATHS[0]: ["enum PersistentSchemaV4", "PersistentSchemaReleaseRegistryV1"],
        SOURCE_PATHS[1]: ["generationLeaseDirectory", "generationLeaseControl", "generationLeaseControlTemporary", "generationLeaseOwnerLock", "isExcludedFromBackup: true"],
        SOURCE_PATHS[2]: ["GenerationEpochV1", "GenerationLeaseRoleV1", "GenerationLeaseTokenV1", "GenerationPrunePolicyV1", "GenerationPruneDispositionV1", "GenerationPruneReceiptV1", "ownerLivenessUncertain", "GenerationPruneIntentPhaseV1", "GenerationPruneIntentV1", "GenerationLeaseRegistryFailureV1", "productionRetainedInactiveAcceptedGenerationCount = 2"],
        SOURCE_PATHS[3]: ["GenerationLeaseRegistryV1", "GenerationLeaseHandleV1", "StaleWriterFenceV1", "maximumActiveLeaseCount = 256", "maximumOwnerCount = 64", "maximumControlFileBytes = 4 * 1024 * 1024", "func acquire(", "func acquireHandle(", "func release(", "func validateActive(", "func reconcileAbandonedOwners()", "func activeEpochs()", "withExclusiveGenerationMutationLock", "withExclusiveGenerationCommitLock", "verifyAfterOperation: false", "func withAuthorizedCommit"],
        SOURCE_PATHS[4]: ["makeGenerationLeaseRegistry(", "currentGenerationEpoch()", "makeWriterFence(", "reconcileGenerationLeasesAndPrune(", "recoverPruneLocked(", "acceptedGenerationEpoch(", "withExclusiveGenerationMutationLock", "StoreGenerationPruneFaultBoundaryV1", "reachPruneBoundary(.prepared)", "reachPruneBoundary(.bytesRemoved)", "reachPruneBoundary(.retiredPointerPublished)", "reachPruneBoundary(.receiptPublished)"],
        SOURCE_PATHS[5]: ["reconcileGenerationLeasesForStartup()", "reconcileGenerationLeasesAndPrune(", "pruningEnabled: false", "validatingSession: session", "activateValidating(session: session)"],
        SOURCE_PATHS[6]: ["GenerationLeaseHandleV1", "StaleWriterFenceV1", "acquireHandle(", "role: .writer", "writerLeaseToken:", "validatingSession session:", "func activateValidating(session:"],
        SOURCE_PATHS[7]: ["WorkspaceWriterAdapterV1", "ModelContext"],
        SOURCE_PATHS[8]: ["StaleWriterFenceV1", "withAuthorizedRecovery", "withAuthorizedCommit", "validateCurrent()"],
        SOURCE_PATHS[9]: ["MutationReceiptRecoveryServiceV1", "recoverBeforeWriterActivation()", "store.withAuthorizedRecovery"],
        SOURCE_PATHS[10]: ["WholeSignDeletionService", "StaleWriterFenceV1", "writerLeaseHandle", "withAuthorizedCommit", "modelContext.save()"],
    }
    for relative, tokens in bindings.items(): require_tokens(relative, tokens)
    service_text = (ROOT / SOURCE_PATHS[3]).read_text(encoding="utf-8")
    contracts_text = (ROOT / SOURCE_PATHS[2]).read_text(encoding="utf-8")
    require(contracts_text.count("GenerationLeaseRegistryV1.maximumActiveLeaseCount") >= 8, "receipt/intent bounds are not tied to registry maximum")
    require(service_text.count("func publishPruneReceipt(") == 2, "direct and intent-bound prune receipt overloads required")
    require("UInt32(RENAME_EXCL)" in service_text and "verifyControlFilePolicy(" in service_text and "adoption path" in service_text, "control-file publication/retry source proof missing")
    test_text = (ROOT / SOURCE_PATHS[-1]).read_text(encoding="utf-8")
    found = [method for method in TEST_METHODS if f"func {method}(" in test_text]
    require(found == TEST_METHODS and test_text.count("func testV9_08") == 5, "exact five G/A/H/I/R tests missing")
    require("StoreGenerationPruneFaultBoundaryV1\n            .allCases" in test_text and "makeRealPruneFixture(" in test_text, "four real prune fault-boundary loop missing")
    require(all(token in test_text for token in ("BackupExportService(", "BackupImportService(", "BackupRestoreService(", "backupSchemaVersion, 3")), "production backup/import/restore reconciliation evidence missing")
    production = "\n".join((ROOT / path).read_text(encoding="utf-8") for path in SOURCE_PATHS[:-1])
    for token in ("CloudKit", "CKRecord", "serverCursor", "serverRevision", "vectorClock", "remoteProvider", "backgroundDaemon"):
        require(token not in production, f"prohibited production token present: {token}")


def verify_hostile_rejection() -> None:
    schema = load(LEASE_SCHEMA); instance = load(LEASE_DOC); mutations = []
    extra = copy.deepcopy(instance); extra["unexpected"] = True; mutations.append(extra)
    missing = copy.deepcopy(instance); del missing["registry"]; mutations.append(missing)
    changed = copy.deepcopy(instance); changed["leaseRoles"][0] = "REMOTE"; mutations.append(changed)
    digest = copy.deepcopy(instance); digest["artifactDigest"] = "z" * 64; mutations.append(digest)
    for index, mutation in enumerate(mutations):
        try: validate_instance(mutation, schema)
        except VerificationError: continue
        raise VerificationError(f"hostile schema mutation accepted: {index}")


def verify_python_and_generator() -> None:
    for relative in (CONTRACT_SCRIPT, "Scripts/v23/generate_p02_c04_contracts.py", "Scripts/v23/verify_p02_c04_contracts.py"):
        ast.parse((ROOT / relative).read_text(encoding="utf-8"), filename=relative)
    result = subprocess.run([sys.executable, "-B", str(ROOT / "Scripts/v23/generate_p02_c04_contracts.py"), "--check", "--root", str(ROOT)], cwd=ROOT, capture_output=True, text=True)
    require(result.returncode == 0, f"generator --check failed:\n{result.stdout}{result.stderr}")


def main() -> int:
    try:
        verify_generated(); verify_contracts(); verify_manifest(); verify_sources(); verify_hostile_rejection(); verify_python_and_generator()
    except (VerificationError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"V23-P02-C04 verification failed: {error}", file=sys.stderr); return 1
    print("V23-P02-C04 hostile static verification passed: 24 fence paths, 23 sealed inputs, 4 strict schemas, 5 evidence tests"); return 0

if __name__ == "__main__": raise SystemExit(main())
