#!/usr/bin/env python3
"""Generate closed V23 native selections from a versioned manifest.

This prospective tool does not admit a workflow run.  It produces the legacy
ci-selection.json and ci-selection-map.json shapes after checking exact source
method declarations at the supplied checkout.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys


CONTRACT = "v23.closed-selection-manifest.v1"
TASK = "V23-INTEGRATION-20260910"
TOP_KEYS = {
    "schemaVersion", "contractID", "taskID", "sourceRoot", "testBundle",
    "defaultSelectionID", "commonSelection", "selectorPool", "groups", "profiles",
}
COMMON = {
    "schemaVersion": 1,
    "taskID": TASK,
    "tier": "N8",
    "runUISmoke": False,
    "setupArtifactTimeoutSeconds": 300,
    "buildTimeoutSeconds": 1200,
    "testTimeoutSeconds": 900,
    "uiTimeoutSeconds": 0,
    "totalBudgetSeconds": 2400,
    "uiTestSelectors": [],
}
COMMON_KEYS = set(COMMON)
GROUP_KEYS = {"id", "classes"}
LEGACY_PROFILE_KEYS = {"id", "excludedGroupIDs"}
PROFILE_KEYS = LEGACY_PROFILE_KEYS | {"excludedSelectors"}
SELECTOR = re.compile(
    r"^FieldEvidenceAppTests/([A-Za-z_][A-Za-z0-9_]*Tests)/"
    r"(test[A-Za-z0-9_]{1,240})$"
)
IDENTIFIER = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
CLASS = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*Tests$")


class ManifestError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ManifestError(message)


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        require(isinstance(key, str) and key not in result, "duplicate or non-string JSON key")
        result[key] = value
    return result


def load_json(path: Path):
    require(path.is_absolute() and path.parent.resolve() == path.parent
            and path.is_file() and not path.is_symlink(),
            "manifest must be a physical regular file")
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_pairs)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ManifestError("invalid manifest JSON: " + type(error).__name__) from error


def canonical(value) -> bytes:
    try:
        return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                           ensure_ascii=True, allow_nan=False) + "\n").encode("ascii")
    except (TypeError, ValueError, UnicodeError) as error:
        raise ManifestError("noncanonical value: " + type(error).__name__) from error


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest().upper()


def exact_keys(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected), label + " keys")


def parse_selector(selector: str):
    require(isinstance(selector, str), "selector type")
    match = SELECTOR.fullmatch(selector)
    require(match is not None and ".." not in selector and "\\" not in selector,
            "unsafe or malformed selector")
    return match.group(1), match.group(2)


def validate_diagnostic_partitions(value, pool):
    """Validate optional diagnostic metadata without changing generated selections."""
    exact_keys(value, {"schemaVersion", "families"}, "diagnostic partitions")
    require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1,
            "diagnostic partitions schema")
    families = value["families"]
    require(isinstance(families, list) and families, "diagnostic partition families")
    ids = set()
    pool_set = set(pool)
    for family in families:
        exact_keys(family, {"parentID", "parentSelectors", "partitions"}, "diagnostic family")
        parent_id = family["parentID"]
        require(isinstance(parent_id, str) and IDENTIFIER.fullmatch(parent_id)
                and parent_id != "default-132" and parent_id not in ids,
                "diagnostic parent ID")
        ids.add(parent_id)
        parent = family["parentSelectors"]
        require(isinstance(parent, list) and parent
                and all(isinstance(item, str) for item in parent), "diagnostic parent selectors")
        for item in parent:
            parse_selector(item)
        require(len(parent) == len(set(parent)) and set(parent) <= pool_set,
                "diagnostic parent membership")
        partitions = family["partitions"]
        require(isinstance(partitions, list) and len(partitions) >= 2,
                "diagnostic partitions list")
        union = []
        for partition in partitions:
            exact_keys(partition, {"id", "selectors"}, "diagnostic partition")
            partition_id = partition["id"]
            require(isinstance(partition_id, str) and IDENTIFIER.fullmatch(partition_id)
                    and partition_id != "default-132" and partition_id not in ids,
                    "diagnostic partition ID")
            ids.add(partition_id)
            members = partition["selectors"]
            require(isinstance(members, list) and members
                    and all(isinstance(item, str) for item in members),
                    "diagnostic partition selectors")
            for item in members:
                parse_selector(item)
            union.extend(members)
        require(union == parent and len(union) == len(set(union)),
                "diagnostic exact ordered exhaustive disjoint union")
    return value


def validate_manifest(value):
    require(isinstance(value, dict) and set(value) in (TOP_KEYS, TOP_KEYS | {"diagnosticPartitions"}),
            "manifest keys")
    require(value["schemaVersion"] == 1 and type(value["schemaVersion"]) is int,
            "manifest schema")
    require(value["contractID"] == CONTRACT and value["taskID"] == TASK,
            "manifest identity")
    require(value["sourceRoot"] == "FieldEvidenceAppTests"
            and value["testBundle"] == "FieldEvidenceAppTests", "source identity")
    require(value["defaultSelectionID"] == "default-132", "default selection ID")
    exact_keys(value["commonSelection"], COMMON_KEYS, "common selection")
    require(value["commonSelection"] == COMMON
            and all(type(value["commonSelection"][key]) is type(expected)
                    for key, expected in COMMON.items()),
            "frozen environment or budget changed")

    pool = value["selectorPool"]
    require(isinstance(pool, list) and pool and all(isinstance(item, str) for item in pool)
            and len(pool) == len(set(pool)),
            "selector pool must be nonempty and unique")
    if "diagnosticPartitions" in value:
        validate_diagnostic_partitions(value["diagnosticPartitions"], pool)
    selector_classes = []
    for selector in pool:
        selector_classes.append(parse_selector(selector)[0])

    groups = value["groups"]
    require(isinstance(groups, list) and groups, "groups")
    group_ids = set()
    class_owner = {}
    for group in groups:
        exact_keys(group, GROUP_KEYS, "group")
        group_id, classes = group["id"], group["classes"]
        require(isinstance(group_id, str) and IDENTIFIER.fullmatch(group_id)
                and group_id != value["defaultSelectionID"] and group_id not in group_ids,
                "group ID")
        require(isinstance(classes, list) and classes
                and all(isinstance(item, str) for item in classes)
                and len(classes) == len(set(classes)),
                "group classes")
        for class_name in classes:
            require(isinstance(class_name, str) and CLASS.fullmatch(class_name),
                    "group class name")
            require(class_name not in class_owner, "class owned by multiple groups")
            class_owner[class_name] = group_id
        group_ids.add(group_id)
    require(set(selector_classes) == set(class_owner),
            "groups and selector classes must be exhaustive")
    counts = {group_id: 0 for group_id in group_ids}
    for class_name in selector_classes:
        counts[class_owner[class_name]] += 1
    require(all(count > 0 for count in counts.values()), "empty group")

    profiles = value["profiles"]
    require(isinstance(profiles, list) and profiles, "profiles")
    profile_ids = set()
    for profile in profiles:
        require(isinstance(profile, dict)
                and set(profile) in (LEGACY_PROFILE_KEYS, PROFILE_KEYS), "profile keys")
        profile_id, excluded = profile["id"], profile["excludedGroupIDs"]
        excluded_selectors = profile.get("excludedSelectors", [])
        require(isinstance(profile_id, str) and IDENTIFIER.fullmatch(profile_id)
                and profile_id not in profile_ids, "profile ID")
        require(isinstance(excluded, list)
                and all(isinstance(item, str) and item in group_ids for item in excluded)
                and len(excluded) == len(set(excluded)),
                "profile group exclusions")
        require(isinstance(excluded_selectors, list)
                and all(isinstance(item, str) and item in pool for item in excluded_selectors)
                and len(excluded_selectors) == len(set(excluded_selectors)),
                "profile selector exclusions")
        excluded_groups = set(excluded)
        excluded_selector_set = set(excluded_selectors)
        require(all(class_owner[parse_selector(item)[0]] not in excluded_groups
                    for item in excluded_selectors),
                "profile selector exclusion overlaps excluded group")
        require(len(excluded) < len(group_ids), "profile excludes every group")
        retained = [selector for selector in pool
                    if class_owner[parse_selector(selector)[0]] not in excluded_groups
                    and selector not in excluded_selector_set]
        retained_classes = {parse_selector(selector)[0] for selector in retained}
        for group in groups:
            if group["id"] not in excluded_groups:
                require(all(class_name in retained_classes for class_name in group["classes"]),
                        "profile empties included class")
                require(any(parse_selector(selector)[0] in group["classes"]
                            for selector in retained), "profile empties included group")
        profile_ids.add(profile_id)
    return value, class_owner


def _mask_swift_noncode(source: str) -> str:
    """Replace comments and string contents with spaces while preserving layout."""
    out = list(source)
    length = len(source)
    index = 0

    def blank(start, stop):
        for offset in range(start, stop):
            if out[offset] not in "\r\n":
                out[offset] = " "

    while index < length:
        if source.startswith("//", index):
            stop = source.find("\n", index + 2)
            stop = length if stop < 0 else stop
            blank(index, stop)
            index = stop
            continue
        if source.startswith("/*", index):
            start = index
            index += 2
            depth = 1
            while index < length and depth:
                if source.startswith("/*", index):
                    depth += 1; index += 2
                elif source.startswith("*/", index):
                    depth -= 1; index += 2
                else:
                    index += 1
            require(depth == 0, "unterminated Swift block comment")
            blank(start, index)
            continue
        hashes = 0
        if source[index] == "#":
            while index + hashes < length and source[index + hashes] == "#":
                hashes += 1
        quote = index + hashes
        if quote < length and source[quote] == '"':
            start = index
            triple = source.startswith('"""', quote)
            delimiter = ('"""' if triple else '"') + ("#" * hashes)
            index = quote + (3 if triple else 1)
            while index < length:
                if source.startswith(delimiter, index):
                    index += len(delimiter)
                    break
                escape = "\\" + ("#" * hashes)
                if source.startswith(escape, index):
                    index += len(escape) + 1
                else:
                    index += 1
            else:
                raise ManifestError("unterminated Swift string")
            blank(start, min(index, length))
            continue
        index += 1
    return "".join(out)


def _body_at(masked: str, opening: int, class_name: str) -> str:
    depth = 0
    for index in range(opening, len(masked)):
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
            if depth == 0:
                return masked[opening + 1:index]
    raise ManifestError("unclosed XCTestCase declaration: " + class_name)


def _active_swift(masked: str) -> str:
    """Closed Debug iOS Simulator conditions, not a general Swift evaluator.

    Reject unknown directives even in an inactive branch. This prevents a new
    source condition from silently acquiring membership through this parser.
    """
    conditions = {"DEBUG": True, "SWIFT_PACKAGE": False,
                  "DEBUG && os(iOS) && targetEnvironment(simulator)": True,
                  "true": True, "false": False}
    frames = []
    active = True
    output = []
    for line in masked.splitlines(keepends=True):
        directive = re.fullmatch(r"\s*#(if|elseif|else|endif)\b([^\r\n]*)[\r\n]*", line)
        if directive:
            kind, expression = directive.group(1), directive.group(2).strip()
            if kind in ("if", "elseif"):
                require(expression in conditions, "unsupported Swift condition: " + expression)
                enabled = conditions[expression]
            if kind == "if":
                frames.append([active, enabled, False])
                active = active and enabled
            elif kind == "elseif":
                require(frames and not frames[-1][2], "unmatched Swift elseif")
                parent, taken, _ = frames[-1]
                active = parent and not taken and enabled
                frames[-1][1] = taken or enabled
            elif kind == "else":
                require(not expression and frames and not frames[-1][2], "unmatched Swift else")
                parent, taken, _ = frames[-1]
                active = parent and not taken
                frames[-1][1:] = [True, True]
            else:
                require(not expression and frames, "unmatched Swift endif")
                active = frames.pop()[0]
            output.append(re.sub(r"[^\r\n]", " ", line))
        else:
            require(not re.match(r"\s*#(?:if|elseif|else|endif)\b", line),
                    "malformed Swift conditional")
            output.append(line if active else re.sub(r"[^\r\n]", " ", line))
    require(not frames, "unterminated Swift conditional")
    return "".join(output)


def _brace_depths(masked: str):
    depths = []
    depth = 0
    offset = 0
    for brace in re.finditer(r"[{}]", masked):
        # Every position through this brace has the previous depth. Build that
        # span in C instead of appending once per non-brace source character.
        stop = brace.start() + 1
        depths.extend([depth] * (stop - offset))
        offset = stop
        if brace.group() == "{":
            depth += 1
        else:
            depth -= 1
            require(depth >= 0, "unmatched Swift closing brace")
    depths.extend([depth] * (len(masked) - offset))
    require(depth == 0, "unclosed Swift brace")
    return depths


def _declaration_prefix(source: str, start: int) -> str:
    """Capture modifiers/attributes including separate preceding lines.

    Only the small declaration syntax used by the selected tests is admitted.
    Unknown attribute/modifier lines are retained so the caller rejects them.
    """
    beginning = source.rfind("\n", 0, start) + 1
    prefix = source[beginning:start]
    while beginning > 0:
        previous = source.rfind("\n", 0, beginning - 1) + 1
        line = source[previous:beginning].strip()
        if not line:
            beginning = previous
            continue
        if re.match(r"@testable\s+import\b", line):
            break
        if line.startswith("@") or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?", line):
            prefix = line + " " + prefix
            beginning = previous
        else:
            break
    return prefix


def _class_bodies(masked: str, class_name: str, selected_methods=()):
    depths = _brace_depths(masked)
    primary = re.compile(r"\bclass\s+" + re.escape(class_name)
                         + r"\b[^{};]{0,1000}\{")
    declarations = [match for match in primary.finditer(masked) if depths[match.start()] == 0]
    require(len(declarations) == 1,
            "missing or duplicate test class declaration: " + class_name)
    declaration = declarations[0]
    header = re.fullmatch(r"class\s+" + re.escape(class_name)
                          + r"\s*:\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)\s*\{",
                          declaration.group())
    require(header is not None, "unsupported XCTest inheritance: " + class_name)
    require(re.fullmatch(r"\s*(?:(?:@MainActor|final|public|internal)\s+)*",
                         _declaration_prefix(masked, declaration.start())),
            "unsupported test class modifiers: " + class_name)
    extensions = [match for match in re.finditer(r"\bextension\s+" + re.escape(class_name)
                  + r"\b[^{};]{0,1000}\{", masked) if depths[match.start()] == 0]
    for match in extensions:
        body = _body_at(masked, match.end() - 1, class_name)
        if any(re.search(r"\bfunc\s+" + re.escape(method) + r"\b", body) for method in selected_methods):
            require(re.fullmatch(r"extension\s+" + re.escape(class_name) + r"\s*\{", match.group())
                    and re.fullmatch(r"\s*(?:@MainActor\s+)*", _declaration_prefix(masked, match.start())),
                    "unsupported selected class extension: " + class_name)
    matches = declarations + extensions
    matches.sort(key=lambda item: item.start())
    return header.group(1), [_body_at(masked, match.end() - 1, class_name) for match in matches]


def _verify_methods(bodies, class_name, methods):
    direct = {}
    for body in bodies:
        depths = _brace_depths(body)
        for match in re.finditer(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\b", body):
            if depths[match.start()] == 0:
                direct.setdefault(match.group(1), []).append((body, match))
    for method in methods:
        declarations = direct.get(method, [])
        require(len(declarations) == 1,
                "missing or duplicate source method declaration: " + class_name + "/" + method)
        body, match = declarations[0]
        require(re.fullmatch(r"\s*(?:(?:@MainActor|public|internal|final|override)\s+)*",
                             _declaration_prefix(body, match.start())),
                "unsupported test method modifiers: " + class_name + "/" + method)
        require(re.match(r"func\s+" + re.escape(method)
                         + r"\s*\(\s*\)\s*(?:async\s+)?(?:throws\s+)?\{", body[match.start():]),
                "unsupported test method signature: " + class_name + "/" + method)


def verify_source_declarations(manifest, checkout_root: Path):
    require(checkout_root.is_absolute() and checkout_root.is_dir()
            and not checkout_root.is_symlink() and checkout_root.resolve() == checkout_root,
            "checkout root")
    root = checkout_root / manifest["sourceRoot"]
    require(root.is_dir() and not root.is_symlink() and root.resolve() == root,
            "test source root")
    root_resolved = root.resolve()
    by_class = {}
    for selector in manifest["selectorPool"]:
        class_name, method = parse_selector(selector)
        by_class.setdefault(class_name, []).append(method)
    sources = {}
    for class_name in sorted(by_class):
        path = root / (class_name + ".swift")
        require(path.is_file() and not path.is_symlink() and path.resolve().parent == root_resolved,
                "unsafe or missing source path: " + class_name)
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            raise ManifestError("unreadable source: " + class_name) from error
        sources[class_name] = _active_swift(_mask_swift_noncode(source))

    # Resolve inheritance only from the already selected, physically checked
    # source files. No arbitrary path, sibling scan or presumed base authority.
    class_sources = {}
    for source in sources.values():
        depths = _brace_depths(source)
        require(not any(depths[match.start()] == 0 for match in re.finditer(
            r"\b(?:class|struct|enum|protocol|typealias)\s+(?:XCTest|XCTestCase)\b", source)),
            "shadowed XCTest authority")
        for match in re.finditer(r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\b", source):
            if depths[match.start()] == 0:
                class_sources.setdefault(match.group(1), []).append(source)

    def verify_xctest(class_name, ancestors):
        if class_name in ("XCTestCase", "XCTest.XCTestCase"):
            return
        require(class_name not in ancestors, "cyclic XCTest inheritance")
        candidates = class_sources.get(class_name, [])
        require(len(candidates) == 1, "missing or duplicate XCTest superclass: " + class_name)
        superclass, _ = _class_bodies(candidates[0], class_name)
        verify_xctest(superclass, ancestors | {class_name})

    verified = 0
    for class_name, methods in by_class.items():
        verify_xctest(class_name, set())
        _, bodies = _class_bodies(sources[class_name], class_name, methods)
        _verify_methods(bodies, class_name, methods)
        verified += len(methods)
    require(verified == len(manifest["selectorPool"]), "source verification count")
    return verified


def generate(manifest, profile_id: str, checkout_root: Path):
    manifest, class_owner = validate_manifest(manifest)
    source_count = verify_source_declarations(manifest, checkout_root)
    profiles = [item for item in manifest["profiles"] if item["id"] == profile_id]
    require(len(profiles) == 1, "unknown profile")
    excluded = set(profiles[0]["excludedGroupIDs"])
    excluded_selectors = set(profiles[0].get("excludedSelectors", []))
    included_groups = [group for group in manifest["groups"] if group["id"] not in excluded]
    included_ids = {group["id"] for group in included_groups}
    pool = [selector for selector in manifest["selectorPool"]
            if class_owner[parse_selector(selector)[0]] in included_ids
            and selector not in excluded_selectors]
    require(pool and len(pool) == len(set(pool)), "generated selector pool")
    selection = dict(manifest["commonSelection"])
    selection["unitTestSelectors"] = pool
    groups = []
    covered = set()
    for group in included_groups:
        members = [selector for selector in pool if parse_selector(selector)[0] in group["classes"]]
        require(members and not (covered & set(members)), "generated group coverage")
        covered.update(members)
        groups.append({"id": group["id"], "classes": list(group["classes"]),
                       "methodCount": len(members)})
    require(covered == set(pool), "generated groups must cover pool")
    selection_map = {"schemaVersion": 1, "taskID": manifest["taskID"],
                     "defaultSelectionID": manifest["defaultSelectionID"], "groups": groups}
    selection_raw, map_raw = canonical(selection), canonical(selection_map)
    report = {
        "schemaVersion": 1,
        "contractID": CONTRACT,
        "profileID": profile_id,
        "taskID": manifest["taskID"],
        "selectorCount": len(pool),
        "groupCount": len(groups),
        "manifestSourceDeclarationCount": source_count,
        "selectionSHA256": sha256(selection_raw),
        "selectionMapSHA256": sha256(map_raw),
        "nativeReady": False,
        "acceptance": False,
    }
    return selection, selection_map, report


def validate_new_output(path: Path):
    require(path.is_absolute() and path.parent.is_dir() and not path.parent.is_symlink()
            and path.parent.resolve() == path.parent, "output parent")
    require(not path.exists() and not path.is_symlink(), "output already exists")


def write_new(path: Path, raw: bytes):
    validate_new_output(path)
    try:
        with path.open("xb") as stream:
            stream.write(raw)
    except OSError as error:
        raise ManifestError("cannot write output") from error


def parser():
    value = argparse.ArgumentParser()
    value.add_argument("command", choices=("generate", "verify"))
    value.add_argument("--manifest", required=True, type=Path)
    value.add_argument("--checkout-root", required=True, type=Path)
    value.add_argument("--profile", required=True)
    value.add_argument("--selection-output", type=Path)
    value.add_argument("--map-output", type=Path)
    value.add_argument("--report-output", type=Path)
    return value


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        manifest = load_json(args.manifest)
        selection, selection_map, report = generate(manifest, args.profile,
                                                    args.checkout_root)
        if args.command == "verify":
            require(args.selection_output is None and args.map_output is None
                    and args.report_output is None, "verify accepts no output paths")
            sys.stdout.buffer.write(canonical(report))
        else:
            require(args.selection_output is not None and args.map_output is not None,
                    "generate output paths")
            outputs = [args.selection_output, args.map_output]
            if args.report_output is not None:
                outputs.append(args.report_output)
            require(len(outputs) == len(set(outputs)), "output paths must be distinct")
            for output in outputs:
                validate_new_output(output)
            write_new(outputs[0], canonical(selection))
            write_new(outputs[1], canonical(selection_map))
            if len(outputs) == 3:
                write_new(outputs[2], canonical(report))
            sys.stdout.buffer.write(canonical(report))
        return 0
    except ManifestError as error:
        print("selection generation failed: " + str(error), file=sys.stderr)
        return 65


if __name__ == "__main__":
    raise SystemExit(main())
