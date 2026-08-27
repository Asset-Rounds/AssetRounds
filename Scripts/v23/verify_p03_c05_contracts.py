#!/usr/bin/env python3
"""Hostile static verifier for Card 36's closed content-provenance contracts."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import p03_c05_contracts as contracts


class VerificationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


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
            require(set(node["required"]) <= set(node["properties"]), f"{path}: undeclared required property")
        for key, value in node.items():
            strict_objects(value, f"{path}/{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            strict_objects(value, f"{path}/{index}")


def exact_shape(value: dict[str, Any], properties: set[str], optional: set[str], label: str) -> None:
    require(set(value["properties"]) == properties, f"{label}: Codable property projection differs")
    require(set(value["required"]) == properties - optional, f"{label}: optional/required projection differs")


def verify(root: Path) -> dict[str, Any]:
    require(git(root, "rev-parse", "HEAD") == contracts.APP_BASE_HEAD, "application HEAD differs from hydrated base")
    require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE, "application tree differs from hydrated base")
    expected_authority = {
        "COORDINATION_HEAD": "bbefbcafdb00d83fa4c62c58f16826fc0d006fe0",
        "COORDINATION_TREE": "90d0ad767cc5363f1a6a049ef2bf2eea066ca7c5",
        "COORDINATION_CAS_SEQUENCE": 152,
        "COORDINATION_LEDGER_DIGEST": "8b0778a101e86e82964e977d1617ee190dcf649525615b6c2aa205ac3815217d",
        "CONTEXT_DIGEST": "2d545ecac82e81fc931b0aff1b5469165f4ed09345284f77fff2a212cb6d0bc7",
        "FENCE_DIGEST": "f6ef2e304901fc4ccc103c5c210eee65b26faefb6b96a2cd8ae3a171debab614",
        "PREREQUISITE_DIGEST": "76991e8d7727e00111695225ccda54ea19119f7773616a372a1ba684f343fa5c",
        "TRANSITION_DIGEST": "068def66e4bbe824d620c67d9f3dc3f9b80582af16e6baaaa1ffe41b1d0b7334",
        "HYDRATION_PROJECTION_DIGEST": "0ca503fa85ac55dc729f068355ce364b42cd1f0492211ad069104d128a4d09cc",
    }
    for name, expected in expected_authority.items():
        require(getattr(contracts, name) == expected, f"authority constant differs: {name}")
    require(len(contracts.PATH_FENCE) == 24 and len(set(contracts.PATH_FENCE)) == 24, "path fence is not exact")
    require(contracts.EXISTING_PATHS == [] and contracts.NEW_PATHS == contracts.PATH_FENCE, "fence is not all-new")
    require(len(contracts.SOURCE_PATHS) == 9 and len(contracts.TOOL_PATHS) == 15, "source/tool partition differs")
    for relative in contracts.PATH_FENCE:
        require((root / relative).is_file(), f"missing fenced path: {relative}")
    observed = changed_paths(root)
    require(observed == set(contracts.PATH_FENCE), f"changed path set differs: {sorted(observed ^ set(contracts.PATH_FENCE))}")
    base_existing = [path for path in contracts.PATH_FENCE if subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{contracts.APP_BASE_HEAD}:{path}"], capture_output=True).returncode == 0]
    require(not base_existing, f"all-new fence contains base paths: {base_existing}")
    reservation = load(root / "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json")
    require(reservation["contentDigest"] == contracts.S10_RESERVATION_DIGEST and reservation["reservedPathCount"] == 86, "S10 reservation differs")
    require(not set(contracts.PATH_FENCE) & set(reservation["reservedPaths"]), "Phase 10 reservation overlap")
    require(not any("__pycache__" in path or path.endswith((".pyc", ".pyo")) for path in observed), "Python cache leaked")

    outputs = contracts.all_outputs(root)
    require(set(outputs) == set(contracts.GENERATED_PATHS), "generated output set differs")
    for relative, expected in outputs.items():
        require((root / relative).read_bytes() == expected, f"stale generated artifact: {relative}")

    schema_values: dict[str, dict[str, Any]] = {}
    titles: set[str] = set()
    for relative in contracts.SCHEMA_PATHS:
        value = load(root / relative)
        require(value.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{relative}: dialect differs")
        require(value.get("type") == "object" and value.get("additionalProperties") is False, f"{relative}: root is not closed")
        strict_objects(value, relative)
        titles.add(value["title"])
        schema_values[relative] = value
    require(len(titles) == 6, "schema titles collide")
    exact_shape(schema_values[contracts.SCHEMA_PATHS[0]], {"schemaVersion", "workspaceID", "contentID", "byteLength", "mediaType", "digests", "byteRole", "createdAt"}, set(), "ContentReferenceV1")
    exact_shape(schema_values[contracts.SCHEMA_PATHS[1]], {"schemaVersion", "locatorID", "workspaceID", "contentID", "locatorRevision", "contentDigest", "expectedByteLength"}, set(), "ContentLocatorV1")
    exact_shape(schema_values[contracts.SCHEMA_PATHS[2]], {"schemaVersion", "manifestID", "workspaceID", "manifestRevision", "entries"}, set(), "ContentManifestV1")
    exact_shape(schema_values[contracts.SCHEMA_PATHS[3]], {"schemaVersion", "associationEventID", "workspaceID", "evidenceID", "expectedEvidenceRevision", "resultingEvidenceRevision", "mutationID", "action", "contentID", "target", "previousContentID", "previousTarget", "supersedesAssociationEventID", "actorID", "reason", "effectiveAt"}, {"contentID", "target", "previousContentID", "previousTarget", "supersedesAssociationEventID"}, "EvidenceAssociationV1")
    exact_shape(schema_values[contracts.SCHEMA_PATHS[4]], {"schemaVersion", "provenanceID", "workspaceID", "sources", "derivativeContentID", "derivativeDigest", "transform", "metadataSanitizerID", "metadataSanitizerVersion", "createdAt"}, set(), "ContentDerivativeProvenanceV1")
    exact_shape(schema_values[contracts.SCHEMA_PATHS[5]], {"schemaVersion", "receiptID", "registrySHA256", "fixtureSHA256", "sourceArtifacts", "evidenceIDs", "result", "nativeCompileRan", "hostedDispatchRan", "acceptanceCredit", "releaseCredit", "requiresAcceptedS10_6Reconciliation"}, set(), "ContentEvidenceReceiptV1")
    id_shape = {"type": "string", "pattern": "^[a-z0-9._-]+$", "maxLength": 128}
    for relative, fields in {
        contracts.SCHEMA_PATHS[0]: ["workspaceID", "contentID"], contracts.SCHEMA_PATHS[1]: ["locatorID", "workspaceID", "contentID"],
        contracts.SCHEMA_PATHS[2]: ["manifestID", "workspaceID"], contracts.SCHEMA_PATHS[3]: ["associationEventID", "workspaceID", "evidenceID", "mutationID", "contentID", "previousContentID", "supersedesAssociationEventID", "actorID"],
        contracts.SCHEMA_PATHS[4]: ["provenanceID", "workspaceID", "derivativeContentID", "metadataSanitizerID", "metadataSanitizerVersion"],
    }.items():
        for field in fields:
            require(schema_values[relative]["properties"][field] == id_shape, f"{relative}: ID grammar differs for {field}")
    require(schema_values[contracts.SCHEMA_PATHS[0]]["properties"]["digests"]["properties"]["values"]["uniqueItems"] is True, "digest set uniqueness absent")
    require(schema_values[contracts.SCHEMA_PATHS[0]]["properties"]["digests"]["properties"]["values"]["prefixItems"][0]["properties"]["algorithm"] == {"const": "SHA256"}, "required SHA256/order rule absent")
    require(len(schema_values[contracts.SCHEMA_PATHS[0]]["properties"]["digests"]["properties"]["values"]["allOf"]) == 2, "digest algorithm uniqueness matrix differs")
    require(schema_values[contracts.SCHEMA_PATHS[2]]["properties"]["entries"]["uniqueItems"] is True, "manifest entry uniqueness absent")
    require(schema_values[contracts.SCHEMA_PATHS[4]]["properties"]["sources"]["uniqueItems"] is True, "provenance source uniqueness absent")
    require(len(schema_values[contracts.SCHEMA_PATHS[3]]["allOf"]) == 3, "association action condition matrix differs")
    require(schema_values[contracts.SCHEMA_PATHS[2]]["x-assetrounds-runtimeSemanticConstraints"] == ["ENTRIES_SORTED_BY_CONTENT_ID", "CONTENT_ID_UNIQUE"], "manifest runtime semantics declaration differs")
    require(len(schema_values[contracts.SCHEMA_PATHS[3]]["x-assetrounds-runtimeSemanticConstraints"]) == 5, "association runtime semantics declaration differs")
    require(len(schema_values[contracts.SCHEMA_PATHS[4]]["x-assetrounds-runtimeSemanticConstraints"]) == 5, "provenance runtime semantics declaration differs")
    target_kinds = schema_values[contracts.SCHEMA_PATHS[3]]["properties"]["target"]["properties"]["kind"]["enum"]
    require(target_kinds == ["INSPECTION_NODE", "INSPECTION_RESPONSE", "FINDING", "CORRECTIVE_WORK", "ASSET", "WORK_RECORD"], "evidence target kind projection differs")
    require(set(schema_values[contracts.SCHEMA_PATHS[3]]["properties"]["target"]["required"]) == {"workspaceID", "kind", "targetID", "targetRevision"}, "workspace-scoped evidence target shape differs")
    transform_matrix = schema_values[contracts.SCHEMA_PATHS[4]]["properties"]["transform"]["oneOf"]
    require(len(transform_matrix) == 4 and all(len(row.get("not", {}).get("anyOf", [])) == 3 for row in transform_matrix), "closed derivative transform matrix differs")

    fixture_path = root / contracts.SOURCE_PATHS[-1]
    fixture = load(fixture_path)
    require(fixture_path.read_bytes() == contracts.canonical(fixture) + b"\n", "fixture is not canonical compact sorted JSON plus LF")
    require(fixture.get("schema") == "V21P03C05ContentReferenceProvenanceCorpusV1" and fixture.get("schemaVersion") == 1 and fixture.get("testOnly") is True, "fixture identity differs")
    fixture_text = fixture_path.read_text(encoding="utf-8")
    for marker in ["DECLARATION_ONLY", "KERNEL_MEDIA_V1", "DORMANT_REVERT_ALLOWED", "FAIL_CLOSED", "UNKNOWN_DIGEST_ALGORITHM", "ORPHAN_ASSOCIATION", "PROVENANCE_TAMPER"]:
        require(marker in fixture_text, f"fixture semantic marker missing: {marker}")

    methods = contracts.test_methods(root)
    source_texts = {path: (root / path).read_text(encoding="utf-8") for path in contracts.SOURCE_PATHS}
    all_source = "\n".join(source_texts.values())
    for marker in ["ContentReferenceV1", "ContentDigestSetV1", "ContentByteRoleV1", "validateImmutableIdentity"]:
        require(marker in source_texts[contracts.SOURCE_PATHS[0]], f"reference marker missing: {marker}")
    for marker in ["ContentLocatorV1", "ContentManifestV1", "ContentManifestCanonicalCodecV1", "requiredForOpen"]:
        require(marker in source_texts[contracts.SOURCE_PATHS[1]], f"locator/manifest marker missing: {marker}")
    for marker in ["ContentOriginalProvenanceV1", "ContentDerivativeProvenanceV1", "ContentProvenanceGraphV1", "IMMUTABLE_ORIGINAL", "SANITIZED", "THUMBNAIL", "ANNOTATION", "SEQUENCE"]:
        require(marker in source_texts[contracts.SOURCE_PATHS[2]], f"provenance marker missing: {marker}")
    for marker in ["EvidenceAssociationV1", "ContentEvidenceGraphV1", "validateOrphanFree", "ASSIGNED", "REASSIGNED", "REMOVED"]:
        require(marker in source_texts[contracts.SOURCE_PATHS[3]], f"association marker missing: {marker}")
    for marker in ["LocalContentStoreV1", "ContentLocatorV1", "wrongWorkspace", "staleReference"]:
        require(marker in source_texts[contracts.SOURCE_PATHS[4]], f"local store marker missing: {marker}")
    for marker in ["ContentIntegrityV1", "digestMismatch", "byteLengthMismatch"]:
        require(marker in source_texts[contracts.SOURCE_PATHS[5]], f"integrity marker missing: {marker}")
    for marker in ["ContentContractRegistryV1", "KERNEL_MEDIA_V1", "DORMANT_REVERT_ALLOWED"]:
        require(marker in source_texts[contracts.SOURCE_PATHS[6]], f"registry marker missing: {marker}")
    test_source = source_texts[contracts.SOURCE_PATHS[7]]
    for marker in ["wrongWorkspace", "unknownAlgorithm", "orphanEvidence", "digestMismatch", "byteLengthMismatch", "immutableOriginal"]:
        require(marker in all_source, f"failure marker missing: {marker}")
    for marker in ["duplicateAlgorithm", "explicitNull", "mixedTransform", "openReceipt", "forgedReceipt", "partialEffect"]:
        require(marker in test_source, f"hostile strictness assertion missing: {marker}")
    for family in ["G01", "A01", "H01", "I01", "R01"]:
        require(sum(family in method for method in methods) == 1, f"test family differs: {family}")
    for marker in ["C36", "CONTENT_PROMOTED_UNBOUND", "pre-promotion", "EvidenceID", "draftID", "stageID", "commitPlanSHA256", "mutationID", "contentDigest"]:
        require(marker.lower() in all_source.lower(), f"C36 reservation exclusion marker missing: {marker}")

    forbidden = [
        r"provider(?:Path|Name|URL)", r"absolutePath", r"signedURL", r"bookmark", r"uploadState", r"TransferJob", r"multipart",
        r"networkRetry", r"URLSession", r"CloudKit", r"Firebase", r"\baccount(?:ID)?\b", r"authentication", r"tenancy", r"telemetry",
        r"Remote(?:Content|Transfer|Sync)(?:Store|Service|Client|Job)", r"Backend(?:Service|Client)", r"ServerEndpoint", r"EndpointURL",
        r"Outbox(?:Entry|Store)", r"Inbox(?:Entry|Store)", r"serviceCredential", r"tenantID", r"objectKey", r"providerSDK",
        r"TestFlight", r"AppStore", r"acceptanceCredit\s*[:=]\s*true", r"releaseCredit\s*[:=]\s*true",
    ]
    for pattern in forbidden:
        require(re.search(pattern, all_source, re.I) is None, f"forbidden source token/claim: {pattern}")

    for relative in contracts.CONTRACT_PATHS[:-1]:
        value = load(root / relative)
        require(value["cardID"] == contracts.CARD and value["schemaVersion"] == 1, f"{relative}: identity differs")
        unsigned = dict(value)
        recorded = unsigned.pop("artifactDigest")
        require(recorded == digest(contracts.pretty(unsigned)), f"{relative}: artifact seal differs")
        require(value["persistentChangeMode"] == "DECLARATION_ONLY" and value["persistentContractSchema"] == "KERNEL_MEDIA_V1", f"{relative}: lifecycle differs")
        for flag in ["nativeCompileRan", "hostedDispatchRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit", "phase10PollingDuringParallelExecution", "nativeOrHostedEvidenceClaimed", "acceptanceOrReleaseClaimed"]:
            require(value[flag] is False, f"{relative}: forbidden claim {flag}")
        require(value["requiresAcceptedS10_6Reconciliation"] is True, f"{relative}: S10 reconciliation flag differs")
        require(value["authority"] == contracts.authority(), f"{relative}: authority differs")
    evidence = load(root / contracts.CONTRACT_PATHS[-1])
    expected_receipt_keys = set(schema_values[contracts.SCHEMA_PATHS[5]]["properties"])
    require(set(evidence) == expected_receipt_keys, "evidence receipt shape differs")
    require(evidence["schemaVersion"] == 1 and evidence["receiptID"] == "v23-p03-c05-static-receipt", "evidence receipt identity differs")
    require(evidence["evidenceIDs"] == contracts.EVIDENCE_IDS and evidence["result"] == "PASS", "evidence families/result differ")
    expected_sources = [{"path": path, "sha256": digest((root / path).read_bytes())} for path in contracts.SOURCE_PATHS]
    require(evidence["sourceArtifacts"] == expected_sources, "evidence receipt source closure differs")
    require(evidence["fixtureSHA256"] == digest(fixture_path.read_bytes()), "evidence receipt fixture digest differs")
    canonical_registry = contracts.canonical({
        "declaredContracts": ["ContentReferenceV1", "ContentLocatorV1", "ContentManifestV1", "EvidenceAssociationV1", "ContentDerivativeProvenanceV1", "LocalContentStoreV1"],
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED", "persistentContractSchema": "KERNEL_MEDIA_V1", "schemaVersion": 1,
    })
    require(evidence["registrySHA256"] == digest(canonical_registry), "evidence receipt registry digest differs")
    for flag in ["nativeCompileRan", "hostedDispatchRan", "acceptanceCredit", "releaseCredit"]:
        require(evidence[flag] is False, f"evidence receipt forbidden claim: {flag}")
    require(evidence["requiresAcceptedS10_6Reconciliation"] is True, "evidence receipt S10 reconciliation flag differs")

    manifest_path = root / contracts.MANIFEST
    manifest = load(manifest_path)
    unsigned_manifest = dict(manifest)
    recorded_manifest = unsigned_manifest.pop("artifactDigest")
    require(recorded_manifest == digest(contracts.pretty(unsigned_manifest)), "manifest seal differs")
    require(manifest["pathFence"] == contracts.PATH_FENCE and manifest["pathFenceCount"] == 24, "manifest fence differs")
    require(manifest["existingPaths"] == [] and manifest["newPaths"] == contracts.PATH_FENCE, "manifest all-new partition differs")
    require(manifest["artifactCount"] == 23 and manifest["pendingArtifactCount"] == 0 and len(manifest["artifacts"]) == 23, "manifest closure differs")
    rows = manifest["artifacts"]
    require(len({row["path"] for row in rows}) == len(rows), "manifest duplicate dependency")
    require({row["path"] for row in rows} == set(contracts.MANIFEST_INPUT_PATHS), "manifest missing/extra dependency")
    for row in rows:
        raw = (root / row["path"]).read_bytes()
        require(row["sha256"] == digest(raw) and row["bytes"] == len(raw), f"manifest stale/tampered dependency: {row['path']}")
    require(manifest["artifactSetDigest"] == digest(contracts.canonical(rows)), "manifest artifact-set seal differs")
    generated_text = "\n".join((root / path).read_text(encoding="utf-8") for path in contracts.GENERATED_PATHS)
    for pattern in forbidden:
        require(re.search(pattern, generated_text, re.I) is None, f"forbidden generated token/claim: {pattern}")

    return {
        "result": "PASS", "cardID": contracts.CARD, "pathFenceCount": 24, "changedPathCount": 24,
        "sourcePathCount": 9, "strictSchemaCount": 6, "contractDocumentCount": 5,
        "namedStaticTestCount": 5, "fixtureSHA256": digest(fixture_path.read_bytes()),
        "manifestSHA256": digest(manifest_path.read_bytes()), "nativeCompileRan": False,
        "hostedDispatchRan": False, "acceptanceCredit": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"V23-P03-C05 verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
