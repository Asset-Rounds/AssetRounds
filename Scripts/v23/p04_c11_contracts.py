#!/usr/bin/env python3
"""Fail-closed static evidence contracts for V23-P04-C11."""
from __future__ import annotations
import hashlib,json,os,re,subprocess
from pathlib import Path
from typing import Any
os.environ["PYTHONDONTWRITEBYTECODE"]="1"
ROOT=Path(__file__).resolve().parents[2]; COORD=Path(r"C:\AssetRounds-v23-coordination")
CARD="V23-P04-C11"; TITLE="Fast Survey Inbox with explicit typed promotion and frozen snippet provenance"; APP_BASE_HEAD="6951989fde21babfe4b67bec6329de749a116dd2"; CONTEXT_DIGEST="970aefe2d793a497f697c37d78c881f80522761c3f26467ccec5c6ccde35267b"; FENCE_DIGEST="adda61090ea7969ae0399c5cab79f6e8a729de4806e8c2a8f38f5b888bc6a08c"; COORDINATION_HEAD="a94fdc778c9436e15bdc363281db21ce064cc06d"; COORDINATION_TREE="5d7d7661ed6f6e193ba26bc926dacb3493c70ad9"; HYDRATION_TRANSITION_DIGEST="7d41cff3e448b9d7c10bf0db4d3a1923433ba887030d7473b1c6b33a5a1151eb"; HYDRATED_LEDGER_DIGEST="2119c7ab220d6c801517cd3ececa0ac319b0a84b7ec26b4c57a44bea41b12eed"; HYDRATED_PROJECTION_DIGEST="79d8991574411652b50c84f2676c92601d0e15aa109edbaafc70daed959765fe"; REGISTER_ORDINAL=99; FINAL_HASHES_SEALED=True
SCHEMA_PATH="Scripts/v23/fast-survey-inbox.schema.json"; CONTRACT_PATH="docs/design/v23/tooling/V23P04C11FastSurveyInboxContractV1.json"; EVIDENCE_PATH="docs/design/v23/tooling/V23P04C11FastSurveyInboxEvidenceReceiptV1.json"; BRAND_PATH="docs/design/v23/tooling/V23P04C11BrandImpactManifestV1.json"; MANIFEST_PATH="docs/design/v23/tooling/V23-P04-C11-tooling-manifest.json"; SCRIPT_PATHS=("Scripts/v23/p04_c11_contracts.py","Scripts/v23/generate_p04_c11_contracts.py","Scripts/v23/verify_p04_c11_contracts.py"); GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH)
IMPLEMENTATION_PATHS=("FieldEvidenceApp/Application/FastSurveyInbox/FastSurveyInboxCoordinatorV1.swift","FieldEvidenceApp/Domain/FastSurveyInbox/FastSurveyInboxContractsV1.swift","FieldEvidenceApp/Domain/Models/FastSurveyInboxPersistenceModelsV1.swift","FieldEvidenceApp/Features/CheckRunner/FastSurveyInboxView.swift","FieldEvidenceApp/Infrastructure/Persistence/FastSurveyInboxLifecycleAdapterV1.swift","FieldEvidenceAppTests/Fixtures/V22/FastSurveyInbox/V22P04C11FastSurveyInboxCorpusV1.json","FieldEvidenceAppTests/V9_75FastSurveyInboxTests.swift","FieldEvidenceAppUITests/V23_P04_C11FastSurveyInboxUITests.swift")
NEW_PATHS=(MANIFEST_PATH,BRAND_PATH,CONTRACT_PATH,EVIDENCE_PATH,*IMPLEMENTATION_PATHS,SCHEMA_PATH,"Scripts/v23/generate_p04_c11_contracts.py","Scripts/v23/p04_c11_contracts.py","Scripts/v23/verify_p04_c11_contracts.py")
SELECTORS=("testV23P04C11G01RapidOfflineCaptureReviewAndTypedPromotionPreserveOriginalProvenance","testV23P04C11A01UnassignedItemAndEditedSnippetRemainExplicitWithoutChangingFrozenRecords","testV23P04C11H01DuplicatePromotionStaleDestinationMissingContentAndSnippetSubstitutionFailClosed","testV23P04C11I01InterruptedCaptureOrPromotionPreservesBytesAndRecoverableInbox","testV23P04C11R01RestoreReplayRebuildsInboxPromotionLinksSnippetVersionsAndUnresolvedItemsWithoutDoubleInsertion"); EVIDENCE_IDS=tuple(f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")); LIFECYCLE=("MIGRATION","BACKUP","REPLACE_RESTORE","DELETE","ERASE","EXPORT","REPORT","SEARCH","REBUILD","JOURNAL","REPLAY")
FLAGS={k:False for k in ("activation","native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")}
def strict(pairs):
 out={}
 for k,v in pairs:
  if k in out: raise ValueError("duplicate JSON key:"+k)
  out[k]=v
 return out
def canonical(v:Any)->bytes:return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
def pretty(v:Any)->bytes:return (json.dumps(v,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n").encode()
def sha(v:bytes)->str:return hashlib.sha256(v).hexdigest()
def load(p:str)->dict[str,Any]:return json.loads((COORD/p).read_bytes(),object_pairs_hook=strict)
def sealed(v:dict[str,Any],key:str)->str:return sha((json.dumps({k:x for k,x in v.items() if k!=key},sort_keys=True,separators=(",",":"))+"\n").encode())
def run(*args:str,cwd=ROOT)->str:return subprocess.run(["git",*args],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def authority():
 c=load("contexts/V23-P04-C11-attempt-1/BootstrapCardContextV1.json"); f=load("contexts/V23-P04-C11-attempt-1/BootstrapPathFenceV1.json"); t=load("transitions/000430-V23-P04-C11-attempt-1-NOT_STARTED-to-HYDRATING.json"); l=load("state/BootstrapExecutionLedgerEnvelopeV1.json"); p=load("projections/ActiveWorkSetProjectionV1.json")
 expected={"existing":"681ff2df60cefc1b6e0657b46e7c3f81fea8c660af068810bb7879971ad58c88","new":"4e86a54276acdf9692e1181e0b5b8ed1a5d0abbc16c1dc0ab675e60cb0d9357b","combined":"f6173358cd4bb2a35099c3f059f8653ba896de47a51abe792fdbafcca85e0a51"}; proof=f.get("priorFenceProof",{})
 if c.get("cardID")!=CARD or c.get("contextDigest")!=CONTEXT_DIGEST or sealed(c,"contextDigest")!=CONTEXT_DIGEST or f.get("cardID")!=CARD or f.get("fenceDigest")!=FENCE_DIGEST or sealed(f,"fenceDigest")!=FENCE_DIGEST:raise ValueError("C11 context/fence identity differs")
 if tuple(c.get("newPaths",()))!=NEW_PATHS or tuple(f.get("allowedCreateOrReplacePaths",()))!=tuple(c.get("existingPaths",()))+NEW_PATHS:raise ValueError("C11 path fence drift")
 if len(c.get("existingPaths",()))!=97 or len(NEW_PATHS)!=16 or len(f.get("allowedCreateOrReplacePaths",()))!=113 or proof.get("fenceCount")!=99 or proof.get("priorOwnedPathCount")!=1563 or proof.get("missingPathCount")!=0 or proof.get("duplicatePathCount")!=0 or proof.get("authorizedOverlapCount")!=4005 or proof.get("unauthorizedOverlapCount")!=0 or proof.get("allocationDigests")!=expected:raise ValueError("C11 prior fence proof differs")
 if set(f["allowedCreateOrReplacePaths"])&set(f["activeS10ReservedPaths"]):raise ValueError("C11 S10 overlap differs")
 if c.get("repository",{}).get("appBaseHead")!=APP_BASE_HEAD or c.get("registerOrdinal")!=REGISTER_ORDINAL or c.get("directPrerequisites")!=["V23-P04-C02"] or proof.get("executionPredecessorCardID")!="V23-P04-C10":raise ValueError("C11 base/prerequisite differs")
 if run("rev-parse","HEAD",cwd=COORD)!=COORDINATION_HEAD or run("rev-parse","origin/main",cwd=COORD)!=COORDINATION_HEAD or run("rev-parse","HEAD^{tree}",cwd=COORD)!=COORDINATION_TREE or l.get("casSequence")!=430 or l.get("ledgerDigest")!=HYDRATED_LEDGER_DIGEST or t.get("transitionDigest")!=HYDRATION_TRANSITION_DIGEST or t.get("newLedgerDigest")!=HYDRATED_LEDGER_DIGEST or p.get("projectionDigest")!=HYDRATED_PROJECTION_DIGEST:raise ValueError("C11 hydration authority differs")
 return c,f
def source_rows():
 rows=[]
 for path in IMPLEMENTATION_PATHS:
  x=ROOT/path;data=x.read_bytes() if x.is_file() else b"";rows.append({"path":path,"status":"SOURCE_PRESENT" if x.is_file() else "SOURCE_MISSING","byteCount":len(data),"sha256":sha(data) if x.is_file() else None})
 return rows,all(x["status"]=="SOURCE_PRESENT" for x in rows)
def fence_rows():
 _,f=authority(); rows=[]
 for path in f["allowedCreateOrReplacePaths"]:
  x=ROOT/path;data=x.read_bytes() if x.is_file() else b"";rows.append({"path":path,"status":"PRESENT" if x.is_file() else "MISSING","byteCount":len(data),"sha256":sha(data) if x.is_file() else None})
 def names(*args):return {x.replace("\\","/") for x in run(*args).splitlines() if x}
 # New fence paths are the candidate allocation even before a generator has
 # materialized its four documents; otherwise --apply would alter its own
 # accounting.  The base/worktree union still catches every foreign path.
 changed=names("diff","--name-only",APP_BASE_HEAD,"HEAD")|names("diff","--name-only","HEAD")|names("diff","--name-only","--cached")|names("ls-files","--others","--exclude-standard")|set(NEW_PATHS);owned=set(f["allowedCreateOrReplacePaths"])
 return rows,{"changedPathCount":len(changed&owned),"missingPathCount":sum(x["status"]=="MISSING" for x in rows),"unownedChangedPathCount":len(changed-owned),"s10ReservationOverlapCount":len(owned&set(f["activeS10ReservedPaths"]))}
def validate_source_semantics(rows,ready):
 if not ready:return
 support=("FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift","FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift","FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift","FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift","FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift","FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift","FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift","FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift","FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift","FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift","FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift","FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift","FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift")
 body={x:(ROOT/x).read_text(encoding="utf-8") for x in (*IMPLEMENTATION_PATHS,*support)}; alltext="\n".join(body.values());missing=[x for x in ("FastSurveyInboxSchemaV1","CaptureInboxItemV1","CapturePromotionV1","CapturePromotionDestinationV1","CapturePromotionDestinationResolvingV1","SnippetV1","SnippetInsertionV1","SnippetInsertionHistoryRowV1","FastSurveyInboxMutationPayloadV1","FastSurveyInboxQueryTargetV1","FastSurveyInboxQueryResultV1","PersistentSchemaV48","WorkspaceWriterV1","WorkspaceWriterAdapterV1","MutationJournalStoreV1","MutationReceiptV1","LocalChangeJournal","FastSurveyInboxLifecycleAdapterV1","XCTSkip",*LIFECYCLE,*SELECTORS) if x.lower() not in alltext.lower()]
 if missing:raise ValueError("C11 model/lifecycle/selector coverage missing:"+",".join(missing))
 coordinator,adapter,model,tests,ui=(body[IMPLEMENTATION_PATHS[x]] for x in (0,4,2,6,7))
 if not re.search(r"expected(?:Revision|_revision).*mutation(?:ID|_id)|mutation(?:ID|_id).*expected(?:Revision|_revision)",coordinator,re.S|re.I):raise ValueError("C11 writer revision/mutation fence missing")
 for path,text,need in ((IMPLEMENTATION_PATHS[0],coordinator,("WorkspaceWriterV1","receipt","submitOrRecover")),(IMPLEMENTATION_PATHS[4],adapter,("func replay","func search","func replaceRestore","func erase","func report","func export","func migrate")),(IMPLEMENTATION_PATHS[2],model,("CaptureInboxItem","CapturePromotion","Snippet","init(restoring")),(IMPLEMENTATION_PATHS[7],ui,("XCTSkip","no acceptance credit"))):
  absent=[x for x in need if x.lower() not in text.lower()]
  if absent:raise ValueError("C11 scoped semantics missing:"+path+":"+",".join(absent))
 # Require concrete enum-case patterns rather than a fixture variable name.
 # The production result contract deliberately exposes inbox, promotion, and
 # snippet cases; tests must match an actual closed case, not inspect a fake store.
 closed_cases=r"(?:\.inboxItems\s*\(|\.inboxItem\s*\(|\.promotion\s*\(|\.snippet\s*\(|\.snippets\s*\()"
 if len(re.findall(r"\.lifecycle\.(?:replaceRestore|report|search|replay|delete|erase)\s*\(",tests))<6 or not re.search(closed_cases,tests):raise ValueError("C11 production lifecycle/query result assertions missing")
 if any(x in alltext for x in ("C11FastSurveyInboxStore","C11RealPersistenceProbe","FakeFastSurveyInboxState","FastSurveyInboxInMemoryStore")):raise ValueError("C11 independent persistence probe")
 writer_adapter=body[support[4]]
 if not re.search(r"promotion\.validate\(source:\s*source,\s*promotedItem:\s*promotedItem,\s*resolver:\s*resolver\)",writer_adapter,re.S) or "modelContext.insert(itemRow)" not in writer_adapter or "modelContext.insert(promotionRow)" not in writer_adapter:raise ValueError("C11 incumbent destination resolver atomic promotion validation missing")
 if not all(x in alltext for x in ("SnippetInsertionHistoryRowV1", "insertSnippet", "textIsFrozen = true", "laterSnippetChangesAffectInsertion = false")):raise ValueError("C11 durable frozen insertion coverage missing")
 catalog=body[support[1]]; sync_catalog=body[support[2]]; factory=body[support[3]]; journal=body[support[7]]
 if not all(x in catalog for x in ("V23_P04_C11", "CaptureInboxItemRowV1", "CapturePromotionRowV1", "SnippetRowV1", "SnippetInsertionHistoryRowV1", "FastSurveyInboxMutationReceiptRowV1", "cloneOrForkDisposition")) or "makeV48Container" not in factory or "fastSurveyInboxRowsAreEmpty" not in factory or "syncDisposition" not in journal or "rebuildIntegrationProjection" not in journal:raise ValueError("C11 factory/sync/rebuild/journal/replay/clone/fork lifecycle coverage missing")
 if not all(x in sync_catalog for x in ("v48PersistentModelNames", "AdditionalSpec", "SnippetInsertionHistoryRowV1", "FastSurveyInboxMutationReceiptRowV1")):raise ValueError("C11 V48 AdditionalSpec registration missing")
 if not all(x in adapter for x in ("case let .snippetInsertion(id):", "case let .snippetInsertions(target):", "return .snippetInsertion", "return .snippetInsertions")):raise ValueError("C11 snippet insertion search rebuild coverage missing")
 recovery=body[support[-2]]; journal_store=body[support[-1]]
 if not re.search(r"func recoverBeforeWriterActivation\(\) throws \{.*?validateFastSurveyInboxRecoveryParity\(\)",recovery,re.S) or not re.search(r"func recoverFastSurveyInboxEffectsBeforeWriterActivation\(\) throws \{\s*try recoverBeforeWriterActivation\(\)",recovery,re.S) or "FastSurveyInboxMutationReceiptRecoveryPolicyV1.validateRecovered(" not in recovery:raise ValueError("C11 canonical recovery parity activation missing")
 if not all(x in journal_store for x in ("func fastSurveyInboxRecoveryPairs()", "FetchDescriptor<MutationReceiptRow>", "FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>", "commandsByKey.removeValue(forKey: key)", "typedReceipt.recoveryState == .receiptCommitted", "postImageIdentities == targets", "typedReceipt.semanticSHA256s")):raise ValueError("C11 generic/typed receipt bijection or postimage semantics missing")
 i01=tests.partition("func testV23P04C11I01InterruptedCaptureOrPromotionPreservesBytesAndRecoverableInbox")[2].partition("func testV23P04C11R01")[0]
 if i01.count("MutationJournalFaultBoundaryV1.allCases") < 2 or ".putInboxItem(item)" not in i01 or ".promote(promotion, promoted)" not in i01 or i01.count("recoverBeforeWriterActivation()") < 2:raise ValueError("C11 I01 capture/promotion interruption matrix lacks both all-boundary lanes")
 if re.search(r"\b(ai|opaque confidence|automatic pass|automatic fail|automatic completeness)\b",alltext,re.I):raise ValueError("C11 prohibited automatic/AI claim")
 if not all(x in alltext.lower() for x in ("unpromoted","complete","frozen")):raise ValueError("C11 unpromoted/snippet provenance missing")
def semantics():return {"persistentContractMode":"NEW_SCHEMA_VERSION","persistentContractSchema":"FastSurveyInboxSchemaV1","namedContracts":["CaptureInboxItemV1","CapturePromotionV1","CapturePromotionDestinationV1","CapturePromotionDestinationResolvingV1","SnippetV1","SnippetInsertionV1"],"persistentRows":["CaptureInboxItemRowV1","CapturePromotionRowV1","SnippetRowV1","SnippetInsertionHistoryRowV1","FastSurveyInboxMutationReceiptRowV1"],"activeModelCount":158,"canonicalOwner":"V23-P04-C11_SOLE_FAST_SURVEY_INBOX_WRITER_OWNER","oneCanonicalWriter":True,"canonicalWriterRequirements":["EXPECTED_REVISION","MUTATION_ID","ONE_CANONICAL_WRITER_TRANSACTION","DURABLE_RECEIPT","SEMANTIC_REVERSAL_OR_SUPERSESSION","EFFECT_BEFORE_RECEIPT_RECOVERY"],"workspaceBoundPromotionDestination":True,"incumbentDestinationResolverValidatedAtomically":True,"durableFrozenSnippetInsertion":True,"recoveryParityRequiresGenericTypedBijection":True,"mutationPayloadCases":["putInboxItem","promote","putSnippet","insertSnippet"],"queryResultCases":["inboxItem","inboxItems","promotion","snippet","snippets","snippetInsertion","snippetInsertions","notFound"],"lifecycleCoverage":[*LIFECYCLE,"FACTORY","SYNC","CLONE","FORK"],"unpromotedNeverLeaks":True,"snippetHistoryFrozen":True,"containedUI":"POST_S10_6_ADOPTION_SKIP_NO_CREDIT","uiAcceptanceCredit":False,"statusFlags":FLAGS}
def documents():
 c,f=authority();sources,ready=source_rows();owned,counts=fence_rows();prov=not(FINAL_HASHES_SEALED and ready);auth={"cardID":CARD,"title":TITLE,"registerOrdinal":REGISTER_ORDINAL,"appBaseHead":APP_BASE_HEAD,"contextDigest":CONTEXT_DIGEST,"pathFenceDigest":FENCE_DIGEST,"taskStartCoordinationHead":c["coordination"]["coordinationHead"],"taskStartCoordinationCASSequence":c["coordination"]["ledgerCASSequence"],"taskStartLedgerDigest":c["coordination"]["ledgerDigest"],"taskStartProjectionDigest":c["coordination"]["projectionDigest"],"hydrationCoordinationHead":COORDINATION_HEAD,"hydrationCoordinationTree":COORDINATION_TREE,"hydrationCASSequence":430,"hydrationTransitionDigest":HYDRATION_TRANSITION_DIGEST,"hydrationLedgerDigest":HYDRATED_LEDGER_DIGEST,"hydrationProjectionDigest":HYDRATED_PROJECTION_DIGEST,"finalHashesSealed":FINAL_HASHES_SEALED,"directPrerequisites":["V23-P04-C02"],"executionPredecessor":"V23-P04-C10","fenceCount":99,"existingPathCount":97,"newPathCount":16,"fencePathCount":113};source={"sourceReady":ready,"sourceStatus":"SOURCE_READY" if ready else "SOURCE_MISSING_PROVISIONAL","sourceRows":sources,"ownedFenceCounts":counts,"sourceSemanticsInspected":ready,"selectors":list(SELECTORS),"evidenceIDs":list(EVIDENCE_IDS)}
 contract={"schema":"V23P04C11FastSurveyInboxContractV1","schemaVersion":1,"cardID":CARD,"title":TITLE,"status":"SEALED" if not prov else "PROVISIONAL","provisional":prov,"authority":auth,"semantics":semantics(),"sourceProjection":source,"testSelectors":list(SELECTORS),"evidenceIDs":list(EVIDENCE_IDS),"statusFlags":FLAGS};receipt={"schema":"V23P04C11FastSurveyInboxEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"status":"SEALED_SOURCE_READY" if not prov else "PROVISIONAL_SOURCE_LANES_PENDING","provisional":prov,"authority":auth,"sourceProjection":source,"contractDigest":sha(canonical(contract)),"lifecycleCoverage":[*LIFECYCLE,"FACTORY","SYNC","CLONE","FORK"],"statusFlags":FLAGS};brand={"schema":"V23P04C11BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"title":TITLE,"provisional":prov,"authority":auth,"semantics":semantics(),"sourceProjection":source,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False,"statusFlags":FLAGS};payload={CONTRACT_PATH:pretty(contract),EVIDENCE_PATH:pretty(receipt),BRAND_PATH:pretty(brand)};files=[]
 for row in owned:
  if row["path"] in payload:files.append({"path":row["path"],"status":"RENDERED","byteCount":len(payload[row["path"]]),"sha256":sha(payload[row["path"]])})
  elif row["path"]==MANIFEST_PATH:files.append({"path":row["path"],"status":"SELF_UNSEALED","byteCount":0,"sha256":"UNSEALED_SELF_REFERENCE"})
  else:files.append(row)
 manifest={"schema":"V23P04C11ToolingManifestV1","schemaVersion":1,"cardID":CARD,"provisional":prov,"finalHashesSealed":FINAL_HASHES_SEALED,"authority":auth,"pathFence":list(f["allowedCreateOrReplacePaths"]),"existingPaths":list(c["existingPaths"]),"newPaths":list(NEW_PATHS),"existingPathCount":97,"newPathCount":16,"fencePathCount":113,"priorFenceCount":99,"priorOwnedPathCount":1563,"authorizedOverlapCount":4005,"unauthorizedOverlapCount":0,"allocationDigests":f["priorFenceProof"]["allocationDigests"],"files":files,"counts":counts,"generatedArtifacts":[{"path":p,"byteCount":len(x),"sha256":sha(x)} for p,x in sorted(payload.items())],"toolingPaths":[*SCRIPT_PATHS,*GENERATED_PATHS],"statusFlags":FLAGS}
 return {CONTRACT_PATH:contract,EVIDENCE_PATH:receipt,BRAND_PATH:brand,MANIFEST_PATH:manifest}
def _schema_validate(v,rule,root,where="$"):
 if "$ref" in rule:return _schema_validate(v,root["$defs"][rule["$ref"].rsplit("/",1)[1]],root,where)
 if "oneOf" in rule:
  ok=0
  for x in rule["oneOf"]:
   try:_schema_validate(v,x,root,where);ok+=1
   except ValueError:pass
  if ok!=1:raise ValueError(where+": schema oneOf mismatch")
  return
 if "const" in rule and v!=rule["const"]:raise ValueError(where+": schema const mismatch")
 if "enum" in rule and v not in rule["enum"]:raise ValueError(where+": schema enum mismatch")
 kinds={"object":dict,"array":list,"string":str,"boolean":bool,"integer":int}
 if "type" in rule and (not isinstance(v,kinds[rule["type"]]) or (rule["type"]=="integer" and isinstance(v,bool))):raise ValueError(where+": schema type mismatch")
 if isinstance(v,dict):
  if set(rule.get("required",()))-set(v):raise ValueError(where+": schema required mismatch")
  props=rule.get("properties",{})
  if rule.get("additionalProperties") is False and set(v)-set(props):raise ValueError(where+": schema extra field")
  for k,x in v.items():
   if k in props:_schema_validate(x,props[k],root,where+"."+k)
 if isinstance(v,list):
  if len(v)<rule.get("minItems",0) or ("maxItems" in rule and len(v)>rule["maxItems"]):raise ValueError(where+": schema item count mismatch")
  if isinstance(rule.get("items"),dict):
   for i,x in enumerate(v):_schema_validate(x,rule["items"],root,where+"["+str(i)+"]")
def validate_generated_documents(values):
 schema=json.loads((ROOT/SCHEMA_PATH).read_bytes(),object_pairs_hook=strict)
 for path,value in values.items():_schema_validate(value,schema,schema,path)
