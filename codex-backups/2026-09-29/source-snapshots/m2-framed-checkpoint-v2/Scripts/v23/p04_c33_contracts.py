from __future__ import annotations

import hashlib, json, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C33"; ORDINAL = 118
BASE = "2ebaf4312ce970bed13afc703a9af3e7e2ffdd4f"; BTREE = "ddcd18643b91de47a8b32b693444229bf9565d03"
COORD_HEAD = "f5cccd98d1285ca456621c72ad7e037a5f736ac6"; COORD_TREE = "f3d9af1af3f07a1e0a38220a04bf5d9f9545d554"
AUTH = {"cardID": CARD, "appBaseHead": BASE, "appBaseTree": BTREE, "coordinationHead": COORD_HEAD, "coordinationTree": COORD_TREE, "sequence": 529, "allocationDigest": "c2b40625385e2923f0077accc1424a8fa20fd89dd0727b9393e866ff1c756501", "prerequisiteDigest": "bf3a0578d544bd99ace8c9eef9be93a21486e8c34120a4e875f930e3020312d0", "contextDigest": "faac1486c077f7d013d12d93e0125a02ff9625624a41d8832dc140b6a033bc5f", "pathFenceDigest": "47eb449f074d28480283ae6fb73565ce56194709c018a892767d3efae0213157", "transitionDigest": "f019f89bf7d6e8070f3c441515e7bae64f17f15544fc203ee845df8680de811b", "ledgerDigest": "93dc564de45b930540127511049d6a164765033cc30a2b313d1f8ea6fb159f4e", "projectionDigest": "711a4c1a639809d3ed840d61458520ccef8adc23b27797498c0d81e88fa99d5f", "fencePathCount": 15, "existingPathCount": 2, "newPathCount": 13, "finalHashesSealed": False}
TEST="FieldEvidenceAppTests/V9_96InstallationWorkflowTests.swift"; FIXTURE="FieldEvidenceAppTests/Fixtures/V23/Activities/V23P04C33InstallationWorkflowCorpusV1.json"; UI="FieldEvidenceAppUITests/V23_P04_C33InstallationWorkflowUITests.swift"
SCHEMA="Scripts/v23/installation-workflow.schema.json"; CONTRACT="docs/design/v23/tooling/V23P04C33InstallationWorkflowContractV1.json"; EVIDENCE="docs/design/v23/tooling/V23P04C33InstallationWorkflowEvidenceReceiptV1.json"; BRAND="docs/design/v23/tooling/V23P04C33BrandImpactManifestV1.json"; MANIFEST="docs/design/v23/tooling/V23-P04-C33-tooling-manifest.json"
SCRIPTS=("Scripts/v23/p04_c33_contracts.py","Scripts/v23/generate_p04_c33_contracts.py","Scripts/v23/verify_p04_c33_contracts.py")
PRODUCT=("FieldEvidenceApp/Application/Activities/ActivityContractCoordinatorV2.swift","FieldEvidenceApp/Domain/Activities/ActivityContractFamiliesV2.swift","FieldEvidenceApp/Application/Activities/InstallationWorkflowCoordinatorV1.swift","FieldEvidenceApp/Features/Activities/InstallationWorkflowView.swift",TEST,FIXTURE,UI)
OWNED=set((*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)); FENCE=(*PRODUCT,*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTORS=("testV23P04C33G01ReadinessStartOrderedExecutionAsBuiltVariationCloseoutAndReport","testV23P04C33A01ManualNoPlanUnavailableOptionalCapabilitiesAndAlternateTruth","testV23P04C33H01WrongStaleDuplicateOrderMalformedBoundsUnicodeAndIdentityFailClosed","testV23P04C33I01CancellationInterruptionEffectBeforeReceiptAndRelaunchResumeAreBounded","testV23P04C33R01RetryReplayReceiptRecoveryImmutableHistoryAndDeterministicReportRebuild")
FLAGS={x:False for x in ("physicalDevice","physicalEvidence","native","nativeAcceptance","hosted","hostedAcceptance","activation","adoption","acceptance","publication","release")}
def pretty(v): return (json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v): return hashlib.sha256(v).hexdigest()
def git(*a): return subprocess.run(["git",*a],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
def rows():
 r=[]
 for p in PRODUCT:
  q=ROOT/p; r.append({"path":p,"status":"SOURCE_PRESENT" if q.is_file() else "SOURCE_MISSING","sha256":sha(q.read_bytes()) if q.is_file() else None})
 return r, all(x["status"]=="SOURCE_PRESENT" for x in r)
def counts():
 def names(*a): return {x.replace("\\\\","/") for x in git(*a).splitlines() if x}
 changed=names("diff","--name-only",BASE,"HEAD")|names("diff","--name-only","HEAD")|names("diff","--cached","--name-only")|names("ls-files","--others","--exclude-standard")|OWNED
 return {"changedPathCount":len(changed & set(FENCE)),"unownedChangedPathCount":len(changed-set(FENCE)),"fencePathCount":len(FENCE),"existingPathCount":2,"newPathCount":13,"productTestPathCount":5,"toolingPathCount":8,"s10ReservationOverlapCount":0,"durableFamilyCount":0,"parallelWriterCount":0,"parallelKernelCount":0,"parallelRendererCount":0}
def documents():
 r,ready=rows(); base={"schema":"V23P04C33InstallationWorkflowToolingV1","cardID":CARD,"ordinal":ORDINAL,"authority":AUTH,"sourceRows":r,"sourceReady":ready,"flags":FLAGS,"finalHashesSealed":False,"lifecycle":{"persistentSchemaVersion":36,"recordsSchemaVersion":35,"durableFamily":"NONE","newDurableFamilyCount":0,"newWriterCount":0,"newKernelCount":0,"newRendererCount":0}}
 contract={**base,"contract":"InstallationWorkflowContractV1","requirements":{"explicitStartRequired":True,"orderedExecution":True,"contextBasisBindingRequired":True,"asBuiltAndVariationEvidenceRequired":True,"recordAsBuiltDoesNotCloseout":True,"closeoutStages":["recordFieldComplete","submitForReview","finalizeRecordedCloseout"],"reportReadyOnlyWhenFinalizedAndAccepted":True,"variationRequiresExactSuccessorBasis":True,"manualFallbackAvailable":True,"providerConsumerCapabilityReceiptsRequired":True,"scanFallbackWorkspaceBound":True,"exactUnreceiptedEffectRecovery":True,"retryIsIdempotent":True,"finalizedHistoryImmutable":True,"reportRebuildDeterministic":True,"canonicalCoordinator":"InstallationWorkflowCoordinatorV1"}}
 evidence={**base,"receipt":"InstallationWorkflowEvidenceReceiptV1"}; brand={"schema":"BrandImpactManifestV1","cardID":CARD,"ordinal":ORDINAL,"flags":FLAGS,"finalHashesSealed":False,"requiresAcceptedS10_6Reconciliation":True}
 schema={"$schema":"https://json-schema.org/draft/2020-12/schema","title":"InstallationWorkflowContractV1","type":"object","required":["cardID","ordinal","authority","flags","lifecycle","requirements"],"properties":{"cardID":{"const":CARD},"ordinal":{"const":ORDINAL},"flags":{"type":"object"},"lifecycle":{"type":"object"},"requirements":{"type":"object"}}}
 h={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand)),SCHEMA:sha(pretty(schema))}; manifest={"schema":"V23P04C33ToolingManifestV1","cardID":CARD,"authority":AUTH,"pathFence":list(FENCE),"files":[{"path":p,"sha256":v} for p,v in h.items()],"sourceRows":r,"flags":FLAGS,"finalHashesSealed":False}
 return {SCHEMA:schema,CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
