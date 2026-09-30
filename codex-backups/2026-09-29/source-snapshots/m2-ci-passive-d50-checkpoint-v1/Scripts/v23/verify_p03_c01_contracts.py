#!/usr/bin/env python3
"""Hostile independent verifier for Card32 package-registry evidence.

The verifier intentionally re-derives the fence, source declarations, package
identity, selectors, and absence rules from the live inputs.  It does not call
the generator to decide whether generated output is correct.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import p03_c01_contracts as c


class VerificationError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def read(root: Path, relative: str) -> bytes:
    path = root / relative
    require(path.is_file(), f"missing fenced path: {relative}")
    return path.read_bytes()


def text(root: Path, relative: str) -> str:
    try:
        return read(root, relative).decode("utf-8")
    except UnicodeDecodeError as error:
        raise VerificationError(f"{relative}: non-UTF-8 input") from error


def load(root: Path, relative: str) -> dict[str, Any]:
    raw = read(root, relative)
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise VerificationError(f"{relative}: invalid JSON: {error}") from error
    require(isinstance(value, dict), f"{relative}: JSON root is not an object")
    require(raw == c.pretty(value), f"{relative}: JSON is not canonical pretty form")
    return value


def load_input_json(root: Path, relative: str) -> dict[str, Any]:
    """Parse a fenced source/fixture JSON file without imposing artifact formatting."""
    raw = read(root, relative)
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise VerificationError(f"{relative}: invalid JSON: {error}") from error
    require(isinstance(value, dict), f"{relative}: JSON root is not an object")
    return value


def verify_seal(value: dict[str, Any], label: str) -> None:
    observed = value.get("artifactDigest")
    require(
        isinstance(observed, str) and re.fullmatch(r"[0-9a-f]{64}", observed) is not None,
        f"{label}: malformed artifactDigest",
    )
    body = dict(value)
    body.pop("artifactDigest")
    require(observed == c.sha(c.pretty(body)), f"{label}: artifactDigest mismatch")


def validate_instance(value: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        expected = schema["const"]
        require(type(value) is type(expected) and value == expected, f"{path}: const mismatch")
    if "enum" in schema:
        require(value in schema["enum"], f"{path}: enum mismatch")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(value, dict), f"{path}: object expected")
        props = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            require(set(value).issubset(props), f"{path}: additional property")
        required = schema.get("required", [])
        require(set(required).issubset(value), f"{path}: required property missing")
        for key, child in props.items():
            if key in value:
                validate_instance(value[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(value, list), f"{path}: array expected")
        require(schema.get("minItems", 0) <= len(value), f"{path}: too few array items")
        require(len(value) <= schema.get("maxItems", len(value)), f"{path}: too many array items")
        prefix = schema.get("prefixItems", [])
        require(len(value) >= len(prefix), f"{path}: prefix item missing")
        for index, child in enumerate(prefix):
            validate_instance(value[index], child, f"{path}[{index}]")
        if schema.get("items") is False:
            require(len(value) == len(prefix), f"{path}: open array")
        elif isinstance(schema.get("items"), dict):
            for index in range(len(prefix), len(value)):
                validate_instance(value[index], schema["items"], f"{path}[{index}]")
    elif kind == "string":
        require(isinstance(value, str), f"{path}: string expected")
        if "pattern" in schema:
            require(re.fullmatch(schema["pattern"], value) is not None, f"{path}: pattern mismatch")
    elif kind == "integer":
        require(isinstance(value, int) and not isinstance(value, bool), f"{path}: integer expected")
    elif kind == "boolean":
        require(isinstance(value, bool), f"{path}: boolean expected")
    elif kind == "null":
        require(value is None, f"{path}: null expected")
    elif kind is not None:
        raise VerificationError(f"{path}: unsupported schema type {kind!r}")


def verify_strict_schema(schema: dict[str, Any], label: str) -> None:
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{label}: wrong draft")
    require(isinstance(schema.get("$id"), str) and schema["$id"].startswith("https://assetrounds.invalid/v23/"), f"{label}: wrong $id")

    def walk(node: Any, path: str) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object":
            props = node.get("properties", {})
            require(node.get("additionalProperties") is False, f"{label}{path}: object is open")
            require(set(node.get("required", [])) == set(props), f"{label}{path}: required/property closure differs")
            for key, child in props.items():
                walk(child, f"{path}.{key}")
        elif node.get("type") == "array":
            require(node.get("items") is False, f"{label}{path}: array is open")
            prefix = node.get("prefixItems", [])
            require(node.get("minItems") == node.get("maxItems") == len(prefix), f"{label}{path}: array is not exact")
            for index, child in enumerate(prefix):
                walk(child, f"{path}[{index}]")

    walk(schema, "$")


def static_enum_values(source: str, enum_name: str) -> list[str]:
    match = re.search(rf"\benum\s+{re.escape(enum_name)}\b.*?\{{(.*?)\n\}}", source, re.S)
    require(match is not None, f"missing enum {enum_name}")
    values = re.findall(r"\bcase\s+[A-Za-z0-9_]+\s*=\s*\"([^\"]+)\"", match.group(1))
    require(values and len(values) == len(set(values)), f"invalid enum {enum_name}")
    return values


def static_string(source: str, name: str) -> str:
    match = re.search(rf"\bstatic\s+let\s+{re.escape(name)}\s*=\s*\"([^\"]+)\"", source)
    require(match is not None, f"missing static string {name}")
    return match.group(1)


def verify_fence(manifest: dict[str, Any], root: Path) -> None:
    require(c.PATH_FENCE == c.SOURCE_PATHS + c.TOOL_PATHS, "tooling fence construction differs")
    require(len(c.PATH_FENCE) == 24, "Card32 fence is not 24 paths")
    require(len(c.EXISTING_PATHS) == 3 and len(c.NEW_PATHS) == 21, "Card32 existing/new partition differs")
    require(len(set(c.PATH_FENCE)) == 24, "Card32 fence contains duplicate paths")
    require(manifest.get("pathFence") == c.PATH_FENCE, "manifest fence differs")
    require(manifest.get("pathFenceCount") == 24, "manifest fence count differs")
    require(manifest.get("existingPaths") == c.EXISTING_PATHS, "manifest existing paths differ")
    require(manifest.get("sourcePaths") == c.SOURCE_PATHS, "manifest source paths differ")
    require(manifest.get("toolingPaths") == c.TOOL_PATHS, "manifest tooling paths differ")
    require(manifest.get("sourcePathCount") == 9 and manifest.get("toolingPathCount") == 15, "manifest path counts differ")
    require(manifest.get("generatedPaths") == c.GENERATED_PATHS, "manifest generated paths differ")
    require(manifest.get("newPaths") == c.NEW_PATHS, "manifest new paths differ")
    fence_proof = manifest.get("fenceProof")
    require(isinstance(fence_proof, dict), "manifest fence proof missing")
    require(fence_proof.get("baseHead") == c.APP_BASE_HEAD and fence_proof.get("baseTree") == c.APP_BASE_TREE, "manifest base differs")
    require(fence_proof.get("pathFenceDigest") == c.FENCE_DIGEST, "manifest fence digest differs")
    require(fence_proof.get("allowedPathCount") == 24 and fence_proof.get("existingPathCount") == 3 and fence_proof.get("newPathCount") == 21, "manifest fence proof counts differ")
    require(fence_proof.get("priorFenceOverlapCount") == 0 and fence_proof.get("authorizedPriorFenceOverlapCount") == 0, "prior fence overlap is not zero")
    require(fence_proof.get("activeS10Overlap") is False and fence_proof.get("activeS10ReservationDigest") == c.S10_RESERVATION_DIGEST, "S10 reservation proof differs")
    rows = manifest.get("artifacts")
    require(isinstance(rows, list) and len(rows) == 23, "manifest must seal 23 non-manifest inputs")
    require([row.get("path") for row in rows] == c.MANIFEST_INPUT_PATHS, "manifest artifact order differs")
    for row in rows:
        relative = row.get("path")
        require(isinstance(relative, str) and relative in c.MANIFEST_INPUT_PATHS, "manifest artifact path differs")
        data = read(root, relative)
        require(row.get("bytes") == len(data) and row.get("sha256") == c.sha(data), f"manifest input digest differs: {relative}")
    require(manifest.get("artifactCount") == 23, "manifest artifact count differs")
    require(manifest.get("pendingFencePaths") == [] and manifest.get("pendingArtifactCount") == 0, "manifest has pending inputs")
    require(manifest.get("artifactSetDigest") == c.sha(c.pretty(rows)), "manifest artifact set digest differs")


def verify_authority(value: dict[str, Any], label: str) -> None:
    authority = value.get("authority")
    require(isinstance(authority, dict), f"{label}: authority missing")
    expected = c.authority()
    require(authority == expected, f"{label}: authority differs")


def verify_flags(value: dict[str, Any], label: str) -> None:
    for key, expected in c.flags().items():
        require(value.get(key) == expected, f"{label}: flag {key} differs")
    require(value.get("provisionalKernelOnly") is True, f"{label}: provisional kernel flag differs")
    require(value.get("shippingBoundaryAdoption") == "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION", f"{label}: adoption boundary differs")
    require(value.get("noNewSwiftDataV6Entity") is True, f"{label}: V6 entity claim differs")


def verify_source_bindings(value: dict[str, Any], root: Path) -> None:
    rows = value.get("sourceBindings")
    require(isinstance(rows, list) and len(rows) == 9, "source binding count differs")
    seen: list[str] = []
    for row in rows:
        require(isinstance(row, dict), "source binding row is not object")
        relative = row.get("path")
        require(isinstance(relative, str) and relative in c.SOURCE_PATHS, "source binding path outside fence")
        require(relative not in seen, f"duplicate source binding: {relative}")
        seen.append(relative)
        data = read(root, relative)
        require(row.get("bytes") == len(data) and row.get("sha256") == c.sha(data), f"source binding digest differs: {relative}")
        tokens = row.get("requiredTokens")
        symbols = row.get("symbols")
        require(isinstance(tokens, list) and tokens and all(isinstance(item, str) for item in tokens), f"{relative}: token list missing")
        require(isinstance(symbols, list) and symbols and all(isinstance(item, str) for item in symbols), f"{relative}: symbol list missing")
        source = data.decode("utf-8")
        for token in tokens:
            require(token.lower() in source.lower(), f"{relative}: source token absent: {token}")
    require(seen == c.SOURCE_PATHS, "source binding order/coverage differs")


def verify_source_semantics(root: Path, manifest: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    contracts = text(root, c.NEW_SOURCE_PATHS[0])
    registry = text(root, c.NEW_SOURCE_PATHS[1])
    bundled = text(root, c.NEW_SOURCE_PATHS[2])
    adapter = text(root, c.NEW_SOURCE_PATHS[3])
    sign_pack = text(root, c.EXISTING_PATHS[0])
    resource = load_input_json(root, c.EXISTING_PATHS[2])
    fixture = load_input_json(root, c.NEW_SOURCE_PATHS[5])
    test_source = text(root, c.NEW_SOURCE_PATHS[4])

    require(static_string(sign_pack, "illuminatedSignPackageID") == c.PACKAGE_ID, "SignPack package ID differs")
    require(resource.get("packID") == c.PACKAGE_ID, "production resource package ID differs")
    require(resource.get("schemaVersion") == 1 and resource.get("contentVersion") == 1, "production resource version differs")
    require(static_string(contracts, "name") == c.REGISTRY_NAME, "registry schema name source differs")
    version_match = re.search(r"\bstatic\s+let\s+version\s*=\s*(\d+)", contracts)
    require(version_match is not None and int(version_match.group(1)) == 2, "registry schema version source differs")
    require("static let packageID = SignPack.illuminatedSignPackageID" in adapter, "adapter package ID differs")
    require(static_string(bundled, "source") == "BUNDLED_ONLY", "bundled source policy differs")
    require("runtimeDownloadsAllowed = false" in bundled, "runtime download policy missing")
    require("shippingPackageIDs" in bundled and "InspectionPackageRegistryPublisherV2.publish" in bundled, "bundled registry binding incomplete")
    require("InspectionPackageRegistryPublisherV2" in registry and "orderedPackageIDs" in registry, "registry publisher binding incomplete")
    require("persistentWriteOccurred: false" in registry, "registry persistence boundary missing")
    for token in ("InspectionPackageClosedCodingV2", "requireExactKeys", "CaseIterable", "allCases", "nonCanonicalData", "contentVersion == 1"):
        require(token.lower() in contracts.lower(), f"strict package decoding token missing: {token}")

    require(static_enum_values(contracts, "InspectionPackageCapabilityV2") == c.CAPABILITY_VALUES, "capability enum differs")
    require(static_enum_values(contracts, "InspectionPackagePermissionV2") == c.PERMISSION_VALUES, "permission enum differs")
    require(static_enum_values(contracts, "InspectionPackageGuidanceKindV2") == c.GUIDANCE_KIND_VALUES, "guidance enum differs")
    failure_start = contracts.find("enum InspectionPackageFailureV2")
    require(failure_start >= 0, "failure enum missing")
    failure_block = contracts[failure_start:contracts.find("}\n\nenum InspectionPackageCapabilityV2", failure_start)]
    failures = re.findall(r"\bcase\s+([A-Za-z0-9_]+)\b", failure_block)
    require(failures == c.FAILURE_VALUES, "failure enum differs")

    methods = re.findall(r"\bfunc\s+(testV9_11[A-Za-z0-9_]*)\s*\(", test_source)
    require(len(methods) == 5 and len(set(methods)) == 5, f"expected exactly five V9_11 tests, found {methods}")
    families = [re.search(r"testV9_11([GAHIR]01)", name).group(1) for name in methods]
    require(sorted(families) == sorted(c.EVIDENCE_FAMILIES), "V9_11 family coverage differs")
    require(manifest.get("testMethods") == methods, "manifest test selectors differ")

    require(fixture.get("schemaVersion") == 2, "alternate fixture schema differs")
    require(isinstance(fixture.get("packageID"), str) and fixture["packageID"] != c.PACKAGE_ID, "alternate fixture is not distinct")
    require(fixture["packageID"].startswith("test."), "alternate fixture is not test-only")
    require(c.PACKAGE_ID not in text(root, c.NEW_SOURCE_PATHS[5]), "alternate fixture embeds shipping package ID")
    for relative in c.NEW_SOURCE_PATHS[:4]:
        require("V21P03C01AlternatePackV1" not in text(root, relative), f"alternate fixture leaked into production source: {relative}")
    require(c.NEW_SOURCE_PATHS[5].endswith("V21P03C01AlternatePackV1.json"), "alternate fixture path identity differs")

    # The package kernel must remain sign-feature neutral; only the adapter and
    # bundled composition layer may mention the old SignPack representation.
    for relative in (c.NEW_SOURCE_PATHS[0], c.NEW_SOURCE_PATHS[1]):
        source = text(root, relative)
        require("SignPack" not in source and "ShippingIlluminatedSignAdapter" not in source, f"kernel sign dependency leaked: {relative}")
    require("ShippingIlluminatedSignAdapterV1" in adapter and "exactParity" in adapter, "adapter parity source missing")
    require("ShippingIlluminatedSignParityReceiptV1" in adapter and "sourceCanonicalSHA256" in adapter and "roundTripCanonicalSHA256" in adapter, "adapter receipt source missing")
    require("InspectionPackageRegistryPublicationBoundaryV2" in registry, "publication boundary source missing")
    for boundary in ("beforeValidation", "afterValidationBeforePublication", "afterPublicationBeforeReceipt"):
        require(boundary in registry, f"publication interruption boundary missing: {boundary}")

    # Production package code cannot smuggle in a remote/entitlement/second
    # shipping surface.  Policy wording is intentionally kept in tooling and
    # tests; this scan only covers executable production source.
    forbidden = re.compile(r"URLSession|URLRequest|CloudKit|SwiftData|StoreKit|marketplace|https?://|CKRecord|NWPathMonitor", re.I)
    for relative in c.NEW_SOURCE_PATHS[:4]:
        require(forbidden.search(text(root, relative)) is None, f"forbidden production integration token: {relative}")
    guidance_rows = [
        {"guidanceID": guidance_id, "kind": kind.upper(), "localizationKey": key}
        for guidance_id, kind, key in re.findall(
            r"guidanceID:\s*\"([^\"]+)\"\s*,\s*kind:\s*\.([A-Za-z0-9_]+)\s*,\s*"
            r"localizationKey:\s*\"([^\"]+)\"",
            adapter,
            re.S,
        )
    ]
    require(guidance_rows and len(guidance_rows) == len(set(row["guidanceID"] for row in guidance_rows)), "guidance source declarations differ")
    return {
        "packageID": c.PACKAGE_ID,
        "sourceSchemaVersion": resource["schemaVersion"],
        "contentVersion": resource["contentVersion"],
        "inspectionPackageSchemaVersion": 2,
        "capabilities": sorted(c.CAPABILITY_VALUES),
        "permissions": sorted(c.PERMISSION_VALUES),
        "advisoryGuidance": sorted(guidance_rows, key=lambda row: row["guidanceID"]),
        "sourceCanonicalSHA256": c.sha(c.canonical(resource)),
    }, methods


def verify_semantic_documents(root: Path, docs: dict[str, dict[str, Any]], package: dict[str, Any], methods: list[str]) -> None:
    registry = docs[c.REGISTRY_DOC]
    value = registry.get("registry")
    require(isinstance(value, dict), "registry contract missing registry object")
    for key, expected in {
        "name": c.REGISTRY_NAME,
        "version": 2,
        "source": "BUNDLED_ONLY",
        "closed": True,
        "maximumPackageCount": 32,
        "shippingPackageIDs": [c.PACKAGE_ID],
        "orderedPackageIDs": [c.PACKAGE_ID],
        "deterministicOrdering": "SORTED_ASCENDING_PACKAGE_ID",
        "duplicatePackageIDDisposition": "FAIL_CLOSED",
        "unknownPackageDisposition": "FAIL_CLOSED",
        "incompatiblePackageDisposition": "FAIL_CLOSED",
        "runtimeDownloadsAllowed": False,
        "userAuthoredPackagesAllowed": False,
        "secondShippingVerticalAllowed": False,
        "persistentWriteOccurred": False,
        "declarationOnly": True,
        "migrationRequired": False,
        "backupRestoreRequired": False,
        "deleteEraseRequired": False,
        "exportReportRequired": False,
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
    }.items():
        require(value.get(key) == expected, f"registry semantic field differs: {key}")
    require(value.get("failureKinds") == c.FAILURE_VALUES, "registry failure-kind parity differs")
    coding = registry.get("coding")
    require(isinstance(coding, dict), "registry coding contract missing")
    for key, expected in {
        "strictDecodable": True,
        "exactCodingKeys": True,
        "unknownKeyDisposition": "FAIL_CLOSED",
        "duplicateKeyDisposition": "FAIL_CLOSED",
        "nonCanonicalDataDisposition": "FAIL_CLOSED",
        "canonicalCodec": "InspectionPackageCanonicalCodecV2",
        "canonicalEqualityRequired": True,
        "sortedKeys": True,
        "withoutEscapingSlashes": True,
        "maximumCanonicalBytes": 1_048_576,
        "contentVersionExact": 1,
    }.items():
        require(coding.get(key) == expected, f"strict registry coding field differs: {key}")
    publication = registry.get("publication")
    require(isinstance(publication, dict), "publication contract missing")
    require(publication.get("boundaries") == c.PUBLICATION_BOUNDARIES, "publication boundaries differ")
    require(publication.get("partialPublicationAllowed") is False and publication.get("receiptRequired") is True, "publication safety differs")

    capability = docs[c.CAPABILITY_DOC]
    caps = capability.get("capabilities")
    perms = capability.get("permissions")
    guidance = capability.get("guidance")
    require(caps.get("closedValues") == sorted(c.CAPABILITY_VALUES) and caps.get("declaredShippingValues") == package["capabilities"], "capability contract differs")
    require(perms.get("closedValues") == sorted(c.PERMISSION_VALUES) and perms.get("declaredShippingValues") == package["permissions"], "permission contract differs")
    require(guidance.get("closedKinds") == sorted(c.GUIDANCE_KIND_VALUES), "guidance kinds differ")
    require(guidance.get("entries") == package["advisoryGuidance"], "guidance entries differ")
    require(guidance.get("unknownKindDisposition") == "FAIL_CLOSED", "guidance fail-closed policy differs")

    compatibility = docs[c.COMPATIBILITY_DOC].get("compatibility")
    require(isinstance(compatibility, dict), "compatibility object missing")
    require(compatibility.get("registryName") == c.REGISTRY_NAME and compatibility.get("registryVersion") == 2, "compatibility registry differs")
    require(compatibility.get("packageSchemaVersion") == 2 and compatibility.get("packageContentVersion") == 1, "compatibility package versions differ")
    require(compatibility.get("validationBeforeExecution") is True, "compatibility admission boundary missing")
    require(compatibility.get("unknownPackageDisposition") == "FAIL_CLOSED" and compatibility.get("incompatiblePackageDisposition") == "FAIL_CLOSED", "compatibility failure policy differs")
    require(compatibility.get("canonicalCodec") == "InspectionPackageCanonicalCodecV2" and compatibility.get("sortedKeys") is True, "canonical codec binding differs")
    require(compatibility.get("strictDecoder") == "InspectionPackageClosedCodingV2.requireExactKeys", "strict decoder binding differs")
    require(compatibility.get("exactCodingKeys") is True and compatibility.get("unknownKeyDisposition") == "FAIL_CLOSED", "strict decoder policy differs")
    require(compatibility.get("contentVersionExact") == 1, "compatibility content version binding differs")

    shipping = docs[c.SHIPPING_DOC].get("shippingAdapter")
    require(isinstance(shipping, dict), "shipping adapter object missing")
    require(shipping.get("type") == "ShippingIlluminatedSignAdapterV1" and shipping.get("packageID") == c.PACKAGE_ID, "shipping adapter identity differs")
    for key in ("exactParityRequired", "displayParityRequired", "behaviorParityRequired", "byteOrderParityRequired"):
        require(shipping.get(key) is True, f"shipping parity requirement missing: {key}")
    require(shipping.get("sourceCanonicalSHA256") == package["sourceCanonicalSHA256"], "shipping source digest differs")
    require(shipping.get("roundTripCanonicalSHA256") == package["sourceCanonicalSHA256"], "shipping round-trip digest differs")
    require(shipping.get("signUITypeInKernel") is False and shipping.get("adapterOnly") is True, "shipping kernel boundary differs")

    evidence = docs[c.EVIDENCE_DOC]
    require(evidence.get("testMethods") == methods, "evidence test methods differ")
    require([row.get("evidenceID") for row in evidence.get("evidence", [])] == c.EVIDENCE_IDS, "evidence IDs differ")
    require([row.get("family") for row in evidence.get("evidence", [])] == list(c.EVIDENCE_FAMILIES), "evidence family order differs")
    require(evidence.get("interruptionBoundaries") == c.PUBLICATION_BOUNDARIES, "evidence interruption boundaries differ")
    alternate = evidence.get("alternateFixture")
    require(isinstance(alternate, dict) and alternate.get("testOnly") is True and alternate.get("productionBundleMember") is False and alternate.get("productionRegistryMember") is False, "alternate fixture absence proof differs")
    brand = evidence.get("brandImpact")
    require(isinstance(brand, dict) and brand.get("manifestType") == "BrandImpactManifestV1" and brand.get("manifestCount") == 1, "brand impact receipt differs")
    require(brand.get("changedScreens") == [] and brand.get("changedStates") == [], "Card32 claims a UI delta")
    privacy = evidence.get("privacy")
    require(isinstance(privacy, dict) and all(privacy.get(key) is False for key in ("customerDataInDiagnostics", "secretsInContracts", "networkTransport", "downloadedPackageBytes", "userAuthoredRules")), "privacy boundary differs")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        manifest = load(root, c.MANIFEST)
        verify_seal(manifest, c.MANIFEST)
        verify_fence(manifest, root)
        schemas = {
            c.REGISTRY_SCHEMA: load(root, c.REGISTRY_SCHEMA),
            c.CAPABILITY_SCHEMA: load(root, c.CAPABILITY_SCHEMA),
            c.GUIDANCE_SCHEMA: load(root, c.GUIDANCE_SCHEMA),
            c.COMPATIBILITY_SCHEMA: load(root, c.COMPATIBILITY_SCHEMA),
            c.SHIPPING_SCHEMA: load(root, c.SHIPPING_SCHEMA),
            c.EVIDENCE_SCHEMA: load(root, c.EVIDENCE_SCHEMA),
        }
        for relative, schema in schemas.items():
            verify_strict_schema(schema, relative)
        docs = {
            c.REGISTRY_DOC: load(root, c.REGISTRY_DOC),
            c.CAPABILITY_DOC: load(root, c.CAPABILITY_DOC),
            c.COMPATIBILITY_DOC: load(root, c.COMPATIBILITY_DOC),
            c.SHIPPING_DOC: load(root, c.SHIPPING_DOC),
            c.EVIDENCE_DOC: load(root, c.EVIDENCE_DOC),
        }
        for relative, document in docs.items():
            verify_seal(document, relative)
            verify_authority(document, relative)
            verify_flags(document, relative)
            verify_source_bindings(document, root)
        package, methods = verify_source_semantics(root, manifest)
        # Independently validate every generated document against its paired
        # strict schema.  This catches a schema that is strict only on paper.
        pairs = {
            c.REGISTRY_DOC: c.REGISTRY_SCHEMA,
            c.CAPABILITY_DOC: c.CAPABILITY_SCHEMA,
            c.COMPATIBILITY_DOC: c.COMPATIBILITY_SCHEMA,
            c.SHIPPING_DOC: c.SHIPPING_SCHEMA,
            c.EVIDENCE_DOC: c.EVIDENCE_SCHEMA,
        }
        for doc_path, schema_path in pairs.items():
            validate_instance(docs[doc_path], schemas[schema_path], doc_path)
        verify_semantic_documents(root, docs, package, methods)
    except (VerificationError, OSError, UnicodeError, ValueError, KeyError) as error:
        print(f"V23-P03-C01 hostile verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P03-C01 hostile static verification passed: 24 fence paths, 23 sealed inputs, 6 strict schemas, 5 evidence tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
