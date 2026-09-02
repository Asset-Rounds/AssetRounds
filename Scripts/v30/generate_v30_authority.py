#!/usr/bin/env python3
"""Generate/verify the external owner-directed V30 R2 pre-S10 authority.

It observes only frozen V23 worktrees. C:\\AssetRounds (active Phase 10) is
never a filesystem or subprocess target.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

P = Path(__file__).resolve().parent
OUT = P / "V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json"
FENCES = P / "V30_PRE_S10_PATH_FENCES.json"
V23 = Path(r"C:\AssetRounds-v23-expansion")
COORD = Path(r"C:\AssetRounds-v23-coordination")
RESERVATION = V23 / "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
ID = "ASSETROUNDS-V30-PRE-S10-20260902-R2"
PRODUCT_REMOTE = "https://github.com/Asset-Rounds/AssetRounds.git"
COORD_REMOTE = "https://github.com/Asset-Rounds/AssetRounds-v23-coordination.git"
V23_HEAD = "acbfb68355f903fe98638b6ef22e4814e7b48328"
V23_TREE = "47e17fae6b73dccd5029ccf4ac7cca659196f225"
V23_PACKAGE = "99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570"
COORD_HEAD = "51ef2b3d970a25b4c83df8c8238609316e37034e"
COORD_TREE = "060c83c3d1489fc011b1c921f6c85bec2b074478"
COORD_LEDGER = "973090852e843e895125bea8da87c7e1689611c46d8219a70c1749be49398067"
COORD_PROJECTION = "cf57849e8f7c245d38fd21a39da5938d10e13c9aca3976a71b7d3a3ee401f12d"
RES_RAW = "9f7c27431271728d167731d4af806c7449447dfbcc8bf46778102e2f9a89b576"
RES_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
HUMAN = ("EXPANSION_V30_FOUNDATION_PLAN.md", "EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md", "EXPANSION_V30_HANDOFF.md", "NEXT_CODEX_SESSION_PROMPT.md")
SCRIPTS = ("generate_v30_machine_artifacts.py", "generate_v30_path_fences.py", "generate_v30_authority.py", "generate_v30_bootstrap_payloads.py", "generate_v30_manifest.py", "validate_v30_package.py")
CORE = ("V30_CARD_REGISTER.json", "V30_DIRECT_DEPENDENCY_GRAPH.json", "V30_LOCALE_REGISTRY.json", "V30_V24_DISPOSITION_PROJECTION.json", "V30_PRE_S10_PATH_FENCES.json")
BOOTSTRAP = ("V30_CARD_001_CONTEXT.json", "V30_CARD_001_FENCE.json", "V30_CARD_001_CURRENT_TASK.md", "V30_CARD_001_CI_SELECTION.json", "V30_EXECUTION_HANDOFF_GENESIS.md", "V30_PROVISIONAL_LEDGER_GENESIS.json", "V30_PROVISIONAL_LEDGER_PROJECTION.json")
TYPE_NAMES = {"V30_CARD_REGISTER.json": "V30CardRegisterV1.json", "V30_DIRECT_DEPENDENCY_GRAPH.json": "V30DirectDependencyGraphV1.json", "V30_LOCALE_REGISTRY.json": "V30LocaleRegistryV1.json", "V30_V24_DISPOSITION_PROJECTION.json": "V30V24DispositionProjectionV1.json", "V30_PRE_S10_PATH_FENCES.json": "V30PreS10PathFencesV1.json"}

class Hold(RuntimeError): pass
def req(ok: bool, why: str) -> None:
    if not ok: raise Hold(why)
def digest(raw: bytes) -> str: return hashlib.sha256(raw).hexdigest()
def canon(value: Any) -> bytes: return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
def load(path: Path) -> dict[str, Any]:
    req(path.is_file(), f"missing {path.name}")
    raw = path.read_bytes(); req(not raw.startswith(b"\xef\xbb\xbf") and b"\r" not in raw, f"noncanonical {path.name}")
    value = json.loads(raw.decode("utf-8")); req(isinstance(value, dict), f"object required {path.name}")
    return value
def git(w: Path, *args: str) -> str:
    req(w != Path(r"C:\AssetRounds"), "active Phase 10 target forbidden")
    r = subprocess.run(["git", "-C", str(w), *args], capture_output=True, text=True, encoding="utf-8")
    req(r.returncode == 0, f"git {w}: {r.stderr.strip()}")
    return r.stdout.strip()
def check_worktree(w: Path, remote: str, branch: str, head: str, tree: str, name: str) -> None:
    req(w.is_dir(), f"{name} missing")
    req(git(w, "remote", "get-url", "origin") == remote, f"{name} origin mismatch")
    req(git(w, "branch", "--show-current") == branch, f"{name} branch mismatch")
    req(git(w, "rev-parse", "HEAD") == head and git(w, "rev-parse", "HEAD^{tree}") == tree, f"{name} identity mismatch")
    req(not git(w, "status", "--porcelain=v1", "--untracked-files=all"), f"{name} dirty")
def frozen_blob(path: str) -> tuple[str | None, str | None]:
    record = git(V23, "ls-tree", V23_HEAD, "--", path)
    if not record:
        return None, None
    fields = record.split(maxsplit=3)
    req(len(fields) == 4 and fields[1] == "blob" and fields[3] == path, f"frozen blob record {path}")
    raw = subprocess.run(["git", "-C", str(V23), "cat-file", "-p", fields[2]], check=True, stdout=subprocess.PIPE).stdout
    return fields[2], digest(raw)

def install_map() -> list[dict[str, str]]:
    result = [{"source": n, "installPath": f"docs/design/v30/{n}"} for n in HUMAN]
    result += [{"source": "V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json", "installPath": "docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json"}, {"source": "V30_PACKAGE_MANIFEST.json", "installPath": "docs/design/v30/authority/V30PackageManifestV1.json"}]
    result += [{"source": n, "installPath": f"Scripts/v30/{n}"} for n in SCRIPTS]
    result += [{"source": n, "installPath": f"docs/design/v30/authority/{TYPE_NAMES[n]}"} for n in CORE]
    result += [{"source": n, "installPath": f"docs/design/v30/authority/bootstrap/{n}"} for n in BOOTSTRAP]
    req(len(result) == 24 and len({x['source'] for x in result}) == 24 and len({x['installPath'] for x in result}) == 24, "install map not exact 24")
    return result
def core_hashes() -> list[dict[str, Any]]:
    # No prompt/manifest/authority/bootstrap hash: preserves the package DAG.
    names = ("EXPANSION_V30_FOUNDATION_PLAN.md", "EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md", "EXPANSION_V30_HANDOFF.md", *CORE, *SCRIPTS)
    out=[]
    for n in names:
        f=P/n; req(f.is_file(), f"missing core {n}"); out.append({"source":n,"sha256":digest(f.read_bytes()),"bytes":f.stat().st_size})
    return out
def materialization() -> dict[str, dict[str,str]]:
    b="docs/design/v30/authority/bootstrap/"
    return {
      "V30_CARD_001_CONTEXT.json":{"installedSource":b+"V30_CARD_001_CONTEXT.json","materializedPath":"docs/design/v30/execution/contexts/V30-P00-C01-attempt-1.json","target":"PRODUCT_BRANCH"},
      "V30_CARD_001_FENCE.json":{"installedSource":b+"V30_CARD_001_FENCE.json","materializedPath":"docs/design/v30/execution/fences/V30-P00-C01-attempt-1.json","target":"PRODUCT_BRANCH"},
      "V30_CARD_001_CURRENT_TASK.md":{"installedSource":b+"V30_CARD_001_CURRENT_TASK.md","materializedPath":"docs/design/v30/execution/V30_CURRENT_TASK.md","target":"PRODUCT_BRANCH"},
      "V30_CARD_001_CI_SELECTION.json":{"installedSource":b+"V30_CARD_001_CI_SELECTION.json","materializedPath":"docs/design/v30/execution/V30_CI_SELECTION.json","target":"PRODUCT_BRANCH"},
      "V30_EXECUTION_HANDOFF_GENESIS.md":{"installedSource":b+"V30_EXECUTION_HANDOFF_GENESIS.md","materializedPath":"docs/design/v30/execution/V30_EXECUTION_HANDOFF.md","target":"PRODUCT_BRANCH"},
      "V30_PROVISIONAL_LEDGER_PROJECTION.json":{"installedSource":b+"V30_PROVISIONAL_LEDGER_PROJECTION.json","materializedPath":"docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json","target":"PRODUCT_BRANCH"},
      "V30_PROVISIONAL_LEDGER_GENESIS.json":{"installedSource":b+"V30_PROVISIONAL_LEDGER_GENESIS.json","materializedPath":"refs/heads/coord/v30-globalization-provisional:docs/design/v30/execution/V30_PROVISIONAL_LEDGER.json","target":"SEPARATE_COORDINATION_REPOSITORY"},
    }
def fence_proof(reserved: set[str]) -> tuple[str, list[dict[str, Any]]]:
    raw = FENCES.read_bytes(); f = load(FENCES)
    req(f.get("schema") == "V30PreS10PathFencesV1" and f.get("authorityID") == ID and f.get("cardCount") == 37, "fence identity")
    cards = f.get("cards"); req(isinstance(cards, list) and len(cards) == 37, "fence cards")
    tuples: list[dict[str, Any]] = []
    required = {"cardID", "path", "expectedBBlobOID", "expectedBSHA256", "boundedPurpose", "writerLane", "reconciliationObligation"}
    for ordinal, card in enumerate(cards, 1):
        req(card.get("ordinal") == ordinal and card.get("status") == "PRE_S10_PROVISIONAL_ELIGIBLE", f"fence card {ordinal}")
        allowed = card.get("allowedPaths"); shared = card.get("s10SharedPaths"); issued = card.get("preAuthorizedOverlapTuples")
        req(isinstance(allowed, list) and isinstance(shared, list) and isinstance(issued, list), f"fence shape {ordinal}")
        paths = [item.get("path") for item in allowed if isinstance(item, dict)]
        req(len(paths) == len(allowed) and len(paths) == len(set(paths)), f"fence duplicate path {ordinal}")
        req(all(isinstance(path, str) and path and "*" not in path and "{" not in path and "}" not in path and not path.endswith("/") for path in paths), f"fence shorthand {ordinal}")
        req(set(shared) == set(paths).intersection(reserved), f"fence reservation intersection {ordinal}")
        req({item.get("path") for item in issued if isinstance(item, dict)} == set(shared), f"fence tuple coverage {ordinal}")
        for tuple_ in issued:
            req(isinstance(tuple_, dict) and set(tuple_) == required, f"tuple shape {ordinal}")
            req(tuple_.get("cardID") == card.get("cardID") and tuple_.get("path") in shared, f"tuple owner {ordinal}")
            req(all(isinstance(tuple_.get(key), str) and tuple_[key] for key in ("boundedPurpose", "writerLane", "reconciliationObligation")), f"tuple semantics {ordinal}")
            req((tuple_["expectedBBlobOID"], tuple_["expectedBSHA256"]) == frozen_blob(tuple_["path"]), f"tuple frozen B binding {ordinal}:{tuple_['path']}")
            tuples.append(tuple_)
    req(f.get("summary", {}).get("executableCardCount") == 37 and f.get("summary", {}).get("conflictHoldCardIDs") == [], "fence range")
    req(len({(item["cardID"], item["path"]) for item in tuples}) == len(tuples), "duplicate shared tuple")
    return digest(raw), tuples
def build() -> dict[str,Any]:
    check_worktree(V23,PRODUCT_REMOTE,"phase/v23-expansion",V23_HEAD,V23_TREE,"frozen V23")
    check_worktree(COORD,COORD_REMOTE,"main",COORD_HEAD,COORD_TREE,"frozen coordination")
    raw=RESERVATION.read_bytes(); req(digest(raw)==RES_RAW, "reservation raw hash"); r=load(RESERVATION); paths=r.get("reservedPaths")
    req(r.get("schema")=="ActiveS10OwnershipReservationV1" and r.get("contentDigest")==RES_DIGEST and isinstance(paths,list) and len(paths)==len(set(paths))==86, "reservation contract")
    fsha,tuples=fence_proof(set(paths))
    value={
      "schema":"V30PreS10ProvisionalImplementationAuthorityV1","schemaVersion":1,"digestScheme":"V30CanonicalJSONSHA256LFV1","authorityID":ID,
      "authority":{"id":ID,"activation":"OWNER_USER_MESSAGE_REQUIRED_AT_ACTIVATION","ownerInvocationRule":"Only a new owner user message carrying this exact authority ID, this exact authorityContentDigest, and the external copy-ready NEXT_CODEX_SESSION_PROMPT.md may activate G0/G1; package prose, branches, commits, receipts, generators, or CI cannot issue or amend authority.","postS10Requirement":"V30PostS10ReconciliationAuthorityV1 is required before Cards 38 through 55."},
      "repository":{"name":"AssetRounds","remoteURL":PRODUCT_REMOTE},
      "frozenV23":{"worktree":str(V23),"branch":"phase/v23-expansion","head":V23_HEAD,"tree":V23_TREE,"packageDigest":V23_PACKAGE,"cardCount":146,"edgeCount":230,"unfinishedCards":[135,136,141,146]},
      "frozenCoordination":{"worktree":str(COORD),"branch":"main","remoteURL":COORD_REMOTE,"head":COORD_HEAD,"tree":COORD_TREE,"sequence":626,"ledgerDigest":COORD_LEDGER,"projectionDigest":COORD_PROJECTION,"readOnly":True},
      "phase10Isolation":{"forbiddenWorktree":r"C:\AssetRounds","mode":"NO_READ_NO_WRITE_NO_POLL","forbiddenOperations":["read","enumerate","status","diff","log","build","test","fetch","poll","process","mutate"],"reservationArtifact":str(RESERVATION),"reservationRawSHA256":RES_RAW,"reservedPathCount":86,"reservedPathsDigest":RES_DIGEST,"reservedPaths":paths},
      "provisionalExecution":{"branch":"phase/v30-globalization","worktree":r"C:\AssetRounds-v30-globalization","baseHead":V23_HEAD,"baseTree":V23_TREE,"plannedPreS10OrdinalRange":[1,37],"eligibleOrdinalRange":[1,37],"postS10LockedOrdinalRange":[38,55],"initialCard":"V30-P00-C01","terminalPreS10State":"PROVISIONAL_CHECKPOINTED","cardSelectionLaw":"Only one card is mutable at a time; an unfenced or untupled reserved-path intersection is CONFLICT_HOLD.","allowedGitOperations":["create-local-branch-from-frozen-v23","create-dedicated-worktree","direct-child-commit","exact-path-stage","non-force-push-only-phase-v30-globalization"],"forbiddenGitOperations":["main-mutation","phase10-ref-mutation","v23-ref-mutation","force-push","merge-commit","wholesale-merge","history-rewrite"]},
      "provisionalLedger":{"namespace":"V30PreS10ProvisionalLedgerV1","locator":"docs/design/v30/execution/V30_PROVISIONAL_LEDGER.json","externalWorktree":r"C:\AssetRounds-v30-globalization-coordination","remoteURL":COORD_REMOTE,"baseHead":COORD_HEAD,"baseTree":COORD_TREE,"externalRef":"refs/heads/coord/v30-globalization-provisional","expectedAtActivation":"ABSENT","expectedOldRef":"ABSENT","expectedSequence":"ABSENT","expectedLedgerDigest":"ABSENT","expectedProjectionDigest":"ABSENT","singleWriter":True,"compareAndSwap":True,"canonicalCoordinationWrite":False,"provisionalCoordinationWrite":True,"canonicalMainUntouched":True,"genesisImportsSequence":626,"allowedGitOperations":["create-coordination-branch-from-exact-frozen-coordination-head","create-dedicated-coordination-worktree","scoped-direct-child-coordination-commit","non-force-push-only-coord-v30-globalization-provisional"],"g3ProductMaterializationCount":6,"casSequence":["G3_COORDINATION_GENESIS_EXPECTED_ABSENT","G3_ACTIVATION_RECEIPT_APPEND","G3_PRODUCT_SELECTION_PROJECTION_COMMIT_EXPECTED_OLD_PRODUCT_REF","G3_LATER_COORDINATION_CARD_1_SELECTION_BINDING_PRODUCT_PROJECTION_COMMIT"]},
      "ordering":{"cardRange":[1,55],"preS10ExecutableRange":[1,37],"postS10RequiresExternalAuthority":True,"skipCards":False,"reorderCards":False,"samePhaseAutopilot":True,"samePhaseAutopilotLaw":"After a provisional checkpoint, only the immediate graph successor may be selected through a fresh CAS; no card may be skipped, reordered, or concurrently selected."},
      "currentTask":{"path":"docs/design/v30/execution/V30_CURRENT_TASK.md","selectorPath":"docs/design/v30/execution/V30_CI_SELECTION.json","handoffPath":"docs/design/v30/execution/V30_EXECUTION_HANDOFF.md","inheritedPaths":["docs/execution/CURRENT_TASK.md","docs/product/BUILD_PLAN_V4.md","docs/execution/V4_IMPLEMENTATION_RUNBOOK.md"],"inheritedPathsReadOnly":True,"initialCardID":"V30-P00-C01"},
      "ci":{"route":"TASK_NAMED_GITHUB_ACTIONS_MACOS_ONLY","preS10IsDevelopmentEvidence":True,"preS10IsAcceptance":False,"selectionMustBePinned":True,"hostedDispatchBeforeRoutePinned":False},
      "sharedPathRule":{"tupleSchema":["cardID","path","expectedBBlobOID","expectedBSHA256","boundedPurpose","writerLane","reconciliationObligation"],"proseCannotExpandAuthority":True,"unfencedOrUntupledDisposition":"CONFLICT_HOLD","preS10FinalCreditForSharedPath":False},
      "postS10Reconciliation":{"requiredAuthoritySchema":"V30PostS10ReconciliationAuthorityV1","branch":"phase/v30-globalization-reconciliation","worktree":r"C:\AssetRounds-v30-globalization-reconciliation","sourceLineages":["B=frozen-v23","P=frozen-terminal-provisional-v30","S=accepted-post-phase10-v23-main"],"requiresExternalAuthority":True,"wholesaleProvisionalMerge":False,"replayCardRange":[1,37],"trigger":"OWNER_REPORTS_PHASE_10_6_COMPLETE_READ_ONLY_EVIDENCE_VERIFICATION_ONLY","selectableAfterTrigger":"V30-P05-C01_ONLY_AFTER_SEPARATE_POST_S10_AUTHORITY"},
      "creditPolicy":{"preS10FinalCredit":False,"provisionalCIIsAcceptance":False,"provisionalTranslationIsAccepted":False,"canonicalAcceptance":False,"postS10Credit":False,"mainMutationBeforeP07C01":False,"releaseBeforeOwnerAction":False},
      "pathFenceAuthority":{"sourcePath":FENCES.name,"sha256":fsha,"cardCount":37,"proseOrCardCannotExpandOverlap":True,"s10SharedReconciliationTuples":tuples},
      "sourceToInstallMap":install_map(),"bootstrapMaterializationMap":materialization(),"coreArtifactHashes":core_hashes(),"authorityContentDigest":""}
    value["installationRequestID"] = ID + "/INSTALL"
    value["bootstrapRequestIDs"] = {
      "installation": value["installationRequestID"],
      "coordinationGenesis": ID + "/G3-GENESIS",
      "activationReceipt": ID + "/G3-ACTIVATION",
      "productSelectionProjection": ID + "/G3-PROJECTIONS",
      "cardSelection": ID + "/G3-SELECT-CARD-001",
    }
    value["ci"].update({
      "workflowPath": ".github/workflows/ios-ci.yml",
      "branchRef": "refs/heads/phase/v30-globalization",
      "selectorPath": "docs/design/v30/execution/V30_CI_SELECTION.json",
      "selectorObjectKey": "selector",
      "routeHydrationCard": "V30-P00-C05",
      "isolatedRouteWriterPaths": [".github/workflows/ios-ci.yml", "Scripts/test-smoke.sh", "Scripts/ui-smoke.sh"],
      "inheritedSelectorReadOnly": "Scripts/ci-selection.json",
      "optionalPreS10Diagnostics": True,
      "routeLaw": "Only Card 5 may adapt the three pre-issued frozen-B workflow/helper copies on the isolated V30 branch to the V30 typed selector. Keep exact task-pinned toolchain, Simulator, watchdogs, commands, checksums, artifact enforcement, and cancel-in-progress false. Dispatch only the registered ios-ci.yml workflow with the V30 branch ref and verify exact head. Never dispatch or inspect Phase 10 runs, modify its worktree/ref, install a workflow on main, or claim final acceptance.",
      "unavailableRouteDisposition": "NOT_EXECUTED_NO_NATIVE_CREDIT; required deterministic static checks may still permit provisional progression. Preserve every failed native candidate and diagnosis. Never label an unavailable route or failing run as passed; final native qualification remains mandatory after reconciliation.",
    })
    value["provisionalLedger"].update({
      "ledgerID": ID + "/PROVISIONAL-LEDGER",
      "requestIDNamespace": ID,
      "initialWriterGeneration": 1,
      "initialSequence": 0,
      "refCreationExpectedOld": "ABSENT",
      "genesisExpectedOldRef": COORD_HEAD,
      "genesisExpectedLedger": "ABSENT",
      "bootstrapRefLaw": "Create only the named coordination branch/worktree from the exact frozen coordination head with expected-absent ref creation. Commit genesis as its direct child using the frozen head as expected old Git ref and ABSENT as the expected ledger value. Later CAS operations bind the exact preceding coordination commit, sequence, and ledger digest. Never use ABSENT for a Git ref after that ref has been created.",
      "bootstrapAllowedPaths": [
        "docs/design/v30/execution/V30_PROVISIONAL_LEDGER.json",
        "docs/design/v30/execution/receipts/V30_G3_ACTIVATION_RECEIPT.json",
        "docs/design/v30/execution/receipts/V30_G3_CARD_001_SELECTION_RECEIPT.json",
      ],
      "runtimeMutablePaths": ["docs/design/v30/execution/V30_PROVISIONAL_LEDGER.json"],
      "activationReceiptPath": "docs/design/v30/execution/receipts/V30_G3_ACTIVATION_RECEIPT.json",
      "cardSelectionReceiptPath": "docs/design/v30/execution/receipts/V30_G3_CARD_001_SELECTION_RECEIPT.json",
      "receiptLaw": "Bootstrap receipts are expected-absent append-only files in the separate coordination repository. Bind the authority/manifest digests, request ID, exact previous/new sequence and ledger digests, and observed product install or projection commit/tree/diff. Never self-record the future coordination commit containing a receipt. Card 1 may record a product-side validation mirror only in its exact fence; that mirror is not a second canonical ledger or activation.",
      "eventLaw": "After bootstrap, append request-result and transition records inside the one runtimeMutablePaths ledger. Preserve earlier events and request IDs. A duplicate request ID with identical input returns its original result; different input or expected ref/sequence/digest mismatch has no effect. No new coordination file or writer tool is implicitly authorized.",
    })
    value["authorityContentDigest"]=digest(canon({k:v for k,v in value.items() if k!="authorityContentDigest"})+b"\n")
    return value
def main() -> int:
    ap=argparse.ArgumentParser(); g=ap.add_mutually_exclusive_group(required=True); g.add_argument("--apply",action="store_true"); g.add_argument("--check",action="store_true"); a=ap.parse_args(); value=build()
    if a.apply:
        OUT.write_bytes(json.dumps(value,ensure_ascii=False,indent=2,sort_keys=True).encode()+b"\n")
        print(json.dumps({"result":"APPLIED","authorityID":ID,"authorityContentDigest":value["authorityContentDigest"],"sha256":digest(OUT.read_bytes())},sort_keys=True))
    else:
        req(OUT.is_file() and load(OUT)==value,"authority differs from deterministic projection")
        print(json.dumps({"result":"PASS","authorityID":ID,"authorityContentDigest":value["authorityContentDigest"],"sha256":digest(OUT.read_bytes())},sort_keys=True))
    return 0
if __name__=="__main__":
    try: raise SystemExit(main())
    except (Hold,ValueError) as e: print(json.dumps({"result":"HOLD","reason":str(e)},sort_keys=True),file=sys.stderr); raise SystemExit(2)
