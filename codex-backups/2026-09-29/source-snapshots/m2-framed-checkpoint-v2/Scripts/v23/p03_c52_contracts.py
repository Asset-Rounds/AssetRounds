#!/usr/bin/env python3
"""Fail-closed portable service-request tooling for V23-P03-C52."""
from __future__ import annotations
import hashlib,json,os,re,subprocess,sys
from pathlib import Path
from typing import Any
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
CARD="V23-P03-C52"; REGISTER_ORDINAL=83; BASE_HEAD="837fe50cc71f030618236aafe7896ac424f10437"; BASE_TREE="965d8633d5bbd4f4f7d26941085e9a9e428185af"
COORDINATION_HEAD="a570041e3d8aaac2d6c361058fc6e3ef339a8d00"; COORDINATION_TREE="9df30630cb993834b3792ce6ec5d09e715b39d5d"; CAS_SEQUENCE=351
CONTEXT_DIGEST="bdc93a2b8154732b8d60e41642a4456e66a251a26257447a3575853bc16e4de6"; FENCE_DIGEST="c8757de12d29beea737ab668dd2a04523cc28931135cc5925b5b7887060f25cb"; PREREQUISITE_DIGEST="8b948592897d21c263fe2553b61a422a3a91845faacdf82e9e0558af26f9975d"; TRANSITION_DIGEST="afd460b4cba8aaf350b01601c7af0394c5311f8e1dfed8b317dd8c0a6040667e"; LEDGER_DIGEST="830e2ce7e3739b83d79fb1abe8f33acaefc7e7103a5b814af4d4e5300d1a75e7"; PROJECTION_DIGEST="449e99ba1dfde75d3ae2c8e1aae97772f35a593404ffe1ee8eaa1209cd46e4ba"
DOSSIER_SHA256="ae29ad5b4f773a4b3a66cf2b5b9b4c16a5407d9183c8c93242bda97b6dea7565"; DOSSIER_BYTES=7215; REGISTER_SHA256="4b641a5e76345d64358d813a111be0e064e8485259e87a7428a17e6704221ef4"; REGISTER_BYTES=317; REGISTER_SECTION_SHA256="3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"; REGISTER_SECTION_BYTES=44217
HYDRATION=Path(r"C:\AssetRounds-v23-coordination\contexts\V23-P03-C52-attempt-1\BootstrapPathFenceV1.json")
SCHEMA_PATH="Scripts/v23/portable-service-request.schema.json"; CONTRACT_PATH="docs/design/v23/tooling/V23P03C52PortableServiceRequestContractV1.json"; EVIDENCE_PATH="docs/design/v23/tooling/V23P03C52PortableServiceRequestEvidenceReceiptV1.json"; BRAND_PATH="docs/design/v23/tooling/V23P03C52BrandImpactManifestV1.json"; MANIFEST_PATH="docs/design/v23/tooling/V23-P03-C52-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p03_c52_contracts.py","Scripts/v23/generate_p03_c52_contracts.py","Scripts/v23/verify_p03_c52_contracts.py"); IMPLEMENTATION_PATHS=("FieldEvidenceApp/Domain/ServiceRequests/PortableServiceRequestContractsV1.swift","FieldEvidenceApp/Domain/Models/ServiceRequestPersistenceModelsV1.swift","FieldEvidenceApp/Application/ServiceRequests/ServiceRequestCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/ServiceRequests/ServiceRequestLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_60PortableServiceRequestTests.swift","FieldEvidenceAppTests/Fixtures/V22/ServiceRequests/V22P03C52PortableServiceRequestCorpusV1.json"); GENERATED_PATHS=(CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH)
SUPPORT_PATHS=("FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift","FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift","FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift","FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift","FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift","FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift")
BACKUP_PATHS=("FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift","FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift")
STORE_RECEIPT_PATH="FieldEvidenceApp/Infrastructure/ReviewExchange/PortableExchangeSessionStoreV2.swift"
FLAGS={k:False for k in("native","hosted","physical","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalAcceptance","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}; EVIDENCE_IDS=tuple(f"{CARD}-{x}" for x in("G01","A01","H01","I01","R01")); PRIOR_FENCES={"V23-P03-C46":"466e730797b35fa438c4ab60cbf9c347372680bf504d0257db4b7e952577235b","V23-P03-C48":"1abe6ceebd594bee60bdec5fd19b8758c18e585dc7dd35a5757e500b75673027"}
def canonical(v:Any)->bytes:return json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()+b"\n"
def pretty(v:Any)->bytes:return (json.dumps(v,sort_keys=True,indent=2,ensure_ascii=False)+"\n").encode()
def _text(root:Path,p:str)->str:
 q=root/p
 if not q.is_file():raise ValueError("source path absent:"+p)
 return q.read_text(encoding="utf-8")
def _hydration()->dict[str,Any]:
 if not HYDRATION.is_file():raise ValueError("C52 hydration absent")
 d=json.loads(HYDRATION.read_text(encoding="utf-8"))
 if d.get("cardID")!=CARD or d.get("fenceDigest")!=FENCE_DIGEST:raise ValueError("C52 hydration authority differs")
 return d
_H=_hydration(); EXISTING_PATHS=tuple(_H["existingPaths"]); NEW_PATHS=tuple(_H["newPaths"]); PATH_FENCE=EXISTING_PATHS+NEW_PATHS
def _tokens(t:str,xs:tuple[str,...],label:str)->None:
 m=[x for x in xs if x not in t]
 if m:raise ValueError(label+" missing:"+",".join(m))
def _support(root:Path)->None:
 for p,n in zip(SUPPORT_PATHS,("C52ServiceRequestRuntimePortBoundaryV1","C52ServiceRequestLocalJobPortBoundaryV1","C52ServiceRequestCheckRunnerContractBoundaryV1","C52ServiceRequestCheckRunnerCoordinatorBoundaryV1","C52ServiceRequestLocalJobRunnerBoundaryV1","C52ServiceRequestLocalJobModelBoundaryV1")):_tokens(_text(root,p),(n,),"C52 support anchor")
def _swift_declaration(text:str,name:str)->str:
 match=re.search(r"\b(?:struct|enum|actor|final\s+class|class)\s+"+re.escape(name)+r"\b",text)
 if not match:raise ValueError("C52 declaration absent:"+name)
 tail=text[match.start():]
 next_declaration=re.search(r"\n(?:struct|enum|actor|final\s+class|class)\s+[A-Za-z_]",tail[1:])
 return tail if not next_declaration else tail[:next_declaration.start()+1]
def _strict_decoder(text:str,name:str,label:str)->None:
 body=_swift_declaration(text,name)
 if "init(from decoder" not in body or not any(x in body for x in ("requireExact(decoder","requireAllowed(decoder")) or not any(x in body for x in ("try validate()","let rebuilt","try Self(")):
  raise ValueError("C52 strict validating decoder absent:"+label)
def _assert_record_capability_containment(text:str)->None:
 body=_swift_declaration(text,"PortableServiceRequestCodecV1")
 start=body.find("static func assertRecordBytesExcludeCapability")
 if start<0:raise ValueError("C52 record capability containment absent")
 record=body[start:body.find("static func",start+1) if body.find("static func",start+1)>=0 else len(body)]
 _tokens(record,("record.validate()","ServiceRequestCanonicalCodecV1.data(record)","capability.rawBytes","base64EncodedString"),"C52 record capability containment")
 if "decodeSubmission" in record or "assertSubmissionBytesExcludeCapability" in record:raise ValueError("C52 record capability containment decodes submission")
def _backup_sources(root:Path)->None:
 contracts,imports,exports=(_text(root,p) for p in BACKUP_PATHS)
 _tokens(contracts,("C52ServiceRequestBoundary_V4BackupContracts","C52ServiceRequestBackupEnrollmentV1","serviceRequests","serviceRequestDispositionEvents","serviceRequestWorkLinkEvents","validateC49WorkResources"),"C52 domain backup")
 _tokens(imports,("C49WorkResourceBackupImportBoundaryV1","validateC49WorkResources","C52ServiceRequestBackupImportBoundaryV1","C52ServiceRequestBoundary_V4BackupImportContracts","C52ServiceRequestBackupEnrollmentV1.validate(records:"),"C52 backup import")
 _tokens(exports,("C52ServiceRequestBackupExportBoundaryV1","workResources: workResources","serviceRequests: serviceRequests","serviceRequestDispositionEvents: serviceRequestDispositionEvents","serviceRequestWorkLinkEvents: serviceRequestWorkLinkEvents"),"C52 backup export")
 for symbol in ("C52ServiceRequestBoundary_V4BackupContracts","C52ServiceRequestBackupEnrollmentV1","C52ServiceRequestBackupImportBoundaryV1","C52ServiceRequestBoundary_V4BackupImportContracts","C52ServiceRequestBackupExportBoundaryV1"):
  if sum(text.count(symbol) for text in (contracts,imports,exports))<1:raise ValueError("C52 backup boundary missing:"+symbol)
def _store_receipt_sources(root:Path)->None:
 store=_text(root,STORE_RECEIPT_PATH)
 for name in ("PortableExchangeServiceRequestImportReceiptV2","PortableExchangeServiceRequestReconciliationReceiptV2"):_strict_decoder(store,name,"store "+name)
def _sources(root:Path)->None:
 c,m,co,a,t,f=(_text(root,p) for p in IMPLEMENTATION_PATHS)
 _tokens(c,("PortableServiceRequestProtocolReleaseV1","ServiceRequestSubmissionCapabilityV1","ServiceRequestCapabilityProofV1","ServiceRequestRecordV1","ServiceRequestWorkLinkEventV1","SecRandomCopyBytes","AssetRounds.ServiceRequestCapabilityProof.V1","HMAC","constantTime","ACCEPT_AS_NEW","ACCEPT_AND_LINK_DUPLICATE","DECLINE_WITH_REASON","RECORD_HISTORY_ONLY","KEEP_QUARANTINED","DISCARD_UNIMPORTED","OPEN_UNTRIAGED","OPEN_ACCEPTED","HANDLED_BY_LINKED_WORK","DECLINED","CLOSED_NO_WORK","SUPERSEDED"),"C52 contracts")
 for name in ("ServiceRequestImportPlanV1","ServiceRequestImportReceiptV1"):_strict_decoder(c,name,"domain "+name)
 _tokens(m,("ServiceRequestRecord","Persistent","immutable"),"C52 persistence")
 _tokens(co,("WorkspaceExpectedRevisionV1","expectedRevision: WorkspaceExpectedRevisionV1","expectedRevision.workspaceID","expectedRevision.workspaceRevision","ServiceRequestWorkConversionPlanV1","ServiceRequestWorkLinkEventV1","projectCandidates","durableServiceRequestReceipt","commitServiceRequest","zeroWrite","previewWritesWorkspace = false","duplicateCandidatesAreSuggestionOnly = true","automaticWorkCreation = false",".acceptAndLinkDuplicate: return .openAccepted","@MainActor","ServiceRequestLifecycleAdapterV1"),"C52 coordinator")
 _strict_decoder(co,"ServiceRequestWorkConversionReceiptV1","coordinator work receipt")
 _strict_decoder(co,"ServiceRequestStatusArtifactHandoffV1","coordinator status artifact")
 _tokens(a,("arserviceinvite","arservicesubmission","cleartext","backup","restore","clone","fork","journal","replay","erase","quarantine","actor ServiceRequestLifecycleAdapterV1","PortableExchangeSessionStorePortV2 & PortableExchangeServiceRequestStorePortV2","async throws","prepareSubmission","finalizeSubmission","recoverSubmission"),"C52 lifecycle")
 _assert_record_capability_containment(a)
 _tokens(t,("testV23P03C52G01","testV23P03C52A01","testV23P03C52H01","testV23P03C52I01","testV23P03C52R01","ServiceRequestCoordinatorV1(","ServiceRequestLifecycleAdapterV1("),"C52 G/A/H/I/R real wiring")
 _tokens(f,("V23-P03-C52","G01","A01","H01","I01","R01"),"C52 corpus")
 _backup_sources(root)
 _store_receipt_sources(root)
 for bad in (r"\b(?:URLSession|WebSocket|CRM|telemetry|marketing|dispatch|SLA|automaticWork|autoMerge)\b",r"\b(?:rawCapability.*(?:report|log|search|diagnostic)|capability.*submission)\b"):
  if re.search(bad,"\n".join((c,m,co,a)),re.I):raise ValueError("C52 forbidden:"+bad)
def assert_scaffold(root:Path)->None:
 if (len(EXISTING_PATHS),len(NEW_PATHS),len(PATH_FENCE))!=(253,14,267):raise ValueError("C52 fence cardinality")
 if NEW_PATHS!=(*IMPLEMENTATION_PATHS,*SCRIPT_PATHS,SCHEMA_PATH,*GENERATED_PATHS):raise ValueError("C52 hydration new paths differ")
 if len(set(PATH_FENCE))!=267 or any(FLAGS.values()):raise ValueError("C52 fence or flags")
 _tokens(_text(root,SCHEMA_PATH),(CARD,"V23P03C52PortableServiceRequestContractV1"),"C52 schema");_support(root)
def authority()->dict[str,Any]:return {"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":CAS_SEQUENCE,"contextDigest":CONTEXT_DIGEST,"pathFenceDigest":FENCE_DIGEST,"provisionalPrerequisiteDigest":PREREQUISITE_DIGEST,"hydrationTransitionDigest":TRANSITION_DIGEST,"coordinationLedgerDigest":LEDGER_DIGEST,"coordinationProjectionDigest":PROJECTION_DIGEST,"dossierSHA256":DOSSIER_SHA256,"dossierUTF8Length":DOSSIER_BYTES,"inheritedV21PayloadPresent":False,"registerOrdinal":REGISTER_ORDINAL,"registerRowSHA256":REGISTER_SHA256,"registerRowUTF8Length":REGISTER_BYTES,"registerSectionSHA256":REGISTER_SECTION_SHA256,"registerSectionUTF8Length":REGISTER_SECTION_BYTES,"directPrerequisiteFences":PRIOR_FENCES}
def all_outputs(root:Path)->dict[str,bytes]:
 assert_scaffold(root);_sources(root); common={"cardID":CARD,"authority":authority(),"evidenceIDs":list(EVIDENCE_IDS),"statusFlags":FLAGS,"priorPrerequisiteProof":{"cards":list(PRIOR_FENCES),"fences":PRIOR_FENCES,"liveResealRequired":False},"s10ReservationOverlapCount":0,"s10ReservedPathCount":86}
 out={CONTRACT_PATH:pretty({"schema":"V23P03C52PortableServiceRequestContractV1","schemaVersion":1,**common,"semantics":{"capabilityBytes":32,"exactHMACTranscript":True,"cleartextFormats":[".arserviceinvite",".arservicesubmission"],"duplicateSuggestionsOnly":True,"exactlyOnceWorkConversion":True,"noAutomaticWork":True,"workspaceExpectedRevisionPropagates":True,"acceptAndLinkDuplicateState":"OPEN_ACCEPTED","actorLifecyclePort":True,"recordCapabilityContainmentWithoutSubmissionDecode":True,"strictPlanReceiptStatusAndStoreDecoders":True,"uniqueDomainBackupBoundaries":True,"backupExportC52ArrayCount":3,"c49WorkResourcesRemainSeparate":True,"v960InstantiatesCoordinatorAndLifecycle":True}}),EVIDENCE_PATH:pretty({"schema":"V23P03C52PortableServiceRequestEvidenceReceiptV1","schemaVersion":1,**common,"cases":list(EVIDENCE_IDS),"journey":"FJ08","nativeCompileRan":False,"hostedDispatchEnabled":False,"physicalLockedState":"REQUIRED_PENDING_OWNER"}),BRAND_PATH:pretty({"schema":"V23P03C52BrandImpactManifestV1","schemaVersion":1,**common,"uiSurfaceDelta":True,"brandSurfaceDelta":True,"networkDeliveryMarketingMeasurementFlow":False,"customerIdentityVerified":False})}
 files=[{"path":p,"byteCount":len(out[p] if p in out else (root/p).read_bytes()),"sha256":hashlib.sha256(out[p] if p in out else (root/p).read_bytes()).hexdigest()} for p in PATH_FENCE if p!=MANIFEST_PATH];out[MANIFEST_PATH]=pretty({"schema":"V23P03C52ToolingManifestV1","schemaVersion":1,**common,"existingPathCount":253,"newPathCount":14,"fencePathCount":267,"files":files});return out
