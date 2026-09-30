#!/usr/bin/env python3
"""Fail-closed static verifier for the V23-P04-C37 tooling lane."""

from __future__ import annotations

import argparse
import ast
import os
import re
import sys
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c37_contracts as contracts


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _read_text(path: str | Path) -> str:
    target = Path(path)
    if not target.is_absolute():
        target = ROOT / target
    if not target.is_file():
        raise ValueError(f"missing source: {target.as_posix()}")
    try:
        return target.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"malformed UTF-8 source: {target.as_posix()}") from error


def _read_json(path: str | Path) -> Any:
    return contracts.read_json(path)


def _validate_corpus(corpus: Any) -> None:
    _require(isinstance(corpus, dict), "C37 corpus must be an object")
    _require(set(corpus) == set(contracts.CORPUS_TOP_LEVEL_KEYS), "C37 corpus top-level key set differs")
    _require(corpus.get("schema") == contracts.CORPUS_SCHEMA, "C37 corpus schema differs")
    _require(corpus.get("schemaVersion") == 1 and type(corpus.get("schemaVersion")) is int, "C37 corpus schemaVersion differs")
    _require(corpus.get("cardID") == contracts.CARD, "C37 corpus cardID differs")
    _require(corpus.get("corpusID") == "v23-p04-c37-incumbent-file-adapter-workflow-corpus-v1", "C37 corpus ID differs")
    _require(corpus.get("testOnly") is True and corpus.get("synthetic") is True, "C37 corpus must be test-only synthetic data")
    _require(corpus.get("containsCustomerData") is False and corpus.get("containsSecrets") is False, "C37 corpus data boundary differs")
    _require(corpus.get("evidenceIDs") == list(contracts.SELECTORS), "C37 evidence IDs differ")
    _require(corpus.get("production") == contracts.CORPUS_PRODUCTION, "C37 production disabled boundary differs")
    _require(corpus.get("syntheticAuthority") == contracts.CORPUS_SYNTHETIC_AUTHORITY, "C37 synthetic authority differs")
    _require(corpus.get("hostileCases") == contracts.CORPUS_HOSTILE_CASES, "C37 hostile cases differ")
    _require(corpus.get("recoveryCases") == contracts.CORPUS_RECOVERY_CASES, "C37 recovery cases differ")
    _require(corpus.get("claims") == contracts.CORPUS_CLAIMS, "C37 corpus claims differ")
    _require(all(value is False for value in corpus["claims"].values()), "C37 corpus claim flags must all be false")


def _artifact_documents(expected: dict[str, Any]) -> dict[str, dict[str, Any]]:
    documents: dict[str, dict[str, Any]] = {}
    for path in expected:
        value = _read_json(path)
        _require(isinstance(value, dict), f"artifact must be an object: {path}")
        documents[path] = value
    return documents


def _validate_flags(documents: dict[str, dict[str, Any]]) -> None:
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("flags") == contracts.FLAGS, f"C37 artifact flags differ: {path}")
        _require(document.get("finalHashesSealed") is False, f"C37 final hashes must remain unsealed: {path}")


def _validate_artifact_semantics(documents: dict[str, dict[str, Any]], expected: dict[str, Any]) -> None:
    _require(set(documents) == {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST}, "C37 artifact set differs")
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("cardID") == contracts.CARD, f"C37 artifact cardID differs: {path}")
        _require(document.get("ordinal") == contracts.ORDINAL, f"C37 artifact ordinal differs: {path}")
        if path in (contracts.CONTRACT, contracts.EVIDENCE, contracts.MANIFEST):
            _require(document.get("authority") == expected[contracts.CONTRACT]["authority"], f"C37 artifact authority differs: {path}")
            _require(document.get("sourceRows") == expected[contracts.CONTRACT]["sourceRows"], f"C37 artifact source rows differ: {path}")

    contract = documents[contracts.CONTRACT]
    _require(contract.get("contract") == "IncumbentFileAdapterWorkflowContractV1", "C37 contract identity differs")
    _require(contract.get("lifecycle") == expected[contracts.CONTRACT]["lifecycle"], "C37 contract lifecycle differs")
    _require(contract.get("independence") == expected[contracts.CONTRACT]["independence"], "C37 contract independence differs")
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "C37 contract evidence IDs differ")
    _require(contract.get("scenarioRows") == list(contracts.SCENARIO_ROWS), "C37 scenario mapping differs")
    requirements = contract.get("requirements")
    _require(isinstance(requirements, dict), "C37 contract requirements missing")
    for key in ("closedTypedWorkflow", "disabledZeroAction", "previewZeroWrite", "deterministicClosedSeam", "exactReleaseSelection", "optionalReadOnlyC50Exchange", "optionalReadOnlyC08ImportEngine", "readOnlyC16Prerequisite", "noNetwork", "noSDK", "noLogin", "noCredentials", "noProfileSpecificStrings", "noProviderSuccessClaim", "noParallelImporter", "noParallelStore", "noParallelWriter", "noParallelRenderer", "noParallelBackend", "nonPersistent", "finalHashesUnsealed", "fiveEvidenceScenarios", "noAutomaticImport", "noFileMeansSyncOrDelivery"):
        _require(requirements.get(key) is True, f"C37 requirement is not enabled: {key}")
    for key, value in {
        "disabledState": "DISABLED_NO_SELECTED_PROFILE",
        "selectedProfileCount": 0,
        "manualCommandCases": ["previewInbound", "previewCanonicalImport", "beginCanonicalImport", "commitOrCancelCanonicalImport", "export", "recover"],
        "executeAPI": "IncumbentFileAdapterWorkflowCoordinatorV1.execute",
        "projectionAPI": "IncumbentFileAdapterWorkflowCoordinatorV1.projection",
        "previewAPI": "IncumbentFileExchangeCoordinatorV1.preview",
        "renderAPI": "IncumbentFileExchangeCoordinatorV1.render",
        "recoveryAPI": "IncumbentFileExchangeCoordinatorV1.recover",
        "importEngineOwner": "V23-P04-C08",
        "adapterPortOwner": "V23-P03-C50",
        "futureReentry": "CLOSED_TYPED_REENTRY_REQUIRES_EXACT_PROFILE_SELECTION_AND_NEW_MAPPING_PREVIEW",
    }.items():
        _require(requirements.get(key) == value, f"C37 requirement differs: {key}")

    evidence = documents[contracts.EVIDENCE]
    _require(evidence.get("receipt") == "IncumbentFileAdapterWorkflowEvidenceReceiptV1", "C37 evidence receipt identity differs")
    _require(evidence.get("receiptState") == "PROVISIONAL_STATIC_TOOLING" and evidence.get("acceptanceCredit") is False, "C37 evidence boundary differs")
    _require(evidence.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "C37 evidence IDs differ")
    _require(evidence.get("claims") == contracts.CORPUS_CLAIMS and all(value is False for value in evidence["claims"].values()), "C37 evidence claims must all be false")
    _require(evidence.get("productionBoundary") == contracts.CORPUS_PRODUCTION, "C37 production evidence boundary differs")
    _require(evidence.get("recoveryCases") == contracts.CORPUS_RECOVERY_CASES, "C37 evidence recovery cases differ")

    brand = documents[contracts.BRAND]
    _require(brand.get("schema") == "BrandImpactManifestV1", "C37 brand schema differs")
    for key in ("requiresAcceptedS10_6Reconciliation", "uiAdoptionSkipped", "selectedProfileCount", "profileState", "providerSuccessClaim", "networkOrSDK", "customerDataPresent", "customerSecretsPresent", "licenseTrademarkEvidence", "syncDeliveryAcceptanceClaim"):
        expected_value = True if key in ("requiresAcceptedS10_6Reconciliation", "uiAdoptionSkipped") else (0 if key == "selectedProfileCount" else "DISABLED_NO_SELECTED_PROFILE" if key == "profileState" else False)
        _require(brand.get(key) == expected_value, f"C37 brand boundary differs: {key}")
    _require(brand.get("uiAcceptanceCredit") is False and brand.get("nativeOrHostedAdoption") is False, "C37 brand adoption boundary differs")

    manifest = documents[contracts.MANIFEST]
    _require(manifest.get("schema") == "V23P04C37ToolingManifestV1", "C37 manifest schema differs")
    _require(manifest.get("pathFence") == list(contracts.PATH_FENCE), "C37 manifest path fence differs")
    _require(manifest.get("counts") == {"fencePathCount": 13, "existingPathCount": 0, "newPathCount": 13, "productTestUIFixturePathCount": 5, "toolingPathCount": 8, "durableFamilyCount": 0, "s10ReservationOverlapCount": 0}, "C37 manifest counts differ")
    _require(manifest.get("independence") == expected[contracts.CONTRACT]["independence"], "C37 manifest independence differs")
    expected_hashes = {contracts.CONTRACT: contracts.sha(contracts.pretty(expected[contracts.CONTRACT])), contracts.EVIDENCE: contracts.sha(contracts.pretty(expected[contracts.EVIDENCE])), contracts.BRAND: contracts.sha(contracts.pretty(expected[contracts.BRAND])), contracts.SCHEMA: contracts.sha(contracts.pretty(expected[contracts.SCHEMA]))}
    _require(manifest.get("files") == [{"path": path, "sha256": digest} for path, digest in expected_hashes.items()], "C37 manifest file hashes differ")

    schema = documents[contracts.SCHEMA]
    _require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "C37 schema dialect differs")
    _require(schema.get("title") == "V23P04C37IncumbentFileAdapterWorkflowToolingV1", "C37 schema title differs")
    _require(schema.get("properties", {}).get("cardID", {}).get("const") == contracts.CARD, "C37 schema card identity differs")
    _require(schema.get("properties", {}).get("ordinal", {}).get("const") == contracts.ORDINAL, "C37 schema ordinal differs")
    _require(schema.get("properties", {}).get("finalHashesSealed", {}).get("const") is False, "C37 schema final-hash boundary differs")


def _method_bodies(test_text: str) -> dict[str, str]:
    matches = list(re.finditer(r"(?m)^\s*func\s+(testV23P04C37[A-Za-z0-9]+)\s*\(", test_text))
    _require(len(matches) == 5, "C37 tests must declare exactly five evidence methods")
    methods: dict[str, str] = {}
    for index, match in enumerate(matches):
        name = match.group(1)
        _require(name not in methods, f"duplicate C37 test method: {name}")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(test_text)
        methods[name] = test_text[match.start():end]
    return methods


def _validate_source_semantics() -> None:
    coordinator = _read_text(contracts.PRODUCT[0])
    view = _read_text(contracts.PRODUCT[1])
    tests = _read_text(contracts.PRODUCT[2])
    fixture = _read_json(contracts.PRODUCT[3])
    source = "\n".join((coordinator, view, tests))
    declarations = (
        r"\benum\s+IncumbentFileAdapterWorkflowFailureV1\b",
        r"\benum\s+IncumbentFileAdapterWorkflowStateV1\b",
        r"\bstruct\s+IncumbentFileAdapterWorkflowContextV1\b",
        r"\bstruct\s+IncumbentFileAdapterWorkflowProjectionV1\b",
        r"\bstruct\s+IncumbentFileAdapterInboundPreviewV1\b",
        r"\bstruct\s+IncumbentFileAdapterC08PreviewCommandV1\b",
        r"\bstruct\s+IncumbentFileAdapterC08BeginCommandV1\b",
        r"\bstruct\s+IncumbentFileAdapterC08CommitCommandV1\b",
        r"\bstruct\s+IncumbentFileAdapterC08ReentryV1\b",
        r"\benum\s+IncumbentFileAdapterWorkflowCommandV1\b",
        r"\benum\s+IncumbentFileAdapterWorkflowOutcomeV1\b",
        r"\benum\s+IncumbentFileAdapterWorkflowClaimsV1\b",
        r"\b(?:final\s+)?class\s+IncumbentFileAdapterWorkflowCoordinatorV1\b",
    )
    for declaration in declarations:
        _require(re.search(declaration, coordinator) is not None, f"C37 declaration missing: {declaration}")
    for token in (
        "case previewInbound", "case previewCanonicalImport", "case beginCanonicalImport", "case commitOrCancelCanonicalImport", "case export", "case recover",
        "func projection(", "func execute(", "IncumbentFileExchangeCoordinatorV1", "ImportBulkCoordinatorV1", "IncumbentFileAdapterC08ReentryV1", "IncumbentFileAdapterInboundPreviewV1", "exchange.preview", "exchange.render", "exchange.recover", "try validate(inbound:", "currentSourceSHA256", "currentWorkspaceRevisionSHA256",
    ):
        _require(token in coordinator, f"C37 coordinator token missing: {token}")
    _require("isZeroWrite: true" in coordinator and "previewWritesCanonicalState: false" in coordinator and "previewMeansImported: false" in coordinator, "C37 preview zero-write semantics missing")
    _require("result.preview.inputSHA256 == input.byteSHA256" in coordinator, "C37 inbound source digest binding missing")
    _require("canDetectParseOrMap: false" in coordinator and "canPreviewCanonicalImport: false" in coordinator and "canCommitCanonicalImport: false" in coordinator and "canExport: false" in coordinator, "C37 disabled projection is not zero action")
    _require("selectedReleaseID: nil" in coordinator and "selectedReleaseSHA256: nil" in coordinator and "providerDisplayToken: nil" in coordinator, "C37 disabled projection identity differs")
    _require("importBulk: ImportBulkCoordinatorV1?" in coordinator and "guard let importBulk" in coordinator, "C37 optional C08 import seam differs")
    _require("scopeSHA256" in coordinator and "mappingManifestSHA256" in coordinator and "cancellationRequested" in coordinator, "C37 exact re-entry binding missing")
    for token in ("selectedProductionProfileCount = 0", "createsGenericMapper = false", "createsCanonicalWriter = false", "fileCreatedMeansSynced = false", "fileCreatedMeansAccepted = false", "fileCreatedMeansDelivered = false", "previewMeansImported = false", "establishesProviderSuccess = false"):
        _require(token in coordinator, f"C37 claim boundary missing: {token}")

    forbidden_patterns = (
        r"\bURLSession\b", r"\bURLRequest\b", r"\bURLComponents\b", r"\bNWConnection\b", r"\bWebSocket\b", r"\bAlamofire\b", r"\bStoreKit\b", r"\bOAuth\b", r"\bKeychain\w*\b", r"\bSecItem\w*\b", r"\bASAuthorization\w*\b", r"\bClientSecret\b", r"\bAPIKey\b", r"https?://", r"\b(?:Acme|QuickBooks|SAP|Oracle|Salesforce)\b",
    )
    for pattern in forbidden_patterns:
        _require(re.search(pattern, source, re.IGNORECASE) is None, f"C37 source introduces prohibited integration token: {pattern}")
    for pattern in (r"\b(?:class|struct|actor|enum|protocol)\s+\w*(?:Store|Writer|Renderer|Backend|Importer)\w*\b", r"@Model\b", r"\bModelContainer\b", r"\bModelContext\b"):
        _require(re.search(pattern, coordinator + "\n" + view) is None, f"C37 parallel infrastructure declaration: {pattern}")
    for token in ("IncumbentFileAdapterWorkflowCoordinatorV1", "previewInbound", "previewCanonicalImport", "beginCanonicalImport", "commitOrCancelCanonicalImport", "export", "recover"):
        _require(token in view, f"C37 view workflow token missing: {token}")
    _require(len(re.findall(r"\bthrow\s+XCTSkip\s*\(", _read_text(contracts.PRODUCT[4]))) == 1, "C37 UI lane must have one deferred no-launch skip")
    ui = _read_text(contracts.PRODUCT[4])
    _require("V23-P04-C37" in ui and "no-launch" in ui.lower(), "C37 UI deferral boundary differs")
    _require("launch" not in ui.lower().replace("no-launch", ""), "C37 UI must not launch")

    methods = _method_bodies(tests)
    ids: dict[str, str] = {}
    for method, body in methods.items():
        match = re.search(r"testV23P04C37([GAHIR]01)", method)
        _require(match is not None, f"C37 test method does not identify G/A/H/I/R row: {method}")
        identifier = match.group(1)
        _require(identifier not in ids, f"duplicate C37 evidence method ID: {identifier}")
        ids[identifier] = body
    _require(tuple(ids) == ("G01", "A01", "H01", "I01", "R01"), "C37 test method order differs")
    required_terms = {
        "G01": ("disabled", "selectedprofile", "zero", "projection", "claims", "providerName"),
        "A01": ("synthetic", "exactprofile", "preview", "export", "deterministic", "isZeroWrite"),
        "H01": ("hostile", "throws", "unknown", "stale", "mismatch", "applyCount"),
        "I01": ("cancellation", "effectbefore", "retry", "exactlyonce", "completed", "applyCount"),
        "R01": ("byteidentical", "divergent", "quarantined", "cleanup", "replay", "canonicalReapplyOccurred"),
    }
    for identifier, terms in required_terms.items():
        body = ids[identifier].lower()
        for term in terms:
            _require(term.lower() in body, f"{identifier} test lacks real semantic coverage: {term}")
    _require("C50IncumbentFileAdapterTestSupport" in tests and "ImportBulkCoordinatorV1" in tests and "MutationJournalFailureInjectionV1" in tests, "C37 tests do not bind existing C50/C08 seams")
    _require(fixture.get("schema") == contracts.CORPUS_SCHEMA and fixture.get("claims") == contracts.CORPUS_CLAIMS, "C37 source fixture parse differs")


def _validate_file_fence() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in contracts.git(*args).splitlines() if line}

    changed = names("diff", "--name-only", contracts.BASE, "HEAD") | names("diff", "--name-only", "HEAD") | names("diff", "--cached", "--name-only") | names("ls-files", "--others", "--exclude-standard")
    unowned = changed - set(contracts.PATH_FENCE)
    _require(not unowned, "unowned changed paths: " + ",".join(sorted(unowned)))
    return {"changedPathCount": len(changed & set(contracts.PATH_FENCE)), "unownedChangedPathCount": len(unowned), "missingPathCount": sum(not (ROOT / path).is_file() for path in contracts.PATH_FENCE), "s10ReservationOverlapCount": 0, "fencePathCount": len(contracts.PATH_FENCE), "existingPathCount": 0, "newPathCount": len(contracts.NEW), "productTestUIFixturePathCount": len(contracts.PRODUCT), "toolingPathCount": len(contracts.OWNED)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all five C37 source paths")
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    args = parser.parse_args()
    failures: list[str] = []
    source_ready = False
    flags_all_false = False
    counts: dict[str, int] = {}
    try:
        _ = contracts.authority()
        source_rows, source_ready = contracts.rows()
        corpus = _read_json(contracts.PRODUCT[3])
        _validate_corpus(corpus)
        expected = contracts.documents()
        generated = _artifact_documents(expected)
        _validate_flags(generated)
        _validate_artifact_semantics(generated, expected)
        for path, value in expected.items():
            _require((ROOT / path).read_bytes() == contracts.pretty(value), f"generated artifact drift: {path}")
        if source_ready:
            _validate_source_semantics()
        elif args.complete:
            raise ValueError("complete verification requires all five C37 source rows")
        counts = _validate_file_fence()
        if args.complete:
            _require(counts["missingPathCount"] == 0, "complete verification has missing fence paths")
        flags_all_false = True
    except Exception as error:
        failures.append("contracts:" + str(error))
    result = {"cardID": contracts.CARD, "result": "FAIL_STATIC" if failures else "PASS_STATIC_PROVISIONAL", "sourceReady": source_ready, "finalHashesSealed": contracts.FINAL_HASHES_SEALED, "flagsAllFalse": flags_all_false, "failures": failures, "counts": counts, "fencePathCount": len(contracts.PATH_FENCE), "existingPathCount": 0, "newPathCount": len(contracts.NEW), "productTestUIFixturePathCount": len(contracts.PRODUCT), "toolingPathCount": len(contracts.OWNED), "selectors": list(contracts.SELECTORS), "authoritySequence": contracts.SEQUENCE}
    print(__import__("json").dumps(result, sort_keys=True, indent=2) if args.json else result["result"])
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
