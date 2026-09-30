#!/usr/bin/env python3
"""Fail-closed static evidence contracts for V23-P04-C10."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
ROOT = Path(__file__).resolve().parents[2]
COORD = Path(r"C:\AssetRounds-v23-coordination")
CARD = "V23-P04-C10"
TITLE = "Deterministic Evidence Quality Coach with reasoned override and no automatic compliance judgment"
CONTEXT_DIGEST = "1eaab5e9c161c1fb6ae8cb27709dc5b398d47cbe6824d3548dd6496da6253b98"
FENCE_DIGEST = "acf9ae293df735c992882736812a01416d503499820d5f829b0b1179e130e89a"
COORDINATION_HEAD = "dc34313"
COORDINATION_TREE = "185970332669cf127510e902cc427174c18929d3"
HYDRATION_TRANSITION_DIGEST = "1a2dcfa6f84e26f3a7ff5c1075568a5f18895411042178f8211f2ed3025893e5"
HYDRATED_LEDGER_DIGEST = "cf4762a7125ef0f59ee368769ca3ca7a2b114415299337762eeddbf8a92b0f1d"
HYDRATED_PROJECTION_DIGEST = "13f3a13223f564576315542fcc1e9a88484e8c2912217891e99bf30c1b1ef087"
APP_BASE_HEAD = "9292aff5edb5a763599feefec3c00f158d31d33c"
REGISTER_ORDINAL = 98
FINAL_HASHES_SEALED = True
SCHEMA_PATH = "Scripts/v23/evidence-quality.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C10EvidenceQualityContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C10EvidenceQualityEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C10BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C10-tooling-manifest.json"
SCRIPT_PATHS = ("Scripts/v23/p04_c10_contracts.py", "Scripts/v23/generate_p04_c10_contracts.py", "Scripts/v23/verify_p04_c10_contracts.py")
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
 "FieldEvidenceApp/Application/EvidenceQuality/EvidenceQualityCoordinatorV1.swift",
 "FieldEvidenceApp/Domain/EvidenceQuality/EvidenceQualityContractsV1.swift",
 "FieldEvidenceApp/Domain/Models/EvidenceQualityPersistenceModelsV1.swift",
 "FieldEvidenceApp/Features/CheckRunner/EvidenceQualityCoachView.swift",
 "FieldEvidenceApp/Infrastructure/Media/EvidenceQualityLifecycleAdapterV1.swift",
 "FieldEvidenceAppTests/Fixtures/V22/EvidenceQuality/V22P04C10EvidenceQualityCoachCorpusV1.json",
 "FieldEvidenceAppTests/V9_74EvidenceQualityCoachTests.swift",
 "FieldEvidenceAppUITests/V23_P04_C10EvidenceQualityCoachUITests.swift",
)
NEW_PATHS = (MANIFEST_PATH, BRAND_PATH, CONTRACT_PATH, EVIDENCE_PATH, *IMPLEMENTATION_PATHS, SCHEMA_PATH, "Scripts/v23/generate_p04_c10_contracts.py", "Scripts/v23/p04_c10_contracts.py", "Scripts/v23/verify_p04_c10_contracts.py")
EVIDENCE_IDS = tuple(f"{CARD}-{x}" for x in ("G01", "A01", "H01", "I01", "R01"))
SELECTORS = (
 "testV23P04C10G01ClearlyFramedCaptureProducesExactRuleIDsAndThresholdBoundaryResults",
 "testV23P04C10A01RetakeAcceptWithReasonWaiverBindsExactRevisionAndPreservesEvidence",
 "testV23P04C10H01ChangedDuplicateCorruptEvidenceInvalidatesAssessmentAndWaiverWithoutAutoPass",
 "testV23P04C10I01InterruptedAssessmentOrRetakePreservesOriginalWithoutPartialWaiver",
 "testV23P04C10R01RebuiltAssessmentAndRestorePreserveExactFindingsAndWaiverProvenance",
)
PERSISTENT_KINDS = ("EvidenceQualityAssessmentV1", "EvidenceQualityRuleSetV1", "EvidenceQualityWaiverV1")
LIFECYCLE = ("MIGRATION", "BACKUP", "REPLACE_RESTORE", "DELETE", "ERASE", "EXPORT", "REPORT", "SEARCH", "REPLAY")
FORBIDDEN = ("SECOND_WRITER", "SECOND_STORE", "ROOT_ROUTE", "RENDERER", "IMPORTER", "REMOTE", "AUTH", "HOSTED_SERVICE", "AI_DIAGNOSIS", "OPAQUE_CONFIDENCE", "AUTOMATIC_PASS_FAIL", "EVIDENCE_LAUNDERING", "UNBOUNDED_MEDIA", "GENERIC_JSON_EAV", "ANALYTICS", "TELEMETRY", "MARKETING", "LEGAL_OR_CERTIFICATION_CLAIMS")
FLAGS = {key: False for key in ("activation", "native", "hosted", "adoption", "acceptance", "release", "nativeAcceptance", "hostedAcceptance", "physicalEvidence", "phase10PollingDuringParallelExecution")}

def strict(pairs):
    out = {}
    for key, value in pairs:
        if key in out: raise ValueError("duplicate JSON key:" + key)
        out[key] = value
    return out

def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")
def sha(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def _schema_validate(value: Any, rule: dict[str, Any], root: dict[str, Any], where: str = "$") -> None:
    if "$ref" in rule:
        ref=rule["$ref"]
        if not ref.startswith("#/$defs/"): raise ValueError(where+": unsupported schema reference")
        return _schema_validate(value, root["$defs"][ref.rsplit("/",1)[1]], root, where)
    if "oneOf" in rule:
        valid=[]
        for option in rule["oneOf"]:
            try: _schema_validate(value, option, root, where); valid.append(option)
            except ValueError: pass
        if len(valid) != 1: raise ValueError(where+": schema oneOf mismatch")
        return
    if "const" in rule and value != rule["const"]: raise ValueError(where+": schema const mismatch")
    if "enum" in rule and value not in rule["enum"]: raise ValueError(where+": schema enum mismatch")
    types={"object":dict,"array":list,"string":str,"boolean":bool,"integer":int}
    if rule.get("type"):
        kind=types[rule["type"]]
        if not isinstance(value,kind) or (kind is int and isinstance(value,bool)): raise ValueError(where+": schema type mismatch")
    if isinstance(value,dict):
        required=set(rule.get("required",()))
        if required-set(value): raise ValueError(where+": schema required mismatch")
        properties=rule.get("properties",{})
        if rule.get("additionalProperties") is False and set(value)-set(properties): raise ValueError(where+": schema extra field")
        for key, child in value.items():
            if key in properties: _schema_validate(child,properties[key],root,where+"."+key)
    if isinstance(value,list):
        if "minItems" in rule and len(value)<rule["minItems"]: raise ValueError(where+": schema minItems mismatch")
        if "maxItems" in rule and len(value)>rule["maxItems"]: raise ValueError(where+": schema maxItems mismatch")
        if isinstance(rule.get("items"),dict):
            for index,item in enumerate(value): _schema_validate(item,rule["items"],root,where+"["+str(index)+"]")
def validate_generated_documents(values: dict[str, dict[str, Any]]) -> None:
    schema=json.loads((ROOT/SCHEMA_PATH).read_bytes(), object_pairs_hook=strict)
    for path,value in values.items(): _schema_validate(value,schema,schema,path)
def load(relative: str) -> dict[str, Any]:
    path = COORD / relative
    if not path.is_file(): raise ValueError("coordination input unavailable:" + relative)
    value = json.loads(path.read_bytes(), object_pairs_hook=strict)
    if not isinstance(value, dict): raise ValueError("coordination object required:" + relative)
    return value
def sealed(value: dict[str, Any], key: str) -> str:
    return sha((json.dumps({k:v for k,v in value.items() if k != key}, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode())
def authority() -> tuple[dict[str, Any], dict[str, Any]]:
    context = load("contexts/V23-P04-C10-attempt-1/BootstrapCardContextV1.json")
    fence = load("contexts/V23-P04-C10-attempt-1/BootstrapPathFenceV1.json")
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST or sealed(context, "contextDigest") != CONTEXT_DIGEST: raise ValueError("C10 context identity/seal differs")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST or sealed(fence, "fenceDigest") != FENCE_DIGEST: raise ValueError("C10 fence identity/seal differs")
    if tuple(context.get("newPaths", ())) != NEW_PATHS or tuple(fence.get("allowedCreateOrReplacePaths", ())) != tuple(context.get("existingPaths", ())) + NEW_PATHS: raise ValueError("C10 path fence drift")
    proof = fence.get("priorFenceProof", {})
    allocations = proof.get("allocationDigests", {})
    if len(context.get("existingPaths", ())) != 97 or len(NEW_PATHS) != 16 or len(fence.get("allowedCreateOrReplacePaths", ())) != 113 or proof.get("fenceCount") != 98 or proof.get("priorOwnedPathCount") != 1547 or proof.get("missingPathCount") != 0 or proof.get("duplicatePathCount") != 0 or proof.get("unauthorizedOverlapCount") != 0 or proof.get("authorizedOverlapCount") != 3908 or allocations != {"existing":"681ff2df60cefc1b6e0657b46e7c3f81fea8c660af068810bb7879971ad58c88","new":"c68c3fdc9b9b2068c906cd81a23343c893c649bf7eefdc2b5c1bf8435ecf4b98","combined":"aa4976a47b727c1c77814e5a22516b000a2b075ed22ba0b8abf073cf1262f554"}:
        raise ValueError("C10 prior fence proof differs")
    if set(fence.get("allowedCreateOrReplacePaths", ())) & set(fence.get("activeS10ReservedPaths", ())): raise ValueError("C10 S10 overlap differs")
    if context.get("repository", {}).get("appBaseHead") != APP_BASE_HEAD or context.get("registerOrdinal") != REGISTER_ORDINAL: raise ValueError("C10 app base/register differs")
    if context.get("semanticScope", {}).get("persistentContractSchema") != "EvidenceQualitySchemaV1" or tuple(context["semanticScope"].get("requiredLifecycleFamilies", ())) != LIFECYCLE: raise ValueError("C10 semantic lifecycle differs")
    proof = fence.get("priorFenceProof", {})
    if context.get("directPrerequisites") != ["V23-P04-C02"] or proof.get("executionPredecessorCardID") != "V23-P04-C09": raise ValueError("C10 prerequisite ordering differs")
    observed_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=COORD, check=True, capture_output=True, text=True).stdout.strip()
    observed_origin = subprocess.run(["git", "rev-parse", "origin/main"], cwd=COORD, check=True, capture_output=True, text=True).stdout.strip()
    ledger = load("state/BootstrapExecutionLedgerEnvelopeV1.json")
    transition = load("transitions/000426-V23-P04-C10-attempt-1-NOT_STARTED-to-HYDRATING.json")
    projection = load("projections/ActiveWorkSetProjectionV1.json")
    if observed_head != "dc343131c4c4fa08bb41ff2e8d9b6c9562f6d038" or observed_origin != observed_head or not observed_head.startswith(COORDINATION_HEAD) or _git_tree() != COORDINATION_TREE or ledger.get("casSequence") != 426 or ledger.get("ledgerDigest") != HYDRATED_LEDGER_DIGEST or transition.get("transitionDigest") != HYDRATION_TRANSITION_DIGEST or transition.get("newLedgerDigest") != HYDRATED_LEDGER_DIGEST or projection.get("projectionDigest") != HYDRATED_PROJECTION_DIGEST:
        raise ValueError("C10 coordination authority differs")
    return context, fence
def _git_tree() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD^{tree}"], cwd=COORD, check=True, capture_output=True, text=True).stdout.strip()
def source_rows() -> tuple[list[dict[str, Any]], bool]:
    rows=[]
    for rel in IMPLEMENTATION_PATHS:
        p=ROOT/rel
        present=p.is_file()
        rows.append({"path":rel,"status":"SOURCE_PRESENT" if present else "SOURCE_MISSING", "byteCount":len(p.read_bytes()) if present else 0, "sha256":sha(p.read_bytes()) if present else None})
    return rows, all(r["status"] == "SOURCE_PRESENT" for r in rows)
def fence_rows() -> tuple[list[dict[str, Any]], dict[str, int]]:
    context, fence = authority(); rows=[]
    for rel in fence["allowedCreateOrReplacePaths"]:
        p=ROOT/rel; present=p.is_file()
        rows.append({"path":rel,"status":"PRESENT" if present else "MISSING","byteCount":len(p.read_bytes()) if present else 0,"sha256":sha(p.read_bytes()) if present else None})
    def names(*args: str) -> set[str]:
        output=subprocess.run(["git",*args],cwd=ROOT,check=True,capture_output=True,text=True).stdout.splitlines()
        return {path.replace("\\\\","/") for path in output if path}
    # The candidate is the immutable app-base delta plus any exact worktree
    # delta.  This remains identical after the candidate is committed.
    changed_paths=(names("diff","--name-only",APP_BASE_HEAD,"HEAD") | names("diff","--name-only","HEAD") | names("diff","--name-only","--cached") | names("ls-files","--others","--exclude-standard"))
    owned=set(fence["allowedCreateOrReplacePaths"])
    return rows,{"changedPathCount":len(changed_paths & owned),"missingPathCount":sum(r["status"]=="MISSING" for r in rows),"unownedChangedPathCount":len(changed_paths-owned),"s10ReservationOverlapCount":len(owned & set(fence["activeS10ReservedPaths"]))}
def validate_source_semantics(rows: list[dict[str, Any]], ready: bool) -> None:
    """Only a complete source set may make source semantics inspectable."""
    if not ready:
        return
    supporting = ("FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift", "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift", "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift", "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift", "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift", "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift", "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift")
    text = "\n".join((ROOT / path).read_text(encoding="utf-8") for path in (*[row["path"] for row in rows], *supporting))
    missing = [token for token in (*PERSISTENT_KINDS, *LIFECYCLE, *SELECTORS) if token.lower() not in text.lower()]
    if missing:
        raise ValueError("C10 source model/record/lifecycle/selector coverage missing:" + ",".join(missing))
    if not re.search(r"(expectedRevision|expected_revision).*(mutationID|mutation_id)|(mutationID|mutation_id).*(expectedRevision|expected_revision)", text, re.I | re.S):
        raise ValueError("C10 source lacks revision/mutation writer fence")
    required = ("PersistentSchemaV47", "models.count==153", "PersistentSchemaV46.models.count + 4", "EvidenceQualityQueryResultV1", "WorkspaceWriterV1", "MutationReceiptV1", "LocalChangeJournal", "V46", "V45", "cloneDisposition = \"NOT_APPLICABLE\"", "forkDisposition = \"NOT_APPLICABLE\"", "EraseAllService", "RestoreIdentity", "DeterministicOpenJSONRenderer", "XCTSkip", "NO_AUTOMATIC_COMPLIANCE_JUDGMENT", "NO_AUTOMATIC_PASS")
    absent = [token for token in required if token not in text]
    if absent: raise ValueError("C10 canonical lifecycle coverage missing:" + ",".join(absent))
    scoped = {
        "FieldEvidenceApp/Application/EvidenceQuality/EvidenceQualityCoordinatorV1.swift": ("WorkspaceWriterV1", "commitEvidenceQuality", "evidenceQualityReceipt", "EvidenceQualitySwiftDataQuerySourceV1", "EvidenceQualityQueryResultV1", "submitOrRecover"),
        "FieldEvidenceApp/Infrastructure/Media/EvidenceQualityLifecycleAdapterV1.swift": ("func replay", "receipt.validate(command: command)", "func search", "result.validate(for: request)", "func replaceRestore", "func erase", "func report", "func exportCanonical", "func migrate"),
        "FieldEvidenceApp/Domain/Models/EvidenceQualityPersistenceModelsV1.swift": ("EvidenceQualityRuleSetRowV1", "EvidenceQualityAssessmentRowV1", "EvidenceQualityWaiverRowV1", "EvidenceQualityMutationReceiptRowV1", "init(restoring", "verifyRestore"),
        "FieldEvidenceAppTests/V9_74EvidenceQualityCoachTests.swift": (".lifecycle.replaceRestore(", ".lifecycle.report()", ".lifecycle.search(", ".lifecycle.replay(", ".lifecycle.delete()", ".lifecycle.erase()", ".assessmentProjection(found)"),
        "FieldEvidenceAppUITests/V23_P04_C10EvidenceQualityCoachUITests.swift": ("XCTSkip", "no acceptance credit"),
    }
    for path, tokens in scoped.items():
        body=(ROOT/path).read_text(encoding="utf-8")
        absent=[token for token in tokens if token not in body]
        if absent: raise ValueError("C10 scoped assertion missing:"+path+":"+",".join(absent))
    test_body=(ROOT/"FieldEvidenceAppTests/V9_74EvidenceQualityCoachTests.swift").read_text(encoding="utf-8")
    production_adapter=(ROOT/"FieldEvidenceApp/Infrastructure/Media/EvidenceQualityLifecycleAdapterV1.swift").read_text(encoding="utf-8")
    production_required=("PersistentSchemaV47", "WorkspaceWriterAdapterV1", "MutationJournalStoreV1", "WorkspaceWriterV1")
    if any(token not in text for token in production_required):
        raise ValueError("C10 production persistence enrollment missing")
    if "init(workspaceWriter: WorkspaceWriterV1, modelContext: ModelContext" not in production_adapter:
        raise ValueError("C10 production lifecycle initializer missing")
    if ".assessmentProjection(found)" not in test_body or "EvidenceQualityQueryResultV1" not in text:
        raise ValueError("C10 closed query-result case assertion missing")
    for forbidden_store in ("C10EvidenceQualityStore", "C10RealPersistenceProbe"):
        if forbidden_store in text: raise ValueError("C10 prohibited independent persistence test double:"+forbidden_store)
    adapter=(ROOT/"FieldEvidenceApp/Infrastructure/Media/EvidenceQualityLifecycleAdapterV1.swift").read_text(encoding="utf-8")
    for identity, dictionary in (("ruleSetIDs", "Dictionary(uniqueKeysWithValues: snapshot.ruleSets"), ("assessmentIDs", "Dictionary(uniqueKeysWithValues: snapshot.assessments")):
        if adapter.find("Set("+identity+").count") < 0 or adapter.find("Set("+identity+").count") > adapter.find(dictionary):
            raise ValueError("C10 restore provenance uniqueness ordering differs:"+identity)
    if "(ruleSet." in adapter or "(assessment." in adapter:
        raise ValueError("C10 literal interpolation placeholder in lifecycle adapter")
    if re.search(r"\b(ai diagnosis|opaque confidence|automatic pass|automatic compliance)\b", text, re.I):
        raise ValueError("C10 prohibited source claim")
def semantic_scope() -> dict[str, Any]:
    return {"persistentContractMode":"NEW_SCHEMA_VERSION","persistentContractSchema":"EvidenceQualitySchemaV1","persistentKinds":list(PERSISTENT_KINDS),"canonicalOwner":"V23-P04-C10_SOLE_EVIDENCE_QUALITY_WRITER_OWNER","oneCanonicalWriter":True,"canonicalWriterRequirements":["EXPECTED_REVISION","MUTATION_ID","ONE_CANONICAL_WRITER_TRANSACTION","DURABLE_RECEIPT","SEMANTIC_REVERSAL_OR_SUPERSESSION","EFFECT_BEFORE_RECEIPT_RECOVERY"],"lifecycleCoverage":list(LIFECYCLE),"versionedRules":True,"exactAssessmentEvidenceRevisionWaiver":True,"humanJudgmentRule":"NO_AUTOMATIC_COMPLIANCE_JUDGMENT_OR_AUTO_PASS","prohibitedCapabilities":list(FORBIDDEN),"containedUI":"POST_S10_6_ADOPTION_SKIP_NO_CREDIT","uiAcceptanceCredit":False,"statusFlags":FLAGS}
def documents() -> dict[str, dict[str, Any]]:
    context, fence = authority(); rows, ready = source_rows(); owned_rows, counts = fence_rows(); provisional = not (FINAL_HASHES_SEALED and ready)
    auth={"cardID":CARD,"title":TITLE,"registerOrdinal":REGISTER_ORDINAL,"appBaseHead":APP_BASE_HEAD,"contextDigest":CONTEXT_DIGEST,"pathFenceDigest":FENCE_DIGEST,"taskStartCoordinationHead":context["coordination"]["coordinationHead"],"taskStartCoordinationCASSequence":context["coordination"]["ledgerCASSequence"],"taskStartLedgerDigest":context["coordination"]["ledgerDigest"],"taskStartProjectionDigest":context["coordination"]["projectionDigest"],"hydrationCoordinationHead":"dc343131c4c4fa08bb41ff2e8d9b6c9562f6d038","hydrationCoordinationTree":COORDINATION_TREE,"hydrationCASSequence":426,"hydrationTransitionDigest":HYDRATION_TRANSITION_DIGEST,"hydrationLedgerDigest":HYDRATED_LEDGER_DIGEST,"hydrationProjectionDigest":HYDRATED_PROJECTION_DIGEST,"finalHashesSealed":FINAL_HASHES_SEALED,"directPrerequisites":["V23-P04-C02"],"executionPredecessor":"V23-P04-C09","fenceCount":98,"existingPathCount":len(context["existingPaths"]),"newPathCount":len(NEW_PATHS),"fencePathCount":len(fence["allowedCreateOrReplacePaths"])}
    source={"sourceReady":ready,"sourceStatus":"SOURCE_READY" if ready else "SOURCE_MISSING_PROVISIONAL","sourceRows":rows,"ownedFenceCounts":counts,"sourceSemanticsInspected":ready,"selectors":list(SELECTORS),"evidenceIDs":list(EVIDENCE_IDS)}
    contract={"schema":"V23P04C10EvidenceQualityContractV1","schemaVersion":1,"cardID":CARD,"title":TITLE,"status":"SEALED" if not provisional else "PROVISIONAL","provisional":provisional,"authority":auth,"semantics":semantic_scope(),"sourceProjection":source,"testSelectors":list(SELECTORS),"evidenceIDs":list(EVIDENCE_IDS),"statusFlags":FLAGS}
    receipt={"schema":"V23P04C10EvidenceQualityEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"status":"PROVISIONAL_SOURCE_LANES_PENDING" if provisional else "SEALED_SOURCE_READY","provisional":provisional,"authority":auth,"sourceProjection":source,"contractDigest":sha(canonical(contract)),"lifecycleCoverage":list(LIFECYCLE),"statusFlags":FLAGS}
    brand={"schema":"V23P04C10BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"title":TITLE,"provisional":provisional,"authority":auth,"semantics":semantic_scope(),"sourceProjection":source,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False,"statusFlags":FLAGS}
    payload={CONTRACT_PATH:pretty(contract), EVIDENCE_PATH:pretty(receipt), BRAND_PATH:pretty(brand)}
    manifest_rows=[]
    for row in owned_rows:
        if row["path"] in payload:
            data=payload[row["path"]]; manifest_rows.append({"path":row["path"],"status":"RENDERED","byteCount":len(data),"sha256":sha(data)})
        elif row["path"] == MANIFEST_PATH:
            manifest_rows.append({"path":row["path"],"status":"SELF_UNSEALED","byteCount":0,"sha256":"UNSEALED_SELF_REFERENCE"})
        else: manifest_rows.append(row)
    manifest={"schema":"V23P04C10ToolingManifestV1","schemaVersion":1,"cardID":CARD,"provisional":provisional,"finalHashesSealed":FINAL_HASHES_SEALED,"authority":auth,"pathFence":list(fence["allowedCreateOrReplacePaths"]),"existingPaths":list(context["existingPaths"]),"newPaths":list(NEW_PATHS),"existingPathCount":97,"newPathCount":16,"fencePathCount":113,"priorFenceCount":98,"priorOwnedPathCount":1547,"authorizedOverlapCount":3908,"unauthorizedOverlapCount":0,"allocationDigests":fence["priorFenceProof"]["allocationDigests"],"files":manifest_rows,"counts":counts,"generatedArtifacts":[{"path":p,"byteCount":len(b),"sha256":sha(b)} for p,b in sorted(payload.items())],"toolingPaths":[*SCRIPT_PATHS,*GENERATED_PATHS],"statusFlags":FLAGS}
    return {CONTRACT_PATH:contract,EVIDENCE_PATH:receipt,BRAND_PATH:brand,MANIFEST_PATH:manifest}
def write() -> None:
    for path, value in documents().items():
        target=ROOT/path; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(pretty(value))
def verify() -> None:
    authority()
    docs=documents()
    for path, expected in docs.items():
        target=ROOT/path
        if not target.is_file() or target.read_bytes() != pretty(expected): raise ValueError("generated artifact drift:"+path)
    for path in (*SCRIPT_PATHS, *GENERATED_PATHS):
        if not (ROOT/path).is_file(): raise ValueError("required tooling artifact missing:"+path)
    schema = json.loads((ROOT / SCHEMA_PATH).read_bytes(), object_pairs_hook=strict)
    if schema.get("properties", {}).get("cardID", {}).get("const") != CARD or schema.get("properties", {}).get("schemaVersion", {}).get("const") != 1:
        raise ValueError("C10 schema identity differs")
    rows, ready = source_rows()
    validate_source_semantics(rows, ready)
    blob="\n".join(canonical(v).decode("utf-8") for v in docs.values()).lower()
    for claim in ("automatic compliance judgment", "automatic pass", "opaque confidence", "ai diagnosis"):
        if claim in blob and "no_" not in blob: raise ValueError("prohibited claim:"+claim)
