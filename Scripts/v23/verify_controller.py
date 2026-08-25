#!/usr/bin/env python3
"""Deterministic C04 controller contract and hostile/interruption verification."""

from __future__ import annotations

import copy
import hashlib
import json
from datetime import datetime, timezone
from typing import Any, Callable

from controller_contracts import (
    Admission,
    AuthorityBindings,
    CapacityEvidence,
    ClaimDisposition,
    ContractError,
    ControllerResult,
    ControllerSelection,
    DispatchProof,
    ExecutionFence,
    ExecutionMode,
    HostedWorkIdentity,
    OccupancySnapshot,
    PipelineStage,
    Pool,
    RecoveryDisposition,
    TransferDisposition,
    WorkKind,
    canonical_digest,
    classify_recovery,
    evaluate_active_dispatch_set,
    evaluate_admission,
    evaluate_fail_fast,
    evaluate_hosted_dispatch,
    evaluate_pipeline,
    validate_execution_fence,
)


NOW = datetime(2026, 8, 25, 14, 0, tzinfo=timezone.utc)


def digest(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def selection(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": "ControllerSelectionV1",
        "schemaVersion": 1,
        "cardID": "V23-P00-C04",
        "attemptID": 1,
        "candidateHead": "1" * 40,
        "candidateTree": "2" * 40,
        "branch": "phase/v23-expansion",
        "workKind": "PRODUCT_OFFICIAL",
        "requestedPool": "STANDARD_GITHUB",
        "requestedJobs": 5,
        "failFast": True,
        "exhaustiveDiagnostics": False,
        "transportActivated": True,
    }
    value.update(changes)
    return value


def capacity(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": "HostedCapacityEvidenceV1",
        "schemaVersion": 1,
        "pool": "STANDARD_GITHUB",
        "generation": 1,
        "enforcementMechanism": "ACCOUNT",
        "provedHardLimit": 5,
        "activeLeases": 0,
        "externalOccupancyKnown": True,
        "externalOccupancy": 0,
        "providerConfigured": True,
        "observedAt": "2026-08-25T13:59:00Z",
        "validThrough": "2026-08-25T14:05:00Z",
    }
    value.update(changes)
    return value


def authority(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": "ControllerAuthorityBindingsV1",
        "schemaVersion": 1,
        "cardID": "V23-P00-C04",
        "attemptID": 1,
        "branch": "phase/v23-expansion",
        "candidateHead": "1" * 40,
        "candidateTree": "2" * 40,
        "packageDigest": digest("package"),
        "registerDigest": digest("register"),
        "graphDigest": digest("graph"),
        "lineageDigest": digest("lineage"),
        "authorityDigest": digest("authority"),
        "a00ReceiptDigest": digest("a00"),
        "overrideDigest": digest("override"),
        "policyDigest": digest("policy"),
        "enrollmentDigest": None,
        "pathFenceDigest": digest("path-fence"),
        "predecessorDigest": digest("predecessor"),
        "authorityGeneration": 1,
        "enrollmentGeneration": 0,
        "genesisGeneration": 0,
        "projectionGeneration": 0,
        "occupancyGeneration": 0,
        "highWaterGeneration": 0,
        "writerGeneration": 0,
        "transportGenesisDigest": None,
        "projectionDigest": None,
        "occupancyGenesisDigest": None,
        "highWaterDigest": None,
        "hostedDispatchEnabled": False,
        "acceptanceEnabled": False,
        "releaseCredit": False,
    }
    value.update(changes)
    return value


def occupancy(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": "ObservedExternalHostedOccupancySetV1",
        "schemaVersion": 1,
        "pool": "STANDARD_GITHUB",
        "generation": 1,
        "previousGeneration": 0,
        "policyGeneration": 1,
        "scanComplete": True,
        "queryCursor": "complete:1",
        "v23WorkIdentities": [],
        "externalWorkIdentities": [],
        "unknownWorkIdentities": [],
        "observedAt": "2026-08-25T14:00:00Z",
        "genesisDigest": digest("occupancy-genesis"),
    }
    value.update(changes)
    return value


def proof(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": "ControllerDispatchProofBundleV1",
        "schemaVersion": 1,
        "enrollmentActive": True,
        "workflowCommit": "3" * 40,
        "controllerWorkflowDigest": digest("controller-workflow"),
        "workerWorkflowDigest": digest("worker-workflow"),
        "transportGenesisActive": True,
        "occupancyGenesisActive": True,
        "projectionGenesisActive": True,
        "signerPresent": True,
        "signatureValid": True,
        "domainValid": True,
        "highWaterWitnessValid": True,
        "policyGeneration": 1,
        "enrollmentGeneration": 1,
        "genesisGeneration": 1,
        "projectionGeneration": 1,
        "occupancyGeneration": 1,
        "highWaterGeneration": 1,
        "occupancyScanComplete": True,
        "unknownOccupancy": False,
        "hostedDispatchEnabled": True,
        "providerCommands": 0,
        "providerResponses": 0,
        "providerEffects": 0,
    }
    value.update(changes)
    return value


def fence(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": "LocalExecutionFenceV1",
        "schemaVersion": 1,
        "cardID": "V23-P00-C04",
        "attemptID": 1,
        "mode": "TARGETED_NON_ACCEPTING",
        "planDigest": digest("plan"),
        "fenceDigest": digest("fence"),
        "leaseNonce": "nonce-1",
        "acceptanceEnabled": False,
        "releaseCredit": False,
    }
    value.update(changes)
    return value


def work_identity(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": "HostedWorkIdentityV1",
        "schemaVersion": 1,
        "cardID": "V23-P00-C04",
        "attemptID": 1,
        "candidateHead": "1" * 40,
        "candidateTree": "2" * 40,
        "cellID": "cell-1",
        "pool": "STANDARD_GITHUB",
        "workKind": "CONTROLLER_GUARD",
        "nonce": "nonce-1",
    }
    value.update(changes)
    return value


def expect_error(action: Callable[[], object], fragment: str) -> None:
    try:
        action()
    except ContractError as error:
        if fragment not in str(error):
            raise AssertionError(f"Expected {fragment!r} in {error!r}") from error
    else:
        raise AssertionError(f"Expected ContractError containing {fragment!r}")


def assert_no_credit(value: dict[str, Any]) -> None:
    assert value.get("acceptanceCredit") is False
    assert value.get("releaseCredit") is False


def main() -> int:
    cases = 0

    # Baseline capacity arithmetic remains deterministic and backward-compatible.
    selected = ControllerSelection.parse(selection())
    evidence = CapacityEvidence.parse(capacity())
    admitted = evaluate_admission(selected, evidence, now=NOW)
    assert admitted["admission"] == Admission.ADMIT.value
    assert admitted["effectiveCapacity"] == 5
    assert admitted["hostedDispatchStatus"] == ControllerResult.HOSTED_DISPATCH_BLOCKED.value
    assert admitted["dispatchAuthorized"] is False
    assert_no_credit(admitted)
    cases += 1

    unproved = CapacityEvidence.parse(capacity(enforcementMechanism="UNPROVED", provedHardLimit=None))
    blocked = evaluate_admission(selected, unproved, now=NOW)
    assert blocked["admission"] == Admission.BLOCK.value
    assert "HARD_CAP_ENFORCEMENT_UNPROVED" in blocked["reasons"]
    cases += 1

    unknown = CapacityEvidence.parse(capacity(externalOccupancyKnown=False, externalOccupancy=None))
    blocked_unknown = evaluate_admission(selected, unknown, now=NOW)
    assert blocked_unknown["admission"] == Admission.BLOCK.value
    assert "EXTERNAL_OCCUPANCY_UNKNOWN" in blocked_unknown["reasons"]
    cases += 1

    queued = evaluate_admission(
        selected,
        CapacityEvidence.parse(capacity(activeLeases=3, externalOccupancy=1)),
        now=NOW,
    )
    assert queued["admission"] == Admission.QUEUE.value
    assert queued["availableCapacity"] == 1
    cases += 1

    # The nine-path C04 engine cannot dispatch without every authority plane.
    bound = AuthorityBindings.parse(authority())
    denied = evaluate_hosted_dispatch(
        selected,
        evidence,
        authority=bound,
        proof=None,
        occupancy=None,
        now=NOW,
    )
    assert denied["result"] in {
        ControllerResult.ENROLLMENT_REQUIRED.value,
        ControllerResult.GENESIS_REQUIRED.value,
    }
    assert denied["dispatchAuthorized"] is False
    assert denied["providerCommands"] == 0
    assert_no_credit(denied)
    cases += 1

    no_authority = evaluate_hosted_dispatch(
        selected, evidence, authority=None, proof=None, occupancy=None, now=NOW
    )
    assert no_authority["result"] == ControllerResult.HOSTED_DISPATCH_BLOCKED.value
    assert no_authority["providerEffects"] == 0
    cases += 1

    # A hypothetical future proof is accepted only as an authorization result;
    # this local module still emits a zero-provider-effect decision.
    active_authority = AuthorityBindings.parse(
        authority(
            enrollmentDigest=digest("enrollment"),
            enrollmentGeneration=1,
            genesisGeneration=1,
            projectionGeneration=1,
            occupancyGeneration=1,
            highWaterGeneration=1,
            transportGenesisDigest=digest("transport"),
            projectionDigest=digest("projection"),
            occupancyGenesisDigest=digest("occupancy"),
            highWaterDigest=digest("high-water"),
            hostedDispatchEnabled=True,
        )
    )
    active = evaluate_hosted_dispatch(
        selected,
        evidence,
        authority=active_authority,
        proof=DispatchProof.parse(proof()),
        occupancy=OccupancySnapshot.parse(occupancy()),
        now=NOW,
    )
    assert active["result"] == ControllerResult.HOSTED_DISPATCH_AUTHORIZED.value
    assert active["providerCommands"] == 0
    assert active["providerResponses"] == 0
    assert active["providerEffects"] == 0
    assert_no_credit(active)
    cases += 1

    # Occupancy is generation-CAS and unknown work retains its debit.
    unknown_snapshot = OccupancySnapshot.parse(
        occupancy(unknownWorkIdentities=["external-run-1"])
    )
    unknown_decision = evaluate_hosted_dispatch(
        selected,
        evidence,
        authority=active_authority,
        proof=DispatchProof.parse(proof(unknownOccupancy=True)),
        occupancy=unknown_snapshot,
        now=NOW,
    )
    assert unknown_decision["result"] == ControllerResult.CAPACITY_CONFIGURATION_REQUIRED.value
    assert "UNKNOWN_OCCUPANCY_RETAIN_DEBIT" in unknown_decision["reasons"]
    assert unknown_decision["providerEffects"] == 0
    cases += 1

    expect_error(lambda: OccupancySnapshot.parse(occupancy(generation=2, previousGeneration=0)), "advance exactly")
    expect_error(
        lambda: OccupancySnapshot.parse(occupancy(externalWorkIdentities=["same"], unknownWorkIdentities=["same"])),
        "multiple classifications",
    )
    cases += 2

    # Hostile selection/schema inputs are rejected, not coerced.
    expect_error(lambda: ControllerSelection.parse(selection(candidateHead="ABC")), "candidateHead")
    expect_error(lambda: ControllerSelection.parse(selection(requestedJobs=True)), "requestedJobs")
    expect_error(lambda: ControllerSelection.parse({**selection(), "unexpected": 1}), "unexpected")
    expect_error(lambda: ControllerSelection.parse(selection(branch="main")), "phase/v23-expansion")
    expect_error(
        lambda: ControllerSelection.parse(
            selection(workKind="PRODUCT_DIAGNOSTIC", failFast=True, exhaustiveDiagnostics=False)
        ),
        "Diagnostic work",
    )
    expect_error(lambda: AuthorityBindings.parse(authority(acceptanceEnabled=True)), "acceptance")
    cases += 6

    # Canonicalization is order-independent but mutation-sensitive.
    original = selection()
    reordered = json.loads(json.dumps(original, sort_keys=True))
    assert canonical_digest(original) == canonical_digest(reordered)
    mutated = copy.deepcopy(original)
    mutated["requestedJobs"] = 4
    assert canonical_digest(original) != canonical_digest(mutated)
    cases += 1

    # Projection limits, duplicate identities, and cross-authority replay.
    one = HostedWorkIdentity.parse(work_identity())
    projection = evaluate_active_dispatch_set((one,), authority=bound)
    assert projection["valid"] is True
    assert projection["standardGithubActive"] == 1
    assert_no_credit(projection)
    duplicate = evaluate_active_dispatch_set((one, one), authority=bound)
    assert duplicate["valid"] is False
    assert "DUPLICATE_ACTIVE_WORK_IDENTITY" in duplicate["reasons"]
    foreign = HostedWorkIdentity.parse(work_identity(cellID="foreign", cardID="V23-P00-C05"))
    foreign_result = evaluate_active_dispatch_set((foreign,), authority=bound)
    assert foreign_result["valid"] is False
    assert "ACTIVE_PROJECTION_CARD_ATTEMPT_MISMATCH" in foreign_result["reasons"]
    cases += 3

    # Official and diagnostic fences cannot share mode/nonce semantics.
    official_fence = ExecutionFence.parse(fence())
    official_check = validate_execution_fence(
        selected, official_fence, expected_mode=ExecutionMode.TARGETED_NON_ACCEPTING
    )
    assert official_check["valid"] is True
    diagnostic_selection = ControllerSelection.parse(
        selection(
            workKind="PRODUCT_DIAGNOSTIC",
            requestedPool="GETMAC",
            requestedJobs=3,
            failFast=False,
            exhaustiveDiagnostics=True,
        )
    )
    diagnostic_fence = ExecutionFence.parse(
        fence(mode="DIAGNOSTIC_NON_ACCEPTING", leaseNonce="diagnostic-nonce")
    )
    diagnostic_check = validate_execution_fence(
        diagnostic_selection,
        diagnostic_fence,
        expected_mode=ExecutionMode.DIAGNOSTIC_NON_ACCEPTING,
        other_lease_nonces=("official-nonce",),
    )
    assert diagnostic_check["valid"] is True
    replay_check = validate_execution_fence(
        diagnostic_selection,
        ExecutionFence.parse(fence(mode="DIAGNOSTIC_NON_ACCEPTING", leaseNonce="official-nonce")),
        expected_mode=ExecutionMode.DIAGNOSTIC_NON_ACCEPTING,
        other_lease_nonces=("official-nonce",),
    )
    assert replay_check["valid"] is False
    assert "LEASE_NONCE_REUSED" in replay_check["reasons"]
    cases += 3

    # Claim/transfer ordering prevents a product cell from starting early.
    pending_pipeline = evaluate_pipeline(
        selected,
        claim=ClaimDisposition.NOT_CREATED,
        transfer=None,
        stage=PipelineStage.PRODUCT_CELL,
        queue_open=True,
    )
    assert pending_pipeline["result"] == ControllerResult.INFRASTRUCTURE_PENDING.value
    ready_pipeline = evaluate_pipeline(
        selected,
        claim=ClaimDisposition.CREATED_MATCHING,
        transfer=TransferDisposition.TRANSFER_WON,
        stage=PipelineStage.PRODUCT_CELL,
        queue_open=True,
    )
    assert ready_pipeline["result"] == ControllerResult.READY_LOCAL_NONACCEPTING.value
    assert ready_pipeline["dispatchAuthorized"] is False
    cases += 2

    # Official failure stops new dispatches; diagnostics remain exhaustive but non-accepting.
    failfast = evaluate_fail_fast(
        mode=ExecutionMode.OFFICIAL_ACCEPTANCE,
        first_failure="PRODUCT_CELL_FAILED",
        stop_intent_written=True,
        new_dispatch_count=0,
        sibling_observations_reconciled=True,
        late_observations_reconciled=True,
    )
    assert failfast["result"] == ControllerResult.PRODUCT_PROOF_CONTRADICTION.value
    assert failfast["newDispatchAllowed"] is False
    diagnostic_failfast = evaluate_fail_fast(
        mode=ExecutionMode.DIAGNOSTIC_NON_ACCEPTING,
        first_failure="INFRASTRUCTURE_TIMEOUT",
        stop_intent_written=True,
        new_dispatch_count=0,
        sibling_observations_reconciled=True,
        late_observations_reconciled=True,
    )
    assert diagnostic_failfast["result"] == ControllerResult.DIAGNOSTIC_COMPLETE_NON_ACCEPTING.value
    incomplete_stop = evaluate_fail_fast(
        mode=ExecutionMode.OFFICIAL_ACCEPTANCE,
        first_failure="PRODUCT_CELL_FAILED",
        stop_intent_written=False,
        new_dispatch_count=1,
        sibling_observations_reconciled=False,
        late_observations_reconciled=False,
    )
    assert incomplete_stop["result"] == ControllerResult.INFRASTRUCTURE_PENDING.value
    cases += 3

    # Interruption recovery permits only exact absent retry, matching adoption,
    # or divergent quarantine; it never grants credit.
    state = digest("state")
    before = classify_recovery(
        expected_state_digest=state,
        observed_state_digest=state,
        expected_generation=2,
        observed_generation=2,
        effect_state="ABSENT",
        provider_commands=0,
        provider_responses=0,
        provider_effects=0,
    )
    assert before["disposition"] == RecoveryDisposition.BEFORE_EFFECT_AT_EXPECTED_GENERATION.value
    assert before["retryExactSameBytes"] is True
    applied = classify_recovery(
        expected_state_digest=state,
        observed_state_digest=state,
        expected_generation=2,
        observed_generation=2,
        effect_state="APPLIED",
        provider_commands=1,
        provider_responses=1,
        provider_effects=1,
    )
    assert applied["disposition"] == RecoveryDisposition.APPLIED_MATCHING.value
    assert applied["retryExactSameBytes"] is False
    divergent = classify_recovery(
        expected_state_digest=state,
        observed_state_digest=digest("different"),
        expected_generation=2,
        observed_generation=3,
        effect_state="UNKNOWN",
        provider_commands=1,
        provider_responses=0,
        provider_effects=0,
    )
    assert divergent["disposition"] == RecoveryDisposition.DIVERGENT_OR_AMBIGUOUS.value
    assert divergent["retryExactSameBytes"] is False
    for result in (before, applied, divergent):
        assert_no_credit(result)
    cases += 3

    print(
        json.dumps(
            {
                "result": "PASS",
                "cardID": "V23-P00-C04",
                "caseCount": cases,
                "standardGithubConfiguredCeiling": 5,
                "getMacConfiguredCeiling": 3,
                "unknownExternalOccupancyFailsClosed": True,
                "hostedDispatchRequiresAllProofPlanes": True,
                "zeroProviderEffectOnEveryLocalDecision": True,
                "diagnosticsNeverAccept": True,
                "acceptanceCredit": False,
                "releaseCredit": False,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
