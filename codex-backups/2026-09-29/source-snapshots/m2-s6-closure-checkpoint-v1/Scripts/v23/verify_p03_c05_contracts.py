#!/usr/bin/env python3
"""Fail-closed verifier for the C05 attempt-2 tooling projection."""
from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c05_contracts as contracts


class VerificationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout.strip()


def load_json(path: Path) -> Any:
    return json.loads(path.read_bytes(), object_pairs_hook=contracts._strict_pairs)


def cache_paths(root: Path) -> list[str]:
    scripts = root / "Scripts" / "v23"
    if not scripts.is_dir():
        return []
    found: list[str] = []
    for path in scripts.rglob("*"):
        if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo"):
            found.append(path.relative_to(root).as_posix())
    return sorted(found)


def strict_objects(value: Any, label: str) -> None:
    if isinstance(value, dict):
        if value.get("type") == "object":
            require(value.get("additionalProperties") is False, f"{label}: open object schema")
            require(isinstance(value.get("properties"), dict), f"{label}: object properties absent")
            require(isinstance(value.get("required"), list), f"{label}: required properties absent")
            require(set(value["required"]) <= set(value["properties"]), f"{label}: undeclared required property")
        for key, child in value.items():
            strict_objects(child, f"{label}/{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            strict_objects(child, f"{label}/{index}")


def exact_shape(value: dict[str, Any], expected: set[str], optional: set[str], label: str) -> None:
    require(set(value.get("properties", {})) == expected, f"{label}: property projection differs")
    require(set(value.get("required", [])) == expected - optional, f"{label}: required projection differs")


def check_json_hygiene(root: Path) -> list[str]:
    failures: list[str] = []
    for relative in contracts.GENERATED_PATHS:
        path = root / relative
        if not path.is_file():
            continue
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            failures.append(f"BOM:{relative}")
        if b"\r" in raw:
            failures.append(f"CRLF:{relative}")
        if not raw.endswith(b"\n"):
            failures.append(f"missing-final-LF:{relative}")
    return failures


def check_schema_projection(root: Path) -> list[str]:
    failures: list[str] = []
    try:
        values = {path: load_json(root / path) for path in contracts.SCHEMA_PATHS}
        titles = set()
        for relative, value in values.items():
            require(value.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{relative}: dialect differs")
            require(value.get("type") == "object" and value.get("additionalProperties") is False, f"{relative}: root is open")
            strict_objects(value, relative)
            titles.add(value.get("title"))
        require(len(titles) == 6, "C05 schema titles collide")
        exact_shape(values[contracts.SCHEMA_PATHS[0]], {"schemaVersion", "workspaceID", "contentID", "byteLength", "mediaType", "digests", "byteRole", "createdAt"}, set(), "ContentReferenceV1")
        exact_shape(values[contracts.SCHEMA_PATHS[1]], {"schemaVersion", "locatorID", "workspaceID", "contentID", "locatorRevision", "contentDigest", "expectedByteLength"}, set(), "ContentLocatorV1")
        exact_shape(values[contracts.SCHEMA_PATHS[2]], {"schemaVersion", "manifestID", "workspaceID", "manifestRevision", "entries"}, set(), "ContentManifestV1")
        exact_shape(values[contracts.SCHEMA_PATHS[3]], {"schemaVersion", "associationEventID", "workspaceID", "evidenceID", "expectedEvidenceRevision", "resultingEvidenceRevision", "mutationID", "action", "contentID", "target", "previousContentID", "previousTarget", "supersedesAssociationEventID", "actorID", "reason", "effectiveAt"}, {"contentID", "target", "previousContentID", "previousTarget", "supersedesAssociationEventID"}, "EvidenceAssociationV1")
        exact_shape(values[contracts.SCHEMA_PATHS[4]], {"schemaVersion", "provenanceID", "workspaceID", "sources", "derivativeContentID", "derivativeDigest", "transform", "metadataSanitizerID", "metadataSanitizerVersion", "createdAt"}, set(), "ContentDerivativeProvenanceV1")
        receipt_shape = {"schemaVersion", "cardID", "receiptID", "persistentSchemaVersion", "recordsSchemaVersion", "durableFamilyCount", "durableFamilies", "registrySHA256", "sourceArtifacts", "integrationSourcePathCount", "integrationTestCount", "integrationTestMethods", "integrationEventKinds", "integrationOrderingBasis", "integrationLifecycle", "integrationReplayLimit", "evidenceIDs", "result", "verificationStatus", "nativeCompileRan", "hostedDispatchRan", "acceptanceCredit", "releaseCredit", "requiresAcceptedS10_6Reconciliation"}
        exact_shape(values[contracts.SCHEMA_PATHS[5]], receipt_shape, set(), "ContentEvidenceReceiptV1")
        require(values[contracts.SCHEMA_PATHS[0]]["properties"]["digests"]["properties"]["values"]["prefixItems"][0]["properties"]["algorithm"] == {"const": "SHA256"}, "SHA256 ordering rule absent")
        require(values[contracts.SCHEMA_PATHS[0]]["properties"]["digests"]["properties"]["values"]["uniqueItems"] is True, "digest uniqueness absent")
        require(values[contracts.SCHEMA_PATHS[2]]["properties"]["entries"]["uniqueItems"] is True, "manifest uniqueness absent")
        require(values[contracts.SCHEMA_PATHS[4]]["properties"]["sources"]["uniqueItems"] is True, "provenance source uniqueness absent")
        require(len(values[contracts.SCHEMA_PATHS[3]].get("allOf", [])) == 3, "association action matrix differs")
        require(len(values[contracts.SCHEMA_PATHS[4]]["properties"]["transform"].get("oneOf", [])) == 4, "derivative transform matrix differs")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["persistentSchemaVersion"] == {"const": contracts.PERSISTENT_SCHEMA_VERSION}, "receipt persistent schema differs")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["recordsSchemaVersion"] == {"const": contracts.RECORDS_SCHEMA_VERSION}, "receipt records schema differs")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["integrationSourcePathCount"] == {"const": len(contracts.INTEGRATION_SOURCE_PATHS)}, "receipt integration source count differs")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["integrationTestCount"] == {"const": len(contracts.INTEGRATION_TEST_METHODS)}, "receipt integration test count differs")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["integrationTestMethods"] == {"const": list(contracts.INTEGRATION_TEST_METHODS)}, "receipt integration test methods differ")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["integrationEventKinds"] == {"const": list(contracts.INTEGRATION_EVENT_KINDS)}, "receipt integration event kinds differ")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["integrationOrderingBasis"] == {"const": contracts.INTEGRATION_EVENT_ORDERING_BASIS}, "receipt integration ordering differs")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["integrationLifecycle"] == {"const": contracts.INTEGRATION_EVENT_LIFECYCLE}, "receipt integration lifecycle differs")
        require(values[contracts.SCHEMA_PATHS[5]]["properties"]["integrationReplayLimit"] == {"const": contracts.INTEGRATION_REPLAY_LIMIT}, "receipt integration replay limit differs")
    except (KeyError, TypeError, VerificationError, json.JSONDecodeError, OSError) as error:
        failures.append(f"schema:{error}")
    return failures


def check_documents(root: Path) -> list[str]:
    failures: list[str] = []
    for relative in contracts.CONTRACT_PATHS:
        try:
            value = load_json(root / relative)
            require(value.get("cardID") == contracts.CARD and value.get("attemptID") == contracts.ATTEMPT_ID, f"{relative}: identity differs")
            unsigned = dict(value)
            recorded = unsigned.pop("artifactDigest", object())
            if contracts.FINAL_HASHES_SEALED:
                require(isinstance(recorded, str), f"{relative}: artifact digest absent")
                require(recorded == digest(contracts.pretty(unsigned)), f"{relative}: artifact seal differs")
            else:
                require(recorded is None, f"{relative}: provisional digest must be null")
            require(value.get("persistentChangeMode") == contracts.PERSISTENCE["mode"], f"{relative}: persistence mode differs")
            require(value.get("persistentContractSchema") == "EVIDENCE_METADATA_V1_V43_RECORDS42", f"{relative}: persistence schema differs")
            require(value.get("finalHashesSealed") is contracts.FINAL_HASHES_SEALED, f"{relative}: final hash state differs")
            require(value.get("status") == ("SEALED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED"), f"{relative}: status differs")
            require(value.get("authority") == contracts.authority(), f"{relative}: authority differs")
            require(value.get("evidenceIDs") == list(contracts.EVIDENCE_IDS), f"{relative}: evidence IDs differ")
            require(value.get("lifecycleCoverage") == list(contracts.LIFECYCLE_DIMENSIONS), f"{relative}: lifecycle closure differs")
            require(value.get("statusFlags") == contracts.FLAGS, f"{relative}: status flags differ")
            semantics = value.get("semantics", {})
            replication = semantics.get("replication", {})
            require(replication.get("sourceTruth") == "ACCEPTED_MUTATION_RECEIPTS_AND_CHANGE_JOURNAL_V1", f"{relative}: replication source truth differs")
            require(replication.get("receipt", {}).get("postImageCount") == 2, f"{relative}: replication receipt post-image count differs")
            require(replication.get("receipt", {}).get("postImageKinds") == ["evidenceAssociationEvent", "evidenceSequenceRevision"], f"{relative}: replication receipt kinds differ")
            require(replication.get("journal", {}).get("entityChangeCount") == 2, f"{relative}: replication journal count differs")
            require(replication.get("events", {}).get("eventKinds") == list(contracts.INTEGRATION_EVENT_KINDS), f"{relative}: replication event kinds differ")
            require(replication.get("events", {}).get("orderingBasis") == contracts.INTEGRATION_EVENT_ORDERING_BASIS, f"{relative}: replication ordering differs")
            require(replication.get("events", {}).get("lifecycle") == contracts.INTEGRATION_EVENT_LIFECYCLE, f"{relative}: replication lifecycle differs")
            require(replication.get("projection", {}).get("maximumEventsPerReplay") == contracts.INTEGRATION_REPLAY_LIMIT, f"{relative}: replication replay limit differs")
            require(replication.get("consumer", {}).get("advanceAndRebuild") is True, f"{relative}: replication consumer closure differs")
            require(replication.get("checkpointStore", {}).get("canonicalTruth") is False, f"{relative}: replication checkpoint canonicality differs")
            require(replication.get("testMethods") == list(contracts.INTEGRATION_TEST_METHODS), f"{relative}: integration test set differs")
            if relative != contracts.CONTRACT_PATHS[4]:
                require(semantics.get("roles") == list(contracts.ROLE_VALUES), f"{relative}: role closure differs")
                require(semantics.get("policy", {}).get("maximumSequenceItems") == contracts.MAX_SEQUENCE_ITEMS, f"{relative}: policy sequence bound differs")
                require(semantics.get("policy", {}).get("maximumCaptionBytes") == contracts.MAX_CAPTION_BYTES, f"{relative}: caption bound differs")
                require(semantics.get("policy", {}).get("maximumAccessibilityDescriptionBytes") == contracts.MAX_ACCESSIBILITY_DESCRIPTION_BYTES, f"{relative}: description bound differs")
                require(semantics.get("sequenceCAS", {}).get("expectedRevisionPlusOne") is True, f"{relative}: sequence CAS differs")
                require(semantics.get("associationCAS", {}).get("mutationIDRequired") is True, f"{relative}: association CAS differs")
        except (KeyError, TypeError, VerificationError, json.JSONDecodeError, OSError) as error:
            failures.append(f"document:{error}")
    return failures


def check_manifest(root: Path, outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    try:
        raw = outputs[contracts.MANIFEST_PATH]
        manifest = json.loads(raw, object_pairs_hook=contracts._strict_pairs)
        require(isinstance(manifest, dict), "manifest is not an object")
        require(manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence differs")
        require(manifest.get("existingPaths") == list(contracts.EXISTING_PATHS), "manifest existing partition differs")
        require(manifest.get("newPaths") == list(contracts.NEW_PATHS), "manifest new partition differs")
        require(manifest.get("fencePathCount") == contracts.EXPECTED_FENCE_PATH_COUNT, "manifest fence count differs")
        require(manifest.get("existingPathCount") == contracts.EXPECTED_EXISTING_PATH_COUNT, "manifest existing count differs")
        require(manifest.get("newPathCount") == contracts.EXPECTED_NEW_PATH_COUNT, "manifest new count differs")
        require(manifest.get("manifestInputCount") == len(contracts.MANIFEST_INPUT_PATHS), "manifest input count differs")
        require(manifest.get("artifactCount") == len(contracts.MANIFEST_INPUT_PATHS), "manifest artifact count differs")
        rows = manifest.get("files")
        require(isinstance(rows, list) and len(rows) == len(contracts.MANIFEST_INPUT_PATHS), "manifest rows differ")
        require(all(row.get("path") != contracts.MANIFEST_PATH for row in rows), "manifest self included")
        expected_rows = []
        for path in contracts.MANIFEST_INPUT_PATHS:
            data = outputs[path] if path in outputs else (root / path).read_bytes()
            data = contracts.canonical_git_text(data)
            expected_rows.append({"path": path, "byteCount": len(data), "sha256": digest(data), "status": "SEALED_TOOLING" if contracts.FINAL_HASHES_SEALED and path in contracts.TOOLING_EDIT_PATHS else "SEALED_SOURCE" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_TOOLING" if path in contracts.TOOLING_EDIT_PATHS else "PROVISIONAL_SOURCE"})
        require(rows == expected_rows, "manifest byte/hash/status inventory differs")
        require(manifest.get("artifactSetDigest") == digest(contracts.canonical(expected_rows)), "manifest artifact-set digest differs")
        unsigned = dict(manifest)
        recorded = unsigned.pop("artifactDigest", object())
        if contracts.FINAL_HASHES_SEALED:
            require(isinstance(recorded, str), "manifest artifact digest absent")
            require(recorded == digest(contracts.pretty(unsigned)), "manifest artifact digest differs")
        else:
            require(recorded is None, "provisional manifest digest must be null")
        require(manifest.get("authorizedOverlapCount") == contracts.AUTHORIZED_OVERLAP_COUNT, "manifest authorized overlap differs")
        require(manifest.get("unauthorizedOverlapCount") == contracts.UNAUTHORIZED_OVERLAP_COUNT, "manifest unauthorized overlap differs")
        require(manifest.get("s10ReservationOverlapCount") == contracts.S10_RESERVATION_OVERLAP_COUNT, "manifest S10 overlap differs")
        source_projection = manifest.get("sourceProjection", {})
        require(source_projection.get("integrationSourcePaths") == list(contracts.INTEGRATION_SOURCE_PATHS), "manifest integration source paths differ")
        require(source_projection.get("integrationSourcePathCount") == len(contracts.INTEGRATION_SOURCE_PATHS), "manifest integration source count differs")
        require(source_projection.get("integrationTestMethods") == list(contracts.INTEGRATION_TEST_METHODS), "manifest integration test methods differ")
        require(source_projection.get("integrationTestCount") == len(contracts.INTEGRATION_TEST_METHODS), "manifest integration test count differs")
        require(source_projection.get("integrationEventKinds") == list(contracts.INTEGRATION_EVENT_KINDS), "manifest integration event kinds differ")
        require(source_projection.get("integrationOrderingBasis") == contracts.INTEGRATION_EVENT_ORDERING_BASIS, "manifest integration ordering differs")
        require(source_projection.get("integrationLifecycle") == contracts.INTEGRATION_EVENT_LIFECYCLE, "manifest integration lifecycle differs")
        require(source_projection.get("integrationReplayLimit") == contracts.INTEGRATION_REPLAY_LIMIT, "manifest integration replay limit differs")
        require(manifest.get("pendingArtifactCount") == 0, "manifest has pending inputs")
    except (KeyError, TypeError, VerificationError, json.JSONDecodeError, OSError) as error:
        failures.append(f"manifest:{error}")
    return failures


def fresh_outputs(root: Path) -> dict[str, bytes]:
    code = (
        "import base64,json,sys;sys.dont_write_bytecode=True;"
        "sys.path.insert(0,'Scripts/v23');import p03_c05_contracts as c;"
        "from pathlib import Path;"
        "print(json.dumps({k:base64.b64encode(v).decode('ascii') for k,v in c.all_outputs(Path('.')).items()},sort_keys=True))"
    )
    result = subprocess.run([sys.executable, "-B", "-c", code], cwd=root, check=True, capture_output=True, text=True, encoding="utf-8")
    value = json.loads(result.stdout)
    return {key: base64.b64decode(encoded) for key, encoded in value.items()}


def verify(root: Path, complete: bool) -> dict[str, Any]:
    failures: list[str] = []
    changed: set[str] = set()
    outputs: dict[str, bytes] = {}
    selectors: tuple[str, ...] = ()

    try:
        contracts.assert_scaffold(root)
    except Exception as error:
        failures.append(f"scaffold:{error}")
    try:
        for relative in contracts.SCRIPT_PATHS:
            ast.parse((root / relative).read_text(encoding="utf-8"), filename=relative)
    except Exception as error:
        failures.append(f"AST:{error}")
    try:
        selectors = contracts.assert_source_contracts(root)
    except Exception as error:
        failures.append(f"source:{error}")
    try:
        outputs = contracts.all_outputs(root)
    except Exception as error:
        failures.append(f"generation:{error}")

    try:
        changed = contracts.observed_changed_paths(root)
    except Exception as error:
        failures.append(f"change inventory:{error}")
    caches = cache_paths(root)
    missing = [path for path in contracts.PATH_FENCE if not (root / path).is_file()]
    if missing:
        failures.append("missing fenced paths:" + ",".join(missing))

    if outputs:
        for relative, expected in outputs.items():
            target = root / relative
            if not target.is_file() or target.read_bytes() != expected:
                failures.append("stale generated artifact:" + relative)
        failures.extend(check_manifest(root, outputs))
        failures.extend(check_schema_projection(root))
        failures.extend(check_documents(root))
    failures.extend(check_json_hygiene(root))
    if caches:
        failures.append("python cache:" + ",".join(caches))
    if any(value is not False and key != "requiresAcceptedS10_6Reconciliation" for key, value in contracts.FLAGS.items()):
        failures.append("activation/native/hosted/adoption/acceptance/release status flag")

    fenced_changed = changed & set(contracts.PATH_FENCE)
    new_changed = changed & set(contracts.NEW_PATHS)
    unowned = changed - set(contracts.PATH_FENCE)
    unchanged_existing = set(contracts.EXISTING_PATHS) - changed
    missing_new = set(contracts.NEW_PATHS) - changed
    if unowned:
        failures.append("unowned changed path:" + ",".join(sorted(unowned)))
    if complete:
        if missing_new:
            failures.append("missing changed new path:" + ",".join(sorted(missing_new)))
        if not contracts.FINAL_HASHES_SEALED:
            failures.append("final hashes are held provisional")
        if outputs:
            try:
                first = fresh_outputs(root)
                second = fresh_outputs(root)
                if first != second or first != outputs:
                    failures.append("fresh-process generation is nondeterministic")
            except Exception as error:
                failures.append(f"fresh-process generation:{error}")

    return {
        "cardID": contracts.CARD,
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL",
        "complete": complete,
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "fencePathCount": len(contracts.PATH_FENCE),
        "expectedExistingPathCount": contracts.EXPECTED_EXISTING_PATH_COUNT,
        "expectedNewPathCount": contracts.EXPECTED_NEW_PATH_COUNT,
        "expectedFencePathCount": contracts.EXPECTED_FENCE_PATH_COUNT,
        "changedPathCount": len(changed),
        "fencedChangedPathCount": len(fenced_changed),
        "newChangedPathCount": len(new_changed),
        "unchangedExistingPathCount": len(unchanged_existing),
        "missingNewPathCount": len(missing_new),
        "missingPathCount": len(missing),
        "unownedChangedPathCount": len(unowned),
        "pythonCachePathCount": len(caches),
        "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": contracts.S10_RESERVATION_OVERLAP_COUNT,
        "sourcePathCount": len(contracts.SOURCE_PATHS),
        "sourceReady": bool(selectors),
        "selectorCount": len(selectors),
        "selectorSuffixes": list(contracts.SELECTOR_SUFFIXES),
        "integrationSourcePathCount": len(contracts.INTEGRATION_SOURCE_PATHS),
        "integrationTestCount": len(contracts.INTEGRATION_TEST_METHODS),
        "integrationEventKindCount": len(contracts.INTEGRATION_EVENT_KINDS),
        "integrationReplayLimit": contracts.INTEGRATION_REPLAY_LIMIT,
        "persistentSchemaVersion": contracts.PERSISTENT_SCHEMA_VERSION,
        "recordsSchemaVersion": contracts.RECORDS_SCHEMA_VERSION,
        "activeModelCount": contracts.ACTIVE_MODEL_COUNT,
        "durableFamilyCount": contracts.DURABLE_FAMILY_COUNT,
        "flagsAllFalse": all(value is False for key, value in contracts.FLAGS.items() if key != "requiresAcceptedS10_6Reconciliation"),
        "requiresAcceptedS10_6Reconciliation": contracts.FLAGS["requiresAcceptedS10_6Reconciliation"],
        "finalHashesSealed": contracts.FINAL_HASHES_SEALED,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = verify(ROOT, args.complete)
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else result["result"])
    return 0 if not result["failures"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
