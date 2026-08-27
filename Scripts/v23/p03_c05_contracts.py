#!/usr/bin/env python3
"""Deterministic Card 36 content-reference and provenance contract projection."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

CARD = "V23-P03-C05"
APP_BASE_HEAD = "db25f74734b233b31ef5c08a4af4c5c85dbda342"
APP_BASE_TREE = "62a98c7e63f44fad33c1ad55d10acc8828553308"
COORDINATION_HEAD = "bbefbcafdb00d83fa4c62c58f16826fc0d006fe0"
COORDINATION_TREE = "90d0ad767cc5363f1a6a049ef2bf2eea066ca7c5"
COORDINATION_CAS_SEQUENCE = 152
COORDINATION_LEDGER_DIGEST = "8b0778a101e86e82964e977d1617ee190dcf649525615b6c2aa205ac3815217d"
CONTEXT_DIGEST = "2d545ecac82e81fc931b0aff1b5469165f4ed09345284f77fff2a212cb6d0bc7"
FENCE_DIGEST = "f6ef2e304901fc4ccc103c5c210eee65b26faefb6b96a2cd8ae3a171debab614"
PREREQUISITE_DIGEST = "76991e8d7727e00111695225ccda54ea19119f7773616a372a1ba684f343fa5c"
TRANSITION_DIGEST = "068def66e4bbe824d620c67d9f3dc3f9b80582af16e6baaaa1ffe41b1d0b7334"
HYDRATION_PROJECTION_DIGEST = "0ca503fa85ac55dc729f068355ce364b42cd1f0492211ad069104d128a4d09cc"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
    "FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
    "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Content/V21P03C05ContentReferenceProvenanceCorpusV1.json",
]
CONTRACT_SCRIPT = "Scripts/v23/p03_c05_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p03_c05_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p03_c05_contracts.py"
SCHEMA_PATHS = [
    "Scripts/v23/content-reference.schema.json",
    "Scripts/v23/content-locator.schema.json",
    "Scripts/v23/content-manifest.schema.json",
    "Scripts/v23/evidence-association.schema.json",
    "Scripts/v23/content-derivative-provenance.schema.json",
    "Scripts/v23/content-evidence-receipt.schema.json",
]
CONTRACT_PATHS = [
    "docs/design/v23/tooling/V23P03C05ContentReferenceContractV1.json",
    "docs/design/v23/tooling/V23P03C05ContentLocatorManifestContractV1.json",
    "docs/design/v23/tooling/V23P03C05EvidenceAssociationContractV1.json",
    "docs/design/v23/tooling/V23P03C05DerivativeProvenanceContractV1.json",
    "docs/design/v23/tooling/V23P03C05ContentEvidenceReceiptV1.json",
]
MANIFEST = "docs/design/v23/tooling/V23-P03-C05-tooling-manifest.json"
TOOL_PATHS = [CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT] + SCHEMA_PATHS + CONTRACT_PATHS + [MANIFEST]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = SCHEMA_PATHS + CONTRACT_PATHS + [MANIFEST]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
EXISTING_PATHS: list[str] = []
NEW_PATHS = PATH_FENCE
EVIDENCE_IDS = [f"{CARD}-{family}" for family in ["G01", "A01", "H01", "I01", "R01"]]


class ContractError(RuntimeError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(result))
    return result


def read(root: Path, relative: str) -> bytes:
    path = root / relative
    if not path.is_file():
        raise ContractError(f"missing source: {relative}")
    return path.read_bytes()


def text(root: Path, relative: str) -> str:
    return read(root, relative).decode("utf-8")


def fixture(root: Path) -> dict[str, Any]:
    raw = read(root, SOURCE_PATHS[-1])
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid fixture: {error}") from error
    if raw != canonical(value) + b"\n":
        raise ContractError("fixture must be canonical compact sorted JSON plus LF")
    return value


def test_methods(root: Path) -> list[str]:
    methods = sorted(set(re.findall(r"func (testV9_15[A-Za-z0-9_]+)\s*\(", text(root, SOURCE_PATHS[7]))))
    if len(methods) != 5:
        raise ContractError(f"expected exactly five V9_15 tests, found {methods}")
    families = ["G01", "A01", "H01", "I01", "R01"]
    if any(sum(family in method for method in methods) != 1 for family in families):
        raise ContractError("V9_15 test family binding differs")
    return [next(method for method in methods if family in method) for family in families]


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
    }


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False,
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseReady": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def common(schema_name: str) -> dict[str, Any]:
    return {
        "schema": schema_name,
        "schemaVersion": 1,
        "cardID": CARD,
        "persistentChangeMode": "DECLARATION_ONLY",
        "persistentContractSchema": "KERNEL_MEDIA_V1",
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
        "authority": authority(),
        **flags(),
    }


def source_projection(root: Path) -> dict[str, Any]:
    return {path: sha(read(root, path)) for path in SOURCE_PATHS}


def obj(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "properties": properties, "required": list(properties) if required is None else required}


def identifier() -> dict[str, Any]:
    return {"type": "string", "pattern": "^[a-z0-9._-]+$", "maxLength": 128}


def instant() -> dict[str, Any]:
    return {"type": "string", "format": "date-time"}


def integer() -> dict[str, Any]:
    return {"type": "integer", "minimum": 0}


def digest_schema() -> dict[str, Any]:
    value = obj({
        "algorithm": {"type": "string", "enum": ["SHA256", "SHA512"]},
        "hexadecimalValue": {"type": "string", "pattern": "^[0-9a-f]+$", "minLength": 64, "maxLength": 128},
    })
    value["allOf"] = [
        {"if": {"properties": {"algorithm": {"const": "SHA256"}}, "required": ["algorithm"]}, "then": {"properties": {"hexadecimalValue": {"minLength": 64, "maxLength": 64}}}},
        {"if": {"properties": {"algorithm": {"const": "SHA512"}}, "required": ["algorithm"]}, "then": {"properties": {"hexadecimalValue": {"minLength": 128, "maxLength": 128}}}},
    ]
    return value


def schema(title: str, body: dict[str, Any]) -> dict[str, Any]:
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": f"https://assetrounds.invalid/v23/{CARD.lower()}/{title}.schema.json", "title": title, **body}


def schemas() -> dict[str, dict[str, Any]]:
    first_digest = digest_schema()
    first_digest["properties"]["algorithm"] = {"const": "SHA256"}
    digest_values = {
        "type": "array",
        "items": digest_schema(),
        "prefixItems": [first_digest],
        "minItems": 1,
        "maxItems": 2,
        "uniqueItems": True,
        "allOf": [
            {"not": {"contains": {"properties": {"algorithm": {"const": algorithm}}, "required": ["algorithm"]}, "minContains": 2}}
            for algorithm in ["SHA256", "SHA512"]
        ],
    }
    digest_set = obj({"values": digest_values})
    media_type = {"type": "string", "pattern": "^[a-z0-9.+-]+/[a-z0-9.+-]+$", "maxLength": 127}
    reference = obj({
        "schemaVersion": {"const": 1}, "workspaceID": identifier(), "contentID": identifier(),
        "byteLength": integer(), "mediaType": media_type,
        "digests": digest_set, "byteRole": {"type": "string", "enum": ["IMMUTABLE_ORIGINAL", "DERIVATIVE"]}, "createdAt": instant(),
    })
    locator = obj({
        "schemaVersion": {"const": 1}, "locatorID": identifier(), "workspaceID": identifier(), "contentID": identifier(),
        "locatorRevision": integer(), "contentDigest": digest_schema(), "expectedByteLength": integer(),
    })
    entry = obj({"contentID": identifier(), "expectedByteLength": integer(), "mediaType": media_type, "digest": digest_schema(), "expectedLocatorRevision": integer(), "requiredForOpen": {"type": "boolean"}})
    manifest = obj({"schemaVersion": {"const": 1}, "manifestID": identifier(), "workspaceID": identifier(), "manifestRevision": integer(), "entries": {"type": "array", "items": entry, "minItems": 1, "maxItems": 256, "uniqueItems": True}})
    target = obj({"workspaceID": identifier(), "kind": {"type": "string", "enum": ["INSPECTION_NODE", "INSPECTION_RESPONSE", "FINDING", "CORRECTIVE_WORK", "ASSET", "WORK_RECORD"]}, "targetID": identifier(), "targetRevision": integer()})
    association = obj({"schemaVersion": {"const": 1}, "associationEventID": identifier(), "workspaceID": identifier(), "evidenceID": identifier(), "expectedEvidenceRevision": integer(), "resultingEvidenceRevision": integer(), "mutationID": identifier(), "action": {"type": "string", "enum": ["ASSIGNED", "REASSIGNED", "REMOVED"]}, "contentID": identifier(), "target": target, "previousContentID": identifier(), "previousTarget": target, "supersedesAssociationEventID": identifier(), "actorID": identifier(), "reason": {"type": "string", "pattern": ".*\\S.*", "minLength": 1, "maxLength": 1024}, "effectiveAt": instant()}, required=["schemaVersion", "associationEventID", "workspaceID", "evidenceID", "expectedEvidenceRevision", "resultingEvidenceRevision", "mutationID", "action", "actorID", "reason", "effectiveAt"])
    association["allOf"] = [
        {"if": {"properties": {"action": {"const": "ASSIGNED"}}, "required": ["action"]}, "then": {"required": ["contentID", "target"], "not": {"anyOf": [{"required": ["previousContentID"]}, {"required": ["previousTarget"]}, {"required": ["supersedesAssociationEventID"]}]}}},
        {"if": {"properties": {"action": {"const": "REASSIGNED"}}, "required": ["action"]}, "then": {"required": ["contentID", "target", "previousContentID", "previousTarget", "supersedesAssociationEventID"]}},
        {"if": {"properties": {"action": {"const": "REMOVED"}}, "required": ["action"]}, "then": {"required": ["previousContentID", "previousTarget", "supersedesAssociationEventID"], "not": {"anyOf": [{"required": ["contentID"]}, {"required": ["target"]}]}}},
    ]
    source_binding = obj({"contentID": identifier(), "digest": digest_schema()})
    transform = obj({
        "kind": {"type": "string", "enum": ["SANITIZED", "THUMBNAIL", "ANNOTATION", "SEQUENCE"]},
        "sanitized": obj({"sanitizerID": identifier(), "sanitizerVersion": identifier()}),
        "thumbnail": obj({"rendererID": identifier(), "rendererVersion": identifier(), "pixelWidth": {"type": "integer", "minimum": 1, "maximum": 16384}, "pixelHeight": {"type": "integer", "minimum": 1, "maximum": 16384}}),
        "annotation": obj({"rendererID": identifier(), "rendererVersion": identifier(), "annotationManifestSHA256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}}),
        "sequence": obj({"assemblerID": identifier(), "assemblerVersion": identifier(), "orderedSourceCount": {"type": "integer", "minimum": 1, "maximum": 32}}),
    }, required=["kind"])
    transform_payloads = {
        "SANITIZED": "sanitized",
        "THUMBNAIL": "thumbnail",
        "ANNOTATION": "annotation",
        "SEQUENCE": "sequence",
    }
    transform["oneOf"] = [
        {
            "properties": {"kind": {"const": kind}},
            "required": [payload],
            "not": {"anyOf": [{"required": [other]} for other in transform_payloads.values() if other != payload]},
        }
        for kind, payload in transform_payloads.items()
    ]
    provenance = obj({"schemaVersion": {"const": 1}, "provenanceID": identifier(), "workspaceID": identifier(), "sources": {"type": "array", "items": source_binding, "minItems": 1, "maxItems": 32, "uniqueItems": True}, "derivativeContentID": identifier(), "derivativeDigest": digest_schema(), "transform": transform, "metadataSanitizerID": identifier(), "metadataSanitizerVersion": identifier(), "createdAt": instant()})
    manifest["x-assetrounds-runtimeSemanticConstraints"] = ["ENTRIES_SORTED_BY_CONTENT_ID", "CONTENT_ID_UNIQUE"]
    association["x-assetrounds-runtimeSemanticConstraints"] = ["RESULTING_REVISION_EQUALS_EXPECTED_PLUS_ONE", "ACTION_REVISION_MATRIX", "REASSIGNMENT_CHANGES_BINDING", "TARGET_WORKSPACE_EQUALS_ASSOCIATION_WORKSPACE", "TEXT_UTF8_BOUNDS"]
    provenance["x-assetrounds-runtimeSemanticConstraints"] = ["SOURCE_CONTENT_ID_UNIQUE", "SOURCE_NOT_DERIVATIVE_SELF", "NON_SEQUENCE_HAS_ONE_SOURCE", "SEQUENCE_COUNT_EQUALS_SOURCE_COUNT", "INSTANT_UTF8_BOUNDS"]
    source_artifact = obj({"path": {"type": "string", "minLength": 1, "maxLength": 512}, "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}})
    receipt = obj({"schemaVersion": {"const": 1}, "receiptID": identifier(), "registrySHA256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}, "fixtureSHA256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}, "sourceArtifacts": {"type": "array", "items": source_artifact, "minItems": 9, "maxItems": 9, "uniqueItems": True}, "evidenceIDs": {"type": "array", "items": {"type": "string", "pattern": "^V23-P03-C05-(G01|A01|H01|I01|R01)$"}, "minItems": 5, "maxItems": 5, "uniqueItems": True}, "result": {"const": "PASS"}, "nativeCompileRan": {"const": False}, "hostedDispatchRan": {"const": False}, "acceptanceCredit": {"const": False}, "releaseCredit": {"const": False}, "requiresAcceptedS10_6Reconciliation": {"const": True}})
    return {path: value for path, value in zip(SCHEMA_PATHS, [schema("ContentReferenceV1", reference), schema("ContentLocatorV1", locator), schema("ContentManifestV1", manifest), schema("EvidenceAssociationV1", association), schema("ContentDerivativeProvenanceV1", provenance), schema("ContentEvidenceReceiptV1", receipt)])}


def documents(root: Path, methods: list[str], source: dict[str, str], fixture_value: dict[str, Any]) -> dict[str, dict[str, Any]]:
    shared = {"sourceSHA256": source, "fixtureSHA256": sha(read(root, SOURCE_PATHS[-1])), "testMethods": methods}
    contract_values = [
        {**common("V23P03C05ContentReferenceContractV1"), **shared, "identityFields": ["workspaceID", "contentID"], "locationIndependent": True, "algorithmScopedDigests": True, "immutableOriginal": True, "unknownAlgorithmsFailClosed": True},
        {**common("V23P03C05ContentLocatorManifestContractV1"), **shared, "locatorReplaceable": True, "locatorResolvedOnlyByOwnedStore": True, "manifestCanonicalCodec": "ContentManifestCanonicalCodecV1", "manifestEntryLimit": 256, "networkTransferState": False},
        {**common("V23P03C05EvidenceAssociationContractV1"), **shared, "stableEvidenceID": True, "appendOnlyAssociationHistory": True, "workspaceScoped": True, "orphanPrevention": True, "actions": fixture_value.get("associationActions", [])},
        {**common("V23P03C05DerivativeProvenanceContractV1"), **shared, "originalsImmutable": True, "derivativeKinds": fixture_value.get("derivativeKinds", []), "sourceDigestRequired": True, "derivativeDigestRequired": True, "transformBindingRequired": True, "sanitizerVersionBoundWhenApplicable": True},
    ]
    registry = {
        "declaredContracts": [
            "ContentReferenceV1", "ContentLocatorV1", "ContentManifestV1",
            "EvidenceAssociationV1", "ContentDerivativeProvenanceV1", "LocalContentStoreV1",
        ],
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
        "persistentContractSchema": "KERNEL_MEDIA_V1",
        "schemaVersion": 1,
    }
    receipt = {
        "schemaVersion": 1,
        "receiptID": "v23-p03-c05-static-receipt",
        "registrySHA256": sha(canonical(registry)),
        "fixtureSHA256": sha(read(root, SOURCE_PATHS[-1])),
        "sourceArtifacts": [{"path": path, "sha256": source[path]} for path in SOURCE_PATHS],
        "evidenceIDs": EVIDENCE_IDS,
        "result": "PASS",
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    result = {path: seal(value) for path, value in zip(CONTRACT_PATHS[:-1], contract_values)}
    result[CONTRACT_PATHS[-1]] = receipt
    return result


def manifest(root: Path, generated: dict[str, bytes], source: dict[str, str], methods: list[str]) -> dict[str, Any]:
    artifacts = []
    for path in MANIFEST_INPUT_PATHS:
        data = generated[path] if path in generated else read(root, path)
        artifacts.append({"path": path, "sha256": sha(data), "bytes": len(data), "role": "source" if path in SOURCE_PATHS else "tooling"})
    value = {
        **common("V23P03C05ToolingManifestV1"),
        "pathFence": PATH_FENCE, "pathFenceCount": 24, "existingPaths": [], "newPaths": PATH_FENCE,
        "sourcePathCount": 9, "toolPathCount": 15, "generatedArtifactCount": 12,
        "artifactCount": 23, "pendingArtifactCount": 0, "artifacts": artifacts,
        "sourceSHA256": source, "testMethods": methods, "evidenceIDs": EVIDENCE_IDS,
    }
    value["artifactSetDigest"] = sha(canonical(artifacts))
    return seal(value)


def all_outputs(root: Path) -> dict[str, bytes]:
    if len(PATH_FENCE) != 24 or len(set(PATH_FENCE)) != 24 or len(SOURCE_PATHS) != 9 or len(TOOL_PATHS) != 15:
        raise ContractError("fence cardinality differs")
    source = source_projection(root)
    methods = test_methods(root)
    fixture_value = fixture(root)
    generated: dict[str, bytes] = {path: pretty(value) for path, value in schemas().items()}
    generated.update({path: pretty(value) for path, value in documents(root, methods, source, fixture_value).items()})
    generated[MANIFEST] = pretty(manifest(root, generated, source, methods))
    return generated
