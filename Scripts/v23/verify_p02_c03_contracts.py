#!/usr/bin/env python3
"""Hostile static verifier for V23-P02-C03."""
from __future__ import annotations

import ast
import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

from p02_c03_contracts import (
    CARD, CLASSIFICATIONS, CONFLICT_DOC, CONFLICT_RULES, CONFLICT_SCHEMA,
    CONTRACT_SCRIPT, CORPUS_DOC, CORPUS_SCHEMA, EVIDENCE_IDS, GENERATED_PATHS,
    MANIFEST, MANIFEST_INPUT_PATHS, OWNED_FILE_KINDS, PATH_FENCE,
    OWNED_FILE_GROUPS, PERSISTENT_MODEL_GROUPS, PERSISTENT_MODELS, POLICY_AXES, POLICY_DOC, POLICY_SCHEMA, REGISTRY_DOC,
    REGISTRY_SCHEMA, SOURCE_PATHS, TEST_METHODS, TOOL_PATHS, all_outputs,
    authority, canonical, pretty, sha,
)

ROOT = Path(__file__).resolve().parents[2]
TEST_PATH = ROOT / SOURCE_PATHS[-2]
FIXTURE_PATH = ROOT / SOURCE_PATHS[-1]


class VerificationError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def load(relative: str) -> Any:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def verify_seal(document: dict[str, Any], name: str) -> None:
    require(set(document).issuperset({"schema", "schemaVersion", "artifactDigest"}), f"{name}: missing seal fields")
    digest = document["artifactDigest"]
    unsealed = dict(document); del unsealed["artifactDigest"]
    require(digest == sha(pretty(unsealed)), f"{name}: artifactDigest mismatch")


def verify_flags(document: dict[str, Any], name: str) -> None:
    false_keys = ["nativeCompileRan", "hostedDispatchRan", "physicalEvidenceComplete", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit", "phase10PollingDuringParallelExecution"]
    for key in false_keys:
        require(document.get(key) is False, f"{name}: false-credit flag {key}")
    require(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{name}: missing S10.6 gate")
    require(document.get("provisional") is True, f"{name}: not provisional")


def validate_instance(instance: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        require(instance == schema["const"], f"{path}: const mismatch")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(instance, dict), f"{path}: expected object")
        required = schema.get("required", [])
        require(set(required).issubset(instance), f"{path}: missing required property")
        if schema.get("additionalProperties") is False:
            require(set(instance).issubset(schema.get("properties", {})), f"{path}: additional property")
        for key, subschema in schema.get("properties", {}).items():
            if key in instance:
                validate_instance(instance[key], subschema, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(instance, list), f"{path}: expected array")
        require(len(instance) >= schema.get("minItems", 0), f"{path}: too few items")
        require(len(instance) <= schema.get("maxItems", len(instance)), f"{path}: too many items")
        prefixes = schema.get("prefixItems", [])
        for index, subschema in enumerate(prefixes):
            validate_instance(instance[index], subschema, f"{path}[{index}]")
        require(not (schema.get("items") is False and len(instance) > len(prefixes)), f"{path}: additional item")
    elif kind == "string":
        require(isinstance(instance, str), f"{path}: expected string")
        if schema.get("pattern") == "^[0-9a-f]{64}$":
            require(len(instance) == 64 and all(ch in "0123456789abcdef" for ch in instance), f"{path}: invalid digest")


def verify_generated() -> dict[str, bytes]:
    expected = all_outputs(ROOT)
    require(list(expected) == GENERATED_PATHS, "generated path order mismatch")
    for relative, data in expected.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated artifact: {relative}")
        require(path.read_bytes() == data, f"stale generated artifact: {relative}")
        if relative.endswith(".json"):
            value = load(relative)
            require(path.read_bytes() == pretty(value), f"{relative}: noncanonical pretty JSON")
    return expected


def verify_contracts() -> None:
    docs = {name: load(name) for name in (REGISTRY_DOC, POLICY_DOC, CONFLICT_DOC, CORPUS_DOC)}
    for name, document in docs.items():
        verify_seal(document, name); verify_flags(document, name)
        require(document["authority"] == authority(), f"{name}: authority mismatch")
        require(document["evidenceIDs"] == EVIDENCE_IDS, f"{name}: evidence mismatch")
    registry = docs[REGISTRY_DOC]
    require(registry["classifications"] == CLASSIFICATIONS and len(set(CLASSIFICATIONS)) == 5, "classification closure mismatch")
    completeness = registry["completeness"]
    require(completeness["registrationCount"] == 43, "43-registration inventory mismatch")
    require(completeness["persistentModels"] == PERSISTENT_MODELS and completeness["persistentModelCount"] == 13, "13-model inventory mismatch")
    require(completeness["ownedFileKinds"] == OWNED_FILE_KINDS and completeness["ownedFileKindCount"] == 20, "20-file-kind inventory mismatch")
    model_union = [name for group in PERSISTENT_MODEL_GROUPS.values() for name in group]
    file_union = [name for group in OWNED_FILE_GROUPS.values() for name in group]
    require(len(model_union) == len(set(model_union)) == 13 and sorted(model_union) == sorted(PERSISTENT_MODELS), "persistent-model named groups not exact/disjoint")
    require(len(file_union) == len(set(file_union)) == 20 and sorted(file_union) == sorted(OWNED_FILE_KINDS), "owned-file named groups not exact/disjoint")
    require(completeness["persistentModelNamedGroups"] == PERSISTENT_MODEL_GROUPS and completeness["ownedFileKindNamedGroups"] == OWNED_FILE_GROUPS, "generated named groups mismatch")
    require(completeness["unmatchedDeclaredModelOrFileKind"] == "FAIL_CLOSED_INCOMPLETE_INVENTORY", "unknown declared name not fail-closed")
    require(completeness["secretKinds"] == [] and registry["currentCatalog"]["searchImplementationPresent"] is False, "truthful absence mismatch")
    require(registry["currentCatalog"]["registrationCount"] == 84, "84-subject current catalog mismatch")
    require(registry["currentCatalog"]["classificationCounts"] == {"CONTENT_BLOB": 4, "DERIVED_REBUILDABLE": 26, "LOCAL_ONLY": 32, "PRIVATE_DEVICE_ONLY": 8, "REPLICATED": 14}, "current catalog classification counts mismatch")
    policy = docs[POLICY_DOC]
    require(policy["policyAxes"] == POLICY_AXES and policy["policyAxisCount"] == 14, "policy axes mismatch")
    require([row["classification"] for row in policy["classificationMatrix"]] == CLASSIFICATIONS, "policy matrix incomplete")
    require("backupExport" not in canonical(policy).decode("utf-8"), "collapsed backup/export pseudo-axis present")
    for row in policy["classificationMatrix"]:
        require(set(row) == {"classification", "transport", "filesystemBackup", "semanticBackup", "portableExport", "delete", "erase"}, "lifecycle matrix axes incomplete")
    require("PORTABLE_CANONICAL" in policy["classificationMatrix"][1]["portableExport"], "reviewed local diagnostic export missing")
    require("PORTABLE_CANONICAL" in policy["classificationMatrix"][2]["portableExport"], "portable derived projections missing")
    lifecycle_binding = policy["lifecycleAxisBinding"]
    require(lifecycle_binding["axesAreIndependent"] is True and lifecycle_binding["portableDerivedProfile"] == "portableProjection" and lifecycle_binding["portableLocalProfile"] == "reviewedDiagnosticExport", "independent lifecycle binding mismatch")
    require("MutationHistoryQuarantineRecordV1" in lifecycle_binding["replicatedImmutableHistorySubjects"], "quarantine immutable-history profile missing")
    require(policy["networkTransportImplemented"] is False and policy["validation"]["portableSecretsAllowed"] is False, "transport/privacy leak")
    require(policy["closedDomains"]["authority"] == ["WORKSPACE_WRITER", "IMMUTABLE_CONTENT_WRITER", "LOCAL_DEVICE", "DERIVED_FROM_CANONICAL_INPUTS"], "provider-free authority domain mismatch")
    require(policy["closedDomains"]["retention"] == ["UNTIL_CANONICAL_DELETE_OR_ERASE", "IMMUTABLE_HISTORY_UNTIL_ERASE", "REBUILDABLE", "OPERATION_SCOPED", "LOCAL_DEVICE_RETAINED"], "provider-free retention domain mismatch")
    require(policy["validation"]["providerAuthorityOrRetentionExposedAtThisHead"] is False and policy["validation"]["providerAuthorityOrRetentionInput"] == "FAIL_CLOSED_AS_UNKNOWN_ENUM_VALUE", "provider hostile guarantee missing")
    secret = policy["validation"]["secretNeverPortable"]
    require(secret == {"privacy": "SECRET_NEVER_PORTABLE", "authority": "LOCAL_DEVICE", "transport": "EXCLUDED", "bootstrap": ["DESTINATION_LOCAL", "EXCLUDED"], "semanticBackup": "EXCLUDE", "portableExport": "EXCLUDE", "delete": "LOCAL_AUTHORITY", "erase": "LOCAL_AUTHORITY", "violation": "FAIL_CLOSED_INVALID_POLICY"}, "secret portability contract mismatch")
    diagnostic = policy["validation"]["reviewedDiagnosticExportException"]
    require(diagnostic["privacy"] == "NONCUSTOMER_DIAGNOSTIC" and diagnostic["portableExport"] == "PORTABLE_CANONICAL" and diagnostic["mayApplyToSecret"] is False, "reviewed diagnostic exception leaked to secrets")
    for document in docs.values():
        encoded = canonical(document).decode("utf-8")
        require("EXTERNAL_PROVIDER" not in encoded and "PROVIDER_CONTROLLED_CACHE" not in encoded, "provider enum leaked into formal artifact")
    conflict = docs[CONFLICT_DOC]
    require(conflict["conflictRules"] == CONFLICT_RULES and conflict["conflictRuleCount"] == 6, "conflict registry mismatch")
    identity = conflict["conflictIdentity"]
    require(identity["permutationInvariant"] is True and identity["twoAndThreeWayPermutationsRequired"] is True, "permutation contract missing")
    require(set(identity["excludes"]) == {"destinationReceiptID", "arrivalOrder", "journalPosition", "wallClock", "replicaLocalSequence"}, "order-independent exclusions mismatch")
    basis = conflict["resolutionBasis"]
    require(basis["namedMissingInputDisposition"] == "DEFER_WITH_EXACT_SORTED_MISSING_INPUTS", "missing-input deferral absent")
    require(basis["lateCompetitorDisposition"] == "CREATE_DETERMINISTIC_SUCCESSOR_IDENTITY" and basis["priorBasisImmutable"] is True, "frozen successor contract absent")
    corpus = docs[CORPUS_DOC]
    require([row["testMethod"] for row in corpus["evidence"]] == TEST_METHODS, "test mapping mismatch")
    require(corpus["exactFiveTestMethods"] is True and corpus["hostileFailClosed"] is True, "corpus gates missing")
    for doc_path, schema_path in ((REGISTRY_DOC, REGISTRY_SCHEMA), (POLICY_DOC, POLICY_SCHEMA), (CONFLICT_DOC, CONFLICT_SCHEMA), (CORPUS_DOC, CORPUS_SCHEMA)):
        validate_instance(docs[doc_path], load(schema_path))


def verify_manifest() -> None:
    manifest = load(MANIFEST); verify_seal(manifest, MANIFEST); verify_flags(manifest, MANIFEST)
    require(manifest["authority"] == authority(), "manifest authority mismatch")
    require(manifest["pathFence"] == PATH_FENCE and manifest["pathFenceCount"] == 58, "exact 58-path fence mismatch")
    require(manifest["sourcePaths"] == SOURCE_PATHS and manifest["sourcePathCount"] == 46, "exact 46-source closure mismatch")
    require(manifest["toolingPaths"] == TOOL_PATHS and manifest["toolingPathCount"] == 12, "exact 12-tool closure mismatch")
    require(manifest["generatedPaths"] == GENERATED_PATHS, "generated path closure mismatch")
    require(manifest["artifactCount"] == 57 and [row["path"] for row in manifest["artifacts"]] == MANIFEST_INPUT_PATHS, "exact 57-input closure mismatch")
    require(manifest["artifactSetDigest"] == sha(pretty(manifest["artifacts"])), "artifact set digest mismatch")
    for row in manifest["artifacts"]:
        data = (ROOT / row["path"]).read_bytes()
        require(row["bytes"] == len(data) and row["sha256"] == sha(data), f"manifest binding mismatch: {row['path']}")


def require_tokens(relative: str, tokens: list[str]) -> None:
    text = (ROOT / relative).read_text(encoding="utf-8")
    for token in tokens:
        require(token in text, f"{relative}: missing source token {token!r}")


def verify_sources() -> None:
    require_tokens(SOURCE_PATHS[40], ["enum SyncClassificationV1", "case replicated = \"REPLICATED\"", "case localOnly = \"LOCAL_ONLY\"", "case derivedRebuildable = \"DERIVED_REBUILDABLE\"", "case contentBlob = \"CONTENT_BLOB\"", "case privateDeviceOnly = \"PRIVATE_DEVICE_ONLY\"", "schemaID = \"SYNC_REPLICATION_CONFLICT_POLICY_V1\"", "static var registrations", "static func registration(", "static func validate()", "persistentModelNames", "ownedFileClassNames"])
    registry_source = (ROOT / SOURCE_PATHS[40]).read_text(encoding="utf-8")
    mapping = registry_source.split("private static func makeRegistrations()", 1)[1].split("private static func registration(", 1)[0]
    require(mapping.count("default:") == 2, "registry mapping must have exactly two exhaustive rejection defaults")
    require(len(re.findall(r"default:\s*throw SyncClassificationRegistryFailureV1\.incompleteInventory", mapping)) == 2, "registry mapping default is permissive")
    require("default: classification" not in mapping and "default: return" not in mapping, "permissive registry default mapping present")
    for name in PERSISTENT_MODELS + OWNED_FILE_KINDS:
        require(f'\"{name}\"' in mapping, f"registry named group missing declared name: {name}")
    require_tokens(SOURCE_PATHS[41], ["struct ReplicationPolicyV1", "let authority:", "let persistence:", "let transport:", "let bootstrap:", "let privacy:", "let retention:", "let codec:", "let sizeLimit:", "let dependencies:", "let backup:", "let export:", "let deletion:", "let erase:", "func validate()", "func canonicalData()", "func canonicalSHA256()", "decodeCanonical", "privacy == .secretNeverPortable", "ReplicationPolicyFailureV1.secretPortabilityEnabled"])
    require_tokens(SOURCE_PATHS[42], ["enum ConflictRuleV1", "case immutableVersion = \"IMMUTABLE_VERSION\"", "case stableIDAppendUnion = \"STABLE_ID_APPEND_UNION\"", "case exactRevisionManual = \"EXACT_REVISION_MANUAL\"", "case deleteWins = \"DELETE_WINS\"", "case derivedRebuild = \"DERIVED_REBUILD\"", "case localOnly = \"LOCAL_ONLY\"", "struct ConflictIdentityV1", "static func derive(", "struct ConflictResolutionBasisV1", "func readiness(", "func successor(adding", "decodeCanonical"])
    require_tokens(SOURCE_PATHS[43], ["CurrentSyncClassificationCatalogV1", "static var current", "func validate()", "portableContentProjectionNames", "derivedIndexNames", "derivedProjectionNames", "journalRecoveryNames", "diagnosticNames", "secretNames: [String] = []", "declaredSearchImplementationPresent = false", "declaredKeychainUsage = false", "keychainUsageDeclared", "searchImplementationPresent", "semanticBackup", "portableExport", "filesystemBackup", "rebuild", "replay", "PersistentSchemaV4.models", "OwnedFileKindV1.allCases", "MutationHistoryQuarantineRecordV1", ".replicatedMutationHistory", "let runtimeNames = PersistentSchemaV4.models.map", "String(describing: modelType)", "runtimeNames == persistentModelNames", "ObjectIdentifier"])
    test_text = TEST_PATH.read_text(encoding="utf-8")
    found = [method for method in TEST_METHODS if f"func {method}()" in test_text or f"func {method}() async" in test_text or f"func {method}() throws" in test_text or f"func {method}() async throws" in test_text]
    require(found == TEST_METHODS, "exact five G/A/H/I/R methods missing")
    require(test_text.count("func testV10_03") == 5, "unexpected V10_03 test method count")
    fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    expected_fields = ["schema", "schemaVersion", "cardID", "caseIDs", "inventoryExpectations", "rules", "permutations", "hostileCases", "interruptionBoundaries", "lifecycle", "privacy"]
    require(list(fixture) == expected_fields, "fixture top-level fields/order mismatch")
    require(fixture["schema"] == "V21P02C03ReplicationConflictPolicyCorpusV1" and fixture["schemaVersion"] == 1 and fixture["cardID"] == CARD, "fixture identity mismatch")
    require(fixture["caseIDs"] == EVIDENCE_IDS, "fixture case IDs mismatch")
    inventory = fixture["inventoryExpectations"]
    require(inventory["registrationCount"] == 84 and inventory["persistentModelCount"] == 13 and inventory["ownedFileClassCount"] == 20, "fixture primary inventory mismatch")
    require(inventory["portableContentProjectionCount"] == 13 and inventory["derivedIndexProjectionCount"] == 10 and inventory["journalRecoveryCount"] == 21 and inventory["diagnosticCount"] == 7, "fixture current-kind inventory mismatch")
    require(inventory["categoryCounts"] == {"DIAGNOSTIC": 7, "INDEX": 2, "JOURNAL": 21, "OWNED_FILE_CLASS": 20, "PERSISTENT_MODEL": 13, "PROJECTION": 21, "SECRET": 0}, "fixture category counts mismatch")
    require(inventory["classificationCounts"] == {"CONTENT_BLOB": 4, "DERIVED_REBUILDABLE": 26, "LOCAL_ONLY": 32, "PRIVATE_DEVICE_ONLY": 8, "REPLICATED": 14}, "fixture classification counts mismatch")
    require(len(fixture["rules"]) == 6 and len(fixture["permutations"]["twoWay"]) == 2 and len(fixture["permutations"]["threeWay"]) == 6, "fixture matrix/permutation count mismatch")
    require(len(fixture["hostileCases"]) == 17 and len(set(fixture["hostileCases"])) == 17 and len(fixture["interruptionBoundaries"]) == 4, "fixture hostile/interruption count mismatch")
    hostile_required = {"external_provider_authority_present", "provider_controlled_retention_present", "unknown_declared_model_default_classification", "unknown_declared_file_default_classification", "secret_portability_enabled", "secret_present"}
    require(hostile_required.issubset(fixture["hostileCases"]), "fixture provider/default/secret hostile cases missing")
    require(fixture["privacy"].get("containsCustomerData") is False and fixture["privacy"].get("containsSecrets") is False, "fixture privacy mismatch")
    all_source = "\n".join((ROOT / p).read_text(encoding="utf-8", errors="strict") for p in SOURCE_PATHS)
    for prohibited in ("CloudKit", "CKRecord", "NSUbiquitousKeyValueStore", "serverCursor", "vectorClock"):
        require(prohibited not in all_source, f"prohibited transport/source token present: {prohibited}")
    production_source = "\n".join((ROOT / p).read_text(encoding="utf-8", errors="strict") for p in SOURCE_PATHS[:44])
    for prohibited in ("EXTERNAL_PROVIDER", "PROVIDER_CONTROLLED_CACHE", ".externalProvider", ".providerControlledCache"):
        require(prohibited not in production_source, f"provider authority/retention token present in production: {prohibited}")


def verify_hostile_rejection() -> None:
    schema = load(REGISTRY_SCHEMA); instance = load(REGISTRY_DOC)
    mutations = []
    extra = copy.deepcopy(instance); extra["unexpected"] = True; mutations.append(extra)
    missing = copy.deepcopy(instance); del missing["classifications"]; mutations.append(missing)
    changed = copy.deepcopy(instance); changed["classifications"][0] = "UNKNOWN"; mutations.append(changed)
    changed_digest = copy.deepcopy(instance); changed_digest["artifactDigest"] = "z" * 64; mutations.append(changed_digest)
    for index, mutation in enumerate(mutations):
        try:
            validate_instance(mutation, schema)
        except VerificationError:
            continue
        raise VerificationError(f"hostile schema mutation accepted: {index}")


def verify_python_and_generator() -> None:
    for relative in (CONTRACT_SCRIPT, "Scripts/v23/generate_p02_c03_contracts.py", "Scripts/v23/verify_p02_c03_contracts.py"):
        ast.parse((ROOT / relative).read_text(encoding="utf-8"), filename=relative)
    result = subprocess.run([sys.executable, "-B", str(ROOT / "Scripts/v23/generate_p02_c03_contracts.py"), "--check", "--root", str(ROOT)], cwd=ROOT, capture_output=True, text=True)
    require(result.returncode == 0, f"generator --check failed:\n{result.stdout}{result.stderr}")


def main() -> int:
    try:
        verify_generated(); verify_contracts(); verify_manifest(); verify_sources()
        verify_hostile_rejection(); verify_python_and_generator()
    except (VerificationError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"V23-P02-C03 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P02-C03 hostile static verification passed: 58 fence paths, 57 sealed inputs, 4 strict schemas, 5 evidence tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
