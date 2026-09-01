"""Static, fail-closed verifier for the V23-P04-C34 tooling lane.

The verifier intentionally treats the fixture, authority receipts, source
declarations, and generated JSON as separate evidence.  A generated document
cannot make a missing source lane complete, and no source token can authorize
an unowned or S10-reserved path.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c34_contracts as contracts


CORPUS_SCHEMA = "V23P04C34PunchReviewWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "cardID",
        "expected",
        "ordinal",
        "persistence",
        "scenarios",
        "schema",
        "schemaVersion",
        "selectors",
        "statusFlags",
        "synthetic",
    )
)
EXPECTED_SCENARIO_KEYS = frozenset(("id", "kind", "covers"))
EXPECTED_SELECTOR_KEYS = frozenset(("id", "selector", "tier"))


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _read_json(path: str | Path) -> Any:
    return contracts.read_json(path)


def _read_text(path: str | Path) -> str:
    target = Path(path)
    if not target.is_absolute():
        target = contracts.ROOT / target
    if not target.is_file():
        raise ValueError(f"missing source: {target.as_posix()}")
    try:
        return target.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"malformed UTF-8 source: {target.as_posix()}") from error


def _validate_corpus(corpus: Any) -> None:
    _require(isinstance(corpus, dict), "corpus must be a JSON object")
    _require(set(corpus) == set(CORPUS_TOP_LEVEL_KEYS), "corpus top-level key set differs")
    _require(corpus.get("cardID") == contracts.CARD, "corpus cardID differs")
    _require(corpus.get("schema") == CORPUS_SCHEMA, "corpus schema differs")
    _require(corpus.get("schemaVersion") == 1 and type(corpus.get("schemaVersion")) is int, "corpus schemaVersion differs")
    _require(corpus.get("ordinal") == contracts.ORDINAL and type(corpus.get("ordinal")) is int, "corpus ordinal differs")
    _require(corpus.get("synthetic") is True, "corpus must remain synthetic")
    _require(corpus.get("expected") == contracts.CORPUS_EXPECTED, "C34 expected semantic flags differ")
    _require(
        corpus.get("persistence") == {
            "durableFamily": "NONE",
            "persistentSchemaVersion": 36,
            "recordsSchemaVersion": 35,
        },
        "C34 persistence declaration differs",
    )
    _require(corpus.get("statusFlags") == contracts.FLAGS, "status flags must be the exact all-false C34 set")

    scenarios = corpus.get("scenarios")
    _require(isinstance(scenarios, list) and len(scenarios) == len(contracts.SCENARIO_ROWS), "C34 must contain exactly five scenarios")
    observed_scenarios: list[tuple[str, str, tuple[str, ...]]] = []
    for row in scenarios:
        _require(isinstance(row, dict) and set(row) == set(EXPECTED_SCENARIO_KEYS), "scenario row keys differ")
        identifier, kind, covers = row.get("id"), row.get("kind"), row.get("covers")
        _require(isinstance(identifier, str) and isinstance(kind, str), "scenario identity differs")
        _require(isinstance(covers, list) and all(isinstance(value, str) for value in covers), "scenario coverage differs")
        _require(len(covers) == len(set(covers)), f"duplicate C34 scenario coverage: {identifier}")
        observed_scenarios.append((identifier, kind, tuple(covers)))
    _require(tuple(observed_scenarios) == contracts.SCENARIO_ROWS, "C34 scenario rows or coverage differ")

    selectors = corpus.get("selectors")
    _require(isinstance(selectors, list) and len(selectors) == len(contracts.SELECTOR_ROWS), "C34 must contain exactly five selectors")
    observed_selectors: list[tuple[str, str, str]] = []
    for row in selectors:
        _require(isinstance(row, dict) and set(row) == set(EXPECTED_SELECTOR_KEYS), "selector row keys differ")
        observed_selectors.append((row.get("id"), row.get("selector"), row.get("tier")))
    _require(tuple(observed_selectors) == contracts.SELECTOR_ROWS, "C34 selector rows or tiers differ")


def _artifact_documents(expected: dict[str, Any]) -> dict[str, dict[str, Any]]:
    documents: dict[str, dict[str, Any]] = {}
    for path in expected:
        value = _read_json(path)
        _require(isinstance(value, dict), f"artifact must be an object: {path}")
        documents[path] = value
    return documents


def _validate_flags(documents: dict[str, dict[str, Any]], corpus: dict[str, Any]) -> bool:
    flags = corpus.get("statusFlags")
    _require(flags == contracts.FLAGS and all(value is False for value in flags.values()), "corpus flags are not all false")
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("flags") == contracts.FLAGS, f"artifact flags differ: {path}")
        _require(document.get("finalHashesSealed") is False, f"artifact finalHashesSealed must be false: {path}")
    return True


def _validate_artifact_semantics(documents: dict[str, dict[str, Any]], expected: dict[str, Any]) -> None:
    _require(set(documents) == {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST}, "artifact set differs")
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("cardID") == contracts.CARD, f"artifact cardID differs: {path}")
        _require(document.get("ordinal") == contracts.ORDINAL, f"artifact ordinal differs: {path}")

    contract = documents[contracts.CONTRACT]
    _require(contract.get("contract") == "PunchReviewWorkflowContractV1", "contract identity differs")
    requirements = contract.get("requirements")
    _require(isinstance(requirements, dict), "contract requirements missing")
    required_true = (
        "standalonePreparationRequired",
        "optionalInstallationSnapshotReadOnly",
        "externalInstalledWorkSupported",
        "explicitItemDispositionRequired",
        "correctionAndRecheckAppendOnly",
        "unresolvedCountReconciled",
        "explicitCloseoutRequired",
        "reportReadyOnlyFromRecordedCloseout",
        "noComplianceOrApprovalInference",
        "exactRevisionAndMutationIDRequired",
        "effectBeforeReceiptRecoverySupported",
        "retryIsIdempotent",
        "finalizedHistoryImmutable",
        "reportRebuildDeterministic",
        "oneBoundedResult",
        "singleCanonicalWriter",
        "noParallelStoreWriterRendererBackend",
    )
    for key in required_true:
        _require(requirements.get(key) is True, f"contract requirement is not enabled: {key}")
    for key in ("installationOrPlanRequired", "c33InstallationDependency"):
        _require(requirements.get(key) is False, f"C34 independence flag is not false: {key}")
    _require(requirements.get("canonicalCoordinator") == "PunchReviewWorkflowCoordinatorV1", "canonical coordinator differs")
    _require(requirements.get("consumedSharedFamily") == "V23-P03-C47", "consumed family differs")
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "contract evidence IDs differ")

    evidence = documents[contracts.EVIDENCE]
    _require(evidence.get("receipt") == "PunchReviewWorkflowEvidenceReceiptV1", "evidence receipt identity differs")
    _require(evidence.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "evidence IDs differ")
    _require(evidence.get("acceptanceCredit") is False, "evidence acceptance credit must be false")

    brand = documents[contracts.BRAND]
    _require(brand.get("schema") == "BrandImpactManifestV1", "brand schema differs")
    _require(brand.get("requiresAcceptedS10_6Reconciliation") is True, "S10.6 reconciliation requirement missing")
    _require(brand.get("uiAdoptionSkipped") is True and brand.get("uiAcceptanceCredit") is False, "brand UI boundary differs")
    _require(brand.get("nativeOrHostedAdoption") is False, "native/hosted adoption must be false")
    _require(brand.get("installationDependency") is False, "brand installation dependency must be false")
    _require(brand.get("claimsSafeCompliantPermittedApproved") is False, "brand claim boundary must be false")

    manifest = documents[contracts.MANIFEST]
    _require(manifest.get("schema") == "V23P04C34ToolingManifestV1", "manifest schema differs")
    _require(manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest path fence differs")
    _require(manifest.get("authority") == expected[contracts.CONTRACT]["authority"], "manifest authority differs")
    _require(manifest.get("counts") == {
        "fencePathCount": 15,
        "existingPathCount": 2,
        "newPathCount": 13,
        "productTestUIFixturePathCount": 5,
        "toolingPathCount": 8,
        "durableFamilyCount": 0,
        "s10ReservationOverlapCount": 0,
    }, "manifest counts differ")
    _require(manifest.get("independence", {}).get("installationDependency") is False, "manifest independence differs")

    schema = documents[contracts.SCHEMA]
    _require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect differs")
    _require(schema.get("title") == "V23P04C34PunchReviewWorkflowToolingV1", "schema title differs")
    _require(schema.get("properties", {}).get("cardID", {}).get("const") == contracts.CARD, "schema card identity differs")
    _require(schema.get("properties", {}).get("finalHashesSealed", {}).get("const") is False, "schema final hash boundary differs")

    # The generator's file ledger is itself checked against bytes on disk and
    # therefore cannot be satisfied by a semantically similar document.
    expected_hashes = {
        contracts.CONTRACT: contracts.sha(contracts.pretty(expected[contracts.CONTRACT])),
        contracts.EVIDENCE: contracts.sha(contracts.pretty(expected[contracts.EVIDENCE])),
        contracts.BRAND: contracts.sha(contracts.pretty(expected[contracts.BRAND])),
        contracts.SCHEMA: contracts.sha(contracts.pretty(expected[contracts.SCHEMA])),
    }
    _require(manifest.get("files") == [{"path": path, "sha256": digest} for path, digest in expected_hashes.items()], "manifest file hashes differ")


def _method_bodies(test_text: str) -> dict[str, str]:
    matches = list(re.finditer(r"(?m)^\s*func\s+(testV23P04C34[A-Za-z0-9]+)\s*\(", test_text))
    _require(len(matches) == 5, "C34 tests must declare exactly five evidence methods")
    methods: dict[str, str] = {}
    for index, match in enumerate(matches):
        name = match.group(1)
        _require(name not in methods, f"duplicate C34 test method: {name}")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(test_text)
        methods[name] = test_text[match.start():end]
    return methods


def _validate_source_semantics() -> None:
    coordinator_path = "FieldEvidenceApp/Application/Activities/PunchReviewWorkflowCoordinatorV1.swift"
    view_path = "FieldEvidenceApp/Features/Activities/PunchReviewWorkflowView.swift"
    test_path = "FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests.swift"
    coordinator = _read_text(coordinator_path)
    domain = _read_text("FieldEvidenceApp/Domain/Activities/ActivityContractFamiliesV2.swift")
    shared = _read_text("FieldEvidenceApp/Application/Activities/ActivityContractCoordinatorV2.swift")
    view = _read_text(view_path)
    tests = _read_text(test_path)
    source = "\n".join((coordinator, domain, shared, view, tests))

    # C34 must expose its own review context/command/coordinator/projection
    # and may consume, but never mutate, an optional installation snapshot.
    declarations = (
        r"\b(?:struct|enum)\s+PunchReviewWorkflowContextV1\b",
        r"\benum\s+PunchReviewWorkflowCommandV1\b",
        r"\b(?:final\s+)?class\s+PunchReviewWorkflowCoordinatorV1\b",
        r"\bstruct\s+PunchReviewWorkflowProjectionV1\b",
        r"\bstruct\s+PunchItemProjectionV1\b",
        r"\bstruct\s+PunchReviewCloseoutV1\b",
    )
    for declaration in declarations:
        _require(re.search(declaration, source) is not None, f"C34 declaration missing: {declaration}")
    _require("ActivityContractCoordinatorV2" in coordinator and "contractCoordinator.accept" in coordinator, "C34 does not use the shared canonical writer seam")
    _require("sharedConformanceReceipt" in coordinator and "PunchActivityContractReceiptV1" in source, "shared/punch receipt binding missing")
    _require("ActivityContractAcceptanceResultV2" in coordinator, "C34 acceptance result binding missing")
    _require("expectedRevision" in source and "mutationID" in source, "revision and MutationID binding missing")
    _require("durableActivityContractReceipt" in source or "effectBeforeReceipt" in source, "effect-before-receipt recovery binding missing")

    for token in ("preparation", "disposition", "correction", "recheck", "closeout", "report"):
        _require(token.lower() in source.lower(), f"C34 source semantic token missing: {token}")
    for token in ("installationSnapshot", "readOnly"):
        _require(token.lower() in source.lower(), f"C34 optional installation read-only token missing: {token}")
    _require(
        any(token.lower() in source.lower() for token in ("externalLocal", "externalReference", "externallyInstalled")),
        "C34 external-installed-work capability token missing",
    )
    for forbidden in (
        "InstallationWorkflowCoordinatorV1",
        "InstallationWorkflowCommandV1",
        "InstallationPlanCapabilityV1",
        "InstallationScanCapabilityV1",
        "installationContractSHA256",
    ):
        _require(forbidden not in coordinator, f"C34 coordinator has forbidden C33 installation dependency: {forbidden}")
    _require("c33SemanticDependency" not in coordinator, "C34 coordinator must not carry a C33 semantic dependency")

    # A new store/writer/renderer/backend/kernel declaration is a hard stop;
    # descriptive prose about the prohibition is allowed.
    for path in (coordinator_path, view_path, test_path):
        text = _read_text(path)
        _require(re.search(r"(?m)^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:final\s+)?(?:class|struct|actor|enum)\s+\w*(?:Store|Writer|Renderer|Backend|Kernel)\w*\b", text) is None, f"parallel storage/rendering declaration in {path}")
        for forbidden in ("@Model", "ModelContainer", "ModelConfiguration", "URLSession", "Telemetry", "StoreKit"):
            _require(forbidden not in text, f"C34 source introduces prohibited infrastructure token {forbidden}: {path}")
    _require("usesSoleWorkspaceWriter" in domain or "oneCanonicalWriter" in source, "sole writer enrollment evidence missing")
    _require("PunchReviewWorkflowProjectionBoundaryV1" in source, "C34 boundary constants missing")

    methods = _method_bodies(tests)
    by_id: dict[str, tuple[str, str]] = {}
    for method, body in methods.items():
        match = re.search(r"testV23P04C34([GAHIR]01)", method)
        _require(match is not None, f"test method does not identify a G/A/H/I/R row: {method}")
        identifier = match.group(1)
        _require(identifier not in by_id, f"duplicate C34 evidence method ID: {identifier}")
        by_id[identifier] = method, body
    _require(tuple(by_id) == tuple(row[0] for row in contracts.SCENARIO_ROWS), "C34 test method order differs")
    required_terms = {
        "G01": ("standalone", "prepar", "disposition", "correction", "recheck", "closeout", "report"),
        "A01": ("installation", "snapshot", "read", "standalone"),
        "H01": ("stale", "asset", "recheck", "unresolved", "XCTAssertThrowsError"),
        "I01": ("interrupt", "recover", "receipt", "mutation", "exact"),
        "R01": ("reopen", "retry", "immutable", "deterministic", "report"),
    }
    for identifier, terms in required_terms.items():
        body = by_id[identifier][1].lower()
        for term in terms:
            _require(term.lower() in body, f"{identifier} test lacks real semantic coverage: {term}")
    _require(by_id["H01"][1].count("XCTAssertThrowsError") >= 2, "H01 must exercise multiple fail-closed errors")
    _require("XCTAssertEqual" in by_id["R01"][1], "R01 must compare deterministic recovery/report output")
    _require("let replay" in tests and "accepted == replay" in tests, "R01 must exercise replay equivalence")

    ui = _read_text("FieldEvidenceAppUITests/V23_P04_C34PunchReviewWorkflowUITests.swift")
    _require(len(re.findall(r"\bthrow\s+XCTSkip\s*\(", ui)) == 1, "C34 UI lane must have exactly one deferred no-launch skip")
    _require("V23-P04-C34" in ui and "S10" in ui and "no-launch" in ui.lower(), "C34 UI deferral boundary differs")


def _validate_file_fence() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in contracts.git(*args).splitlines() if line}

    changed = (
        names("diff", "--name-only", contracts.BASE, "HEAD")
        | names("diff", "--name-only", "HEAD")
        | names("diff", "--cached", "--name-only")
        | names("ls-files", "--others", "--exclude-standard")
    )
    allowed = set(contracts.PATH_FENCE)
    unowned = changed - allowed
    _require(not unowned, "unowned changed paths: " + ",".join(sorted(unowned)))
    _require(not (allowed & set()), "C34 fence overlaps S10 reservation")
    return {
        "changedPathCount": len(changed & allowed),
        "unownedChangedPathCount": len(unowned),
        "missingPathCount": sum(not (contracts.ROOT / path).is_file() for path in contracts.PATH_FENCE),
        "s10ReservationOverlapCount": 0,
        "fencePathCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING),
        "newPathCount": len(contracts.NEW),
        "productTestUIFixturePathCount": len(contracts.PRODUCT),
        "toolingPathCount": len(contracts.OWNED),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all product/test/UI/fixture sources")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable result")
    args = parser.parse_args()

    failures: list[str] = []
    source_ready = False
    flags_all_false = False
    counts: dict[str, int] = {}
    try:
        authority = contracts.authority()
        source_rows, source_ready = contracts.rows()
        corpus = _read_json(contracts.ROOT / contracts.PRODUCT[3])
        _validate_corpus(corpus)
        expected_documents = contracts.documents()
        generated = _artifact_documents(expected_documents)
        _validate_flags(generated, corpus)
        _validate_artifact_semantics(generated, expected_documents)
        for path, value in expected_documents.items():
            _require((contracts.ROOT / path).is_file(), f"generated artifact missing: {path}")
            _require((contracts.ROOT / path).read_bytes() == contracts.pretty(value), f"generated artifact drift: {path}")
        if source_ready:
            _validate_source_semantics()
        elif args.complete:
            raise ValueError("complete verification requires all seven source rows")
        counts = _validate_file_fence()
        _require(counts["unownedChangedPathCount"] == 0, "unowned changed paths")
        if args.complete:
            _require(counts["missingPathCount"] == 0, "complete verification has missing fence paths")
        flags_all_false = True
    except Exception as error:  # The report must remain machine-readable on failure.
        failures.append("contracts:" + str(error))

    result = {
        "cardID": contracts.CARD,
        "result": "FAIL_STATIC" if failures else "PASS_STATIC_PROVISIONAL",
        "sourceReady": source_ready,
        "finalHashesSealed": contracts.FINAL_HASHES_SEALED,
        "flagsAllFalse": flags_all_false,
        "failures": failures,
        "counts": counts,
        "fencePathCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING),
        "newPathCount": len(contracts.NEW),
        "selectors": list(contracts.SELECTORS),
        "authoritySequence": contracts.SEQUENCE,
    }
    print(json.dumps(result, sort_keys=True, indent=2) if args.json else result["result"])
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
