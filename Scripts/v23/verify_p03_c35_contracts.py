#!/usr/bin/env python3
"""Fail-closed static verifier for V23-P03-C35."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import p03_c35_contracts as contracts

class VerificationError(ValueError): pass
def require(value: bool, message: str) -> None:
    if not value: raise VerificationError(message)
def git(root: Path,*args: str)->str:
    return subprocess.run(["git","-C",str(root),*args],check=True,capture_output=True,text=True).stdout.strip()
def changed(root: Path)->set[str]:
    tracked=set(filter(None,git(root,"diff","--name-only",contracts.BASE_HEAD,"--").splitlines()))
    untracked=set(filter(None,git(root,"ls-files","--others","--exclude-standard").splitlines()))
    return {value.replace("\\","/") for value in tracked|untracked}
def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"),object_pairs_hook=lambda pairs:_closed(pairs,path))
def _closed(pairs,path):
    result={}
    for key,value in pairs:
        if key in result: raise VerificationError(f"duplicate JSON key {key}: {path}")
        result[key]=value
    return result

def verify(root: Path)->dict:
    require(git(root,"rev-parse","HEAD")==contracts.BASE_HEAD,"base head differs")
    require(git(root,"show","-s","--format=%T","HEAD")==contracts.BASE_TREE,"base tree differs")
    require(len(contracts.PATH_FENCE)==58 and len(set(contracts.PATH_FENCE))==58,"exact 58-path fence differs")
    actual=changed(root)
    require(actual.issubset(set(contracts.PATH_FENCE)),"changed path escapes the 58-path fence")
    require(set(contracts.GENERATED_PATHS+[contracts.TEST_PATH,contracts.FIXTURE_PATH]).issubset(actual),"required new evidence path is unchanged or missing")
    require(all((root/path).is_file() for path in contracts.PATH_FENCE),"fenced artifact missing")
    corpus=load(root/contracts.FIXTURE_PATH)
    require(corpus["schema"]=="V21P03C35LocationPlacementCompositionCorpusV1" and corpus["schemaVersion"]==1,"corpus identity differs")
    require(corpus["flatMigration"]=={"sourceSchema":5,"destinationSchema":6,"assetIDs":["40000000-0000-4000-8000-000000000001","40000000-0000-4000-8000-000000000002"],"baselineLocationNodeID":None,"baselineEventKind":"MIGRATED_BASELINE","eventsPerAsset":1,"preservesSiteAndAssetIDs":True},"migration vector differs")
    require(len(corpus["nodes"])==4 and len(corpus["hostileCases"])==12 and len(set(corpus["hostileCases"]))==12,"fixed hierarchy/hostile matrix differs")
    placements=corpus["placementHistory"]
    asset_ids=corpus["flatMigration"]["assetIDs"]
    require(len(placements)==4 and {row["assetID"] for row in placements}==set(asset_ids),"both asset placement histories are not complete")
    required_placement={"schemaVersion","eventID","workspaceID","assetID","siteID","locationNodeID","predecessorID","kind","physicalEpisodeID","continuity","pathNodeIDs","mutationID","occurredAtMilliseconds","eventSHA256","tip"}
    require(all(set(row)==required_placement for row in placements),"placement row fields differ")
    for asset_id in asset_ids:
        history=[row for row in placements if row["assetID"]==asset_id]
        require(len(history)==2 and sum(bool(row["tip"]) for row in history)==1 and
                sum(row["predecessorID"] is None for row in history)==1,"placement root/tip closure differs")
        tip=next(row for row in history if row["tip"]); root_row=next(row for row in history if row["predecessorID"] is None)
        require(tip["predecessorID"]==root_row["eventID"],"placement predecessor reachability differs")
    edges=corpus["compositionHistory"]
    require(all(row["parentAssetID"] in asset_ids and row["childAssetID"] in asset_ids for row in edges),"composition endpoint missing")
    require(sum(bool(row["isActive"]) for row in edges)==1 and sum(not bool(row["isActive"]) for row in edges)==1,"active/retired composition closure differs")
    require(len({row["edgeID"] for row in edges})==1 and len({row["eventID"] for row in edges})==2 and
            edges[1]["predecessorID"]==edges[0]["eventID"],"composition fixture does not preserve stable edge/event history identity")
    require([row["id"] for row in corpus["deletionMatrix"]]==["last-asset","active-component-parent","node-with-active-asset","archived-empty-node","erase-all"],"deletion matrix differs")
    require(corpus["releaseAbsence"]=={"nativeCompileRan":False,"hostedDispatchEnabled":False,"adoptionEnabled":False,"acceptanceCredit":False,"releaseCredit":False,"phase10PollingDuringParallelExecution":False,"requiresAcceptedS10_6Reconciliation":True},"release posture differs")
    schema=load(root/contracts.SCHEMA_PATH)
    require(schema==contracts.schema(corpus),"strict Draft 2020-12 corpus schema differs")
    require("const" not in schema and schema.get("additionalProperties") is False,"schema is const-only or open")
    test=(root/contracts.TEST_PATH).read_text(encoding="utf-8")
    methods=re.findall(r"\bfunc\s+(testV9_LocationHierarchyPlacementComposition[A-Za-z0-9_]*)\s*\(",test)
    require(methods==contracts.TEST_METHODS,"exact five test methods differ")
    require(test.count("func testV9_LocationHierarchyPlacementComposition")==5,"test count differs")
    require("@MainActor" in test,"Swift 6 main-actor isolation missing")
    for token in ("LocationHierarchyPolicyV1.validate", "AssetPlacementHistoryV1.validate",
                  "AssetCompositionPolicyV1.validate", "LocationMigrationReceiptV1(",
                  "LocationPersistenceCodecV1.decode", "CompletedLocationCompositionSnapshotV1.build(",
                  "encodeSemanticRecords", "V4BackupRecordsV1("):
        require(token in test,f"executable production seam missing from tests: {token}")
    hierarchy=(root/"FieldEvidenceApp/Domain/Location/LocationHierarchyContractsV1.swift").read_text(encoding="utf-8")
    for token in ("validatePartialChangeSet", "bindingChangedAssetIDs", "filter(\\.changesAssetBinding)",
                  "beforeByID[$0.id] != nil || $0.revision == 1",
                  "LocationHierarchyConsumerImpactV1", "openRoundIDs", "reportConsumerIDs",
                  "searchRebuildRequired", "currentPathProjectionRebuildRequired"):
        require(token in hierarchy,f"hierarchy change-plan guard missing: {token}")
    placement=(root/"FieldEvidenceApp/Domain/Location/AssetPlacementContractsV1.swift").read_text(encoding="utf-8")
    require("source != .migratedBaseline" in placement,"ordinary placement route admits migration-only source")
    require("$0.pathSnapshot.nodes.map(\\.nodeID) != proposedPath.nodes.map(\\.nodeID)" in placement,
            "placement rebase is not bound to the full location identity path")
    composition=(root/"FieldEvidenceApp/Domain/Location/AssetCompositionContractsV1.swift").read_text(encoding="utf-8")
    for token in ("requireID(id)", "currentResultEdge == event.edge", "currentResultEdge == nil",
                  "currentPlacementByAssetID[event.edge.parentAssetID] != nil",
                  "currentPlacementByAssetID[event.edge.childAssetID] != nil",
                  "Reversing the root ADD restores the pre-edge state"):
        require(token in composition,f"composition plan/event guard missing: {token}")
    adapter=(root/"FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift").read_text(encoding="utf-8")
    for token in ("Set(liveTips.map(\\.assetID)) == liveAssetIDs",
                  "Set(placementTips.map(\\.assetID)) == liveAssetIDs",
                  "value.initialPlacementMutationID", "AssetPlacementEventRow(event)",
                  "AssetPlacementHistoryV1.validate([event])"):
        require(token in adapter,f"writer location integration guard missing: {token}")
    mutation=(root/"FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift").read_text(encoding="utf-8")
    writer=(root/"FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift").read_text(encoding="utf-8")
    coordinator=(root/"FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift").read_text(encoding="utf-8")
    require("initialPlacementMutationID" in mutation and "initialPlacementEventID" in mutation and
            "initialPhysicalEpisodeID" in mutation,"first-sign command does not carry atomic placement identity")
    require("writer.execute(command, mutationID: mutationID)" in coordinator and
            "initialPlacementMutationID: initialPlacementMutationID" in coordinator,
            "live first-sign route does not bind placement to the canonical mutation")
    require("requiresInitialPlacementForFirstSign" in writer and
            "value.initialPlacementMutationID.map({ $0 == request.mutationID }) ?? true" in writer and
            "sourceKind != .importedHistory" in writer,
            "real first-sign creation does not reject a missing or mismatched initial placement")
    require("let requiresInitialPlacementForFirstSign = true" in adapter,
            "production persistence adapter does not require initial placement")
    pack_fixture=(root/"FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift").read_text(encoding="utf-8")
    require("initialPlacementMutationID: mutationID" in pack_fixture and
            "mutationID: firstMutationID" in pack_fixture and
            "kind: .assetPlacementEvent" in pack_fixture,
            "real V6 pack-lifecycle first-sign fixture omits atomic placement identity")
    location_coordinator=(root/"FieldEvidenceApp/Application/Location/AssetPlacementChangeCoordinatorV1.swift").read_text(encoding="utf-8")
    require("operationID: plan.operationID" in location_coordinator and
            "placementChanges: [AssetPlacementChangePlanV1] = []" in location_coordinator and
            "hierarchyChange.affectedAssetIDs == deletion.affectedAssetIDs" in location_coordinator,
            "hierarchy child-operation/deletion disposition path is not bound")
    mutation_contract=(root/"FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift").read_text(encoding="utf-8")
    require("$0.operationID == plan.operationID" in mutation_contract and
            "$0.mutationID.rawValue == plan.operationID" in mutation_contract,
            "hierarchy child plan is not bound to the top-level operation")
    migration=(root/"FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift").read_text(encoding="utf-8")
    require("LocationMigrationReceiptV1" in migration and ".migratedBaseline" in migration and
            "LocationMigrationIntegrityV1.validate" in migration,"V5-to-V6 placement migration integrity is not bound")
    migration_contract=(root/"FieldEvidenceApp/Domain/Models/LocationPersistenceModelsV1.swift").read_text(encoding="utf-8")
    require("knownAssetIDs: Set<UUID>" in migration_contract and
            "Set(receipt.bindings.map(\\.assetID)).isSubset(of: knownAssetIDs)" in migration_contract,
            "migration receipt may reference an unknown asset identity")
    backup_encoder=(root/"FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift").read_text(encoding="utf-8")
    backup_validator=(root/"FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift").read_text(encoding="utf-8")
    restore_rule=(root/"FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift").read_text(encoding="utf-8")
    require("Dictionary(grouping: placements, by: \\.assetID).values" in backup_encoder and
            "AssetPlacementHistoryV1.validate(history)" in backup_encoder,
            "backup export does not validate complete placement histories")
    require("AssetPlacementHistoryV1.validate(history)" in backup_validator,
            "backup package validation does not enforce placement histories")
    require("AssetPlacementHistoryV1.validate(history)" in restore_rule,
            "replacement restore does not enforce placement histories")
    completed=(root/"FieldEvidenceApp/Domain/Location/CompletedLocationCompositionSnapshotV1.swift").read_text(encoding="utf-8")
    require("currentLocationPath: LocationPathSnapshotV1" in completed and
            "locationPath: currentLocationPath" in completed,
            "completed snapshot does not freeze the explicit current hierarchy path")
    ledger=(root/"FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift").read_text(encoding="utf-8")
    require(re.findall(r'case [A-Za-z]+ = "([A-Za-z]+)"',ledger)==["site","asset","workflowRecord","evidenceFile","issue","packet","report"],"released DeletionRecordKindV2 changed")
    rule=(root/"FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift").read_text(encoding="utf-8")
    service=(root/"FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift").read_text(encoding="utf-8")
    require("siteIDToDelete: nil" in rule,"last asset may cascade site")
    for token in ("validateLocationDeletionNoCascade", "AssetPlacementHistoryV1.validate",
                  "visited.count == events.count", "AssetCompositionPolicyV1.validate",
                  "siteAssetIDs.contains($0.parentAssetID)", "siteAssetIDs.contains($0.childAssetID)",
                  "placementTips[assetID]?.siteID == siteID"):
        require(token in rule,f"location deletion guard missing: {token}")
    require("liveAssetSiteByID: Dictionary(uniqueKeysWithValues: rows.assets.map" in service and
            "validateLocationDeletionNoCascade" in service,"service deletion graph binding missing")
    expected=contracts.all_outputs(root)
    require(expected==contracts.all_outputs(root),"generation is nondeterministic")
    for relative,raw in expected.items(): require((root/relative).read_bytes()==raw,f"stale generated artifact: {relative}")
    require(not any(path.name=="__pycache__" or path.suffix in (".pyc",".pyo") for path in root.rglob("*")),"Python cache leaked")
    return {"cardID":contracts.CARD,"result":"PASS","verificationMode":"STATIC_ONLY","pathFenceCount":58,"evidenceIDCount":5,"nativeCompileRan":False,"hostedDispatchEnabled":False,"acceptanceCredit":False,"releaseCredit":False}

def main()->int:
    root=Path(__file__).resolve().parents[2]
    try: result=verify(root)
    except (VerificationError,OSError,ValueError,json.JSONDecodeError,subprocess.CalledProcessError) as error:
        print(f"{contracts.CARD} verification failed: {error}",file=sys.stderr); return 1
    print(json.dumps(result,sort_keys=True,separators=(",",":"))); return 0
if __name__=="__main__": raise SystemExit(main())
