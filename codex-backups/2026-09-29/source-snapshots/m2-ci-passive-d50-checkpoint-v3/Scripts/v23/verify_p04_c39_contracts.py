#!/usr/bin/env python3
"""Verify C39 artifacts, source semantics, corpus, and exact hydration fence."""

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

import p04_c39_contracts as contracts


def _require(condition: bool, failure: str, failures: list[str]) -> None:
    if not condition:
        failures.append(failure)


def _read_text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _read_json(path: str) -> Any:
    return contracts.read_json(path)


def _validate_corpus(failures: list[str]) -> None:
    path = contracts.PRODUCT[8]
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
    _require(corpus.get("scenarioIDs") == contracts.CORPUS_SCENARIO_IDS, "corpus scenario IDs differ", failures)
    _require(corpus.get("thresholds") == contracts.CORPUS_THRESHOLDS, "corpus thresholds differ", failures)
    _require(corpus.get("boundaryVectors") == contracts.CORPUS_BOUNDARY_VECTORS, "corpus boundary vectors differ", failures)
    _require(corpus.get("includedReadbacks") == contracts.CORPUS_INCLUDED_READBACKS, "corpus included readbacks differ", failures)
    _require(corpus.get("excludedCompletionCases") == contracts.CORPUS_EXCLUDED_COMPLETIONS, "corpus excluded completion cases differ", failures)
    _require(corpus.get("activeContextSuppressions") == contracts.CORPUS_ACTIVE_CONTEXTS, "corpus active context suppressions differ", failures)
    _require(corpus.get("ledgerStates") == contracts.CORPUS_LEDGER_STATES, "corpus ledger states differ", failures)
    _require(corpus.get("interruptionVectors") == contracts.CORPUS_INTERRUPTION_CASES, "corpus interruption vectors differ", failures)
    _require(corpus.get("truth") == contracts.CORPUS_TRUTH, "corpus truth boundary differs", failures)
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
    _require(contract.get("contract") == "RatingSupportWorkflowContractV1", "contract identity differs", failures)
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "contract evidence IDs differ", failures)
    _require(contract.get("scenarioRows") == list(contracts.SCENARIO_ROWS), "contract scenario mapping differs", failures)
    requirements = contract.get("requirements", {})
    required_true = (
        "closedTypedWorkflow",
        "modernAppStoreRequestReview",
        "sceneBoundRequest",
        "solePreferencesAdapter",
        "soleEraseAllService",
        "s6_6EraseRecoveryRegression",
        "deviceLocalNonWorkspaceLedger",
        "persistedLedgerExcludesCustomerWorkspaceActivitySnapshotReceiptIdentifiers",
        "threeDistinctFinalizedActivitySeries",
        "minimumSevenDays",
        "stableMarketingVersion",
        "naturalIdleStoppingPoint",
        "matchingFinalizationReceiptAndCurrentFinalizedSnapshot",
        "oneAttemptPerMarketingVersion",
        "minimum120DaysBetweenAttempts",
        "maximumTwoAttemptsPerRollingYear",
        "supportAlwaysVisible",
        "supportIndependentOfRating",
        "noPromptDisplayRecording",
        "noStarRecording",
        "noReviewRecording",
        "noSubmissionRecording",
        "noStoreResponseRecording",
        "noConversionRecording",
        "noTelemetry",
        "noAnalytics",
        "noNetwork",
        "noMarketingWrites",
        "noContactWrites",
        "noDeprecatedRequestAPI",
        "noCustomRatingDialog",
        "noNewDurableFamily",
        "noNewModel",
        "noNewSchema",
        "noNewMigration",
        "noNewStore",
        "noNewWriter",
        "noParallelRenderer",
        "noParallelBackend",
        "fiveEvidenceScenarios",
        "finalHashesUnsealed",
    )
    for key in required_true:
        _require(requirements.get(key) is True, f"contract requirement disabled: {key}", failures)
    _require(requirements.get("requestAPI") == "AppStore.requestReview(in:)", "contract request API differs", failures)
    _require(requirements.get("excludedSeries") == contracts.EXCLUDED_SERIES, "contract exclusions differ", failures)
    _require(requirements.get("suppressionContexts") == contracts.SUPPRESSION_CONTEXTS, "contract suppression contexts differ", failures)
    _require(requirements.get("scenarioSelectors") == list(contracts.SELECTORS), "contract selectors differ", failures)
    for key, value in {
        "resetDisposition": "PRESERVE_LEDGER",
        "eraseDisposition": "ERASED_COOLDOWN_365_DAYS",
        "freshInstallDisposition": "ABSENT_FRESH_INSTALL_EARNS_THRESHOLD",
        "corruptFutureMigrationFailureDisposition": "DISABLE_AUTO_REQUEST",
        "duplicateInvocationDisposition": "IDEMPOTENT",
        "appDeathDisposition": "AT_MOST_ONE_CONSERVATIVE_ATTEMPT",
        "missingAppStoreIdentity": "TYPED_DISABLED_RATING_LINK",
    }.items():
        _require(requirements.get(key) == value, f"contract requirement differs: {key}", failures)
    evidence = documents.get(contracts.EVIDENCE, {})
    _require(isinstance(evidence, dict) and evidence.get("receipt") == "RatingSupportWorkflowEvidenceReceiptV1", "evidence receipt identity differs", failures)
    _require(isinstance(evidence, dict) and evidence.get("acceptanceCredit") is False, "evidence acceptance credit must be false", failures)
    brand = documents.get(contracts.BRAND, {})
    _require(isinstance(brand, dict) and brand.get("requiresAcceptedS10_6Reconciliation") is True and brand.get("uiAdoptionSkipped") is True, "brand reconciliation/skip boundary differs", failures)
    _require(isinstance(brand, dict) and brand.get("supportAlwaysVisible") is True and brand.get("supportIndependentOfRating") is True, "brand support independence differs", failures)
    manifest = documents.get(contracts.MANIFEST, {})
    _require(isinstance(manifest, dict) and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence differs", failures)
    _require(
        isinstance(manifest, dict)
        and manifest.get("counts", {}).get("fencePathCount") == 18
        and manifest.get("counts", {}).get("existingPathCount") == 3
        and manifest.get("counts", {}).get("newPathCount") == 15
        and manifest.get("counts", {}).get("productTestUIFixturePathCount") == 7
        and manifest.get("counts", {}).get("toolingPathCount") == 8,
        "manifest counts differ",
        failures,
    )


def _method_bodies(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"\bfunc\s+(testV23P04C39[GAHIR]01\w*)\s*\([^)]*\)[^{]*\{", text))
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


def _normalized(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def _validate_source(failures: list[str]) -> None:
    contracts_source = _read_text(contracts.PRODUCT[0])
    coordinator = _read_text(contracts.PRODUCT[1])
    adapter = _read_text(contracts.PRODUCT[2])
    preferences = _read_text(contracts.EXISTING_PATHS[0])
    erase = _read_text(contracts.EXISTING_PATHS[1])
    erase_tests = _read_text(contracts.EXISTING_PATHS[2])
    view = _read_text(contracts.PRODUCT[6])
    tests = _read_text(contracts.PRODUCT[7])
    ui = _read_text(contracts.PRODUCT[9])
    fixture = _read_json(contracts.PRODUCT[8])

    source_code = _swift_code("\n".join((contracts_source, coordinator, adapter, view, tests, ui)))
    owner_code = _swift_code("\n".join((preferences, erase, erase_tests)))
    for token in (
        "RatingEligibilityPolicyV1",
        "RatingEligibilityReasonV1",
        "RatingEligibleCompletionProjectionV1",
        "RatingRequestAttemptLedgerStateV1",
        "RatingRequestAttemptV1",
        "RatingRequestAdapterV1",
        "RateAppLinkV1",
    ):
        _require(token in source_code, f"C39 contract/source token missing: {token}", failures)
    for token in ("RatingEligibilityCoordinatorV1", "project", "requestIfEligible", "eligible", "finalized", "RatingEligibilityProjectionV1"):
        _require(token.lower() in coordinator.lower(), f"C39 coordinator token missing: {token}", failures)
    for token in ("PreferencesAdapterV1", "RatingEligibilityStoreV1", "load", "compareAndSwap", "ratingEligibility", "UserDefaults"):
        _require(token.lower() in preferences.lower(), f"PreferencesAdapter owner token missing: {token}", failures)
    for token in ("EraseAllService", "RatingEligibilityCoordinatorV1", "applyCompletedErase", "ERASED_COOLDOWN", "eraseCooldownSeconds"):
        _require(token.lower() in owner_code.lower(), f"Erase owner/recovery token missing: {token}", failures)
    for token in ("S6_6", "EraseAllService", "ERASED_COOLDOWN", "rating-eligibility.v1"):
        _require(token.lower() in erase_tests.lower(), f"S6_6 erase regression token missing: {token}", failures)
    adapter_code = _swift_code(adapter)
    coordinator_code = _swift_code(coordinator)
    contracts_code = _swift_code(contracts_source)
    for token in ("RatingNativeRequestPreparationV1", "prepareRequest"):
        _require(token.lower() in contracts_code.lower(), f"scene preparation contract token missing: {token}", failures)
    for token in (
        "func prepareRequest() -> RatingNativeRequestPreparationV1?",
        "activeWindowSceneProvider()",
        "RatingNativeRequestPreparationV1 {",
        "AppStore.requestReview(in: scene)",
        "return nil",
    ):
        _require(token in adapter_code, f"scene preparation adapter token missing: {token}", failures)
    for token in ("nativeRequest.prepareRequest()", "preparedRequest.invoke()"):
        _require(token in coordinator_code, f"scene preparation coordinator token missing: {token}", failures)
    _require("precondition" not in adapter_code.lower() + coordinator_code.lower(), "scene preparation uses a precondition", failures)
    _require("AppStore.requestReview(in: scene)" in adapter_code, "modern AppStore.requestReview(in:) call missing", failures)
    _require("SKStoreReviewController" not in source_code, "deprecated SKStoreReviewController request path", failures)
    _require(re.search(r"\b(?:star|stars|rating)\b.{0,40}\b(?:dialog|sheet|survey|picker)\b", source_code, re.IGNORECASE) is None, "custom rating dialog or rating pre-screen", failures)
    for token in ("Support", "Recovery", "Rate AssetRounds", "RATE_LINK_DISABLED_UNVERIFIED_APP_STORE_ID", "always"):
        _require(token.lower() in view.lower(), f"support view token missing: {token}", failures)
    lifecycle_aliases = {
        "device-local ledger": ("DEVICE_LOCAL_NONWORKSPACE", "ratingeligibility", "rating-eligibility"),
        "reset preservation": ("PRESERVE_LEDGER", "preserved", "applySettingsReset"),
        "erase cooldown": ("ERASED_COOLDOWN", "eraseCooldown", "eraseCooldownSeconds"),
        "disabled recovery": ("DISABLE_AUTO_REQUEST", "ledgerCorrupt", "ledgerFutureVersion", "ledgerMigrationFailed"),
    }
    for label, aliases in lifecycle_aliases.items():
        _require(any(alias.lower() in (source_code + owner_code).lower() for alias in aliases), f"lifecycle token missing: {label}", failures)

    # These are explicitly forbidden even when the host platform happens to
    # expose them.  Comments were removed so explanatory blueprint text cannot
    # trigger this scan.
    for pattern in (
        r"\bURLSession\b",
        r"\bURLRequest\b",
        r"\bNWConnection\b",
        r"\bWebSocket\b",
        r"\bCloudKit\b",
        r"\bMetricKit\b",
        r"\bAnalytics(?:Kit|SDK|Service|Client)\b",
        r"\bTelemetry(?:Kit|SDK|Service|Client)\b",
        r"\bFirebase\b",
        r"\bAmplitude\b",
        r"\bMixpanel\b",
        r"\bSKStoreReviewController\b",
        r"\bEventKit\b",
        r"\bUserActivity\b",
    ):
        _require(re.search(pattern, source_code, re.IGNORECASE) is None, f"prohibited C39 integration token: {pattern}", failures)
    for token in contracts.FORBIDDEN_PERSISTED_IDENTIFIERS:
        # The attempt ledger is intentionally not allowed to carry workspace,
        # customer, activity, snapshot, receipt, or review identity.
        _require(token.lower() not in _normalized(adapter), f"persisted ledger identity token present: {token}", failures)
    _require(re.search(r"\b(?:class|struct|actor|enum|protocol)\s+\w*(?:Store|Writer|Renderer|Backend|Telemetry|Network|Marketing|Contact)\w*", coordinator + "\n" + view, re.IGNORECASE) is None, "parallel C39 infrastructure declaration", failures)
    _require("V23-P04-C39" in ui and len(re.findall(r"throw\s+XCTSkip\s*\(", ui)) == 1, "UI lane must have one no-launch skip", failures)
    _require(re.search(r"\b(?:XCUIApplication|app)\s*\(?.*\)?\.launch\s*\(", ui, re.IGNORECASE) is None, "UI lane must not launch", failures)

    methods = _method_bodies(tests)
    found: dict[str, str] = {}
    for name, body in methods.items():
        match = re.search(r"testV23P04C39([GAHIR]01)", name)
        if match:
            identifier = match.group(1)
            _require(identifier not in found, f"duplicate evidence method: {identifier}", failures)
            found[identifier] = body
    _require(tuple(found) == ("G01", "A01", "H01", "I01", "R01"), "test evidence method order differs", failures)
    terms = {
        "G01": ("finalized", "receipt", "snapshot", "3", "7", "systemconsideration", "support"),
        "A01": ("version", "120", "rolling", "365", "boundaries", "eligible"),
        "H01": ("exclusions", "contexts", "hostile", "ledgers", "failclosed", "importedhistory", "evaluationcounted", "corrupt", "future", "migration", "rollback", "unverified", "disabled"),
        "I01": ("reserved", "call", "kill", "relaunch", "duplicate", "invoke", "atmostonce"),
        "R01": ("reset", "erase", "cooldown", "fresh", "reearn", "365", "customer"),
    }
    for identifier, required in terms.items():
        body = _normalized(found.get(identifier, ""))
        for token in required:
            _require(_normalized(token) in body, f"{identifier} test lacks semantic coverage: {token}", failures)
    _require(
        "prepareRequest" in tests and "preparationCount" in tests and "callCount" in tests,
        "tests do not cover prepared native adapter call",
        failures,
    )
    _require("RatingEligibilityStoreV1" in tests and "C39Store" in tests, "tests do not bind the C39 store seam", failures)
    for token in (
        "hasExactEraseCooldown",
        "persistentDomainName: defaultsDomainName",
        "activated.eraseID",
        "ratingErase.receipt.operationID == activated.eraseID",
        "ratingErase.receipt.resultingRevision == ratingLedger.revision",
        "ratingErase.receipt.stateSHA256 == ratingLedger.stateSHA256",
    ):
        _require(token in erase, f"exact erase cooldown preservation token missing: {token}", failures)
    for token in (
        "suppressUntil.timeIntervalSince(erasedAt)",
        "Set(remainingDefaults.keys), Set([\"rating-eligibility.v1\"])",
        "ratingLedger.attempts.isEmpty",
    ):
        _require(token in erase_tests, f"S6_6 exact cooldown evidence token missing: {token}", failures)
    _require(
        fixture.get("schema") == contracts.CORPUS_SCHEMA
        and fixture.get("scenarioIDs") == contracts.CORPUS_SCENARIO_IDS
        and fixture.get("thresholds") == contracts.CORPUS_THRESHOLDS
        and fixture.get("boundaryVectors") == contracts.CORPUS_BOUNDARY_VECTORS
        and fixture.get("includedReadbacks") == contracts.CORPUS_INCLUDED_READBACKS
        and fixture.get("excludedCompletionCases") == contracts.CORPUS_EXCLUDED_COMPLETIONS
        and fixture.get("activeContextSuppressions") == contracts.CORPUS_ACTIVE_CONTEXTS
        and fixture.get("ledgerStates") == contracts.CORPUS_LEDGER_STATES
        and fixture.get("interruptionVectors") == contracts.CORPUS_INTERRUPTION_CASES
        and fixture.get("truth") == contracts.CORPUS_TRUTH
        and fixture.get("claims") == contracts.CORPUS_CLAIMS,
        "source fixture parse differs",
        failures,
    )


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
        "productTestUIFixturePathCount": contracts.NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT,
        "toolingPathCount": len(contracts.OWNED),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all ten source paths")
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
        failures.append("complete:missing C39 source paths")
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
        "productTestUIFixturePathCount": contracts.NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT,
        "toolingPathCount": len(contracts.OWNED),
        "selectors": list(contracts.SELECTORS),
        "authoritySequence": contracts.SEQUENCE,
    }
    print(json.dumps(result, sort_keys=True, indent=2 if args.json else None))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
