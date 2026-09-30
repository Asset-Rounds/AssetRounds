from pathlib import Path
p=Path('.codex-temp/cold-physical-continuation-successor-v5/candidate/FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift')
s=p.read_text()
# Private observation retains original sealed DATA and current metadata relation.
s=s.replace('''        let genericMetadata: OriginalEraseOwnedScratchMetadataV1?
        fileprivate init''','''        let genericMetadata: OriginalEraseOwnedScratchMetadataV1?
        let sealedOriginalAccountingRow: OriginalEraseAuxiliaryPairAccountingDataV1.Row?
        let sealedMetadataRelation: OriginalEraseSealedScratchMetadataRelationV1?
        fileprivate init''',1)
s=s.replace('''            genericMetadata: OriginalEraseOwnedScratchMetadataV1?) {
            self.treeRelative''','''            genericMetadata: OriginalEraseOwnedScratchMetadataV1?,
            sealedOriginalAccountingRow: OriginalEraseAuxiliaryPairAccountingDataV1.Row?,
            sealedMetadataRelation: OriginalEraseSealedScratchMetadataRelationV1?) {
            self.treeRelative''',1)
s=s.replace('''            self.policyObservations = policyObservations; self.genericMetadata = genericMetadata
        }
    }
    struct Schema2ColdReadWork''','''            self.policyObservations = policyObservations; self.genericMetadata = genericMetadata
            self.sealedOriginalAccountingRow = sealedOriginalAccountingRow
            self.sealedMetadataRelation = sealedMetadataRelation
        }
    }
    struct Schema2ColdReadWork''',1)
s=s.replace('''            let firstCaptureRole: OriginalEraseC16FirstCapturePathRoleV1?
            init''','''            let firstCaptureRole: OriginalEraseC16FirstCapturePathRoleV1?
            let sealedGenericRole: OriginalEraseSealedGenericPathRoleV1?
            init''',1)
s=s.replace('''                firstCaptureRole: OriginalEraseC16FirstCapturePathRoleV1? = nil) {
''','''                firstCaptureRole: OriginalEraseC16FirstCapturePathRoleV1? = nil,
                sealedGenericRole: OriginalEraseSealedGenericPathRoleV1? = nil) {
''',1)
s=s.replace('''                self.policy = policy; self.publicationRole = publicationRole; self.firstCaptureRole = firstCaptureRole
''','''                self.policy = policy; self.publicationRole = publicationRole; self.firstCaptureRole = firstCaptureRole
                self.sealedGenericRole = sealedGenericRole
''',1)
s=s.replace('policy: node.policy, publicationRole: node.publicationRole, firstCaptureRole: node.firstCaptureRole)','policy: node.policy, publicationRole: node.publicationRole, firstCaptureRole: node.firstCaptureRole, sealedGenericRole: node.sealedGenericRole)',1)
a=s.index('    func schema2ColdCurrentOwnedTree(');b=s.index('\n    func postRetiredTree(',a);c=s[a:b]
c=c.replace('''        firstCaptureScope: OriginalEraseC16FirstCaptureObservationScopeV1? = nil,
        operationsRelativePrefix''','''        firstCaptureScope: OriginalEraseC16FirstCaptureObservationScopeV1? = nil,
        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil,
        operationsRelativePrefix''')
c=c.replace('''              ((scope == nil && initialScope == nil && firstCaptureScope == nil) == (operationsRelativePrefix == nil))''','''              firstCaptureScope == nil || genericScope == nil,
              ((scope == nil && initialScope == nil && firstCaptureScope == nil && genericScope == nil) == (operationsRelativePrefix == nil))''')
c=c.replace('''            let genericMetadata: OriginalEraseOwnedScratchMetadataV1?
        }''','''            let genericMetadata: OriginalEraseOwnedScratchMetadataV1?
            let sealedRow: OriginalEraseAuxiliaryPairAccountingDataV1.Row?
            let sealedRelation: OriginalEraseSealedScratchMetadataRelationV1?
        }''')
c=c.replace('try firstCaptureScope?.requireCurrentBinding() }','try firstCaptureScope?.requireCurrentBinding(); try genericScope?.requireCurrentBinding() }')
c=c.replace('firstCaptureScope?.poisonOnUncertainObservation(); poison()','firstCaptureScope?.poisonOnUncertainObservation(); genericScope?.poisonOnUncertainObservation(); poison()')
c=c.replace('''            metadata: OriginalEraseOwnedScratchMetadataV1? = nil) throws {''','''            metadata: OriginalEraseOwnedScratchMetadataV1? = nil,
            sealedRow: OriginalEraseAuxiliaryPairAccountingDataV1.Row? = nil,
            sealedRelation: OriginalEraseSealedScratchMetadataRelationV1? = nil) throws {''')
c=c.replace('''originKind: kind, originBinding: binding, policies: policies, genericMetadata: metadata)''','''originKind: kind, originBinding: binding, policies: policies, genericMetadata: metadata,
                sealedRow: sealedRow, sealedRelation: sealedRelation)''')
c=c.replace('''                    let observedPolicy: TemporalPolicyObservationV1?
                    if let captureRole {''','''                    let genericRole: OriginalEraseSealedGenericPathRoleV1?
                    if let rolePath, let genericScope {
                        genericRole = try genericScope.roleFor(path: rolePath, fullFact: fullFact(before), sha256: sha)
                    } else { genericRole = nil }
                    let observedPolicy: TemporalPolicyObservationV1?
                    if let genericRole, genericRole != .ordinary {
                        guard role == .ordinary, captureRole == nil, let genericScope else {
                            throw StoreGenerationFailure.dataPointerInvalid
                        }
                        switch genericRole {
                        case .ordinary: throw StoreGenerationFailure.dataPointerInvalid
                        case .observedOwnedGenericAliases(let pair):
                            guard before.st_nlink == 2, pair.members.count == 2,
                                  pair.members.contains(where: { $0.url == url }),
                                  pair.operationID == genericScope.operationID,
                                  pair.originBinding == genericScope.originBinding,
                                  pair.accountingSHA256 == genericScope.accountingSHA256,
                                  pair.sha256 == sha, pair.byteCount == Int64(before.st_size),
                                  pair.device == UInt64(before.st_dev), pair.inode == UInt64(before.st_ino) else {
                                throw StoreGenerationFailure.dataPointerInvalid
                            }
                            let reserved = try reservePairWork(pair.byteCount, .observedOwnedGenericAliases)
                            let values = try ProtectedFilePolicyV1.observeEraseObservedOwnedGenericAliasTemporalPairWithCheckedClose(
                                aliasURLs: pair.members.map(\\.url), scope: genericScope, retainUncertainDescriptor: retain)
                            try completedPairWork(reserved)
                            try recordPair(urls: pair.members.map(\\.url), facts: pair.members.map(\\.fullFact),
                                policies: values, sha: sha, bytes: pair.byteCount, before: before,
                                operationID: pair.operationID, kind: "sealedOwnedGeneric", binding: pair.originBinding,
                                sealedRow: pair.original, sealedRelation: pair.metadataRelation)
                            observedPolicy = values[0]
                        case .ownedGenericSingleSurvivor(let survivor):
                            guard before.st_nlink == 1, survivor.member.url == url,
                                  survivor.member.fullFact == fullFact(before), survivor.sha256 == sha,
                                  survivor.operationID == genericScope.operationID,
                                  survivor.originBinding == genericScope.originBinding,
                                  survivor.accountingSHA256 == genericScope.accountingSHA256,
                                  case .oneMemberConsumed(let fresh) = try genericScope.requireOwnedGenericEvolution(
                                    accountingRowIndex: survivor.original.index), fresh == survivor else {
                                throw StoreGenerationFailure.dataPointerInvalid
                            }
                            // The actual source/record scope proves its sole assigned
                            // loss; policy remains the strict one-link reader.
                            observedPolicy = try policy(url, before)
                        }
                    } else if let captureRole {''')
c=c.replace('''sha256: sha, policy: observedPolicy, publicationRole: role, firstCaptureRole: captureRole))''','''sha256: sha, policy: observedPolicy, publicationRole: role, firstCaptureRole: captureRole,
                        sealedGenericRole: genericRole))''')
c=c.replace('''policyObservations: pair.policies, genericMetadata: pair.genericMetadata))''','''policyObservations: pair.policies, genericMetadata: pair.genericMetadata,
                    sealedOriginalAccountingRow: pair.sealedRow, sealedMetadataRelation: pair.sealedRelation))''')
s=s[:a]+c+s[b:];p.write_text(s)
