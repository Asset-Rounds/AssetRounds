#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
def _c45_without_comments_and_literals(source):
 # Source-only inspection: strings/comments cannot supply a live timing guard.
 return re.sub(r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\])*"',
               lambda match: '\n' * match.group(0).count('\n'), source, flags=re.S)


def _c45_unique_braced_body(code, declaration):
 matches=list(re.finditer(declaration+r'\s*\{',code))
 if len(matches)!=1:return None
 start=matches[0].end();depth=1
 for index in range(start,len(code)):
  if code[index]=='{':depth+=1
  elif code[index]=='}':
   depth-=1
   if depth==0:return code[start:index]
 return None


def _c45_raw_awake_timing_failures(adapter):
 code=_c45_without_comments_and_literals(adapter);failures=[]
 compact=lambda value: re.sub(r'\s+','',value) if value is not None else None
 timing=_c45_unique_braced_body(code,r'\bstruct\s+VoiceCaptureElapsedTimingV1\s*:\s*Sendable')
 if timing is None:return ['adapter anti-clamp: unique private elapsed helper missing']
 if len(re.findall(r'\bprivate\s+let\s+startedAt\s*:\s*SuspendingClock\.Instant\b',timing))!=1:
  failures.append('adapter anti-clamp: private awake origin missing')
 constructor=_c45_unique_braced_body(timing,r'\binit\s*\(\s*startedAt\s*:\s*SuspendingClock\.Instant\s*\)')
 if compact(constructor)!='self.startedAt=startedAt':
  failures.append('adapter anti-clamp: elapsed helper origin binding differs')
 raw=_c45_unique_braced_body(timing,r'\bfunc\s+rawDuration\s*\(\s*at\s+instant\s*:\s*SuspendingClock\.Instant\s*=\s*\.now\s*\)\s*->\s*Duration')
 if compact(raw)!='max(.zero,startedAt.duration(to:instant))':
  failures.append('adapter anti-clamp: raw awake duration is not unrounded and unclamped')
 parameters=r'\(\s*maximumDurationSeconds\s*:\s*UInt64\s*,\s*at\s+instant\s*:\s*SuspendingClock\.Instant\s*=\s*\.now\s*\)'
 admission=_c45_unique_braced_body(timing,r'\bfunc\s+admitsFinalCallback\s*'+parameters+r'\s*->\s*Bool')
 if compact(admission)!='rawDuration(at:instant)<=.seconds(maximumDurationSeconds)':
  failures.append('adapter anti-clamp: final admission does not compare the raw awake duration')
 reporting=_c45_unique_braced_body(timing,r'\bfunc\s+reportedDurationSeconds\s*'+parameters+r'\s*->\s*UInt64')
 expected_reporting=('letbounded=min(rawDuration(at:instant),.seconds(maximumDurationSeconds))'
                     'letcomponents=bounded.components'
                     'returnUInt64(components.seconds)+(components.attoseconds>0?1:0)')
 if compact(reporting)!=expected_reporting:
  failures.append('adapter anti-clamp: reporting ceiling and clamp differ')
 if re.search(r'\b(systemEpoch|unsafeBitCast|Mirror|JSONEncoder|JSONDecoder)\b',timing):
  failures.append('adapter anti-clamp: private instant exposure in elapsed helper')
 active=_c45_unique_braced_body(code,r'\bprivate\s+final\s+class\s+ActiveCapture')
 if active is None or len(re.findall(r'\blet\s+elapsedTiming\s*:\s*VoiceCaptureElapsedTimingV1\b',active))!=1 or compact(active).count('self.elapsedTiming=elapsedTiming')!=1:
  failures.append('adapter anti-clamp: active capture does not retain its elapsed origin')
 begin=_c45_unique_braced_body(code,r'\bfunc\s+beginPushToTalkCapture\s*\([^{}]*\)\s*async\s*throws')
 origin=('letsession=ActiveCapture(context:context,recognizer:recognizer,request:request,'
         'audioEngine:AVAudioEngine(),elapsedTiming:VoiceCaptureElapsedTimingV1(startedAt:.now))')
 begin_code=compact(begin) or ''
 if begin_code.count(origin)!=1 or 'tryaudioSession.setCategory(' not in begin_code or begin_code.index(origin)>begin_code.index('tryaudioSession.setCategory('):
  failures.append('adapter anti-clamp: elapsed origin is not bound before audio setup')
 callback=_c45_unique_braced_body(code,r'\bprivate\s+func\s+handleRecognitionCallback\s*\([^{}]*\)')
 final_body=_c45_unique_braced_body(callback or '',r'\bif\s+result\.isFinal\s*\{\s*do')
 guard=('guardsession.elapsedTiming.admitsFinalCallback(maximumDurationSeconds:contextMaximumSeconds(session)),'
        'transcript.utf8.count<=VoiceStructuringLimitsV1.maximumTranscriptUTF8Byteselse{'
        'throwVoiceCaptureFailureV1.captureRejected}')
 final_code=compact(final_body) or ''
 if not final_code.startswith(guard) or final_code.count('finishFinal(session,captured:captured)')!=1:
  failures.append('adapter anti-clamp: actual final callback is not fenced by the raw duration guard')
 reporter=_c45_unique_braced_body(code,r'\bprivate\s+func\s+reportedElapsedSeconds\s*\(\s*for\s+session\s*:\s*ActiveCapture\s*\)\s*->\s*UInt64')
 if compact(reporter)!='session.elapsedTiming.reportedDurationSeconds(maximumDurationSeconds:contextMaximumSeconds(session))':
  failures.append('adapter anti-clamp: displayed elapsed duration is not separately reported')
 maximum=_c45_unique_braced_body(code,r'\bprivate\s+func\s+contextMaximumSeconds\s*\(\s*_\s+session\s*:\s*ActiveCapture\s*\)\s*->\s*UInt64')
 if compact(maximum)!='session.context.maximumDurationSeconds':
  failures.append('adapter anti-clamp: fixed context maximum binding differs')
 return failures


sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c45_contracts as c

def _current_hosted_unit_fixture_result():
 """Exact current DEBUG unit Source structure, never live-voice/UI evidence."""
 import p04_c41_contracts as reader
 failures=[];rows=[]
 selectors=["FieldEvidenceAppTests/"+c.CURRENT_HOSTED_UNIT_CLASS+"/"+method for method in c.CURRENT_HOSTED_UNIT_METHODS]
 try:
  inputs=c.current_hosted_unit_sources();rows=inputs["rows"]
  def block(path,declaration,label):return reader.current_source_block(inputs,path,declaration,label)
  def need(value,expressions,label):reader.current_source_require(value,expressions,label,failures)
  def ordered(value,expressions,label):reader.current_source_order(value,expressions,label,failures)
  def literal(value,expression,label):reader.current_source_literal(value,expression,label,inputs,failures)
  path=c.CURRENT_HOSTED_UNIT_PATH
  methods={method:block(path,r"func\s+"+re.escape(method),method) for method in c.CURRENT_HOSTED_UNIT_METHODS}
  for index,(method,value) in enumerate(methods.items()):
   if re.search(r"\bXCTSkip\s*\(",value["code"]):failures.append("current DEBUG method must not skip: "+method)
   if index:
    if value["declarationPrefix"].strip()!="@MainActor":failures.append("current method must be MainActor: "+method)
    if re.fullmatch(r"\s*#if\s+DEBUG\s*\n[\s\S]*\n\s*#else\s*\n\s*throw\s+XCTSkip\s*\([^)]*\)\s*\n\s*#endif\s*",value["maskedBody"]) is None:
     failures.append("current method must retain only its Release observation skip: "+method)
  boundary=methods[c.CURRENT_HOSTED_UNIT_METHOD]
  need(boundary,(
   "let shellFixture = try await makeFixture(","defer { shellFixture.cleanUp() }",
   "try await makeWorkAsset(in: shellFixture, label:",
   "let before = try shellFixture.coordinator.workspaceWriter.currentRevision()",
   "let history = try shellFixture.coordinator.workspaceWriter.sourceMutationHistorySnapshot()",
   "var shell = AppShellView(","storeSession: shellFixture.coordinator",
   "contentAccess: try XCTUnwrap(shellFixture.presentation.renderAccess)",
   "myDayAccess: try XCTUnwrap(shellFixture.presentation.myDayAccess)",
   "shell.onProductionSceneBoundForTesting = { boundScene = $0 }",
   "AnyView(shell.modelContext(shellFixture.coordinator.modelContext))",
   "let scene = try XCTUnwrap(boundScene)","for root in AppRootV1.frozenOrder","try scene.select(root)",
   "case .today:","case .work:","case .assets:","case .reports:",
   "ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier",
   "ProductionWorkRootViewV1.screenAccessibilityIdentifier","SignDetailView.screenAccessibilityIdentifier",
   "ReportsRootView.screenAccessibilityIdentifier","XCTAssertTrue(loaded,","assertNoC45CaptureSurface(in: mountedShell)",
   "XCTAssertEqual(try shellFixture.coordinator.workspaceWriter.currentRevision(), before)",
   "XCTAssertEqual(try shellFixture.coordinator.workspaceWriter.sourceMutationHistorySnapshot(), history)",
   "XCTAssertFalse(shellFixture.coordinator.modelContext.hasChanges)",
   "RecordWorkView(draft: existing.draft, coordinator: existing.work, usesImportedFixtureForUITest: false)",
   "completionCount += 1","waitForMountedScreen(RecordWorkView.screenAccessibilityIdentifier, from: mountedDraft.host)",
   "XCTAssertTrue(draftLoaded,","assertNoC45CaptureSurface(in: mountedDraft)","XCTAssertEqual(completionCount, 0)",
   "captureContext: context, state: .ready","XCTAssertTrue(controlLoaded)","XCTAssertTrue(draftContextLoaded)",
   "XCTAssertTrue(captureAction,","XCTAssertTrue(actions.speakDetailsButtonPresent)","XCTAssertTrue(actions.speakDetailsEnabled)",
   "XCTAssertEqual(actions.state.model.draft.draftID, existing.draft.recordID)",
   "XCTAssertEqual(actions.state.model.captureContext, context)","XCTAssertTrue(requests.commands.isEmpty)",
   "XCTAssertEqual(requests.captureRequestCount, 0,","try assertC45DraftPreserved(existing)",
  ),"C45 loaded shipping/draft and real positive control")
  ordered(boundary,("try await makeWorkAsset(","let before = try shellFixture.coordinator.workspaceWriter.currentRevision()",
   "let mountedShell = try mountC45(","XCTAssertTrue(loaded,","assertNoC45CaptureSurface(in: mountedShell)",
   "XCTAssertEqual(try shellFixture.coordinator.workspaceWriter.currentRevision(), before)","mountedShell.unmount()",
   "let existing = try await makeC45ExistingDraft()","let mountedDraft = try mountC45(","XCTAssertTrue(draftLoaded,",
   "assertNoC45CaptureSurface(in: mountedDraft)","try assertC45DraftPreserved(existing)","mountedDraft.unmount()",
   "let control = try mountC45Projection(","XCTAssertTrue(captureAction,","XCTAssertTrue(requests.commands.isEmpty)",
   "try assertC45DraftPreserved(existing)"),"C45 negative route before positive control")
  if "v23PhaseGate" in boundary["code"] or "allFeatures" in boundary["code"]:
   failures.append("C45 shipping boundary must not inject a gate or activate a feature")
  manual=methods[c.CURRENT_HOSTED_UNIT_METHODS[2]]
  need(manual,(
   "for state in [VoicePushToTalkCaptureStateV1.manualFallback, .permissionDenied, .unsupported]",
   "state: state, canStartCapture: false","XCTAssertTrue(fieldLoaded)","XCTAssertTrue(continueLoaded)",
   "XCTAssertFalse(initial.speakDetailsButtonPresent)","XCTAssertFalse(initial.speakDetailsEnabled)",
   "XCTAssertFalse(nativeScreenObservation(VoicePushToTalkCaptureView.speakDetailsAccessibilityIdentifier, from: mounted.host).found)",
   "XCTAssertNil(initial.state.model.captureContext)","initial.manualText.wrappedValue =",
   "XCTAssertTrue(typed)","XCTAssertTrue(requests.commands.isEmpty,","try XCTUnwrap(current.continueManualEntry)()",
   "XCTAssertTrue(emptyTyped)","XCTAssertTrue(emptyRejected)","XCTAssertTrue(errorRendered,",
   "VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes + 1","manualBinding.wrappedValue = oversized",
   "XCTAssertTrue(oversizedTyped)","XCTAssertEqual(requests.captureRequestCount, 0)","try assertC45DraftPreserved(existing)",
  ),"C45 real manual fallback requests and refusals")
  literal(manual,'XCTAssertEqual(requests.commands, [.manualEntry(text: "Manual correction")])',"C45 exact normalized manual request")
  if re.sub(r"\s+","",manual["code"]).count("XCTAssertEqual(requests.commands,[.manualEntry(text:)])")!=3:
   failures.append("C45 manual request/no-request stage equations differ")
  field=methods[c.CURRENT_HOSTED_UNIT_METHODS[3]]
  need(field,(
   "let context = try c45Context(existing)","let proposal = try c45Proposal(context)",
   "state: .review, proposal: proposal, canStartCapture: false","XCTAssertTrue(actionLoaded,",
   "XCTAssertTrue(requests.commands.isEmpty,","XCTAssertFalse(initial.finishReviewEnabled)",
   "XCTAssertEqual(proposal.fields.count, 1)","try XCTUnwrap(field.accept)()",
   "VoiceProposalFieldReviewV1(fieldID:","disposition: .accept, reviewedValue: .text(",
   "try XCTUnwrap(requests.actions?.fields.first?.edit)()","XCTAssertTrue(editing)","XCTAssertTrue(controlLoaded,",
   "let editBinding = try XCTUnwrap(editingField.editedText)","editBinding.wrappedValue =","XCTAssertTrue(edited)",
   "XCTAssertEqual(requests.commands.count, 1,","try XCTUnwrap(requests.actions?.fields.first?.cancelEdit)()",
   "XCTAssertTrue(cancelled)","XCTAssertTrue(editingAgain)","try XCTUnwrap(requests.actions?.fields.first?.applyEdit)()",
   "XCTAssertTrue(applied)","try XCTUnwrap(requests.actions?.fields.first?.reject)()",
   "disposition: .reject, reviewedValue: nil","XCTAssertFalse(try XCTUnwrap(requests.actions).finishReviewEnabled,",
   "(.review, .stale, true, .idle)","(.review, .current, false, .idle)","(.review, .current, true, .awaitingReceipt)",
   "(.review, .current, true, .stale)","(.staleTarget, .current, true, .idle)",
   "XCTAssertTrue(blockedActionRendered,","XCTAssertNil(blockedField.accept)","XCTAssertNil(blockedField.edit)",
   "XCTAssertNil(blockedField.applyEdit)","XCTAssertNil(blockedField.reject)","XCTAssertFalse(blockedActions.finishReviewEnabled)",
   "if !editable { XCTAssertNil(blockedActions.continueManualEntry) }","XCTAssertTrue(blocked.commands.isEmpty)",
   "try assertC45DraftPreserved(existing)",
  ),"C45 mounted field review and unavailable controls")
  literal(field,'XCTAssertEqual(requests.commands, [\n            .acceptField(proposalID: proposal.proposalID, review: accepted),\n            .editField(proposalID: proposal.proposalID, fieldID: "note", fieldKind: .noteText,\n                valueText: "Corrected by keyboard"),\n            .rejectField(proposalID: proposal.proposalID, review: rejected),\n        ])',"C45 exact accept/edit/reject payloads")
  conservation=block(path,r"func\s+assertC45DraftPreserved","C45 actual canonical conservation")
  need(conservation,("XCTAssertEqual(try existing.fixture.storeCoordinator.workspaceWriter.currentRevision(), existing.revision,",
   "XCTAssertEqual(try existing.fixture.storeCoordinator.workspaceWriter.sourceMutationHistorySnapshot(), existing.history,",
   "XCTAssertEqual(try existing.fixture.context.fetchCount(FetchDescriptor<WorkflowRecord>()), existing.recordCount,",
   "XCTAssertEqual(try existing.fixture.context.fetchCount(FetchDescriptor<Issue>()), existing.issueCount,",
   "XCTAssertFalse(existing.fixture.context.hasChanges,"),"C45 actual canonical conservation")
  seed=block(path,r"func\s+makeC45ExistingDraft","C45 genuine existing draft")
  need(seed,("WorkCanonicalOpenIssueFixtureV1.make(","WorkCoordinator(modelContext: opened.context,",
   "checkRunnerCoordinator: opened.runner, lifecycleDependencies: opened.lifecycleDependencies)",
   "C45ExistingDraftV1(fixture: opened, work: work, draft: work.beginWork(issueID: opened.issueID))"),"C45 genuine existing draft")
  baseline=block(path,r"init\s*\(\s*fixture\s*:\s*WorkCanonicalOpenIssueFixtureV1","C45 post-beginWork baseline")
  need(baseline,("let snapshot = try fixture.storeCoordinator.workspaceWriter.currentRevision()","revision = snapshot",
   "history = try fixture.storeCoordinator.workspaceWriter.sourceMutationHistorySnapshot()",
   "recordCount = try fixture.context.fetchCount(FetchDescriptor<WorkflowRecord>())",
   "issueCount = try fixture.context.fetchCount(FetchDescriptor<Issue>())",
   "WorkspaceEntityIdentityV1(kind: .asset, id: fixture.assetID)",
   "targetRevision = try XCTUnwrap(snapshot.entityRevisions.first { $0.identity == identity }).revision"),"C45 post-beginWork baseline")
  mount=block(path,r"func\s+mountC45Projection","C45 real view binding")
  need(mount,("VoicePushToTalkCaptureView(model: projection) { requests.commands.append($0) }",
   "view.onActionsBoundForTesting = { requests.actions = $0 }","AnyView(NavigationStack { view })"),"C45 real view binding")
  wait=block(path,r"func\s+waitForC45","C45 bounded observer")
  need(wait,("for _ in 0..<200","Task.sleep(nanoseconds: 25_000_000)","return predicate()"),"C45 bounded observer")
  view="FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift"
  binding=block(view,r"func\s+publishActionsForTesting","C45 existing view handler binding")
  need(binding,("model.presentedFields.map { presentation in","editingFieldID == presentation.id",
   "accept: !editing && canReviewFields && acceptIsAvailable(presentation.field) ? { submitAccept(presentation) } : nil",
   "edit: !editing && canReviewFields ? { beginEdit(presentation) } : nil",
   "editedText: editing ? editedValueBinding(for: presentation) : nil",
   "applyEdit: editing && canReviewFields ? { submitEdit(presentation) } : nil",
   "cancelEdit: editing ? { cancelFieldEdit() } : nil",
   "reject: !editing && canReviewFields ? { submitReject(presentation) } : nil",
   "manualText: $manualText","continueManualEntry: model.draft.canEdit ? { submitManualEntry() } : nil",
   "speakDetailsEnabled: hasSpeakButton && canStartCapture","finishReviewEnabled: model.hasReviewedAllFields && canReviewFields"),"C45 existing view handler binding")
  manual_view=block(view,r"func\s+submitManualEntry","C45 real manual guard")
  ordered(manual_view,("manualText.trimmingCharacters(in: .whitespacesAndNewlines)","guard !text.isEmpty else",
   "return","guard text.utf8.count <= VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes else","return",
   "send(.manualEntry(text: text),"),"C45 real manual guard")
  accept=block(view,r"func\s+submitAccept","C45 real accept handler")
  need(accept,("let proposalID = model.proposalID","let value = presentation.field.proposedValue",
   "acceptIsAvailable(presentation.field)","disposition: .accept, reviewedValue: value",
   ".acceptField(proposalID: proposalID, review: review)"),"C45 real accept handler")
  edit=block(view,r"func\s+submitEdit","C45 real edit handler")
  need(edit,("let proposalID = model.proposalID",".trimmingCharacters(in: .whitespacesAndNewlines)",
   "guard !value.isEmpty else","guard value.utf8.count <= VoiceStructuringLimitsV1.maximumTextUTF8Bytes else",
   ".editField(proposalID: proposalID, fieldID: presentation.field.fieldID, fieldKind: presentation.field.kind, valueText: value)",
   "editingFieldID = nil","focusedField = nil"),"C45 real edit handler")
  reject=block(view,r"func\s+submitReject","C45 real reject handler")
  need(reject,("let proposalID = model.proposalID","disposition: .reject, reviewedValue: nil",
   ".rejectField(proposalID: proposalID, review: review)"),"C45 real reject handler")
  controls=block(view,r"func\s+fieldCard","C45 actual field controls")
  need(controls,("Button() { submitAccept(presentation) }",".disabled(!canReviewFields || !acceptIsAvailable(presentation.field))",
   "Button() { beginEdit(presentation) }","Button() { submitEdit(presentation) }",
   "Button(, action: cancelFieldEdit)","Button() { submitReject(presentation) }",
   "text: editedValueBinding(for: presentation)",".disabled(!canReviewFields)",".nativeScreenObservationWitnessV1("),"C45 actual field controls")
  fallback=block(view,r"var\s+manualFallback","C45 actual manual controls")
  need(fallback,("TextEditor(text: $manualText)","Button() { submitManualEntry() }",
   ".disabled(!model.draft.canEdit)",".nativeScreenObservationWitnessV1(Self.manualEntryFieldAccessibilityIdentifier)"),"C45 actual manual controls")
  review=block(view,r"var\s+canReviewFields","C45 unavailable review guard")
  need(review,("model.state == .review","model.proposalID != nil","model.draft.state == .current",
   "model.draft.canEdit","model.operation.state != .awaitingReceipt","model.operation.state != .stale"),"C45 unavailable review guard")
  body=block(view,r"var\s+body","C45 mounted binding lifecycle")
  need(body,(".nativeScreenObservationWitnessV1(Self.screenAccessibilityIdentifier)","publishActionsForTesting()",
   ".onChange(of: testingState)",".onDisappear { onActionsBoundForTesting?(nil) }"),"C45 mounted binding lifecycle")
  record=inputs["sources"]["FieldEvidenceApp/Features/Issues/RecordWorkView.swift"]
  need(record,(".accessibilityIdentifier(Self.screenAccessibilityIdentifier)",
   ".nativeScreenObservationWitnessV1(Self.screenAccessibilityIdentifier)"),"C45 incumbent draft control")
  shell="FieldEvidenceApp/Features/Shell/AppShellView.swift"
  tabs=block(shell,r"func\s+availableTabs","C45 actual shipping root composition")
  need(tabs,("ProductionMyDayRootViewV1(source: sources)","workRoot(scene: scene, sources: sources, completedWork: completedWork)",
   "SignsRootView(workflow: workflow,","ReportsRootView(workflow: workflow,"),"C45 actual shipping root composition")
  signs=inputs["sources"]["FieldEvidenceApp/Features/Signs/SignsRootView.swift"]
  need(signs,("case .work(let draft):","RecordWorkView(draft: draft, coordinator: workCoordinator,"),"C45 incumbent shipping draft composition")
  gate=inputs["sources"]["FieldEvidenceApp/App/V23PhaseGateV1.swift"]
  need(gate,("static let shipping = V23PhaseGateV1(through: .phase1)",
   "static let defaultValue: V23PhaseGateV1 = .shipping"),"C45 default shipping phase boundary")
  for owner in (shell,"FieldEvidenceApp/Features/Signs/SignsRootView.swift"):
   if re.search(r"\b(?:VoicePushToTalkCaptureView|VoicePushToTalkCoordinatorV1|OnDevicePushToTalkVoiceCaptureAdapterV1)\s*\(",inputs["sources"][owner]["code"]):
    failures.append("C45 current shipping route composes a deferred voice edge: "+owner)
  unit=inputs["sources"][path]["code"]
  for forbidden in (r"\bOnDevicePushToTalkVoiceCaptureAdapterV1\s*\(",r"\bVoicePushToTalkCoordinatorV1\s*\(",
                    r"\b(?:requestMicrophonePermission|requestSpeechRecognitionPermission|requestRecordPermission|beginPushToTalkCapture|dictateOnDevice)\s*\("):
   if re.search(forbidden,unit):failures.append("C45 contained Source must not invoke real capture/permissions: "+forbidden)
 except (OSError,ValueError,UnicodeError) as error:failures.append("currentHostedUnitSource:"+str(error))
 return {"cardID":c.CARD,"question":"CURRENT_HOSTED_UNIT_FIXTURE_SOURCE_STRUCTURE",
  "result":"FAIL_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE" if failures else "PASS_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE_ONLY",
  "failures":failures,"selectors":selectors,"testBundle":"FieldEvidenceAppTests","currentSourceInputRows":rows,
  "SourceReady":False,"nativeExecution":False,"compilationVerified":False,"runtimeVerified":False,"adoption":False,"acceptanceCredit":False,
  "gateCredit":False,"releaseReady":False,"historicalArtifactsRegenerated":False,"historicalAllocationVerifiedByThisMode":False,
  "physicalMenuOrAccessibilityQualification":False,"globalOSPermissionOrCaptureProof":False,
  "completeLiveVoiceJourneyPending":True,"historicalUIPath":c.NEW_PRODUCT_PATHS[6],"historicalDeferredUIRequirementUnchanged":True}

p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true')
p.add_argument('--current-hosted-unit-fixture',action='store_true',help='current DEBUG unit Source only; historical UI adoption remains separate and deferred')
a=p.parse_args()
if a.current_hosted_unit_fixture:
 if a.complete:p.error('--complete is the separate historical-card question')
 result=_current_hosted_unit_fixture_result();print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));raise SystemExit(1 if result['failures'] else 0)
fails=[]
try:expected=c.documents()
except Exception as e:expected={};fails.append('authority:'+str(e))
for path,v in expected.items():
 try:
  if c.read_json(path)!=v:fails.append('artifact drift: '+path)
 except Exception as e:fails.append('artifact:'+str(e))
rows,ready=c.rows()
if a.complete and not ready:fails.append('complete:missing C45 source paths')
if ready:
 plist=(ROOT/c.EXISTING_PATHS[0]).read_text(encoding='utf-8');domain=(ROOT/c.NEW_PRODUCT_PATHS[0]).read_text(encoding='utf-8');coordinator=(ROOT/c.NEW_PRODUCT_PATHS[1]).read_text(encoding='utf-8');adapter=(ROOT/c.NEW_PRODUCT_PATHS[2]).read_text(encoding='utf-8');view=(ROOT/c.NEW_PRODUCT_PATHS[3]).read_text(encoding='utf-8');tests=(ROOT/c.NEW_PRODUCT_PATHS[4]).read_text(encoding='utf-8');ui=(ROOT/c.NEW_PRODUCT_PATHS[6]).read_text(encoding='utf-8')
 texts=[plist,domain,coordinator,adapter,view,tests,ui]
 joined='\n'.join(texts)
 for token in ('StructuredVoiceCaptureContextV1','VoiceScratchDispositionV1','Speech','AVFoundation','60','push','on-device','transcript','confidence','accept','edit','reject','manual','callback','revision','cleanup','NONPERSISTENT'):
  if token.lower() not in joined.lower():fails.append('source token missing: '+token)
 # Exact platform disclosure keys are required and their values cannot be blank.
 for key in ('NSMicrophoneUsageDescription','NSSpeechRecognitionUsageDescription'):
  m=re.search(r'<key>'+key+r'</key>\s*<string>(.*?)</string>',plist,re.S);
  if not m or not m.group(1).strip():fails.append('Info.plist missing nonempty '+key)
 # Adapter checks use code with comments stripped, so policy prose cannot trigger negatives.
 code=re.sub(r'//[^\n]*|/\*.*?\*/','',adapter,flags=re.S)
 for token in ('import Speech','import AVFoundation','requiresOnDeviceRecognition = true','contextMaximumSeconds','callbackSequence','interruptionNotification','didEnterBackgroundNotification','cancelPushToTalkCapture'):
  if token not in code:fails.append('adapter structural token missing: '+token)
 # Raw elapsed time is the admission value; the reported value is display-only
 # and must never let a clamped UI duration bypass the fixed capture ceiling.
 fails.extend(_c45_raw_awake_timing_failures(adapter))
 for token in ('URLSession','URLRequest','NWConnection','WebSocket','FileHandle','AVAudioFile','CloudKit'):
  if re.search(r'\b'+re.escape(token)+r'\b',code):fails.append('adapter forbidden symbol: '+token)
 for token in ('StructuredVoiceCaptureContextV1','VoiceScratchDispositionV1'):
  if token not in domain:fails.append('domain ref missing: '+token)
 for token in ('preservingSource','retryableCleanup','cleanupPending','VoicePushToTalkReviewingV1'):
  if token not in coordinator:fails.append('coordinator structural token missing: '+token)
 for token in ('terminalCancellationPending','retryTerminalCancellation','preservingSource'):
  if token.lower() not in coordinator.lower():fails.append('coordinator terminal cancellation token missing: '+token)
 for token in ('presentationInFlight','deferredTerminal','finishDeferredTerminal','recoverAfterPresentationFenceMismatch','presentationInFlight = false'):
  if token not in coordinator:fails.append('coordinator presentation recovery token missing: '+token)
 coordinator_code=re.sub(r'//[^\n]*|/\*.*?\*/','',coordinator,flags=re.S)
 for token in ('WorkspaceWriter','ModelContext','StoreGeneration','writer.execute'):
  if token in coordinator_code:fails.append('coordinator forbidden persistence call: '+token)
 for token in ('v23.p04.c45.','Accept','Edit','Reject','manualEntryFieldAccessibilityIdentifier','static let'):
  if token not in view:fails.append('view structural token missing: '+token)
 for token in ('V23P04C45G01','V23P04C45A01','V23P04C45H01','V23P04C45I01','V23P04C45R01','C45Capture','C45Scratch','C45Review'):
  if token not in tests:fails.append('test structural token missing: '+token)
 for token in ('terminalCancellationPending','retryTerminalCancellation','cancelFailures'):
  if token not in tests:fails.append('test cancellation-recovery token missing: '+token)
 for token in ('suspendPresent','presentInFlight','presentationTerminalPending','must not return proposal'):
  if token.lower() not in tests.lower():fails.append('test presentation-recovery token missing: '+token)
 if 'VoiceScratchDispositionV1.completed' in view or 'case completed' in domain:fails.append('obsolete VoiceScratchDispositionV1.completed remains')
 if 'throw XCTSkip(' not in ui:fails.append('UI must explicitly XCTSkip deferred adoption')
changed=set(c.git('diff','--name-only',c.BASE,'HEAD').splitlines())|set(c.git('diff','--name-only','HEAD').splitlines())|set(c.git('diff','--cached','--name-only').splitlines())|set(c.git('ls-files','--others','--exclude-standard').splitlines());changed.discard('');unowned=changed-set(c.PATH_FENCE)
if unowned:fails.append('unowned changed paths: '+','.join(sorted(unowned)))
counts={'changedPathCount':len(changed&set(c.PATH_FENCE)),'unownedChangedPathCount':len(unowned),'missingPathCount':sum(not(ROOT/x).is_file() for x in c.PATH_FENCE),'fencePathCount':16,'existingPathCount':1,'newPathCount':15,'toolingPathCount':8,'s10ReservationOverlapCount':0};result={'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL' if not fails else 'FAIL_STATIC','sourceReady':ready,'flagsAllFalse':all(v is False for v in c.FLAGS.values()),'failures':fails,'counts':counts,'selectors':list(c.SELECTORS),'authoritySequence':c.SEQUENCE,'sourceRows':rows};print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));raise SystemExit(0 if not fails else 1)
