#!/usr/bin/env python3
"""Hostile static verifier for V23-P01-C04 generated contracts."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from p01_c04_contracts import (
    ARCHIVE_ARTIFACT, ARCHIVE_SCHEMA, CARD, CORPUS_ARTIFACT, CORPUS_SCHEMA,
    FULL_FENCE, HOSTILE_CASES, LIMITS, MANIFEST, SOURCE_LIMIT_LITERALS,
    SOURCE_SPECS, TOOL_PATHS,
    ContractError, all_outputs, flags, pretty, sha,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_canonical(root: Path, path: str) -> dict[str, Any]:
    data = (root / path).read_bytes()
    value = json.loads(data)
    require(isinstance(value, dict), f"{path}: JSON root must be object")
    require(data == pretty(value), f"{path}: noncanonical JSON")
    return value


def verify_seal(value: dict[str, Any], path: str) -> None:
    digest = value.get("artifactDigest")
    payload = dict(value)
    payload.pop("artifactDigest", None)
    require(digest == sha(pretty(payload)), f"{path}: invalid artifactDigest")


def reject_unknown(value: dict[str, Any], allowed: set[str], path: str) -> None:
    extra = set(value) - allowed
    require(not extra, f"{path}: unknown keys {sorted(extra)}")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        expected = all_outputs(root)
        for path, data in expected.items():
            require((root / path).is_file(), f"missing generated artifact: {path}")
            require((root / path).read_bytes() == data, f"stale generated artifact: {path}")

        archive = load_canonical(root, ARCHIVE_ARTIFACT)
        corpus = load_canonical(root, CORPUS_ARTIFACT)
        manifest = load_canonical(root, MANIFEST)
        archive_schema = load_canonical(root, ARCHIVE_SCHEMA)
        corpus_schema = load_canonical(root, CORPUS_SCHEMA)
        for value, path in ((archive, ARCHIVE_ARTIFACT), (corpus, CORPUS_ARTIFACT), (manifest, MANIFEST)):
            verify_seal(value, path)
            require(value.get("cardID") == CARD, f"{path}: wrong card")
            for key, expected_flag in flags().items():
                require(value.get(key) is expected_flag, f"{path}: unsafe {key}")

        require(FULL_FENCE == [path for path, _ in SOURCE_SPECS] + TOOL_PATHS, "exact 15-path fence ordering")
        require(len(FULL_FENCE) == len(set(FULL_FENCE)) == 15, "exact 15-path fence")
        require(manifest.get("fullCardFence") == FULL_FENCE, "manifest fence drift")
        require(manifest.get("pathFence") == TOOL_PATHS and manifest.get("toolingPathCount") == 8, "tool fence drift")
        require(archive.get("fullCardFence") == FULL_FENCE, "archive fence drift")
        require(archive.get("limits") == corpus.get("limits") == LIMITS, "limits drift")
        contracts_source = (root / SOURCE_SPECS[0][0]).read_text(encoding="utf-8")
        require(all(literal in contracts_source for literal in SOURCE_LIMIT_LITERALS), "source limit declarations drift")
        require(archive["versionDispatch"] == {"streamingFormat": "ASRBA1", "streamingFormatVersion": 1, "portablePackageVersion": 4, "legacyV4ReaderRetained": True, "unknownVersionDisposition": "FAIL_CLOSED", "wholeArchiveMemoryLoading": False}, "version dispatch weakened")
        require(archive["determinism"]["repeatExportByteIdentical"] is True, "determinism weakened")
        require(archive["lifecycle"]["mode"] == "CONTENT_ONLY", "lifecycle mode drift")
        require(archive["lifecycle"]["recovery"] == "INVALIDATE_STREAMING_WRITER_RETAIN_VERIFIED_V4_READER_EXPORT", "recovery weakened")

        hostile_ids = [item["id"] for item in archive["hostileCases"]]
        require(hostile_ids == [item[0] for item in HOSTILE_CASES], "hostile matrix drift")
        require(len(hostile_ids) == len(set(hostile_ids)), "duplicate hostile IDs")
        corpus_ids = [item["id"] for item in corpus["cases"]]
        require(set(hostile_ids).issubset(corpus_ids), "corpus omits hostile case")
        require({"VALID_STREAMING_DETERMINISTIC_REPEAT", "VALID_V4_LEGACY_DISPATCH", "BOUNDED_MAXIMUM_FIXTURE", "WRITER_INVALIDATION_READER_RETENTION"}.issubset(corpus_ids), "corpus omits acceptance class")
        require(len(corpus_ids) == len(set(corpus_ids)), "duplicate corpus IDs")
        require(corpus["coverage"]["caseCount"] == len(corpus_ids), "corpus count mismatch")
        require(all(corpus["coverage"][key] is True for key in ("allLimitDimensionsCovered", "allPathClassesCovered", "legacyV4Covered", "deterministicRepeatCovered")), "corpus coverage weakened")

        bindings = archive["sourceBindings"]
        require([row["path"] for row in bindings] == [path for path, _ in SOURCE_SPECS], "source binding order drift")
        for row, (path, symbols) in zip(bindings, SOURCE_SPECS):
            data = (root / path).read_bytes()
            text = data.decode("utf-8")
            require(row["sha256"] == sha(data) and row["bytes"] == len(data), f"{path}: source binding digest drift")
            require(row["requiredSymbols"] == symbols and all(symbol in text for symbol in symbols), f"{path}: source symbol drift")
        fixture = (root / SOURCE_SPECS[-1][0]).read_bytes()
        require(corpus["fixtureBinding"] == {"path": SOURCE_SPECS[-1][0], "bytes": len(fixture), "sha256": sha(fixture)}, "fixture binding drift")
        fixture_value = json.loads(fixture)
        require(fixture_value.get("schemaVersion") == 1 and fixture_value.get("authority") == "V21-P01-C04", "fixture authority drift")
        require(fixture_value.get("limits") == LIMITS, "fixture limits differ from source contract")
        fixture_cases = fixture_value.get("cases")
        require(isinstance(fixture_cases, list) and fixture_cases, "fixture cases missing")
        fixture_ids = [row.get("id") for row in fixture_cases]
        require(len(fixture_ids) == len(set(fixture_ids)), "fixture case IDs duplicate")
        require({row.get("family") for row in fixture_cases} == {"G01", "A01", "H01", "I01", "R01"}, "fixture evidence families incomplete")
        require(all(row.get("expected") in {"accept", "reject", "cancel", "recover"} for row in fixture_cases), "fixture expected outcome is open")

        rows = manifest["artifacts"]
        require([row["path"] for row in rows] == TOOL_PATHS[:-1], "manifest artifact order drift")
        for row in rows:
            data = (root / row["path"]).read_bytes()
            require(row["bytes"] == len(data) and row["sha256"] == sha(data), f"{row['path']}: manifest digest drift")
        require(manifest["artifactSetDigest"] == sha(pretty(rows)), "artifact-set digest drift")
        require(manifest["artifactCount"] == 7 and manifest["sourceBindingCount"] == 7 and manifest["sourceBindingComplete"] is True, "manifest counts drift")

        reject_unknown(archive, {"schema", "schemaVersion", "cardID", "authority", "limits", "versionDispatch", "pathPolicy", "determinism", "lifecycle", "sourceBindings", "hostileCases", "fullCardFence", *flags().keys(), "artifactDigest"}, ARCHIVE_ARTIFACT)
        reject_unknown(corpus, {"schema", "schemaVersion", "cardID", "authority", "fixtureBinding", "limits", "cases", "coverage", *flags().keys(), "artifactDigest"}, CORPUS_ARTIFACT)
        require(archive_schema["properties"]["fullCardFence"]["minItems"] == 15, "archive schema fence weakened")
        require(corpus_schema["properties"]["cases"]["minItems"] == len(HOSTILE_CASES) + 4, "corpus schema weakened")
    except (ContractError, OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        print(f"V23-P01-C04 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P01-C04 static contracts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
