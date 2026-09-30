from __future__ import annotations
import hashlib, json, os, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; CARD='V23-P04-C26'; BASE='2df711cb2e0eb7dedfe11618fc82641e760b8be7'; BTREE='dcac37cb39b42902713f15d3aff34ac93f333298'; HEAD='4a896e8d422c185ffaf05b6b09e645ebd052ed75'; CTREE='92bb3771e40f01dcb10ca99a8ed991ac0c51f2e3'; SEALED_HEAD='8c1b168842a97f94caafba3cca494a005bad8467'; SEALED_TREE='0b58ab4a7c6069d4a57a0da71b43b595ae315283'; CONTEXT='657cdeb44c2f29b11522a55e4b003b5f83b740dbe9009e5e0a26b75d0297881e'; FENCE='7e9e7da91a051d0180435b8d724f3d790d5522388b18ee95403016a275c48d41'; ALLOCATION='9dbbfb46ca60c914e0b2bc1eb1dbeb9ceba1c0e35f24b5ebdf5b747baecc1de7'; PREREQ='c595e12e2c0ff284fb30262b11183e8802b1cc409ff29daad94f8c9907a30004'; CORRECTION='a132bc8fff9189c11460eedb03b0f902b271538c159c550e8d34c7986e5156ee'; CHECKPOINT='60a606f56956d7b40617f4470f6b97723f1c7126d94a333b66421ff517471bf7'; VERIFICATION='9bd8957662b845952bdd96ee5ac61de7756e4a4839a728276426bee136944316'; ACCEPTED='cfbc01fddbba84e4b31a1c798980d0bc4c2306d7'; ACCEPTED_TREE='8582ae34472de39bae5637ad4d8df279b234c073'; SEQ=494; FINAL_HASHES_SEALED=False
CATALOG='docs/product/discovery/DiscoveryTruthCatalogV1.json'; CATALOG_SHA='c2372225274acfc819e0293bb4ea624bd434f115bc41f46c014b605e9cc099fb'; SCHEMA='Scripts/v23/organic-findability-drafts.schema.json'; CONTRACT='docs/design/v23/tooling/V23P04C26OrganicFindabilityContractV1.json'; EVIDENCE='docs/design/v23/tooling/V23P04C26OrganicFindabilityEvidenceReceiptV1.json'; BRAND='docs/design/v23/tooling/V23P04C26BrandImpactManifestV1.json'; MANIFEST='docs/design/v23/tooling/V23-P04-C26-tooling-manifest.json'; SCRIPTS=('Scripts/v23/p04_c26_contracts.py','Scripts/v23/generate_p04_c26_contracts.py','Scripts/v23/verify_p04_c26_contracts.py'); OWNED=set((*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST))
PATH_FENCE=('Scripts/release-preflight.sh','FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift','docs/product/discovery/V23P04C26AcquisitionContentDraftV1.json','docs/product/discovery/V23P04C26AppTagDispositionV1.json','docs/product/discovery/V23P04C26DiscoveryTruthCatalogRefinementReceiptV1.json','docs/product/discovery/V23P04C26MetadataEvidenceReportV1.json','docs/accessibility/V23P04C26SupportContentAccessibilityManifestV1.json','FieldEvidenceAppTests/Fixtures/V21/DiscoveryTruth/V23P04C26OrganicFindabilityCorpusV1.json','Scripts/v23/p04_c26_contracts.py','Scripts/v23/generate_p04_c26_contracts.py','Scripts/v23/verify_p04_c26_contracts.py','Scripts/v23/organic-findability-drafts.schema.json',CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTORS=('testV23P04C26G01BoundCatalogRefinementAndDisabledPublication','testV23P04C26A01ApprovalAbsenceDefersAllPublication','testV23P04C26H01HostileClaimsBindingsAndMetadataLimitsFailClosed','testV23P04C26I01ExpiryWithdrawalAndInterruptedDraftRecovery','testV23P04C26R01ReleasePreflightAndAccessibilityGateRemainPublicationIneligible')
FORBIDDEN=('publication','networkAccess','dnsHosting','appStoreSubmission','upload','paidAcquisition','analyticsProvider','customerDataUse','finalScreenshots','finalKeywords'); FLAGS={x:False for x in ('native','hosted','adoption','acceptance',*FORBIDDEN,'release')}; FROZEN_S10_SHA='1d0790ae41110078ffc10ba3af87f76e371d8cdec0a566674119b8217d868054'; PROJECTION_SHA='364da876b48c5ab5bc6578c66a6679ee2e234cd6da61eaa914b6b0b10614bf55'
DECLARATIONS={'docs/product/discovery/V23P04C26AcquisitionContentDraftV1.json':'b668e29382c1154cc93d3106d416ddf80bf6cf35915746b2b128696801064238','docs/product/discovery/V23P04C26AppTagDispositionV1.json':'dedbc785e15a6c93a477f477178ce9144bad5e01df187f80aa720e0cdd35c2c8','docs/product/discovery/V23P04C26DiscoveryTruthCatalogRefinementReceiptV1.json':'5b1594305a51e80c0a63108d317318ff570e318d63c2531b8a9c7704b8570374','docs/product/discovery/V23P04C26MetadataEvidenceReportV1.json':'468eae786e7a461e21b3e2d826269e4a1ddb875e60ecc9e1f78f050511637bf5'}
def pretty(v): return (json.dumps(v,sort_keys=True,indent=2)+'\n').encode()
def sha(v): return hashlib.sha256(v).hexdigest()
def coordination_root():
 override=os.environ.get('V23_P04_C26_COORDINATION_ROOT'); sibling=ROOT.parent/'AssetRounds-v23-coordination'
 if override=='NONE': return None
 return Path(override).expanduser().resolve() if override else (sibling if sibling.is_dir() else None)
def _coord_git(coord,*args): return subprocess.run(['git',*args],cwd=coord,capture_output=True,text=True,check=True).stdout.strip()
def _coord_json(coord,revision,path): return json.loads(subprocess.run(['git','show',revision+':'+path],cwd=coord,capture_output=True,check=True).stdout)
def _coord_blob(coord,revision,path): return _coord_git(coord,'rev-parse',revision+':'+path)
def _coord_is_ancestor(coord,ancestor,descendant): return subprocess.run(['git','merge-base','--is-ancestor',ancestor,descendant],cwd=coord,capture_output=True).returncode==0
def _app_git(*args): return subprocess.run(['git',*args],cwd=ROOT,capture_output=True,text=True,check=True).stdout.strip()
def _app_is_ancestor(ancestor,descendant): return subprocess.run(['git','merge-base','--is-ancestor',ancestor,descendant],cwd=ROOT,capture_output=True).returncode==0
def _checkpointed_c26_entry(entries):
 matches=[entry for entry in entries if entry.get('cardID')==CARD and entry.get('state')=='CHECKPOINTED']
 return matches[-1] if matches else None
def _post_checkpoint_tuple(coord,head,ledger_entry,projection_entry,sealed_ledger,sealed_projection):
 keys=('postCheckpointToolingCorrectionDigest','postCheckpointToolingVerificationHead','postCheckpointToolingVerificationTree')
 if any(ledger_entry.get(key)!=sealed_ledger.get(key) for key in sealed_ledger) or any(projection_entry.get(key)!=sealed_projection.get(key) for key in sealed_projection) or set(ledger_entry)-set(sealed_ledger)-set(keys) or set(projection_entry)-set(sealed_projection)-set(keys): raise ValueError('C26 sealed row mutation differs')
 present=[key for key in keys if key in ledger_entry or key in projection_entry]
 if not present: return
 if len(present)!=len(keys) or any(key not in ledger_entry or key not in projection_entry or ledger_entry[key]!=projection_entry[key] for key in keys): raise ValueError('C26 post-checkpoint tuple differs')
 digest,post_head,post_tree=(ledger_entry[key] for key in keys); receipt_paths=[path for path in _coord_git(coord,'ls-tree','-r','--name-only',head,'--','receipts').splitlines() if re.fullmatch(r'receipts/V23-P04-C26-post-checkpoint-tooling-verification-correction-v[1-9][0-9]*\.json',path)]
 records=[]
 for path in receipt_paths:
  records.append((int(re.search(r'-v([1-9][0-9]*)\.json$',path).group(1)),_coord_json(coord,head,path)))
 by_digest={}
 for record in records: by_digest.setdefault(record[1].get('correctionDigest'),[]).append(record)
 v1_keys={'acceptanceCredit','acceptanceEnabled','adoptionEnabled','cardID','changedPaths','checkpointImmutable','correctionDigest','createdAt','directParentHead','flagsAllFalse','hostedDispatchEnabled','hostedDispatchRan','nativeCompileRan','nextEligibleCardID','nextEligibleRegisterOrdinal','normalVerifierStatus','originalAcceptedCandidateHead','originalAcceptedCandidateTree','originalCheckpointDigest','originalVerificationReceiptDigest','phase10PollingDuringParallelExecution','physicalDeviceEnabled','portableVerifierStatus','postCheckpointToolingVerificationHead','postCheckpointToolingVerificationTree','publicationEnabled','releaseCredit','releaseReady','schema'}
 v2_keys={'acceptanceCredit','acceptanceEnabled','adoptionEnabled','cardID','correctionDigest','createdAt','cumulativeChangedPaths','directParentHead','flagsAllFalse','hostedDispatchEnabled','hostedDispatchRan','nativeCompileRan','nextEligibleCardID','nextEligibleRegisterOrdinal','normalAndPortableVerifierStatus','originalCheckpointDigest','originalVerificationReceiptDigest','phase10PollingDuringParallelExecution','physicalDeviceEnabled','postCheckpointToolingVerificationHead','postCheckpointToolingVerificationTree','priorPostCheckpointToolingVerificationHead','publicationEnabled','releaseCredit','releaseReady','schema','supersedesCorrectionDigest'}
 false_flags=('acceptanceCredit','acceptanceEnabled','adoptionEnabled','hostedDispatchEnabled','hostedDispatchRan','nativeCompileRan','phase10PollingDuringParallelExecution','physicalDeviceEnabled','publicationEnabled','releaseCredit','releaseReady')
 def validate(record,seen=()):
  version,receipt=record; receipt_digest=receipt.get('correctionDigest'); receipt_basis=dict(receipt); receipt_basis.pop('correctionDigest',None)
  if receipt_digest in seen or sha((json.dumps(receipt_basis,sort_keys=True,separators=(',',':'))+'\n').encode())!=receipt_digest or any(receipt.get(key) is not False for key in false_flags) or receipt.get('cardID')!=CARD or receipt.get('originalCheckpointDigest')!=CHECKPOINT or receipt.get('originalVerificationReceiptDigest')!=VERIFICATION: raise ValueError('C26 post-checkpoint receipt authority differs')
  receipt_head=receipt.get('postCheckpointToolingVerificationHead'); receipt_tree=receipt.get('postCheckpointToolingVerificationTree')
  if not _app_is_ancestor(ACCEPTED,receipt_head) or not _app_is_ancestor(receipt_head,_app_git('rev-parse','HEAD')) or _app_git('rev-parse',receipt_head+'^{tree}')!=receipt_tree or _app_git('rev-parse',receipt_head+'^')!=receipt.get('directParentHead') or not _app_is_ancestor(ACCEPTED,receipt.get('directParentHead')) or set(_app_git('diff','--name-only',ACCEPTED,receipt_head).splitlines())!={'Scripts/v23/p04_c26_contracts.py'}: raise ValueError('C26 post-checkpoint receipt lineage differs')
  if version==1:
   fixed={'schema':'PostCheckpointToolingVerificationCorrectionReceiptV1','originalAcceptedCandidateHead':ACCEPTED,'originalAcceptedCandidateTree':ACCEPTED_TREE,'checkpointImmutable':True,'normalVerifierStatus':'PASS_STATIC_PROVISIONAL','portableVerifierStatus':'PASS_STATIC_PROVISIONAL','changedPaths':['Scripts/v23/p04_c26_contracts.py'],'directParentHead':ACCEPTED}
   if set(receipt)!=v1_keys or any(receipt.get(key)!=value for key,value in fixed.items()): raise ValueError('C26 post-checkpoint v1 receipt differs')
  else:
   fixed={'schema':'PostCheckpointToolingVerificationCorrectionV2ReceiptV1','normalAndPortableVerifierStatus':'PASS_STATIC_PROVISIONAL','cumulativeChangedPaths':['Scripts/v23/p04_c26_contracts.py']}
   prior_matches=by_digest.get(receipt.get('supersedesCorrectionDigest'),[])
   if set(receipt)!=v2_keys or any(receipt.get(key)!=value for key,value in fixed.items()) or len(prior_matches)!=1 or prior_matches[0][0]>=version: raise ValueError('C26 post-checkpoint v2 receipt differs')
   prior=validate(prior_matches[0],seen+(receipt_digest,))
   if receipt.get('priorPostCheckpointToolingVerificationHead')!=prior.get('postCheckpointToolingVerificationHead') or receipt.get('directParentHead')!=prior.get('postCheckpointToolingVerificationHead'): raise ValueError('C26 post-checkpoint supersession differs')
  return receipt
 matches=by_digest.get(digest,[])
 if len(matches)!=1: raise ValueError('C26 post-checkpoint receipt differs')
 receipt=validate(matches[0])
 if receipt.get('postCheckpointToolingVerificationHead')!=post_head or receipt.get('postCheckpointToolingVerificationTree')!=post_tree: raise ValueError('C26 post-checkpoint tuple receipt differs')
def authority():
 coord=coordination_root()
 if coord:
  context_path=f'contexts/{CARD}-attempt-1/BootstrapCardContextV1.json'; fence_path=f'contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json'; correction_path=f'receipts/{CARD}-hydration-fence-correction-v2.json'; checkpoint_path=f'receipts/{CARD}-provisional-checkpoint.json'; verification_path=f'receipts/{CARD}-provisional-verification.json'
  head=_coord_git(coord,'rev-parse','HEAD'); tree=_coord_git(coord,'rev-parse','HEAD^{tree}')
  if _coord_git(coord,'rev-parse',HEAD+'^{tree}')!=CTREE or _coord_git(coord,'rev-parse',SEALED_HEAD+'^{tree}')!=SEALED_TREE or not _coord_is_ancestor(coord,HEAD,SEALED_HEAD) or not _coord_is_ancestor(coord,SEALED_HEAD,head): raise ValueError('C26 coordination lineage differs')
  if subprocess.run(['git','diff','--quiet'],cwd=coord).returncode or subprocess.run(['git','diff','--cached','--quiet'],cwd=coord).returncode: raise ValueError('C26 coordination worktree differs')
  for path,revision in ((context_path,HEAD),(fence_path,HEAD),(correction_path,HEAD),(checkpoint_path,SEALED_HEAD),(verification_path,SEALED_HEAD)):
   if _coord_blob(coord,revision,path)!=_coord_blob(coord,head,path): raise ValueError('C26 immutable authority blob differs: '+path)
  context=_coord_json(coord,HEAD,context_path); f=_coord_json(coord,HEAD,fence_path); correction=_coord_json(coord,HEAD,correction_path); checkpoint=_coord_json(coord,SEALED_HEAD,checkpoint_path); verification=_coord_json(coord,SEALED_HEAD,verification_path)
  if context.get('contextDigest')!=CONTEXT or context.get('pathFenceDigest')!=FENCE or context.get('ownerAuthorizedPathAllocationDigest')!=ALLOCATION or tuple(f.get('allowedCreateOrReplacePaths',()))!=PATH_FENCE or f.get('fenceDigest')!=FENCE or correction.get('receiptDigest')!=CORRECTION or correction.get('contextDigest')!=CONTEXT or correction.get('fenceDigest')!=FENCE or correction.get('allocationReceiptDigest')!=ALLOCATION: raise ValueError('C26 hydration authority differs')
  tuple_fields={'cardID':CARD,'acceptedCandidateHead':ACCEPTED,'acceptedCandidateTree':ACCEPTED_TREE,'checkpointDigest':CHECKPOINT,'verificationReceiptDigest':VERIFICATION}
  if any(checkpoint.get(key)!=value for key,value in tuple_fields.items()) or any(verification.get(key)!=value for key,value in {'cardID':CARD,'acceptedCandidateHead':ACCEPTED,'acceptedCandidateTree':ACCEPTED_TREE,'receiptDigest':VERIFICATION}.items()): raise ValueError('C26 sealed checkpoint differs')
  ledger=_coord_json(coord,head,'state/BootstrapExecutionLedgerEnvelopeV1.json'); projection=_coord_json(coord,head,'projections/ActiveWorkSetProjectionV1.json'); sealed_ledger=_coord_json(coord,SEALED_HEAD,'state/BootstrapExecutionLedgerEnvelopeV1.json'); sealed_projection=_coord_json(coord,SEALED_HEAD,'projections/ActiveWorkSetProjectionV1.json'); ledger_entry=_checkpointed_c26_entry(ledger.get('attempts',())); projection_entry=_checkpointed_c26_entry(projection.get('activeEntries',()))
  required={'cardID':CARD,'attemptID':1,'state':'CHECKPOINTED','acceptedCandidateHead':ACCEPTED,'acceptedCandidateTree':ACCEPTED_TREE,'contextDigest':CONTEXT,'pathFenceDigest':FENCE,'ownerAuthorizedPathAllocationDigest':ALLOCATION,'provisionalPrerequisiteDigest':PREREQ,'provisionalCheckpointDigest':CHECKPOINT,'provisionalVerificationDigest':VERIFICATION}
  if ledger_entry is None or any(ledger_entry.get(key)!=value for key,value in required.items()) or projection_entry is None or projection.get('ledgerDigest')!=ledger.get('ledgerDigest'): raise ValueError('C26 sealed ledger/projection differs')
  _post_checkpoint_tuple(coord,head,ledger_entry,projection_entry,_checkpointed_c26_entry(sealed_ledger.get('attempts',())),_checkpointed_c26_entry(sealed_projection.get('activeEntries',())))
  return f
 manifest=json.loads((ROOT/MANIFEST).read_bytes()); a=manifest['authority']; reserved=a['frozenS10ReservedPaths']
 if tuple(manifest['pathFence'])!=PATH_FENCE or a['frozenS10ReservedPathsSHA256']!=FROZEN_S10_SHA or sha((json.dumps(reserved,separators=(',',':'))+'\n').encode())!=FROZEN_S10_SHA or set(reserved)&set(PATH_FENCE): raise ValueError('C26 portable fence differs')
 return {'allowedCreateOrReplacePaths':list(PATH_FENCE),'activeS10ReservedPaths':reserved}
def sources(): return (CATALOG,*(x for x in PATH_FENCE if x not in OWNED))
def rows(): return ([{'path':x,'status':'SOURCE_PRESENT' if (ROOT/x).is_file() else 'SOURCE_MISSING','sha256':sha((ROOT/x).read_bytes()) if (ROOT/x).is_file() else None} for x in sources()],all((ROOT/x).is_file() for x in sources()))
def counts():
 f=authority(); allowed=set(f['allowedCreateOrReplacePaths'])
 def names(*args):
  return {x.replace('\\','/') for x in subprocess.run(['git',*args],cwd=ROOT,check=True,capture_output=True,text=True).stdout.splitlines() if x}
 changed=names('diff','--name-only',BASE,'HEAD')|names('diff','--name-only','HEAD')|names('diff','--cached','--name-only')|names('ls-files','--others','--exclude-standard')|OWNED
 return {'changedPathCount':len(changed&allowed),'missingPathCount':sum(not(ROOT/x).is_file() for x in allowed-OWNED),'unownedChangedPathCount':len(changed-allowed),'s10ReservationOverlapCount':len(allowed&set(f['activeS10ReservedPaths']))}
def _json_equal(left,right): return json.dumps(left,sort_keys=True,separators=(',',':'))==json.dumps(right,sort_keys=True,separators=(',',':'))
def _draft2020_errors(value,node,root,trail='$'):
 if '$ref' in node:
  ref=node['$ref']
  if not isinstance(ref,str) or not ref.startswith('#/$defs/') or ref.count('/')!=2 or ref.split('/')[-1] not in root.get('$defs',{}): return [trail+': unsupported ref']
  return _draft2020_errors(value,root['$defs'][ref.split('/')[-1]],root,trail)
 if 'oneOf' in node:
  choices=node['oneOf']; passed=[choice for choice in choices if not _draft2020_errors(value,choice,root,trail)]
  return [] if len(passed)==1 else [trail+': oneOf match count '+str(len(passed))]
 errors=[]; expected=node.get('type')
 type_ok={'object':isinstance(value,dict),'array':isinstance(value,list),'string':isinstance(value,str),'integer':isinstance(value,int) and not isinstance(value,bool),'boolean':isinstance(value,bool),'null':value is None}
 if expected is not None and (expected not in type_ok or not type_ok[expected]): return [trail+': expected '+str(expected)]
 if 'const' in node and not _json_equal(value,node['const']): errors.append(trail+': const differs')
 if 'enum' in node and not any(_json_equal(value,option) for option in node['enum']): errors.append(trail+': enum differs')
 if isinstance(value,dict):
  properties=node.get('properties',{}); missing=[key for key in node.get('required',[]) if key not in value]
  errors.extend(trail+'.'+key+': required' for key in missing)
  if node.get('additionalProperties') is False: errors.extend(trail+'.'+key+': additional property' for key in value if key not in properties)
  for key,child in properties.items():
   if key in value: errors.extend(_draft2020_errors(value[key],child,root,trail+'.'+key))
 if isinstance(value,list):
  if 'minItems' in node and len(value)<node['minItems']: errors.append(trail+': fewer than minItems')
  if 'maxItems' in node and len(value)>node['maxItems']: errors.append(trail+': more than maxItems')
  if node.get('uniqueItems') and len({_canonical(item) for item in value})!=len(value): errors.append(trail+': duplicate item')
  if 'items' in node:
   for index,item in enumerate(value): errors.extend(_draft2020_errors(item,node['items'],root,trail+'['+str(index)+']'))
 if isinstance(value,str):
  if 'minLength' in node and len(value)<node['minLength']: errors.append(trail+': shorter than minLength')
  if 'maxLength' in node and len(value)>node['maxLength']: errors.append(trail+': longer than maxLength')
  if 'pattern' in node and re.search(node['pattern'],value) is None: errors.append(trail+': pattern differs')
 if isinstance(value,int) and not isinstance(value,bool):
  if 'minimum' in node and value<node['minimum']: errors.append(trail+': below minimum')
  if 'maximum' in node and value>node['maximum']: errors.append(trail+': above maximum')
 return errors
def _canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'))
def _optional_jsonschema_cross_check(schema,value):
 try:
  from jsonschema import Draft202012Validator
 except ImportError: return
 Draft202012Validator.check_schema(schema)
 if list(Draft202012Validator(schema).iter_errors(value)): raise ValueError('C26 optional Draft 2020-12 cross-check differs')
def _validate_checked_in_schema(schema,value):
 errors=_draft2020_errors(value,schema,schema)
 if errors: return errors
 _optional_jsonschema_cross_check(schema,value); return []
def validate_source_contracts(_=None):
 schema=json.loads((ROOT/SCHEMA).read_bytes())
 if schema.get('$schema')!='https://json-schema.org/draft/2020-12/schema': raise ValueError('C26 schema draft differs')
 if sha((ROOT/CATALOG).read_bytes())!=CATALOG_SHA: raise ValueError('C26 catalog binding differs')
 for path,digest in DECLARATIONS.items():
  value=json.loads((ROOT/path).read_bytes())
  if sha((ROOT/path).read_bytes())!=digest or set(value.get('forbiddenCapabilities',{}))!=set(FORBIDDEN) or any(value['forbiddenCapabilities'].values()) or value.get('publishEligibility') is not False: raise ValueError('C26 declaration validation differs: '+path)
  errors=_validate_checked_in_schema(schema,value)
  if errors: raise ValueError('C26 schema validation differs: '+path+': '+errors[0])
 meta=json.loads((ROOT/'docs/product/discovery/V23P04C26MetadataEvidenceReportV1.json').read_bytes())
 if meta.get('limits',{}).get('verifiedAt')!='2026-09-01T00:00:00Z': raise ValueError('C26 timestamp differs')
def source_contract_self_test():
 # The fallback evaluates the checked-in Draft 2020-12 contract itself, so
 # hostile variants remain independent from the declarations' source shape.
 import copy
 schema=json.loads((ROOT/SCHEMA).read_bytes())
 acquisition='docs/product/discovery/V23P04C26AcquisitionContentDraftV1.json'
 original=json.loads((ROOT/acquisition).read_bytes()); hostile=[]
 for label, mutate in (('extra-root-key',lambda x:x.__setitem__('unexpected',0)),('control-uploadReady-string',lambda x:x['control'].__setitem__('uploadReady','false'))):
  candidate=copy.deepcopy(original); mutate(candidate)
  if not _validate_checked_in_schema(schema,candidate): raise ValueError('C26 hostile accepted: '+label)
  hostile.append(label)
 metadata='docs/product/discovery/V23P04C26MetadataEvidenceReportV1.json'; candidate=json.loads((ROOT/metadata).read_bytes()); candidate['limits']['verifiedAt']='2026-01-01T00:00:00Z'
 if not _validate_checked_in_schema(schema,candidate): raise ValueError('C26 hostile accepted: limits-verifiedAt')
 hostile.append('limits-verifiedAt'); return {'result':'PASS','rejected':hostile,'count':len(hostile)}
def semantics(ready):
 if not ready: return
 validate_source_contracts(); source_contract_self_test()
 text='\n'.join((ROOT/path).read_text(encoding='utf-8',errors='replace') for path in sources())
 if any(x not in text for x in SELECTORS): raise ValueError('C26 selectors missing')
 if any(x in text for x in ('URLSession','URLRequest(','.dataTask(','.uploadTask(','DNSService','paidAcquisition(')): raise ValueError('C26 executable forbidden capability')
def protocol(): return {'protocol':'MANIFEST_LAST_ATOMIC_REPLACE','rows':[{'boundary':'BEFORE_ARTIFACTS','acceptedSetCount':0,'manifestLast':True,'temporaryRootMayContainIncompleteArtifacts':True,'retryAcceptedSetCount':1,'retryDeterministic':True,'realWorktreeUnchanged':True},{'boundary':'AFTER_ARTIFACTS_BEFORE_MANIFEST','acceptedSetCount':0,'manifestLast':True,'temporaryRootMayContainIncompleteArtifacts':True,'retryAcceptedSetCount':1,'retryDeterministic':True,'realWorktreeUnchanged':True},{'boundary':'AFTER_MANIFEST','acceptedSetCount':1,'manifestLast':True,'temporaryRootMayContainIncompleteArtifacts':False,'retryAcceptedSetCount':1,'retryDeterministic':True,'realWorktreeUnchanged':True}],'deterministicRerun':True,'realWorktreeUnchanged':True,'temporaryRootIncompleteStatePermitted':True}
def claim_authority_projection():
 acquisition=json.loads((ROOT/'docs/product/discovery/V23P04C26AcquisitionContentDraftV1.json').read_bytes()); rows=[]; coord=coordination_root()
 if coord is None:
  evidence=json.loads((ROOT/EVIDENCE).read_bytes()); manifest=json.loads((ROOT/MANIFEST).read_bytes()); rows=evidence.get('claimAuthorityProjection')
  if not isinstance(rows,list) or sha(pretty(rows))!=PROJECTION_SHA or manifest.get('claimAuthorityProjectionSHA256')!=PROJECTION_SHA: raise ValueError('C26 portable projection differs')
  bindings={x['claimID']:x['acceptanceBinding'] for x in acquisition['claims']}
  if len(rows)!=6 or set(x.get('claimID') for x in rows)!=set(bindings): raise ValueError('C26 portable projection coverage differs')
  for row in rows:
   b=bindings[row['claimID']]
   if any(row.get(k)!=b.get(k) for k in ('checkpointPath','checkpointSHA256','checkpointDigest','verificationPath','verificationSHA256','currentness','compatibilityDisposition','recoveryProof')) or row.get('cardID')!=next(x['acceptedFeatureCard'] for x in acquisition['claims'] if x['claimID']==row['claimID']) or 'receiptDigest' not in row: raise ValueError('C26 portable projection binding differs')
  return rows
 for claim in sorted(acquisition['claims'],key=lambda x:x['claimID']):
  b=claim['acceptanceBinding']; row={'claimID':claim['claimID'],'cardID':claim['acceptedFeatureCard'],'acceptedHead':b['acceptedCandidateHead'],'acceptedTree':b['acceptedCandidateTree'],'checkpointPath':b['checkpointPath'],'checkpointSHA256':b['checkpointSHA256'],'checkpointDigest':b['checkpointDigest'],'verificationPath':b['verificationPath'],'verificationSHA256':b['verificationSHA256'],'currentness':b['currentness'],'compatibilityDisposition':b['compatibilityDisposition'],'recoveryProof':b['recoveryProof']}
  if coord:
   if sha((coord/row['checkpointPath']).read_bytes())!=row['checkpointSHA256'] or sha((coord/row['verificationPath']).read_bytes())!=row['verificationSHA256']: raise ValueError('C26 claim projection hash differs')
   row['receiptDigest']=json.loads((coord/row['verificationPath']).read_bytes())['receiptDigest']
  rows.append(row)
 if len(rows)!=6 or len({x['claimID'] for x in rows})!=6: raise ValueError('C26 claim projection differs')
 return rows
def documents():
 d=_documents_without_projection(); projection=claim_authority_projection(); d[EVIDENCE]['claimAuthorityProjection']=projection; d[MANIFEST]['claimAuthorityProjectionSHA256']=sha(pretty(projection)); d[MANIFEST]['files']=[{'path':x,'sha256':sha(pretty(v))} for x,v in ((CONTRACT,d[CONTRACT]),(EVIDENCE,d[EVIDENCE]),(BRAND,d[BRAND]))]; return d
def _documents_without_projection():
 f=authority(); source_rows,ready=rows(); c=counts(); reserved=f['activeS10ReservedPaths']; a={'cardID':CARD,'appBaseHead':BASE,'appBaseTree':BTREE,'coordinationHead':HEAD,'coordinationTree':CTREE,'sequence':SEQ,'contextDigest':CONTEXT,'pathFenceDigest':FENCE,'allocationDigest':ALLOCATION,'prerequisiteDigest':PREREQ,'hydrationCorrectionReceiptDigest':CORRECTION,'readOnlyCatalogSHA256':CATALOG_SHA,'finalHashesSealed':False,'fencePathCount':16,'existingPathCount':2,'newPathCount':14,'priorFenceCount':2,'priorOwnedPathCount':45,'authorizedOverlapCount':2,'s10OverlapCount':0,'frozenS10ReservedPaths':reserved,'frozenS10ReservedPathsSHA256':sha((json.dumps(reserved,separators=(',',':'))+'\n').encode())}
 p={'sourceReady':ready,'sourceRows':source_rows,'counts':c,'selectors':list(SELECTORS)}; s={'persistentSchema':'V53','activeModelCount':168,'newDurableRecordCount':0,'newDurableFamilies':[],'publicationEligible':False,'statusFlags':FLAGS}; co={'schema':'V23P04C26OrganicFindabilityContractV1','schemaVersion':1,'cardID':CARD,'provisional':True,'authority':a,'semantics':s,'sourceProjection':p,'testSelectors':list(SELECTORS),'statusFlags':FLAGS}; ev={'schema':'V23P04C26OrganicFindabilityEvidenceReceiptV1','schemaVersion':1,'cardID':CARD,'provisional':True,'authority':a,'sourceProjection':p,'contractDigest':sha(pretty(co)),'generatorInterruptionProtocol':protocol(),'statusFlags':FLAGS}; br={'schema':'V23P04C26BrandImpactManifestV1','schemaVersion':1,'cardID':CARD,'provisional':True,'authority':a,'semantics':s,'sourceProjection':p,'uiAdoptionSkipped':True,'uiAcceptanceCredit':False,'statusFlags':FLAGS}; m={'schema':'V23P04C26ToolingManifestV1','schemaVersion':1,'cardID':CARD,'provisional':True,'finalHashesSealed':False,'authority':a,'pathFence':list(PATH_FENCE),'files':[{'path':x,'sha256':sha(pretty(v))} for x,v in ((CONTRACT,co),(EVIDENCE,ev),(BRAND,br))],'sources':source_rows,'counts':c,'toolingPaths':[ *SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST],'statusFlags':FLAGS}; return {CONTRACT:co,EVIDENCE:ev,BRAND:br,MANIFEST:m}
