from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True; sys.path.insert(0,str(Path(__file__).resolve().parent))
import p04_c33_contracts as c
TOP={"cardID","expected","ordinal","persistence","scenarios","schema","schemaVersion","selectors","statusFlags","synthetic"}
SCENARIOS=(("G01","GOLDEN"),("A01","ALTERNATE"),("H01","HOSTILE"),("I01","INTERRUPTION"),("R01","RECOVERY"))
def read(p):return json.loads((c.ROOT/p).read_bytes())
def require(ok,msg):
 if not ok:raise ValueError(msg)
def text(p):return (c.ROOT/p).read_text(encoding="utf-8")
def function_body(source,name):
 m=re.search(r"(?ms)^\s*func\s+"+re.escape(name)+r"\s*\([^\n]*\).*?(?=^\s*func\s+|^\s*(?:private\s+)?(?:final\s+)?class\s+|\Z)",source)
 require(m is not None,"missing parsed test "+name); return m.group(0)
def validate_corpus(corpus):
 expected={"asBuiltAndVariationEvidenceRequired":True,"explicitStartRequired":True,"finalizedHistoryImmutable":True,"manualFallbackAvailable":True,"oneBoundedResult":True,"optionalPlanAndScan":True,"reportRebuildDeterministic":True,"retryIsIdempotent":True}
 require(corpus["expected"]==expected,"expected semantics")
 expected_covers={"G01":("readiness","explicit_start","ordered_execution","as_built","variation","validated_closeout","report_ready"),"A01":("manual_no_plan_fallback","optional_plan_unavailable","optional_scan_unavailable","blocked","stale","partial"),"H01":("wrong_revision","stale_revision","duplicate_id","invalid_transition","invalid_order","malformed_input","unbounded_input","unicode","identity","no_partial_success"),"I01":("cancellation","interruption","effect_before_receipt","relaunch","resume"),"R01":("retry","replay","receipt_recovery","same_authorized_receipt_or_effect","no_effect","immutable_finalized_history","deterministic_report_rebuild")}
 for row in corpus["scenarios"]: require(tuple(row)==("covers","id","kind") and tuple(row["covers"])==expected_covers[row["id"]],"scenario coverage "+str(row.get("id")))
def validate_final_api(source,coordinator,view,test):
 # Structural requirements are checked against the actual declarations/branches, not marker claims.
 for fragment in ("let basis: InstallationBasisSnapshotV1","basis.activityID == envelope.activityID","basisReference == (try InstallationBasisReferenceV1(basis))","let nextCloseoutAction = closeoutAction", "let reportReadiness: InstallationReportReadinessV1", "reportReady: reportReadiness == .readyForExistingRenderer", "closeoutRecorded: context.envelope.installationCloseout != nil") : require(fragment in coordinator,"API structure "+fragment)
 asbuilt=re.search(r"(?ms)case \.recordAsBuilt:.*?(?=\s*case \.recordVariation:)",coordinator); require(asbuilt is not None and "to == from" in asbuilt.group(0) and "installationCloseout == context.envelope.installationCloseout" in asbuilt.group(0),"recordAsBuilt separate from closeout")
 closeout=re.search(r"(?ms)case \.closeout:.*?(?=\n\s*}\n\s*}\n\s*private func readinessBlockers)",coordinator); require(closeout is not None,"closeout branch")
 for stage in (".recordFieldComplete",".submitForReview",".finalizeRecordedCloseout"): require(stage in coordinator,"closeout stage "+stage)
 require("context.envelope.state == .finalized" in coordinator and "context.envelope.installationCloseout != nil" in coordinator,"finalized report gate")
 variation=re.search(r"(?ms)private func validateVariation.*?(?=\n\s*@discardableResult)",coordinator); require(variation is not None,"variation validator")
 for fragment in ("successorReference == (try InstallationBasisReferenceV1(basis))","basis.predecessorBasisSHA256 == predecessorReference.basisSHA256","variation.successorBasisSHA256 == basis.basisSHA256","variation.mutationID == mutation.mutationID"): require(fragment in variation.group(0),"variation binding "+fragment)
 for fragment in ("providerID == Self.providerID","consumerID == Self.consumerID","capabilityID == Self.capabilityID","manual.workspaceID != envelope.workspaceID"): require(fragment in source,"capability receipt/workspace binding "+fragment)
 require("isExactUnreceiptedEffect" in source and "durableActivityContractReceipt" in source,"exact unreceipted-effect recovery")
 require(view.count("XCTSkip(")==0,"view defers by cleanup, not a UI skip")
 g=function_body(test,"testV23P04C33G01ReadinessStartOrderedExecutionAsBuiltVariationCloseoutAndReport"); h=function_body(test,"testV23P04C33H01WrongStaleDuplicateOrderMalformedBoundsUnicodeAndIdentityFailClosed"); i=function_body(test,"testV23P04C33I01CancellationInterruptionEffectBeforeReceiptAndRelaunchResumeAreBounded"); r=function_body(test,"testV23P04C33R01RetryReplayReceiptRecoveryImmutableHistoryAndDeterministicReportRebuild")
 require("ActivityStateMachineV2.permits" in g and "nextTaskID" in g,"G real state coverage")
 require(h.count("XCTAssertThrowsError")>=4 and "differentRelease" in h,"H real fail-closed coverage")
 require("await harness.workflow.execute" in i and "await harness.workflow.recover" in i and "effectCount" in i,"I execute/recover harness")
 require(r.count("await harness.workflow.recover")>=2 and "divergentStart" in r and "unboundVariation" in r,"R replay and variation recovery harness")
def main():
 a=argparse.ArgumentParser();a.add_argument("--complete",action="store_true");a.add_argument("--json",action="store_true");z=a.parse_args();fails=[];ready=False;counts={};flags=False
 try:
  require(c.git("rev-parse",c.BASE+"^{tree}")==c.BTREE,"app base tree")
  corpus=read(c.FIXTURE); require(set(corpus)==TOP,"corpus keys"); require((corpus["cardID"],corpus["ordinal"],corpus["schema"],corpus["schemaVersion"],corpus["synthetic"])==(c.CARD,c.ORDINAL,"V23P04C33InstallationWorkflowCorpusV1",1,True),"corpus identity")
  require(tuple((x.get("id"),x.get("kind")) for x in corpus["scenarios"])==SCENARIOS,"five scenarios"); require(tuple((x.get("id"),x.get("selector"),x.get("tier")) for x in corpus["selectors"])==tuple((i,f"V23-P04-C33-{i}",k) for i,k in SCENARIOS),"five selectors")
  require(corpus["persistence"]=={"durableFamily":"NONE","persistentSchemaVersion":36,"recordsSchemaVersion":35},"persistence"); validate_corpus(corpus)
  require(corpus["statusFlags"]==c.FLAGS,"status flags"); require(all(v is False for v in c.FLAGS.values()),"false flags"); flags=True
  r,ready=c.rows(); require(ready or not z.complete,"source lanes pending")
  if ready:
   source="\n".join(text(p) for p in c.PRODUCT if p!=c.FIXTURE); coordinator=text("FieldEvidenceApp/Application/Activities/InstallationWorkflowCoordinatorV1.swift"); view=text("FieldEvidenceApp/Features/Activities/InstallationWorkflowView.swift"); tests=text(c.TEST)
   validate_final_api(source,coordinator,view,tests)
   for forbidden in ("parallelKernelAdded = true","writerOrBackendAdded = true","persistentFamilyAdded = true","reportRendererAdded = true"): require(forbidden not in source,"forbidden "+forbidden)
   require(text(c.UI).count("XCTSkip(")==1,"one no-launch skip")
  docs=c.documents()
  for p,v in docs.items():require((c.ROOT/p).is_file() and (c.ROOT/p).read_bytes()==c.pretty(v),"artifact drift "+p)
  counts=c.counts(); require(counts["fencePathCount"]==15 and counts["changedPathCount"]==15,"all fifteen changed"); require(counts["unownedChangedPathCount"]==0,"unowned changed")
 except Exception as e:fails.append("contracts:"+str(e))
 out={"cardID":c.CARD,"result":"FAIL_STATIC" if fails else "PASS_STATIC_PROVISIONAL","sourceReady":ready,"finalHashesSealed":False,"flagsAllFalse":flags,"failures":fails,"counts":counts,"fencePathCount":15,"existingPathCount":2,"newPathCount":13,"selectors":list(c.SELECTORS)}
 print(json.dumps(out,sort_keys=True,indent=2) if z.json else out["result"]);raise SystemExit(bool(fails))
if __name__=="__main__":main()
