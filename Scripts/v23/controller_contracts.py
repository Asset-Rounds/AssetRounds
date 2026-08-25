#!/usr/bin/env python3
"""Deterministic, dependency-free contracts for the V23 acceptance controller."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from typing import Any


SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
CARD_PATTERN = re.compile(r"^V23-P\d{2}-C\d{2}$")
BRANCH = "phase/v23-expansion"
POOL_CEILINGS = {"STANDARD_GITHUB": 5, "GETMAC": 3}


class ContractError(ValueError):
    """A fail-closed controller contract violation."""


class Pool(str, Enum):
    STANDARD_GITHUB = "STANDARD_GITHUB"
    GETMAC = "GETMAC"


class WorkKind(str, Enum):
    PRODUCT_OFFICIAL = "PRODUCT_OFFICIAL"
    PRODUCT_DIAGNOSTIC = "PRODUCT_DIAGNOSTIC"
    PROTECTED_RELEASE = "PROTECTED_RELEASE"


class HostedWorkKind(str, Enum):
    """Closed hosted-work set from the C04 capacity and ledger laws."""

    PRODUCT_PIPELINE = "PRODUCT_PIPELINE"
    PROTECTED_RELEASE_PIPELINE = "PROTECTED_RELEASE_PIPELINE"
    PROTECTED_RELEASE_RECONCILIATION = "PROTECTED_RELEASE_RECONCILIATION"
    CONTROLLER_GUARD = "CONTROLLER_GUARD"
    POLICY_ACTIVATION_GUARD = "POLICY_ACTIVATION_GUARD"
    CAPACITY_EVIDENCE_RENEWAL_GUARD = "CAPACITY_EVIDENCE_RENEWAL_GUARD"
    ROLLOVER_SELF_TEST = "ROLLOVER_SELF_TEST"


class EnforcementMechanism(str, Enum):
    PLATFORM = "PLATFORM"
    POOL = "POOL"
    ACCOUNT = "ACCOUNT"
    UNPROVED = "UNPROVED"


class Admission(str, Enum):
    ADMIT = "ADMIT"
    QUEUE = "QUEUE"
    BLOCK = "BLOCK"


class ControllerResult(str, Enum):
    READY_LOCAL_NONACCEPTING = "READY_LOCAL_NONACCEPTING"
    HOSTED_DISPATCH_AUTHORIZED = "HOSTED_DISPATCH_AUTHORIZED"
    HOSTED_DISPATCH_BLOCKED = "HOSTED_DISPATCH_BLOCKED"
    CAPACITY_CONFIGURATION_REQUIRED = "CAPACITY_CONFIGURATION_REQUIRED"
    UNKNOWN_OCCUPANCY_RETAIN_DEBIT = "UNKNOWN_OCCUPANCY_RETAIN_DEBIT"
    ENROLLMENT_REQUIRED = "ENROLLMENT_REQUIRED"
    GENESIS_REQUIRED = "GENESIS_REQUIRED"
    STALE_OR_DIVERGENT_AUTHORITY = "STALE_OR_DIVERGENT_AUTHORITY"
    INFRASTRUCTURE_PENDING = "INFRASTRUCTURE_PENDING"
    PRODUCT_PROOF_CONTRADICTION = "PRODUCT_PROOF_CONTRADICTION"
    SUPERSEDED_NONPRODUCT = "SUPERSEDED_NONPRODUCT"
    DIAGNOSTIC_COMPLETE_NON_ACCEPTING = "DIAGNOSTIC_COMPLETE_NON_ACCEPTING"


class RecoveryDisposition(str, Enum):
    BEFORE_EFFECT_AT_EXPECTED_GENERATION = "BEFORE_EFFECT_AT_EXPECTED_GENERATION"
    APPLIED_MATCHING = "APPLIED_MATCHING"
    DIVERGENT_OR_AMBIGUOUS = "DIVERGENT_OR_AMBIGUOUS"


class ExecutionMode(str, Enum):
    TARGETED_NON_ACCEPTING = "TARGETED_NON_ACCEPTING"
    DIAGNOSTIC_NON_ACCEPTING = "DIAGNOSTIC_NON_ACCEPTING"
    OFFICIAL_ACCEPTANCE = "OFFICIAL_ACCEPTANCE"


class ClaimDisposition(str, Enum):
    EXPECTED_ABSENT = "EXPECTED_ABSENT"
    CREATED_MATCHING = "CREATED_MATCHING"
    NOT_CREATED = "NOT_CREATED"
    OBSERVED_CONFLICT = "OBSERVED_CONFLICT"


class TransferDisposition(str, Enum):
    TRANSFER_WON = "TRANSFER_WON"
    NOOP_WON = "NOOP_WON"
    RETRY_EPOCH_1 = "RETRY_EPOCH_1"
    INFRASTRUCTURE_TERMINAL = "INFRASTRUCTURE_TERMINAL"


class PipelineStage(str, Enum):
    CLAIM_ONLY_GUARD = "CLAIM_ONLY_GUARD"
    PRODUCT_CELL = "PRODUCT_CELL"


def canonical_bytes(value: Any) -> bytes:
    try:
        encoded = json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    except (TypeError, ValueError) as error:
        raise ContractError("Value cannot be canonically encoded as JSON") from error
    return (encoded + "\n").encode("utf-8")


def canonical_digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def require_keys(value: dict[str, Any], expected: set[str], subject: str) -> None:
    if not isinstance(value, dict):
        raise ContractError(f"{subject} must be a JSON object")
    observed = set(value)
    if observed != expected:
        raise ContractError(
            f"{subject} keys differ: missing={sorted(expected - observed)}, "
            f"unexpected={sorted(observed - expected)}"
        )


def _require_bool(value: Any, subject: str) -> bool:
    if not isinstance(value, bool):
        raise ContractError(f"{subject} must be boolean")
    return value


def _require_int(value: Any, subject: str, *, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise ContractError(f"{subject} must be an integer >= {minimum}")
    return value


def _require_sha(value: Any, subject: str) -> str:
    if not isinstance(value, str) or not SHA_PATTERN.fullmatch(value):
        raise ContractError(f"{subject} must be a lowercase 40-character Git SHA")
    return value


def _require_digest(value: Any, subject: str, *, allow_none: bool = False) -> str | None:
    if allow_none and value is None:
        return None
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ContractError(f"{subject} must be a lowercase 64-character SHA-256 digest")
    return value


def _require_string(value: Any, subject: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str) or (not allow_empty and not value):
        raise ContractError(f"{subject} must be a non-empty string")
    return value


def _require_unique_strings(value: Any, subject: str) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise ContractError(f"{subject} must be an array of non-empty strings")
    if len(set(value)) != len(value):
        raise ContractError(f"{subject} must not contain duplicate identities")
    return tuple(value)


def parse_timestamp(value: str, subject: str) -> datetime:
    if not isinstance(value, str):
        raise ContractError(f"{subject} is not an ISO-8601 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError) as error:
        raise ContractError(f"{subject} is not an ISO-8601 timestamp") from error
    if parsed.tzinfo is None:
        raise ContractError(f"{subject} must include a timezone")
    return parsed.astimezone(timezone.utc)


def pool_ceiling(pool: Pool) -> int:
    return POOL_CEILINGS[pool.value]


@dataclass(frozen=True)
class ControllerSelection:
    card_id: str
    attempt_id: int
    candidate_head: str
    candidate_tree: str
    branch: str
    work_kind: WorkKind
    requested_pool: Pool
    requested_jobs: int
    fail_fast: bool
    exhaustive_diagnostics: bool
    transport_activated: bool

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "ControllerSelection":
        require_keys(
            value,
            {
                "schema",
                "schemaVersion",
                "cardID",
                "attemptID",
                "candidateHead",
                "candidateTree",
                "branch",
                "workKind",
                "requestedPool",
                "requestedJobs",
                "failFast",
                "exhaustiveDiagnostics",
                "transportActivated",
            },
            "ControllerSelectionV1",
        )
        if value["schema"] != "ControllerSelectionV1" or value["schemaVersion"] != 1:
            raise ContractError("Unsupported ControllerSelectionV1 version")
        card_id = value["cardID"]
        if not isinstance(card_id, str) or not CARD_PATTERN.fullmatch(card_id):
            raise ContractError("cardID must match V23-PNN-CNN")
        attempt_id = _require_int(value["attemptID"], "attemptID", minimum=1)
        candidate_head = _require_sha(value["candidateHead"], "candidateHead")
        candidate_tree = _require_sha(value["candidateTree"], "candidateTree")
        if value["branch"] != BRANCH:
            raise ContractError(f"Controller selection must target {BRANCH}")
        try:
            work_kind = WorkKind(value["workKind"])
            pool = Pool(value["requestedPool"])
        except (TypeError, ValueError) as error:
            raise ContractError(str(error)) from error
        requested_jobs = _require_int(value["requestedJobs"], "requestedJobs", minimum=1)
        fail_fast = _require_bool(value["failFast"], "failFast")
        exhaustive = _require_bool(value["exhaustiveDiagnostics"], "exhaustiveDiagnostics")
        transport = _require_bool(value["transportActivated"], "transportActivated")
        if work_kind in {WorkKind.PRODUCT_OFFICIAL, WorkKind.PROTECTED_RELEASE}:
            if not fail_fast or exhaustive:
                raise ContractError("Official/release work must be fail-fast and non-exhaustive")
        if work_kind is WorkKind.PRODUCT_DIAGNOSTIC:
            if fail_fast or not exhaustive:
                raise ContractError("Diagnostic work must be exhaustive and non-fail-fast")
        if pool is Pool.GETMAC and work_kind is not WorkKind.PRODUCT_DIAGNOSTIC:
            raise ContractError("GetMac is development-only diagnostic capacity")
        return cls(
            card_id=card_id,
            attempt_id=attempt_id,
            candidate_head=candidate_head,
            candidate_tree=candidate_tree,
            branch=value["branch"],
            work_kind=work_kind,
            requested_pool=pool,
            requested_jobs=requested_jobs,
            fail_fast=fail_fast,
            exhaustive_diagnostics=exhaustive,
            transport_activated=transport,
        )


@dataclass(frozen=True)
class CapacityEvidence:
    pool: Pool
    generation: int
    enforcement_mechanism: EnforcementMechanism
    proved_hard_limit: int | None
    active_leases: int
    external_occupancy_known: bool
    external_occupancy: int | None
    provider_configured: bool
    observed_at: datetime
    valid_through: datetime

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "CapacityEvidence":
        require_keys(
            value,
            {
                "schema",
                "schemaVersion",
                "pool",
                "generation",
                "enforcementMechanism",
                "provedHardLimit",
                "activeLeases",
                "externalOccupancyKnown",
                "externalOccupancy",
                "providerConfigured",
                "observedAt",
                "validThrough",
            },
            "HostedCapacityEvidenceV1",
        )
        if value["schema"] != "HostedCapacityEvidenceV1" or value["schemaVersion"] != 1:
            raise ContractError("Unsupported HostedCapacityEvidenceV1 version")
        try:
            pool = Pool(value["pool"])
            mechanism = EnforcementMechanism(value["enforcementMechanism"])
        except (TypeError, ValueError) as error:
            raise ContractError(str(error)) from error
        generation = _require_int(value["generation"], "generation")
        active_leases = _require_int(value["activeLeases"], "activeLeases")
        hard_limit = value["provedHardLimit"]
        if hard_limit is not None:
            hard_limit = _require_int(hard_limit, "provedHardLimit")
        external = value["externalOccupancy"]
        if external is not None:
            external = _require_int(external, "externalOccupancy")
        known = _require_bool(value["externalOccupancyKnown"], "externalOccupancyKnown")
        if known != (external is not None):
            raise ContractError("external occupancy value/known flag disagree")
        provider = _require_bool(value["providerConfigured"], "providerConfigured")
        observed = parse_timestamp(value["observedAt"], "observedAt")
        valid = parse_timestamp(value["validThrough"], "validThrough")
        if valid <= observed:
            raise ContractError("Capacity evidence validThrough must follow observedAt")
        if mechanism is EnforcementMechanism.UNPROVED and hard_limit not in (None, 0):
            raise ContractError("UNPROVED capacity cannot declare a positive hard limit")
        if mechanism is not EnforcementMechanism.UNPROVED and hard_limit is None:
            raise ContractError("Proved enforcement requires a hard limit")
        return cls(
            pool=pool,
            generation=generation,
            enforcement_mechanism=mechanism,
            proved_hard_limit=hard_limit,
            active_leases=active_leases,
            external_occupancy_known=known,
            external_occupancy=external,
            provider_configured=provider,
            observed_at=observed,
            valid_through=valid,
        )


def evaluate_admission(
    selection: ControllerSelection,
    evidence: CapacityEvidence,
    *,
    now: datetime,
) -> dict[str, Any]:
    """Evaluate pool capacity; hosted dispatch stays separately fail-closed."""

    reasons: list[str] = []
    configured_ceiling = pool_ceiling(evidence.pool)
    if evidence.pool is not selection.requested_pool:
        reasons.append("POOL_EVIDENCE_MISMATCH")
    if not selection.transport_activated:
        reasons.append("TRANSPORT_NOT_ACTIVATED")
    if not evidence.provider_configured:
        reasons.append("PROVIDER_NOT_CONFIGURED")
    if evidence.enforcement_mechanism is EnforcementMechanism.UNPROVED:
        reasons.append("HARD_CAP_ENFORCEMENT_UNPROVED")
    if evidence.proved_hard_limit == 0:
        reasons.append("HARD_CAP_NOT_POSITIVE")
    if evidence.valid_through <= now.astimezone(timezone.utc):
        reasons.append("CAPACITY_EVIDENCE_EXPIRED")
    if not evidence.external_occupancy_known:
        reasons.append("EXTERNAL_OCCUPANCY_UNKNOWN")
    effective_capacity = (
        min(evidence.proved_hard_limit or 0, configured_ceiling)
        if evidence.enforcement_mechanism is not EnforcementMechanism.UNPROVED
        else 0
    )
    occupied = evidence.active_leases + (evidence.external_occupancy or 0)
    available = max(0, effective_capacity - occupied)
    if selection.requested_jobs > configured_ceiling:
        reasons.append("REQUEST_EXCEEDS_CONFIGURED_POOL_CEILING")
    hard_blockers = {
        "POOL_EVIDENCE_MISMATCH",
        "TRANSPORT_NOT_ACTIVATED",
        "PROVIDER_NOT_CONFIGURED",
        "HARD_CAP_ENFORCEMENT_UNPROVED",
        "HARD_CAP_NOT_POSITIVE",
        "CAPACITY_EVIDENCE_EXPIRED",
        "EXTERNAL_OCCUPANCY_UNKNOWN",
        "REQUEST_EXCEEDS_CONFIGURED_POOL_CEILING",
    }
    if hard_blockers.intersection(reasons):
        admission = Admission.BLOCK
    elif selection.requested_jobs > available:
        admission = Admission.QUEUE
        reasons.append("INSUFFICIENT_CURRENT_CAPACITY")
    else:
        admission = Admission.ADMIT
        reasons.append("CAPACITY_AND_POLICY_SATISFIED")
    decision_without_digest = {
        "schema": "ControllerAdmissionDecisionV1",
        "schemaVersion": 1,
        "cardID": selection.card_id,
        "attemptID": selection.attempt_id,
        "candidateHead": selection.candidate_head,
        "candidateTree": selection.candidate_tree,
        "branch": selection.branch,
        "workKind": selection.work_kind.value,
        "pool": selection.requested_pool.value,
        "requestedJobs": selection.requested_jobs,
        "capacityGeneration": evidence.generation,
        "configuredCeiling": configured_ceiling,
        "effectiveCapacity": effective_capacity,
        "observedOccupancy": occupied,
        "availableCapacity": available,
        "admission": admission.value,
        "reasons": reasons,
        "hostedDispatchStatus": ControllerResult.HOSTED_DISPATCH_BLOCKED.value,
        "dispatchAuthorized": False,
        "providerCommands": 0,
        "providerResponses": 0,
        "providerEffects": 0,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }
    return {**decision_without_digest, "decisionDigest": canonical_digest(decision_without_digest)}


@dataclass(frozen=True)
class AuthorityBindings:
    """Immutable authority, digest, and generation tuple for a controller decision."""

    card_id: str
    attempt_id: int
    branch: str
    candidate_head: str
    candidate_tree: str
    package_digest: str
    register_digest: str
    graph_digest: str
    lineage_digest: str
    authority_digest: str
    a00_receipt_digest: str
    override_digest: str
    policy_digest: str
    enrollment_digest: str | None
    path_fence_digest: str
    predecessor_digest: str
    authority_generation: int
    enrollment_generation: int
    genesis_generation: int
    projection_generation: int
    occupancy_generation: int
    high_water_generation: int
    writer_generation: int
    transport_genesis_digest: str | None
    projection_digest: str | None
    occupancy_genesis_digest: str | None
    high_water_digest: str | None
    hosted_dispatch_enabled: bool
    acceptance_enabled: bool
    release_credit: bool

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "AuthorityBindings":
        require_keys(
            value,
            {
                "schema", "schemaVersion", "cardID", "attemptID", "branch",
                "candidateHead", "candidateTree", "packageDigest", "registerDigest",
                "graphDigest", "lineageDigest", "authorityDigest", "a00ReceiptDigest",
                "overrideDigest", "policyDigest", "enrollmentDigest", "pathFenceDigest",
                "predecessorDigest", "authorityGeneration", "enrollmentGeneration",
                "genesisGeneration", "projectionGeneration", "occupancyGeneration",
                "highWaterGeneration", "writerGeneration", "transportGenesisDigest",
                "projectionDigest", "occupancyGenesisDigest", "highWaterDigest",
                "hostedDispatchEnabled", "acceptanceEnabled", "releaseCredit",
            },
            "ControllerAuthorityBindingsV1",
        )
        if value["schema"] != "ControllerAuthorityBindingsV1" or value["schemaVersion"] != 1:
            raise ContractError("Unsupported ControllerAuthorityBindingsV1 version")
        card_id = _require_string(value["cardID"], "cardID")
        if not CARD_PATTERN.fullmatch(card_id):
            raise ContractError("cardID must match V23-PNN-CNN")
        branch = _require_string(value["branch"], "branch")
        if branch != BRANCH:
            raise ContractError(f"Authority branch must be {BRANCH}")
        required_digest_names = (
            "packageDigest", "registerDigest", "graphDigest", "lineageDigest",
            "authorityDigest", "a00ReceiptDigest", "overrideDigest", "policyDigest",
            "pathFenceDigest", "predecessorDigest",
        )
        required_digests = {
            name: _require_digest(value[json_name], json_name)
            for name, json_name in {
                "package_digest": "packageDigest", "register_digest": "registerDigest",
                "graph_digest": "graphDigest", "lineage_digest": "lineageDigest",
                "authority_digest": "authorityDigest", "a00_receipt_digest": "a00ReceiptDigest",
                "override_digest": "overrideDigest", "policy_digest": "policyDigest",
                "path_fence_digest": "pathFenceDigest", "predecessor_digest": "predecessorDigest",
            }.items()
        }
        optional_digests = {
            name: _require_digest(value[json_name], json_name, allow_none=True)
            for name, json_name in {
                "enrollment_digest": "enrollmentDigest", "transport_genesis_digest": "transportGenesisDigest",
                "projection_digest": "projectionDigest", "occupancy_genesis_digest": "occupancyGenesisDigest",
                "high_water_digest": "highWaterDigest",
            }.items()
        }
        generations = {
            name: _require_int(value[json_name], json_name)
            for name, json_name in {
                "authority_generation": "authorityGeneration", "enrollment_generation": "enrollmentGeneration",
                "genesis_generation": "genesisGeneration", "projection_generation": "projectionGeneration",
                "occupancy_generation": "occupancyGeneration", "high_water_generation": "highWaterGeneration",
                "writer_generation": "writerGeneration",
            }.items()
        }
        hosted = _require_bool(value["hostedDispatchEnabled"], "hostedDispatchEnabled")
        acceptance = _require_bool(value["acceptanceEnabled"], "acceptanceEnabled")
        release = _require_bool(value["releaseCredit"], "releaseCredit")
        if acceptance or release:
            raise ContractError("Provisional authority cannot enable acceptance or release credit")
        return cls(
            card_id=card_id,
            attempt_id=_require_int(value["attemptID"], "attemptID", minimum=1),
            branch=branch,
            candidate_head=_require_sha(value["candidateHead"], "candidateHead"),
            candidate_tree=_require_sha(value["candidateTree"], "candidateTree"),
            **required_digests,
            **optional_digests,
            **generations,
            hosted_dispatch_enabled=hosted,
            acceptance_enabled=acceptance,
            release_credit=release,
        )

    def mismatches(self, selection: ControllerSelection) -> list[str]:
        checks = (
            ("CARD_ID_MISMATCH", self.card_id != selection.card_id),
            ("ATTEMPT_ID_MISMATCH", self.attempt_id != selection.attempt_id),
            ("BRANCH_MISMATCH", self.branch != selection.branch),
            ("CANDIDATE_HEAD_MISMATCH", self.candidate_head != selection.candidate_head),
            ("CANDIDATE_TREE_MISMATCH", self.candidate_tree != selection.candidate_tree),
        )
        return [name for name, mismatch in checks if mismatch]


@dataclass(frozen=True)
class OccupancySnapshot:
    """Complete generation-CAS observation of one hosted pool."""

    pool: Pool
    generation: int
    previous_generation: int
    policy_generation: int
    scan_complete: bool
    query_cursor: str
    v23_work_identities: tuple[str, ...]
    external_work_identities: tuple[str, ...]
    unknown_work_identities: tuple[str, ...]
    observed_at: datetime
    genesis_digest: str | None

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "OccupancySnapshot":
        require_keys(
            value,
            {
                "schema", "schemaVersion", "pool", "generation", "previousGeneration",
                "policyGeneration", "scanComplete", "queryCursor", "v23WorkIdentities",
                "externalWorkIdentities", "unknownWorkIdentities", "observedAt", "genesisDigest",
            },
            "ObservedExternalHostedOccupancySetV1",
        )
        if value["schema"] != "ObservedExternalHostedOccupancySetV1" or value["schemaVersion"] != 1:
            raise ContractError("Unsupported occupancy snapshot version")
        try:
            pool = Pool(value["pool"])
        except (TypeError, ValueError) as error:
            raise ContractError(str(error)) from error
        generation = _require_int(value["generation"], "occupancy generation")
        previous = _require_int(value["previousGeneration"], "previous occupancy generation")
        if generation != previous + 1:
            raise ContractError("Occupancy generation must advance exactly one step")
        v23 = _require_unique_strings(value["v23WorkIdentities"], "v23WorkIdentities")
        external = _require_unique_strings(value["externalWorkIdentities"], "externalWorkIdentities")
        unknown = _require_unique_strings(value["unknownWorkIdentities"], "unknownWorkIdentities")
        if set(v23) & set(external) or set(v23) & set(unknown) or set(external) & set(unknown):
            raise ContractError("Occupancy identity cannot occupy multiple classifications")
        return cls(
            pool=pool,
            generation=generation,
            previous_generation=previous,
            policy_generation=_require_int(value["policyGeneration"], "policyGeneration"),
            scan_complete=_require_bool(value["scanComplete"], "scanComplete"),
            query_cursor=_require_string(value["queryCursor"], "queryCursor", allow_empty=True),
            v23_work_identities=v23,
            external_work_identities=external,
            unknown_work_identities=unknown,
            observed_at=parse_timestamp(value["observedAt"], "occupancy observedAt"),
            genesis_digest=_require_digest(value["genesisDigest"], "genesisDigest", allow_none=True),
        )

    @property
    def external_occupancy(self) -> int:
        return len(self.external_work_identities)

    @property
    def unknown_occupancy(self) -> int:
        return len(self.unknown_work_identities)

    @property
    def digest(self) -> str:
        return canonical_digest(
            {
                "schema": "ObservedExternalHostedOccupancySetV1",
                "schemaVersion": 1,
                "pool": self.pool.value,
                "generation": self.generation,
                "previousGeneration": self.previous_generation,
                "policyGeneration": self.policy_generation,
                "scanComplete": self.scan_complete,
                "queryCursor": self.query_cursor,
                "v23WorkIdentities": list(self.v23_work_identities),
                "externalWorkIdentities": list(self.external_work_identities),
                "unknownWorkIdentities": list(self.unknown_work_identities),
                "observedAt": self.observed_at.isoformat().replace("+00:00", "Z"),
                "genesisDigest": self.genesis_digest,
            }
        )


@dataclass(frozen=True)
class DispatchProof:
    """Proof planes required before hosted dispatch can be authorized."""

    enrollment_active: bool
    workflow_commit: str | None
    controller_workflow_digest: str | None
    worker_workflow_digest: str | None
    transport_genesis_active: bool
    occupancy_genesis_active: bool
    projection_genesis_active: bool
    signer_present: bool
    signature_valid: bool
    domain_valid: bool
    high_water_witness_valid: bool
    policy_generation: int
    enrollment_generation: int
    genesis_generation: int
    projection_generation: int
    occupancy_generation: int
    high_water_generation: int
    occupancy_scan_complete: bool
    unknown_occupancy: bool
    hosted_dispatch_enabled: bool
    provider_commands: int
    provider_responses: int
    provider_effects: int

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "DispatchProof":
        require_keys(
            value,
            {
                "schema", "schemaVersion", "enrollmentActive", "workflowCommit",
                "controllerWorkflowDigest", "workerWorkflowDigest", "transportGenesisActive",
                "occupancyGenesisActive", "projectionGenesisActive", "signerPresent",
                "signatureValid", "domainValid", "highWaterWitnessValid", "policyGeneration",
                "enrollmentGeneration", "genesisGeneration", "projectionGeneration",
                "occupancyGeneration", "highWaterGeneration", "occupancyScanComplete",
                "unknownOccupancy", "hostedDispatchEnabled", "providerCommands",
                "providerResponses", "providerEffects",
            },
            "ControllerDispatchProofBundleV1",
        )
        if value["schema"] != "ControllerDispatchProofBundleV1" or value["schemaVersion"] != 1:
            raise ContractError("Unsupported ControllerDispatchProofBundleV1 version")
        commit = value["workflowCommit"]
        if commit is not None:
            commit = _require_sha(commit, "workflowCommit")
        # JSON uses camelCase while the dataclass uses snake_case.
        booleans = {
            name: value[json_name]
            for name, json_name in {
                "enrollment_active": "enrollmentActive",
                "transport_genesis_active": "transportGenesisActive",
                "occupancy_genesis_active": "occupancyGenesisActive",
                "projection_genesis_active": "projectionGenesisActive",
                "signer_present": "signerPresent",
                "signature_valid": "signatureValid",
                "domain_valid": "domainValid",
                "high_water_witness_valid": "highWaterWitnessValid",
                "occupancy_scan_complete": "occupancyScanComplete",
                "unknown_occupancy": "unknownOccupancy",
                "hosted_dispatch_enabled": "hostedDispatchEnabled",
            }.items()
        }
        for name, item in booleans.items():
            booleans[name] = _require_bool(item, name)
        generations = {
            name: _require_int(value[json_name], json_name)
            for name, json_name in {
                "policy_generation": "policyGeneration",
                "enrollment_generation": "enrollmentGeneration",
                "genesis_generation": "genesisGeneration",
                "projection_generation": "projectionGeneration",
                "occupancy_generation": "occupancyGeneration",
                "high_water_generation": "highWaterGeneration",
            }.items()
        }
        counts = {
            name: _require_int(value[json_name], json_name)
            for name, json_name in {
                "provider_commands": "providerCommands",
                "provider_responses": "providerResponses",
                "provider_effects": "providerEffects",
            }.items()
        }
        return cls(
            workflow_commit=commit,
            controller_workflow_digest=_require_digest(value["controllerWorkflowDigest"], "controllerWorkflowDigest", allow_none=True),
            worker_workflow_digest=_require_digest(value["workerWorkflowDigest"], "workerWorkflowDigest", allow_none=True),
            **booleans,
            **generations,
            **counts,
        )


@dataclass(frozen=True)
class ExecutionFence:
    card_id: str
    attempt_id: int
    mode: ExecutionMode
    plan_digest: str
    fence_digest: str
    lease_nonce: str
    acceptance_enabled: bool
    release_credit: bool

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "ExecutionFence":
        require_keys(
            value,
            {
                "schema", "schemaVersion", "cardID", "attemptID", "mode", "planDigest",
                "fenceDigest", "leaseNonce", "acceptanceEnabled", "releaseCredit",
            },
            "LocalExecutionFenceV1",
        )
        if value["schema"] != "LocalExecutionFenceV1" or value["schemaVersion"] != 1:
            raise ContractError("Unsupported LocalExecutionFenceV1 version")
        try:
            mode = ExecutionMode(value["mode"])
        except (TypeError, ValueError) as error:
            raise ContractError(str(error)) from error
        acceptance = _require_bool(value["acceptanceEnabled"], "acceptanceEnabled")
        release = _require_bool(value["releaseCredit"], "releaseCredit")
        if acceptance or release:
            raise ContractError("Local provisional fence cannot grant acceptance or release credit")
        return cls(
            card_id=_require_string(value["cardID"], "cardID"),
            attempt_id=_require_int(value["attemptID"], "attemptID", minimum=1),
            mode=mode,
            plan_digest=_require_digest(value["planDigest"], "planDigest") or "",
            fence_digest=_require_digest(value["fenceDigest"], "fenceDigest") or "",
            lease_nonce=_require_string(value["leaseNonce"], "leaseNonce"),
            acceptance_enabled=acceptance,
            release_credit=release,
        )


@dataclass(frozen=True)
class HostedWorkIdentity:
    card_id: str
    attempt_id: int
    candidate_head: str
    candidate_tree: str
    cell_id: str
    pool: Pool
    work_kind: HostedWorkKind
    nonce: str

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "HostedWorkIdentity":
        require_keys(
            value,
            {
                "schema", "schemaVersion", "cardID", "attemptID", "candidateHead",
                "candidateTree", "cellID", "pool", "workKind", "nonce",
            },
            "HostedWorkIdentityV1",
        )
        if value["schema"] != "HostedWorkIdentityV1" or value["schemaVersion"] != 1:
            raise ContractError("Unsupported HostedWorkIdentityV1 version")
        try:
            pool = Pool(value["pool"])
            work_kind = HostedWorkKind(value["workKind"])
        except (TypeError, ValueError) as error:
            raise ContractError(str(error)) from error
        return cls(
            card_id=_require_string(value["cardID"], "cardID"),
            attempt_id=_require_int(value["attemptID"], "attemptID", minimum=1),
            candidate_head=_require_sha(value["candidateHead"], "candidateHead"),
            candidate_tree=_require_sha(value["candidateTree"], "candidateTree"),
            cell_id=_require_string(value["cellID"], "cellID"),
            pool=pool,
            work_kind=work_kind,
            nonce=_require_string(value["nonce"], "nonce"),
        )

    @property
    def key(self) -> str:
        return f"{self.card_id}:{self.attempt_id}:{self.cell_id}:{self.nonce}"


def _proof_reasons(
    selection: ControllerSelection,
    evidence: CapacityEvidence,
    authority: AuthorityBindings | None,
    proof: DispatchProof | None,
    occupancy: OccupancySnapshot | None,
    *,
    now: datetime,
) -> list[str]:
    reasons: list[str] = []
    if authority is None:
        reasons.append("AUTHORITY_BINDINGS_REQUIRED")
    else:
        reasons.extend(authority.mismatches(selection))
        if not authority.hosted_dispatch_enabled:
            reasons.append("HOSTED_DISPATCH_DISABLED_BY_AUTHORITY")
        if authority.acceptance_enabled or authority.release_credit:
            reasons.append("FORBIDDEN_CREDIT_ENABLED")
        if authority.enrollment_digest is None or authority.enrollment_generation == 0:
            reasons.append("ENROLLMENT_REQUIRED")
        if authority.transport_genesis_digest is None or authority.genesis_generation == 0:
            reasons.append("TRANSPORT_GENESIS_REQUIRED")
        if authority.projection_digest is None or authority.projection_generation == 0:
            reasons.append("PROJECTION_GENESIS_REQUIRED")
        if authority.occupancy_genesis_digest is None or authority.occupancy_generation == 0:
            reasons.append("OCCUPANCY_GENESIS_REQUIRED")
        if authority.high_water_digest is None or authority.high_water_generation == 0:
            reasons.append("HIGH_WATER_WITNESS_REQUIRED")
    if proof is None:
        reasons.append("DISPATCH_PROOF_REQUIRED")
    else:
        if not proof.enrollment_active:
            reasons.append("ENROLLMENT_NOT_ACTIVE")
        if proof.workflow_commit is None or proof.controller_workflow_digest is None or proof.worker_workflow_digest is None:
            reasons.append("WORKFLOW_ENROLLMENT_INCOMPLETE")
        if not proof.transport_genesis_active or not proof.occupancy_genesis_active or not proof.projection_genesis_active:
            reasons.append("TRANSPORT_GENESIS_INCOMPLETE")
        if not proof.signer_present or not proof.signature_valid or not proof.domain_valid:
            reasons.append("SIGNED_PROJECTION_PROOF_INVALID")
        if not proof.high_water_witness_valid:
            reasons.append("HIGH_WATER_WITNESS_INVALID")
        if not proof.occupancy_scan_complete:
            reasons.append("OCCUPANCY_SCAN_INCOMPLETE")
        if proof.unknown_occupancy:
            reasons.append("UNKNOWN_OCCUPANCY_RETAIN_DEBIT")
        if not proof.hosted_dispatch_enabled:
            reasons.append("HOSTED_DISPATCH_DISABLED_BY_PROOF")
        if proof.provider_commands or proof.provider_responses or proof.provider_effects:
            reasons.append("NONZERO_PROVIDER_EFFECT_BEFORE_ADMISSION")
        if authority is not None:
            comparisons = (
                ("POLICY_GENERATION", proof.policy_generation, authority.authority_generation),
                ("ENROLLMENT_GENERATION", proof.enrollment_generation, authority.enrollment_generation),
                ("GENESIS_GENERATION", proof.genesis_generation, authority.genesis_generation),
                ("PROJECTION_GENERATION", proof.projection_generation, authority.projection_generation),
                ("OCCUPANCY_GENERATION", proof.occupancy_generation, authority.occupancy_generation),
                ("HIGH_WATER_GENERATION", proof.high_water_generation, authority.high_water_generation),
            )
            reasons.extend(
                f"{name}_MISMATCH"
                for name, observed, expected in comparisons
                if observed != expected
            )
        if proof.policy_generation != evidence.generation:
            reasons.append("CAPACITY_POLICY_GENERATION_MISMATCH")
        if occupancy is not None and proof.occupancy_generation != occupancy.generation:
            reasons.append("OCCUPANCY_GENERATION_MISMATCH")
    local = evaluate_admission(selection, evidence, now=now)
    if local["admission"] != Admission.ADMIT.value:
        reasons.append(f"LOCAL_CAPACITY_{local['admission']}")
    if selection.work_kind is WorkKind.PROTECTED_RELEASE:
        reasons.append("PROTECTED_RELEASE_NOT_PERMITTED_IN_PROVISIONAL_C04")
    return sorted(set(reasons))


def evaluate_hosted_dispatch(
    selection: ControllerSelection,
    evidence: CapacityEvidence,
    *,
    authority: AuthorityBindings | None,
    proof: DispatchProof | None,
    occupancy: OccupancySnapshot | None,
    now: datetime,
) -> dict[str, Any]:
    """Return a zero-effect dispatch decision; no provider is contacted."""

    reasons = _proof_reasons(selection, evidence, authority, proof, occupancy, now=now)
    if not reasons:
        status = ControllerResult.HOSTED_DISPATCH_AUTHORIZED
        authorized = True
    elif any(
        reason in {"ENROLLMENT_REQUIRED", "ENROLLMENT_NOT_ACTIVE", "WORKFLOW_ENROLLMENT_INCOMPLETE"}
        for reason in reasons
    ):
        status = ControllerResult.ENROLLMENT_REQUIRED
        authorized = False
    elif any("GENESIS" in reason or "PROJECTION" in reason or "HIGH_WATER" in reason for reason in reasons):
        status = ControllerResult.GENESIS_REQUIRED
        authorized = False
    elif any("OCCUPANCY" in reason or "CAPACITY" in reason for reason in reasons):
        status = ControllerResult.CAPACITY_CONFIGURATION_REQUIRED
        authorized = False
    elif "AUTHORITY_BINDINGS_REQUIRED" in reasons and "DISPATCH_PROOF_REQUIRED" in reasons:
        status = ControllerResult.HOSTED_DISPATCH_BLOCKED
        authorized = False
    elif any("MISMATCH" in reason or "AUTHORITY" in reason for reason in reasons):
        status = ControllerResult.STALE_OR_DIVERGENT_AUTHORITY
        authorized = False
    else:
        status = ControllerResult.HOSTED_DISPATCH_BLOCKED
        authorized = False
    decision_without_digest = {
        "schema": "ControllerDispatchDecisionV1",
        "schemaVersion": 1,
        "cardID": selection.card_id,
        "attemptID": selection.attempt_id,
        "candidateHead": selection.candidate_head,
        "candidateTree": selection.candidate_tree,
        "branch": selection.branch,
        "result": status.value,
        "reasons": reasons,
        "dispatchAuthorized": authorized,
        "providerCommands": 0,
        "providerResponses": 0,
        "providerEffects": 0,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }
    return {**decision_without_digest, "decisionDigest": canonical_digest(decision_without_digest)}


def validate_execution_fence(
    selection: ControllerSelection,
    fence: ExecutionFence,
    *,
    expected_mode: ExecutionMode,
    other_lease_nonces: tuple[str, ...] = (),
) -> dict[str, Any]:
    """Validate local official/diagnostic separation and nonce uniqueness."""

    reasons: list[str] = []
    if fence.card_id != selection.card_id or fence.attempt_id != selection.attempt_id:
        reasons.append("FENCE_CARD_OR_ATTEMPT_MISMATCH")
    if fence.mode is not expected_mode:
        reasons.append("EXECUTION_MODE_MISMATCH")
    if fence.lease_nonce in set(other_lease_nonces):
        reasons.append("LEASE_NONCE_REUSED")
    if expected_mode is ExecutionMode.DIAGNOSTIC_NON_ACCEPTING:
        if selection.work_kind is not WorkKind.PRODUCT_DIAGNOSTIC:
            reasons.append("DIAGNOSTIC_MODE_REQUIRES_DIAGNOSTIC_SELECTION")
        if selection.fail_fast or not selection.exhaustive_diagnostics:
            reasons.append("DIAGNOSTIC_MODE_MUST_BE_EXHAUSTIVE_NON_FAIL_FAST")
    if expected_mode is ExecutionMode.OFFICIAL_ACCEPTANCE:
        if not selection.fail_fast or selection.exhaustive_diagnostics:
            reasons.append("OFFICIAL_MODE_MUST_BE_FAIL_FAST_NON_EXHAUSTIVE")
    return {
        "schema": "ExecutionFenceValidationV1",
        "schemaVersion": 1,
        "valid": not reasons,
        "reasons": sorted(set(reasons)),
        "mode": fence.mode.value,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }


def evaluate_active_dispatch_set(
    entries: tuple[HostedWorkIdentity, ...],
    *,
    authority: AuthorityBindings,
) -> dict[str, Any]:
    """Check an append-only projection without making it a dispatch effect."""

    reasons: list[str] = []
    if len(entries) > POOL_CEILINGS["STANDARD_GITHUB"]:
        reasons.append("ACTIVE_PROJECTION_EXCEEDS_FIVE_STANDARD_LANES")
    keys = [entry.key for entry in entries]
    if len(keys) != len(set(keys)):
        reasons.append("DUPLICATE_ACTIVE_WORK_IDENTITY")
    lanes = {Pool.STANDARD_GITHUB: 0, Pool.GETMAC: 0}
    for entry in entries:
        lanes[entry.pool] += 1
        if entry.card_id != authority.card_id or entry.attempt_id != authority.attempt_id:
            reasons.append("ACTIVE_PROJECTION_CARD_ATTEMPT_MISMATCH")
        if entry.candidate_head != authority.candidate_head or entry.candidate_tree != authority.candidate_tree:
            reasons.append("ACTIVE_PROJECTION_CANDIDATE_MISMATCH")
        if entry.pool is Pool.GETMAC and entry.work_kind in {
            HostedWorkKind.PRODUCT_PIPELINE,
            HostedWorkKind.PROTECTED_RELEASE_PIPELINE,
        }:
            reasons.append("GETMAC_PRODUCT_OR_RELEASE_WORK_FORBIDDEN")
    if lanes[Pool.GETMAC] > POOL_CEILINGS["GETMAC"]:
        reasons.append("ACTIVE_PROJECTION_EXCEEDS_THREE_GETMAC_LANES")
    return {
        "schema": "ActiveDispatchSetValidationV1",
        "schemaVersion": 1,
        "valid": not reasons,
        "reasons": sorted(set(reasons)),
        "standardGithubActive": lanes[Pool.STANDARD_GITHUB],
        "getMacActive": lanes[Pool.GETMAC],
        "acceptanceCredit": False,
        "releaseCredit": False,
    }


def evaluate_pipeline(
    selection: ControllerSelection,
    *,
    claim: ClaimDisposition,
    transfer: TransferDisposition | None,
    stage: PipelineStage,
    queue_open: bool,
    nonce_reused: bool = False,
) -> dict[str, Any]:
    """Model the claim/transfer boundary without starting a hosted job."""

    reasons: list[str] = []
    if selection.work_kind is WorkKind.PROTECTED_RELEASE:
        reasons.append("PROTECTED_RELEASE_NOT_PERMITTED_IN_PROVISIONAL_C04")
    if nonce_reused:
        reasons.append("LEASE_NONCE_REUSED")
    if stage is PipelineStage.PRODUCT_CELL and claim is not ClaimDisposition.CREATED_MATCHING:
        reasons.append("PRODUCT_CELL_REQUIRES_MATCHING_CLAIM")
    if transfer not in {TransferDisposition.TRANSFER_WON, TransferDisposition.NOOP_WON}:
        reasons.append("DURABLE_PRETRANSFER_DECISION_REQUIRED")
    if not queue_open:
        reasons.append("QUEUE_CLOSED_OR_STALE")
    result = ControllerResult.INFRASTRUCTURE_PENDING if reasons else ControllerResult.READY_LOCAL_NONACCEPTING
    return {
        "schema": "HostedProductPipelineDecisionV1",
        "schemaVersion": 1,
        "cardID": selection.card_id,
        "attemptID": selection.attempt_id,
        "stage": stage.value,
        "claim": claim.value,
        "transfer": transfer.value if transfer else None,
        "result": result.value,
        "reasons": sorted(set(reasons)),
        "dispatchAuthorized": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }


def evaluate_fail_fast(
    *,
    mode: ExecutionMode,
    first_failure: str | None,
    stop_intent_written: bool,
    new_dispatch_count: int,
    sibling_observations_reconciled: bool,
    late_observations_reconciled: bool,
) -> dict[str, Any]:
    """Enforce first-failure stop ordering and diagnostic non-acceptance."""

    if first_failure is None:
        if stop_intent_written or new_dispatch_count or not sibling_observations_reconciled:
            raise ContractError("A no-failure run cannot contain a stop or unaccounted dispatch")
        result = ControllerResult.READY_LOCAL_NONACCEPTING
    elif not stop_intent_written or new_dispatch_count or not sibling_observations_reconciled or not late_observations_reconciled:
        result = ControllerResult.INFRASTRUCTURE_PENDING
    elif mode is ExecutionMode.DIAGNOSTIC_NON_ACCEPTING:
        result = ControllerResult.DIAGNOSTIC_COMPLETE_NON_ACCEPTING
    elif first_failure.startswith("PRODUCT_"):
        result = ControllerResult.PRODUCT_PROOF_CONTRADICTION
    else:
        result = ControllerResult.INFRASTRUCTURE_PENDING
    return {
        "schema": "FailFastDecisionV1",
        "schemaVersion": 1,
        "mode": mode.value,
        "firstFailure": first_failure,
        "stopIntentFirstDurableEffect": bool(first_failure) and stop_intent_written,
        "newDispatchAllowed": False if first_failure else new_dispatch_count == 0,
        "siblingObservationsReconciled": sibling_observations_reconciled,
        "lateObservationsReconciled": late_observations_reconciled,
        "result": result.value,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }


def classify_recovery(
    *,
    expected_state_digest: str,
    observed_state_digest: str | None,
    expected_generation: int,
    observed_generation: int | None,
    effect_state: str,
    provider_commands: int,
    provider_responses: int,
    provider_effects: int,
) -> dict[str, Any]:
    """Classify interruption recovery as absent, matching, or divergent."""

    _require_digest(expected_state_digest, "expectedStateDigest")
    if observed_state_digest is not None:
        _require_digest(observed_state_digest, "observedStateDigest")
    _require_int(expected_generation, "expectedGeneration")
    if observed_generation is not None:
        _require_int(observed_generation, "observedGeneration")
    if effect_state not in {"ABSENT", "APPLIED", "UNKNOWN"}:
        raise ContractError("effectState must be ABSENT, APPLIED, or UNKNOWN")
    commands = _require_int(provider_commands, "providerCommands")
    responses = _require_int(provider_responses, "providerResponses")
    effects = _require_int(provider_effects, "providerEffects")
    matching = observed_generation == expected_generation and observed_state_digest == expected_state_digest
    if effect_state == "ABSENT" and matching and commands == 0 and responses == 0 and effects == 0:
        disposition = RecoveryDisposition.BEFORE_EFFECT_AT_EXPECTED_GENERATION
        retry_same_bytes = True
    elif effect_state == "APPLIED" and matching and effects >= 1:
        disposition = RecoveryDisposition.APPLIED_MATCHING
        retry_same_bytes = False
    else:
        disposition = RecoveryDisposition.DIVERGENT_OR_AMBIGUOUS
        retry_same_bytes = False
    return {
        "schema": "ControllerEffectRecoveryDecisionV1",
        "schemaVersion": 1,
        "disposition": disposition.value,
        "retryExactSameBytes": retry_same_bytes,
        "retainCapacityDebit": disposition is not RecoveryDisposition.APPLIED_MATCHING,
        "zeroEffectProof": commands == 0 and responses == 0 and effects == 0,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }
