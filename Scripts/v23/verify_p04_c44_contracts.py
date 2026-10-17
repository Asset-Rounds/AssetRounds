#!/usr/bin/env python3
"""Verify C44 provisional tooling, source seams, and exact path fence."""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c44_contracts as c
def req(ok,msg,fs):
 if not ok:fs.append(msg)
def tokens(text,label,values,fs):
 for value in values:req(value in text,label+' missing structural token: '+value,fs)
def _current_hosted_unit_fixture_result():
 """The fixed current app-hosted UNIT Source question, never historical UI."""
 import p04_c42_contracts as reader
 failures=[];rows=[];guard_executed=False
 selectors=["FieldEvidenceAppTests/"+c.CURRENT_HOSTED_UNIT_CLASS+"/"+name
            for name in c.CURRENT_HOSTED_UNIT_METHODS]
 try:
  inputs=c.current_hosted_unit_sources();rows=inputs["rows"]
  def block(path,declaration,label):return reader.current_source_block(inputs,path,declaration,label)
  def need(value,expressions,label):reader.current_source_require(value,expressions,label,failures)
  def ordered(value,expressions,label):reader.current_source_order(value,expressions,label,failures)
  def active_literal(value,expression,label):
   # Bind this exact feature-local literal/call to active code at its real
   # source offset. Comments, quoted code and inactive branches cannot supply it.
   for match in re.finditer(re.escape(expression),value["source"]):
    expected=inputs["generator"]._mask_swift_noncode(match.group())
    if expected==value["code"][match.start():match.end()]:return
   failures.append(label+" missing active literal/call: "+expression)
  path=c.CURRENT_HOSTED_UNIT_PATH
  methods={name:block(path,r"func\s+"+re.escape(name),name)
           for name in c.CURRENT_HOSTED_UNIT_METHODS}
  for name in c.CURRENT_HOSTED_UNIT_METHODS[1:]:
   value=methods[name]
   if value["declarationPrefix"].strip()!="@MainActor":
    failures.append("current method must be MainActor: "+name)
   if re.fullmatch(r"\s*#if\s+DEBUG\s*\n[\s\S]*\n\s*#else\s*\n\s*XCTFail\s*\(\s*\)\s*\n\s*#endif\s*",value["maskedBody"]) is None:
    failures.append("current method must retain an explicit unsupported-Release failure: "+name)
  unit=inputs["sources"][path]
  if "testV23P04C44LiveAdoptionRemainsPendingS10" in unit["code"]:
   failures.append("old live-adoption name must not become a boundary-only PASS")
  tokens(unit["source"],"retained future live obligations",("PENDING",)+c.CURRENT_PENDING_LIVE_METHODS,failures)
  boundary=methods[c.CURRENT_HOSTED_UNIT_METHOD]
  need(boundary,(
   "let fixture = try await makeFixture(","defer { fixture.cleanUp() }",
   "let writer = fixture.coordinator.workspaceWriter",
   "let seed = try C954StockSeedV1.make(writer: writer, context: fixture.coordinator.modelContext, workspaceID: fixture.coordinator.workspaceID)",
   "let before = try seed.snapshot(writer: writer)",
   "XCTAssertEqual(before.stock.parts, [seed.part])","XCTAssertEqual(before.stock.uses, [seed.used])",
   "XCTAssertEqual(before.drafts, [seed.checkpoint])","XCTAssertFalse(before.receipts.isEmpty)",
   "try selectWorkBeforeLaunch(fixture)","var composedScene: AppShellSceneStateV1?",
   "let shipping = try mountCompletedWorkShell(store: fixture.coordinator, presentation: fixture.presentation, diagnostics: fixture.diagnostics, router: fixture.router)",
   "defer { shipping.unmount() }","let workMounted = await waitForMountedScreen(ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: shipping.host)",
   "XCTAssertTrue(workMounted,","let completedMounted = await waitForMountedScreen(SignoffEnrollmentView.workRootAccessibilityIdentifier, from: shipping.host)",
   "XCTAssertTrue(completedMounted,","let scene = try XCTUnwrap(composedScene)",
   "XCTAssertEqual(scene.snapshot?.selectedRoot, .work)",
   "let featureWitnesses = c954FeatureWitnesses(seed: seed)","for identifier in featureWitnesses",
   "XCTAssertFalse(nativeScreenObservation(identifier, from: shipping.host).found,",
   "XCTAssertEqual(try seed.snapshot(writer: writer), before)","XCTAssertFalse(seed.context.hasChanges)",
   "let projection = try seed.containedProjection(writer: writer)",
   "XCTAssertEqual(projection.selectedItem?.detail.part, seed.part)",
   "XCTAssertEqual(projection.eligibleReturns.map(\\.sourceUse), [seed.used])",
   "XCTAssertEqual(projection.draft?.draftID, seed.checkpoint.draftID)",
   "XCTAssertEqual(projection.draft?.revision, seed.checkpoint.draftRevision)",
   "var commands: [PartsStockWorkflowCommandV1] = []",
   "let contained = try mountC954ContainedView(projection: projection) { commands.append($0) }",
   "defer { contained.unmount() }","let mounted = await waitForMountedScreen(identifier, from: contained.host)",
   "XCTAssertTrue(mounted,","XCTAssertTrue(commands.isEmpty,",
  ),"C44 actual loaded Work and same-node positive",)
  ordered(boundary,("try selectWorkBeforeLaunch(fixture)","let shipping = try mountCompletedWorkShell(",
   "XCTAssertTrue(workMounted,","XCTAssertTrue(completedMounted,",
   "XCTAssertEqual(scene.snapshot?.selectedRoot, .work)","XCTAssertFalse(nativeScreenObservation(",
   "XCTAssertEqual(try seed.snapshot(writer: writer), before)","shipping.unmount()",
   "let projection = try seed.containedProjection(writer: writer)","let contained = try mountC954ContainedView(",
   "XCTAssertTrue(mounted,","XCTAssertTrue(commands.isEmpty,",
   "XCTAssertEqual(try seed.snapshot(writer: writer), before)"),"C44 prerequisite/control order")
  preservation=methods[c.CURRENT_HOSTED_UNIT_METHODS[2]]
  need(preservation,(
   "let harness = try C954WriterHarnessV1()","defer { harness.writer.invalidate() }",
   "let seed = try C954StockSeedV1.make(writer: harness.writer, context: harness.context, workspaceID: harness.identity.workspaceID)",
   "let beforeExport = try enabled.exportCSV(workspaceID: seed.workspaceID)",
   "let before = try seed.snapshot(writer: harness.writer)",
   "XCTAssertEqual(before.stock.parts, [seed.part])","XCTAssertEqual(before.stock.uses, [seed.used])",
   "XCTAssertEqual(before.workResources, [seed.used.workResourceSuccessor])",
   "XCTAssertEqual(before.drafts, [seed.checkpoint])","XCTAssertEqual(before.draftEvidence.receipt, seed.draftReceipt)",
   "XCTAssertEqual(try harness.writer.durableReceipt(mutationID: seed.checkpoint.mutationID), seed.draftReceipt)",
   "let disabled = try seed.workflow(writer: harness.writer, policy: .readExportRecoveryOnly)",
   "disabled.catalog(workspaceID: seed.workspaceID)","disabled.lookup(workspaceID: seed.workspaceID,",
   "disabled.detail(workspaceID: seed.workspaceID,","disabled.lowStock(workspaceID: seed.workspaceID,",
   "XCTAssertEqual(unknown.balance, .unknown)","XCTAssertFalse(unknown.isBelowPreferred,",
   "XCTAssertEqual(try disabled.exportCSV(workspaceID: seed.workspaceID), beforeExport)",
   "disabled.previewCSVImport(workspaceID: seed.workspaceID, csvBytes: importBytes)",
   "XCTAssertThrowsError(try operation(), name)",
   "XCTAssertEqual(error as? PartsStockFailureV1, .writesDisabled, name)",
   "XCTAssertEqual(harness.ids.allocationCount, allocationsBefore,",
   "XCTAssertEqual(try seed.snapshot(writer: harness.writer), before, name)",
   "XCTAssertFalse(harness.context.hasChanges, name)",
   "disabled.count(","disabled.adjust(","disabled.transfer(","disabled.use(useInput, context: useContext)",
   "disabled.`return`(returnInput, context: returnContext)","disabled.archive(","disabled.importCSV(importPlan)",
   "let oldWriterInstance = try harness.writer.currentRevision().writerInstanceID",
   "try harness.reactivateAfterHealthyRecovery()",
   "XCTAssertNotEqual(try harness.writer.currentRevision().writerInstanceID, oldWriterInstance)",
   "let recovered = try seed.workflow(writer: harness.writer, policy: .readExportRecoveryOnly)",
   "XCTAssertEqual(try recovered.exportCSV(workspaceID: seed.workspaceID), beforeExport)",
   "XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: seed.checkpoint.mutationID), before.draftEvidence)",
   "XCTAssertThrowsError(try recovered.count(",
   "XCTAssertEqual(harness.ids.allocationCount, recoveredAllocations)",
  ),"C44 real policy/preservation/refusal/recovery")
  for name in ("Count","Adjust","Transfer","Use","Return","Archive","CSV import"):
   active_literal(preservation,'try rejectWrite("'+name+'")',"C44 seven actual refusal calls")
  seed=block(path,r"static\s+func\s+make","C44 real writer-owned seed")
  need(seed,("writer.execute(.applyPartyAccountability(.appendActorSnapshot(actor))",
   "writer.execute(.applyWorkPacket(packetMutation)","writer.commitPartsStock(.upsertPart(part))",
   "stock.count(","let used = try enabled.use(use, context: useContext).0",
   "purpose: .workPacket, codec: C36FieldDraftTestSupportV1.codec(for: .workPacket)",
   "try checkpoint.validate(registry: C36FieldDraftTestSupportV1.makeRegistry())",
   "writer.makeFieldDraftLifecycleAdapter(modelContext: context)","draftAdapter.compareAndSwap(",
   "draftAdapter.currentCheckpoint(","writer.fieldDraftEvidence(mutationID: checkpoint.mutationID)"),"C44 authentic seed")
  harness=block(path,r"class\s+C954WriterHarnessV1","C44 complete real-journal fixture")
  need(harness,("Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)",
   "isStoredInMemoryOnly: true","context.autosaveEnabled = false","MutationJournalStoreV1(",
   "WorkspaceWriterV1("),"C44 real fixture")
  recover=block(path,r"func\s+reactivateAfterHealthyRecovery","C44 healthy recovery")
  ordered(recover,("writer.invalidate()","MutationReceiptRecoveryServiceV1(store: journal).recoverBeforeWriterActivation()",
   "writer = try WorkspaceWriterV1("),"C44 sequential same-journal recovery")
  snapshot=block(path,r"func\s+snapshot","C44 real value invariant oracle")
  need(snapshot,("writer.currentRevision()","writer.acceptedReceiptsForProjection()",
   "context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())","context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>())",
   "writer.fieldDraftEvidence(mutationID: checkpoint.mutationID)","lifecycle.snapshotForBackup(workspaceID: workspaceID)",
   "lifecycle.replay(workspaceID: workspaceID)"),"C44 snapshot")
  witness=block(path,r"func\s+c954FeatureWitnesses","C44 same actual node set")
  need(witness,("PartsStockWorkflowView.screenAccessibilityIdentifier","PartsStockWorkflowView.catalogAccessibilityIdentifier",
   "PartsStockWorkflowView.catalogItemAccessibilityIdentifierPrefix","seed.part.partID.uuidString.lowercased()",
   "PartsStockWorkflowView.countAccessibilityIdentifier","PartsStockWorkflowView.eligibleReturnObservationIdentifier"),"C44 witness set")
  active_literal(witness,'PartsStockWorkflowView.useAccessibilityIdentifier + ".submit"',"C44 actual Use field witness")
  active_literal(witness,'PartsStockWorkflowView.draftAccessibilityIdentifier + ".material"',"C44 actual supplied-draft witness")
  mount=block(path,r"func\s+mountC954ContainedView","C44 actual contained host")
  need(mount,("NavigationStack { PartsStockWorkflowView(model: projection, onCommand: onCommand) }",
   "UIHostingController(rootView: AnyView(content))","window.makeKeyAndVisible()"),"C44 contained host")
  owner="FieldEvidenceAppTests/V23ProductionSignoffResponseJourneyTests.swift"
  shipping=block(owner,r"func\s+mountCompletedWorkShell","actual shared production shell")
  need(shipping,("var shell = AppShellView(","storeSession: store",
   "shell.onProductionSceneBoundForTesting = onScene","AnyView(shell.modelContext(store.modelContext))",
   "window.makeKeyAndVisible()"),"actual default-gate shell")
  unmount=block(owner,r"func\s+unmount","actual shared host cleanup")
  need(unmount,("guard isMounted else { return }","window.isHidden = true",
   "window.rootViewController = nil","previousKeyWindow?.makeKeyAndVisible()"),"host cleanup")
  support="FieldEvidenceAppTests/V23ProductionFourRootShellTests.swift"
  wait=block(support,r"func\s+waitForMountedScreen","unchanged bounded observer")
  need(wait,("for _ in 0..<200","Task.sleep(nanoseconds: 25_000_000)",
   "nativeScreenObservation(identifier, from: host).found","return false"),"bounded observer")
  view="FieldEvidenceApp/Features/PartsStock/PartsStockWorkflowView.swift"
  for declaration,expression,label in (
   (r"var\s+body",".nativeScreenObservationWitnessV1(Self.screenAccessibilityIdentifier)","real C44 screen"),
   (r"var\s+catalog",".nativeScreenObservationWitnessV1(Self.catalogAccessibilityIdentifier)","real catalog"),
   (r"func\s+explicitActions",".nativeScreenObservationWitnessV1(Self.countAccessibilityIdentifier)","actual Count control"),
   (r"func\s+useEditor",'.nativeScreenObservationWitnessV1("\\(Self.useAccessibilityIdentifier).submit")',"actual Use submit"),
   (r"func\s+returnCandidate",".nativeScreenObservationWitnessV1(Self.eligibleReturnObservationIdentifier)","eligible Return button"),
   (r"var\s+draft",'.nativeScreenObservationWitnessV1("\\(Self.draftAccessibilityIdentifier).material")',"actual supplied draft field"),
  ):
   active_literal(block(view,declaration,label),expression,label)
  guard_executed=True
 except (OSError,ValueError,UnicodeError) as error:
  failures.append("currentHostedUnitSource:"+str(error))
 result={"cardID":c.CARD,"question":"CURRENT_HOSTED_UNIT_FIXTURE_SOURCE_STRUCTURE",
  "result":"FAIL_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE" if failures else "PASS_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE_ONLY",
  "failures":failures,"selectors":selectors,"testBundle":"FieldEvidenceAppTests",
  "currentUnitGuardExecuted":guard_executed,"currentSourceInputRows":rows,
  "SourceReady":False,"nativeExecution":False,"compilationVerified":False,"runtimeVerified":False,
  "adoption":False,"acceptanceCredit":False,"gateCredit":False,"releaseReady":False,
  "historicalArtifactsRegenerated":False,"historicalAllocationVerifiedByThisMode":False,
  "historicalUIPath":c.NEW_PRODUCT_PATHS[5],"historicalDeferredUIRequirementUnchanged":True,
  "fullLiveStockAndStockDraftJourneysPending":True}
 if guard_executed:
  result["currentUnitBoundary"]={"scope":"PHASE1_NONADOPTION_AND_INCUMBENT_READ_ONLY_PRESERVATION",
   "guardPassed":not failures,"methods":list(c.CURRENT_HOSTED_UNIT_METHODS),
   "pendingLiveMethods":list(c.CURRENT_PENDING_LIVE_METHODS),"behaviorVerified":False,"gateCredit":False}
 return result

def validate_source(fs):
 existing=[(ROOT/p).read_text(encoding='utf-8') for p in c.EXISTING_PATHS];new=[(ROOT/p).read_text(encoding='utf-8') for p in c.NEW_PRODUCT_PATHS];domain,coordinator,view,tests,fixture,ui=new;contracts,basecoordinator,manual,writer=existing
 tokens(contracts,'existing parts contracts',('StockBalanceProjectionV1','StockReturnAgainstUseReceiptV1'),fs)
 tokens(domain,'C44 durable contract',('LocalStockFeaturePolicyV1','LOCAL_PART_CATALOG_V1','Use','Count','low','CSV'),fs)
 tokens(coordinator,'C44 coordinator',('preview','commit','Use','Return','MutationID'),fs)
 tokens(manual,'manual work boundary',('material','stock'),fs)
 tokens(writer,'writer boundary',('PartsStock','return','overflow'),fs)
 tokens(view,'C44 view',('LocalStockFeaturePolicyV1','Count','Adjust','Transfer','Use','Return','Archive','CSV'),fs)
 tokens(tests,'C44 tests',('V23P04C44G01','V23P04C44A01','V23P04C44H01','V23P04C44I01','CSV'),fs)
 tokens(ui,'C44 UI adoption boundary',('throw XCTSkip(','post-S10'),fs)
 try:fixture_json=json.loads(fixture);req(isinstance(fixture_json,dict),'fixture must be JSON object',fs)
 except Exception as e:fs.append('fixture JSON: '+str(e))
def main():
 p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true')
 p.add_argument('--current-hosted-unit-fixture',action='store_true',help='current app-hosted DEBUG unit Source only; separate from historical UI/readiness')
 a=p.parse_args()
 if a.current_hosted_unit_fixture:
  if a.complete:p.error('--complete is the separate historical-card question')
  result=_current_hosted_unit_fixture_result()
  print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));return 1 if result['failures'] else 0
 fs=[]
 try:expected=c.documents()
 except Exception as e:expected={};fs.append('authority:'+str(e))
 docs={}
 for path in (c.SCHEMA,c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
  try:docs[path]=c.read_json(path)
  except Exception as e:fs.append('artifact:'+str(e))
 for path,value in expected.items():req(docs.get(path)==value,'deterministic artifact differs: '+path,fs)
 rows,ready=c.rows()
 if a.complete and not ready:fs.append('complete:missing C44 source paths')
 if ready:validate_source(fs)
 changed=set(c.git('diff','--name-only',c.BASE,'HEAD').splitlines())|set(c.git('diff','--name-only','HEAD').splitlines())|set(c.git('diff','--cached','--name-only').splitlines())|set(c.git('ls-files','--others','--exclude-standard').splitlines());changed.discard('');unowned=changed-set(c.PATH_FENCE)
 if unowned:fs.append('unowned changed paths: '+','.join(sorted(unowned)))
 counts={'changedPathCount':len(changed&set(c.PATH_FENCE)),'unownedChangedPathCount':len(unowned),'missingPathCount':sum(not(ROOT/x).is_file() for x in c.PATH_FENCE),'fencePathCount':18,'existingPathCount':4,'newPathCount':14,'productTestUIFixturePathCount':6,'toolingPathCount':8,'s10ReservationOverlapCount':0}
 result={'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL' if not fs else 'FAIL_STATIC','sourceReady':ready,'finalHashesSealed':False,'flagsAllFalse':all(x is False for x in c.FLAGS.values()),'failures':fs,'counts':counts,'selectors':list(c.SELECTORS),'authoritySequence':c.SEQUENCE,'sourceRows':rows};print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));return 0 if not fs else 1
if __name__=='__main__':raise SystemExit(main())
