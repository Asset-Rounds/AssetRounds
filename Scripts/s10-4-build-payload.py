#!/usr/bin/env python3
"""Finite H411 exact-head shared payload protocol. No build or test execution.

The relocatable product-tree kernel is extracted from the existing S10.4 worker.
API and native qualification validation are a separate typed H411 contract;
old diagnostic/pilot receipts are never promoted.
"""
import argparse
import datetime as dt
import io
import math
import shlex
import shutil
import struct
import urllib.parse
import urllib.request
import zipfile
import hashlib

class PayloadError(ValueError):
    pass
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT_LABEL = "FieldEvidenceDerivedData/Build/Products"
ALLOWED_MACROS = {"__TESTROOT__", "__PLATFORMS__", "__TESTHOST__", "__TESTBUNDLE__"}
PILOT_UNIT_SOURCE_PARTS = ("FieldEvidenceAppTests", "S10_4AutomatedBrandLabTests.swift")
PILOT_UNIT_SOURCE_PATH = "/".join(PILOT_UNIT_SOURCE_PARTS)
CANONICAL_SYSTEM_DYLD_PAIRS = frozenset({
    (
        ("FieldEvidenceAppTests", "EnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "/usr/lib/libRPAC.dylib",
    ),
    (
        ("FieldEvidenceAppTests", "TestingEnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "__TESTHOST__/Frameworks/libXCTestBundleInject.dylib:__SIMRUNTIMEROOT__/usr/lib/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib",
    ),
    (
        ("FieldEvidenceAppUITests", "EnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "/usr/lib/libRPAC.dylib",
    ),
    (
        ("FieldEvidenceAppUITests", "TestingEnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "__SIMRUNTIMEROOT__/usr/lib/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib",
    ),
})

def fail(message):
    raise PayloadError(message)

def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()

def require_checkout_head(value):
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{40}", value) is None:
        fail("malformed checkout head")
    return value

def require_checkout_sha256(value):
    if not isinstance(value, str) or re.fullmatch(r"[0-9A-F]{64}", value) is None:
        fail("malformed checkout source digest")
    return value

def checkout_directory(path):
    try:
        mode = os.lstat(path).st_mode
    except OSError:
        fail("unsafe checkout directory")
    if not stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
        fail("unsafe checkout directory")

def validate_checkout_root(root_text):
    if not isinstance(root_text, str) or not root_text:
        fail("unsafe checkout root")
    if any(ord(character) < 32 or ord(character) == 127 for character in root_text):
        fail("unsafe checkout root")
    if not os.path.isabs(root_text) or os.path.normpath(root_text) != root_text:
        fail("unsafe checkout root")
    try:
        physical_root = os.path.realpath(root_text)
    except OSError:
        fail("unsafe checkout root")
    if physical_root != root_text:
        fail("unsafe checkout root")
    root = Path(root_text)
    checkout_directory(root)
    return root

def run_checkout_git(root, arguments, capture=False):
    try:
        result = subprocess.run(
            ["git", "-C", os.fspath(root), *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            shell=False,
            text=capture,
            encoding="ascii" if capture else None,
            errors="strict" if capture else None,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError, UnicodeError):
        fail("checkout git verification failed")
    return result

def validate_checkout_source(root_text, expected_head, expected_sha256=None):
    root = validate_checkout_root(root_text)
    expected_head = require_checkout_head(expected_head)
    if expected_sha256 is not None:
        expected_sha256 = require_checkout_sha256(expected_sha256)
    source_directory = root
    for component in PILOT_UNIT_SOURCE_PARTS[:-1]:
        source_directory = source_directory / component
        checkout_directory(source_directory)
    source_path = source_directory / PILOT_UNIT_SOURCE_PARTS[-1]
    try:
        source_mode = os.lstat(source_path).st_mode
    except OSError:
        fail("unsafe checkout source")
    if not stat.S_ISREG(source_mode) or stat.S_ISLNK(source_mode):
        fail("unsafe checkout source")
    head_result = run_checkout_git(root, ["rev-parse", "--verify", "HEAD"], capture=True)
    if head_result.returncode != 0 or head_result.stdout.strip() != expected_head:
        fail("checkout head mismatch")
    tracked_result = run_checkout_git(
        root, ["ls-files", "--error-unmatch", "--", PILOT_UNIT_SOURCE_PATH]
    )
    if tracked_result.returncode != 0:
        fail("checkout source is not tracked")
    clean_result = run_checkout_git(
        root, ["diff", "--quiet", "--exit-code", expected_head, "--", PILOT_UNIT_SOURCE_PATH]
    )
    if clean_result.returncode != 0:
        fail("checkout source is not clean")
    try:
        source_sha256 = sha256_file(source_path)
    except OSError:
        fail("checkout source unreadable")
    if expected_sha256 is not None and source_sha256 != expected_sha256:
        fail("checkout source digest mismatch")
    return source_sha256

def strict_pairs(pairs):
    output = {}
    for key, value in pairs:
        if key in output:
            fail("duplicate JSON key: " + key)
        output[key] = value
    return output

def read_json(path):
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream, object_pairs_hook=strict_pairs, parse_constant=lambda value: fail("nonfinite JSON"))
    except (OSError, ValueError, UnicodeError) as error:
        fail(f"invalid JSON {path}: {error}")

def regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except OSError:
        return False

def real_directory(path):
    try:
        mode = os.lstat(path).st_mode
    except OSError as error:
        fail(f"missing directory {path}: {error}")
    if not stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
        fail("unsafe directory ancestor: " + str(path))

def require_product_ancestors(products):
    payload_root = products.parents[2]
    real_directory(payload_root)
    real_directory(payload_root / "FieldEvidenceDerivedData")
    real_directory(payload_root / "FieldEvidenceDerivedData" / "Build")
    real_directory(products)

def safe_relative(relative):
    if not relative or relative.startswith("/") or "\\" in relative or ":" in relative:
        fail("unsafe relative member path")
    if any(part in ("", ".", "..") for part in relative.split("/")):
        fail("unsafe relative member component")
    if any(char in relative for char in ("\x00", "\n", "\r")):
        fail("unsafe relative member character")

def read_xctestrun(path):
    try:
        with path.open("rb") as stream:
            return plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        fail("invalid xctestrun type=" + type(error).__name__)

def xctestrun_strings(value, field_path=()):
    if isinstance(value, str):
        yield field_path, value
    elif isinstance(value, dict):
        for key in sorted(value, key=str):
            yield from xctestrun_strings(value[key], field_path + (str(key),))
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            yield from xctestrun_strings(nested, field_path + (str(index),))

def normalize_xctestrun(root, source_root):
    xctestruns = []
    for directory, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        for name in files:
            path = Path(directory) / name
            if name.endswith(".xctestrun") and regular_file(path):
                xctestruns.append(path)
    if len(xctestruns) != 1:
        fail("expected exactly one regular .xctestrun before normalization")
    source_text = str(source_root)
    if not source_root.is_absolute() or not source_text.endswith("/Build/Products"):
        fail("invalid source products root")
    payload = read_xctestrun(xctestruns[0])
    source_occurrence_count = sum(
        text.count(source_text) for _, text in xctestrun_strings(payload)
    )
    original_testroot_count = sum(
        text.count("__TESTROOT__") for _, text in xctestrun_strings(payload)
    )
    replacement_count = 0

    def replace_source_root(text):
        nonlocal replacement_count
        output = []
        cursor = 0
        while True:
            index = text.find(source_text, cursor)
            if index < 0:
                output.append(text[cursor:])
                break
            end = index + len(source_text)
            before_is_boundary = index == 0 or text[index - 1] in "=:"
            after_is_boundary = end == len(text) or text[end] == "/"
            if not before_is_boundary or not after_is_boundary:
                fail("noncanonical source products root occurrence")
            output.append(text[cursor:index])
            output.append("__TESTROOT__")
            replacement_count += 1
            cursor = end
        rewritten = "".join(output)
        if source_text in rewritten:
            fail("incomplete source products root normalization")
        return rewritten

    def rewrite(value):
        if isinstance(value, str):
            return replace_source_root(value)
        if isinstance(value, dict):
            return {key: rewrite(nested) for key, nested in value.items()}
        elif isinstance(value, list):
            return [rewrite(nested) for nested in value]
        return value

    normalized = rewrite(payload)
    if replacement_count != source_occurrence_count:
        fail("xctestrun source products root was not bound")
    normalized_testroot_count = sum(
        text.count("__TESTROOT__") for _, text in xctestrun_strings(normalized)
    )
    if normalized_testroot_count != original_testroot_count + replacement_count:
        fail("xctestrun normalization count mismatch")
    temporary = xctestruns[0].with_name(xctestruns[0].name + ".normalized")
    if temporary.exists() or temporary.is_symlink():
        fail("xctestrun normalization temporary path exists")
    try:
        with temporary.open("wb") as stream:
            plistlib.dump(normalized, stream, fmt=plistlib.FMT_XML, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, stat.S_IMODE(os.lstat(xctestruns[0]).st_mode))
        os.replace(temporary, xctestruns[0])
    finally:
        if temporary.exists() or temporary.is_symlink():
            temporary.unlink()

def value_classification(text):
    runner_temp = os.environ.get("RUNNER_TEMP", "")
    workspace = os.environ.get("GITHUB_WORKSPACE", "")
    developer_dir = os.environ.get("DEVELOPER_DIR", "")
    if runner_temp and runner_temp in text:
        return "runner-temp"
    if workspace and workspace in text:
        return "workspace"
    if developer_dir and developer_dir in text:
        return "developer-dir"
    if text.startswith(("/Applications/", "/Library/", "/System/", "/usr/")):
        return "system"
    if "file:" in text:
        return "file-url"
    return "other"

def redacted_components(parts):
    component_count = len(parts)
    displayed = parts[:16]
    return {
        "componentCount": component_count,
        "components": [
            {
                "bytes": len(component.encode("utf-8")),
                "class": value_classification(component),
                "sha256": hashlib.sha256(component.encode("utf-8")).hexdigest().upper(),
            }
            for component in displayed
        ],
        "truncated": component_count > len(displayed),
    }

def validate_xctestrun(path, producer_root):
    payload = read_xctestrun(path)
    producer_text = str(producer_root)
    violations = []
    for field_path, text in xctestrun_strings(payload):
        text_bytes = text.encode("utf-8")
        field_bytes = "/".join(field_path).encode("utf-8")
        kinds = {}
        if producer_text in text:
            kinds["producer-specific-xctestrun-path"] = 1
        is_canonical_system_dyld = (field_path, text) in CANONICAL_SYSTEM_DYLD_PAIRS
        if re.search(r"(?:^|[=:])(?:/|~|file:)", text) and not is_canonical_system_dyld:
            kinds["absolute-xctestrun-path"] = 1
        if "/../" in text or text.startswith("../"):
            kinds["traversing-xctestrun-path"] = 1
        if "$" in text:
            kinds["unresolved-xctestrun-macro"] = 1
        unknown_macro_count = sum(
            1 for macro in re.findall(r"__[A-Za-z0-9_]+__", text)
            if macro not in ALLOWED_MACROS and not (
                is_canonical_system_dyld and macro == "__SIMRUNTIMEROOT__"
            )
        )
        if unknown_macro_count:
            kinds["unknown-xctestrun-macro"] = unknown_macro_count
        if kinds:
            field_components = redacted_components(list(field_path))
            value_components = redacted_components(text.split(":"))
            for component in field_components["components"]:
                component.pop("class")
            violations.append({
                "field": {
                    "componentCount": field_components["componentCount"],
                    "components": field_components["components"],
                    "depth": len(field_path),
                    "sha256": hashlib.sha256(field_bytes).hexdigest().upper(),
                    "truncated": field_components["truncated"],
                },
                "kinds": kinds,
                "value": {
                    "bytes": len(text_bytes),
                    "class": value_classification(text),
                    "componentCount": value_components["componentCount"],
                    "components": value_components["components"],
                    "sha256": hashlib.sha256(text_bytes).hexdigest().upper(),
                    "truncated": value_components["truncated"],
                },
            })
    if violations:
        violations.sort(key=lambda item: (
            item["field"]["sha256"], item["value"]["sha256"],
            tuple(sorted(item["kinds"].items())),
        ))
        displayed = violations[:64]
        diagnostic = {
            "recordCount": len(violations),
            "truncated": len(violations) > len(displayed),
            "violationCount": sum(sum(item["kinds"].values()) for item in violations),
            "violations": displayed,
        }
        fail("xctestrun residual violations " + json.dumps(
            diagnostic, sort_keys=True, separators=(",", ":")
        ))

def collect(root):
    require_product_ancestors(root)
    try:
        root_mode = os.lstat(root).st_mode
    except OSError as error:
        fail(f"missing product tree: {error}")
    if not stat.S_ISDIR(root_mode) or stat.S_ISLNK(root_mode):
        fail("product root is not a real directory")
    entries = []
    folded = set()
    xctestruns = []
    for directory, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories + files:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            safe_relative(relative)
            folded_relative = relative.casefold()
            if folded_relative in folded:
                fail("case-colliding product member: " + relative)
            folded.add(folded_relative)
            mode = os.lstat(path).st_mode
            if stat.S_ISLNK(mode):
                fail("symlink product member: " + relative)
            if stat.S_ISDIR(mode):
                entries.append({
                    "mode": stat.S_IMODE(mode),
                    "path": relative,
                    "type": "directory",
                })
            elif stat.S_ISREG(mode):
                digest = sha256_file(path)
                entries.append({
                    "mode": stat.S_IMODE(mode),
                    "path": relative,
                    "sha256": digest,
                    "size": os.lstat(path).st_size,
                    "type": "file",
                })
                if relative.endswith(".xctestrun"):
                    xctestruns.append((relative, path))
            else:
                fail("nonregular product member: " + relative)
    entries.sort(key=lambda entry: entry["path"])
    if len(xctestruns) != 1:
        fail("expected exactly one regular .xctestrun")
    validate_xctestrun(xctestruns[0][1], root)
    return entries, xctestruns[0][0]

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


# H411 uses a distinct immutable schema; historical pilot/diagnostic records fail it.
CONTRACT = "s10.4.shared-build.v1"
REPOSITORY = "Asset-Rounds/AssetRounds"
PHASE_REF = "refs/heads/phase/s10-brand-refresh"
WORKFLOW = ".github/workflows/ios-ci.yml"
RETENTION_SECONDS = 14 * 86400
DIAGNOSTIC_SECONDS = 86400
MAX_ARCHIVE_BYTES = 2 * 1024**3
MAX_MEMBERS = 100000
MAX_JSON_BYTES = 4 * 1024**2
TOOLCHAIN = {"xcodeVersion": "Xcode 26.6", "xcodeBuild": "17F113",
             "sdkName": "iphonesimulator26.5", "sdkBuild": "23F81a",
             "architecture": "arm64", "project": "FieldEvidenceApp.xcodeproj",
             "scheme": "FieldEvidenceApp", "configuration": "Debug"}
CURRENT_DEVICE = {"deviceProfileID": "iphone-17-ios-26.2-current",
                  "simulatorName": "iPhone 17", "simulatorRuntime": "iOS 26.2",
                  "simulatorRuntimeBuild": "23C54"}
MINIMUM_DEVICE = {"deviceProfileID": "iphone-se-3-ios-18.0-minimum",
                  "simulatorName": "iPhone SE (3rd generation)",
                  "simulatorRuntime": "iOS 18.0", "simulatorRuntimeBuild": "22A3351"}
METHODS = (
    "testFrozenBrandPaletteProvidesExactOpaqueNormalAndIncreasedContrastTruth",
    "testFrozenInventoryDerivesExactUnpromotedVisualAndAccessibilityMatrices",
    "testMigratedProductAndTokenCoverageRemainBoundToFrozenInventory",
    "testMinimumOSCameraDeniedLegacyTabCorrectionIsNarrowAndDiagnosticFree",
    "testPinnedOverlaySelectorAndExactSevenPlusSevenShardContract",
)
TEST_CLASS = "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests"
UNIT_IDS = tuple(TEST_CLASS + "/" + method for method in METHODS)
SHARD_NAMES = (
    "s10.4.current.default-light", "s10.4.current.default-dark",
    "s10.4.current.increased-contrast", "s10.4.current.ax-text",
    "s10.4.current.differentiate-without-color", "s10.4.current.reduce-motion",
    "s10.4.current.reduce-transparency", "s10.4.minimum.minimum-os",
    "s10.4.minimum.double-length", "s10.4.minimum.rtl", "s10.4.minimum.rtl-string",
    "s10.4.minimum.tall", "s10.4.minimum.accented", "s10.4.minimum.bounded",
)
SOURCE_PATHS = (
    WORKFLOW, ".github/workflows/ios-ci-worker.yml", "Scripts/s10-4-build-payload.py",
    "Scripts/ci-selection.json", "Scripts/s10-4-shards.json", "Scripts/s10-4-segment-plan.json",
    "Scripts/build-smoke.sh", "Scripts/test-smoke.sh", "Scripts/ui-smoke.sh",
    "Scripts/s10-4-segment-assembler.sh", PILOT_UNIT_SOURCE_PATH,
    "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift",
    "docs/execution/CURRENT_TASK.md", "docs/execution/S10_4_CI_OPERATING_BRIEF.md",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json",
)
PRODUCER_STEPS = (
    "Check out the exact revision", "Validate task selection and timeout tier",
    "Verify pinned toolchain, shared scheme, and simulator", "Build unsigned simulator app",
    "Prepare S10.4 shared build payload", "Run targeted tests",
    "Qualify S10.4 shared build payload", "Upload S10.4 shared build payload",
    "Upload S10.4 shared unit evidence", "Seal S10.4 shared build provenance",
    "Upload S10.4 shared build seal",
)
PRODUCER_FIELDS = {"runID", "runAttempt", "jobID", "runnerProvider", "runnerName", "simulatorUDID"}
CONSUMER_FIELDS = {"runID", "runAttempt", "jobID", "runnerProvider", "runnerName", "shardID",
                   "segmentID", "purpose", "toolchain", "simulatorUDID", "simulatorName",
                   "simulatorRuntime", "simulatorRuntimeBuild", "isolationID"}


def require(condition, message):
    if not condition:
        fail(message)


def exact_keys(value, fields, message="unexpected object fields"):
    require(type(value) is dict and set(value) == set(fields), message)


def positive(value):
    require(type(value) is int and 0 < value < 2**64, "positive integer required")
    return value


def decimal_id(value):
    require(type(value) is str and re.fullmatch(r"[1-9][0-9]{0,19}", value), "canonical positive run ID required")
    return positive(int(value))


def hash_value(value):
    require(type(value) is str and re.fullmatch(r"[0-9A-F]{64}", value), "uppercase SHA256 required")
    return value


def uuid_value(value):
    require(type(value) is str and re.fullmatch(r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}", value), "canonical UUID required")
    return value


def timestamp(value):
    require(type(value) is str and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value), "UTC timestamp required")
    try:
        return int(dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc).timestamp())
    except ValueError:
        fail("invalid UTC timestamp")


def now_epoch():
    return int(dt.datetime.now(dt.timezone.utc).timestamp())


def utc(value):
    return dt.datetime.fromtimestamp(value, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def canonical_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False, ensure_ascii=True).encode("utf-8")


def object_sha(value):
    return hashlib.sha256(canonical_bytes(value)).hexdigest().upper()


def decode_bytes(raw):
    require(len(raw) <= MAX_JSON_BYTES, "JSON exceeds bound")
    try:
        return json.loads(raw, object_pairs_hook=strict_pairs, parse_constant=lambda value: fail("nonfinite JSON"))
    except (UnicodeError, ValueError) as error:
        fail("invalid JSON: " + type(error).__name__)


def load(path):
    require(regular_file(path) and path.stat().st_size <= MAX_JSON_BYTES, "unsafe/oversized JSON file")
    return decode_bytes(path.read_bytes())


def save(path, value):
    require(not path.exists() and not path.is_symlink(), "refuse evidence overwrite")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_bytes(value) + b"\n")


def new_directory(path):
    require(path.is_absolute() and not path.exists() and not path.is_symlink(), "output must be a new absolute directory")
    require(path.parent.exists() and path.parent.resolve() == path.parent, "unsafe output ancestor")
    path.mkdir(mode=0o700)
    return path


def checked_path(text):
    require(type(text) is str and text and Path(text).is_absolute(), "absolute local path required")
    path = Path(text)
    require(path.resolve() == path and not path.is_symlink(), "symlink/noncanonical local path")
    return path


def inventory(root):
    real_directory(root)
    require(root.resolve() == root, "unsafe tree ancestor")
    entries = []
    folded = set()
    total = 0
    for directory, directories, files in os.walk(root, followlinks=False):
        directories.sort(); files.sort()
        for name in directories + files:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            safe_relative(relative)
            require(relative.casefold() not in folded, "case collision")
            folded.add(relative.casefold())
            mode = os.lstat(path).st_mode
            require(not stat.S_ISLNK(mode), "symlink tree member")
            require(not stat.S_IMODE(mode) & 0o7000, "special permission tree member")
            entry = {"path": relative, "mode": stat.S_IMODE(mode)}
            if stat.S_ISDIR(mode):
                entry["type"] = "directory"
            elif stat.S_ISREG(mode):
                size = os.lstat(path).st_size
                total += size
                require(total <= MAX_ARCHIVE_BYTES, "tree exceeds byte bound")
                entry.update(type="file", size=size, sha256=sha256_file(path))
            else:
                fail("nonregular tree member")
            entries.append(entry)
            require(len(entries) <= MAX_MEMBERS, "tree exceeds member bound")
    return sorted(entries, key=lambda entry: entry["path"])


def copy_tree(source, destination):
    before = inventory(source)
    require(not destination.exists() and not destination.is_symlink(), "copy destination exists")
    shutil.copytree(source, destination, copy_function=shutil.copy2)
    require(inventory(destination) == before and inventory(source) == before, "copy changed source/closure")
    return before


def evidence_identity(root):
    # GitHub artifact ZIP transport normalizes permission bits. Native originals
    # bind names, types, sizes and bytes; executable product modes remain in TAR.
    return object_sha([{k: v for k, v in entry.items() if k != "mode"} for entry in inventory(root)])


def checksum_manifest(root):
    entries = inventory(root)
    lines = [entry["sha256"] + "  " + entry["path"] for entry in entries
             if entry["type"] == "file" and entry["path"] != "SHA256SUMS.txt"]
    return ("\n".join(lines) + "\n").encode("utf-8")


def write_checksums(root):
    path = root / "SHA256SUMS.txt"
    require(not path.exists() and not path.is_symlink(), "checksum manifest already exists")
    path.write_bytes(checksum_manifest(root))


def verify_checksums(root):
    path = root / "SHA256SUMS.txt"
    require(regular_file(path) and path.read_bytes() == checksum_manifest(root), "complete original checksum closure mismatch")


def source_identity(root, head, require_environment=True):
    require_checkout_head(head)
    root = validate_checkout_root(str(root))
    if require_environment:
        require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY and
                os.environ.get("GITHUB_REF") == PHASE_REF and os.environ.get("GITHUB_SHA") == head,
                "execution environment source mismatch")
    result = run_checkout_git(root, ["rev-parse", "--verify", "HEAD"], True)
    require(result.returncode == 0 and result.stdout.strip() == head, "physical checkout head mismatch")
    require(run_checkout_git(root, ["diff", "--quiet", "--exit-code", head, "--"]).returncode == 0, "dirty tracked checkout")
    tree = run_checkout_git(root, ["rev-parse", "HEAD^{tree}"], True)
    require(tree.returncode == 0 and re.fullmatch(r"[0-9a-f]{40}", tree.stdout.strip()), "missing exact Git tree")
    files = {}
    for relative in SOURCE_PATHS:
        path = root / relative
        require(path.resolve().is_relative_to(root) and regular_file(path), "unsafe source binding")
        require(run_checkout_git(root, ["ls-files", "--error-unmatch", "--", relative]).returncode == 0, "untracked source binding")
        files[relative] = sha256_file(path)
    declared = re.findall(r"^    func (test\w+)\(", (root / PILOT_UNIT_SOURCE_PATH).read_text(encoding="utf-8"), re.M)
    require(len(declared) == 5 and set(declared) == set(METHODS), "native method contract changed")
    shard_contract(root)
    return {"head": head, "gitTree": tree.stdout.strip(), "files": files}


def shard_contract(root):
    contract = load(root / "Scripts/s10-4-shards.json")
    require(contract.get("schemaVersion") == 1 and contract.get("taskID") == "S10.4" and
            contract.get("expectedStateCount") == 67 and contract.get("expectedVisualCellCount") == 938 and
            contract.get("expectedAccessibilityRowCount") == 84 and contract.get("commonTaskCount") == 6,
            "wrong frozen shard coverage")
    shards = contract.get("shards")
    require(type(shards) is list and len(shards) == 14 and
            [x.get("shardID") for x in shards] == list(SHARD_NAMES) and
            [x.get("ordinal") for x in shards] == list(range(1, 15)), "closed fourteen-shard identity mismatch")
    profiles = contract.get("deviceProfiles")
    require(type(profiles) is list and len(profiles) == 2, "wrong device profiles")
    for expected in [CURRENT_DEVICE, MINIMUM_DEVICE]:
        found = [x for x in profiles if x.get("deviceProfileID") == expected["deviceProfileID"]]
        require(len(found) == 1 and all(found[0].get(k) == v for k, v in expected.items()), "pinned runtime mismatch")
    for index, shard in enumerate(shards):
        expected = CURRENT_DEVICE if index < 7 else MINIMUM_DEVICE
        require(shard.get("deviceProfileID") == expected["deviceProfileID"], "shard runtime substitution")
    return contract


def producer_identity(value):
    exact_keys(value, PRODUCER_FIELDS)
    for key in ["runID", "runAttempt", "jobID"]:
        positive(value[key])
    require(value["runnerProvider"] == "bitrise" and type(value["runnerName"]) is str and value["runnerName"], "unapproved shared producer")
    uuid_value(value["simulatorUDID"])
    return value


def consumer_identity(value, root):
    exact_keys(value, CONSUMER_FIELDS)
    for key in ["runID", "runAttempt", "jobID"]:
        positive(value[key])
    require(value["purpose"] in ["acceptance", "diagnostic"], "unknown consumer purpose")
    # Formal Bitrise UI continues through its existing two-shard equivalence route;
    # this initial shared-consumer implementation cannot bypass that gate.
    require(value["runnerProvider"] == "github", "shared consumer provider not admitted; existing Bitrise gate unchanged")
    require(value["toolchain"] == TOOLCHAIN and type(value["runnerName"]) is str and value["runnerName"], "consumer toolchain mismatch")
    uuid_value(value["simulatorUDID"]); uuid_value(value["isolationID"])
    contract = shard_contract(root)
    found = [x for x in contract["shards"] if x["shardID"] == value["shardID"]]
    require(len(found) == 1, "unknown consumer shard")
    device = CURRENT_DEVICE if found[0]["ordinal"] <= 7 else MINIMUM_DEVICE
    require(all(value[k] == device[k] for k in ["simulatorName", "simulatorRuntime", "simulatorRuntimeBuild"]), "consumer runtime mismatch")
    require(type(value["segmentID"]) is str and value["segmentID"] in ["none", "segment-1", "segment-2", "segment-3", "minimum-segment-1", "minimum-segment-2", "minimum-segment-3"], "unknown shared segment")
    if value["segmentID"] != "none":
        require((found[0]["ordinal"] >= 8 and value["segmentID"].startswith("minimum-segment-")) or (value["shardID"] == "s10.4.current.ax-text" and value["segmentID"].startswith("segment-")), "segment not admitted for shard")
    return found[0]


def ensure_command(command, action, xctestrun=None, destination=None):
    require(type(command) is list and all(type(x) is str and x and not any(c in x for c in ["\n", "\r", "\x00"]) for x in command), "command must be original argument vector")
    require(Path(command[0]).name == "xcodebuild" and command.count(action) == 1, "wrong build/test command")
    require(not any(x in command for x in (["build", "build-for-testing", "test"] if action == "test-without-building" else ["test", "test-without-building"])), "consumer rebuild or wrong action")
    require("CODE_SIGNING_ALLOWED=NO" in command, "unsigned command required")
    def option(name):
        require(command.count(name) == 1, "missing/duplicate command option: " + name)
        at = command.index(name); require(at + 1 < len(command), "missing option value")
        return command[at + 1]
    if action == "build-for-testing":
        require(option("-project") == TOOLCHAIN["project"] and option("-scheme") == TOOLCHAIN["scheme"] and option("-configuration") == "Debug", "build project/scheme/config mismatch")
    else:
        require(option("-xctestrun") == str(xctestrun) and "-project" not in command and "-scheme" not in command and "-derivedDataPath" not in command, "shared execution must use exact xctestrun")
    require(option("-destination") == "platform=iOS Simulator,id=" + destination, "command destination mismatch")
    allowed = ({"-project", "-scheme", "-configuration", "-destination", "-derivedDataPath", "-resultBundlePath"}
               if action == "build-for-testing" else {"-xctestrun", "-destination", "-resultBundlePath"})
    for name in allowed:
        option(name)
    cursor = 1
    while cursor < len(command):
        text = command[cursor]
        if text in allowed:
            cursor += 2
        elif text in [action, "CODE_SIGNING_ALLOWED=NO"] or (action == "test-without-building" and text.startswith("-only-testing:")):
            cursor += 1
        else:
            fail("undeclared command argument")
    require(command.count("CODE_SIGNING_ALLOWED=NO") == 1 and Path(option("-resultBundlePath")).is_absolute(), "unsigned/result path mismatch")
    return command


def native_five(tree, executed, device):
    require(type(tree) is dict and type(tree.get("testNodes")) is list and type(executed) is list, "native test exports required")
    cases = []
    def walk(node):
        require(type(node) is dict, "malformed native test node")
        if "result" in node:
            require(node["result"] == "Passed", "native container/method did not pass")
        if node.get("nodeType") == "Test Case":
            require(node.get("result") == "Passed" and not node.get("isExpectedFailure", False), "native method did not pass")
            require(node.get("nodeIdentifierURL", "").startswith("test://com.apple.xcode/FieldEvidenceApp/"), "foreign native test URL")
            identifier = node["nodeIdentifierURL"].removeprefix("test://com.apple.xcode/FieldEvidenceApp/").removesuffix("()")
            require(node.get("nodeIdentifier", "").removesuffix("()") == identifier.removeprefix("FieldEvidenceAppTests/"), "native identifier mismatch")
            require(node.get("name", "").removesuffix("()") == identifier.split("/")[-1], "native method name mismatch")
            duration = node.get("durationInSeconds")
            require(type(duration) in [int, float] and math.isfinite(duration) and duration >= 0, "invalid native duration")
            cases.append({"identifier": identifier, "result": "Passed", "durationInSeconds": duration})
        children = node.get("children", [])
        require(type(children) is list, "malformed native children")
        for child in children:
            walk(child)
    for node in tree["testNodes"]:
        walk(node)
    require(len(cases) == 5 and len({x["identifier"] for x in cases}) == 5 and {x["identifier"] for x in cases} == set(UNIT_IDS), "missing/extra/duplicate native method")
    require(len(executed) == 5 and all(type(x) is dict and x.get("result") == "Passed" for x in executed), "executed methods did not all pass")
    identities = [x.get("identifier", "").removesuffix("()") for x in executed]
    require(len(set(identities)) == 5 and set(identities) == set(UNIT_IDS), "executed method identity mismatch")
    devices = tree.get("devices")
    require(type(devices) is list and len(devices) == 1, "ambiguous native unit device")
    expected = {"deviceId": device["simulatorUDID"], "deviceName": CURRENT_DEVICE["simulatorName"],
                "osVersion": "26.2", "osBuildNumber": "23C54", "architecture": "arm64", "platform": "iOS Simulator"}
    require(all(devices[0].get(k) == v for k, v in expected.items()), "unit runtime/device mismatch")
    return sorted(cases, key=lambda x: x["identifier"])


REQUEST_FIELDS = {
    "prepare": "checkoutRoot head producer toolchain derivedDataRoot buildCommand buildResultBundle buildLog",
    "qualify": "checkoutRoot head preparedRoot unitEvidenceRoot unitCommand unitResultsRelativePath executedTestsRelativePath unitXCResultRelativePath unitLogRelativePath unitDevice",
    "seal": "checkoutRoot head preparedRoot qualificationRoot payloadArtifactID unitArtifactID",
    "admit": "checkoutRoot head sourceRunID selection",
    "restore": "checkoutRoot head sourceRunID consumer",
    "verify-consumer": "checkoutRoot head restoreRoot consumer uiCommand isolationReceipt",
}


def envelope(kind, **values):
    return dict(schemaVersion=1, contractID=CONTRACT, recordType=kind, **values)


def typed(value, kind, fields):
    exact_keys(value, set(fields.split()) | {"schemaVersion", "contractID", "recordType"})
    require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1 and
            value["contractID"] == CONTRACT and value["recordType"] == kind, "wrong typed record")
    return value


def relative_file(root, relative):
    safe_relative(relative)
    result = root / relative
    require(result.resolve().is_relative_to(root) and regular_file(result), "unsafe referenced file")
    return result


def nonempty_bundle(path):
    entries = inventory(path)
    require(any(e["type"] == "file" and e["size"] > 0 for e in entries), "empty native result bundle")
    return object_sha(entries)


def products_binding(payload):
    products = payload / ROOT_LABEL
    bounded = inventory(products)
    entries, relative = collect(products)
    require(entries == bounded, "product inventory disagreement")
    compatibility = product_compatibility(products, products / relative)
    return {"tree": entries, "treeSHA256": object_sha(entries), "xctestrunPath": ROOT_LABEL + "/" + relative,
            "xctestrunSHA256": sha256_file(products / relative), "compatibility": compatibility}


def product_compatibility(products, xctestrun):
    settings = read_xctestrun(xctestrun)
    require(type(settings) is dict and all(type(settings.get(k)) is dict for k in
            ["FieldEvidenceAppTests", "FieldEvidenceAppUITests"]), "missing executable test targets")
    for target in ["FieldEvidenceAppTests", "FieldEvidenceAppUITests"]:
        host = settings[target].get("TestHostPath")
        require(type(host) is str and host.startswith("__TESTROOT__/"), "test host not bound to product closure")
        for field in ["TestBundlePath", "TestHostPath"]:
            text = settings[target].get(field)
            if type(text) is str and text.startswith("__TESTHOST__/"):
                text = host + text.removeprefix("__TESTHOST__")
            require(type(text) is str and text.startswith("__TESTROOT__/"), "test executable not bound to product closure")
            relative = text.removeprefix("__TESTROOT__/"); safe_relative(relative)
            path = products / relative
            require(path.exists() and path.resolve().is_relative_to(products) and not path.is_symlink(), "missing test executable closure")
        for text in settings[target].get("DependentProductPaths", []):
            require(type(text) is str and text.startswith("__TESTROOT__/"), "unbound dependent product")
            relative = text.removeprefix("__TESTROOT__/"); safe_relative(relative)
            require((products / relative).exists(), "missing dependent product")
    binaries = []
    for entry in inventory(products):
        if entry["type"] != "file" or entry["size"] < 4:
            continue
        path = products / entry["path"]
        with path.open("rb") as handle:
            magic = handle.read(4)
            universal = magic in [b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"]
            slice_bytes = entry["size"]
            if universal:
                count_raw = handle.read(4)
                require(len(count_raw) == 4, "truncated universal header")
                count = struct.unpack(">I", count_raw)[0]
                require(0 < count <= 32, "universal architecture count")
                width = 32 if magic == b"\xca\xfe\xba\xbf" else 20
                slices = []
                for unused in range(count):
                    raw = handle.read(width); require(len(raw) == width, "truncated universal slice table")
                    fields = struct.unpack(">IIQQII" if width == 32 else ">IIIII", raw)
                    cpu, subtype, offset, size, alignment = fields[:5]
                    require(offset >= 8 + count * width and size >= 32 and offset + size <= entry["size"] and alignment <= 32,
                            "invalid universal slice bounds")
                    slices.append((cpu, offset, size))
                ordered = sorted(slices, key=lambda s: s[1])
                require(all(a[1] + a[2] <= b[1] for a, b in zip(ordered, ordered[1:])), "overlapping universal slices")
                arm64 = [s for s in slices if s[0] == 0x0100000C]
                require(len(arm64) == 1, "missing/ambiguous universal arm64 slice")
                _, offset, slice_bytes = arm64[0]
                handle.seek(offset); magic = handle.read(4)
            if magic != b"\xcf\xfa\xed\xfe":
                require(magic not in [b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xfe\xed\xfa\xcf"], "unsupported executable architecture/container")
                require(not universal, "universal arm64 slice has wrong format")
                continue
            header = handle.read(28)
            require(len(header) == 28, "truncated Mach-O header")
            cpu, subtype, filetype, ncmds, sizecmds, flags, reserved = struct.unpack("<7I", header)
            require(cpu == 0x0100000C and 0 < ncmds <= 4096 and sizecmds <= min(slice_bytes - 32, 16 * 1024**2), "wrong/truncated Mach-O architecture")
            commands = handle.read(sizecmds); cursor = 0; versions = []
            for unused in range(ncmds):
                require(cursor + 8 <= len(commands), "truncated load command")
                cmd, size = struct.unpack_from("<II", commands, cursor)
                require(size >= 8 and cursor + size <= len(commands), "invalid load command size")
                if cmd == 0x32:
                    require(size >= 24, "truncated build-version command")
                    platform, minimum, sdk, tools = struct.unpack_from("<4I", commands, cursor + 8)
                    require(platform == 7 and minimum <= (18 << 16), "executable runtime incompatible")
                    # Xcode's bundled universal test runner/frameworks are built
                    # against 26.4; current app and test products use SDK 26.5.
                    if filetype in [2, 8] and not universal:
                        require(sdk == ((26 << 16) | (5 << 8)), "app/test executable SDK mismatch")
                    versions.append({"platform": platform, "minimumOS": minimum, "sdk": sdk})
                cursor += size
            require(cursor == len(commands), "load command closure mismatch")
            if filetype not in [2, 6, 8]:
                continue
            require(len(versions) == 1, "missing/duplicate executable compatibility version")
            binaries.append({"path": entry["path"], "sha256": entry["sha256"], **versions[0]})
    require(len(binaries) >= 3, "missing app/unit/UI native executable closure")
    return binaries


def prepared(root, source):
    value = typed(load(root / "prepared-build.json"), "prepared-build",
                  "source producer toolchain products buildEvidence")
    require(value["source"] == source and value["toolchain"] == TOOLCHAIN, "prepared source/toolchain mismatch")
    producer_identity(value["producer"])
    require(products_binding(root / "payload") == value["products"], "prepared closure changed")
    require(load(root / "products-before-units.json") == value["products"], "pre-unit closure mismatch")
    return value


def prepare_command(request, output, source):
    producer = producer_identity(request["producer"])
    require(request["toolchain"] == TOOLCHAIN, "producer toolchain mismatch")
    require(str(producer["runID"]) == os.environ.get("GITHUB_RUN_ID") and
            str(producer["runAttempt"]) == os.environ.get("GITHUB_RUN_ATTEMPT"), "producer environment mismatch")
    command = ensure_command(request["buildCommand"], "build-for-testing", destination=producer["simulatorUDID"])
    log = checked_path(request["buildLog"])
    require(regular_file(log) and log.stat().st_size > 0 and b"** TEST BUILD SUCCEEDED **" in log.read_bytes(), "missing unsigned build success log")
    source_command = log.parent / "s10-4-shared-build-command.json"
    require(load(source_command) == command, "recorded source build command disagrees with request")
    bundle = checked_path(request["buildResultBundle"])
    bundle_sha = nonempty_bundle(bundle)
    original = checked_path(request["derivedDataRoot"]) / "Build/Products"
    staged = output / "payload" / ROOT_LABEL
    staged.parent.mkdir(parents=True)
    copy_tree(original, staged)
    normalize_xctestrun(staged, original)
    products = products_binding(output / "payload")
    # Retain original build evidence as provenance, never as consumer-local execution.
    evidence = output / "original-build-evidence"
    evidence.mkdir()
    copy_tree(bundle, evidence / "Build.xcresult")
    shutil.copy2(log, evidence / "build.log")
    shutil.copy2(source_command, evidence / "s10-4-shared-build-command.json")
    save(evidence / "command.json", command)
    write_checksums(evidence)
    value = envelope("prepared-build", source=source, producer=producer, toolchain=TOOLCHAIN,
                     products=products, buildEvidence={"bundleTreeSHA256": bundle_sha,
                     "logSHA256": sha256_file(log), "command": command,
                     "sourceCommandSHA256": sha256_file(source_command),
                     "checksumsSHA256": sha256_file(evidence / "SHA256SUMS.txt")})
    save(output / "prepared-build.json", value)
    save(output / "products-before-units.json", products)
    return {"xctestrunPath": str(output / "payload" / products["xctestrunPath"]),
            "preparedRoot": str(output), "productsSHA256": products["treeSHA256"]}


def make_tar(root, path):
    before = inventory(root)
    with tarfile.open(path, "x", format=tarfile.PAX_FORMAT) as archive:
        for entry in before:
            archive.add(root / entry["path"], arcname="FieldEvidencePayload/" + entry["path"], recursive=False)
    require(inventory(root) == before, "archive source changed")
    require(path.stat().st_size <= MAX_ARCHIVE_BYTES, "tar exceeds bound")
    return {"name": "FieldEvidencePayload.tar", "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def qualification(root, source):
    verify_checksums(root)
    value = typed(load(root / "producer-qualification.json"), "producer-qualification",
                  "source producer toolchain products nativeTests unitDevice unitCommand originalEvidenceSHA256 buildEvidenceSHA256 originalEvidencePaths archive")
    require(value["source"] == source and value["toolchain"] == TOOLCHAIN, "qualification source mismatch")
    producer_identity(value["producer"])
    require(len(value["nativeTests"]) == 5 and {x["identifier"] for x in value["nativeTests"]} == set(UNIT_IDS)
            and all(x["result"] == "Passed" for x in value["nativeTests"]), "qualification native methods mismatch")
    require(evidence_identity(root / "original-unit-evidence") == value["originalEvidenceSHA256"], "unit evidence changed")
    require(evidence_identity(root / "original-build-evidence") == value["buildEvidenceSHA256"], "build evidence changed")
    paths = value["originalEvidencePaths"]
    exact_keys(paths, {"results", "executed", "xcresult", "log"})
    evidence = root / "original-unit-evidence"
    environment_proof(evidence, value["producer"])
    require(native_five(load(relative_file(evidence, paths["results"])), load(relative_file(evidence, paths["executed"])),
                       value["unitDevice"]) == value["nativeTests"], "original native proof disagrees with qualification")
    safe_relative(paths["xcresult"]); nonempty_bundle(evidence / paths["xcresult"])
    require(b"** TEST EXECUTE SUCCEEDED **" in relative_file(evidence, paths["log"]).read_bytes(), "missing original unit success")
    return value


def environment_proof(root, producer):
    version = relative_file(root, "xcode-version.txt").read_text(encoding="utf-8").splitlines()
    require(version == ["Xcode 26.6", "Build version 17F113"], "original Xcode evidence mismatch")
    selection = relative_file(root, "simulator-selection.txt").read_text(encoding="utf-8")
    for key, expected in {"runtime": "iOS 26.2", "runtime_build": "23C54", "name": "iPhone 17", "udid": producer["simulatorUDID"]}.items():
        values = re.findall(r"^" + key + r"=(.*)$", selection, re.M)
        require(values == [expected], "original producer Simulator evidence mismatch")
    settings = relative_file(root, "build-settings.txt").read_text(encoding="utf-8")
    for key, expected in {"ARCHS": "arm64", "CONFIGURATION": "Debug", "SDK_PRODUCT_BUILD_VERSION": "23F81a",
                          "SDK_VERSION": "26.5", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}.items():
        values = re.findall(r"^\s*" + key + r" = (.*?)\s*$", settings, re.M)
        require(bool(values) and all(value == expected for value in values), "original build settings mismatch: " + key)


def qualify_command(request, output, source):
    prepared_root = checked_path(request["preparedRoot"])
    value = prepared(prepared_root, source)
    products = value["products"]
    command = ensure_command(request["unitCommand"], "test-without-building",
        prepared_root / "payload" / products["xctestrunPath"], value["producer"]["simulatorUDID"])
    require(command.count("-only-testing:" + TEST_CLASS) == 1 and
            sum(x.startswith("-only-testing:") for x in command) == 1 and
            not any(x.startswith("-skip-testing") for x in command), "unit command selector changed")
    exact_keys(request["unitDevice"], {"simulatorUDID"})
    require(request["unitDevice"]["simulatorUDID"] == value["producer"]["simulatorUDID"], "unit simulator mismatch")
    unit_root = checked_path(request["unitEvidenceRoot"])
    environment_proof(unit_root, value["producer"])
    tree = load(relative_file(unit_root, request["unitResultsRelativePath"]))
    executed = load(relative_file(unit_root, request["executedTestsRelativePath"]))
    tests = native_five(tree, executed, request["unitDevice"])
    relative = request["unitXCResultRelativePath"]; safe_relative(relative)
    nonempty_bundle(unit_root / relative)
    log = relative_file(unit_root, request["unitLogRelativePath"])
    require(b"** TEST EXECUTE SUCCEEDED **" in log.read_bytes(), "missing native unit success log")
    copy_tree(unit_root, output / "original-unit-evidence")
    copy_tree(prepared_root / "original-build-evidence", output / "original-build-evidence")
    # Freeze a self-contained copy only after units have used the normalized closure.
    payload = output / "frozen-payload"
    copy_tree(prepared_root / "payload", payload)
    save(payload / "prepared-build.json", value)
    save(payload / "products-before-units.json", products)
    write_checksums(payload)
    require(products_binding(payload) == products and prepared(prepared_root, source) == value, "units changed products")
    transport = output / "payload-transport"; transport.mkdir()
    archive = make_tar(payload, transport / "FieldEvidencePayload.tar")
    (transport / "FieldEvidencePayload.tar.sha256").write_text(
        archive["sha256"] + " " + str(archive["bytes"]) + " FieldEvidencePayload.tar\n", encoding="utf-8")
    result = envelope("producer-qualification", source=source, producer=value["producer"], toolchain=TOOLCHAIN,
        products=products, nativeTests=tests, unitDevice=request["unitDevice"], unitCommand=command,
        originalEvidenceSHA256=evidence_identity(output / "original-unit-evidence"),
        buildEvidenceSHA256=evidence_identity(output / "original-build-evidence"),
        originalEvidencePaths={"results": request["unitResultsRelativePath"], "executed": request["executedTestsRelativePath"],
                               "xcresult": request["unitXCResultRelativePath"], "log": request["unitLogRelativePath"]}, archive=archive)
    save(output / "producer-qualification.json", result)
    # Unit artifact has explicit contents; products and payload transport are uploaded separately.
    unit_upload = output / "unit-upload"; unit_upload.mkdir()
    copy_tree(output / "original-unit-evidence", unit_upload / "original-unit-evidence")
    copy_tree(output / "original-build-evidence", unit_upload / "original-build-evidence")
    save(unit_upload / "producer-qualification.json", result)
    write_checksums(unit_upload)
    write_checksums(output)
    return {"producerQualificationSHA256": object_sha(result), "unitArtifactRoot": str(unit_upload),
            "payloadArtifactRoot": str(transport), "archive": archive}


def api_url(endpoint):
    require(type(endpoint) is str and re.fullmatch(r"[A-Za-z0-9/?=&._-]+", endpoint) and ".." not in endpoint, "invalid API endpoint")
    return "https://api.github.com/repos/" + REPOSITORY + "/" + endpoint


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        url = urllib.parse.urlsplit(newurl)
        host = url.hostname or ""
        require(url.scheme == "https" and not url.username and not url.password and url.port in [None, 443] and
                (host == "api.github.com" or host.endswith(".blob.core.windows.net") or host.endswith(".githubusercontent.com")), "untrusted artifact redirect")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if host != "api.github.com":
            redirected.remove_header("Authorization")
        return redirected


def response(endpoint):
    token = os.environ.get("GH_TOKEN", "")
    require(bool(token), "read token unavailable")
    request = urllib.request.Request(api_url(endpoint), headers={"Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    return urllib.request.build_opener(SafeRedirect()).open(request, timeout=60)


def api(endpoint):
    with response(endpoint) as handle:
        raw = handle.read(MAX_JSON_BYTES + 1)
    return decode_bytes(raw)


def list_api(endpoint, field):
    result = api(endpoint + "?per_page=100")
    require(type(result) is dict and type(result.get(field)) is list and type(result.get("total_count")) is int and
            len(result[field]) == result["total_count"] <= 100, "incomplete/unbounded API inventory")
    ids = [positive(x.get("id")) for x in result[field]]
    require(len(ids) == len(set(ids)), "duplicate API identity")
    return result[field]


def run_contract(run, rid, head):
    require(type(run) is dict and run.get("id") == rid and run.get("head_sha") == head and
            run.get("head_branch") == PHASE_REF.removeprefix("refs/heads/") and run.get("event") == "workflow_dispatch" and
            run.get("path") == WORKFLOW and run.get("repository", {}).get("full_name") == REPOSITORY and
            run.get("head_repository", {}).get("full_name") == REPOSITORY and
            run.get("repository", {}).get("id") == run.get("head_repository", {}).get("id") and
            run.get("display_title") == "iOS CI · lane=s10-4-shared-build-producer · shard=none · head=" + head,
            "wrong shared producer workflow")
    positive(run["repository"]["id"]); positive(run.get("run_attempt")); timestamp(run.get("created_at"))
    return run


def job_contract(jobs, run, producer=None, terminal=True):
    # Identity comes from original API and, after sealing, its bound positive job ID.
    found = [j for j in jobs if (producer is None or j.get("id") == producer["jobID"]) and
             any(s.get("name") == "Prepare S10.4 shared build payload" for s in j.get("steps", []))]
    require(len(found) == 1, "ambiguous/missing shared producer job")
    job = found[0]
    require(job.get("run_id") == run["id"] and job.get("run_attempt") == run["run_attempt"] and
            job.get("head_sha") == run["head_sha"] and job.get("head_branch") == run["head_branch"], "producer job provenance mismatch")
    positive(job.get("id")); timestamp(job.get("started_at"))
    for name in (PRODUCER_STEPS if terminal else PRODUCER_STEPS[:-2]):
        steps = [s for s in job.get("steps", []) if s.get("name") == name]
        require(len(steps) == 1 and steps[0].get("status") == "completed" and steps[0].get("conclusion") == "success", "producer step not successful: " + name)
    if terminal:
        require(job.get("status") == "completed" and job.get("conclusion") == "success", "producer job not successful")
    return job


def artifact_name(kind, run):
    return "s10-4-shared-" + {"payload": "payload", "unit": "units", "seal": "seal"}[kind] + "-" + str(run["id"]) + "-" + str(run["run_attempt"]) + "-" + run["head_sha"]


def artifact_contract(value, run, kind, now, purpose="acceptance"):
    require(value.get("name") == artifact_name(kind, run) and value.get("expired") is False, "wrong/expired artifact")
    aid = positive(value.get("id")); size = positive(value.get("size_in_bytes"))
    require(size <= (MAX_JSON_BYTES if kind == "seal" else MAX_ARCHIVE_BYTES), "oversized artifact")
    digest = value.get("digest", "")
    require(type(digest) is str and re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest), "missing API digest")
    owner = value.get("workflow_run", {})
    require(owner.get("id") == run["id"] and owner.get("head_sha") == run["head_sha"] and
            owner.get("head_branch") == run["head_branch"] and owner.get("repository_id") ==
            owner.get("head_repository_id") == run["repository"]["id"], "artifact source mismatch")
    created = timestamp(value.get("created_at")); expires = timestamp(value.get("expires_at"))
    require(timestamp(run["created_at"]) <= created <= now < expires and 0 < expires - created <= RETENTION_SECONDS,
            "invalid artifact retention/expiry")
    require(purpose in ["acceptance", "diagnostic"], "unknown purpose")
    if purpose == "diagnostic":
        require(now - timestamp(run["created_at"]) <= DIAGNOSTIC_SECONDS, "diagnostic source exceeds 24 hours")
    return {"id": aid, "name": value["name"], "bytes": size, "sha256": digest[7:].upper(),
            "createdAtUTC": value["created_at"], "expiresAtUTC": value["expires_at"]}


def download(artifact, path):
    require(not path.exists() and not path.is_symlink(), "refuse duplicate original download")
    total = 0
    with response("actions/artifacts/" + str(artifact["id"]) + "/zip") as handle, path.open("xb") as output:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk); require(total <= artifact["bytes"], "download exceeds original size")
            output.write(chunk)
    require(total == artifact["bytes"] and sha256_file(path) == artifact["sha256"], "original archive size/digest mismatch")


def extract_zip(path, root):
    require(not root.exists(), "ZIP destination exists")
    root.mkdir()
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist(); seen = set(); total = 0
        require(0 < len(infos) <= MAX_MEMBERS, "ZIP member bound")
        for info in infos:
            require(info.orig_filename == info.filename, "noncanonical original ZIP member name")
            name = info.filename.rstrip("/") if info.is_dir() else info.filename
            safe_relative(name)
            require(name.casefold() not in seen, "ZIP name collision")
            seen.add(name.casefold())
            mode = info.external_attr >> 16
            require(stat.S_IFMT(mode) in [0, stat.S_IFREG, stat.S_IFDIR] and not stat.S_IMODE(mode) & 0o7000 and not info.flag_bits & 1,
                    "unsafe ZIP member type/permissions/encryption")
            total += info.file_size; require(total <= MAX_ARCHIVE_BYTES, "ZIP expansion bound")
        for info in infos:
            target = root / info.filename
            require(target.resolve().is_relative_to(root), "ZIP escape")
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(info) as src, target.open("xb") as dst:
                    shutil.copyfileobj(src, dst, 1024 * 1024)
                require(target.stat().st_size == info.file_size, "ZIP size mismatch")
        require(archive.testzip() is None, "ZIP CRC failure")


def extract_tar(path, root):
    require(not root.exists(), "tar destination exists")
    root.mkdir()
    with tarfile.open(path, "r:") as archive:
        members = []; seen = set(); total = 0
        for member in archive:
            members.append(member)
            require(len(members) <= MAX_MEMBERS, "tar member bound")
            require(member.name.startswith("FieldEvidencePayload/"), "wrong tar root")
            relative = member.name.removeprefix("FieldEvidencePayload/").rstrip("/")
            safe_relative(relative)
            require(relative.casefold() not in seen and (member.isfile() or member.isdir()) and
                    not member.mode & 0o7000 and not member.linkname and not member.sparse, "unsafe tar member")
            seen.add(relative.casefold()); total += member.size
            require(total <= MAX_ARCHIVE_BYTES, "tar expansion bound")
            require(not any(key in member.pax_headers for key in ["linkpath", "GNU.sparse.name", "GNU.sparse.map"]), "unsafe tar extension")
        require(bool(members), "empty tar")
        for member in members:
            target = root / member.name.removeprefix("FieldEvidencePayload/")
            require(target.resolve().is_relative_to(root), "tar escape")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as src, target.open("xb") as dst:
                    shutil.copyfileobj(src, dst, 1024 * 1024)
                require(target.stat().st_size == member.size, "tar member size mismatch")
            os.chmod(target, member.mode)


def seal_command(request, output, source):
    value = prepared(checked_path(request["preparedRoot"]), source)
    qroot = checked_path(request["qualificationRoot"])
    unit = qualification(qroot / "unit-upload", source)
    require(unit["products"] == value["products"] and unit["producer"] == value["producer"], "qualification prepared mismatch")
    producer = value["producer"]
    run = run_contract(api("actions/runs/" + str(producer["runID"])), producer["runID"], source["head"])
    require(run["run_attempt"] == producer["runAttempt"], "producer attempt mismatch")
    jobs = list_api("actions/runs/" + str(run["id"]) + "/attempts/" + str(run["run_attempt"]) + "/jobs", "jobs")
    job_contract(jobs, run, producer, terminal=False)
    artifacts = {}
    for kind, field in [("payload", "payloadArtifactID"), ("unit", "unitArtifactID")]:
        aid = positive(request[field]); raw = api("actions/artifacts/" + str(aid))
        artifacts[kind] = artifact_contract(raw, run, kind, now_epoch())
        save(output / (kind + "-artifact-api.json"), raw)
    tar = qroot / "payload-transport/FieldEvidencePayload.tar"
    require(tar.stat().st_size == unit["archive"]["bytes"] and sha256_file(tar) == unit["archive"]["sha256"], "frozen tar changed")
    identity = {"source": source, "producer": producer, "toolchain": TOOLCHAIN, "payloadArtifact": artifacts["payload"],
                "archive": unit["archive"], "products": unit["products"]}
    result = envelope("shared-build-seal", sharedBuildIdentity=identity, sharedBuildIdentitySHA256=object_sha(identity),
        producerQualificationSHA256=object_sha(unit), unitArtifact=artifacts["unit"])
    save(output / "shared-build-seal.json", result)
    write_checksums(output)
    return result


def selection_contract(value, root):
    exact_keys(value, {"shardID", "segmentID", "purpose"})
    shard = [s for s in shard_contract(root)["shards"] if s["shardID"] == value["shardID"]]
    require(len(shard) == 1 and value["purpose"] in ["acceptance", "diagnostic"], "unknown selection")
    allowed = ["none"]
    if shard[0]["ordinal"] >= 8:
        allowed += ["minimum-segment-1", "minimum-segment-2", "minimum-segment-3"]
    elif value["shardID"] == "s10.4.current.ax-text":
        allowed += ["segment-1", "segment-2", "segment-3"]
    require(value["segmentID"] in allowed, "segment not admitted")
    return value


def admit_source(request, output, source, selection):
    rid = decimal_id(request["sourceRunID"])
    run = run_contract(api("actions/runs/" + str(rid)), rid, source["head"])
    jobs = list_api("actions/runs/" + str(rid) + "/attempts/" + str(run["run_attempt"]) + "/jobs", "jobs")
    job = job_contract(jobs, run)
    raw_artifacts = list_api("actions/runs/" + str(rid) + "/artifacts", "artifacts")
    artifacts = {}
    for kind in ["payload", "unit", "seal"]:
        found = [a for a in raw_artifacts if a.get("name") == artifact_name(kind, run)]
        require(len(found) == 1, "missing/duplicate original artifact")
        artifacts[kind] = artifact_contract(found[0], run, kind, now_epoch(), selection["purpose"])
    save(output / "producer-run.json", run); save(output / "producer-job.json", job)
    save(output / "artifact-metadata.json", raw_artifacts)
    download(artifacts["seal"], output / "original-seal.zip")
    seal_root = output / "seal-original"; extract_zip(output / "original-seal.zip", seal_root)
    require({e["path"] for e in inventory(seal_root)} == {"shared-build-seal.json", "SHA256SUMS.txt", "payload-artifact-api.json", "unit-artifact-api.json"}, "seal archive closure mismatch")
    verify_checksums(seal_root)
    seal = typed(load(seal_root / "shared-build-seal.json"), "shared-build-seal",
                 "sharedBuildIdentity sharedBuildIdentitySHA256 producerQualificationSHA256 unitArtifact")
    identity = seal["sharedBuildIdentity"]
    exact_keys(identity, {"source", "producer", "toolchain", "payloadArtifact", "archive", "products"})
    producer_identity(identity["producer"])
    require(identity["source"] == source and identity["toolchain"] == TOOLCHAIN and
            identity["producer"]["runID"] == rid and identity["producer"]["runAttempt"] == run["run_attempt"] and
            identity["producer"]["jobID"] == job["id"], "seal producer/source mismatch")
    require(identity["payloadArtifact"] == artifacts["payload"] and seal["unitArtifact"] == artifacts["unit"] and
            seal["sharedBuildIdentitySHA256"] == object_sha(identity), "seal artifact/identity mismatch")
    hash_value(seal["producerQualificationSHA256"])
    save(output / "shared-build-seal.json", seal)
    admission = envelope("admission", source=source, selection=selection, producerRunID=rid,
        sharedBuildIdentitySHA256=seal["sharedBuildIdentitySHA256"], producerQualificationSHA256=seal["producerQualificationSHA256"],
        artifacts=artifacts, admittedAtUTC=utc(now_epoch()), diagnosticOnly=selection["purpose"] == "diagnostic")
    save(output / "admission.json", admission)
    return seal, admission


def admit_command(request, output, source):
    selection = selection_contract(request["selection"], checked_path(request["checkoutRoot"]))
    seal, admission = admit_source(request, output, source, selection)
    materialize_shared(seal, admission, output, source)
    return admission


def restore_command(request, output, source):
    root = checked_path(request["checkoutRoot"])
    consumer_identity(request["consumer"], root)
    consumer = request["consumer"]
    require(str(consumer["runID"]) == os.environ.get("GITHUB_RUN_ID") and
            str(consumer["runAttempt"]) == os.environ.get("GITHUB_RUN_ATTEMPT"), "consumer environment mismatch")
    selection = {k: consumer[k] for k in ["shardID", "segmentID", "purpose"]}
    seal, admission = admit_source(request, output, source, selection)
    require(consumer["runID"] != admission["producerRunID"] and consumer["simulatorUDID"] != seal["sharedBuildIdentity"]["producer"]["simulatorUDID"], "consumer isolation reused producer")
    value = materialize_shared(seal, admission, output, source)
    save(output / "products-before-consumer.json", value["products"])
    result = envelope("consumer-provenance", source=source, consumer=consumer,
        sharedBuildIdentitySHA256=seal["sharedBuildIdentitySHA256"], producerQualificationSHA256=seal["producerQualificationSHA256"],
        unitTestCount=0, producerUnitTestCount=5, originalUnitArtifact=seal["unitArtifact"], products=value["products"],
        xctestrunPath=str(output / "payload" / value["products"]["xctestrunPath"]), diagnosticOnly=consumer["purpose"] == "diagnostic")
    save(output / "consumer-provenance.json", result)
    return result


def materialize_shared(seal, admission, output, source):
    download(admission["artifacts"]["payload"], output / "original-payload.zip")
    transport = output / "payload-transport"; extract_zip(output / "original-payload.zip", transport)
    require({e["path"] for e in inventory(transport)} == {"FieldEvidencePayload.tar", "FieldEvidencePayload.tar.sha256"}, "payload transport closure mismatch")
    archive = seal["sharedBuildIdentity"]["archive"]
    exact_keys(archive, {"name", "bytes", "sha256"})
    require(archive["name"] == "FieldEvidencePayload.tar", "wrong archive name")
    tar = transport / archive["name"]
    require(tar.stat().st_size == archive["bytes"] and sha256_file(tar) == archive["sha256"] and
            (transport / "FieldEvidencePayload.tar.sha256").read_text(encoding="utf-8") ==
            archive["sha256"] + " " + str(archive["bytes"]) + " FieldEvidencePayload.tar\n", "tar binding mismatch")
    extract_tar(tar, output / "payload"); verify_checksums(output / "payload")
    value = load(output / "payload/prepared-build.json")
    require(value["source"] == source and value["products"] == seal["sharedBuildIdentity"]["products"] and
            products_binding(output / "payload") == value["products"], "restored products mismatch")
    download(admission["artifacts"]["unit"], output / "original-unit-evidence.zip")
    extract_zip(output / "original-unit-evidence.zip", output / "unit-proof")
    unit = qualification(output / "unit-proof", source)
    require(object_sha(unit) == seal["producerQualificationSHA256"] and unit["products"] == value["products"] and
            unit["producer"] == seal["sharedBuildIdentity"]["producer"] and unit["archive"] == archive, "native qualification binding mismatch")
    return value


def verify_consumer_command(request, output, source):
    consumer_identity(request["consumer"], checked_path(request["checkoutRoot"]))
    root = checked_path(request["restoreRoot"])
    value = typed(load(root / "consumer-provenance.json"), "consumer-provenance",
        "source consumer sharedBuildIdentitySHA256 producerQualificationSHA256 unitTestCount producerUnitTestCount originalUnitArtifact products xctestrunPath diagnosticOnly")
    require(value["source"] == source and value["consumer"] == request["consumer"] and value["unitTestCount"] == 0 and
            type(value["unitTestCount"]) is int and value["producerUnitTestCount"] == 5 and
            type(value["producerUnitTestCount"]) is int and value["diagnosticOnly"] is (request["consumer"]["purpose"] == "diagnostic"), "consumer provenance changed")
    seal = typed(load(root / "shared-build-seal.json"), "shared-build-seal",
                 "sharedBuildIdentity sharedBuildIdentitySHA256 producerQualificationSHA256 unitArtifact")
    require(seal["sharedBuildIdentity"]["source"] == source and
            object_sha(seal["sharedBuildIdentity"]) == seal["sharedBuildIdentitySHA256"] == value["sharedBuildIdentitySHA256"] and
            seal["producerQualificationSHA256"] == value["producerQualificationSHA256"] and
            seal["unitArtifact"] == value["originalUnitArtifact"] and seal["sharedBuildIdentity"]["products"] == value["products"],
            "consumer seal reference changed")
    require(object_sha(qualification(root / "unit-proof", source)) == value["producerQualificationSHA256"], "consumer original unit proof changed")
    require(products_binding(root / "payload") == value["products"] == load(root / "products-before-consumer.json"), "consumer changed frozen products")
    require(value["xctestrunPath"] == str(root / "payload" / value["products"]["xctestrunPath"]), "consumer xctestrun path changed")
    command = ensure_command(request["uiCommand"], "test-without-building", value["xctestrunPath"], value["consumer"]["simulatorUDID"])
    selector = load(checked_path(request["checkoutRoot"]) / "Scripts/ci-selection.json")
    require(selector.get("taskID") == "S10.4" and selector.get("uiTestSelectors") ==
            ["FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests"], "source UI selector mismatch")
    expected = "-only-testing:" + selector["uiTestSelectors"][0]
    require(command.count(expected) == 1 and sum(x.startswith("-only-testing:") for x in command) == 1 and
            not any(x.startswith("-skip-testing") for x in command), "UI selector changed")
    receipt = load(checked_path(request["isolationReceipt"]))
    exact_keys(receipt, {"schemaVersion", "runID", "jobID", "simulatorUDID", "isolationID", "createdByThisJob", "preexistingDevice", "creationCommand"})
    c = value["consumer"]
    require(type(receipt["schemaVersion"]) is int and receipt["schemaVersion"] == 1 and
            all(receipt[k] == c[k] for k in ["runID", "jobID", "simulatorUDID", "isolationID"]) and
            receipt["createdByThisJob"] is True and receipt["preexistingDevice"] is False and
            type(receipt["creationCommand"]) is list and receipt["creationCommand"][:3] == ["xcrun", "simctl", "create"], "missing fresh Simulator proof")
    result = envelope("consumer-build-reference", **{k: v for k, v in value.items() if k not in ["schemaVersion", "contractID", "recordType"]},
        uiCommand=command, isolationReceiptSHA256=object_sha(receipt), productsUnchanged=True)
    save(output / "consumer-build-reference.json", result); write_checksums(output)
    return result


# Exact ede8844 legacy pilot verifier; emitted verbatim, never executed here.
LEGACY_PILOT_VERIFIER_SOURCE = r'''#!/usr/bin/env python3
import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT_LABEL = "FieldEvidenceDerivedData/Build/Products"
ALLOWED_MACROS = {"__TESTROOT__", "__PLATFORMS__", "__TESTHOST__", "__TESTBUNDLE__"}
PILOT_UNIT_SOURCE_PARTS = ("FieldEvidenceAppTests", "S10_4AutomatedBrandLabTests.swift")
PILOT_UNIT_SOURCE_PATH = "/".join(PILOT_UNIT_SOURCE_PARTS)
CANONICAL_SYSTEM_DYLD_PAIRS = frozenset({
    (
        ("FieldEvidenceAppTests", "EnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "/usr/lib/libRPAC.dylib",
    ),
    (
        ("FieldEvidenceAppTests", "TestingEnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "__TESTHOST__/Frameworks/libXCTestBundleInject.dylib:__SIMRUNTIMEROOT__/usr/lib/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib",
    ),
    (
        ("FieldEvidenceAppUITests", "EnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "/usr/lib/libRPAC.dylib",
    ),
    (
        ("FieldEvidenceAppUITests", "TestingEnvironmentVariables", "DYLD_INSERT_LIBRARIES"),
        "__SIMRUNTIMEROOT__/usr/lib/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib",
    ),
})

def fail(message):
    raise SystemExit("S10.4 pilot payload validation failed: " + message)

def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()

def require_checkout_head(value):
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{40}", value) is None:
        fail("malformed checkout head")
    return value

def require_checkout_sha256(value):
    if not isinstance(value, str) or re.fullmatch(r"[0-9A-F]{64}", value) is None:
        fail("malformed checkout source digest")
    return value

def checkout_directory(path):
    try:
        mode = os.lstat(path).st_mode
    except OSError:
        fail("unsafe checkout directory")
    if not stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
        fail("unsafe checkout directory")

def validate_checkout_root(root_text):
    if not isinstance(root_text, str) or not root_text:
        fail("unsafe checkout root")
    if any(ord(character) < 32 or ord(character) == 127 for character in root_text):
        fail("unsafe checkout root")
    if not os.path.isabs(root_text) or os.path.normpath(root_text) != root_text:
        fail("unsafe checkout root")
    try:
        physical_root = os.path.realpath(root_text)
    except OSError:
        fail("unsafe checkout root")
    if physical_root != root_text:
        fail("unsafe checkout root")
    root = Path(root_text)
    checkout_directory(root)
    return root

def run_checkout_git(root, arguments, capture=False):
    try:
        result = subprocess.run(
            ["git", "-C", os.fspath(root), *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            shell=False,
            text=capture,
            encoding="ascii" if capture else None,
            errors="strict" if capture else None,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError, UnicodeError):
        fail("checkout git verification failed")
    return result

def validate_checkout_source(root_text, expected_head, expected_sha256=None):
    root = validate_checkout_root(root_text)
    expected_head = require_checkout_head(expected_head)
    if expected_sha256 is not None:
        expected_sha256 = require_checkout_sha256(expected_sha256)
    source_directory = root
    for component in PILOT_UNIT_SOURCE_PARTS[:-1]:
        source_directory = source_directory / component
        checkout_directory(source_directory)
    source_path = source_directory / PILOT_UNIT_SOURCE_PARTS[-1]
    try:
        source_mode = os.lstat(source_path).st_mode
    except OSError:
        fail("unsafe checkout source")
    if not stat.S_ISREG(source_mode) or stat.S_ISLNK(source_mode):
        fail("unsafe checkout source")
    head_result = run_checkout_git(root, ["rev-parse", "--verify", "HEAD"], capture=True)
    if head_result.returncode != 0 or head_result.stdout.strip() != expected_head:
        fail("checkout head mismatch")
    tracked_result = run_checkout_git(
        root, ["ls-files", "--error-unmatch", "--", PILOT_UNIT_SOURCE_PATH]
    )
    if tracked_result.returncode != 0:
        fail("checkout source is not tracked")
    clean_result = run_checkout_git(
        root, ["diff", "--quiet", "--exit-code", expected_head, "--", PILOT_UNIT_SOURCE_PATH]
    )
    if clean_result.returncode != 0:
        fail("checkout source is not clean")
    try:
        source_sha256 = sha256_file(source_path)
    except OSError:
        fail("checkout source unreadable")
    if expected_sha256 is not None and source_sha256 != expected_sha256:
        fail("checkout source digest mismatch")
    return source_sha256

def strict_pairs(pairs):
    output = {}
    for key, value in pairs:
        if key in output:
            fail("duplicate JSON key: " + key)
        output[key] = value
    return output

def read_json(path):
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream, object_pairs_hook=strict_pairs)
    except (OSError, ValueError, UnicodeError) as error:
        fail(f"invalid JSON {path}: {error}")

def regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except OSError:
        return False

def real_directory(path):
    try:
        mode = os.lstat(path).st_mode
    except OSError as error:
        fail(f"missing directory {path}: {error}")
    if not stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
        fail("unsafe directory ancestor: " + str(path))

def require_product_ancestors(products):
    payload_root = products.parents[2]
    real_directory(payload_root)
    real_directory(payload_root / "FieldEvidenceDerivedData")
    real_directory(payload_root / "FieldEvidenceDerivedData" / "Build")
    real_directory(products)

def safe_relative(relative):
    if not relative or relative.startswith("/") or "\\" in relative:
        fail("unsafe relative member path")
    if any(part in ("", ".", "..") for part in relative.split("/")):
        fail("unsafe relative member component")
    if any(char in relative for char in ("\x00", "\n", "\r")):
        fail("unsafe relative member character")

def read_xctestrun(path):
    try:
        with path.open("rb") as stream:
            return plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        fail("invalid xctestrun type=" + type(error).__name__)

def xctestrun_strings(value, field_path=()):
    if isinstance(value, str):
        yield field_path, value
    elif isinstance(value, dict):
        for key in sorted(value, key=str):
            yield from xctestrun_strings(value[key], field_path + (str(key),))
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            yield from xctestrun_strings(nested, field_path + (str(index),))

def normalize_xctestrun(root, source_root):
    xctestruns = []
    for directory, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        for name in files:
            path = Path(directory) / name
            if name.endswith(".xctestrun") and regular_file(path):
                xctestruns.append(path)
    if len(xctestruns) != 1:
        fail("expected exactly one regular .xctestrun before normalization")
    source_text = str(source_root)
    if not source_root.is_absolute() or not source_text.endswith("/Build/Products"):
        fail("invalid source products root")
    payload = read_xctestrun(xctestruns[0])
    source_occurrence_count = sum(
        text.count(source_text) for _, text in xctestrun_strings(payload)
    )
    original_testroot_count = sum(
        text.count("__TESTROOT__") for _, text in xctestrun_strings(payload)
    )
    replacement_count = 0

    def replace_source_root(text):
        nonlocal replacement_count
        output = []
        cursor = 0
        while True:
            index = text.find(source_text, cursor)
            if index < 0:
                output.append(text[cursor:])
                break
            end = index + len(source_text)
            before_is_boundary = index == 0 or text[index - 1] in "=:"
            after_is_boundary = end == len(text) or text[end] == "/"
            if not before_is_boundary or not after_is_boundary:
                fail("noncanonical source products root occurrence")
            output.append(text[cursor:index])
            output.append("__TESTROOT__")
            replacement_count += 1
            cursor = end
        rewritten = "".join(output)
        if source_text in rewritten:
            fail("incomplete source products root normalization")
        return rewritten

    def rewrite(value):
        if isinstance(value, str):
            return replace_source_root(value)
        if isinstance(value, dict):
            return {key: rewrite(nested) for key, nested in value.items()}
        elif isinstance(value, list):
            return [rewrite(nested) for nested in value]
        return value

    normalized = rewrite(payload)
    if replacement_count != source_occurrence_count:
        fail("xctestrun source products root was not bound")
    normalized_testroot_count = sum(
        text.count("__TESTROOT__") for _, text in xctestrun_strings(normalized)
    )
    if normalized_testroot_count != original_testroot_count + replacement_count:
        fail("xctestrun normalization count mismatch")
    temporary = xctestruns[0].with_name(xctestruns[0].name + ".normalized")
    if temporary.exists() or temporary.is_symlink():
        fail("xctestrun normalization temporary path exists")
    try:
        with temporary.open("wb") as stream:
            plistlib.dump(normalized, stream, fmt=plistlib.FMT_XML, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, stat.S_IMODE(os.lstat(xctestruns[0]).st_mode))
        os.replace(temporary, xctestruns[0])
    finally:
        if temporary.exists() or temporary.is_symlink():
            temporary.unlink()

def value_classification(text):
    runner_temp = os.environ.get("RUNNER_TEMP", "")
    workspace = os.environ.get("GITHUB_WORKSPACE", "")
    developer_dir = os.environ.get("DEVELOPER_DIR", "")
    if runner_temp and runner_temp in text:
        return "runner-temp"
    if workspace and workspace in text:
        return "workspace"
    if developer_dir and developer_dir in text:
        return "developer-dir"
    if text.startswith(("/Applications/", "/Library/", "/System/", "/usr/")):
        return "system"
    if "file:" in text:
        return "file-url"
    return "other"

def redacted_components(parts):
    component_count = len(parts)
    displayed = parts[:16]
    return {
        "componentCount": component_count,
        "components": [
            {
                "bytes": len(component.encode("utf-8")),
                "class": value_classification(component),
                "sha256": hashlib.sha256(component.encode("utf-8")).hexdigest().upper(),
            }
            for component in displayed
        ],
        "truncated": component_count > len(displayed),
    }

def validate_xctestrun(path, producer_root):
    payload = read_xctestrun(path)
    producer_text = str(producer_root)
    violations = []
    for field_path, text in xctestrun_strings(payload):
        text_bytes = text.encode("utf-8")
        field_bytes = "/".join(field_path).encode("utf-8")
        kinds = {}
        if producer_text in text:
            kinds["producer-specific-xctestrun-path"] = 1
        is_canonical_system_dyld = (field_path, text) in CANONICAL_SYSTEM_DYLD_PAIRS
        if re.search(r"(?:^|[=:])(?:/|~|file:)", text) and not is_canonical_system_dyld:
            kinds["absolute-xctestrun-path"] = 1
        if "/../" in text or text.startswith("../"):
            kinds["traversing-xctestrun-path"] = 1
        if "$" in text:
            kinds["unresolved-xctestrun-macro"] = 1
        unknown_macro_count = sum(
            1 for macro in re.findall(r"__[A-Za-z0-9_]+__", text)
            if macro not in ALLOWED_MACROS and not (
                is_canonical_system_dyld and macro == "__SIMRUNTIMEROOT__"
            )
        )
        if unknown_macro_count:
            kinds["unknown-xctestrun-macro"] = unknown_macro_count
        if kinds:
            field_components = redacted_components(list(field_path))
            value_components = redacted_components(text.split(":"))
            for component in field_components["components"]:
                component.pop("class")
            violations.append({
                "field": {
                    "componentCount": field_components["componentCount"],
                    "components": field_components["components"],
                    "depth": len(field_path),
                    "sha256": hashlib.sha256(field_bytes).hexdigest().upper(),
                    "truncated": field_components["truncated"],
                },
                "kinds": kinds,
                "value": {
                    "bytes": len(text_bytes),
                    "class": value_classification(text),
                    "componentCount": value_components["componentCount"],
                    "components": value_components["components"],
                    "sha256": hashlib.sha256(text_bytes).hexdigest().upper(),
                    "truncated": value_components["truncated"],
                },
            })
    if violations:
        violations.sort(key=lambda item: (
            item["field"]["sha256"], item["value"]["sha256"],
            tuple(sorted(item["kinds"].items())),
        ))
        displayed = violations[:64]
        diagnostic = {
            "recordCount": len(violations),
            "truncated": len(violations) > len(displayed),
            "violationCount": sum(sum(item["kinds"].values()) for item in violations),
            "violations": displayed,
        }
        fail("xctestrun residual violations " + json.dumps(
            diagnostic, sort_keys=True, separators=(",", ":")
        ))

def collect(root):
    require_product_ancestors(root)
    try:
        root_mode = os.lstat(root).st_mode
    except OSError as error:
        fail(f"missing product tree: {error}")
    if not stat.S_ISDIR(root_mode) or stat.S_ISLNK(root_mode):
        fail("product root is not a real directory")
    entries = []
    folded = set()
    xctestruns = []
    for directory, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories + files:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            safe_relative(relative)
            folded_relative = relative.casefold()
            if folded_relative in folded:
                fail("case-colliding product member: " + relative)
            folded.add(folded_relative)
            mode = os.lstat(path).st_mode
            if stat.S_ISLNK(mode):
                fail("symlink product member: " + relative)
            if stat.S_ISDIR(mode):
                entries.append({
                    "mode": stat.S_IMODE(mode),
                    "path": relative,
                    "type": "directory",
                })
            elif stat.S_ISREG(mode):
                digest = sha256_file(path)
                entries.append({
                    "mode": stat.S_IMODE(mode),
                    "path": relative,
                    "sha256": digest,
                    "size": os.lstat(path).st_size,
                    "type": "file",
                })
                if relative.endswith(".xctestrun"):
                    xctestruns.append((relative, path))
            else:
                fail("nonregular product member: " + relative)
    entries.sort(key=lambda entry: entry["path"])
    if len(xctestruns) != 1:
        fail("expected exactly one regular .xctestrun")
    validate_xctestrun(xctestruns[0][1], root)
    return entries, xctestruns[0][0]

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))

def create(root, source_root, tree_path, checksums_path):
    normalize_xctestrun(root, source_root)
    entries, xctestrun_path = collect(root)
    tree = {"entries": entries, "root": ROOT_LABEL, "schemaVersion": 1}
    tree_path.write_text(canonical(tree) + "\n", encoding="utf-8")
    checksum_lines = [
        f'{entry["sha256"]}  {ROOT_LABEL}/{entry["path"]}'
        for entry in entries if entry["type"] == "file"
    ]
    checksums_path.write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")
    print(xctestrun_path)

def validate_payload_root(root):
    expected_names = {
        "FieldEvidenceDerivedData",
        "s10-4-payload-metadata.json",
        "s10-4-payload-tree.json",
        "s10-4-payload-sha256sums.txt",
        "s10-4-pilot-receipt.json",
    }
    real_directory(root)
    if {item.name for item in root.iterdir()} != expected_names:
        fail("unexpected payload root members")
    for name in expected_names - {"FieldEvidenceDerivedData"}:
        if not regular_file(root / name):
            fail("unsafe payload metadata member: " + name)
    require_product_ancestors(root / "FieldEvidenceDerivedData" / "Build" / "Products")

def archive_payload(payload_root, transport_root):
    validate_payload_root(payload_root)
    if transport_root.exists() or transport_root.is_symlink():
        fail("transport root already exists")
    transport_root.mkdir(mode=0o700)
    archive_path = transport_root / "FieldEvidencePayload.tar"
    nodes = [payload_root]
    for directory, directories, files in os.walk(payload_root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories + files:
            path = Path(directory) / name
            mode = os.lstat(path).st_mode
            if stat.S_ISLNK(mode) or not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
                fail("unsafe payload archive source member: " + str(path))
            nodes.append(path)
    with tarfile.open(archive_path, "w", format=tarfile.GNU_FORMAT) as archive:
        for path in nodes:
            relative = "." if path == payload_root else path.relative_to(payload_root).as_posix()
            arcname = "FieldEvidencePayload" if relative == "." else "FieldEvidencePayload/" + relative
            mode = os.lstat(path).st_mode
            info = tarfile.TarInfo(arcname)
            info.mode = stat.S_IMODE(mode)
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            if stat.S_ISDIR(mode):
                info.type = tarfile.DIRTYPE
                info.size = 0
                archive.addfile(info)
            else:
                info.type = tarfile.REGTYPE
                info.size = os.lstat(path).st_size
                with path.open("rb") as stream:
                    archive.addfile(info, stream)
    archive_size = os.lstat(archive_path).st_size
    digest = sha256_file(archive_path)
    (transport_root / "FieldEvidencePayload.tar.sha256").write_text(
        f"{digest} {archive_size} FieldEvidencePayload.tar\n", encoding="utf-8"
    )

def extract_payload(transport_root, extraction_root, arguments):
    if len(arguments) != 11:
        fail("wrong archive verifier argument count")
    real_directory(transport_root)
    expected_transport_names = {"FieldEvidencePayload.tar", "FieldEvidencePayload.tar.sha256"}
    if {item.name for item in transport_root.iterdir()} != expected_transport_names:
        fail("unexpected transport members")
    archive_path = transport_root / "FieldEvidencePayload.tar"
    digest_path = transport_root / "FieldEvidencePayload.tar.sha256"
    if not regular_file(archive_path) or not regular_file(digest_path):
        fail("unsafe transport member")
    digest_record = digest_path.read_text(encoding="utf-8")
    match = re.fullmatch(r"([0-9A-F]{64}) ([0-9]+) FieldEvidencePayload\.tar\n", digest_record)
    if match is None:
        fail("invalid detached archive digest")
    if match.group(1) != sha256_file(archive_path) or int(match.group(2)) != os.lstat(archive_path).st_size:
        fail("archive digest or size mismatch")
    try:
        with tarfile.open(archive_path, "r:") as archive:
            members = archive.getmembers()
            seen = set()
            folded = set()
            for member in members:
                name = member.name.rstrip("/")
                if not name or name.startswith("/") or "\\" in name:
                    fail("unsafe archive member name")
                parts = name.split("/")
                if parts[0] != "FieldEvidencePayload" or any(part in ("", ".", "..") for part in parts):
                    fail("unsafe archive member path")
                if name in seen or name.casefold() in folded:
                    fail("duplicate or case-colliding archive member")
                seen.add(name)
                folded.add(name.casefold())
                if member.issym() or member.islnk() or member.isdev() or member.isfifo() or not (member.isdir() or member.isreg()):
                    fail("unsafe archive member type")
            if not members or members[0].name.rstrip("/") != "FieldEvidencePayload" or not members[0].isdir():
                fail("archive lacks a single safe root")
            if extraction_root.exists() or extraction_root.is_symlink():
                fail("extraction root already exists")
            extraction_root.mkdir(mode=0o700)
            for member in members:
                archive.extract(member, extraction_root, set_attrs=True, numeric_owner=False)
    except (OSError, tarfile.TarError) as error:
        fail(f"unsafe archive extraction: {error}")
    payload_root = extraction_root / "FieldEvidencePayload"
    verify(payload_root, arguments)
    return payload_root

def verify(root, arguments):
    if len(arguments) != 11:
        fail("wrong verifier argument count")
    head, ref, repository, artifact, xcode_version, xcode_build, sdk_name, sdk_build, architecture, configuration, selector_sha = arguments
    validate_payload_root(root)
    products = root / "FieldEvidenceDerivedData" / "Build" / "Products"
    tree_path = root / "s10-4-payload-tree.json"
    sums_path = root / "s10-4-payload-sha256sums.txt"
    metadata_path = root / "s10-4-payload-metadata.json"
    receipt_path = root / "s10-4-pilot-receipt.json"
    metadata = read_json(metadata_path)
    expected_keys = {
        "architecture", "checksumsSHA256", "configuration", "deviceProfileID", "head",
        "payloadArtifactName", "producerRunnerProvider", "producerSegmentID", "producerShardID",
        "productsRoot", "ref", "repository", "schemaVersion", "selectorSHA256",
        "simulatorName", "simulatorRuntime", "simulatorRuntimeBuild", "taskID",
        "sourceBinding", "toolchain", "treeManifestSHA256", "xctestrunPath"
    }
    if not isinstance(metadata, dict) or set(metadata) != expected_keys:
        fail("unexpected payload metadata keys")
    expected = {
        "schemaVersion": 1, "payloadArtifactName": artifact, "head": head, "ref": ref,
        "repository": repository, "taskID": "S10.4", "producerRunnerProvider": "bitrise",
        "producerShardID": "s10.4.current.default-light", "producerSegmentID": "none",
        "deviceProfileID": "iphone-17-ios-26.2-current", "simulatorRuntime": "iOS 26.2",
        "simulatorRuntimeBuild": "23C54", "simulatorName": "iPhone 17",
        "productsRoot": ROOT_LABEL, "architecture": architecture, "configuration": configuration,
        "selectorSHA256": selector_sha,
    }
    for key, value in expected.items():
        if metadata.get(key) != value:
            fail("payload metadata mismatch: " + key)
    source_binding = metadata.get("sourceBinding")
    if not isinstance(source_binding, dict) or set(source_binding) != {"path", "sha256"} \
        or source_binding.get("path") != PILOT_UNIT_SOURCE_PATH:
        fail("payload source binding mismatch")
    require_checkout_sha256(source_binding.get("sha256"))
    expected_toolchain = {
        "sdkBuild": sdk_build, "sdkName": sdk_name, "xcodeBuild": xcode_build,
        "xcodeVersion": xcode_version,
    }
    if metadata.get("toolchain") != expected_toolchain:
        fail("payload toolchain mismatch")
    if metadata["treeManifestSHA256"] != sha256_file(tree_path):
        fail("payload tree manifest digest mismatch")
    if metadata["checksumsSHA256"] != sha256_file(sums_path):
        fail("payload checksum manifest digest mismatch")
    entries, xctestrun_path = collect(products)
    tree = read_json(tree_path)
    if tree != {"entries": entries, "root": ROOT_LABEL, "schemaVersion": 1}:
        fail("payload tree manifest mismatch")
    if metadata["xctestrunPath"] != xctestrun_path:
        fail("payload xctestrun identity mismatch")
    expected_sums = "\n".join(
        f'{entry["sha256"]}  {ROOT_LABEL}/{entry["path"]}'
        for entry in entries if entry["type"] == "file"
    ) + "\n"
    if sums_path.read_text(encoding="utf-8") != expected_sums:
        fail("payload checksum manifest mismatch")
    receipt = read_json(receipt_path)
    if not isinstance(receipt, dict) or receipt.get("schemaVersion") != 1 \
        or receipt.get("head") != head or receipt.get("ref") != ref \
        or receipt.get("payloadArtifactName") != artifact \
        or receipt.get("executionRole") != "payload-producer" \
        or receipt.get("runnerProvider") != "bitrise" \
        or receipt.get("shardID") != "s10.4.current.default-light" \
        or receipt.get("finalAcceptanceEligible") is not False \
        or receipt.get("result") != "payload-produced":
        fail("payload producer receipt mismatch")
    print(xctestrun_path)

def fingerprint(root):
    entries, _ = collect(root)
    print(hashlib.sha256(canonical(entries).encode("utf-8")).hexdigest().upper())

if len(sys.argv) < 2:
    fail("missing command")
command = sys.argv[1]
if command == "create" and len(sys.argv) == 6:
    create(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]), Path(sys.argv[5]))
elif command == "archive" and len(sys.argv) == 4:
    archive_payload(Path(sys.argv[2]), Path(sys.argv[3]))
elif command == "extract" and len(sys.argv) == 15:
    extract_payload(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:])
elif command == "verify" and len(sys.argv) == 14:
    verify(Path(sys.argv[2]), sys.argv[3:])
elif command == "checkout-source" and len(sys.argv) == 4:
    print(validate_checkout_source(sys.argv[2], sys.argv[3]))
elif command == "verify-checkout" and len(sys.argv) == 5:
    validate_checkout_source(sys.argv[2], sys.argv[3], sys.argv[4])
elif command == "fingerprint" and len(sys.argv) == 3:
    fingerprint(Path(sys.argv[2]))
else:
    fail("invalid command")
'''


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else list(argv)
    if arguments == ["emit-legacy-pilot-verifier"]:
        # stdout.buffer preserves the exact LF bytes on Windows as well as macOS.
        sys.stdout.buffer.write(LEGACY_PILOT_VERIFIER_SOURCE.encode("utf-8"))
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=REQUEST_FIELDS)
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    request = load(checked_path(args.request))
    exact_keys(request, set(REQUEST_FIELDS[args.command].split()) | {"schemaVersion", "contractID"})
    require(type(request["schemaVersion"]) is int and request["schemaVersion"] == 1 and request["contractID"] == CONTRACT, "wrong request schema")
    source = source_identity(checked_path(request["checkoutRoot"]), request["head"])
    output = new_directory(Path(args.output))
    handler = {"prepare": prepare_command, "qualify": qualify_command, "seal": seal_command,
               "admit": admit_command, "restore": restore_command, "verify-consumer": verify_consumer_command}[args.command]
    result = handler(request, output, source)
    print(canonical(result))


if __name__ == "__main__":
    try:
        main()
    except (PayloadError, OSError, tarfile.TarError, zipfile.BadZipFile, KeyError, TypeError) as error:
        print("shared-payload validation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
