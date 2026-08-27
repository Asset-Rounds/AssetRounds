#!/usr/bin/env python3
"""Fail-closed exact-byte and reference audit for the portable validator lock."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urldefrag, urljoin

sys.dont_write_bytecode = True

import portable_contract_validator_v1 as portable


LOCKED_TOP_LEVEL_KEYS = {
    "schema", "schemaVersion", "tool", "officialMetaSchema", "files",
    "inventoryPolicy", "referencePolicy",
}
OWNED_PREFIXES = (
    "Scripts/v21-contracts/",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/",
)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise portable.PortableContractError(message)


def _owned_files(root: Path) -> set[str]:
    values: set[str] = set()
    scripts = root / "Scripts" / "v21-contracts"
    meta = root / "TestSupport" / "PortableContracts" / "JSONSchemaDraft202012"
    if scripts.is_dir():
        values.update(path.relative_to(root).as_posix() for path in scripts.rglob("*") if path.is_file())
    if meta.is_dir():
        values.update(path.relative_to(root).as_posix() for path in meta.rglob("*") if path.is_file())
    return values


def _walk_references(value: Any, base_uri: str, path: str = "") -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    if isinstance(value, dict):
        next_base = base_uri
        identifier = value.get("$id")
        if isinstance(identifier, str):
            next_base = urldefrag(urljoin(base_uri, identifier))[0]
        for keyword in ("$ref", "$dynamicRef"):
            if isinstance(value.get(keyword), str):
                rows.append((path + "/" + keyword.replace("~", "~0").replace("/", "~1"), next_base, value[keyword]))
        for key, child in value.items():
            token = key.replace("~", "~0").replace("/", "~1")
            rows.extend(_walk_references(child, next_base, path + "/" + token))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            rows.extend(_walk_references(child, base_uri, path + f"/{index}"))
    return rows


def verify_lock(root: Path) -> dict[str, Any]:
    lock_path = root / portable.LOCK_RELATIVE_PATH
    lock = portable.load_lock(root)
    _require(set(lock) == LOCKED_TOP_LEVEL_KEYS, "lock top-level field inventory differs")

    tool = lock["tool"]
    _require(isinstance(tool, dict), "lock tool is not an object")
    _require(tool == {
        "toolID": "ASSETROUNDS_PYTHON_JSON_SCHEMA_DRAFT_2020_12_V1",
        "implementationLanguage": "PYTHON_STDLIB",
        "minimumPython": "3.11",
        "stdlibOnly": True,
        "entryPoint": "Scripts/v21-contracts/run-portable-contracts.py",
        "lockChecker": "Scripts/v21-contracts/check-portable-contract-lock.py",
        "networkPolicy": "DENY_ALL",
    }, "lock tool identity differs")

    official = lock["officialMetaSchema"]
    _require(isinstance(official, dict), "officialMetaSchema is not an object")
    _require(set(official) == {"draft", "rootURI", "registry"}, "officialMetaSchema field inventory differs")
    _require(official["draft"] == "JSON_SCHEMA_DRAFT_2020_12", "official meta-schema draft differs")
    _require(official["rootURI"] == portable.DRAFT_ROOT_URI, "official meta-schema root URI differs")

    inventory = lock["inventoryPolicy"]
    _require(inventory == {
        "lockedFileCount": 11,
        "selfHashDisposition": "LOCK_FILE_EXCLUDED_TO_AVOID_RECURSION",
        "unexpectedOwnedFileDisposition": "REJECT",
        "lineEndingPolicy": "EXACT_BYTES",
    }, "inventory policy differs")

    rows = lock["files"]
    _require(isinstance(rows, list) and len(rows) == inventory["lockedFileCount"], "locked file count differs")
    expected_fields = {"path", "role", "byteCount", "sha256"}
    locked_paths: list[str] = []
    for row in rows:
        _require(isinstance(row, dict) and set(row) == expected_fields, "locked file row shape differs")
        relative = row["path"]
        _require(isinstance(relative, str) and relative.startswith(OWNED_PREFIXES), "locked path is outside owned roots")
        _require(".." not in Path(relative).parts and not Path(relative).is_absolute(), "locked path is not normalized relative")
        _require(relative not in locked_paths, f"duplicate locked path: {relative}")
        path = root / relative
        _require(path.is_file(), f"locked file is missing: {relative}")
        data = path.read_bytes()
        _require(row["byteCount"] == len(data), f"locked byte count differs: {relative}")
        _require(row["sha256"] == portable.sha256_bytes(data), f"locked SHA-256 differs: {relative}")
        locked_paths.append(relative)

    expected_owned = set(locked_paths) | {portable.LOCK_RELATIVE_PATH}
    observed_owned = _owned_files(root)
    _require(observed_owned == expected_owned, f"owned portable file inventory differs: {sorted(observed_owned ^ expected_owned)}")

    registry_rows = official["registry"]
    _require(isinstance(registry_rows, list) and len(registry_rows) == 8, "official registry count differs")
    registry_uris = [row.get("uri") for row in registry_rows if isinstance(row, dict)]
    registry_paths = [row.get("path") for row in registry_rows if isinstance(row, dict)]
    _require(len(registry_uris) == 8 and len(set(registry_uris)) == 8, "registry URI inventory differs")
    _require(len(registry_paths) == 8 and len(set(registry_paths)) == 8, "registry path inventory differs")
    locked_meta_paths = [row["path"] for row in rows if row["role"] == "OFFICIAL_META_SCHEMA"]
    _require(registry_paths == locked_meta_paths, "registry and locked meta-schema order differ")

    reference_policy = lock["referencePolicy"]
    _require(isinstance(reference_policy, dict), "reference policy is not an object")
    _require(set(reference_policy) == {"remoteResolution", "allowedAbsoluteURIs", "allowedRelativeReferencePrefixes"}, "reference policy field inventory differs")
    _require(reference_policy["remoteResolution"] == "FORBIDDEN", "remote resolution is not forbidden")
    _require(reference_policy["allowedAbsoluteURIs"] == registry_uris, "absolute URI allowlist differs from registry")
    _require(reference_policy["allowedRelativeReferencePrefixes"] == ["#", "meta/"], "relative reference allowlist differs")

    registry = portable.load_registry(root, lock)
    validator = portable.Draft202012Validator(registry, assert_formats=True)
    reference_count = 0
    for uri, relative in zip(registry_uris, registry_paths):
        document = registry[uri]
        _require(document.get("$schema") == portable.DRAFT_ROOT_URI, f"meta-schema dialect differs: {relative}")
        for pointer, base_uri, reference in _walk_references(document, uri):
            reference_count += 1
            _require(isinstance(reference, str), f"non-string reference: {relative}{pointer}")
            absolute_uri = urldefrag(urljoin(base_uri, reference))[0]
            if reference.startswith(("http://", "https://")):
                _require(absolute_uri in registry, f"absolute reference is outside vendored registry: {reference}")
            else:
                _require(reference.startswith(("#", "meta/")), f"relative reference prefix is forbidden: {reference}")
            try:
                validator._resolve(reference, base_uri, pointer.endswith("$dynamicRef"))
            except portable.PortableContractError as error:
                raise portable.PortableContractError(f"unresolved vendored reference {relative}{pointer}: {error}") from error

    forbidden_imports = (
        b"urllib" + b".request", b"http" + b".client", b"reque" + b"sts",
        b"sock" + b"et", b"urlopen" + b"(", b"curl" + b" ",
    )
    for relative in locked_paths:
        if relative.endswith(".py"):
            data = (root / relative).read_bytes()
            for marker in forbidden_imports:
                _require(marker not in data, f"network-capable marker in tool source: {relative}: {marker.decode()}")

    return {
        "schema": "PortableContractValidatorLockCheckV1",
        "schemaVersion": 1,
        "valid": True,
        "lockPath": portable.LOCK_RELATIVE_PATH,
        "lockSHA256": portable.sha256_bytes(lock_path.read_bytes()),
        "lockedFileCount": len(rows),
        "registryEntryCount": len(registry),
        "referenceCount": reference_count,
        "networkResolution": "FORBIDDEN",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)
    try:
        result = verify_lock(portable.repository_root(Path(__file__)))
    except portable.PortableContractError as error:
        result = {"schema": "PortableContractValidatorLockCheckV1", "schemaVersion": 1, "valid": False, "error": str(error)}
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
