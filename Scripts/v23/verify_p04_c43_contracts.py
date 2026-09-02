#!/usr/bin/env python3
"""Verify V23-P04-C43 tooling, shared source semantics, and exact fence."""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c43_contracts as c

def _block(text, declaration):
 m=re.search(declaration+r"[^\{]*\{",text)
 if not m:return ""
 depth=0
 for i in range(m.end()-1,len(text)):
  if text[i]=='{':depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0:return text[m.start():i+1]
 return ""

def _tokens(text, label, tokens, failures):
 for token in tokens:
  if token not in text:failures.append(f"{label} missing structural token: {token}")

def _validate_structural_source(failures):
 party=(ROOT/c.EXISTING_PATHS[0]).read_text(encoding='utf-8')
 writer=(ROOT/c.EXISTING_PATHS[3]).read_text(encoding='utf-8')
 domain=(ROOT/c.NEW_PRODUCT_PATHS[1]).read_text(encoding='utf-8')
 issue=(ROOT/c.EXISTING_PATHS[2]).read_text(encoding='utf-8')
 coordinator=(ROOT/c.NEW_PRODUCT_PATHS[0]).read_text(encoding='utf-8')
 view=(ROOT/c.NEW_PRODUCT_PATHS[2]).read_text(encoding='utf-8')
 tests=(ROOT/c.NEW_PRODUCT_PATHS[4]).read_text(encoding='utf-8')
 ui=(ROOT/c.NEW_PRODUCT_PATHS[5]).read_text(encoding='utf-8')
 # The writer boundary must recognize the reserved purpose and validate its fixed release.
 append_start=writer.find("case let .appendSignoff(value):")
 append_end=writer.find("\n        case ",append_start+1)
 append=writer[append_start:append_end if append_end >= 0 else len(writer)]
 _tokens(append,"writer C43 appendSignoff boundary",("C43SignoffEnrollmentBoundaryV1.isEnrollmentSnapshot(value)","C43SignoffEnrollmentBoundaryV1.validate(value)"),failures)
 _tokens(domain,"fixed C43 purpose/release",("WORK_DETAIL_COMPLETED_RESPONSE_V1","work-detail-completed-response.local-v1"),failures)
 # C43 has one adapter: preview creates appendSignoff and commit delegates its receipt-first helper.
 preview=_block(coordinator,r"func preview\(")
 commit=_block(coordinator,r"func commit\(")
 _tokens(preview,"C43 coordinator preview",(".appendSignoff(snapshot)","previewC43SignoffEnrollment","expectedRevision"),failures)
 _tokens(commit,"C43 coordinator commit",("commitC43SignoffEnrollment","partyReceipt"),failures)
 generic=_block(party,r"func commit\(")
 first_receipt=generic.find("writer.durableReceipt")
 execute=generic.find("writer.execute")
 if first_receipt < 0 or execute < 0 or first_receipt > execute:failures.append("generic party commit must lookup durableReceipt before writer execute")
 # Durable request/plan/receipt truth explicitly carries route and claim boundaries.
 request=_block(domain,r"struct SignoffEnrollmentRequestV1")
 plan=_block(domain,r"struct SignoffEnrollmentPlanV1")
 receipt=_block(domain,r"struct SignoffEnrollmentReceiptV1")
 route=_block(domain,r"struct SignoffEnrollmentRouteChainTruthV1")
 claims=_block(domain,r"struct SignoffEnrollmentProhibitedClaimFlagsV1")
 _tokens(request,"request",("manifest","typedName","claimedRole","claimedRelationship","expectedRevision","routeChain","drawnMark","mutationID"),failures)
 _tokens(plan,"plan",("manifest","routeChain","partyPlan","planSHA256",".appendSignoff(snapshot)"),failures)
 _tokens(receipt,"receipt",("partyReceipt","mutationID","receiptSHA256"),failures)
 _tokens(route,"route",("actionRoot = .work","editorDestination = .signoffEditor","historyDestination = .signoffHistory","requiresVisibleWorkRoot = true","directDeepLinkOnlyIsEligible = false"),failures)
 _tokens(claims,"prohibited claims",("disclaimsBehalfOfAnotherPerson","disclaimsLegalEffect","disclaimsVerifiedIdentity","disclaimsVerifiedAuthority","disclaimsLegalSignature","disclaimsNonrepudiation","disclaimsFinalApproval"),failures)
 # Only the transient view may have strokes; the durable plan/receipt must be presence-only.
 mark=_block(domain,r"enum SignoffEnrollmentDrawnMarkV1")
 _tokens(mark,"mark payload",("case presentNonBiometric",),failures)
 if len(re.findall(r"case\s+",mark))!=1:failures.append("mark payload must be presence-only")
 for label,block in (("durable plan",plan),("durable receipt",receipt)):
  if re.search(r"stroke|image|hash|biometric",block,re.I):failsafe=f"{label} contains forbidden mark material";failures.append(failsafe)
 # IssueDetail owns only a resolved-state optional More menu containing the action.
 resolved=_block(issue,r"if issue\.status == \.resolved,")
 _tokens(resolved,"IssueDetail resolved containment",("let recordApprovalResponse","Menu {","Button(\"Record response\", action: recordApprovalResponse)","Label(\"More\"","signoffMoreAccessibilityIdentifier","signoffRecordResponseAccessibilityIdentifier"),failures)
 # The contained view has exact action wording, closed IDs, typed fields, and optional-mark copy.
 _tokens(view,"SignoffEnrollmentView",("Text(\"Record approval response\")","Button(\"Record approval response\", action: submit)","typedNameAccessibilityIdentifier","claimedRoleAccessibilityIdentifier","claimedRelationshipAccessibilityIdentifier","drawnMarkAccessibilityIdentifier","Optional drawn mark","not biometric","markStrokes.isEmpty ? nil : .presentNonBiometric"),failures)
 # UI remains explicitly skipped pending post-S10 adoption; no live journey is claimed.
 _tokens(ui,"UI adoption boundary",("throw XCTSkip(","Pending post-S10 launch adoption","does not claim a live root or executed UI flow"),failures)
 # The test suite must pin the pre-C43 literal and hostile reserved-purpose collision.
 _tokens(tests,"frozen acknowledgement test",("frozenPreC43Bytes","JSONDecoder().decode(AcknowledgementSnapshotV1.self","JSONEncoder()","XCTAssertEqual(bytes, frozenPreC43Bytes)"),failures)
 _tokens(tests,"hostile reserved-purpose collision",("foreign-local-response-v1","WORK_DETAIL_COMPLETED_RESPONSE_V1","genericPlan","XCTAssertThrowsError(try bundle.party.commit(genericPlan))"),failures)
def main():
 p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();fails=[]
 try:expected=c.documents()
 except Exception as e:expected={};fails.append(f'authority:{e}')
 docs={}
 for path in (c.SCHEMA,c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
  try:docs[path]=c.read_json(path)
  except Exception as e:fails.append(f'artifact:{e}')
 for path,v in expected.items():
  if docs.get(path)!=v:fails.append(f'deterministic artifact differs: {path}')
 rows,ready=c.rows()
 if a.complete and not ready:fails.append('complete:missing C43 source paths')
 if ready:
  text='\n'.join((ROOT/x).read_text(encoding='utf-8') for x in (*c.EXISTING_PATHS,*c.NEW_PRODUCT_PATHS) if x.endswith('.swift'))
  normalized=re.sub(r'[^a-z0-9]+','',text.lower())
  for phrase in ('record approval response','work','completed','more','record response','history','acknowledgementsnapshotv1','mutationid','expectedrevision','receipt'):
   if re.sub(r'[^a-z0-9]+','',phrase.lower()) not in normalized:fails.append('source semantic missing: '+phrase)
  _validate_structural_source(fails)
 changed=set(c.git('diff','--name-only',c.BASE,'HEAD').splitlines())|set(c.git('diff','--name-only','HEAD').splitlines())|set(c.git('diff','--cached','--name-only').splitlines())|set(c.git('ls-files','--others','--exclude-standard').splitlines());changed.discard('')
 unowned=changed-set(c.PATH_FENCE)
 if unowned:fails.append('unowned changed paths: '+','.join(sorted(unowned)))
 counts={'changedPathCount':len(changed&set(c.PATH_FENCE)),'unownedChangedPathCount':len(unowned),'missingPathCount':sum(not(ROOT/x).is_file() for x in c.PATH_FENCE),'fencePathCount':18,'existingPathCount':4,'newPathCount':14,'productTestUIFixturePathCount':6,'toolingPathCount':8,'s10ReservedOverlapCount':1}
 result={'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL' if not fails else 'FAIL_STATIC','sourceReady':ready,'finalHashesSealed':False,'flagsAllFalse':all(v is False for v in c.FLAGS.values()),'failures':fails,'counts':counts,'selectors':list(c.SELECTORS),'authoritySequence':c.SEQUENCE,'sourceRows':rows}
 print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));return 0 if not fails else 1
if __name__=='__main__':raise SystemExit(main())
