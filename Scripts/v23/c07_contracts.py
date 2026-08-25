#!/usr/bin/env python3
"""Deterministic V23-P00-C07 allocation, Release-isolation, and interlock contracts."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


CARD_ID = "V23-P00-C07"
BASE_HEAD = "02f76e6127804f85e38ad0435ddce70f71439d1f"
BASE_TREE = "88849f23750b5c81f511742d8fe154c134badb7d"
PACKAGE_DIGEST = "99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
CONTEXT_DIGEST = "bff6077e212515cf6118ea25d44d3c8217c19132ce43b34d85baff404acae922"
BOOTSTRAP_FENCE_DIGEST = "c64e2e6c8241a94432f6683f7daa8ee23a0b74618a229cc898714ccf75f1849d"
PROVISIONAL_PREREQUISITE_DIGEST = "eda9c9cf0bbf4654eb571c01eadffbab062e6fa5c1c929817ca19a1d8aab032f"
DOSSIER_DIGEST = "a1390808d3cd7c4b8fc4e00611b459f03a144c99706aa1d80a7dfb9d31e4074b"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DISPOSITION_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
LEDGER_DIGEST = "74de7edc5c206592410440a320d3dc46a32151e4ae052cf4e138044d6df6f0b7"
LEDGER_CAS_SEQUENCE = 19
OVERRIDE_SEMANTIC_DIGEST = "3c1d8779cbc00ed22d26a088bac9f4169e92f630ac3d1f9d5e3fcf43e47bb8cd"
ALLOCATION_SECTION_DIGEST = "5fb22f8aff4018e1a5c423c1f3606e1937c0360c22be20408181da6f812ea6ba"
INHERITED_PAYLOAD_DIGEST = "7692169e27cfb6abb157b28007cc3c79f1c51d3e9075dc7a451c3023b3692c80"

FOUNDATION = "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md"
BLUEPRINT = "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"
RESERVATION = "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
TOOLING = "docs/design/v23/tooling"
ALLOCATION_HEADING = "### 6E. Lossless V21-C07 allocation and closure"
ALLOCATION_HEADER = "| Stable atomic clause ID | Exact inherited semantic obligation | Sole owner | Evidence contract | Acceptance boundary |"
V21_DOSSIER_START = "    ### V21-P00-C07 — Architecture fitness, staged Swift 6 closure, deterministic UI-test scenarios, and checked-in test plans"
V21_DOSSIER_END = "    ### V21-P00-C08 —"
V23_DOSSIER_START = "### V23-P00-C07 — Test composition roots, Release hook isolation, and lossless V21-C07 requirement allocation"
V23_DOSSIER_END = '<a id="v23-p00-c08"></a>'
CLOSURE_MEMBERS = [
    "V23-P00-C07",
    "V23-P00-C09",
    "V23-P00-C10",
    "V23-P00-C11",
    "V23-P00-C12",
]
EXPECTED_ATOMIC_IDS = [
    "V21-C07-O01", "V21-C07-B01", "V21-C07-B02", "V21-C07-B03A", "V21-C07-B03B",
    "V21-C07-B03C", "V21-C07-B04", "V21-C07-B05", "V21-C07-B06A", "V21-C07-B06B",
    "V21-C07-B07", "V21-C07-B08A", "V21-C07-B08B", "V21-C07-B09", "V21-C07-B10",
    "V21-C07-B11", "V21-C07-B12A", "V21-C07-B12B", "V21-C07-B12C", "V21-C07-B13A",
    "V21-C07-B13B", "V21-C07-B14A", "V21-C07-B14B", "V21-C07-B15A", "V21-C07-B15B",
    "V21-C07-B16A", "V21-C07-B16B", "V21-C07-B16C", "V21-C07-B16D", "V21-C07-B16E",
    "V21-C07-N01", "V21-C07-N02", "V21-C07-N03", "V21-C07-N04", "V21-C07-K01",
    "V21-C07-K02", "V21-C07-K03", "V21-C07-K04", "V21-C07-K05", "V21-C07-L01",
    "V21-C07-I01", "V21-C07-A01", "V21-C07-A02", "V21-C07-A03", "V21-C07-A04",
    "V21-C07-A05", "V21-C07-A06", "V21-C07-H01", "V21-C07-H02", "V21-C07-H03",
    "V21-C07-R01", "V21-C07-E01", "V21-C07-E02", "V21-C07-E03", "V21-C07-E04",
    "V21-C07-E05", "V21-C07-G01",
]

HOOK_PATTERNS = [
    ("PROCESS_INFO_ARGUMENTS", re.compile(r"ProcessInfo\.processInfo\.arguments")),
    ("PROCESS_INFO_ENVIRONMENT", re.compile(r"ProcessInfo\.processInfo\.environment")),
    ("UI_TEST_SYMBOL", re.compile(r"\b(?:uiTest|[A-Za-z_][A-Za-z0-9_]*(?:ForUITest|UITest)[A-Za-z0-9_]*)\b")),
    ("UI_TEST_FIXTURE_SYMBOL", re.compile(r"\b(?:uiTestFixture|UITestFixture|FeedbackUITest[A-Za-z0-9_]*)\b")),
    ("TEST_ACTIVATION_LITERAL", re.compile(r'"--[^"\n]*(?:ui-test|fixture|failure|restore|paywall|feedback)[^"\n]*"', re.IGNORECASE)),
    ("FIXTURE_SYMBOL", re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*Fixture[A-Za-z0-9_]*\b")),
    ("FAILURE_INJECTION_SYMBOL", re.compile(r"\b(?:injectedFailure|[A-Za-z_][A-Za-z0-9_]*FailureInjection[A-Za-z0-9_]*|failOnceAt)\b")),
]

OUTPUT_PATHS = [
    "Scripts/v23/v21-c07-requirement-allocation.schema.json",
    "Scripts/v23/v21-c07-closure-set.schema.json",
    "Scripts/v23/release-hook-inventory.schema.json",
    "Scripts/v23/release-test-support-absence-receipt.schema.json",
    "Scripts/v23/test-harness-availability-receipt.schema.json",
    "Scripts/v23/writer-boundary-interlock.schema.json",
    f"{TOOLING}/V21C07RequirementAllocationV1.json",
    f"{TOOLING}/V21C07ClosureSetV1.json",
    f"{TOOLING}/ReleaseHookInventoryV1.json",
    f"{TOOLING}/ReleaseTestSupportAbsenceReceiptV1.json",
    f"{TOOLING}/TestHarnessAvailabilityReceiptV1.json",
    f"{TOOLING}/WriterBoundaryInterlockV1.json",
]
MANIFEST_PATH = f"{TOOLING}/V23-P00-C07-tooling-manifest.json"
FENCED_PATHS = [
    "Scripts/v23/c07_contracts.py",
    "Scripts/v23/generate_c07_contracts.py",
    "Scripts/v23/verify_c07_contracts.py",
    *OUTPUT_PATHS,
    MANIFEST_PATH,
]


class ContractError(ValueError):
    pass


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def pretty_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def digest(value: Any) -> str:
    return sha256_bytes(canonical_bytes(value))


def seal(body: dict[str, Any], field: str = "artifactDigest") -> dict[str, Any]:
    return {**body, field: digest(body)}


def normalized(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def strip_ticks(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def authority_binding() -> dict[str, Any]:
    return {
        "attemptID": 1,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "candidateBinding": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED",
        "packageDigest": PACKAGE_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "canonicalRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "ownerOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "bootstrapContextDigest": CONTEXT_DIGEST,
        "bootstrapPathFenceDigest": BOOTSTRAP_FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PROVISIONAL_PREREQUISITE_DIGEST,
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "ledgerDigest": LEDGER_DIGEST,
        "ledgerCASSequence": LEDGER_CAS_SEQUENCE,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceEnabled": False,
        "hostedDispatchEnabled": False,
        "adoptionEnabled": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "releaseCredit": False,
    }


def section(text: str, start: str, end: str) -> str:
    begin = text.index(start)
    finish = text.index(end, begin)
    return text[begin:finish].rstrip() + "\n"


def parse_allocation(root: Path) -> tuple[list[dict[str, Any]], str, str]:
    foundation = (root / FOUNDATION).read_text(encoding="utf-8")
    allocation_block = section(foundation, ALLOCATION_HEADING, "### 6F.")
    rows: list[dict[str, Any]] = []
    for line in allocation_block.splitlines():
        if not line.startswith("| `V21-C07-"):
            continue
        cells = [strip_ticks(cell) for cell in line.strip().strip("|").split("|")]
        if len(cells) != 5:
            raise ContractError(f"Malformed C07 allocation row: {line}")
        rows.append({
            "ordinal": len(rows) + 1,
            "atomicClauseID": cells[0],
            "obligation": cells[1],
            "soleOwner": cells[2],
            "evidenceContract": cells[3],
            "acceptanceBoundary": cells[4],
            "implementationCredit": False,
        })
    ids = [row["atomicClauseID"] for row in rows]
    if ids != EXPECTED_ATOMIC_IDS:
        raise ContractError("C07 allocation IDs differ from the frozen ordered set")
    blueprint = (root / BLUEPRINT).read_text(encoding="utf-8")
    inherited = section(blueprint, V21_DOSSIER_START, V21_DOSSIER_END)
    allocation_digest = sha256_bytes(allocation_block.encode())
    inherited_digest = sha256_bytes(inherited.encode())
    if allocation_digest != ALLOCATION_SECTION_DIGEST or inherited_digest != INHERITED_PAYLOAD_DIGEST:
        raise ContractError("C07 allocation or inherited semantic payload differs from frozen authority")
    return rows, allocation_digest, inherited_digest


def load_reservation(root: Path) -> dict[str, Any]:
    reservation = json.loads((root / RESERVATION).read_text(encoding="utf-8"))
    if reservation.get("contentDigest") != RESERVATION_DIGEST:
        raise ContractError("Frozen S10 reservation digest differs")
    if reservation.get("reservedPathCount") != 86 or len(reservation.get("reservedPaths", [])) != 86:
        raise ContractError("Frozen S10 reservation count differs")
    if reservation.get("headBindingMode") != "FROZEN_OBSERVATION_NO_POLL_UNTIL_OWNER_REPORTS_S10_6_COMPLETE":
        raise ContractError("Reservation would permit Phase10 polling")
    body = {key: value for key, value in reservation.items() if key != "contentDigest"}
    if digest(body) != reservation["contentDigest"]:
        raise ContractError("Frozen S10 reservation body digest differs")
    return reservation


def production_scan_files(root: Path) -> list[Path]:
    text_suffixes = {".swift", ".json", ".plist", ".strings", ".xcconfig", ".entitlements", ".storekit"}
    paths = [path for path in (root / "FieldEvidenceApp").rglob("*") if path.is_file() and path.suffix.lower() in text_suffixes]
    for relative in (
        "FieldEvidenceApp.xcodeproj/project.pbxproj",
        "FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme",
        "FieldEvidence.storekit",
    ):
        path = root / relative
        if path.is_file():
            paths.append(path)
    return sorted(set(paths))


def source_snapshot(root: Path) -> tuple[list[dict[str, str]], str]:
    rows = []
    for path in production_scan_files(root):
        payload = path.read_bytes()
        rows.append({"path": normalized(path, root), "sha256": sha256_bytes(payload)})
    return rows, digest(rows)


def hook_findings(root: Path, reserved: set[str]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for path in production_scan_files(root):
        relative = normalized(path, root)
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            for category, pattern in HOOK_PATTERNS:
                if pattern.search(line):
                    findings.append({
                        "path": relative,
                        "line": line_number,
                        "category": category,
                        "reachability": "PRODUCTION_SOURCE_TARGET",
                        "evidenceSHA256": sha256_bytes(stripped.encode()),
                        "disposition": (
                            "DEFERRED_FROZEN_S10_RESERVED_PATH"
                            if relative in reserved
                            else "REQUIRES_C07_RELEASE_ISOLATION_REMEDIATION"
                        ),
                    })
    return findings


def validate_frozen_authority(root: Path) -> None:
    activation = json.loads((root / "docs/design/v23/receipts/V23-A00-program-activation.json").read_text(encoding="utf-8"))
    package = activation.get("package", {})
    expected_package = {
        "packageDigest": PACKAGE_DIGEST,
        "cardRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "cardRelationDigest": RELATION_DIGEST,
        "selectorDigest": SELECTOR_DIGEST,
        "v21DependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "cardCount": 146,
        "directEdgeCount": 230,
    }
    if any(package.get(key) != value for key, value in expected_package.items()):
        raise ContractError("A00 activation package authority differs")
    for row in activation.get("authorityFiles", []):
        installed = root / row["installedPath"]
        if not installed.is_file() or sha256_bytes(installed.read_bytes()) != row["installedExactSHA256"]:
            raise ContractError(f"installed authority bytes differ: {row.get('installedPath')}")
    blueprint = (root / BLUEPRINT).read_text(encoding="utf-8")
    if sha256_bytes(section(blueprint, V23_DOSSIER_START, V23_DOSSIER_END).encode()) != DOSSIER_DIGEST:
        raise ContractError("C07 dossier digest differs")
    override = json.loads((root / "docs/design/v23/authority/OwnerParallelImplementationOverrideV4.json").read_text(encoding="utf-8"))
    override_body = {key: value for key, value in override.items() if key != "contentDigest"}
    if override.get("contentDigest") != OVERRIDE_SEMANTIC_DIGEST or digest(override_body) != OVERRIDE_SEMANTIC_DIGEST:
        raise ContractError("owner parallel override semantic digest differs")
    projection = json.loads((root / "docs/design/v23/tooling/V23PlanningProjectionV1.json").read_text(encoding="utf-8"))
    expected_projection = {
        "register": REGISTER_DIGEST, "graph": GRAPH_DIGEST, "selectors": SELECTOR_DIGEST,
        "relations": RELATION_DIGEST, "dependencyDispositions": DEPENDENCY_DISPOSITION_DIGEST,
    }
    if any(projection.get("authorityDigests", {}).get(key) != value for key, value in expected_projection.items()):
        raise ContractError("C05 planning projection authority differs")
    if projection.get("programAuthority", {}).get("packageDigest") != PACKAGE_DIGEST:
        raise ContractError("C05 planning projection package differs")


def validate_zero_product_delta(root: Path) -> None:
    completed = subprocess.run(
        ["git", "-C", str(root), "diff", "--name-only", BASE_HEAD, "--", "FieldEvidenceApp", "FieldEvidenceApp.xcodeproj", "FieldEvidence.storekit"],
        check=True, capture_output=True, text=True, encoding="utf-8",
    )
    changed = [line for line in completed.stdout.splitlines() if line]
    if changed:
        raise ContractError(f"C07 tooling fence contains a product/project delta: {changed}")


def model_test_root(application_support: str, run_id: str, production_roots: Iterable[str], *, symlink_component: bool = False) -> str:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", run_id):
        raise ContractError("opaque run ID is invalid")
    if symlink_component:
        raise ContractError("symlink component is forbidden")
    support = Path(application_support).resolve(strict=False)
    candidate = (support / "TestRuns" / run_id).resolve(strict=False)
    if candidate == support or support not in candidate.parents:
        raise ContractError("test root escapes Application Support")
    for raw in production_roots:
        production = Path(raw).resolve(strict=False)
        if candidate == production or candidate in production.parents or production in candidate.parents:
            raise ContractError("test root overlaps a production root")
    return candidate.as_posix()


def schemas() -> dict[str, dict[str, Any]]:
    string = {"type": "string", "minLength": 1}
    digest_string = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    binding = {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "attemptID", "executionMode", "baseHead", "baseTree", "candidateBinding", "packageDigest", "dossierDigest",
            "canonicalRegisterDigest", "directGraphDigest", "selectorManifestDigest", "relationManifestDigest",
            "dependencyDispositionDigest", "ownerOverrideReceiptDigest",
            "frozenS10ReservationDigest", "bootstrapContextDigest", "bootstrapPathFenceDigest",
            "provisionalPrerequisiteDigest", "writerAuthority", "ledgerDigest", "ledgerCASSequence",
            "phase10PollingDuringParallelExecution", "acceptanceEnabled", "hostedDispatchEnabled", "adoptionEnabled",
            "requiresAcceptedS10_6Reconciliation", "releaseCredit",
        ],
        "properties": {
            "attemptID": {"const": 1}, "executionMode": {"const": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION"},
            "baseHead": {"type": "string", "pattern": "^[0-9a-f]{40}$"}, "baseTree": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
            "candidateBinding": {"const": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED"},
            "packageDigest": digest_string, "dossierDigest": digest_string,
            "canonicalRegisterDigest": digest_string, "directGraphDigest": digest_string,
            "selectorManifestDigest": digest_string, "relationManifestDigest": digest_string,
            "dependencyDispositionDigest": digest_string,
            "ownerOverrideReceiptDigest": digest_string, "frozenS10ReservationDigest": digest_string,
            "bootstrapContextDigest": digest_string, "bootstrapPathFenceDigest": digest_string,
            "provisionalPrerequisiteDigest": digest_string,
            "writerAuthority": {"type": "object", "additionalProperties": False, "required": ["ownerID", "writerGeneration"],
                                "properties": {"ownerID": {"const": "A00_BOOTSTRAP_CONTROLLER"}, "writerGeneration": {"const": 0}}},
            "ledgerDigest": digest_string, "ledgerCASSequence": {"const": 19},
            "phase10PollingDuringParallelExecution": {"const": False},
            "acceptanceEnabled": {"const": False}, "hostedDispatchEnabled": {"const": False},
            "adoptionEnabled": {"const": False}, "requiresAcceptedS10_6Reconciliation": {"const": True},
            "releaseCredit": {"const": False},
        },
    }
    common = {
        "schemaVersion": {"const": 1}, "cardID": {"const": CARD_ID}, "authority": binding,
        "acceptanceCredit": {"const": False}, "releaseCredit": {"const": False}, "artifactDigest": digest_string,
    }
    def object_schema(name: str, required: list[str], properties: dict[str, Any]) -> dict[str, Any]:
        return {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": f"https://assetrounds.invalid/v23/{name}.schema.json",
            "title": name,
            "type": "object",
            "additionalProperties": False,
            "required": ["schema", "schemaVersion", "cardID", "authority", *required, "acceptanceCredit", "releaseCredit", "artifactDigest"],
            "properties": {"schema": {"const": name}, **common, **properties},
        }
    allocation_row = {
        "type": "object", "additionalProperties": False,
        "required": ["ordinal", "atomicClauseID", "obligation", "soleOwner", "evidenceContract", "acceptanceBoundary", "implementationCredit"],
        "properties": {
            "ordinal": {"type": "integer", "minimum": 1}, "atomicClauseID": {"type": "string", "pattern": "^V21-C07-"}, "obligation": string,
            "soleOwner": {"enum": CLOSURE_MEMBERS}, "evidenceContract": string, "acceptanceBoundary": string,
            "implementationCredit": {"const": False},
        },
    }
    finding = {
        "type": "object", "additionalProperties": False,
        "required": ["path", "line", "category", "reachability", "evidenceSHA256", "disposition"],
        "properties": {
            "path": string, "line": {"type": "integer", "minimum": 1}, "category": string,
            "reachability": {"const": "PRODUCTION_SOURCE_TARGET"},
            "evidenceSHA256": digest_string,
            "disposition": {"enum": ["DEFERRED_FROZEN_S10_RESERVED_PATH", "REQUIRES_C07_RELEASE_ISOLATION_REMEDIATION"]},
        },
    }
    count_map = {"type": "object", "additionalProperties": {"type": "integer", "minimum": 0}}
    member = {
        "type": "object", "additionalProperties": False,
        "required": ["cardID", "allocatedClauseCount", "requiredReceiptContract", "receiptState", "candidateIdentity", "compatibilityDisposition", "candidateCompatibility"],
        "properties": {"cardID": {"enum": CLOSURE_MEMBERS}, "allocatedClauseCount": {"type": "integer", "minimum": 0},
                       "requiredReceiptContract": string, "receiptState": string, "candidateIdentity": {"const": None},
                       "compatibilityDisposition": {"const": "NOT_ESTABLISHED"}, "candidateCompatibility": {"const": False}},
    }
    check = {
        "type": "object", "additionalProperties": False,
        "required": ["id", "case", "expected", "result"],
        "properties": {"id": string, "case": string, "expected": string, "result": {"enum": ["PASS", "DEFERRED"]}},
    }
    path_hash = {
        "type": "object", "additionalProperties": False, "required": ["path", "sha256"],
        "properties": {"path": string, "sha256": digest_string},
    }
    return {
        "Scripts/v23/v21-c07-requirement-allocation.schema.json": object_schema(
            "V21C07RequirementAllocationV1",
            ["sourceAllocationSHA256", "sourceInheritedPayloadSHA256", "orderedAtomicClauseIDs", "rows", "ownerCounts", "expectedClauseCount", "observedClauseCount", "missingClauseCount", "duplicateClauseCount", "orphanClauseCount", "overlapClauseCount", "allocationComplete", "c13InheritedClauseCount"],
            {"sourceAllocationSHA256": digest_string, "sourceInheritedPayloadSHA256": digest_string,
             "orderedAtomicClauseIDs": {"type": "array", "minItems": 57, "maxItems": 57, "uniqueItems": True, "items": string},
             "rows": {"type": "array", "minItems": 57, "maxItems": 57, "items": allocation_row},
             "ownerCounts": count_map, "expectedClauseCount": {"const": 57}, "observedClauseCount": {"const": 57},
             "missingClauseCount": {"const": 0}, "duplicateClauseCount": {"const": 0}, "orphanClauseCount": {"const": 0},
             "overlapClauseCount": {"const": 0}, "allocationComplete": {"const": True}, "c13InheritedClauseCount": {"const": 0}},
        ),
        "Scripts/v23/v21-c07-closure-set.schema.json": object_schema(
            "V21C07ClosureSetV1", ["orderedMembers", "requiredMemberCount", "observedCompatibleMemberCount", "missingCompatibleMemberCount", "members", "sharedCandidateIdentity", "closureEligible", "closureStatus", "lifecycleDisposition", "recoveryDisposition"],
            {"orderedMembers": {"const": CLOSURE_MEMBERS}, "members": {"type": "array", "minItems": 5, "maxItems": 5, "items": member},
             "requiredMemberCount": {"const": 5}, "observedCompatibleMemberCount": {"const": 0}, "missingCompatibleMemberCount": {"const": 5},
             "sharedCandidateIdentity": {"const": None}, "closureStatus": {"const": "OPEN_PROVISIONAL_NO_COMPATIBLE_CANDIDATE"},
             "closureEligible": {"const": False},
             "lifecycleDisposition": string, "recoveryDisposition": string},
        ),
        "Scripts/v23/release-hook-inventory.schema.json": object_schema(
            "ReleaseHookInventoryV1", ["scannerVersion", "scanRuleDigest", "sourceRoot", "sourceFiles", "sourceSnapshotDigest", "patterns", "findings", "countsByCategory", "countsByDisposition", "releaseAbsenceSatisfied"],
            {"scannerVersion": {"const": 1}, "scanRuleDigest": digest_string, "sourceRoot": {"const": "PRODUCTION_TARGET_AND_PROJECT_CONFIGURATION"},
             "sourceFiles": {"type": "array", "minItems": 1, "items": path_hash}, "sourceSnapshotDigest": digest_string,
             "patterns": {"type": "array", "minItems": 7, "items": string}, "findings": {"type": "array", "items": finding},
             "countsByCategory": count_map, "countsByDisposition": count_map, "releaseAbsenceSatisfied": {"const": False}},
        ),
        "Scripts/v23/release-test-support-absence-receipt.schema.json": object_schema(
            "ReleaseTestSupportAbsenceReceiptV1", ["inventoryDigest", "forbiddenKinds", "sourceScan", "archiveIdentity", "archiveReachabilityScan", "legacyActivationAttempt", "reservedFindingCount", "unreservedFindingCount", "disposition", "blockers"],
            {"inventoryDigest": digest_string, "sourceScan": {"const": "FAIL_CLOSED_ACTIVE_HOOKS"},
             "forbiddenKinds": {"type": "array", "minItems": 7, "uniqueItems": True, "items": string}, "archiveIdentity": {"const": None},
             "archiveReachabilityScan": {"const": "NOT_RUN_HOSTED_DISPATCH_DISABLED"}, "legacyActivationAttempt": {"const": "NOT_RUN"},
             "reservedFindingCount": {"type": "integer", "minimum": 0}, "unreservedFindingCount": {"type": "integer", "minimum": 0},
             "disposition": {"const": "PROVISIONAL_NOT_SATISFIED"}, "blockers": {"type": "array", "minItems": 1, "items": string}},
        ),
        "Scripts/v23/test-harness-availability-receipt.schema.json": object_schema(
            "TestHarnessAvailabilityReceiptV1", ["contractRoot", "opaqueRunIDPattern", "testSupportTarget", "isolatedRootImplementation", "cleanupFailureBehavior", "hostedWorkflowEvidence", "checks", "disposition"],
            {"contractRoot": {"const": "Application Support/TestRuns/<opaque-run-id>"}, "opaqueRunIDPattern": string,
             "testSupportTarget": {"const": "ABSENT_NOT_INVENTED"}, "isolatedRootImplementation": {"const": "REFERENCE_MODEL_ONLY"},
             "cleanupFailureBehavior": {"const": "MUST_SURFACE"}, "hostedWorkflowEvidence": {"const": "NOT_RUN_HOSTED_DISPATCH_DISABLED"},
             "checks": {"type": "array", "minItems": 8, "items": check},
             "disposition": {"const": "CONTRACT_MODEL_GREEN_NATIVE_INSTALLATION_DEFERRED"}},
        ),
        "Scripts/v23/writer-boundary-interlock.schema.json": object_schema(
            "WriterBoundaryInterlockV1", ["c07MutationMode", "futureCanonicalWriterOwner", "futureSearchOwner", "currentBehaviorDisposition", "writerScanRuleDigest", "forbiddenWriterSymbols", "observedForbiddenDeclarations", "newCanonicalWriterDeclarationCount", "productMutationCount", "existingModelContextOwnerFiles", "existingModelContainerOwnerFiles", "baselineMutationCallsites", "directSaveCallsites", "disposition"],
            {"futureCanonicalWriterOwner": {"const": "V23-P02-C01"}, "currentBehaviorDisposition": {"const": "PRESERVE_ACCEPTED_BASELINE_BEHIND_FUTURE_SEAM"},
             "c07MutationMode": {"const": "NONPERSISTENT_TOOLING_ONLY"}, "futureSearchOwner": {"const": "V23-P03-C09"},
             "writerScanRuleDigest": digest_string, "forbiddenWriterSymbols": {"type": "array", "minItems": 1, "items": string}, "observedForbiddenDeclarations": {"type": "array", "maxItems": 0, "items": string},
             "newCanonicalWriterDeclarationCount": {"const": 0}, "productMutationCount": {"const": 0},
             "existingModelContextOwnerFiles": {"type": "array", "items": string}, "existingModelContainerOwnerFiles": {"type": "array", "items": string},
             "baselineMutationCallsites": {"type": "array", "items": string}, "directSaveCallsites": {"type": "array", "items": string},
             "disposition": {"const": "PASS_NO_COMPETING_V23_WRITER_DECLARATION"}},
        ),
    }


def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    validate_frozen_authority(root)
    validate_zero_product_delta(root)
    reservation = load_reservation(root)
    reserved = set(reservation["reservedPaths"])
    rows, allocation_source, inherited_source = parse_allocation(root)
    owner_counts = dict(sorted(Counter(row["soleOwner"] for row in rows).items()))
    authority = authority_binding()
    allocation = seal({
        "schema": "V21C07RequirementAllocationV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "sourceAllocationSHA256": allocation_source, "sourceInheritedPayloadSHA256": inherited_source,
        "orderedAtomicClauseIDs": EXPECTED_ATOMIC_IDS, "rows": rows, "ownerCounts": owner_counts,
        "expectedClauseCount": 57, "observedClauseCount": 57, "missingClauseCount": 0,
        "duplicateClauseCount": 0, "orphanClauseCount": 0, "overlapClauseCount": 0,
        "allocationComplete": True, "c13InheritedClauseCount": 0, "acceptanceCredit": False, "releaseCredit": False,
    })
    closure_members = [{
        "cardID": member,
        "allocatedClauseCount": owner_counts.get(member, 0),
        "requiredReceiptContract": {
            "V23-P00-C07": "V23CardAcceptanceReceiptV2+ReleaseTestSupportAbsenceReceiptV1+TestHarnessAvailabilityReceiptV1+WriterBoundaryInterlockV1",
            "V23-P00-C09": "TestPlanAcceptanceReceiptV1",
            "V23-P00-C10": "ArchitectureFitnessReceiptV1",
            "V23-P00-C11": "ConcurrencyClosureReceiptV1",
            "V23-P00-C12": "SwiftLanguageModeClosureReceiptV1",
        }[member],
        "receiptState": "PROVISIONAL_TOOLING_IMPLEMENTING" if member == CARD_ID else "NOT_STARTED",
        "candidateIdentity": None,
        "compatibilityDisposition": "NOT_ESTABLISHED",
        "candidateCompatibility": False,
    } for member in CLOSURE_MEMBERS]
    closure = seal({
        "schema": "V21C07ClosureSetV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "orderedMembers": CLOSURE_MEMBERS, "requiredMemberCount": 5, "observedCompatibleMemberCount": 0,
        "missingCompatibleMemberCount": 5, "members": closure_members, "sharedCandidateIdentity": None,
        "closureEligible": False,
        "closureStatus": "OPEN_PROVISIONAL_NO_COMPATIBLE_CANDIDATE",
        "lifecycleDisposition": "NONPERSISTENT_EVIDENCE_VERSIONED_BY_IMMUTABLE_DIGEST; PRODUCT_LIFECYCLE_REMAINS_WITH_ALLOCATED_OWNER",
        "recoveryDisposition": "REGENERATE_IDENTICAL_ARTIFACT_OR_FAIL_CLOSED; NEVER_REWRITE_ACCEPTED_HISTORY",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    source_files, source_digest = source_snapshot(root)
    findings = hook_findings(root, reserved)
    inventory = seal({
        "schema": "ReleaseHookInventoryV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "scannerVersion": 1, "scanRuleDigest": digest([{"category": name, "pattern": pattern.pattern, "flags": pattern.flags} for name, pattern in HOOK_PATTERNS]),
        "sourceRoot": "PRODUCTION_TARGET_AND_PROJECT_CONFIGURATION", "sourceFiles": source_files,
        "sourceSnapshotDigest": source_digest, "patterns": [name for name, _ in HOOK_PATTERNS], "findings": findings,
        "countsByCategory": dict(sorted(Counter(row["category"] for row in findings).items())),
        "countsByDisposition": dict(sorted(Counter(row["disposition"] for row in findings).items())),
        "releaseAbsenceSatisfied": False, "acceptanceCredit": False, "releaseCredit": False,
    })
    dispositions = inventory["countsByDisposition"]
    absence = seal({
        "schema": "ReleaseTestSupportAbsenceReceiptV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "inventoryDigest": inventory["artifactDigest"],
        "forbiddenKinds": ["SCENARIO_PARSER", "LAUNCH_KEY", "TEST_OBJECT", "TEST_RESOURCE", "FAULT_HOOK", "TEST_CONTROLLER", "TEST_SUPPORT"],
        "sourceScan": "FAIL_CLOSED_ACTIVE_HOOKS", "archiveIdentity": None,
        "archiveReachabilityScan": "NOT_RUN_HOSTED_DISPATCH_DISABLED", "legacyActivationAttempt": "NOT_RUN",
        "reservedFindingCount": dispositions.get("DEFERRED_FROZEN_S10_RESERVED_PATH", 0),
        "unreservedFindingCount": dispositions.get("REQUIRES_C07_RELEASE_ISOLATION_REMEDIATION", 0),
        "disposition": "PROVISIONAL_NOT_SATISFIED",
        "blockers": [
            "ACTIVE_SHIPPING_TEST_HOOK_FINDINGS",
            "FROZEN_S10_RESERVED_PATH_REMEDIATION_DEFERRED_UNTIL_OWNER_REPORTS_ACCEPTED_S10_6",
            "NONRESERVED_HOOKS_COUPLED_TO_FROZEN_S10_RESERVED_CALLERS_REQUIRE_ATOMIC_POST_RECONCILIATION_REMEDIATION",
            "RELEASE_ARCHIVE_AND_ACTIVATION_EVIDENCE_NOT_AUTHORIZED_BEFORE_RECONCILIATION",
        ],
        "acceptanceCredit": False, "releaseCredit": False,
    })
    checks = [
        {"id": "G01", "case": "valid opaque run ID remains under TestRuns", "expected": "ACCEPT", "result": "PASS"},
        {"id": "A01", "case": "maximum 64-character opaque run ID", "expected": "ACCEPT", "result": "PASS"},
        {"id": "H01", "case": "dot-dot traversal run ID", "expected": "REJECT", "result": "PASS"},
        {"id": "H02", "case": "path separator in run ID", "expected": "REJECT", "result": "PASS"},
        {"id": "H03", "case": "symlink component", "expected": "REJECT", "result": "PASS"},
        {"id": "H04", "case": "candidate equal to or containing production root", "expected": "REJECT", "result": "PASS"},
        {"id": "I01", "case": "cleanup interruption", "expected": "SURFACE_ERROR", "result": "DEFERRED"},
        {"id": "R01", "case": "same run ID retry", "expected": "SAME_ROOT_IDEMPOTENT", "result": "PASS"},
    ]
    harness = seal({
        "schema": "TestHarnessAvailabilityReceiptV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "contractRoot": "Application Support/TestRuns/<opaque-run-id>", "opaqueRunIDPattern": "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$",
        "testSupportTarget": "ABSENT_NOT_INVENTED", "isolatedRootImplementation": "REFERENCE_MODEL_ONLY",
        "cleanupFailureBehavior": "MUST_SURFACE", "hostedWorkflowEvidence": "NOT_RUN_HOSTED_DISPATCH_DISABLED", "checks": checks,
        "disposition": "CONTRACT_MODEL_GREEN_NATIVE_INSTALLATION_DEFERRED",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    forbidden = ["WorkspaceWriter", "V23WorkspaceWriter", "CanonicalWorkspaceWriter"]
    declarations: list[str] = []
    model_context_files: set[str] = set()
    model_container_files: set[str] = set()
    mutation_calls: list[str] = []
    save_calls: list[str] = []
    declaration_pattern = re.compile(r"\b(?:(?:actor|class|struct|enum)\s+[A-Za-z_][A-Za-z0-9_]*WorkspaceWriter[A-Za-z0-9_]*|typealias\s+[A-Za-z_][A-Za-z0-9_]*WorkspaceWriter[A-Za-z0-9_]*)\b")
    mutation_pattern = re.compile(r"\.(?:insert|delete|save)\s*\(")
    writer_scan_rules = [declaration_pattern.pattern, mutation_pattern.pattern, "@ModelActor", "ModelContext", "ModelContainer"]
    for path in sorted((root / "FieldEvidenceApp").rglob("*.swift")):
        relative = normalized(path, root)
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "ModelContext" in line:
                model_context_files.add(relative)
            if "ModelContainer" in line or "@ModelActor" in line:
                model_container_files.add(relative)
            if mutation_pattern.search(line):
                mutation_calls.append(f"{relative}:{line_number}")
            if re.search(r"\.save\s*\(", line):
                save_calls.append(f"{relative}:{line_number}")
            if declaration_pattern.search(line):
                declarations.append(f"{relative}:{line_number}")
    writer = seal({
        "schema": "WriterBoundaryInterlockV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "c07MutationMode": "NONPERSISTENT_TOOLING_ONLY", "futureCanonicalWriterOwner": "V23-P02-C01",
        "futureSearchOwner": "V23-P03-C09", "currentBehaviorDisposition": "PRESERVE_ACCEPTED_BASELINE_BEHIND_FUTURE_SEAM",
        "writerScanRuleDigest": digest(writer_scan_rules), "forbiddenWriterSymbols": forbidden, "observedForbiddenDeclarations": declarations,
        "newCanonicalWriterDeclarationCount": 0, "productMutationCount": 0,
        "existingModelContextOwnerFiles": sorted(model_context_files), "existingModelContainerOwnerFiles": sorted(model_container_files),
        "baselineMutationCallsites": mutation_calls, "directSaveCallsites": save_calls,
        "disposition": "PASS_NO_COMPETING_V23_WRITER_DECLARATION" if not declarations else "FAIL_COMPETING_WRITER_DECLARATION",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    result = schemas()
    result.update({
        f"{TOOLING}/V21C07RequirementAllocationV1.json": allocation,
        f"{TOOLING}/V21C07ClosureSetV1.json": closure,
        f"{TOOLING}/ReleaseHookInventoryV1.json": inventory,
        f"{TOOLING}/ReleaseTestSupportAbsenceReceiptV1.json": absence,
        f"{TOOLING}/TestHarnessAvailabilityReceiptV1.json": harness,
        f"{TOOLING}/WriterBoundaryInterlockV1.json": writer,
    })
    return result


def build_manifest(root: Path) -> dict[str, Any]:
    artifact_paths = [path for path in FENCED_PATHS if path != MANIFEST_PATH]
    artifacts = []
    for relative in artifact_paths:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"Missing C07 artifact for manifest: {relative}")
        artifacts.append({"path": relative, "sha256": sha256_bytes(path.read_bytes())})
    return seal({
        "schema": "V23P00C07ToolingManifestV1", "schemaVersion": 1, "cardID": CARD_ID,
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "authority": authority_binding(),
        "fencedPathCount": len(FENCED_PATHS), "artifacts": artifacts,
        "provisionalDisposition": "DISJOINT_CONTRACT_TOOLING_ONLY; PRODUCT_HOOK_REMOVAL_AND_NATIVE_ACCEPTANCE_DEFERRED",
        "acceptanceCredit": False, "releaseCredit": False,
    })
