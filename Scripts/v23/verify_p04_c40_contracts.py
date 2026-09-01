#!/usr/bin/env python3
"""Verify C40 artifacts, corpus, source semantics, and the exact fence."""

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

import p04_c40_contracts as contracts


def _require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _read_text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _read_json(path: str) -> Any:
    return contracts.read_json(path)


def _validate_corpus(failures: list[str]) -> None:
    try:
        corpus = _read_json(contracts.PRODUCT[8])
    except (OSError, ValueError) as error:
        failures.append(f"corpus:{error}")
        return
    _require(isinstance(corpus, dict), "corpus must be an object", failures)
    if not isinstance(corpus, dict):
        return
    _require(set(corpus) == set(contracts.CORPUS_TOP_LEVEL_KEYS), "corpus top-level key set differs", failures)
    checks = (
        (corpus.get("schema"), contracts.CORPUS_SCHEMA, "corpus schema"),
        (corpus.get("schemaVersion"), 1, "corpus schemaVersion"),
        (corpus.get("cardID"), contracts.CARD, "corpus cardID"),
        (corpus.get("testOnly"), True, "corpus testOnly"),
        (corpus.get("synthetic"), True, "corpus synthetic"),
        (corpus.get("containsCustomerData"), False, "corpus customer-data boundary"),
        (corpus.get("containsSecrets"), False, "corpus secret boundary"),
        (corpus.get("sources"), contracts.SOURCES, "corpus sources"),
        (corpus.get("states"), contracts.STATES, "corpus states"),
        (corpus.get("dispositions"), contracts.DISPOSITIONS, "corpus dispositions"),
        (corpus.get("scenarios"), contracts.CORPUS_SCENARIOS, "corpus scenarios"),
        (corpus.get("evidenceIDs"), list(contracts.SELECTORS), "corpus evidence IDs"),
        (corpus.get("hostileCases"), contracts.HOSTILE_CASES, "corpus hostile cases"),
        (corpus.get("interruptionBoundaries"), contracts.INTERRUPTION_BOUNDARIES, "corpus interruption boundaries"),
        (corpus.get("lifecycle"), contracts.LIFECYCLE, "corpus lifecycle"),
        (corpus.get("truth"), contracts.TRUTH, "corpus truth"),
        (corpus.get("claims"), contracts.CLAIMS, "corpus claims"),
    )
    for actual, expected, label in checks:
        _require(actual == expected, f"{label} differs", failures)
    _require(all(value is False for value in corpus.get("claims", {}).values()), "corpus claims must all be false", failures)


def _validate_flags(documents: dict[str, Any], failures: list[str]) -> bool:
    result = True
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        flags = document.get("flags") if isinstance(document, dict) else None
        ok = flags == contracts.FLAGS and isinstance(document, dict) and document.get("finalHashesSealed") is False
        result = result and ok
        _require(ok, f"artifact flags/final hash boundary differs: {path}", failures)
    return result


def _validate_documents(documents: dict[str, Any], expected: dict[str, Any], failures: list[str]) -> None:
    expected_paths = {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST}
    _require(set(documents) == expected_paths, "artifact set differs", failures)
    for path in expected_paths:
        _require(documents.get(path) == expected.get(path), f"deterministic artifact differs: {path}", failures)
    contract = documents.get(contracts.CONTRACT, {})
    if not isinstance(contract, dict):
        failures.append("contract is not an object")
        return
    _require(contract.get("contract") == "ServiceRequestWorkflowContractV1", "contract identity differs", failures)
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "contract evidence IDs differ", failures)
    _require(contract.get("scenarioRows") == list(contracts.SCENARIO_ROWS), "contract scenario mapping differs", failures)
    requirements = contract.get("requirements", {})
    for key in (
        "manualCapture",
        "portableCapture",
        "todayWorkSiteAssetNoFifthRoot",
        "interruptionSafeDrafts",
        "previewZeroWrite",
        "duplicateReasonsSuggestionOnly",
        "separateCreateWork",
        "immutableRequestWorkLink",
        "customerSafeStatus",
        "statusDoesNotClaimReceiptOrDelivery",
        "searchableNeedsTriageProjection",
        "needsTriageDerivedRebuildable",
        "purposeNamespacedPortableDrafts",
        "reviewGrammarAndQuotaUnmixed",
        "recipientModeEntitlementIndependent",
        "portableFilesCleartextInV23",
        "portableServiceKindsRejectedByEnvelope",
        "c14CanonicalApplyOnly",
        "noNewRoot",
        "noNewStore",
        "noNewWriter",
        "noNewImporter",
        "noNewRenderer",
        "noNewModel",
        "noNewSchemaFamily",
        "noNewMigration",
        "noBackend",
        "noNetwork",
        "noTelemetry",
        "noMarketingWrites",
        "noContactWrites",
        "fiveEvidenceScenarios",
        "finalHashesUnsealed",
    ):
        _require(requirements.get(key) is True, f"contract requirement disabled: {key}", failures)
    for key in (
        "requesterIdentityVerified",
        "requesterAuthorityVerified",
        "contactVerified",
        "urgencyVerified",
        "deliveryConfirmed",
        "emergencyIntake",
        "portalAvailable",
        "slaPromised",
        "automaticDuplicateMerge",
        "automaticWorkCreation",
        "encryptedServiceRequestV1",
        "marketingConsent",
        "telemetryWritten",
    ):
        _require(requirements.get(key) is False, f"prohibited claim boundary differs: {key}", failures)
    _require(requirements.get("explicitDispositions") == contracts.DISPOSITIONS, "contract dispositions differ", failures)
    _require(requirements.get("statusFormats") == ["PDF", "TEXT"], "contract status formats differ", failures)
    _require(requirements.get("scenarioSelectors") == list(contracts.SELECTORS), "contract selectors differ", failures)
    _require(requirements.get("canonicalManualCommitOwner") == contracts.EXISTING_PATHS[0], "canonical manual owner differs", failures)
    _require(requirements.get("c48SoleStore") == "PortableExchangeSessionStoreV2", "C48 store owner differs", failures)
    evidence = documents.get(contracts.EVIDENCE, {})
    _require(isinstance(evidence, dict) and evidence.get("receipt") == "ServiceRequestWorkflowEvidenceReceiptV1", "evidence receipt identity differs", failures)
    _require(isinstance(evidence, dict) and evidence.get("acceptanceCredit") is False, "evidence acceptance credit must be false", failures)
    brand = documents.get(contracts.BRAND, {})
    _require(isinstance(brand, dict) and brand.get("requiresAcceptedS10_6Reconciliation") is True, "brand S10 reconciliation boundary differs", failures)
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
    pattern = re.compile(r"\bfunc\s+(testV23P04C40\w*)\s*\([^)]*\)[^{]*\{")
    for match in pattern.finditer(text):
        depth = 0
        start = match.end() - 1
        for index in range(start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    result[match.group(1)] = text[match.start():index + 1]
                    break
    return result


def _validate_source(failures: list[str]) -> None:
    canonical = _swift_code(_read_text(contracts.EXISTING_PATHS[0]))
    store = _swift_code(_read_text(contracts.EXISTING_PATHS[1]))
    drafts = _swift_code(_read_text(contracts.EXISTING_PATHS[2]))
    harness = _swift_code(_read_text(contracts.EXISTING_PATHS[3]))
    workflow_contracts = _swift_code(_read_text(contracts.PRODUCT[4]))
    coordinator = _swift_code(_read_text(contracts.PRODUCT[5]))
    view = _swift_code(_read_text(contracts.PRODUCT[6]))
    tests = _swift_code(_read_text(contracts.PRODUCT[7]))
    fixture = _read_text(contracts.PRODUCT[8])
    ui = _swift_code(_read_text(contracts.PRODUCT[9]))
    source = "\n".join((canonical, store, drafts, harness, workflow_contracts, coordinator, view, tests, ui))
    new_source = "\n".join((workflow_contracts, coordinator, view, tests, ui))

    for token in (
        "ServiceRequestWorkflowFailureV1",
        "ServiceRequestManualIntakeV1",
        "ServiceRequestManualPreviewV1",
        "ServiceRequestManualReceiptV1",
        "ServiceRequestDispositionPlanV1",
        "ServiceRequestNeedsTriageProjectionV1",
        "ServiceRequestWorkflowClaimsV1",
        "ServiceRequestStatusArtifactV1",
        "ServiceRequestWorkflowContextV1",
        "ServiceRequestWorkflowProjectionV1",
        "ServiceRequestWorkflowCommandV1",
        "ServiceRequestWorkflowOutcomeV1",
    ):
        _require(token in source, f"C40 contract/source token missing: {token}", failures)
    for token in (
        "previewManualIntake",
        "commitManualIntake",
        "recoverManualIntake",
        "previewPortableImport",
        "commitImport",
        "recoverImport",
        "previewDisposition",
        "commitDisposition",
        "recoverDisposition",
        "previewWorkConversion",
        "previewWorkLinkReversal",
        "commitWorkConversion",
        "recoverWorkConversion",
    ):
        _require(token in canonical, f"canonical service-request owner token missing: {token}", failures)
    for token in (
        "ServiceRequestCoordinatorV1",
        "ServiceRequestImportPlanV1",
        "ServiceRequestImportPreviewV1",
        "ServiceRequestDraftReferenceV1",
        "project(",
        "execute(",
        "needsTriage",
        "derived",
        "rebuildable",
    ):
        _require(token in source, f"C40 workflow token missing: {token}", failures)
    for token in (
        "previewManual",
        "commitManual",
        "recoverManual",
        "previewPortable",
        "commitPortable",
        "recoverPortable",
        "previewDisposition",
        "commitDisposition",
        "recoverDisposition",
        "previewWorkConversion",
        "previewWorkReversal",
        "commitWork",
        "recoverWork",
        "makeStatusArtifact",
    ):
        _require(token in coordinator, f"workflow command case missing: {token}", failures)
    for token in (
        "acceptAsNew",
        "acceptAndLinkDuplicate",
        "declineWithReason",
        "recordHistoryOnly",
        "keepQuarantined",
        "discardUnimported",
    ):
        _require(token in canonical or token in workflow_contracts, f"explicit disposition missing: {token}", failures)
    for token in ("zeroWrite", "previewSHA256", "preview", "writesCanonical"):
        _require(token in source, f"zero-write preview token missing: {token}", failures)
    for token in ("ServiceRequestWorkConversionPlanV1", "commitWorkConversion", "recoverWorkConversion", "ServiceRequestStatusArtifactV1", "textLines"):
        _require(token in source, f"conversion/status token missing: {token}", failures)
    for token in ("PortableExchangeSessionStoreV2", "serviceRequest", "SERVICE_REQUEST", "namespace", "review"):
        _require(token.lower() in store.lower() + drafts.lower(), f"portable purpose-isolation token missing: {token}", failures)
    for token in ("deliveryClaimed = false", "requesterIdentityVerified = false", "urgencyVerified = false", "duplicateAutomaticallyMerged = false", "workAutomaticallyCreated = false"):
        _require(token in workflow_contracts, f"false claims matrix token missing: {token}", failures)
    _require("ServiceRequestWorkflowView" in view and "Refresh zero-write preview" in view and "Create work" in view, "contained service-request view semantics missing", failures)
    _require(
        "ServiceRequestStatusArtifactV1" in view
        and "statusArtifact" in view
        and "statusText" in view
        and "customerNote" in view,
        "status artifact UI binding missing",
        failures,
    )
    _require(
        "prepareStatusArtifactHandoff" in canonical
        and "ServiceRequestStatusArtifactHandoffV1" in canonical
        and "handoffIntent" in canonical,
        "canonical status handoff seam missing",
        failures,
    )
    _require("canonical" in coordinator and "manualDuplicates" in coordinator and "clock" in coordinator, "coordinator seam missing", failures)

    # Needs-triage manual previews intentionally carry no disposition event.
    # Keep that optional value valid through both construction and the
    # deterministic validator/rebuild path; only explicit dispositions may
    # append a disposition effect.
    manual_preview = re.search(
        r"\bstruct\s+ServiceRequestManualPreviewV1\b.*?(?=\nstruct\s+ServiceRequestManualReceiptV1\b)",
        workflow_contracts,
        re.DOTALL,
    )
    _require(manual_preview is not None, "manual preview contract block missing", failures)
    manual_preview_code = manual_preview.group(0) if manual_preview else ""
    _require(
        re.search(r"\bdispositionEvent\s*:\s*ServiceRequestDispositionEventV1\?", manual_preview_code) is not None
        and re.search(r"\bif\s+let\s+dispositionEvent\s*\{", manual_preview_code) is not None
        and manual_preview_code.count("dispositionEvent: dispositionEvent") >= 2,
        "needs-triage nil disposition-event validator path missing",
        failures,
    )
    _require(
        re.search(r"case\s+\.needsTriage\s*:\s*event\s*=\s*nil", canonical) is not None
        and "if let event" in canonical
        and ".needsTriage" in tests
        and "resultingState, .openUntriaged" in tests,
        "needs-triage nil-event production/test binding missing",
        failures,
    )

    # The correction adds a shared test-support registry case, not another
    # writer.  Require the real exhaustive mapping to the existing command
    # kind and keep the migration witness on the async store seam.
    _require(
        re.search(r"case\s+\.serviceRequest\s*:\s*\.applyServiceRequest", harness) is not None,
        "shared harness serviceRequest mapping missing",
        failures,
    )
    _require(
        "func migrateLegacyServiceRequestDraft" in store
        and re.search(r"func\s+migrateLegacyServiceRequestDraft[^{]*\)\s*async\s+throws", store) is not None,
        "async migration owner missing",
        failures,
    )
    _require(
        tests.count("migrateLegacyServiceRequestDraft") >= 4
        and tests.count("try await h.store.migrateLegacyServiceRequestDraft") >= 2
        and tests.count("try await reloaded.migrateLegacyServiceRequestDraft") >= 2,
        "async migration witness/calls missing",
        failures,
    )

    # XCTest assertion arguments are autoclosures and must not contain an
    # awaited expression.  Scan balanced assertion calls rather than merely
    # checking individual lines so multiline assertions are covered.
    for match in re.finditer(r"\bXCTAssert[A-Za-z0-9_]*\s*\(", tests):
        depth = 0
        end = None
        for index in range(match.end() - 1, len(tests)):
            if tests[index] == "(":
                depth += 1
            elif tests[index] == ")":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is not None:
            _require("await" not in tests[match.start():end], "await inside XCTest assertion autoclosure", failures)

    # The new coordinator delegates writes to the existing C52 owner.  It may
    # mention the writer through command names, but it must not declare a new
    # persistence or transport owner.
    _require(re.search(r"\b(?:class|struct|actor|enum|protocol)\s+\w*(?:Store|Writer|Renderer|Importer|Backend|Network|Telemetry|Root)\w*", new_source, re.IGNORECASE) is None, "parallel C40 infrastructure declaration", failures)
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
        r"\bEventKit\b",
        r"\bUserActivity\b",
    ):
        _require(re.search(pattern, new_source, re.IGNORECASE) is None, f"prohibited C40 integration token: {pattern}", failures)
    _require("V23-P04-C40" in ui and len(re.findall(r"throw\s+XCTSkip\s*\(", ui)) == 1, "UI lane must have one no-launch skip", failures)
    _require(re.search(r"\b(?:XCUIApplication|app)\s*\(?.*\)?\.launch\s*\(", ui, re.IGNORECASE) is None, "UI lane must not launch", failures)

    methods = _method_bodies(tests)
    found: dict[str, str] = {}
    for name, body in methods.items():
        match = re.search(r"testV23P04C40([GAHIR]01)", name)
        if match:
            identifier = match.group(1)
            _require(identifier not in found, f"duplicate evidence method: {identifier}", failures)
            found[identifier] = body
    _require(tuple(found) == ("G01", "A01", "H01", "I01", "R01"), "test evidence method order differs", failures)
    terms = {
        "G01": (("manual",), ("portable",), ("preview",), ("zero",), ("triage",), ("work",), ("status",)),
        "A01": (("manual",), ("disposition",), ("draft",), ("current",), ("contact",), ("purpose",), ("reversal", "unlink")),
        "H01": (("hostile",), ("corrupt",), ("stale",), ("unsupported",), ("scope",), ("portable",)),
        "I01": (("draft",), ("cancel", "cancellation"), ("effect",), ("receipt",), ("recover",), ("exact",), ("mutation",)),
        "R01": (("exact",), ("replay",), ("rebuild", "rebuilt"), ("lifecycle",), ("erase",), ("namespace",), ("restore",), ("clone",), ("fork",), ("migration",)),
    }
    for identifier, required in terms.items():
        body = _normalized(found.get(identifier, ""))
        for aliases in required:
            _require(any(_normalized(token) in body for token in aliases), f"{identifier} test lacks semantic coverage: {'/'.join(aliases)}", failures)
    _require("V9_103ServiceRequestWorkflowTests" in tests and "testV23P04C40" in tests, "tests do not bind C40 workflow", failures)

    try:
        corpus = json.loads(fixture)
    except json.JSONDecodeError as error:
        failures.append(f"source fixture JSON malformed: {error}")
        corpus = {}
    _require(isinstance(corpus, dict), "source fixture must be an object", failures)
    if isinstance(corpus, dict):
        _require(corpus.get("claims") == contracts.CLAIMS and all(value is False for value in corpus.get("claims", {}).values()), "source fixture claims differ", failures)


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
    parser.add_argument("--complete", action="store_true", help="require all nine source paths")
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
        failures.append("complete:missing C40 source paths")
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
