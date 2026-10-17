#!/usr/bin/env python3
"""Verify C42 tooling artifacts, source semantics, corpus, and path fence."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p04_c42_contracts as contracts


def _require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _read_text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _read_json(path: str) -> Any:
    return contracts.read_json(path)



def _current_hosted_unit_fixture_result() -> dict[str, Any]:
    """Check the separate current UNIT Source question, never historical UI."""
    failures: list[str] = []
    rows: list[dict[str, Any]] = []
    selector = "FieldEvidenceAppTests/" + contracts.CURRENT_HOSTED_UNIT_CLASS + "/" + contracts.CURRENT_HOSTED_UNIT_METHOD
    try:
        inputs = contracts.current_hosted_unit_sources(contracts.CURRENT_HOSTED_UNIT_PATH,
            contracts.CURRENT_HOSTED_UNIT_CLASS, contracts.CURRENT_HOSTED_UNIT_METHODS,
            contracts.CURRENT_HOSTED_UNIT_METHOD, contracts.CURRENT_HOSTED_UNIT_DEPENDENCIES)
        rows = inputs["rows"]
        body = inputs["method"]
        contracts.current_source_require(body, (
            "let fixture = try await makeFixture(", "defer { fixture.cleanUp() }",
            "let context = fixture.coordinator.modelContext", "let writer = fixture.coordinator.workspaceWriter",
            "let query = C42Query(context: context, workspaceID: workspaceID)",
            "OperationalContactRowQueryV1(modelContext: context, workspaceID: workspaceID)",
            "OperationalContactCoordinatorV1(query: contactQuery, writer: writer, system: system",
            "PartyAccountabilityCoordinatorV1(writer: writer, idSource: SystemApplicationIDSource())",
            "let setupReceiptCount = try context.fetchCount(FetchDescriptor<MutationReceiptRow>())",
            "let site = try await makeWorkAsset(in: fixture, label:",
            "XCTAssertTrue(try context.fetch(FetchDescriptor<ServicePartyRow>()).isEmpty,",
            "guard case .party = try await workflow.execute(.commitParty(seedParty))",
            "guard case .contact = try await workflow.execute(.commitContact(seedPhone))",
            "guard case .siteRole = try await workflow.execute(.commitSiteRole(seedRole))",
            "let revisionBefore = try writer.currentRevision()", "let rowsBefore = try c42CanonicalRows(in: context)",
            "XCTAssertEqual(rowsBefore.parties.count, 1)", "XCTAssertEqual(rowsBefore.contacts.count, 1)",
            "XCTAssertEqual(rowsBefore.siteRoles.count, 1)",
            "XCTAssertEqual(rowsBefore.receipts.count, setupReceiptCount + 4,",
            "XCTAssertTrue(rowsBefore.handoffIntents.isEmpty)",
            "let partyPreview = try await workflow.previewCreateParty(workspaceID: workspaceID, partyID: proposedPartyID",
            "let contactPreview = try await workflow.previewCreateContact(workspaceID: workspaceID, contactPointID: proposedContactID, partyID: partyID, kind: .email",
            "let rolePreview = try await workflow.previewAppendSiteRole(workspaceID: workspaceID, eventID: proposedRoleID, siteID: site.siteID, partyID: partyID, role: .serviceProvider",
            "XCTAssertTrue(partyPreview.zeroWrite)", "XCTAssertTrue(contactPreview.zeroWrite)", "XCTAssertTrue(rolePreview.zeroWrite)",
            "XCTAssertEqual(partyPreview.impact.operation, .createParty)",
            "XCTAssertEqual(partyPreview.impact.affectedPartyIDs, [proposedPartyID])",
            "XCTAssertEqual(contactPreview.impact.operation, .createContact)",
            "XCTAssertEqual(contactPreview.impact.affectedPartyIDs, [partyID])",
            "XCTAssertEqual(contactPreview.impact.affectedContactPointIDs, [proposedContactID])",
            "XCTAssertEqual(contactPreview.impact.preferredScopes, contactPreview.mutation.preferredScopes)",
            "XCTAssertEqual(contactPreview.impact.preferredScopes.map(\\.partyID), [partyID])",
            "XCTAssertEqual(contactPreview.impact.preferredScopes.map(\\.kind), [.email])",
            "XCTAssertEqual(contactPreview.impact.preferredScopes.map(\\.activeContactPointIDs), [[proposedContactID]])",
            "XCTAssertEqual(contactPreview.impact.preferredScopes.map(\\.preferredContactPointID), [Optional(proposedContactID)])",
            "XCTAssertTrue(contactPreview.mutation.handoffIntents.isEmpty)",
            "XCTAssertEqual(rolePreview.impact.operation, .appendSiteRole)",
            "XCTAssertEqual(rolePreview.impact.affectedPartyIDs, [partyID])",
            "XCTAssertEqual(rolePreview.impact.affectedSiteRoleEventIDs, [proposedRoleID])",
            "for impact in [partyPreview.impact, contactPreview.impact, rolePreview.impact]",
            "XCTAssertEqual(impact.cascadeCount, 0)", "XCTAssertEqual(impact.identityMergeCount, 0)",
            "XCTAssertEqual(impact.warnings, [.equalValuesRemainDistinct, .noCascade, .operationalPurposeOnly, .customerAndSiteLabelsArePresentationOnly])",
            "let history = try workflow.history(workspaceID: workspaceID, partyRevisions: parties, contactRevisions: contacts, siteRoleEvents: roles)",
            "XCTAssertEqual(history.partyRevisions, parties)", "XCTAssertEqual(history.contactRevisions, contacts)",
            "XCTAssertEqual(history.siteRoleEvents, roles)",
            "callbacks.surface(party: partyPreview, history: history)",
            "callbacks.surface(contact: contactPreview, history: history)",
            "callbacks.surface(role: rolePreview, history: history)",
            "for (root, title) in zip(AppRootV1.frozenOrder, titles)", "try scene.restore()", "try scene.select(root)",
            "let mounted = try mountC42ShippingShell(fixture)", "await fulfillment(of: [bound], timeout: 20)",
            "let tabBar = try XCTUnwrap(observedTabBar)",
            "XCTAssertEqual(tabBar.items?.map(\\.title), titles.map(Optional.some))",
            "XCTAssertEqual(tabBar.items?.map(\\.accessibilityIdentifier), identifiers.map(Optional.some))",
            "XCTAssertEqual(tabBar.selectedItem?.title, title)",
            "switch root { case .today, .work:",
            "let loadedRootIdentifier = root == .today ? ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier : ProductionWorkRootViewV1.screenAccessibilityIdentifier",
            "let rootContentMounted = await waitForMountedScreen(loadedRootIdentifier, from: mounted.host)",
            "XCTAssertTrue(rootContentMounted,",
            "XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: mounted.host).found)",
            "case .assets, .reports: break",
            "let settings = try mountC42Settings(fixture)", "defer { settings.unmount() }",
            "let settingsMounted = await waitForMountedScreen(AppShellView.settingsScreenAccessibilityIdentifier, from: settings.host)",
            "XCTAssertTrue(settingsMounted,", "XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: settings.host).found)",
            "for surface in surfaces", "let mounted = try mountC42Content(AnyView(NavigationStack { surface }.modelContext(context)))",
            "let surfaceMounted = await waitForMountedScreen(SemanticSelector.screen, from: mounted.host)",
            "XCTAssertTrue(surfaceMounted,", "XCTAssertTrue(nativeScreenObservation(SemanticSelector.screen, from: mounted.host).found)",
            "XCTAssertTrue(callbacks.previewRequests.isEmpty)", "XCTAssertEqual(callbacks.confirmationCount, 0)",
            "surface.onRequestPreview(operation)",
            "XCTAssertEqual(callbacks.previewRequests, [.createParty, .createContact, .appendSiteRole])",
            "XCTAssertTrue(system.requests.isEmpty)", "XCTAssertFalse(context.hasChanges)",
        ), "C42 actual contained boundary", failures)
        contracts.current_source_literal(body, 'let titles = ["Today", "Work", "Assets", "Reports"]', "C42 accepted tabs", inputs, failures)
        contracts.current_source_literal(body, 'let identifiers = ["v23.tab.today", "v23.tab.work", "s1.tab.signs", "s1.tab.reports"]', "C42 accepted tab identifiers", inputs, failures)
        contracts.current_source_order(body, (
            "let site = try await makeWorkAsset(", "XCTAssertTrue(try context.fetch(FetchDescriptor<ServicePartyRow>()).isEmpty,",
            "workflow.execute(.commitParty(seedParty))", "workflow.execute(.commitContact(seedPhone))",
            "workflow.execute(.commitSiteRole(seedRole))", "let revisionBefore = try writer.currentRevision()",
            "let rowsBefore = try c42CanonicalRows(in: context)",
            "let partyPreview = try await workflow.previewCreateParty(",
            "XCTAssertEqual(try writer.currentRevision(), revisionBefore)", "XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)",
            "let contactPreview = try await workflow.previewCreateContact(",
            "XCTAssertEqual(try writer.currentRevision(), revisionBefore)", "XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)",
            "let rolePreview = try await workflow.previewAppendSiteRole(",
            "XCTAssertEqual(try writer.currentRevision(), revisionBefore)", "XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)",
            "let history = try workflow.history(", "let mounted = try mountC42ShippingShell(fixture)",
            "await fulfillment(of: [bound], timeout: 20)", "let tabBar = try XCTUnwrap(observedTabBar)",
            "switch root { case .today, .work:",
            "let loadedRootIdentifier = root == .today ? ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier : ProductionWorkRootViewV1.screenAccessibilityIdentifier",
            "let rootContentMounted = await waitForMountedScreen(loadedRootIdentifier, from: mounted.host)",
            "XCTAssertTrue(rootContentMounted,",
            "XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: mounted.host).found)",
            "case .assets, .reports: break",
            "let settings = try mountC42Settings(fixture)", "XCTAssertTrue(settingsMounted,",
            "XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: settings.host).found)",
            "for surface in surfaces", "XCTAssertTrue(surfaceMounted,",
            "XCTAssertTrue(nativeScreenObservation(SemanticSelector.screen, from: mounted.host).found)",
            "surface.onRequestPreview(operation)", "XCTAssertEqual(callbacks.previewRequests, [.createParty, .createContact, .appendSiteRole])",
            "XCTAssertEqual(try writer.currentRevision(), revisionBefore)", "XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)",
        ), "C42 seed/preview/positive-observation order", failures)
        compact = re.sub(r"\s+", "", body["code"])
        for expression, count in (
            ("XCTAssertEqual(trywriter.currentRevision(),revisionBefore)", 8),
            ("XCTAssertEqual(tryc42CanonicalRows(in:context),rowsBefore)", 8),
        ):
            _require(compact.count(expression) == count, "C42 immutable conservation stage count differs: " + expression, failures)
        measured = body["code"].split("let revisionBefore", 1)[1]
        _require(re.search(r"\b(?:execute|commit|insert|delete|save|handOff)\s*\(", measured) is None,
                 "C42 measured interval contains a write or handoff call", failures)
        _require("v23PhaseGate" not in body["code"], "C42 must not borrow an unrelated feature gate", failures)

        path = contracts.CURRENT_HOSTED_UNIT_PATH
        snapshot = contracts.current_source_block(inputs, path, r"func\s+c42CanonicalRows", "C42 immutable rows")
        for row, identity in (("ServicePartyRow", "partyID"), ("ServiceContactPointRow", "contactPointID"),
                              ("SitePartyRoleEventRow", "eventID"), ("SystemHandoffIntentRow", "intentID")):
            contracts.current_source_require(snapshot, ("context.fetch(FetchDescriptor<" + row + ">())",
                ".sorted { $0." + identity + ".uuidString < $1." + identity + ".uuidString }"), "C42 immutable " + row, failures)
        contracts.current_source_require(snapshot, ("context.fetch(FetchDescriptor<MutationReceiptRow>())",
            ".sorted { $0.receiptIdentity < $1.receiptIdentity }.map { C42BoundaryReceipt($0) }"), "C42 receipt snapshots", failures)
        _require(snapshot["code"].count("_ = try row.value()") == 4 and snapshot["code"].count("return row.canonicalData") == 4,
                 "C42 row representations must validate and copy bytes, not retain row objects", failures)
        receipt = contracts.current_source_block(inputs, path, r"init\s*\(\s*_\s+row:\s*MutationReceiptRow", "C42 full receipt copy")
        for field in ("mutationID", "workspaceMutationKey", "receiptIdentity", "workspaceID", "replicaID", "localSequence",
                      "commandKind", "envelopeData", "envelopeSHA256", "receiptData", "receiptSHA256",
                      "reversalBasisData", "reversalBasisSHA256", "semanticReversalData"):
            contracts.current_source_require(receipt, (field + " = row." + field,), "C42 full receipt", failures)
        expected = contracts.current_source_block(inputs, path, r"func\s+c42Expected", "C42 actual expected revision")
        contracts.current_source_require(expected, ("let current = try writer.currentRevision()",
            "WorkspaceEntityRevisionV1(identity: identity, revision: 0)",
            "workspaceRevision: current.revision", "writerInstanceID: current.writerInstanceID"), "C42 expected revision", failures)
        mount = contracts.current_source_block(inputs, path, r"func\s+mountC42ShippingShell", "C42 production shell")
        contracts.current_source_require(mount, ("var shell = AppShellView(", "storeSession: fixture.coordinator",
            "contentAccess: try XCTUnwrap(fixture.presentation.renderAccess)",
            "myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess)",
            "shell.onNativeTabsBoundForTesting = onTabs",
            "mountC42Content(AnyView(shell.modelContext(fixture.coordinator.modelContext)))"), "C42 production shell", failures)
        _require("v23PhaseGate" not in mount["code"], "C42 shell must use shipping environment", failures)
        settings = contracts.current_source_block(inputs, path, r"func\s+mountC42Settings", "C42 production Settings")
        contracts.current_source_require(settings, ("let settings = SettingsPlaceholderView(modelContext: fixture.coordinator.modelContext",
            "settings.reminderSettingsSectionForTesting(section)",
            ".environment(\\.appContentAccess, try XCTUnwrap(fixture.presentation.renderAccess))"), "C42 production Settings", failures)
        host = contracts.current_source_block(inputs, path, r"func\s+mountC42Content", "C42 actual host")
        contracts.current_source_require(host, ("UIHostingController(rootView: content)", "window.rootViewController = host",
            "window.makeKeyAndVisible()", "host.view.layoutIfNeeded()",
            "return SIG1MountedShellV1(window: window, host: host, previousKeyWindow: previousKeyWindow)"), "C42 actual host", failures)
        view = inputs["sources"]["FieldEvidenceApp/Features/Contacts/PartyContactSiteRoleWorkflowView.swift"]
        contracts.current_source_require(view, (".nativeScreenObservationWitnessV1(Self.screenAccessibilityIdentifier)",
            "onRequestPreview(operation)"), "C42 real view witness/request binding", failures)
        system = contracts.current_source_block(inputs, path, r"func\s+handOff", "C42 injected handoff recorder")
        contracts.current_source_require(system, ("requests.append(request)", "disposition: .systemUnavailable"), "C42 injected handoff", failures)
        query = inputs["sources"]["FieldEvidenceAppTests/V9_105PartyContactSiteRoleWorkflowTests.swift"]
        contracts.current_source_require(query, ("@MainActor final class C42Query: PartyContactSiteRoleWorkflowQueryingV1",
            "FetchDescriptor<ServicePartyRow>(", "FetchDescriptor<ServiceContactPointRow>(", "FetchDescriptor<SitePartyRoleEventRow>("), "C42 actual query", failures)
        today = inputs["sources"]["FieldEvidenceApp/Features/Shell/ProductionMyDayRootViewV1.swift"]
        contracts.current_source_require(today, (
            "if phaseGate.allows(.myDay) { ProductionMyDayCurrentWorkRootV1(source: source) } else { ProductionTodayPhaseOneEmptyStateV1() }",
            "NativeScreenObservationAnchorV1(identifier: ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier)",
        ), "C42 actual loaded Phase 1 Today witness", failures)
        work = inputs["sources"]["FieldEvidenceApp/Features/Shell/ProductionWorkRootViewV1.swift"]
        contracts.current_source_require(work, (
            "if source.snapshot != nil { NativeScreenObservationAnchorV1(identifier: Self.screenAccessibilityIdentifier)",
        ), "C42 actual loaded Work witness", failures)
        gate = inputs["sources"]["FieldEvidenceApp/App/V23PhaseGateV1.swift"]
        contracts.current_source_require(gate, (
            "static let shipping = V23PhaseGateV1(through: .phase1)",
            "static let defaultValue: V23PhaseGateV1 = .shipping",
        ), "C42 unchanged shipping environment", failures)
        support = "FieldEvidenceAppTests/V23ProductionFourRootShellTests.swift"
        wait = contracts.current_source_block(inputs, support, r"func\s+waitForMountedScreen", "C42 bounded observer")
        contracts.current_source_require(wait, ("for _ in 0..<200", "nativeScreenObservation(identifier, from: host).found",
            "Task.sleep(nanoseconds: 25_000_000)", "return false"), "C42 bounded observer", failures)
        unmount = contracts.current_source_block(inputs, "FieldEvidenceAppTests/V23ProductionSignoffResponseJourneyTests.swift",
            r"func\s+unmount", "C42 existing cleanup")
        contracts.current_source_require(unmount, ("guard isMounted else { return }", "isMounted = false",
            "window.isHidden = true", "window.rootViewController = nil", "previousKeyWindow?.makeKeyAndVisible()"), "C42 existing cleanup", failures)
    except (OSError, ValueError, UnicodeError, IndexError) as error:
        failures.append("currentHostedUnitSource:" + str(error))
    return {"cardID": contracts.CARD, "question": "CURRENT_HOSTED_UNIT_FIXTURE_SOURCE_STRUCTURE",
            "result": "FAIL_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE" if failures else "PASS_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE_ONLY",
            "failures": failures, "selector": selector, "testBundle": "FieldEvidenceAppTests",
            "currentSourceInputRows": rows, "SourceReady": False, "nativeExecution": False,
            "acceptanceCredit": False, "gateCredit": False, "releaseReady": False,
            "historicalArtifactsRegenerated": False, "historicalAllocationVerifiedByThisMode": False,
            "historicalDeclaredUIPath": contracts.NEW_PRODUCT_PATHS[5],
            "historicalDeclaredUIPathPresent": (ROOT / contracts.NEW_PRODUCT_PATHS[5]).is_file(),
            "dynamicallyObservedShippingFrontDoors": ["TODAY_PHASE1_CONTENT", "WORK_LOADED_CONTENT", "SETTINGS_SCREEN"],
            "unobservedShippingRootContentAndRoutes": ["ASSETS", "REPORTS"],
            "unobservedShippingRootContentAndRoutesStatus": "PENDING",
            "liveRouteOrContactPermissionAdoption": False, "physicalMenuOrAccessibilityQualification": False}

def _validate_corpus(failures: list[str]) -> None:
    try:
        corpus = _read_json(contracts.NEW_PRODUCT_PATHS[4])
    except (OSError, ValueError) as error:
        failures.append(f"corpus:{error}")
        return
    _require(isinstance(corpus, dict), "corpus must be an object", failures)
    if not isinstance(corpus, dict):
        return
    expected = contracts._corpus_expectations()
    _require(set(corpus) == set(contracts.CORPUS_TOP_LEVEL_KEYS), "corpus top-level key set differs", failures)
    for key, value in expected.items():
        _require(corpus.get(key) == value, f"corpus {key} differs", failures)
    claims = corpus.get("claims", {})
    _require(isinstance(claims, dict) and all(value is False for value in claims.values()), "corpus claims must all be false", failures)


def _validate_flags(documents: dict[str, Any], failures: list[str]) -> bool:
    result = True
    for path, document in documents.items():
        if path == contracts.SCHEMA:
            continue
        flags = document.get("flags") if isinstance(document, dict) else None
        ok = isinstance(document, dict) and flags == contracts.FLAGS and document.get("finalHashesSealed") is False
        result = result and ok
        _require(ok, f"artifact flags/final hash boundary differs: {path}", failures)
    return result


def _validate_documents(documents: dict[str, Any], expected: dict[str, Any], failures: list[str]) -> None:
    expected_paths = {contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST}
    _require(set(documents) == expected_paths, "artifact set differs", failures)
    for path in expected_paths:
        _require(documents.get(path) == expected.get(path), f"deterministic artifact differs: {path}", failures)
    contract = documents.get(contracts.CONTRACT, {})
    _require(isinstance(contract, dict) and contract.get("contract") == "PartyContactSiteRoleWorkflowContractV1", "contract identity differs", failures)
    if not isinstance(contract, dict):
        return
    _require(contract.get("scenarioEvidenceIDs") == list(contracts.SELECTORS), "contract evidence IDs differ", failures)
    _require(contract.get("scenarioRows") == list(contracts.SCENARIO_ROWS), "contract scenario mapping differs", failures)
    requirements = contract.get("requirements", {})
    for key in (
        "distinctUUIDIdentity", "equalValuesWarnOnly", "warningsDoNotMerge", "exactImpactPreview", "zeroWritePreview",
        "partyRetirementIrreversible", "contactRetirementReversible", "preferredPerPartyAndKind", "roleReversalAppendOnly",
        "historicalSnapshotsFrozen", "receiptFirstRecovery", "explicitExpectedRevisions", "manualPartyAndContactActions",
        "noAutoPartyCreation", "noContactsAccess", "noPurposeConflation", "noNewModel", "noNewSchemaFamily",
        "noNewStore", "noNewWriter", "noNewMigration", "noNewRoot", "noNetwork", "noTelemetry", "noBackend",
        "fiveEvidenceScenarios", "finalHashesUnsealed",
    ):
        _require(requirements.get(key) is True, f"contract requirement disabled: {key}", failures)
    _require(requirements.get("cascadeCount") == 0 and requirements.get("identityMergeCount") == 0, "impact zero counts differ", failures)
    for key, value in contracts.CLAIMS.items():
        _require(requirements.get(key) is value, f"prohibited claim boundary differs: {key}", failures)
    _require(requirements.get("scenarioSelectors") == list(contracts.SELECTORS), "contract selectors differ", failures)
    _require(contract.get("directPrerequisites") == contracts.DIRECT_PREREQUISITES, "contract prerequisite edges differ", failures)
    _require(contract.get("contractRefs") == contracts.CONTRACT_REFS, "contract references differ", failures)
    evidence = documents.get(contracts.EVIDENCE, {})
    _require(isinstance(evidence, dict) and evidence.get("receipt") == "PartyContactSiteRoleWorkflowEvidenceReceiptV1", "evidence receipt identity differs", failures)
    _require(isinstance(evidence, dict) and evidence.get("acceptanceCredit") is False, "evidence acceptance credit differs", failures)
    brand = documents.get(contracts.BRAND, {})
    _require(isinstance(brand, dict) and brand.get("requiresAcceptedS10_6Reconciliation") is True, "brand S10 reconciliation differs", failures)
    _require(isinstance(brand, dict) and brand.get("uiAdoptionSkipped") is True and brand.get("uiAcceptanceCredit") is False, "brand UI boundary differs", failures)
    manifest = documents.get(contracts.MANIFEST, {})
    _require(isinstance(manifest, dict) and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence differs", failures)
    counts = manifest.get("counts", {}) if isinstance(manifest, dict) else {}
    for key, expected_value in {"fencePathCount": 18, "existingPathCount": 4, "newPathCount": 14, "productTestUIFixturePathCount": 6, "toolingPathCount": 8, "durableFamilyCount": 0, "modelDeltaCount": 0, "schemaDeltaCount": 0, "migrationCount": 0, "storeDeltaCount": 0, "writerDeltaCount": 0, "rendererDeltaCount": 0, "backendDeltaCount": 0, "s10ReservationOverlapCount": 0}.items():
        _require(counts.get(key) == expected_value, f"manifest count differs: {key}", failures)


def _swift_code(text: str) -> str:
    text = re.sub(r"(?s)/\*.*?\*/", " ", text)
    return re.sub(r"//[^\r\n]*", " ", text)


def _normalized(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def _any(text: str, *needles: str) -> bool:
    return any(needle in text for needle in needles)


def _method_bodies(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    pattern = re.compile(r"\bfunc\s+(test\w*)\s*\([^)]*\)[^{]*\{")
    for match in pattern.finditer(text):
        depth = 0
        start = match.end() - 1
        for index in range(start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    result[match.group(1)] = text[match.start():index + 1]
                    break
    return result


def _validate_source(failures: list[str]) -> None:
    party = _swift_code(_read_text(contracts.EXISTING_PATHS[0]))
    party_coordinator = _swift_code(_read_text(contracts.EXISTING_PATHS[1]))
    contact = _swift_code(_read_text(contracts.EXISTING_PATHS[2]))
    contact_coordinator = _swift_code(_read_text(contracts.EXISTING_PATHS[3]))
    workflow = _swift_code(_read_text(contracts.NEW_PRODUCT_PATHS[0]))
    coordinator = _swift_code(_read_text(contracts.NEW_PRODUCT_PATHS[1]))
    view = _swift_code(_read_text(contracts.NEW_PRODUCT_PATHS[2]))
    tests_raw = _read_text(contracts.NEW_PRODUCT_PATHS[3])
    tests = _swift_code(tests_raw)
    fixture = _read_text(contracts.NEW_PRODUCT_PATHS[4])
    ui_raw = _read_text(contracts.NEW_PRODUCT_PATHS[5])
    ui = _swift_code(ui_raw)
    source = "\n".join((party, party_coordinator, contact, contact_coordinator, workflow, coordinator, view, tests, ui))
    new_source = "\n".join((workflow, coordinator, view))

    for token in ("ServicePartyReferenceV1", "SitePartyRoleEventV1", "ServiceContactPointV1", "PartyContactSiteRoleWorkflowFailureV1", "PartyContactSiteRoleImpactV1", "PartyWorkflowPreviewV1", "OperationalContactWorkflowPreviewV1", "SiteRoleWorkflowPreviewV1", "PartyContactSiteRoleHistoryProjectionV1", "PartyContactSiteRoleWorkflowQueryingV1"):
        _require(token in source, f"C42 contract/source token missing: {token}", failures)
    for token in ("PartyContactSiteRoleOperationV1", "PartyContactSiteRoleWarningV1", "equalValuesRemainDistinct", "noCascade", "identityMergeCount", "cascadeCount", "zeroWrite"):
        _require(token in workflow, f"C42 workflow semantic token missing: {token}", failures)
    for token in ("preferredScopes", "ServiceContactPreferredScopeV1", "siteRoleHistoryIsAppendOnly", "partyAndContactHistoryIsCallerBounded", "validateSupersession"):
        _require(token in workflow or token in contact, f"C42 history/preferred semantic token missing: {token}", failures)
    _require(re.search(r"cascadeCount\s*=\s*0", workflow) is not None, "C42 cascade zero invariant missing", failures)
    _require(re.search(r"identityMergeCount\s*=\s*0", workflow) is not None, "C42 identity merge zero invariant missing", failures)
    _require("retiredParty" in workflow or "retiredParty" in coordinator, "C42 party retirement guard missing", failures)
    _require(_any(source.lower(), "reactivatecontact", "reactivate"), "C42 reversible contact retirement seam missing", failures)
    _require(_any(source.lower(), "receipt", "recover") and _any(coordinator.lower(), "recover"), "C42 receipt-first recovery seam missing", failures)
    _require(_any(workflow.lower(), "historical", "snapshot", "partyrevisions", "contactrevisions"), "C42 historical snapshot seam missing", failures)

    _require(re.search(r"\b(?:class|struct|actor|enum|protocol)\s+\w*(?:Store|Writer|Renderer|Importer|Backend|Network|Telemetry|Root|Merge)\w*", new_source, re.IGNORECASE) is None, "parallel C42 infrastructure declaration", failures)
    for pattern in (r"\bURLSession\b", r"\bURLRequest\b", r"\bNWConnection\b", r"\bWebSocket\b", r"\bCloudKit\b", r"\bMetricKit\b", r"\bFirebase\b", r"\bAmplitude\b", r"\bMixpanel\b", r"\bCNContactStore\b", r"\bEventKit\b"):
        _require(re.search(pattern, new_source, re.IGNORECASE) is None, f"prohibited C42 integration token: {pattern}", failures)
    for token in ("PartyContactSiteRoleWorkflowView", "Customer", "Site", "preferred", "history", "retire"):
        _require(token.lower() in view.lower(), f"C42 view binding missing: {token}", failures)
    _require("V23-P04-C42" in ui, "UI lane does not bind C42", failures)
    _require(len(re.findall(r"throw\s+XCTSkip\s*\(", ui_raw)) == 1, "UI lane must have one no-launch skip", failures)
    _require(re.search(r"\b(?:XCUIApplication|app)\s*\([^)]*\)\s*\.launch\s*\(", ui, re.IGNORECASE) is None, "UI lane must not launch", failures)

    for match in re.finditer(r"\bXCTAssert[A-Za-z0-9_]*\s*\(", tests_raw):
        depth = 0
        end = None
        for index in range(match.end() - 1, len(tests_raw)):
            if tests_raw[index] == "(":
                depth += 1
            elif tests_raw[index] == ")":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is not None:
            _require("await" not in tests_raw[match.start():end], "await inside XCTest assertion autoclosure", failures)

    methods = _method_bodies(tests)
    found: dict[str, str] = {}
    for name, body in methods.items():
        match = re.search(r"V23P04C42([GAHIR]01)", name)
        if match:
            identifier = match.group(1)
            _require(identifier not in found, f"duplicate evidence method: {identifier}", failures)
            found[identifier] = body
    _require(tuple(found) == ("G01", "A01", "H01", "I01", "R01"), "test evidence method order differs", failures)
    terms = {
        "G01": (("party", "contact", "create"), ("equal", "distinct", "uuid"), ("preferred",), ("role",), ("history",), ("impact", "cascade")),
        "A01": (("rename", "edit", "retire"), ("reactivate", "reversible"), ("preferred", "kind"), ("supersede", "reverse")),
        "H01": (("equal", "duplicate"), ("stale",), ("workspace",), ("divergent", "mutation"), ("impact", "no_effect", "invalid_context")),
        "I01": (("receipt",), ("recover", "replay"), ("effect",), ("mutation",)),
        "R01": (("histor", "snapshot"), ("namespace", "sibling"), ("party", "retir"), ("contact", "reactivat")),
    }
    for identifier, required in terms.items():
        body = _normalized(found.get(identifier, ""))
        for aliases in required:
            _require(any(_normalized(token) in body for token in aliases), f"{identifier} test lacks semantic coverage: {'/'.join(aliases)}", failures)
    _require("V9_105PartyContactSiteRoleWorkflowTests" in tests and "testV23P04C42" in tests, "tests do not bind C42 workflow", failures)
    try:
        fixture_value = json.loads(fixture)
    except json.JSONDecodeError as error:
        failures.append(f"source fixture JSON malformed: {error}")
        fixture_value = {}
    _require(isinstance(fixture_value, dict), "source fixture must be an object", failures)
    if isinstance(fixture_value, dict):
        _require(fixture_value == contracts._corpus_expectations(), "source fixture corpus differs", failures)


def _validate_fence(failures: list[str]) -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in contracts.git(*args).splitlines() if line}
    changed = names("diff", "--name-only", contracts.BASE, "HEAD") | names("diff", "--name-only", "HEAD") | names("diff", "--cached", "--name-only") | names("ls-files", "--others", "--exclude-standard")
    unowned = changed - set(contracts.PATH_FENCE)
    _require(not unowned, "unowned changed paths: " + ",".join(sorted(unowned)), failures)
    return {"changedPathCount": len(changed & set(contracts.PATH_FENCE)), "unownedChangedPathCount": len(unowned), "missingPathCount": sum(not (ROOT / path).is_file() for path in contracts.PATH_FENCE), "s10ReservationOverlapCount": 0, "fencePathCount": 18, "existingPathCount": 4, "newPathCount": 14, "productTestUIFixturePathCount": 6, "toolingPathCount": 8, "durableFamilyCount": 0, "modelDeltaCount": 0, "schemaDeltaCount": 0, "migrationCount": 0, "storeDeltaCount": 0, "writerDeltaCount": 0, "rendererDeltaCount": 0, "backendDeltaCount": 0}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every C42 product/test/UI/fixture source path")
    parser.add_argument("--json", action="store_true", help="emit a JSON result")
    parser.add_argument("--current-hosted-unit-fixture", action="store_true",
                        help="check current app-hosted UNIT Source only; preserve historical card/UI artifacts")
    args = parser.parse_args()
    if args.current_hosted_unit_fixture:
        if args.complete:
            parser.error("--complete belongs to the historical allocation question")
        result = _current_hosted_unit_fixture_result()
        print(json.dumps(result, sort_keys=True, indent=2 if args.json else None))
        return 1 if result["failures"] else 0
    failures: list[str] = []
    try:
        contracts.authority()
    except Exception as error:
        failures.append(f"authority:{error}")
    try:
        source_rows, source_ready = contracts.rows()
    except Exception as error:
        failures.append(f"sourceRows:{error}")
        source_rows, source_ready = [], False
    _validate_corpus(failures)
    try:
        expected = contracts.documents()
    except Exception as error:
        failures.append(f"documents:{error}")
        expected = {}
    documents: dict[str, Any] = {}
    for path in (contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST):
        try:
            documents[path] = _read_json(path)
        except (OSError, ValueError) as error:
            failures.append(f"artifact:{error}")
    flags_all_false = False
    if expected and len(documents) == 5:
        _validate_documents(documents, expected, failures)
        flags_all_false = _validate_flags(documents, failures)
    if source_ready:
        try:
            _validate_source(failures)
        except (OSError, ValueError) as error:
            failures.append(f"source:{error}")
    elif args.complete:
        failures.append("complete:missing C42 source paths")
    try:
        counts = _validate_fence(failures)
    except Exception as error:
        failures.append(f"fence:{error}")
        counts = {}
    result = {"cardID": contracts.CARD, "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC", "sourceReady": source_ready, "finalHashesSealed": contracts.FINAL_HASHES_SEALED, "flagsAllFalse": flags_all_false, "failures": failures, "counts": counts, "fencePathCount": 18, "existingPathCount": 4, "newPathCount": 14, "productTestUIFixturePathCount": 6, "toolingPathCount": 8, "selectors": list(contracts.SELECTORS), "authoritySequence": contracts.SEQUENCE, "sourceRows": source_rows}
    print(json.dumps(result, sort_keys=True, indent=2 if args.json else None))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
