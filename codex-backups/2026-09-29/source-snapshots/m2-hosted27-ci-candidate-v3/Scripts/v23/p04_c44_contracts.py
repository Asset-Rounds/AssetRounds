#!/usr/bin/env python3
"""Deterministic provisional C44 local parts-and-stock tooling."""
from __future__ import annotations
import hashlib,json,os,subprocess
from pathlib import Path
from typing import Any
ROOT=Path(__file__).resolve().parents[2];CARD="V23-P04-C44";ORDINAL=132;BASE="a0fae03c252c233b97adcd52ba68bbcbbacc7d71";BASE_TREE="78a96d36331222ae44e1ae6fc9d9fa530a698942";COORDINATION_HEAD="dab3f0316ec3831fa966ae1aa6bd55496b2e4f0d";COORDINATION_TREE="2b82979d0e90b02183e59dd1a0efb43d62b3e0f9";SEQUENCE=576
ALLOCATION_DIGEST="ab50ea3f853bd2b5de8835d9d0b1e1fcd7568f06775b9c340c632a0ee1b56374";PREREQUISITE_DIGEST="636f81e1b36b813898010f279137fbf6931e160a577e2d179879534c51f3537a";CONTEXT_DIGEST="933025ecbe299c3cc857ce38e92c5e155bd5c8e1361fbe8ea871f213af6aa14f";FENCE_DIGEST="27567c0d8cfc71832f7d56f784f8c14dc7cea96b8cf7f24f0f2b4cb571e0f5b9";TRANSITION_DIGEST="3b51166e1985f5a2a7936c46a8676fbbb6e644de620f5934f3abbae65e207b42";LEDGER_DIGEST="f2f8a7d3e7a0a456bd79ddc8f2b94f735e2839611e06cc3837da6573383af94f";PROJECTION_DIGEST="71bd8597cecd1ce69c085a2d82bd1ab07702c05554609a547a782b7866242060"
EXISTING_PATHS=("FieldEvidenceApp/Domain/PartsStock/PartsStockContractsV1.swift","FieldEvidenceApp/Application/PartsStock/PartsStockCoordinatorV1.swift","FieldEvidenceApp/Application/WorkResources/ManualWorkResourceWorkflowCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift")
NEW_PRODUCT_PATHS=("FieldEvidenceApp/Domain/PartsStock/PartsStockWorkflowContractsV1.swift","FieldEvidenceApp/Application/PartsStock/PartsStockWorkflowCoordinatorV1.swift","FieldEvidenceApp/Features/PartsStock/PartsStockWorkflowView.swift","FieldEvidenceAppTests/V9_107PartsStockWorkflowTests.swift","FieldEvidenceAppTests/Fixtures/V23/PartsStock/V23P04C44PartsStockWorkflowCorpusV1.json","FieldEvidenceAppUITests/V23_P04_C44PartsStockWorkflowUITests.swift")
SCRIPTS=("Scripts/v23/p04_c44_contracts.py","Scripts/v23/generate_p04_c44_contracts.py","Scripts/v23/verify_p04_c44_contracts.py");SCHEMA="Scripts/v23/parts-stock-workflow.schema.json";CONTRACT="docs/design/v23/tooling/V23P04C44PartsStockWorkflowContractV1.json";EVIDENCE="docs/design/v23/tooling/V23P04C44PartsStockWorkflowEvidenceReceiptV1.json";BRAND="docs/design/v23/tooling/V23P04C44BrandImpactManifestV1.json";MANIFEST="docs/design/v23/tooling/V23-P04-C44-tooling-manifest.json";TOOLING_PATHS=(*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST);PATH_FENCE=(*EXISTING_PATHS,*NEW_PRODUCT_PATHS,*TOOLING_PATHS)
SELECTOR_ROWS=(("G01","V23-P04-C44-G01","GOLDEN"),("A01","V23-P04-C44-A01","ALTERNATE"),("H01","V23-P04-C44-H01","HOSTILE"),("I01","V23-P04-C44-I01","INTERRUPTION"),("R01","V23-P04-C44-R01","RECOVERY"));SELECTORS=tuple(x[1] for x in SELECTOR_ROWS);FINAL_HASHES_SEALED=False
FLAGS={x:False for x in("native","hosted","physicalDevice","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalEvidence","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}
POLICY={"definesLocalPartCatalogV1":True,"definesLocalStockFeaturePolicyV1":True,"workLocalCatalog":True,"scanAndManualLookup":True,"typingMaterialLineDecrementsStock":False,"explicitUseAtomicMutationOnly":True,"returnOnlyEligibleUseWithOutstandingQuantityAndDestination":True,"standaloneUnboundReturn":False,"rejectPartialConcurrentDoubleReturnOverflow":True,"countAdjustTransferUseReturnArchive":True,"lowStockAttention":True,"exactCSVImportExport":True,"draftsAndFeatureDisablePreservation":True,"customerReportsExposeBalancesOrInternalLocations":False,"customerSafeReportsReviewedMaterialSnapshotsOnly":True,"reusesStockBalanceProjectionV1":True,"reusesStockReturnAgainstUseReceiptV1":True,"newMigration":False,"newModel":False,"newRoot":False,"newSchema":False,"newStore":False,"newWriter":False,"rootOrNetworkOrTelemetry":False}
def pretty(v:Any)->bytes:return (json.dumps(v,sort_keys=True,indent=2,ensure_ascii=False)+"\n").encode()
def sha(v:bytes)->str:return hashlib.sha256(v).hexdigest()
def git(*a,cwd=ROOT):return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def _unique(pairs):
 d={}
 for k,v in pairs:
  if k in d:raise ValueError("duplicate JSON key: "+k)
  d[k]=v
 return d
def read_json(p):
 p=Path(p);p=p if p.is_absolute() else ROOT/p
 try:return json.loads(p.read_text(encoding="utf-8"),object_pairs_hook=_unique)
 except Exception as e:raise ValueError(f"JSON {p.as_posix()}: {e}") from e
def coordination_root():return Path(os.environ.get("V23_P04_C44_COORDINATION_ROOT",ROOT.parent/"AssetRounds-v23-coordination"))
def authority():
 r=coordination_root()
 if git("rev-parse","HEAD",cwd=r)!=COORDINATION_HEAD or git("show","-s","--format=%T",COORDINATION_HEAD,cwd=r)!=COORDINATION_TREE:raise ValueError("coordination pin drift")
 x=read_json(r/f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json");f=read_json(r/f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json");a=read_json(r/f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
 for d,k,v in ((x,"contextDigest",CONTEXT_DIGEST),(x,"ownerAuthorizedPathAllocationDigest",ALLOCATION_DIGEST),(x,"provisionalPrerequisiteDigest",PREREQUISITE_DIGEST),(f,"fenceDigest",FENCE_DIGEST),(a,"allocationDigest",ALLOCATION_DIGEST)):
  if d.get(k)!=v:raise ValueError(k+" drift")
 if tuple(f.get("allowedCreateOrReplacePaths",()))!=PATH_FENCE or tuple(a.get("exactOrderedPaths",()))!=PATH_FENCE:raise ValueError("exact18 fence drift")
 if x.get("persistenceDecision")!=POLICY:raise ValueError("policy drift")
 return {"cardID":CARD,"ordinal":ORDINAL,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"appBaseHead":BASE,"appBaseTree":BASE_TREE,"sequence":SEQUENCE,"allocationDigest":ALLOCATION_DIGEST,"prerequisiteDigest":PREREQUISITE_DIGEST,"contextDigest":CONTEXT_DIGEST,"fenceDigest":FENCE_DIGEST,"transitionDigest":TRANSITION_DIGEST,"ledgerDigest":LEDGER_DIGEST,"projectionDigest":PROJECTION_DIGEST,"pathFence":list(PATH_FENCE)}
def rows():
 ps=(*EXISTING_PATHS,*NEW_PRODUCT_PATHS);return ([{"path":p,"status":"SOURCE_PRESENT" if (ROOT/p).is_file() else "SOURCE_MISSING","sha256":sha((ROOT/p).read_bytes()) if (ROOT/p).is_file() else None} for p in ps],all((ROOT/p).is_file() for p in ps))
def documents():
 au=authority();rs,ready=rows();common={"schema":"V23P04C44PartsStockWorkflowToolingV1","cardID":CARD,"ordinal":ORDINAL,"authority":au,"sourceRows":rs,"sourceReady":ready,"flags":FLAGS,"finalHashesSealed":False,"policy":POLICY};scenarios=[{"id":a,"evidenceID":b,"kind":k} for a,b,k in SELECTOR_ROWS]
 schema={"$schema":"https://json-schema.org/draft/2020-12/schema","title":"V23 P04 C44 local parts stock workflow","type":"object","required":["schema","cardID","authority","flags","finalHashesSealed"],"properties":{"schema":{"const":"V23P04C44PartsStockWorkflowToolingV1"},"cardID":{"const":CARD},"flags":{"type":"object","additionalProperties":{"const":False}},"finalHashesSealed":{"const":False}},"additionalProperties":True}
 contract={**common,"contract":"PartsStockWorkflowContractV1","catalogPolicy":"LOCAL_PART_CATALOG_V1","featurePolicy":"LocalStockFeaturePolicyV1","scenarioEvidenceIDs":list(SELECTORS),"scenarioRows":scenarios,"requirements":{"zeroWriteLookupAndTyping":True,"explicitUseAtomic":True,"returnFrontierOutstandingDestination":True,"rejectStandaloneTornConcurrentDoubleExcessOverflow":True,"countAdjustTransferArchive":True,"lowStockUnknownNotZero":True,"csvExactResumableReceiptFirst":True,"featureDisablePreservesDrafts":True,"customerReportRedaction":True,"oneExistingWriter":True,"noNewPersistenceFamilies":True,"uiAdoptionDeferred":True}}
 evidence={**common,"receipt":"PartsStockWorkflowEvidenceReceiptV1","acceptanceCredit":False,"scenarios":scenarios,"csv":{"deterministic":True,"resumable":True,"perRowReceiptsFirst":True,"prematureComplete":False}}
 brand={**common,"manifest":"BrandImpactManifestV1","requiresAcceptedS10_6Reconciliation":True,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False}
 manifest={**common,"manifest":"V23-P04-C44-tooling-manifest","pathFence":list(PATH_FENCE),"counts":{"fencePathCount":18,"existingPathCount":4,"newPathCount":14,"productTestUIFixturePathCount":6,"toolingPathCount":8,"missingPathCount":0,"unownedChangedPathCount":0,"s10ReservationOverlapCount":0,"durableFamilyCount":0,"writerDeltaCount":0}}
 return {SCHEMA:schema,CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
