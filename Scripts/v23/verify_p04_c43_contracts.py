#!/usr/bin/env python3
"""Verify V23-P04-C43 tooling, shared source semantics, and exact fence."""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c43_contracts as c

def _block(text, declaration):
 m=re.search(declaration+r"[^\{]*\{",text)
 if not m:return ""
 depth=0
 for i in range(m.end()-1,len(text)):
  if text[i]=='{':depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0:return text[m.start():i+1]
 return ""

def _tokens(text, label, tokens, failures):
 for token in tokens:
  if token not in text:failures.append(f"{label} missing structural token: {token}")

# Exact current observer body, extracted by the existing active-source parser.
# Structural clauses below explain the contract; this frame also closes early
# returns/unreachable-token shortcuts and preserves diagnostic literal privacy.
CURRENT_MORE_MENU_OBSERVER_SOURCE_SHA256 = "36cf0345fdfe479d4d4aca70646a22bd89af1b5a0f99f41b0abd74a15a6082b6"


def _current_more_menu_observer_frame(inputs, reader, failures):
    observer = reader.current_source_block(inputs,
        "FieldEvidenceAppTests/V23ProductionSignoffResponseJourneyTests.swift",
        r"func\s+waitForCompletedWorkMoreMenu", "More functional menu observer")
    if re.sub(r"\s+", "", observer["declarationPrefix"]) != "@MainActorprivate":
        failures.append("More observer actor/visibility declaration differs")
    if c.sha(observer["source"].encode("utf-8")) != CURRENT_MORE_MENU_OBSERVER_SOURCE_SHA256:
        failures.append("complete More observer source frame differs")


def _current_more_menu_observer_contract(inputs, reader, failures):
    """Bind the real control/menu handshake, not a renamed success helper."""
    owner = "FieldEvidenceAppTests/V23ProductionSignoffResponseJourneyTests.swift"
    observer = reader.current_source_block(inputs, owner,
        r"func\s+waitForCompletedWorkMoreMenu", "More functional menu observer")
    label = "More functional menu observer"
    reader.current_source_require(observer, (
        "guard #available(iOS 17.4, *) else { return false }",
        "guard let root = host.viewIfLoaded, let window = root.window else { return false }",
        "var remainingWaits = 200",
        "guard root.window === window, nativeScreenObservation(SignoffEnrollmentView.immutableDetailAccessibilityIdentifier, from: host).found else {",
        "let controls = findControls()",
        "guard !controls.truncated, controls.buttons.count <= 1 else {",
        "if let button = controls.buttons.first { selected = button break }",
        "guard let button = selected, !Task.isCancelled, button.isContextMenuInteractionEnabled, let interaction = button.contextMenuInteraction else {",
        "var initiallyVisible = false interaction.updateVisibleMenu { menu in initiallyVisible = true return menu } guard !initiallyVisible else { return false } button.performPrimaryAction()",
        "var callbacks = 0", "var expectedActionVisible = false",
        "interaction.updateVisibleMenu { menu in callbacks += 1",
        "if menu.children.count == 1, let action = menu.children.first as? UIAction {",
        "expectedActionVisible = action.title == SignoffEnrollmentManifestV1.actionTitle && !action.attributes.contains(.disabled) && !action.attributes.contains(.hidden)",
        "else { expectedActionVisible = false",
        "if callbacks > 0 { break }",
        "interaction.dismissMenu() var consecutiveAbsentSamples = 0 var dismissed = false repeat { var stillVisible = false interaction.updateVisibleMenu { menu in stillVisible = true return menu } consecutiveAbsentSamples = stillVisible ? 0 : consecutiveAbsentSamples + 1 if consecutiveAbsentSamples == 2 { dismissed = true break } } while await nextSample()",
        "let finalControls = findControls()",
        "let sameMountedControl = !finalControls.truncated && finalControls.buttons.count == 1 && finalControls.buttons.first === button && root.window === window && nativeScreenObservation(SignoffEnrollmentView.immutableDetailAccessibilityIdentifier, from: host).found",
        "let observed = callbacks == 1 && expectedActionVisible && dismissed && sameMountedControl && !Task.isCancelled",
        "return observed",
    ), label, failures)
    reader.current_source_order(observer, (
        "var remainingWaits = 200", "var selected: UIButton?", "let controls = findControls()",
        "guard let button = selected", "var initiallyVisible = false",
        "guard !initiallyVisible else { return false }", "button.performPrimaryAction()",
        "var callbacks = 0", "interaction.updateVisibleMenu { menu in callbacks += 1",
        "if callbacks > 0 { break }", "interaction.dismissMenu()",
        "var consecutiveAbsentSamples = 0", "if consecutiveAbsentSamples == 2",
        "let finalControls = findControls()", "let observed =", "return observed",
    ), "More functional observation order", failures)
    wait = reader.current_source_block(inputs, owner, r"func\s+nextSample", "More shared wait")
    reader.current_source_require(wait, (
        "guard remainingWaits > 0, !Task.isCancelled else { return false }",
        "remainingWaits -= 1", "try await Task.sleep(nanoseconds: 25_000_000)",
        "return !Task.isCancelled", "catch { return false }",
    ), "More shared wait", failures)
    visible = reader.current_source_block(inputs, owner, r"func\s+visiblyAttached", "More visible control")
    reader.current_source_require(visible, (
        "guard button.window === window, button.isDescendant(of: root), button.isEnabled, !button.bounds.isEmpty else { return false }",
        "var visible = button.convert(button.bounds, to: window)",
        "guard !visible.isNull, !visible.isInfinite, !visible.isEmpty else { return false }",
        "guard seen.count < 64, seen.insert(ObjectIdentifier(current)).inserted, (current === window || current.window === window), !current.isHidden, current.alpha > 0, current.isUserInteractionEnabled else { return false }",
        "if current.clipsToBounds || current === window { visible = visible.intersection(current.convert(current.bounds, to: window)) guard !visible.isNull, !visible.isInfinite, !visible.isEmpty else { return false } }",
        "if current === window { return true }", "ancestor = current.superview", "return false",
    ), "More visible control", failures)
    controls = reader.current_source_block(inputs, owner, r"func\s+findControls", "More complete control census")
    reader.current_source_require(controls, (
        "var seenViews = Set<ObjectIdentifier>()", "var candidates: [UIButton] = []", "var truncated = false",
        "guard depth <= 32, seenViews.count < 256 else { truncated = true; return }",
        "guard seenViews.insert(ObjectIdentifier(view)).inserted else { return }",
        "if let button = view as? UIButton, button.menu != nil, button.showsMenuAsPrimaryAction, visiblyAttached(button) { candidates.append(button) }",
        "if view.subviews.count > 64 { truncated = true }",
        "for child in view.subviews.prefix(64) { visit(child, depth: depth + 1) }",
        "visit(root, depth: 0)", "return (candidates, truncated)",
    ), "More complete control census", failures)
    compact = re.sub(r"\s+", "", observer["code"])
    for expression, count in (
        ("button.performPrimaryAction()", 1), ("interaction.dismissMenu()", 1),
        ("interaction.updateVisibleMenu{", 3), ("whileawaitnextSample()", 3),
        ("Task.sleep(", 1), ("returnobserved", 1), ("returntrue", 1),
        ("callbacks+=1", 1), ("remainingWaits-=1", 1),
    ):
        if compact.count(expression) != count:
            failures.append(label + " operation count differs: " + expression)
    for name, count in (("remainingWaits", 2), ("initiallyVisible", 2),
                        ("callbacks", 2), ("expectedActionVisible", 3),
                        ("consecutiveAbsentSamples", 2), ("dismissed", 2),
                        ("stillVisible", 2)):
        if len(re.findall(r"\b" + name + r"\s*[+*/-]?=(?!=)", observer["code"])) != count:
            failures.append(label + " state write count differs: " + name)
    if re.search(r"\b(?:isHeld|menuAppearance)\b|\b(?:requestRecord|submit|sendAction|sendActions|performSelector|accessibilityActivate)\s*\(", observer["code"]):
        failures.append(label + " unsupported visibility oracle or action dispatch")

def _current_hosted_unit_fixture_result():
 """Current Source structure only, separate from the original card artifacts."""
 import p04_c41_contracts as reader
 failures=[];rows=[]
 selector="FieldEvidenceAppTests/"+c.CURRENT_HOSTED_UNIT_CLASS+"/"+c.CURRENT_HOSTED_UNIT_METHOD
 try:
  inputs=c.current_hosted_unit_sources();rows=inputs["rows"];body=inputs["method"]
  reader.current_source_require(body,(
   "let fixture = try await makeFixture(","defer { fixture.cleanUp() }",
   "let report = try await makeReadyReport(in: fixture, label:",
   "let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)",
   "let writer = fixture.coordinator.workspaceWriter","try selectWorkBeforeLaunch(fixture)",
   "let previousObserver = CompletedWorkPresentationV1.didCreateForTesting",
   "CompletedWorkPresentationV1.didCreateForTesting = { value in if captured == nil { captured = value } }",
   "defer { CompletedWorkPresentationV1.didCreateForTesting = previousObserver }",
   "let mounted = try mountCompletedWorkShell(store: fixture.coordinator, presentation: fixture.presentation, diagnostics: fixture.diagnostics, router: fixture.router)",
   "defer { mounted.unmount() }","let revisionBefore = try writer.currentRevision()",
   "let receiptsBefore = try completedWorkRowCount(MutationReceiptRow.self, in: context)",
   "let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self, in: context)",
   "let signoffsBefore = try completedWorkRowCount(SignoffSnapshotRow.self, in: context)",
   "let reportsBefore = try completedWorkRowCount(Report.self, in: context)",
   "let recordsBefore = try c43WorkflowRecordFacts(in: context)","let packetsBefore = try c43PacketFacts(in: context)",
   "let presentation = try await driveCompletedWorkToEditor(key: key, host: mounted.host) { captured }",
   "XCTAssertEqual(try writer.currentRevision(), revisionBefore,",
   "let route = try XCTUnwrap(presentation.editorRoute)","XCTAssertFalse(route.resumesRetainedAttempt)",
   "let submission = SignoffEnrollmentSubmissionV1(route: route.metadata,",
   "XCTAssertEqual(presentation.submit(submission), .saved)","XCTAssertEqual(presentation.lastResult, .saved)",
   "XCTAssertNil(presentation.editorRoute)","XCTAssertNil(presentation.detailRoute)",
   "XCTAssertEqual(signoffs.count, signoffsBefore + 1)",
   "XCTAssertEqual(signoff.workspaceID, fixture.coordinator.workspaceID)",
   "XCTAssertEqual(signoff.subjectID, report.reportID)","XCTAssertEqual(signoff.subjectRevision, key.subjectRevision)",
   "XCTAssertEqual(signoff.method, .typedLocalAssertion)","XCTAssertEqual(signoff.disposition, .recordedLocalAssertion)",
   "XCTAssertNil(signoff.supersedesSnapshotID)","let assertion = try XCTUnwrap(signoff.roleAssertion)",
   "XCTAssertEqual(assertion.actor.responsibility, .acknowledgedBy)","XCTAssertNotEqual(assertion.actor.responsibility, .approvedBy)",
   "XCTAssertNil(assertion.actor.actor.partyID)",
   "XCTAssertEqual(assertion.claimedRelationship, .client)",
   "XCTAssertEqual(assertion.disclosureRelease.disclosureText, SignoffEnrollmentDisclosureV1.disclosureText)",
   "XCTAssertEqual(try actorRow.value(), assertion.actor)","try C43SignoffEnrollmentBoundaryV1.validate(signoff)",
   "let receipt = try XCTUnwrap(try writer.durableReceipt(mutationID: signoff.mutationID))","try receipt.validate()",
   "XCTAssertEqual(receipt.mutationID, signoff.mutationID)","XCTAssertEqual(receipt.identity.workspaceID, signoff.workspaceID)",
   "XCTAssertEqual(receipt.resultingRevision.workspaceRevision, revisionBefore.revision + 2)",
   "XCTAssertEqual(try writer.currentRevision().revision, revisionBefore.revision + 2)",
   "XCTAssertEqual(try completedWorkRowCount(MutationReceiptRow.self, in: context), receiptsBefore + 2)",
   "XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: context), actorsBefore + 1)",
   "let historyTarget = try SignoffHistoryRouteV1(workspaceID: fixture.coordinator.workspaceID, signoffID: signoff.snapshotID).reportsTarget",
   "let scene = try XCTUnwrap(shellScene)","XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)",
   "XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [historyTarget])",
   "XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [],",
   "let historyMounted = await waitForMountedScreen(SignoffEnrollmentView.historyAccessibilityIdentifier, from: mounted.host)",
   "XCTAssertTrue(historyMounted,","let persisted = await waitUntilCompletedWork",
   "case let .restored(snapshot) = loaded else { return false }",
   "snapshot.selectedRoot == .reports && snapshot.path(for: .reports)?.targets == [historyTarget]",
   "XCTAssertTrue(persisted,",
   "XCTAssertFalse(containsAccessibilityIdentifier(identifiedBy: SignoffEnrollmentView.confirmAccessibilityIdentifier, in: mounted.host.view))",
   "let workflow = try makeCompletedWorkWorkflow(in: fixture)",
   "let history = try workflow.completedWorkResponses.history(focusedSignoffID: signoff.snapshotID)",
   "XCTAssertNil(history.unavailableReason)","XCTAssertTrue(history.earlier.isEmpty)",
   "XCTAssertEqual(history.current.count, 1)","XCTAssertTrue(try XCTUnwrap(history.current.first).isFocused)",
   "XCTAssertEqual(history.current.first?.facts?.disclosureText, SignoffEnrollmentDisclosureV1.disclosureText)",
  ),"C43 current Work response journey",failures)
  reader.current_source_order(body,(
   "try selectWorkBeforeLaunch(fixture)","CompletedWorkPresentationV1.didCreateForTesting =",
   "let mounted = try mountCompletedWorkShell(","let revisionBefore = try writer.currentRevision()",
   "let presentation = try await driveCompletedWorkToEditor(",
   "XCTAssertEqual(try writer.currentRevision(), revisionBefore,",
   "XCTAssertEqual(presentation.submit(submission), .saved)",
   "try C43SignoffEnrollmentBoundaryV1.validate(signoff)","try receipt.validate()",
   "XCTAssertEqual(try writer.currentRevision().revision, revisionBefore.revision + 2)",
   "XCTAssertEqual(try c43PacketFacts(in: context), packetsBefore)",
   "let historyTarget = try SignoffHistoryRouteV1(","XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)",
   "let historyMounted = await waitForMountedScreen(","XCTAssertTrue(historyMounted,",
   "let persisted = await waitUntilCompletedWork","XCTAssertTrue(persisted,",
   "let history = try workflow.completedWorkResponses.history(",
  ),"C43 no-write entry then recorded focused history",failures)
  for expression in (
   'XCTAssertEqual(signoff.purpose, "WORK_DETAIL_COMPLETED_RESPONSE_V1")',
   'XCTAssertEqual(route.metadata.subject.versionText, "Version 1")',
   'XCTAssertEqual(assertion.actor.displayNameAtTime, "Jordan Hosted")',
   'XCTAssertEqual(assertion.claimedRole, "Facilities lead")',
   'XCTAssertEqual(history.current.first?.facts?.typedName, "Jordan Hosted")',
   'XCTAssertEqual(history.current.first?.facts?.claimedRole, "Facilities lead")',
   'XCTAssertEqual(history.current.first?.facts?.relationshipText, "Client")',
   'XCTAssertEqual(history.current.first?.facts?.methodText, "Typed response")',
   'XCTAssertEqual(history.subject?.versionText, "Version 1")',
  ):reader.current_source_literal(body,expression,"C43 fixed fact",inputs,failures)
  compact=re.sub(r"\s+","",body["code"])
  for expression,count in (
   ("XCTAssertEqual(trycompletedWorkRowCount(Report.self,in:context),reportsBefore)",2),
   ("XCTAssertEqual(tryc43WorkflowRecordFacts(in:context),recordsBefore)",2),
   ("XCTAssertEqual(tryc43PacketFacts(in:context),packetsBefore)",2),
   ("XCTAssertFalse(context.hasChanges)",4),
  ):
   if compact.count(expression)!=count:failures.append("C43 conservation stage count differs: "+expression)
  workflow=reader.current_source_block(inputs,c.CURRENT_HOSTED_UNIT_PATH,r"func\s+c43WorkflowRecordFacts","C43 workflow facts")
  reader.current_source_literal(workflow,
   'try context.fetch(FetchDescriptor<WorkflowRecord>()).map { record in\n'
   '            "\\(record.id.uuidString)|\\(record.state)|\\(record.stage)|\\(record.revisionKind)|"\n'
   '                + "\\(record.completedAt?.timeIntervalSince1970 ?? -1)"\n'
   '        }.sorted()',"C43 workflow fact expression",inputs,failures)
  packets=reader.current_source_block(inputs,c.CURRENT_HOSTED_UNIT_PATH,r"func\s+c43PacketFacts","C43 packet facts")
  reader.current_source_literal(packets,
   'try context.fetch(FetchDescriptor<Packet>()).map { packet in\n'
   '            "\\(packet.id.uuidString)|\\(packet.currentRecordID?.uuidString ?? "nil")|"\n'
   '                + "\\(packet.contentDeletedAt?.timeIntervalSince1970 ?? -1)"\n'
   '        }.sorted()',"C43 packet fact expression",inputs,failures)
  owner="FieldEvidenceAppTests/V23ProductionSignoffResponseJourneyTests.swift"
  journey=reader.current_source_block(inputs,owner,r"func\s+driveCompletedWorkToEditor","incumbent visible Work journey")
  reader.current_source_require(journey,(
   "waitForMountedScreen(ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: host)","XCTAssertTrue(rootMounted,",
   "waitForMountedScreen(SignoffEnrollmentView.workRootAccessibilityIdentifier, from: host)","XCTAssertTrue(sectionMounted,",
   "let presentation = try XCTUnwrap(provider(),","return items.contains { $0.key == key }","XCTAssertTrue(listed,",
   "XCTAssertEqual(item.eligibility, .eligible)","XCTAssertEqual(item.responseCount, 0)","presentation.open(item)",
   "waitForMountedScreen(SignoffEnrollmentView.immutableDetailAccessibilityIdentifier, from: host)","XCTAssertTrue(detailMounted,",
   "let moreVisible = await waitForCompletedWorkMoreMenu(from: host)",
   "XCTAssertEqual(detail.key, key)","XCTAssertEqual(detail.eligibility, .eligible)","XCTAssertNotNil(detail.proof)",
   "presentation.requestRecord()","waitForMountedScreen(SignoffEnrollmentView.screenAccessibilityIdentifier, from: host)",
   "XCTAssertTrue(editorMounted,","XCTAssertNotNil(presentation.editorRoute)","return presentation",
  ),"incumbent visible Work journey",failures)
  reader.current_source_order(journey,("XCTAssertTrue(rootMounted,","XCTAssertTrue(sectionMounted,",
   "XCTAssertTrue(listed,","presentation.open(item)","XCTAssertTrue(detailMounted,",
   "XCTAssertTrue(moreVisible,","XCTAssertNotNil(detail.proof)","presentation.requestRecord()",
   "XCTAssertTrue(editorMounted,","return presentation"),"incumbent observed journey order",failures)
  reader.current_source_literal(journey,'XCTAssertTrue(moreVisible, "The detail offers More")',"retained genuine More assertion",inputs,failures)
  mount=reader.current_source_block(inputs,owner,r"func\s+mountCompletedWorkShell","real shell mount")
  reader.current_source_require(mount,("var shell = AppShellView(","storeSession: store",
   "contentAccess: try XCTUnwrap(presentation.renderAccess)","myDayAccess: try XCTUnwrap(presentation.myDayAccess)",
   "shell.onProductionSceneBoundForTesting = onScene","AnyView(shell.modelContext(store.modelContext))",
   "window.makeKeyAndVisible()","return SIG1MountedShellV1(window: window, host: host, previousKeyWindow: previousKeyWindow)"),"real shell mount",failures)
  unmount=reader.current_source_block(inputs,owner,r"func\s+unmount","host cleanup")
  reader.current_source_require(unmount,("guard isMounted else { return }","isMounted = false","window.isHidden = true",
   "window.rootViewController = nil","previousKeyWindow?.makeKeyAndVisible()"),"host cleanup",failures)
  wait=reader.current_source_block(inputs,owner,r"func\s+waitUntilCompletedWork","bounded completed observer")
  reader.current_source_require(wait,("for _ in 0..<200","Task.sleep(nanoseconds: 25_000_000)","return condition()"),"bounded completed observer",failures)
  support="FieldEvidenceAppTests/V23ProductionFourRootShellTests.swift"
  wait=reader.current_source_block(inputs,support,r"func\s+waitForMountedScreen","bounded mounted observer")
  reader.current_source_require(wait,("for _ in 0..<200","nativeScreenObservation(identifier, from: host).found",
   "Task.sleep(nanoseconds: 25_000_000)","return false"),"bounded mounted observer",failures)
  _current_more_menu_observer_contract(inputs,reader,failures)
  _current_more_menu_observer_frame(inputs,reader,failures)
  menu=reader.current_source_block(inputs,"FieldEvidenceApp/Features/Accountability/CompletedWorkDetailViewV1.swift",r"var\s+moreMenu","production More menu")
  reader.current_source_require(menu,("Menu {","presentation.requestRecord()","Text(verbatim: SignoffEnrollmentManifestV1.actionTitle)",
   ".disabled(!canRecord)",".accessibilityIdentifier(SignoffEnrollmentView.recordResponseAccessibilityIdentifier)",
   ".accessibilityIdentifier(SignoffEnrollmentView.moreAccessibilityIdentifier)"),"production More menu",failures)
  reader.current_source_literal(menu,'Label("More", systemImage: "ellipsis.circle")',"production More label",inputs,failures)
  domain="FieldEvidenceApp/Domain/Accountability/SignoffEnrollmentContractsV1.swift"
  manifest=reader.current_source_block(inputs,domain,r"enum\s+SignoffEnrollmentManifestV1","fixed response manifest")
  reader.current_source_literal(manifest,'case workDetailCompletedResponseV1 = "WORK_DETAIL_COMPLETED_RESPONSE_V1"',"fixed purpose",inputs,failures)
  reader.current_source_literal(manifest,'static let actionTitle = "Record approval response"',"fixed action",inputs,failures)
  claims=reader.current_source_block(inputs,domain,r"struct\s+SignoffEnrollmentProhibitedClaimFlagsV1","prohibited claim truth")
  reader.current_source_require(claims,tuple(field+" = true" for field in (
   "disclaimsVerifiedIdentity","disclaimsVerifiedAuthority","disclaimsBehalfOfAnotherPerson",
   "disclaimsLegalSignature","disclaimsLegalEffect","disclaimsNonrepudiation",
   "disclaimsFinalApproval","disclaimsWorkflowTransition")),"prohibited claim truth",failures)
 except (OSError,ValueError,UnicodeError) as error:failures.append("currentHostedUnitSource:"+str(error))
 return {"cardID":c.CARD,"question":"CURRENT_HOSTED_UNIT_FIXTURE_SOURCE_STRUCTURE",
  "result":"FAIL_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE" if failures else "PASS_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE_ONLY",
  "failures":failures,"selector":selector,"testBundle":"FieldEvidenceAppTests","currentSourceInputRows":rows,
  "SourceReady":False,"nativeExecution":False,"acceptanceCredit":False,"gateCredit":False,"releaseReady":False,
  "historicalArtifactsRegenerated":False,"historicalAllocationVerifiedByThisMode":False,
  "physicalMenuOrAccessibilityQualification":False}

def _validate_structural_source(failures):
 party=(ROOT/c.EXISTING_PATHS[0]).read_text(encoding='utf-8')
 writer=(ROOT/c.EXISTING_PATHS[3]).read_text(encoding='utf-8')
 domain=(ROOT/c.NEW_PRODUCT_PATHS[1]).read_text(encoding='utf-8')
 issue=(ROOT/c.EXISTING_PATHS[2]).read_text(encoding='utf-8')
 coordinator=(ROOT/c.NEW_PRODUCT_PATHS[0]).read_text(encoding='utf-8')
 view=(ROOT/c.NEW_PRODUCT_PATHS[2]).read_text(encoding='utf-8')
 tests=(ROOT/c.NEW_PRODUCT_PATHS[4]).read_text(encoding='utf-8')
 ui=(ROOT/c.NEW_PRODUCT_PATHS[5]).read_text(encoding='utf-8')
 # The writer boundary must recognize the reserved purpose and validate its fixed release.
 append_start=writer.find("case let .appendSignoff(value):")
 append_end=writer.find("\n        case ",append_start+1)
 append=writer[append_start:append_end if append_end >= 0 else len(writer)]
 _tokens(append,"writer C43 appendSignoff boundary",("C43SignoffEnrollmentBoundaryV1.isEnrollmentSnapshot(value)","C43SignoffEnrollmentBoundaryV1.validate(value)"),failures)
 _tokens(domain,"fixed C43 purpose/release",("WORK_DETAIL_COMPLETED_RESPONSE_V1","work-detail-completed-response.local-v1"),failures)
 # C43 has one adapter: preview creates appendSignoff and commit delegates its receipt-first helper.
 preview=_block(coordinator,r"func preview\(")
 commit=_block(coordinator,r"func commit\(")
 _tokens(preview,"C43 coordinator preview",(".appendSignoff(snapshot)","previewC43SignoffEnrollment","expectedRevision"),failures)
 _tokens(commit,"C43 coordinator commit",("commitC43SignoffEnrollment","partyReceipt"),failures)
 generic=_block(party,r"func commit\(")
 first_receipt=generic.find("writer.durableReceipt")
 execute=generic.find("writer.execute")
 if first_receipt < 0 or execute < 0 or first_receipt > execute:failures.append("generic party commit must lookup durableReceipt before writer execute")
 # Durable request/plan/receipt truth explicitly carries route and claim boundaries.
 request=_block(domain,r"struct SignoffEnrollmentRequestV1")
 plan=_block(domain,r"struct SignoffEnrollmentPlanV1")
 receipt=_block(domain,r"struct SignoffEnrollmentReceiptV1")
 route=_block(domain,r"struct SignoffEnrollmentRouteChainTruthV1")
 claims=_block(domain,r"struct SignoffEnrollmentProhibitedClaimFlagsV1")
 _tokens(request,"request",("manifest","typedName","claimedRole","claimedRelationship","expectedRevision","routeChain","drawnMark","mutationID"),failures)
 _tokens(plan,"plan",("manifest","routeChain","partyPlan","planSHA256",".appendSignoff(snapshot)"),failures)
 _tokens(receipt,"receipt",("partyReceipt","mutationID","receiptSHA256"),failures)
 _tokens(route,"route",("actionRoot = .work","editorDestination = .signoffEditor","historyDestination = .signoffHistory","requiresVisibleWorkRoot = true","directDeepLinkOnlyIsEligible = false"),failures)
 _tokens(claims,"prohibited claims",("disclaimsBehalfOfAnotherPerson","disclaimsLegalEffect","disclaimsVerifiedIdentity","disclaimsVerifiedAuthority","disclaimsLegalSignature","disclaimsNonrepudiation","disclaimsFinalApproval"),failures)
 # Only the transient view may have strokes; the durable plan/receipt must be presence-only.
 mark=_block(domain,r"enum SignoffEnrollmentDrawnMarkV1")
 _tokens(mark,"mark payload",("case presentNonBiometric",),failures)
 if len(re.findall(r"case\s+",mark))!=1:failures.append("mark payload must be presence-only")
 for label,block in (("durable plan",plan),("durable receipt",receipt)):
  if re.search(r"stroke|image|hash|biometric",block,re.I):failsafe=f"{label} contains forbidden mark material";failures.append(failsafe)
 # IssueDetail owns only a resolved-state optional More menu containing the action.
 resolved=_block(issue,r"if issue\.status == \.resolved,")
 _tokens(resolved,"IssueDetail resolved containment",("let recordApprovalResponse","Menu {","Button(\"Record response\", action: recordApprovalResponse)","Label(\"More\"","signoffMoreAccessibilityIdentifier","signoffRecordResponseAccessibilityIdentifier"),failures)
 # The contained view has exact action wording, closed IDs, typed fields, and optional-mark copy.
 _tokens(view,"SignoffEnrollmentView",("Text(\"Record approval response\")","Button(\"Record approval response\", action: submit)","typedNameAccessibilityIdentifier","claimedRoleAccessibilityIdentifier","claimedRelationshipAccessibilityIdentifier","drawnMarkAccessibilityIdentifier","Optional drawn mark","not biometric","markStrokes.isEmpty ? nil : .presentNonBiometric"),failures)
 # UI remains explicitly skipped pending post-S10 adoption; no live journey is claimed.
 _tokens(ui,"UI adoption boundary",("throw XCTSkip(","Pending post-S10 launch adoption","does not claim a live root or executed UI flow"),failures)
 # The test suite must pin the pre-C43 literal and hostile reserved-purpose collision.
 _tokens(tests,"frozen acknowledgement test",("frozenPreC43Bytes","JSONDecoder().decode(AcknowledgementSnapshotV1.self","JSONEncoder()","XCTAssertEqual(bytes, frozenPreC43Bytes)"),failures)
 _tokens(tests,"hostile reserved-purpose collision",("foreign-local-response-v1","WORK_DETAIL_COMPLETED_RESPONSE_V1","genericPlan","XCTAssertThrowsError(try bundle.party.commit(genericPlan))"),failures)
def main():
 p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true')
 p.add_argument('--current-hosted-unit-fixture',action='store_true',help='current DEBUG unit-fixture Source only; preserve historical card artifacts')
 a=p.parse_args();fails=[]
 if a.current_hosted_unit_fixture:
  if a.complete:p.error('--complete is the separate historical-card question')
  result=_current_hosted_unit_fixture_result();print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));return 1 if result['failures'] else 0
 try:expected=c.documents()
 except Exception as e:expected={};fails.append(f'authority:{e}')
 docs={}
 for path in (c.SCHEMA,c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
  try:docs[path]=c.read_json(path)
  except Exception as e:fails.append(f'artifact:{e}')
 for path,v in expected.items():
  if docs.get(path)!=v:fails.append(f'deterministic artifact differs: {path}')
 rows,ready=c.rows()
 if a.complete and not ready:fails.append('complete:missing C43 source paths')
 if ready:
  text='\n'.join((ROOT/x).read_text(encoding='utf-8') for x in (*c.EXISTING_PATHS,*c.NEW_PRODUCT_PATHS) if x.endswith('.swift'))
  normalized=re.sub(r'[^a-z0-9]+','',text.lower())
  for phrase in ('record approval response','work','completed','more','record response','history','acknowledgementsnapshotv1','mutationid','expectedrevision','receipt'):
   if re.sub(r'[^a-z0-9]+','',phrase.lower()) not in normalized:fails.append('source semantic missing: '+phrase)
  _validate_structural_source(fails)
 changed=set(c.git('diff','--name-only',c.BASE,'HEAD').splitlines())|set(c.git('diff','--name-only','HEAD').splitlines())|set(c.git('diff','--cached','--name-only').splitlines())|set(c.git('ls-files','--others','--exclude-standard').splitlines());changed.discard('')
 unowned=changed-set(c.PATH_FENCE)
 if unowned:fails.append('unowned changed paths: '+','.join(sorted(unowned)))
 counts={'changedPathCount':len(changed&set(c.PATH_FENCE)),'unownedChangedPathCount':len(unowned),'missingPathCount':sum(not(ROOT/x).is_file() for x in c.PATH_FENCE),'fencePathCount':18,'existingPathCount':4,'newPathCount':14,'productTestUIFixturePathCount':6,'toolingPathCount':8,'s10ReservedOverlapCount':1}
 result={'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL' if not fails else 'FAIL_STATIC','sourceReady':ready,'finalHashesSealed':False,'flagsAllFalse':all(v is False for v in c.FLAGS.values()),'failures':fails,'counts':counts,'selectors':list(c.SELECTORS),'authoritySequence':c.SEQUENCE,'sourceRows':rows}
 print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));return 0 if not fails else 1
if __name__=='__main__':raise SystemExit(main())
