#!/usr/bin/env python3
"""Verify C13 coverage contracts, schemas, parsers, and hostile cases."""
from __future__ import annotations

import ast
import copy
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from c07_contracts import seal, sha256_bytes
from c13_contracts import (
    ARTIFACT_PATHS, BASE_HEAD, BASE_TREE, CARD_ID, DIFF_COMMAND, EXCLUSION_KINDS,
    FENCED_PATHS, MANIFEST_PATH, PROTECTED_EXCLUSION_TOKENS, SCHEMA_PATHS, TIER_FLOORS,
    ContractError, authority_binding, build_artifacts, build_manifest, build_outputs,
    evaluate_tier, parse_changed_lines, pretty_bytes, validate_exclusion,
    validate_exclusion_set, validate_changed_line_sets, validate_pass_closure,
)
from verify_c07_contracts import verify_digest


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_schema(value: Any, schema: dict[str, Any], where: str = "$") -> None:
    if "anyOf" in schema:
        for option in schema["anyOf"]:
            try:
                validate_schema(value, option, where)
                return
            except ContractError:
                pass
        raise ContractError(f"{where}: no anyOf branch matched")
    if "const" in schema and value != schema["const"]:
        raise ContractError(f"{where}: const mismatch")
    if "enum" in schema and value not in schema["enum"]:
        raise ContractError(f"{where}: enum mismatch")
    expected_type = schema.get("type")
    types = {"object": dict, "array": list, "string": str, "integer": int,
             "number": (int, float), "boolean": bool, "null": type(None)}
    if expected_type:
        expected = types[expected_type]
        if not isinstance(value, expected) or (expected_type in ("integer", "number") and isinstance(value, bool)):
            raise ContractError(f"{where}: expected {expected_type}")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        missing = set(schema.get("required", [])) - set(value)
        extras = set(value) - set(properties)
        if missing or (schema.get("additionalProperties") is False and extras):
            raise ContractError(f"{where}: missing={sorted(missing)} extras={sorted(extras)}")
        for key, item in value.items():
            if key in properties:
                validate_schema(item, properties[key], f"{where}.{key}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0) or len(value) > schema.get("maxItems", sys.maxsize):
            raise ContractError(f"{where}: item count")
        prefix = schema.get("prefixItems", [])
        for index, item_schema in enumerate(prefix):
            if index < len(value): validate_schema(value[index], item_schema, f"{where}[{index}]")
        items = schema.get("items")
        if items is False and len(value) > len(prefix): raise ContractError(f"{where}: extra items")
        if isinstance(items, dict):
            for index, item in enumerate(value[len(prefix):], len(prefix)):
                validate_schema(item, items, f"{where}[{index}]")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0): raise ContractError(f"{where}: short string")
        if "pattern" in schema and re.fullmatch(schema["pattern"], value) is None:
            raise ContractError(f"{where}: pattern mismatch")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if not math.isfinite(value): raise ContractError(f"{where}: non-finite number")
        if value < schema.get("minimum", value) or value > schema.get("maximum", value):
            raise ContractError(f"{where}: numeric range")


def reject(callable_value: Any) -> None:
    try:
        callable_value()
    except (ContractError, ValueError):
        return
    raise ContractError("hostile C13 case did not fail")


def validate_repository_state(root: Path) -> None:
    def run(*args: str) -> str:
        return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True,
                              text=True, encoding="utf-8").stdout.strip()
    head = run("rev-parse", "HEAD")
    if run("show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ContractError("local base head/tree differs")
    subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}^{{commit}}"], check=True,
                   capture_output=True)
    remote = run("ls-remote", "--heads", "origin", "refs/heads/phase/v23-expansion")
    if not remote:
        raise ContractError("remote phase/v23-expansion is absent")
    remote_head = remote.split()[0]
    status_paths = set()
    status_output = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True, encoding="utf-8",
    ).stdout
    for line in status_output.splitlines():
        if line: status_paths.add(line[3:].replace("\\", "/"))
    expected_paths = set(FENCED_PATHS)
    if head == BASE_HEAD:
        if remote_head != BASE_HEAD or status_paths != expected_paths:
            raise ContractError(
                f"pre-commit candidate is not the exact remote-base 12-path fence: {sorted(status_paths)}"
            )
        return
    ancestor = subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", BASE_HEAD, head],
        capture_output=True,
    )
    committed_paths = {
        path.replace("\\", "/")
        for path in run("diff", "--name-only", f"{BASE_HEAD}..{head}").splitlines()
        if path
    }
    if (ancestor.returncode != 0 or remote_head != head or
            not status_paths <= expected_paths or committed_paths != expected_paths):
        raise ContractError(
            "post-commit candidate/fix is not a pushed exact-fence lineage: "
            f"ancestor={ancestor.returncode} remote={remote_head} status={sorted(status_paths)} "
            f"paths={sorted(committed_paths)}"
        )


def validate_current(artifacts: list[dict[str, Any]]) -> None:
    receipt, tier, exclusion, comparison = artifacts
    authority = authority_binding()
    if any(artifact["authority"] != authority for artifact in artifacts):
        raise ContractError("C13 authority binding differs")
    if (authority["deterministicEvidenceIDs"] != [f"V23-P00-C13-{suffix}" for suffix in ("G01","A01","H01","I01","R01")] or
            authority["policyRefs"] != ["V23-POL-ARCH-001","V23-POL-IPHONE-001","V23-POL-TEST-001"] or
            authority["contractRefs"] != ["CodeCoverageReceiptV1","CoverageTierReleaseV1","CoverageExclusionV1",
                "CoverageComparisonBaseV1","DirectPrerequisiteEvidenceSetV1","CardAcceptanceInclusionProofV1",
                "CardAcceptanceInclusionProofRecoveryReceiptV1","CandidateAcceptanceCompatibilityReceiptV1"] or
            authority["journeyRefs"] != "NONE" or
            authority["aggregateAcceptanceMemberships"] != ["AutonomousRequiredAcceptedSetV1"] or
            authority["invalidationConsumers"] != ["V23-P04-C29"] or
            authority["impactManifestDigest"] != "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b" or
            authority["impactFacetDigest"] != "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f" or
            authority["impactRowDigest"] != "7699e730ad507c8109e5f371186887459f0b3807ce871cb333e31b4dddaeeba9" or
            authority["sourceDisposition"] != "PINNED_DOSSIER_STATIC_PROVISIONAL" or
            authority["fixtureDisposition"] != "UNRESOLVED_UNTIL_ACCEPTING_XCRESULT" or
            authority["currentnessDisposition"] != "UNRESOLVED_ACCEPTANCE_DISABLED"):
        raise ContractError("C13 frozen evidence/policy/impact authority differs")
    prerequisite = authority["directPrerequisite"]
    if prerequisite != {
        "cardID": "V23-P00-C12", "implementationHead": "7b72263ea2c64a8f9bace8e87872d1a293400969",
        "implementationTree": "d3fbaa46c1a35c5a52909731dfbfa30fed3b1086",
        "contextDigest": "e549afb029c183733eab5514345ad49cfda954fa9dc2842574faa9511fa69d81",
        "fenceDigest": "c23d8f566b104f8ebc4cf2192d5c06e447621f72871fb43811e59972a53d9b6d",
        "verificationDigest": "c6c3c607b1a667a1cbb227fac4128c67f5f66da4af1a3feb0cd243af991e4a96",
        "checkpointDigest": "a7d0c64d08442db60ed5dad4a19398601b58ea7e8c2ebd4797402cd8f0737764",
        "swiftLanguageModeClosureReceiptDigest": "d229005282b59b5002137b09d9415555190405eec7a51e066bc6744007f11229",
        "swiftLanguageModeClosureReceiptFileSHA256": "b367c8c87bbe897d1f8f03a730bb13ece46fd2950df3899bb56c52d5e4fef344",
        "toolingManifestDigest": "01e5960fafb04523557257e6286257cd7103c7481039ed3006345b9c18fc6c15",
        "toolingManifestFileSHA256": "6258b2ed0bf3c543ca2f1092003af2abb5668e6149e447c09a0c35b586af40e8",
        "nativeCompileRan": False, "nativeTestsRan": False,
        "languageModeClosureSatisfied": False, "acceptanceCredit": False, "releaseCredit": False,
        "directPrerequisiteEvidenceSetReceiptDigest": "035e7b80772e813cb04ade498ea0182c860fc1a7e5a32a4c41025cd47ce0ce23",
        "officialAcceptanceEvidence": {
            "CardAcceptanceInclusionProofV1Digest": None,
            "CardAcceptanceInclusionProofRecoveryReceiptV1Digest": None,
            "CandidateAcceptanceCompatibilityReceiptV1Digest": None,
            "acceptanceCurrentness": "UNRESOLVED_ACCEPTANCE_DISABLED",
            "compatibility": "UNRESOLVED_ACCEPTANCE_DISABLED",
            "zeroOrphanAcceptanceProofComplete": False,
        },
    }:
        raise ContractError("sole C12 prerequisite evidence differs")
    if tier["tiers"] != TIER_FLOORS or tier["changedLineLaw"]["command"] != DIFF_COMMAND:
        raise ContractError("coverage tier or diff law differs")
    if tier["uiAndPlatformGlue"]["coveragePercentGate"] != "FORBIDDEN_VANITY_PERCENT" or tier["performanceCoverageInstrumentation"] != "REJECTED":
        raise ContractError("UI/performance coverage law differs")
    if (exclusion["allowedKinds"] != EXCLUSION_KINDS or exclusion["protectedPathTokens"] != PROTECTED_EXCLUSION_TOKENS or
            exclusion["exclusions"] or exclusion["reviewerReceipts"]):
        raise ContractError("coverage exclusion law differs")
    if comparison["cardPreCardIntegrationBase"] != {"head": BASE_HEAD, "tree": BASE_TREE,
                                                       "purpose": "CHANGED_CODE_NON_REGRESSION"}:
        raise ContractError("pre-card comparison base differs")
    release_base = comparison["releaseClosureAcceptedS10_6Base"]
    if (release_base != {"head": None, "tree": None, "status": "UNRESOLVED_RECONCILIATION_REQUIRED"} or
            comparison["comparisonReady"] or not comparison["basesAreDistinctAuthorities"]):
        raise ContractError("accepted S10.6 base was fabricated")
    if receipt["tierReleaseDigest"] != tier["artifactDigest"] or receipt["exclusionDigest"] != exclusion["artifactDigest"] or receipt["comparisonBaseDigest"] != comparison["artifactDigest"]:
        raise ContractError("coverage receipt cross-digest differs")
    if any(receipt[key] is not None for key in ("candidateHead", "candidateTree", "acceptingXcresultPath",
                                                "acceptingXcresultDigest", "toolchainIdentity", "fixtureDigest",
                                                "changedDiffArtifactPath", "changedDiffDigest",
                                                "changedCandidateLineSetDigest")):
        raise ContractError("NOT_RUN receipt binds candidate/xcresult")
    if receipt["xcresultReusePolicy"] != "SAME_ACCEPTING_XCRESULT_BUNDLES_ONLY":
        raise ContractError("accepted xcresult reuse policy differs")
    if (receipt["xccovStatus"] != "NOT_RUN" or receipt["changedCandidateLines"] or
            receipt["xccovExecutableLineIdentities"] or receipt["xccovExecutableLineSetDigest"] is not None or
            receipt["changedExecutableLines"] or receipt["evidenceArtifacts"]):
        raise ContractError("NOT_RUN receipt fabricates evidence")
    if any(row["result"] != "NOT_RUN" for row in receipt["coverageByTier"]):
        raise ContractError("NOT_RUN tier fabricates result")
    for row in receipt["coverageByTier"][:2]:
        if any(row[key] is not None for key in ("executableLinePercent", "functionPercent",
                                                "changedExecutableLinePercent", "changedFunctionCompletelyUncoveredCount")):
            raise ContractError("NOT_RUN tier fabricates metric")
    false_fields = ("candidateBound", "performanceCoverageInstrumentationUsed", "nativeCompileRan",
                    "hostedDispatchRan", "adoptionEnabled", "acceptanceEnabled", "receiptSatisfied",
                    "releaseReady", "phase10PollingDuringParallelExecution", "acceptanceCredit", "releaseCredit")
    if any(receipt[key] for key in false_fields) or not receipt["requiresAcceptedS10_6Reconciliation"]:
        raise ContractError("C13 provisional receipt overclaims closure")
    if receipt["currentness"] != {"candidateBindingCurrent": False, "xcresultCurrent": False,
                                  "comparisonBaseCurrent": False, "toolchainAndFixtureCurrent": False,
                                  "result": "BLOCKED"}:
        raise ContractError("C13 provisional currentness differs")
    if not receipt["performanceCoverageInstrumentationRejected"]:
        raise ContractError("performance coverage instrumentation was permitted")
    expected_lifecycle = {"persistence":"IMMUTABLE_BUILD_BOUND_TOOLING_OR_EVIDENCE_ARTIFACT",
        "supersession":"APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT",
        "successorTriggers":["SOURCE_CHANGE","COMPARISON_BASE_CHANGE","TOOLCHAIN_CHANGE","FIXTURE_CHANGE","EVIDENCE_CHANGE"],
        "customerData":"NONE", "interruption":"FAIL_CLOSED_NO_PARTIAL_ACCEPTANCE",
        "recovery":"BYTE_EXACT_REGENERATION_OR_NEW_SUCCESSOR_RECEIPT"}
    if any(artifact["lifecycle"] != expected_lifecycle for artifact in artifacts):
        raise ContractError("immutable successor lifecycle differs")
    if any(artifact["acceptanceCredit"] or artifact["releaseCredit"] for artifact in artifacts):
        raise ContractError("provisional artifact grants acceptance/release credit")


def future_probes(artifacts: list[dict[str, Any]], schemas: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], str]:
    receipt, tier, exclusion, comparison = copy.deepcopy(artifacts)
    official = {"CardAcceptanceInclusionProofV1Digest": "2" * 64,
                "CardAcceptanceInclusionProofRecoveryReceiptV1Digest": "3" * 64,
                "CandidateAcceptanceCompatibilityReceiptV1Digest": "4" * 64,
                "acceptanceCurrentness": "PASS", "compatibility": "PASS",
                "zeroOrphanAcceptanceProofComplete": True}
    for artifact in (receipt, tier, exclusion, comparison):
        authority = artifact["authority"]
        authority.update(executionMode="POST_S10_6_ACCEPTANCE", ledgerDigest="5" * 64,
                         ledgerCASSequence=48, acceptanceEnabled=True,
                         hostedDispatchEnabled=True, requiresAcceptedS10_6Reconciliation=False)
        prerequisite = authority["directPrerequisite"]
        prerequisite.update(nativeCompileRan=True, nativeTestsRan=True,
                            languageModeClosureSatisfied=True, acceptanceCredit=True,
                            officialAcceptanceEvidence=copy.deepcopy(official))
    exclusion["exclusions"] = [{"kind": "GENERATED_CODE", "pattern": "Generated/Model.swift",
                                 "reason": "Pinned generator output", "reviewerReceiptDigest": "a" * 64}]
    exclusion["reviewerReceipts"] = [{"receiptDigest":"a"*64, "kind":"GENERATED_CODE",
        "pattern":"Generated/Model.swift", "status":"APPROVED", "path":"Generated/Model.swift",
        "reasonDigest":sha256_bytes(b"Pinned generator output")}]
    comparison["releaseClosureAcceptedS10_6Base"] = {"head": "b" * 40, "tree": "c" * 40, "status": "PASS"}
    comparison["comparisonReady"] = True
    tier = seal({key:value for key,value in tier.items() if key != "artifactDigest"})
    exclusion = seal({key:value for key,value in exclusion.items() if key != "artifactDigest"})
    comparison = seal({key:value for key,value in comparison.items() if key != "artifactDigest"})
    validate_schema(comparison, schemas[3])
    receipt.update(candidateHead="d" * 40, candidateTree="e" * 40, candidateBound=True,
                   acceptingXcresultPath="artifacts/accepted.xcresult", acceptingXcresultDigest="f" * 64,
                   toolchainIdentity="Xcode accepted build", fixtureDigest="1" * 64,
                   xccovStatus="PASS", blockers=[], nativeCompileRan=True, hostedDispatchRan=True,
                   acceptanceEnabled=True, receiptSatisfied=True, acceptanceCredit=True,
                   requiresAcceptedS10_6Reconciliation=False)
    future_diff = ("diff --git a/FieldEvidenceApp/Domain/Model.swift b/FieldEvidenceApp/Domain/Model.swift\n"
        "--- a/FieldEvidenceApp/Domain/Model.swift\n+++ b/FieldEvidenceApp/Domain/Model.swift\n"
        "@@ -7 +7 @@\n-old value\n+return value\n")
    changed = parse_changed_lines(future_diff)
    identities = [{"path":"FieldEvidenceApp/Domain/Model.swift", "line":7}]
    receipt["changedDiffArtifactPath"] = "artifacts/changed.diff"
    receipt["changedDiffDigest"] = sha256_bytes(future_diff.encode("utf-8"))
    receipt["changedCandidateLineSetDigest"] = sha256_bytes(pretty_bytes(changed))
    receipt["changedCandidateLines"] = changed
    receipt["xccovExecutableLineIdentities"] = identities
    receipt["xccovExecutableLineSetDigest"] = sha256_bytes(pretty_bytes(identities))
    receipt["changedExecutableLines"] = changed
    receipt["coverageByTier"][0].update(executableLinePercent=90, functionPercent=85,
                                         changedExecutableLinePercent=95,
                                         changedFunctionCompletelyUncoveredCount=0, result="PASS")
    receipt["coverageByTier"][1].update(executableLinePercent=80, functionPercent=75,
                                         changedExecutableLinePercent=85,
                                         changedFunctionCompletelyUncoveredCount=0, result="PASS")
    receipt["coverageByTier"][2].update(semanticIntegrationEvidence=["artifact://ui-integration"], result="PASS")
    receipt["evidenceArtifacts"] = ["artifact://xccov-json"]
    receipt["currentness"] = {"candidateBindingCurrent": True, "xcresultCurrent": True,
                              "comparisonBaseCurrent": True, "toolchainAndFixtureCurrent": True,
                              "result": "PASS"}
    receipt["tierReleaseDigest"] = tier["artifactDigest"]
    receipt["exclusionDigest"] = exclusion["artifactDigest"]
    receipt["comparisonBaseDigest"] = comparison["artifactDigest"]
    receipt = seal({key:value for key,value in receipt.items() if key != "artifactDigest"})
    future = [receipt, tier, exclusion, comparison]
    for artifact, schema in zip(future, schemas): validate_schema(artifact, schema)
    validate_pass_closure(*future, future_diff)
    return future, future_diff


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    validate_repository_state(root)
    expected = build_outputs(root); checks = 0
    for relative, value in expected.items():
        if not (root / relative).is_file() or (root / relative).read_bytes() != pretty_bytes(value):
            raise ContractError(f"generated output differs: {relative}")
        checks += 1
    artifacts = [load(root / path) for path in ARTIFACT_PATHS]
    schemas = [load(root / path) for path in SCHEMA_PATHS]
    identities = [artifact["schema"] for artifact in artifacts]
    if ([schema["title"] for schema in schemas] != identities or
            [schema["$id"].rsplit("/", 1)[-1] for schema in schemas] != [f"{name}.schema.json" for name in identities]):
        raise ContractError("schema/artifact identity differs")
    checks += 1
    for schema, artifact in zip(schemas, artifacts):
        validate_schema(artifact, schema); verify_digest(artifact); checks += 2
    validate_current(artifacts); checks += 12
    future, future_diff = future_probes(artifacts, schemas); checks += 5
    for script in FENCED_PATHS[:3]:
        ast.parse((root / script).read_text(encoding="utf-8"), filename=script); checks += 1

    diff_cases = 0
    modified = "diff --git a/Domain/A.swift b/Domain/A.swift\n--- a/Domain/A.swift\n+++ b/Domain/A.swift\n@@ -10,1 +10,2 @@\n-old\n+let value = 1\n+// comment\n"
    rows = parse_changed_lines(modified)
    if rows != [{"path": "Domain/A.swift", "line": 10, "changeKind": "MODIFIED", "candidateText": "let value = 1"},
                {"path": "Domain/A.swift", "line": 11, "changeKind": "ADDED", "candidateText": "// comment"}]:
        raise ContractError("modified hunk parsing differs")
    diff_cases += 1
    added = "diff --git a/new.swift b/new.swift\nnew file mode 100644\n--- /dev/null\n+++ b/new.swift\n@@ -0,0 +1,2 @@\n+let a = 1\n+return a\n"
    if [row["changeKind"] for row in parse_changed_lines(added)] != ["ADDED", "ADDED"]:
        raise ContractError("added hunk parsing differs")
    diff_cases += 1
    renamed = "diff --git a/Old.swift b/New.swift\nsimilarity index 90%\nrename from Old.swift\nrename to New.swift\n--- a/Old.swift\n+++ b/New.swift\n@@ -1 +1 @@\n-old()\n+new()\n"
    if parse_changed_lines(renamed)[0]["path"] != "New.swift": raise ContractError("rename target identity differs")
    diff_cases += 1
    deleted = "diff --git a/Gone.swift b/Gone.swift\ndeleted file mode 100644\n--- a/Gone.swift\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-let a = 1\n-return a\n"
    if parse_changed_lines(deleted): raise ContractError("deleted-only lines counted")
    diff_cases += 1
    if parse_changed_lines(modified.replace("\n", "\r\n")) != rows: raise ContractError("CRLF normalization differs")
    diff_cases += 1
    mode_diff = ("diff --git a/A.swift b/A.swift\nold mode 100644\nnew mode 100755\n"
                 "--- a/A.swift\n+++ b/A.swift\n@@ -1 +1 @@\n-a\n+b\n")
    if parse_changed_lines(mode_diff)[0]["path"] != "A.swift": raise ContractError("mode metadata parsing differs")
    diff_cases += 1
    copy_diff = ("diff --git a/A.swift b/B.swift\nsimilarity index 90%\ncopy from A.swift\ncopy to B.swift\n"
                 "--- a/A.swift\n+++ b/B.swift\n@@ -1 +1 @@\n-a\n+b\n")
    if parse_changed_lines(copy_diff)[0]["path"] != "B.swift": raise ContractError("copy target identity differs")
    diff_cases += 1
    for binary_diff in (
        "diff --git a/A.png b/A.png\nBinary files a/A.png and b/A.png differ\n",
        "diff --git a/A.bin b/A.bin\nGIT binary patch\nliteral 1\nabc\n",
        "diff --git a/A.bin b/A.bin\nGIT binary patch\ndelta 1\nabc\n",
    ):
        try: parse_changed_lines(binary_diff)
        except ContractError as error:
            if str(error) != "BINARY_DIFF_REQUIRES_NONEXECUTABLE_DISPOSITION": raise
        else: raise ContractError("binary diff did not fail closed with typed disposition")
        diff_cases += 1
    checks += diff_cases

    strict_diff_hostiles = [
        "rename to A.swift\n", "@@ -1 +1 @@\n-a\n+b\n",
        "diff --git a/A.swift b/A.swift\n@@ -1 +1 @@\n-a\n+b\n",
        "diff --git a/A.swift b/B.swift\nrename from A.swift\nrename to B.swift\n--- a/A.swift\n+++ b/C.swift\n@@ -1 +1 @@\n-a\n+b\n",
        "diff --git a/A.swift b/A.swift\n--- a/A.swift\n+++ b/A.swift\n@@ -0,0 +1,0 @@\n+x\n",
        "diff --git a/A.swift b/A.swift\n--- a/A.swift\n+++ b/A.swift\n@@ -1,1 +1,1 @@\n-a\n+b\n+c\n",
        "diff --git a/A.swift b/A.swift\n--- a/A.swift\n+++ b/A.swift\n@@ -1,2 +1,1 @@\n-a\n+b\n",
        "diff --git a/A.swift b/A.swift\n--- a/A.swift\n+++ b/A.swift\n@@ -1 +1 @@\n context\n",
        "diff --git a/A.swift b/A.swift\n--- a/A.swift\n+++ b/A.swift\n-stray\n",
        "diff --git a/A.swift b/A.swift\n--- a/A.swift\n+++ b/A.swift\n+stray\n",
    ]
    for invalid in strict_diff_hostiles: reject(lambda value=invalid: parse_changed_lines(value))
    hostile_count = len(strict_diff_hostiles)

    if evaluate_tier({"executableLinePercent": 90, "functionPercent": 85,
                      "changedExecutableLinePercent": 95,
                      "changedFunctionCompletelyUncoveredCount": 0}, TIER_FLOORS[0]) != "PASS":
        raise ContractError("critical boundary tier failed")
    if evaluate_tier({"executableLinePercent": 80, "functionPercent": 75,
                      "changedExecutableLinePercent": 85,
                      "changedFunctionCompletelyUncoveredCount": 2}, TIER_FLOORS[1]) != "PASS":
        raise ContractError("domain boundary tier failed")
    if evaluate_tier({"executableLinePercent": 100, "functionPercent": 100,
                      "changedExecutableLinePercent": 100,
                      "changedFunctionCompletelyUncoveredCount": 1}, TIER_FLOORS[0]) != "FAIL":
        raise ContractError("uncovered critical function passed")
    checks += 3
    for nonfinite in (float("nan"), float("inf"), float("-inf")):
        reject(lambda value=nonfinite: evaluate_tier({"executableLinePercent":value, "functionPercent":85,
            "changedExecutableLinePercent":95, "changedFunctionCompletelyUncoveredCount":0}, TIER_FLOORS[0]))
        hostile_count += 1

    exclusion_hostiles = [
        {"kind":"GENERATED_CODE","pattern":"/abs.swift","reason":"x","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"C:\\abs.swift","reason":"x","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"a/../b.swift","reason":"x","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"*","reason":"x","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"**","reason":"x","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"Generated/**","reason":"x","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"Generated/*","reason":"generated","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"FieldEvidenceApp/*.swift","reason":"generated","reviewerReceiptDigest":"a"*64},
        {"kind":"PREVIEW","pattern":"Preview/A?.swift","reason":"preview","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"Generated/A.swift","reason":"","reviewerReceiptDigest":"a"*64},
        {"kind":"GENERATED_CODE","pattern":"Generated/A.swift","reason":"x","reviewerReceiptDigest":"bad"},
        {"kind":"OTHER","pattern":"Generated/A.swift","reason":"x","reviewerReceiptDigest":"a"*64},
        {"kind":"PLATFORM_GLUE","pattern":"Adapters/A.swift","reason":"generated output","reviewerReceiptDigest":"a"*64},
    ] + [{"kind":"PLATFORM_GLUE","pattern":f"FieldEvidenceApp/{token}/A.swift","reason":"x","reviewerReceiptDigest":"a"*64}
         for token in ("Domain", "Writer", "Migration", "Import", "Restore", "Erase")]
    for row in exclusion_hostiles: reject(lambda value=row: validate_exclusion(value))
    checks += len(exclusion_hostiles)

    hostile_count += len(exclusion_hostiles)
    mutation_specs = [
        (1, ("tiers",0,"executableLinePercent"), 89), (1,("tiers",0,"functionPercent"),84),
        (1,("tiers",0,"changedExecutableLinePercent"),94), (1,("tiers",1,"executableLinePercent"),79),
        (1,("tiers",1,"functionPercent"),74), (1,("tiers",1,"changedExecutableLinePercent"),84),
        (1,("tiers",0,"changedFunctionCompletelyUncoveredAllowed"),True),
        (1,("tiers",1,"changedFunctionCompletelyUncoveredAllowed"),False),
        (1,("uiAndPlatformGlue","coveragePercentGate"),"PERCENT_REQUIRED"),
        (1,("performanceCoverageInstrumentation",),"ALLOWED"),
        (3,("comparisonReady",),True), (3,("basesAreDistinctAuthorities",),False),
        (0,("candidateBound",),True), (0,("xccovStatus",),"PASS"), (0,("nativeCompileRan",),True),
        (0,("hostedDispatchRan",),True), (0,("adoptionEnabled",),True), (0,("acceptanceEnabled",),True),
        (0,("receiptSatisfied",),True), (0,("releaseReady",),True),
        (0,("phase10PollingDuringParallelExecution",),True), (0,("acceptanceCredit",),True),
        (0,("releaseCredit",),True), (0,("requiresAcceptedS10_6Reconciliation",),False),
        (0,("tierReleaseDigest",),"0"*64),
        (0,("authority","directPrerequisite","implementationHead"),"0"*40),
        (0,("authority","directPrerequisite","nativeCompileRan"),True),
    ]
    for artifact_index, path, replacement in mutation_specs:
        hostile = copy.deepcopy(artifacts); target = hostile[artifact_index]
        for component in path[:-1]: target = target[component]
        target[path[-1]] = replacement
        try:
            validate_current(hostile)
        except ContractError:
            hostile_count += 1
        else:
            raise ContractError(f"hostile semantic mutation did not fail: artifact={artifact_index} path={path}")
    lifecycle = copy.deepcopy(artifacts); lifecycle[2]["lifecycle"]["successorTriggers"].pop()
    reject(lambda: validate_current(lifecycle)); hostile_count += 1
    for artifact_index in range(4):
        for field in ("acceptanceCredit", "releaseCredit"):
            hostile = copy.deepcopy(artifacts); hostile[artifact_index][field] = True
            reject(lambda value=hostile: validate_current(value)); hostile_count += 1
        hostile = copy.deepcopy(artifacts); hostile[artifact_index]["lifecycle"]["recovery"] = "REWRITE"
        reject(lambda value=hostile: validate_current(value)); hostile_count += 1
    schema_extra = copy.deepcopy(artifacts[0]); schema_extra["unexpected"] = True
    reject(lambda: validate_schema(schema_extra, schemas[0])); hostile_count += 1
    digest_bad = copy.deepcopy(artifacts[0]); digest_bad["artifactDigest"] = "0" * 64
    reject(lambda: verify_digest(digest_bad)); hostile_count += 1
    for invalid_diff in (
        "diff --git malformed\n", "diff --git a/A b/A\n+++ /absolute\n@@ -0,0 +1 @@\n+x\n",
        "diff --git a/A b/../A\n+++ b/../A\n@@ -0,0 +1 @@\n+x\n",
    ):
        reject(lambda value=invalid_diff: parse_changed_lines(value)); hostile_count += 1
    valid_exclusion = future[2]
    for exclusions, receipts in (
        (valid_exclusion["exclusions"], []),
        (valid_exclusion["exclusions"], valid_exclusion["reviewerReceipts"] * 2),
        (valid_exclusion["exclusions"], [{**valid_exclusion["reviewerReceipts"][0], "path":"Other.swift"}]),
    ):
        reject(lambda a=exclusions, b=receipts: validate_exclusion_set(a, b)); hostile_count += 1
    candidate = future[0]["changedCandidateLines"]
    identities = future[0]["xccovExecutableLineIdentities"]
    reject(lambda: validate_changed_line_sets(candidate + candidate, identities, candidate)); hostile_count += 1
    reject(lambda: validate_changed_line_sets(candidate, identities + identities, candidate)); hostile_count += 1
    reject(lambda: validate_changed_line_sets(candidate, [], candidate)); hostile_count += 1
    reject(lambda: validate_changed_line_sets([{**candidate[0], "path":"A\\B.swift"}], identities, candidate)); hostile_count += 1

    pass_mutations = [
        (0, ("candidateHead",), None), (0, ("candidateTree",), "bad"),
        (0, ("acceptingXcresultPath",), None), (0, ("acceptingXcresultDigest",), None),
        (0, ("toolchainIdentity",), None), (0, ("fixtureDigest",), None),
        (0, ("xccovStatus",), "NOT_RUN"), (0, ("xccovExecutableLineSetDigest",), "0"*64),
        (0, ("coverageByTier",0,"changedFunctionCompletelyUncoveredCount"), 1),
        (0, ("coverageByTier",2,"semanticIntegrationEvidence"), []),
        (0, ("evidenceArtifacts",), []), (0, ("blockers",), ["BLOCKED"]),
        (0, ("currentness","xcresultCurrent"), False),
        (0, ("performanceCoverageInstrumentationUsed",), True),
        (0, ("requiresAcceptedS10_6Reconciliation",), True),
        (0, ("acceptanceEnabled",), False), (0, ("receiptSatisfied",), False),
        (0, ("acceptanceCredit",), False), (3, ("comparisonReady",), False),
        (0, ("tierReleaseDigest",), "0"*64),
        (0, ("nativeCompileRan",), False), (0, ("hostedDispatchRan",), False),
        (0, ("performanceCoverageInstrumentationRejected",), False),
        (0, ("releaseCredit",), True), (1, ("acceptanceCredit",), True),
        (2, ("releaseCredit",), True), (3, ("acceptanceCredit",), True),
        (0, ("authority","directPrerequisite","cardID"), "V23-P00-C08"),
        (0, ("lifecycle","recovery"), "REWRITE"),
        (0, ("authority","directPrerequisite","officialAcceptanceEvidence","zeroOrphanAcceptanceProofComplete"), False),
        (0, ("authority","directPrerequisite","officialAcceptanceEvidence","CardAcceptanceInclusionProofV1Digest"), None),
        (0, ("authority","directPrerequisite","officialAcceptanceEvidence","acceptanceCurrentness"), "FAIL"),
        (0, ("authority","directPrerequisite","officialAcceptanceEvidence","compatibility"), "FAIL"),
    ]
    for artifact_index, path, replacement in pass_mutations:
        hostile = copy.deepcopy(future); target = hostile[artifact_index]
        for component in path[:-1]: target = target[component]
        target[path[-1]] = replacement
        reject(lambda value=hostile: validate_pass_closure(*value, future_diff)); hostile_count += 1

    def reseal_future(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        for index in (1, 2, 3):
            items[index] = seal({key: value for key, value in items[index].items()
                                 if key != "artifactDigest"})
        items[0]["tierReleaseDigest"] = items[1]["artifactDigest"]
        items[0]["exclusionDigest"] = items[2]["artifactDigest"]
        items[0]["comparisonBaseDigest"] = items[3]["artifactDigest"]
        items[0] = seal({key: value for key, value in items[0].items()
                         if key != "artifactDigest"})
        return items

    coordinated_drift = copy.deepcopy(future)
    for artifact in coordinated_drift:
        artifact["authority"]["directPrerequisite"]["cardID"] = "V23-P00-C08"
    coordinated_drift = reseal_future(coordinated_drift)
    reject(lambda: validate_pass_closure(*coordinated_drift, future_diff)); hostile_count += 1
    resealed_policy_mutations = [
        (0, ("xcresultReusePolicy",), "ANY"),
        (1, ("changedLineLaw", "command"), "git diff --unified=3"),
        (1, ("uiAndPlatformGlue", "coveragePercentGate"), "PERCENT_REQUIRED"),
        (2, ("allowedKinds",), EXCLUSION_KINDS + ["OTHER"]),
        (2, ("protectedPathTokens",), []),
        (2, ("broadAbsoluteBackslashOrTraversalPatternAllowed",), True),
        (2, ("unknownExclusionDisposition",), "ALLOW"),
        (3, ("basesAreDistinctAuthorities",), False),
        (3, ("fabricatedBaselineAllowed",), True),
    ]
    for artifact_index, path, replacement in resealed_policy_mutations:
        hostile = copy.deepcopy(future); target = hostile[artifact_index]
        for component in path[:-1]: target = target[component]
        target[path[-1]] = replacement
        hostile = reseal_future(hostile)
        reject(lambda value=hostile: validate_pass_closure(*value, future_diff)); hostile_count += 1
    for hostile_diff in ("", future_diff + "\n"):
        reject(lambda value=hostile_diff: validate_pass_closure(*future, value)); hostile_count += 1
    for field, replacement in (("changedDiffDigest", "0"*64),
                               ("changedCandidateLineSetDigest", "0"*64),
                               ("changedCandidateLines", []),
                               ("changedDiffArtifactPath", None)):
        hostile = copy.deepcopy(future); hostile[0][field] = replacement
        reject(lambda value=hostile: validate_pass_closure(*value, future_diff)); hostile_count += 1
    nan_schema = copy.deepcopy(future[0]); nan_schema["coverageByTier"][0]["executableLinePercent"] = float("nan")
    reject(lambda: validate_schema(nan_schema, schemas[0])); hostile_count += 1
    checks += (len(mutation_specs) + len(strict_diff_hostiles) + len(pass_mutations) +
               len(resealed_policy_mutations) + 26)

    regenerated = list(build_artifacts(root).values())
    if [pretty_bytes(value) for value in regenerated] != [pretty_bytes(value) for value in artifacts]:
        raise ContractError("interruption regeneration differs")
    validate_current(regenerated); checks += 2
    manifest = load(root / MANIFEST_PATH)
    if manifest != build_manifest(root) or manifest["artifactCount"] != 11 or manifest["pathFence"] != FENCED_PATHS:
        raise ContractError("C13 tooling manifest differs")
    verify_digest(manifest)
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"manifest hash differs: {row['path']}")
    checks += 3
    run = subprocess.run([sys.executable, "-B", str(root / "Scripts/v23/generate_c13_contracts.py"),
                          "--check", "--root", str(root)], check=True, capture_output=True, text=True,
                         env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    if "PASS V23-P00-C13 generated=9 check=True" not in run.stdout:
        raise ContractError("generator check failed")
    checks += 1
    print(json.dumps({"result":"PASS","cardID":CARD_ID,"checks":checks,"artifactCount":4,
        "schemaArtifactPairCount":4,"futurePassProbeCount":4,"tierCount":2,
        "diffScenarioCount":diff_cases,"exclusionHostileCount":len(exclusion_hostiles),
        "hostileMutationCount":hostile_count,"nativeCompileRan":False,"xccovStatus":"NOT_RUN",
        "acceptedS10_6BaseResolved":False,"hostedDispatchRan":False,"adoptionEnabled":False,
        "acceptanceCredit":False,"releaseReady":False,"releaseCredit":False,
        "phase10PollingDuringParallelExecution":False}, sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())
