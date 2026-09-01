#!/usr/bin/env python3
"""Verify C41 tooling artifacts, source semantics, corpus, and path fence."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p04_c41_contracts as contracts


def _require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _read_text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _read_json(path: str) -> Any:
    return contracts.read_json(path)


def _validate_corpus(failures: list[str]) -> None:
    try:
        corpus = _read_json(contracts.NEW_PRODUCT_PATHS[4])
    except (OSError, ValueError) as error:
        failures.append(f"corpus:{error}")
        return
    _require(isinstance(corpus, dict), "corpus must be an object", failures)
    if not isinstance(corpus, dict):
        return
    expected = contracts._corpus_expectations()
    _require(set(corpus) == set(contracts.CORPUS_TOP_LEVEL_KEYS), "corpus top-level key set differs", failures)
    for key, value in expected.items():
        _require(corpus.get(key) == value, f"corpus {key} differs", failures)
    _require(all(value is False for value in corpus.get("claims", {}).values()), "corpus claims must all be false", failures)


def _validate_flags(documents: dict[str, Any], failures: list[str]) -> bool:
    result = True
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        flags = document.get("flags") if isinstance(document, dict) else None
        ok = isinstance(document, dict) and flags == contracts.FLAGS and document.get("finalHashesSealed") is False
        result = result and ok
        _require(ok, f"artifact flags/final hash boundary differs: {path}", failures)
    return result


def _validate_documents(documents: dict[str, Any], expected: dict[str, Any], failures: list[str]) -> None:
    expected_paths = {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST}
    _require(set(documents) == expected_paths, "artifact set differs", failures)
    for path in expected_paths:
        _require(documents.get(path) == expected.get(path), f"deterministic artifact differs: {path}", failures)
    contract = documents.get(contracts.CONTRACT, {})
    _require(isinstance(contract, dict) and contract.get("contract") == "MyDayWorkflowContractV1", "contract identity differs", failures)
    if not isinstance(contract, dict):
        return
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "contract evidence IDs differ", failures)
    _require(contract.get("scenarioRows") == list(contracts.SCENARIO_ROWS), "contract scenario mapping differs", failures)
    requirements = contract.get("requirements", {})
    for key in (
        "manualOrderOnly",
        "manualMoveActions",
        "draftPreviewZeroWrite",
        "summaryProjectionDerived",
        "summaryProjectionNonpersistent",
        "summaryProjectionRebuildable",
        "dueReadinessDurationCuesReadOnly",
        "typedExistingStartResumeIntent",
        "routeRequestDoesNotClaimStarted",
        "explicitCarryover",
        "explicitReconciliation",
        "c57CanonicalWriterAndReplayReused",
        "c22DueTruthReadOnly",
        "c12ReadinessAndResumeReadOnly",
        "noNewModel",
        "noNewSchemaFamily",
        "noNewStore",
        "noNewWriter",
        "noNewMigration",
        "noNewRouteEngine",
        "noNewRoot",
        "noNewRenderer",
        "noBackend",
        "noNetwork",
        "noTelemetry",
        "fiveEvidenceScenarios",
        "finalHashesUnsealed",
    ):
        if key == "manualMoveActions":
            _require(requirements.get(key) == ["UP", "DOWN", "TO_INDEX"], "contract manual move actions differ", failures)
        else:
            _require(requirements.get(key) is True, f"contract requirement disabled: {key}", failures)
    for key in (
        "automaticPrioritization",
        "automaticCarryover",
        "automaticSorting",
        "automaticScheduling",
        "sourceMutation",
        "storedReadinessProjection",
        "storedSummaryProjection",
        "estimatedDurationIsActualDuration",
        "hostedDependency",
    ):
        _require(requirements.get(key) is False, f"prohibited claim boundary differs: {key}", failures)
    _require(requirements.get("scenarioSelectors") == list(contracts.SELECTORS), "contract selectors differ", failures)
    _require(requirements.get("carryoverEligibleStates") == ["ACTIVE", "REOPENED"], "carryover eligible states differ", failures)
    _require(requirements.get("carryoverExcludedStates") == contracts.CARRYOVER["excludedStates"], "carryover excluded states differ", failures)
    _require(contract.get("directPrerequisites") == contracts.DIRECT_PREREQUISITES, "contract prerequisite edges differ", failures)
    _require(contract.get("contractRefs") == contracts.CONTRACT_REFS, "contract references differ", failures)
    evidence = documents.get(contracts.EVIDENCE, {})
    _require(isinstance(evidence, dict) and evidence.get("receipt") == "MyDayWorkflowEvidenceReceiptV1", "evidence receipt identity differs", failures)
    _require(isinstance(evidence, dict) and evidence.get("acceptanceCredit") is False, "evidence acceptance credit differs", failures)
    brand = documents.get(contracts.BRAND, {})
    _require(isinstance(brand, dict) and brand.get("requiresAcceptedS10_6Reconciliation") is True, "brand S10 reconciliation differs", failures)
    _require(isinstance(brand, dict) and brand.get("uiAdoptionSkipped") is True and brand.get("uiAcceptanceCredit") is False, "brand UI boundary differs", failures)
    manifest = documents.get(contracts.MANIFEST, {})
    _require(isinstance(manifest, dict) and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence differs", failures)
    counts = manifest.get("counts", {}) if isinstance(manifest, dict) else {}
    for key, expected_value in {
        "fencePathCount": 18,
        "existingPathCount": 4,
        "newPathCount": 14,
        "productTestUIFixturePathCount": 7,
        "toolingPathCount": 8,
        "durableFamilyCount": 0,
        "modelDeltaCount": 0,
        "schemaDeltaCount": 0,
        "migrationCount": 0,
        "storeDeltaCount": 0,
        "writerDeltaCount": 0,
        "rendererDeltaCount": 0,
        "backendDeltaCount": 0,
        "s10ReservationOverlapCount": 0,
    }.items():
        _require(counts.get(key) == expected_value, f"manifest count differs: {key}", failures)


def _swift_code(text: str) -> str:
    text = re.sub(r"(?s)/\*.*?\*/", " ", text)
    return re.sub(r"//[^\r\n]*", " ", text)


def _normalized(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def _method_bodies(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    pattern = re.compile(r"\bfunc\s+(testV23P04C41\w*)\s*\([^)]*\)[^{]*\{")
    for match in pattern.finditer(text):
        depth = 0
        start = match.end() - 1
        for index in range(start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    result[match.group(1)] = text[match.start() : index + 1]
                    break
    return result


def _validate_source(failures: list[str]) -> None:
    canonical = _swift_code(_read_text(contracts.EXISTING_PATHS[0]))
    workspace_contracts = _swift_code(_read_text(contracts.EXISTING_PATHS[1]))
    workspace_coordinator = _swift_code(_read_text(contracts.EXISTING_PATHS[2]))
    harness = _swift_code(_read_text(contracts.EXISTING_PATHS[3]))
    workflow_contracts = _swift_code(_read_text(contracts.NEW_PRODUCT_PATHS[0]))
    coordinator = _swift_code(_read_text(contracts.NEW_PRODUCT_PATHS[1]))
    view = _swift_code(_read_text(contracts.NEW_PRODUCT_PATHS[2]))
    tests_raw = _read_text(contracts.NEW_PRODUCT_PATHS[3])
    tests = _swift_code(tests_raw)
    fixture = _read_text(contracts.NEW_PRODUCT_PATHS[4])
    ui_raw = _read_text(contracts.NEW_PRODUCT_PATHS[5])
    ui = _swift_code(ui_raw)
    source = "\n".join((canonical, workspace_contracts, workspace_coordinator, harness, workflow_contracts, coordinator, view, tests, ui))
    new_source = "\n".join((workflow_contracts, coordinator, view))

    for token in (
        "MyDayWorkflowFailureV1",
        "MyDayPlanDraftV1",
        "MyDayAccessibleMoveV1",
        "MyDayExistingRouteIntentV1",
        "MyDayExistingRouteActionV1",
        "MyDaySummaryItemV1",
        "MyDaySummaryProjectionV1",
        "MyDaySavePreviewV1",
        "MyDayCarryoverPreviewV1",
        "MyDayWorkflowCommandV1",
        "MyDayWorkflowOutcomeV1",
    ):
        _require(token in source, f"C41 contract/source token missing: {token}", failures)

    for token in (
        "MyDayWritingV1",
        "commit(",
        "replay(",
        "MyDayCommandReplayResolutionV1",
        "reconcileLocalReminders",
    ):
        _require(token in canonical, f"C57 canonical writer/replay token missing: {token}", failures)
    for token in ("recoverSave", "recoverCarryover", "MyDayCommandReplayResolutionV1"):
        _require(token in canonical, f"C57 executable recovery seam missing: {token}", failures)
    for token in ("save(", "carryover(", "readinessProjection(", "currentPlan("):
        _require(token in canonical, f"C57 canonical operation missing: {token}", failures)

    for token in (
        "func draft(",
        "func move(",
        "func previewSave(",
        "func summary(",
        "func routeIntent(",
        "func previewCarryover(",
        "func execute(",
        "canonical.save(",
        "canonical.carryover(",
    ):
        _require(token in coordinator, f"C41 workflow API missing: {token}", failures)
    for token in (
        "manualOrder",
        "automaticPrioritizationApplied",
        "scheduleTruthMutated",
        "derived = true",
        "rebuildable = true",
        "zeroWrite = true",
        "carryoverEligible",
        "MyDayExistingRouteActionV1",
        "case start",
        "case resume",
    ):
        _require(token in workflow_contracts, f"C41 workflow semantic token missing: {token}", failures)
    for token in ("MyDayReadinessProjectionV1", "OccurrenceDueQueueStateV1", "ExceptionQueueProjectionV1"):
        _require(token in workflow_contracts, f"C41 read-only provider token missing: {token}", failures)
    for token in ("TodayMyDayCompositionV1", "root = .today"):
        _require(token in workspace_contracts, f"Today composition contract token missing: {token}", failures)
    _require("todayMyDay(" in workspace_coordinator, "Today composition coordinator seam missing", failures)
    for token in ("C57MyDayCoordinatorLifecycleBoundaryV1", "sourceMutationCount", "storedDerivedProjectionCount"):
        _require(token in canonical, f"C57 lifecycle boundary token missing: {token}", failures)
    for token in ("C22RecurringRoundMyDayBoundaryV1", "storedQueueProjectionCount", "storedReminderReconciliationCount"):
        _require(token in canonical, f"C22 read-only boundary token missing: {token}", failures)

    _require("items.map(\\.item.manualOrder) == Array(0..<items.count)" in workflow_contracts, "manual order invariant missing", failures)
    _require("!automaticPrioritizationApplied" in workflow_contracts and "!scheduleTruthMutated" in workflow_contracts, "automatic/schedule mutation guards missing", failures)
    _require("sourceSummary.carryoverEligibleMembershipIDs" in coordinator, "explicit carryover eligibility seam missing", failures)
    _require("routeIntent" in workflow_contracts and "routeRequested = false" in workflow_contracts and "workStarted = false" in workflow_contracts, "typed route intent truth missing", failures)
    _require("readinessProjection" in coordinator and "dueQueue" in coordinator and "exceptionQueue" in coordinator, "derived source reconciliation inputs missing", failures)

    # New C41 production files may not declare infrastructure owners or bring
    # in a network/telemetry/backend/root route.  Existing C57 ownership is
    # intentionally checked separately above.
    _require(re.search(r"\b(?:class|struct|actor|enum|protocol)\s+\w*(?:Store|Writer|Renderer|Importer|Backend|Network|Telemetry|RouteEngine|Root)\w*", new_source, re.IGNORECASE) is None, "parallel C41 infrastructure declaration", failures)
    for pattern in (r"\bURLSession\b", r"\bURLRequest\b", r"\bNWConnection\b", r"\bWebSocket\b", r"\bCloudKit\b", r"\bMetricKit\b", r"\bFirebase\b", r"\bAmplitude\b", r"\bMixpanel\b", r"\bEventKit\b"):
        _require(re.search(pattern, new_source, re.IGNORECASE) is None, f"prohibited C41 integration token: {pattern}", failures)

    _require("MyDayWorkflowView" in view, "contained My Day view missing", failures)
    for token in ("manual order", "Derived readiness", "Start or resume", "Explicit carryover", "Reconciliation"):
        _require(token.lower() in view.lower(), f"My Day view binding missing: {token}", failures)
    _require("V23-P04-C41" in ui, "UI lane does not bind C41", failures)
    _require(len(re.findall(r"throw\s+XCTSkip\s*\(", ui_raw)) == 1, "UI lane must have one no-launch skip", failures)
    _require(re.search(r"\b(?:XCUIApplication|app)\s*\([^)]*\)\s*\.launch\s*\(", ui, re.IGNORECASE) is None, "UI lane must not launch", failures)
    _require("rootAdoptionEnabled = false" in ui and "nativeLaunchAdoptionEnabled = false" in ui, "UI adoption boundary differs", failures)

    # XCTest assertion arguments are autoclosures; awaited expressions are
    # invalid there.  Scan balanced assertion calls so multiline calls are
    # covered without depending on formatting.
    for match in re.finditer(r"\bXCTAssert[A-Za-z0-9_]*\s*\(", tests_raw):
        depth = 0
        end = None
        for index in range(match.end() - 1, len(tests_raw)):
            if tests_raw[index] == "(":
                depth += 1
            elif tests_raw[index] == ")":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is not None:
            _require("await" not in tests_raw[match.start() : end], "await inside XCTest assertion autoclosure", failures)

    methods = _method_bodies(tests)
    found: dict[str, str] = {}
    for name, body in methods.items():
        match = re.search(r"testV23P04C41([GAHIR]01)", name)
        if match:
            identifier = match.group(1)
            _require(identifier not in found, f"duplicate evidence method: {identifier}", failures)
            found[identifier] = body
    _require(tuple(found) == ("G01", "A01", "H01", "I01", "R01"), "test evidence method order differs", failures)
    terms = {
        "G01": (("selection", "draft"), ("manual", "order"), ("summary",), ("zeroWrite", "zero write"), ("route", "start", "resume"), ("carryover",), ("reconcile",)),
        "A01": (("move", "accessible"), ("estimate",), ("lifecycle", "completed", "cancelled", "reopened"), ("summary",)),
        "H01": (("hostile", "identity", "wrong"), ("duplicate", "validvalid"), ("stale",), ("mutation",), ("automaticPrioritization", "automatic")),
        "I01": (("effect",), ("receipt",), ("recover", "replay"), ("exact",), ("mutation",)),
        "R01": (("rebuild", "rebuilt"), ("carryover",), ("history",), ("namespace",), ("preserve",)),
    }
    for identifier, required in terms.items():
        body = _normalized(found.get(identifier, ""))
        for aliases in required:
            _require(any(_normalized(token) in body for token in aliases), f"{identifier} test lacks semantic coverage: {'/'.join(aliases)}", failures)
    _require("V9_104MyDayWorkflowTests" in tests and "testV23P04C41" in tests, "tests do not bind C41 workflow", failures)

    try:
        fixture_value = json.loads(fixture)
    except json.JSONDecodeError as error:
        failures.append(f"source fixture JSON malformed: {error}")
        fixture_value = {}
    _require(isinstance(fixture_value, dict), "source fixture must be an object", failures)
    if isinstance(fixture_value, dict):
        _require(fixture_value == contracts._corpus_expectations(), "source fixture corpus differs", failures)


def _validate_fence(failures: list[str]) -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in contracts.git(*args).splitlines() if line}

    changed = (
        names("diff", "--name-only", contracts.BASE, "HEAD")
        | names("diff", "--name-only", "HEAD")
        | names("diff", "--cached", "--name-only")
        | names("ls-files", "--others", "--exclude-standard")
    )
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
        "productTestUIFixturePathCount": contracts.NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT,
        "toolingPathCount": len(contracts.OWNED),
        "durableFamilyCount": 0,
        "modelDeltaCount": 0,
        "schemaDeltaCount": 0,
        "migrationCount": 0,
        "storeDeltaCount": 0,
        "writerDeltaCount": 0,
        "rendererDeltaCount": 0,
        "backendDeltaCount": 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every C41 product/test/UI/fixture source path")
    parser.add_argument("--json", action="store_true", help="emit a JSON result")
    args = parser.parse_args()
    failures: list[str] = []
    try:
        contracts.authority()
    except Exception as error:
        failures.append(f"authority:{error}")
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
        failures.append("complete:missing C41 source paths")
    try:
        counts = _validate_fence(failures)
    except Exception as error:
        failures.append(f"fence:{error}")
        counts = {}
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
        "productTestUIFixturePathCount": contracts.NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT,
        "toolingPathCount": len(contracts.OWNED),
        "selectors": list(contracts.SELECTORS),
        "authoritySequence": contracts.SEQUENCE,
        "sourceRows": source_rows,
    }
    print(json.dumps(result, sort_keys=True, indent=2 if args.json else None))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
