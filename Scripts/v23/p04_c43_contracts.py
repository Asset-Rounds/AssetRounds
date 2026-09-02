#!/usr/bin/env python3
"""Deterministic provisional contract artifacts for V23-P04-C43."""
from __future__ import annotations
import hashlib, json, os, subprocess
from pathlib import Path
from typing import Any

ROOT=Path(__file__).resolve().parents[2]
CARD="V23-P04-C43"; ORDINAL=131
BASE="ff594be4b8ed4f6b73330775a3db8ea2d3ae739d"; BASE_TREE="aa84d07e63f50ccc23b5adadd4d690fd045f15d3"
COORDINATION_HEAD="3db4113cc825a60d335fda3b1ae6b6f22c4364cd"; COORDINATION_TREE="0e0bad30d736f38bd2d5886298b2d2dbc9593c55"; SEQUENCE=572
ALLOCATION_DIGEST="a3a73085ce30f95d7cff0530d132ac6e8bd45e5a4264e2daa9493574f95c6045"; PREREQUISITE_DIGEST="7ecb6877135b87cc18953a8c6e8a9a380e23739617b11e32b42b788df8fd2344"; CONTEXT_DIGEST="9f41da0b28cbb8e7e85a0a4ee017adc97cad387cf699f7e93f987901639f7458"; FENCE_DIGEST="f27bee7cb03540b9b2fcc5030f30596b497692f3d4ad97e070fcfa0c36c1c8f6"; TRANSITION_DIGEST="7657d6c7c16cd605daef3cf01eead666ddcf9340000027af602721c14fe68d71"; LEDGER_DIGEST="6b44edeba5b0f7e8924ec7fd3652dd53ac33f307989350cde0dc653ae05bb499"; PROJECTION_DIGEST="7904e9fb570c91d6f5a747488173f1b936c30aa6d67079f354967db4cb871b90"
EXISTING_PATHS=("FieldEvidenceApp/Application/Accountability/PartyAccountabilityCoordinatorV1.swift","FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift","FieldEvidenceApp/Features/Issues/IssueDetailView.swift","FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift")
NEW_PRODUCT_PATHS=("FieldEvidenceApp/Application/Accountability/SignoffEnrollmentCoordinatorV1.swift","FieldEvidenceApp/Domain/Accountability/SignoffEnrollmentContractsV1.swift","FieldEvidenceApp/Features/Accountability/SignoffEnrollmentView.swift","FieldEvidenceAppTests/Fixtures/V23/Accountability/V23P04C43SignoffEnrollmentCorpusV1.json","FieldEvidenceAppTests/V9_106SignoffEnrollmentTests.swift","FieldEvidenceAppUITests/V23_P04_C43SignoffEnrollmentUITests.swift")
SCRIPTS=("Scripts/v23/generate_p04_c43_contracts.py","Scripts/v23/p04_c43_contracts.py","Scripts/v23/verify_p04_c43_contracts.py"); SCHEMA="Scripts/v23/signoff-enrollment.schema.json"; CONTRACT="docs/design/v23/tooling/V23P04C43SignoffEnrollmentContractV1.json"; EVIDENCE="docs/design/v23/tooling/V23P04C43SignoffEnrollmentEvidenceReceiptV1.json"; BRAND="docs/design/v23/tooling/V23P04C43BrandImpactManifestV1.json"; MANIFEST="docs/design/v23/tooling/V23-P04-C43-tooling-manifest.json"
TOOLING_PATHS=(*SCRIPTS,SCHEMA,MANIFEST,BRAND,CONTRACT,EVIDENCE); PATH_FENCE=(*EXISTING_PATHS,*NEW_PRODUCT_PATHS,*TOOLING_PATHS); OWNED=frozenset(TOOLING_PATHS)
SELECTOR_ROWS=(("G01","V23-P04-C43-G01","GOLDEN"),("A01","V23-P04-C43-A01","ALTERNATE"),("H01","V23-P04-C43-H01","HOSTILE"),("I01","V23-P04-C43-I01","INTERRUPTION"),("R01","V23-P04-C43-R01","RECOVERY")); SELECTORS=tuple(x[1] for x in SELECTOR_ROWS)
FLAGS={x:False for x in ("native","hosted","physicalDevice","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalEvidence","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}; FINAL_HASHES_SEALED=False
PERSISTENCE_DECISION={"exactAction":"Record approval response","visibleWorkRootPathRequired":True,"typedPathAccessible":True,"deepLinkOnlyAcceptance":False,"optionalDrawnMark":True,"drawnMarkBiometric":False,"acknowledgementSnapshotV1BytePreserved":True,"acknowledgementSnapshotV1Migration":False,"identityClaim":False,"authorityClaim":False,"legalClaim":False,"nonrepudiationClaim":False,"verifiedOrFinalApprovalClaim":False,"newDurableFamilyCount":0,"newMigrationCount":0,"newModelCount":0,"newSchemaCount":0,"newStoreCount":0,"newWriterCount":0,"rootOrNetworkOrTelemetry":False}
CLAIMS={"identityProof":False,"authorityProof":False,"legalApproval":False,"nonrepudiation":False,"verifiedApproval":False,"finalApproval":False,"biometricMark":False,"deepLinkOnlyAcceptance":False,"hostedDependency":False,"nativeBuildVerified":False}
def pretty(v:Any)->bytes:return (json.dumps(v,sort_keys=True,indent=2,ensure_ascii=False)+"\n").encode()
def sha(v:bytes)->str:return hashlib.sha256(v).hexdigest()
def git(*a:str,cwd:Path=ROOT)->str:return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def read_json(p:str|Path)->Any:
 p=Path(p); p=p if p.is_absolute() else ROOT/p
 try:return json.loads(p.read_text(encoding="utf-8"),object_pairs_hook=lambda pairs:_unique(pairs))
 except Exception as e:raise ValueError(f"JSON {p.as_posix()}: {e}") from e
def _unique(pairs):
 d={}
 for k,v in pairs:
  if k in d:raise ValueError(f"duplicate key {k}")
  d[k]=v
 return d
def coordination_root()->Path:return Path(os.environ.get("V23_P04_C43_COORDINATION_ROOT",ROOT.parent/"AssetRounds-v23-coordination"))
def authority()->dict[str,Any]:
 root=coordination_root()
 if git("rev-parse","HEAD",cwd=root)!=COORDINATION_HEAD or git("show","-s","--format=%T",COORDINATION_HEAD,cwd=root)!=COORDINATION_TREE:raise ValueError("coordination pin drift")
 c=read_json(root/f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json"); f=read_json(root/f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json"); a=read_json(root/f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
 for d,k,v in ((c,"contextDigest",CONTEXT_DIGEST),(c,"ownerAuthorizedPathAllocationDigest",ALLOCATION_DIGEST),(c,"provisionalPrerequisiteDigest",PREREQUISITE_DIGEST),(f,"fenceDigest",FENCE_DIGEST),(a,"allocationDigest",ALLOCATION_DIGEST)):
  if d.get(k)!=v:raise ValueError(f"{k} drift")
 if tuple(f.get("allowedCreateOrReplacePaths",()))!=PATH_FENCE or tuple(a.get("exactOrderedPaths",()))!=PATH_FENCE:raise ValueError("exact18 fence drift")
 if f.get("priorFenceProof",{}).get("s10ReservedOverlapCount")!=1 or f.get("priorFenceProof",{}).get("s10ReservedOverlapPaths")!=[EXISTING_PATHS[2]]:raise ValueError("S10 reconciliation fence drift")
 if c.get("persistenceDecision")!=PERSISTENCE_DECISION:raise ValueError("persistence decision drift")
 return {"cardID":CARD,"ordinal":ORDINAL,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"appBaseHead":BASE,"appBaseTree":BASE_TREE,"sequence":SEQUENCE,"allocationDigest":ALLOCATION_DIGEST,"prerequisiteDigest":PREREQUISITE_DIGEST,"contextDigest":CONTEXT_DIGEST,"fenceDigest":FENCE_DIGEST,"transitionDigest":TRANSITION_DIGEST,"ledgerDigest":LEDGER_DIGEST,"projectionDigest":PROJECTION_DIGEST,"pathFence":list(PATH_FENCE)}
def rows():
 return ([{"path":p,"status":"SOURCE_PRESENT" if (ROOT/p).is_file() else "SOURCE_MISSING","sha256":sha((ROOT/p).read_bytes()) if (ROOT/p).is_file() else None} for p in (*EXISTING_PATHS,*NEW_PRODUCT_PATHS)],all((ROOT/p).is_file() for p in (*EXISTING_PATHS,*NEW_PRODUCT_PATHS)))
def documents()->dict[str,Any]:
 au=authority(); rows_,ready=rows(); scenarios=[{"id":a,"evidenceID":b,"kind":c} for a,b,c in SELECTOR_ROWS]; common={"schema":"V23P04C43SignoffEnrollmentToolingV1","cardID":CARD,"ordinal":ORDINAL,"authority":au,"sourceRows":rows_,"sourceReady":ready,"flags":FLAGS,"finalHashesSealed":False,"persistenceDecision":PERSISTENCE_DECISION,"claims":CLAIMS}
 schema={"$schema":"https://json-schema.org/draft/2020-12/schema","title":"V23 P04 C43 signoff enrollment","type":"object","required":["schema","cardID","authority","flags","finalHashesSealed"],"properties":{"schema":{"const":"V23P04C43SignoffEnrollmentToolingV1"},"cardID":{"const":CARD},"flags":{"type":"object","additionalProperties":{"const":False}},"finalHashesSealed":{"const":False}},"additionalProperties":True}
 contract={**common,"contract":"SignoffEnrollmentContractV1","exactAction":"Record approval response","scenarioEvidenceIDs":list(SELECTORS),"scenarioRows":scenarios,"requirements":{"workPath":["Work root","immutable completed detail","More","Record response","editor","history"],"deepLinkAloneNeverAccepted":True,"typedAccessiblePath":True,"optionalNonBiometricNonDurableMark":True,"acknowledgementSnapshotV1Untouched":True,"oneExistingWriter":True,"receiptFirstSameMutationIDExpectedRevisionRecovery":True,"prohibitedClaimsAllFalse":True,"s10IssueDetailViewReconciliationOnly":True}}
 evidence={**common,"receipt":"SignoffEnrollmentEvidenceReceiptV1","acceptanceCredit":False,"scenarios":scenarios,"requiredRecovery":{"sameMutationID":True,"expectedRevision":True,"receiptFirst":True}}
 brand={**common,"manifest":"BrandImpactManifestV1","requiresAcceptedS10_6Reconciliation":True,"issueDetailView":"RECONCILIATION_ONLY","uiAdoptionSkipped":True,"uiAcceptanceCredit":False}
 manifest={**common,"manifest":"V23-P04-C43-tooling-manifest","pathFence":list(PATH_FENCE),"counts":{"fencePathCount":18,"existingPathCount":4,"newPathCount":14,"productTestUIFixturePathCount":6,"toolingPathCount":8,"missingPathCount":0,"unownedChangedPathCount":0,"s10ReservedOverlapCount":1,"durableFamilyCount":0,"writerDeltaCount":0}}
 return {SCHEMA:schema,CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
