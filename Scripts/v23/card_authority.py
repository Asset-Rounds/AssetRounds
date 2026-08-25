"""Pure C05 state-writer adoption/abort and interruption recovery model."""

from __future__ import annotations

import copy
from typing import Any

from card_contracts import ContractError, digest


CONTROLLER_CELLS = frozenset(
    {
        "A00_BOOTSTRAP_ACTIVE",
        "PENDING_C05_CUTOVER",
        "PENDING_C05_ABORT_EFFECT",
        "PENDING_P00_C04_ACTIVATION",
        "P00_C04_ACTIVE",
    }
)
RECOVERY_CLASSES = frozenset(
    {
        "A00_ACTIVE_BEFORE_PENDING",
        "PENDING_CUTOVER_BEFORE_BRANCH",
        "PENDING_ABORT_BEFORE_EFFECT",
        "PENDING_ABORT_EFFECT_APPLIED_FINALIZE_A00",
        "PENDING_P00_ACTIVATION_EFFECT_APPLIED_PROOF_PENDING",
        "PENDING_P00_ACTIVATION_PROOF_READY_FINALIZE",
        "APPLIED_MATCHING_P00_ACTIVE",
        "DIVERGENT_OR_AMBIGUOUS",
    }
)


def _is_digest(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def begin_cutover(state: dict[str, Any], token: str, acceptance_authority: dict[str, Any]) -> dict[str, Any]:
    required = {
        "adoptionEnabled", "officialDecision", "officialDecisionDigest", "wrapperReceiptDigest",
        "semanticEquivalenceDigest", "effectiveAuthorizationDigest", "cardID", "attemptID",
        "candidateHead", "candidateTree", "acceptedS10Reconciliation", "expectedPlanes", "pendingEffectID",
    }
    if set(acceptance_authority) != required:
        raise ContractError("cutover authority is missing or widened")
    digest_fields = {"officialDecisionDigest", "wrapperReceiptDigest", "semanticEquivalenceDigest", "effectiveAuthorizationDigest"}
    if acceptance_authority["adoptionEnabled"] is not True:
        raise ContractError("C05 adoption is disabled by provisional authority")
    if acceptance_authority["officialDecision"] != "ACCEPT" or acceptance_authority["acceptedS10Reconciliation"] != "PASS":
        raise ContractError("official C05 acceptance or accepted S10.6 reconciliation is absent")
    if any(not _is_digest(acceptance_authority[field]) for field in digest_fields):
        raise ContractError("cutover authority contains an invalid evidence digest")
    expected_plane_names = {"ledger", "acceptanceEvidence", "hostedTransport", "expectedMainBase"}
    if set(acceptance_authority["expectedPlanes"]) != expected_plane_names or any(
        not _is_digest(value) for value in acceptance_authority["expectedPlanes"].values()
    ):
        raise ContractError("cutover authority does not bind four exact state planes")
    if (
        acceptance_authority["cardID"] != "V23-P00-C05"
        or acceptance_authority["attemptID"] != state.get("c05AttemptID")
        or acceptance_authority["candidateHead"] != state.get("candidateHead")
        or acceptance_authority["candidateTree"] != state.get("candidateTree")
    ):
        raise ContractError("cutover authority identity/candidate mismatch")
    if state.get("cell") != "A00_BOOTSTRAP_ACTIVE" or state.get("pendingToken") is not None:
        raise ContractError("cutover cannot begin from current controller cell")
    result = copy.deepcopy(state)
    result.update(
        {
            "cell": "PENDING_C05_CUTOVER",
            "pendingToken": token,
            "pendingEffectID": acceptance_authority["pendingEffectID"],
            "dispatchEnabled": False,
            "cutoverAuthority": copy.deepcopy(acceptance_authority),
            "cutoverAuthorityDigest": digest(acceptance_authority),
        }
    )
    return result


def choose_branch(state: dict[str, Any], token: str, branch: str, evidence: dict[str, Any]) -> dict[str, Any]:
    if state.get("cell") != "PENDING_C05_CUTOVER" or state.get("pendingToken") != token:
        raise ContractError("stale or mismatched cutover token")
    if branch not in {"ADOPT", "ABORT"}:
        raise ContractError("unknown cutover branch")
    result = copy.deepcopy(state)
    if branch == "ABORT":
        if set(evidence) != {"adoptionApplied", "effectID", "abortIntentDigest"} or evidence.get("adoptionApplied"):
            raise ContractError("abort is illegal after adoption")
        if evidence["effectID"] != state.get("pendingEffectID") or not _is_digest(evidence["abortIntentDigest"]):
            raise ContractError("abort intent/effect identity mismatch")
        result["cell"] = "PENDING_C05_ABORT_EFFECT"
        result["branchDigest"] = digest({"token": token, "branch": branch, "evidence": evidence})
        return result
    authority = state.get("cutoverAuthority", {})
    if set(evidence) != {"matchingStatePlanes", "semanticEquivalenceDigest", "officialDecisionDigest", "wrapperReceiptDigest", "effectID"}:
        raise ContractError("adoption evidence is missing or widened")
    if (
        evidence.get("matchingStatePlanes") != authority.get("expectedPlanes")
        or evidence.get("semanticEquivalenceDigest") != authority.get("semanticEquivalenceDigest")
        or evidence.get("officialDecisionDigest") != authority.get("officialDecisionDigest")
        or evidence.get("wrapperReceiptDigest") != authority.get("wrapperReceiptDigest")
        or evidence.get("effectID") != state.get("pendingEffectID")
    ):
        raise ContractError("four-way adoption evidence is partial or divergent")
    writer_authority = state.get("writerAuthority", {})
    adoption_effect = {
        "token": token,
        "effectID": evidence["effectID"],
        "cutoverAuthorityDigest": state["cutoverAuthorityDigest"],
        "adoptedPlanes": evidence["matchingStatePlanes"],
    }
    result.update(
        {
            "cell": "PENDING_P00_C04_ACTIVATION",
            "writerAuthority": {"ownerID": "V23-P00-C05", "writerGeneration": writer_authority.get("writerGeneration", -1) + 1},
            "a00PermanentlyRevoked": True,
            "c05AcceptedCount": state.get("c05AcceptedCount", 0) + 1,
            "adoptedPlanes": copy.deepcopy(evidence["matchingStatePlanes"]),
            "adoptionEffectDigest": digest(adoption_effect),
            "branchDigest": digest({"token": token, "branch": branch, "evidence": evidence}),
        }
    )
    if result["c05AcceptedCount"] != 1:
        raise ContractError("C05 ACCEPTED would be appended more than once")
    return result


def apply_abort(state: dict[str, Any], token: str, effect: dict[str, Any]) -> dict[str, Any]:
    if state.get("cell") != "PENDING_C05_ABORT_EFFECT" or state.get("pendingToken") != token:
        raise ContractError("abort effect token mismatch")
    if set(effect) != {"effectID", "abortEffectDigest"} or effect["effectID"] != state.get("pendingEffectID") or not _is_digest(effect["abortEffectDigest"]):
        raise ContractError("abort effect receipt mismatch")
    result = copy.deepcopy(state)
    result.update(
        {
            "cell": "A00_BOOTSTRAP_ACTIVE",
            "pendingToken": None,
            "dispatchEnabled": True,
            "supersededAttemptID": state["c05AttemptID"],
            "c05AttemptID": state["c05AttemptID"] + 1,
            "c05AttemptState": "NOT_STARTED",
            "controllerEpoch": state.get("controllerEpoch", 0) + 1,
            "abortEffectDigest": effect["abortEffectDigest"],
        }
    )
    return result


def finalize_activation(state: dict[str, Any], token: str, proof: dict[str, Any]) -> dict[str, Any]:
    if state.get("cell") != "PENDING_P00_C04_ACTIVATION" or state.get("pendingToken") != token:
        raise ContractError("activation finalization token mismatch")
    required = {"proofDigest", "recoveryReceiptDigest", "cardID", "attemptID", "writerAuthority"}
    if set(proof) != required or not _is_digest(proof.get("proofDigest")) or not _is_digest(proof.get("recoveryReceiptDigest")):
        raise ContractError("C05 inclusion proof/recovery is not durable")
    if (
        proof["cardID"] != "V23-P00-C05"
        or proof["attemptID"] != state.get("c05AttemptID")
        or proof["writerAuthority"] != state.get("writerAuthority")
    ):
        raise ContractError("C05 inclusion proof identity/writer mismatch")
    result = copy.deepcopy(state)
    result.update({"cell": "P00_C04_ACTIVE", "pendingToken": None, "dispatchEnabled": True, "inclusionProof": copy.deepcopy(proof)})
    return result


def classify_recovery(state: dict[str, Any]) -> str:
    cell = state.get("cell")
    if cell not in CONTROLLER_CELLS:
        return "DIVERGENT_OR_AMBIGUOUS"
    if cell == "A00_BOOTSTRAP_ACTIVE":
        return "A00_ACTIVE_BEFORE_PENDING"
    if cell == "PENDING_C05_CUTOVER":
        return "PENDING_CUTOVER_BEFORE_BRANCH"
    if cell == "PENDING_C05_ABORT_EFFECT":
        return "PENDING_ABORT_BEFORE_EFFECT" if not state.get("abortEffectApplied") else "PENDING_ABORT_EFFECT_APPLIED_FINALIZE_A00"
    if cell == "PENDING_P00_C04_ACTIVATION":
        return "PENDING_P00_ACTIVATION_PROOF_READY_FINALIZE" if state.get("inclusionProofReady") else "PENDING_P00_ACTIVATION_EFFECT_APPLIED_PROOF_PENDING"
    if state.get("a00PermanentlyRevoked") and state.get("writerAuthority", {}).get("ownerID") == "V23-P00-C05":
        return "APPLIED_MATCHING_P00_ACTIVE"
    return "DIVERGENT_OR_AMBIGUOUS"
