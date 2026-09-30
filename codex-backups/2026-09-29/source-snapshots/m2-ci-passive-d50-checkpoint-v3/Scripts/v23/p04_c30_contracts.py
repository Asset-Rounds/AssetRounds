from __future__ import annotations

"""Fail-closed static contracts for V23-P04-C30.

The implementation deliberately treats generated evidence as provisional: it can
prove byte-level inputs and static semantics, but never grants print, native, or
S10.6 acceptance credit.
"""
import copy
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C30"
BASE = "8b97b33a0c83d639349d9c28806092fdeb79b95f"
BTREE = "0c804ceb7b50a5b804b1380762408aedac644d2d"
HEAD = "1b902e448a0f38f7189e237e383f8567ffbf10c3"
CTREE = "fa2dbae64b7ad67d72c1b6a6a02bcbf040c7a673"
SEQ = 514
CONTEXT = "c1ac4c3961fde5b1743f3703ee158720b9059b6af4538bf59d5df788e5327b02"
FENCE = "72484e9d476b2c1cf858ebaecd1d08ef16e7e83e554f270991ac0d7351f68f3d"
ALLOCATION = "9f66dad445adf0d9e942859dfa4af636009619c3f0a98083047157419de06ee4"
PREREQ = "33e53e92d05fb20c88b4758b3d73c1afefc1e12dd053bc3038de8cb3f2ad38d7"
S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FINAL_HASHES_SEALED = False

TEST = "FieldEvidenceAppTests/V9_93AssetLabelOutputTests.swift"
FIXTURE = "FieldEvidenceAppTests/Fixtures/V23/Labels/V23P04C30AssetLabelOutputCorpusV1.json"
UI = "FieldEvidenceAppUITests/V23_P04_C30AssetLabelOutputUITests.swift"
SCHEMA = "Scripts/v23/asset-label-output.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C30AssetLabelOutputContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C30AssetLabelOutputEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C30BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C30-tooling-manifest.json"
SCRIPTS = ("Scripts/v23/p04_c30_contracts.py", "Scripts/v23/generate_p04_c30_contracts.py", "Scripts/v23/verify_p04_c30_contracts.py")
OWNED = set((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
PATH_FENCE = (
 "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift", "FieldEvidenceApp/Infrastructure/Reporting/AssetLabelLifecycleAdapterV1.swift", TEST, FIXTURE, UI,
 *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
SELECTORS = (
 "testV23P04C30G01DeterministicLabelSheetVendorCSVPreviewReprintAndScanClosure",
 "testV23P04C30A01ManualShortCodeOfflineFallbackAndFormulaSafeVendorCSV",
 "testV23P04C30H01StaleCollisionRetiredReplacedUnsafeCSVAndHistoricDeployFailClosed",
 "testV23P04C30I01InterruptedGenerationAndRepeatedRecoveryLeaveNoPartialArtifact",
 "testV23P04C30R01RetryReexportsExactAcceptedBytesAndPreservesHistoricExportOnlyWarning")
PINS = {"V23-P04-C30":(7276,"b63376f7d1078ad6fb57b19a3431148b1472222e1766e6a04e4bd19de3aaf432"),"V21-P04-C30":(4952,"9d7b031827d7ecda404621f2ada667edfe1d297753352528bca1c7fd2b36c0fa"),"V23-P04-C30-register":(330,"0ab9a0290f16f6df3f5d9a83f2fb17880316520e586f703b2dbe051556eed5f3")}
FLAGS = {k:False for k in ("physicalDevice","native","hosted","activation","adoption","acceptance","publication","release")}

def pretty(v): return (json.dumps(v, sort_keys=True, indent=2)+"\n").encode()
def sha(v): return hashlib.sha256(v).hexdigest()
def git(*args, cwd=ROOT): return subprocess.run(["git",*args],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def _coord():
    raw=os.environ.get("V23_P04_C30_COORDINATION_ROOT")
    if raw == "NONE": return None
    p=Path(raw) if raw else ROOT.parent/"AssetRounds-v23-coordination"
    return p if p.is_dir() else None
def _blob(path): return subprocess.run(["git","show",f"{BASE}:{path}"],cwd=ROOT,check=True,capture_output=True).stdout
def source_pins():
    if git("rev-parse",BASE+"^{tree}") != BTREE: raise ValueError("app base tree differs")
    blueprint=_blob("docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"); foundation=_blob("docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")
    def block(name,indent):
        m=re.search(rf"(?ms)^{indent}### {re.escape(name)} —.*?(?=^{indent}### |\Z)",blueprint.decode())
        if not m: raise ValueError("source block missing "+name)
        return m.group(0).encode()
    at=foundation.index(b"P04-C30"); row=foundation[foundation.rfind(b"\n",0,at)+1:foundation.index(b"\n",at)+1]
    vals={"V23-P04-C30":block("V23-P04-C30",""),"V21-P04-C30":block("V21-P04-C30","    "),"V23-P04-C30-register":row}
    for key,value in vals.items():
        if (len(value),sha(value)) != PINS[key]: raise ValueError("source pin differs "+key)
    return [{"anchor":k,"utf8Length":len(v),"sha256":sha(v)} for k,v in vals.items()]
def sealed_authority(pins=None):
    return {"cardID":CARD,"appBaseHead":BASE,"appBaseTree":BTREE,"coordinationHead":HEAD,"coordinationTree":CTREE,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"allocationDigest":ALLOCATION,"prerequisiteDigest":PREREQ,"fencePathCount":13,"existingPathCount":2,"newPathCount":11,"priorFenceProof":{"fenceCount":120,"priorOwnedPathCount":2,"authorizedOverlapEdgeCount":9,"unauthorizedOverlapCount":0,"s10ReservedOverlapCount":0},"s10OverlapCount":0,"frozenS10ReservationDigest":S10_DIGEST,"orderedPathFence":list(PATH_FENCE),"sourcePins":pins or [{"anchor":k,"utf8Length":v[0],"sha256":v[1]} for k,v in PINS.items()],"finalHashesSealed":False}
def authority():
    sealed=sealed_authority(source_pins()); coord=_coord()
    if coord is None:
        m=json.loads((ROOT/MANIFEST).read_bytes())
        if m.get("authority") != sealed or tuple(m.get("pathFence",())) != PATH_FENCE: raise ValueError("portable authority differs")
        return sealed
    if (git("rev-parse","HEAD",cwd=coord),git("rev-parse","HEAD^{tree}",cwd=coord)) != (HEAD,CTREE): raise ValueError("coordination identity differs")
    load=lambda p:json.loads((coord/p).read_bytes())
    ctx=load(f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json"); fence=load(f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json")
    if (ctx.get("contextDigest"),fence.get("fenceDigest"),ctx.get("ownerAuthorizedPathAllocationDigest"),ctx.get("provisionalPrerequisiteDigest")) != (CONTEXT,FENCE,ALLOCATION,PREREQ): raise ValueError("authority digest differs")
    proof=fence.get("priorFenceProof",{})
    if tuple(fence.get("allowedCreateOrReplacePaths",())) != PATH_FENCE or (len(fence.get("existingPaths",())),len(fence.get("newPaths",())),proof.get("fenceCount"),proof.get("priorOwnedPathCount"),proof.get("authorizedOverlapEdgeCount"),proof.get("unauthorizedOverlapCount"),proof.get("s10ReservedOverlapCount")) != (2,11,120,2,9,0,0): raise ValueError("fence proof differs")
    if fence.get("frozenS10ReservationDigest") != S10_DIGEST or set(PATH_FENCE)&set(fence.get("activeS10ReservedPaths",())): raise ValueError("S10 differs")
    return sealed
def rows():
    out=[]
    for path in PATH_FENCE:
        if path not in OWNED:
            file=ROOT/path; out.append({"path":path,"status":"SOURCE_PRESENT" if file.is_file() else "SOURCE_MISSING","sha256":sha(file.read_bytes()) if file.is_file() else None})
    return out,all(x["status"]=="SOURCE_PRESENT" for x in out)
def counts():
    names=lambda *a:{x.replace("\\\\","/") for x in git(*a).splitlines() if x}
    changed=names("diff","--name-only",BASE,"HEAD")|names("diff","--name-only","HEAD")|names("diff","--cached","--name-only")|names("ls-files","--others","--exclude-standard")|OWNED
    allowed=set(PATH_FENCE)
    return {"changedPathCount":len(changed&allowed),"missingPathCount":sum(not(ROOT/p).is_file() for p in allowed-OWNED),"unownedChangedPathCount":len(changed-allowed),"s10ReservationOverlapCount":0}
def _err(value,node,root,trail="$"):
    if "$ref" in node: return _err(value,root["$defs"][node["$ref"].rsplit("/",1)[1]],root,trail)
    typ=node.get("type"); kinds={"object":isinstance(value,dict),"array":isinstance(value,list),"string":isinstance(value,str),"integer":isinstance(value,int) and not isinstance(value,bool),"boolean":isinstance(value,bool),"null":value is None}
    if typ:
        options=typ if isinstance(typ,list) else [typ]
        if not isinstance(options,list) or not options or not any(kinds.get(item,False) for item in options): return [trail+": type"]
    e=[]
    if "const" in node and value != node["const"]: e.append(trail+": const")
    if "enum" in node and value not in node["enum"]: e.append(trail+": enum")
    if isinstance(value,dict):
        props=node.get("properties",{}); e += [trail+"."+x+": required" for x in node.get("required",[]) if x not in value]
        if node.get("additionalProperties") is False: e += [trail+"."+x+": extra" for x in value if x not in props]
        for k,v in value.items():
            if k in props: e += _err(v,props[k],root,trail+"."+k)
    if isinstance(value,list):
        if len(value)<node.get("minItems",0): e.append(trail+": minItems")
        if "maxItems" in node and len(value)>node["maxItems"]: e.append(trail+": maxItems")
        if node.get("uniqueItems") and len({json.dumps(x,sort_keys=True) for x in value})!=len(value): e.append(trail+": unique")
        if "items" in node:
            for i,v in enumerate(value): e += _err(v,node["items"],root,f"{trail}[{i}]")
    if isinstance(value,str):
        if len(value)<node.get("minLength",0): e.append(trail+": minLength")
        if "pattern" in node and not re.search(node["pattern"],value): e.append(trail+": pattern")
    return e
def validate_schema(value):
    schema=json.loads((ROOT/SCHEMA).read_bytes()); errors=_err(value,schema,schema)
    if errors: raise ValueError("schema validation "+errors[0])
    try:
        from jsonschema import Draft202012Validator
        Draft202012Validator.check_schema(schema)
        if list(Draft202012Validator(schema).iter_errors(value)): raise ValueError("formal schema validation")
    except ImportError: pass
def semantics(ready):
    if not ready: return
    read_dependencies=("FieldEvidenceApp/Domain/Labels/AssetLabelContractsV1.swift","FieldEvidenceApp/Application/Labels/AssetLabelCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift","FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift","FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift","FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift","FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift")
    texts={p:(ROOT/p).read_text(encoding="utf-8",errors="ignore") for p in (*PATH_FENCE,*read_dependencies) if p.endswith(".swift") or p.endswith(".json")}
    required=("AssetLabel","WorkspaceWriterV1","MutationReceiptRow","HISTORIC_EXPORT_ONLY","DeterministicPDF","CSV","formula","locator")
    joined="\n".join(texts.values())
    for token in required:
        if token not in joined: raise ValueError("semantic token missing "+token)
    for path in (TEST,UI):
        for selector in SELECTORS:
            if selector not in texts[path]: raise ValueError("selector missing "+selector)
    source_contracts={
        "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift":(
            "makeAssetLabelWorkflow(",
            "accessGate: any AppAccessGatePortV1",
            "requireContentAccess(for: .render)",
        ),
        "FieldEvidenceApp/Infrastructure/Reporting/AssetLabelLifecycleAdapterV1.swift":(
            "prepareExactAcceptedExport(",
            "requiresDoNotDeployWarning",
            "else { return }",
        ),
        TEST:(
            "verifyRealPublicationRecovery(",
            "EvidenceBundleStoreFailureInjection(",
            ".assetLabelPublicationBeforeMarkerCommit",
            "generationLeaseRegistry: generationLeaseRegistry",
            ".awaitingPublication",
            "recoverAfterInterruption()",
            "prepareExactAcceptedExport(",
            "verifyProductionCompositionRemainsAccessGated()",
        ),
    }
    for path,tokens in source_contracts.items():
        for token in tokens:
            if token not in texts[path]: raise ValueError("source regression "+path+":"+token)
def _accepted(root):
    manifest=Path(root)/MANIFEST
    try:
        files=json.loads(manifest.read_bytes())["files"]
        return int(len(files)==3 and all((Path(root)/row["path"]).is_file() and sha((Path(root)/row["path"]).read_bytes())==row["sha256"] for row in files))
    except Exception: return 0
def _tree(root):
    rows=[(str(p.relative_to(root)).replace("\\","/"),sha(p.read_bytes())) for p in sorted(Path(root).rglob("*")) if p.is_file()]
    return sha((json.dumps(rows,separators=(",",":"))+"\n").encode())
def atomic_write(docs,root,boundary=None):
    if boundary=="BEFORE_ARTIFACTS": raise RuntimeError(boundary)
    staged=[]
    try:
        for path in (CONTRACT,EVIDENCE,BRAND,MANIFEST):
            target=Path(root)/path; target.parent.mkdir(parents=True,exist_ok=True)
            fd,name=tempfile.mkstemp(prefix="."+target.name+".",dir=target.parent)
            with os.fdopen(fd,"wb") as handle: handle.write(pretty(docs[path]))
            staged.append((target,Path(name)))
        for target,tmp in staged[:-1]: os.replace(tmp,target)
        if boundary=="AFTER_ARTIFACTS_BEFORE_MANIFEST": raise RuntimeError(boundary)
        os.replace(staged[-1][1],staged[-1][0])
        if boundary=="AFTER_MANIFEST": raise RuntimeError(boundary)
    finally:
        for _,tmp in staged:
            if tmp.exists():tmp.unlink()
def _draft_documents(protocol=None):
    auth=authority(); sourceRows,ready=rows()
    base={"schema":"V23P04C30AssetLabelOutputToolingV1","cardID":CARD,"authority":auth,"sourceRows":sourceRows,"sourceReady":ready,"finalHashesSealed":False,"flags":FLAGS,"selectors":list(SELECTORS),"lifecycle":{"persistentSchema":"V53","activeModelCount":168,"newDurableFamilyCount":0,"newWriterCount":0,"newMigrationCount":0,"physicalValidation":"REQUIRED_PENDING_OWNER_NO_ACCEPTANCE_CREDIT"}}
    contract={**base,"contract":"AssetLabelOutputContractV1","requirements":{"compositionWiring":True,"acceptedArtifactReexportOnly":True,"historicExportOnlyNoDeploy":True,"formulaSafeCSV":True,"deterministicPDFCSVText":True,"locatorScanConvergence":True}}
    evidence={**base,"receipt":"AssetLabelOutputEvidenceReceiptV1","generatorInterruptionProtocol":protocol or {"result":"PENDING_SOURCE_STABILITY","protocol":"MANIFEST_LAST_ATOMIC_REPLACE","rows":[]}}
    brand={"schema":"BrandImpactManifestV1","cardID":CARD,"flags":FLAGS,"finalHashesSealed":False,"nativeOrHostedAdoption":False,"requiresAcceptedS10_6Reconciliation":True}
    files={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand))}
    manifest={"schema":"V23P04C30ToolingManifestV1","cardID":CARD,"authority":auth,"pathFence":list(PATH_FENCE),"files":[{"path":p,"sha256":h} for p,h in files.items()],"sourceRows":sourceRows,"finalHashesSealed":False,"flags":FLAGS}
    return {CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
def interruption_protocol():
    # Run the same four-artifact writer in a sibling, same-filesystem temp root.
    # The generated set is a seed without this observation; that avoids a recursive
    # digest while still exercising the exact production writer and paths.
    docs=_draft_documents({"result":"SEED","protocol":"MANIFEST_LAST_ATOMIC_REPLACE","rows":[]})
    before=_tree(ROOT); rows=[]
    with tempfile.TemporaryDirectory(prefix=".c30-atomic-",dir=ROOT.parent) as tmp:
        for boundary,expected in zip(("BEFORE_ARTIFACTS","AFTER_ARTIFACTS_BEFORE_MANIFEST","AFTER_MANIFEST"),(0,0,1)):
            output=Path(tmp)/boundary
            try: atomic_write(docs,output,boundary)
            except RuntimeError: pass
            observed=_accepted(output)
            if observed != expected: raise ValueError("interruption accepted set differs "+boundary)
            atomic_write(docs,output); recovery_tree=_tree(output); recovery_count=_accepted(output)
            atomic_write(docs,output); retry_tree=_tree(output); retry_count=_accepted(output)
            rows.append({"boundary":boundary,"acceptedSetCount":observed,"recoveryAcceptedSetCount":recovery_count,"secondRetryAcceptedSetCount":retry_count,"recoveryTreeDigest":recovery_tree,"secondRetryTreeDigest":retry_tree,"manifestLast":True,"retryDeterministic":recovery_count==retry_count==1 and recovery_tree==retry_tree,"realWorktreeUnchanged":_tree(ROOT)==before})
    if _tree(ROOT)!=before or not all(row["retryDeterministic"] and row["realWorktreeUnchanged"] for row in rows): raise ValueError("interruption protocol differs")
    return {"result":"PASS","protocol":"MANIFEST_LAST_ATOMIC_REPLACE","rows":rows,"deterministicRerun":True,"realWorktreeUnchanged":True}
def documents():
    return _draft_documents(interruption_protocol())
