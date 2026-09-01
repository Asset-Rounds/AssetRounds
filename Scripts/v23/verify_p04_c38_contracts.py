#!/usr/bin/env python3
"""Verify C38's deterministic artifacts, corpus, source seam, and fence."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p04_c38_contracts as contracts


def _require(condition: bool, failure: str, failures: list[str]) -> None:
    if not condition:
        failures.append(failure)


def _read_text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _read_json(path: str) -> Any:
    return contracts.read_json(path)


def _validate_corpus(failures: list[str]) -> None:
    path = contracts.PRODUCT[3]
    try:
        corpus = _read_json(path)
    except (OSError, ValueError) as error:
        failures.append(f"corpus:{error}")
        return
    _require(isinstance(corpus, dict), "corpus must be an object", failures)
    if not isinstance(corpus, dict):
        return
    _require(set(corpus) == set(contracts.CORPUS_TOP_LEVEL_KEYS), "corpus top-level key set differs", failures)
    _require(corpus.get("schema") == contracts.CORPUS_SCHEMA, "corpus schema differs", failures)
    _require(corpus.get("schemaVersion") == 1 and type(corpus.get("schemaVersion")) is int, "corpus schemaVersion differs", failures)
    _require(corpus.get("cardID") == contracts.CARD, "corpus cardID differs", failures)
    _require(corpus.get("testOnly") is True and corpus.get("synthetic") is True, "corpus must be test-only synthetic data", failures)
    _require(corpus.get("containsCustomerData") is False and corpus.get("containsSecrets") is False, "corpus data boundary differs", failures)
    _require(corpus.get("evidenceIDs") == list(contracts.SELECTORS), "corpus evidence IDs differ", failures)
    _require(corpus.get("golden") == contracts.CORPUS_GOLDEN, "corpus golden grammar differs", failures)
    _require(corpus.get("alternate") == contracts.CORPUS_ALTERNATE, "corpus alternate semantics differ", failures)
    _require(corpus.get("hostileCases") == contracts.CORPUS_HOSTILE_CASES, "corpus hostile cases differ", failures)
    _require(corpus.get("interruptionCases") == contracts.CORPUS_INTERRUPTION_CASES, "corpus interruption cases differ", failures)
    _require(corpus.get("recoveryCases") == contracts.CORPUS_RECOVERY_CASES, "corpus recovery cases differ", failures)
    _require(corpus.get("persistence") == contracts.CORPUS_PERSISTENCE, "corpus persistence boundary differs", failures)
    _require(corpus.get("claims") == contracts.CORPUS_CLAIMS, "corpus claims differ", failures)
    _require(all(value is False for value in corpus.get("claims", {}).values()), "corpus claims must all be false", failures)


def _validate_flags(documents: dict[str, Any], failures: list[str]) -> bool:
    all_false = True
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        flags = document.get("flags") if isinstance(document, dict) else None
        ok = flags == contracts.FLAGS and document.get("finalHashesSealed") is False
        all_false = all_false and ok
        _require(ok, f"artifact flags/final hash boundary differs: {path}", failures)
    return all_false


def _validate_documents(documents: dict[str, Any], expected: dict[str, Any], failures: list[str]) -> None:
    expected_paths = {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST}
    _require(set(documents) == expected_paths, "artifact set differs", failures)
    for path in expected_paths:
        _require(documents.get(path) == expected.get(path), f"deterministic artifact differs: {path}", failures)
    contract = documents.get(contracts.CONTRACT, {})
    if not isinstance(contract, dict):
        failures.append("contract is not an object")
        return
    _require(contract.get("contract") == "AdvancedRecurrenceWorkflowContractV1", "contract identity differs", failures)
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "contract evidence IDs differ", failures)
    _require(contract.get("scenarioRows") == list(contracts.SCENARIO_ROWS), "contract scenario mapping differs", failures)
    requirements = contract.get("requirements", {})
    for key in (
        "boundedClosedRecurrenceGrammar", "deterministicOccurrenceIdentity", "exceptionPrecedence", "completedOccurrenceImmutable",
        "dstRecovery", "timezoneRecovery", "clockChangeRecovery", "reminderReconciliation", "exactInterruptionReplay",
        "expectedRevisionMutationID", "oneCanonicalWriterTransaction", "durableReceipt", "effectBeforeReceiptRecovery",
        "noCron", "noRRULE", "noServer", "noCalendarIntegration", "noBackgroundExecution", "noHolidayDatabase",
        "noSecondRecurrenceEngine", "noNewDurableFamily", "noNewModel", "noNewSchema", "noNewMigration", "noNewStore",
        "noNewWriter", "fiveEvidenceScenarios", "finalHashesUnsealed",
    ):
        _require(requirements.get(key) is True, f"contract requirement disabled: {key}", failures)
    expected_values = {
        "exceptionScopes": ["THIS_OCCURRENCE", "THIS_AND_FUTURE", "ENTIRE_SERIES"],
        "canonicalOwners": ["V23-P03-C51", "V23-P04-C22"],
        "reinspectionOwner": "V23-P04-C12",
        "persistentSchema": "V53",
        "totalModelCount": 168,
        "scenarioSelectors": list(contracts.SELECTORS),
        "futureReentry": "CLOSED_TYPED_REENTRY_ONLY",
    }
    for key, value in expected_values.items():
        _require(requirements.get(key) == value, f"contract requirement differs: {key}", failures)
    evidence = documents.get(contracts.EVIDENCE, {})
    _require(isinstance(evidence, dict) and evidence.get("receipt") == "AdvancedRecurrenceWorkflowEvidenceReceiptV1", "evidence receipt identity differs", failures)
    _require(isinstance(evidence, dict) and evidence.get("acceptanceCredit") is False, "evidence acceptance credit must be false", failures)
    brand = documents.get(contracts.BRAND, {})
    _require(isinstance(brand, dict) and brand.get("requiresAcceptedS10_6Reconciliation") is True and brand.get("uiAdoptionSkipped") is True, "brand reconciliation/skip boundary differs", failures)
    manifest = documents.get(contracts.MANIFEST, {})
    _require(isinstance(manifest, dict) and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence differs", failures)
    _require(isinstance(manifest, dict) and manifest.get("counts", {}).get("fencePathCount") == 14 and manifest.get("counts", {}).get("existingPathCount") == 1 and manifest.get("counts", {}).get("newPathCount") == 13, "manifest counts differ", failures)


def _method_bodies(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"\bfunc\s+(testV23P04C38[GAHIR]01\w*)\s*\([^)]*\)[^{]*\{", text))
    result: dict[str, str] = {}
    for match in matches:
        depth = 0
        end = match.end() - 1
        for index in range(end, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    result[match.group(1)] = text[match.start():index + 1]
                    break
    return result


def _swift_code(text: str) -> str:
    """Return Swift tokens with comments removed for negative integration scans."""
    text = re.sub(r"(?s)/\*.*?\*/", " ", text)
    return re.sub(r"//[^\r\n]*", " ", text)


def _validate_source(failures: list[str]) -> None:
    coordinator = _read_text(contracts.PRODUCT[0])
    view = _read_text(contracts.PRODUCT[1])
    tests = _read_text(contracts.PRODUCT[2])
    ui = _read_text(contracts.PRODUCT[4])
    schedule_owner = _read_text(contracts.EXISTING_PATHS[0])
    fixture = _read_json(contracts.PRODUCT[3])
    required_coordinator = (
        "AdvancedRecurrenceWorkflowCoordinatorV1", "AdvancedRecurrenceWorkflowProjectionV1", "AdvancedRecurrenceWorkflowCommandV1",
        "projection", "execute", "recover", "AdvancedRecurrenceRuleV1", "ScheduleCoordinatorV1",
        "schedule.recordOverride", "schedule.generateFrozen", "occurrence", "override", "reminder", "completed",
    )
    for token in required_coordinator:
        _require(token in coordinator, f"coordinator token missing: {token}", failures)
    for token in ("ScheduleCoordinatorV1", ".appendOverrideEvent", ".generateOccurrences", "private func commit", "acceptedScheduleMutation", "applySchedule"):
        _require(token in schedule_owner, f"existing schedule owner token missing: {token}", failures)
    for token in ("ScheduleDefinitionReleaseRow", "OccurrenceHistoryEventRow", "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow", "WorkspaceWriterV1"):
        _require(token not in coordinator, f"C38 coordinator directly accesses canonical owner token: {token}", failures)
    source_code = _swift_code(coordinator + "\n" + view + "\n" + tests)
    for token in ("occurrenceID", "identityPredecessorOccurrenceID", "TimeContextRule", "nonexistentGap", "ambiguousFold", "clockDisposition", "ScheduleOverridePrecedenceV1", "ScheduleOccurrenceGeneratorV1", "ScheduleReminderLifecycleV1"):
        _require(token in source_code, f"C38 source semantic token missing: {token}", failures)
    for token in ("Advanced recurrence", "exception", "due", "reminder", "history", "DST"):
        _require(token.lower() in view.lower(), f"view token missing: {token}", failures)
    forbidden = (
        r"\bEventKit\b", r"\bEKEventStore\b", r"\bEKCalendar\b", r"\bUNUserNotificationCenter\b", r"\bCloudKit\b",
        r"\bURLSession\b", r"\bURLRequest\b", r"\bNWConnection\b", r"\bWebSocket\b", r"\bOAuth\b", r"\bKeychain\w*\b",
        r"\bSecItem\w*\b", r"\bcron\b", r"\bRRULE\b", r"\bholiday\s+database\b", r"\bCalendarServer\b",
    )
    for pattern in forbidden:
        _require(re.search(pattern, source_code, re.IGNORECASE) is None, f"prohibited recurrence integration token: {pattern}", failures)
    _require(re.search(r"\b(?:class|struct|actor|enum|protocol)\s+\w*(?:Store|Writer|Renderer|Backend|Importer|Engine)\w*", coordinator + "\n" + view, re.IGNORECASE) is None, "parallel recurrence infrastructure declaration", failures)
    _require("V23-P04-C38" in ui and len(re.findall(r"throw\s+XCTSkip\s*\(", ui)) == 1, "UI lane must have one no-launch skip", failures)
    _require(re.search(r"\b(?:XCUIApplication|app)\s*\(?.*\)?\.launch\s*\(", ui, re.IGNORECASE) is None, "UI lane must not launch", failures)

    methods = _method_bodies(tests)
    found: dict[str, str] = {}
    for name, body in methods.items():
        match = re.search(r"testV23P04C38([GAHIR]01)", name)
        if match:
            identifier = match.group(1)
            _require(identifier not in found, f"duplicate evidence method: {identifier}", failures)
            found[identifier] = body
    _require(tuple(found) == ("G01", "A01", "H01", "I01", "R01"), "test evidence method order differs", failures)
    terms = {
        "G01": ("daily", "weekly", "monthlyday", "monthlyweekday", "calendar_day", "weekday", "last_day", "interval", "occurrence", "deterministic"),
        "A01": ("override", "leap", "monthend", "lastweekday", "scope", "allcases", "kind", "addone"),
        "H01": ("throws", "invalid", "stale", "budget", "conflicting", "identity"),
        "I01": ("timecontextrule", "nonexistentgap", "ambiguousfold", "clock", "reminder", "cancel", "effectbefore", "retry"),
        "R01": ("immutable", "replay", "rebuilt", "decode", "completed", "divergent"),
    }
    for identifier, required in terms.items():
        body = found.get(identifier, "").lower().replace(" ", "")
        for token in required:
            _require(token.lower().replace(" ", "") in body, f"{identifier} test lacks semantic coverage: {token}", failures)
    for token in (".skip", ".move", ".addOne"):
        _require(token in tests, f"A01 override kind missing: {token}", failures)
    _require("ScheduleMutationV1" in tests and "ScheduleCoordinatorV1" in tests, "tests do not bind canonical schedule owners", failures)
    _require(fixture.get("schema") == contracts.CORPUS_SCHEMA and fixture.get("claims") == contracts.CORPUS_CLAIMS, "source fixture parse differs", failures)


def _validate_fence(failures: list[str]) -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in contracts.git(*args).splitlines() if line}

    changed = names("diff", "--name-only", contracts.BASE, "HEAD") | names("diff", "--name-only", "HEAD") | names("diff", "--cached", "--name-only") | names("ls-files", "--others", "--exclude-standard")
    unowned = changed - set(contracts.PATH_FENCE)
    _require(not unowned, "unowned changed paths: " + ",".join(sorted(unowned)), failures)
    return {
        "changedPathCount": len(changed & set(contracts.PATH_FENCE)),
        "unownedChangedPathCount": len(unowned),
        "missingPathCount": sum(not (ROOT / path).is_file() for path in contracts.PATH_FENCE),
        "s10ReservationOverlapCount": 0,
        "fencePathCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW),
        "productTestUIFixturePathCount": len(contracts.PRODUCT),
        "toolingPathCount": len(contracts.OWNED),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all five source paths")
    parser.add_argument("--json", action="store_true", help="emit JSON result")
    args = parser.parse_args()
    failures: list[str] = []
    counts: dict[str, int] = {}
    try:
        authority = contracts.authority()
    except Exception as error:  # fail closed while keeping machine-readable diagnostics
        failures.append(f"authority:{error}")
        authority = {}
    try:
        source_rows, source_ready = contracts.rows()
    except Exception as error:
        failures.append(f"sourceRows:{error}")
        source_rows, source_ready = [], False
    _validate_corpus(failures)
    try:
        expected = contracts.documents()
    except Exception as error:
        failures.append(f"documents:{error}")
        expected = {}
    documents: dict[str, Any] = {}
    for path in (contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST):
        try:
            documents[path] = _read_json(path)
        except (OSError, ValueError) as error:
            failures.append(f"artifact:{error}")
    if expected and len(documents) == 5:
        _validate_documents(documents, expected, failures)
        flags_all_false = _validate_flags(documents, failures)
    else:
        flags_all_false = False
    if source_ready:
        try:
            _validate_source(failures)
        except (OSError, ValueError) as error:
            failures.append(f"source:{error}")
    elif args.complete:
        failures.append("complete:missing C38 source paths")
    try:
        counts = _validate_fence(failures)
    except Exception as error:
        failures.append(f"fence:{error}")
    result = {
        "cardID": contracts.CARD,
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC",
        "sourceReady": source_ready,
        "finalHashesSealed": contracts.FINAL_HASHES_SEALED,
        "flagsAllFalse": flags_all_false,
        "failures": failures,
        "counts": counts,
        "fencePathCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW),
        "productTestUIFixturePathCount": len(contracts.PRODUCT),
        "toolingPathCount": len(contracts.OWNED),
        "selectors": list(contracts.SELECTORS),
        "authoritySequence": contracts.SEQUENCE,
    }
    print(json.dumps(result, sort_keys=True, indent=2 if args.json else None))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
