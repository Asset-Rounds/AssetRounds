#!/usr/bin/env python3
"""Verify V23-P00-C10 architecture contracts and hostile cases."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

from c07_contracts import sha256_bytes
from c10_contracts import (
    ARTIFACT_PATHS,
    BASE_HEAD,
    CARD_ID,
    COORDINATOR_CONTRACT_PATH,
    COORDINATOR_PATH,
    EXTRACTED_SYMBOLS,
    FENCED_PATHS,
    MANIFEST_PATH,
    ROOT_PATH,
    SCHEMA_PATHS,
    ContractError,
    build_manifest,
    build_outputs,
    pretty_bytes,
    top_level_symbols,
    validate_swift_delta,
)
from verify_c07_contracts import validate_schema, verify_digest


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def expect_failure(callable_value) -> None:
    try:
        callable_value()
    except (ContractError, ValueError):
        return
    raise ContractError("hostile C10 case did not fail")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    expected = build_outputs(root)
    checks = 0
    for relative, value in expected.items():
        if not (root / relative).is_file() or (root / relative).read_bytes() != pretty_bytes(value):
            raise ContractError(f"generated C10 output differs: {relative}")
        checks += 1
    for index, schema_path in enumerate(SCHEMA_PATHS):
        schema = load(root / schema_path)
        artifact = load(root / ARTIFACT_PATHS[index])
        validate_schema(artifact, schema)
        verify_digest(artifact)
        checks += 2

    root_artifact = load(root / ARTIFACT_PATHS[0])
    ports = load(root / ARTIFACT_PATHS[1])
    fitness = load(root / ARTIFACT_PATHS[2])
    boundary = load(root / ARTIFACT_PATHS[3])
    debt = load(root / ARTIFACT_PATHS[4])
    coordinator = load(root / ARTIFACT_PATHS[5])
    if root_artifact["rootDeclarationCount"] != 1 or len(root_artifact["constructedSymbols"]) != 7:
        raise ContractError("composition-root topology differs")
    if root_artifact["installationStatus"] != "ROOT_IMPLEMENTED_WIRING_DEFERRED_RESERVED_APP_AND_FEATURE_ROOTS":
        raise ContractError("composition-root installation is not fail-closed")
    checks += 2
    if [row["port"] for row in ports["ports"]] != ["ApplicationClock", "ApplicationIDSource"]:
        raise ContractError("runtime port order differs")
    if {row["adapter"] for row in ports["platformAdapters"]} != {"SystemApplicationClock", "SystemApplicationIDSource"}:
        raise ContractError("runtime adapter registry differs")
    checks += 2
    if boundary["boundarySatisfied"] or not boundary["featureConstructionFindings"] or not boundary["modelContextReferenceFindings"]:
        raise ContractError("architecture boundary manifest is not honest about baseline debt")
    if boundary["physicalTargetExtractionDisposition"] != "DEFERRED_NO_MEASURED_BUILD_BENEFIT":
        raise ContractError("physical target extraction disposition differs")
    checks += 2
    if debt["newForbiddenDebtCount"] != 0 or not debt["debtBaselineSatisfied"]:
        raise ContractError("C10 introduced forbidden architecture debt")
    if not debt["hotspots"] or debt["hotspots"][0]["lineCount"] < 1000:
        raise ContractError("architecture hotspot inventory is incomplete")
    checks += 2
    if coordinator["extractedSymbols"] != EXTRACTED_SYMBOLS or not coordinator["structuralExtractionSatisfied"]:
        raise ContractError("coordinator extraction receipt differs")
    if coordinator["currentCoordinatorLineCount"] >= coordinator["baseCoordinatorLineCount"]:
        raise ContractError("coordinator contract extraction did not reduce hotspot size")
    validate_swift_delta(root)
    checks += 3
    root_source = (root / ROOT_PATH).read_text(encoding="utf-8")
    if "static let shared" in root_source or "ServiceLocator" in root_source or root_source.count("ProductionCompositionRoot") != 1:
        raise ContractError("composition root contains singleton/service-locator pattern or duplicate reference")
    if "ProcessInfo" in root_source or "@unchecked Sendable" in root_source or "Task.detached" in root_source:
        raise ContractError("composition root contains forbidden debt")
    checks += 2
    contract_symbols = top_level_symbols((root / COORDINATOR_CONTRACT_PATH).read_text(encoding="utf-8"))
    coordinator_symbols = top_level_symbols((root / COORDINATOR_PATH).read_text(encoding="utf-8"))
    if contract_symbols != EXTRACTED_SYMBOLS or set(contract_symbols) & set(coordinator_symbols):
        raise ContractError("coordinator symbols are missing, reordered, or duplicated")
    checks += 1
    if fitness["staticVerificationStatus"] != "PASS" or fitness["nativeCompileStatus"] != "NOT_RUN_HOSTED_DISPATCH_DISABLED":
        raise ContractError("architecture fitness receipt overclaims verification")
    if any(fitness[key] != value["artifactDigest"] for key, value in (
        ("compositionRootDigest", root_artifact),
        ("portRegistryDigest", ports),
        ("boundaryManifestDigest", boundary),
        ("debtLedgerDigest", debt),
        ("coordinatorReceiptDigest", coordinator),
    )):
        raise ContractError("architecture fitness cross-artifact digest differs")
    checks += 2
    authorities = [load(root / path)["authority"] for path in ARTIFACT_PATHS]
    if any(value != authorities[0] for value in authorities[1:]):
        raise ContractError("C10 cross-artifact authority differs")
    if any(authorities[0][key] for key in ("phase10PollingDuringParallelExecution", "acceptanceEnabled", "hostedDispatchEnabled", "adoptionEnabled", "releaseCredit")):
        raise ContractError("C10 provisional authority enabled forbidden capability")
    checks += 2
    for schema_path, artifact_path in zip(SCHEMA_PATHS, ARTIFACT_PATHS):
        schema = load(root / schema_path)
        artifact = load(root / artifact_path)
        unknown = copy.deepcopy(artifact)
        unknown["unknown"] = True
        expect_failure(lambda value=unknown, contract=schema: validate_schema(value, contract))
        corrupt = copy.deepcopy(artifact)
        corrupt["cardID"] = "V23-P00-C99"
        expect_failure(lambda value=corrupt, contract=schema: validate_schema(value, contract))
        checks += 2
    manifest = load(root / MANIFEST_PATH)
    if manifest != build_manifest(root):
        raise ContractError("C10 manifest differs")
    verify_digest(manifest)
    paths = [row["path"] for row in manifest["artifacts"]]
    if paths != [path for path in FENCED_PATHS if path != MANIFEST_PATH] or len(paths) != len(set(paths)):
        raise ContractError("C10 manifest path fence differs")
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"C10 manifest hash differs: {row['path']}")
    checks += 3
    completed = subprocess.run(
        [sys.executable, "-B", str(root / "Scripts/v23/generate_c10_contracts.py"), "--check", "--root", str(root)],
        check=True,
        capture_output=True,
        text=True,
    )
    if "PASS V23-P00-C10" not in completed.stdout:
        raise ContractError("C10 deterministic generator check failed")
    checks += 1
    print(json.dumps({
        "result": "PASS", "cardID": CARD_ID, "checks": checks,
        "compositionRootCount": root_artifact["rootDeclarationCount"], "runtimePortCount": len(ports["ports"]),
        "featureConstructionFindingCount": len(boundary["featureConstructionFindings"]),
        "modelContextReferenceFindingCount": len(boundary["modelContextReferenceFindings"]),
        "extractedSymbolCount": len(coordinator["extractedSymbols"]), "nativeCompileRan": False,
        "phase10PollingDuringParallelExecution": False, "acceptanceCredit": False, "releaseCredit": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
