#!/usr/bin/env python3
"""Deterministic V23-P00-C13 coverage contracts and diff policy."""

from __future__ import annotations

import json
import math
import re
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any

from c07_contracts import (
    DEPENDENCY_DISPOSITION_DIGEST, GRAPH_DIGEST, OVERRIDE_RECEIPT_DIGEST,
    PACKAGE_DIGEST, REGISTER_DIGEST, RELATION_DIGEST, RESERVATION_DIGEST,
    SELECTOR_DIGEST, ContractError, digest, load_reservation, pretty_bytes, seal,
    sha256_bytes, validate_frozen_authority,
)

CARD_ID = "V23-P00-C13"
BASE_HEAD = "d3517e6633b4e51eaff9b9ffe791b2398365c49a"
BASE_TREE = "93db49fcda5a1e706417158a1f437f3b89c886e3"
CONTEXT_DIGEST = "950671d70a0b3a87170f125258daf7dad76194990f60227358d6c46668cbde7f"
FENCE_DIGEST = "da9de4fd75416c8a3b8a2bb5224894794ac4bf2e3e80b9b1011ea9585c7d559d"
PREREQUISITE_DIGEST = "035e7b80772e813cb04ade498ea0182c860fc1a7e5a32a4c41025cd47ce0ce23"
DOSSIER_DIGEST = "b7c08055f362ea55660de381083a8f21eb5011299d1512653dd95b88d3f0a762"
LEDGER_DIGEST = "bd811b3103350985c989312e57a618886067f2c752cb61406da7a84317c09351"
LEDGER_CAS_SEQUENCE = 47
C12_IMPLEMENTATION_HEAD = "7b72263ea2c64a8f9bace8e87872d1a293400969"
C12_IMPLEMENTATION_TREE = "d3fbaa46c1a35c5a52909731dfbfa30fed3b1086"
C12_CONTEXT_DIGEST = "e549afb029c183733eab5514345ad49cfda954fa9dc2842574faa9511fa69d81"
C12_FENCE_DIGEST = "c23d8f566b104f8ebc4cf2192d5c06e447621f72871fb43811e59972a53d9b6d"
C12_VERIFICATION_DIGEST = "c6c3c607b1a667a1cbb227fac4128c67f5f66da4af1a3feb0cd243af991e4a96"
C12_CHECKPOINT_DIGEST = "a7d0c64d08442db60ed5dad4a19398601b58ea7e8c2ebd4797402cd8f0737764"
C12_SWIFT_DIGEST = "d229005282b59b5002137b09d9415555190405eec7a51e066bc6744007f11229"
C12_SWIFT_FILE_SHA256 = "b367c8c87bbe897d1f8f03a730bb13ece46fd2950df3899bb56c52d5e4fef344"
C12_MANIFEST_DIGEST = "01e5960fafb04523557257e6286257cd7103c7481039ed3006345b9c18fc6c15"
C12_MANIFEST_FILE_SHA256 = "6258b2ed0bf3c543ca2f1092003af2abb5668e6149e447c09a0c35b586af40e8"
IMPACT_MANIFEST_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
IMPACT_FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
PLANNING_PROJECTION_DIGEST = "676b8eb03523474ba844ecbcaac5d63a10505b00769debb8dbec2c9aba70c33d"
IMPACT_ROW_DIGEST = "7699e730ad507c8109e5f371186887459f0b3807ce871cb333e31b4dddaeeba9"
EVIDENCE_IDS = [f"{CARD_ID}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
POLICY_REFS = ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001"]
CONTRACT_REFS = ["CodeCoverageReceiptV1", "CoverageTierReleaseV1", "CoverageExclusionV1",
                 "CoverageComparisonBaseV1", "DirectPrerequisiteEvidenceSetV1",
                 "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1",
                 "CandidateAcceptanceCompatibilityReceiptV1"]
IMPACT_ROW = {"id": CARD_ID, "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
              "invalidationConsumers": ["V23-P04-C29"], "optionalCapabilityProviders": [],
              "conformanceSubjects": []}
BLUEPRINT = "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"

SCHEMA_PATHS = [
    "Scripts/v23/code-coverage-receipt.schema.json",
    "Scripts/v23/coverage-tier-release.schema.json",
    "Scripts/v23/coverage-exclusion.schema.json",
    "Scripts/v23/coverage-comparison-base.schema.json",
]
ARTIFACT_PATHS = [
    "docs/design/v23/tooling/CodeCoverageReceiptV1.json",
    "docs/design/v23/tooling/CoverageTierReleaseV1.json",
    "docs/design/v23/tooling/CoverageExclusionV1.json",
    "docs/design/v23/tooling/CoverageComparisonBaseV1.json",
]
MANIFEST_PATH = "docs/design/v23/tooling/V23-P00-C13-tooling-manifest.json"
FENCED_PATHS = [
    "Scripts/v23/c13_contracts.py", "Scripts/v23/generate_c13_contracts.py",
    "Scripts/v23/verify_c13_contracts.py", *SCHEMA_PATHS, *ARTIFACT_PATHS, MANIFEST_PATH,
]

TIER_FLOORS = [
    {"tier": "CRITICAL_CORRECTNESS", "executableLinePercent": 90,
     "functionPercent": 85, "changedExecutableLinePercent": 95,
     "changedFunctionCompletelyUncoveredAllowed": False},
    {"tier": "DOMAIN_APPLICATION", "executableLinePercent": 80,
     "functionPercent": 75, "changedExecutableLinePercent": 85,
     "changedFunctionCompletelyUncoveredAllowed": True},
]
EXCLUSION_KINDS = ["GENERATED_CODE", "PREVIEW", "PLATFORM_GLUE"]
PROTECTED_EXCLUSION_TOKENS = ["domain", "writer", "migration", "import", "restore", "erase"]
DIFF_COMMAND = "git diff --no-ext-diff --find-renames --unified=0 <base>...<candidate> --"
RESULTS = ["PASS", "FAIL", "NOT_RUN", "BLOCKED", "INCONCLUSIVE_BLOCKED"]


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          capture_output=True, text=True, encoding="utf-8").stdout


def authority_binding() -> dict[str, Any]:
    return {
        "attemptID": 1, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "candidateBinding": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED",
        "packageDigest": PACKAGE_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "canonicalRegisterDigest": REGISTER_DIGEST, "directGraphDigest": GRAPH_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST, "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "ownerOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "bootstrapContextDigest": CONTEXT_DIGEST, "bootstrapPathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "deterministicEvidenceIDs": EVIDENCE_IDS, "policyRefs": POLICY_REFS,
        "contractRefs": CONTRACT_REFS, "journeyRefs": "NONE",
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "invalidationConsumers": ["V23-P04-C29"],
        "impactManifestDigest": IMPACT_MANIFEST_DIGEST, "impactFacetDigest": IMPACT_FACET_DIGEST,
        "planningProjectionDigest": PLANNING_PROJECTION_DIGEST,
        "impactRow": IMPACT_ROW, "impactRowDigest": IMPACT_ROW_DIGEST,
        "sourceDisposition": "PINNED_DOSSIER_STATIC_PROVISIONAL",
        "fixtureDisposition": "UNRESOLVED_UNTIL_ACCEPTING_XCRESULT",
        "currentnessDisposition": "UNRESOLVED_ACCEPTANCE_DISABLED",
        "directPrerequisite": {
            "cardID": "V23-P00-C12", "implementationHead": C12_IMPLEMENTATION_HEAD,
            "implementationTree": C12_IMPLEMENTATION_TREE, "contextDigest": C12_CONTEXT_DIGEST,
            "fenceDigest": C12_FENCE_DIGEST, "verificationDigest": C12_VERIFICATION_DIGEST,
            "checkpointDigest": C12_CHECKPOINT_DIGEST,
            "swiftLanguageModeClosureReceiptDigest": C12_SWIFT_DIGEST,
            "swiftLanguageModeClosureReceiptFileSHA256": C12_SWIFT_FILE_SHA256,
            "toolingManifestDigest": C12_MANIFEST_DIGEST,
            "toolingManifestFileSHA256": C12_MANIFEST_FILE_SHA256,
            "nativeCompileRan": False, "nativeTestsRan": False,
            "languageModeClosureSatisfied": False, "acceptanceCredit": False,
            "releaseCredit": False,
            "directPrerequisiteEvidenceSetReceiptDigest": PREREQUISITE_DIGEST,
            "officialAcceptanceEvidence": {
                "CardAcceptanceInclusionProofV1Digest": None,
                "CardAcceptanceInclusionProofRecoveryReceiptV1Digest": None,
                "CandidateAcceptanceCompatibilityReceiptV1Digest": None,
                "acceptanceCurrentness": "UNRESOLVED_ACCEPTANCE_DISABLED",
                "compatibility": "UNRESOLVED_ACCEPTANCE_DISABLED",
                "zeroOrphanAcceptanceProofComplete": False,
            },
        },
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "ledgerDigest": LEDGER_DIGEST, "ledgerCASSequence": LEDGER_CAS_SEQUENCE,
        "phase10PollingDuringParallelExecution": False, "acceptanceEnabled": False,
        "hostedDispatchEnabled": False, "adoptionEnabled": False,
        "requiresAcceptedS10_6Reconciliation": True, "releaseCredit": False,
    }


def validate_fence(root: Path) -> None:
    reservation = load_reservation(root)
    if len(FENCED_PATHS) != 12 or len(set(FENCED_PATHS)) != 12:
        raise ContractError("C13 fence cardinality differs")
    if len(reservation["reservedPaths"]) != 86 or set(FENCED_PATHS) & set(reservation["reservedPaths"]):
        raise ContractError("C13 fence overlaps frozen reservation")
    changed = {line.replace("\\", "/") for line in git(root, "diff", "--name-only", BASE_HEAD).splitlines() if line}
    if not changed <= set(FENCED_PATHS):
        raise ContractError(f"C13 out-of-fence delta: {sorted(changed - set(FENCED_PATHS))}")
    for line in git(root, "status", "--porcelain=v1", "--untracked-files=all").splitlines():
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"C13 delete/rename forbidden: {line}")
        if raw.replace("\\", "/") not in FENCED_PATHS:
            raise ContractError(f"C13 out-of-fence work: {raw}")


def validate_sources(root: Path) -> None:
    blueprint = (root / BLUEPRINT).read_text(encoding="utf-8")
    start = blueprint.index("### V23-P00-C13 — Critical-domain code-coverage receipt, accepted-xcresult reuse, and changed-code non-regression gate")
    end = blueprint.index('<a id="v23-p01-c01"></a>', start)
    dossier = blueprint[start:end].rstrip() + "\n"
    if sha256_bytes(dossier.encode("utf-8")) != DOSSIER_DIGEST:
        raise ContractError("C13 dossier authority differs")
    projection = json.loads((root / "docs/design/v23/tooling/V23PlanningProjectionV1.json").read_text(encoding="utf-8-sig"))
    if projection.get("projectionDigest") != PLANNING_PROJECTION_DIGEST or \
            projection.get("authorityDigests", {}).get("impact") != IMPACT_MANIFEST_DIGEST or \
            projection.get("authorityDigests", {}).get("facets") != IMPACT_FACET_DIGEST:
        raise ContractError("planning projection authority differs")
    rows = [row for row in projection.get("impact", []) if row.get("id") == CARD_ID]
    if rows != [IMPACT_ROW] or sha256_bytes(pretty_bytes(rows[0])) != IMPACT_ROW_DIGEST:
        raise ContractError("C13 impact row identity/digest differs")


def validate_c12(root: Path) -> None:
    swift_path = root / "docs/design/v23/tooling/SwiftLanguageModeClosureReceiptV1.json"
    manifest_path = root / "docs/design/v23/tooling/V23-P00-C12-tooling-manifest.json"
    if sha256_bytes(swift_path.read_bytes()) != C12_SWIFT_FILE_SHA256:
        raise ContractError("C12 Swift receipt file differs")
    if sha256_bytes(manifest_path.read_bytes()) != C12_MANIFEST_FILE_SHA256:
        raise ContractError("C12 manifest file differs")
    swift = json.loads(swift_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if swift["artifactDigest"] != C12_SWIFT_DIGEST or manifest["artifactDigest"] != C12_MANIFEST_DIGEST:
        raise ContractError("C12 semantic evidence differs")
    if any((swift["nativeCompileRan"], swift["nativeTestsRan"], swift["languageModeClosureSatisfied"],
            swift["acceptanceCredit"], swift["releaseCredit"], manifest["nativeCompileRan"],
            manifest["acceptanceCredit"], manifest["releaseCredit"])):
        raise ContractError("C12 prerequisite overclaims closure")


def normalize_repo_path(value: str) -> str:
    if not value or "\\" in value or value.startswith("/") or re.match(r"^[A-Za-z]:", value):
        raise ContractError(f"invalid repository path: {value!r}")
    path = PurePosixPath(value)
    if any(part in ("", ".", "..") for part in path.parts):
        raise ContractError(f"non-normal repository path: {value!r}")
    normalized = path.as_posix()
    if normalized != value:
        raise ContractError(f"repository path is not normalized: {value!r}")
    return normalized


def is_executable_candidate_line(value: str) -> bool:
    text = value.strip()
    return bool(text and not text.startswith(("//", "/*", "*", "#")) and text not in ("{", "}", "},", ");"))


def parse_changed_lines(diff_text: str) -> list[dict[str, Any]]:
    """Strict parser for Git's zero-context unified diff; returns candidate source lines."""
    lines = diff_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if lines and lines[-1] == "": lines.pop()
    in_file = False; plus_seen = False; old_path = target_path = rename_target = None
    copy_source = copy_target = None
    old_remaining = new_remaining = new_line = candidate_ordinal = modified_quota = 0
    rows: list[dict[str, Any]] = []

    def complete_hunk() -> None:
        if old_remaining or new_remaining:
            raise ContractError("truncated or under-counted hunk")
        if in_file and (copy_source is None) != (copy_target is None):
            raise ContractError("incomplete copy identity")

    for line in lines:
        if line.startswith("diff --git "):
            complete_hunk()
            match = re.fullmatch(r"diff --git a/(.+) b/(.+)", line)
            if not match: raise ContractError("malformed diff header")
            old_path, target_path = map(normalize_repo_path, match.groups())
            in_file = True; plus_seen = False; rename_target = None; copy_source = copy_target = None
            continue
        if not in_file: raise ContractError("orphan diff metadata or hunk")
        if line.startswith("@@ "):
            complete_hunk()
            if not plus_seen: raise ContractError("hunk lacks consistent +++ header")
            if (copy_source is None) != (copy_target is None): raise ContractError("incomplete copy identity")
            match = re.fullmatch(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: .*)?", line)
            if not match: raise ContractError("malformed hunk header")
            old_remaining = int(match.group(2) or "1"); new_remaining = int(match.group(4) or "1")
            if target_path is None and new_remaining != 0:
                raise ContractError("deleted candidate hunk adds lines")
            new_line = int(match.group(3)); candidate_ordinal = 0
            modified_quota = min(old_remaining, new_remaining)
            continue
        if old_remaining or new_remaining:
            if line.startswith("-") and not line.startswith("---"):
                if old_remaining == 0: raise ContractError("overlong old hunk")
                old_remaining -= 1; continue
            if line.startswith("+") and not line.startswith("+++"):
                if new_remaining == 0 or target_path is None: raise ContractError("addition in zero/deleted/complete new hunk")
                content = line[1:]
                rows.append({"path": target_path, "line": new_line,
                             "changeKind": "MODIFIED" if candidate_ordinal < modified_quota else "ADDED",
                             "candidateText": content})
                candidate_ordinal += 1; new_line += 1; new_remaining -= 1; continue
            if line == "\\ No newline at end of file": continue
            raise ContractError("unknown zero-context hunk body")
        if line.startswith("rename from "):
            if normalize_repo_path(line[12:]) != old_path: raise ContractError("rename-from mismatch")
        elif line.startswith("rename to "):
            rename_target = normalize_repo_path(line[10:])
            if rename_target != target_path: raise ContractError("rename-to differs from diff target")
        elif line.startswith("copy from "):
            copy_source = normalize_repo_path(line[10:])
            if copy_source != old_path: raise ContractError("copy-from mismatch")
        elif line.startswith("copy to "):
            copy_target = normalize_repo_path(line[8:])
            if copy_target != target_path: raise ContractError("copy-to differs from diff target")
        elif line.startswith("--- "):
            value = line[4:]
            if value != "/dev/null" and (not value.startswith("a/") or normalize_repo_path(value[2:]) != old_path):
                raise ContractError("old header differs from diff identity")
        elif line.startswith("+++ "):
            value = line[4:]
            if value == "/dev/null": target_path = None
            elif not value.startswith("b/") or normalize_repo_path(value[2:]) != target_path:
                raise ContractError("candidate header differs from diff identity")
            if rename_target is not None and target_path != rename_target: raise ContractError("rename target mismatch")
            plus_seen = True
        elif re.fullmatch(r"(?:(?:old|new) mode|(?:new|deleted) file mode) [0-7]{6}", line):
            pass
        elif line.startswith(("index ", "similarity index ", "dissimilarity index ")):
            pass
        elif line == "GIT binary patch" or line.startswith(("Binary files ", "literal ", "delta ")):
            raise ContractError("BINARY_DIFF_REQUIRES_NONEXECUTABLE_DISPOSITION")
        elif line == "\\ No newline at end of file":
            pass
        else:
            raise ContractError("unknown diff metadata")
    complete_hunk()
    return rows


def validate_exclusion(row: dict[str, Any]) -> None:
    required = {"kind", "pattern", "reason", "reviewerReceiptDigest"}
    if set(row) != required or row["kind"] not in EXCLUSION_KINDS:
        raise ContractError("coverage exclusion shape/kind differs")
    pattern = row["pattern"]
    normalize_repo_path(pattern.replace("*", "x"))
    parent, _, leaf = pattern.rpartition("/")
    if (pattern in ("*", "**") or pattern.endswith("/**") or pattern.startswith("**/") or
            any(character in pattern for character in "?[]") or pattern.count("*") > 1 or
            ("*" in pattern and (not parent or "*" in parent or leaf in ("*", "**")))):
        raise ContractError("broad coverage exclusion forbidden")
    if not row["reason"].strip() or not re.fullmatch(r"[0-9a-f]{64}", row["reviewerReceiptDigest"]):
        raise ContractError("coverage exclusion lacks reason/reviewer receipt")
    reason = row["reason"].lower()
    required_reason_word = {"GENERATED_CODE": "generat", "PREVIEW": "preview", "PLATFORM_GLUE": "platform"}
    if required_reason_word[row["kind"]] not in reason:
        raise ContractError("coverage exclusion reason does not establish its allowed kind")
    if "*" in pattern:
        markers = {"GENERATED_CODE": ("generat",), "PREVIEW": ("preview",),
                   "PLATFORM_GLUE": ("platform", "adapter", "infrastructure")}[row["kind"]]
        if not any(marker in pattern.lower() for marker in markers):
            raise ContractError("coverage exclusion glob is not bounded to its allowed kind")
    lowered = pattern.lower()
    if any(token in lowered for token in PROTECTED_EXCLUSION_TOKENS):
        raise ContractError("coverage exclusion reaches protected correctness path")


def validate_exclusion_set(exclusions: list[dict[str, Any]], receipts: list[dict[str, Any]]) -> None:
    by_digest: dict[str, dict[str, Any]] = {}
    for receipt in receipts:
        if set(receipt) != {"receiptDigest", "kind", "pattern", "status", "path", "reasonDigest"}:
            raise ContractError("reviewer receipt shape differs")
        digest_value = receipt["receiptDigest"]
        if not re.fullmatch(r"[0-9a-f]{64}", digest_value) or digest_value in by_digest:
            raise ContractError("duplicate/invalid reviewer receipt")
        by_digest[digest_value] = receipt
    used: set[str] = set()
    for row in exclusions:
        validate_exclusion(row)
        receipt = by_digest.get(row["reviewerReceiptDigest"])
        if receipt is None or receipt["kind"] != row["kind"] or receipt["pattern"] != row["pattern"] or \
                receipt["path"] != row["pattern"] or receipt["status"] != "APPROVED" or \
                receipt["reasonDigest"] != sha256_bytes(row["reason"].encode("utf-8")):
            raise ContractError("exclusion reviewer binding differs")
        used.add(row["reviewerReceiptDigest"])
    if used != set(by_digest): raise ContractError("orphan reviewer receipt")


def validate_changed_line_sets(candidate: list[dict[str, Any]], identities: list[dict[str, Any]],
                               executable: list[dict[str, Any]]) -> None:
    candidate_keys: set[tuple[str, int]] = set()
    for row in candidate:
        if set(row) != {"path", "line", "changeKind", "candidateText"}:
            raise ContractError("changed candidate row shape differs")
        key = (normalize_repo_path(row["path"]), row["line"])
        if key in candidate_keys or not isinstance(row["line"], int) or row["line"] < 1:
            raise ContractError("duplicate/invalid changed candidate identity")
        candidate_keys.add(key)
    identity_keys: set[tuple[str, int]] = set()
    for row in identities:
        if set(row) != {"path", "line"}: raise ContractError("xccov identity shape differs")
        key = (normalize_repo_path(row["path"]), row["line"])
        if key in identity_keys or not isinstance(row["line"], int) or row["line"] < 1:
            raise ContractError("duplicate/invalid xccov identity")
        identity_keys.add(key)
    expected = [row for row in candidate if (row["path"], row["line"]) in identity_keys]
    executable_keys = {(normalize_repo_path(row["path"]), row["line"]) for row in executable}
    if len(executable_keys) != len(executable) or executable_keys != candidate_keys & identity_keys or executable != expected:
        raise ContractError("changed executable rows are not the exact xccov intersection")


def evaluate_tier(metrics: dict[str, Any], floor: dict[str, Any]) -> str:
    required = ("executableLinePercent", "functionPercent", "changedExecutableLinePercent",
                "changedFunctionCompletelyUncoveredCount")
    if any(key not in metrics or not isinstance(metrics[key], (int, float)) for key in required):
        raise ContractError("coverage metrics are incomplete")
    if any(not math.isfinite(metrics[key]) for key in required):
        raise ContractError("coverage metric is non-finite")
    if any(metrics[key] < 0 or metrics[key] > 100 for key in required[:3]) or metrics[required[3]] < 0:
        raise ContractError("coverage metric outside closed range")
    passed = (metrics["executableLinePercent"] >= floor["executableLinePercent"] and
              metrics["functionPercent"] >= floor["functionPercent"] and
              metrics["changedExecutableLinePercent"] >= floor["changedExecutableLinePercent"])
    if floor["tier"] == "CRITICAL_CORRECTNESS" and metrics["changedFunctionCompletelyUncoveredCount"] != 0:
        passed = False
    return "PASS" if passed else "FAIL"


def validate_pass_closure(receipt: dict[str, Any], tier: dict[str, Any], exclusion: dict[str, Any],
                          comparison: dict[str, Any], diff_text: str) -> None:
    artifacts = (receipt, tier, exclusion, comparison)
    if any(item["authority"] != receipt["authority"] for item in artifacts):
        raise ContractError("future PASS authority differs across artifacts")
    expected_authority = authority_binding()
    actual_authority = receipt["authority"]
    for key in ("executionMode", "ledgerDigest", "ledgerCASSequence", "acceptanceEnabled",
                "hostedDispatchEnabled", "requiresAcceptedS10_6Reconciliation"):
        expected_authority[key] = actual_authority.get(key)
    actual_prerequisite = actual_authority.get("directPrerequisite", {})
    for key in ("nativeCompileRan", "nativeTestsRan", "languageModeClosureSatisfied",
                "acceptanceCredit"):
        expected_authority["directPrerequisite"][key] = actual_prerequisite.get(key)
    expected_authority["directPrerequisite"]["officialAcceptanceEvidence"] = \
        actual_prerequisite.get("officialAcceptanceEvidence")
    if receipt["authority"] != expected_authority or receipt["authority"]["directPrerequisite"]["cardID"] != "V23-P00-C12":
        raise ContractError("future PASS immutable C13/C12 authority differs")
    if (actual_authority["executionMode"] != "POST_S10_6_ACCEPTANCE" or
            not re.fullmatch(r"[0-9a-f]{64}", actual_authority.get("ledgerDigest") or "") or
            not isinstance(actual_authority.get("ledgerCASSequence"), int) or
            actual_authority["ledgerCASSequence"] <= LEDGER_CAS_SEQUENCE or
            not actual_authority["acceptanceEnabled"] or not actual_authority["hostedDispatchEnabled"] or
            actual_authority["requiresAcceptedS10_6Reconciliation"] or
            actual_authority["phase10PollingDuringParallelExecution"] or actual_authority["releaseCredit"]):
        raise ContractError("future PASS execution authority is not accepted and current")
    if (not actual_prerequisite["nativeCompileRan"] or not actual_prerequisite["nativeTestsRan"] or
            not actual_prerequisite["languageModeClosureSatisfied"] or
            not actual_prerequisite["acceptanceCredit"] or actual_prerequisite["releaseCredit"]):
        raise ContractError("future PASS C12 prerequisite is not accepted")
    official = receipt["authority"]["directPrerequisite"]["officialAcceptanceEvidence"]
    proof_keys = ("CardAcceptanceInclusionProofV1Digest",
                  "CardAcceptanceInclusionProofRecoveryReceiptV1Digest",
                  "CandidateAcceptanceCompatibilityReceiptV1Digest")
    if set(official) != set(proof_keys) | {"acceptanceCurrentness", "compatibility", "zeroOrphanAcceptanceProofComplete"} or \
            any(not re.fullmatch(r"[0-9a-f]{64}", official.get(key, "")) for key in proof_keys) or \
            official.get("acceptanceCurrentness") != "PASS" or official.get("compatibility") != "PASS" or \
            not official.get("zeroOrphanAcceptanceProofComplete"):
        raise ContractError("official prerequisite acceptance proofs incomplete")
    if not re.fullmatch(r"[0-9a-f]{40}", receipt.get("candidateHead") or "") or \
            not re.fullmatch(r"[0-9a-f]{40}", receipt.get("candidateTree") or "") or not receipt["candidateBound"]:
        raise ContractError("future PASS candidate is unbound")
    if not receipt.get("acceptingXcresultPath") or not re.fullmatch(r"[0-9a-f]{64}", receipt.get("acceptingXcresultDigest") or "") or \
            not receipt.get("toolchainIdentity") or not re.fullmatch(r"[0-9a-f]{64}", receipt.get("fixtureDigest") or ""):
        raise ContractError("future PASS xcresult/toolchain/fixture incomplete")
    if receipt["xccovStatus"] != "PASS" or not re.fullmatch(r"[0-9a-f]{64}", receipt.get("xccovExecutableLineSetDigest") or ""):
        raise ContractError("future PASS xccov evidence incomplete")
    normalized_diff = diff_text.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized_diff or not receipt.get("changedDiffArtifactPath") or \
            normalize_repo_path(receipt["changedDiffArtifactPath"]) != receipt["changedDiffArtifactPath"] or \
            receipt.get("changedDiffDigest") != sha256_bytes(normalized_diff.encode("utf-8")):
        raise ContractError("future PASS normalized changed-diff binding differs")
    parsed = parse_changed_lines(normalized_diff)
    if receipt["changedCandidateLines"] != parsed or \
            receipt.get("changedCandidateLineSetDigest") != sha256_bytes(pretty_bytes(parsed)):
        raise ContractError("future PASS candidate rows are not bound to changed diff")
    validate_changed_line_sets(receipt["changedCandidateLines"], receipt["xccovExecutableLineIdentities"],
                               receipt["changedExecutableLines"])
    expected_identity_digest = sha256_bytes(pretty_bytes(receipt["xccovExecutableLineIdentities"]))
    if receipt["xccovExecutableLineSetDigest"] != expected_identity_digest:
        raise ContractError("xccov executable identity digest differs")
    if tier["tiers"] != TIER_FLOORS or tier["performanceCoverageInstrumentation"] != "REJECTED":
        raise ContractError("future PASS tier authority differs")
    for index, floor in enumerate(TIER_FLOORS):
        row = receipt["coverageByTier"][index]
        if row["tier"] != floor["tier"] or row["result"] != "PASS" or evaluate_tier(row, floor) != "PASS":
            raise ContractError("future PASS tier gate failed")
    ui = receipt["coverageByTier"][2]
    if ui["tier"] != "UI_PLATFORM_GLUE" or ui["result"] != "PASS" or not ui["semanticIntegrationEvidence"]:
        raise ContractError("future PASS UI semantic evidence absent")
    validate_exclusion_set(exclusion["exclusions"], exclusion["reviewerReceipts"])
    accepted = comparison["releaseClosureAcceptedS10_6Base"]
    if not comparison["comparisonReady"] or accepted["status"] != "PASS" or \
            not re.fullmatch(r"[0-9a-f]{40}", accepted.get("head") or "") or \
            not re.fullmatch(r"[0-9a-f]{40}", accepted.get("tree") or ""):
        raise ContractError("accepted S10.6 comparison base unresolved")
    current = receipt["currentness"]
    if current != {"candidateBindingCurrent": True, "xcresultCurrent": True,
                    "comparisonBaseCurrent": True, "toolchainAndFixtureCurrent": True, "result": "PASS"}:
        raise ContractError("future PASS currentness incomplete")
    if receipt["tierReleaseDigest"] != tier["artifactDigest"] or receipt["exclusionDigest"] != exclusion["artifactDigest"] or \
            receipt["comparisonBaseDigest"] != comparison["artifactDigest"]:
        raise ContractError("future PASS cross-digests stale")
    required_true = ("acceptanceEnabled", "receiptSatisfied", "acceptanceCredit")
    if any(not receipt[key] for key in required_true) or receipt["blockers"] or not receipt["evidenceArtifacts"] or \
            not receipt["nativeCompileRan"] or not receipt["hostedDispatchRan"] or \
            not receipt["performanceCoverageInstrumentationRejected"] or \
            receipt["performanceCoverageInstrumentationUsed"] or receipt["requiresAcceptedS10_6Reconciliation"] or \
            receipt["releaseCredit"] or any(item["acceptanceCredit"] or item["releaseCredit"] for item in artifacts[1:]):
        raise ContractError("future PASS closure gates incomplete")
    expected_lifecycle = common_fields("unused")["lifecycle"]
    if any(item["lifecycle"] != expected_lifecycle for item in artifacts):
        raise ContractError("future PASS immutable lifecycle differs")
    for item in artifacts:
        body = {key: value for key, value in item.items() if key != "artifactDigest"}
        if item.get("artifactDigest") != digest(body):
            raise ContractError(f"future PASS artifact digest differs: {item.get('schema')}")


def common_fields(schema: str) -> dict[str, Any]:
    return {
        "schema": schema, "schemaVersion": 1, "cardID": CARD_ID,
        "authority": authority_binding(),
        "lifecycle": {
            "persistence": "IMMUTABLE_BUILD_BOUND_TOOLING_OR_EVIDENCE_ARTIFACT",
            "supersession": "APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT",
            "successorTriggers": ["SOURCE_CHANGE", "COMPARISON_BASE_CHANGE", "TOOLCHAIN_CHANGE",
                                  "FIXTURE_CHANGE", "EVIDENCE_CHANGE"],
            "customerData": "NONE", "interruption": "FAIL_CLOSED_NO_PARTIAL_ACCEPTANCE",
            "recovery": "BYTE_EXACT_REGENERATION_OR_NEW_SUCCESSOR_RECEIPT",
        },
    }


def sealed(value: dict[str, Any]) -> dict[str, Any]:
    value.update({"acceptanceCredit": False, "releaseCredit": False})
    return seal(value)


def build_artifacts(root: Path) -> dict[str, dict[str, Any]]:
    validate_frozen_authority(root)
    validate_fence(root)
    validate_sources(root)
    validate_c12(root)
    tier = sealed({**common_fields("CoverageTierReleaseV1"),
        "tiers": TIER_FLOORS,
        "uiAndPlatformGlue": {"coveragePercentGate": "FORBIDDEN_VANITY_PERCENT",
                              "requiredEvidence": "SEMANTIC_AND_INTEGRATION_EVIDENCE"},
        "changedLineLaw": {"command": DIFF_COMMAND, "pathForm": "NORMALIZED_REPOSITORY_RELATIVE_POSIX",
                           "addedAndModifiedCandidateExecutableLinesCount": True,
                           "deletedOnlyLinesCount": False, "renameIdentity": "TARGET_PATH",
                           "xccovExecutableIntersectionRequired": True},
        "performanceCoverageInstrumentation": "REJECTED",
    })
    exclusion = sealed({**common_fields("CoverageExclusionV1"),
        "allowedKinds": EXCLUSION_KINDS, "exclusions": [], "reviewerReceipts": [],
        "requiredFields": ["EXACT_PATH_OR_BOUNDED_GLOB", "GENERATOR_OR_PLATFORM_REASON",
                           "REVIEWER_RECEIPT_DIGEST"],
        "protectedPathTokens": PROTECTED_EXCLUSION_TOKENS,
        "broadAbsoluteBackslashOrTraversalPatternAllowed": False,
        "unknownExclusionDisposition": "FAIL_CLOSED",
    })
    comparison = sealed({**common_fields("CoverageComparisonBaseV1"),
        "cardPreCardIntegrationBase": {"head": BASE_HEAD, "tree": BASE_TREE,
                                       "purpose": "CHANGED_CODE_NON_REGRESSION"},
        "releaseClosureAcceptedS10_6Base": {"head": None, "tree": None,
                                            "status": "UNRESOLVED_RECONCILIATION_REQUIRED"},
        "basesAreDistinctAuthorities": True, "comparisonReady": False,
        "fabricatedBaselineAllowed": False,
    })
    receipt = sealed({**common_fields("CodeCoverageReceiptV1"),
        "candidateHead": None, "candidateTree": None, "candidateBound": False,
        "tierReleaseDigest": tier["artifactDigest"], "exclusionDigest": exclusion["artifactDigest"],
        "comparisonBaseDigest": comparison["artifactDigest"],
        "acceptingXcresultPath": None, "acceptingXcresultDigest": None,
        "xcresultReusePolicy": "SAME_ACCEPTING_XCRESULT_BUNDLES_ONLY",
        "toolchainIdentity": None, "fixtureDigest": None,
        "xccovStatus": "NOT_RUN", "changedDiffCommand": DIFF_COMMAND,
        "changedDiffArtifactPath": None, "changedDiffDigest": None,
        "changedCandidateLineSetDigest": None,
        "changedCandidateLines": [], "xccovExecutableLineIdentities": [],
        "xccovExecutableLineSetDigest": None, "changedExecutableLines": [], "coverageByTier": [
            {"tier": "CRITICAL_CORRECTNESS", "executableLinePercent": None,
             "functionPercent": None, "changedExecutableLinePercent": None,
             "changedFunctionCompletelyUncoveredCount": None, "result": "NOT_RUN"},
            {"tier": "DOMAIN_APPLICATION", "executableLinePercent": None,
             "functionPercent": None, "changedExecutableLinePercent": None,
             "changedFunctionCompletelyUncoveredCount": None, "result": "NOT_RUN"},
            {"tier": "UI_PLATFORM_GLUE", "semanticIntegrationEvidence": [], "result": "NOT_RUN"},
        ],
        "evidenceArtifacts": [], "blockers": ["CANDIDATE_UNBOUND", "XCRESULT_NOT_BOUND",
                                               "XCCOV_NOT_RUN", "ACCEPTED_S10_6_BASE_UNRESOLVED"],
        "currentness": {"candidateBindingCurrent": False, "xcresultCurrent": False,
                        "comparisonBaseCurrent": False, "toolchainAndFixtureCurrent": False,
                        "result": "BLOCKED"},
        "performanceCoverageInstrumentationRejected": True,
        "performanceCoverageInstrumentationUsed": False,
        "nativeCompileRan": False, "hostedDispatchRan": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "receiptSatisfied": False, "releaseReady": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    })
    return dict(zip(ARTIFACT_PATHS, [receipt, tier, exclusion, comparison]))


def exclusion_row_schema() -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False,
            "required": ["kind", "pattern", "reason", "reviewerReceiptDigest"],
            "properties": {
                "kind": {"type": "string", "enum": EXCLUSION_KINDS},
                "pattern": {"type": "string", "minLength": 1},
                "reason": {"type": "string", "minLength": 1},
                "reviewerReceiptDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            }}


def reviewer_receipt_schema() -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False,
            "required": ["receiptDigest", "kind", "pattern", "status", "path", "reasonDigest"],
            "properties": {"receiptDigest": {"type":"string", "pattern":"^[0-9a-f]{64}$"},
                "kind": {"type":"string", "enum":EXCLUSION_KINDS}, "pattern":{"type":"string","minLength":1},
                "status":{"const":"APPROVED"}, "path":{"type":"string","minLength":1},
                "reasonDigest":{"type":"string","pattern":"^[0-9a-f]{64}$"}}}


def line_identity_schema() -> dict[str, Any]:
    return {"type":"object", "additionalProperties":False, "required":["path","line"],
            "properties":{"path":{"type":"string","minLength":1},"line":{"type":"integer","minimum":1}}}


def changed_line_schema() -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False,
            "required": ["path", "line", "changeKind", "candidateText"],
            "properties": {"path": {"type": "string", "minLength": 1},
                           "line": {"type": "integer", "minimum": 1},
                           "changeKind": {"type": "string", "enum": ["ADDED", "MODIFIED"]},
                           "candidateText": {"type": "string", "minLength": 1}}}


def structural_schema(value: Any, key: str = "") -> dict[str, Any]:
    if key in ("schema", "schemaVersion", "cardID"):
        return {"const": value}
    if value is None:
        if key in ("candidateHead", "candidateTree", "head", "tree"):
            return {"anyOf": [{"type": "null"}, {"type": "string", "pattern": "^[0-9a-f]{40}$"}]}
        if key.endswith("Digest"):
            return {"anyOf": [{"type": "null"}, {"type": "string", "pattern": "^[0-9a-f]{64}$"}]}
        if key.endswith("Percent"):
            return {"anyOf": [{"type": "null"}, {"type": "number", "minimum": 0, "maximum": 100}]}
        if key.endswith("Count"):
            return {"anyOf": [{"type": "null"}, {"type": "integer", "minimum": 0}]}
        return {"anyOf": [{"type": "null"}, {"type": "string", "minLength": 1}]}
    if isinstance(value, bool):
        return {"type": "boolean"}
    if isinstance(value, int):
        return {"type": "integer", "minimum": 0}
    if isinstance(value, str):
        if key.endswith("Digest"):
            return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        if key in ("baseHead", "baseTree", "implementationHead", "implementationTree"):
            return {"type": "string", "pattern": "^[0-9a-f]{40}$"}
        if key == "result" or key.lower().endswith("status"):
            return {"type": "string", "enum": sorted(set(RESULTS + [value]))}
        return {"type": "string", "minLength": 1}
    if isinstance(value, list):
        if key in ("exclusions",):
            return {"type": "array", "items": exclusion_row_schema()}
        if key == "reviewerReceipts":
            return {"type":"array", "items": reviewer_receipt_schema()}
        if key in ("changedCandidateLines", "changedExecutableLines"):
            return {"type": "array", "items": changed_line_schema()}
        if key == "xccovExecutableLineIdentities":
            return {"type":"array", "items":line_identity_schema()}
        if key in ("evidenceArtifacts", "semanticIntegrationEvidence", "blockers"):
            return {"type": "array", "items": {"type": "string", "minLength": 1}}
        return {"type": "array", "minItems": len(value), "maxItems": len(value),
                "prefixItems": [structural_schema(item, key) for item in value], "items": False}
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "required": list(value),
                "properties": {name: structural_schema(item, name) for name, item in value.items()}}
    raise ContractError(f"unsupported schema value: {key}")


def reusable_schema(artifact: dict[str, Any]) -> dict[str, Any]:
    return {"$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": f"https://assetrounds.invalid/v23/{artifact['schema']}.schema.json",
            "title": artifact["schema"], **structural_schema(artifact)}


def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    artifacts = build_artifacts(root)
    schemas = {schema: reusable_schema(artifacts[artifact])
               for schema, artifact in zip(SCHEMA_PATHS, ARTIFACT_PATHS)}
    return {**schemas, **artifacts}


def build_manifest(root: Path) -> dict[str, Any]:
    rows = []
    for relative in FENCED_PATHS:
        if relative == MANIFEST_PATH:
            continue
        path = root / relative
        if not path.is_file():
            raise ContractError(f"C13 manifest input missing: {relative}")
        rows.append({"path": relative, "sha256": sha256_bytes(path.read_bytes()), "bytes": path.stat().st_size})
    return seal({"schema": "V23P00C13ToolingManifestV1", "schemaVersion": 1,
                 "cardID": CARD_ID, "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
                 "authority": authority_binding(), "pathFence": FENCED_PATHS,
                 "artifacts": rows, "artifactCount": len(rows), "nativeCompileRan": False,
                 "hostedDispatchRan": False, "adoptionEnabled": False, "acceptanceEnabled": False,
                 "phase10PollingDuringParallelExecution": False, "acceptanceCredit": False,
                 "releaseReady": False, "releaseCredit": False})
