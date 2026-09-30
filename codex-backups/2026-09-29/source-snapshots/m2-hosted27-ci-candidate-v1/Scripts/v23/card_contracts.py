"""Fail-closed contracts shared by V23 card projection and hydration tooling."""

from __future__ import annotations

import copy
import hashlib
import json
from collections import Counter, defaultdict, deque
from typing import Any, Iterable


class ContractError(ValueError):
    pass


RELATION_KINDS = frozenset(
    {
        "DIRECT_EXECUTION_PREREQUISITE",
        "AGGREGATE_ACCEPTANCE_MEMBER",
        "INVALIDATION_CONSUMER",
        "PROVENANCE_REFERENCE",
        "OPTIONAL_CAPABILITY_PROVIDER",
        "CONFORMANCE_SUBJECT",
        "CONTRACT_INPUT_PROVIDER",
    }
)
FROZEN_AUTHORITY_DIGESTS = {
    "register": "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd",
    "graph": "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae",
    "impact": "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b",
    "selectors": "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2",
    "relations": "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4",
    "facets": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "dependencyDispositions": "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c",
}
FROZEN_PROGRAM_AUTHORITY = {
    "packageDigest": "99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570",
    "overrideID": "V23-OWNER-PARALLEL-IMPLEMENTATION-004",
    "overrideSemanticDigest": "3c1d8779cbc00ed22d26a088bac9f4169e92f630ac3d1f9d5e3fcf43e47bb8cd",
    "overrideReceiptDigest": "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452",
    "frozenS10ReservationDigest": "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a",
    "phase10PollingDuringParallelExecution": False,
    "officialAcceptanceEnabled": False,
    "releaseCredit": False,
}
NON_DIRECT_RELATION_KINDS = RELATION_KINDS - {"DIRECT_EXECUTION_PREREQUISITE"}
COMPATIBILITY_CONTEXT_FIELDS = {
    "DIRECT_EDGE": {"kind", "sourceCardID", "targetCardID", "edgeOrdinal", "directGraphDigest"},
    "SELECTOR_MEMBER": {"kind", "selectorID", "memberCardID", "memberOrdinal", "selectorDigest"},
}
CARD_STATES = frozenset(
    {
        "NOT_STARTED", "HYDRATING", "READY", "IMPLEMENTING", "TARGETED_GREEN",
        "WAITING_ACCEPTANCE_SET", "ACCEPTANCE_RUNNING", "ACCEPTANCE_FAILED",
        "DIAGNOSTIC_COMPLETE_NON_ACCEPTING", "VALIDATION_RESULT_NONRELEASE",
        "MONITORING_COMPLETE_NONRELEASE", "CORRECTION_REQUIRED", "INFRASTRUCTURE_PENDING",
        "OWNER_PENDING", "ACCEPTED", "HANDOFF_PENDING", "COMPLETE", "DEFERRED", "SUPERSEDED",
    }
)
ALLOWED_TRANSITIONS = {
    "NOT_STARTED": {"HYDRATING", "DEFERRED", "OWNER_PENDING", "SUPERSEDED"},
    "HYDRATING": {"READY", "CORRECTION_REQUIRED", "INFRASTRUCTURE_PENDING", "OWNER_PENDING", "SUPERSEDED"},
    "READY": {"IMPLEMENTING", "OWNER_PENDING", "SUPERSEDED"},
    "IMPLEMENTING": {"TARGETED_GREEN", "VALIDATION_RESULT_NONRELEASE", "MONITORING_COMPLETE_NONRELEASE", "DEFERRED", "CORRECTION_REQUIRED", "INFRASTRUCTURE_PENDING", "OWNER_PENDING", "SUPERSEDED"},
    "TARGETED_GREEN": {"WAITING_ACCEPTANCE_SET", "ACCEPTANCE_RUNNING", "INFRASTRUCTURE_PENDING", "CORRECTION_REQUIRED", "SUPERSEDED"},
    "WAITING_ACCEPTANCE_SET": {"ACCEPTANCE_RUNNING", "CORRECTION_REQUIRED", "INFRASTRUCTURE_PENDING", "OWNER_PENDING", "SUPERSEDED"},
    "ACCEPTANCE_RUNNING": {"ACCEPTED", "ACCEPTANCE_FAILED", "INFRASTRUCTURE_PENDING", "SUPERSEDED"},
    "ACCEPTANCE_FAILED": {"DIAGNOSTIC_COMPLETE_NON_ACCEPTING", "CORRECTION_REQUIRED", "INFRASTRUCTURE_PENDING", "OWNER_PENDING", "SUPERSEDED"},
    "DIAGNOSTIC_COMPLETE_NON_ACCEPTING": {"CORRECTION_REQUIRED", "INFRASTRUCTURE_PENDING", "OWNER_PENDING", "SUPERSEDED"},
    "VALIDATION_RESULT_NONRELEASE": {"SUPERSEDED"},
    "MONITORING_COMPLETE_NONRELEASE": {"SUPERSEDED"},
    "CORRECTION_REQUIRED": {"IMPLEMENTING", "OWNER_PENDING", "SUPERSEDED"},
    "INFRASTRUCTURE_PENDING": {"HYDRATING", "READY", "IMPLEMENTING", "TARGETED_GREEN", "WAITING_ACCEPTANCE_SET", "ACCEPTANCE_RUNNING", "OWNER_PENDING", "SUPERSEDED"},
    "OWNER_PENDING": {"HYDRATING", "READY", "IMPLEMENTING", "DEFERRED", "SUPERSEDED"},
    "ACCEPTED": {"HANDOFF_PENDING", "COMPLETE", "SUPERSEDED"},
    "HANDOFF_PENDING": {"HYDRATING", "COMPLETE", "INFRASTRUCTURE_PENDING", "OWNER_PENDING", "SUPERSEDED"},
    "DEFERRED": {"SUPERSEDED"},
    "COMPLETE": {"SUPERSEDED"},
    "SUPERSEDED": set(),
}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def verify_embedded_digest(value: dict[str, Any], field: str) -> None:
    if field not in value:
        raise ContractError(f"missing {field}")
    body = {key: item for key, item in value.items() if key != field}
    if digest(body) != value[field]:
        raise ContractError(f"{field} mismatch")


def verify_coordination_digest(value: dict[str, Any], field: str) -> None:
    if field not in value:
        raise ContractError(f"missing {field}")
    body = {key: item for key, item in value.items() if key != field}
    encoded = (json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    if hashlib.sha256(encoded).hexdigest() != value[field]:
        raise ContractError(f"{field} mismatch")


def require_exact_keys(value: dict[str, Any], required: Iterable[str], optional: Iterable[str] = ()) -> None:
    required_set, optional_set = set(required), set(optional)
    missing = required_set - value.keys()
    extra = value.keys() - required_set - optional_set
    if missing or extra:
        raise ContractError(f"object keys missing={sorted(missing)} extra={sorted(extra)}")


def validate_compatibility_context(context: dict[str, Any]) -> None:
    kind = context.get("kind")
    expected = COMPATIBILITY_CONTEXT_FIELDS.get(kind)
    if expected is None or set(context) != expected:
        raise ContractError("compatibility context is not one closed union member")
    ordinal_field = "edgeOrdinal" if kind == "DIRECT_EDGE" else "memberOrdinal"
    if not isinstance(context[ordinal_field], int) or context[ordinal_field] < 1:
        raise ContractError("compatibility ordinal must be positive")


def _has_path(adjacency: dict[str, set[str]], source: str, target: str, excluded: tuple[str, str]) -> bool:
    queue = deque([source])
    visited = {source}
    while queue:
        node = queue.popleft()
        for successor in adjacency.get(node, set()):
            if (node, successor) == excluded:
                continue
            if successor == target:
                return True
            if successor not in visited:
                visited.add(successor)
                queue.append(successor)
    return False


def validate_projection(projection: dict[str, Any]) -> None:
    verify_embedded_digest(projection, "projectionDigest")
    cards = projection.get("cards", [])
    card_ids = [row.get("id") for row in cards]
    if len(cards) != 146 or len(set(card_ids)) != 146:
        raise ContractError("projection must contain 146 unique cards")
    ordinals = [row.get("ordinal") for row in cards]
    if ordinals != list(range(1, 147)):
        raise ContractError("register ordinals are not canonical")
    edge_rows = projection.get("directEdges", [])
    if len(edge_rows) != 230:
        raise ContractError("direct graph must contain 230 edges")
    adjacency: dict[str, set[str]] = defaultdict(set)
    indegree = Counter({card: 0 for card in card_ids})
    seen_edges = set()
    expected_edge_rows = [
        {"source": source, "target": row["id"], "edgeOrdinal": ordinal}
        for row in cards
        for ordinal, source in enumerate(row["directPrerequisites"], start=1)
    ]
    if edge_rows != expected_edge_rows:
        raise ContractError("direct edges do not exactly match ordered register prerequisites")
    for edge in edge_rows:
        key = (edge.get("source"), edge.get("target"))
        if key in seen_edges or key[0] not in indegree or key[1] not in indegree:
            raise ContractError("duplicate or orphan direct edge")
        seen_edges.add(key)
        adjacency[key[0]].add(key[1])
        indegree[key[1]] += 1
    queue = deque(card for card in card_ids if indegree[card] == 0)
    visited = []
    while queue:
        node = queue.popleft()
        visited.append(node)
        for successor in adjacency.get(node, set()):
            indegree[successor] -= 1
            if indegree[successor] == 0:
                queue.append(successor)
    if len(visited) != len(card_ids):
        raise ContractError("direct graph contains a cycle")
    for source, target in seen_edges:
        if _has_path(adjacency, source, target, (source, target)):
            raise ContractError(f"direct graph is not transitively reduced: {source}->{target}")
    relations = projection.get("relations", [])
    if len(relations) != 1247 or any(row.get("kind") not in NON_DIRECT_RELATION_KINDS for row in relations):
        raise ContractError("non-direct relation manifest is incomplete or contains an unknown kind")
    if len(projection.get("selectors", [])) != 7:
        raise ContractError("selector manifest must contain seven rows")
    authority = projection.get("authorityDigests", {})
    if authority != FROZEN_AUTHORITY_DIGESTS:
        raise ContractError("embedded authority digests differ from frozen A00 pins")
    if projection.get("programAuthority") != FROZEN_PROGRAM_AUTHORITY:
        raise ContractError("program authority differs from frozen A00/owner override pins")
    structural_register = [
        {key: row[key] for key in ("id", "title", "classification", "status", "directPrerequisites", "lineage")}
        for row in cards
    ]
    graph = [{"id": row["id"], "directPrerequisites": row["directPrerequisites"]} for row in cards]
    selectors = [
        {key: row[key] for key in ("id", "members", "consumers", "predicate")}
        for row in projection["selectors"]
    ]
    checks = {
        "register": structural_register,
        "graph": graph,
        "impact": projection.get("impact", []),
        "selectors": selectors,
        "relations": relations,
        "dependencyDispositions": projection.get("dependencyDispositions", []),
    }
    for key, value in checks.items():
        if digest(value) != authority.get(key):
            raise ContractError(f"frozen {key} digest mismatch")


def validate_direct_evidence(
    projection: dict[str, Any], target_card_id: str, evidence_rows: list[dict[str, Any]]
) -> None:
    expected = [edge for edge in projection["directEdges"] if edge["target"] == target_card_id]
    keys = [(row.get("sourceCardID"), row.get("targetCardID"), row.get("edgeOrdinal")) for row in evidence_rows]
    if len(keys) != len(set(keys)) or len(evidence_rows) != len(expected):
        raise ContractError("direct evidence count is missing, duplicate, orphaned, or extra")
    by_key = {key: row for key, row in zip(keys, evidence_rows)}
    for edge in expected:
        key = (edge["source"], edge["target"], edge["edgeOrdinal"])
        row = by_key.get(key)
        if row is None:
            raise ContractError(f"missing direct evidence {key}")
        special = edge["source"] == "V23-P00-C03" and edge["target"].startswith("V23-P06-")
        if special:
            required = {"NonreleasePrerequisiteSatisfactionReceiptV1", "NonreleaseResultInclusionProofV1"}
            if row.get("evidenceKind") != "SATISFIED_GO_EVIDENCE" or not required <= set(row.get("artifacts", [])):
                raise ContractError("nonrelease special edge lacks supported GO evidence")
            if row.get("releaseCredit") is not False:
                raise ContractError("nonrelease special edge granted release credit")
        else:
            required = {
                "V23CardAcceptanceReceiptV2",
                "CardAcceptanceInclusionProofV1",
                "CardAcceptanceInclusionProofRecoveryReceiptV1",
                "CandidateAcceptanceCompatibilityReceiptV1",
            }
            if row.get("evidenceKind") != "ORDINARY_ACCEPTED_COMPATIBLE" or not required <= set(row.get("artifacts", [])):
                raise ContractError("ordinary direct edge evidence incomplete")
            validate_compatibility_context(row.get("compatibilityContext", {}))
            context = row["compatibilityContext"]
            if context != {
                "kind": "DIRECT_EDGE",
                "sourceCardID": edge["source"],
                "targetCardID": edge["target"],
                "edgeOrdinal": edge["edgeOrdinal"],
                "directGraphDigest": projection["authorityDigests"]["graph"],
            }:
                raise ContractError("ordinary edge compatibility context mismatch")


def validate_fence_subset(spec_paths: list[str], fence: dict[str, Any], bootstrap_fence: dict[str, Any]) -> None:
    verify_embedded_digest(fence, "fenceDigest")
    allowed = fence.get("allowedPaths", [])
    bootstrap_allowed = bootstrap_fence.get("allowedCreateOrReplacePaths", bootstrap_fence.get("allowedPaths", []))
    if len(allowed) != len(set(allowed)) or not set(allowed) <= set(bootstrap_allowed):
        raise ContractError("hydrated fence widens or duplicates the bootstrap fence")
    if sorted(spec_paths) != sorted(allowed):
        raise ContractError("hydrated spec and path fence disagree")
    if any(path.startswith("/") or ".." in path.replace("\\", "/").split("/") for path in allowed):
        raise ContractError("path fence contains a non-repository path")
    if fence.get("releaseCredit") is not False:
        raise ContractError("path fence granted release credit")


def validate_ledger(transitions: list[dict[str, Any]], writer_owner: str, writer_generation: int) -> str:
    prior = "GENESIS"
    last_state: dict[tuple[str, int], str] = {}
    max_attempt: dict[str, int] = {}
    for sequence, frame in enumerate(transitions, start=1):
        verify_embedded_digest(frame, "transitionDigest")
        if frame.get("sequence") != sequence or frame.get("priorTransitionDigest") != prior:
            raise ContractError("ledger sequence or hash chain is not consecutive")
        authority = frame.get("writerAuthority", {})
        if authority != {"ownerID": writer_owner, "writerGeneration": writer_generation}:
            raise ContractError("ledger writer authority mismatch")
        _validate_transition_frame(frame)
        card_id, attempt_id = frame.get("cardID"), frame.get("attemptID")
        attempt = (card_id, attempt_id)
        if attempt in last_state and frame.get("priorState") != last_state[attempt]:
            raise ContractError("attempt state chain mismatch or terminal attempt reopened")
        if attempt not in last_state:
            prior_attempt = max_attempt.get(card_id, 0)
            if not isinstance(attempt_id, int) or attempt_id < 1 or attempt_id > prior_attempt + 1:
                raise ContractError("attempt identity is stale, skipped, or nonmonotonic")
            max_attempt[card_id] = max(prior_attempt, attempt_id)
        last_state[attempt] = frame["newState"]
        prior = frame["transitionDigest"]
    return prior


def _validate_transition_frame(frame: dict[str, Any]) -> None:
    prior_state, new_state = frame.get("priorState"), frame.get("newState")
    if prior_state not in CARD_STATES or new_state not in ALLOWED_TRANSITIONS.get(prior_state, set()):
        raise ContractError("unlisted CardExecutionStateV2 transition")
    if frame.get("releaseCredit") is True:
        raise ContractError("card transition cannot grant release credit")
    classification = frame.get("classification")
    if classification in {"VALIDATE_NEXT", "DEFER"} and new_state in {
        "TARGETED_GREEN", "WAITING_ACCEPTANCE_SET", "ACCEPTANCE_RUNNING", "ACCEPTED", "HANDOFF_PENDING", "COMPLETE"
    }:
        raise ContractError("nonautonomous classification entered an accepting state")
    if new_state == "ACCEPTED":
        required = {"officialDecisionDigest", "effectiveAuthorizationDigest", "candidateHead", "candidateTree"}
        if frame.get("acceptanceEnabled") is not True or not required <= frame.keys():
            raise ContractError("ACCEPTED transition lacks official decision authority")


def append_transition(
    transitions: list[dict[str, Any]], frame: dict[str, Any], expected_tip: str, expected_sequence: int
) -> dict[str, Any]:
    current_tip = transitions[-1]["transitionDigest"] if transitions else "GENESIS"
    if current_tip != expected_tip or len(transitions) != expected_sequence:
        raise ContractError("ledger CAS mismatch")
    next_frame = copy.deepcopy(frame)
    _validate_transition_frame(next_frame)
    next_frame["sequence"] = expected_sequence + 1
    next_frame["priorTransitionDigest"] = current_tip
    next_frame["transitionDigest"] = digest(next_frame)
    return next_frame
