#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
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
 for token in ('rawElapsedSeconds','rawDurationSeconds','reportedElapsedSeconds','rawDurationSeconds <= Double(contextMaximumSeconds(session))'):
  if token not in code:fails.append('adapter anti-clamp token missing: '+token)
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
