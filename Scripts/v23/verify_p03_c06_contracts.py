#!/usr/bin/env python3
"""Fail-closed static verifier for the provisional V23-P03-C06 lane."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import p03_c06_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout.strip()


def load(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf"), f"BOM forbidden: {path}")
    duplicates: list[str] = []

    def pairs(rows: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in rows:
            if key in result:
                duplicates.append(key)
            result[key] = value
        return result

    value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    require(not duplicates, f"duplicate JSON keys in {path}: {duplicates}")
    require(isinstance(value, dict), f"JSON root is not object: {path}")
    return value


def changed_paths(root: Path) -> set[str]:
    rows = git(root, "status", "--porcelain=v1", "--untracked-files=all").splitlines()
    return {row[3:].replace("\\", "/") for row in rows if len(row) >= 4}


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def exact_properties(schema: dict[str, Any], expected: set[str], optional: set[str], label: str) -> None:
    require(set(schema["properties"]) == expected, f"{label}: properties differ")
    require(set(schema["required"]) == expected - optional, f"{label}: required/optional omission differs")


def independently_generated(root: Path) -> dict[str, bytes]:
    command = [sys.executable, "-B", str(root / contracts.SCRIPT_PATHS[1]), "--dump-json"]
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    first = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True, text=True)
    second = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True, text=True)
    require(first.stdout == second.stdout, "independent subprocess generation differs between runs")
    encoded = json.loads(first.stdout)
    require(isinstance(encoded, dict), "independent generation output is not an object")
    return {path: base64.b64decode(value, validate=True) for path, value in encoded.items()}


def validate_with_pinned_json_schema_net(root: Path, fixture: dict[str, Any]) -> None:
    assembly = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/JsonSchema.Net.dll"
    require(assembly.is_file(), "pinned offline JsonSchema.Net assembly unavailable")
    require(digest(assembly.read_bytes()) == "1243dc7749d37818beadf8967c3963082ba00efe05877e3f180346e9f56007a0",
            "pinned JsonSchema.Net digest differs")
    samples = contracts.sample_instances(fixture)
    samples[contracts.SCHEMA_PATHS[4]] = load(root / contracts.CONTRACT_PATHS[2])
    samples[contracts.SCHEMA_PATHS[5]] = load(root / contracts.CONTRACT_PATHS[4])
    require(set(samples) == set(contracts.SCHEMA_PATHS), "sample/schema inventory differs")
    with tempfile.TemporaryDirectory(prefix="v23-p03-c06-schema-") as temporary:
        temp = Path(temporary)
        rows: list[dict[str, Any]] = []
        for index, schema_path in enumerate(contracts.SCHEMA_PATHS):
            instance_path = temp / f"sample-{index}.json"
            instance_path.write_bytes(contracts.pretty(samples[schema_path]))
            rows.append({"schema": str((root / schema_path).resolve()), "instance": str(instance_path.resolve()),
                         "expectedValid": True, "label": f"POSITIVE_{index}"})
        negatives = contracts.negative_sample_instances(fixture)
        require([row["label"] for row in negatives] == fixture["schemaNegativeCases"], "negative schema inventory differs")
        for index, row in enumerate(negatives):
            instance_path = temp / f"negative-{index}.json"
            instance_path.write_bytes(contracts.pretty(row["instance"]))
            rows.append({"schema": str((root / row["schemaPath"]).resolve()), "instance": str(instance_path.resolve()),
                         "expectedValid": False, "label": row["label"]})
        index_path = temp / "index.json"
        index_path.write_bytes(contracts.pretty({"rows": rows, "schemas": [str((root / path).resolve()) for path in contracts.SCHEMA_PATHS]}))

        def quoted(path: Path) -> str:
            return "'" + str(path.resolve()).replace("'", "''") + "'"

        script = (
            f"Add-Type -Path {quoted(assembly)}; "
            "$options=[Json.Schema.EvaluationOptions]::new(); "
            f"$index=Get-Content -LiteralPath {quoted(index_path)} -Raw | ConvertFrom-Json; "
            "foreach($path in $index.schemas) { "
            "$node=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $path -Raw)); "
            "$result=[Json.Schema.MetaSchemas]::Draft202012.Evaluate($node,$options); "
            "if(-not $result.IsValid){ throw ('meta-schema failure: '+$path) } }; "
            "foreach($row in $index.rows) { "
            "$schema=[Json.Schema.JsonSchema]::FromFile($row.schema); "
            "$instance=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $row.instance -Raw)); "
            "$result=$schema.Evaluate($instance,$options); "
            "if($result.IsValid -ne [bool]$row.expectedValid){ throw ('sample expectation failure: '+$row.label) } }; 'PASS'"
        )
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], capture_output=True, text=True)
        require(result.returncode == 0 and result.stdout.strip().endswith("PASS"),
                f"pinned Draft 2020-12 meta/sample validation failed: {result.stderr.strip()}")


def verify(root: Path) -> dict[str, Any]:
    require(git(root, "rev-parse", "HEAD") == contracts.APP_BASE_HEAD, "application HEAD differs from hydrated base")
    require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE, "application tree differs from hydrated base")
    expected_authority = {
        "COORDINATION_HEAD": "f026315fb5d833eb5334e75cc27c96413be9e857",
        "COORDINATION_TREE": "5aa8e800e296f89cfe748941babdbd7c31458d2e",
        "COORDINATION_CAS_SEQUENCE": 156,
        "COORDINATION_LEDGER_DIGEST": "8fcf5068ca18a4433071f08b82d25b69fc0eb6a1129027533e90dc02dfe9bb98",
        "CONTEXT_DIGEST": "1058e2792a104f74af0a43844467482a7abb29a99da129c8e0be92b6ea0f922d",
        "FENCE_DIGEST": "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2",
        "PREREQUISITE_DIGEST": "62ea4185d0266ec91ea0df9352645e192869cdbf2924278a08ecdfd3bd75488c",
        "TRANSITION_DIGEST": "f7b73b37ef4ba4cf4388821b9658cfc49aa5e45fb9188b7d3dd7b0c2704c3072",
        "HYDRATION_PROJECTION_DIGEST": "74cc810fa233e659d6fe7ea006b39dc1012ead0912f097539e16c2839f6de6a0",
    }
    for name, expected in expected_authority.items():
        require(getattr(contracts, name) == expected, f"authority constant differs: {name}")
    require(len(contracts.PATH_FENCE) == 24 and len(set(contracts.PATH_FENCE)) == 24, "path fence differs")
    require(contracts.PATH_FENCE == contracts.SOURCE_PATHS + contracts.TOOL_PATHS, "path fence partition/order differs")
    require(len(contracts.SOURCE_PATHS) == 9 and len(contracts.TOOL_PATHS) == 15, "source/tool partition differs")
    require(contracts.EXISTING_PATHS == [] and contracts.NEW_PATHS == contracts.PATH_FENCE, "all-new partition differs")
    observed = changed_paths(root)
    require(observed == set(contracts.PATH_FENCE), f"changed path fence differs: {sorted(observed ^ set(contracts.PATH_FENCE))}")
    for relative in contracts.PATH_FENCE:
        require((root / relative).is_file(), f"missing fenced path: {relative}")
        exists_at_base = subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{contracts.APP_BASE_HEAD}:{relative}"], capture_output=True)
        require(exists_at_base.returncode != 0, f"all-new path existed at base: {relative}")
    caches = [path for path in root.rglob("*") if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo")]
    require(not caches, f"Python cache leaked: {[str(path.relative_to(root)) for path in caches]}")
    reservation = load(root / "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json")
    require(reservation["contentDigest"] == contracts.S10_RESERVATION_DIGEST and reservation["reservedPathCount"] == 86,
            "S10 reservation differs")
    require(not set(contracts.PATH_FENCE) & set(reservation["reservedPaths"]), "Phase 10 path overlap")

    first = contracts.all_outputs(root)
    second = contracts.all_outputs(root)
    require(first == second and set(first) == set(contracts.GENERATED_PATHS), "in-process generation is not byte deterministic")
    independent = independently_generated(root)
    require(independent == first, "independent subprocess generation differs from in-process generation")
    for relative, expected in first.items():
        require((root / relative).read_bytes() == expected, f"stale generated artifact: {relative}")

    schemas = {path: load(root / path) for path in contracts.SCHEMA_PATHS}
    fixture_path = root / contracts.FIXTURE
    fixture = load(fixture_path)
    validate_with_pinned_json_schema_net(root, fixture)
    for relative, schema in schemas.items():
        require(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", f"dialect differs: {relative}")
        require(schema["$id"].startswith("https://schemas.assetrounds.local/v23/p03/c06/"), f"schema ID differs: {relative}")
        require(schema["type"] == "object" and schema["additionalProperties"] is False, f"root not strict: {relative}")
        for node in walk(schema):
            if isinstance(node, dict) and "$ref" in node:
                require(str(node["$ref"]).startswith("#/$defs/"), f"non-local schema ref: {relative}")
            if isinstance(node, dict) and node.get("type") == "object" and "properties" in node:
                require(node.get("additionalProperties") is False, f"open nested object: {relative}")

    exact_properties(schemas[contracts.SCHEMA_PATHS[0]], {"schemaVersion", "payload", "snapshotSHA256"}, set(), "CompletedActivitySnapshotV1")
    exact_properties(schemas[contracts.SCHEMA_PATHS[1]], {"schemaVersion", "profileID", "profileRelease", "audience", "outputScopeID",
        "privacyTransformID", "privacyTransformVersion", "markupProfileID", "markupProfileVersion", "localeIdentifier", "displayProfileID",
        "rendererVersion", "audiencePrivacyPolicy", "includedFieldIDs", "limitationsText"}, set(), "EvidenceDetailCardProfileV1")
    exact_properties(schemas[contracts.SCHEMA_PATHS[2]], {"schemaVersion", "receiptID", "snapshotID", "cardID", "outputScopeID", "audience",
        "sourceSnapshotSHA256", "profileSHA256", "privacyTransformSHA256", "reviewedMarkupSHA256", "semanticSHA256", "semanticTextSHA256",
        "composedOutputSHA256", "confirmationID", "confirmation", "limitationsPresented", "captureTimeVerified", "locationVerified", "personVerified"}, set(), "EvidenceDetailCardRenderReceiptV1")
    exact_properties(schemas[contracts.SCHEMA_PATHS[3]], {"schemaVersion", "confirmationID", "workspaceID", "outputScopeID", "profileID",
        "sourceSnapshotSHA256", "profileSHA256", "privacyTransformSHA256", "reviewedMarkupSHA256", "semanticSHA256", "semanticTextSHA256",
        "cardSHA256", "card", "audience", "localeIdentifier", "displayProfileID", "rendererVersion", "audiencePrivacyPolicyID",
        "audiencePrivacyPolicyVersion", "audiencePrivacyPolicySHA256", "composedOutputSHA256", "privacyTransformAppliedBeforeMarkup",
        "userConfirmedExactComposedBytes", "detectorID", "detectorVersion", "detectorDisposition", "detection", "captureTimeVerified",
        "locationVerified", "personVerified", "deliveryVerified", "approvalVerified", "securityVerified", "historicalRewriteClaimed"}, set(), "FinalAudiencePrivacyConfirmationV1")
    exact_properties(schemas[contracts.SCHEMA_PATHS[4]], {"schemaVersion", "manifestID", "manifestVersion", "persistentContractSchema",
        "codec", "compatibility", "objects", "enums", "reportSectionRegistry"}, set(), "ContractManifestV1")
    snapshot_defs = schemas[contracts.SCHEMA_PATHS[0]]["$defs"]
    payload = snapshot_defs["completed-activity-snapshot-payload-v1"]
    exact_properties(payload, {"schemaVersion", "workspaceID", "snapshotID", "snapshotRevision", "sourceActivityID",
        "sourceRevision", "reportID", "packageReleaseID", "generatedAt", "completedAt", "supersedesSnapshotID",
        "supersededSnapshotSHA256", "amendmentReason", "profileBinding", "serviceFacts", "evidenceCards", "limitations"},
        {"supersedesSnapshotID", "supersededSnapshotSHA256", "amendmentReason"}, "CompletedActivitySnapshotPayloadV1")
    require(not {"supersedesSnapshotID", "supersededSnapshotSHA256", "amendmentReason"} & set(payload["required"]),
            "Swift optional snapshot fields must be omitted, not required/null")
    exact_properties(snapshot_defs["completed-service-fact-v1"], {"factID", "kind", "privacyClass", "label", "value", "effectiveAt"},
        {"effectiveAt"}, "CompletedServiceFactV1")
    card = snapshot_defs["evidence-detail-card-v1"]
    exact_properties(card, {"schemaVersion", "cardID", "workspaceID", "evidenceID", "outputScopeID", "profileID", "profileSHA256",
        "profile", "audience", "privacyTransformID", "privacyTransformVersion", "localeIdentifier", "displayProfileID", "rendererVersion",
        "audiencePrivacyPolicyID", "audiencePrivacyPolicyVersion", "audiencePrivacyPolicySHA256", "audiencePrivacyPolicy",
        "privacyTransformedSHA256", "reviewedMarkupID", "reviewedMarkupSHA256", "reviewedMarkup", "fields", "outputReferences",
        "annotations", "referenceLabels", "limitationsText"}, set(), "EvidenceDetailCardV1")
    exact_properties(snapshot_defs["reviewed-evidence-markup-v1"], {"markupID", "sourcePrivacyDigest", "orderedAnnotations",
        "orderedReferenceLabels"}, set(), "ReviewedEvidenceMarkupV1")
    exact_properties(snapshot_defs["audience-privacy-policy-v1"], {"schemaVersion", "policyID", "policyVersion", "audience",
        "prohibitedCanaries", "policySHA256"}, set(), "AudiencePrivacyPolicyV1")
    output_ref = snapshot_defs["output-scoped-content-reference-v1"]
    require(set(output_ref["properties"]) == {"outputScopeID", "outputReferenceID", "workspaceBindingSHA256", "contentSHA256", "mediaType", "byteRole"},
            "workspace-bound output reference differs")
    detection = schemas[contracts.SCHEMA_PATHS[3]]["$defs"]["post-markup-audience-privacy-detection-v1"]
    exact_properties(detection, {"schemaVersion", "detectorID", "detectorVersion", "audience", "policyID", "policyVersion",
        "policySHA256", "cardSHA256", "semanticText", "semanticTextSHA256", "composedOutput", "composedOutputSHA256", "disposition", "findingKinds"},
        set(), "PostMarkupAudiencePrivacyDetectionV1")
    composed_output = detection["properties"]["composedOutput"]
    require(composed_output["contentEncoding"] == "base64" and composed_output["x_assetrounds_maximumDecodedBytes"] == 8388608 and
            composed_output["x_assetrounds_maximumEncodedUTF8Bytes"] == 11184812,
            "base64 composed-output bounds differ")

    require(fixture_path.read_bytes() == contracts.canonical(fixture) + b"\n", "fixture is not canonical compact sorted JSON plus LF")
    require(fixture["schema"] == "V21P03C06SnapshotProjectionCorpusV1" and fixture["schemaVersion"] == 1 and fixture["testOnly"] is True,
            "fixture identity differs")
    require(len(fixture["hostileCases"]) == 18 and len(fixture["interruption"]["boundaries"]) == 7, "fixture coverage counts differ")
    require(len(fixture["acceptanceEvidenceIDs"]) == 5 and set(fixture["acceptanceEvidenceIDs"]) == set(contracts.EVIDENCE_IDS),
            "fixture must name exactly five evidence IDs")
    require(fixture["schemaSampleSeeds"]["semanticText"] and len(fixture["schemaSampleSeeds"]["sha256"]) == 64,
            "fixture sample seeds differ")
    require(fixture["persistentContract"] == {"backupRestoreRequired": False, "deleteEraseRequired": False,
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED", "exportReportRequired": True, "migrationRequired": False,
        "mode": "DECLARATION_ONLY", "schema": "KERNEL_SNAPSHOT_V1"}, "lifecycle declaration differs")

    normative = contracts.normative_contract_manifest()
    concrete = load(root / contracts.CONTRACT_PATHS[2])
    require(concrete == normative, "concrete normative ContractManifestV1 instance differs")
    require(concrete["objects"] == sorted(concrete["objects"], key=lambda x: x["typeID"]), "manifest objects unordered")
    require(concrete["enums"] == sorted(concrete["enums"], key=lambda x: x["typeID"]), "manifest enums unordered")
    closure = fixture["manifestClosure"]
    object_ids = [item["typeID"] for item in concrete["objects"]]
    enum_ids = [item["typeID"] for item in concrete["enums"]]
    require(len(object_ids) == 29 and object_ids == closure["objectTypeIDs"], "exact 29-object manifest closure differs")
    require(len(enum_ids) == 15 and enum_ids == closure["enumTypeIDs"], "exact 15-enum manifest closure differs")
    require(closure["productSchemaPaths"] == contracts.PRODUCT_SCHEMA_PATHS and
            closure["toolingSchemaPaths"] == contracts.TOOLING_SCHEMA_PATHS,
            "product/tooling schema partition differs")
    manifest_fields = [item for definition in concrete["objects"] for item in definition["fields"]]
    require(any(item["kind"] == "ENUM" for item in manifest_fields), "manifest omits ENUM kind")
    require(any(item.get("arrayElementKind") == "ENUM" for item in manifest_fields), "manifest omits enum arrayElementKind")
    require(all((item["kind"] == "ARRAY") == ("arrayElementKind" in item) for item in manifest_fields), "arrayElementKind shape differs")
    require(all(item["nullable"] is False for item in manifest_fields if not item["required"]),
            "optional fields must reject explicit null")
    require(all(re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", item["fieldID"]) for item in manifest_fields),
            "manifest fieldID grammar differs")
    require("BASE64_BYTES" in next(item for item in concrete["enums"] if item["typeID"] == "contract-scalar-kind-v1")["knownValues"],
            "contract scalar enum omits BASE64_BYTES")
    all_definition_ids = set(object_ids + enum_ids)
    for schema_path in contracts.PRODUCT_SCHEMA_PATHS:
        schema = schemas[schema_path]
        require(schema == contracts.compile_product_schema(concrete, schema_path),
                f"product schema is not compiled from manifest: {schema_path}")
        require(schema["x_assetrounds_normativeManifestPath"] == contracts.CONTRACT_PATHS[2] and
                schema["x_assetrounds_productManifestDerived"] is True and
                schema["x_assetrounds_schemaClass"] == "PRODUCT_CONTRACT" and
                schema["x_assetrounds_rootTypeID"] == contracts.schema_root_type_id(schema_path),
                f"product schema lacks normative manifest projection metadata: {schema_path}")
        require(set(schema["$defs"]) == all_definition_ids,
                f"product schema definition closure differs: {schema_path}")
    tooling_schema = schemas[contracts.TOOLING_SCHEMA_PATHS[0]]
    require(tooling_schema == contracts.evidence_schema() and
            tooling_schema["x_assetrounds_productManifestDerived"] is False and
            tooling_schema["x_assetrounds_schemaClass"] == "OPERATIONAL_EVIDENCE_TOOLING" and "$defs" not in tooling_schema,
            "operational evidence schema is not separately classified tooling")
    require(not hasattr(contracts, "manifest_schema"), "parallel handwritten manifest schema remains")
    section_schema = schemas[contracts.SCHEMA_PATHS[4]]["$defs"]["report-section-definition-v1"]
    require(section_schema["properties"]["privacyClass"] == {"$ref": "#/$defs/report-privacy-class-v1"} and
            section_schema["properties"]["supportedFormats"]["items"] == {"$ref": "#/$defs/report-projection-format-v1"} and
            section_schema["properties"]["supportedFormats"]["x_assetrounds_orderingKey"] == "RAW_VALUE",
            "closed section enum bindings/order annotation differ")
    manifest_def = schemas[contracts.SCHEMA_PATHS[4]]["$defs"]["contract-manifest-v1"]
    require(manifest_def["properties"]["objects"]["x_assetrounds_orderingKey"] == "typeID" and
            manifest_def["properties"]["enums"]["x_assetrounds_orderingKey"] == "typeID",
            "manifest ordering annotations differ")
    codec_schema = schemas[contracts.SCHEMA_PATHS[4]]["$defs"]["contract-codec-rule-v1"]
    exact_properties(codec_schema, {"binaryEncoding", "canonicalJSON", "codecVersion", "formatAssertion", "integerEncoding",
        "nullEncoding", "stringNormalization", "timeEncoding"}, set(), "ContractCodecRuleV1")
    require(concrete["codec"]["binaryEncoding"] == "RFC4648_BASE64_PADDED" and
            concrete["codec"]["stringNormalization"] == "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED",
            "canonical binary/string codec rule differs")
    field_schema = schemas[contracts.SCHEMA_PATHS[4]]["$defs"]["contract-field-definition-v1"]
    require(len(field_schema.get("allOf", [])) == 8, "ContractFieldDefinitionV1 tagged-union rules differ")
    for schema_path in contracts.PRODUCT_SCHEMA_PATHS:
        for node in walk(schemas[schema_path]):
            if isinstance(node, dict) and "x_assetrounds_maximumUTF8Bytes" in node:
                require(node.get("maxLength") == node["x_assetrounds_maximumUTF8Bytes"] and
                        node.get("x_assetrounds_maxLengthSemantics") == "SOUND_CODE_POINT_CEILING_NOT_UTF8_BYTE_PARITY" and
                        node.get("x_assetrounds_requiresNFC") is True and
                        node.get("x_assetrounds_noncharacterPolicy") == "REJECT_ALL_UNICODE_NONCHARACTERS",
                        f"UTF-8/NFC/noncharacter annotations differ: {schema_path}")

    methods = contracts.test_methods(root)
    require(len(methods) == 5 and len(set(methods)) == 5, f"named test count differs: {methods}")
    for family in ("G01", "A01", "H01", "I01", "R01"):
        require(sum(family in method for method in methods) == 1, f"test family differs: {family}")
    all_fenced_text = "\n".join((root / path).read_text(encoding="utf-8") for path in contracts.PATH_FENCE)
    forbidden = ["URL" + "Session", "Cloud" + "Kit", "Fire" + "base", "signed" + "URL", "service" + "Credential",
                 "Backend" + "Client", "Remote" + "Sync", "Test" + "Flight", "App" + "Store",
                 r"acceptanceCredit\s*[:=]\s*true", r"releaseCredit\s*[:=]\s*true", r"nativeCompileRan\s*[:=]\s*true",
                 r"hostedDispatchRan\s*[:=]\s*true", r"releaseReady\s*[:=]\s*true"]
    for pattern in forbidden:
        require(re.search(pattern, all_fenced_text, re.I) is None, f"forbidden full-fence token/claim: {pattern}")

    for relative in (contracts.CONTRACT_PATHS[0], contracts.CONTRACT_PATHS[1], contracts.CONTRACT_PATHS[3]):
        value = load(root / relative); unsigned = dict(value); seal = unsigned.pop("artifactDigest")
        require(seal == digest(contracts.pretty(unsigned)), f"contract seal differs: {relative}")
        require(value["authority"] == contracts.authority(), f"authority differs: {relative}")
        for flag in ("nativeCompileRan", "hostedDispatchRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled",
                     "acceptanceCredit", "releaseReady", "releaseCredit", "phase10PollingDuringParallelExecution",
                     "nativeOrHostedEvidenceClaimed", "acceptanceOrReleaseClaimed"):
            require(value[flag] is False, f"forbidden claim {flag}: {relative}")
        require(value["verificationMode"] == "STATIC_ONLY", f"non-static verification mode: {relative}")
    evidence = load(root / contracts.CONTRACT_PATHS[4])
    require(evidence["evidenceIDs"] == contracts.EVIDENCE_IDS and len(evidence["evidenceIDs"]) == 5 and evidence["result"] == "PASS",
            "evidence identity/result differs")
    require(evidence["verificationMode"] == "STATIC_ONLY" and not any(evidence[key] for key in
            ("nativeCompileRan", "hostedDispatchRan", "hostedDispatchEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit")),
            "evidence exceeds static-only authority")
    require(evidence["byteNormalization"] == contracts.BYTE_NORMALIZATION,
            "evidence byte-normalization rule differs")
    require(evidence["sourceArtifacts"] == [{"path": path, "sha256": digest(contracts.evidence_bytes(root, path))} for path in contracts.SOURCE_PATHS],
            "source evidence closure differs")
    require(evidence["fixtureSHA256"] == digest(contracts.evidence_bytes(root, contracts.FIXTURE)),
            "fixture evidence digest differs")

    tooling = load(root / contracts.MANIFEST); unsigned = dict(tooling); seal = unsigned.pop("artifactDigest")
    require(seal == digest(contracts.pretty(unsigned)), "tooling manifest seal differs")
    require(tooling["byteNormalization"] == contracts.BYTE_NORMALIZATION,
            "tooling byte-normalization rule differs")
    require(tooling["authority"] == contracts.authority() and tooling["pathFence"] == contracts.PATH_FENCE and tooling["pathFenceCount"] == 24,
            "tooling manifest authority/fence differs")
    require(tooling["artifactCount"] == 23 and tooling["pendingArtifactCount"] == 0 and len(tooling["artifacts"]) == 23,
            "tooling manifest closure count differs")
    require([row["path"] for row in tooling["artifacts"]] == contracts.MANIFEST_INPUT_PATHS, "tooling manifest artifact order differs")
    require(tooling["artifactSetDigest"] == digest(contracts.canonical(tooling["artifacts"])), "tooling manifest set seal differs")
    require(tooling["verificationMode"] == "STATIC_ONLY" and not any(tooling[key] for key in
            ("nativeCompileRan", "hostedDispatchRan", "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit")),
            "tooling manifest exceeds static-only authority")
    for row in tooling["artifacts"]:
        raw = contracts.evidence_bytes(root, row["path"])
        require(row["bytes"] == len(raw) and row["sha256"] == digest(raw), f"stale tooling manifest row: {row['path']}")

    return {"result": "PASS", "verificationMode": "STATIC_ONLY", "cardID": contracts.CARD,
            "pathFenceCount": 24, "changedPathCount": 24, "sourcePathCount": 9, "strictSchemaCount": 6,
            "sampleInstanceCount": 6, "negativeSampleInstanceCount": 7, "productManifestDerivedSchemaCount": 5,
            "toolingSchemaCount": 1, "contractObjectDefinitionCount": 29, "contractEnumDefinitionCount": 15,
            "contractDocumentCount": 5, "namedStaticTestCount": 5,
            "evidenceIDCount": 5, "fixtureSHA256": digest(fixture_path.read_bytes()),
            "manifestSHA256": digest((root / contracts.MANIFEST).read_bytes()), "nativeCompileRan": False,
            "hostedDispatchRan": False, "acceptanceCredit": False, "releaseCredit": False,
            "requiresAcceptedS10_6Reconciliation": True}


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError,
            subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C06 verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
