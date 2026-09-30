from pathlib import Path
import hashlib,json
q=Path('.codex-temp/cold-ledger-continuation-successor-v1')
p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
s=p.read_text();before=hashlib.sha256(p.read_bytes()).hexdigest()
assert before=='fbb01e58432b4ce123c779213e2b1150dddf86360bc73f0086d710f7302d2b03',before
old='''                erase = .init(operationID: operationID, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                    targets: published, unpublishedTargets: try unfinished.map(makeUnpublishedIngressEraseTarget))
                try erase.validate()'''
new='''                if originalEraseBorrowedExclusiveCheck != nil,
                   let plan = originalEraseC16ReferencePlan {
                    // Dynamic bytes selected by the genuine producer are
                    // retained in the exact pending request before a partial
                    // effect. Replay consumes them instead of selecting a
                    // replacement date from a current target directory.
                    erase = try originalEraseC16FixedFreshEraseMarker(plan: plan)
                    guard erase.targets == published,
                          erase.unpublishedTargets.map(\\.preparation) == unfinished else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                } else {
                    erase = .init(operationID: operationID, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                        targets: published, unpublishedTargets: try unfinished.map(makeUnpublishedIngressEraseTarget))
                }
                try erase.validate()'''
assert s.count(old)==1;s=s.replace(old,new)
old='''            marker = .init(schemaVersion: 1, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                controlDevice: pinned.rootDevice, controlInode: pinned.rootInode, files: files)
            let data = try CompatibilityCanonicalV1.encode(marker)'''
new='''            if originalEraseBorrowedExclusiveCheck != nil,
               let plan = originalEraseC16ReferencePlan,
               let producerOrdinal = plan.steps.firstIndex(of: .eraseFinalControl),
               let retained = try originalEraseC16PendingProducerBytes(slot: .init(
                producerOrdinal: producerOrdinal, role: "scratchControlErase",
                path: "ProtectedIngressReceiptsV1/" + Self.controlEraseName)) {
                marker = try CompatibilityCanonicalV1.decode(C16ScratchControlEraseV1.self, from: retained)
                try marker.validate()
                guard marker.rootDevice == authority.rootDevice, marker.rootInode == authority.rootInode,
                      marker.controlDevice == pinned.rootDevice, marker.controlInode == pinned.rootInode,
                      marker.files == files,
                      try CompatibilityCanonicalV1.encode(marker) == retained else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else {
                marker = .init(schemaVersion: 1, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                    controlDevice: pinned.rootDevice, controlInode: pinned.rootInode, files: files)
            }
            let data = try CompatibilityCanonicalV1.encode(marker)'''
assert s.count(old)==1;s=s.replace(old,new)
p.write_text(s)
record={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':before,
 'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),
 'change':'Actual borrowed FreshE and scratch marker producers consume retained pending payload, matching fixed plan/real unaffected files; ordinary producers unchanged',
 'limitations':['Actual required Store pending slot callback/readback not implemented','No compile/runtime proof','Current capacity and complete generic directory lineage remain due']}
(q/'PENDING_PRODUCER_RECIPE_V25.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
