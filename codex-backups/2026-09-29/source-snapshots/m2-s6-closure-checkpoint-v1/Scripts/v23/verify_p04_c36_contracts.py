"""Fail-closed static verifier for the V23-P04-C36 tooling lane.

This verifier proves the pinned authority, synthetic fixture, generated
receipts, C36 source semantics, and exact fourteen-path fence (including the
authorized C55 owner overlap).  A static pass
does not claim native, hosted, adoption, acceptance, release, or final-hash
evidence.
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
import p04_c36_contracts as contracts


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
    _require(set(corpus) == set(contracts.CORPUS_TOP_LEVEL_KEYS), "C36 corpus top-level key set differs")
    _require(corpus.get("schema") == contracts.CORPUS_SCHEMA, "C36 corpus schema differs")
    _require(corpus.get("schemaVersion") == 1 and type(corpus.get("schemaVersion")) is int, "C36 corpus schemaVersion differs")
    _require(corpus.get("cardID") == contracts.CARD, "C36 corpus cardID differs")
    _require(corpus.get("corpusID") == "v23-p04-c36-manual-work-resource-workflow-corpus-v1", "C36 corpus ID differs")
    _require(corpus.get("testOnly") is True and corpus.get("synthetic") is True, "C36 corpus must be test-only synthetic data")
    _require(corpus.get("containsCustomerData") is False and corpus.get("containsProductionSecrets") is False, "C36 corpus data boundary differs")
    _require(corpus.get("deterministicSeed") == "C36-V23-FIXED-0001", "C36 deterministic seed differs")
    _require(corpus.get("evidenceIDs") == list(contracts.SELECTORS), "C36 evidence IDs differ")

    persistence = corpus.get("consumedPersistence")
    _require(isinstance(persistence, dict) and set(persistence) == set(contracts.CORPUS_PERSISTENCE_KEYS), "C36 persistence key set differs")
    _require(persistence == contracts.CORPUS_PERSISTENCE, "C36 consumed persistence differs")
    for key in ("manualWorkResource", "partsStock"):
        _require(set(persistence[key]) == set(contracts.CORPUS_VERSION_KEYS), f"C36 persistence version keys differ: {key}")

    selectors = corpus.get("selectors")
    _require(isinstance(selectors, dict) and set(selectors) == set(contracts.CORPUS_SELECTOR_KEYS), "C36 selector key set differs")
    _require(selectors == contracts.CORPUS_SELECTORS, "C36 selector values differ")
    _require(corpus.get("golden") == contracts.CORPUS_GOLDEN, "C36 golden fixture differs")
    _require(corpus.get("alternate") == contracts.CORPUS_ALTERNATE, "C36 alternate fixture differs")
    _require(corpus.get("hostileCases") == contracts.CORPUS_HOSTILE_CASES, "C36 hostile case corpus differs")
    _require(corpus.get("recoveryCases") == contracts.CORPUS_RECOVERY_CASES, "C36 recovery case corpus differs")


def _artifact_documents(expected: dict[str, Any]) -> dict[str, dict[str, Any]]:
    documents: dict[str, dict[str, Any]] = {}
    for path in expected:
        value = _read_json(path)
        _require(isinstance(value, dict), f"artifact must be an object: {path}")
        documents[path] = value
    return documents


def _validate_flags(documents: dict[str, dict[str, Any]], corpus: dict[str, Any]) -> None:
    selectors = corpus["selectors"]
    for key in ("automaticStockMovement", "catalogLookup", "liveBalanceClaim", "accountingClaim", "invoiceClaim", "availabilityClaim", "approvalClaim", "usesBinaryFloatingPoint", "requiresNetwork", "requiresAccount", "requiresEntitlement"):
        _require(selectors.get(key) is False, f"C36 selector claim must be false: {key}")
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("flags") == contracts.FLAGS, f"C36 artifact flags differ: {path}")
        _require(document.get("finalHashesSealed") is False, f"C36 finalHashesSealed must be false: {path}")


def _validate_artifact_semantics(documents: dict[str, dict[str, Any]], expected: dict[str, Any]) -> None:
    _require(set(documents) == {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST}, "C36 artifact set differs")
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("cardID") == contracts.CARD, f"artifact cardID differs: {path}")
        _require(document.get("ordinal") == contracts.ORDINAL, f"artifact ordinal differs: {path}")
        if path in (contracts.CONTRACT, contracts.EVIDENCE, contracts.MANIFEST):
            _require(document.get("authority") == expected[contracts.CONTRACT]["authority"], f"artifact authority differs: {path}")
            _require(document.get("sourceRows") == expected[contracts.CONTRACT]["sourceRows"], f"artifact source rows differ: {path}")

    contract = documents[contracts.CONTRACT]
    _require(contract.get("contract") == "ManualWorkResourceWorkflowContractV1", "C36 contract identity differs")
    _require(contract.get("lifecycle") == expected[contracts.CONTRACT]["lifecycle"], "C36 contract lifecycle differs")
    _require(contract.get("independence") == expected[contracts.CONTRACT]["independence"], "C36 contract independence differs")
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "C36 contract evidence IDs differ")
    _require(contract.get("scenarioRows") == list(contracts.SCENARIO_ROWS), "C36 contract scenario rows differ")
    requirements = contract.get("requirements")
    _require(isinstance(requirements, dict), "C36 contract requirements missing")
    for key in contracts.CORPUS_EXPECTED:
        _require(requirements.get(key) is True, f"C36 requirement is not enabled: {key}")
    for key, value in {"manualAppendOwner": "WorkResourceCoordinatorV1", "manualProviderCardID": "V23-P03-C49", "manualRecordFamily": "ManualWorkResourceRecordRow_V37_RECORDS36", "optionalStockProvider": "V23-P03-C55:USE_FROM_STOCK", "soleCompositeCommit": "PartsStockCoordinatorV1_USE_OR_RETURN_WITH_EMBEDDED_FROZEN_WORK_SUCCESSOR", "stockFamily": "PartsStockCoordinatorV1_V41_RECORDS40", "executeAPI": "ManualWorkResourceWorkflowCoordinatorV1.execute", "projectionAPI": "ManualWorkResourceWorkflowCoordinatorV1.projection", "forbiddenNumericType": "Double", "stockCallerMutationIDParameter": "mutationID suppliedMutationID: MutationIDV1? = nil", "c36StockDTOField": "mutationID: MutationIDV1"}.items():
        _require(requirements.get(key) == value, f"C36 requirement differs: {key}")
    _require(requirements.get("manualCommandCases") == ["saveManual", "useFromStock", "returnToStock"], "C36 command cases differ")
    _require(requirements.get("typedStockFallback") == ["available", "disabled", "unavailable", "manualOnly"], "C36 typed fallback cases differ")

    evidence = documents[contracts.EVIDENCE]
    _require(evidence.get("receipt") == "ManualWorkResourceWorkflowEvidenceReceiptV1", "C36 evidence receipt identity differs")
    _require(evidence.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "C36 evidence IDs differ")
    _require(evidence.get("receiptState") == "PROVISIONAL_STATIC_TOOLING", "C36 evidence state differs")
    _require(evidence.get("acceptanceCredit") is False, "C36 evidence acceptance credit must be false")
    _require(evidence.get("lifecycle") == expected[contracts.EVIDENCE]["lifecycle"], "C36 evidence lifecycle differs")
    _require(evidence.get("independence") == expected[contracts.EVIDENCE]["independence"], "C36 evidence independence differs")
    claims = evidence.get("claims")
    _require(isinstance(claims, dict) and claims and all(value is False for value in claims.values()), "C36 evidence claims must all be false")
    _require(evidence.get("prohibitedClaims") == contracts.CORPUS_FORBIDDEN_CLAIMS, "C36 prohibited claims differ")

    brand = documents[contracts.BRAND]
    _require(brand.get("schema") == "BrandImpactManifestV1", "C36 brand schema differs")
    _require(brand.get("requiresAcceptedS10_6Reconciliation") is True, "C36 S10.6 reconciliation requirement missing")
    _require(brand.get("uiAdoptionSkipped") is True and brand.get("uiAcceptanceCredit") is False, "C36 UI adoption boundary differs")
    for key in ("nativeOrHostedAdoption", "installationDependency", "c33SemanticDependency", "c34PunchReviewDependency", "customerDataPresent", "customerSecretsPresent", "claimsSafeCompliantPermittedApproved", "manualEntryClaim", "stockAvailabilityClaim", "accountingOrInvoiceClaim"):
        _require(brand.get(key) is False, f"C36 brand boundary must be false: {key}")

    manifest = documents[contracts.MANIFEST]
    _require(manifest.get("schema") == "V23P04C36ToolingManifestV1", "C36 manifest schema differs")
    _require(manifest.get("pathFence") == list(contracts.PATH_FENCE), "C36 manifest path fence differs")
    _require(manifest.get("authority") == expected[contracts.CONTRACT]["authority"], "C36 manifest authority differs")
    _require(manifest.get("counts") == {"fencePathCount": 14, "existingPathCount": 1, "newPathCount": 13, "productTestUIFixturePathCount": 5, "toolingPathCount": 8, "durableFamilyCount": 0, "s10ReservationOverlapCount": 0}, "C36 manifest counts differ")
    _require(manifest.get("independence") == expected[contracts.CONTRACT]["independence"], "C36 manifest independence differs")
    expected_hashes = {contracts.CONTRACT: contracts.sha(contracts.pretty(expected[contracts.CONTRACT])), contracts.EVIDENCE: contracts.sha(contracts.pretty(expected[contracts.EVIDENCE])), contracts.BRAND: contracts.sha(contracts.pretty(expected[contracts.BRAND])), contracts.SCHEMA: contracts.sha(contracts.pretty(expected[contracts.SCHEMA]))}
    _require(manifest.get("files") == [{"path": path, "sha256": digest} for path, digest in expected_hashes.items()], "C36 manifest file hashes differ")

    schema = documents[contracts.SCHEMA]
    _require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "C36 schema dialect differs")
    _require(schema.get("title") == "V23P04C36ManualWorkResourceWorkflowToolingV1", "C36 schema title differs")
    _require(schema.get("properties", {}).get("cardID", {}).get("const") == contracts.CARD, "C36 schema card identity differs")
    _require(schema.get("properties", {}).get("ordinal", {}).get("const") == contracts.ORDINAL, "C36 schema ordinal differs")
    _require(schema.get("properties", {}).get("finalHashesSealed", {}).get("const") is False, "C36 schema final hash boundary differs")


def _method_bodies(test_text: str) -> dict[str, str]:
    matches = list(re.finditer(r"(?m)^\s*func\s+(testV23P04C36[A-Za-z0-9]+)\s*\(", test_text))
    _require(len(matches) == 5, "C36 tests must declare exactly five evidence methods")
    methods: dict[str, str] = {}
    for index, match in enumerate(matches):
        name = match.group(1)
        _require(name not in methods, f"duplicate C36 test method: {name}")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(test_text)
        methods[name] = test_text[match.start():end]
    return methods


def _validate_source_semantics() -> None:
    coordinator = _read_text(contracts.PRODUCT[0])
    view = _read_text(contracts.PRODUCT[1])
    tests = _read_text(contracts.PRODUCT[2])
    fixture = _read_json(contracts.PRODUCT[3])
    stock_coordinator = _read_text(contracts.EXISTING[0])
    source = "\n".join((coordinator, view, tests, stock_coordinator))

    declarations = (
        r"\benum\s+ManualWorkResourceWorkflowFailureV1\b",
        r"\benum\s+ManualWorkResourceStockCapabilityV1\b",
        r"\bstruct\s+ManualWorkResourceSuccessorDraftV1\b",
        r"\bstruct\s+ManualWorkResourceWorkflowContextV1\b",
        r"\bstruct\s+ManualWorkResourceWorkflowProjectionV1\b",
        r"\bstruct\s+ManualWorkResourceUseStockCommandV1\b",
        r"\bstruct\s+ManualWorkResourceReturnStockCommandV1\b",
        r"\benum\s+ManualWorkResourceWorkflowCommandV1\b",
        r"\benum\s+ManualWorkResourceWorkflowOutcomeV1\b",
        r"\benum\s+ManualWorkResourceWorkflowClaimsV1\b",
        r"\b(?:final\s+)?class\s+ManualWorkResourceWorkflowCoordinatorV1\b",
    )
    for declaration in declarations:
        _require(re.search(declaration, coordinator) is not None, f"C36 declaration missing: {declaration}")
    for token in ("case saveManual", "case useFromStock", "case returnToStock", "func projection(", "func execute(", "WorkResourceCoordinatorV1", "PartsStockCoordinatorV1", "workResources.append", "stock.use(", "stock.returnAgainstUse(", "ManualWorkResourceWorkflowOutcomeV1", "ManualWorkResourceSuccessorDraftV1", "ManualWorkResourceWorkflowContextV1", "ManualWorkResourceWorkflowProjectionV1"):
        _require(token in coordinator, f"C36 coordinator token missing: {token}")
    _require(coordinator.count("workResources.append") == 1, "C36 must not append C49 twice for stock composite actions")
    _require(coordinator.count("stock.use(") == 1 and coordinator.count("stock.returnAgainstUse(") == 1, "C55 use/return must each have one delegated composite call")
    for token in ("ManualDurationV1", "ManualMaterialLineV1", "DirectCostEntryV1", "ExactDecimalQuantityV1", "ExactMoneyAmountV1", "StockQuantityV1", "Int64", "mantissa", "scale", "MutationIDV1", "mutationID", "frozenMaterialLineID", "sourceUse", "predecessorFrontier", "outstanding", "workResourceSuccessor", "stockCapability", ".manualOnly", ".disabled", ".unavailable", "editingChangesStock: false", "stockChanged: false"):
        _require(token in source, f"C36 semantic token missing: {token}")
    _require("Double" not in source, "C36 must not use Double or binary floating point")
    _require("input.mutationID" in coordinator and "mutationID in" in coordinator, "C36 same-MutationID successor binding missing")
    _require("input.workResourceSuccessor.predecessor == input.workResourcePredecessor" in coordinator, "C36 frozen successor binding missing")
    _require("outstanding >= input.quantity.mantissa" in coordinator, "C36 outstanding return bound missing")

    # C55 remains the existing owner of the atomic stock transaction.  The
    # correction adds a caller-stable ID seam while preserving the legacy
    # default allocation for callers that do not supply one.
    for operation in ("use", "returnAgainstUse"):
        _require(re.search(rf"func {operation}\([^\n]*mutationID suppliedMutationID: MutationIDV1\? = nil", stock_coordinator) is not None, f"C55 {operation} caller mutation-ID overload missing")
    _require(stock_coordinator.count("mutationID suppliedMutationID: MutationIDV1? = nil") == 2, "C55 caller mutation-ID overload cardinality differs")
    _require(stock_coordinator.count("if let suppliedMutationID") == 2, "C55 supplied mutation-ID branches differ")
    _require(stock_coordinator.count("MutationIDV1(rawValue: suppliedMutationID.rawValue)") == 2, "C55 supplied mutation-ID normalization differs")
    _require(stock_coordinator.count("else { mutationID = try writer.makeMutationID() }") == 2, "C55 default mutation-ID allocation differs")
    _require(stock_coordinator.count("commit(.use(use))") == 1 and stock_coordinator.count("commit(.returnAgainstUse(value))") == 1, "C55 composite commit ownership differs")

    # Both C36 stock DTOs carry the caller ID through to C55 and use it to
    # construct the frozen successor, closing the retry identity seam.
    for command in ("ManualWorkResourceUseStockCommandV1", "ManualWorkResourceReturnStockCommandV1"):
        block = re.search(rf"struct {command}\b.*?\n\}}", coordinator, re.DOTALL)
        _require(block is not None and "let mutationID: MutationIDV1" in block.group(0), f"C36 DTO mutation-ID field missing: {command}")
    _require(len(re.findall(r"(?m)^\s+mutationID: input\.mutationID,\s*$", coordinator)) == 2, "C36 DTO mutation-ID propagation differs")
    _require(coordinator.count("input.workResourceSuccessor.entry(mutationID: input.mutationID)") == 1, "C36 successor DTO mutation-ID binding differs")

    for path, text in ((contracts.PRODUCT[0], coordinator), (contracts.PRODUCT[1], view)):
        _require(re.search(r"(?m)^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:final\s+)?(?:class|struct|actor|enum)\s+\w*(?:Store|Writer|Renderer|Backend|Kernel)\w*\b", text) is None, f"parallel storage/rendering declaration in {path}")
        for forbidden in ("@Model", "ModelContainer", "ModelConfiguration", "URLSession", "Telemetry", "StoreKit"):
            _require(forbidden not in text, f"C36 product source introduces prohibited infrastructure token {forbidden}: {path}")
    for forbidden in ("InstallationWorkflowCoordinatorV1", "InstallationWorkflowCommandV1", "PunchReviewWorkflowCoordinatorV1", "RecipientReviewWorkflowCoordinatorV1", "V23-P04-C33", "V23-P04-C34"):
        _require(forbidden not in coordinator + view, f"C36 has unrelated workflow dependency: {forbidden}")

    claims = re.search(r"enum\s+ManualWorkResourceWorkflowClaimsV1\b.*?(?=\n}\s*\n|\Z)", coordinator, re.DOTALL)
    _require(claims is not None, "C36 claim boundary declaration missing")
    for token in ("editingChangesStock = false", "createsAccountingTruth = false", "createsInvoiceTruth = false", "establishesCatalogAvailability = false", "establishesApproval = false", "establishesDelivery = false", "establishesIdentity = false"):
        _require(token in claims.group(0), f"C36 prohibited claim is not false: {token}")

    methods = _method_bodies(tests)
    ids: dict[str, str] = {}
    for method, body in methods.items():
        match = re.search(r"testV23P04C36([GAHIR]01)", method)
        _require(match is not None, f"C36 test method does not identify a G/A/H/I/R row: {method}")
        identifier = match.group(1)
        _require(identifier not in ids, f"duplicate C36 evidence method ID: {identifier}")
        ids[identifier] = body
    _require(tuple(ids) == ("G01", "A01", "H01", "I01", "R01"), "C36 test method order differs")
    required_terms = {
        "G01": ("manual", "stock", "mutation", "receipt", "successor", "canSaveManualEntry", "editingChangesStock"),
        "A01": ("manualonly", "disabled", "unavailable", "manual save", "stockmovementeventrowv1", "0"),
        "H01": ("invalid", "stale", "wrongpart", "overreturn", "frontier", "baseline", "XCTAssertThrowsError"),
        "I01": ("effectbeforereceipt", "aftereffectbeforereceipt", "atomic", "composite", "XCTAssertThrowsError", "retry"),
        "R01": ("idempotent", "replay", "divergent", "return", "lineage", "XCTAssertEqual", "receipt"),
    }
    for identifier, terms in required_terms.items():
        body = ids[identifier].lower()
        for term in terms:
            _require(term.lower() in body, f"{identifier} test lacks real semantic coverage: {term}")
    interruption = ids["I01"]
    _require(interruption.count(".useFromStock(interruptedUse)") >= 2, "I01 must retry the identical stock-use command")
    _require(interruption.count(".returnToStock(interruptedReturn)") >= 2, "I01 must retry the identical stock-return command")
    _require("XCTAssertEqual(recoveredUse.mutationID, interruptedUse.mutationID)" in interruption, "I01 must prove caller-stable use mutation ID")
    _require("XCTAssertEqual(recoveredReceipt.mutationID, interruptedUse.mutationID)" in interruption, "I01 must prove stock receipt mutation ID")
    _require("XCTAssertEqual(replayedReturn, recoveredReturn)" in interruption and "XCTAssertEqual(replayedReturnReceipt, recoveredReturnReceipt)" in interruption, "I01 return replay must be exact")
    _require("PersistentSchemaV41" in tests and "JSONDecoder" in tests, "C36 tests must bind the existing V41 schema and fixture")
    _require(fixture.get("schema") == contracts.CORPUS_SCHEMA, "C36 source fixture parse differs")

    for forbidden in ("@Model", "URLSession", "Telemetry", "StoreKit"):
        _require(forbidden not in tests, f"C36 tests introduce prohibited seam: {forbidden}")
    ui = _read_text(contracts.PRODUCT[4])
    _require(len(re.findall(r"\bthrow\s+XCTSkip\s*\(", ui)) == 1, "C36 UI lane must have exactly one deferred no-launch skip")
    _require("V23-P04-C36" in ui and "S10" in ui and "no-launch" in ui.lower(), "C36 UI deferral boundary differs")
    _require("launch" not in ui.lower().replace("no-launch", ""), "C36 UI must not launch or claim native adoption")


def _validate_file_fence() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in contracts.git(*args).splitlines() if line}

    changed = names("diff", "--name-only", contracts.BASE, "HEAD") | names("diff", "--name-only", "HEAD") | names("diff", "--cached", "--name-only") | names("ls-files", "--others", "--exclude-standard")
    allowed = set(contracts.PATH_FENCE)
    unowned = changed - allowed
    _require(not unowned, "unowned changed paths: " + ",".join(sorted(unowned)))
    return {"changedPathCount": len(changed & allowed), "unownedChangedPathCount": len(unowned), "missingPathCount": sum(not (contracts.ROOT / path).is_file() for path in contracts.PATH_FENCE), "s10ReservationOverlapCount": 0, "fencePathCount": len(contracts.PATH_FENCE), "existingPathCount": len(contracts.EXISTING), "newPathCount": len(contracts.NEW), "productTestUIFixturePathCount": len(contracts.PRODUCT), "toolingPathCount": len(contracts.OWNED)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all five C36 product/test/UI/fixture sources")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable result")
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
        _validate_flags(generated, corpus)
        _validate_artifact_semantics(generated, expected)
        for path, value in expected.items():
            _require((contracts.ROOT / path).read_bytes() == contracts.pretty(value), f"generated artifact drift: {path}")
        if source_ready:
            _validate_source_semantics()
        elif args.complete:
            raise ValueError("complete verification requires all five C36 source rows")
        counts = _validate_file_fence()
        _require(counts["unownedChangedPathCount"] == 0, "unowned changed paths")
        if args.complete:
            _require(counts["missingPathCount"] == 0, "complete verification has missing fence paths")
        flags_all_false = True
    except Exception as error:
        failures.append("contracts:" + str(error))
    result = {"cardID": contracts.CARD, "result": "FAIL_STATIC" if failures else "PASS_STATIC_PROVISIONAL", "sourceReady": source_ready, "finalHashesSealed": contracts.FINAL_HASHES_SEALED, "flagsAllFalse": flags_all_false, "failures": failures, "counts": counts, "fencePathCount": len(contracts.PATH_FENCE), "existingPathCount": len(contracts.EXISTING), "newPathCount": len(contracts.NEW), "productTestUIFixturePathCount": len(contracts.PRODUCT), "toolingPathCount": len(contracts.OWNED), "selectors": list(contracts.SELECTORS), "authoritySequence": contracts.SEQUENCE}
    print(json.dumps(result, sort_keys=True, indent=2) if args.json else result["result"])
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
