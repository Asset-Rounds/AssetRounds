#!/usr/bin/env python3
"""Deterministic Card 35 finding-lifecycle contracts.

The seven Swift declarations, one test source, and one canonical fixture are
the only semantic inputs. Generated JSON is a sealed projection of those
inputs and immutable hydration authority; it is not a second implementation.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C04"
TITLE = "Finding, human-recorded operational disposition, corrective work, verified recheck, release-to-service, and duplicate-link lifecycle"
ORDINAL = 35

APP_BASE_HEAD = "c7ec5971598837bfabae62011dbe0900dc240502"
APP_BASE_TREE = "9fe3e63517d68c86e46c14efe8362944810e8b1b"
COORDINATION_HEAD = "99765a544d0d5a5a2d0b39636928ef337441b3c7"
COORDINATION_TREE = "68f3a0d250227a8359e8a9f0bee922d2008d88f4"
COORDINATION_CAS_SEQUENCE = 148
COORDINATION_LEDGER_DIGEST = "225aab4d7ef7818d1b0a81703456274c7fb74dd1bf16c62d1f672bbf090c6b0a"
CONTEXT_DIGEST = "08b416bc888cf2ce2cc408b1ad93163a23022ff078af002bb9aedc83baaf12ab"
FENCE_DIGEST = "cafb01052cd0eb74fb7a90f0815439d3e3b29811c3a8b920fbae4d948d5c166c"
PREREQUISITE_DIGEST = "19c5febfafc1574a9b3c15e9621b3d149996c8b9458e04ced71475359751adab"
TRANSITION_DIGEST = "f88bc4a4adc884137d6a6b238df0b8037b65d7a76b4d8907c7e09fa3fb7f700e"
HYDRATION_PROJECTION_DIGEST = "14857ad67f63d5c492d613e706190d50041ed31aa637f8c3ef80879e5c66b650"
REGISTER_SECTION_DIGEST = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_ROW_DIGEST = "ec4c18100d9104105174641677eb0bb9512e916af88177d1a992068d71cd9d03"
DOSSIER_DIGEST = "d6f920d2ccee0b21fd6952e4fdc39f30eac9de4775228ba94b35fc7de41a66e3"
INHERITED_DIGEST = "46d7bb5238d24f1eb8efe341ffc6f0554101a9203c4173c33f63bdfc4f261c10"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p03-c04-contracts-v1"
GENERATOR_SEED = 230304

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/InspectionKernel/FindingContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/FindingLifecycleV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CorrectiveWorkContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/VerifiedRecheckContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ReleaseToServiceContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RelatedWorkContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/FindingContractRegistryV1.swift",
    "FieldEvidenceAppTests/V9_14FindingLifecycleTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/InspectionKernel/V21P03C04FindingLifecycleCorpusV1.json",
]
CONTRACT_SCRIPT = "Scripts/v23/p03_c04_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p03_c04_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p03_c04_contracts.py"
SCHEMA_PATHS = [
    "Scripts/v23/finding.schema.json",
    "Scripts/v23/finding-transition.schema.json",
    "Scripts/v23/corrective-work-link.schema.json",
    "Scripts/v23/verified-recheck.schema.json",
    "Scripts/v23/work-relationship.schema.json",
    "Scripts/v23/finding-lifecycle-evidence-receipt.schema.json",
]
CONTRACT_PATHS = [
    "docs/design/v23/tooling/V23P03C04FindingContractV1.json",
    "docs/design/v23/tooling/V23P03C04FindingLifecycleContractV1.json",
    "docs/design/v23/tooling/V23P03C04CorrectiveRecheckReleaseContractV1.json",
    "docs/design/v23/tooling/V23P03C04RelatedWorkContractV1.json",
    "docs/design/v23/tooling/V23P03C04FindingLifecycleEvidenceReceiptV1.json",
]
MANIFEST = "docs/design/v23/tooling/V23-P03-C04-tooling-manifest.json"
TOOL_PATHS = [CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT] + SCHEMA_PATHS + CONTRACT_PATHS + [MANIFEST]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = SCHEMA_PATHS + CONTRACT_PATHS + [MANIFEST]
EXISTING_PATHS: list[str] = []
NEW_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]

EVIDENCE_FAMILIES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = [f"{CARD}-{family}" for family in EVIDENCE_FAMILIES]
EVIDENCE_OUTCOMES = {
    "G01": "COMPLETE_FINDING_LIFECYCLE_AND_REOPEN_MATRIX_IS_EXPLICIT_ORDERED_AND_RECONSTRUCTABLE",
    "A01": "INVALID_TRANSITION_AND_TERMINAL_NEGATIVES_FAIL_CLOSED_WITHOUT_HISTORY_REWRITE",
    "H01": "CONCURRENT_CORRECTION_RECHECK_AND_STALE_MUTATIONS_PRESERVE_EXPECTED_REVISION_TRUTH",
    "I01": "INTERRUPTED_DORMANT_REGISTRY_PUBLICATION_EXPOSES_ZERO_OR_COMPLETE_CANONICAL_RESULT",
    "R01": "SNAPSHOT_LINEAGE_AND_RELATED_WORK_REBUILD_RECONCILE_WITHOUT_AUTO_MERGE_CLOSE_OR_COPY",
}

class ContractError(ValueError):
    pass

def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")

def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result

def read(root: Path, relative: str) -> bytes:
    path = root / relative
    if not path.is_file():
        raise ContractError(f"missing fenced input: {relative}")
    return path.read_bytes()

def text(root: Path, relative: str) -> str:
    try:
        return read(root, relative).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ContractError(f"non-UTF-8 input: {relative}") from error

def fixture(root: Path) -> dict[str, Any]:
    try:
        value = json.loads(read(root, SOURCE_PATHS[-1]))
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid fixture JSON: {error}") from error
    if not isinstance(value, dict):
        raise ContractError("fixture must be an object")
    if read(root, SOURCE_PATHS[-1]) != canonical(value) + b"\n":
        raise ContractError("fixture must be canonical compact sorted JSON plus LF")
    return value

def test_methods(root: Path) -> list[str]:
    methods = re.findall(r"\bfunc\s+(testV9_14[A-Za-z0-9_]*)\s*\(", text(root, SOURCE_PATHS[7]))
    if len(methods) != 5 or len(set(methods)) != 5:
        raise ContractError(f"expected exactly five unique V9_14 tests, found {methods}")
    families = []
    for method in methods:
        match = re.fullmatch(r"testV9_14([GAHIR]01)[A-Za-z0-9_]*", method)
        if match is None:
            raise ContractError(f"test lacks deterministic evidence family: {method}")
        families.append(match.group(1))
    if families != list(EVIDENCE_FAMILIES):
        raise ContractError(f"evidence family order differs: {families}")
    return methods

def require_semantics(root: Path) -> dict[str, list[str]]:
    required = {
        SOURCE_PATHS[0]: ["FindingV1", "FindingSeverityBindingV1", "severityID", "severityScaleReleaseID", "severityScaleSHA256", "findingID", "categoryID", "subject", "source"],
        SOURCE_PATHS[1]: ["FindingTransitionV1", "OperationalDispositionEventV1", "expectedFindingRevision", "mutationID", "reopen", "releaseToServiceID", "validateVerifiedResolutionLineage", "validateReturnedToService"],
        SOURCE_PATHS[2]: ["CorrectiveWorkLinkV1", "workID", "findingRevision", "workRevision"],
        SOURCE_PATHS[3]: ["VerifiedRecheckV1", "findingRevision", "PASSED", "FAILED", "INCONCLUSIVE"],
        SOURCE_PATHS[4]: ["ReleaseToServiceV1", "authorizingActorID", "authority", "reason", "verifiedRecheckID", "verifiedRecheckOutcome", "permitsVerifiedResolution"],
        SOURCE_PATHS[5]: ["RelatedWorkSuggestionV1", "WorkRelationshipV1", "WorkRelationshipDecisionV1", "policySHA256", "suggestionID", "NOT_RELATED", "REMOVE_RELATION", "DUPLICATE_OF", "RELATED_TO"],
        SOURCE_PATHS[6]: ["FindingContractRegistryV1", "FindingLifecycleCanonicalEvidenceV1", "FindingLifecycleCanonicalEvidenceCodecV1", "correctiveWorkLinks", "canonicalEvidenceIncomplete", "validateVerifiedResolutionLineage", "validateReturnedToService", "policySHA256", "suggestionID", "DECLARATION_ONLY", "KERNEL_FINDING_V1", "DORMANT_REVERT_ALLOWED"],
    }
    for relative, markers in required.items():
        source = text(root, relative).lower()
        missing = [marker for marker in markers if marker.lower() not in source]
        if missing:
            raise ContractError(f"{relative}: missing semantic markers: {missing}")
    if "FindingSeverityV1" in text(root, SOURCE_PATHS[0]):
        raise ContractError("invented Card 35 severity vocabulary remains in source")
    all_swift = "\n".join(text(root, path) for path in SOURCE_PATHS[:7]).lower()
    prohibited = [r"\burlsession\b", r"\bcloudkit\b", r"\bfirebase\b", r"\btestflight\b", r"\bapp store\b", r"\bsla\b", r"\bnotification backend\b"]
    leaked = [token for token in prohibited if re.search(token, all_swift)]
    if leaked:
        raise ContractError(f"forbidden native/hosted/release semantic tokens: {leaked}")
    return required

def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": ORDINAL, "title": TITLE,
        "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND", "lineageSource": "V21-P03-C04",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION", "branch": "phase/v23-expansion",
        "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD, "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "transitionDigest": TRANSITION_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "registerSectionDigest": REGISTER_SECTION_DIGEST, "registerRowDigest": REGISTER_ROW_DIGEST,
        "dossierDigest": DOSSIER_DIGEST, "inheritedV21BlockDigest": INHERITED_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P03-C03"], "deterministicEvidenceIDs": EVIDENCE_IDS,
        "invalidationConsumers": ["V23-P03-C05", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
    }

def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False, "hostedDispatchRan": False, "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False,
        "releaseReady": False, "releaseCredit": False, "phase10PollingDuringParallelExecution": False,
        "nativeOrHostedEvidenceClaimed": False, "acceptanceOrReleaseClaimed": False,
        "uiSurfaceDelta": False, "brandSurfaceDelta": False, "requiresAcceptedS10_6Reconciliation": True,
    }

def common(schema: str) -> dict[str, Any]:
    return {
        "schema": schema, "schemaVersion": 1, "cardID": CARD, "authority": authority(),
        "persistentChangeMode": "DECLARATION_ONLY", "persistentContractSchema": "KERNEL_FINDING_V1",
        "migrationRequired": False, "backupRestoreRequired": False, "deleteEraseRequired": False,
        "exportReportRequired": False, "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
        "schemaBehaviorDelta": False, "migrationBehaviorDelta": False, "backupBehaviorDelta": False,
        "restoreBehaviorDelta": False, "deleteBehaviorDelta": False, "exportBehaviorDelta": False,
        "provisionalKernelOnly": True, "shippingBoundaryAdoption": "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION",
        **flags(),
    }

def source_projection(root: Path) -> dict[str, Any]:
    rows = [{"path": path, "bytes": len(read(root, path)), "sha256": sha(read(root, path))} for path in SOURCE_PATHS]
    return {"paths": rows, "pathCount": 9, "sourceSetDigest": sha(canonical(rows))}

def fixture_projection(root: Path) -> dict[str, Any]:
    value = fixture(root)
    return {
        "path": SOURCE_PATHS[-1], "schema": value.get("schema"), "schemaVersion": value.get("schemaVersion"),
        "testOnly": value.get("testOnly"), "topLevelKeys": sorted(value),
        "bytes": len(read(root, SOURCE_PATHS[-1])), "sha256": sha(read(root, SOURCE_PATHS[-1])),
        "canonicalSHA256": sha(canonical(value)),
    }

def obj(properties: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "properties": properties, "required": required}

def string(*, enum: list[str] | None = None, pattern: str | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "string"}
    if enum is not None: result["enum"] = enum
    if pattern is not None: result["pattern"] = pattern
    return result

def identifier() -> dict[str, Any]:
    return {"type": "string", "pattern": "^[a-z0-9._-]+$", "maxLength": 128}

def array(items: dict[str, Any], minimum: int = 0) -> dict[str, Any]:
    return {"type": "array", "items": items, "minItems": minimum}

def schema(title: str, body: dict[str, Any]) -> dict[str, Any]:
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": f"https://assetrounds.invalid/v23/{title}.schema.json", "title": title, **body}

def schemas() -> dict[str, dict[str, Any]]:
    sha_s = string(pattern="^[0-9a-f]{64}$")
    nonnegative = {"type": "integer", "minimum": 0}
    severity = obj({"severityID": identifier(), "severityScaleReleaseID": identifier(), "severityScaleSHA256": sha_s}, ["severityID", "severityScaleReleaseID", "severityScaleSHA256"])
    subject = obj({"subjectKindID": identifier(), "subjectID": identifier(), "subjectRevision": nonnegative}, ["subjectKindID", "subjectID", "subjectRevision"])
    source_evidence = array(identifier())
    source_evidence.update({"maxItems": 32, "uniqueItems": True})
    finding_source = obj({"kind": string(enum=["INSPECTION_RESPONSE", "INSPECTION_OBSERVATION", "HUMAN_OBSERVATION", "IMPORTED_RECORD"]), "sourceID": identifier(), "sourceRevision": nonnegative, "evidenceRevisionIDs": source_evidence}, ["kind", "sourceID", "sourceRevision", "evidenceRevisionIDs"])
    finding = obj({"schemaVersion": {"const": 1}, "findingID": identifier(), "revision": nonnegative, "severity": severity, "categoryID": identifier(), "subject": subject, "source": finding_source, "summary": string()}, ["schemaVersion", "findingID", "revision", "severity", "categoryID", "subject", "source", "summary"])
    states = ["OPEN", "CORRECTIVE_WORK_IN_PROGRESS", "AWAITING_VERIFIED_RECHECK", "VERIFIED_RESOLVED", "CLOSED", "REOPENED"]
    transition_properties = {"schemaVersion": {"const": 1}, "transitionID": identifier(), "findingID": identifier(), "expectedFindingRevision": nonnegative, "resultingFindingRevision": nonnegative, "mutationID": identifier(), "fromState": string(enum=states), "toState": string(enum=states), "actorID": identifier(), "reason": string(), "effectiveAt": string(), "verifiedRecheckID": identifier()}
    transition = obj(transition_properties, [key for key in transition_properties if key != "verifiedRecheckID"])
    transition["allOf"] = [
        {"if": {"properties": {"toState": {"const": "VERIFIED_RESOLVED"}}, "required": ["toState"]}, "then": {"required": ["verifiedRecheckID"]}},
        {"if": {"required": ["verifiedRecheckID"]}, "then": {"properties": {"toState": {"const": "VERIFIED_RESOLVED"}}}},
    ]
    work_properties = {"schemaVersion": {"const": 1}, "linkID": identifier(), "findingID": identifier(), "findingRevision": nonnegative, "workID": identifier(), "workRevision": nonnegative, "expectedLinkRevision": nonnegative, "resultingLinkRevision": nonnegative, "mutationID": identifier(), "action": string(enum=["LINKED", "REMOVED"]), "actorID": identifier(), "reason": string(), "effectiveAt": string(), "supersedesLinkEventID": identifier()}
    work = obj(work_properties, [key for key in work_properties if key != "supersedesLinkEventID"])
    work["allOf"] = [{"if": {"properties": {"action": {"const": "REMOVED"}}, "required": ["action"]}, "then": {"required": ["supersedesLinkEventID"]}}]
    recheck_evidence = array(identifier(), 1)
    recheck_evidence.update({"maxItems": 32, "uniqueItems": True})
    recheck_properties = {"schemaVersion": {"const": 1}, "recheckID": identifier(), "findingID": identifier(), "findingRevision": nonnegative, "correctiveWorkID": identifier(), "correctiveWorkRevision": nonnegative, "priorRecheckID": identifier(), "evidenceRevisionIDs": recheck_evidence, "expectedRecheckRevision": nonnegative, "resultingRecheckRevision": nonnegative, "mutationID": identifier(), "outcome": string(enum=["PASSED", "FAILED", "INCONCLUSIVE"]), "verifierActorID": identifier(), "verifierAuthority": string(), "reason": string(), "effectiveAt": string()}
    recheck = obj(recheck_properties, [key for key in recheck_properties if key != "priorRecheckID"])
    relationship = obj({"schemaVersion": {"const": 1}, "relationshipID": identifier(), "sourceWorkID": identifier(), "sourceWorkRevision": nonnegative, "targetWorkID": identifier(), "targetWorkRevision": nonnegative, "kind": string(enum=["DUPLICATE_OF", "RELATED_TO"]), "direction": string(enum=["DIRECTED", "SYMMETRIC"]), "reason": string(), "actorID": identifier(), "mutationID": identifier(), "createdAt": string()}, ["schemaVersion", "relationshipID", "sourceWorkID", "sourceWorkRevision", "targetWorkID", "targetWorkRevision", "kind", "direction", "reason", "actorID", "mutationID", "createdAt"])
    relationship["allOf"] = [
        {"if": {"properties": {"kind": {"const": "DUPLICATE_OF"}}, "required": ["kind"]}, "then": {"properties": {"direction": {"const": "DIRECTED"}}}},
        {"if": {"properties": {"kind": {"const": "RELATED_TO"}}, "required": ["kind"]}, "then": {"properties": {"direction": {"const": "SYMMETRIC"}}}},
    ]
    evidence_row = obj({"evidenceID": string(enum=EVIDENCE_IDS), "family": string(enum=list(EVIDENCE_FAMILIES)), "testMethod": string(pattern="^testV9_14[GAHIR]01[A-Za-z0-9_]+$"), "outcome": string(), "sourceSetDigest": sha_s}, ["evidenceID", "family", "testMethod", "outcome", "sourceSetDigest"])
    evidence_array = array(evidence_row, 5)
    evidence_array["maxItems"] = 5
    evidence_array["uniqueItems"] = True
    receipt = obj({"schemaVersion": {"const": 1}, "cardID": {"const": CARD}, "evidence": evidence_array, "fixtureSHA256": sha_s, "nativeCompileRan": {"const": False}, "hostedDispatchRan": {"const": False}, "acceptanceCredit": {"const": False}, "releaseCredit": {"const": False}}, ["schemaVersion", "cardID", "evidence", "fixtureSHA256", "nativeCompileRan", "hostedDispatchRan", "acceptanceCredit", "releaseCredit"])
    return {path: schema(title, body) for path, title, body in zip(SCHEMA_PATHS, ["FindingV1", "FindingTransitionV1", "CorrectiveWorkLinkV1", "VerifiedRecheckV1", "WorkRelationshipV1", "FindingLifecycleEvidenceReceiptV1"], [finding, transition, work, recheck, relationship, receipt])}

def evidence_rows(root: Path, methods: list[str], source: dict[str, Any]) -> list[dict[str, Any]]:
    return [{"evidenceID": EVIDENCE_IDS[i], "family": family, "testMethod": methods[i], "outcome": EVIDENCE_OUTCOMES[family], "sourceSetDigest": source["sourceSetDigest"]} for i, family in enumerate(EVIDENCE_FAMILIES)]

def documents(root: Path, methods: list[str], source: dict[str, Any], fix: dict[str, Any]) -> dict[str, dict[str, Any]]:
    base = {"sourceProjection": source, "fixtureProjection": fix, "testMethods": methods, "evidenceIDs": EVIDENCE_IDS}
    finding = seal({**common("V23P03C04FindingContractV1"), **base, "stableIdentity": True, "presentationIndependent": True, "attributes": ["findingID", "revision", "severity", "categoryID", "subject", "source"], "severityContract": {"bindingType": "FindingSeverityBindingV1", "fields": ["severityID", "severityScaleReleaseID", "severityScaleSHA256"], "stableSeverityID": True, "immutableScaleReleaseBinding": True, "locallyInventedVocabulary": False}, "historyPolicy": "APPEND_ONLY_ORDERED_NO_REWRITE"})
    aggregate = {"type": "FindingLifecycleCanonicalEvidenceV1", "codec": "FindingLifecycleCanonicalEvidenceCodecV1", "requiredFields": ["finding", "lifecycle", "correctiveWorkLinks", "verifiedRechecks", "releasesToService", "operationalDispositionEvents", "relatedWorkSuggestions", "workRelationships", "workRelationshipDecisions"], "canonicalSortedExactBytes": True, "failClosedError": "canonicalEvidenceIncomplete", "findingAndSubjectScoped": True, "relatedSuggestionScopeFields": ["subjectID", "categoryID"]}
    lifecycle = seal({**common("V23P03C04FindingLifecycleContractV1"), **base, "transitionPolicy": "FINITE_EXPLICIT_EXPECTED_REVISION_MUTATION_ID_IDEMPOTENCY_TERMINAL_REOPEN", "dispositions": ["IN_SERVICE_RECORDED", "RESTRICTED_USE_RECORDED", "OUT_OF_SERVICE_RECORDED", "RETURNED_TO_SERVICE_RECORDED", "UNKNOWN_REVIEW_REQUIRED"], "resolutionRequiresVerifiedRecheck": True, "failedOrInconclusiveCannotResolve": True, "canonicalEvidence": aggregate})
    corrective = seal({**common("V23P03C04CorrectiveRecheckReleaseContractV1"), **base, "correctiveLinkBinding": ["stableWorkID", "workRevision", "findingID", "findingRevision"], "canonicalAggregateRequiresCorrectiveWorkLinks": True, "recheckRequiresHistoricallyEffectiveLinkedCorrectiveTarget": True, "groupedCorrectiveAndRecheckLedgers": True, "releaseSeparateFromCorrectionAndRecheck": True, "releaseSeparateHumanAuthorization": True, "releaseAuthorizationFields": ["authorizingActorID", "authority", "reason", "effectiveAt", "mutationID"], "releaseVerifiedRecheckFields": ["verifiedRecheckID", "verifiedRecheckFindingRevision", "verifiedRecheckOutcome"], "releaseRequiresActualUniquePassingVerifiedRecheck": True, "returnedToServiceDispositionRequiresExactReleaseAndRecheck": True, "returnedToServiceLineageValidator": "OperationalDispositionLedgerV1.validateReturnedToService", "automaticClosure": False, "safetyOrComplianceInference": False})
    related = seal({**common("V23P03C04RelatedWorkContractV1"), **base, "relationshipKinds": ["DUPLICATE_OF", "RELATED_TO"], "decisionKinds": ["CONFIRM", "NOT_RELATED", "REMOVE_RELATION"], "decisionBasisFields": ["suggestionID", "sourceWorkID", "sourceWorkRevision", "candidateWorkID", "candidateWorkRevision", "policySHA256"], "decisionDecodeRecomputesSuggestionID": True, "canonicalAggregateRequiresUniqueSuggestionBasis": True, "canonicalAggregateSuggestionScope": {"subjectID": "finding.subject.subjectID", "categoryID": "finding.categoryID", "mismatchDisposition": "canonicalEvidenceIncomplete"}, "canonicalAggregateAllowsOnlyConfirmedRelationships": True, "suggestionsRebuildable": True, "decisionsAppendOnly": True, "automaticMergeCloseCopyCompletionChange": False})
    evidence = seal({**common("V23P03C04FindingLifecycleEvidenceReceiptV1"), **base, "evidence": evidence_rows(root, methods, source), "fixtureSHA256": fix["sha256"], "requiredEvidence": ["transition table", "lifecycle fixtures", "lineage reconciliation", "canonical aggregate exact-byte reconciliation"], "canonicalAggregate": aggregate, "crossRecordFailureCases": ["ARBITRARY_RESOLUTION_RECHECK", "CORRECTIVE_TARGET_MISSING_OR_REMOVED", "FABRICATED_SUGGESTION_DIVERGENT_BASIS", "RELEASE_ACTUAL_RECHECK_MISSING_OR_MISMATCHED", "RETURNED_DISPOSITION_RELEASE_MISMATCH", "ORPHAN_RELATIONSHIP"], "interruptionBoundaries": ["BEFORE_VALIDATION", "AFTER_VALIDATION_BEFORE_PUBLICATION", "AFTER_PUBLICATION_BEFORE_RECEIPT"]})
    return dict(zip(CONTRACT_PATHS, [finding, lifecycle, corrective, related, evidence]))

def manifest(root: Path, generated: dict[str, bytes], source: dict[str, Any], fix: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    rows, pending = [], []
    for relative in MANIFEST_INPUT_PATHS:
        data = generated.get(relative)
        if data is None:
            path = root / relative
            if not path.is_file(): pending.append(relative); continue
            data = path.read_bytes()
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data)})
    return seal({
        **common("V23-P03-C04-tooling-manifest"), "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": PATH_FENCE, "pathFenceCount": 24, "existingPaths": [], "newPaths": NEW_PATHS,
        "sourcePaths": SOURCE_PATHS, "sourcePathCount": 9, "toolingPaths": TOOL_PATHS, "toolingPathCount": 15,
        "generatedPaths": GENERATED_PATHS, "artifacts": rows, "artifactCount": len(rows),
        "pendingFencePaths": pending, "pendingArtifactCount": len(pending), "artifactSetDigest": sha(pretty(rows)),
        "fenceProof": {"baseHead": APP_BASE_HEAD, "baseTree": APP_BASE_TREE, "pathFenceDigest": FENCE_DIGEST, "allowedPathCount": 24, "existingPathCount": 0, "newPathCount": 24, "priorFenceOverlapCount": 0, "authorizedPriorFenceOverlapCount": 0, "unauthorizedPriorFenceOverlapCount": 0, "allowedDeletePaths": [], "allowedRenamePaths": [], "activeS10ReservationDigest": S10_RESERVATION_DIGEST, "activeS10Overlap": False},
        "sourceProjection": source, "fixtureProjection": fix, "testMethods": methods, "evidenceIDs": EVIDENCE_IDS,
        "strictSchemaCount": 6, "contractDocumentCount": 5, "privacyAllowlistOnly": True,
        "noNetwork": True, "noRuntimeDownloads": True, "noNewSwiftDataV6Entity": True, "declarationOnly": True,
    })

def all_outputs(root: Path) -> dict[str, bytes]:
    if len(PATH_FENCE) != 24 or len(set(PATH_FENCE)) != 24 or EXISTING_PATHS or NEW_PATHS != PATH_FENCE:
        raise ContractError("Card 35 fence must contain exactly 24 unique all-new paths")
    methods = test_methods(root)
    require_semantics(root)
    source = source_projection(root)
    fix = fixture_projection(root)
    if fix["testOnly"] is not True or fix["schemaVersion"] != 1:
        raise ContractError("fixture identity/test-only declaration differs")
    generated = {path: pretty(value) for path, value in schemas().items()}
    generated.update({path: pretty(value) for path, value in documents(root, methods, source, fix).items()})
    generated[MANIFEST] = pretty(manifest(root, generated, source, fix, methods))
    return generated
