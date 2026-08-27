#!/usr/bin/env python3
"""Fail-closed static verification for provisional V23-P03-C16."""
from __future__ import annotations

import ast
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
import p03_c16_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def source(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def digest_without(value: dict[str, Any], key: str) -> str:
    return contracts.sha256(contracts.pretty({name: item for name, item in value.items() if name != key}))


def git(root: Path, *arguments: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(root), *arguments], check=True,
        capture_output=True,
    ).stdout


def changed_paths(root: Path) -> set[str]:
    text = git(root, "status", "--porcelain", "--untracked-files=all").decode("utf-8")
    paths = set()
    for line in text.splitlines():
        raw = line[3:]
        if " -> " in raw:
            raw = raw.split(" -> ", 1)[1]
        paths.add(raw.replace("\\", "/"))
    return paths


def schema_checks(root: Path) -> None:
    schema = load(root / contracts.SCHEMA_PATH)
    fixture = load(root / contracts.FIXTURE_PATH)
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect differs")
    require(schema.get("type") == "object" and schema.get("additionalProperties") is False, "schema root is not strict")
    for name in ("runtimeUI", "catalog", "catalogKey", "permissionCatalog", "presentation",
                 "semanticAccessibility", "semanticEntry", "legacyAllowlist", "packageBinding",
                 "frozenDisplay", "fixtureDigest", "evidenceCase"):
        require(schema.get("$defs", {}).get(name, {}).get("additionalProperties") is False,
                f"schema definition is not strict: {name}")
    portable_root = root / "Scripts/v21-contracts"
    sys.path.insert(0, str(portable_root))
    try:
        import portable_contract_validator_v1 as portable
        lock = portable.load_lock(root)
        registry = portable.load_registry(root, lock)
        base_uri = (root / contracts.SCHEMA_PATH).resolve().as_uri()
        meta = portable.validate_schema_against_official_meta(schema, registry, base_uri)
        require(meta["valid"], f"schema meta-validation differs: {meta['errors'][:5]}")
        result = portable.validate_instance(fixture, schema, registry, base_uri)
        require(result["valid"], f"fixture schema validation differs: {result['errors'][:8]}")
    finally:
        sys.path.remove(str(portable_root))


def authority_checks(root: Path) -> None:
    require(len(contracts.PATH_FENCE) == len(set(contracts.PATH_FENCE)) == 18, "path fence differs")
    require(len(contracts.NEW_PATHS) == 15 and len(contracts.EXISTING_PATHS) == 3, "path partition differs")
    require(set(contracts.NEW_PATHS) | set(contracts.EXISTING_PATHS) == set(contracts.PATH_FENCE), "path closure differs")
    require(not set(contracts.NEW_PATHS) & set(contracts.EXISTING_PATHS), "path partition overlaps")
    observed = changed_paths(root)
    require(observed == set(contracts.PATH_FENCE),
            f"changed paths differ from exact fence: missing={sorted(set(contracts.PATH_FENCE)-observed)}, extra={sorted(observed-set(contracts.PATH_FENCE))}")
    require(all((root / path).is_file() for path in contracts.PATH_FENCE), "fence file closure differs")
    import p03_c08_contracts as c08
    reserved = set(c08.ACTIVE_S10_RESERVED_PATHS)
    require(len(reserved) == 86 and not set(contracts.PATH_FENCE) & reserved, "S10 reservation differs or overlaps")
    require(contracts.S10_RESERVATION_DIGEST == c08.S10_RESERVATION_DIGEST, "reservation digest differs")


def catalog_checks(root: Path) -> None:
    catalogs = sorted(
        path.relative_to(root).as_posix()
        for path in (root / "FieldEvidenceApp").rglob("Localizable.xcstrings")
    )
    require(catalogs == [contracts.CATALOG_PATH], f"application catalog count/path differs: {catalogs}")
    catalog = load(root / contracts.CATALOG_PATH)
    require(catalog.get("sourceLanguage") == "en" and catalog.get("version") == "1.0", "catalog identity differs")
    strings = catalog.get("strings")
    require(isinstance(strings, dict) and sorted(strings) == contracts.CATALOG_KEYS, "catalog key set differs")
    for key, entry in strings.items():
        require(isinstance(entry, dict) and isinstance(entry.get("comment"), str) and entry["comment"].strip(),
                f"catalog comment differs: {key}")
        localizations = entry.get("localizations")
        require(isinstance(localizations, dict) and set(localizations) == {"en"}, f"catalog locale differs: {key}")
    plural = strings["feedback.mail.attachment_count"]["localizations"]["en"]["variations"]["plural"]
    require(set(plural) == {"one", "other"}, "English plural schema differs")

    bundled = source(root, "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift")
    literal_keys = re.findall(r'String\(localized:\s*"([^"]+)"', bundled)
    require(sorted(literal_keys) == contracts.CATALOG_KEYS and len(literal_keys) == len(set(literal_keys)) == 11,
            "literal compiler extraction key set differs")
    literal_rows = re.findall(
        r'String\(localized: "([^"]+)", defaultValue: "((?:\\.|[^"])*)", '
        r'bundle: bundle, locale: locale, comment: "((?:\\.|[^"])*)"\)', bundled
    )
    require(len(literal_rows) == 11, "literal localization row extraction differs")
    for key, encoded_value, encoded_comment in literal_rows:
        expected_value = json.loads('"' + encoded_value + '"')
        expected_comment = json.loads('"' + encoded_comment + '"')
        entry = strings[key]
        english = entry["localizations"]["en"]
        unit = english.get("stringUnit") or english.get("variations", {}).get("plural", {}).get("other", {}).get("stringUnit")
        require(unit.get("value") == expected_value and entry["comment"] == expected_comment,
                f"catalog literal value/comment parity differs: {key}")
    require("static let runtimeLanguage = \"en\"" in bundled and
            "static let appStorePrimaryMetadataLocale = \"en-US\"" in bundled and
            "runtimeDownloadsAllowed = false" in bundled, "shipping locale truth differs")
    require(all(key in bundled for key in contracts.PACKAGE_KEYS), "package keys missing from bundled registry")

    info_path = "FieldEvidenceApp/InfoPlist.xcstrings"
    current = (root / info_path).read_bytes()
    prior = git(root, "show", f"{contracts.APP_BASE_HEAD}:{info_path}")
    require(current == prior, "InfoPlist catalog changed despite read-only disposition")
    info = json.loads(current)
    require(info.get("sourceLanguage") == "en" and set(info.get("strings", {})) == {"NSCameraUsageDescription"},
            "InfoPlist catalog truth differs")


def swift_and_fixture_checks(root: Path) -> None:
    localization = source(root, contracts.PATH_FENCE[1])
    accessibility = source(root, contracts.PATH_FENCE[2])
    bundled = source(root, contracts.PATH_FENCE[3])
    package_registry = source(root, contracts.PATH_FENCE[15])
    mail = source(root, contracts.PATH_FENCE[17])
    test = source(root, contracts.SWIFT_TEST_PATH)
    ui_test = source(root, contracts.UI_TEST_PATH)
    required_localization = [
        "LocalizationKeyRegistryV1", "LocalizationCatalogReleaseV1",
        "PackageLocalizationReleaseBindingV1", "FrozenDisplaySnapshotV1",
        "static let persistent = false", "ZERO_OR_COMPLETE", "NOT_APPLICABLE",
    ]
    require(all(token in localization for token in required_localization), "localization contracts lack required structure")
    require("init(reportSnapshot: ReportSnapshotV1)" in bundled and
            "ReportSnapshotEncoderV1().encode(reportSnapshot)" in bundled,
            "frozen display is not integrated with canonical ReportSnapshot encoding")
    require(all(token in accessibility for token in ["AccessibilityContractV1", "SemanticAccessibilityIDRegistryV1",
                                                       "LegacyLocalizationAccessibilityAllowlistV1", "opaqueLowercaseHex"]),
            "accessibility contracts lack required structure")
    require("localization.definition(for: key).state == .active" in accessibility,
            "accessibility hint/value keys are not required active")
    require(all(token in bundled for token in ["beforeValidation", "afterValidationBeforePublication",
                                                "afterPublicationBeforeReceipt", "formattedInteger",
                                                "formattedLength", "formattedDate"]), "bundled lifecycle/formatting differs")
    require("guard legacy == requiredMailLegacy" in bundled,
            "first publication does not enforce the frozen legacy baseline")
    require("PackageLocalizationReleaseBindingV1" in package_registry and
            "shippingLocalizationSlotBindings" in package_registry, "package sidecar binding differs")
    require("ordered == expectedSlots" in localization,
            "package sidecar does not bind exact slot identity")
    runtime_ids = re.findall(r'accessibilityIdentifier\s*=\s*"([^"]+)"', mail)
    require(runtime_ids == contracts.LEGACY_MAIL_IDS, f"Mail legacy IDs changed or grew: {runtime_ids}")
    require(all(token in mail for token in ["BundledLocalizationCatalogV1.localized", "formattedInteger"]),
            "Mail composer localization adoption differs")
    require("s8.4.mail.new" not in mail, "Mail legacy allowlist grew")
    require("try!" not in localization + accessibility + bundled + package_registry + mail, "forced try introduced")

    fixture = load(root / contracts.FIXTURE_PATH)
    fixture_keys = [row["key"] for row in fixture["catalog"]["keys"]]
    require(sorted(fixture_keys) == contracts.CATALOG_KEYS and len(fixture_keys) == len(set(fixture_keys)),
            "fixture catalog parity differs")
    binding = fixture["packageBindings"]
    require(len(binding) == 1 and binding[0]["slotKeys"] == contracts.PACKAGE_KEYS,
            "fixture package key binding differs")
    require(binding[0]["catalogKeyDigest"] == contracts.sha256(contracts.canonical(contracts.CATALOG_KEYS)),
            "fixture catalog key digest differs")
    legacy = fixture["legacyAllowlist"]
    require(legacy["baseline"] == legacy["current"] == contracts.LEGACY_MAIL_IDS and
            legacy["newEntries"] == [] and legacy["growthAllowed"] is False,
            "legacy no-growth fixture differs")
    semantic = sorted(row["id"] for row in fixture["semanticAccessibility"]["entries"])
    require(semantic == contracts.SEMANTIC_MAIL_IDS, "semantic registry fixture differs")
    pseudo = sorted(row["locale"] for row in fixture["runtimeUI"]["pseudoLocales"])
    require(pseudo == contracts.PSEUDO_LOCALES and all(row["testOnly"] and not row["shipping"]
                                                       for row in fixture["runtimeUI"]["pseudoLocales"]),
            "pseudo locale fixture differs")
    frozen = fixture["frozenDisplay"]
    require(frozen["localeInvariant"] and frozen["historicOutputByteIdentical"] and
            frozen["canonicalIDsUnlocalized"], "frozen display fixture differs")

    unit_methods = re.findall(r"func (testV9_22[A-Za-z0-9_]+)\(", test)
    ui_methods = re.findall(r"func (testV23P03C16[A-Za-z0-9_]+)\(", ui_test)
    require(unit_methods == contracts.TEST_METHODS, f"unit selectors differ: {unit_methods}")
    require(ui_methods == contracts.UI_TEST_METHODS, f"UI selectors differ: {ui_methods}")
    require(ui_test.count("skipUntilPostS10Reconciliation") == 6 and "throw XCTSkip" in ui_test and
            "post-S10" in ui_test and "reservation" in ui_test, "UI deferral is not explicit/honest")
    require("testV9_11C16ShippingPackageLocalizationSlotsRemainBoundToCatalog" in
            source(root, contracts.PATH_FENCE[16]), "package regression selector missing")
    require("S3_3ReportSnapshotV1.json" in test and
            "FrozenDisplaySnapshotV1(reportSnapshot: historicReport)" in test,
            "R01 does not use an existing canonical report snapshot fixture")


def historic_immutability_checks(root: Path) -> None:
    for relative in [
        "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
        "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
        "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
        "FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift",
        "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift",
    ]:
        require((root / relative).read_bytes() == git(root, "show", f"{contracts.APP_BASE_HEAD}:{relative}"),
                f"canonical/historic owner changed outside C16: {relative}")


def generated_checks(root: Path) -> None:
    contract = load(root / contracts.CONTRACT_PATH)
    evidence = load(root / contracts.EVIDENCE_PATH)
    brand = load(root / contracts.BRAND_PATH)
    manifest = load(root / contracts.MANIFEST_PATH)
    for value in (contract, evidence, brand, manifest):
        require(value["artifactDigest"] == digest_without(value, "artifactDigest"),
                f"self digest differs: {value.get('schema')}")
        for key in ("nativeCompileRan", "hostedDispatchEnabled", "hostedDispatchRan",
                    "adoptionEnabled", "acceptanceEnabled", "implementationCredit",
                    "acceptanceCredit", "releaseCredit", "releaseReady",
                    "phase10PollingDuringParallelExecution"):
            require(value.get(key) is False, f"overclaim: {value.get('schema')}.{key}")
        require(value.get("requiresAcceptedS10_6Reconciliation") is True,
                f"reconciliation flag differs: {value.get('schema')}")
    require(contract["pathFence"] == contracts.PATH_FENCE and
            contract["localization"]["shippingRuntimeLocales"] == ["en"] and
            contract["localization"]["appStorePrimaryLocale"] == "en-US" and
            contract["localization"]["pseudoLocalesShipping"] is False and
            contract["accessibility"]["legacyAllowlistGrowthAllowed"] is False and
            contract["packageLocalization"]["packageSchemaChanged"] is False and
            contract["presentation"]["adoptedLiveCallSites"] == ["FEEDBACK_MAIL_ATTACHMENT_INTEGER"] and
            contract["presentation"]["dateAndMeasurementAdoption"] == "DECLARED_NOT_ADOPTED_NO_CREDIT_S10_RESERVED" and
            contract["presentation"]["historicReportDisplayRewritten"] is False,
            "generated contract semantics differ")
    require(evidence["result"] == "PASS_STATIC_PROVISIONAL" and evidence["pathFenceCount"] == 18 and
            evidence["catalogKeyCount"] == 11 and evidence["s10FenceOverlapPaths"] == [] and
            len(evidence["evidenceMatrix"]) == 5, "evidence receipt differs")
    require(brand["affectedSurfacePaths"] == ["FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift"] and
            brand["reservedAffectedConsumerDisposition"] == "DEFERRED_PENDING_S10_6_RECONCILIATION",
            "brand impact disposition differs")
    require(manifest["manifestInputCount"] == len(manifest["artifacts"]) == 17 and
            manifest["artifactSetDigest"] == contracts.sha256(contracts.canonical(manifest["artifacts"])) and
            {row["path"] for row in manifest["artifacts"]} == set(contracts.PATH_FENCE) - {contracts.MANIFEST_PATH},
            "tooling manifest closure differs")
    for row in manifest["artifacts"]:
        raw = (root / row["path"]).read_bytes()
        require(row["bytes"] == len(raw) and row["sha256"] == hashlib.sha256(raw).hexdigest(),
                f"manifest artifact differs: {row['path']}")


def verify(root: Path) -> dict[str, Any]:
    for relative in (contracts.PATH_FENCE[7], contracts.PATH_FENCE[8], contracts.PATH_FENCE[9]):
        ast.parse(source(root, relative), filename=relative)
    authority_checks(root)
    schema_checks(root)
    catalog_checks(root)
    swift_and_fixture_checks(root)
    historic_immutability_checks(root)
    generated_checks(root)
    require(not [path for path in root.rglob("*") if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo")],
            "Python cache leaked")
    return {
        "result": "PASS_STATIC_PROVISIONAL", "cardID": contracts.CARD, "verificationMode": "STATIC_ONLY",
        "pathFenceCount": 18, "existingPathCount": 3, "newPathCount": 15,
        "catalogKeyCount": 11, "semanticIDCount": 5, "legacyAllowlistCount": 5,
        "evidenceIDCount": 5, "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError,
            subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C16 static verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
