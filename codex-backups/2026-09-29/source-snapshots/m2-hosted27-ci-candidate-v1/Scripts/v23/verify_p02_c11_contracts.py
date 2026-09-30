#!/usr/bin/env python3
"""Hostile independent verifier for Card31 app-lock contracts."""
from __future__ import annotations
import argparse, copy, hashlib, json, re, subprocess, sys
from pathlib import Path
from typing import Any
sys.dont_write_bytecode=True
import p02_c11_contracts as c

SOURCE=[
 "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift","FieldEvidenceApp/Domain/Security/AppAccessContractsV1.swift",
 "FieldEvidenceApp/Application/Ports/AppAccessPortsV1.swift","FieldEvidenceApp/Infrastructure/Security/SystemLocalAuthenticationClientV1.swift",
 "FieldEvidenceApp/Infrastructure/Security/AppAccessGateV1.swift","FieldEvidenceApp/Infrastructure/Security/ProtectedIngressCoordinatorV1.swift",
 "FieldEvidenceApp/Infrastructure/Security/AppLockLifecycleCoordinatorV1.swift","FieldEvidenceAppTests/V9_15AppLockLifecycleTests.swift",
 "FieldEvidenceAppTests/Fixtures/V23/AppLock/V23P02C11AppLockLifecycleCorpusV1.json"]
TOOLS=["Scripts/v23/p02_c11_contracts.py","Scripts/v23/generate_p02_c11_contracts.py","Scripts/v23/verify_p02_c11_contracts.py",
 "Scripts/v23/device-local-app-lock-setting.schema.json","Scripts/v23/app-access-gate.schema.json","Scripts/v23/local-authentication-policy.schema.json",
 "Scripts/v23/protected-ingress.schema.json","Scripts/v23/app-lock-access-lifecycle.schema.json","Scripts/v23/app-lock-evidence-receipt.schema.json",
 "docs/design/v23/tooling/V23P02C11DeviceLocalAppLockSettingContractV1.json","docs/design/v23/tooling/V23P02C11AppAccessGateContractV1.json",
 "docs/design/v23/tooling/V23P02C11LocalAuthenticationPolicyContractV1.json","docs/design/v23/tooling/V23P02C11ProtectedIngressLifecycleContractV1.json",
 "docs/design/v23/tooling/V23P02C11AppLockEvidenceReceiptV1.json","docs/design/v23/tooling/V23-P02-C11-tooling-manifest.json"]
FENCE=SOURCE+TOOLS; GENERATED=TOOLS[3:]; SCHEMAS=TOOLS[3:9]; DOCS=TOOLS[9:14]; MANIFEST=TOOLS[14]
TESTS=["testV9_15G01OptInAccessGateUsesFreshDeviceOwnerAuthentication","testV9_15A01LockedIngressAndNotificationsRemainContentBlind",
 "testV9_15H01CorruptSettingsAndAuthenticationFailuresFailLocked","testV9_15I01BackgroundTerminationAndJournalInterruptionRecoverLocked",
 "testV9_15R01EraseClearsDeviceLocalLockAndProtectedIngress"]
SYMBOLS=["DeviceLocalAppLockSettingV1","AppAccessGateV1","AppAccessStateV1","AppLockReasonV1","LocalAuthenticationClient",
 "SystemLocalAuthenticationClient","LocalAuthenticationAvailabilityV1","LocalAuthenticationAttemptV1","LocalAuthenticationOutcomeV1",
 "LockedIngressDispositionV1","PendingLockedExternalIntentV1","ProtectedIngressStartupHygieneReceiptV1","AppLockRecoveryDispositionV1","AppLockNotificationPrivacyDispositionV1"]
FALSE={"nativeCompileRan","hostedDispatchEnabled","physicalEvidenceComplete","adoptionEnabled","acceptanceEnabled","acceptanceCredit","releaseCredit","nativeEvidenceClaimed","hostedEvidenceClaimed","releaseReady"}
class VerificationError(ValueError): pass
def read(root:Path,p:str)->bytes:
 q=root/p
 if not q.is_file(): raise VerificationError(f"missing fenced input: {p}")
 return q.read_bytes()
def load(root:Path,p:str)->dict[str,Any]:
 v=json.loads(read(root,p))
 if not isinstance(v,dict): raise VerificationError(f"object required: {p}")
 return v
def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def pretty(v:Any)->bytes:return (json.dumps(v,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n").encode()
def declaration_block(text:str,needle:str)->str:
 start=text.find(needle)
 if start<0:raise VerificationError(f"missing source declaration: {needle}")
 brace=text.find("{",start)
 if brace<0:raise VerificationError(f"missing source declaration body: {needle}")
 depth=0
 for index in range(brace,len(text)):
  if text[index]=="{":depth+=1
  elif text[index]=="}":
   depth-=1
   if depth==0:return text[start:index+1]
 raise VerificationError(f"unterminated source declaration: {needle}")
def ordered(block:str,tokens:list[str],label:str)->None:
 cursor=-1
 for token in tokens:
  found=block.find(token,cursor+1)
  if found<0:raise VerificationError(f"{label} lacks ordered token {token}")
  cursor=found
def digest_check(v:dict[str,Any],label:str)->None:
 actual=v.get("artifactDigest"); body=dict(v); body.pop("artifactDigest",None)
 if actual!=sha(pretty(body)): raise VerificationError(f"{label} artifactDigest mismatch")
def flag_check(v:Any,path:str="$")->None:
 if isinstance(v,dict):
  for k,x in v.items():
   if k in FALSE and x is not False: raise VerificationError(f"overclaim {path}.{k}")
   flag_check(x,f"{path}.{k}")
 elif isinstance(v,list):
  for i,x in enumerate(v):flag_check(x,f"{path}[{i}]")
def strict_schema(v:Any,label:str="schema",root:bool=True)->None:
 if not isinstance(v,dict): raise VerificationError(f"{label} node not object")
 if root:
  if v.get("$schema")!="https://json-schema.org/draft/2020-12/schema" or not all(k in v for k in ("$id","title")): raise VerificationError(f"{label} draft metadata")
 if v.get("type")=="object":
  props=v.get("properties"); required=v.get("required")
  if v.get("additionalProperties") is not False or not isinstance(props,dict) or not isinstance(required,list) or set(required)!=set(props) or len(required)!=len(props): raise VerificationError(f"{label} object open")
  for k,x in props.items():strict_schema(x,f"{label}.{k}",False)
 elif v.get("type")=="array":
  prefix=v.get("prefixItems")
  if v.get("items") is not False or not isinstance(prefix,list) or v.get("minItems")!=len(prefix) or v.get("maxItems")!=len(prefix): raise VerificationError(f"{label} array open")
  for i,x in enumerate(prefix):strict_schema(x,f"{label}[{i}]",False)
 elif not any(k in v for k in ("const","pattern")): raise VerificationError(f"{label} unconstrained leaf")
def validate(v:Any,s:dict[str,Any],path:str="$")->None:
 if "const" in s and v!=s["const"]: raise VerificationError(f"{path} const mismatch")
 if s.get("type")=="object":
  if not isinstance(v,dict) or set(v)!=set(s["required"]):raise VerificationError(f"{path} object closure")
  for k,x in v.items():validate(x,s["properties"][k],f"{path}.{k}")
 elif s.get("type")=="array":
  if not isinstance(v,list) or len(v)!=s["minItems"]:raise VerificationError(f"{path} array closure")
  for i,x in enumerate(v):validate(x,s["prefixItems"][i],f"{path}[{i}]")
 elif s.get("type")=="string":
  if not isinstance(v,str) or ("pattern" in s and re.fullmatch(s["pattern"],v) is None):raise VerificationError(f"{path} string mismatch")
def source_fence(root:Path)->None:
 changed=subprocess.run(["git","-C",str(root),"diff","--name-only",c.APP_BASE_HEAD],check=True,capture_output=True,text=True).stdout.splitlines()
 status=subprocess.run(["git","-C",str(root),"status","--porcelain=v1","--untracked-files=all"],check=True,capture_output=True,text=True).stdout.splitlines()
 names={x.replace("\\","/") for x in changed if x}
 for line in status:
  if " -> " in line[3:] or "D" in line[:2] or "R" in line[:2]:raise VerificationError(f"delete/rename: {line}")
  names.add(line[3:].replace("\\","/"))
 if names!=set(FENCE):raise VerificationError(f"exact fence differs: missing={sorted(set(FENCE)-names)} outside={sorted(names-set(FENCE))}")
def source_check(root:Path,fixture:dict[str,Any])->None:
 texts={p:read(root,p).decode(errors="strict") for p in SOURCE[:-1]}; joined="\n".join(texts.values())
 for symbol in SYMBOLS:
  owners=[p for p,t in texts.items() if re.search(rf"\b(?:struct|enum|protocol|actor|class|typealias)\s+{symbol}\b",t)]
  if len(owners)!=1:raise VerificationError(f"symbol owner not unique {symbol}: {owners}")
 tests=texts[SOURCE[-2]]; found=re.findall(r"\bfunc\s+(testV9_15\w+)\s*\(",tests)
 if found!=TESTS or sorted(fixture.get("testMethods",[]))!=sorted(TESTS):raise VerificationError(f"exact five tests differ: {found}")
 tokens={TESTS[0]:["AppAccessGateV1","LocalAuthenticationAttemptV1.policy","maximumEvaluationCountPerAttempt"],TESTS[1]:["LockedIngressKindV1","stageWhileLocked","receipt.disposition","InjectedProtectedIngressStoreV1","AppLockNotificationPrivacyCoordinatorV1","wrong subject"],
 TESTS[2]:["corruptOrAmbiguous","configurationUnknown","JSONDecoder().decode","performBlindStartupHygiene","contentRead","terminalSnapshotStore"],TESTS[3]:["returnedFromBackground","relaunch","recovered"],TESTS[4]:["erase(operationID:","absentDisabled","PROTECTED_INGRESS_STAGING"]}
 for method,required in tokens.items():
  start=tests.find("func "+method); end=min([x for x in [tests.find("\n    func testV9_15",start+5),len(tests)] if x!=-1]); block=tests[start:end]
  for token in required:
   if token.lower() not in block.lower():raise VerificationError(f"{method} lacks {token}")
 production="\n".join(texts[p] for p in SOURCE[:7])
 for token in [".deviceOwnerAuthentication","LAContext()","configurationUnknownLocked","maximumByteCount","maximumLifetimeSeconds","DEFERRED_UNTIL_ACCEPTED_S10_6_COMPOSITION"]:
  if token not in production:raise VerificationError(f"production omits {token}")
 lowered=production.lower()
 for forbidden in ["custompin","persistedunlockedsession = true","urlsession","cloudkit","remote wipe","identityverification = true"]:
  if forbidden in lowered:raise VerificationError(f"forbidden production token {forbidden}")
 source_contract_check(texts)
def source_contract_check(texts:dict[str,str])->None:
 domain=texts[SOURCE[1]];ports=texts[SOURCE[2]];system=texts[SOURCE[3]]
 gate=texts[SOURCE[4]];ingress=texts[SOURCE[5]];lifecycle=texts[SOURCE[6]]
 # Production effects remain behind the declared Sendable ports. A similarly
 # named concrete type without the conformance is not an implementation.
 for text,pattern,label in [
  (system,r"actor\s+SystemLocalAuthenticationClient\s*:\s*LocalAuthenticationClient\b","system authentication port"),
  (gate,r"actor\s+AppAccessGateV1\s*:\s*AppAccessGatePortV1\b","access gate port"),
  (ingress,r"actor\s+InjectedProtectedIngressStoreV1\s*:\s*ProtectedIngressStoreV1\b","protected ingress store port"),
  (lifecycle,r"actor\s+AppLockNotificationPrivacyCoordinatorV1\s*:\s*AppLockNotificationPrivacyPortV1\b","notification privacy port"),
  (lifecycle,r"actor\s+DeviceLocalAppLockSettingAdapterV1\s*:\s*DeviceLocalAppLockSettingPortV1\b","setting port"),
 ]:
  if re.search(pattern,text) is None:raise VerificationError(f"missing production conformance: {label}")
 # Every validation-bearing Codable record must route decoded bytes through
 # its validating initializer instead of accepting Swift's synthesized path.
 codable_types=re.findall(r"\bstruct\s+(\w+)\s*:\s*[^\{\n]*\bCodable\b",domain+"\n"+ports)
 if len(codable_types)!=len(set(codable_types)) or not codable_types:
  raise VerificationError("Codable validation inventory is missing or duplicated")
 combined=domain+"\n"+ports
 for name in codable_types:
  block=declaration_block(combined,f"struct {name}")
  if "init(from decoder: any Decoder) throws" not in block:
   raise VerificationError(f"synthesized Decodable bypass: {name}")
  decoder=declaration_block(block,"init(from decoder: any Decoder) throws")
  validated_init=("try self.init(" in decoder or
                  ("self.init(" in decoder and ("try validate()" in decoder or
                   ("Self.schemaVersion" in decoder and "guard" in decoder))) or
                  (re.search(r"let\s+(\w+)\s*=\s*"+re.escape(name)+r"\(",decoder) is not None and
                   re.search(r"try\s+(\w+)\.validate\(\)",decoder) is not None and
                   re.search(r"self\s*=\s*(\w+)",decoder) is not None and
                   re.search(r"let\s+(\w+)\s*=",decoder).group(1)==
                   re.search(r"try\s+(\w+)\.validate\(\)",decoder).group(1)==
                   re.search(r"self\s*=\s*(\w+)",decoder).group(1)))
  if not validated_init:
   raise VerificationError(f"decoded value skips validation: {name}")
 # Claim an authentication attempt before the first suspension, revalidate it
 # after both authentication-client awaits, and never unlock before the final
 # claim check. This rejects actor-reentrancy claim-after-await and reuse bugs.
 auth=declaration_block(gate,"func authenticate(")
 ordered(auth,["activeAttemptID = attemptID","await authentication.availability()","isCurrentAttempt(","await authentication.authenticate(attempt)","isCurrentAttempt(","activeAttemptID = nil","case .authenticated:","state = .unlockedForeground"],"authentication claim lifecycle")
 if auth.count("activeAttemptID = attemptID")!=1 or auth.count("await authentication.authenticate(attempt)")!=1:
  raise VerificationError("authentication attempt claim/evaluation is reusable")
 system_auth=declaration_block(system,"func authenticate(")
 if system_auth.count("LAContext()")!=1 or system_auth.count("evaluatePolicy(")!=1:
  raise VerificationError("system authentication must create/evaluate one fresh context")
 if "private let context" in system or "static let context" in system:
  raise VerificationError("system authentication context is persisted or reused")
 ordered(system_auth,["var outcome = await","guard contexts[attempt.attemptID] === context else {","contexts.removeValue(forKey: attempt.attemptID)","if outcome == .authenticated","context.evaluatedPolicyDomainState","acceptedPolicyDomainState != observed","outcome = .biometryChanged","self.acceptedPolicyDomainState = observed","context.invalidate()","return outcome"],"authentication domain-state lifecycle")
 for token in ["private var acceptedPolicyDomainState: Data?","init(acceptedPolicyDomainState: Data? = nil)","func acceptedPolicyDomainStateSnapshot() -> Data?"]:
  if token not in system:raise VerificationError(f"authentication domain-state contract omits {token}")
 # Ingress work captures an unlocked session and proves the same session after
 # every awaited store effect. Returning metadata without that last proof is a
 # stale-session content admission.
 resume=declaration_block(ingress,"func resumeAfterAuthentication()")
 awaits=[x.start() for x in re.finditer(r"(?:try\s+)?await\s+store\.(?:pendingIntents|remove|markReadyForAuthenticatedValidation)",resume)]
 proofs=[x.start() for x in re.finditer(r"try await requireSameUnlockedSession\(sessionID\)",resume)]
 if len(awaits)<2 or len(proofs)<len(awaits):
  raise VerificationError("protected ingress omits post-await same-session proof")
 for position in awaits:
  if not any(proof>position for proof in proofs):
   raise VerificationError("protected ingress has a store await after its final session proof")
 if proofs[-1]>resume.rfind("return ready"):
  raise VerificationError("protected ingress same-session proof occurs after return")
 # Lifecycle mutations must share one closed claim owner across enable,
 # disable, recovery, lifecycle handling, and Erase; defer closes claims even
 # when an injected effect throws. This rejects actor-reentrant interleaving.
 for token in ["activeOperationID","beginOperation(","endOperation("]:
  if token not in lifecycle:raise VerificationError(f"lifecycle operation claim omits {token}")
 for signature in ["func enable(","func disable(","func recoverAfterAuthentication(","func erase("]:
  block=declaration_block(lifecycle,signature)
  if "beginOperation(" not in block or "defer" not in block or not any(
      close in block for close in ("endOperation(","release(")):
   raise VerificationError(f"lifecycle mutation not closed against interleaving: {signature}")
 release=declaration_block(lifecycle,"private func release(")
 if "endOperation(" not in release:
  raise VerificationError("lifecycle release bypasses paired endOperation")
 handle=declaration_block(lifecycle,"func handle(")
 switch=handle.find("switch event")
 if switch<0 or any(token in handle[:switch] for token in ("beginOperation(","claim(","release(","endOperation(")):
  raise VerificationError("ordinary lifecycle handling takes the configuration-operation claim")
 if "case .erase:" not in handle or "try await erase(operationID: operationID)" not in handle:
  raise VerificationError("lifecycle Erase does not delegate to the claimed Erase operation")
 disable=declaration_block(lifecycle,"func disable(")
 ordered(disable,["let write = try await setting.writeAppLockSetting(","DeviceLocalAppLockSettingV1(isEnabled: false)","let notification = try await notifications.rebuildPriorPolicy(journal)"],"disable fail-closed effect order")
 notification=declaration_block(lifecycle,"actor AppLockNotificationPrivacyCoordinatorV1")
 for signature in ["func applyGenericProjection(","func rebuildPriorPolicy("]:
  if "Self.sameSubject(current, journal)" not in declaration_block(notification,signature):
   raise VerificationError(f"terminal notification adoption is not exact-subject: {signature}")
 subject=declaration_block(notification,"private static func sameSubject(")
 for token in ["lhs.operationID == rhs.operationID","lhs.targetEnabled == rhs.targetEnabled","lhs.priorPolicy == rhs.priorPolicy","lhs.projections == rhs.projections"]:
  if token not in subject:raise VerificationError(f"terminal notification subject omits {token}")
 declaration=declaration_block(domain,"struct AppLockLifecycleDeclarationV1")
 declaration_validation=declaration_block(declaration,"func validate() throws")
 frozen={"schemaVersion":"Self.schemaVersion","writerCommand":".deviceLocalOnly","canonicalQuery":".deviceLocalOnly","migration":".idempotentRecovery","filesystemBackup":".excluded","semanticBackup":".excluded","replaceRestore":".excluded","clone":".excluded","fork":".excluded","importDisposition":".injectedAuthority","export":".denied","search":".denied","delete":".eraseRequired","erase":".eraseRequired","retention":".deviceLocalOnly","downgrade":".denied","forwardFix":".idempotentRecovery","interruptionRecovery":".idempotentRecovery","idempotentReceipt":".idempotentRecovery","shippingAdoption":".deferredUntilAcceptedS10_6Composition"}
 for field,value in frozen.items():
  if f"{field} == {value}" not in declaration_validation:
   raise VerificationError(f"lifecycle declaration field is not frozen: {field}")
 # Coordinator construction is closed over injected effects; no default or
 # ambient singleton may silently become a second authority.
 bootstrap=declaration_block(lifecycle,"static func bootstrap(")
 for injected in ["setting: any DeviceLocalAppLockSettingPortV1","authentication: any LocalAuthenticationClient","ingressStore: any ProtectedIngressStoreV1","notifications: any AppLockNotificationPrivacyPortV1","clock: any ApplicationClock","identifiers: any ApplicationIDSource"]:
  if injected not in bootstrap:raise VerificationError(f"bootstrap omits injected effect: {injected}")
 if re.search(r"(?:=\s*\.\w+|=\s*\w+\(\))\s*[,)]",bootstrap[:bootstrap.find(") async")]) is not None:
  raise VerificationError("bootstrap admits ambient/default effect authority")
 for text,actor,port,field in [
  (ingress,"actor InjectedProtectedIngressStoreV1", "ProtectedIngressDurableEffectPortV1", "effects"),
  (lifecycle,"actor AppLockNotificationPrivacyCoordinatorV1", "AppLockNotificationEffectPortV1", "effects"),
 ]:
  block=declaration_block(text,actor)
  if f"private let {field}: any {port}" not in block or f"init({field}: any {port})" not in block:
   raise VerificationError(f"production coordinator is not closed over injected {port}")
 hygiene=declaration_block(ingress,"func performBlindStartupHygiene(")
 ordered(hygiene,["try claimMutation()","performBlindStartupHygieneEffect(","!receipt.contentRead","readBlindStartupHygieneReceiptEffect(","receiptReadback == receipt","validatedSnapshot()","pendingReadback.count == receipt.retainedValidCount","+ receipt.deferredAmbiguousCount","return receipt"],"blind startup hygiene")
 snapshot=declaration_block(ingress,"private func validatedSnapshot()")
 if "values.count <= ProtectedIngressCoordinatorV1.maximumPendingIntentCount" not in snapshot or "Self.isActivePersistedDisposition($0.disposition)" not in snapshot:
  raise VerificationError("pending ingress snapshot is not bounded/closed to active dispositions")
 disposition=declaration_block(ingress,"private static func isActivePersistedDisposition(")
 active=[".stagedProtectedPendingAuthentication",".readyForAuthenticatedValidation",".deferredAmbiguousOwnership"]
 terminal=[".duplicateAdopted",".rejectedUnsupportedKind",".rejectedSize",".rejectedStorage",".rejectedProtectedData",".expiredDeleted",".consumed",".erased"]
 for token in active:
  if token not in disposition[:disposition.find("return true")]:raise VerificationError(f"active ingress disposition rejected: {token}")
 for token in terminal:
  if token not in disposition[disposition.find("return true"):disposition.find("return false")]:raise VerificationError(f"terminal ingress disposition may persist: {token}")
 ready=declaration_block(ingress,"func markReadyForAuthenticatedValidation(")
 ordered(ready,["existing.disposition == .stagedProtectedPendingAuthentication","existing.disposition == .deferredAmbiguousOwnership","existing.advancing(to: .readyForAuthenticatedValidation)","replacePendingIntentEffect(","expected: existing","replacement: replacement","validatedSnapshot()","== replacement","return replacement"],"authenticated deferred-ingress CAS")
 if any(token in ready.lower() for token in ("parse(","deserialize(","decrypt(","preview(","payloaddata","contents(of:")):
  raise VerificationError("authenticated deferred-ingress transition reads payload content")
 bootstrap=declaration_block(lifecycle,"static func bootstrap(")
 ordered(bootstrap,["let settingRead = await setting.readAppLockSetting()","performBlindStartupHygiene(","let gate = AppAccessGateV1(","if hygiene.requiresAuthenticatedRecovery","await gate.markConfigurationUnknown()","return coordinator"],"typed-setting hygiene gate bootstrap")
 setting_position=bootstrap.find("let settingRead = await setting.readAppLockSetting()")
 hygiene_position=bootstrap.find("performBlindStartupHygiene(")
 gate_positions=[x.start() for x in re.finditer(r"AppAccessGateV1\(",bootstrap)]
 if len(gate_positions)!=1 or gate_positions[0]<hygiene_position or hygiene_position<setting_position:
  raise VerificationError("access gate construction precedes typed-setting startup hygiene")
def fixture_check(f:dict[str,Any])->None:
 serialized=json.dumps(f,ensure_ascii=False)
 if any(marker in serialized for marker in ("\ufffd","Ã","â€","â€™","â€œ","â€�")):
  raise VerificationError("fixture contains replacement characters or UTF-8 mojibake")
 exact={"schemaVersion","fixtureIdentity","authority","activation","testMethods","evidenceIDs","exactCopy","setting","accessStates","lockReasons","lifecycleEvents","lifecycleMatrix","authentication","gatedEntryPoints","ingressKinds","lockedIngress","notificationPrivacy","interruptionBoundaries","recovery","erase","claimFlags","accessibility","physicalEvidence"}
 if set(f)!=exact or f.get("fixtureIdentity")!="V23-P02-C11-APP-LOCK-LIFECYCLE-CORPUS-V1":raise VerificationError("fixture closure/identity")
 if f["authority"]!={"cardID":c.CARD,"contextDigest":c.CONTEXT_DIGEST,"pathFenceDigest":c.FENCE_DIGEST,"baseHead":c.APP_BASE_HEAD}:raise VerificationError("fixture authority")
 if f["setting"].get("defaultEnabled") is not False or f["setting"].get("persistsUnlockedSession") is not False:raise VerificationError("setting default/session")
 if f["authentication"].get("policy")!="DEVICE_OWNER_AUTHENTICATION" or f["authentication"].get("freshContextPerAttempt") is not True or f["authentication"].get("maximumEvaluationsPerContext")!=1:raise VerificationError("authentication policy")
 if f["notificationPrivacy"].get("mixedPrivateAndGenericAllowed") is not False:raise VerificationError("notification privacy")
 if any(v is not False for v in f["claimFlags"].values()):raise VerificationError("claim overstatement")
 if f["erase"].get("nextLaunchState")!="DISABLED" or "PROTECTED_INGRESS_STAGING" not in f["erase"].get("clears",[]):raise VerificationError("erase closure")
def semantic(root:Path,docs:dict[str,dict[str,Any]],manifest:dict[str,Any],fixture:dict[str,Any])->None:
 expected_rows=[{"path":p,"bytes":len((b:=read(root,p))),"sha256":sha(b),"present":True} for p in SOURCE]
 schemas=["V23P02C11DeviceLocalAppLockSettingContractV1","V23P02C11AppAccessGateContractV1","V23P02C11LocalAuthenticationPolicyContractV1","V23P02C11ProtectedIngressLifecycleContractV1","V23P02C11AppLockEvidenceReceiptV1"]
 for (p,v),name in zip(docs.items(),schemas):
  if v.get("schema")!=name or v.get("cardID")!=c.CARD or v.get("sourceBindings")!=expected_rows:raise VerificationError(f"document identity/binding {p}")
  if v.get("pathFence",{}).get("authorizedPriorOverlap")!=[c.OVERLAP]:raise VerificationError("overlap binding")
  digest_check(v,p);flag_check(v,p)
 if docs[DOCS[0]]["setting"]!=fixture["setting"] or docs[DOCS[1]]["lifecycleMatrix"]!=fixture["lifecycleMatrix"]:raise VerificationError("setting/gate fixture binding")
 expected_gate_policy={"freshAttemptRequired":True,"noPersistedUnlock":True,"coldBackgroundTerminationLockNowLock":True,
  "transientSystemSheetDoesNotRelock":True,"backgroundDuringAuthenticationCancels":True,
  "ordinaryLifecycleEventsPreemptConfiguration":True,"handleDoesNotClaimConfigurationOperation":True,
  "eraseDelegatesToClaimedErase":True,"disableSettingFalseBeforePriorPolicyRebuild":True,
  "exactTerminalNotificationAdoption":True,"lifecycleDeclarationExactFieldFreeze":True,
  "shippingAdoption":"DEFERRED_UNTIL_ACCEPTED_S10_6_COMPOSITION"}
 if docs[DOCS[1]].get("policy")!=expected_gate_policy:raise VerificationError("gate/lifecycle policy differs")
 if docs[DOCS[2]]["authentication"]!=fixture["authentication"] or docs[DOCS[3]]["notificationPrivacy"]!=fixture["notificationPrivacy"]:raise VerificationError("auth/ingress fixture binding")
 expected_hygiene={"runsBeforeGateConstruction":True,"metadataOnly":True,"contentRead":False,"maximumInspectedCount":128,
  "removesOnlyKnownOwnedExpiredOrInterrupted":True,"ambiguousOwnershipDisposition":"CONFIGURATION_UNKNOWN_LOCKED",
  "exactReceiptReadbackRequired":True,"typedPendingReadbackCount":"RETAINED_VALID_PLUS_DEFERRED_AMBIGUOUS",
  "deferredAuthenticatedTransition":"EXACT_CAS_TO_READY_FOR_AUTHENTICATED_VALIDATION","deferredTransitionPayloadRead":False,
  "activePersistedDispositions":["STAGED_PROTECTED_PENDING_AUTHENTICATION","READY_FOR_AUTHENTICATED_VALIDATION","DEFERRED_AMBIGUOUS_OWNERSHIP"],
  "terminalPersistedDispositionsRejected":["DUPLICATE_ADOPTED","REJECTED_UNSUPPORTED_KIND","REJECTED_SIZE","REJECTED_STORAGE","REJECTED_PROTECTED_DATA","EXPIRED_DELETED","CONSUMED","ERASED"]}
 if docs[DOCS[3]].get("startupHygiene")!=expected_hygiene:raise VerificationError("startup hygiene policy differs")
 expected_auth_policy={"laPolicy":"DEVICE_OWNER_AUTHENTICATION","freshContextPerAttempt":True,"passcodeFallbackAllowed":True,
  "customPIN":False,"identityAssertion":False,"maximumEvaluationsPerContext":1,
  "acceptedPolicyDomainStateDeviceLocal":True,"acceptedPolicyDomainStateInjectable":True,
  "compareEvaluatedPolicyDomainStateAfterSuccess":True,"changedDomainStateOutcome":"BIOMETRY_CHANGED",
  "changedDomainStateCurrentAttemptFailsClosed":True,"changedDomainStateNeverUnlocks":True,
  "observedChangedDomainStateBecomesFreshRetryBaseline":True,"freshRetryRequiredAfterDomainChange":True,
  "cancelledLateCallbackCannotMutateAcceptedDomainState":True}
 if docs[DOCS[2]].get("policy")!=expected_auth_policy:raise VerificationError("authentication domain-state policy differs")
 if docs[DOCS[4]]["erase"]!=fixture["erase"] or docs[DOCS[4]]["claimFlags"]!=fixture["claimFlags"]:raise VerificationError("evidence lifecycle binding")
 manifest_check(root,manifest)
def manifest_check(root:Path,m:dict[str,Any])->None:
 if m.get("pathFence")!=FENCE or m.get("pathFenceCount")!=24 or m.get("existingPaths")!=[SOURCE[0]] or m.get("newPaths")!=FENCE[1:]:raise VerificationError("manifest fence partitions")
 if m.get("sourcePaths")!=SOURCE or m.get("sourcePathCount")!=9 or m.get("toolingPaths")!=TOOLS or m.get("toolingPathCount")!=15 or m.get("generatedPaths")!=GENERATED:raise VerificationError("manifest path partitions")
 rows=m.get("artifacts"); expected=[]
 for p in FENCE[:-1]:
  b=read(root,p);expected.append({"path":p,"bytes":len(b),"sha256":sha(b)})
 if rows!=expected or m.get("artifactCount")!=23 or m.get("artifactSetDigest")!=sha(pretty(expected)):raise VerificationError("manifest sealed rows")
 proof=m.get("fenceProof",{})
 if (proof.get("priorFenceCount"),proof.get("priorOwnedPathCount"),proof.get("priorFenceOverlapCount"),proof.get("authorizedPriorFenceOverlapCount"),proof.get("unauthorizedPriorFenceOverlapCount"))!=(31,481,1,1,0) or proof.get("authorizedOverlapEdges")!=[c.OVERLAP] or proof.get("activeS10Overlap") is not False:raise VerificationError("manifest overlap proof")
 if m.get("pendingFencePaths")!=[] or m.get("pendingArtifactCount")!=0 or m.get("strictSchemaCount")!=6:raise VerificationError("manifest pending/schema")
 digest_check(m,"manifest");flag_check(m,"manifest")
def expect_fail(fn:Any,label:str)->None:
 try:fn()
 except (VerificationError,KeyError,TypeError,ValueError):return
 raise VerificationError(f"hostile tamper accepted: {label}")
def hostile(root:Path,docs:dict[str,dict[str,Any]],manifest:dict[str,Any],schemas:dict[str,dict[str,Any]],fixture:dict[str,Any])->None:
 s=copy.deepcopy(schemas[SCHEMAS[0]]);s["properties"]["setting"]["additionalProperties"]=True;expect_fail(lambda:strict_schema(s),"open schema")
 d=copy.deepcopy(docs);d[DOCS[0]]["policy"]["defaultDisabled"]=False;expect_fail(lambda:semantic(root,d,manifest,fixture),"enabled default")
 d=copy.deepcopy(docs);d[DOCS[1]]["policy"]["noPersistedUnlock"]=False;expect_fail(lambda:semantic(root,d,manifest,fixture),"persisted unlock")
 d=copy.deepcopy(docs);d[DOCS[1]]["policy"]["ordinaryLifecycleEventsPreemptConfiguration"]=False;expect_fail(lambda:semantic(root,d,manifest,fixture),"lifecycle cannot preempt configuration")
 d=copy.deepcopy(docs);d[DOCS[2]]["policy"]["laPolicy"]="BIOMETRICS_ONLY";expect_fail(lambda:semantic(root,d,manifest,fixture),"wrong LA policy")
 d=copy.deepcopy(docs);d[DOCS[2]]["policy"]["changedDomainStateNeverUnlocks"]=False;expect_fail(lambda:semantic(root,d,manifest,fixture),"changed domain state unlock")
 d=copy.deepcopy(docs);d[DOCS[2]]["policy"]["observedChangedDomainStateBecomesFreshRetryBaseline"]=False;expect_fail(lambda:semantic(root,d,manifest,fixture),"changed domain state retry loop")
 d=copy.deepcopy(docs);d[DOCS[3]]["gateBefore"].remove("PARSE");expect_fail(lambda:semantic(root,d,manifest,fixture),"parse before gate")
 d=copy.deepcopy(docs);d[DOCS[3]]["startupHygiene"]["contentRead"]=True;expect_fail(lambda:semantic(root,d,manifest,fixture),"startup hygiene reads content")
 d=copy.deepcopy(docs);d[DOCS[3]]["startupHygiene"]["terminalPersistedDispositionsRejected"].remove("ERASED");expect_fail(lambda:semantic(root,d,manifest,fixture),"terminal ingress row survives")
 d=copy.deepcopy(docs);d[DOCS[3]]["startupHygiene"]["deferredTransitionPayloadRead"]=True;expect_fail(lambda:semantic(root,d,manifest,fixture),"deferred transition reads payload")
 d=copy.deepcopy(docs);d[DOCS[4]]["erase"]["clears"].remove("PROTECTED_INGRESS_STAGING");expect_fail(lambda:semantic(root,d,manifest,fixture),"erase orphan")
 m=copy.deepcopy(manifest);m["fenceProof"]["unauthorizedPriorFenceOverlapCount"]=1;expect_fail(lambda:manifest_check(root,m),"unauthorized overlap")
 m=copy.deepcopy(manifest);m["artifacts"][0]["sha256"]="0"*64;expect_fail(lambda:manifest_check(root,m),"artifact digest")
 f=copy.deepcopy(fixture);f["claimFlags"]["appPIN"]=True;expect_fail(lambda:fixture_check(f),"PIN claim")
 f=copy.deepcopy(fixture);f["authentication"]["freshContextPerAttempt"]=False;expect_fail(lambda:fixture_check(f),"context reuse")
 f=copy.deepcopy(fixture);f["exactCopy"]["setting"]="AssetRounds â€™ lock";expect_fail(lambda:fixture_check(f),"fixture mojibake")
 d=copy.deepcopy(docs);d[DOCS[4]]["provisional"]["adoptionEnabled"]=True;expect_fail(lambda:semantic(root,d,manifest,fixture),"adoption overclaim")
 texts={p:read(root,p).decode(errors="strict") for p in SOURCE[:-1]}
 def source_tamper(path:str,old:str,new:str,label:str)->None:
  altered=dict(texts)
  if old not in altered[path]:raise VerificationError(f"hostile source anchor missing: {label}")
  altered[path]=altered[path].replace(old,new,1)
  expect_fail(lambda:source_contract_check(altered),label)
 source_tamper(SOURCE[4],"activeAttemptID = attemptID","activeAttemptID = nil","authentication claim after await")
 source_tamper(SOURCE[4],"guard isCurrentAttempt(attemptID, generation: capturedGeneration) else {","guard true else {","stale authentication result")
 source_tamper(SOURCE[3],"// A fresh context is created here, never cached or reused across attempts.\n        let context = LAContext()","// hostile reuse\n        let context = sharedContext","reused authentication context")
 source_tamper(SOURCE[3],"acceptedPolicyDomainState != observed","acceptedPolicyDomainState == observed","wrong authentication domain-state comparison")
 source_tamper(SOURCE[3],"outcome = .biometryChanged","outcome = .authenticated","changed authentication domain state unlock")
 source_tamper(SOURCE[3],"guard contexts[attempt.attemptID] === context else {","guard true else {","cancelled callback mutates authentication metadata")
 source_tamper(SOURCE[3],"self.acceptedPolicyDomainState = observed","_ = observed","changed authentication domain state retry loop")
 source_tamper(SOURCE[5],"try await requireSameUnlockedSession(sessionID)","try await gate.requireContentAccess()","stale ingress session")
 source_tamper(SOURCE[5],"!receipt.contentRead","receipt.contentRead","startup hygiene content read")
 source_tamper(SOURCE[5],"receiptReadback == receipt","receiptReadback.operationID == receipt.operationID","startup hygiene inexact receipt adoption")
 source_tamper(SOURCE[5],"existing.disposition == .deferredAmbiguousOwnership","existing.disposition == .readyForAuthenticatedValidation","deferred ingress cannot recover")
 source_tamper(SOURCE[5],"expected: existing,","expected: replacement,","deferred ingress non-CAS mutation")
 source_tamper(SOURCE[5],".consumed, .erased:",".consumed:\n            return false\n        case .erased:","terminal ingress persisted row")
 source_tamper(SOURCE[6],"let settingRead = await setting.readAppLockSetting()","let settingRead = await setting.readAppLockSetting()\n        let gate = AppAccessGateV1(setting: settingRead, authentication: authentication, clock: clock, identifiers: identifiers)","gate constructed before startup hygiene")
 source_tamper(SOURCE[1],"init(from decoder: any Decoder) throws","init(from otherDecoder: any Decoder) throws","synthesized Decodable bypass")
 source_tamper(SOURCE[1],"shippingAdoption: try values.decode(AppLockShippingAdoptionV1.self, forKey: .shippingAdoption)\n        )\n        try validate()","shippingAdoption: try values.decode(AppLockShippingAdoptionV1.self, forKey: .shippingAdoption)\n        )\n        // hostile validation bypass","decoded lifecycle declaration validation bypass")
 source_tamper(SOURCE[3],": LocalAuthenticationClient", "", "missing authentication port conformance")
 source_tamper(SOURCE[6],"try beginOperation(operationID)","_ = operationID","lifecycle interleaving")
 source_tamper(SOURCE[6],"try validate(operationID)\n        switch event","try validate(operationID)\n        try beginOperation(operationID)\n        switch event","lifecycle preemption blocked by global claim")
 source_tamper(SOURCE[6],"try await erase(operationID: operationID)","try await performErase(operationID: operationID)","lifecycle Erase bypasses claim")
 source_tamper(SOURCE[6],"lhs.projections == rhs.projections","true","terminal notification adopts conflicting subject")
 source_tamper(SOURCE[6],"let write = try await setting.writeAppLockSetting(\n                DeviceLocalAppLockSettingV1(isEnabled: false)","let write = try await setting.writeAppLockSetting(\n                DeviceLocalAppLockSettingV1(isEnabled: true)","disable restores details before durable false")
 source_tamper(SOURCE[1],"writerCommand == .deviceLocalOnly","writerCommand != .deviceLocalOnly","unfrozen lifecycle declaration")
 source_tamper(SOURCE[6],"static func bootstrap(\n        setting: any DeviceLocalAppLockSettingPortV1","static func bootstrap(\n        setting: DeviceLocalAppLockSettingAdapterV1 = .shared","ambient coordinator effect")
def main()->int:
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[2]);root=parser.parse_args().root.resolve()
 try:
  source_fence(root);fixture=load(root,SOURCE[-1]);fixture_check(fixture);source_check(root,fixture)
  run=subprocess.run([sys.executable,"-B",str(root/c.GENERATOR_SCRIPT),"--check","--root",str(root)],cwd=root,capture_output=True,text=True)
  if run.returncode or run.stdout.strip()!="Card31 verified 12 deterministic artifacts":raise VerificationError(f"generator --check failed: {run.stdout}{run.stderr}")
  docs={p:load(root,p) for p in DOCS};schemas={p:load(root,p) for p in SCHEMAS};manifest=load(root,MANIFEST)
  for p,s in schemas.items():strict_schema(s,p)
  for p,v,s in zip(DOCS,[docs[x] for x in DOCS],[schemas[x] for x in SCHEMAS[:5]]):validate(v,s,p)
  validate(docs[DOCS[4]],schemas[SCHEMAS[5]],DOCS[4])
  try:
   import jsonschema
   for p,v,s in zip(DOCS,[docs[x] for x in DOCS],[schemas[x] for x in SCHEMAS[:5]]):jsonschema.Draft202012Validator(s).validate(v)
  except ImportError:pass
  semantic(root,docs,manifest,fixture);hostile(root,docs,manifest,schemas,fixture)
  print("Card31 hostile verifier PASS: 24 fence paths, 23 sealed inputs, 6 strict schemas, 5 evidence tests, 1 authorized C10 overlap");return 0
 except (OSError,ValueError,KeyError,subprocess.SubprocessError) as error:
  print(f"Card31 hostile verifier FAIL: {error}",file=sys.stderr);return 1
if __name__=="__main__":raise SystemExit(main())
