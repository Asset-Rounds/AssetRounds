import Foundation

enum SurveyDefinitionScheduleBoundaryV1 { static let bindingRequiresExactRelease = true }

enum SurveyDefinitionFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, incompatibleVersion, invalidSuccessor
    case invalidTransition, stalePreview, hostileArchive, limitExceeded, wrongWorkspace
}

enum ActivityKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case inspection = "INSPECTION"
    case survey = "SURVEY"
    case preventiveMaintenance = "PREVENTIVE_MAINTENANCE"
    case repair = "REPAIR"
    case operationalRecheck = "OPERATIONAL_RECHECK"
}

enum ActivityCompletionSemanticV1: String, Codable, Hashable, Sendable {
    case criterionAssessment = "CRITERION_ASSESSMENT"
    case typedFactCollection = "TYPED_FACT_COLLECTION"
    case maintenanceWorkRecord = "MAINTENANCE_WORK_RECORD"
    case remedyWorkRecord = "REMEDY_WORK_RECORD"
    case subsequentOperationalObservation = "SUBSEQUENT_OPERATIONAL_OBSERVATION"
}

struct ActivityKindSemanticsV1: Codable, Equatable, Sendable {
    let kind: ActivityKindV1
    let completion: ActivityCompletionSemanticV1
    let mayClaimInspectionResult: Bool
    let mayClaimRepairPerformed: Bool
    let mayClaimReleaseToService: Bool

    init(kind: ActivityKindV1) {
        self.kind = kind
        switch kind {
        case .inspection: completion = .criterionAssessment; mayClaimInspectionResult = true; mayClaimRepairPerformed = false
        case .survey: completion = .typedFactCollection; mayClaimInspectionResult = false; mayClaimRepairPerformed = false
        case .preventiveMaintenance: completion = .maintenanceWorkRecord; mayClaimInspectionResult = false; mayClaimRepairPerformed = false
        case .repair: completion = .remedyWorkRecord; mayClaimInspectionResult = false; mayClaimRepairPerformed = true
        case .operationalRecheck: completion = .subsequentOperationalObservation; mayClaimInspectionResult = false; mayClaimRepairPerformed = false
        }
        mayClaimReleaseToService = false
    }
}

enum SurveyDefinitionLifecycleStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case draft = "DRAFT", published = "PUBLISHED", retired = "RETIRED"
}

enum SurveyDefinitionLifecycleActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case createDraft = "CREATE_DRAFT", reviseDraft = "REVISE_DRAFT", publish = "PUBLISH", retire = "RETIRE"
    case duplicateAsDraft = "DUPLICATE_AS_DRAFT", importAsDraft = "IMPORT_AS_DRAFT", adoptUpgradeAsDraft = "ADOPT_UPGRADE_AS_DRAFT"
}

enum SurveyFieldKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case instruction = "INSTRUCTION", shortText = "SHORT_TEXT", longText = "LONG_TEXT"
    case integer = "INTEGER", decimal = "DECIMAL", measurement = "MEASUREMENT"
    case booleanObservation = "BOOLEAN_OBSERVATION", singleChoice = "SINGLE_CHOICE", multipleChoice = "MULTIPLE_CHOICE"
    case date = "DATE", time = "TIME", subjectReference = "SUBJECT_REFERENCE", locator = "LOCATOR"
    case oneShotLocation = "ONE_SHOT_LOCATION", normalizedPlanPlacement = "NORMALIZED_PLAN_PLACEMENT"
    case evidenceRequest = "EVIDENCE_REQUEST", repeatableGroup = "REPEATABLE_GROUP"
    case attributedAcknowledgement = "ATTRIBUTED_ACKNOWLEDGEMENT"
}

enum SurveyBooleanObservationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case yes = "YES", no = "NO", unknown = "UNKNOWN", notObserved = "NOT_OBSERVED"
}

enum SurveyDefinitionLimitsV1 {
    static let maximumSections = 128, maximumFacts = 2_048, maximumChoices = 128
    static let maximumRules = 256, maximumExpressionDepth = 16, maximumRepeatCount = 128
    static let maximumAggregateExpressionNodes = 4_096
    static let maximumTextBytes = 4_096, maximumCanonicalBytes = 4_194_304
    static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    static func token(_ value: String, maximumBytes: Int = 256) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,58,95].contains($0)
        }
    }
    static func digest(_ value: String) -> Bool { KernelCanonicalHashV1.validSHA256(value) }
}

struct SurveyChoiceV1: Codable, Equatable, Hashable, Sendable {
    let choiceID: String, labelLocalizationKey: String, accessibilityLabelLocalizationKey: String
    func validate() throws { guard SurveyDefinitionLimitsV1.token(choiceID), SurveyDefinitionLimitsV1.token(labelLocalizationKey), SurveyDefinitionLimitsV1.token(accessibilityLabelLocalizationKey) else { throw SurveyDefinitionFailureV1.invalidValue } }
}

struct SurveyVisibilityPredicateV1: Codable, Equatable, Hashable, Sendable {
    let factID: String
    let expectedValue: ResponseValueV1
    func validate() throws { guard SurveyDefinitionLimitsV1.token(factID) else { throw SurveyDefinitionFailureV1.invalidValue }; try expectedValue.validate() }
}

indirect enum SurveyVisibilityExpressionV1: Codable, Equatable, Sendable {
    case predicate(SurveyVisibilityPredicateV1), all([Self]), any([Self]), not(Self)
    func validate(depth: Int = 1) throws {
        guard depth <= SurveyDefinitionLimitsV1.maximumExpressionDepth else { throw SurveyDefinitionFailureV1.limitExceeded }
        switch self { case .predicate(let p): try p.validate(); case .not(let v): try v.validate(depth: depth + 1); case .all(let v), .any(let v): guard !v.isEmpty, v.count <= SurveyDefinitionLimitsV1.maximumRules else { throw SurveyDefinitionFailureV1.limitExceeded }; try v.forEach { try $0.validate(depth: depth + 1) } }
    }
    var referencedFactIDs: [String] { switch self { case .predicate(let p): return [p.factID]; case .not(let v): return v.referencedFactIDs; case .all(let v), .any(let v): return v.flatMap(\.referencedFactIDs) } }
}

struct SurveyTextConstraintsV1: Codable, Equatable, Sendable { let maximumUTF8Bytes: Int; func validate() throws { guard (1...SurveyDefinitionLimitsV1.maximumTextBytes).contains(maximumUTF8Bytes) else { throw SurveyDefinitionFailureV1.limitExceeded } } }
struct SurveyNumericConstraintsV1: Codable, Equatable, Sendable { let minimum: ExactDecimalV1?, maximum: ExactDecimalV1?; func validate() throws { if let minimum, let maximum, try minimum.compared(to: maximum) == .orderedDescending { throw SurveyDefinitionFailureV1.invalidValue } } }
struct SurveyMeasurementConstraintsV1: Codable, Equatable, Sendable { let dimension: MeasurementDimensionV1; let allowedUnitIDs: [String]; let maximumPrecisionScale: Int; func validate() throws { guard !allowedUnitIDs.isEmpty, allowedUnitIDs == allowedUnitIDs.sorted(), Set(allowedUnitIDs).count == allowedUnitIDs.count, (0...ExactDecimalV1.maximumScale).contains(maximumPrecisionScale), try allowedUnitIDs.allSatisfy { try KernelUnitRegistryV1.definition(unitID: $0).dimension == dimension } else { throw SurveyDefinitionFailureV1.invalidValue } } }
struct SurveyEvidenceRequestV1: Codable, Equatable, Sendable { let purposeID: String; let minimumCount: Int; let maximumCount: Int; func validate() throws { guard SurveyDefinitionLimitsV1.token(purposeID), minimumCount >= 0, maximumCount >= minimumCount, maximumCount <= ResponseCardinalityV1.maximumResponses else { throw SurveyDefinitionFailureV1.invalidValue } } }
struct SurveyRepeatableGroupV1: Codable, Equatable, Sendable { let groupID: String; let childFactIDs: [String]; let minimum: Int; let maximum: Int; func validate() throws { guard SurveyDefinitionLimitsV1.token(groupID), !childFactIDs.isEmpty, childFactIDs == childFactIDs.sorted(), Set(childFactIDs).count == childFactIDs.count, childFactIDs.allSatisfy({ SurveyDefinitionLimitsV1.token($0) }), minimum >= 0, maximum >= Swift.max(1, minimum), maximum <= SurveyDefinitionLimitsV1.maximumRepeatCount else { throw SurveyDefinitionFailureV1.invalidValue } } }

enum SurveyFactPayloadV1: Codable, Equatable, Sendable {
    case instruction, shortText(SurveyTextConstraintsV1), longText(SurveyTextConstraintsV1)
    case integer(SurveyNumericConstraintsV1), decimal(SurveyNumericConstraintsV1), measurement(SurveyMeasurementConstraintsV1)
    case booleanObservation, singleChoice([SurveyChoiceV1]), multipleChoice(choices: [SurveyChoiceV1], minimum: Int, maximum: Int)
    case date, time, subjectReference([String]), locator([String]), oneShotLocation, normalizedPlanPlacement
    case evidenceRequest(SurveyEvidenceRequestV1), repeatableGroup(SurveyRepeatableGroupV1), attributedAcknowledgement(disclosureLocalizationKey: String)
    var kind: SurveyFieldKindV1 { switch self { case .instruction:return .instruction;case .shortText:return .shortText;case .longText:return .longText;case .integer:return .integer;case .decimal:return .decimal;case .measurement:return .measurement;case .booleanObservation:return .booleanObservation;case .singleChoice:return .singleChoice;case .multipleChoice:return .multipleChoice;case .date:return .date;case .time:return .time;case .subjectReference:return .subjectReference;case .locator:return .locator;case .oneShotLocation:return .oneShotLocation;case .normalizedPlanPlacement:return .normalizedPlanPlacement;case .evidenceRequest:return .evidenceRequest;case .repeatableGroup:return .repeatableGroup;case .attributedAcknowledgement:return .attributedAcknowledgement} }
    func validate() throws { switch self { case .instruction,.booleanObservation,.date,.time,.oneShotLocation,.normalizedPlanPlacement:break; case .shortText(let v),.longText(let v):try v.validate();case .integer(let v),.decimal(let v):try v.validate();case .measurement(let v):try v.validate();case .singleChoice(let v):try Self.choices(v);case .multipleChoice(let v,let minimum,let maximum):try Self.choices(v);guard minimum>=0,maximum>=Swift.max(1,minimum),maximum<=v.count else{throw SurveyDefinitionFailureV1.invalidValue};case .subjectReference(let v),.locator(let v):guard !v.isEmpty,v==v.sorted(),Set(v).count==v.count,v.allSatisfy({ SurveyDefinitionLimitsV1.token($0) })else{throw SurveyDefinitionFailureV1.invalidValue};case .evidenceRequest(let v):try v.validate();case .repeatableGroup(let v):try v.validate();case .attributedAcknowledgement(let key):guard SurveyDefinitionLimitsV1.token(key)else{throw SurveyDefinitionFailureV1.invalidValue}} }
    private static func choices(_ values:[SurveyChoiceV1])throws{guard !values.isEmpty,values.count<=SurveyDefinitionLimitsV1.maximumChoices,values.map(\.choiceID)==values.map(\.choiceID).sorted(),Set(values.map(\.choiceID)).count==values.count else{throw SurveyDefinitionFailureV1.invalidValue};try values.forEach{$0.validate()} }
}

struct FactDefinitionV1: Codable, Equatable, Sendable {
    let factID:String, labelLocalizationKey:String, accessibilityLabelLocalizationKey:String
    let helpLocalizationKey:String?, required:Bool, defaultValue:ResponseValueV1?, visibility:SurveyVisibilityExpressionV1?, payload:SurveyFactPayloadV1
    var kind:SurveyFieldKindV1{payload.kind}
    func validate()throws{guard SurveyDefinitionLimitsV1.token(factID),SurveyDefinitionLimitsV1.token(labelLocalizationKey),SurveyDefinitionLimitsV1.token(accessibilityLabelLocalizationKey),helpLocalizationKey.map({ SurveyDefinitionLimitsV1.token($0) }) ?? true else{throw SurveyDefinitionFailureV1.invalidValue};try payload.validate();try defaultValue?.validate();try visibility?.validate();if payload.kind == .instruction && (required || defaultValue != nil){throw SurveyDefinitionFailureV1.invalidValue}}
}

struct SurveySectionV1:Codable,Equatable,Sendable{let sectionID,titleLocalizationKey,accessibilityHeadingLocalizationKey:String;let ordinal:Int;let facts:[FactDefinitionV1];func validate()throws{guard SurveyDefinitionLimitsV1.token(sectionID),SurveyDefinitionLimitsV1.token(titleLocalizationKey),SurveyDefinitionLimitsV1.token(accessibilityHeadingLocalizationKey),ordinal>=0,!facts.isEmpty,facts.count<=SurveyDefinitionLimitsV1.maximumFacts,facts.map(\.factID)==facts.map(\.factID).sorted(),Set(facts.map(\.factID)).count==facts.count else{throw SurveyDefinitionFailureV1.invalidValue};try facts.forEach{$0.validate()}}}

indirect enum SurveyCompletionExpressionV1:Codable,Equatable,Sendable{case allRequiredVisibleFactsAnswered, factPresent(String), all([Self]), any([Self]);func validate(depth:Int=1)throws{guard depth<=SurveyDefinitionLimitsV1.maximumExpressionDepth else{throw SurveyDefinitionFailureV1.limitExceeded};switch self{case .allRequiredVisibleFactsAnswered:break;case .factPresent(let id):guard SurveyDefinitionLimitsV1.token(id)else{throw SurveyDefinitionFailureV1.invalidValue};case .all(let v),.any(let v):guard !v.isEmpty,v.count<=SurveyDefinitionLimitsV1.maximumRules else{throw SurveyDefinitionFailureV1.limitExceeded};try v.forEach{try $0.validate(depth:depth+1)}}};var referencedFactIDs:[String]{switch self{case .allRequiredVisibleFactsAnswered:return[];case .factPresent(let id):return[id];case .all(let v),.any(let v):return v.flatMap(\.referencedFactIDs)}}}
struct CompletionRuleV1:Codable,Equatable,Sendable{let ruleID:String;let expression:SurveyCompletionExpressionV1;let failureLocalizationKey:String;func validate()throws{guard SurveyDefinitionLimitsV1.token(ruleID),SurveyDefinitionLimitsV1.token(failureLocalizationKey)else{throw SurveyDefinitionFailureV1.invalidValue};try expression.validate()}}
struct ClaimsProfileV1:Codable,Equatable,Sendable{let profileID:String;let activityKind:ActivityKindV1;let allowedClaimKeys,forbiddenClaimKeys,limitationLocalizationKeys:[String];func validate()throws{let groups=[allowedClaimKeys,forbiddenClaimKeys,limitationLocalizationKeys];guard SurveyDefinitionLimitsV1.token(profileID),!Self.prohibitedVocabulary(profileID),groups.allSatisfy({$0==$0.sorted()&&Set($0).count==$0.count&&$0.allSatisfy({ SurveyDefinitionLimitsV1.token($0) })}),Set(allowedClaimKeys).isDisjoint(with:forbiddenClaimKeys),allowedClaimKeys.allSatisfy({!Self.prohibitedVocabulary($0)}),activityKind != .survey || allowedClaimKeys.isEmpty else{throw SurveyDefinitionFailureV1.invalidValue}}private static func prohibitedVocabulary(_ value:String)->Bool{let normalized=value.lowercased().replacingOccurrences(of:"_",with:" ").replacingOccurrences(of:"-",with:" ").replacingOccurrences(of:".",with:" "),prohibited=["certification","certified","compliance","compliant","approval","approved","pass","fail","training","trained","comprehension","legal signature","secure","verified"];return prohibited.contains(where:{normalized.contains($0)})}}
struct SurveyReportProjectionV1:Codable,Equatable,Sendable{let projectionID,projectionVersion,headingLocalizationKey,emptyValueLocalizationKey:String;let sectionIDs,includedFactIDs:[String];func validate()throws{guard [projectionID,projectionVersion,headingLocalizationKey,emptyValueLocalizationKey].allSatisfy({ SurveyDefinitionLimitsV1.token($0) }),sectionIDs==sectionIDs.sorted(),includedFactIDs==includedFactIDs.sorted(),Set(sectionIDs).count==sectionIDs.count,Set(includedFactIDs).count==includedFactIDs.count else{throw SurveyDefinitionFailureV1.invalidValue}}}

enum SurveyDefinitionStaticValidationV1 {
    static func validate(sections: [SurveySectionV1], completionRules: [CompletionRuleV1]) throws -> Bool {
        let sectionIDs = sections.map(\.sectionID)
        let ordinals = sections.map(\.ordinal).sorted()
        let ruleIDs = completionRules.map(\.ruleID)
        let facts = sections.sorted { $0.ordinal < $1.ordinal }.flatMap(\.facts)
        let factByID = Dictionary(uniqueKeysWithValues: facts.map { ($0.factID, $0) })
        let indexByID = Dictionary(uniqueKeysWithValues: facts.enumerated().map { ($0.element.factID, $0.offset) })
        let visibilityNodes = facts.reduce(0) { $0 + ($1.visibility.map(expressionNodeCount) ?? 0) }
        let completionNodes = completionRules.reduce(0) { $0 + completionNodeCount($1.expression) }
        guard Set(sectionIDs).count == sectionIDs.count,
              ordinals == Array(0..<sections.count),
              completionRules.count <= SurveyDefinitionLimitsV1.maximumRules,
              Set(ruleIDs).count == ruleIDs.count,
              visibilityNodes + completionNodes <= SurveyDefinitionLimitsV1.maximumAggregateExpressionNodes else {
            throw SurveyDefinitionFailureV1.limitExceeded
        }
        for (index, fact) in facts.enumerated() {
            if let defaultValue = fact.defaultValue {
                if case .triState(let state) = defaultValue,
                   state == .unknown || state == .notObserved {
                    throw SurveyDefinitionFailureV1.invalidValue
                }
                guard response(defaultValue, isCompatibleWith: fact) else {
                    throw SurveyDefinitionFailureV1.invalidValue
                }
            }
            guard let visibility = fact.visibility else { continue }
            guard try expressionCanBeTrue(visibility, before: index, factByID: factByID, indexByID: indexByID) else {
                throw SurveyDefinitionFailureV1.invalidValue
            }
            if fact.required {
                guard visibility.referencedFactIDs.allSatisfy({ (indexByID[$0] ?? Int.max) < index }) else {
                    throw SurveyDefinitionFailureV1.invalidValue
                }
            }
        }
        return true
    }

    private static func expressionNodeCount(_ value: SurveyVisibilityExpressionV1) -> Int {
        switch value { case .predicate: return 1; case .not(let child): return 1 + expressionNodeCount(child); case .all(let children),.any(let children): return 1 + children.reduce(0) { $0 + expressionNodeCount($1) } }
    }
    private static func completionNodeCount(_ value: SurveyCompletionExpressionV1) -> Int {
        switch value { case .allRequiredVisibleFactsAnswered,.factPresent: return 1; case .all(let children),.any(let children): return 1 + children.reduce(0) { $0 + completionNodeCount($1) } }
    }
    private struct VisibilityAlternativeV1 {
        var exact:[String:ResponseValueV1]=[:]
        var excluded:[String:[ResponseValueV1]]=[:]
        func merged(with other:Self)->Self? {
            var result=self
            for (factID,value) in other.exact {
                if let current=result.exact[factID],current != value{return nil}
                if result.excluded[factID]?.contains(value)==true{return nil}
                result.exact[factID]=value
            }
            for (factID,values) in other.excluded {
                if let current=result.exact[factID],values.contains(current){return nil}
                var merged=result.excluded[factID] ?? []
                for value in values where !merged.contains(value){merged.append(value)}
                result.excluded[factID]=merged
            }
            return result
        }
    }
    private static func expressionCanBeTrue(_ value:SurveyVisibilityExpressionV1,before index:Int,factByID:[String:FactDefinitionV1],indexByID:[String:Int])throws->Bool {
        guard expressionIsWellTyped(value,before:index,factByID:factByID,indexByID:indexByID) else{return false}
        return try alternatives(value,negated:false).isEmpty == false
    }
    private static func alternatives(_ value:SurveyVisibilityExpressionV1,negated:Bool)throws->[VisibilityAlternativeV1] {
        switch value {
        case .predicate(let predicate):
            if negated{return[.init(exact:[:],excluded:[predicate.factID:[predicate.expectedValue]])]}
            return[.init(exact:[predicate.factID:predicate.expectedValue],excluded:[:])]
        case .not(let child):return try alternatives(child,negated:!negated)
        case .all(let children):if negated{return try union(children,negated:true)};return try intersection(children,negated:false)
        case .any(let children):if negated{return try intersection(children,negated:true)};return try union(children,negated:false)
        }
    }
    private static func union(_ children:[SurveyVisibilityExpressionV1],negated:Bool)throws->[VisibilityAlternativeV1] {
        var result:[VisibilityAlternativeV1]=[]
        for child in children { result += try alternatives(child,negated:negated);if result.count>SurveyDefinitionLimitsV1.maximumAggregateExpressionNodes{throw SurveyDefinitionFailureV1.limitExceeded} }
        return result
    }
    private static func intersection(_ children:[SurveyVisibilityExpressionV1],negated:Bool)throws->[VisibilityAlternativeV1] {
        var result=[VisibilityAlternativeV1()]
        for child in children {
            let childAlternatives=try alternatives(child,negated:negated)
            var next:[VisibilityAlternativeV1]=[]
            for left in result { for right in childAlternatives { if let merged=left.merged(with:right){next.append(merged);if next.count>SurveyDefinitionLimitsV1.maximumAggregateExpressionNodes{throw SurveyDefinitionFailureV1.limitExceeded}} } }
            result=next
            if result.isEmpty{return[]}
        }
        return result
    }
    private static func expressionIsWellTyped(_ value:SurveyVisibilityExpressionV1,before index:Int,factByID:[String:FactDefinitionV1],indexByID:[String:Int])->Bool {
        switch value { case .predicate(let predicate):guard let source=factByID[predicate.factID],let sourceIndex=indexByID[predicate.factID],sourceIndex<index else{return false};return response(predicate.expectedValue,isCompatibleWith:source);case .not(let child):return expressionIsWellTyped(child,before:index,factByID:factByID,indexByID:indexByID);case .all(let children),.any(let children):return children.allSatisfy{expressionIsWellTyped($0,before:index,factByID:factByID,indexByID:indexByID)} }
    }
    static func response(_ value:ResponseValueV1,isCompatibleWith fact:FactDefinitionV1)->Bool {
        switch (fact.payload,value) {
        case (.shortText(let constraints),.text(let text)),(.longText(let constraints),.text(let text)):return text.utf8.count<=constraints.maximumUTF8Bytes
        case (.integer(let constraints),.integer(let integer)):guard let decimal=try? ExactDecimalV1(mantissa:integer,scale:0)else{return false};return numeric(decimal,satisfies:constraints)
        case (.decimal(let constraints),.decimal(let decimal)):return numeric(decimal,satisfies:constraints)
        case (.measurement(let constraints),.measurement(let measurement)):return measurement.dimension==constraints.dimension&&constraints.allowedUnitIDs.contains(measurement.enteredUnitID)&&measurement.precisionScale<=constraints.maximumPrecisionScale
        case (.booleanObservation,.triState),(.date,.localDate),(.time,.localTime),(.oneShotLocation,.contentReference),(.normalizedPlanPlacement,.contentReference),(.evidenceRequest,.contentReference),(.attributedAcknowledgement,.boolean):return true
        case (.subjectReference(let kinds),.entityReference(let reference)),(.locator(let kinds),.entityReference(let reference)):return kinds.contains(reference.entityKindID)
        case (.singleChoice(let choices),.singleOption(let value)):return choices.contains{$0.choiceID==value}
        case (.multipleChoice(let choices,let minimum,let maximum),.multipleOptions(let values)):let allowed=Set(choices.map(\.choiceID));return values.count>=minimum&&values.count<=maximum&&Set(values).count==values.count&&Set(values).isSubset(of:allowed)
        default:return false
        }
    }
    private static func numeric(_ value:ExactDecimalV1,satisfies constraints:SurveyNumericConstraintsV1)->Bool {
        if let minimum=constraints.minimum,(try? value.compared(to:minimum)) == .orderedAscending{return false}
        if let maximum=constraints.maximum,(try? value.compared(to:maximum)) == .orderedDescending{return false}
        return true
    }
}

struct SurveyDefinitionReleaseReferenceV1:Codable,Equatable,Hashable,Sendable{let releaseID,definitionID:UUID;let revision:UInt64;let releaseSHA256:String;init(_ value:SurveyDefinitionReleaseV1)throws{try value.validate();releaseID=value.releaseID;definitionID=value.definitionID;revision=value.revision;releaseSHA256=value.releaseSHA256}func validate()throws{guard releaseID != SurveyDefinitionLimitsV1.zero,definitionID != SurveyDefinitionLimitsV1.zero,revision>0,SurveyDefinitionLimitsV1.digest(releaseSHA256)else{throw SurveyDefinitionFailureV1.invalidValue}}}

struct SurveyDefinitionReleaseV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let definitionID:UUID;let activityKind:ActivityKindV1;let ownerPackageID:String;let sections:[SurveySectionV1];let completionRules:[CompletionRuleV1];let claimsProfile:ClaimsProfileV1;let reportProjection:SurveyReportProjectionV1;let localizationReleaseSHA256:String;let supersedesReleaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let authoredBy:ActorSnapshotV1;let authoredAt:Date;let releaseSHA256:String
    init(releaseID:UUID,workspaceID:WorkspaceID,definitionID:UUID,activityKind:ActivityKindV1,ownerPackageID:String,sections:[SurveySectionV1],completionRules:[CompletionRuleV1],claimsProfile:ClaimsProfileV1,reportProjection:SurveyReportProjectionV1,localizationReleaseSHA256:String,supersedesReleaseID:UUID?=nil,revision:UInt64,mutationID:MutationIDV1,authoredBy:ActorSnapshotV1,authoredAt:Date)throws{schemaVersion=Self.schemaVersion;self.releaseID=releaseID;self.workspaceID=workspaceID;self.definitionID=definitionID;self.activityKind=activityKind;self.ownerPackageID=ownerPackageID;self.sections=sections.sorted{$0.ordinal<$1.ordinal};self.completionRules=completionRules.sorted{$0.ruleID<$1.ruleID};self.claimsProfile=claimsProfile;self.reportProjection=reportProjection;self.localizationReleaseSHA256=localizationReleaseSHA256;self.supersedesReleaseID=supersedesReleaseID;self.revision=revision;self.mutationID=mutationID;self.authoredBy=authoredBy;self.authoredAt=authoredAt;releaseSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,releaseID:releaseID,workspaceID:workspaceID,definitionID:definitionID,activityKind:activityKind,ownerPackageID:ownerPackageID,sections:self.sections,completionRules:self.completionRules,claimsProfile:claimsProfile,reportProjection:reportProjection,localizationReleaseSHA256:localizationReleaseSHA256,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID,authoredBy:authoredBy,authoredAt:authoredAt));try validate()}
    func validate()throws{try authoredBy.validate();try sections.forEach{$0.validate()};try completionRules.forEach{$0.validate()};try claimsProfile.validate();try reportProjection.validate();let facts=sections.flatMap(\.facts),ids=Set(facts.map(\.factID)),refs=Set(facts.flatMap{$0.visibility?.referencedFactIDs ?? []}+completionRules.flatMap{$0.expression.referencedFactIDs});guard schemaVersion==Self.schemaVersion,releaseID != SurveyDefinitionLimitsV1.zero,definitionID != SurveyDefinitionLimitsV1.zero,SurveyDefinitionLimitsV1.token(ownerPackageID),!sections.isEmpty,sections.count<=SurveyDefinitionLimitsV1.maximumSections,facts.count<=SurveyDefinitionLimitsV1.maximumFacts,ids.count==facts.count,refs.isSubset(of:ids),try Self.visibilityGraphIsAcyclic(facts),try SurveyDefinitionStaticValidationV1.validate(sections:sections,completionRules:completionRules),claimsProfile.activityKind==activityKind,Set(reportProjection.sectionIDs).isSubset(of:Set(sections.map(\.sectionID))),Set(reportProjection.includedFactIDs).isSubset(of:ids),SurveyDefinitionLimitsV1.digest(localizationReleaseSHA256),revision>0,(supersedesReleaseID==nil)==(revision==1),supersedesReleaseID != releaseID,authoredBy.workspaceID==workspaceID,authoredAt.timeIntervalSinceReferenceDate.isFinite,releaseSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveyDefinitionFailureV1.invalidDigest}}
    private static func visibilityGraphIsAcyclic(_ facts:[FactDefinitionV1]) throws -> Bool { let graph=Dictionary(uniqueKeysWithValues:facts.map{($0.factID,$0.visibility?.referencedFactIDs ?? [])});var visiting=Set<String>(),visited=Set<String>();func visit(_ id:String)->Bool{if visiting.contains(id){return false};if visited.contains(id){return true};visiting.insert(id);for dependency in graph[id] ?? []{if !visit(dependency){return false}};visiting.remove(id);visited.insert(id);return true};return graph.keys.allSatisfy(visit) }
    func validateSuccessor(of old:Self)throws{try old.validate();try validate();guard releaseID != old.releaseID,supersedesReleaseID==old.releaseID,workspaceID==old.workspaceID,definitionID==old.definitionID,activityKind==old.activityKind,ownerPackageID==old.ownerPackageID,mutationID != old.mutationID,old.revision<UInt64.max,revision==old.revision+1 else{throw SurveyDefinitionFailureV1.invalidSuccessor}}
    func rebound(to workspaceID:WorkspaceID,actor:ActorSnapshotV1)throws->Self{try .init(releaseID:releaseID,workspaceID:workspaceID,definitionID:definitionID,activityKind:activityKind,ownerPackageID:ownerPackageID,sections:sections,completionRules:completionRules,claimsProfile:claimsProfile,reportProjection:reportProjection,localizationReleaseSHA256:localizationReleaseSHA256,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID,authoredBy:actor,authoredAt:authoredAt)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,releaseID:releaseID,workspaceID:workspaceID,definitionID:definitionID,activityKind:activityKind,ownerPackageID:ownerPackageID,sections:sections,completionRules:completionRules,claimsProfile:claimsProfile,reportProjection:reportProjection,localizationReleaseSHA256:localizationReleaseSHA256,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID,authoredBy:authoredBy,authoredAt:authoredAt)}
    private struct Basis:Codable{let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let definitionID:UUID;let activityKind:ActivityKindV1;let ownerPackageID:String;let sections:[SurveySectionV1];let completionRules:[CompletionRuleV1];let claimsProfile:ClaimsProfileV1;let reportProjection:SurveyReportProjectionV1;let localizationReleaseSHA256:String;let supersedesReleaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let authoredBy:ActorSnapshotV1;let authoredAt:Date}
}

struct SurveyDefinitionLifecycleEventV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let definitionID:UUID;let action:SurveyDefinitionLifecycleActionV1;let priorState:SurveyDefinitionLifecycleStateV1?;let resultingState:SurveyDefinitionLifecycleStateV1;let release:SurveyDefinitionReleaseReferenceV1;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let sourceDefinitionID,sourceReleaseID:UUID?;let sourceReleaseSHA256,sourceArchiveSHA256,semanticDiffSHA256:String?;let actor:ActorSnapshotV1;let recordedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,workspaceID:WorkspaceID,definitionID:UUID,action:SurveyDefinitionLifecycleActionV1,priorState:SurveyDefinitionLifecycleStateV1?,resultingState:SurveyDefinitionLifecycleStateV1,release:SurveyDefinitionReleaseReferenceV1,predecessorEventID:UUID?=nil,predecessorEventSHA256:String?=nil,sourceDefinitionID:UUID?=nil,sourceReleaseID:UUID?=nil,sourceReleaseSHA256:String?=nil,sourceArchiveSHA256:String?=nil,semanticDiffSHA256:String?=nil,actor:ActorSnapshotV1,recordedAt:Date,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;self.workspaceID=workspaceID;self.definitionID=definitionID;self.action=action;self.priorState=priorState;self.resultingState=resultingState;self.release=release;self.predecessorEventID=predecessorEventID;self.predecessorEventSHA256=predecessorEventSHA256;self.sourceDefinitionID=sourceDefinitionID;self.sourceReleaseID=sourceReleaseID;self.sourceReleaseSHA256=sourceReleaseSHA256;self.sourceArchiveSHA256=sourceArchiveSHA256;self.semanticDiffSHA256=semanticDiffSHA256;self.actor=actor;self.recordedAt=recordedAt;self.revision=revision;self.mutationID=mutationID;eventSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,eventID:eventID,workspaceID:workspaceID,definitionID:definitionID,action:action,priorState:priorState,resultingState:resultingState,release:release,predecessorEventID:predecessorEventID,predecessorEventSHA256:predecessorEventSHA256,sourceDefinitionID:sourceDefinitionID,sourceReleaseID:sourceReleaseID,sourceReleaseSHA256:sourceReleaseSHA256,sourceArchiveSHA256:sourceArchiveSHA256,semanticDiffSHA256:semanticDiffSHA256,actor:actor,recordedAt:recordedAt,revision:revision,mutationID:mutationID));try validateIntrinsic()}
    func validate(release value:SurveyDefinitionReleaseV1)throws{try validateIntrinsic();try value.validate();guard workspaceID==value.workspaceID,definitionID==value.definitionID,release==(try SurveyDefinitionReleaseReferenceV1(value))else{throw SurveyDefinitionFailureV1.invalidTransition}}
    func validateSuccessor(of old:Self,release value:SurveyDefinitionReleaseV1)throws{try old.validateIntrinsic();try validate(release:value);guard eventID != old.eventID,predecessorEventID==old.eventID,predecessorEventSHA256==old.eventSHA256,workspaceID==old.workspaceID,definitionID==old.definitionID,priorState==old.resultingState,mutationID != old.mutationID,old.revision<UInt64.max,revision==old.revision+1 else{throw SurveyDefinitionFailureV1.invalidSuccessor}}
    private func validateIntrinsic()throws{try release.validate();try actor.validate();let root=[SurveyDefinitionLifecycleActionV1.createDraft,.duplicateAsDraft,.importAsDraft].contains(action);let transitionOK:Bool;switch action{case .createDraft:transitionOK=priorState==nil&&resultingState == .draft&&sourceDefinitionID==nil&&sourceArchiveSHA256==nil;case .duplicateAsDraft:transitionOK=priorState==nil&&resultingState == .draft&&sourceDefinitionID != nil&&sourceReleaseID != nil&&sourceReleaseSHA256.map(SurveyDefinitionLimitsV1.digest)==true;case .importAsDraft:transitionOK=priorState==nil&&resultingState == .draft&&sourceArchiveSHA256.map(SurveyDefinitionLimitsV1.digest)==true;case .reviseDraft:transitionOK=priorState == .draft&&resultingState == .draft;case .adoptUpgradeAsDraft:transitionOK=priorState == .draft&&resultingState == .draft&&semanticDiffSHA256.map(SurveyDefinitionLimitsV1.digest)==true;case .publish:transitionOK=priorState == .draft&&resultingState == .published;case .retire:transitionOK=priorState == .published&&resultingState == .retired};guard schemaVersion==Self.schemaVersion,eventID != SurveyDefinitionLimitsV1.zero,definitionID != SurveyDefinitionLimitsV1.zero,release.definitionID==definitionID,revision>0,root == (revision==1&&predecessorEventID==nil&&predecessorEventSHA256==nil),!root == (revision>1&&predecessorEventID != nil&&predecessorEventSHA256.map(SurveyDefinitionLimitsV1.digest)==true),transitionOK,actor.workspaceID==workspaceID,recordedAt.timeIntervalSinceReferenceDate.isFinite,eventSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveyDefinitionFailureV1.invalidTransition}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,workspaceID:workspaceID,definitionID:definitionID,action:action,priorState:priorState,resultingState:resultingState,release:release,predecessorEventID:predecessorEventID,predecessorEventSHA256:predecessorEventSHA256,sourceDefinitionID:sourceDefinitionID,sourceReleaseID:sourceReleaseID,sourceReleaseSHA256:sourceReleaseSHA256,sourceArchiveSHA256:sourceArchiveSHA256,semanticDiffSHA256:semanticDiffSHA256,actor:actor,recordedAt:recordedAt,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let definitionID:UUID;let action:SurveyDefinitionLifecycleActionV1;let priorState:SurveyDefinitionLifecycleStateV1?;let resultingState:SurveyDefinitionLifecycleStateV1;let release:SurveyDefinitionReleaseReferenceV1;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let sourceDefinitionID,sourceReleaseID:UUID?;let sourceReleaseSHA256,sourceArchiveSHA256,semanticDiffSHA256:String?;let actor:ActorSnapshotV1;let recordedAt:Date;let revision:UInt64;let mutationID:MutationIDV1}
}

struct SurveyDefinitionIdentityV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let definitionID:UUID;let workspaceID:WorkspaceID;let activityKind:ActivityKindV1;let lifecycleState:SurveyDefinitionLifecycleStateV1;let currentRelease:SurveyDefinitionReleaseReferenceV1;let latestLifecycleEventID:UUID;let latestLifecycleEventSHA256:String;let createdBy:ActorSnapshotV1;let createdAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let identitySHA256:String
    init(definitionID:UUID,workspaceID:WorkspaceID,activityKind:ActivityKindV1,lifecycleState:SurveyDefinitionLifecycleStateV1,currentRelease:SurveyDefinitionReleaseReferenceV1,latestLifecycleEventID:UUID,latestLifecycleEventSHA256:String,createdBy:ActorSnapshotV1,createdAt:Date,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.definitionID=definitionID;self.workspaceID=workspaceID;self.activityKind=activityKind;self.lifecycleState=lifecycleState;self.currentRelease=currentRelease;self.latestLifecycleEventID=latestLifecycleEventID;self.latestLifecycleEventSHA256=latestLifecycleEventSHA256;self.createdBy=createdBy;self.createdAt=createdAt;self.revision=revision;self.mutationID=mutationID;identitySHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,definitionID:definitionID,workspaceID:workspaceID,activityKind:activityKind,lifecycleState:lifecycleState,currentRelease:currentRelease,latestLifecycleEventID:latestLifecycleEventID,latestLifecycleEventSHA256:latestLifecycleEventSHA256,createdBy:createdBy,createdAt:createdAt,revision:revision,mutationID:mutationID));try validateIntrinsic()}
    func validate(currentRelease value:SurveyDefinitionReleaseV1,event:SurveyDefinitionLifecycleEventV1)throws{try validateIntrinsic();try event.validate(release:value);guard definitionID==value.definitionID,workspaceID==value.workspaceID,activityKind==value.activityKind,currentRelease==(try SurveyDefinitionReleaseReferenceV1(value)),latestLifecycleEventID==event.eventID,latestLifecycleEventSHA256==event.eventSHA256,lifecycleState==event.resultingState,revision==event.revision,mutationID==event.mutationID else{throw SurveyDefinitionFailureV1.invalidTransition}}
    func validateSuccessor(of old:Self,event:SurveyDefinitionLifecycleEventV1,release:SurveyDefinitionReleaseV1)throws{try old.validateIntrinsic();try validate(currentRelease:release,event:event);guard definitionID==old.definitionID,workspaceID==old.workspaceID,activityKind==old.activityKind,createdBy==old.createdBy,createdAt==old.createdAt,event.predecessorEventID==old.latestLifecycleEventID,event.predecessorEventSHA256==old.latestLifecycleEventSHA256,event.priorState==old.lifecycleState,old.revision<UInt64.max,revision==old.revision+1 else{throw SurveyDefinitionFailureV1.invalidSuccessor}}
    func validateIntrinsic()throws{try currentRelease.validate();try createdBy.validate();guard schemaVersion==Self.schemaVersion,definitionID != SurveyDefinitionLimitsV1.zero,currentRelease.definitionID==definitionID,latestLifecycleEventID != SurveyDefinitionLimitsV1.zero,SurveyDefinitionLimitsV1.digest(latestLifecycleEventSHA256),createdBy.workspaceID==workspaceID,createdAt.timeIntervalSinceReferenceDate.isFinite,revision>0,identitySHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveyDefinitionFailureV1.invalidDigest}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,definitionID:definitionID,workspaceID:workspaceID,activityKind:activityKind,lifecycleState:lifecycleState,currentRelease:currentRelease,latestLifecycleEventID:latestLifecycleEventID,latestLifecycleEventSHA256:latestLifecycleEventSHA256,createdBy:createdBy,createdAt:createdAt,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let definitionID:UUID;let workspaceID:WorkspaceID;let activityKind:ActivityKindV1;let lifecycleState:SurveyDefinitionLifecycleStateV1;let currentRelease:SurveyDefinitionReleaseReferenceV1;let latestLifecycleEventID:UUID;let latestLifecycleEventSHA256:String;let createdBy:ActorSnapshotV1;let createdAt:Date;let revision:UInt64;let mutationID:MutationIDV1}
}

enum SurveySemanticChangeKindV1:String,Codable,CaseIterable,Hashable,Sendable{case sectionAdded="SECTION_ADDED",sectionRemoved="SECTION_REMOVED",sectionChanged="SECTION_CHANGED",factAdded="FACT_ADDED",factRemoved="FACT_REMOVED",factChanged="FACT_CHANGED",completionRuleChanged="COMPLETION_RULE_CHANGED",claimsProfileChanged="CLAIMS_PROFILE_CHANGED",reportProjectionChanged="REPORT_PROJECTION_CHANGED",localizationChanged="LOCALIZATION_CHANGED",activityKindChanged="ACTIVITY_KIND_CHANGED"}
enum SurveySemanticCompatibilityV1:String,Codable,Hashable,Sendable{case noChange="NO_CHANGE",additiveDraftSafe="ADDITIVE_DRAFT_SAFE",draftMigrationRequired="DRAFT_MIGRATION_REQUIRED",activeWorkIncompatible="ACTIVE_WORK_INCOMPATIBLE",invalid="INVALID"}
struct SurveySemanticChangeV1:Codable,Equatable,Hashable,Sendable{let kind:SurveySemanticChangeKindV1;let stableSubjectID:String;var stableKey:String{"\(kind.rawValue)|\(stableSubjectID)"}}
struct SurveyDefinitionSemanticDiffV1:Codable,Equatable,Sendable{let source,target:SurveyDefinitionReleaseReferenceV1;let changes:[SurveySemanticChangeV1];let compatibility:SurveySemanticCompatibilityV1;let diffSHA256:String;init(source:SurveyDefinitionReleaseV1,target:SurveyDefinitionReleaseV1)throws{try source.validate();try target.validate();guard source.workspaceID==target.workspaceID,source.definitionID==target.definitionID else{throw SurveyDefinitionFailureV1.invalidValue};self.source=try .init(source);self.target=try .init(target);var c:[SurveySemanticChangeV1]=[];if source.activityKind != target.activityKind{c.append(.init(kind:.activityKindChanged,stableSubjectID:target.definitionID.uuidString))};let sourceSections=Set(source.sections.map(\.sectionID)),targetSections=Set(target.sections.map(\.sectionID)),sourceSectionMap=Dictionary(uniqueKeysWithValues:source.sections.map{($0.sectionID,$0)}),targetSectionMap=Dictionary(uniqueKeysWithValues:target.sections.map{($0.sectionID,$0)});for id in targetSections.subtracting(sourceSections).sorted(){c.append(.init(kind:.sectionAdded,stableSubjectID:id))};for id in sourceSections.subtracting(targetSections).sorted(){c.append(.init(kind:.sectionRemoved,stableSubjectID:id))};for id in sourceSections.intersection(targetSections).sorted(){if let old=sourceSectionMap[id],let new=targetSectionMap[id],old.ordinal != new.ordinal||old.titleLocalizationKey != new.titleLocalizationKey||old.accessibilityHeadingLocalizationKey != new.accessibilityHeadingLocalizationKey{c.append(.init(kind:.sectionChanged,stableSubjectID:id))}};let a=Dictionary(uniqueKeysWithValues:source.sections.flatMap(\.facts).map{($0.factID,$0)}),b=Dictionary(uniqueKeysWithValues:target.sections.flatMap(\.facts).map{($0.factID,$0)});for id in Set(b.keys).subtracting(a.keys).sorted(){c.append(.init(kind:.factAdded,stableSubjectID:id))};for id in Set(a.keys).subtracting(b.keys).sorted(){c.append(.init(kind:.factRemoved,stableSubjectID:id))};for id in Set(a.keys).intersection(b.keys).sorted() where a[id] != b[id]{c.append(.init(kind:.factChanged,stableSubjectID:id))};if source.completionRules != target.completionRules{c.append(.init(kind:.completionRuleChanged,stableSubjectID:"completion"))};if source.claimsProfile != target.claimsProfile{c.append(.init(kind:.claimsProfileChanged,stableSubjectID:"claims"))};if source.reportProjection != target.reportProjection{c.append(.init(kind:.reportProjectionChanged,stableSubjectID:"report"))};if source.localizationReleaseSHA256 != target.localizationReleaseSHA256{c.append(.init(kind:.localizationChanged,stableSubjectID:"localization"))};changes=c.sorted{$0.stableKey<$1.stableKey};if changes.isEmpty{compatibility = .noChange}else if changes.contains(where:{$0.kind == .activityKindChanged}){compatibility = .invalid}else if changes.contains(where:{[.sectionRemoved,.sectionChanged,.factRemoved,.factChanged,.completionRuleChanged,.claimsProfileChanged].contains($0.kind)}){compatibility = .activeWorkIncompatible}else{compatibility = .additiveDraftSafe};diffSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(source:self.source,target:self.target,changes:changes,compatibility:compatibility))}func validate()throws{try source.validate();try target.validate();guard changes==changes.sorted(by:{$0.stableKey<$1.stableKey}),Set(changes.map(\.stableKey)).count==changes.count,diffSHA256==(try WorkspaceMutationCanonicalV1.sha256(Basis(source:source,target:target,changes:changes,compatibility:compatibility)))else{throw SurveyDefinitionFailureV1.invalidDigest}}func validate(source sourceRelease:SurveyDefinitionReleaseV1,target targetRelease:SurveyDefinitionReleaseV1)throws{try validate();let expected=try Self(source:sourceRelease,target:targetRelease);guard self==expected else{throw SurveyDefinitionFailureV1.stalePreview}}private struct Basis:Codable{let source,target:SurveyDefinitionReleaseReferenceV1;let changes:[SurveySemanticChangeV1];let compatibility:SurveySemanticCompatibilityV1}}
enum SurveyAdoptionDispositionV1:String,Codable,Hashable,Sendable{case noChange="NO_CHANGE",explicitDraftAdoptionAvailable="EXPLICIT_DRAFT_ADOPTION_AVAILABLE",activeWorkPinned="ACTIVE_WORK_PINNED",blocked="BLOCKED"}
struct SurveyDefinitionAdoptionPreviewV1:Codable,Equatable,Sendable{let previewID:String;let workspaceID:WorkspaceID;let semanticDiff:SurveyDefinitionSemanticDiffV1;let affectedDraftIDs:[UUID];let pinnedActiveWorkCount:Int;let disposition:SurveyAdoptionDispositionV1;let generatedAt:Date;let previewSHA256:String;init(workspaceID:WorkspaceID,diff:SurveyDefinitionSemanticDiffV1,affectedDraftIDs:[UUID],pinnedActiveWorkCount:Int,generatedAt:Date)throws{try diff.validate();self.workspaceID=workspaceID;semanticDiff=diff;self.affectedDraftIDs=affectedDraftIDs.sorted{$0.uuidString<$1.uuidString};self.pinnedActiveWorkCount=pinnedActiveWorkCount;self.generatedAt=generatedAt;guard pinnedActiveWorkCount>=0,Set(affectedDraftIDs).count==affectedDraftIDs.count,generatedAt.timeIntervalSinceReferenceDate.isFinite else{throw SurveyDefinitionFailureV1.invalidValue};switch diff.compatibility{case .noChange:disposition = .noChange;case .additiveDraftSafe,.draftMigrationRequired:disposition = pinnedActiveWorkCount>0 ? .activeWorkPinned:.explicitDraftAdoptionAvailable;case .activeWorkIncompatible:disposition = .activeWorkPinned;case .invalid:disposition = .blocked};previewSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID:workspaceID,semanticDiff:diff,affectedDraftIDs:self.affectedDraftIDs,pinnedActiveWorkCount:pinnedActiveWorkCount,disposition:disposition,generatedAt:generatedAt));previewID=previewSHA256}func validate(source:SurveyDefinitionReleaseV1,target:SurveyDefinitionReleaseV1,currentDraftIDs:[UUID],currentActiveWorkCount:Int)throws{try semanticDiff.validate(source:source,target:target);let expected=try Self(workspaceID:source.workspaceID,diff:semanticDiff,affectedDraftIDs:currentDraftIDs,pinnedActiveWorkCount:currentActiveWorkCount,generatedAt:generatedAt);guard self==expected else{throw SurveyDefinitionFailureV1.stalePreview}}private struct Basis:Codable{let workspaceID:WorkspaceID;let semanticDiff:SurveyDefinitionSemanticDiffV1;let affectedDraftIDs:[UUID];let pinnedActiveWorkCount:Int;let disposition:SurveyAdoptionDispositionV1;let generatedAt:Date}}

struct SurveyTemplateArchiveEntryV1: Codable, Equatable, Sendable {
    static let maximumPathUTF8Bytes = 240
    static let maximumPathDepth = 8
    static let maximumExpandedBytes: Int64 = 8_388_608
    static let maximumCompressionRatio: Int64 = 20
    let path, mediaType: String
    let compressedByteCount: Int64
    let byteCount: Int64
    let storedSHA256: String
    let sha256: String
    init(path: String, mediaType: String, byteCount: Int64, sha256: String, compressedByteCount: Int64? = nil, storedSHA256: String? = nil) {
        self.path = path
        self.mediaType = mediaType
        self.compressedByteCount = compressedByteCount ?? byteCount
        self.byteCount = byteCount
        self.storedSHA256 = storedSHA256 ?? sha256
        self.sha256 = sha256
    }
    func validate() throws {
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.utf8.count <= Self.maximumPathUTF8Bytes,
              pieces.count <= Self.maximumPathDepth,
              !path.hasPrefix("/"), !path.contains("\\"),
              !pieces.contains(".."), !pieces.contains("."), !pieces.contains(""),
              Self.validMediaType(mediaType),
              compressedByteCount >= 0,
              byteCount >= 0, byteCount <= Self.maximumExpandedBytes,
              (compressedByteCount == 0) == (byteCount == 0),
              compressedByteCount <= Self.maximumExpandedBytes,
              compressedByteCount == 0 || byteCount / compressedByteCount <= Self.maximumCompressionRatio,
              compressedByteCount == 0 || !(byteCount / compressedByteCount == Self.maximumCompressionRatio && byteCount % compressedByteCount != 0),
              SurveyDefinitionLimitsV1.digest(storedSHA256),
              SurveyDefinitionLimitsV1.digest(sha256) else {
            throw SurveyDefinitionFailureV1.hostileArchive
        }
    }
    private static func validMediaType(_ value:String)->Bool{!value.isEmpty&&value.utf8.count<=128&&value.utf8.allSatisfy{(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[43,45,46,47].contains($0)}}
}
struct SurveyTemplateArchiveManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1, fileExtension = "arsurveytemplate", maximumEntries = 128
    static let maximumArchiveBytes: Int64 = 16_777_216
    let schemaVersion: Int
    let archiveID: UUID
    let definitionRelease: SurveyDefinitionReleaseReferenceV1
    let entries: [SurveyTemplateArchiveEntryV1]
    let archiveByteCount: Int64
    let archiveSHA256, manifestSHA256: String
    init(archiveID:UUID,definitionRelease:SurveyDefinitionReleaseReferenceV1,entries:[SurveyTemplateArchiveEntryV1],archiveByteCount:Int64,archiveSHA256:String)throws{schemaVersion=Self.schemaVersion;self.archiveID=archiveID;self.definitionRelease=definitionRelease;self.entries=entries.sorted{$0.path<$1.path};self.archiveByteCount=archiveByteCount;self.archiveSHA256=archiveSHA256;manifestSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,archiveID:archiveID,definitionRelease:definitionRelease,entries:self.entries,archiveByteCount:archiveByteCount,archiveSHA256:archiveSHA256));try validate()}
    init(schemaVersion:Int,archiveID:UUID,definitionRelease:SurveyDefinitionReleaseReferenceV1,entries:[SurveyTemplateArchiveEntryV1],archiveByteCount:Int64,archiveSHA256:String,manifestSHA256:String){self.schemaVersion=schemaVersion;self.archiveID=archiveID;self.definitionRelease=definitionRelease;self.entries=entries;self.archiveByteCount=archiveByteCount;self.archiveSHA256=archiveSHA256;self.manifestSHA256=manifestSHA256}
    func validate() throws {
        try definitionRelease.validate(); try entries.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              archiveID != SurveyDefinitionLimitsV1.zero,
              !entries.isEmpty, entries.count <= Self.maximumEntries,
              entries == entries.sorted(by: { $0.path < $1.path }),
              Set(entries.map(\.path)).count == entries.count,
              archiveByteCount == entries.reduce(Int64(0), { $0 + $1.byteCount }),
              archiveByteCount <= Self.maximumArchiveBytes,
              SurveyDefinitionLimitsV1.digest(archiveSHA256),
              SurveyDefinitionLimitsV1.digest(manifestSHA256),
              manifestSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw SurveyDefinitionFailureV1.hostileArchive
        }
    }
    private var basis:Basis{.init(schemaVersion:schemaVersion,archiveID:archiveID,definitionRelease:definitionRelease,entries:entries,archiveByteCount:archiveByteCount,archiveSHA256:archiveSHA256)}
    private struct Basis:Codable{let schemaVersion:Int;let archiveID:UUID;let definitionRelease:SurveyDefinitionReleaseReferenceV1;let entries:[SurveyTemplateArchiveEntryV1];let archiveByteCount:Int64;let archiveSHA256:String}
}
enum SurveyTemplateQuarantineDispositionV1:String,Codable,Hashable,Sendable{case draftCandidate="DRAFT_CANDIDATE",rejected="REJECTED"}
struct SurveyTemplateQuarantineAssessmentV1:Codable,Equatable,Sendable{let quarantineID:UUID;let archiveSHA256:String;let manifestSHA256,candidateReleaseSHA256:String?;let disposition:SurveyTemplateQuarantineDispositionV1;let findings:[String];let assessedAt:Date;let assessmentSHA256:String;init(quarantineID:UUID,archiveSHA256:String,manifestSHA256:String?,candidateReleaseSHA256:String?,disposition:SurveyTemplateQuarantineDispositionV1,findings:[String],assessedAt:Date)throws{self.quarantineID=quarantineID;self.archiveSHA256=archiveSHA256;self.manifestSHA256=manifestSHA256;self.candidateReleaseSHA256=candidateReleaseSHA256;self.disposition=disposition;self.findings=findings.sorted();self.assessedAt=assessedAt;assessmentSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(quarantineID:quarantineID,archiveSHA256:archiveSHA256,manifestSHA256:manifestSHA256,candidateReleaseSHA256:candidateReleaseSHA256,disposition:disposition,findings:self.findings,assessedAt:assessedAt));try validate()}init(quarantineID:UUID,archiveSHA256:String,manifestSHA256:String?,candidateReleaseSHA256:String?,disposition:SurveyTemplateQuarantineDispositionV1,findings:[String],assessedAt:Date,assessmentSHA256:String){self.quarantineID=quarantineID;self.archiveSHA256=archiveSHA256;self.manifestSHA256=manifestSHA256;self.candidateReleaseSHA256=candidateReleaseSHA256;self.disposition=disposition;self.findings=findings;self.assessedAt=assessedAt;self.assessmentSHA256=assessmentSHA256}func validate()throws{guard quarantineID != SurveyDefinitionLimitsV1.zero,SurveyDefinitionLimitsV1.digest(archiveSHA256),manifestSHA256.map(SurveyDefinitionLimitsV1.digest) ?? true,candidateReleaseSHA256.map(SurveyDefinitionLimitsV1.digest) ?? true,findings==findings.sorted(),Set(findings).count==findings.count,findings.allSatisfy({ SurveyDefinitionLimitsV1.token($0) }),assessedAt.timeIntervalSinceReferenceDate.isFinite,SurveyDefinitionLimitsV1.digest(assessmentSHA256),(disposition == .draftCandidate)==(manifestSHA256 != nil&&candidateReleaseSHA256 != nil&&findings.isEmpty),assessmentSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveyDefinitionFailureV1.hostileArchive}}private var basis:Basis{.init(quarantineID:quarantineID,archiveSHA256:archiveSHA256,manifestSHA256:manifestSHA256,candidateReleaseSHA256:candidateReleaseSHA256,disposition:disposition,findings:findings,assessedAt:assessedAt)}private struct Basis:Codable{let quarantineID:UUID;let archiveSHA256:String;let manifestSHA256,candidateReleaseSHA256:String?;let disposition:SurveyTemplateQuarantineDispositionV1;let findings:[String];let assessedAt:Date}}

enum SurveyDefinitionCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];e.dateEncodingStrategy = .millisecondsSince1970;let d=try e.encode(value);guard !d.isEmpty,d.count<=SurveyDefinitionLimitsV1.maximumCanonicalBytes else{throw SurveyDefinitionFailureV1.limitExceeded};return d}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=SurveyDefinitionLimitsV1.maximumCanonicalBytes else{throw SurveyDefinitionFailureV1.limitExceeded};let d=JSONDecoder();d.dateDecodingStrategy = .millisecondsSince1970;let v=try d.decode(type,from:data);guard try encode(v)==data else{throw SurveyDefinitionFailureV1.invalidDigest};return v}}
enum SurveyDefinitionLifecycleV1{static let persistentFamilies=["SurveyDefinitionIdentityV1","SurveyDefinitionReleaseV1"];static let lifecycleEventPersistence="CANONICAL_MUTATION_JOURNAL_ENVELOPE";static let semanticDiffPersistence="NONPERSISTENT";static let adoptionPreviewPersistence="NONPERSISTENT";static let quarantinePersistence="DERIVED_ONLY";static let writer="SOLE_CANONICAL_WORKSPACE_WRITER";static let importDisposition="QUARANTINE_THEN_NEW_DRAFT_IDENTITY"}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Packs_SurveyDefinitionContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}
