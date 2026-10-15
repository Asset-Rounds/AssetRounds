#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
def _c45_without_comments_and_literals(source):
 # Source-only inspection: strings/comments cannot supply a live timing guard.
 return re.sub(r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\])*"',
               lambda match: '\n' * match.group(0).count('\n'), source, flags=re.S)


def _c45_unique_braced_body(code, declaration):
 matches=list(re.finditer(declaration+r'\s*\{',code))
 if len(matches)!=1:return None
 start=matches[0].end();depth=1
 for index in range(start,len(code)):
  if code[index]=='{':depth+=1
  elif code[index]=='}':
   depth-=1
   if depth==0:return code[start:index]
 return None


def _c45_raw_awake_timing_failures(adapter):
 code=_c45_without_comments_and_literals(adapter);failures=[]
 compact=lambda value: re.sub(r'\s+','',value) if value is not None else None
 timing=_c45_unique_braced_body(code,r'\bstruct\s+VoiceCaptureElapsedTimingV1\s*:\s*Sendable')
 if timing is None:return ['adapter anti-clamp: unique private elapsed helper missing']
 if len(re.findall(r'\bprivate\s+let\s+startedAt\s*:\s*SuspendingClock\.Instant\b',timing))!=1:
  failures.append('adapter anti-clamp: private awake origin missing')
 constructor=_c45_unique_braced_body(timing,r'\binit\s*\(\s*startedAt\s*:\s*SuspendingClock\.Instant\s*\)')
 if compact(constructor)!='self.startedAt=startedAt':
  failures.append('adapter anti-clamp: elapsed helper origin binding differs')
 raw=_c45_unique_braced_body(timing,r'\bfunc\s+rawDuration\s*\(\s*at\s+instant\s*:\s*SuspendingClock\.Instant\s*=\s*\.now\s*\)\s*->\s*Duration')
 if compact(raw)!='max(.zero,startedAt.duration(to:instant))':
  failures.append('adapter anti-clamp: raw awake duration is not unrounded and unclamped')
 parameters=r'\(\s*maximumDurationSeconds\s*:\s*UInt64\s*,\s*at\s+instant\s*:\s*SuspendingClock\.Instant\s*=\s*\.now\s*\)'
 admission=_c45_unique_braced_body(timing,r'\bfunc\s+admitsFinalCallback\s*'+parameters+r'\s*->\s*Bool')
 if compact(admission)!='rawDuration(at:instant)<=.seconds(maximumDurationSeconds)':
  failures.append('adapter anti-clamp: final admission does not compare the raw awake duration')
 reporting=_c45_unique_braced_body(timing,r'\bfunc\s+reportedDurationSeconds\s*'+parameters+r'\s*->\s*UInt64')
 expected_reporting=('letbounded=min(rawDuration(at:instant),.seconds(maximumDurationSeconds))'
                     'letcomponents=bounded.components'
                     'returnUInt64(components.seconds)+(components.attoseconds>0?1:0)')
 if compact(reporting)!=expected_reporting:
  failures.append('adapter anti-clamp: reporting ceiling and clamp differ')
 if re.search(r'\b(systemEpoch|unsafeBitCast|Mirror|JSONEncoder|JSONDecoder)\b',timing):
  failures.append('adapter anti-clamp: private instant exposure in elapsed helper')
 active=_c45_unique_braced_body(code,r'\bprivate\s+final\s+class\s+ActiveCapture')
 if active is None or len(re.findall(r'\blet\s+elapsedTiming\s*:\s*VoiceCaptureElapsedTimingV1\b',active))!=1 or compact(active).count('self.elapsedTiming=elapsedTiming')!=1:
  failures.append('adapter anti-clamp: active capture does not retain its elapsed origin')
 begin=_c45_unique_braced_body(code,r'\bfunc\s+beginPushToTalkCapture\s*\([^{}]*\)\s*async\s*throws')
 origin=('letsession=ActiveCapture(context:context,recognizer:recognizer,request:request,'
         'audioEngine:AVAudioEngine(),elapsedTiming:VoiceCaptureElapsedTimingV1(startedAt:.now))')
 begin_code=compact(begin) or ''
 if begin_code.count(origin)!=1 or 'tryaudioSession.setCategory(' not in begin_code or begin_code.index(origin)>begin_code.index('tryaudioSession.setCategory('):
  failures.append('adapter anti-clamp: elapsed origin is not bound before audio setup')
 callback=_c45_unique_braced_body(code,r'\bprivate\s+func\s+handleRecognitionCallback\s*\([^{}]*\)')
 final_body=_c45_unique_braced_body(callback or '',r'\bif\s+result\.isFinal\s*\{\s*do')
 guard=('guardsession.elapsedTiming.admitsFinalCallback(maximumDurationSeconds:contextMaximumSeconds(session)),'
        'transcript.utf8.count<=VoiceStructuringLimitsV1.maximumTranscriptUTF8Byteselse{'
        'throwVoiceCaptureFailureV1.captureRejected}')
 final_code=compact(final_body) or ''
 if not final_code.startswith(guard) or final_code.count('finishFinal(session,captured:captured)')!=1:
  failures.append('adapter anti-clamp: actual final callback is not fenced by the raw duration guard')
 reporter=_c45_unique_braced_body(code,r'\bprivate\s+func\s+reportedElapsedSeconds\s*\(\s*for\s+session\s*:\s*ActiveCapture\s*\)\s*->\s*UInt64')
 if compact(reporter)!='session.elapsedTiming.reportedDurationSeconds(maximumDurationSeconds:contextMaximumSeconds(session))':
  failures.append('adapter anti-clamp: displayed elapsed duration is not separately reported')
 maximum=_c45_unique_braced_body(code,r'\bprivate\s+func\s+contextMaximumSeconds\s*\(\s*_\s+session\s*:\s*ActiveCapture\s*\)\s*->\s*UInt64')
 if compact(maximum)!='session.context.maximumDurationSeconds':
  failures.append('adapter anti-clamp: fixed context maximum binding differs')
 return failures


sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c45_contracts as c
p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();fails=[]
try:expected=c.documents()
except Exception as e:expected={};fails.append('authority:'+str(e))
for path,v in expected.items():
 try:
  if c.read_json(path)!=v:fails.append('artifact drift: '+path)
 except Exception as e:fails.append('artifact:'+str(e))
rows,ready=c.rows()
if a.complete and not ready:fails.append('complete:missing C45 source paths')
if ready:
 plist=(ROOT/c.EXISTING_PATHS[0]).read_text(encoding='utf-8');domain=(ROOT/c.NEW_PRODUCT_PATHS[0]).read_text(encoding='utf-8');coordinator=(ROOT/c.NEW_PRODUCT_PATHS[1]).read_text(encoding='utf-8');adapter=(ROOT/c.NEW_PRODUCT_PATHS[2]).read_text(encoding='utf-8');view=(ROOT/c.NEW_PRODUCT_PATHS[3]).read_text(encoding='utf-8');tests=(ROOT/c.NEW_PRODUCT_PATHS[4]).read_text(encoding='utf-8');ui=(ROOT/c.NEW_PRODUCT_PATHS[6]).read_text(encoding='utf-8')
 texts=[plist,domain,coordinator,adapter,view,tests,ui]
 joined='\n'.join(texts)
 for token in ('StructuredVoiceCaptureContextV1','VoiceScratchDispositionV1','Speech','AVFoundation','60','push','on-device','transcript','confidence','accept','edit','reject','manual','callback','revision','cleanup','NONPERSISTENT'):
  if token.lower() not in joined.lower():fails.append('source token missing: '+token)
 # Exact platform disclosure keys are required and their values cannot be blank.
 for key in ('NSMicrophoneUsageDescription','NSSpeechRecognitionUsageDescription'):
  m=re.search(r'<key>'+key+r'</key>\s*<string>(.*?)</string>',plist,re.S);
  if not m or not m.group(1).strip():fails.append('Info.plist missing nonempty '+key)
 # Adapter checks use code with comments stripped, so policy prose cannot trigger negatives.
 code=re.sub(r'//[^\n]*|/\*.*?\*/','',adapter,flags=re.S)
 for token in ('import Speech','import AVFoundation','requiresOnDeviceRecognition = true','contextMaximumSeconds','callbackSequence','interruptionNotification','didEnterBackgroundNotification','cancelPushToTalkCapture'):
  if token not in code:fails.append('adapter structural token missing: '+token)
 # Raw elapsed time is the admission value; the reported value is display-only
 # and must never let a clamped UI duration bypass the fixed capture ceiling.
 fails.extend(_c45_raw_awake_timing_failures(adapter))
 for token in ('URLSession','URLRequest','NWConnection','WebSocket','FileHandle','AVAudioFile','CloudKit'):
  if re.search(r'\b'+re.escape(token)+r'\b',code):fails.append('adapter forbidden symbol: '+token)
 for token in ('StructuredVoiceCaptureContextV1','VoiceScratchDispositionV1'):
  if token not in domain:fails.append('domain ref missing: '+token)
 for token in ('preservingSource','retryableCleanup','cleanupPending','VoicePushToTalkReviewingV1'):
  if token not in coordinator:fails.append('coordinator structural token missing: '+token)
 for token in ('terminalCancellationPending','retryTerminalCancellation','preservingSource'):
  if token.lower() not in coordinator.lower():fails.append('coordinator terminal cancellation token missing: '+token)
 for token in ('presentationInFlight','deferredTerminal','finishDeferredTerminal','recoverAfterPresentationFenceMismatch','presentationInFlight = false'):
  if token not in coordinator:fails.append('coordinator presentation recovery token missing: '+token)
 coordinator_code=re.sub(r'//[^\n]*|/\*.*?\*/','',coordinator,flags=re.S)
 for token in ('WorkspaceWriter','ModelContext','StoreGeneration','writer.execute'):
  if token in coordinator_code:fails.append('coordinator forbidden persistence call: '+token)
 for token in ('v23.p04.c45.','Accept','Edit','Reject','manualEntryFieldAccessibilityIdentifier','static let'):
  if token not in view:fails.append('view structural token missing: '+token)
 for token in ('V23P04C45G01','V23P04C45A01','V23P04C45H01','V23P04C45I01','V23P04C45R01','C45Capture','C45Scratch','C45Review'):
  if token not in tests:fails.append('test structural token missing: '+token)
 for token in ('terminalCancellationPending','retryTerminalCancellation','cancelFailures'):
  if token not in tests:fails.append('test cancellation-recovery token missing: '+token)
 for token in ('suspendPresent','presentInFlight','presentationTerminalPending','must not return proposal'):
  if token.lower() not in tests.lower():fails.append('test presentation-recovery token missing: '+token)
 if 'VoiceScratchDispositionV1.completed' in view or 'case completed' in domain:fails.append('obsolete VoiceScratchDispositionV1.completed remains')
 if 'throw XCTSkip(' not in ui:fails.append('UI must explicitly XCTSkip deferred adoption')
changed=set(c.git('diff','--name-only',c.BASE,'HEAD').splitlines())|set(c.git('diff','--name-only','HEAD').splitlines())|set(c.git('diff','--cached','--name-only').splitlines())|set(c.git('ls-files','--others','--exclude-standard').splitlines());changed.discard('');unowned=changed-set(c.PATH_FENCE)
if unowned:fails.append('unowned changed paths: '+','.join(sorted(unowned)))
counts={'changedPathCount':len(changed&set(c.PATH_FENCE)),'unownedChangedPathCount':len(unowned),'missingPathCount':sum(not(ROOT/x).is_file() for x in c.PATH_FENCE),'fencePathCount':16,'existingPathCount':1,'newPathCount':15,'toolingPathCount':8,'s10ReservationOverlapCount':0};result={'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL' if not fails else 'FAIL_STATIC','sourceReady':ready,'flagsAllFalse':all(v is False for v in c.FLAGS.values()),'failures':fails,'counts':counts,'selectors':list(c.SELECTORS),'authoritySequence':c.SEQUENCE,'sourceRows':rows};print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));raise SystemExit(0 if not fails else 1)
