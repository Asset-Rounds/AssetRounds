import Foundation

enum MeasurementIntegrityFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case wrongWorkspace
    case staleReference
    case duplicateIdentity
    case invalidTransition
    case immutableHistory
    case unsupportedSource
    case incompleteSeries
    case reviewRequired
    case digestMismatch
    case nonCanonicalData
    case limitExceeded
}

enum MeasurementIntegrityLimitsV1 {
    static let maximumTextBytes = 512
    static let maximumUnitCount = 128
    static let maximumEvidenceCount = 32
    static let maximumSampleCount = 10_000
    static let maximumReasonCount = 32
    static let maximumCanonicalBytes = 8_388_608
}

protocol MeasurementIntegrityValidatableV1 { func validate() throws }

enum InstrumentKindV1: String, CaseIterable, Codable, Sendable {
    case illuminanceMeter = "ILLUMINANCE_METER"
    case multimeter = "MULTIMETER"
    case thermometer = "THERMOMETER"
    case otherTypedLocalInstrument = "OTHER_TYPED_LOCAL_INSTRUMENT"
}

enum InstrumentLifecycleStateV1: String, CaseIterable, Codable, Sendable {
    case active = "ACTIVE"
    case outOfService = "OUT_OF_SERVICE"
    case retired = "RETIRED"
}

enum CalibrationStatusV1: String, CaseIterable, Codable, Sendable {
    case notRequired = "NOT_REQUIRED"
    case current = "CURRENT"
    case expired = "EXPIRED"
    case unknown = "UNKNOWN"
    case outOfService = "OUT_OF_SERVICE"
}

enum CalibrationBasisV1: String, CaseIterable, Codable, Sendable {
    case declaredNotRequired = "DECLARED_NOT_REQUIRED"
    case referencedEvidence = "REFERENCED_EVIDENCE"
    case locallyRecordedStatus = "LOCALLY_RECORDED_STATUS"
    case unknown = "UNKNOWN"
}

enum MeasurementCaptureSourceModeV1: String, CaseIterable, Codable, Sendable {
    case manualEntry = "MANUAL_ENTRY"
    case localObservation = "LOCAL_OBSERVATION"
}

enum MeasurementSeriesStateV1: String, CaseIterable, Codable, Sendable {
    case open = "OPEN"
    case finalized = "FINALIZED"
}

enum MeasurementAggregationPolicyV1: String, CaseIterable, Codable, Sendable {
    case none = "NONE"
    case mean = "MEAN"
    case median = "MEDIAN"
    case minimum = "MINIMUM"
    case maximum = "MAXIMUM"
}

enum MeasurementQualitySubjectKindV1: String, CaseIterable, Codable, Sendable {
    case capture = "CAPTURE"
    case series = "SERIES"
}

enum MeasurementQualityResultV1: String, CaseIterable, Codable, Sendable {
    case clear = "CLEAR"
    case reviewRequired = "REVIEW_REQUIRED"
    case overridden = "OVERRIDDEN"
}

enum MeasurementQualityReasonV1: String, CaseIterable, Codable, Hashable, Comparable, Sendable {
    case declaredChecksClear = "DECLARED_CHECKS_CLEAR"
    case calibrationNotRequired = "CALIBRATION_NOT_REQUIRED"
    case calibrationExpired = "CALIBRATION_EXPIRED"
    case calibrationUnknown = "CALIBRATION_UNKNOWN"
    case instrumentOutOfService = "INSTRUMENT_OUT_OF_SERVICE"
    case missingUncertainty = "MISSING_UNCERTAINTY"
    case uncertaintyCrossesBoundary = "UNCERTAINTY_CROSSES_BOUNDARY"
    case incompleteSampleSet = "INCOMPLETE_SAMPLE_SET"
    case duplicateSample = "DUPLICATE_SAMPLE"
    case retainedOutlier = "RETAINED_OUTLIER"
    case observationLimitation = "OBSERVATION_LIMITATION"
    case humanOverride = "HUMAN_OVERRIDE"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct InstrumentRevisionReferenceV1: Codable, Equatable, Sendable {
    let instrumentID: UUID
    let referenceID: UUID
    let revision: UInt64
    let referenceSHA256: String

    init(instrumentID: UUID, referenceID: UUID, revision: UInt64, referenceSHA256: String) throws {
        self.instrumentID = instrumentID; self.referenceID = referenceID
        self.revision = revision; self.referenceSHA256 = referenceSHA256
        try validate()
    }

    init(_ value: InstrumentReferenceV1) throws {
        try self.init(instrumentID: value.instrumentID, referenceID: value.referenceID,
                      revision: value.revision, referenceSHA256: value.referenceSHA256)
    }

    func validate() throws {
        guard instrumentID != UUID.zero, referenceID != UUID.zero, revision > 0,
              MutationEnvelopeV1.isSHA256(referenceSHA256) else { throw MeasurementIntegrityFailureV1.invalidValue }
    }
}

struct CalibrationSnapshotReferenceV1: Codable, Equatable, Sendable {
    let snapshotID: UUID
    let revision: UInt64
    let snapshotSHA256: String

    init(snapshotID: UUID, revision: UInt64, snapshotSHA256: String) throws {
        self.snapshotID = snapshotID; self.revision = revision; self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    init(_ value: CalibrationStatusSnapshotV1) throws {
        try self.init(snapshotID: value.snapshotID, revision: value.revision,
                      snapshotSHA256: value.snapshotSHA256)
    }

    func validate() throws {
        guard snapshotID != UUID.zero, revision > 0, MutationEnvelopeV1.isSHA256(snapshotSHA256) else {
            throw MeasurementIntegrityFailureV1.invalidValue
        }
    }
}

struct MeasurementCaptureReferenceV1: Codable, Equatable, Sendable {
    let captureID: UUID
    let revision: UInt64
    let captureSHA256: String
    let sampleOrdinal: Int

    init(captureID: UUID, revision: UInt64, captureSHA256: String, sampleOrdinal: Int) throws {
        self.captureID = captureID; self.revision = revision
        self.captureSHA256 = captureSHA256; self.sampleOrdinal = sampleOrdinal
        try validate()
    }

    func validate() throws {
        guard captureID != UUID.zero, revision > 0, sampleOrdinal > 0,
              sampleOrdinal <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              MutationEnvelopeV1.isSHA256(captureSHA256) else { throw MeasurementIntegrityFailureV1.invalidValue }
    }
}

struct MeasurementProtocolReferenceV1: Codable, Equatable, Sendable {
    let releaseID: UUID
    let revision: UInt64
    let releaseSHA256: String

    init(_ value: MeasurementProtocolReleaseV1) throws {
        try value.validate(); releaseID = value.releaseID; revision = value.revision; releaseSHA256 = value.releaseSHA256
    }

    init(releaseID: UUID, revision: UInt64, releaseSHA256: String) throws {
        self.releaseID = releaseID; self.revision = revision; self.releaseSHA256 = releaseSHA256; try validate()
    }

    func validate() throws {
        guard releaseID != UUID.zero, revision > 0, MutationEnvelopeV1.isSHA256(releaseSHA256) else {
            throw MeasurementIntegrityFailureV1.invalidValue
        }
    }
}

struct InstrumentReferenceV1: Codable, Equatable, Sendable, MeasurementIntegrityValidatableV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let referenceID: UUID; let instrumentID: UUID; let workspaceID: WorkspaceID
    let kind: InstrumentKindV1; let label: String; let opaqueSerial: String?; let manufacturer: String?; let model: String?
    let supportedUnitIDs: [String]; let lifecycleState: InstrumentLifecycleStateV1
    let recordedAt: Date; let supersedesReferenceID: UUID?; let revision: UInt64; let mutationID: MutationIDV1
    let referenceSHA256: String

    init(referenceID: UUID, instrumentID: UUID, workspaceID: WorkspaceID, kind: InstrumentKindV1,
         label: String, opaqueSerial: String? = nil, manufacturer: String? = nil, model: String? = nil,
         supportedUnitIDs: [String], lifecycleState: InstrumentLifecycleStateV1,
         recordedAt: Date, supersedesReferenceID: UUID? = nil, revision: UInt64 = 1,
         mutationID: MutationIDV1) throws {
        let units = supportedUnitIDs.sorted()
        schemaVersion = Self.schemaVersion; self.referenceID = referenceID; self.instrumentID = instrumentID
        self.workspaceID = workspaceID; self.kind = kind; self.label = label; self.opaqueSerial = opaqueSerial
        self.manufacturer = manufacturer; self.model = model; self.supportedUnitIDs = units
        self.lifecycleState = lifecycleState; self.recordedAt = recordedAt
        self.supersedesReferenceID = supersedesReferenceID; self.revision = revision; self.mutationID = mutationID
        referenceSHA256 = try MeasurementIntegrityCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, referenceID: referenceID, instrumentID: instrumentID,
            workspaceID: workspaceID, kind: kind, label: label, opaqueSerial: opaqueSerial,
            manufacturer: manufacturer, model: model, supportedUnitIDs: units, lifecycleState: lifecycleState,
            recordedAt: recordedAt, supersedesReferenceID: supersedesReferenceID, revision: revision, mutationID: mutationID))
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, referenceID != UUID.zero, instrumentID != UUID.zero,
              revision > 0, (revision == 1) == (supersedesReferenceID == nil), supersedesReferenceID != referenceID,
              MeasurementIntegrityValidationV1.text(label), supportedUnitIDs.count <= MeasurementIntegrityLimitsV1.maximumUnitCount,
              supportedUnitIDs == supportedUnitIDs.sorted(), Set(supportedUnitIDs).count == supportedUnitIDs.count,
              opaqueSerial.map(MeasurementIntegrityValidationV1.text) ?? true,
              manufacturer.map(MeasurementIntegrityValidationV1.text) ?? true,
              model.map(MeasurementIntegrityValidationV1.text) ?? true else { throw MeasurementIntegrityFailureV1.invalidValue }
        for unitID in supportedUnitIDs { _ = try KernelUnitRegistryV1.definition(unitID: unitID) }
        guard referenceSHA256 == (try MeasurementIntegrityCanonicalCodecV1.sha256(digestBasis)) else {
            throw MeasurementIntegrityFailureV1.digestMismatch
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validate(); try validate(); let next = predecessor.revision.addingReportingOverflow(1)
        guard !next.overflow, revision == next.partialValue, instrumentID == predecessor.instrumentID,
              workspaceID == predecessor.workspaceID, supersedesReferenceID == predecessor.referenceID,
              recordedAt >= predecessor.recordedAt,
              predecessor.lifecycleState != .retired || lifecycleState == .retired else {
            throw MeasurementIntegrityFailureV1.immutableHistory
        }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try .init(referenceID: referenceID, instrumentID: instrumentID, workspaceID: workspaceID, kind: kind,
                  label: label, opaqueSerial: opaqueSerial, manufacturer: manufacturer, model: model,
                  supportedUnitIDs: supportedUnitIDs, lifecycleState: lifecycleState, recordedAt: recordedAt,
                  supersedesReferenceID: supersedesReferenceID, revision: revision, mutationID: mutationID)
    }

    private var digestBasis: DigestBasis { .init(schemaVersion: schemaVersion, referenceID: referenceID,
        instrumentID: instrumentID, workspaceID: workspaceID, kind: kind, label: label, opaqueSerial: opaqueSerial,
        manufacturer: manufacturer, model: model, supportedUnitIDs: supportedUnitIDs, lifecycleState: lifecycleState,
        recordedAt: recordedAt, supersedesReferenceID: supersedesReferenceID, revision: revision, mutationID: mutationID) }
    private struct DigestBasis: Codable { let schemaVersion:Int;let referenceID:UUID;let instrumentID:UUID;let workspaceID:WorkspaceID;let kind:InstrumentKindV1;let label:String;let opaqueSerial:String?;let manufacturer:String?;let model:String?;let supportedUnitIDs:[String];let lifecycleState:InstrumentLifecycleStateV1;let recordedAt:Date;let supersedesReferenceID:UUID?;let revision:UInt64;let mutationID:MutationIDV1 }
}

struct CalibrationStatusSnapshotV1: Codable, Equatable, Sendable, MeasurementIntegrityValidatableV1 {
    static let schemaVersion = 1
    let schemaVersion:Int;let snapshotID:UUID;let workspaceID:WorkspaceID;let instrument:InstrumentRevisionReferenceV1
    let status:CalibrationStatusV1;let basis:CalibrationBasisV1;let effectiveAt:Date?;let expiresAt:Date?
    let sourceReference:ContentReferenceV1?;let capturedAt:Date;let supersedesSnapshotID:UUID?;let revision:UInt64
    let mutationID:MutationIDV1;let snapshotSHA256:String

    init(snapshotID:UUID, workspaceID:WorkspaceID, instrument:InstrumentRevisionReferenceV1,
         status:CalibrationStatusV1, basis:CalibrationBasisV1, effectiveAt:Date? = nil, expiresAt:Date? = nil,
         sourceReference:ContentReferenceV1? = nil, capturedAt:Date, supersedesSnapshotID:UUID? = nil,
         revision:UInt64 = 1, mutationID:MutationIDV1) throws {
        schemaVersion=Self.schemaVersion;self.snapshotID=snapshotID;self.workspaceID=workspaceID;self.instrument=instrument
        self.status=status;self.basis=basis;self.effectiveAt=effectiveAt;self.expiresAt=expiresAt;self.sourceReference=sourceReference
        self.capturedAt=capturedAt;self.supersedesSnapshotID=supersedesSnapshotID;self.revision=revision;self.mutationID=mutationID
        snapshotSHA256 = try MeasurementIntegrityCanonicalCodecV1.sha256(DigestBasis(schemaVersion:Self.schemaVersion,snapshotID:snapshotID,workspaceID:workspaceID,instrument:instrument,status:status,basis:basis,effectiveAt:effectiveAt,expiresAt:expiresAt,sourceReference:sourceReference,capturedAt:capturedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID))
        try validate()
    }

    func validate() throws {
        try instrument.validate()
        if let sourceReference { try MeasurementIntegrityValidationV1.evidence([sourceReference], workspaceID: workspaceID) }
        let shape: Bool
        switch status {
        case .notRequired: shape = basis == .declaredNotRequired && expiresAt == nil
        case .current: shape = effectiveAt != nil && expiresAt != nil && basis != .unknown
        case .expired: shape = effectiveAt != nil && expiresAt != nil && basis != .unknown
        case .unknown: shape = basis == .unknown && effectiveAt == nil && expiresAt == nil
        case .outOfService: shape = basis != .declaredNotRequired
        }
        let temporalShape: Bool
        switch status {
        case .current: temporalShape = effectiveAt.map { $0 <= capturedAt } == true && expiresAt.map { capturedAt <= $0 } == true
        case .expired: temporalShape = expiresAt.map { $0 < capturedAt } == true
        default: temporalShape = true
        }
        guard schemaVersion==Self.schemaVersion,snapshotID != UUID.zero,revision>0,
              (revision == 1) == (supersedesSnapshotID == nil), supersedesSnapshotID != snapshotID,
              shape, (basis == .referencedEvidence) == (sourceReference != nil),
              expiresAt.map { expiry in effectiveAt.map { $0 <= expiry } ?? false } ?? true,
              temporalShape,
              snapshotSHA256 == (try MeasurementIntegrityCanonicalCodecV1.sha256(digestBasis)) else {
            throw MeasurementIntegrityFailureV1.invalidValue
        }
    }

    func validateSuccessor(of predecessor:Self)throws { try predecessor.validate();try validate();let next=predecessor.revision.addingReportingOverflow(1);guard !next.overflow,revision==next.partialValue,workspaceID==predecessor.workspaceID,instrument.instrumentID==predecessor.instrument.instrumentID,supersedesSnapshotID==predecessor.snapshotID,capturedAt>=predecessor.capturedAt else{throw MeasurementIntegrityFailureV1.immutableHistory} }
    func rebound(to workspaceID:WorkspaceID)throws->Self{let source=try sourceReference.map{try MeasurementIntegrityValidationV1.rebound([$0],to:workspaceID)[0]};return try .init(snapshotID:snapshotID,workspaceID:workspaceID,instrument:instrument,status:status,basis:basis,effectiveAt:effectiveAt,expiresAt:expiresAt,sourceReference:source,capturedAt:capturedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID)}
    private var digestBasis:DigestBasis{.init(schemaVersion:schemaVersion,snapshotID:snapshotID,workspaceID:workspaceID,instrument:instrument,status:status,basis:basis,effectiveAt:effectiveAt,expiresAt:expiresAt,sourceReference:sourceReference,capturedAt:capturedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID)}
    private struct DigestBasis:Codable{let schemaVersion:Int;let snapshotID:UUID;let workspaceID:WorkspaceID;let instrument:InstrumentRevisionReferenceV1;let status:CalibrationStatusV1;let basis:CalibrationBasisV1;let effectiveAt:Date?;let expiresAt:Date?;let sourceReference:ContentReferenceV1?;let capturedAt:Date;let supersedesSnapshotID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct MeasurementCaptureV1: Codable, Equatable, Sendable, MeasurementIntegrityValidatableV1 {
    static let schemaVersion=1
    let schemaVersion:Int;let captureID:UUID;let workspaceID:WorkspaceID;let packageReleaseID:String;let workflowSHA256:String
    let response:BoundResponseValueV1;let measurement:ExactMeasurementV1;let sourceMode:MeasurementCaptureSourceModeV1
    let instrument:InstrumentRevisionReferenceV1?;let calibration:CalibrationSnapshotReferenceV1?
    let observationBasis:ObservationBasisV1;let operatorSnapshot:ActorSnapshotV1;let evidence:[ContentReferenceV1]
    let capturedAt:Date;let supersedesCaptureID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let captureSHA256:String

    init(captureID:UUID,workspaceID:WorkspaceID,packageReleaseID:String,workflowSHA256:String,
         response:BoundResponseValueV1,measurement:ExactMeasurementV1,sourceMode:MeasurementCaptureSourceModeV1,
         instrument:InstrumentRevisionReferenceV1?=nil,calibration:CalibrationSnapshotReferenceV1?=nil,
         observationBasis:ObservationBasisV1,operatorSnapshot:ActorSnapshotV1,evidence:[ContentReferenceV1]=[],
         capturedAt:Date,supersedesCaptureID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{
        let sorted=evidence.sorted{$0.id<$1.id};schemaVersion=Self.schemaVersion;self.captureID=captureID;self.workspaceID=workspaceID
        self.packageReleaseID=packageReleaseID;self.workflowSHA256=workflowSHA256;self.response=response;self.measurement=measurement
        self.sourceMode=sourceMode;self.instrument=instrument;self.calibration=calibration;self.observationBasis=observationBasis
        self.operatorSnapshot=operatorSnapshot;self.evidence=sorted;self.capturedAt=capturedAt;self.supersedesCaptureID=supersedesCaptureID
        self.revision=revision;self.mutationID=mutationID
        captureSHA256=try MeasurementIntegrityCanonicalCodecV1.sha256(DigestBasis(schemaVersion:Self.schemaVersion,captureID:captureID,workspaceID:workspaceID,packageReleaseID:packageReleaseID,workflowSHA256:workflowSHA256,response:response,measurement:measurement,sourceMode:sourceMode,instrument:instrument,calibration:calibration,observationBasis:observationBasis,operatorSnapshot:operatorSnapshot,evidence:sorted,capturedAt:capturedAt,supersedesCaptureID:supersedesCaptureID,revision:revision,mutationID:mutationID));try validate()
    }
    func validate()throws{
        try measurement.validate();try response.value.validate();try observationBasis.validate();try operatorSnapshot.validate();try instrument?.validate();try calibration?.validate();try MeasurementIntegrityValidationV1.evidence(evidence,workspaceID:workspaceID)
        guard case .measurement(let responseMeasurement)=response.value else{throw MeasurementIntegrityFailureV1.invalidValue}
        let sourceShape = sourceMode == .manualEntry ? (instrument == nil && calibration == nil && measurement.source == .manualEntry) : (instrument != nil && calibration != nil && measurement.source == .instrumentObserved)
        guard schemaVersion==Self.schemaVersion,captureID != UUID.zero,revision>0,
              (revision == 1) == (supersedesCaptureID == nil), supersedesCaptureID != captureID,
              MutationEnvelopeV1.isSHA256(packageReleaseID),MutationEnvelopeV1.isSHA256(workflowSHA256),
              responseMeasurement==measurement,sourceShape,operatorSnapshot.workspaceID==workspaceID,
              [.performedBy,.recordedBy].contains(operatorSnapshot.responsibility),
              captureSHA256==(try MeasurementIntegrityCanonicalCodecV1.sha256(digestBasis)) else{throw MeasurementIntegrityFailureV1.invalidValue}
    }
    func validate(fieldDefinition:ResponseFieldDefinitionV1)throws{try validate();guard fieldDefinition.packageReleaseID==packageReleaseID,fieldDefinition.workflowSHA256==workflowSHA256 else{throw MeasurementIntegrityFailureV1.staleReference};try ResponseFieldValidatorV1.validate(response,against:fieldDefinition)}
    func validateClosure(instrument instrumentValue:InstrumentReferenceV1?,calibration calibrationValue:CalibrationStatusSnapshotV1?)throws{try validate();switch sourceMode{case .manualEntry:guard instrumentValue==nil,calibrationValue==nil else{throw MeasurementIntegrityFailureV1.invalidValue};case .localObservation:guard let instrumentValue,let calibrationValue else{throw MeasurementIntegrityFailureV1.staleReference};let expectedInstrument=try InstrumentRevisionReferenceV1(instrumentValue);let expectedCalibration=try CalibrationSnapshotReferenceV1(calibrationValue);guard instrument==expectedInstrument,calibration==expectedCalibration,instrumentValue.workspaceID==workspaceID,calibrationValue.workspaceID==workspaceID,calibrationValue.instrument==instrument else{throw MeasurementIntegrityFailureV1.staleReference}}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validate();try validate();let next=predecessor.revision.addingReportingOverflow(1);guard !next.overflow,revision==next.partialValue,workspaceID==predecessor.workspaceID,supersedesCaptureID==predecessor.captureID,capturedAt>=predecessor.capturedAt else{throw MeasurementIntegrityFailureV1.immutableHistory}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(captureID:captureID,workspaceID:workspaceID,packageReleaseID:packageReleaseID,workflowSHA256:workflowSHA256,response:response,measurement:measurement,sourceMode:sourceMode,instrument:instrument,calibration:calibration,observationBasis:observationBasis,operatorSnapshot:MeasurementIntegrityValidationV1.rebound(operatorSnapshot,to:workspaceID),evidence:try MeasurementIntegrityValidationV1.rebound(evidence,to:workspaceID),capturedAt:capturedAt,supersedesCaptureID:supersedesCaptureID,revision:revision,mutationID:mutationID)}
    private var digestBasis:DigestBasis{.init(schemaVersion:schemaVersion,captureID:captureID,workspaceID:workspaceID,packageReleaseID:packageReleaseID,workflowSHA256:workflowSHA256,response:response,measurement:measurement,sourceMode:sourceMode,instrument:instrument,calibration:calibration,observationBasis:observationBasis,operatorSnapshot:operatorSnapshot,evidence:evidence,capturedAt:capturedAt,supersedesCaptureID:supersedesCaptureID,revision:revision,mutationID:mutationID)}
    private struct DigestBasis:Codable{let schemaVersion:Int;let captureID:UUID;let workspaceID:WorkspaceID;let packageReleaseID:String;let workflowSHA256:String;let response:BoundResponseValueV1;let measurement:ExactMeasurementV1;let sourceMode:MeasurementCaptureSourceModeV1;let instrument:InstrumentRevisionReferenceV1?;let calibration:CalibrationSnapshotReferenceV1?;let observationBasis:ObservationBasisV1;let operatorSnapshot:ActorSnapshotV1;let evidence:[ContentReferenceV1];let capturedAt:Date;let supersedesCaptureID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct MeasurementSeriesV1:Codable,Equatable,Sendable,MeasurementIntegrityValidatableV1{
    static let schemaVersion=1
    let schemaVersion:Int;let snapshotID:UUID;let seriesID:UUID;let workspaceID:WorkspaceID;let protocolReference:MeasurementProtocolReferenceV1
    let samples:[MeasurementCaptureReferenceV1];let expectedSampleCount:Int;let observedSampleCount:Int;let aggregationPolicy:MeasurementAggregationPolicyV1;let state:MeasurementSeriesStateV1
    let derivedFact:DerivedFactProvenanceV1?;let recordedAt:Date;let supersedesSnapshotID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let seriesSHA256:String
    init(snapshotID:UUID,seriesID:UUID,workspaceID:WorkspaceID,protocolReference:MeasurementProtocolReferenceV1,samples:[MeasurementCaptureReferenceV1],expectedSampleCount:Int,aggregationPolicy:MeasurementAggregationPolicyV1,state:MeasurementSeriesStateV1,derivedFact:DerivedFactProvenanceV1?=nil,recordedAt:Date,supersedesSnapshotID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{
        let ordered=samples.sorted{$0.sampleOrdinal<$1.sampleOrdinal};schemaVersion=Self.schemaVersion;self.snapshotID=snapshotID;self.seriesID=seriesID;self.workspaceID=workspaceID;self.protocolReference=protocolReference;self.samples=ordered;self.expectedSampleCount=expectedSampleCount;observedSampleCount=ordered.count;self.aggregationPolicy=aggregationPolicy;self.state=state;self.derivedFact=derivedFact;self.recordedAt=recordedAt;self.supersedesSnapshotID=supersedesSnapshotID;self.revision=revision;self.mutationID=mutationID;seriesSHA256=try MeasurementIntegrityCanonicalCodecV1.sha256(DigestBasis(schemaVersion:Self.schemaVersion,snapshotID:snapshotID,seriesID:seriesID,workspaceID:workspaceID,protocolReference:protocolReference,samples:ordered,expectedSampleCount:expectedSampleCount,observedSampleCount:ordered.count,aggregationPolicy:aggregationPolicy,state:state,derivedFact:derivedFact,recordedAt:recordedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID));try validate()
    }
    func validate()throws{try protocolReference.validate();try samples.forEach{$0.validate()};try derivedFact?.validate();guard expectedSampleCount>0,expectedSampleCount<=MeasurementIntegrityLimitsV1.maximumSampleCount else{throw MeasurementIntegrityFailureV1.invalidValue};let ordinals=samples.map(\.sampleOrdinal);let expectedOrdinals=Array(1...expectedSampleCount);let aggregateShape=aggregationPolicy == .none ? derivedFact==nil : derivedFact != nil;let finalShape=state == .finalized ? (observedSampleCount==expectedSampleCount && ordinals==expectedOrdinals && aggregateShape) : (observedSampleCount<=expectedSampleCount && derivedFact==nil);guard schemaVersion==Self.schemaVersion,snapshotID != UUID.zero,seriesID != UUID.zero,revision>0,(revision == 1)==(supersedesSnapshotID==nil),supersedesSnapshotID != snapshotID,observedSampleCount==samples.count,Set(samples.map(\.captureID)).count==samples.count,Set(ordinals).count==ordinals.count,finalShape,derivedFact.map{$0.workspaceID==workspaceID && $0.protocolReleaseID==protocolReference.releaseID} ?? true,seriesSHA256==(try MeasurementIntegrityCanonicalCodecV1.sha256(digestBasis)) else{throw MeasurementIntegrityFailureV1.invalidValue}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validate();try validate();let next=predecessor.revision.addingReportingOverflow(1);guard predecessor.state == .open,!next.overflow,revision==next.partialValue,seriesID==predecessor.seriesID,workspaceID==predecessor.workspaceID,protocolReference==predecessor.protocolReference,aggregationPolicy==predecessor.aggregationPolicy,supersedesSnapshotID==predecessor.snapshotID,recordedAt>=predecessor.recordedAt,samples.starts(with:predecessor.samples),expectedSampleCount==predecessor.expectedSampleCount else{throw MeasurementIntegrityFailureV1.immutableHistory}}
    func validateClosure(captures:[MeasurementCaptureV1],protocolRelease:MeasurementProtocolReleaseV1)throws{try validate();try protocolRelease.validate();let expectedProtocol=try MeasurementProtocolReferenceV1(protocolRelease);var byID:[UUID:MeasurementCaptureV1]=[:];for capture in captures{guard byID[capture.captureID]==nil else{throw MeasurementIntegrityFailureV1.duplicateIdentity};byID[capture.captureID]=capture};guard protocolRelease.workspaceID==workspaceID,protocolReference==expectedProtocol,expectedSampleCount>=protocolRelease.minimumSampleCount,expectedSampleCount<=protocolRelease.maximumSampleCount else{throw MeasurementIntegrityFailureV1.staleReference};for reference in samples{guard let capture=byID[reference.captureID],capture.workspaceID==workspaceID,capture.revision==reference.revision,capture.captureSHA256==reference.captureSHA256,capture.measurement.dimension==protocolRelease.dimension else{throw MeasurementIntegrityFailureV1.staleReference}}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(snapshotID:snapshotID,seriesID:seriesID,workspaceID:workspaceID,protocolReference:protocolReference,samples:samples,expectedSampleCount:expectedSampleCount,aggregationPolicy:aggregationPolicy,state:state,derivedFact:try derivedFact.map{try $0.rebound(to:workspaceID)},recordedAt:recordedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID)}
    private var digestBasis:DigestBasis{.init(schemaVersion:schemaVersion,snapshotID:snapshotID,seriesID:seriesID,workspaceID:workspaceID,protocolReference:protocolReference,samples:samples,expectedSampleCount:expectedSampleCount,observedSampleCount:observedSampleCount,aggregationPolicy:aggregationPolicy,state:state,derivedFact:derivedFact,recordedAt:recordedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID)}
    private struct DigestBasis:Codable{let schemaVersion:Int;let snapshotID:UUID;let seriesID:UUID;let workspaceID:WorkspaceID;let protocolReference:MeasurementProtocolReferenceV1;let samples:[MeasurementCaptureReferenceV1];let expectedSampleCount:Int;let observedSampleCount:Int;let aggregationPolicy:MeasurementAggregationPolicyV1;let state:MeasurementSeriesStateV1;let derivedFact:DerivedFactProvenanceV1?;let recordedAt:Date;let supersedesSnapshotID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct MeasurementQualityAssessmentV1:Codable,Equatable,Sendable,MeasurementIntegrityValidatableV1{
    static let schemaVersion=1
    let schemaVersion:Int;let assessmentID:UUID;let workspaceID:WorkspaceID;let subjectKind:MeasurementQualitySubjectKindV1;let subjectID:UUID;let subjectRevision:UInt64;let subjectSHA256:String
    let result:MeasurementQualityResultV1;let reasonCodes:[MeasurementQualityReasonV1];let policyVersion:String;let policySHA256:String
    let evidence:[ContentReferenceV1];let reviewer:ActorSnapshotV1?;let overrideRationale:String?;let assessedAt:Date
    let supersedesAssessmentID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let assessmentSHA256:String
    init(assessmentID:UUID,workspaceID:WorkspaceID,subjectKind:MeasurementQualitySubjectKindV1,subjectID:UUID,subjectRevision:UInt64,subjectSHA256:String,result:MeasurementQualityResultV1,reasonCodes:[MeasurementQualityReasonV1],policyVersion:String,policySHA256:String,evidence:[ContentReferenceV1]=[],reviewer:ActorSnapshotV1?=nil,overrideRationale:String?=nil,assessedAt:Date,supersedesAssessmentID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{let reasons=reasonCodes.sorted();let refs=evidence.sorted{$0.id<$1.id};schemaVersion=Self.schemaVersion;self.assessmentID=assessmentID;self.workspaceID=workspaceID;self.subjectKind=subjectKind;self.subjectID=subjectID;self.subjectRevision=subjectRevision;self.subjectSHA256=subjectSHA256;self.result=result;self.reasonCodes=reasons;self.policyVersion=policyVersion;self.policySHA256=policySHA256;self.evidence=refs;self.reviewer=reviewer;self.overrideRationale=overrideRationale;self.assessedAt=assessedAt;self.supersedesAssessmentID=supersedesAssessmentID;self.revision=revision;self.mutationID=mutationID;assessmentSHA256=try MeasurementIntegrityCanonicalCodecV1.sha256(DigestBasis(schemaVersion:Self.schemaVersion,assessmentID:assessmentID,workspaceID:workspaceID,subjectKind:subjectKind,subjectID:subjectID,subjectRevision:subjectRevision,subjectSHA256:subjectSHA256,result:result,reasonCodes:reasons,policyVersion:policyVersion,policySHA256:policySHA256,evidence:refs,reviewer:reviewer,overrideRationale:overrideRationale,assessedAt:assessedAt,supersedesAssessmentID:supersedesAssessmentID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try MeasurementIntegrityValidationV1.evidence(evidence,workspaceID:workspaceID);try reviewer?.validate();let positive:Set<MeasurementQualityReasonV1>=[.declaredChecksClear,.calibrationNotRequired];let reasons=Set(reasonCodes);let resultShape:Bool;switch result{case .clear:resultShape=reasons.isSubset(of:positive);case .reviewRequired:resultShape=!reasons.isSubset(of:positive)&&!reasons.contains(.humanOverride)&&reviewer==nil&&overrideRationale==nil;case .overridden:resultShape=reasons.contains(.humanOverride)&&reviewer != nil&&overrideRationale.map(MeasurementIntegrityValidationV1.text)==true&&supersedesAssessmentID != nil&&!evidence.isEmpty};guard schemaVersion==Self.schemaVersion,assessmentID != UUID.zero,subjectID != UUID.zero,subjectRevision>0,revision>0,(revision == 1)==(supersedesAssessmentID==nil),supersedesAssessmentID != assessmentID,MutationEnvelopeV1.isSHA256(subjectSHA256),MeasurementIntegrityValidationV1.token(policyVersion),MutationEnvelopeV1.isSHA256(policySHA256),!reasonCodes.isEmpty,reasonCodes.count<=MeasurementIntegrityLimitsV1.maximumReasonCount,reasonCodes==reasonCodes.sorted(),Set(reasonCodes).count==reasonCodes.count,resultShape,reviewer.map{$0.workspaceID==workspaceID && $0.responsibility == .reviewedBy} ?? true,assessmentSHA256==(try MeasurementIntegrityCanonicalCodecV1.sha256(digestBasis)) else{throw MeasurementIntegrityFailureV1.invalidValue}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validate();try validate();let next=predecessor.revision.addingReportingOverflow(1);guard !next.overflow,revision==next.partialValue,workspaceID==predecessor.workspaceID,subjectKind==predecessor.subjectKind,subjectID==predecessor.subjectID,subjectRevision==predecessor.subjectRevision,subjectSHA256==predecessor.subjectSHA256,supersedesAssessmentID==predecessor.assessmentID,assessedAt>=predecessor.assessedAt else{throw MeasurementIntegrityFailureV1.immutableHistory}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(assessmentID:assessmentID,workspaceID:workspaceID,subjectKind:subjectKind,subjectID:subjectID,subjectRevision:subjectRevision,subjectSHA256:subjectSHA256,result:result,reasonCodes:reasonCodes,policyVersion:policyVersion,policySHA256:policySHA256,evidence:try MeasurementIntegrityValidationV1.rebound(evidence,to:workspaceID),reviewer:try reviewer.map{try MeasurementIntegrityValidationV1.rebound($0,to:workspaceID)},overrideRationale:overrideRationale,assessedAt:assessedAt,supersedesAssessmentID:supersedesAssessmentID,revision:revision,mutationID:mutationID)}
    private var digestBasis:DigestBasis{.init(schemaVersion:schemaVersion,assessmentID:assessmentID,workspaceID:workspaceID,subjectKind:subjectKind,subjectID:subjectID,subjectRevision:subjectRevision,subjectSHA256:subjectSHA256,result:result,reasonCodes:reasonCodes,policyVersion:policyVersion,policySHA256:policySHA256,evidence:evidence,reviewer:reviewer,overrideRationale:overrideRationale,assessedAt:assessedAt,supersedesAssessmentID:supersedesAssessmentID,revision:revision,mutationID:mutationID)}
    private struct DigestBasis:Codable{let schemaVersion:Int;let assessmentID:UUID;let workspaceID:WorkspaceID;let subjectKind:MeasurementQualitySubjectKindV1;let subjectID:UUID;let subjectRevision:UInt64;let subjectSHA256:String;let result:MeasurementQualityResultV1;let reasonCodes:[MeasurementQualityReasonV1];let policyVersion:String;let policySHA256:String;let evidence:[ContentReferenceV1];let reviewer:ActorSnapshotV1?;let overrideRationale:String?;let assessedAt:Date;let supersedesAssessmentID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct InstallationPlanReferenceV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let planID:UUID;let planVersion:UInt64;let planSHA256:String;let measurementSubjectID:UUID;let measurementSubjectRevision:UInt64;let measurementSubjectSHA256:String;init(workspaceID:WorkspaceID,planID:UUID,planVersion:UInt64,planSHA256:String,measurementSubjectID:UUID,measurementSubjectRevision:UInt64,measurementSubjectSHA256:String)throws{self.workspaceID=workspaceID;self.planID=planID;self.planVersion=planVersion;self.planSHA256=planSHA256;self.measurementSubjectID=measurementSubjectID;self.measurementSubjectRevision=measurementSubjectRevision;self.measurementSubjectSHA256=measurementSubjectSHA256;try validate()}func validate()throws{guard planID != UUID.zero,measurementSubjectID != UUID.zero,planVersion>0,measurementSubjectRevision>0,MutationEnvelopeV1.isSHA256(planSHA256),MutationEnvelopeV1.isSHA256(measurementSubjectSHA256)else{throw MeasurementIntegrityFailureV1.invalidValue}}}
struct PunchPlanReferenceV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let planID:UUID;let planVersion:UInt64;let planSHA256:String;let measurementSubjectID:UUID;let measurementSubjectRevision:UInt64;let measurementSubjectSHA256:String;init(workspaceID:WorkspaceID,planID:UUID,planVersion:UInt64,planSHA256:String,measurementSubjectID:UUID,measurementSubjectRevision:UInt64,measurementSubjectSHA256:String)throws{self.workspaceID=workspaceID;self.planID=planID;self.planVersion=planVersion;self.planSHA256=planSHA256;self.measurementSubjectID=measurementSubjectID;self.measurementSubjectRevision=measurementSubjectRevision;self.measurementSubjectSHA256=measurementSubjectSHA256;try validate()}func validate()throws{guard planID != UUID.zero,measurementSubjectID != UUID.zero,planVersion>0,measurementSubjectRevision>0,MutationEnvelopeV1.isSHA256(planSHA256),MutationEnvelopeV1.isSHA256(measurementSubjectSHA256)else{throw MeasurementIntegrityFailureV1.invalidValue}}}

enum MeasurementQualityEvaluatorV1{
    static func reasons(capture:MeasurementCaptureV1,calibration:CalibrationStatusSnapshotV1?,requiresUncertainty:Bool)throws->[MeasurementQualityReasonV1]{try capture.validate();switch capture.sourceMode{case .manualEntry:guard calibration==nil,capture.calibration==nil else{throw MeasurementIntegrityFailureV1.staleReference};case .localObservation:guard let calibration,calibration.workspaceID==capture.workspaceID,let frozen=capture.calibration,frozen == (try CalibrationSnapshotReferenceV1(calibration)),calibration.instrument==capture.instrument else{throw MeasurementIntegrityFailureV1.staleReference}};var reasons:Set<MeasurementQualityReasonV1>=[];if !capture.observationBasis.limitations.isEmpty{reasons.insert(.observationLimitation)};if requiresUncertainty && capture.measurement.uncertaintyCanonical==nil{reasons.insert(.missingUncertainty)};if capture.sourceMode == .localObservation,let calibration{switch calibration.status{case .notRequired:reasons.insert(.calibrationNotRequired);case .current:break;case .expired:reasons.insert(.calibrationExpired);case .unknown:reasons.insert(.calibrationUnknown);case .outOfService:reasons.insert(.instrumentOutOfService)}};if reasons.isEmpty{reasons.insert(.declaredChecksClear)};return reasons.sorted()}
    static func result(for reasons:[MeasurementQualityReasonV1])->MeasurementQualityResultV1{Set(reasons).isSubset(of:[.declaredChecksClear,.calibrationNotRequired]) ? .clear : .reviewRequired}
    static func assessCapture(assessmentID:UUID,capture:MeasurementCaptureV1,calibration:CalibrationStatusSnapshotV1?,requiresUncertainty:Bool,policyVersion:String,policySHA256:String,evidence:[ContentReferenceV1]=[],assessedAt:Date,mutationID:MutationIDV1)throws->MeasurementQualityAssessmentV1{let reasons=try reasons(capture:capture,calibration:calibration,requiresUncertainty:requiresUncertainty);return try .init(assessmentID:assessmentID,workspaceID:capture.workspaceID,subjectKind:.capture,subjectID:capture.captureID,subjectRevision:capture.revision,subjectSHA256:capture.captureSHA256,result:result(for:reasons),reasonCodes:reasons,policyVersion:policyVersion,policySHA256:policySHA256,evidence:evidence,assessedAt:assessedAt,mutationID:mutationID)}
}

enum MeasurementSeriesEvaluatorV1{
    static func aggregate(policy:MeasurementAggregationPolicyV1,captures:[MeasurementCaptureV1])throws->ExactMeasurementV1?{guard policy != .none else{return nil};guard let first=captures.first,!captures.isEmpty,Set(captures.map(\.captureID)).count==captures.count else{throw MeasurementIntegrityFailureV1.incompleteSeries};try captures.forEach{try $0.validate()};let scale=first.measurement.canonicalValue.scale;guard captures.allSatisfy({$0.measurement.dimension==first.measurement.dimension && $0.measurement.canonicalUnitID==first.measurement.canonicalUnitID && $0.measurement.canonicalValue.scale==scale})else{throw MeasurementIntegrityFailureV1.invalidValue};let values=captures.map{$0.measurement.canonicalValue.mantissa}.sorted();let mantissa:Int64;switch policy{case .none:return nil;case .minimum:mantissa=values[0];case .maximum:mantissa=values[values.count-1];case .mean:var total:Int64=0;for value in values{total=try ExactIntegerMathV1.add(total,value)};mantissa=try ExactUnitConverterV1.rounded(numerator:total,denominator:Int64(values.count),targetScale:scale).canonicalValue.mantissa;case .median:let middle=values.count/2;if values.count.isMultiple(of:2){let total=try ExactIntegerMathV1.add(values[middle-1],values[middle]);mantissa=try ExactUnitConverterV1.rounded(numerator:total,denominator:2,targetScale:scale).canonicalValue.mantissa}else{mantissa=values[middle]}};var uncertainty:ExactDecimalV1?;for value in captures.compactMap({$0.measurement.uncertaintyCanonical}){if let current=uncertainty{if try value.compared(to:current) == .orderedDescending{uncertainty=value}}else{uncertainty=value}};return try ExactMeasurementV1(enteredValue:ExactDecimalV1(mantissa:mantissa,scale:scale),enteredUnitID:first.measurement.canonicalUnitID,precisionScale:scale,uncertaintyCanonical:uncertainty,source:.derived,captureMethodID:"measurement.series.\(policy.rawValue.lowercased()).v1")}
    static func finalized(snapshotID:UUID,seriesID:UUID,workspaceID:WorkspaceID,protocolRelease:MeasurementProtocolReleaseV1,evaluator:DerivedFactEvaluatorDescriptorV1,captures:[MeasurementCaptureV1],expectedSampleCount:Int,aggregationPolicy:MeasurementAggregationPolicyV1 = .mean,provenanceID:UUID,recordedAt:Date,supersedes:MeasurementSeriesV1?,mutationID:MutationIDV1)throws->MeasurementSeriesV1{let ordered=captures;guard aggregationPolicy == .mean,ordered.count==expectedSampleCount,Set(ordered.map(\.captureID)).count==ordered.count,ordered.allSatisfy({$0.workspaceID==workspaceID}),evaluator.kind == .arithmeticMeanCanonical else{throw MeasurementIntegrityFailureV1.incompleteSeries};let expectedAggregate=try aggregate(policy:aggregationPolicy,captures:ordered);let inputs=try ordered.enumerated().map{try DerivedFactInputV1(sampleID:$0.element.captureID,sampleOrdinal:$0.offset+1,state:.present,measurement:$0.element.measurement)};let provenance=try DeterministicDerivedFactEvaluatorV1.evaluate(provenanceID:provenanceID,workspaceID:workspaceID,protocolRelease:protocolRelease,evaluator:evaluator,inputs:inputs,recordedAt:recordedAt);guard let actual=provenance.result,let expectedAggregate,actual.canonicalValue==expectedAggregate.canonicalValue,actual.canonicalUnitID==expectedAggregate.canonicalUnitID,actual.dimension==expectedAggregate.dimension,actual.uncertaintyCanonical==expectedAggregate.uncertaintyCanonical else{throw MeasurementIntegrityFailureV1.digestMismatch};let refs=try ordered.enumerated().map{try MeasurementCaptureReferenceV1(captureID:$0.element.captureID,revision:$0.element.revision,captureSHA256:$0.element.captureSHA256,sampleOrdinal:$0.offset+1)};let previousRevision=supersedes?.revision ?? 0;let next=previousRevision.addingReportingOverflow(1);guard !next.overflow else{throw MeasurementIntegrityFailureV1.invalidValue};return try .init(snapshotID:snapshotID,seriesID:seriesID,workspaceID:workspaceID,protocolReference:MeasurementProtocolReferenceV1(protocolRelease),samples:refs,expectedSampleCount:expectedSampleCount,aggregationPolicy:aggregationPolicy,state:.finalized,derivedFact:provenance,recordedAt:recordedAt,supersedesSnapshotID:supersedes?.snapshotID,revision:next.partialValue,mutationID:mutationID)}
}

enum MeasurementIntegrityCanonicalCodecV1{
    static func encode<T:Encodable>(_ value:T)throws->Data{try WorkspaceMutationCanonicalV1.data(value)}
    static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}
    static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=MeasurementIntegrityLimitsV1.maximumCanonicalBytes else{throw MeasurementIntegrityFailureV1.limitExceeded};let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;let value=try decoder.decode(type,from:data);if let validatable=value as? any MeasurementIntegrityValidatableV1{try validatable.validate()};guard try encode(value)==data else{throw MeasurementIntegrityFailureV1.nonCanonicalData};return value}
}

enum MeasurementIntegrityForwardFixPolicyV1{static let schemaGeneration=18;static func requireForwardFix(afterFirstWrite hasWrittenV18:Bool,requestedGeneration:Int)throws{guard !hasWrittenV18 || requestedGeneration>=schemaGeneration else{throw MeasurementIntegrityFailureV1.invalidTransition}}}

enum MeasurementIntegrityValidationV1{
    static func text(_ value:String)->Bool{!value.isEmpty && value==value.trimmingCharacters(in:.whitespacesAndNewlines) && value.utf8.count<=MeasurementIntegrityLimitsV1.maximumTextBytes}
    static func token(_ value:String)->Bool{ResponseIdentifierValidationV1.valid(value)}
    static func evidence(_ values:[ContentReferenceV1],workspaceID:WorkspaceID)throws{guard values.count<=MeasurementIntegrityLimitsV1.maximumEvidenceCount,values==values.sorted(by:{$0.id<$1.id}),Set(values.map(\.id)).count==values.count,values.allSatisfy({$0.workspaceID==workspaceID.rawValue.uuidString.lowercased()})else{throw MeasurementIntegrityFailureV1.wrongWorkspace}}
    static func rebound(_ values:[ContentReferenceV1],to workspaceID:WorkspaceID)throws->[ContentReferenceV1]{try values.map{try ContentReferenceV1(workspaceID:workspaceID.rawValue.uuidString.lowercased(),contentID:$0.contentID,byteLength:$0.byteLength,mediaType:$0.mediaType,digests:$0.digests,byteRole:$0.byteRole,createdAt:$0.createdAt)}}
    static func rebound(_ value:ActorSnapshotV1,to workspaceID:WorkspaceID)throws->ActorSnapshotV1{let actor=try LocalActorReferenceV1(actorReferenceID:value.actor.actorReferenceID,workspaceID:workspaceID,partyID:value.actor.partyID,displayName:value.actor.displayName);return try ActorSnapshotV1(snapshotID:value.snapshotID,workspaceID:workspaceID,actor:actor,responsibility:value.responsibility,displayNameAtTime:value.displayNameAtTime,capturedAt:value.capturedAt)}
}

private extension UUID { static let zero = UUID(uuidString:"00000000-0000-0000-0000-000000000000")! }

enum C53SharedMeasurementEvidenceBoundaryV1 {
    static let measurementCaptureType: MeasurementCaptureV1.Type = MeasurementCaptureV1.self
    static let metricInputType: ReliabilityMetricInputProjectionV1.Type = ReliabilityMetricInputProjectionV1.self
    static let measurementCapturesRemainEvidenceInputs = true
    static let explicitObservationBasisAndTimeAreRetained = true
    static let unqualifiedCaptureCannotSatisfyServiceExposure = true
    static let fixedPointDigestAndRevisionSemanticsRemainC19 = true
    static let noHardwareIoTOrPredictiveProviderIsIntroduced = true
    static let sourceContractNames = C53SharedServiceReliabilitySemanticBoundaryV1.contractNames
}
