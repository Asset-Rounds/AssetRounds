#!/usr/bin/env python3
"""Hostile static verifier for Card 35's closed finding lifecycle."""
from __future__ import annotations
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any
sys.dont_write_bytecode = True
import p03_c04_contracts as contracts

class VerificationError(RuntimeError):
    pass

def require(condition: bool, message: str) -> None:
    if not condition: raise VerificationError(message)

def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True, encoding="utf-8").stdout.strip()

def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def changed_paths(root: Path) -> set[str]:
    tracked = set(filter(None, git(root, "diff", "--name-only", contracts.APP_BASE_HEAD).splitlines()))
    untracked = set(filter(None, git(root, "ls-files", "--others", "--exclude-standard").splitlines()))
    return {path.replace("\\", "/") for path in tracked | untracked}

def strict_objects(node: Any, path: str) -> None:
    if isinstance(node, dict):
        if node.get("type") == "object":
            require(node.get("additionalProperties") is False, f"{path}: open object schema")
            require(isinstance(node.get("properties"), dict), f"{path}: object properties absent")
            require(isinstance(node.get("required"), list), f"{path}: required set absent")
            require(set(node["required"]) <= set(node["properties"]), f"{path}: required key is not declared")
        for key, value in node.items(): strict_objects(value, f"{path}/{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node): strict_objects(value, f"{path}/{index}")

def verify(root: Path) -> dict[str, Any]:
    require(git(root, "rev-parse", "HEAD") == contracts.APP_BASE_HEAD, "application HEAD differs from hydrated base")
    require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE, "application base tree differs")
    expected_authority = {
        "COORDINATION_HEAD": "99765a544d0d5a5a2d0b39636928ef337441b3c7",
        "COORDINATION_TREE": "68f3a0d250227a8359e8a9f0bee922d2008d88f4",
        "COORDINATION_CAS_SEQUENCE": 148,
        "COORDINATION_LEDGER_DIGEST": "225aab4d7ef7818d1b0a81703456274c7fb74dd1bf16c62d1f672bbf090c6b0a",
        "CONTEXT_DIGEST": "08b416bc888cf2ce2cc408b1ad93163a23022ff078af002bb9aedc83baaf12ab",
        "FENCE_DIGEST": "cafb01052cd0eb74fb7a90f0815439d3e3b29811c3a8b920fbae4d948d5c166c",
        "PREREQUISITE_DIGEST": "19c5febfafc1574a9b3c15e9621b3d149996c8b9458e04ced71475359751adab",
        "TRANSITION_DIGEST": "f88bc4a4adc884137d6a6b238df0b8037b65d7a76b4d8907c7e09fa3fb7f700e",
        "HYDRATION_PROJECTION_DIGEST": "14857ad67f63d5c492d613e706190d50041ed31aa637f8c3ef80879e5c66b650",
    }
    for name, expected in expected_authority.items(): require(getattr(contracts, name) == expected, f"authority constant differs: {name}")
    require(len(contracts.PATH_FENCE) == 24 and len(set(contracts.PATH_FENCE)) == 24, "path fence is not exact")
    require(contracts.EXISTING_PATHS == [] and contracts.NEW_PATHS == contracts.PATH_FENCE, "fence is not all-new")
    require(len(contracts.SOURCE_PATHS) == 9 and len(contracts.TOOL_PATHS) == 15, "source/tool partition differs")
    for relative in contracts.PATH_FENCE: require((root / relative).is_file(), f"missing fenced path: {relative}")
    observed = changed_paths(root)
    require(observed == set(contracts.PATH_FENCE), f"changed path set differs: {sorted(observed ^ set(contracts.PATH_FENCE))}")
    base_existing = [path for path in contracts.PATH_FENCE if subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{contracts.APP_BASE_HEAD}:{path}"], capture_output=True).returncode == 0]
    require(not base_existing, f"all-new fence contains base paths: {base_existing}")
    reservation = load(root / "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json")
    require(reservation["contentDigest"] == contracts.S10_RESERVATION_DIGEST, "S10 reservation digest differs")
    require(reservation["reservedPathCount"] == 86 and len(reservation["reservedPaths"]) == 86, "S10 reservation count differs")
    require(not set(contracts.PATH_FENCE) & set(reservation["reservedPaths"]), "Phase 10 reservation overlap")
    require(not any("__pycache__" in path or path.endswith((".pyc", ".pyo")) for path in observed), "Python cache leaked into fence")

    outputs = contracts.all_outputs(root)
    require(set(outputs) == set(contracts.GENERATED_PATHS), "generated output set differs")
    for relative, expected in outputs.items(): require((root / relative).read_bytes() == expected, f"stale generated artifact: {relative}")

    titles = []
    schema_values = {}
    for relative in contracts.SCHEMA_PATHS:
        value = load(root / relative)
        require(value.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{relative}: dialect differs")
        require(value.get("type") == "object" and value.get("additionalProperties") is False, f"{relative}: root not closed")
        strict_objects(value, relative)
        titles.append(value["title"])
        schema_values[relative] = value
    require(len(set(titles)) == 6, "schema titles differ or collide")
    exact_shapes = {
        contracts.SCHEMA_PATHS[0]: ({"schemaVersion", "findingID", "revision", "severity", "categoryID", "subject", "source", "summary"}, set()),
        contracts.SCHEMA_PATHS[1]: ({"schemaVersion", "transitionID", "findingID", "expectedFindingRevision", "resultingFindingRevision", "mutationID", "fromState", "toState", "actorID", "reason", "effectiveAt", "verifiedRecheckID"}, {"verifiedRecheckID"}),
        contracts.SCHEMA_PATHS[2]: ({"schemaVersion", "linkID", "findingID", "findingRevision", "workID", "workRevision", "expectedLinkRevision", "resultingLinkRevision", "mutationID", "action", "actorID", "reason", "effectiveAt", "supersedesLinkEventID"}, {"supersedesLinkEventID"}),
        contracts.SCHEMA_PATHS[3]: ({"schemaVersion", "recheckID", "findingID", "findingRevision", "correctiveWorkID", "correctiveWorkRevision", "priorRecheckID", "evidenceRevisionIDs", "expectedRecheckRevision", "resultingRecheckRevision", "mutationID", "outcome", "verifierActorID", "verifierAuthority", "reason", "effectiveAt"}, {"priorRecheckID"}),
        contracts.SCHEMA_PATHS[4]: ({"schemaVersion", "relationshipID", "sourceWorkID", "sourceWorkRevision", "targetWorkID", "targetWorkRevision", "kind", "direction", "reason", "actorID", "mutationID", "createdAt"}, set()),
    }
    for relative, (properties, optional) in exact_shapes.items():
        value = schema_values[relative]
        require(set(value["properties"]) == properties, f"{relative}: model property projection differs")
        require(set(value["required"]) == properties - optional, f"{relative}: optional/required projection differs")
    require("decision" not in schema_values[contracts.SCHEMA_PATHS[4]]["properties"], "WorkRelationshipV1 schema embeds decision ownership")
    id_shape = {"type": "string", "pattern": "^[a-z0-9._-]+$", "maxLength": 128}
    root_id_fields = {
        contracts.SCHEMA_PATHS[0]: ["findingID", "categoryID"],
        contracts.SCHEMA_PATHS[1]: ["transitionID", "findingID", "mutationID", "actorID", "verifiedRecheckID"],
        contracts.SCHEMA_PATHS[2]: ["linkID", "findingID", "workID", "mutationID", "actorID", "supersedesLinkEventID"],
        contracts.SCHEMA_PATHS[3]: ["recheckID", "findingID", "correctiveWorkID", "priorRecheckID", "mutationID", "verifierActorID"],
        contracts.SCHEMA_PATHS[4]: ["relationshipID", "sourceWorkID", "targetWorkID", "actorID", "mutationID"],
    }
    for relative, fields in root_id_fields.items():
        for field in fields:
            require(schema_values[relative]["properties"][field] == id_shape, f"{relative}: ID constraint differs for {field}")
    finding_properties = schema_values[contracts.SCHEMA_PATHS[0]]["properties"]
    for nested, fields in {"severity": ["severityID", "severityScaleReleaseID"], "subject": ["subjectKindID", "subjectID"]}.items():
        for field in fields:
            require(finding_properties[nested]["properties"][field] == id_shape, f"finding schema nested ID differs: {nested}.{field}")
    source_evidence = finding_properties["source"]["properties"]["evidenceRevisionIDs"]
    require(source_evidence["items"] == id_shape and source_evidence["uniqueItems"] is True and source_evidence["maxItems"] == 32, "finding source ID-array constraints differ")
    recheck_evidence = schema_values[contracts.SCHEMA_PATHS[3]]["properties"]["evidenceRevisionIDs"]
    require(recheck_evidence["items"] == id_shape and recheck_evidence["minItems"] == 1 and recheck_evidence["maxItems"] == 32 and recheck_evidence["uniqueItems"] is True, "verified-recheck evidence ID-array constraints differ")
    transition_conditions = schema_values[contracts.SCHEMA_PATHS[1]]["allOf"]
    require(len(transition_conditions) == 2, "finding transition iff condition count differs")
    require(transition_conditions[0]["then"] == {"required": ["verifiedRecheckID"]}, "verified resolution does not require recheck ID")
    require(transition_conditions[1]["then"] == {"properties": {"toState": {"const": "VERIFIED_RESOLVED"}}}, "recheck ID does not imply verified resolution")
    work_conditions = schema_values[contracts.SCHEMA_PATHS[2]]["allOf"]
    require(work_conditions == [{"if": {"properties": {"action": {"const": "REMOVED"}}, "required": ["action"]}, "then": {"required": ["supersedesLinkEventID"]}}], "corrective removal predecessor condition differs")
    relationship_conditions = schema_values[contracts.SCHEMA_PATHS[4]]["allOf"]
    require(relationship_conditions == [
        {"if": {"properties": {"kind": {"const": "DUPLICATE_OF"}}, "required": ["kind"]}, "then": {"properties": {"direction": {"const": "DIRECTED"}}}},
        {"if": {"properties": {"kind": {"const": "RELATED_TO"}}, "required": ["kind"]}, "then": {"properties": {"direction": {"const": "SYMMETRIC"}}}},
    ], "work relationship kind/direction condition differs")

    fixture_path = root / contracts.SOURCE_PATHS[-1]
    fixture = load(fixture_path)
    require(fixture_path.read_bytes() == contracts.canonical(fixture) + b"\n", "fixture is not canonical compact sorted JSON plus LF")
    require(fixture.get("schema") == "V21P03C04FindingLifecycleCorpusV1", "fixture schema differs")
    require(fixture.get("schemaVersion") == 1 and fixture.get("testOnly") is True, "fixture version/test-only differs")
    fixture_text = fixture_path.read_text(encoding="utf-8")
    for marker in ["DORMANT_REVERT_ALLOWED", "DECLARATION_ONLY", "KERNEL_FINDING_V1", "DUPLICATE_OF", "RELATED_TO", "NOT_RELATED", "REMOVE_RELATION"]:
        require(marker in fixture_text, f"fixture semantic marker missing: {marker}")
    require(fixture["severityBinding"] == {"fields": ["severityID", "severityScaleReleaseID", "severityScaleSHA256"], "scaleReleaseID": "severity-scale.fixture.release.v1", "scaleSHA256": "d" * 64, "taxonomyOwner": "V23-P03-C40"}, "fixture severity binding differs")
    require(fixture["releaseToService"] == {"automaticFromRepairClosure": False, "requiresExplicitHumanDisposition": True, "requiresExplicitReleaseRecord": True, "requiresPassingVerifiedRecheck": True}, "fixture release-to-service policy differs")
    require("RETURNED_TO_SERVICE_WITHOUT_EXPLICIT_RELEASE" in fixture["negativeCases"], "fixture omits human disposition/release negative")
    require(fixture["canonicalAggregate"] == {"codec": "FindingLifecycleCanonicalEvidenceCodecV1", "correctiveTargetRequired": True, "exactByteReconciliation": True, "findingScoped": True, "relationshipBasisRequired": True, "releaseRequiresActualPassingRecheck": True, "returnedDispositionRequiresExactRelease": True}, "fixture canonical aggregate policy differs")
    for hostile in ["ARBITRARY_RESOLUTION_RECHECK", "CORRECTIVE_TARGET_MISSING_OR_REMOVED", "FABRICATED_SUGGESTION_DIVERGENT_BASIS", "RELEASE_ACTUAL_RECHECK_MISSING_OR_MISMATCHED", "RETURNED_DISPOSITION_RELEASE_MISMATCH"]:
        require(hostile in fixture["negativeCases"], f"fixture canonical hostile case missing: {hostile}")

    methods = contracts.test_methods(root)
    require(len(methods) == 5, "named test count differs")
    contracts.require_semantics(root)
    all_source = "\n".join((root / path).read_text(encoding="utf-8") for path in contracts.SOURCE_PATHS)
    finding_source = (root / contracts.SOURCE_PATHS[0]).read_text(encoding="utf-8")
    lifecycle_source = (root / contracts.SOURCE_PATHS[1]).read_text(encoding="utf-8")
    release_source = (root / contracts.SOURCE_PATHS[4]).read_text(encoding="utf-8")
    related_source = (root / contracts.SOURCE_PATHS[5]).read_text(encoding="utf-8")
    registry_source = (root / contracts.SOURCE_PATHS[6]).read_text(encoding="utf-8")
    test_source = (root / contracts.SOURCE_PATHS[7]).read_text(encoding="utf-8")
    require("FindingSeverityBindingV1" in finding_source and "FindingSeverityV1" not in finding_source, "severity is not an external stable binding")
    for marker in ["severityID", "severityScaleReleaseID", "severityScaleSHA256"]:
        require(marker in finding_source, f"severity binding marker missing: {marker}")
    for marker in ["releaseToServiceID", "validateVerifiedResolutionLineage", "validateReturnedToService"]:
        require(marker in lifecycle_source, f"human disposition/release lineage marker missing: {marker}")
    for marker in ["verifiedRecheckOutcome", "verifiedRecheckOutcome == .passed", "authorizingActorID", "authority", "reason"]:
        require(marker in release_source, f"explicit human release marker missing: {marker}")
    for marker in ["policySHA256", "RelatedWorkSuggestionV1.identity", "suggestionID"]:
        require(marker in related_source, f"decision suggestion-basis marker missing: {marker}")
    for marker in ["FindingLifecycleCanonicalEvidenceV1", "FindingLifecycleCanonicalEvidenceCodecV1", "correctiveWorkLinks", "verifiedRechecks", "releasesToService", "operationalDispositionEvents", "relatedWorkSuggestions", "workRelationships", "workRelationshipDecisions", "canonicalEvidenceIncomplete", "validateVerifiedResolutionLineage", "validateReturnedToService", "RelatedWorkSuggestionV1.identity", "policySHA256"]:
        require(marker in registry_source, f"canonical aggregate marker missing: {marker}")
    require("$0.subjectID == finding.subject.subjectID" in registry_source and "$0.categoryID == finding.categoryID" in registry_source, "related suggestion finding subject/category scope missing")
    require('suggestions[0]["subjectID"] = "asset.other"' in test_source, "hostile related-suggestion subject mismatch test missing")
    for marker in ["canonicalEvidenceFixture", "mutatedCanonicalBytes", "CORRECTIVE_TARGET_MISSING_OR_REMOVED", "FABRICATED_SUGGESTION_DIVERGENT_BASIS"]:
        require(marker in test_source or marker in fixture_text, f"cross-record test/evidence marker missing: {marker}")
    for forbidden in [r"\bURLSession\b", r"\bCloudKit\b", r"\bFirebase\b", r"\bTestFlight\b", r"\bAppStore\b", r"acceptanceCredit\s*[:=]\s*true", r"releaseCredit\s*[:=]\s*true"]:
        require(re.search(forbidden, all_source, re.I) is None, f"forbidden source claim/token: {forbidden}")

    for relative in contracts.CONTRACT_PATHS:
        value = load(root / relative)
        require(value["cardID"] == contracts.CARD and value["schemaVersion"] == 1, f"{relative}: identity differs")
        unsigned = dict(value); recorded = unsigned.pop("artifactDigest")
        require(recorded == digest(contracts.pretty(unsigned)), f"{relative}: artifact seal differs")
        require(value["persistentChangeMode"] == "DECLARATION_ONLY" and value["persistentContractSchema"] == "KERNEL_FINDING_V1", f"{relative}: lifecycle differs")
        for flag in ["nativeCompileRan", "hostedDispatchRan", "hostedDispatchEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit", "phase10PollingDuringParallelExecution", "nativeOrHostedEvidenceClaimed", "acceptanceOrReleaseClaimed"]:
            require(value[flag] is False, f"{relative}: forbidden claim {flag}")
        authority = value["authority"]
        require(authority["coordinationAuthorityHead"] == contracts.COORDINATION_HEAD and authority["coordinationAuthorityTree"] == contracts.COORDINATION_TREE, f"{relative}: coordination binding differs")
        require(authority["coordinationLedgerDigest"] == contracts.COORDINATION_LEDGER_DIGEST and authority["coordinationCASSequence"] == 148, f"{relative}: CAS binding differs")

    evidence = load(root / contracts.CONTRACT_PATHS[-1])
    require(len(evidence["evidence"]) == 5 and [row["evidenceID"] for row in evidence["evidence"]] == contracts.EVIDENCE_IDS, "evidence families differ")
    require([row["testMethod"] for row in evidence["evidence"]] == methods, "evidence/test binding differs")
    finding_contract = load(root / contracts.CONTRACT_PATHS[0])
    require(finding_contract["severityContract"] == {"bindingType": "FindingSeverityBindingV1", "fields": ["severityID", "severityScaleReleaseID", "severityScaleSHA256"], "stableSeverityID": True, "immutableScaleReleaseBinding": True, "locallyInventedVocabulary": False}, "finding severity contract differs")
    finding_schema = load(root / contracts.SCHEMA_PATHS[0])
    severity_schema = finding_schema["properties"]["severity"]
    require(severity_schema["required"] == ["severityID", "severityScaleReleaseID", "severityScaleSHA256"], "severity schema binding differs")
    corrective_contract = load(root / contracts.CONTRACT_PATHS[2])
    require(corrective_contract["releaseSeparateFromCorrectionAndRecheck"] is True and corrective_contract["releaseSeparateHumanAuthorization"] is True, "release is not explicitly separate/human-authorized")
    require(corrective_contract["canonicalAggregateRequiresCorrectiveWorkLinks"] is True and corrective_contract["recheckRequiresHistoricallyEffectiveLinkedCorrectiveTarget"] is True, "corrective target aggregate chain differs")
    require(corrective_contract["releaseRequiresActualUniquePassingVerifiedRecheck"] is True and corrective_contract["returnedToServiceDispositionRequiresExactReleaseAndRecheck"] is True, "release/recheck/disposition chain differs")
    lifecycle_contract = load(root / contracts.CONTRACT_PATHS[1])
    aggregate_contract = lifecycle_contract["canonicalEvidence"]
    require(aggregate_contract["type"] == "FindingLifecycleCanonicalEvidenceV1" and aggregate_contract["codec"] == "FindingLifecycleCanonicalEvidenceCodecV1", "canonical aggregate identity differs")
    require(aggregate_contract["requiredFields"] == ["finding", "lifecycle", "correctiveWorkLinks", "verifiedRechecks", "releasesToService", "operationalDispositionEvents", "relatedWorkSuggestions", "workRelationships", "workRelationshipDecisions"], "canonical aggregate field set differs")
    require(aggregate_contract["canonicalSortedExactBytes"] is True and aggregate_contract["failClosedError"] == "canonicalEvidenceIncomplete", "canonical aggregate exact-byte failure policy differs")
    require(aggregate_contract["relatedSuggestionScopeFields"] == ["subjectID", "categoryID"], "canonical aggregate suggestion scope fields differ")
    related_contract = load(root / contracts.CONTRACT_PATHS[3])
    require(related_contract["decisionBasisFields"] == ["suggestionID", "sourceWorkID", "sourceWorkRevision", "candidateWorkID", "candidateWorkRevision", "policySHA256"], "related decision basis differs")
    require(related_contract["decisionDecodeRecomputesSuggestionID"] is True and related_contract["canonicalAggregateAllowsOnlyConfirmedRelationships"] is True, "related decision/relationship reconciliation differs")
    require(related_contract["canonicalAggregateSuggestionScope"] == {"subjectID": "finding.subject.subjectID", "categoryID": "finding.categoryID", "mismatchDisposition": "canonicalEvidenceIncomplete"}, "related suggestion finding scope contract differs")
    generated_text = "\n".join((root / path).read_text(encoding="utf-8") for path in contracts.GENERATED_PATHS)
    for invented in ["INFORMATIONAL", "\"LOW\"", "\"MEDIUM\"", "\"HIGH\"", "CRITICAL"]:
        require(invented not in generated_text, f"invented severity vocabulary leaked into generated artifacts: {invented}")

    manifest_path = root / contracts.MANIFEST
    manifest = load(manifest_path)
    unsigned_manifest = dict(manifest); recorded_manifest = unsigned_manifest.pop("artifactDigest")
    require(recorded_manifest == digest(contracts.pretty(unsigned_manifest)), "manifest seal differs")
    require(manifest["pathFence"] == contracts.PATH_FENCE and manifest["pathFenceCount"] == 24, "manifest fence differs")
    require(manifest["existingPaths"] == [] and len(manifest["newPaths"]) == 24, "manifest all-new partition differs")
    require(manifest["pendingArtifactCount"] == 0 and manifest["artifactCount"] == 23, "manifest artifact closure differs")
    artifact_rows = {row["path"]: row for row in manifest["artifacts"]}
    require(set(artifact_rows) == set(contracts.MANIFEST_INPUT_PATHS), "manifest artifact paths differ")
    for relative, row in artifact_rows.items():
        data = (root / relative).read_bytes()
        require(row == {"path": relative, "bytes": len(data), "sha256": digest(data)}, f"manifest artifact binding differs: {relative}")
    for flag in ["nativeCompileRan", "hostedDispatchRan", "hostedDispatchEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit", "phase10PollingDuringParallelExecution", "nativeOrHostedEvidenceClaimed", "acceptanceOrReleaseClaimed"]:
        require(manifest[flag] is False, f"manifest forbidden claim: {flag}")

    return {"result": "PASS", "cardID": contracts.CARD, "pathFenceCount": 24, "changedPathCount": 24, "sourcePathCount": 9, "strictSchemaCount": 6, "contractDocumentCount": 5, "namedStaticTestCount": 5, "fixtureSHA256": digest(fixture_path.read_bytes()), "manifestSHA256": digest(manifest_path.read_bytes()), "nativeCompileRan": False, "hostedDispatchRan": False, "acceptanceCredit": False, "releaseCredit": False, "requiresAcceptedS10_6Reconciliation": True, "phase10PollingDuringParallelExecution": False}

def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"V23-P03-C04 hostile verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
