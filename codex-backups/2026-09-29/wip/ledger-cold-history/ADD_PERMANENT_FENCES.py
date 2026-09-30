from pathlib import Path
import re,json
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
a='    private var originalEraseBorrowedAdmitting = false\n'
s=s.replace(a,'''    private enum OriginalEraseBorrowedLifetimeV1 { case ordinary, active, closed, uncertain }
    private var originalEraseBorrowedLifetime: OriginalEraseBorrowedLifetimeV1 = .ordinary

    private func requireScratchDescriptorAccess() throws {
        switch originalEraseBorrowedLifetime {
        case .ordinary: return
        case .active:
            guard originalEraseBorrowedExclusiveCheck != nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        case .closed, .uncertain: throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

'''+a,1)
a='            store.originalEraseBorrowedOwnerCheck = { try permit.requireHeld() }\n'
s=s.replace(a,'            store.originalEraseBorrowedLifetime = .active\n'+a,1)
a='''            defer {
                store.originalEraseBorrowedExclusiveCheck = nil'''
s=s.replace(a,'''            defer {
                if store.originalEraseBorrowedLifetime == .active {
                    store.originalEraseBorrowedLifetime = .uncertain
                }
                store.originalEraseBorrowedExclusiveCheck = nil''',1)
a='''                try permit.requireHeld()
            } catch {
                store.ingressControlAuthority?'''
b='''                try permit.requireHeld()
                store.originalEraseBorrowedLifetime = .closed
            } catch {
                store.originalEraseBorrowedLifetime = .uncertain
                store.ingressControlAuthority?''';assert a in s;s=s.replace(a,b,1)
a='''        if let check = originalEraseBorrowedExclusiveCheck {
            return try Self.filesystemLock.withLock {
                try check()
                let result = try body()
                try check()
                return result
            }
        }
        let activity = try OwnedStorageProducerActivityV1.acquire('''
b='''        guard originalEraseBorrowedLifetime == .ordinary else {
            // Public legacy operations never become alternate EX writers.
            // The sole typed borrowed controller calls the shared primitives.
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let activity = try OwnedStorageProducerActivityV1.acquire(''';assert a in s;s=s.replace(a,b,1)
start=s.index('final class ScratchDataLeaseStoreV1:')
end=s.index('\nprotocol EncryptedPortableEnvelopeTerminalScratchV1',start) if '\nprotocol EncryptedPortableEnvelopeTerminalScratchV1' in s[start:] else s.index('\nfinal class EncryptedPortableEnvelopeProtectedFileScratchV1',start)
# One-indentation instance declarations are precisely this class's methods;
# nested session types use two indentations and get their store fence below.
pattern=re.compile(r'^    (?:@MainActor\s+)?(?:(?:private|fileprivate|internal|public|final|override|nonisolated)\s+)*(?P<static>static\s+)?func\s+(?P<name>\w+)',re.M)
items=[]
for m in pattern.finditer(s,start,end):
 if m.group('static') or m.group('name')=='requireScratchDescriptorAccess':continue
 # Walk balanced parameters; default closures inside the argument list are
 # not mistaken for the declaration's body.
 op=s.index('(',m.end()); depth=0; cp=None
 for j in range(op,len(s)):
  ch=s[j]
  if ch=='(':depth+=1
  elif ch==')':
   depth-=1
   if depth==0:cp=j;break
 if cp is None:raise RuntimeError(m.group('name'))
 brace=s.index('{',cp)
 header=s[cp:brace]
 if 'throws' not in header:continue
 items.append((brace+1,m.group('name')))
for pos,name in reversed(items):s=s[:pos]+'\n        try requireScratchDescriptorAccess()'+s[pos:]
# Session operations may retain old aliases after a failed lexical owner.
# They must ask only the Store's memory latch before any later inspection.
s=s.replace('''        func advance() throws -> Bool {
            guard currentStep == nil''','''        func advance() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            guard currentStep == nil''',1)
s=s.replace('''        func advanceFailureSettlement() throws -> Bool {
            if failurePublications == nil''','''        func advanceFailureSettlement() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            if failurePublications == nil''',1)
# Publication advance and failure settlement occur later in the same class.
pos=s.index('    private final class PublicationSessionV1')
tail=s[pos:]
tail=tail.replace('''        func advance() throws -> Bool {
''','''        func advance() throws -> Bool {
            try store.requireScratchDescriptorAccess()
''',1)
tail=tail.replace('''        func advanceFailureSettlement() throws -> Bool {
''','''        func advanceFailureSettlement() throws -> Bool {
            try store.requireScratchDescriptorAccess()
''',1)
s=s[:pos]+tail
p.write_text(s)
Path('.codex-temp/cold-ledger-continuation-successor-v1/MEMORY_FENCES_WORKING.json').write_text(json.dumps({'instance_throwing_methods':[name for _,name in items],'count':len(items),'status':'working census; terminal latch is permanent and separate from permit clearing'},indent=2)+'\n')
print('fenced',len(items))
