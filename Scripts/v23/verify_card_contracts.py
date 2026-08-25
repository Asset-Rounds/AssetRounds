#!/usr/bin/env python3
"""Deterministic positive, hostile, interruption, and recovery checks for C05."""

from __future__ import annotations

import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

from card_authority import (
    apply_abort,
    begin_cutover,
    choose_branch,
    classify_recovery,
    finalize_activation,
)
from card_contracts import (
    ContractError,
    append_transition,
    digest,
    validate_compatibility_context,
    validate_direct_evidence,
    validate_fence_subset,
    validate_ledger,
    validate_projection,
)
from generate_card_projection import build
from hydrate_card import hydrate


ROOT = Path(__file__).resolve().parents[2]
COORDINATION = ROOT.parent / "AssetRounds-v23-coordination"


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def redigest(value: dict[str, Any], field: str) -> dict[str, Any]:
    result = copy.deepcopy(value)
    result.pop(field, None)
    result[field] = digest(result)
    return result


class ProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.projection, cls.facets = build(ROOT)

    def test_generator_is_deterministic(self) -> None:
        self.assertEqual(build(ROOT), build(ROOT))

    def test_checked_in_projection_current(self) -> None:
        self.assertEqual(load(ROOT / "docs/design/v23/tooling/V23PlanningProjectionV1.json"), self.projection)

    def test_checked_in_facets_current(self) -> None:
        self.assertEqual(load(ROOT / "docs/design/v23/tooling/ContractFacetRegistryV1.json"), self.facets)

    def test_contract_ownership_manifest_unique(self) -> None:
        members = [member for row in self.facets["ownershipRows"] for member in row["familyMembers"]]
        self.assertEqual((len(self.facets["ownershipRows"]), len(members), len(set(members))), (79, 359, 359))

    def test_projection_valid(self) -> None:
        validate_projection(self.projection)

    def test_manifest_artifact_hashes(self) -> None:
        manifest = load(ROOT / "docs/design/v23/tooling/V23-P00-C05-tooling-manifest.json")
        expected_paths = {
            "Scripts/v23/card_contracts.py", "Scripts/v23/card_authority.py",
            "Scripts/v23/generate_card_projection.py", "Scripts/v23/hydrate_card.py",
            "Scripts/v23/verify_card_contracts.py", "Scripts/v23/hydrated-card-execution-spec.schema.json",
            "Scripts/v23/path-fence.schema.json", "docs/design/v23/tooling/V23PlanningProjectionV1.json",
            "docs/design/v23/tooling/ContractFacetRegistryV1.json",
        }
        self.assertEqual({artifact["path"] for artifact in manifest["artifacts"]}, expected_paths)
        for artifact in manifest["artifacts"]:
            self.assertEqual(hashlib.sha256((ROOT / artifact["path"]).read_bytes()).hexdigest(), artifact["sha256"])
        self.assertEqual(manifest["authority"]["packageDigest"], self.projection["programAuthority"]["packageDigest"])
        self.assertEqual(manifest["authority"]["overrideReceiptDigest"], self.projection["programAuthority"]["overrideReceiptDigest"])

    def test_exact_counts(self) -> None:
        self.assertEqual(self.projection["counts"], {
            "cards": 146, "directEdges": 230, "impactRows": 146, "selectors": 7,
            "nonDirectRelations": 1247, "dependencyDispositions": 1058,
            "contractFacets": 69, "nonreleaseSpecialEdges": 10,
        })

    def test_unknown_relation_kind_rejected(self) -> None:
        bad = copy.deepcopy(self.projection)
        bad["relations"][0]["kind"] = "PROSE_INFERRED"
        bad = redigest(bad, "projectionDigest")
        with self.assertRaises(ContractError):
            validate_projection(bad)

    def test_relation_tamper_rejected_even_if_artifact_redigested(self) -> None:
        bad = copy.deepcopy(self.projection)
        bad["relations"][0]["target"] = "V23-P99-C99"
        bad = redigest(bad, "projectionDigest")
        with self.assertRaises(ContractError):
            validate_projection(bad)

    def test_graph_tamper_rejected(self) -> None:
        bad = copy.deepcopy(self.projection)
        bad["directEdges"][0]["source"] = bad["directEdges"][0]["target"]
        bad = redigest(bad, "projectionDigest")
        with self.assertRaises(ContractError):
            validate_projection(bad)

    def test_duplicate_card_rejected(self) -> None:
        bad = copy.deepcopy(self.projection)
        bad["cards"][1]["id"] = bad["cards"][0]["id"]
        bad = redigest(bad, "projectionDigest")
        with self.assertRaises(ContractError):
            validate_projection(bad)


class CompatibilityTests(unittest.TestCase):
    def test_direct_context_valid(self) -> None:
        validate_compatibility_context({
            "kind": "DIRECT_EDGE", "sourceCardID": "V23-P00-C04", "targetCardID": "V23-P00-C05",
            "edgeOrdinal": 1, "directGraphDigest": "0" * 64,
        })

    def test_selector_context_valid(self) -> None:
        validate_compatibility_context({
            "kind": "SELECTOR_MEMBER", "selectorID": "A", "memberCardID": "V23-P00-C05",
            "memberOrdinal": 1, "selectorDigest": "0" * 64,
        })

    def test_context_confusion_rejected(self) -> None:
        with self.assertRaises(ContractError):
            validate_compatibility_context({
                "kind": "DIRECT_EDGE", "selectorID": "A", "memberCardID": "V23-P00-C05",
                "memberOrdinal": 1, "selectorDigest": "0" * 64,
            })

    def test_extra_union_field_rejected(self) -> None:
        with self.assertRaises(ContractError):
            validate_compatibility_context({
                "kind": "DIRECT_EDGE", "sourceCardID": "A", "targetCardID": "B", "edgeOrdinal": 1,
                "directGraphDigest": "0" * 64, "selectorID": "C",
            })

    def test_zero_ordinal_rejected(self) -> None:
        with self.assertRaises(ContractError):
            validate_compatibility_context({
                "kind": "DIRECT_EDGE", "sourceCardID": "A", "targetCardID": "B", "edgeOrdinal": 0,
                "directGraphDigest": "0" * 64,
            })


class DirectEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.projection, _ = build(ROOT)

    def ordinary(self) -> dict[str, Any]:
        return {
            "sourceCardID": "V23-P00-C04", "targetCardID": "V23-P00-C05", "edgeOrdinal": 1,
            "evidenceKind": "ORDINARY_ACCEPTED_COMPATIBLE",
            "artifacts": ["V23CardAcceptanceReceiptV2", "CardAcceptanceInclusionProofV1",
                          "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
            "compatibilityContext": {"kind": "DIRECT_EDGE", "sourceCardID": "V23-P00-C04",
                                     "targetCardID": "V23-P00-C05", "edgeOrdinal": 1,
                                     "directGraphDigest": self.projection["authorityDigests"]["graph"]},
        }

    def valid_rows_for_target(self, target: str) -> list[dict[str, Any]]:
        rows = []
        for edge in (item for item in self.projection["directEdges"] if item["target"] == target):
            if edge["source"] == "V23-P00-C03" and target.startswith("V23-P06-"):
                rows.append({
                    "sourceCardID": edge["source"], "targetCardID": target, "edgeOrdinal": edge["edgeOrdinal"],
                    "evidenceKind": "SATISFIED_GO_EVIDENCE",
                    "artifacts": ["NonreleasePrerequisiteSatisfactionReceiptV1", "NonreleaseResultInclusionProofV1"],
                    "releaseCredit": False,
                })
            else:
                rows.append({
                    "sourceCardID": edge["source"], "targetCardID": target, "edgeOrdinal": edge["edgeOrdinal"],
                    "evidenceKind": "ORDINARY_ACCEPTED_COMPATIBLE",
                    "artifacts": ["V23CardAcceptanceReceiptV2", "CardAcceptanceInclusionProofV1",
                                  "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
                    "compatibilityContext": {"kind": "DIRECT_EDGE", "sourceCardID": edge["source"],
                                             "targetCardID": target, "edgeOrdinal": edge["edgeOrdinal"],
                                             "directGraphDigest": self.projection["authorityDigests"]["graph"]},
                })
        return rows

    def test_ordinary_evidence_valid(self) -> None:
        validate_direct_evidence(self.projection, "V23-P00-C05", [self.ordinary()])

    def test_missing_evidence_rejected(self) -> None:
        with self.assertRaises(ContractError):
            validate_direct_evidence(self.projection, "V23-P00-C05", [])

    def test_duplicate_evidence_rejected(self) -> None:
        with self.assertRaises(ContractError):
            validate_direct_evidence(self.projection, "V23-P00-C05", [self.ordinary(), self.ordinary()])

    def test_wrong_graph_digest_rejected(self) -> None:
        row = self.ordinary()
        row["compatibilityContext"]["directGraphDigest"] = "0" * 64
        with self.assertRaises(ContractError):
            validate_direct_evidence(self.projection, "V23-P00-C05", [row])

    def test_wrong_ordinal_rejected(self) -> None:
        row = self.ordinary()
        row["edgeOrdinal"] = 2
        with self.assertRaises(ContractError):
            validate_direct_evidence(self.projection, "V23-P00-C05", [row])

    def test_special_nonrelease_evidence_valid(self) -> None:
        edge = next(edge for edge in self.projection["directEdges"] if edge["source"] == "V23-P00-C03" and edge["target"].startswith("V23-P06-"))
        validate_direct_evidence(self.projection, edge["target"], self.valid_rows_for_target(edge["target"]))

    def test_special_edge_cannot_grant_release_credit(self) -> None:
        edge = next(edge for edge in self.projection["directEdges"] if edge["source"] == "V23-P00-C03" and edge["target"].startswith("V23-P06-"))
        rows = self.valid_rows_for_target(edge["target"])
        next(row for row in rows if row["sourceCardID"] == "V23-P00-C03")["releaseCredit"] = True
        with self.assertRaises(ContractError):
            validate_direct_evidence(self.projection, edge["target"], rows)


class HydrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.projection, cls.facets = build(ROOT)
        cls.authority = load(COORDINATION / "contexts/V23-P00-C05-attempt-1/BootstrapCardContextV1.json")

    def hydrate_named(self, directory: str) -> tuple[dict[str, Any], dict[str, Any]]:
        base = COORDINATION / "contexts" / directory
        return hydrate(self.projection, self.facets, load(base / "BootstrapCardContextV1.json"),
                       load(base / "BootstrapPathFenceV1.json"), self.authority)

    def test_c01_c02_c04_c05_deterministic(self) -> None:
        names = ["V23-P00-C01-attempt-1", "V23-P00-C02-attempt-2", "V23-P00-C04-attempt-2", "V23-P00-C05-attempt-1"]
        for name in names:
            self.assertEqual(self.hydrate_named(name), self.hydrate_named(name))

    def test_bootstrap_spec_digests_match_manifest(self) -> None:
        manifest = load(ROOT / "docs/design/v23/tooling/V23-P00-C05-tooling-manifest.json")
        names = ["V23-P00-C01-attempt-1", "V23-P00-C02-attempt-2", "V23-P00-C04-attempt-2", "V23-P00-C05-attempt-1"]
        actual = {name.rsplit("-attempt-", 1)[0]: self.hydrate_named(name)[0]["specDigest"] for name in names}
        self.assertEqual(actual, manifest["bootstrapSpecDigests"])

    def test_c05_fence_exact_ten_paths(self) -> None:
        spec, fence = self.hydrate_named("V23-P00-C05-attempt-1")
        self.assertEqual(len(spec["repositoryPaths"]), 10)
        self.assertEqual(spec["repositoryPaths"], fence["allowedPaths"])
        self.assertIn("HydratedCardExecutionSpecV2", spec["contractSymbols"])
        self.assertEqual(spec["readinessDisposition"], "PROVISIONAL_IMPLEMENTATION_ONLY_NOT_READY_FOR_ACCEPTANCE")
        self.assertFalse(spec["directPrerequisiteEvidenceValidated"])
        self.assertGreaterEqual(len(spec["contractFacets"]), 4)

    def test_latest_authority_context_is_mandatory(self) -> None:
        base = COORDINATION / "contexts/V23-P00-C05-attempt-1"
        with self.assertRaises(ContractError):
            hydrate(self.projection, self.facets, load(base / "BootstrapCardContextV1.json"),
                    load(base / "BootstrapPathFenceV1.json"), None)

    def test_provisional_hydration_rejects_official_evidence(self) -> None:
        base = COORDINATION / "contexts/V23-P00-C05-attempt-1"
        with self.assertRaises(ContractError):
            hydrate(self.projection, self.facets, load(base / "BootstrapCardContextV1.json"),
                    load(base / "BootstrapPathFenceV1.json"), self.authority, [{"unexpected": True}])

    def test_stale_authority_digest_rejected(self) -> None:
        context = copy.deepcopy(self.authority)
        context["sourceProjection"]["directGraphDigest"] = "0" * 64
        context = redigest_coordination(context, "contextDigest")
        fence = load(COORDINATION / "contexts/V23-P00-C05-attempt-1/BootstrapPathFenceV1.json")
        with self.assertRaises(ContractError):
            hydrate(self.projection, self.facets, context, fence, context)

    def test_fence_widening_rejected(self) -> None:
        _, fence = self.hydrate_named("V23-P00-C05-attempt-1")
        bootstrap = load(COORDINATION / "contexts/V23-P00-C05-attempt-1/BootstrapPathFenceV1.json")
        widened = copy.deepcopy(fence)
        widened["allowedPaths"].append("FieldEvidenceApp/Forbidden.swift")
        widened = redigest(widened, "fenceDigest")
        with self.assertRaises(ContractError):
            validate_fence_subset(widened["allowedPaths"], widened, bootstrap)

    def test_release_credit_rejected(self) -> None:
        _, fence = self.hydrate_named("V23-P00-C05-attempt-1")
        bootstrap = load(COORDINATION / "contexts/V23-P00-C05-attempt-1/BootstrapPathFenceV1.json")
        bad = copy.deepcopy(fence)
        bad["releaseCredit"] = True
        bad = redigest(bad, "fenceDigest")
        with self.assertRaises(ContractError):
            validate_fence_subset(bad["allowedPaths"], bad, bootstrap)

    def test_context_fence_identity_mismatch_rejected(self) -> None:
        context = self.authority
        wrong = load(COORDINATION / "contexts/V23-P00-C04-attempt-2/BootstrapPathFenceV1.json")
        with self.assertRaises(ContractError):
            hydrate(self.projection, self.facets, context, wrong, context)


def redigest_coordination(value: dict[str, Any], field: str) -> dict[str, Any]:
    import hashlib
    result = copy.deepcopy(value)
    result.pop(field, None)
    encoded = (json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()
    result[field] = hashlib.sha256(encoded).hexdigest()
    return result


class LedgerTests(unittest.TestCase):
    def frame(self, state: str = "READY", prior_state: str = "HYDRATING") -> dict[str, Any]:
        return {"cardID": "V23-P00-C05", "attemptID": 1, "priorState": prior_state, "newState": state,
                "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0}}

    def test_append_and_verify(self) -> None:
        frame = append_transition([], self.frame(), "GENESIS", 0)
        self.assertEqual(validate_ledger([frame], "A00_BOOTSTRAP_CONTROLLER", 0), frame["transitionDigest"])

    def test_stale_cas_rejected(self) -> None:
        with self.assertRaises(ContractError):
            append_transition([], self.frame(), "wrong", 0)

    def test_wrong_writer_rejected(self) -> None:
        frame = append_transition([], self.frame(), "GENESIS", 0)
        with self.assertRaises(ContractError):
            validate_ledger([frame], "V23-P00-C05", 1)

    def test_hash_tamper_rejected(self) -> None:
        frame = append_transition([], self.frame(), "GENESIS", 0)
        frame["newState"] = "ACCEPTED"
        with self.assertRaises(ContractError):
            validate_ledger([frame], "A00_BOOTSTRAP_CONTROLLER", 0)

    def test_skipped_sequence_rejected(self) -> None:
        frame = append_transition([], self.frame(), "GENESIS", 0)
        frame["sequence"] = 2
        frame = redigest(frame, "transitionDigest")
        with self.assertRaises(ContractError):
            validate_ledger([frame], "A00_BOOTSTRAP_CONTROLLER", 0)

    def test_terminal_attempt_reopen_rejected(self) -> None:
        first = append_transition([], self.frame("SUPERSEDED"), "GENESIS", 0)
        second = append_transition([first], self.frame("READY"), first["transitionDigest"], 1)
        with self.assertRaises(ContractError):
            validate_ledger([first, second], "A00_BOOTSTRAP_CONTROLLER", 0)

    def test_unlisted_transition_rejected(self) -> None:
        with self.assertRaises(ContractError):
            append_transition([], self.frame("ACCEPTED"), "GENESIS", 0)

    def test_acceptance_requires_official_authority(self) -> None:
        with self.assertRaises(ContractError):
            append_transition([], self.frame("ACCEPTED", "ACCEPTANCE_RUNNING"), "GENESIS", 0)


class AuthorityTests(unittest.TestCase):
    def initial(self) -> dict[str, Any]:
        return {"cell": "A00_BOOTSTRAP_ACTIVE", "pendingToken": None, "dispatchEnabled": True,
                "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
                "c05AttemptID": 1, "c05AttemptState": "ACCEPTANCE_RUNNING", "c05AcceptedCount": 0,
                "a00PermanentlyRevoked": False, "candidateHead": "1" * 40, "candidateTree": "2" * 40,
                "controllerEpoch": 4}

    def acceptance_authority(self, enabled: bool = True) -> dict[str, Any]:
        return {
            "adoptionEnabled": enabled, "officialDecision": "ACCEPT", "officialDecisionDigest": "a" * 64,
            "wrapperReceiptDigest": "b" * 64, "semanticEquivalenceDigest": "c" * 64,
            "effectiveAuthorizationDigest": "d" * 64, "cardID": "V23-P00-C05", "attemptID": 1,
            "candidateHead": "1" * 40, "candidateTree": "2" * 40, "acceptedS10Reconciliation": "PASS",
            "expectedPlanes": {"ledger": "3" * 64, "acceptanceEvidence": "4" * 64,
                               "hostedTransport": "5" * 64, "expectedMainBase": "6" * 64},
            "pendingEffectID": "c05-cutover-1",
        }

    def evidence(self) -> dict[str, Any]:
        authority = self.acceptance_authority()
        return {"matchingStatePlanes": authority["expectedPlanes"],
                "semanticEquivalenceDigest": authority["semanticEquivalenceDigest"],
                "officialDecisionDigest": authority["officialDecisionDigest"],
                "wrapperReceiptDigest": authority["wrapperReceiptDigest"], "effectID": authority["pendingEffectID"]}

    def proof(self) -> dict[str, Any]:
        return {"proofDigest": "7" * 64, "recoveryReceiptDigest": "8" * 64, "cardID": "V23-P00-C05",
                "attemptID": 1, "writerAuthority": {"ownerID": "V23-P00-C05", "writerGeneration": 1}}

    def test_provisional_adoption_blocked(self) -> None:
        with self.assertRaises(ContractError):
            begin_cutover(self.initial(), "t", self.acceptance_authority(False))

    def test_full_adoption_transfers_writer_once(self) -> None:
        pending = begin_cutover(self.initial(), "t", self.acceptance_authority())
        adopted = choose_branch(pending, "t", "ADOPT", self.evidence())
        self.assertEqual(adopted["writerAuthority"], {"ownerID": "V23-P00-C05", "writerGeneration": 1})
        self.assertEqual(adopted["c05AcceptedCount"], 1)

    def test_partial_adoption_rejected(self) -> None:
        pending = begin_cutover(self.initial(), "t", self.acceptance_authority())
        evidence = self.evidence(); evidence["matchingStatePlanes"].pop("expectedMainBase")
        with self.assertRaises(ContractError):
            choose_branch(pending, "t", "ADOPT", evidence)

    def test_stale_token_rejected(self) -> None:
        pending = begin_cutover(self.initial(), "t", self.acceptance_authority())
        with self.assertRaises(ContractError):
            choose_branch(pending, "other", "ADOPT", self.evidence())

    def test_abort_creates_new_attempt(self) -> None:
        pending = begin_cutover(self.initial(), "t", self.acceptance_authority())
        aborting = choose_branch(pending, "t", "ABORT", {"adoptionApplied": False, "effectID": "c05-cutover-1", "abortIntentDigest": "9" * 64})
        result = apply_abort(aborting, "t", {"effectID": "c05-cutover-1", "abortEffectDigest": "e" * 64})
        self.assertEqual((result["supersededAttemptID"], result["c05AttemptID"], result["c05AttemptState"]), (1, 2, "NOT_STARTED"))

    def test_abort_after_adoption_rejected(self) -> None:
        pending = begin_cutover(self.initial(), "t", self.acceptance_authority())
        with self.assertRaises(ContractError):
            choose_branch(pending, "t", "ABORT", {"adoptionApplied": True, "effectID": "c05-cutover-1", "abortIntentDigest": "9" * 64})

    def test_finalize_requires_proof(self) -> None:
        pending = begin_cutover(self.initial(), "t", self.acceptance_authority())
        adopted = choose_branch(pending, "t", "ADOPT", self.evidence())
        with self.assertRaises(ContractError):
            finalize_activation(adopted, "t", {})

    def test_finalize_after_proof(self) -> None:
        pending = begin_cutover(self.initial(), "t", self.acceptance_authority())
        adopted = choose_branch(pending, "t", "ADOPT", self.evidence())
        final = finalize_activation(adopted, "t", self.proof())
        self.assertEqual(final["cell"], "P00_C04_ACTIVE")

    def test_recovery_classes_closed(self) -> None:
        initial = self.initial()
        self.assertEqual(classify_recovery(initial), "A00_ACTIVE_BEFORE_PENDING")
        pending = begin_cutover(initial, "t", self.acceptance_authority())
        self.assertEqual(classify_recovery(pending), "PENDING_CUTOVER_BEFORE_BRANCH")
        adopted = choose_branch(pending, "t", "ADOPT", self.evidence())
        self.assertEqual(classify_recovery(adopted), "PENDING_P00_ACTIVATION_EFFECT_APPLIED_PROOF_PENDING")
        adopted["inclusionProofReady"] = True
        self.assertEqual(classify_recovery(adopted), "PENDING_P00_ACTIVATION_PROOF_READY_FINALIZE")

    def test_divergent_recovery_quarantined(self) -> None:
        self.assertEqual(classify_recovery({"cell": "UNKNOWN"}), "DIVERGENT_OR_AMBIGUOUS")


def main() -> int:
    if not COORDINATION.exists():
        raise SystemExit(f"coordination checkout required for bootstrap equivalence: {COORDINATION}")
    suite = unittest.defaultTestLoader.loadTestsFromModule(__import__(__name__))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = {"result": "PASS" if result.wasSuccessful() else "FAIL", "testsRun": result.testsRun,
               "failures": len(result.failures), "errors": len(result.errors),
               "phase10Polled": False, "acceptanceEnabled": False, "releaseCredit": False}
    print(json.dumps(summary, sort_keys=True))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
