"""Static, fail-closed verifier for the V23-P04-C35 tooling lane.

The verifier separates authority, synthetic corpus, generated receipts, source
declarations, and the exact path fence.  A provisional static pass is not a
native or hosted acceptance claim; all status flags and final hash sealing
remain false until the separately authorized lifecycle evidence exists.
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
import p04_c35_contracts as contracts


CORPUS_SCHEMA = "V23P04C35RecipientReviewWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "schema",
        "schemaVersion",
        "cardID",
        "ordinal",
        "testOnly",
        "synthetic",
        "containsCustomerData",
        "containsSecrets",
        "persistence",
        "selectors",
        "scenarios",
        "excludedFromStableExchange",
        "forbiddenClaims",
    )
)
CORPUS_PERSISTENCE_KEYS = frozenset(
    (
        "persistentSchemaVersion",
        "recordInventoryVersion",
        "addsRecordFamily",
        "writer",
        "sessionStore",
        "namespace",
    )
)
SELECTOR_KEYS = frozenset(
    (
        "requestMode",
        "responseMode",
        "encryption",
        "decision",
        "networkRequired",
        "accountRequired",
        "entitlementRequired",
        "deliveryVerified",
        "readVerified",
        "identityVerified",
        "securityClaimed",
        "legalAcceptanceClaimed",
        "automaticApply",
        "automaticFinalize",
    )
)


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
    _require(corpus.get("schema") == CORPUS_SCHEMA, "corpus schema differs")
    _require(corpus.get("schemaVersion") == 1 and type(corpus.get("schemaVersion")) is int, "corpus schemaVersion differs")
    _require(corpus.get("cardID") == contracts.CARD, "corpus cardID differs")
    _require(corpus.get("ordinal") == contracts.ORDINAL and type(corpus.get("ordinal")) is int, "corpus ordinal differs")
    for key in ("testOnly", "synthetic"):
        _require(corpus.get(key) is True, f"corpus {key} must remain true")
    for key in ("containsCustomerData", "containsSecrets"):
        _require(corpus.get(key) is False, f"corpus {key} must remain false")

    _require(
        corpus.get("persistence") == contracts.CORPUS_PERSISTENCE
        and set(corpus["persistence"]) == CORPUS_PERSISTENCE_KEYS,
        "C35 persistence declaration differs",
    )
    _require(
        corpus.get("selectors") == contracts.CORPUS_SELECTORS
        and set(corpus["selectors"]) == SELECTOR_KEYS,
        "C35 selector object differs",
    )
    _require(corpus.get("excludedFromStableExchange") == contracts.CORPUS_EXCLUDED, "stable-exchange exclusion list differs")
    _require(corpus.get("forbiddenClaims") == contracts.CORPUS_FORBIDDEN_CLAIMS, "forbidden claim list differs")

    scenarios = corpus.get("scenarios")
    _require(isinstance(scenarios, list) and len(scenarios) == 5, "C35 must contain exactly five scenarios")
    _require(scenarios == list(contracts.SCENARIO_ROWS), "C35 scenario rows differ")
    identifiers = [row.get("id") for row in scenarios]
    kinds = [row.get("kind") for row in scenarios]
    _require(identifiers == ["G01", "A01", "H01", "I01", "R01"], "C35 scenario IDs differ")
    _require(kinds == ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"], "C35 scenario tiers differ")


def _artifact_documents(expected: dict[str, Any]) -> dict[str, dict[str, Any]]:
    documents: dict[str, dict[str, Any]] = {}
    for path in expected:
        value = _read_json(path)
        _require(isinstance(value, dict), f"artifact must be an object: {path}")
        documents[path] = value
    return documents


def _validate_flags(documents: dict[str, dict[str, Any]], corpus: dict[str, Any]) -> None:
    # The corpus deliberately uses named booleans rather than claiming any
    # native, hosted, adoption, acceptance, release, or final-hash state.
    selectors = corpus["selectors"]
    for key in (
        "networkRequired",
        "accountRequired",
        "entitlementRequired",
        "deliveryVerified",
        "readVerified",
        "identityVerified",
        "securityClaimed",
        "legalAcceptanceClaimed",
        "automaticApply",
        "automaticFinalize",
    ):
        _require(selectors.get(key) is False, f"corpus selector claim must be false: {key}")
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("flags") == contracts.FLAGS, f"artifact flags differ: {path}")
        _require(document.get("finalHashesSealed") is False, f"artifact finalHashesSealed must be false: {path}")


def _validate_artifact_semantics(
    documents: dict[str, dict[str, Any]], expected: dict[str, Any]
) -> None:
    _require(
        set(documents)
        == {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST},
        "artifact set differs",
    )
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        _require(document.get("cardID") == contracts.CARD, f"artifact cardID differs: {path}")
        _require(document.get("ordinal") == contracts.ORDINAL, f"artifact ordinal differs: {path}")
        if path in (contracts.CONTRACT, contracts.EVIDENCE, contracts.MANIFEST):
            _require(document.get("authority") == expected[contracts.CONTRACT]["authority"], f"artifact authority differs: {path}")
            _require(document.get("sourceRows") == expected[contracts.CONTRACT]["sourceRows"], f"artifact source rows differ: {path}")

    contract = documents[contracts.CONTRACT]
    _require(contract.get("contract") == "RecipientReviewWorkflowContractV1", "contract identity differs")
    _require(contract.get("lifecycle") == expected[contracts.CONTRACT]["lifecycle"], "contract lifecycle boundary differs")
    _require(contract.get("independence") == expected[contracts.CONTRACT]["independence"], "contract independence boundary differs")
    requirements = contract.get("requirements")
    _require(isinstance(requirements, dict), "contract requirements missing")
    true_requirements = (
        "entitlementIndependent",
        "isolatedRecipientFlow",
        "exactRequestByteReplay",
        "responseReceivedElsewhereUnverified",
        "previewZeroWrite",
        "freshRevisionRequired",
        "explicitAcceptAndApplyRequired",
        "wrongPassphraseAndTamperNeutral",
        "legacyClearWarning",
        "noClearDowngrade",
        "ephemeralPassphrase",
        "optionalEncryptionOnly",
        "serviceRequestInnerKindRejected",
        "c48SoleStore",
        "c14CanonicalApplyOnly",
        "c54OptionalOnly",
        "duplicateTerminalResponseQuarantined",
        "noIdentityDeliveryOrLegalClaim",
        "noSecondDurableFamilyStoreWriterMigration",
        "exactReplayIdempotent",
        "finalizedHistoryImmutable",
    )
    for key in true_requirements:
        _require(requirements.get(key) is True, f"contract requirement is not enabled: {key}")
    _require(requirements.get("canonicalApplyOwner") == "WorkspaceWriterV1", "canonical apply owner differs")
    _require(requirements.get("canonicalApplyCard") == "V23-P04-C14", "canonical apply card differs")
    _require(requirements.get("providerCardID") == "V23-P03-C48", "C48 provider identity differs")
    _require(requirements.get("soleStore") == "PortableExchangeSessionStoreV2", "sole store differs")
    _require(requirements.get("optionalProvider") == "V23-P03-C54:ENCRYPTED_REVIEW", "C54 optional provider differs")
    _require(requirements.get("canonicalCoordinator") == "RecipientReviewWorkflowCoordinatorV1", "canonical coordinator differs")
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "contract evidence IDs differ")

    evidence = documents[contracts.EVIDENCE]
    _require(evidence.get("receipt") == "RecipientReviewWorkflowEvidenceReceiptV1", "evidence receipt identity differs")
    _require(evidence.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "evidence IDs differ")
    _require(evidence.get("receiptState") == "PROVISIONAL_STATIC_TOOLING", "evidence state differs")
    _require(evidence.get("acceptanceCredit") is False, "evidence acceptance credit must be false")
    _require(evidence.get("lifecycle") == expected[contracts.EVIDENCE]["lifecycle"], "evidence lifecycle boundary differs")
    _require(evidence.get("independence") == expected[contracts.EVIDENCE]["independence"], "evidence independence boundary differs")
    claims = evidence.get("claims")
    _require(isinstance(claims, dict) and claims and all(value is False for value in claims.values()), "evidence claims must all be false")
    _require(evidence.get("prohibitedClaims") == contracts.CORPUS_FORBIDDEN_CLAIMS, "evidence claim boundaries differ")

    brand = documents[contracts.BRAND]
    _require(brand.get("schema") == "BrandImpactManifestV1", "brand schema differs")
    _require(brand.get("requiresAcceptedS10_6Reconciliation") is True, "S10.6 reconciliation requirement missing")
    _require(brand.get("uiAdoptionSkipped") is True and brand.get("uiAcceptanceCredit") is False, "brand UI boundary differs")
    for key in ("nativeOrHostedAdoption", "installationDependency", "c33SemanticDependency", "c54EncryptionOwnerChanged"):
        _require(brand.get(key) is False, f"brand boundary must be false: {key}")
    _require(brand.get("claimsSafeCompliantPermittedApproved") is False, "brand claim boundary must be false")
    _require(brand.get("customerDataPresent") is False and brand.get("customerSecretsPresent") is False, "brand data boundary differs")

    manifest = documents[contracts.MANIFEST]
    _require(manifest.get("schema") == "V23P04C35ToolingManifestV1", "manifest schema differs")
    _require(manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest path fence differs")
    _require(manifest.get("authority") == expected[contracts.CONTRACT]["authority"], "manifest authority differs")
    _require(manifest.get("counts") == {
        "fencePathCount": 14,
        "existingPathCount": 1,
        "newPathCount": 13,
        "productTestUIFixturePathCount": 5,
        "toolingPathCount": 8,
        "durableFamilyCount": 0,
        "s10ReservationOverlapCount": 0,
    }, "manifest counts differ")
    _require(manifest.get("independence") == expected[contracts.CONTRACT]["independence"], "manifest independence differs")
    expected_hashes = {
        contracts.CONTRACT: contracts.sha(contracts.pretty(expected[contracts.CONTRACT])),
        contracts.EVIDENCE: contracts.sha(contracts.pretty(expected[contracts.EVIDENCE])),
        contracts.BRAND: contracts.sha(contracts.pretty(expected[contracts.BRAND])),
        contracts.SCHEMA: contracts.sha(contracts.pretty(expected[contracts.SCHEMA])),
    }
    _require(
        manifest.get("files")
        == [{"path": path, "sha256": digest} for path, digest in expected_hashes.items()],
        "manifest file hashes differ",
    )

    schema = documents[contracts.SCHEMA]
    _require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect differs")
    _require(schema.get("title") == "V23P04C35RecipientReviewWorkflowToolingV1", "schema title differs")
    _require(schema.get("properties", {}).get("cardID", {}).get("const") == contracts.CARD, "schema card identity differs")
    _require(schema.get("properties", {}).get("ordinal", {}).get("const") == contracts.ORDINAL, "schema ordinal differs")
    _require(schema.get("properties", {}).get("finalHashesSealed", {}).get("const") is False, "schema final hash boundary differs")


def _method_bodies(test_text: str) -> dict[str, str]:
    matches = list(re.finditer(r"(?m)^\s*func\s+(testV23P04C35[A-Za-z0-9]+)\s*\(", test_text))
    _require(len(matches) == 5, "C35 tests must declare exactly five evidence methods")
    methods: dict[str, str] = {}
    for index, match in enumerate(matches):
        name = match.group(1)
        _require(name not in methods, f"duplicate C35 test method: {name}")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(test_text)
        methods[name] = test_text[match.start():end]
    return methods


def _require_any(text: str, terms: tuple[str, ...], message: str) -> None:
    lowered = text.lower()
    _require(any(term.lower() in lowered for term in terms), message)


def _validate_source_semantics() -> None:
    coordinator_path = contracts.PRODUCT[0]
    view_path = contracts.PRODUCT[1]
    test_path = contracts.PRODUCT[2]
    store_path = contracts.EXISTING[0]
    coordinator = _read_text(coordinator_path)
    view = _read_text(view_path)
    tests = _read_text(test_path)
    store = _read_text(store_path)
    source = "\n".join((coordinator, view, tests, store))

    declarations = (
        r"\bstruct\s+RecipientReviewWorkflowContextV1\b",
        r"\bstruct\s+RecipientReviewWorkflowProjectionV1\b",
        r"\benum\s+RecipientReviewWorkflowCommandV1\b",
        r"\b(?:final\s+)?class\s+RecipientReviewWorkflowCoordinatorV1\b",
        r"\bstruct\s+RecipientReviewRequestReplayV1\b",
        r"\bstruct\s+RecipientReviewImportPreviewV1\b",
        r"\bstruct\s+RecipientReviewHistoryReceiptV1\b",
    )
    for declaration in declarations:
        _require(re.search(declaration, coordinator) is not None, f"C35 declaration missing: {declaration}")

    # These are the coordinator's real command cases.  Checking the cases
    # rather than an invented generic spelling makes source drift visible.
    for case in (
        "replayClearRequest",
        "createResponse",
        "previewImport",
        "acceptAndApply",
        "finalizeSessionOnly",
        "recordResponseReceivedElsewhere",
        "recoverAcceptAndApply",
    ):
        _require(re.search(rf"\bcase\s+.*\.?{re.escape(case)}\b", coordinator) is not None or re.search(rf"\b{re.escape(case)}\b", coordinator) is not None, f"C35 command case/API missing: {case}")
    _require(re.search(r"\bfunc\s+execute\s*\(", coordinator) is not None, "C35 execute API missing")
    _require(re.search(r"\bfunc\s+recoverAcceptAndApply\s*\(", coordinator) is not None, "C35 recover API missing")

    for token in (
        "PortableExchangeSessionStoreV2",
        "exactReviewRequestBytes",
        "PortableExchangeReviewRequestBytesV2",
        "ReviewRequestC14SubjectItemMappingV1",
        "canonicalReview.acceptAndApply",
        "WorkspaceWriterV1",
        "OriginRecordedReviewResponseV1",
        "EncryptedPortableEnvelopeCoordinatorV1",
        "reviewProtectionMode",
        "passphraseEncryptedV1",
    ):
        _require(token in source, f"C35 source token missing: {token}")
    for token in ("basisWorkspaceRevision", "expectedRevision", "workspaceRevision", "MutationIDV1", "mutationID"):
        _require(token in coordinator or token in store, f"C35 revision/mutation token missing: {token}")
    for token in ("isZeroWrite: true", "previewWrites: false", "requiresExplicitDecision", "acceptAndApply"):
        _require(token in coordinator, f"C35 preview/apply semantic token missing: {token}")
    for token in ("wrongPassphraseOrDamagedEnvelope", "cleartextWarningRequired", "legacyClearWithExplicitWarning", "passphrase.clear()"):
        _require(token in coordinator, f"C35 protection semantic token missing: {token}")
    _require("unsupportedExchangeKind" in coordinator and "innerKind" in coordinator, "C35 clear-downgrade/kind boundary missing")
    _require("recordResponseReceivedElsewhere" in coordinator and "isVerifiedResponse: false" in coordinator, "unverified elsewhere response boundary missing")
    _require("appliedToCanonicalC14" in store, "C14 apply receipt binding missing from sole store")
    _require("PortableExchangeImportReceiptV2" in store, "C48 import receipt binding missing")

    for token in (
        "RecipientReviewWorkflowView",
        "RecipientReviewWorkflowCoordinatorV1",
        "RecipientReviewWorkflowProjectionV1",
        "previewAccessibilityIdentifier",
        "accept-and-apply",
        "normal workspace",
        "passphrase",
    ):
        _require(token.lower() in view.lower(), f"C35 view semantic token missing: {token}")

    # C35 cannot introduce another durable family, writer, renderer, backend,
    # kernel, model container, network client, telemetry, or commerce seam.
    for path, text in (
        (coordinator_path, coordinator),
        (view_path, view),
        (test_path, tests),
    ):
        _require(
            re.search(
                r"(?m)^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:final\s+)?(?:class|struct|actor|enum)\s+\w*(?:Store|Writer|Renderer|Backend|Kernel)\w*\b",
                text,
            )
            is None,
            f"parallel storage/rendering declaration in {path}",
        )
        # The unit harness may instantiate the already-authorized C14
        # WorkspaceWriterV1 in an in-memory ModelContainer.  That is test
        # plumbing, not a new C35 persistence family.  Product sources remain
        # barred from model/network/commerce seams.
        forbidden_tokens = ("@Model", "ModelContainer", "ModelConfiguration", "URLSession", "Telemetry", "StoreKit")
        if path == test_path:
            forbidden_tokens = ("@Model", "URLSession", "Telemetry", "StoreKit")
        for forbidden in forbidden_tokens:
            _require(forbidden not in text, f"C35 source introduces prohibited infrastructure token {forbidden}: {path}")

    for forbidden in (
        "InstallationWorkflowCoordinatorV1",
        "InstallationWorkflowCommandV1",
        "InstallationPlanCapabilityV1",
        "InstallationScanCapabilityV1",
        "installationContractSHA256",
        "V23-P04-C33",
    ):
        _require(forbidden not in coordinator, f"C35 coordinator has installation/C33 dependency: {forbidden}")

    claims = re.search(
        r"enum\s+RecipientReviewWorkflowClaimsV1\b.*?(?=\n}\s*\n|\Z)",
        coordinator,
        re.DOTALL,
    )
    _require(claims is not None, "C35 claim boundary declaration missing")
    for token in (
        "requiresEntitlement = false",
        "previewWrites = false",
        "establishesIdentity = false",
        "establishesDelivery = false",
        "establishesRead = false",
        "establishesLegalEffect = false",
        "establishesSecurityApproval = false",
    ):
        _require(token in claims.group(0), f"C35 prohibited claim is not false: {token}")

    methods = _method_bodies(tests)
    by_id: dict[str, str] = {}
    for method, body in methods.items():
        match = re.search(r"testV23P04C35([GAHIR]01)", method)
        _require(match is not None, f"test method does not identify a G/A/H/I/R row: {method}")
        identifier = match.group(1)
        _require(identifier not in by_id, f"duplicate C35 evidence method ID: {identifier}")
        by_id[identifier] = body
    _require(
        tuple(by_id) == tuple(row["id"] for row in contracts.SCENARIO_ROWS),
        "C35 test method order differs",
    )
    required_terms = {
        "G01": ("isolated", "offline", "replay", "preview", "zero", "acceptandapply"),
        "A01": ("legacy", "clear", "warning", "encryption", "elsewhere", "disabled"),
        "H01": ("wrong", "damaged", "passphrase", "wrongPassphraseOrDamagedEnvelope", "duplicate", "stale"),
        "I01": ("interrupt", "recover", "receipt", "mutation", "count"),
        "R01": ("relaunch", "replay", "reexport", "receipt", "divergence", "deterministic"),
    }
    for identifier, terms in required_terms.items():
        body = by_id[identifier].lower()
        for term in terms:
            _require(term.lower() in body, f"{identifier} test lacks real semantic coverage: {term}")
    _require("XCTAssertThrowsError" in by_id["H01"], "H01 must exercise neutral fail-closed errors")
    _require("XCTAssertEqual" in by_id["R01"], "R01 must compare deterministic recovery output")
    _require_any(
        by_id["R01"],
        ("byteIdentical", "== replay", "replay ==", "request.sha256", "XCTAssertEqual(first, second)"),
        "R01 must compare exact replay",
    )

    ui = _read_text(contracts.PRODUCT[4])
    _require(len(re.findall(r"\bthrow\s+XCTSkip\s*\(", ui)) == 1, "C35 UI lane must have exactly one deferred no-launch skip")
    _require("V23-P04-C35" in ui and "S10" in ui and "no-launch" in ui.lower(), "C35 UI deferral boundary differs")
    _require("launch" not in ui.lower().replace("no-launch", ""), "C35 UI must not launch or claim native adoption")


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
        corpus = _read_json(contracts.PRODUCT[3])
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
            raise ValueError("complete verification requires all six source rows")
        counts = _validate_file_fence()
        _require(counts["unownedChangedPathCount"] == 0, "unowned changed paths")
        if args.complete:
            _require(counts["missingPathCount"] == 0, "complete verification has missing fence paths")
        flags_all_false = True
    except Exception as error:
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
        "productTestUIFixturePathCount": len(contracts.PRODUCT),
        "toolingPathCount": len(contracts.OWNED),
        "selectors": list(contracts.SELECTORS),
        "authoritySequence": contracts.SEQUENCE,
    }
    print(json.dumps(result, sort_keys=True, indent=2) if args.json else result["result"])
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
