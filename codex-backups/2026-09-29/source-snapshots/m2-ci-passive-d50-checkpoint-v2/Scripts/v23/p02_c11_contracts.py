#!/usr/bin/env python3
"""Deterministic Card31 app-lock tooling contracts."""
from __future__ import annotations

import hashlib, json, re, subprocess, sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
CARD = "V23-P02-C11"
ORDINAL = 31
APP_BASE_HEAD = "3acab655d53f76f2f2b2e3fc5c27464b4d385ac5"
APP_BASE_TREE = "d897c15c99f82b993bd3072caf3ce7e937c224c5"
CONTEXT_DIGEST = "b864682eb37661d7b0316331e9f53de201b7027cc4f8363e130ce5ee66015469"
FENCE_DIGEST = "c9bef9203b66eea8e816413a646ee5f3ef530ca3d1d5797be43c8f05314207a5"
PREREQUISITE_DIGEST = "1b8045783e35c40f4068db8e692c81751c1d76f58760572a680c699c1ffb4195"
C10_FENCE_DIGEST = "9d402508388e16f092697f74de5bdc56fbe8eee6934bfa40c5eeb12675d905d7"
C10_CONTEXT_DIGEST = "30e8590878c7ebf335245cbc37e160523194a0be0cef648c125eda46e2aa294e"
C10_VERIFICATION_DIGEST = "5cbe13f4521b03cf3a7b2793715373f0ec4f36be9adbcdf6a0cf0fca5f851ed4"
C10_CHECKPOINT_DIGEST = "d34b2c65f7bda83e42d01efee9f846d99d4b20893ef30668316b83d25a208820"
S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

SOURCE_PATHS = [
 "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
 "FieldEvidenceApp/Domain/Security/AppAccessContractsV1.swift",
 "FieldEvidenceApp/Application/Ports/AppAccessPortsV1.swift",
 "FieldEvidenceApp/Infrastructure/Security/SystemLocalAuthenticationClientV1.swift",
 "FieldEvidenceApp/Infrastructure/Security/AppAccessGateV1.swift",
 "FieldEvidenceApp/Infrastructure/Security/ProtectedIngressCoordinatorV1.swift",
 "FieldEvidenceApp/Infrastructure/Security/AppLockLifecycleCoordinatorV1.swift",
 "FieldEvidenceAppTests/V9_15AppLockLifecycleTests.swift",
 "FieldEvidenceAppTests/Fixtures/V23/AppLock/V23P02C11AppLockLifecycleCorpusV1.json",
]
TOOL_PATHS = [
 "Scripts/v23/p02_c11_contracts.py", "Scripts/v23/generate_p02_c11_contracts.py",
 "Scripts/v23/verify_p02_c11_contracts.py", "Scripts/v23/device-local-app-lock-setting.schema.json",
 "Scripts/v23/app-access-gate.schema.json", "Scripts/v23/local-authentication-policy.schema.json",
 "Scripts/v23/protected-ingress.schema.json", "Scripts/v23/app-lock-access-lifecycle.schema.json",
 "Scripts/v23/app-lock-evidence-receipt.schema.json",
 "docs/design/v23/tooling/V23P02C11DeviceLocalAppLockSettingContractV1.json",
 "docs/design/v23/tooling/V23P02C11AppAccessGateContractV1.json",
 "docs/design/v23/tooling/V23P02C11LocalAuthenticationPolicyContractV1.json",
 "docs/design/v23/tooling/V23P02C11ProtectedIngressLifecycleContractV1.json",
 "docs/design/v23/tooling/V23P02C11AppLockEvidenceReceiptV1.json",
 "docs/design/v23/tooling/V23-P02-C11-tooling-manifest.json",
]
GENERATOR_SCRIPT = TOOL_PATHS[1]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = TOOL_PATHS[3:]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
EXISTING_PATHS = [SOURCE_PATHS[0]]
NEW_PATHS = PATH_FENCE[1:]
SCHEMAS = TOOL_PATHS[3:9]
DOCS = TOOL_PATHS[9:14]
MANIFEST = TOOL_PATHS[14]
TEST_METHODS = [
 "testV9_15G01OptInAccessGateUsesFreshDeviceOwnerAuthentication",
 "testV9_15A01LockedIngressAndNotificationsRemainContentBlind",
 "testV9_15H01CorruptSettingsAndAuthenticationFailuresFailLocked",
 "testV9_15I01BackgroundTerminationAndJournalInterruptionRecoverLocked",
 "testV9_15R01EraseClearsDeviceLocalLockAndProtectedIngress",
]
CONTRACT_SYMBOLS = ["DeviceLocalAppLockSettingV1", "AppAccessGateV1", "AppAccessStateV1",
 "AppLockReasonV1", "LocalAuthenticationClient", "SystemLocalAuthenticationClient",
 "LocalAuthenticationAvailabilityV1", "LocalAuthenticationAttemptV1",
 "LocalAuthenticationOutcomeV1", "LockedIngressDispositionV1",
 "PendingLockedExternalIntentV1", "ProtectedIngressStartupHygieneReceiptV1", "AppLockRecoveryDispositionV1",
 "AppLockNotificationPrivacyDispositionV1"]
OVERLAP = {"path": SOURCE_PATHS[0], "priorCardID": "V23-P02-C10",
 "priorFenceDigest": C10_FENCE_DIGEST,
 "disposition": "AUTHORIZED_SEMANTIC_EXTENSION_OF_DEVICE_LOCAL_TYPED_SETTING_REGISTRY_FOR_APP_LOCK_WITH_PREDECESSOR_EVIDENCE_BOUND",
 "boundEvidence": {"cardID":"V23-P02-C10","attemptID":1,"candidateHead":APP_BASE_HEAD,
 "candidateTree":APP_BASE_TREE,"contextDigest":C10_CONTEXT_DIGEST,"pathFenceDigest":C10_FENCE_DIGEST,
 "verificationReceiptDigest":C10_VERIFICATION_DIGEST,"checkpointDigest":C10_CHECKPOINT_DIGEST}}

class ContractError(ValueError): pass
def sha(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def pretty(value: Any) -> bytes:
 return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)+"\n").encode()
def seal(value: dict[str, Any]) -> dict[str, Any]:
 out=dict(value); out["artifactDigest"]=sha(pretty(out)); return out
def read(root: Path, rel: str) -> bytes:
 path=root/rel
 if not path.is_file(): raise ContractError(f"missing fenced input: {rel}")
 return path.read_bytes()
def load(root: Path, rel: str) -> dict[str, Any]:
 value=json.loads(read(root,rel))
 if not isinstance(value,dict): raise ContractError(f"object required: {rel}")
 return value
def enum_values(text: str, name: str) -> list[str]:
 m=re.search(rf"enum\s+{re.escape(name)}\b[^{{]*{{",text)
 if not m: raise ContractError(f"missing enum {name}")
 depth=0; end=None
 for i in range(m.end()-1,len(text)):
  if text[i]=="{": depth+=1
  elif text[i]=="}":
   depth-=1
   if depth==0: end=i; break
 if end is None: raise ContractError(f"unterminated enum {name}")
 return re.findall(r'\bcase\s+\w+\s*=\s*"([^"]+)"',text[m.end():end])
def flags() -> dict[str,Any]:
 return {"executionMode":"PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION","provisionalKernelOnly":True,
 "nativeCompileRan":False,"hostedDispatchEnabled":False,"physicalEvidenceComplete":False,
 "physicalLockedState":"REQUIRED_PENDING_OWNER","adoptionEnabled":False,"acceptanceEnabled":False,
 "acceptanceCredit":False,"releaseCredit":False,"phase10PollingDuringParallelExecution":False,
 "requiresAcceptedS10_6Reconciliation":True}
def authority() -> dict[str,Any]:
 return {"cardID":CARD,"registerOrdinal":ORDINAL,"appBaseHead":APP_BASE_HEAD,"appBaseTree":APP_BASE_TREE,
 "contextDigest":CONTEXT_DIGEST,"pathFenceDigest":FENCE_DIGEST,"provisionalPrerequisiteDigest":PREREQUISITE_DIGEST,
 "directPrerequisites":["V23-P02-C10"],"invalidationConsumers":["V23-P04-C14","V23-P04-C16"],
 "lineage":"ADDED_V23","conformanceSubjects":["KernelConformanceSubjectSetV1","FJ10"]}
def source_rows(root:Path)->list[dict[str,Any]]:
 return [{"path":p,"bytes":len((b:=read(root,p))),"sha256":sha(b),"present":True} for p in SOURCE_PATHS]
def semantics(root:Path)->dict[str,Any]:
 fixture=load(root,SOURCE_PATHS[-1]); tests=read(root,SOURCE_PATHS[-2]).decode(); domain=read(root,SOURCE_PATHS[1]).decode()
 found=re.findall(r"\bfunc\s+(testV9_15\w+)\s*\(",tests)
 if found != TEST_METHODS: raise ContractError(f"exact Card31 tests differ: {found}")
 if sorted(fixture.get("testMethods",[])) != sorted(TEST_METHODS): raise ContractError("fixture test methods differ")
 for symbol in CONTRACT_SYMBOLS:
  if not any(symbol in read(root,p).decode(errors="ignore") for p in SOURCE_PATHS[:-2]):
   raise ContractError(f"missing contract symbol: {symbol}")
 enums={name:enum_values(domain,name) for name in ["AppLockReasonV1","LocalAuthenticationBiometryV1",
  "LocalAuthenticationAvailabilityStatusV1","LocalAuthenticationTriggerV1","LocalAuthenticationOutcomeV1",
  "LockedIngressKindV1","LockedIngressDispositionV1","AppLockRecoveryDispositionV1",
  "AppLockNotificationPrivacyDispositionV1","AppLockLifecycleEventV1"]}
 return {"fixture":fixture,"fixtureDigest":sha(read(root,SOURCE_PATHS[-1])),"tests":found,"enums":enums,
  "sourceBindings":source_rows(root)}
def common(root:Path,s:dict[str,Any])->dict[str,Any]:
 return {"schemaVersion":1,"cardID":CARD,"authority":authority(),"pathFence":{"paths":PATH_FENCE,"count":24,
 "digest":FENCE_DIGEST,"s10Overlap":False,"authorizedPriorOverlap":[OVERLAP]},"provisional":flags(),
 "exactFiveTests":{"required":True,"methods":TEST_METHODS,"count":5},"sourceBindings":s["sourceBindings"]}
def contracts(root:Path)->dict[str,dict[str,Any]]:
 s=semantics(root); f=s["fixture"]; c=common(root,s)
 setting=seal({**c,"schema":"V23P02C11DeviceLocalAppLockSettingContractV1","owner":"DeviceLocalAppLockSettingV1",
  "setting":f["setting"],"copy":f["exactCopy"],"registryOwner":"SettingsRegistryV1",
  "policy":{"optIn":True,"defaultDisabled":True,"soleDevicePreferenceAdapter":True,"backupExcluded":True,
  "persistedUnlockedSession":False,"eraseResetsDisabled":True,"corruptAmbiguousFutureFailLocked":True}})
 gate=seal({**c,"schema":"V23P02C11AppAccessGateContractV1","owner":"AppAccessGateV1",
  "accessStates":f["accessStates"],"lockReasons":f["lockReasons"],"lifecycleMatrix":f["lifecycleMatrix"],
  "lifecycleEvents":f["lifecycleEvents"],
  "enums":s["enums"],"policy":{"freshAttemptRequired":True,"noPersistedUnlock":True,
  "coldBackgroundTerminationLockNowLock":True,"transientSystemSheetDoesNotRelock":True,
  "backgroundDuringAuthenticationCancels":True,"ordinaryLifecycleEventsPreemptConfiguration":True,
  "handleDoesNotClaimConfigurationOperation":True,"eraseDelegatesToClaimedErase":True,
  "disableSettingFalseBeforePriorPolicyRebuild":True,"exactTerminalNotificationAdoption":True,
  "lifecycleDeclarationExactFieldFreeze":True,
  "shippingAdoption":"DEFERRED_UNTIL_ACCEPTED_S10_6_COMPOSITION"}})
 auth=seal({**c,"schema":"V23P02C11LocalAuthenticationPolicyContractV1","owner":"SystemLocalAuthenticationClient",
  "authentication":f["authentication"],"policy":{"laPolicy":"DEVICE_OWNER_AUTHENTICATION","freshContextPerAttempt":True,
  "passcodeFallbackAllowed":True,"customPIN":False,"identityAssertion":False,"maximumEvaluationsPerContext":1,
  "acceptedPolicyDomainStateDeviceLocal":True,"acceptedPolicyDomainStateInjectable":True,
  "compareEvaluatedPolicyDomainStateAfterSuccess":True,"changedDomainStateOutcome":"BIOMETRY_CHANGED",
  "changedDomainStateCurrentAttemptFailsClosed":True,"changedDomainStateNeverUnlocks":True,
  "observedChangedDomainStateBecomesFreshRetryBaseline":True,"freshRetryRequiredAfterDomainChange":True,
  "cancelledLateCallbackCannotMutateAcceptedDomainState":True}})
 ingress=seal({**c,"schema":"V23P02C11ProtectedIngressLifecycleContractV1","owner":"ProtectedIngressLifecycleV1",
  "ingressKinds":f["ingressKinds"],"lockedIngress":f["lockedIngress"],"notificationPrivacy":f["notificationPrivacy"],
  "gatedEntryPoints":f["gatedEntryPoints"],
  "scratch":{"contentBlind":True,"trustedPathOwnershipProtectionAgeOnly":True,"ambiguousWaitsForAuthentication":True},
  "startupHygiene":{"runsBeforeGateConstruction":True,"metadataOnly":True,"contentRead":False,
   "maximumInspectedCount":128,"removesOnlyKnownOwnedExpiredOrInterrupted":True,
   "ambiguousOwnershipDisposition":"CONFIGURATION_UNKNOWN_LOCKED","exactReceiptReadbackRequired":True,
   "typedPendingReadbackCount":"RETAINED_VALID_PLUS_DEFERRED_AMBIGUOUS",
   "deferredAuthenticatedTransition":"EXACT_CAS_TO_READY_FOR_AUTHENTICATED_VALIDATION",
   "deferredTransitionPayloadRead":False,
  "activePersistedDispositions":["STAGED_PROTECTED_PENDING_AUTHENTICATION","READY_FOR_AUTHENTICATED_VALIDATION","DEFERRED_AMBIGUOUS_OWNERSHIP"],
   "terminalPersistedDispositionsRejected":["DUPLICATE_ADOPTED","REJECTED_UNSUPPORTED_KIND","REJECTED_SIZE","REJECTED_STORAGE","REJECTED_PROTECTED_DATA","EXPIRED_DELETED","CONSUMED","ERASED"]},
  "gateBefore":["PARSE","PREVIEW","INDEX","RESOLUTION","RENDER","MUTATION"]})
 evidence=seal({**c,"schema":"V23P02C11AppLockEvidenceReceiptV1","owner":"V9_15AppLockLifecycleTests",
  "evidence":[{"evidenceID":f"{CARD}-{family}","testMethod":method,"family":family}
   for family,method in zip(["G01","A01","H01","I01","R01"],TEST_METHODS)],"interruptionBoundaries":f["interruptionBoundaries"],
  "recovery":f["recovery"],"erase":f["erase"],"claimFlags":f["claimFlags"],"accessibility":f["accessibility"],
  "physicalEvidence":f["physicalEvidence"],"fixtureBinding":{"sha256":s["fixtureDigest"],"topLevelKeys":sorted(f),"value":f},
  "sourceDigestRows":s["sourceBindings"],"brandImpact":{"manifestCount":1,"changedScreens":[],"changedStates":[],
  "affectedConsumers":[CARD,"V23-P04-C14","V23-P04-C16"],"nativeOrHostedClaimed":False}})
 return dict(zip(DOCS,[setting,gate,auth,ingress,evidence]))
def strict(v:Any,key:str="")->dict[str,Any]:
 if isinstance(v,dict): return {"type":"object","additionalProperties":False,"required":list(v),"properties":{k:strict(x,k) for k,x in v.items()}}
 if isinstance(v,list): return {"type":"array","minItems":len(v),"maxItems":len(v),"prefixItems":[strict(x) for x in v],"items":False}
 if isinstance(v,bool) or v is None or isinstance(v,(int,float)): return {"const":v}
 if isinstance(v,str):
  if key=="artifactDigest" or key.lower().endswith("digest") or key=="sha256": return {"type":"string","pattern":"^[0-9a-f]{64}$"}
  return {"const":v}
 raise ContractError(f"unsupported schema type {type(v)}")
def schema(title:str,v:dict[str,Any])->dict[str,Any]:
 out=strict(v); out.update({"$schema":"https://json-schema.org/draft/2020-12/schema","$id":f"https://assetrounds.invalid/v23/{title}.schema.json","title":title}); return out
def manifest(root:Path,generated:dict[str,bytes],s:dict[str,Any])->dict[str,Any]:
 rows=[]
 for p in MANIFEST_INPUT_PATHS:
  b=generated[p] if p in generated else read(root,p); rows.append({"path":p,"bytes":len(b),"sha256":sha(b)})
 return seal({"schema":"V23-P02-C11-tooling-manifest","schemaVersion":1,"cardID":CARD,
  "generator":{"version":"p02-c11-contracts-v1","seed":230211},"authority":authority(),"pathFence":PATH_FENCE,
  "pathFenceCount":24,"existingPaths":EXISTING_PATHS,"newPaths":NEW_PATHS,"sourcePaths":SOURCE_PATHS,"sourcePathCount":9,
  "toolingPaths":TOOL_PATHS,"toolingPathCount":15,"generatedPaths":GENERATED_PATHS,"artifacts":rows,"artifactCount":23,
  "pendingFencePaths":[],"pendingArtifactCount":0,"artifactSetDigest":sha(pretty(rows)),"strictSchemaCount":6,
  "fenceProof":{"baseHead":APP_BASE_HEAD,"baseTree":APP_BASE_TREE,"pathFenceDigest":FENCE_DIGEST,
  "priorFenceCount":31,"priorOwnedPathCount":481,"priorFenceOverlapCount":1,"authorizedPriorFenceOverlapCount":1,
  "unauthorizedPriorFenceOverlapCount":0,"authorizedOverlapEdges":[OVERLAP],"allowedDeletePaths":[],"allowedRenamePaths":[],
  "activeS10ReservationDigest":S10_DIGEST,"activeS10Overlap":False},"semanticCoverage":{"contractSymbolCount":len(CONTRACT_SYMBOLS),
  "exactTestCount":5,"interruptionBoundaryCount":len(s["fixture"]["interruptionBoundaries"]),"fixtureDigest":s["fixtureDigest"],"sourcePending":False},
  **flags()})
def validate_fence(root:Path)->None:
 changed=subprocess.run(["git","-C",str(root),"diff","--name-only",APP_BASE_HEAD],check=True,capture_output=True,text=True).stdout.splitlines()
 status=subprocess.run(["git","-C",str(root),"status","--porcelain=v1","--untracked-files=all"],check=True,capture_output=True,text=True).stdout.splitlines()
 names={x.replace("\\","/") for x in changed if x}
 for line in status:
  if " -> " in line[3:] or "D" in line[:2] or "R" in line[:2]: raise ContractError(f"delete/rename forbidden: {line}")
  names.add(line[3:].replace("\\","/"))
 outside=sorted(names-set(PATH_FENCE))
 if outside: raise ContractError(f"Card31 out-of-fence delta: {outside}")
def all_outputs(root:Path)->dict[str,bytes]:
 validate_fence(root); docs=contracts(root); s=semantics(root)
 schema_docs=[docs[DOCS[0]],docs[DOCS[1]],docs[DOCS[2]],docs[DOCS[3]],docs[DOCS[4]],docs[DOCS[4]]]
 generated={p:pretty(schema(Path(p).stem,v)) for p,v in zip(SCHEMAS,schema_docs)}
 generated.update({p:pretty(v) for p,v in docs.items()}); generated[MANIFEST]=pretty(manifest(root,generated,s)); return generated
if __name__=="__main__":
 print(json.dumps({"authorizedPriorOverlapCount":1,"card":CARD,"fenceCount":24,"generatedCount":12},sort_keys=True))
