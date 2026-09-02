#!/usr/bin/env python3
"""Generate and verify the deterministic V30 structural projections.

This generator is intentionally package-local.  It reads only the V30
architecture blueprint in this directory and emits the four support
projections used by the activation package.  It never reads the active app,
Phase 10 checkout, or either V23 repository.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parent
BLUEPRINT = ROOT / "EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md"

OUTPUTS = {
    "cards": ROOT / "V30_CARD_REGISTER.json",
    "graph": ROOT / "V30_DIRECT_DEPENDENCY_GRAPH.json",
    "locales": ROOT / "V30_LOCALE_REGISTRY.json",
    "v24": ROOT / "V30_V24_DISPOSITION_PROJECTION.json",
}

V24_SOURCE_PATH = (
    "C:\\Users\\palat\\OneDrive\\Desktop\\"
    "ASSETROUNDS_V24_GLOBALIZATION_FOUNDATION_BLUEPRINT.md"
)
V24_SOURCE_SHA256 = (
    "370c378bbb3b567c465d217111e8de3342581916e260b234a32511e807c01d94"
)

GRAPH_START = "## 21. Closed 55-card graph"
GRAPH_END = "## 22. Graph invariants and topological checks"
APPENDIX_START = "## Appendix A — V24 normative-requirement disposition matrix"
APPENDIX_END = "### Appendix A.1 Deterministic machine projection"

EXPECTED_CARD_COUNT = 55
EXPECTED_EDGE_COUNT = 107
EXPECTED_APPENDIX_COUNT = 97
VALID_CLASSES = {
    "FOUNDATION",
    "IMPLEMENTATION",
    "VERIFICATION",
    "INTEGRATION",
    "OWNER_ACTION",
    "VALIDATE_NEXT",
    "DEFER",
    "MONITOR",
}
VALID_DISPOSITIONS = {
    "INCORPORATED_WITH_PROVENANCE",
    "REJECTED_WITH_RATIONALE",
    "DEFERRED_UNCHANGED",
}
INITIAL_LOCALES = ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
NEXT_WAVE_LOCALES = [
    "pt-BR",
    "fil",
    "ar",
    "fr",
    "fr-CA",
    "ru",
    "pl",
    "hi",
    "id",
    "ja",
    "tr",
    "ht",
]


class GenerationError(RuntimeError):
    """Raised when the blueprint is not in the expected closed form."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise GenerationError(message)


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def read_blueprint() -> tuple[str, str]:
    raw = BLUEPRINT.read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf"), "blueprint has UTF-8 BOM")
    require(b"\r" not in raw, "blueprint has CR/CRLF line endings")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise GenerationError(f"blueprint is not UTF-8: {exc}") from exc
    require(text.endswith("\n"), "blueprint is missing its final LF")
    require(
        all(line == line.rstrip(" \t") for line in text.splitlines()),
        "blueprint has trailing spaces or tabs",
    )
    return text, sha256_bytes(raw)


def bounded_lines(text: str, start_heading: str, end_heading: str) -> tuple[list[str], int]:
    """Return section lines and the one-based source line of the first line."""

    lines = text.splitlines()
    starts = [index for index, line in enumerate(lines) if line == start_heading]
    ends = [index for index, line in enumerate(lines) if line == end_heading]
    require(len(starts) == 1, f"expected one section heading: {start_heading}")
    require(len(ends) == 1, f"expected one section heading: {end_heading}")
    start = starts[0]
    end = ends[0]
    require(start < end, f"section order invalid: {start_heading}")
    return lines[start : end + 1], start + 1


def markdown_cells(line: str, expected_count: int, context: str) -> list[str] | None:
    stripped = line.strip()
    if not stripped.startswith("|"):
        return None
    require(stripped.endswith("|"), f"{context}: table row lacks final pipe")
    cells = [cell.strip() for cell in stripped[1:-1].split("|")]
    require(
        len(cells) == expected_count,
        f"{context}: expected {expected_count} cells, found {len(cells)}",
    )
    return cells


def parse_prerequisites(cell: str, card_id: str) -> list[str]:
    require(cell.startswith("[") and cell.endswith("]"), f"{card_id}: malformed prerequisites")
    inner = cell[1:-1].strip()
    if not inner:
        return []
    items = [item.strip() for item in inner.split(",")]
    require(all(items), f"{card_id}: empty prerequisite token")
    for item in items:
        require(
            re.fullmatch(r"V30-P\d{2}-C\d{2}", item) is not None,
            f"{card_id}: malformed prerequisite {item!r}",
        )
    require(len(items) == len(set(items)), f"{card_id}: duplicate prerequisite")
    return items


def parse_cards(text: str, blueprint_sha256: str) -> tuple[list[dict], list[dict]]:
    section, section_start = bounded_lines(text, GRAPH_START, GRAPH_END)
    cards: list[dict] = []
    for offset, line in enumerate(section):
        cells = markdown_cells(line, 5, f"card table line {section_start + offset}")
        if cells is None or not cells[0].isdigit():
            continue
        ordinal = int(cells[0])
        match = re.fullmatch(r"(V30-P\d{2}-C\d{2})\s+—\s+(.+)", cells[1])
        require(match is not None, f"card {ordinal}: malformed ID/title cell")
        card_id, title = match.groups()
        prerequisites = parse_prerequisites(cells[3], card_id)
        cards.append(
            {
                "ordinal": ordinal,
                "cardID": card_id,
                "title": title,
                "class": cells[2],
                "directPrerequisites": prerequisites,
                "outcome": cells[4],
                "executionEpoch": execution_epoch(ordinal),
                "planningStatus": planning_status(ordinal),
                "preS10FinalCredit": False,
                "sourceStartLine": section_start + offset,
                "sourceEndLine": section_start + offset,
            }
        )

    require(len(cards) == EXPECTED_CARD_COUNT, f"card count {len(cards)} != {EXPECTED_CARD_COUNT}")
    require([card["ordinal"] for card in cards] == list(range(1, EXPECTED_CARD_COUNT + 1)), "card ordinals are not 1..55")
    require(len({card["cardID"] for card in cards}) == EXPECTED_CARD_COUNT, "duplicate card ID")
    for card in cards:
        require(card["class"] in VALID_CLASSES, f"{card['cardID']}: invalid class")

    ordinal_by_id = {card["cardID"]: card["ordinal"] for card in cards}
    edges: list[dict] = []
    edge_keys: set[tuple[str, str]] = set()
    for card in cards:
        for prerequisite in card["directPrerequisites"]:
            require(prerequisite in ordinal_by_id, f"{card['cardID']}: unknown prerequisite {prerequisite}")
            require(ordinal_by_id[prerequisite] < card["ordinal"], f"{card['cardID']}: prerequisite is not earlier")
            key = (prerequisite, card["cardID"])
            require(key not in edge_keys, f"duplicate direct edge {key}")
            edge_keys.add(key)
            edges.append({"from": prerequisite, "to": card["cardID"]})
    require(len(edges) == EXPECTED_EDGE_COUNT, f"edge count {len(edges)} != {EXPECTED_EDGE_COUNT}")

    counts = {card_class: 0 for card_class in VALID_CLASSES}
    for card in cards:
        counts[card["class"]] += 1
    expected_counts = {
        "FOUNDATION": 11,
        "IMPLEMENTATION": 26,
        "VERIFICATION": 7,
        "INTEGRATION": 5,
        "OWNER_ACTION": 3,
        "VALIDATE_NEXT": 1,
        "DEFER": 1,
        "MONITOR": 1,
    }
    require(counts == expected_counts, f"class counts differ: {counts}")
    prove_acyclic(cards, edges)
    return cards, edges


def execution_epoch(ordinal: int) -> str:
    if 1 <= ordinal <= 37:
        return "PRE_S10_PROVISIONAL"
    if 38 <= ordinal <= 43:
        return "POST_S10_RECONCILIATION"
    if 44 <= ordinal <= 50:
        return "FINAL_ACCEPTANCE"
    if 51 <= ordinal <= 55:
        return "POST_ACCEPTANCE"
    raise GenerationError(f"ordinal outside closed graph: {ordinal}")


def planning_status(ordinal: int) -> str:
    if 1 <= ordinal <= 37:
        return "PRE_S10_PROVISIONAL_ELIGIBLE"
    return "POST_S10_NOT_SELECTABLE"


def prove_acyclic(cards: list[dict], edges: list[dict]) -> None:
    card_ids = [card["cardID"] for card in cards]
    incoming = {card_id: 0 for card_id in card_ids}
    outgoing = {card_id: [] for card_id in card_ids}
    for edge in edges:
        incoming[edge["to"]] += 1
        outgoing[edge["from"]].append(edge["to"])
    ready = [card_id for card_id in card_ids if incoming[card_id] == 0]
    visited: list[str] = []
    while ready:
        node = ready.pop()
        visited.append(node)
        for consumer in outgoing[node]:
            incoming[consumer] -= 1
            if incoming[consumer] == 0:
                ready.append(consumer)
    require(len(visited) == len(card_ids), "card graph is cyclic")


def parse_appendix(text: str, blueprint_sha256: str, cards: list[dict]) -> dict:
    section, section_start = bounded_lines(text, APPENDIX_START, APPENDIX_END)
    valid_ids = {card["cardID"] for card in cards}
    records: list[dict] = []
    for offset, line in enumerate(section):
        cells = markdown_cells(line, 5, f"Appendix A line {section_start + offset}")
        if cells is None or not cells[0].isdigit():
            continue
        ordinal = int(cells[0])
        anchor, requirement, disposition, target_text = cells[1:]
        require(disposition in VALID_DISPOSITIONS, f"Appendix row {ordinal}: invalid disposition")
        targets = re.findall(r"V30-P\d{2}-C\d{2}", target_text)
        require(len(targets) == len(set(targets)), f"Appendix row {ordinal}: duplicate V30 target")
        require(all(target in valid_ids for target in targets), f"Appendix row {ordinal}: unknown V30 target")
        records.append(
            {
                "sourceOrdinal": ordinal,
                "sourceStartLine": section_start + offset,
                "sourceEndLine": section_start + offset,
                "section": "Appendix A",
                "sourceAnchor": anchor,
                "canonicalRequirement": collapse_whitespace(requirement),
                "disposition": disposition,
                "rationale": target_text,
                "targetText": target_text,
                "v30Targets": targets,
                "noCredit": True,
                "rawSourceText": line,
            }
        )
    require(len(records) == EXPECTED_APPENDIX_COUNT, f"Appendix row count {len(records)} != {EXPECTED_APPENDIX_COUNT}")
    require([record["sourceOrdinal"] for record in records] == list(range(1, EXPECTED_APPENDIX_COUNT + 1)), "Appendix ordinals are not 1..97")
    return {
        "schema": "V30V24DispositionProjectionV1",
        "source": {
            "blueprintPath": BLUEPRINT.name,
            "blueprintSha256": blueprint_sha256,
            "section": APPENDIX_START,
        },
        "v24SourcePath": V24_SOURCE_PATH,
        "v24SourceSha256": V24_SOURCE_SHA256,
        "recordCount": len(records),
        "noCredit": True,
        "records": records,
    }


def collapse_whitespace(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def locale_registry(blueprint_sha256: str) -> dict:
    # These are the package's owner-approved initial and next-wave IDs.  Keep
    # identifiers stable and make region/storefront/jurisdiction independent
    # facts explicit in the projection.
    localizations = [
        {
            "id": "en",
            "language": "English",
            "script": "Latin",
            "formattingProfiles": ["en-US", "en-GB"],
            "metadataLanguage": "English (US)",
        },
        {
            "id": "es",
            "language": "Spanish",
            "script": "Latin",
            "formattingProfiles": ["es-US", "es-MX", "es-419"],
            "metadataLanguage": "Spanish (Mexico)",
        },
        {
            "id": "zh-Hans",
            "language": "Chinese",
            "script": "Simplified",
            "formattingProfiles": ["zh-Hans-US", "zh-Hans-CN"],
            "metadataLanguage": "Chinese (Simplified)",
        },
        {
            "id": "zh-Hant",
            "language": "Chinese",
            "script": "Traditional",
            "formattingProfiles": ["zh-Hant-US", "zh-Hant-TW"],
            "metadataLanguage": "Chinese (Traditional)",
        },
        {
            "id": "vi",
            "language": "Vietnamese",
            "script": "Latin",
            "formattingProfiles": ["vi-US", "vi-VN"],
            "metadataLanguage": "Vietnamese",
        },
        {
            "id": "ko",
            "language": "Korean",
            "script": "Hangul",
            "formattingProfiles": ["ko-US", "ko-KR"],
            "metadataLanguage": "Korean",
        },
    ]
    return {
        "schema": "V30LocaleRegistryV1",
        "source": {
            "blueprintPath": BLUEPRINT.name,
            "blueprintSha256": blueprint_sha256,
            "sections": ["9.2 Required initial cohort", "9.6 LocaleMarketMatrixV1", "10.1 System-first rule"],
        },
        "storefrontCountries": ["US"],
        "storefrontPolicy": "UNITED_STATES_ONLY",
        "projectJurisdiction": "US",
        "completeBinaryLocalizationIDs": INITIAL_LOCALES,
        "initialLocales": localizations,
        "nextWaveLocaleIDs": NEXT_WAVE_LOCALES,
        "nextWaveOrder": NEXT_WAVE_LOCALES,
        "selectionPolicy": {
            "systemFirst": True,
            "applePreferredLanguages": True,
            "applePerAppLanguage": True,
            "inAppPicker": "SETTINGS_DISCOVERY_ONLY",
            "unsupportedLanguageFallback": "en",
            "defaultLanguage": "en",
            "fallbackChain": ["exactLocale", "baseLanguage", "en"],
            "regionDoesNotSelectLanguage": True,
            "languageDoesNotSelectJurisdiction": True,
        },
    }


def build_outputs(text: str, blueprint_sha256: str) -> dict[str, bytes]:
    cards, edges = parse_cards(text, blueprint_sha256)
    appendix = parse_appendix(text, blueprint_sha256, cards)
    source = {
        "blueprintPath": BLUEPRINT.name,
        "blueprintSha256": blueprint_sha256,
        "section": GRAPH_START,
    }
    card_register = {
        "schema": "V30CardRegisterV1",
        "source": source,
        "cardCount": len(cards),
        "edgeCount": len(edges),
        "cards": cards,
    }
    graph = {
        "schema": "V30DirectDependencyGraphV1",
        "source": source,
        "cardCount": len(cards),
        "edgeCount": len(edges),
        "edges": edges,
    }
    values = {
        "cards": card_register,
        "graph": graph,
        "locales": locale_registry(blueprint_sha256),
        "v24": appendix,
    }
    return {key: encode_json(value) for key, value in values.items()}


def encode_json(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def first_difference(expected: bytes, actual: bytes) -> str:
    limit = min(len(expected), len(actual))
    for index in range(limit):
        if expected[index] != actual[index]:
            start = max(0, index - 20)
            end = min(limit, index + 20)
            return f"byte {index}: expected {expected[start:end]!r}, actual {actual[start:end]!r}"
    return f"length differs: expected {len(expected)}, actual {len(actual)}"


def check_outputs(expected: dict[str, bytes]) -> None:
    for key, path in OUTPUTS.items():
        require(path.is_file(), f"missing output {path.name}")
        actual = path.read_bytes()
        require(actual == expected[key], f"{path.name}: {first_difference(expected[key], actual)}")
        require(not actual.startswith(b"\xef\xbb\xbf"), f"{path.name}: UTF-8 BOM")
        require(b"\r" not in actual, f"{path.name}: CR/CRLF present")
        require(actual.endswith(b"\n"), f"{path.name}: missing final LF")
        require(
            all(line == line.rstrip(b" \t") for line in actual.splitlines()),
            f"{path.name}: trailing whitespace",
        )
        try:
            json.loads(actual.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise GenerationError(f"{path.name}: invalid JSON: {exc}") from exc


def apply_outputs(expected: dict[str, bytes]) -> None:
    for key, path in OUTPUTS.items():
        path.write_bytes(expected[key])


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="write the four projections")
    mode.add_argument("--check", action="store_true", help="verify exact existing bytes without writing")
    return parser.parse_args(list(argv))


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    text, blueprint_sha256 = read_blueprint()
    expected = build_outputs(text, blueprint_sha256)
    if args.apply:
        apply_outputs(expected)
        check_outputs(expected)
        print("PASS_APPLY")
    else:
        check_outputs(expected)
        print("PASS_CHECK")
    for key, path in OUTPUTS.items():
        print(f"{path.name}: {sha256_bytes(expected[key])}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (GenerationError, FileNotFoundError) as exc:
        print(json.dumps({"result": "FAIL", "reason": str(exc)}, sort_keys=True))
        raise SystemExit(1)
