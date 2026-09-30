#!/usr/bin/env python3
"""Verify C08 contracts and reusable future receipt schemas."""
from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from c07_contracts import sha256_bytes
from c08_contracts import (
    ARTIFACT_PATHS, CARD_ID, EVIDENCE_LAYERS, EXPECTED_HIG_COUNTS, FENCED_PATHS,
    INHERITED_SEMANTICS, MANIFEST_PATH, PLANNING_AUTHORITY_FACET_DIGEST,
    PLANNING_AUTHORITY_IMPACT_DIGEST, PRINCIPLES, SCHEMA_PATHS, ContractError,
    RESERVED_SHARED_DEFERRALS, STATIC_SEAM_INVENTORY,
    authority_binding, build_artifacts, build_manifest, build_outputs, common_members,
    member_digest, pretty_bytes, source_contracts,
)
from verify_c07_contracts import verify_digest

RESULT_FIELDS = [
    "startingFixtureResult", "pathResult", "checkpointResult", "branchResult",
    "endpointResult", "cancelResult", "backResult", "focusResult", "fallbackResult",
    "accessibilityResult", "result",
]
NULL_PAYLOAD_FIELDS = ["startingFixture", "typedRoute", "semanticPath", "successEndpoint",
                       "cancelBehavior", "backBehavior", "focusBehavior", "fallbackBehavior"]
EMPTY_PAYLOAD_FIELDS = ["publicUIActions", "checkpoints", "branches", "accessibilityEvidence", "artifacts"]
INTERACTION_PROVISIONAL_GATES = [
    "acceptanceEnabled", "adoptionEnabled", "archiveInspectionComplete",
    "installedRuntimeClosureComplete", "releaseHookClosureComplete", "releaseTestSupportAbsent",
    "nativeCompileRan", "hostedDispatchRan", "interactionAcceptanceSatisfied", "releaseReady",
    "acceptanceCredit", "releaseCredit",
]


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_schema(value: Any, schema: dict[str, Any], where: str = "$") -> None:
    if "anyOf" in schema:
        failures = []
        for option in schema["anyOf"]:
            try:
                validate_schema(value, option, where)
                return
            except ContractError as error:
                failures.append(str(error))
        raise ContractError(f"{where}: no anyOf branch matched: {failures}")
    if "const" in schema and value != schema["const"]:
        raise ContractError(f"{where}: const mismatch")
    if "enum" in schema and value not in schema["enum"]:
        raise ContractError(f"{where}: enum mismatch")
    expected_type = schema.get("type")
    types = {"object": dict, "array": list, "string": str, "integer": int,
             "boolean": bool, "null": type(None)}
    if expected_type:
        expected = types[expected_type]
        if not isinstance(value, expected) or (expected_type == "integer" and isinstance(value, bool)):
            raise ContractError(f"{where}: expected {expected_type}")
    if isinstance(value, dict):
        missing = set(schema.get("required", [])) - set(value)
        if missing:
            raise ContractError(f"{where}: missing {sorted(missing)}")
        properties = schema.get("properties", {})
        extras = set(value) - set(properties)
        if schema.get("additionalProperties") is False and extras:
            raise ContractError(f"{where}: extra keys {sorted(extras)}")
        for key, item in value.items():
            if key in properties:
                validate_schema(item, properties[key], f"{where}.{key}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0) or len(value) > schema.get("maxItems", sys.maxsize):
            raise ContractError(f"{where}: item count")
        prefix = schema.get("prefixItems", [])
        for index, item_schema in enumerate(prefix):
            if index < len(value):
                validate_schema(value[index], item_schema, f"{where}[{index}]")
        items = schema.get("items")
        if items is False and len(value) > len(prefix):
            raise ContractError(f"{where}: extra array items")
        if isinstance(items, dict):
            for index, item in enumerate(value[len(prefix):], len(prefix)):
                validate_schema(item, items, f"{where}[{index}]")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise ContractError(f"{where}: string too short")
        if "pattern" in schema and re.fullmatch(schema["pattern"], value) is None:
            raise ContractError(f"{where}: pattern mismatch")
    if isinstance(value, int) and not isinstance(value, bool) and value < schema.get("minimum", value):
        raise ContractError(f"{where}: below minimum")


def reject(callable_value: Any) -> None:
    try:
        callable_value()
    except (ContractError, ValueError):
        return
    raise ContractError("hostile C08 case did not fail")


def receipt_rows(artifact: dict[str, Any]) -> list[dict[str, Any]]:
    return artifact.get("journeys", artifact.get("commonJourneys", [])) + artifact.get("featureJourneys", [])


def validate_semantics(artifacts: list[dict[str, Any]], sources: dict[str, Any], root: Path) -> None:
    policy, common_release, common_receipt, feature_release, feature_receipt, _, owner_receipt, layers, interaction = artifacts
    expected_common = common_members(sources["common"])
    if policy["authority"] != authority_binding() or any(item["authority"] != policy["authority"] for item in artifacts):
        raise ContractError("cross-artifact authority binding differs")
    authority = policy["authority"]
    if authority["planningAuthorityImpactDigest"] != PLANNING_AUTHORITY_IMPACT_DIGEST or authority["planningAuthorityFacetDigest"] != PLANNING_AUTHORITY_FACET_DIGEST:
        raise ContractError("planning authority impact/facet binding differs")
    if authority["directPrerequisite"] != {
        "cardID": "V23-P00-C06", "contextDigest": "afbb364ed404d4fbd57ee66c5707c8f670a002b8d81cdc425cc6a0cfb3c53d60",
        "fenceDigest": "ca49bcc135ddc270e18c42b808a804a6b1de71bb8a08647b32bccd3b1a9a6eca",
        "verificationDigest": "77444d12c7a2bec4b09f16e96fcb70f8278805d58200a15cd8033263eb4d53b8",
        "checkpointDigest": "8bdd5bcee83c136496e1ca6bd4b2a9ec79719ecf002d6f8bca9b73d853fc03ee",
        "platformArtifactDigest": "ba548ef8cec1be0d290c300ebf88f10239640bc57e35841843aa4632d4bbed6b",
        "toolingManifestDigest": "33e5f0043ab318261ec63ee92b0bc4360215e5fd7bd7ac279b647738b743198e",
        "predecessorCandidateHead": "e6bfa3dd047e15b71f132b76db2e358bc734bfb0",
        "predecessorCandidateTree": "e333cf05f1256b2636f31c96cf1d74d323d61193",
        "releaseTestSupportAbsent": False,
    }:
        raise ContractError("C06 direct prerequisite binding differs")
    if policy["principles"] != PRINCIPLES or len(policy["principles"]) != 5:
        raise ContractError("five-principle closure differs")
    snapshot = policy["higSnapshot"]
    if snapshot["rows"] != sources["hig"] or snapshot["rowCount"] != 157 or snapshot["dispositionCounts"] != EXPECTED_HIG_COUNTS:
        raise ContractError("exact HIG source matrix differs")
    if policy["inheritedSemantics"] != INHERITED_SEMANTICS:
        raise ContractError("inherited semantic closure differs")
    seam = policy["currentSeamObservation"]
    if (seam["inventory"] != STATIC_SEAM_INVENTORY or
            seam["reservedSharedOwnerDeferrals"] != RESERVED_SHARED_DEFERRALS or
            seam["productMutation"] or seam["acceptedS10Baseline"] != "NOT_FABRICATED_RECONCILIATION_REQUIRED"):
        raise ContractError("static seam observation/deferral closure differs")
    if any(not (root / row["path"]).is_file() for row in STATIC_SEAM_INVENTORY + RESERVED_SHARED_DEFERRALS):
        raise ContractError("static seam observation path missing")
    laws = policy["laws"]
    if laws["actionAndSearchLaw"] != {
        "maximumAppAuthoredToolbarGroupsBeforeNativeOverflow": 3,
        "systemItemsExcludedFromGroupCount": True, "dominantTaskActionCount": 1,
        "searchDispositionCardinalityPerSearchableSurface": 1,
        "closedSearchDispositionsInclude": "NO_SEARCH_WITH_RATIONALE",
        "gestureOnlyRequiredAction": "FORBIDDEN", "minimumAppAuthoredTargetPoints": 44,
        "maximumAcknowledgementMilliseconds": 100,
    }:
        raise ContractError("action/search law differs")
    if laws["ownershipBoundary"]["unknownOrCustomOwnership"] != "FAIL_CLOSED" or not laws["nativeComponentLaw"]["systemComponentsDefault"]:
        raise ContractError("native ownership law differs")
    if laws["loadingTokenLaw"]["duplicateEffect"] != "FORBIDDEN" or laws["loadingTokenLaw"]["staleSuccess"] != "FORBIDDEN":
        raise ContractError("loading token fencing differs")
    performance = laws["performanceLaw"]
    if (performance["tiers"] != ["AUTOMATED_SIMULATOR_REGRESSION", "OWNER_PHYSICAL_RELEASE"] or
            performance["measuredRepetitions"] != 20 or performance["additionalBatchMaximum"] != 10 or
            performance["additionalBatchConditionPercent"] != 5 or performance["gateStatistic"] != "P95" or
            not performance["zeroHangsRequired"]):
        raise ContractError("performance law differs")
    if len(laws["staticScanners"]) != 8 or len(laws["releaseExclusion"]) != 5 or any(row["status"] != "NOT_RUN" for row in laws["deferrals"]):
        raise ContractError("scanner/release/deferral law differs")
    expected_common_ids = [row["id"] for row in sources["common"]]
    if common_release["orderedMembers"] != expected_common or [row["id"] for row in common_release["orderedMembers"]] != expected_common_ids:
        raise ContractError("exact common journey semantics/order differs")
    if feature_release["orderedMembers"] != sources["feature"] or [row["id"] for row in feature_release["orderedMembers"]] != [f"FJ{i:02d}" for i in range(1, 18)]:
        raise ContractError("exact feature journey semantics/order differs")
    if feature_release["receiptBindingContract"] != {
        "requiredPerMember": ["STARTING_FIXTURE", "PUBLIC_UI_ACTIONS", "CHECKPOINTS", "BRANCHES",
                              "SUCCESS_ENDPOINT", "ACCESSIBILITY_EVIDENCE", "FALLBACK_BEHAVIOR",
                              "ARTIFACT_REFERENCES", "EVIDENCE_LAYER_RESULTS"],
        "concreteRouteIdentifiers": "REQUIRED_CONSUMER_ENROLLMENT_NO_INVENTED_IMPLEMENTATION",
        "zeroMissingMembers": True,
    }:
        raise ContractError("feature receipt binding contract differs")
    if layers["layers"] != EVIDENCE_LAYERS:
        raise ContractError("evidence layer order differs")
    for receipt, release in ((common_receipt, common_release), (feature_receipt, feature_release)):
        expected_digests = [member_digest(member) for member in release["orderedMembers"]]
        if receipt["releaseDigest"] != release["artifactDigest"] or receipt["memberDigests"] != expected_digests:
            raise ContractError("receipt release/member digest binding differs")
        if [row["memberDigest"] for row in receipt["journeys"]] != expected_digests:
            raise ContractError("receipt row member digest binding differs")
    if owner_receipt["commonReleaseDigest"] != common_release["artifactDigest"] or owner_receipt["featureReleaseDigest"] != feature_release["artifactDigest"]:
        raise ContractError("owner receipt journey release binding differs")
    all_rows = receipt_rows(common_receipt) + receipt_rows(feature_receipt) + receipt_rows(owner_receipt)
    if any(row[field] != "NOT_RUN" for row in all_rows for field in RESULT_FIELDS):
        raise ContractError("journey receipt fabricates evidence")
    if any(row["artifacts"] or not row["blocksAcceptance"] for row in all_rows):
        raise ContractError("NOT_RUN receipt does not block")
    if any(any(row[field] is not None for field in NULL_PAYLOAD_FIELDS) or
           any(row[field] for field in EMPTY_PAYLOAD_FIELDS) or
           any(layer["result"] != "NOT_RUN" or layer["artifactReferences"]
               for layer in row["evidenceLayerResults"]) for row in all_rows):
        raise ContractError("NOT_RUN receipt contains evidence payload")
    if any(receipt["candidateHead"] is not None or receipt["candidateTree"] is not None for receipt in (common_receipt, feature_receipt, owner_receipt)):
        raise ContractError("NOT_RUN receipt binds fabricated candidate")
    if any((common_receipt["receiptSatisfied"], feature_receipt["receiptSatisfied"], owner_receipt["receiptSatisfied"])):
        raise ContractError("C08 overclaims closure")
    if any(interaction[field] for field in INTERACTION_PROVISIONAL_GATES):
        raise ContractError("C08 interaction receipt prematurely promotes a provisional gate")
    if interaction["acceptedS10BaselineDigest"] is not None:
        raise ContractError("C08 interaction receipt fabricates an accepted S10 baseline digest")
    if interaction["releaseTestSupportBlocker"]["releaseAbsenceSatisfied"]:
        raise ContractError("C07 blocker was dropped")
    if interaction["acceptedS10Baseline"] != "NOT_FABRICATED_RECONCILIATION_REQUIRED":
        raise ContractError("S10 baseline fabricated")


def future_pass_probe(receipt: dict[str, Any], schema: dict[str, Any]) -> None:
    probe = copy.deepcopy(receipt)
    probe["candidateHead"] = "a" * 40
    probe["candidateTree"] = "b" * 40
    probe["evidenceStatus"] = "PASS"
    probe["receiptSatisfied"] = True
    probe["acceptanceCredit"] = True
    for row in receipt_rows(probe):
        for field in NULL_PAYLOAD_FIELDS:
            row[field] = f"accepted-{field}"
        for field in EMPTY_PAYLOAD_FIELDS:
            row[field] = [f"artifact://accepted-{field}"]
        for field in RESULT_FIELDS:
            row[field] = "PASS"
        for layer in row["evidenceLayerResults"]:
            layer["result"] = "PASS"
            layer["artifactReferences"] = ["artifact://accepted-layer-evidence"]
        row["blocksAcceptance"] = False
    validate_schema(probe, schema)


def future_interaction_pass_probe(receipt: dict[str, Any], schema: dict[str, Any]) -> None:
    probe = copy.deepcopy(receipt)
    probe["candidateHead"] = "c" * 40
    probe["candidateTree"] = "d" * 40
    probe["nativeEvidence"] = "PASS"
    probe["dualRuntimeSemanticParity"] = "PASS"
    probe["performanceEvidence"]["simulator"] = "PASS"
    probe["performanceEvidence"]["ownerPhysical"] = "PASS"
    probe["performanceEvidence"]["zeroHangProof"] = "PASS"
    probe["performanceEvidence"]["p95GateEvaluated"] = True
    probe["archiveReleaseExclusion"] = "PASS"
    probe["acceptedS10Baseline"] = "ACCEPTED"
    probe["acceptedS10BaselineDigest"] = "e" * 64
    for field in INTERACTION_PROVISIONAL_GATES:
        probe[field] = True
    validate_schema(probe, schema)


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    expected = build_outputs(root)
    checks = 0
    for relative, value in expected.items():
        if not (root / relative).is_file() or (root / relative).read_bytes() != pretty_bytes(value):
            raise ContractError(f"generated output differs: {relative}")
        checks += 1
    artifacts = [load(root / path) for path in ARTIFACT_PATHS]
    schemas = [load(root / path) for path in SCHEMA_PATHS]
    identities = [artifact["schema"] for artifact in artifacts]
    if [schema["title"] for schema in schemas] != identities or [schema["$id"].rsplit("/", 1)[-1] for schema in schemas] != [f"{name}.schema.json" for name in identities]:
        raise ContractError("nine schema/artifact pair identities differ")
    checks += 1
    for schema, artifact in zip(schemas, artifacts):
        validate_schema(artifact, schema)
        verify_digest(artifact)
        checks += 2
    sources = source_contracts(root)
    validate_semantics(artifacts, sources, root)
    checks += 12
    for receipt_index in (2, 4, 6):
        future_pass_probe(artifacts[receipt_index], schemas[receipt_index])
        checks += 1
    future_interaction_pass_probe(artifacts[8], schemas[8])
    checks += 1

    hostile_cases = []
    for kind in ("hig_duplicate", "hig_reorder", "hig_missing", "j_duplicate", "j_reorder",
                 "j_missing", "fj_duplicate", "fj_reorder", "fj_missing", "sixth_principle",
                 "wrong_layer", "authority", "law"):
        hostile = copy.deepcopy(artifacts)
        if kind == "hig_duplicate": hostile[0]["higSnapshot"]["rows"][1] = hostile[0]["higSnapshot"]["rows"][0]
        elif kind == "hig_reorder": hostile[0]["higSnapshot"]["rows"][0:2] = reversed(hostile[0]["higSnapshot"]["rows"][0:2])
        elif kind == "hig_missing": hostile[0]["higSnapshot"]["rows"].pop()
        elif kind == "j_duplicate": hostile[1]["orderedMembers"][1] = hostile[1]["orderedMembers"][0]
        elif kind == "j_reorder": hostile[1]["orderedMembers"][0:2] = reversed(hostile[1]["orderedMembers"][0:2])
        elif kind == "j_missing": hostile[1]["orderedMembers"].pop()
        elif kind == "fj_duplicate": hostile[3]["orderedMembers"][1] = hostile[3]["orderedMembers"][0]
        elif kind == "fj_reorder": hostile[3]["orderedMembers"][0:2] = reversed(hostile[3]["orderedMembers"][0:2])
        elif kind == "fj_missing": hostile[3]["orderedMembers"].pop()
        elif kind == "sixth_principle": hostile[0]["principles"].append("ORNAMENT")
        elif kind == "wrong_layer": hostile[7]["layers"][0] = "PIXEL_SNAPSHOT"
        elif kind == "authority": hostile[0]["authority"]["planningAuthorityImpactDigest"] = "0" * 64
        elif kind == "law": hostile[0]["laws"]["actionAndSearchLaw"]["maximumAppAuthoredToolbarGroupsBeforeNativeOverflow"] = 4
        hostile_cases.append(hostile)
    for gate in INTERACTION_PROVISIONAL_GATES:
        hostile = copy.deepcopy(artifacts)
        hostile[8][gate] = True
        hostile_cases.append(hostile)
    fabricated_baseline = copy.deepcopy(artifacts)
    fabricated_baseline[8]["acceptedS10BaselineDigest"] = "f" * 64
    hostile_cases.append(fabricated_baseline)
    for hostile in hostile_cases:
        reject(lambda value=hostile: validate_semantics(value, sources, root))
        checks += 1
    digest_mutation = copy.deepcopy(artifacts[1])
    digest_mutation["artifactDigest"] = "0" * 64
    reject(lambda: verify_digest(digest_mutation)); checks += 1
    schema_extra = copy.deepcopy(artifacts[0])
    schema_extra["unexpected"] = True
    reject(lambda: validate_schema(schema_extra, schemas[0])); checks += 1

    regenerated = list(build_artifacts(root).values())
    if [pretty_bytes(value) for value in regenerated] != [pretty_bytes(value) for value in artifacts]:
        raise ContractError("interruption regeneration differs")
    validate_semantics(regenerated, sources, root)
    checks += 2
    manifest = load(root / MANIFEST_PATH)
    if manifest != build_manifest(root) or manifest["pathFence"] != FENCED_PATHS or manifest["artifactCount"] != 21:
        raise ContractError("C08 tooling manifest differs")
    verify_digest(manifest)
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"manifest hash differs: {row['path']}")
    checks += 3
    run = subprocess.run([sys.executable, "-B", str(root / "Scripts/v23/generate_c08_contracts.py"),
                          "--check", "--root", str(root)], check=True, capture_output=True, text=True,
                         env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    if "PASS V23-P00-C08" not in run.stdout:
        raise ContractError("generator check failed")
    checks += 1
    print(json.dumps({"result": "PASS", "cardID": CARD_ID, "checks": checks,
        "schemaArtifactPairCount": 9, "futurePassSchemaProbes": 4,
        "hostileMutationCount": len(hostile_cases) + 2,
        "principleCount": 5, "higRowCount": 157, "higDispositionCounts": EXPECTED_HIG_COUNTS,
        "commonJourneyCount": 14, "featureJourneyCount": 17, "evidenceLayerCount": 3,
        "nativeCompileRan": False, "dualRuntimeEvidence": "NOT_RUN", "performanceEvidence": "NOT_RUN",
        "archiveEvidence": "NOT_RUN", "releaseTestSupportAbsent": False,
        "phase10PollingDuringParallelExecution": False, "acceptanceCredit": False,
        "releaseReady": False, "releaseCredit": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
