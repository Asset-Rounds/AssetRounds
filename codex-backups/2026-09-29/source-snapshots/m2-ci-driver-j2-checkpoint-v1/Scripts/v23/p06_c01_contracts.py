from __future__ import annotations

import copy
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P06-C01"
ORDINAL = 137
APP_HEAD = "5b6f98b3bbaceee128c52a8815b5b5e3ee5eca9e"
APP_TREE = "d6abeea2627cc312db39ca4d6476717f58040eca"
COORD_HEAD = "60f94ce514ca1a49c09866b052d5cb68ad7c2c45"
COORD_TREE = "690e75edc3465008bd0feea20bc09b33631af534"
SEQUENCE = 595
V5_SHA = "33ca39e0996baf62069f60d68b96181844160dfdcc97a2ba05e8ba045dfc46b5"
V5_SEMANTIC = "57255dfd005eedb7971f1dffb42257d06d44f4dd929788b125be1abb6fdf1e38"
V5_PATH = "docs/design/v23/authority/OwnerParallelImplementationOverrideV5.json"
RESERVATION_PATH = "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
HYDRATION = {
    "staticPreparationAnchorDigest": "6deb25429aac46a6beb9feda5c367909f048f22b719573dcc66f88db0ab603d3",
    "executionSpecificationDigest": "cfb05e1963f79c983ec432a630ea1382091e672a09fbe05228f5df5fce1da2b2",
    "pathFenceDigest": "3947043339df1ca82be0796ab09124177d73dceb665fae425376da24cdd0ba35",
    "staticPrerequisiteDigest": "dfb9170f929f56dabbdd1f514d0f3763685c200ac6f6417790c2e50c3b3dc980",
    "transitionDigest": "0de14f4105524a46b06e31c4edad322090b492aad61bccbebab2a5573bd7db6e",
    "ledgerDigest": "0c187d220f572dc595711a406502ff601e73e3078110333f3fd5656add17e622",
    "projectionDigest": "d19fa7f331b38dbd28f83bacd458e0142e47a9a1012792dc6a2b5f8926f34787",
}
COORDINATION_ARTIFACTS = {
    "receipts/V23-P00-C03-static-preparation-anchor-v1.json": ("anchorDigest", HYDRATION["staticPreparationAnchorDigest"]),
    "contexts/V23-P06-C01-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json": ("executionSpecDigest", HYDRATION["executionSpecificationDigest"]),
    "contexts/V23-P06-C01-attempt-1/ProvisionalStaticPreparationPathFenceV1.json": ("pathFenceDigest", HYDRATION["pathFenceDigest"]),
    "receipts/V23-P06-C01-provisional-static-prerequisite-set-v1.json": ("prerequisiteSetDigest", HYDRATION["staticPrerequisiteDigest"]),
    "transitions/000595-V23-P06-C01-attempt-1-NOT_STARTED-to-HYDRATING-static-preparation.json": ("transitionDigest", HYDRATION["transitionDigest"]),
}
SCRIPTS = (
    "Scripts/v23/p06_c01_contracts.py",
    "Scripts/v23/generate_p06_c01_contracts.py",
    "Scripts/v23/verify_p06_c01_contracts.py",
)
SCHEMA = "Scripts/v23/shallow-organization-static-protocol.schema.json"
CORPUS = "FieldEvidenceAppTests/Fixtures/V23/P06/ShallowOrganization/V23P06C01ShallowOrganizationStaticCorpusV1.json"
CONTRACT = "docs/design/v23/tooling/V23P06C01ShallowOrganizationStaticPreparationContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P06C01ShallowOrganizationStaticPreparationEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P06C01BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P06-C01-tooling-manifest.json"
OWNED = (*SCRIPTS, SCHEMA, CORPUS, CONTRACT, EVIDENCE, BRAND, MANIFEST)
FLAGS = {key: False for key in (
    "native", "hosted", "physical", "implementation", "acceptance", "selector",
    "release", "phase", "main", "merge", "adoption", "publication"
)}
CASE_PREFIX = "V23-P06-C01-"
CASES = tuple(CASE_PREFIX + suffix for suffix in ("G01", "A01", "H01-MALFORMED", "H01-DUPLICATE", "H01-ESCAPE", "I01", "R01"))
FORBIDDEN = ("VALIDATED_PASS", "VALIDATED_FAIL", "ACCEPTED", "READY", "RELEASED", "PHASE_INTEGRATED")

def pretty(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode("utf-8")

def sha(value): return hashlib.sha256(value).hexdigest()
def canonical(value): return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
def load(path): return json.loads((ROOT / path).read_bytes())
def git(*args): return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()

def authority():
    return {
        "cardID": CARD, "ordinal": ORDINAL, "attemptID": 1,
        "appBaseHead": APP_HEAD, "appBaseTree": APP_TREE,
        "observedCandidateIdentityPolicy": "RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN",
        "coordinationHead": COORD_HEAD, "coordinationTree": COORD_TREE,
        "sequence": SEQUENCE, "ownerOverrideV5SHA256": V5_SHA,
        "ownerOverrideV5SemanticDigest": V5_SEMANTIC, **HYDRATION,
        "disposition": "PROVISIONAL_STATIC_PREPARATION_ONLY",
        "fencePathCount": len(OWNED), "existingPathCount": 0, "newPathCount": len(OWNED),
        "s10ReservationOverlapCount": s10_overlap(), "finalHashesSealed": False,
    }

def verify_identities():
    if subprocess.run(["git", "merge-base", "--is-ancestor", APP_HEAD, "HEAD"], cwd=ROOT).returncode:
        raise ValueError("app base is not an ancestor of observed candidate")
    if git("rev-parse", f"{APP_HEAD}^{{tree}}") != APP_TREE:
        raise ValueError("frozen app base tree differs")
    verify_v5_and_reservation()
    coordination = ROOT.parent / "AssetRounds-v23-coordination"
    if not coordination.is_dir(): raise ValueError("coordination root missing")
    def cg(*args): return subprocess.run(["git", *args], cwd=coordination, check=True, capture_output=True, text=True).stdout.strip()
    if (cg("rev-parse", "HEAD"), cg("rev-parse", "origin/main"), cg("rev-parse", "HEAD^{tree}")) != (COORD_HEAD, COORD_HEAD, COORD_TREE):
        raise ValueError("coordination identity differs")
    for relative, (field, digest) in COORDINATION_ARTIFACTS.items():
        path = coordination / relative
        if not path.is_file():
            raise ValueError("hydration artifact differs:" + relative)
        verify_self_digest(load_coord(path), field, digest)
    spec = load_coord(coordination / "contexts/V23-P06-C01-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json")
    fence = load_coord(coordination / "contexts/V23-P06-C01-attempt-1/ProvisionalStaticPreparationPathFenceV1.json")
    if spec.get("protocol", {}).get("externalActions") != "NONE" or spec.get("validationStudyAuthorized") is not False or spec.get("customerData") is not False:
        raise ValueError("hydration static-only constraints differ")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != OWNED or fence.get("s10ReservedOverlapCount") != 0:
        raise ValueError("hydration path fence differs")
    ledger = load_coord(coordination / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    projection = load_coord(coordination / "projections/ActiveWorkSetProjectionV1.json")
    verify_self_digest(ledger, "ledgerDigest", HYDRATION["ledgerDigest"])
    verify_self_digest(projection, "projectionDigest", HYDRATION["projectionDigest"])
    if projection.get("ledgerDigest") != HYDRATION["ledgerDigest"] or ledger.get("casSequence") != SEQUENCE:
        raise ValueError("ledger/projection linkage differs")
    row = [r for r in ledger.get("attempts", ()) if r.get("cardID") == CARD and r.get("attemptID") == 1]
    if len(row) != 1 or row[0].get("state") != "HYDRATING" or row[0].get("canonicalDirectPrerequisiteSatisfaction") is not False:
        raise ValueError("hydrated C01 state differs")

def load_coord(path):
    return json.loads(path.read_bytes())

def verify_self_digest(value, field, expected):
    body = copy.deepcopy(value)
    actual = body.pop(field, None)
    if actual != expected or sha(canonical(body)) != expected:
        raise ValueError("self digest differs:" + field)

def verify_v5_and_reservation():
    v5_path = ROOT / V5_PATH
    if sha(v5_path.read_bytes()) != V5_SHA: raise ValueError("V5 file SHA differs")
    v5 = load(V5_PATH)
    v5_body = copy.deepcopy(v5); v5_actual = v5_body.pop("contentDigest", None)
    if v5_actual != V5_SEMANTIC or sha(json.dumps(v5_body, sort_keys=True, separators=(",", ":")).encode("utf-8")) != V5_SEMANTIC:
        raise ValueError("V5 semantic digest differs")
    plane = v5.get("provisionalStaticPreparationPlane", {})
    if plane.get("plane") != "PROVISIONAL_STATIC_PREPARATION_ONLY" or CARD not in plane.get("eligibleCardsInCanonicalOrder", ()):
        raise ValueError("V5 static plane differs")
    no_credit = v5.get("noCredit", {})
    if not all(no_credit.get(key) is True for key in ("implementationCreditProhibited", "acceptanceCreditProhibited", "selectorCreditProhibited", "releaseCreditProhibited", "phaseCreditProhibited", "mainCreditProhibited", "mergeCreditProhibited")):
        raise ValueError("V5 no-credit constraint differs")
    reservation = load(RESERVATION_PATH)
    verify_self_digest(reservation, "contentDigest", v5.get("frozenPhase10Observation", {}).get("reservationContentDigest"))
    if reservation.get("reservedPathCount") != len(reservation.get("reservedPaths", ())) or len(reservation["reservedPaths"]) != 86:
        raise ValueError("S10 reservation cardinality differs")

def s10_overlap():
    reservation = load(RESERVATION_PATH)
    return len(set(OWNED) & set(reservation.get("reservedPaths", ())))

def observed_candidate():
    return {"head": git("rev-parse", "HEAD"), "tree": git("rev-parse", "HEAD^{tree}"), "baseHead": APP_HEAD, "baseTree": APP_TREE}

def protocol():
    return {
        "schema": "V23P06C01ShallowOrganizationStaticProtocolV1", "cardID": CARD,
        "disposition": "PROVISIONAL_STATIC_PREPARATION_ONLY",
        "purpose": "Static repository-only feasibility preparation for shallow organization; not a validation study.",
        "scope": {"organizationDepth": "SHALLOW", "customerData": False, "sourceClass": "SYNTHETIC_OR_REPOSITORY_ONLY", "externalActions": "NONE"},
        "hypothesis": "Existing local/shared contracts can represent shallow workspace organization and delegated package administration without a second writer, store, kernel, backend, auth, billing, network, or product behavior.",
        "disconfirmers": ["second writer", "second store", "new kernel", "backend", "auth", "billing", "network", "customer data", "public product claim", "loss of manual offline fallback"],
        "preconditions": {"p00C03": "NOT_PREELIGIBLE_PRESERVED", "p04C13": "PROVISIONAL_ONLY", "realValidationStudy": False},
        "expiry": {"maximumDays": 30, "reconcileOnAcceptedS10_6": True, "invalidateOn": ["authority-change", "register-change", "graph-change", "reservation-change", "origin-main-change", "predecessor-checkpoint-change", "revocation"]},
        "evidenceIDs": list(CASES),
        "flags": FLAGS,
        "forbiddenResults": list(FORBIDDEN),
    }

def corpus():
    cases = [
        {"id":CASES[0], "kind":"golden", "input":"synthetic shallow organization", "expected":"STATIC_PROTOCOL_ONLY"},
        {"id":CASES[1], "kind":"accessibility", "input":"en-US and RTL terminology review", "expected":"STATIC_PROTOCOL_ONLY"},
        {"id":CASES[2], "kind":"hostile", "input":"malformed shallow organization", "expected":"REJECT_NO_STUDY"},
        {"id":CASES[3], "kind":"hostile", "input":"duplicate local identity", "expected":"REJECT_NO_STUDY"},
        {"id":CASES[4], "kind":"hostile", "input":"backend or customer-data escape", "expected":"REJECT_OUT_OF_SCOPE"},
        {"id":CASES[5], "kind":"interruption", "input":"synthetic static-review interruption", "expected":"NO_RUNTIME_CLAIM"},
        {"id":CASES[6], "kind":"recovery", "input":"expired or revoked static protocol", "expected":"RECONCILE_OR_DISCARD"},
    ]
    return {"schema":"V23P06C01ShallowOrganizationStaticCorpusV1", "cardID":CARD,
            "disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY", "syntheticOnly":True,
            "cases":cases, "forbiddenResults":list(FORBIDDEN), "realTerminalValidationResult":False}

def schema():
    return {"$schema":"https://json-schema.org/draft/2020-12/schema", "title":"V23 P06 C01 static protocol", "type":"object", "additionalProperties":False,
            "required":["schema","cardID","disposition","purpose","scope","hypothesis","disconfirmers","preconditions","expiry","evidenceIDs","flags","forbiddenResults"],
            "properties":{"schema":{"const":"V23P06C01ShallowOrganizationStaticProtocolV1"},"cardID":{"const":CARD},"disposition":{"const":"PROVISIONAL_STATIC_PREPARATION_ONLY"},"purpose":{"type":"string"},"scope":{"type":"object"},"hypothesis":{"type":"string"},"disconfirmers":{"type":"array","minItems":9},"preconditions":{"type":"object"},"expiry":{"type":"object"},"evidenceIDs":{"type":"array","minItems":7},"flags":{"type":"object"},"forbiddenResults":{"type":"array","minItems":6}}}

def validate_protocol(value):
    if value != protocol(): raise ValueError("protocol semantic drift")
    if value["disposition"] != "PROVISIONAL_STATIC_PREPARATION_ONLY" or any(value["flags"].values()): raise ValueError("provisional credit or disposition drift")
    if value["scope"]["customerData"] or value["scope"]["externalActions"] != "NONE" or value["preconditions"]["p00C03"] != "NOT_PREELIGIBLE_PRESERVED": raise ValueError("source/privacy prerequisite drift")
    if tuple(value["evidenceIDs"]) != CASES: raise ValueError("canonical evidence IDs differ")
    forbidden_text = json.dumps(value).lower()
    for token in ("second writer", "second store", "new kernel", "backend", "auth", "billing", "network"):
        if token not in forbidden_text: raise ValueError("missing disconfirmer:" + token)

def documents():
    verify_identities(); p = protocol(); c = corpus(); validate_protocol(p)
    base = {"schema":"V23P06C01StaticPreparationToolingV1","cardID":CARD,"authority":authority(),"appBaseIdentity":{"head":APP_HEAD,"tree":APP_TREE},"observedCandidateIdentityPolicy":"RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN","disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","flags":FLAGS,"noProductionPath":True,"noRealStudy":True,"noAcceptanceCredit":True}
    contract = {**base,"contract":"ShallowOrganizationStaticPreparationContractV1","protocol":p,"corpusPath":CORPUS}
    evidence = {**base,"receipt":"ShallowOrganizationStaticPreparationEvidenceReceiptV1","protocolSHA256":sha(pretty(p)),"corpusSHA256":sha(pretty(c)),"result":"PASS_STATIC_PROVISIONAL","terminalValidationResult":None}
    brand = {**base,"manifest":"ShallowOrganizationBrandImpactManifestV1","impact":"NONE_SHIPPING","requiresMergeTimeS10_6Reconciliation":True}
    values = {SCHEMA:schema(), CORPUS:c, CONTRACT:contract, EVIDENCE:evidence, BRAND:brand}
    manifest = {**base,"manifest":"V23P06C01ToolingManifestV1","pathFence":list(OWNED),"generatedFiles":[{"path":k,"sha256":sha(pretty(v))} for k,v in values.items()],"canonicalGeneration":"MANIFEST_LAST_ATOMIC_REPLACE"}
    values[MANIFEST] = manifest
    return values

def changed_paths():
    if subprocess.run(["git", "merge-base", "--is-ancestor", APP_HEAD, "HEAD"], cwd=ROOT).returncode:
        raise ValueError("cannot compute fence from non-descendant candidate")
    paths = {line.replace("\\", "/") for line in git("diff", "--name-only", APP_HEAD, "HEAD").splitlines() if line}
    result = set(subprocess.run(["git", "status", "--porcelain=v1"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.splitlines())
    for row in result:
        if len(row) < 4:
            continue
        path = row[3:].replace("\\", "/")
        target = ROOT / path
        if target.is_dir():
            paths.update(item.relative_to(ROOT).as_posix() for item in target.rglob("*") if item.is_file())
        else:
            paths.add(path)
    return paths

def counts():
    changed = changed_paths(); owned = set(OWNED)
    return {"changedPathCount":len(changed & owned), "missingOwnedPathCount":sum(not (ROOT/p).is_file() for p in owned), "unownedChangedPathCount":len(changed-owned), "s10ReservationOverlapCount":s10_overlap(), "fencePathCount":len(OWNED)}

def self_test():
    p = protocol(); rejected=[]
    for name, change in (("false-flag",lambda x:x["flags"].__setitem__("release",True)),("customer-data",lambda x:x["scope"].__setitem__("customerData",True)),("external-action",lambda x:x["scope"].__setitem__("externalActions","OUTREACH")),("p00-validated",lambda x:x["preconditions"].__setitem__("p00C03","VALIDATED_PASS"))):
        value=copy.deepcopy(p); change(value)
        try: validate_protocol(value)
        except ValueError: rejected.append(name)
    if len(rejected) != 4: raise ValueError("hostile self-test accepted mutation")
    return {"result":"PASS_STATIC_PROVISIONAL","rejected":rejected}
