from pathlib import Path
import hashlib,json,re
q=Path('.codex-temp/cold-ledger-continuation-successor-v1'); p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'; s=p.read_text(); chars=list(s)
# Lexical mask preserves positions and lines. It intentionally does not treat
# Swift string interpolation as callable source; explicit caveat is retained.
i=0
while i<len(s):
    end=None
    if s.startswith('//',i): end=s.find('\n',i); end=len(s) if end<0 else end
    elif s.startswith('/*',i):
        j=i+2; depth=1
        while j<len(s) and depth:
            if s.startswith('/*',j):depth+=1;j+=2
            elif s.startswith('*/',j):depth-=1;j+=2
            else:j+=1
        end=j
    elif s.startswith('"""',i):
        j=s.find('"""',i+3);end=len(s) if j<0 else j+3
    elif s[i]=='"':
        j=i+1
        while j<len(s):
            if s[j]=='\\':j+=2
            elif s[j]=='"':j+=1;break
            else:j+=1
        end=j
    if end is not None:
        for k in range(i,end):
            if chars[k]!='\n':chars[k]=' '
        i=end
    else:i+=1
m=''.join(chars); depths=[];d=0
for c in m:
    depths.append(d)
    if c=='{':d+=1
    elif c=='}':d-=1
assert d==0,d
start=m.index('final class ScratchDataLeaseStoreV1:'); opening=m.index('{',start); base=depths[opening]+1
closing=next(i for i in range(opening+1,len(m)) if m[i]=='}' and depths[i]==base)
line=lambda pos:s.count('\n',0,pos)+1
func=re.compile(r'(?m)^([ \t]*(?:(?:public|internal|private|fileprivate|final|static|class|nonisolated|override|convenience|required|mutating|@MainActor)\s+)*)(func\s+([A-Za-z0-9_]+)|init\b|deinit\b)')
items=[]
os=re.compile(r'\b(?:Darwin\.(?:fstat|fstatat|lstat|stat|open|openat|close|read|write|fsync|rewinddir|renameat|renameatx_np|unlinkat|linkat|mkdirat|dup)|flock|fdopendir|closedir|readdir|dirfd)\s*\(')
for hit in func.finditer(m,opening+1,closing):
    if depths[hit.start(2)]!=base:continue
    j=hit.end(); paren=0
    while j<closing:
        c=m[j]
        if c=='(':paren+=1
        elif c==')':paren-=1
        elif c=='{' and paren==0:break
        j+=1
    if j>=closing:continue
    end=next(k for k in range(j+1,closing+1) if m[k]=='}' and depths[k]==depths[j]+1)
    body=s[j+1:end]; masked=m[j+1:end]; prefix=body.strip()[:320]; matches=list(os.finditer(masked))
    if not matches and not re.search(r'\b(?:authority|directoryDescriptor|rootDescriptor|operationsDescriptor|originalEraseBorrowedExclusiveCheck)\b',masked):continue
    name=hit.group(3) or hit.group(2).split()[0]; static=bool(re.search(r'\bstatic\b',hit.group(1)))
    direct=prefix.startswith('try requireScratchDescriptorAccess()') or prefix.startswith('try self.requireScratchDescriptorAccess()')
    deferred=bool(re.match(r'\s*\[\.(?:plan|effect)\s*\{[^\n]*\n\s*try (?:self\.)?requireScratchDescriptorAccess\(\)',body))
    special=name=='originalEraseRequireFreshGenericBinding'
    dispatch=name=='requireScratchDescriptorAccess' and prefix.startswith('switch originalEraseBorrowedLifetime')
    io=name=='originalEraseBorrowedObservationIO' and prefix.startswith('let incomingErrno = errno\n        try requireScratchDescriptorAccess()')
    category='static factory/constructor: separate retained owner/permit audit required' if static or name=='init' else 'permanent memory fence first' if direct else 'first deferred shared-engine memory fence' if deferred else 'memory-only actor bridge guard before provider' if special else 'permanent memory latch switch before provider or descriptor' if dispatch else 'errno-only save then permanent memory fence before IO closure' if io else 'requires manual path classification'
    items.append({'name':name,'line':line(hit.start(2)),'endLine':line(end),'static':static,'category':category,'directOSLines':[line(j+1+x.start()) for x in matches],'prefix':prefix})
record={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','sourceSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'kind':'static lexical census only; no compilation/runtime/independent approval','classLines':[line(start),line(closing)],'methods':items,'unclassified':[x for x in items if x['category']=='requires manual path classification'],'limitations':['String interpolation bodies are masked; not semantic reachability proof','Nested owner types, PinnedScratchRoot, constructor Support-SH/EX and external typed terminal release need separate owner-path audit','Fresh provider wrapper is additive around main instance and nested PublicationSession observations/effects; opens/dup/close ownership order needs separate manual audit, not a wrapper shortcut','Generic policy bridge is implemented against required external scopes; actual complete directory source/initial classification/coupled binding and runtime remain due']}
f=q/'LEGACY_FD_PATH_CENSUS_WORKING_V28.json';f.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({'sourceSHA256':record['sourceSHA256'],'classLines':record['classLines'],'count':len(items),'unclassified':[(x['name'],x['line']) for x in record['unclassified']],'censusSHA256':hashlib.sha256(f.read_bytes()).hexdigest()},indent=2))
