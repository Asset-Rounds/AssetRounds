#!/usr/bin/env python3
"""Generate or verify deterministic, pre-mutation V30 Card 1 bootstrap payloads.

This program is deliberately a package-side generator.  It never accesses the
active Phase 10 checkout.  It only projects pre-issued package authority into
the isolated V30 execution namespace; it is not an authority issuer.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


PACKAGE = Path(__file__).resolve().parent
FENCE_SOURCE = PACKAGE / "V30_PRE_S10_PATH_FENCES.json"
AUTHORITY = PACKAGE / "V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json"

AUTHORITY_ID = "ASSETROUNDS-V30-PRE-S10-20260902-R2"
V23_HEAD = "acbfb68355f903fe98638b6ef22e4814e7b48328"
V23_TREE = "47e17fae6b73dccd5029ccf4ac7cca659196f225"
COORDINATION_HEAD = "51ef2b3d970a25b4c83df8c8238609316e37034e"
COORDINATION_TREE = "060c83c3d1489fc011b1c921f6c85bec2b074478"
COORDINATION_SEQUENCE = 626
COORDINATION_LEDGER_DIGEST = "973090852e843e895125bea8da87c7e1689611c46d8219a70c1749be49398067"
COORDINATION_PROJECTION_DIGEST = "cf57849e8f7c245d38fd21a39da5938d10e13c9aca3976a71b7d3a3ee401f12d"
V30_BRANCH = "phase/v30-globalization"
V30_WORKTREE = r"C:\AssetRounds-v30-globalization"
V30_COORDINATION_BRANCH = "coord/v30-globalization-provisional"
V30_COORDINATION_WORKTREE = r"C:\AssetRounds-v30-globalization-coordination"
CARD_ID = "V30-P00-C01"
CARD_TITLE = "Provisional authority and isolated-lane validation"
MATERIALIZATION_TARGETS = {
    "context": "docs/design/v30/execution/contexts/V30-P00-C01-attempt-1.json",
    "fence": "docs/design/v30/execution/fences/V30-P00-C01-attempt-1.json",
    "currentTask": "docs/design/v30/execution/V30_CURRENT_TASK.md",
    "ciSelection": "docs/design/v30/execution/V30_CI_SELECTION.json",
    "executionHandoff": "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
    "provisionalLedgerProjection": "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json",
}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def payload_digest(value: dict[str, Any]) -> str:
    projected = dict(value)
    projected.pop("payloadDigest", None)
    return sha256_bytes(canonical(projected))


def load_json(path: Path) -> Any:
    try:
        raw = path.read_bytes()
    except FileNotFoundError as exc:
        raise ValueError(f"required package authority is absent: {path.name}") from exc
    if raw.startswith(b"\xef\xbb\xbf") or b"\r\n" in raw:
        raise ValueError(f"non-canonical package JSON encoding: {path.name}")
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid JSON: {path.name}: {exc}") from exc


def locate_card_one(source: Any) -> dict[str, Any]:
    candidates: list[Any] = []
    if isinstance(source, dict):
        for key in ("cards", "cardFences", "fences", "entries"):
            value = source.get(key)
            if isinstance(value, list):
                candidates.extend(value)
            elif isinstance(value, dict):
                candidates.extend(value.values())
        if source.get("cardID") == CARD_ID:
            candidates.append(source)
    elif isinstance(source, list):
        candidates = source
    matches = [item for item in candidates if isinstance(item, dict) and item.get("cardID") == CARD_ID]
    if len(matches) != 1:
        raise ValueError(f"path-fence authority must contain exactly one {CARD_ID} entry; found {len(matches)}")
    return matches[0]


def extract_path_records(value: Any, label: str, *, required: bool) -> tuple[list[str], list[dict[str, Any]]]:
    """Project fence records into active path strings without discarding evidence.

    The fence is authoritative: every allowed path is a record carrying its own
    provenance/evidence, rather than a bare string.  The execution projection
    needs the exact path sequence while retaining those source records intact.
    """
    if not isinstance(value, list) or (required and not value):
        raise ValueError(f"{label} must be {'a non-empty' if required else 'a'} list")
    records: list[dict[str, Any]] = []
    paths: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, dict) or not isinstance(item.get("path"), str) or not item["path"]:
            raise ValueError(f"{label}[{index}] must be an object with non-empty path")
        records.append(item)
        paths.append(item["path"])
    if len(set(paths)) != len(paths):
        raise ValueError(f"{label} must not contain duplicate paths")
    return paths, records


def authority_binding() -> dict[str, Any]:
    authority = load_json(AUTHORITY)
    authority_meta = authority.get("authority")
    authority_id = authority_meta.get("id") if isinstance(authority_meta, dict) else authority.get("authorityID")
    if authority_id != AUTHORITY_ID:
        raise ValueError("authorityID mismatch")
    authority_digest = authority.get("authorityContentDigest")
    if not isinstance(authority_digest, str) or len(authority_digest) != 64:
        raise ValueError("authorityContentDigest absent or invalid")
    installation_request_id = authority.get("installationRequestID")
    request_ids = authority.get("bootstrapRequestIDs")
    ledger_authority = authority.get("provisionalLedger")
    if not isinstance(installation_request_id, str) or not installation_request_id:
        raise ValueError("authority installationRequestID absent")
    if not isinstance(request_ids, dict) or not all(isinstance(request_ids.get(key), str) and request_ids[key] for key in (
        "installation", "coordinationGenesis", "activationReceipt", "productSelectionProjection", "cardSelection"
    )):
        raise ValueError("authority bootstrapRequestIDs incomplete")
    if request_ids["installation"] != installation_request_id:
        raise ValueError("authority installation request ID mismatch")
    if not isinstance(ledger_authority, dict):
        raise ValueError("authority provisionalLedger absent")
    required_ledger_fields = (
        "ledgerID", "requestIDNamespace", "initialWriterGeneration", "initialSequence", "externalRef",
        "refCreationExpectedOld", "genesisExpectedOldRef", "genesisExpectedLedger", "bootstrapAllowedPaths",
        "runtimeMutablePaths", "activationReceiptPath", "cardSelectionReceiptPath",
    )
    if any(field not in ledger_authority for field in required_ledger_fields):
        raise ValueError("authority provisionalLedger bootstrap fields incomplete")
    if ledger_authority["requestIDNamespace"] != AUTHORITY_ID:
        raise ValueError("authority provisionalLedger request namespace mismatch")
    if ledger_authority["initialWriterGeneration"] != 1 or ledger_authority["initialSequence"] != 0:
        raise ValueError("authority provisionalLedger genesis generation or sequence mismatch")
    if not isinstance(ledger_authority["bootstrapAllowedPaths"], list) or len(ledger_authority["bootstrapAllowedPaths"]) != 3:
        raise ValueError("authority provisionalLedger bootstrap path set mismatch")
    if not isinstance(ledger_authority["runtimeMutablePaths"], list) or len(ledger_authority["runtimeMutablePaths"]) != 1:
        raise ValueError("authority provisionalLedger runtime mutable path set mismatch")
    return {
        "authorityContentDigest": authority_digest,
        "authorityFileSHA256": sha256_bytes(AUTHORITY.read_bytes()),
        "pathFenceFileSHA256": sha256_bytes(FENCE_SOURCE.read_bytes()),
        "installationRequestID": installation_request_id,
        "bootstrapRequestIDs": request_ids,
        "provisionalLedger": {field: ledger_authority[field] for field in required_ledger_fields},
    }


def make_payloads() -> dict[str, bytes]:
    binding = authority_binding()
    fence_source = load_json(FENCE_SOURCE)
    card_fence = locate_card_one(fence_source)
    allowed_paths, allowed_path_records = extract_path_records(
        card_fence.get("allowedPaths"), "Card 1 allowedPaths", required=True
    )
    s10_shared_paths, s10_shared_records = extract_path_records(
        card_fence.get("s10SharedPaths", card_fence.get("s10Shared", [])),
        "Card 1 s10SharedPaths",
        required=False,
    )
    if not set(s10_shared_paths).issubset(allowed_paths):
        raise ValueError("Card 1 s10SharedPaths must be an exact allowedPaths subset")

    common = {
        "schemaVersion": "V30BootstrapPayloadV1",
        "authorityID": AUTHORITY_ID,
        "cardID": CARD_ID,
        "cardTitle": CARD_TITLE,
        "preS10FinalCredit": False,
        "phase10Access": "FORBIDDEN_NO_READ_NO_WRITE_NO_POLL",
        "frozenV23": {"branch": "phase/v23-expansion", "head": V23_HEAD, "tree": V23_TREE},
        "frozenV23Coordination": {
            "head": COORDINATION_HEAD,
            "tree": COORDINATION_TREE,
            "sequence": COORDINATION_SEQUENCE,
            "ledgerDigest": COORDINATION_LEDGER_DIGEST,
            "projectionDigest": COORDINATION_PROJECTION_DIGEST,
        },
        "provisionalExecution": {"branch": V30_BRANCH, "worktree": V30_WORKTREE},
        "installationRequestID": binding["installationRequestID"],
        "bootstrapRequestIDs": binding["bootstrapRequestIDs"],
        "packageBinding": binding,
        "materializationTargets": MATERIALIZATION_TARGETS,
    }

    context: dict[str, Any] = {
        **common,
        "kind": "V30CardContextV1",
        "directPrerequisites": [],
        "outcome": "Validate authority/package/worktree/Phase10 isolation/zero credit only; no product work.",
        "activeTaskPath": MATERIALIZATION_TARGETS["currentTask"],
        "fencePath": MATERIALIZATION_TARGETS["fence"],
        "allowedPaths": allowed_paths,
        "allowedPathCount": len(allowed_paths),
        "selectorPath": MATERIALIZATION_TARGETS["ciSelection"],
        "executionHandoffPath": MATERIALIZATION_TARGETS["executionHandoff"],
        "inheritedExecutionPaths": [
            "docs/execution/CURRENT_TASK.md",
            "docs/product/BUILD_PLAN_V4.md",
            "docs/execution/V4_IMPLEMENTATION_RUNBOOK.md",
        ],
        "inheritedExecutionPathsDisposition": "FROZEN_READ_ONLY_PREDECESSOR_EVIDENCE",
    }
    context["payloadDigest"] = payload_digest(context)

    fence: dict[str, Any] = {
        **common,
        "kind": "V30CardPathFenceV1",
        "source": {
            "path": FENCE_SOURCE.name,
            "sha256": sha256_bytes(FENCE_SOURCE.read_bytes()),
            "sourceCardFence": card_fence,
        },
        "allowedPaths": allowed_paths,
        "allowedPathRecords": allowed_path_records,
        "s10SharedPaths": s10_shared_paths,
        "s10SharedPathRecords": s10_shared_records,
        "forbiddenPaths": ["C:\\AssetRounds"],
        "forbiddenOperation": "No read, write, status, build, test, Git, or process inspection against active Phase 10 checkout.",
    }
    fence["payloadDigest"] = payload_digest(fence)

    ci: dict[str, Any] = {
        **common,
        "kind": "V30CISelectionV1",
        "mode": "DISABLED_STATIC_PREFLIGHT",
        "hostedDispatchAllowed": False,
        "hostedDispatchUnlockCard": "V30-P00-C05",
        "windowsStaticChecksAllowed": True,
        "selector": None,
        "reason": "Card 1 validates bootstrap authority only; no hosted route is pinned before Card 5.",
    }
    ci["payloadDigest"] = payload_digest(ci)

    current_task = "\n".join([
        "# V30 Current Task",
        "",
        "- Schema: `V30CurrentTaskV1`",
        f"- Authority ID: `{AUTHORITY_ID}`",
        f"- Card: `{CARD_ID} — {CARD_TITLE}`",
        "- Card ordinal: `1 of 55`",
        "- Execution epoch: `PRE_S10_PROVISIONAL`",
        "- Direct prerequisites: `[]`",
        "- Outcome: Validate authority, package, dedicated worktree, Phase 10 isolation, and zero-credit posture only. No product work.",
        "- Allowed paths: exactly the generated Card 1 fence; no inferred paths.",
        f"- Exact Card 1 fence: `{MATERIALIZATION_TARGETS['fence']}`.",
        f"- Installation request ID: `{binding['installationRequestID']}`.",
        "- Active selector: `docs/design/v30/execution/V30_CI_SELECTION.json` (`DISABLED_STATIC_PREFLIGHT`).",
        "- Hosted dispatch: forbidden until `V30-P00-C05` pins the route.",
        "- Phase 10 checkout `C:\\AssetRounds`: forbidden read/write/poll/build/test/Git/process target.",
        "- Inherited `docs/execution/CURRENT_TASK.md`, `docs/product/BUILD_PLAN_V4.md`, and `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`: frozen read-only predecessor evidence; not V30 active-task authority.",
        "- Inherited `Scripts/ci-selection.json`: frozen read-only predecessor evidence; never the V30 active selector and never modified.",
        "- Credit: all pre-S10 work is provisional and earns no final-card, main, release, or Phase 10 compatibility credit.",
        "",
        "## Exact allowed paths",
        "",
        *[f"- `{path}`" for path in allowed_paths],
        "",
    ]).encode("utf-8")

    ledger_authority = binding["provisionalLedger"]
    ledger_genesis: dict[str, Any] = {
        "schemaVersion": "V30ProvisionalExecutionLedgerV1",
        "kind": "EXPECTED_ABSENT_G3_COORDINATION_LEDGER_GENESIS",
        "authorityID": AUTHORITY_ID,
        "installationRequestID": binding["installationRequestID"],
        "requestID": binding["bootstrapRequestIDs"]["coordinationGenesis"],
        "ledgerID": ledger_authority["ledgerID"],
        "requestIDNamespace": ledger_authority["requestIDNamespace"],
        "coordination": {
            "branch": V30_COORDINATION_BRANCH,
            "worktree": V30_COORDINATION_WORKTREE,
            "externalRef": ledger_authority["externalRef"],
            "expectedRef": ledger_authority["refCreationExpectedOld"],
            "genesisExpectedOldRef": ledger_authority["genesisExpectedOldRef"],
            "expectedLedgerDigest": ledger_authority["genesisExpectedLedger"],
            "expectedAbsent": True,
            "canonicalLedgerExternal": True,
        },
        "sequence": ledger_authority["initialSequence"],
        "writerGeneration": ledger_authority["initialWriterGeneration"],
        "state": "GENESIS_PRE_SELECTION",
        "selectedCard": None,
        "creditedCards": [],
        "preS10FinalCredit": False,
        "previousLedgerDigest": None,
        "events": [],
        "requestResults": [],
        "bootstrapAllowedPaths": ledger_authority["bootstrapAllowedPaths"],
        "runtimeMutablePaths": ledger_authority["runtimeMutablePaths"],
        "receiptMetadata": {
            "activationRequestID": binding["bootstrapRequestIDs"]["activationReceipt"],
            "activationReceiptPath": ledger_authority["activationReceiptPath"],
            "selectionRequestID": binding["bootstrapRequestIDs"]["cardSelection"],
            "selectionReceiptPath": ledger_authority["cardSelectionReceiptPath"],
            "productProjectionRequestID": binding["bootstrapRequestIDs"]["productSelectionProjection"],
        },
        "frozenV23Observations": common["frozenV23"],
        "frozenV23CoordinationObservations": common["frozenV23Coordination"],
        "packageBinding": binding,
        "nextMutation": "Ordered separate operations only: coordination-genesis CAS, activation-receipt CAS, product-projection commit, then card-selection CAS for V30-P00-C01. They are never one combined operation.",
    }
    ledger_genesis["payloadDigest"] = payload_digest(ledger_genesis)

    ledger_projection: dict[str, Any] = {
        "schemaVersion": "V30ProvisionalLedgerProjectionV1",
        "kind": "PRODUCT_BRANCH_READ_ONLY_PROJECTION",
        "authorityID": AUTHORITY_ID,
        "canonicalLedgerExternal": True,
        "projectionTarget": MATERIALIZATION_TARGETS["provisionalLedgerProjection"],
        "installationRequestID": binding["installationRequestID"],
        "productProjectionRequestID": binding["bootstrapRequestIDs"]["productSelectionProjection"],
        "sourceGenesis": {
            "file": "V30_PROVISIONAL_LEDGER_GENESIS.json",
            "payloadDigest": ledger_genesis["payloadDigest"],
            "sequence": ledger_genesis["sequence"],
            "coordination": ledger_genesis["coordination"],
        },
        "selectedCard": None,
        "creditedCards": [],
        "preS10FinalCredit": False,
        "writeDisposition": "READ_ONLY_PROJECTION; product branch never becomes the canonical coordination ledger.",
        "packageBinding": binding,
    }
    ledger_projection["payloadDigest"] = payload_digest(ledger_projection)

    handoff = "\n".join([
        "# V30 Execution Handoff",
        "",
        "- Schema: `V30ExecutionHandoffGenesisV1`",
        "- Kind: `IMMUTABLE_GENESIS_HEADER`",
        f"- Authority ID: `{AUTHORITY_ID}`",
        f"- Authority content digest: `{binding['authorityContentDigest']}`",
        f"- Authority raw SHA-256: `{binding['authorityFileSHA256']}`",
        f"- Card-1 path-fence SHA-256: `{binding['pathFenceFileSHA256']}`",
        f"- Installation request ID: `{binding['installationRequestID']}`",
        "- Append-only: `true`",
        "- Pre-S10 final credit: `false`",
        f"- Initial next card: `{CARD_ID}`",
        f"- Install target: `{MATERIALIZATION_TARGETS['executionHandoff']}`",
        "- Entries: none. Entries may be appended only after installation and the separate G3 selection CAS.",
        "",
    ]).encode("utf-8")

    return {
        "V30_CARD_001_CONTEXT.json": canonical(context),
        "V30_CARD_001_FENCE.json": canonical(fence),
        "V30_CARD_001_CURRENT_TASK.md": current_task,
        "V30_CARD_001_CI_SELECTION.json": canonical(ci),
        "V30_EXECUTION_HANDOFF_GENESIS.md": handoff,
        "V30_PROVISIONAL_LEDGER_GENESIS.json": canonical(ledger_genesis),
        "V30_PROVISIONAL_LEDGER_PROJECTION.json": canonical(ledger_projection),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apply", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        expected = make_payloads()
    except ValueError as exc:
        print(f"HOLD: {exc}", file=sys.stderr)
        return 2
    mismatches = [name for name, content in expected.items() if not (PACKAGE / name).is_file() or (PACKAGE / name).read_bytes() != content]
    if args.check:
        if mismatches:
            print("FAIL: bootstrap payload drift: " + ", ".join(mismatches), file=sys.stderr)
            return 1
        print("PASS: V30 Card 1 bootstrap payloads are canonical")
        return 0
    for name, content in expected.items():
        (PACKAGE / name).write_bytes(content)
    print("APPLIED: V30 Card 1 bootstrap payloads")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
