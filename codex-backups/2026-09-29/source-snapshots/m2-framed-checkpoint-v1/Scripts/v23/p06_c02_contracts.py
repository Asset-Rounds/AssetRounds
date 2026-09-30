from __future__ import annotations

import copy
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD, ORDINAL = "V23-P06-C02", 138
APP_BASE, APP_TREE = "01d5fdcdaad3bd9b4f59dba22b42a51f1ac4c3b3", "bbb05df9632fda7e23294af1e073a4242ff0c969"
COORD_HEAD, COORD_TREE, SEQUENCE = "edbd7235b1097f04f98c0fc70bdc4035082378f3", "61d43e7b9297b6090e1d0e89c7429529192decbb", 599
V5_PATH = "docs/design/v23/authority/OwnerParallelImplementationOverrideV5.json"
V5_SHA, V5_DIGEST = "33ca39e0996baf62069f60d68b96181844160dfdcc97a2ba05e8ba045dfc46b5", "57255dfd005eedb7971f1dffb42257d06d44f4dd929788b125be1abb6fdf1e38"
RESERVATION_PATH = "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
HYDRATION = {"staticPreparationAnchorDigest":"6deb25429aac46a6beb9feda5c367909f048f22b719573dcc66f88db0ab603d3","executionSpecDigest":"3d4db1bd5e29ce55debc1b622eed2e776afac9d18b1894fe305014a4a696e27f","pathFenceDigest":"efee91b7c07695426561d5a3b220ebf829f8d5cec8bbcb0778cd0fd5dad1291a","prerequisiteSetDigest":"ef8f5ce259d8ebe1922fb11f2c31dd7893fa99717fc0b914c98e84c90adf7c41","transitionDigest":"1644d21dc5099b6ef14a8e8d5953ad4bd5c20de162357b2667d90f3766bf3653","ledgerDigest":"4058e103c2924150cdc08a21b4f7783221e89651df20d79ee4afc5e35daa7ee6","projectionDigest":"1108643c3014e1da8fed418cca7c8518af12e3dbafc356a9c86366edd202b49f"}
P04 = (("V23-P04-C23","b72edc2db3c0fcf59f50fd4af51bb8be3c308b0107c3e681fd2c91742a2a7599","fc939bec28e4ebe79801399f2bc589a83ea78447ccc17d4f24f9f27ccd118fbe","3a338afa490daa214c07e7e80264769436d4383e","1e5d88c62f195555d5ec16cdced0f7998c9d61b2"),("V23-P04-C24","30ada73a63ae79cf60ebe87ab3bc7c34bafe2a4a825986b269e852360a3e0b8f","bf129fa4917b40a74eb88834e7e02a3498c7294bf0bf335a9d7a7052708960f0","e65c2b807fe6242b383c24947d454c099c0f8265","206747a8ff6df2c7d80a24f58e2152619c1d75f3"))
SCRIPTS=("Scripts/v23/p06_c02_contracts.py","Scripts/v23/generate_p06_c02_contracts.py","Scripts/v23/verify_p06_c02_contracts.py")
SCHEMA="Scripts/v23/assisted-capture-static-protocol.schema.json"
CORPUS="FieldEvidenceAppTests/Fixtures/V23/P06/AssistedCapture/V23P06C02AssistedCaptureStaticCorpusV1.json"
CONTRACT="docs/design/v23/tooling/V23P06C02AssistedCaptureStaticPreparationContractV1.json"
EVIDENCE="docs/design/v23/tooling/V23P06C02AssistedCaptureStaticPreparationEvidenceReceiptV1.json"
BRAND="docs/design/v23/tooling/V23P06C02BrandImpactManifestV1.json"
MANIFEST="docs/design/v23/tooling/V23-P06-C02-tooling-manifest.json"
OWNED=(*SCRIPTS,SCHEMA,CORPUS,CONTRACT,EVIDENCE,BRAND,MANIFEST)
FLAGS={key:False for key in ("native","hosted","physical","adoption","implementation","acceptance","selector","release","phase","main","merge","publication")}
PREFIX="V23-P06-C02-"
CASE_IDS=tuple(PREFIX+x for x in ("G01","A01","H01-MALFORMED","H01-NETWORK","H01-DATA","I01","R01"))
FORBIDDEN=("VALIDATED_PASS","VALIDATED_FAIL","ACCEPTED","READY","RELEASED","PHASE_INTEGRATED")

def pretty(v): return (json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def canonical(v): return (json.dumps(v,sort_keys=True,separators=(",",":"))+"\n").encode()
def sha(b): return hashlib.sha256(b).hexdigest()
def load(path): return json.loads((ROOT/path).read_bytes())
def git(*args): return subprocess.run(["git",*args],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
def coord_root(): return ROOT.parent/"AssetRounds-v23-coordination"
def c_load(path): return json.loads(path.read_bytes())
def c_git(*args): return subprocess.run(["git",*args],cwd=coord_root(),check=True,capture_output=True,text=True).stdout.strip()

def seal_check(value, field, expected):
    body=copy.deepcopy(value); actual=body.pop(field,None)
    if actual != expected or sha(canonical(body)) != expected: raise ValueError("self digest differs:"+field)

def verify_v5_reservation():
    file=ROOT/V5_PATH
    if sha(file.read_bytes()) != V5_SHA: raise ValueError("V5 byte digest differs")
    v5=load(V5_PATH); body=copy.deepcopy(v5); actual=body.pop("contentDigest",None)
    if actual != V5_DIGEST or sha(json.dumps(body,sort_keys=True,separators=(",",":")).encode()) != V5_DIGEST: raise ValueError("V5 semantic digest differs")
    if CARD not in v5.get("provisionalStaticPreparationPlane",{}).get("eligibleCardsInCanonicalOrder",()): raise ValueError("V5 eligibility differs")
    if not all(v5.get("noCredit",{}).get(k) is True for k in ("implementationCreditProhibited","acceptanceCreditProhibited","selectorCreditProhibited","releaseCreditProhibited","phaseCreditProhibited","mainCreditProhibited","mergeCreditProhibited")): raise ValueError("V5 no-credit differs")
    reservation=load(RESERVATION_PATH); expected=v5["frozenPhase10Observation"]["reservationContentDigest"]
    seal_check(reservation,"contentDigest",expected)
    if len(reservation.get("reservedPaths",())) != 86 or reservation.get("reservedPathCount") != 86: raise ValueError("reservation cardinality differs")
    return reservation

def s10_overlap(): return len(set(OWNED)&set(load(RESERVATION_PATH).get("reservedPaths",())))

def verify_coordination():
    if not coord_root().is_dir() or (c_git("rev-parse","HEAD"),c_git("rev-parse","origin/main"),c_git("rev-parse","HEAD^{tree}")) != (COORD_HEAD,COORD_HEAD,COORD_TREE): raise ValueError("coordination identity differs")
    paths={
      "receipts/V23-P00-C03-static-preparation-anchor-v1.json":("anchorDigest",HYDRATION["staticPreparationAnchorDigest"]),
      "contexts/V23-P06-C02-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json":("executionSpecDigest",HYDRATION["executionSpecDigest"]),
      "contexts/V23-P06-C02-attempt-1/ProvisionalStaticPreparationPathFenceV1.json":("pathFenceDigest",HYDRATION["pathFenceDigest"]),
      "receipts/V23-P06-C02-provisional-static-prerequisite-set-v1.json":("prerequisiteSetDigest",HYDRATION["prerequisiteSetDigest"]),
      "transitions/000599-V23-P06-C02-attempt-1-NOT_STARTED-to-HYDRATING-static-preparation.json":("transitionDigest",HYDRATION["transitionDigest"]),
      "state/BootstrapExecutionLedgerEnvelopeV1.json":("ledgerDigest",HYDRATION["ledgerDigest"]),
      "projections/ActiveWorkSetProjectionV1.json":("projectionDigest",HYDRATION["projectionDigest"]),
    }
    docs={relative:c_load(coord_root()/relative) for relative in paths}
    for relative,(field,digest) in paths.items(): seal_check(docs[relative],field,digest)
    spec=docs["contexts/V23-P06-C02-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json"]
    fence=docs["contexts/V23-P06-C02-attempt-1/ProvisionalStaticPreparationPathFenceV1.json"]
    prereq=docs["receipts/V23-P06-C02-provisional-static-prerequisite-set-v1.json"]
    if tuple(fence.get("allowedCreateOrReplacePaths",())) != OWNED or fence.get("s10ReservedOverlapCount") != 0: raise ValueError("fence differs")
    if spec.get("validationStudyAuthorized") is not False or spec.get("customerData") is not False or spec.get("externalActions") != "NONE": raise ValueError("spec static-only differs")
    if tuple((x.get("cardID"),x.get("checkpointDigest"),x.get("verificationReceiptDigest"),x.get("candidateHead"),x.get("candidateTree")) for x in prereq.get("sources",())[1:]) != P04: raise ValueError("P04 prerequisite pins differ")
    ledger=docs["state/BootstrapExecutionLedgerEnvelopeV1.json"]; projection=docs["projections/ActiveWorkSetProjectionV1.json"]
    if ledger.get("casSequence") != SEQUENCE or projection.get("ledgerDigest") != HYDRATION["ledgerDigest"]: raise ValueError("ledger projection binding differs")

def observed_candidate(): return {"head":git("rev-parse","HEAD"),"tree":git("rev-parse","HEAD^{tree}"),"baseHead":APP_BASE,"baseTree":APP_TREE}
def verify_identities():
    if subprocess.run(["git","merge-base","--is-ancestor",APP_BASE,"HEAD"],cwd=ROOT).returncode: raise ValueError("base is not ancestor")
    if git("rev-parse",f"{APP_BASE}^{{tree}}") != APP_TREE: raise ValueError("base tree differs")
    verify_v5_reservation(); verify_coordination()

def protocol(): return {"schema":"V23P06C02AssistedCaptureStaticProtocolV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","purpose":"Declarative OCR, dictation, and location assisted-capture protocol only; not a validation study.","capabilityInvoked":False,"network":False,"canonicalWrites":0,"capturedMedia":False,"modelOutput":False,"locationData":False,"scope":{"sources":"SYNTHETIC_OR_REPOSITORY_ONLY","customerData":False,"externalActions":"NONE","offlineFirst":True},"hypothesis":"Existing local capture and shared contracts can frame assisted capture as bounded offline-first refinement without backend, remote control plane, or second writer/store/kernel.","disconfirmers":["backend or auth","remote control plane","second writer","second store","new kernel","customer data","captured media","model output","location data","loss of manual offline fallback"],"preconditions":{"p00C03":"NOT_PREELIGIBLE_PRESERVED","p04C23":"PROVISIONAL_ONLY","p04C24":"PROVISIONAL_ONLY","realValidationStudy":False},"evidenceIDs":list(CASE_IDS),"expiry":{"maximumDays":30,"reconcileOnAcceptedS10_6":True,"invalidateOn":["authority-change","register-change","graph-change","reservation-change","origin-main-change","predecessor-checkpoint-change","revocation"]},"flags":FLAGS,"forbiddenResults":list(FORBIDDEN)}
def corpus(): return {"schema":"V23P06C02AssistedCaptureStaticCorpusV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","syntheticOnly":True,"realTerminalValidationResult":False,"cases":[{"id":CASE_IDS[0],"kind":"golden","input":"synthetic declarative OCR/dictation/location protocol","expected":"STATIC_PROTOCOL_ONLY"},{"id":CASE_IDS[1],"kind":"accessibility","input":"synthetic text alternatives and locale review","expected":"STATIC_PROTOCOL_ONLY"},{"id":CASE_IDS[2],"kind":"hostile","input":"malformed capability descriptor","expected":"REJECT_NO_STUDY"},{"id":CASE_IDS[3],"kind":"hostile","input":"network invocation request","expected":"REJECT_OUT_OF_SCOPE"},{"id":CASE_IDS[4],"kind":"hostile","input":"captured media model output or location data","expected":"REJECT_NO_DATA_CAPTURE"},{"id":CASE_IDS[5],"kind":"interruption","input":"synthetic static-review interruption","expected":"NO_RUNTIME_CLAIM"},{"id":CASE_IDS[6],"kind":"recovery","input":"expired or revoked static protocol","expected":"RECONCILE_OR_DISCARD"}],"forbiddenResults":list(FORBIDDEN)}
def schema(): return {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":False,"required":["schema","cardID","disposition","purpose","capabilityInvoked","network","canonicalWrites","capturedMedia","modelOutput","locationData","scope","hypothesis","disconfirmers","preconditions","evidenceIDs","expiry","flags","forbiddenResults"],"properties":{"schema":{"const":"V23P06C02AssistedCaptureStaticProtocolV1"},"cardID":{"const":CARD},"disposition":{"const":"PROVISIONAL_STATIC_PREPARATION_ONLY"},"capabilityInvoked":{"const":False},"network":{"const":False},"canonicalWrites":{"const":0},"capturedMedia":{"const":False},"modelOutput":{"const":False},"locationData":{"const":False},"evidenceIDs":{"type":"array","minItems":7},"flags":{"type":"object"}}}
def validate_protocol(v):
    if v != protocol() or any(v["flags"].values()): raise ValueError("protocol or no-credit drift")
    if tuple(v["evidenceIDs"]) != CASE_IDS or v["scope"]["customerData"] or v["scope"]["externalActions"] != "NONE" or v["preconditions"]["p00C03"] != "NOT_PREELIGIBLE_PRESERVED": raise ValueError("protocol safety drift")
    if any(v[k] for k in ("capabilityInvoked","network","capturedMedia","modelOutput","locationData")) or v["canonicalWrites"] != 0: raise ValueError("capture capability drift")
def authority(): return {"cardID":CARD,"ordinal":ORDINAL,"attemptID":1,"appBaseHead":APP_BASE,"appBaseTree":APP_TREE,"observedCandidateIdentityPolicy":"RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN","coordinationHead":COORD_HEAD,"coordinationTree":COORD_TREE,"sequence":SEQUENCE,"ownerOverrideV5SHA256":V5_SHA,"ownerOverrideV5SemanticDigest":V5_DIGEST,**HYDRATION,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","fencePathCount":9,"existingPathCount":0,"newPathCount":9,"s10ReservationOverlapCount":s10_overlap(),"finalHashesSealed":False}
def documents():
    verify_identities(); p=protocol(); c=corpus(); validate_protocol(p)
    base={"schema":"V23P06C02StaticPreparationToolingV1","cardID":CARD,"authority":authority(),"appBaseIdentity":{"head":APP_BASE,"tree":APP_TREE},"observedCandidateIdentityPolicy":"RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN","disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","flags":FLAGS,"noProductionPath":True,"noRealStudy":True,"noAcceptanceCredit":True}
    contract={**base,"contract":"AssistedCaptureStaticPreparationContractV1","protocol":p,"corpusPath":CORPUS}
    evidence={**base,"receipt":"AssistedCaptureStaticPreparationEvidenceReceiptV1","protocolSHA256":sha(pretty(p)),"corpusSHA256":sha(pretty(c)),"result":"PASS_STATIC_PROVISIONAL","terminalValidationResult":None}
    brand={**base,"manifest":"AssistedCaptureBrandImpactManifestV1","impact":"NONE_SHIPPING","requiresMergeTimeS10_6Reconciliation":True}
    values={SCHEMA:schema(),CORPUS:c,CONTRACT:contract,EVIDENCE:evidence,BRAND:brand}; values[MANIFEST]={**base,"manifest":"V23P06C02ToolingManifestV1","pathFence":list(OWNED),"generatedFiles":[{"path":k,"sha256":sha(pretty(v))} for k,v in values.items()],"canonicalGeneration":"MANIFEST_LAST_ATOMIC_REPLACE"}; return values
def changed_paths():
    if subprocess.run(["git","merge-base","--is-ancestor",APP_BASE,"HEAD"],cwd=ROOT).returncode: raise ValueError("non-descendant candidate")
    paths={line.replace("\\","/") for line in git("diff","--name-only",APP_BASE,"HEAD").splitlines() if line}
    for row in subprocess.run(["git","status","--porcelain=v1"],cwd=ROOT,check=True,capture_output=True,text=True).stdout.splitlines():
        path=row[3:].replace("\\","/"); target=ROOT/path
        if target.is_dir(): paths.update(x.relative_to(ROOT).as_posix() for x in target.rglob("*") if x.is_file())
        elif path: paths.add(path)
    return paths
def counts():
    changed=changed_paths(); return {"changedPathCount":len(changed&set(OWNED)),"missingOwnedPathCount":sum(not(ROOT/p).is_file() for p in OWNED),"unownedChangedPathCount":len(changed-set(OWNED)),"s10ReservationOverlapCount":s10_overlap(),"fencePathCount":len(OWNED)}
def self_test():
    rejected=[]
    for name,change in (("network",lambda x:x.__setitem__("network",True)),("writer",lambda x:x.__setitem__("canonicalWrites",1)),("media",lambda x:x.__setitem__("capturedMedia",True)),("data",lambda x:x["scope"].__setitem__("customerData",True))):
        value=copy.deepcopy(protocol()); change(value)
        try: validate_protocol(value)
        except ValueError: rejected.append(name)
    if len(rejected)!=4: raise ValueError("hostile self-test accepted mutation")
    return {"result":"PASS_STATIC_PROVISIONAL","rejected":rejected}
