#!/usr/bin/env python3
"""Fail-closed route-registry tooling for V23-P03-C34."""
from __future__ import annotations
import ast, hashlib, json, os, re, subprocess, sys
from pathlib import Path
from typing import Any
os.environ["PYTHONDONTWRITEBYTECODE"]="1"; sys.dont_write_bytecode=True
CARD="V23-P03-C34"; BASE_HEAD="fc21e6dbc57e3c0b72fbaaad00a5b4116d3e60f7"; BASE_TREE="229edd42ff97a76786a16fc15905a65610006fb4"
COORDINATION_HEAD="d9f09107e9f48cee63fb08cc69b0874e4cdd94e3"; COORDINATION_TREE="f57e28f951d1e78b2e08a75523171da69978a70b"; CAS_SEQUENCE=347
CONTEXT_DIGEST="8add3078bd1abace390df25dab4bbdd8c9943e966c22f6b1f0624ea29f8a57db"; FENCE_DIGEST="0e54c0aae93e45c906fc6870cf7ccfec05557223382ca5cd95776c793af69be4"; PREREQUISITE_DIGEST="842e58295f9b31ebc59a36edcdd8a5b1fd08dfaddd4c5d818713cd4d96fbefc5"; TRANSITION_DIGEST="5f77d824f31a3fffdffe655520250ddca89db0d57b8dc9d85f4be87b94f6e9b0"; LEDGER_DIGEST="f6b74fdaeb299e925a7863f646e2331d6d927db0c4252969587822f48ab850c8"; PROJECTION_DIGEST="9a9c3506571f01cbb4f98027e1974d73b0917aa36d64630ded0cf4b26a7b1e34"
HYDRATION_PATH=Path(r"C:\AssetRounds-v23-coordination\contexts\V23-P03-C34-attempt-1\BootstrapPathFenceV1.json")
SCHEMA_PATH="Scripts/v23/route-registry.schema.json"; CONTRACT_PATH="docs/design/v23/tooling/V23P03C34RouteRegistryContractV1.json"; EVIDENCE_PATH="docs/design/v23/tooling/V23P03C34RouteRegistryEvidenceReceiptV1.json"; BRAND_PATH="docs/design/v23/tooling/V23P03C34BrandImpactManifestV1.json"; MANIFEST_PATH="docs/design/v23/tooling/V23-P03-C34-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p03_c34_contracts.py","Scripts/v23/generate_p03_c34_contracts.py","Scripts/v23/verify_p03_c34_contracts.py")
IMPLEMENTATION_PATHS=("FieldEvidenceApp/Domain/Navigation/RouteRegistryContractsV1.swift","FieldEvidenceApp/Domain/Navigation/SceneNavigationContractsV1.swift","FieldEvidenceApp/Application/Navigation/RouteCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Navigation/SceneNavigationStateAdapterV1.swift","FieldEvidenceAppTests/V9_59RouteRegistryRestorationTests.swift","FieldEvidenceAppTests/Fixtures/V22/Navigation/V22P03C34RouteRegistryCorpusV1.json")
LIFECYCLE_BOUNDARY_PATHS=("FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift","FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift","FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift","FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift","FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift","FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift","FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift","FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift","FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift","FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift","FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift","FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift","FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift")
GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH); FLAGS={k:False for k in ("native","hosted","physical","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalAcceptance","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}; EVIDENCE_IDS=tuple(f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01"))
def _hydration()->dict[str,Any]:
    if not HYDRATION_PATH.is_file(): raise ValueError("C34 hydration absent")
    d=json.loads(HYDRATION_PATH.read_text(encoding="utf-8"))
    if d.get("cardID")!=CARD or d.get("fenceDigest")!=FENCE_DIGEST: raise ValueError("C34 hydration authority differs")
    return d
_h=_hydration(); EXISTING_PATHS=tuple(_h["existingPaths"]); NEW_PATHS=tuple(_h["newPaths"]); PATH_FENCE=EXISTING_PATHS+NEW_PATHS
def canonical(v:Any)->bytes:return json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()+b"\n"
def pretty(v:Any)->bytes:return (json.dumps(v,sort_keys=True,indent=2,ensure_ascii=False)+"\n").encode()
def _text(root:Path,p:str)->str:
    q=root/p
    if not q.is_file():raise ValueError("source path absent:"+p)
    return q.read_text(encoding="utf-8")
def _tokens(t:str, xs:tuple[str,...], label:str)->None:
    m=[x for x in xs if x not in t]
    if m:raise ValueError(label+" missing:"+",".join(m))
def _sources(root:Path)->None:
    contracts,scene,coordinator,adapter,tests,fixture=(_text(root,p) for p in IMPLEMENTATION_PATHS)
    _tokens(contracts,("AppRootV1","frozenOrder","frozenOrder.count == 4","RouteRegistryV1","PackageSurfaceManifestV1","PackageSurfaceRouteV1","duplicatePackage","duplicateRoute","startsAutomaticWork == false","canonicalMutationCount: 0"),"C34 route registry")
    _tokens(scene,("SceneNavigationSnapshotV1","SceneNavigationLifecycleDispositionV1","tolerantDecode","eraseClears","workspaceTruth = false","backupIncluded = false","journalIncluded = false"),"C34 snapshot lifecycle")
    _tokens(coordinator,("RouteCoordinatorV1","restore","startupMaintenanceTarget","incompleteMutationRecoveryTarget","explicitIngressTarget","sceneSnapshot","RouteRestorationReceiptV1"),"C34 route precedence")
    _tokens(scene,("RouteConformanceReceiptV1",),"C34 route conformance receipt")
    _tokens(adapter,("SceneNavigationStateAdapterV1","loadAndReconcile","save","discarded","erase","snapshot"),"C34 device snapshot adapter")
    _tokens(tests,("testExactlyFourFrozenRootsAndNoAutomaticWork","testPackageRejectsAuthorityEscalationAndDuplicateRoute","testTolerantStateDecodeDiscardsFutureAndCorruptBytesAndEraseClears","testSnapshotRoundTripIsDeviceOperationalOnly","testAllEvidenceReceiptsAreZeroWriteAndExactRetryIsIdempotent","XCTAssertThrowsError"),"C34 G/A/H/I/R")
    _tokens(fixture,("V23-P03-C34","G01","A01","H01","I01","R01"),"C34 corpus")
    lifecycle=tuple(_text(root,p) for p in LIFECYCLE_BOUNDARY_PATHS)
    _tokens(lifecycle[6],("C34SceneNavigationCompatibilityBoundaryV1","SceneNavigationLifecycleDispositionV1","DEVICE_OPERATIONAL_NONCANONICAL","workspaceTruth","backupIncluded","journalIncluded","tolerantDecode","eraseClears"),"C34 compatibility exclusion")
    for text in lifecycle[:6]+lifecycle[7:10]+lifecycle[10:11]+lifecycle[12:13]:
        _tokens(text,("C34SceneNavigationCompatibilityBoundaryV1",),"C34 noncanonical exclusion owner")
    for text in (lifecycle[11],lifecycle[13]):
        _tokens(text,("C34SceneNavigationCompatibilityBoundaryV1","clearSceneRouteState","SceneNavigationStateAdapterV1","adapter.erase()"),"C34 erase adapter owner")
    for bad in (r"\b(?:URLSession|EventKit|EKEvent|RRULE|cron|WebSocket)\b",r"\b(?:fifthRoot|FifthRoot)\b"):
        if re.search(bad,"\n".join((contracts,scene,coordinator,adapter))):raise ValueError("C34 forbidden:"+bad)
def assert_scaffold(root:Path)->None:
    if (len(EXISTING_PATHS),len(NEW_PATHS),len(PATH_FENCE))!=(202,14,216):raise ValueError("C34 fence cardinality")
    if NEW_PATHS!=(*IMPLEMENTATION_PATHS,*SCRIPT_PATHS,*GENERATED_PATHS):raise ValueError("C34 hydration new paths differ")
    if len(set(PATH_FENCE))!=216 or any(FLAGS.values()):raise ValueError("C34 fence/flags")
    for p in SCRIPT_PATHS:ast.parse(_text(root,p),filename=p)
    _sources(root)
def authority()->dict[str,Any]:return {"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":CAS_SEQUENCE,"contextDigest":CONTEXT_DIGEST,"pathFenceDigest":FENCE_DIGEST,"provisionalPrerequisiteDigest":PREREQUISITE_DIGEST,"hydrationTransitionDigest":TRANSITION_DIGEST,"coordinationLedgerDigest":LEDGER_DIGEST,"coordinationProjectionDigest":PROJECTION_DIGEST,"directPrerequisites":["V23-P03-C36"],"priorFenceProof":{"fenceCount":80,"priorOwnedPathCount":1314,"authorizedOverlapCount":3820,"unauthorizedOverlapCount":0}}
def all_outputs(root:Path)->dict[str,bytes]:
    assert_scaffold(root); common={"cardID":CARD,"authority":authority(),"statusFlags":FLAGS,"evidenceIDs":list(EVIDENCE_IDS)}
    out={CONTRACT_PATH:pretty({"schema":"V23P03C34RouteRegistryContractV1","schemaVersion":1,**common,"semantics":{"typedRoutes":True,"exactPrecedence":True,"tolerantSnapshotRestore":True,"fifthRootRejected":True,"packageUniqueness":True,"c36Boundary":True}}),EVIDENCE_PATH:pretty({"schema":"V23P03C34RouteRegistryEvidenceReceiptV1","schemaVersion":1,**common,"nativeCompileRan":False,"hostedDispatchEnabled":False,"physicalLockedState":"REQUIRED_PENDING_OWNER"}),BRAND_PATH:pretty({"schema":"V23P03C34BrandImpactManifestV1","schemaVersion":1,**common,"uiSurfaceDelta":False,"brandSurfaceDelta":True})}
    files=[{"path":p,"byteCount":len((out[p] if p in out else (root/p).read_bytes())),"sha256":hashlib.sha256(out[p] if p in out else (root/p).read_bytes()).hexdigest()} for p in PATH_FENCE if p!=MANIFEST_PATH]
    out[MANIFEST_PATH]=pretty({"schema":"V23P03C34ToolingManifestV1","schemaVersion":1,**common,"fencePathCount":216,"existingPathCount":202,"newPathCount":14,"s10ReservationOverlapCount":0,"files":files});return out
