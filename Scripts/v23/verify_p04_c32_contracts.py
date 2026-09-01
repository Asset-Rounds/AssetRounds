from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c32_contracts as c


CORPUS_SCHEMA = "V23P04C32PartyContactSiteRoleImportCorpusV1"
CORPUS_SCHEMA_VERSION = 1
CORPUS_CARD = "V23-P04-C32"
CORPUS_ORDINAL = 117

SELECTOR_ROWS = (
    ("G01", "V23-P04-C32-G01", "GOLDEN"),
    ("A01", "V23-P04-C32-A01", "ALTERNATE"),
    ("H01", "V23-P04-C32-H01", "HOSTILE"),
    ("I01", "V23-P04-C32-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C32-R01", "RECOVERY"),
)
SELECTOR_METHODS = (
    "testV23P04C32G01PreviewFirstMultiFilePartyContactAndSiteRoleMigrationGolden",
    "testV23P04C32A01ExplicitKeyBindingSharedRoleCorrectionAndReversalAlternate",
    "testV23P04C32H01HostileIdentityUnicodeFormulaAndBudgetFailClosed",
    "testV23P04C32I01CancellationChunkInterruptionAndRestoreNoPartialClaim",
    "testV23P04C32R01ReceiptReplayBackupRestoreJournalReplicationAndPrivacyRecovery",
)
SOURCE_SCHEMA_ROWS = (
    ("PARTIES_V1", 0),
    ("PARTY_CONTACTS_V1", 1),
    ("SITE_PARTY_ROLES_V1", 2),
)

# The fixture is the source of truth for the expanded status flag union. The
# generated tooling artifacts intentionally carry the older eight-flag
# projection used by the existing C32 contracts module.
CORPUS_FLAG_KEYS = frozenset(
    (
        "acceptance",
        "activation",
        "adoption",
        "hosted",
        "hostedAcceptance",
        "native",
        "nativeAcceptance",
        "physicalDevice",
        "physicalEvidence",
        "publication",
        "release",
    )
)
GENERATED_FLAG_KEYS = frozenset(
    (
        "acceptance",
        "activation",
        "adoption",
        "hosted",
        "native",
        "physicalDevice",
        "publication",
        "release",
    )
)
UI_SKIP_FLAG_NAMES = (
    "activationEnabled",
    "adoptionEnabled",
    "acceptanceEnabled",
    "nativeEnabled",
    "hostedEnabled",
    "releaseEnabled",
)

EXPECTED_TOP_LEVEL_KEYS = frozenset(
    (
        "cardID",
        "expected",
        "ordinal",
        "scenarios",
        "schema",
        "schemaVersion",
        "selectors",
        "statusFlags",
        "synthetic",
    )
)
EXPECTED_EXPECTED_KEYS = frozenset(
    (
        "atomicityPolicy",
        "contactDefaultExportEnabled",
        "externalKeyBinding",
        "fuzzyMatching",
        "oneCanonicalWriter",
        "previewWritesCanonicalState",
        "scratchRetainedAfterTerminalState",
        "sourceOrder",
    )
)
EXPECTED_SELECTOR_KEYS = frozenset(("id", "selector", "tier"))
EXPECTED_SCENARIO_KEYS = frozenset(("id", "kind", "covers"))
SCENARIO_ROWS = (
    ("G01", "GOLDEN", ("deterministic_preview", "exact_key_create", "shared_party", "source_order", "zero_write")),
    ("A01", "ALTERNATE", ("exact_key_update", "correction", "reversal", "shared_role", "contact_free_export")),
    ("H01", "HOSTILE", ("ambiguous_target", "bidi", "budget", "cross_workspace", "duplicate_key", "formula", "malformed_contact", "nfd", "nul", "retired_target", "stale_digest", "stale_revision")),
    ("I01", "INTERRUPTION", ("cancellation", "no_partial_claim", "scratch_cleanup")),
    ("R01", "RECOVERY", ("backup_restore", "journal", "receipt_replay", "replication", "single_effect")),
)
COORDINATOR = "FieldEvidenceApp/Application/ImportExport/PartyContactSiteRoleImportCoordinatorV1.swift"


def _read_json(path: str) -> object:
    target = c.ROOT / path
    if not target.is_file():
        raise ValueError(f"missing JSON source: {path}")
    try:
        return json.loads(target.read_bytes().decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"malformed JSON source: {path}") from error


def _read_text(path: str) -> str:
    target = c.ROOT / path
    if not target.is_file():
        raise ValueError(f"missing text source: {path}")
    try:
        return target.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"malformed UTF-8 source: {path}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _is_exact_false_flags(value: object, keys: frozenset[str]) -> bool:
    return (
        isinstance(value, dict)
        and set(value) == set(keys)
        and all(type(value[key]) is bool and value[key] is False for key in keys)
    )


def _load_generated_documents(expected: dict[str, object]) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for path in expected:
        value = _read_json(path)
        _require(isinstance(value, dict), f"artifact is not an object: {path}")
        result[path] = value
    return result


def _derive_flags_all_false(
    corpus: object, generated: dict[str, dict[str, object]]
) -> bool:
    """Derive the report flag from the bytes on disk, including the corpus."""

    if not isinstance(corpus, dict) or not _is_exact_false_flags(corpus.get("statusFlags"), CORPUS_FLAG_KEYS):
        return False
    if set(generated) != {c.CONTRACT, c.EVIDENCE, c.BRAND, c.MANIFEST}:
        return False
    return all(_is_exact_false_flags(value.get("flags"), GENERATED_FLAG_KEYS) for value in generated.values())


def _validate_generated_flags(corpus: dict[str, object], generated: dict[str, dict[str, object]]) -> None:
    _require(
        _is_exact_false_flags(corpus.get("statusFlags"), CORPUS_FLAG_KEYS),
        "corpus statusFlags must contain exactly the required all-false keys",
    )
    for path, value in generated.items():
        _require(
            _is_exact_false_flags(value.get("flags"), GENERATED_FLAG_KEYS),
            f"artifact flags must contain exactly the required all-false keys: {path}",
        )


def _normalise_source_schema_rows(value: object) -> tuple[tuple[str, int], ...]:
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return tuple((item, index) for index, item in enumerate(value))
    if isinstance(value, list) and all(isinstance(item, dict) for item in value):
        rows: list[tuple[str, int]] = []
        for item in value:
            _require(
                set(item) in ({"schema", "orderIndex"}, {"schemaID", "orderIndex"}),
                "source schema row keys differ",
            )
            schema = item.get("schema", item.get("schemaID"))
            order_index = item.get("orderIndex")
            _require(isinstance(schema, str), "source schema identifier is not text")
            _require(type(order_index) is int, "source schema orderIndex is not an integer")
            rows.append((schema, order_index))
        return tuple(rows)
    raise ValueError("source schema order shape differs")


def _validate_source_schema_order(expected: dict[str, object], coordinator: str) -> None:
    values = [
        expected[key]
        for key in ("sourceSchemaOrder", "sourceOrder", "sourceSchemas")
        if key in expected
    ]
    _require(len(values) == 1, "expected source schema order must have exactly one representation")
    _require(_normalise_source_schema_rows(values[0]) == SOURCE_SCHEMA_ROWS, "corpus source schema order differs")

    enum_start = coordinator.find("enum PartyContactSiteRoleImportSourceKindV1")
    order_start = coordinator.find("var orderIndex: Int", enum_start)
    descriptor_start = coordinator.find(
        "struct PartyContactSiteRoleImportSourceDescriptorV1", order_start
    )
    _require(
        enum_start >= 0 and order_start > enum_start and descriptor_start > order_start,
        "source schema order declarations missing",
    )

    raw_rows = re.findall(
        r"(?m)^\s*case\s+([A-Za-z_]\w*)\s*=\s*\"([^\"]+)\"\s*$",
        coordinator[enum_start:order_start],
    )
    _require(
        tuple(raw_rows)
        == (
            ("parties", "PARTIES_V1"),
            ("partyContacts", "PARTY_CONTACTS_V1"),
            ("sitePartyRoles", "SITE_PARTY_ROLES_V1"),
        ),
        "source schema raw values differ",
    )
    order_rows = re.findall(
        r"(?m)^\s*case\s+\.([A-Za-z_]\w*)\s*:\s*(\d+)\s*$",
        coordinator[order_start:descriptor_start],
    )
    _require(
        tuple((name, int(index)) for name, index in order_rows)
        == (("parties", 0), ("partyContacts", 1), ("sitePartyRoles", 2)),
        "source schema orderIndex values differ",
    )
    _require("orderIndex: $0.kind.orderIndex" in coordinator, "source manifest does not bind orderIndex")


def _validate_expected_semantics(
    corpus: dict[str, object], contract: dict[str, object], source_text: str
) -> None:
    expected = corpus.get("expected")
    _require(isinstance(expected, dict), "corpus expected section is not an object")
    _require(
        set(expected) == EXPECTED_EXPECTED_KEYS,
        "corpus expected key set differs",
    )

    required = (
        "previewWritesCanonicalState",
        "oneCanonicalWriter",
        "fuzzyMatching",
        "contactDefaultExportEnabled",
        "scratchRetainedAfterTerminalState",
    )
    for key in required:
        _require(key in expected, f"corpus expected.{key} is missing")
    _require(expected["previewWritesCanonicalState"] is False, "previewWritesCanonicalState must be false")
    _require(expected["oneCanonicalWriter"] is True, "oneCanonicalWriter must be true")
    _require(expected["fuzzyMatching"] is False, "fuzzyMatching must be false")
    _require(expected["contactDefaultExportEnabled"] is False, "contactDefaultExportEnabled must be false")
    _require(expected["scratchRetainedAfterTerminalState"] is False, "scratchRetainedAfterTerminalState must be false")

    _require(
        expected["atomicityPolicy"] == "ONE_ROOT_ALL_OR_NOTHING",
        "atomicityPolicy must be ONE_ROOT_ALL_OR_NOTHING",
    )
    _require(
        expected["externalKeyBinding"] == "EXACT_ONLY",
        "externalKeyBinding must be EXACT_ONLY",
    )

    _validate_source_schema_order(expected, _read_text(COORDINATOR))

    requirements = contract.get("requirements")
    _require(isinstance(requirements, dict), "generated contract requirements are missing")
    _require(
        requirements.get("sourceSchemaOrder") == ["PARTY", "OPERATIONAL_CONTACT", "SITE_ROLE"],
        "generated source schema order differs",
    )
    _require(requirements.get("exactKeyOnly") is True, "generated exact-key binding differs")
    _require(requirements.get("fuzzyMatching") is False, "generated fuzzy matching differs")
    _require(requirements.get("previewZeroWrite") is True, "generated preview write policy differs")
    _require(requirements.get("allOrNothing") is True, "generated atomicity policy differs")
    _require(requirements.get("safeDefaultExport") is True, "generated default export policy differs")

    lifecycle = contract.get("lifecycle")
    _require(isinstance(lifecycle, dict), "generated lifecycle is missing")
    _require(lifecycle.get("previewWrites") == 0, "generated preview write count differs")
    _require(lifecycle.get("atomicRootCount") == 1, "generated atomic root count differs")
    _require(lifecycle.get("newWriterCount") == 0, "generated writer count differs")

    for token in (
        "externalKeyColumn",
        "stableExternalKey",
        "exactStableKeyCreate",
        "exactStableKeyUpdate",
        "discardScratch",
        "allOrNothing",
    ):
        _require(token in source_text, f"source semantic token missing: {token}")


def _validate_selector_rows(corpus: dict[str, object], test_text: str) -> None:
    rows = corpus.get("selectors")
    _require(isinstance(rows, list) and len(rows) == 5, "corpus must contain exactly five selector rows")
    expected_rows = tuple(
        {"id": id_, "selector": selector, "tier": tier}
        for id_, selector, tier in SELECTOR_ROWS
    )
    actual_rows: list[dict[str, object]] = []
    for row in rows:
        _require(
            isinstance(row, dict) and set(row) == EXPECTED_SELECTOR_KEYS,
            "selector row keys differ",
        )
        actual_rows.append(row)
    _require(tuple(actual_rows) == expected_rows, "selector rows or tiers differ")

    _require(tuple(c.SELECTORS) == SELECTOR_METHODS, "selector method constants differ")
    declared = re.findall(
        r"(?m)^\s*func\s+(testV23P04C32[A-Za-z0-9]+)\s*\(", test_text
    )
    _require(tuple(declared) == SELECTOR_METHODS, "selector method declarations differ")
    for method in SELECTOR_METHODS:
        _require(test_text.count(f"func {method}(") == 1, f"selector method is not unique: {method}")


def _validate_scenario_rows(corpus: dict[str, object]) -> None:
    rows = corpus.get("scenarios")
    _require(isinstance(rows, list) and len(rows) == len(SCENARIO_ROWS), "corpus scenario count differs")
    actual: list[tuple[str, str, tuple[str, ...]]] = []
    for row in rows:
        _require(isinstance(row, dict) and set(row) == EXPECTED_SCENARIO_KEYS, "scenario row keys differ")
        identifier, kind, covers = row.get("id"), row.get("kind"), row.get("covers")
        _require(isinstance(identifier, str) and isinstance(kind, str), "scenario identity differs")
        _require(isinstance(covers, list) and all(isinstance(value, str) for value in covers), "scenario coverage differs")
        _require(len(covers) == len(set(covers)), "scenario coverage contains duplicates")
        actual.append((identifier, kind, tuple(covers)))
    _require(tuple(actual) == SCENARIO_ROWS, "scenario rows, tiers, or coverage differ")


def _validate_ui_skip_tokens(ui_text: str) -> None:
    skip_method = "testV23P04C32PartyContactSiteRoleImportUIIsDeferredPendingS106"
    _require(
        len(re.findall(rf"(?m)^\s*func\s+{skip_method}\s*\(", ui_text)) == 1,
        "UI skip method differs",
    )
    for name in UI_SKIP_FLAG_NAMES:
        declaration = re.findall(
            rf"(?m)^\s*private\s+static\s+let\s+{re.escape(name)}\s*=\s*(true|false)\s*$",
            ui_text,
        )
        _require(declaration == ["false"], f"UI skip flag declaration differs: {name}")
        assertions = re.findall(
            rf"\bXCTAssertFalse\s*\(\s*Self\.{re.escape(name)}\s*\)", ui_text
        )
        _require(len(assertions) == 1, f"UI skip flag assertion differs: {name}")
    _require(
        len(re.findall(r"\bthrow\s+XCTSkip\s*\(", ui_text)) == 1,
        "UI must have exactly one actual XCTSkip token",
    )
    _require(
        "V23-P04-C32" in ui_text and "S10.6" in ui_text,
        "UI skip reason does not name the deferred C32/S10.6 boundary",
    )


def _validate_corpus(
    corpus: object,
    generated: dict[str, dict[str, object]],
    expected_docs: dict[str, dict[str, object]],
) -> None:
    _require(isinstance(corpus, dict), "corpus is not an object")
    _require(set(corpus) == EXPECTED_TOP_LEVEL_KEYS, "corpus top-level key set differs")
    _require(corpus.get("schema") == CORPUS_SCHEMA, "corpus schema differs")
    _require(
        type(corpus.get("schemaVersion")) is int
        and corpus.get("schemaVersion") == CORPUS_SCHEMA_VERSION,
        "corpus schemaVersion differs",
    )
    _require(
        corpus.get("cardID") == CORPUS_CARD == c.CARD,
        "corpus cardID differs",
    )
    _require(
        type(corpus.get("ordinal")) is int and corpus.get("ordinal") == CORPUS_ORDINAL,
        "corpus ordinal differs",
    )
    _require(corpus.get("synthetic") is True, "corpus synthetic flag must be true")
    _validate_selector_rows(corpus, _read_text(c.TEST))
    _validate_scenario_rows(corpus)
    _validate_expected_semantics(corpus, generated[c.CONTRACT], _read_text(COORDINATOR))
    _validate_generated_flags(corpus, generated)
    _validate_ui_skip_tokens(_read_text(c.UI))

    # Keep the artifact check authoritative even if a future generated
    # document adds a semantically similar field under a different name.
    for path, expected in expected_docs.items():
        actual = generated[path]
        _require(actual.get("cardID") == c.CARD, f"artifact cardID differs: {path}")
        _require(actual.get("schema") == expected.get("schema"), f"artifact schema differs: {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    failures: list[str] = []
    ready = False
    counts: dict[str, int] = {}
    flags_all_false = False
    generated: dict[str, dict[str, object]] = {}
    try:
        c.authority()
        _, ready = c.rows()
        c.semantics(ready)
        counts = c.counts()
        expected_docs = c.documents()
        _require(
            len(c.PATH_FENCE) == 30 and len(set(c.PATH_FENCE)) == 30,
            "fence must contain exactly 30 unique paths",
        )
        generated = _load_generated_documents(expected_docs)
        corpus = _read_json(c.FIXTURE)
        flags_all_false = _derive_flags_all_false(corpus, generated)
        if ready:
            _validate_corpus(corpus, generated, expected_docs)
        for path, value in expected_docs.items():
            if not (c.ROOT / path).is_file() or (c.ROOT / path).read_bytes() != c.pretty(value):
                failures.append("artifact-drift:" + path)
        if counts.get("unownedChangedPathCount") or counts.get("s10ReservationOverlapCount"):
            failures.append("fence:unowned-or-S10")
        if args.complete and not ready:
            failures.append("complete:source-lanes-pending")
    except Exception as error:
        failures.append("contracts:" + str(error))

    output = {
        "cardID": c.CARD,
        "result": "FAIL_STATIC" if failures else "PASS_STATIC_PROVISIONAL",
        "sourceReady": ready,
        "finalHashesSealed": c.FINAL_HASHES_SEALED,
        "flagsAllFalse": flags_all_false,
        "failures": failures,
        "counts": counts,
        "fencePathCount": 30,
        "existingPathCount": 16,
        "newPathCount": 14,
        "selectors": list(c.SELECTORS),
    }
    print(json.dumps(output, sort_keys=True, indent=2) if args.json else output["result"])
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
