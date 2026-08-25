#!/usr/bin/env python3
"""Hydrate a deterministic card spec/fence from frozen projection and bootstrap authority."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from card_contracts import (
    ContractError,
    digest,
    validate_fence_subset,
    validate_direct_evidence,
    validate_projection,
    verify_coordination_digest,
    verify_embedded_digest,
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def applicable_selectors(projection: dict[str, Any], card_id: str) -> list[dict[str, Any]]:
    return [row for row in projection["selectors"] if card_id in row["members"] or card_id in row["consumers"]]


def applicable_relations(projection: dict[str, Any], card_id: str) -> list[dict[str, Any]]:
    return [row for row in projection["relations"] if row["source"].split(":", 1)[0] == card_id or row["target"] == card_id]


def hydrate(
    projection: dict[str, Any],
    facets: dict[str, Any],
    context: dict[str, Any],
    bootstrap_fence: dict[str, Any],
    authority_context: dict[str, Any] | None = None,
    direct_evidence: list[dict[str, Any]] | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_projection(projection)
    verify_embedded_digest(facets, "artifactDigest")
    if digest(facets.get("facets", [])) != facets.get("canonicalRegistryDigest"):
        raise ContractError("contract facet registry digest mismatch")
    relation_facets = [row for row in projection["relations"] if row["kind"] == "CONTRACT_INPUT_PROVIDER"]
    facet_pairs = [(row["source"], row["target"]) for row in facets.get("facets", [])]
    relation_pairs = [(row["source"], row["target"]) for row in relation_facets]
    if facet_pairs != relation_pairs or len(facet_pairs) != len(set(facet_pairs)):
        raise ContractError("contract facets are missing, duplicated, orphaned, or out of order")
    ownership_members = [member for row in facets.get("ownershipRows", []) for member in row.get("familyMembers", [])]
    if len(ownership_members) != len(set(ownership_members)):
        raise ContractError("contract ownership manifest has multiple declaration owners")
    for facet in facets.get("facets", []):
        if not facet.get("sourceAuthorityRefs"):
            raise ContractError("contract facet resolves to zero source authority refs")
        selector = facet.get("selector", "")
        if selector.startswith("EXACT_EVIDENCE_FAMILIES:"):
            selected = selector.split(":", 1)[1].split("+")
            if not set(selected) <= set(facet["sourceAuthorityRefs"]):
                raise ContractError("contract facet selects a member outside source authority")
    verify_coordination_digest(context, "contextDigest")
    verify_coordination_digest(bootstrap_fence, "fenceDigest")
    card_id = context.get("cardID")
    attempt_id = context.get("attemptID")
    if bootstrap_fence.get("cardID") != card_id or bootstrap_fence.get("attemptID") != attempt_id:
        raise ContractError("bootstrap context/fence identity mismatch")
    rows = [row for row in projection["cards"] if row["id"] == card_id]
    if len(rows) != 1:
        raise ContractError("card register row is missing or ambiguous")
    row = rows[0]
    source_projection = context.get("sourceProjection", {})
    bound = {
        "register": "canonicalRegisterDigest",
        "graph": "directGraphDigest",
        "selectors": "selectorManifestDigest",
        "relations": "relationManifestDigest",
        "dependencyDispositions": "dependencyDispositionDigest",
    }
    for projection_key, context_key in bound.items():
        if context_key in source_projection and source_projection[context_key] != projection["authorityDigests"][projection_key]:
            raise ContractError(f"context authority mismatch: {context_key}")
    if row["directPrerequisites"] != context.get("directPrerequisites"):
        raise ContractError("context direct prerequisites differ from canonical register")
    paths = bootstrap_fence.get("allowedCreateOrReplacePaths", [])
    if not paths or len(paths) != len(set(paths)):
        raise ContractError("bootstrap fence paths are empty or duplicated")
    direct_edges = [edge for edge in projection["directEdges"] if edge["target"] == card_id]
    relations = applicable_relations(projection, card_id)
    selectors = applicable_selectors(projection, card_id)
    dependency_rows = [row for row in projection["dependencyDispositions"] if row["currentConsumer"] == card_id]
    facet_rows = [
        row for row in facets["facets"]
        if row["source"].split(":", 1)[0] == card_id or row["target"] == card_id
    ]
    short_card_id = card_id.removeprefix("V23-")
    ownership_rows = [
        row for row in facets.get("ownershipRows", [])
        if row["declarationOwner"] == short_card_id
        or row["semanticLifecycleOwner"] == short_card_id
        or row["lifecycleEnrollmentOwner"] == short_card_id
    ]
    contract_symbols = sorted({member for row in ownership_rows for member in row["familyMembers"]})
    if authority_context is None:
        raise ContractError("explicit latest unique authority context is required")
    live_authority = authority_context
    verify_coordination_digest(authority_context, "contextDigest")
    if authority_context.get("cardID") != "V23-P00-C05":
        raise ContractError("authority context must be the latest unique C05 bootstrap context")
    coordination = live_authority.get("coordination")
    if not coordination:
        raise ContractError("latest writer authority/ledger context is required")
    if coordination.get("writerAuthority") != {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0}:
        raise ContractError("provisional writer authority is stale or already adopted")
    if authority_context.get("phase10PollingDuringParallelExecution") is not False:
        raise ContractError("authority context would poll Phase10")
    if "overrideReceiptDigest" in bootstrap_fence and bootstrap_fence["overrideReceiptDigest"] != projection["programAuthority"]["overrideReceiptDigest"]:
        raise ContractError("bootstrap fence owner override receipt mismatch")
    fence_body = {
        "schema": "PathFenceV1",
        "schemaVersion": 1,
        "cardID": card_id,
        "attemptID": attempt_id,
        "baseHead": bootstrap_fence["baseHead"],
        "baseTree": bootstrap_fence["baseTree"],
        "contextDigest": context["contextDigest"],
        "bootstrapFenceDigest": bootstrap_fence["fenceDigest"],
        "authorityContextDigest": authority_context["contextDigest"],
        "writerAuthority": coordination["writerAuthority"],
        "ledgerDigest": coordination["ledgerDigest"],
        "ledgerCASSequence": coordination["ledgerCASSequence"],
        "allowedPaths": paths,
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "prohibitions": [
            "NO_PATH_OUTSIDE_FENCE",
            "NO_PHASE10_MUTATION",
            "NO_MAIN_MUTATION",
            "NO_ACCEPTANCE_OR_RELEASE_CREDIT",
            "NO_ADOPTION_WHILE_PROVISIONAL",
        ],
        "releaseCredit": False,
        "adoptionEnabled": False,
        "historicalDiffSubsetRequired": True,
        "oneShot": True,
        "expiresOn": bootstrap_fence.get("expiresOn", ["LATEST_UNIQUE_AUTHORITY_CONTEXT_CHANGE"]),
    }
    fence = {**fence_body, "fenceDigest": digest(fence_body)}
    execution_mode = context.get("executionMode", "BOOTSTRAP_PROVISIONAL")
    provisional = "PROVISIONAL" in execution_mode
    if provisional:
        if direct_edges and not context.get("provisionalPrerequisiteDigest"):
            raise ContractError("provisional prerequisite checkpoint is missing")
        if direct_evidence:
            raise ContractError("provisional hydration cannot consume official direct-edge evidence")
        readiness = "PROVISIONAL_IMPLEMENTATION_ONLY_NOT_READY_FOR_ACCEPTANCE"
        evidence_validated = False
        evidence_rows: list[dict[str, Any]] = []
    else:
        evidence_rows = direct_evidence or []
        validate_direct_evidence(projection, card_id, evidence_rows)
        readiness = "READY"
        evidence_validated = True
    spec_body = {
        "schema": "HydratedCardExecutionSpecV2",
        "schemaVersion": 2,
        "cardID": card_id,
        "attemptID": attempt_id,
        "registerOrdinal": row["ordinal"],
        "classification": row["classification"],
        "planningStatus": row["status"],
        "title": row["title"],
        "lineage": row["lineage"],
        "contextDigest": context["contextDigest"],
        "pathFenceDigest": fence["fenceDigest"],
        "authorityDigests": projection["authorityDigests"],
        "programAuthority": projection["programAuthority"],
        "authorityContextDigest": authority_context["contextDigest"],
        "directPrerequisiteEdges": direct_edges,
        "directPrerequisiteEvidence": evidence_rows,
        "directPrerequisiteEvidenceValidated": evidence_validated,
        "readinessDisposition": readiness,
        "selectors": selectors,
        "relations": relations,
        "contractFacets": facet_rows,
        "contractOwnership": ownership_rows,
        "contractSymbols": contract_symbols,
        "dependencyDispositions": dependency_rows,
        "repositoryPaths": paths,
        "repositoryPathOwners": [{"path": path, "owner": card_id} for path in paths],
        "generatedOutputs": [path for path in paths if path.endswith(".json")],
        "namedChecks": [f"{card_id}-{kind}01" for kind in ("G", "A", "H", "I", "R")],
        "lifecycleOwner": card_id,
        "declarationOwner": card_id,
        "writerAuthority": coordination["writerAuthority"],
        "ledgerDigest": coordination["ledgerDigest"],
        "ledgerCASSequence": coordination["ledgerCASSequence"],
        "executionMode": execution_mode,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceEnabled": False,
        "releaseCredit": False,
        "adoptionEnabled": False,
        "prohibitions": fence["prohibitions"],
    }
    spec = {**spec_body, "specDigest": digest(spec_body)}
    validate_fence_subset(spec["repositoryPaths"], fence, bootstrap_fence)
    return spec, fence


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--projection", type=Path, required=True)
    parser.add_argument("--facets", type=Path, required=True)
    parser.add_argument("--context", type=Path, required=True)
    parser.add_argument("--bootstrap-fence", type=Path, required=True)
    parser.add_argument("--authority-context", type=Path)
    parser.add_argument("--direct-evidence", type=Path)
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    spec, fence = hydrate(
        read_json(args.projection),
        read_json(args.facets),
        read_json(args.context),
        read_json(args.bootstrap_fence),
        read_json(args.authority_context) if args.authority_context else None,
        read_json(args.direct_evidence) if args.direct_evidence else None,
    )
    if args.output_dir:
        write_json(args.output_dir / "HydratedCardExecutionSpecV2.json", spec)
        write_json(args.output_dir / "PathFenceV1.json", fence)
    print(json.dumps({"result": "PASS", "cardID": spec["cardID"], "specDigest": spec["specDigest"], "fenceDigest": fence["fenceDigest"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
