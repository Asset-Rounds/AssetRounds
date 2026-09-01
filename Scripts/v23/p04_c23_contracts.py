from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COORD = Path(r"C:\AssetRounds-v23-coordination")
CARD = "V23-P04-C23"
BASE = "de600b5251eaa4f1859aa045854457152cde4365"
BTREE = "947c7f00ace38000961199a8106ee88094a3afbf"
HEAD = "4a9d04003f8882ebffefea1b0bd3fa2a186f8346"
CTREE = "b6143c9b3cc047f2ab8fc166ace84806a578d94c"
CONTEXT = "e857b3600c37b20e71fdb6595a5c073155672fefa46068e8ef5453a94c1c6a58"
FENCE = "38070aad8a4a76fec3eea1f7e2df267a6819e2eaf47035d4c7dae45ec4da4aa8"
ALLOCATION = "4d52ffa0bce9f189ece4db4c08e9f0c791b2005ccc926741de84a1ec1d8f1aea"
PREREQ = "aa02c9ef1be576e59bc808b945663270cd8efc185c78e35e4c1f6bef69711a22"
SEQ = 481
CORRECTION_RECEIPT = "aef474ba8a012dfd6642514b2101efb3ee7751c5f55457d43b66b6a311e77a4d"
FINAL_HASHES_SEALED = True
SCHEMA = "Scripts/v23/ocr-proposal.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C23OCRProposalContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C23OCRProposalEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C23BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C23-tooling-manifest.json"
SCRIPTS = ("Scripts/v23/p04_c23_contracts.py", "Scripts/v23/generate_p04_c23_contracts.py", "Scripts/v23/verify_p04_c23_contracts.py")
OWNED = set((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SELECTORS = (
    "testV23P04C23G01SupportedExplicitOCRReviewAcceptAndNoAutomaticWrite",
    "testV23P04C23A01UnsupportedLanguageDeviceAndCompleteManualFallback",
    "testV23P04C23H01LowConfidenceConflictStaleTargetAndHostileSources",
    "testV23P04C23I01CancellationMemoryPressureAndScratchCleanup",
    "testV23P04C23R01AcceptedReceiptRestoreNoEphemeralOrphanAndAccessibility",
)
FLAGS = {x: False for x in ("physicalDevice", "native", "hosted", "activation", "adoption", "acceptance", "publication", "release", "phase10PollingDuringParallelExecution")}

def pretty(value): return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()
def sha(value): return hashlib.sha256(value).hexdigest()
def git(*args, cwd=ROOT): return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()

def authority():
    path = COORD / "contexts/V23-P04-C23-attempt-1"
    context = json.loads((path / "BootstrapCardContextV1.json").read_bytes())
    fence = json.loads((path / "BootstrapPathFenceV1.json").read_bytes())
    proof = fence["priorFenceProof"]
    if (git("rev-parse", "HEAD", cwd=COORD), git("rev-parse", "HEAD^{tree}", cwd=COORD)) != (HEAD, CTREE): raise ValueError("C23 coordination head/tree differs")
    if (context["contextDigest"], fence["fenceDigest"], context["ownerAuthorizedPathAllocationDigest"], context["provisionalPrerequisiteDigest"]) != (CONTEXT, FENCE, ALLOCATION, PREREQ): raise ValueError("C23 authority digest differs")
    if (len(context["existingPaths"]), len(context["newPaths"]), len(fence["allowedCreateOrReplacePaths"]), proof["fenceCount"], proof["priorOwnedPathCount"], proof["authorizedOverlapCount"], proof["unauthorizedOverlapCount"], proof["s10ReservedOverlapCount"]) != (25, 14, 39, 4, 315, 39, 0, 0): raise ValueError("C23 fence proof differs")
    return context, fence

def sources():
    _, fence = authority()
    return tuple(path for path in fence["allowedCreateOrReplacePaths"] if path not in OWNED)

def rows():
    values = [{"path": path, "status": "SOURCE_PRESENT" if (ROOT / path).is_file() else "SOURCE_MISSING", "sha256": sha((ROOT / path).read_bytes()) if (ROOT / path).is_file() else None} for path in sources()]
    return values, all(row["status"] == "SOURCE_PRESENT" for row in values)

def counts():
    _, fence = authority(); owned = set(fence["allowedCreateOrReplacePaths"])
    parse = lambda text: {line.replace("\\", "/") for line in text.splitlines() if line}
    changed = parse(git("diff", "--name-only", BASE, "HEAD")) | parse(git("diff", "--name-only", "HEAD")) | parse(git("diff", "--cached", "--name-only")) | parse(git("ls-files", "--others", "--exclude-standard")) | OWNED
    return {"changedPathCount": len(changed & owned), "missingPathCount": sum(not (ROOT / path).is_file() for path in owned - OWNED), "unownedChangedPathCount": len(changed - owned), "s10ReservationOverlapCount": len(owned & set(fence["activeS10ReservedPaths"]))}

def semantics(ready):
    if not ready: return
    text = {path: (ROOT / path).read_text(encoding="utf-8", errors="replace") for path in sources()}
    corpus = text.get("FieldEvidenceAppTests/Fixtures/V23/Assistance/V23P04C23OCRProposalCorpusV1.json", "")
    tests = text.get("FieldEvidenceAppTests/V9_86OCRProposalTests.swift", "")
    ui = text.get("FieldEvidenceAppUITests/V23_P04_C23OCRProposalUITests.swift", "")
    policy = ROOT / "FieldEvidenceApp/Resources/FeaturePolicyV1.json"
    if sha(policy.read_bytes()) != "98a205edc22421ec4a4f2a5494628f4f40be7117a95cdd3cc94e2d6eab7c98ef" or '"featureID":"scanOCR"' not in policy.read_text(encoding="utf-8") or '"state":"PREPARED_DISABLED"' not in policy.read_text(encoding="utf-8"): raise ValueError("C23 feature policy binding differs")
    registry = ROOT / "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift"
    if not registry.is_file(): raise ValueError("C23 persistent schema registry unavailable")
    all_source = "\n".join((*text.values(), registry.read_text(encoding="utf-8", errors="replace")))
    required = ("OCRProposal", "PREPARED_DISABLED", "InjectedOnDeviceOCRProposalAdapterV1", "explicitUserAction", "requestedLanguageIdentifiers", "sourceCrop", "OCRProposalEvidenceV1", "confidence", "target", "OCRFieldReviewV1", "manualFallback", "scratchDeletionIsIdempotent", "accepted", "search", "report", "PersistentSchemaV53", "AssistanceAcceptanceReceiptRow")
    if any(token not in all_source for token in required): raise ValueError("C23 OCR source semantics missing")
    if any(selector not in tests for selector in SELECTORS) or ui.count("XCTSkip") != 5: raise ValueError("C23 selector/UI skip mismatch")
    if any(token not in corpus for token in ("REQUEST", "LANGUAGE", "CROP", "TARGET", "LOW_CONFIDENCE", "MEMORY_PRESSURE", "terminalScratchCleanupRequired")): raise ValueError("C23 hostile corpus coverage missing")
    core = text["FieldEvidenceApp/Domain/Assistance/OCRProposalContractsV1.swift"]
    coordinator = text["FieldEvidenceApp/Application/Assistance/OCRProposalCoordinatorV1.swift"]
    lifecycle = text["FieldEvidenceApp/Infrastructure/Assistance/OCRProposalLifecycleAdapterV1.swift"]
    exact_core = ("observation.crop == request.sourceCrop", "maximumRecognizedTextBytes == policy.maximumRecognizedTextBytes", "observation.validate(maximumTextBytes:maximumRecognizedTextBytes)", "case enabledOnDevice = \"ENABLED_ON_DEVICE\"")
    exact_coordinator = ("policy.activation == .enabledOnDevice", "try await scratch.prepare(request)", "try await extractor.extract(request)", "scratch.discardAfterFailedExtraction(request)")
    exact_lifecycle = ("struct InjectedOnDeviceOCRProposalAdapterV1", "AssistanceOCRProposalScratchLifecycleV1", "prepareOperation(request)", "assistanceScratch")
    exact_tests = ("XCTAssertEqual(bundle.evidence.observation.crop, bundle.request.sourceCrop)", "maximumRecognizedTextBytes: 8", "C23PrepareThenThrowScratch", "InjectedOnDeviceOCRProposalAdapterV1", "finishedDispositions.map(\\.rawValue), [\"FAILED\"]")
    if any(token not in core for token in exact_core) or any(token not in coordinator for token in exact_coordinator) or any(token not in lifecycle for token in exact_lifecycle) or any(token not in tests for token in exact_tests): raise ValueError("C23 crop/limit/scratch/injected execution guard missing")
    prohibited = ("URLSession", "http://", "https://", "autoAccept", "autoWrite", "cloudUpload", "hiddenRetention")
    if any(token in all_source for token in prohibited): raise ValueError("C23 prohibited OCR behavior found")

def documents():
    _, fence = authority(); source_rows, ready = rows(); count = counts()
    authority_value = {"cardID": CARD, "appBaseHead": BASE, "appBaseTree": BTREE, "coordinationHead": HEAD, "coordinationTree": CTREE, "sequence": SEQ, "contextDigest": CONTEXT, "pathFenceDigest": FENCE, "allocationDigest": ALLOCATION, "prerequisiteDigest": PREREQ, "correctionReceiptDigest": CORRECTION_RECEIPT, "finalHashesSealed": FINAL_HASHES_SEALED, "fencePathCount": 39, "existingPathCount": 25, "newPathCount": 14, "priorFenceCount": 4, "priorOwnedPathCount": 315, "authorizedOverlapCount": 39, "s10OverlapCount": 0, "featurePolicySHA256": "98a205edc22421ec4a4f2a5494628f4f40be7117a95cdd3cc94e2d6eab7c98ef"}
    semantics_value = {"persistentSchema": "V53", "activeModelCount": 168, "newDurableRecordCount": 0, "newDurableFamilies": [], "reusedReceipt": "AssistanceAcceptanceReceiptRow", "availability": "PREPARED_DISABLED", "statusFlags": FLAGS}
    projection = {"sourceReady": ready, "sourceRows": source_rows, "counts": count, "selectors": list(SELECTORS)}
    contract = {"schema": "V23P04C23OCRProposalContractV1", "schemaVersion": 1, "cardID": CARD, "provisional": True, "authority": authority_value, "semantics": semantics_value, "sourceProjection": projection, "testSelectors": list(SELECTORS), "statusFlags": FLAGS}
    evidence = {"schema": "V23P04C23OCRProposalEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD, "provisional": True, "authority": authority_value, "sourceProjection": projection, "contractDigest": sha(pretty(contract)), "statusFlags": FLAGS}
    brand = {"schema": "V23P04C23BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD, "provisional": True, "authority": authority_value, "semantics": semantics_value, "sourceProjection": projection, "uiAdoptionSkipped": True, "uiAcceptanceCredit": False, "statusFlags": FLAGS}
    manifest = {"schema": "V23P04C23ToolingManifestV1", "schemaVersion": 1, "cardID": CARD, "provisional": True, "finalHashesSealed": FINAL_HASHES_SEALED, "authority": authority_value, "pathFence": fence["allowedCreateOrReplacePaths"], "files": [{"path": path, "sha256": sha(pretty(value))} for path, value in ((CONTRACT, contract), (EVIDENCE, evidence), (BRAND, brand))], "sources": source_rows, "counts": count, "toolingPaths": [*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST], "statusFlags": FLAGS}
    return {CONTRACT: contract, EVIDENCE: evidence, BRAND: brand, MANIFEST: manifest}
