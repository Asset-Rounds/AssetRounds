#!/usr/bin/env python3
"""Generate C05's deterministic planning and contract-facet projections."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


FOUNDATION = "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md"
BLUEPRINT = "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"
PROJECTION = "docs/design/v23/tooling/V23PlanningProjectionV1.json"
FACETS = "docs/design/v23/tooling/ContractFacetRegistryV1.json"

EXPECTED = {
    "register": "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd",
    "graph": "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae",
    "impact": "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b",
    "selectors": "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2",
    "relations": "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4",
    "facets": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "dependencyDispositions": "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c",
}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def with_digest(value: dict[str, Any], field: str) -> dict[str, Any]:
    result = dict(value)
    result[field] = digest(value)
    return result


def clean(cell: str) -> str:
    return cell.strip().replace("`", "")


def members(cell: str) -> list[str]:
    if clean(cell).upper() in {"NONE", "NO", "N/A", ""}:
        return []
    quoted = re.findall(r"`([^`]+)`", cell)
    if quoted:
        return quoted
    return [part.strip() for part in cell.split(",") if part.strip()]


def table_after(text: str, header: str) -> list[list[str]]:
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == header)
    except StopIteration as exc:
        raise ValueError(f"missing table header: {header}") from exc
    rows: list[list[str]] = []
    for line in lines[start + 2 :]:
        if not line.startswith("|"):
            break
        rows.append([part.strip() for part in line.strip().strip("|").split("|")])
    return rows


def parse_register(text: str) -> list[dict[str, Any]]:
    rows = table_after(
        text,
        "| # | Card | Exact title | Classification | Planning status | Direct execution prerequisites | Lineage |",
    )
    result = []
    for row in rows:
        card = re.search(r"V23-P\d{2}-C\d{2}", row[1])
        if not card:
            raise ValueError(f"invalid register card: {row[1]}")
        result.append(
            {
                "ordinal": int(row[0]),
                "id": card.group(0),
                "title": row[2],
                "classification": clean(row[3]),
                "status": clean(row[4]),
                "directPrerequisites": members(row[5]),
                "lineage": clean(row[6]),
            }
        )
    return result


def parse_impact(text: str) -> list[dict[str, Any]]:
    rows = table_after(
        text,
        "| Card | Aggregate acceptance memberships | Invalidation consumers | Optional capability providers | Conformance subjects |",
    )
    return [
        {
            "id": clean(row[0]),
            "aggregateAcceptanceMemberships": members(row[1]),
            "invalidationConsumers": members(row[2]),
            "optionalCapabilityProviders": members(row[3]),
            "conformanceSubjects": members(row[4]),
        }
        for row in rows
    ]


def parse_selectors(text: str) -> list[dict[str, Any]]:
    rows = table_after(
        text,
        "| Selector | Exact member count | Exact ordered members | Consumers | Predicate | Selector-row SHA-256 |",
    )
    result = []
    for row in rows:
        item = {
            "id": clean(row[0]),
            "members": members(row[2]),
            "consumers": members(row[3]),
            "predicate": row[4],
            "rowDigest": clean(row[5]),
        }
        if len(item["members"]) != int(row[1]):
            raise ValueError(f"selector count mismatch: {item['id']}")
        result.append(item)
    return result


def parse_relations(text: str) -> list[dict[str, str]]:
    rows = table_after(
        text,
        "| Source | Kind | Target | Evidence/contract | Activation predicate | Typed fallback | Invalidated receipt | Authority |",
    )
    return [
        {
            "source": clean(row[0]),
            "kind": clean(row[1]),
            "target": clean(row[2]),
            "evidence": clean(row[3]),
            "activation": clean(row[4]),
            "fallback": clean(row[5]),
            "invalidates": clean(row[6]),
            "authority": row[7],
        }
        for row in rows
    ]


def parse_dispositions(text: str) -> list[dict[str, str]]:
    rows = table_after(
        text,
        "| V21 consumer | V21 provider | V23 consumer | V23 provider | Disposition | Authority |",
    )
    return [
        {
            "predecessorConsumer": clean(row[0]),
            "predecessorProvider": clean(row[1]),
            "currentConsumer": clean(row[2]),
            "currentProvider": clean(row[3]),
            "disposition": clean(row[4]),
            "authority": row[5],
        }
        for row in rows
    ]


def parse_facets(text: str) -> list[dict[str, Any]]:
    rows = table_after(
        text,
        "| Provider facet | Consumer | Exact member selector | Source authority refs |",
    )
    return [
        {
            "source": clean(row[0]),
            "target": clean(row[1]),
            "selector": clean(row[2]),
            "sourceAuthorityRefs": sorted(re.findall(r"`([^`]+)`", row[3])),
            "activation": "HYDRATED_CONTRACT_DIGEST_SELECTED",
            "fallback": "FAIL_CLOSED_UNRESOLVED_OWNER",
        }
        for row in rows
    ]


def parse_ownership(text: str) -> list[dict[str, Any]]:
    rows = table_after(
        text,
        "| Contract family | Declaration owner | Canonical-record writer | Artifact/staging/codec writer | Semantic lifecycle owner | Lifecycle enrollment/compiler owner | Primary consumers |",
    )
    return [
        {
            "familyMembers": [item.strip() for item in clean(row[0]).split(" / ")],
            "declarationOwner": clean(row[1]),
            "canonicalRecordWriter": clean(row[2]),
            "artifactWriter": clean(row[3]),
            "semanticLifecycleOwner": clean(row[4]),
            "lifecycleEnrollmentOwner": clean(row[5]),
            "primaryConsumers": clean(row[6]),
        }
        for row in rows
    ]


def structural_register(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {key: row[key] for key in ("id", "title", "classification", "status", "directPrerequisites", "lineage")}
        for row in rows
    ]


def build(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    foundation = (root / FOUNDATION).read_text(encoding="utf-8")
    blueprint = (root / BLUEPRINT).read_text(encoding="utf-8")
    register = parse_register(foundation)
    impact = parse_impact(foundation)
    selectors = parse_selectors(foundation)
    relations = parse_relations(foundation)
    dispositions = parse_dispositions(foundation)
    facets = parse_facets(blueprint)
    ownership = parse_ownership(blueprint)
    contract_relation_by_pair = {
        (row["source"], row["target"]): row
        for row in relations
        if row["kind"] == "CONTRACT_INPUT_PROVIDER"
    }
    for facet in facets:
        relation = contract_relation_by_pair.get((facet["source"], facet["target"]))
        if relation is None:
            raise ValueError(f"orphan contract facet: {facet['source']} -> {facet['target']}")
        facet["activation"] = relation["activation"]
        facet["fallback"] = relation["fallback"]
    direct_edges = [
        {"source": source, "target": row["id"], "edgeOrdinal": ordinal}
        for row in register
        for ordinal, source in enumerate(row["directPrerequisites"], start=1)
    ]
    graph = [{"id": row["id"], "directPrerequisites": row["directPrerequisites"]} for row in register]
    actual = {
        "register": digest(structural_register(register)),
        "graph": digest(graph),
        "impact": digest(impact),
        "selectors": digest([{k: row[k] for k in ("id", "members", "consumers", "predicate")} for row in selectors]),
        "relations": digest(relations),
        "facets": digest(facets),
        "dependencyDispositions": digest(dispositions),
    }
    mismatches = {key: [EXPECTED[key], value] for key, value in actual.items() if EXPECTED[key] != value}
    if mismatches:
        raise ValueError(f"frozen structural digest mismatch: {json.dumps(mismatches, sort_keys=True)}")
    if (len(register), len(direct_edges), len(impact), len(selectors), len(relations), len(dispositions)) != (146, 230, 146, 7, 1247, 1058):
        raise ValueError("frozen authority count mismatch")
    relation_kinds = sorted(set(row["kind"] for row in relations))
    allowed_non_direct = [
        "AGGREGATE_ACCEPTANCE_MEMBER",
        "CONFORMANCE_SUBJECT",
        "CONTRACT_INPUT_PROVIDER",
        "INVALIDATION_CONSUMER",
        "OPTIONAL_CAPABILITY_PROVIDER",
        "PROVENANCE_REFERENCE",
    ]
    if relation_kinds != allowed_non_direct:
        raise ValueError(f"unknown relation kinds: {relation_kinds}")
    projection = with_digest(
        {
            "schema": "V23PlanningProjectionV1",
            "schemaVersion": 1,
            "sourceFiles": [FOUNDATION, BLUEPRINT],
            "authorityDigests": EXPECTED,
            "programAuthority": {
                "packageDigest": "99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570",
                "overrideID": "V23-OWNER-PARALLEL-IMPLEMENTATION-004",
                "overrideSemanticDigest": "3c1d8779cbc00ed22d26a088bac9f4169e92f630ac3d1f9d5e3fcf43e47bb8cd",
                "overrideReceiptDigest": "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452",
                "frozenS10ReservationDigest": "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a",
                "phase10PollingDuringParallelExecution": False,
                "officialAcceptanceEnabled": False,
                "releaseCredit": False,
            },
            "counts": {
                "cards": len(register),
                "directEdges": len(direct_edges),
                "impactRows": len(impact),
                "selectors": len(selectors),
                "nonDirectRelations": len(relations),
                "dependencyDispositions": len(dispositions),
                "contractFacets": len(facets),
                "nonreleaseSpecialEdges": 10,
            },
            "readinessRule": "ONLY_DIRECT_EXECUTION_PREREQUISITES",
            "cards": register,
            "directEdges": direct_edges,
            "impact": impact,
            "selectors": selectors,
            "relations": relations,
            "dependencyDispositions": dispositions,
        },
        "projectionDigest",
    )
    registry = with_digest(
        {
            "schema": "ContractFacetRegistryV1",
            "schemaVersion": 1,
            "canonicalRegistryDigest": EXPECTED["facets"],
            "relationManifestDigest": EXPECTED["relations"],
            "resolutionRule": "EXACTLY_ONE_SOURCE_OWNER_AND_ALL_MEMBERS_SOURCE_OWNED",
            "facets": facets,
            "ownershipRows": ownership,
        },
        "artifactDigest",
    )
    return projection, registry


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    projection, facets = build(args.root)
    outputs = [(args.root / PROJECTION, projection), (args.root / FACETS, facets)]
    if args.check:
        for path, expected in outputs:
            if json.loads(path.read_text(encoding="utf-8")) != expected:
                raise SystemExit(f"STALE: {path.relative_to(args.root)}")
    else:
        for path, value in outputs:
            write_json(path, value)
    print(json.dumps({"result": "PASS", "projectionDigest": projection["projectionDigest"], "facetArtifactDigest": facets["artifactDigest"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
