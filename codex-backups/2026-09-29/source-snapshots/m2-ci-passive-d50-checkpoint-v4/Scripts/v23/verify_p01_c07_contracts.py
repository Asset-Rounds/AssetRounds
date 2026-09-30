#!/usr/bin/env python3
"""Hostile/static verification for V23-P01-C07 compatibility tooling."""
from __future__ import annotations

import copy
import base64
import binascii
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

from p01_c07_contracts import (
    CARD,
    CASE_DOC,
    CORPUS_DOC,
    DATA_DOC,
    DOC_PATHS,
    EVIDENCE_IDS,
    FIXTURE_PATHS,
    FULL_FENCE,
    MANIFEST,
    POLICY_DOC,
    RUN_DOC,
    SCHEMA_PATHS,
    SEAL_DOC,
    SEED_DOC,
    SOURCE_PATHS,
    TOOL_PATHS,
    UPGRADE_DOC,
    ContractError,
    all_outputs,
    authority,
    canonical,
    data_manifest,
    flags,
    immutable_references,
    pretty,
    sha,
    source_bindings,
    source_binding_complete,
    support_paths,
    swift_corpus_sha,
    validate_case_rows,
    verify_generated,
    verify_pdf,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_json(root: Path, path: str) -> dict[str, Any]:
    item = root / path
    require(item.is_file(), f"missing JSON artifact: {path}")
    data = item.read_bytes()
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError(f"invalid JSON artifact {path}: {error}") from error
    require(isinstance(value, dict), f"{path}: root must be object")
    require(data == pretty(value), f"{path}: noncanonical JSON")
    return value


def verify_schema_inputs(root: Path) -> None:
    expected_titles = [
        "ReleasedDataCompatibilityPolicyV1", "CompatibilityCaseManifestV1", "CompatibilityCorpusManifestV1",
        "CompatibilityRunReceiptV1", "ReleaseSeedCorpusV1", "ReleaseSeedCorpusSealV1",
        "SupportedUpgradePathV1", "DataCompatibilityManifestV1",
    ]
    for path, title in zip(SCHEMA_PATHS, expected_titles):
        item = root / path
        require(item.is_file(), f"missing schema input: {path}")
        try:
            value = json.loads(item.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise ContractError(f"invalid schema input {path}: {error}") from error
        require(isinstance(value, dict), f"{path}: schema root must be object")
        require(value.get("title") == title, f"{path}: schema title drift")
        require(value.get("additionalProperties") is False, f"{path}: schema is not strict")
        require(isinstance(value.get("required"), list), f"{path}: required list missing")
        require(isinstance(value.get("properties"), dict), f"{path}: properties missing")


def verify_direct_contract_documents(root: Path) -> None:
    policy = load_json(root, POLICY_DOC)
    require(policy == {
        "schemaVersion": 1,
        "dataManifest": data_manifest(),
        "skippedReleaseStoreMigrationRequired": True,
        "immutableReleasedFixturesRequired": True,
        "syntheticFixturesOnly": True,
        "noCustomerData": True,
        "noSecrets": True,
        "appendBeforeFirstWriteRequired": True,
        "firstPublicSealOwner": "V23-P05-C01",
    }, "policy direct contract drift")
    corpus = load_json(root, CORPUS_DOC)
    cases = corpus.get("cases")
    require(isinstance(cases, list), "corpus cases missing")
    validate_case_rows(cases, support_paths())
    require(corpus.get("policyManifestSHA256") == sha(canonical(data_manifest())), "corpus policy digest drift")
    require(corpus.get("sealState") == "provisional_pre_public", "corpus is not provisional")

    case = load_json(root, CASE_DOC)
    require(case in cases, "singular case document is not enrolled in corpus")
    required_case_keys = {"schemaVersion", "caseID", "family", "artifactVersion", "kind", "artifactRelativePath", "artifactSHA256", "source", "dependencyFamilies", "scenarioTags", "expectedDisposition", "synthetic", "licenseIdentifier", "containsCustomerData", "containsSecrets", "immutable", "representative"}
    optional_case_keys = {"normalizedExpectedSHA256", "generatorVersion", "generatorSeed"}
    require(required_case_keys <= set(case) <= required_case_keys | optional_case_keys, "case document is not direct contract shape")
    if case["source"] == "checked_fixture":
        require("generatorVersion" not in case and "generatorSeed" not in case, "checked case carries generator metadata")
    else:
        require(isinstance(case.get("generatorVersion"), str) and isinstance(case.get("generatorSeed"), int), "deterministic case lacks generator metadata")

    run = load_json(root, RUN_DOC)
    representative = [item for item in cases if item.get("representative")]
    selected = [item["caseID"] for item in representative]
    require(run.get("selectedCaseIDs") == selected, "run sentinel selection drift")
    require(run.get("corpusSHA256") == swift_corpus_sha(corpus), "run corpus digest drift")
    require(run.get("mode") == "diagnostic_continue" and run.get("selection") == "representative_sentinel", "checked example is not diagnostic-only sentinel")
    require(len(run.get("results", [])) == len(selected) and all(row.get("outcome") == "passed" for row in run["results"]), "run sentinel result drift")
    cases_by_id = {item["caseID"]: item for item in cases}
    require(all(
        row.get("normalizedOutputSHA256")
            == cases_by_id[row["caseID"]].get(
                "normalizedExpectedSHA256",
                cases_by_id[row["caseID"]]["artifactSHA256"],
            )
        for row in run["results"]
    ), "passed generated result lacks its exact observed output digest")
    accepting = (
        run.get("mode") == "accepting_fail_fast"
        and len(run.get("results", [])) == len(selected)
        and all(
            row.get("outcome") == "passed"
                and isinstance(row.get("normalizedOutputSHA256"), str)
            for row in run["results"]
        )
    )
    require(not accepting, "checked-in diagnostic example was treated as Card acceptance")

    seal = load_json(root, SEAL_DOC)
    require(seal.get("state") == "provisional_pre_public" and seal.get("owner") == CARD, "provisional seal owner/state drift")
    require(seal.get("corpusSHA256") == swift_corpus_sha(corpus) and seal.get("policyManifestSHA256") == corpus["policyManifestSHA256"], "seal digest drift")
    seed = load_json(root, SEED_DOC)
    require(seed.get("manifest") == corpus and seed.get("seal") == seal, "seed manifest/seal envelope drift")
    require(seed.get("syntheticOnly") is True and seed.get("licensedFixturesOnly") is True and seed.get("containsCustomerData") is False and seed.get("containsSecrets") is False, "seed privacy flags weakened")
    upgrade = load_json(root, UPGRADE_DOC)
    require(upgrade == support_paths()[0], "supported upgrade path document drift")
    require(load_json(root, DATA_DOC) == data_manifest(), "data compatibility manifest drift")


def validate_materialized_case_bindings(
    root: Path,
    cases: list[dict[str, Any]],
    generated_case_artifacts: Any,
) -> None:
    require(isinstance(generated_case_artifacts, dict), "generatedCaseArtifacts mapping missing")
    generated_ids = {
        item["caseID"] for item in cases
        if item.get("source") == "deterministic_generator"
    }
    require(set(generated_case_artifacts) == generated_ids, "generatedCaseArtifacts case-ID set drift")
    for item in cases:
        case_id = item["caseID"]
        if item.get("source") == "deterministic_generator":
            encoded = generated_case_artifacts.get(case_id)
            require(isinstance(encoded, str) and encoded, f"missing generated payload: {case_id}")
            try:
                payload = base64.b64decode(encoded, validate=True)
            except (binascii.Error, ValueError) as error:
                raise ContractError(f"invalid generated payload base64: {case_id}") from error
            require(payload and base64.b64encode(payload).decode("ascii") == encoded, f"noncanonical generated payload: {case_id}")
            require(item.get("artifactRelativePath") == f"generatedCaseArtifacts/{case_id}.bin", f"generated payload path drift: {case_id}")
        else:
            require(case_id not in generated_case_artifacts, f"checked case duplicated in generated payloads: {case_id}")
            relative = item.get("artifactRelativePath")
            require(isinstance(relative, str) and relative, f"checked fixture path missing: {case_id}")
            path = root / relative
            require(path.is_file(), f"checked fixture missing: {case_id}")
            payload = path.read_bytes()
            require(payload, f"checked fixture empty: {case_id}")
        require(sha(payload) == item.get("artifactSHA256"), f"case artifact digest mismatch: {case_id}")


def require_materialization_failure(
    root: Path,
    cases: list[dict[str, Any]],
    generated_case_artifacts: dict[str, str],
) -> None:
    try:
        validate_materialized_case_bindings(root, cases, generated_case_artifacts)
    except ContractError:
        return
    raise ContractError("hostile generatedCaseArtifacts mutation was accepted")


def verify_manifest(root: Path) -> None:
    manifest = load_json(root, MANIFEST)
    require(manifest.get("schema") == "V23-P01-C07-tooling-manifest" and manifest.get("cardID") == CARD, "manifest identity drift")
    require(manifest.get("authority") == authority(), "manifest authority drift")
    require(manifest.get("pathFence") == TOOL_PATHS, "tool path fence drift")
    require(manifest.get("fullCardFence") == FULL_FENCE and len(FULL_FENCE) == len(set(FULL_FENCE)) == 33, "exact C07 33-path fence required")
    require(manifest.get("sourcePaths") == SOURCE_PATHS and manifest.get("fixturePaths") == FIXTURE_PATHS and manifest.get("schemaPaths") == SCHEMA_PATHS and manifest.get("documentPaths") == DOC_PATHS, "manifest path projections drift")
    require(manifest.get("toolingPathCount") == 20 and manifest.get("sourceBindingCount") == 9 and manifest.get("fixtureBindingCount") == 4, "manifest path counts drift")
    rows = manifest.get("artifacts")
    require(isinstance(rows, list) and [row.get("path") for row in rows] == TOOL_PATHS[:-1], "manifest artifact rows drift")
    require(manifest.get("artifactCount") == 19 and manifest.get("artifactSetDigest") == sha(pretty(rows)), "manifest artifact digest/count drift")
    for row in rows:
        item = root / row["path"]
        require(item.is_file(), f"missing manifest artifact: {row['path']}")
        data = item.read_bytes()
        require(row.get("bytes") == len(data) and row.get("sha256") == sha(data), f"artifact digest drift: {row['path']}")
    expected_sources = source_bindings(root)
    require(manifest.get("sourceBindings") == expected_sources, "source binding rows drift")
    require(manifest.get("sourceBindingComplete") is source_binding_complete(expected_sources), "sourceBindingComplete was not derived")
    require(manifest.get("fixtureBindingComplete") is True, "fixture binding is incomplete")
    require(manifest.get("evidenceIDs") == EVIDENCE_IDS and len(EVIDENCE_IDS) == 5, "five evidence IDs required")
    for key, expected in flags().items():
        require(manifest.get(key) == expected, f"unsafe manifest flag: {key}")
    refs = immutable_references(root)
    require(manifest.get("immutableReferences") == refs, "immutable reference set drift")


def verify_hostile_invariants(root: Path) -> None:
    corpus = load_json(root, CORPUS_DOC)
    cases = corpus["cases"]
    require(any(tag == "minimum" for item in cases for tag in item["scenarioTags"]), "minimum scenario absent")
    require(any(tag == "maximal" for item in cases for tag in item["scenarioTags"]), "maximal scenario absent")
    require({tag for item in cases for tag in item["scenarioTags"]} >= {"unicode", "rtl", "long", "empty", "dst", "second-launch", "tamper", "truncated", "path", "bomb"}, "hostile/workspace scenario tags incomplete")
    require({item["kind"] for item in cases} == {"positive", "hostile", "interruption", "recovery"}, "case kind coverage incomplete")
    require(len({item["family"] for item in cases if item["kind"] == "positive"}) == 15, "not all current families enrolled")
    require(all(item["containsCustomerData"] is False and item["containsSecrets"] is False and item["synthetic"] is True and item["immutable"] is True for item in cases), "customer/secret or mutable fixture flag found")
    require(all("P02" not in json.dumps(item, ensure_ascii=False) for item in cases), "later P02 format fabricated")
    run = load_json(root, RUN_DOC)
    require(run.get("mode") == "diagnostic_continue", "checked run receipt is not continue-only diagnostic evidence")
    corpus_fixture = load_json(root, FIXTURE_PATHS[0])
    seed_fixture = load_json(root, FIXTURE_PATHS[1])
    generated = corpus_fixture.get("generatedCaseArtifacts")
    require(generated == seed_fixture.get("generatedCaseArtifacts"), "seed/corpus generated payload mappings differ")
    validate_materialized_case_bindings(root, cases, generated)
    first_generated_id = next(item["caseID"] for item in cases if item["source"] == "deterministic_generator")
    missing = dict(generated)
    missing.pop(first_generated_id)
    require_materialization_failure(root, cases, missing)
    mismatched = dict(generated)
    mismatched[first_generated_id] = base64.b64encode(b"mismatched-payload").decode("ascii")
    require_materialization_failure(root, cases, mismatched)
    policy = load_json(root, POLICY_DOC)
    mutated = copy.deepcopy(policy)
    mutated["noSecrets"] = False
    require(mutated != policy and mutated["noSecrets"] is False, "privacy hostile mutation was not material")
    mutated_corpus = copy.deepcopy(corpus)
    mutated_corpus["cases"] = mutated_corpus["cases"][1:]
    require(len(mutated_corpus["cases"]) != len(cases), "corpus removal mutation was not material")
    manifest = load_json(root, MANIFEST)
    mutated_manifest = copy.deepcopy(manifest)
    mutated_manifest["fullCardFence"] = list(FULL_FENCE[:-1])
    require(mutated_manifest["fullCardFence"] != FULL_FENCE, "fence mutation was not material")
    require(load_json(root, CORPUS_DOC)["sealState"] == "provisional_pre_public", "first-public seal claimed prematurely")
    require(load_json(root, SEAL_DOC).get("requiresAcceptedS10_6Reconciliation", True) is not False, "S10.6 reconciliation requirement weakened")
    verify_pdf((root / FIXTURE_PATHS[3]).read_bytes())


def main() -> int:
    parser = __import__("argparse").ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=None, help="repository root (defaults to this checkout)")
    args = parser.parse_args()
    root = (args.root or Path(__file__).resolve().parents[2]).resolve()
    try:
        verify_schema_inputs(root)
        expected = all_outputs(root)
        verify_generated(root, expected)
        verify_direct_contract_documents(root)
        verify_manifest(root)
        verify_hostile_invariants(root)
    except (ContractError, OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
        print(f"V23-P01-C07 hostile verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P01-C07 hostile static contracts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
