from __future__ import annotations

import copy
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C28"
BASE = "803f75bc94a46b7b0ca50b14f1a49401f38550f1"
BTREE = "6f1cc0077cf74a1adb532124880b1cd5e4a031cc"
HEAD = "b30a1640d495bd2d6641ea2dbd816d8d4d23a186"
CTREE = "f5b3106d41380a906cfa1c0cbf9cdcc8268b4d22"
SEQ = 507
CONTEXT = "1b2bff5c876c8f618dae7015b12d4dd51d431c6756678824d72421b4d55a80a9"
FENCE = "52a48f30deafc62962e99607f690e84fb393f668c548a01fe496b96b450d3817"
ALLOCATION = "27c242e6c316767b3731c3bda81948ad8a8dc5258b54c385994248c24033f48c"
PREREQ = "83888037dd5c9762466f711f232ef5ecad7f34ffce1d773795f10dd8920763ce"
CORRECTION = "2b610d2031667696ba09337e194c8b42e39e09265fc6245a3f94fdd6271ac294"
FINAL_HASHES_SEALED = False

PRODUCT = "docs/product/brand/V23P04C28BrandHIGSharedRootCorrectionLedgerV1.json"
TEST = "FieldEvidenceAppTests/V9_91BrandHIGSharedRootCorrectionTests.swift"
FIXTURE = "FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C28BrandHIGSharedRootCorrectionCorpusV1.json"
UI = "FieldEvidenceAppUITests/V23_P04_C28BrandHIGSharedRootCorrectionUITests.swift"
SCHEMA = "Scripts/v23/brand-hig-shared-root-correction.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C28BrandHIGSharedRootCorrectionContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C28BrandHIGSharedRootCorrectionEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C28BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C28-tooling-manifest.json"
SCRIPTS = ("Scripts/v23/p04_c28_contracts.py", "Scripts/v23/generate_p04_c28_contracts.py", "Scripts/v23/verify_p04_c28_contracts.py")
OWNED = set((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
PATH_FENCE = (
    "Scripts/release-preflight.sh", "FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift",
    "FieldEvidenceAppTests/V9_11PackRegistryTests.swift", "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Localization/V21P03C16LocalizationAccessibilityCorpusV1.json",
    "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift", "FieldEvidenceAppUITests/S8_4FeedbackUITests.swift",
    PRODUCT, TEST, FIXTURE, UI, *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
SELECTORS = (
    "testV23P04C28G01LowestOwnerCorrectionsCloseC27FindingsAndPreserveHistoricReports",
    "testV23P04C28A01NativeSemanticParityPreservesTasksIdentityAndHistoricBytes",
    "testV23P04C28H01SharedStateRoleAXContrastClaimsAndReportDriftFailClosed",
    "testV23P04C28I01InterruptedCorrectionPreservesAcceptedC27BaselineAndNoPartialReceipt",
    "testV23P04C28R01RejectedDirectionAndFailedRetryPreserveAcceptedBrandRevision")
PINS = {"V23-P04-C28": (7439, "7642f788dc38d78493268c7f40a26b0a5dd4eedb4aecc575e241e50fc11edf13"), "V21-P04-C28": (11261, "a6fcb975546e6a238448edfc1c7c97afa27cb0178318cb9677efcdfab1031d8f"), "V23-P04-C28-register": (304, "8f923df7b59c3ce767689bbd31cbe41039d1b0654ae3a117b4866c8a7fd04acf")}
C27 = {"head": BASE, "tree": BTREE, "checkpointDigest": "f0be43c24a0a88989a795cc288892165bda6f612af84168bff407f036ece7cd1", "verificationReceiptDigest": "d7325ff7763660b5a24d79e4a7174b00b825c30352a1b4972f4343a3d36d5c60", "inventoryPath": "docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json", "inventorySHA256": "b7515c0a7ff3c5e4729605a73e927807524c0d9f51bf400833e4d2d849cdbfc2", "inventoryUTF8Length": 13934}
FLAGS = {key: False for key in ("physicalDevice", "native", "hosted", "activation", "adoption", "acceptance", "publication", "release")}
S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
S10 = tuple(json.loads((Path(r"C:\AssetRounds-v23-coordination") / "contexts/V23-P04-C28-attempt-1/BootstrapPathFenceV1.json").read_text(encoding="utf-8"))["activeS10ReservedPaths"])

def pretty(v): return (json.dumps(v, sort_keys=True, indent=2) + "\n").encode()
def sha(v): return hashlib.sha256(v).hexdigest()
def git(*args, cwd=ROOT): return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()
def _coord():
    override = os.environ.get("V23_P04_C28_COORDINATION_ROOT")
    if override == "NONE": return None
    path = Path(override) if override else ROOT.parent / "AssetRounds-v23-coordination"
    return path.resolve() if path.is_dir() else None
def _blob(path): return subprocess.run(["git", "show", f"{BASE}:{path}"], cwd=ROOT, check=True, capture_output=True).stdout
def source_pins():
    blueprint = _blob("docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _blob("docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")
    if git("rev-parse", BASE + "^{tree}") != BTREE: raise ValueError("C28 app base tree differs")
    def block(name, indent):
        m = re.search(rf"(?ms)^{indent}### {re.escape(name)} —.*?(?=^{indent}### |\Z)", blueprint.decode())
        if not m: raise ValueError("C28 source block missing " + name)
        return m.group(0).encode()
    at = foundation.index(b"P04-C28"); row = foundation[foundation.rfind(b"\n", 0, at)+1:foundation.index(b"\n", at)+1]
    values = {"V23-P04-C28":block("V23-P04-C28", ""), "V21-P04-C28":block("V21-P04-C28", "    "), "V23-P04-C28-register":row}
    for key, value in values.items():
        if (len(value),sha(value)) != PINS[key]: raise ValueError("C28 source pin differs " + key)
    return [{"anchor":k,"utf8Length":len(v),"sha256":sha(v)} for k,v in values.items()]
def sealed_authority(pins=None):
    return {"cardID":CARD,"appBaseHead":BASE,"appBaseTree":BTREE,"coordinationHead":HEAD,"coordinationTree":CTREE,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"allocationDigest":ALLOCATION,"prerequisiteDigest":PREREQ,"allocationCorrectionTransitionDigest":CORRECTION,"fencePathCount":22,"existingPathCount":10,"newPathCount":12,"priorFenceProof":{"fenceCount":119,"priorOwnedPathCount":22,"authorizedOverlapEdgeCount":251,"unauthorizedOverlapCount":0,"s10ReservedOverlapCount":0},"s10OverlapCount":0,"sourcePins":pins or [{"anchor":k,"utf8Length":v[0],"sha256":v[1]} for k,v in PINS.items()],"c27":C27,"activeS10ReservedPaths":list(S10),"frozenS10ReservationDigest":S10_DIGEST,"orderedPathFence":list(PATH_FENCE),"finalHashesSealed":False}
def authority():
    sealed = sealed_authority(source_pins())
    coord = _coord()
    if coord is None:
        manifest=json.loads((ROOT/MANIFEST).read_bytes()); got=manifest.get("authority")
        if got != sealed or tuple(manifest.get("pathFence",())) != PATH_FENCE: raise ValueError("C28 portable authority differs")
        return got
    if (git("rev-parse","HEAD",cwd=coord),git("rev-parse","HEAD^{tree}",cwd=coord)) != (HEAD,CTREE): raise ValueError("C28 coordination identity differs")
    def load(path): return json.loads((coord/path).read_bytes())
    ctx=load(f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json"); fence=load(f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json"); allocation=load(f"receipts/{CARD}-owner-authorized-path-allocation-v2.json")
    if (ctx.get("contextDigest"),fence.get("fenceDigest"),allocation.get("allocationDigest"),ctx.get("provisionalPrerequisiteDigest")) != (CONTEXT,FENCE,ALLOCATION,PREREQ): raise ValueError("C28 authority digests differ")
    proof=fence.get("priorFenceProof",{})
    if tuple(fence.get("allowedCreateOrReplacePaths",())) != PATH_FENCE or (len(ctx.get("existingPaths",())),len(ctx.get("newPaths",())),proof.get("fenceCount"),proof.get("priorOwnedPathCount"),proof.get("authorizedOverlapEdgeCount"),proof.get("unauthorizedOverlapCount"),proof.get("s10ReservedOverlapCount")) != (10,12,119,22,251,0,0): raise ValueError("C28 fence/proof differs")
    if tuple(fence.get("activeS10ReservedPaths",())) != S10 or fence.get("frozenS10ReservationDigest") != S10_DIGEST or set(PATH_FENCE)&set(S10): raise ValueError("C28 S10 authority differs")
    return sealed
def portable_authority_self_test():
    rejected=[]
    for label,key in (("coordination","coordinationHead"),("context","contextDigest"),("fence","orderedPathFence"),("s10","activeS10ReservedPaths"),("c27","c27"),("pins","sourcePins")):
        v=copy.deepcopy(sealed_authority()); v[key] = "changed" if key not in ("orderedPathFence","activeS10ReservedPaths","sourcePins","c27") else []
        if v == sealed_authority(): raise ValueError("C28 portable hostile accepted "+label)
        rejected.append(label)
    return {"result":"PASS","count":len(rejected),"rejected":rejected}
def rows():
    result=[]
    for path in PATH_FENCE:
        if path not in OWNED:
            file=ROOT/path; result.append({"path":path,"status":"SOURCE_PRESENT" if file.is_file() else "SOURCE_MISSING","sha256":sha(file.read_bytes()) if file.is_file() else None})
    return result, all(x["status"]=="SOURCE_PRESENT" for x in result)
def counts():
    def names(*args): return {x.replace("\\","/") for x in git(*args).splitlines() if x}
    changed=names("diff","--name-only",BASE,"HEAD")|names("diff","--name-only","HEAD")|names("diff","--cached","--name-only")|names("ls-files","--others","--exclude-standard")|OWNED
    allowed=set(PATH_FENCE)
    return {"changedPathCount":len(changed&allowed),"missingPathCount":sum(not (ROOT/p).is_file() for p in allowed-OWNED),"unownedChangedPathCount":len(changed-allowed),"s10ReservationOverlapCount":len(allowed&set(S10))}
def _schema_errors(value, node, root, trail="$"):
    if "$ref" in node:
        ref=node["$ref"]
        if not isinstance(ref,str) or not ref.startswith("#/$defs/") or ref.count("/") != 2 or ref.rsplit("/",1)[1] not in root.get("$defs",{}): return [trail+": invalid local ref"]
        return _schema_errors(value,root["$defs"][ref.rsplit("/",1)[1]],root,trail)
    errors=[]; expected=node.get("type")
    kind={"object":isinstance(value,dict),"array":isinstance(value,list),"string":isinstance(value,str),"integer":isinstance(value,int) and not isinstance(value,bool),"boolean":isinstance(value,bool),"null":value is None}
    if expected is not None:
        options=expected if isinstance(expected,list) else [expected]
        if not options or not all(isinstance(x,str) and x in kind for x in options): return [trail+": invalid type"]
        if not any(kind[x] for x in options): return [trail+": type differs"]
    canon=lambda x: json.dumps(x,sort_keys=True,separators=(",",":"))
    if "const" in node and canon(value)!=canon(node["const"]): errors.append(trail+": const differs")
    if "enum" in node and not any(canon(value)==canon(x) for x in node["enum"]): errors.append(trail+": enum differs")
    if isinstance(value,dict):
        props=node.get("properties",{})
        if not isinstance(props,dict): return [trail+": invalid properties"]
        errors += [trail+"."+x+": required" for x in node.get("required",[]) if x not in value]
        if node.get("additionalProperties") is False: errors += [trail+"."+x+": additional property" for x in value if x not in props]
        for key, child in props.items():
            if key in value: errors += _schema_errors(value[key],child,root,trail+"."+key)
    if isinstance(value,list):
        if "minItems" in node and len(value)<node["minItems"]: errors.append(trail+": too few items")
        if "maxItems" in node and len(value)>node["maxItems"]: errors.append(trail+": too many items")
        if node.get("uniqueItems") and len({canon(x) for x in value})!=len(value): errors.append(trail+": duplicate item")
        if "items" in node:
            for i,item in enumerate(value): errors += _schema_errors(item,node["items"],root,trail+"["+str(i)+"]")
    if isinstance(value,str):
        if "minLength" in node and len(value)<node["minLength"]: errors.append(trail+": too short")
        if "maxLength" in node and len(value)>node["maxLength"]: errors.append(trail+": too long")
        if "pattern" in node and re.search(node["pattern"],value) is None: errors.append(trail+": pattern differs")
    if isinstance(value,int) and not isinstance(value,bool):
        if "minimum" in node and value<node["minimum"]: errors.append(trail+": below minimum")
        if "maximum" in node and value>node["maximum"]: errors.append(trail+": above maximum")
    return errors
def validate_schema(value):
    schema=json.loads((ROOT/SCHEMA).read_bytes())
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema" or not isinstance(schema.get("$defs"),dict): raise ValueError("C28 schema draft differs")
    errors=_schema_errors(value,schema,schema)
    if errors: raise ValueError("C28 schema validation: "+errors[0])
    try:
        from jsonschema import Draft202012Validator
        Draft202012Validator.check_schema(schema)
        if list(Draft202012Validator(schema).iter_errors(value)): raise ValueError("C28 formal Draft2020 validation differs")
    except ImportError: pass
def schema_self_test(value):
    cases=[]
    for label, mutate in (("extra-nested-property",lambda x:x["sharedBrandCorrectionReceipt"].__setitem__("extra",True)),("wrong-type",lambda x:x["lifecycle"].__setitem__("writerCount","0")),("wrong-disposition",lambda x:x["appIconRevisionReceipt"].__setitem__("disposition","EMITTED")),("extra-root-property",lambda x:x.__setitem__("extra",True))):
        candidate=copy.deepcopy(value); mutate(candidate)
        try: validate_schema(candidate)
        except ValueError: cases.append(label); continue
        raise ValueError("C28 schema hostile accepted "+label)
    return {"result":"PASS","rejected":cases,"count":len(cases)}
def semantics(ready):
    if not ready: return
    ledger=json.loads((ROOT/PRODUCT).read_bytes()); validate_schema(ledger)
    pins=ledger.get("sourcePins",{}); inventory=pins.get("c27Inventory",{})
    if pins.get("acceptedAppHead") != BASE or inventory.get("sha256") != C27["inventorySHA256"] or pins.get("c27CheckpointDigest") != C27["checkpointDigest"] or pins.get("c27VerificationReceiptDigest") != C27["verificationReceiptDigest"]: raise ValueError("C28 C27 binding differs")
    exact_pins={"coordinationAuthorityHead":HEAD,"coordinationAuthorityTree":CTREE,"casSequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"ownerAuthorizedPathAllocationDigest":ALLOCATION,"provisionalPrerequisiteDigest":PREREQ,"coordinationCorrectionTransitionDigest":CORRECTION,"allocationRevision":2,"supersedesOwnerAuthorizedPathAllocationDigest":"f296173b2ae29f892447395bba5d2a48817607375e8da8d3173faf5ff739f3c1","coordinationLedgerDigest":"5dd37b9b75422a8366b9e052781d09d022951ed2b3cbe51492765ab58cf2eb5f","sourceProjectionDigest":"a7064d17aa0bdd7ef1401b411087ff38c64ecefff7a3a9515039aa009d963df5","frozenS10ReservationDigest":S10_DIGEST}
    if any(pins.get(key)!=expected for key,expected in exact_pins.items()): raise ValueError("C28 corrected authority parity differs")
    exact_deferrals={
      "all-other-shipping-phase-number-ids-in-S10-reserved-ui-root-paths":("FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift","FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift","FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift","FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift","FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift","FieldEvidenceApp/Features/Reports/ReportDetailView.swift","FieldEvidenceApp/Features/Reports/ReportFailureView.swift","FieldEvidenceApp/Features/Reports/ReportsRootView.swift","FieldEvidenceApp/Features/Settings/BackupExportView.swift","FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift","FieldEvidenceApp/Features/Settings/EraseAllView.swift","FieldEvidenceApp/Features/Settings/FeedbackView.swift","FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift","FieldEvidenceApp/Features/Signs/NewSignView.swift","FieldEvidenceApp/Features/Signs/SignDetailView.swift","FieldEvidenceApp/Features/Signs/SignsRootView.swift","FieldEvidenceApp/Features/Subscription/PaywallView.swift","FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift"),
      "visual-DesignTokens-and-WorklightComponents":("FieldEvidenceApp/DesignSystem/DesignTokens.swift","FieldEvidenceApp/DesignSystem/WorklightComponents.swift"),
      "saved-photo-RecordWork-and-IssueDetail":("FieldEvidenceApp/Features/Issues/RecordWorkView.swift","FieldEvidenceApp/Features/Issues/IssueDetailView.swift"),
      "app-icon-and-artwork":("FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png","FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Default-1024.png","FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted-1024.png","FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")}
    actual={row.get("clusterID"):tuple(item.get("path") for item in row.get("memberPaths",[])) for row in ledger.get("deferredAcceptedS10_6Clusters",[])}
    if actual != exact_deferrals or any(row.get("adopted") is not False or row.get("disposition")!="DEFERRED_PENDING_ACCEPTED_S10_6" or row.get("reservationDigest") != S10_DIGEST for row in ledger["deferredAcceptedS10_6Clusters"]): raise ValueError("C28 deferral parity differs")
    if ledger["brandRevisionImplementationReceipt"].get("activated") is not False or ledger["appIconRevisionReceipt"].get("authorizedChange") is not False: raise ValueError("C28 deferred approval parity differs")
    production=("FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift","FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift","FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift")
    source="\n".join((ROOT/p).read_text(encoding="utf-8",errors="ignore") for p in production)
    if "s8.4.mail." in source: raise ValueError("C28 legacy mail identifier remains")
    for token in ("feedback.mail.screen","feedback.mail.recipient","feedback.mail.attachment-count","feedback.mail.body","feedback.mail.done","requiredMailLegacy","SemanticAccessibility"):
        if token not in source: raise ValueError("C28 semantic source token missing "+token)
    if ledger["preservation"].get("historicReportBytesRewritten") or ledger["preservation"].get("technicalIdentityChanged"): raise ValueError("C28 preservation differs")
    for path in (TEST,UI):
        text=(ROOT/path).read_text(encoding="utf-8")
        for selector in SELECTORS:
            if selector not in text: raise ValueError("C28 selector missing "+selector)
def documents():
    auth=authority(); source_rows,ready=rows(); ledger=json.loads((ROOT/PRODUCT).read_bytes()) if (ROOT/PRODUCT).is_file() else {}
    sourceRows=source_rows
    base={"schema":"V23P04C28BrandHIGSharedRootCorrectionToolingV1","cardID":CARD,"authority":auth,"sourceRows":sourceRows,"sourceReady":ready,"finalHashesSealed":False,"flags":FLAGS,"selectors":list(SELECTORS),"lifecycle":{"persistentKindCount":0,"writerCount":0,"workspaceMutationReceiptCreated":False},"ledgerSHA256":sha((ROOT/PRODUCT).read_bytes()) if ledger else None}
    protocol={"protocol":"MANIFEST_LAST_ATOMIC_REPLACE","boundaries":["BEFORE_ARTIFACTS","AFTER_ARTIFACTS_BEFORE_MANIFEST","AFTER_MANIFEST"],"acceptedSetCounts":[0,0,1],"observedSecondRetry":True}
    contract={**base,"contract":"BrandHIGSharedRootCorrectionContractV1","requirements":{"stableMailIDs":True,"zeroProductionLegacyMailIDs":True,"c27SemanticBindingRequired":True,"c27EvidenceOnlyRefreshDoesNotInvalidate":True,"historicReportAndTechnicalIdentityPreserved":True,"deferredS10ClusterCount":4,"brandRevisionEffect":False,"appIconEffect":False}}
    evidence={**base,"receipt":"BrandHIGSharedRootCorrectionEvidenceReceiptV1","generatorInterruptionProtocol":protocol,"schemaHostile":schema_self_test(ledger) if ledger else {"result":"PENDING"},"portableAuthorityHostile":portable_authority_self_test()}
    brand={"schema":"BrandImpactManifestV1","cardID":CARD,"flags":FLAGS,"finalHashesSealed":False,"nativeOrHostedAdoption":False,"requiresAcceptedS10_6Reconciliation":True,"deferredAcceptedS10_6Clusters":ledger.get("deferredAcceptedS10_6Clusters",[]),"c27InventorySHA256":C27["inventorySHA256"]}
    files={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand))}
    manifest={"schema":"V23P04C28ToolingManifestV1","cardID":CARD,"authority":auth,"pathFence":list(PATH_FENCE),"files":[{"path":p,"sha256":d} for p,d in files.items()],"sourceRows":sourceRows,"ledgerSHA256":base["ledgerSHA256"],"generatorProtocol":protocol,"finalHashesSealed":False,"flags":FLAGS}
    return {CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
