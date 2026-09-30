from pathlib import Path
import hashlib,json,re
q=Path('.codex-temp/cold-ledger-continuation-successor-v1');p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift';b=p.read_bytes();before='7fa795fdf82883518694eefb096e4274c0570047d603aeffb2cbb2d4146b9e1c';assert hashlib.sha256(b).hexdigest()==before;s=b.decode()
# Lexical masking shared with the read-only census; strings/comments cannot
# be rewritten as calls. Parentheses within real arguments remain exact.
chars=list(s);i=0
while i<len(s):
 end=None
 if s.startswith('//',i):end=s.find('\n',i);end=len(s) if end<0 else end
 elif s.startswith('/*',i):
  j=i+2;depth=1
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
m=''.join(chars);depths=[];d=0
for c in m:
 depths.append(d)
 if c=='{':d+=1
 elif c=='}':d-=1
assert d==0
start=m.index('final class ScratchDataLeaseStoreV1:');opening=m.index('{',start);base=depths[opening]+1;closing=next(i for i in range(opening+1,len(m)) if m[i]=='}' and depths[i]==base)
func=re.compile(r'(?m)^([ \t]*(?:(?:public|internal|private|fileprivate|final|static|class|nonisolated|override|convenience|required|mutating|@MainActor)\s+)*)(func\s+([A-Za-z0-9_]+)|init\b|deinit\b)')
call=re.compile(r'\b(?:Darwin\.(?:write|fsync|renameat|renameatx_np|unlinkat|linkat|mkdirat)|flock|readdir|dirfd)\s*\(')
replacements=[];ledger=[]
for hit in func.finditer(m,opening+1,closing):
 if depths[hit.start(2)]!=base or re.search(r'\bstatic\b',hit.group(1)) or not hit.group(3):continue
 j=hit.end();par=0
 while j<closing:
  c=m[j]
  if c=='(':par+=1
  elif c==')':par-=1
  elif c=='{' and par==0:break
  j+=1
 if j>=closing:continue
 end=next(k for k in range(j+1,closing+1) if m[k]=='}' and depths[k]==depths[j]+1)
 name=hit.group(3);body=s[j+1:end];prefix=body.strip()[:120]
 direct=prefix.startswith('try requireScratchDescriptorAccess()') or prefix.startswith('try self.requireScratchDescriptorAccess()')
 deferred=bool(re.match(r'\s*\[\.(?:plan|effect)\s*\{[^\n]*\n\s*try (?:self\.)?requireScratchDescriptorAccess\(\)',body))
 if not(direct or deferred):continue
 for h in call.finditer(m,j+1,end):
  a=h.start();o=m.index('(',a);k=o+1;par=1
  while par:
   if m[k]=='(':par+=1
   elif m[k]==')':par-=1
   k+=1
  replacements.append((a,k,'try self.originalEraseBorrowedObservationIO { '+s[a:k]+' }'))
  ledger.append({'method':name,'lineBefore':s.count('\n',0,a)+1,'call':h.group().strip(' (')})
for a,b,new in sorted(replacements,reverse=True):s=s[:a]+new+s[b:]
p.write_text(s);r={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':before,'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'kind':'Fresh actual provider before/after owned effect and directory read IO; unchanged semantic effect checks and actual errno preserved','wrappedCalls':ledger,'count':len(ledger),'exclusions':['open/openat/dup before descriptor ownership retained require separate exact attempt admission','checked close/closedir terminal paths keep owner fencing and receipts; no descriptor-access wrapper after terminal','static constructors and nested owner types remain separately audited'],'status':'INTERMEDIATE NONINSTALLABLE; parse/typecheck/review/runtime due'};(q/'FRESH_RAW_EFFECTS_V18.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='wrappedCalls'},indent=2))
