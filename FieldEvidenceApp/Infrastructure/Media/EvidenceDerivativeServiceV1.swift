import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum EvidenceDerivativeServiceFailureV1: Error, Equatable, Sendable {
    case invalidRequest
    case limitExceeded
    case missingSource
    case tombstonedSource
    case protectedDataUnavailable
    case interrupted
    case replayDiverged
}

enum EvidenceDerivativeMediaBoundsV1 {
    static let maximumDerivativeBytes = 24 * 1_048_576
    static let maximumTotalRendererSourceBytes: Int64 = 256 * 1_048_576
    static let maximumCanvasEdge = 2_048
    static let maximumCanvasPixels = maximumCanvasEdge * maximumCanvasEdge
    static let flickerCanvasEdge = 512
}

enum EvidenceDerivativePlanV1: Codable, Equatable, Sendable {
    case markup(EvidenceReviewedMarkupPlanV1)
    case sequence(EvidenceSequencePlanV1)

    var workspaceID: WorkspaceID {
        switch self {
        case .markup(let plan): return plan.workspaceID
        case .sequence(let plan): return plan.workspaceID
        }
    }

    var requestSHA256: String {
        switch self {
        case .markup(let plan): return plan.planSHA256
        case .sequence(let plan): return plan.planSHA256
        }
    }

    /// Markup consumes only C20's reviewed privacy derivative. The immutable
    /// original remains association authority but is never fed to the markup
    /// renderer/publication path.
    var renderSources: [ContentReferenceV1] {
        switch self {
        case .markup(let plan): return [plan.privacyManifest.derivative]
        case .sequence(let plan): return plan.orderedSources
        }
    }

    var associationSources: [ContentReferenceV1] {
        switch self {
        case .markup(let plan): return [plan.source]
        case .sequence(let plan): return plan.orderedSources
        }
    }

    func validate() throws {
        switch self {
        case .markup(let plan): try plan.validate()
        case .sequence(let plan): try plan.validate()
        }
    }
}

struct EvidenceDerivativePublicationCommandV1: Sendable {
    let operationID: String
    let plan: EvidenceDerivativePlanV1
    let derivativeBytes: Data
    let derivative: ContentReferenceV1
    let provenance: ContentDerivativeProvenanceV1
    let associationHistory: [EvidenceAssociationV1]
    let currentSequence: EvidenceSequenceV1?
    let metadataMutation: EvidenceMetadataMutationV1

    var derivativeAssociation: EvidenceAssociationV1 { metadataMutation.associationEvent }

    init(
        operationID: String,
        plan: EvidenceDerivativePlanV1,
        derivativeBytes: Data,
        derivative: ContentReferenceV1,
        provenance: ContentDerivativeProvenanceV1,
        associationHistory: [EvidenceAssociationV1],
        currentSequence: EvidenceSequenceV1?,
        metadataMutation: EvidenceMetadataMutationV1
    ) throws {
        guard ContentContractValidationV1.validID(operationID),
              associationHistory.count <= ContentContractLimitsV1.maximumAssociations,
              plan.renderSources.count <= ContentContractLimitsV1.maximumProvenanceSources,
              derivative.byteLength >= 0,
              derivative.byteLength <= Int64(EvidenceDerivativeMediaBoundsV1.maximumDerivativeBytes),
              derivativeBytes.count <= EvidenceDerivativeMediaBoundsV1.maximumDerivativeBytes,
              Int64(derivativeBytes.count) == derivative.byteLength else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        try plan.validate()
        try metadataMutation.validate()
        try currentSequence?.validate()
        let canonical: Data
        switch plan {
        case .markup(let value):
            canonical = try EvidenceCurationCanonicalCodecV1.encode(value)
        case .sequence(let value):
            canonical = try EvidenceCurationCanonicalCodecV1.encode(value)
        }
        guard canonical.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        let result = try EvidenceCurationDerivativeResultV1(
            requestSHA256: plan.requestSHA256,
            derivative: derivative,
            provenance: provenance,
            orderedSources: plan.renderSources
        )
        let derivativeAssociation = metadataMutation.associationEvent
        let sequenceSuccessor = metadataMutation.sequenceSuccessor
        let workspace = plan.workspaceID.rawValue.uuidString.lowercased()
        guard result.derivative.workspaceID == workspace,
              metadataMutation.workspaceID == plan.workspaceID,
              derivativeAssociation.workspaceID == workspace,
              derivativeAssociation.contentID == result.derivative.contentID,
              derivativeAssociation.target == sequenceSuccessor.target,
              derivativeAssociation.action != .removed,
              sequenceSuccessor.orderedItems.filter({
                  $0.evidenceID == derivativeAssociation.evidenceID
                    && $0.contentID == derivative.contentID
              }).count == 1 else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        try EvidenceAssociationLedgerV1.validate(associationHistory + [derivativeAssociation])
        let priorAssociation = associationHistory.last {
            $0.evidenceID == derivativeAssociation.evidenceID
        }
        switch derivativeAssociation.action {
        case .assigned:
            guard priorAssociation == nil,
                  derivativeAssociation.expectedEvidenceRevision == 0,
                  currentSequence?.orderedItems.contains(where: {
                      $0.evidenceID == derivativeAssociation.evidenceID
                  }) != true else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
        case .reassigned:
            guard let priorAssociation,
                  Set(plan.associationSources.map(\.contentID)).contains(priorAssociation.contentID ?? ""),
                  derivativeAssociation.previousContentID == priorAssociation.contentID,
                  currentSequence?.orderedItems.contains(where: {
                      $0.evidenceID == derivativeAssociation.evidenceID
                        && $0.contentID == priorAssociation.contentID
                  }) == true else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
            try derivativeAssociation.validateSuccessor(of: priorAssociation)
        case .removed:
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        if let currentSequence {
            guard metadataMutation.expectedSequenceRevision == currentSequence.revision,
                  sequenceSuccessor.policy == currentSequence.policy else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
            try sequenceSuccessor.validateSuccessor(of: currentSequence)
            try Self.validateSequenceMetadataPreservation(
                current: currentSequence,
                successor: sequenceSuccessor,
                derivativeAssociation: derivativeAssociation
            )
        } else {
            guard metadataMutation.expectedSequenceRevision == 0,
                  sequenceSuccessor.predecessor == nil,
                  sequenceSuccessor.revision == 1 else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
        }
        if case let .sequence(sequencePlan) = plan {
            guard currentSequence == sequencePlan.metadataSequence else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
        }
        self.operationID = operationID
        self.plan = plan
        self.derivativeBytes = derivativeBytes
        self.derivative = derivative
        self.provenance = provenance
        self.associationHistory = associationHistory
        self.currentSequence = currentSequence
        self.metadataMutation = metadataMutation
    }

    private static func validateSequenceMetadataPreservation(
        current: EvidenceSequenceV1,
        successor: EvidenceSequenceV1,
        derivativeAssociation: EvidenceAssociationV1
    ) throws {
        let evidenceID = derivativeAssociation.evidenceID
        let priorItems = current.orderedItems.filter { $0.evidenceID != evidenceID }
        let resultingItems = successor.orderedItems.filter { $0.evidenceID != evidenceID }
        guard priorItems.count == resultingItems.count else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        for (prior, resulting) in zip(priorItems, resultingItems) {
            guard prior.evidenceID == resulting.evidenceID,
                  prior.contentID == resulting.contentID,
                  prior.role == resulting.role,
                  prior.caption == resulting.caption,
                  prior.accessibilityDescription == resulting.accessibilityDescription,
                  prior.target == resulting.target,
                  prior.associationBinding == resulting.associationBinding else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
        }
        if derivativeAssociation.action == .reassigned,
           let prior = current.orderedItems.first(where: { $0.evidenceID == evidenceID }),
           let resulting = successor.orderedItems.first(where: { $0.evidenceID == evidenceID }) {
            guard prior.role == resulting.role,
                  prior.caption == resulting.caption,
                  prior.accessibilityDescription == resulting.accessibilityDescription,
                  prior.ordinal == resulting.ordinal,
                  prior.target == resulting.target else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
        }
    }
}

struct EvidenceDerivativeCancellationV1: Sendable {
    static let never = EvidenceDerivativeCancellationV1 { false }
    private let source: @Sendable () -> Bool
    init(_ source: @escaping @Sendable () -> Bool) { self.source = source }
    var isCancelled: Bool { source() }
}

enum EvidenceDerivativePublicationDispositionV1: String, Codable, Equatable, Sendable {
    case published = "PUBLISHED"
    case adopted = "ADOPTED"
}

struct EvidenceDerivativePublicationReceiptV1: Equatable, Sendable {
    let disposition: EvidenceDerivativePublicationDispositionV1
    let operation: EvidenceCurationOperationReceiptV1
    let result: EvidenceCurationDerivativeResultV1
    let canonicalMutationReceiptSHA256: String
}

struct EvidenceDerivativeContentPublicationReceiptV1: Equatable, Sendable {
    let disposition: EvidenceDerivativePublicationDispositionV1
    let result: EvidenceCurationDerivativeResultV1
}

protocol EvidenceDerivativeCanonicalCommittingV1: Sendable {
    func commitDerivativeMetadata(
        _ mutation: EvidenceMetadataMutationV1
    ) async throws -> EvidenceMetadataMutationReceiptV1
    func receipt(
        for mutation: EvidenceMetadataMutationV1
    ) async throws -> EvidenceMetadataMutationReceiptV1?
}

@MainActor
final class WorkspaceEvidenceDerivativeCanonicalCommitterV1:
    EvidenceDerivativeCanonicalCommittingV1 {
    private let writer: WorkspaceWriterV1

    init(writer: WorkspaceWriterV1) { self.writer = writer }

    func commitDerivativeMetadata(
        _ mutation: EvidenceMetadataMutationV1
    ) async throws -> EvidenceMetadataMutationReceiptV1 {
        try writer.commitEvidenceMetadata(mutation)
    }

    func receipt(
        for mutation: EvidenceMetadataMutationV1
    ) async throws -> EvidenceMetadataMutationReceiptV1? {
        try writer.evidenceMetadataReceipt(for: mutation)
    }
}

struct EvidenceDerivativeStorePackageV1: Sendable {
    let operationID: String
    let workspaceID: WorkspaceID
    let requestSHA256: String
    let orderedSources: [ContentReferenceV1]
    let derivativeBytes: Data
    let result: EvidenceCurationDerivativeResultV1
    let metadataMutation: EvidenceMetadataMutationV1
}

struct EvidenceDerivativePublicationMarkerV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let operationID: String
    let workspaceID: WorkspaceID
    let requestSHA256: String
    let orderedSources: [ContentReferenceV1]
    let result: EvidenceCurationDerivativeResultV1
    let metadataMutation: EvidenceMetadataMutationV1
    let operation: EvidenceCurationOperationReceiptV1

    init(package: EvidenceDerivativeStorePackageV1) throws {
        schemaVersion = Self.schemaVersion
        operationID = package.operationID
        workspaceID = package.workspaceID
        requestSHA256 = package.requestSHA256
        orderedSources = package.orderedSources
        result = package.result
        metadataMutation = package.metadataMutation
        operation = try EvidenceCurationOperationReceiptV1(
            operationID: package.operationID,
            workspaceID: package.workspaceID,
            requestSHA256: package.requestSHA256,
            state: .planned,
            resultSHA256: nil
        )
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              orderedSources.count <= ContentContractLimitsV1.maximumProvenanceSources,
              metadataMutation.workspaceID == workspaceID,
              metadataMutation.associationEvent.contentID == result.derivative.contentID,
              result == (try EvidenceCurationDerivativeResultV1(
                requestSHA256: requestSHA256,
                derivative: result.derivative,
                provenance: result.provenance,
                orderedSources: orderedSources
              )),
              operation.operationID == operationID,
              operation.workspaceID == workspaceID,
              operation.requestSHA256 == requestSHA256,
              operation.state == .planned,
              operation.resultSHA256 == nil,
              operation.metadataReceipt == nil,
              operation.canonicalMutationReceiptSHA256 == nil else {
            throw EvidenceDerivativeServiceFailureV1.replayDiverged
        }
        try metadataMutation.validate()
    }
}

actor EvidenceDerivativeServiceV1: EvidenceCurationContentResolvingV1 {
    private let store: EvidenceBundleStore
    private let canonicalCommitter: any EvidenceDerivativeCanonicalCommittingV1

    init(
        store: EvidenceBundleStore,
        canonicalCommitter: any EvidenceDerivativeCanonicalCommittingV1
    ) {
        self.store = store
        self.canonicalCommitter = canonicalCommitter
    }

    func resolve(_ reference: ContentReferenceV1) async throws -> ContentReferenceV1? {
        try await store.resolveContentReference(reference)
    }

    func publish(
        _ command: EvidenceDerivativePublicationCommandV1,
        cancellation: EvidenceDerivativeCancellationV1 = .never
    ) async throws -> EvidenceDerivativePublicationReceiptV1 {
        if cancellation.isCancelled { throw EvidenceDerivativeServiceFailureV1.interrupted }
        try command.plan.validate()
        try validateActiveAssociations(
            command.associationHistory,
            sources: command.plan.associationSources,
            workspaceID: command.plan.workspaceID
        )
        var totalSourceBytes: Int64 = 0
        for source in command.plan.renderSources {
            let (next, overflow) = totalSourceBytes.addingReportingOverflow(source.byteLength)
            guard source.byteLength > 0,
                  source.byteLength <= Int64(MediaContractV1.sourceByteCountMaximum),
                  !overflow,
                  next <= EvidenceDerivativeMediaBoundsV1.maximumTotalRendererSourceBytes else {
                throw EvidenceDerivativeServiceFailureV1.limitExceeded
            }
            totalSourceBytes = next
        }
        var sourceBytes: [Data] = []
        sourceBytes.reserveCapacity(command.plan.renderSources.count)
        for source in command.plan.renderSources {
            if cancellation.isCancelled { throw EvidenceDerivativeServiceFailureV1.interrupted }
            guard try await store.resolveContentReference(source) == source else {
                throw EvidenceDerivativeServiceFailureV1.missingSource
            }
            sourceBytes.append(try await store.readEvidenceDerivativeSource(source))
        }
        let rendered = try Self.renderDeterministically(command.plan, sourceBytes: sourceBytes)
        guard command.derivative.mediaType == "image/png",
              rendered == command.derivativeBytes else {
            if try await store.evidenceDerivativePublicationExists(
                workspaceID: command.plan.workspaceID,
                contentID: command.derivative.contentID
            ) {
                throw EvidenceDerivativeServiceFailureV1.replayDiverged
            }
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        guard let digest = command.derivative.digests.digest(for: .sha256),
              KernelCanonicalHashV1.sha256(rendered) == digest.hexadecimalValue,
              Int64(rendered.count) == command.derivative.byteLength else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        let result = try EvidenceCurationDerivativeResultV1(
            requestSHA256: command.plan.requestSHA256,
            derivative: command.derivative,
            provenance: command.provenance,
            orderedSources: command.plan.renderSources
        )
        if cancellation.isCancelled { throw EvidenceDerivativeServiceFailureV1.interrupted }
        let content = try await store.publishOrAdoptEvidenceDerivative(
            EvidenceDerivativeStorePackageV1(
                operationID: command.operationID,
                workspaceID: command.plan.workspaceID,
                requestSHA256: command.plan.requestSHA256,
                orderedSources: command.plan.renderSources,
                derivativeBytes: command.derivativeBytes,
                result: result,
                metadataMutation: command.metadataMutation
            ),
            cancellation: cancellation
        )
        if cancellation.isCancelled { throw EvidenceDerivativeServiceFailureV1.interrupted }
        let metadataReceipt: EvidenceMetadataMutationReceiptV1
        if let existing = try await canonicalCommitter.receipt(for: command.metadataMutation) {
            metadataReceipt = existing
        } else {
            metadataReceipt = try await canonicalCommitter.commitDerivativeMetadata(
                command.metadataMutation
            )
        }
        try metadataReceipt.validate()
        let expectedImages = try command.metadataMutation.mutationPostImages
        let expectedKinds = Set(try expectedImages.map { try $0.identity.kind })
        let expectedAffected = try command.metadataMutation.affectedIdentities
        let expectedConcurrency = try command.metadataMutation.concurrencyIdentities
        let expectedCommandSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyEvidenceMetadata(command.metadataMutation)
        )
        guard metadataReceipt.mutationReceipt.postImages == expectedImages,
              metadataReceipt.mutationSHA256 == (try command.metadataMutation.canonicalSHA256()),
              metadataReceipt.affectedIdentities == expectedAffected,
              metadataReceipt.concurrencyIdentities == expectedConcurrency,
              metadataReceipt.mutationReceipt.mutationID == command.metadataMutation.mutationID,
              metadataReceipt.mutationReceipt.identity.workspaceID == command.metadataMutation.workspaceID,
              metadataReceipt.mutationReceipt.commandBodySHA256 == expectedCommandSHA256,
              expectedImages.count == 2,
              expectedKinds == Set([.evidenceAssociationEvent, .evidenceSequenceRevision]) else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        let completion = EvidenceDerivativeCanonicalCompletionV1(
            result: result,
            metadataMutationSHA256: try command.metadataMutation.canonicalSHA256(),
            canonicalMutationReceiptSHA256: try WorkspaceMutationCanonicalV1.sha256(metadataReceipt)
        )
        let operation = try EvidenceCurationOperationReceiptV1(
            operationID: command.operationID,
            workspaceID: command.plan.workspaceID,
            requestSHA256: command.plan.requestSHA256,
            state: .completed,
            resultSHA256: try EvidenceCurationCanonicalCodecV1.sha256(completion),
            metadataReceipt: metadataReceipt
        )
        guard let canonicalMutationReceiptSHA256 = operation.canonicalMutationReceiptSHA256,
              canonicalMutationReceiptSHA256
                == (try WorkspaceMutationCanonicalV1.sha256(metadataReceipt)) else {
            throw EvidenceDerivativeServiceFailureV1.replayDiverged
        }
        return EvidenceDerivativePublicationReceiptV1(
            disposition: content.disposition,
            operation: operation,
            result: result,
            canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256
        )
    }

    static func renderDeterministically(
        _ plan: EvidenceDerivativePlanV1,
        sourceBytes: [Data]
    ) throws -> Data {
        try plan.validate()
        guard sourceBytes.count == plan.renderSources.count else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        return try EvidenceDerivativePNGRendererV1.render(plan: plan, sourceBytes: sourceBytes)
    }

    private func validateActiveAssociations(
        _ events: [EvidenceAssociationV1],
        sources: [ContentReferenceV1],
        workspaceID: WorkspaceID
    ) throws {
        guard events.count <= ContentContractLimitsV1.maximumAssociations else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        try EvidenceAssociationLedgerV1.validate(events)
        let workspace = workspaceID.rawValue.uuidString.lowercased()
        guard events.allSatisfy({ $0.workspaceID == workspace }) else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        var terminal: [String: EvidenceAssociationV1] = [:]
        for event in events { terminal[event.evidenceID] = event }
        for source in sources {
            let matches = terminal.values.filter { $0.contentID == source.contentID }
            guard !matches.isEmpty else {
                if terminal.values.contains(where: { $0.previousContentID == source.contentID && $0.action == .removed }) {
                    throw EvidenceDerivativeServiceFailureV1.tombstonedSource
                }
                throw EvidenceDerivativeServiceFailureV1.missingSource
            }
        }
    }
}

private struct EvidenceDerivativeCanonicalCompletionV1: Codable {
    let result: EvidenceCurationDerivativeResultV1
    let metadataMutationSHA256: String
    let canonicalMutationReceiptSHA256: String
}

private enum EvidenceDerivativePNGRendererV1 {
    private static let maximumCanvasEdge = EvidenceDerivativeMediaBoundsV1.maximumCanvasEdge
    private static let maximumCanvasPixels = EvidenceDerivativeMediaBoundsV1.maximumCanvasPixels
    private static let maximumDerivativeBytes = EvidenceDerivativeMediaBoundsV1.maximumDerivativeBytes
    private static let flickerCanvasEdge = EvidenceDerivativeMediaBoundsV1.flickerCanvasEdge
    private static let bytesPerPixel = 4
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var entry = UInt32(value)
        for _ in 0..<8 {
            entry = (entry & 1) == 1 ? (entry >> 1) ^ 0xedb8_8320 : entry >> 1
        }
        return entry
    }

    private struct Raster {
        let width: Int
        let height: Int
        let pixels: Data
    }

    static func render(plan: EvidenceDerivativePlanV1, sourceBytes: [Data]) throws -> Data {
        let data: Data
        switch plan {
        case .markup(let value):
            guard sourceBytes.count == 1, let source = sourceBytes.first else {
                throw EvidenceDerivativeServiceFailureV1.invalidRequest
            }
            data = try renderMarkup(value, sourceData: source)
        case .sequence(let value):
            switch value.kind {
            case .contactSheet:
                data = try renderContactSheet(value, sourceData: sourceBytes)
            case .flicker:
                data = try renderFlicker(value, sourceData: sourceBytes)
            }
        }
        guard data.count <= maximumDerivativeBytes,
              data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        return data
    }

    private static func renderMarkup(
        _ plan: EvidenceReviewedMarkupPlanV1,
        sourceData: Data
    ) throws -> Data {
        let image = try decodeStillImage(sourceData, maximumEdge: maximumCanvasEdge)
        let annotationLines = plan.reviewedMarkup.orderedAnnotations.enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }
        let lines = annotationLines
        let rowHeight = 24
        let panelHeight = min(maximumCanvasEdge - 1, lines.count * rowHeight + (lines.isEmpty ? 0 : 16))
        let availableImageHeight = max(1, maximumCanvasEdge - panelHeight)
        let scale = min(
            1,
            min(
                Double(maximumCanvasEdge) / Double(image.width),
                Double(availableImageHeight) / Double(image.height)
            )
        )
        let imageWidth = max(1, Int((Double(image.width) * scale).rounded(.down)))
        let imageHeight = max(1, Int((Double(image.height) * scale).rounded(.down)))
        let canvasWidth = max(min(maximumCanvasEdge, max(imageWidth, lines.isEmpty ? 1 : 640)), 1)
        let canvasHeight = imageHeight + panelHeight
        let raster = try makeRaster(width: canvasWidth, height: canvasHeight) { context in
            fill(context, rect: CGRect(
                x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)
            ), gray: 1)
            drawAspectFit(
                image,
                in: context,
                rect: CGRect(
                    x: 0,
                    y: CGFloat(panelHeight),
                    width: CGFloat(canvasWidth),
                    height: CGFloat(imageHeight)
                )
            )
            guard !lines.isEmpty else { return }
            fill(context, rect: CGRect(
                x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(panelHeight)
            ), gray: 0.08)
            let fontSize = CGFloat(14)
            for (index, line) in lines.enumerated() {
                let baseline = CGFloat(panelHeight - 12 - index * rowHeight)
                guard baseline >= 4 else { break }
                let accent = CGColor(red: 1, green: 0.72, blue: 0.12, alpha: 1)
                context.setStrokeColor(accent)
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: 10, y: baseline - 7, width: 12, height: 12))
                context.move(to: CGPoint(x: 24, y: baseline - 1))
                context.addLine(to: CGPoint(x: 39, y: baseline - 1))
                context.addLine(to: CGPoint(x: 34, y: baseline + 4))
                context.move(to: CGPoint(x: 39, y: baseline - 1))
                context.addLine(to: CGPoint(x: 34, y: baseline - 6))
                context.strokePath()
                drawText(
                    String(line.prefix(240)),
                    in: context,
                    at: CGPoint(x: 46, y: baseline - 6),
                    fontSize: fontSize,
                    color: CGColor(gray: 1, alpha: 1)
                )
            }
        }
        return try encodePNG(raster)
    }

    private static func renderContactSheet(
        _ plan: EvidenceSequencePlanV1,
        sourceData: [Data]
    ) throws -> Data {
        guard let columns = plan.contactSheetColumns,
              sourceData.count == plan.orderedSources.count else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        let rows = (sourceData.count + columns - 1) / columns
        let cellEdge = max(1, min(512, maximumCanvasEdge / max(columns, rows)))
        let images = try sourceData.map { try decodeStillImage($0, maximumEdge: cellEdge) }
        let width = columns * cellEdge
        let height = rows * cellEdge
        let raster = try makeRaster(width: width, height: height) { context in
            fill(context, rect: CGRect(
                x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)
            ), gray: 0.08)
            for (index, image) in images.enumerated() {
                let column = index % columns
                let row = index / columns
                let rect = CGRect(
                    x: CGFloat(column * cellEdge),
                    y: CGFloat(height - ((row + 1) * cellEdge)),
                    width: CGFloat(cellEdge),
                    height: CGFloat(cellEdge)
                ).insetBy(dx: 2, dy: 2)
                fill(context, rect: rect, gray: 1)
                drawAspectFit(image, in: context, rect: rect)
            }
        }
        return try encodePNG(raster)
    }

    private static func renderFlicker(
        _ plan: EvidenceSequencePlanV1,
        sourceData: [Data]
    ) throws -> Data {
        guard let duration = plan.frameDurationMilliseconds,
              sourceData.count == plan.orderedSources.count,
              sourceData.count <= EvidenceCurationLimitsV1.maximumSequenceFrames else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        let images = try sourceData.map {
            try decodeStillImage($0, maximumEdge: flickerCanvasEdge)
        }
        let frames = try images.map { image in
            try makeRaster(width: flickerCanvasEdge, height: flickerCanvasEdge) { context in
                fill(
                    context,
                    rect: CGRect(
                        x: 0, y: 0,
                        width: CGFloat(flickerCanvasEdge),
                        height: CGFloat(flickerCanvasEdge)
                    ),
                    gray: 0
                )
                drawAspectFit(
                    image,
                    in: context,
                    rect: CGRect(
                        x: 0, y: 0,
                        width: CGFloat(flickerCanvasEdge),
                        height: CGFloat(flickerCanvasEdge)
                    )
                )
            }
        }
        return try encodeAPNG(frames, frameDurationMilliseconds: duration)
    }

    private static func decodeStillImage(_ data: Data, maximumEdge: Int) throws -> CGImage {
        guard !data.isEmpty,
              data.count <= MediaContractV1.sourceByteCountMaximum,
              (1...maximumCanvasEdge).contains(maximumEdge),
              let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              CGImageSourceGetCount(source) == 1,
              let sourceType = CGImageSourceGetType(source),
              MediaContractV1.acceptedSourceTypeIdentifiers.contains(sourceType as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (MediaContractV1.sourceAxisMinimum...MediaContractV1.sourceAxisMaximum).contains(width),
              (MediaContractV1.sourceAxisMinimum...MediaContractV1.sourceAxisMaximum).contains(height) else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= MediaContractV1.decodedPixelCountMaximum else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceDecodeToSDR: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0,
              image.height > 0,
              image.width <= maximumEdge,
              image.height <= maximumEdge else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        return image
    }

    private static func makeRaster(
        width: Int,
        height: Int,
        draw: (CGContext) throws -> Void
    ) throws -> Raster {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixels.multipliedReportingOverflow(by: bytesPerPixel)
        guard width > 0,
              height > 0,
              width <= maximumCanvasEdge,
              height <= maximumCanvasEdge,
              !pixelOverflow,
              pixels <= maximumCanvasPixels,
              !byteOverflow,
              byteCount <= maximumCanvasPixels * bytesPerPixel else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        var bytes = Data(count: byteCount)
        let rendered = try bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let baseAddress = storage.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * bytesPerPixel,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            try draw(context)
            context.flush()
            return true
        }
        guard rendered else { throw EvidenceDerivativeServiceFailureV1.invalidRequest }
        return Raster(width: width, height: height, pixels: bytes)
    }

    private static func fill(_ context: CGContext, rect: CGRect, gray: CGFloat) {
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(rect)
    }

    private static func drawAspectFit(_ image: CGImage, in context: CGContext, rect: CGRect) {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let width = floor(CGFloat(image.width) * scale)
        let height = floor(CGFloat(image.height) * scale)
        let target = CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
        context.interpolationQuality = .high
        context.draw(image, in: target)
    }

    private static func drawText(
        _ value: String,
        in context: CGContext,
        at point: CGPoint,
        fontSize: CGFloat,
        color: CGColor
    ) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: value,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textMatrix = .identity
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func encodePNG(_ raster: Raster) throws -> Data {
        var output = pngSignature
        try appendChunk("IHDR", data: headerData(width: raster.width, height: raster.height), to: &output)
        try appendChunk("sRGB", data: Data([0]), to: &output)
        try appendChunk("IDAT", data: zlibStored(scanlines(for: raster)), to: &output)
        try appendChunk("IEND", data: Data(), to: &output)
        return output
    }

    private static func encodeAPNG(
        _ frames: [Raster],
        frameDurationMilliseconds: Int
    ) throws -> Data {
        guard let first = frames.first,
              frames.count >= 2,
              frames.count <= EvidenceCurationLimitsV1.maximumSequenceFrames,
              frames.allSatisfy({ $0.width == first.width && $0.height == first.height }),
              (100...5_000).contains(frameDurationMilliseconds),
              frameDurationMilliseconds <= Int(UInt16.max) else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        var output = pngSignature
        try appendChunk("IHDR", data: headerData(width: first.width, height: first.height), to: &output)
        try appendChunk("sRGB", data: Data([0]), to: &output)
        var animationControl = Data()
        appendUInt32(UInt32(frames.count), to: &animationControl)
        appendUInt32(0, to: &animationControl)
        try appendChunk("acTL", data: animationControl, to: &output)
        var sequenceNumber: UInt32 = 0
        for (index, frame) in frames.enumerated() {
            var frameControl = Data()
            appendUInt32(sequenceNumber, to: &frameControl)
            sequenceNumber += 1
            appendUInt32(UInt32(frame.width), to: &frameControl)
            appendUInt32(UInt32(frame.height), to: &frameControl)
            appendUInt32(0, to: &frameControl)
            appendUInt32(0, to: &frameControl)
            appendUInt16(UInt16(frameDurationMilliseconds), to: &frameControl)
            appendUInt16(1_000, to: &frameControl)
            frameControl.append(0)
            frameControl.append(0)
            try appendChunk("fcTL", data: frameControl, to: &output)
            let compressed = zlibStored(scanlines(for: frame))
            if index == 0 {
                try appendChunk("IDAT", data: compressed, to: &output)
            } else {
                var frameData = Data()
                appendUInt32(sequenceNumber, to: &frameData)
                sequenceNumber += 1
                frameData.append(compressed)
                try appendChunk("fdAT", data: frameData, to: &output)
            }
        }
        try appendChunk("IEND", data: Data(), to: &output)
        guard output.count <= maximumDerivativeBytes else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        return output
    }

    private static var pngSignature: Data { Data([137, 80, 78, 71, 13, 10, 26, 10]) }

    private static func headerData(width: Int, height: Int) -> Data {
        var data = Data()
        appendUInt32(UInt32(width), to: &data)
        appendUInt32(UInt32(height), to: &data)
        data.append(contentsOf: [8, 6, 0, 0, 0])
        return data
    }

    private static func scanlines(for raster: Raster) -> Data {
        let rowBytes = raster.width * bytesPerPixel
        var result = Data(capacity: raster.height * (rowBytes + 1))
        for row in (0..<raster.height).reversed() {
            result.append(0)
            let start = row * rowBytes
            result.append(raster.pixels[start..<(start + rowBytes)])
        }
        return result
    }

    private static func zlibStored(_ data: Data) -> Data {
        var output = Data([0x78, 0x01])
        var offset = 0
        while offset < data.count {
            let length = min(65_535, data.count - offset)
            let isFinal = offset + length == data.count
            output.append(isFinal ? 0x01 : 0x00)
            let value = UInt16(length)
            appendUInt16LittleEndian(value, to: &output)
            appendUInt16LittleEndian(~value, to: &output)
            output.append(data[offset..<(offset + length)])
            offset += length
        }
        appendUInt32(adler32(data), to: &output)
        return output
    }

    private static func appendChunk(_ type: String, data: Data, to output: inout Data) throws {
        let typeData = Data(type.utf8)
        guard typeData.count == 4, data.count <= Int(UInt32.max) else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        appendUInt32(UInt32(data.count), to: &output)
        output.append(typeData)
        output.append(data)
        var crcInput = typeData
        crcInput.append(data)
        appendUInt32(crc32(crcInput), to: &output)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func appendUInt16LittleEndian(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func adler32(_ data: Data) -> UInt32 {
        let modulus: UInt32 = 65_521
        var first: UInt32 = 1
        var second: UInt32 = 0
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + 5_552)
            for byte in data[offset..<end] {
                first += UInt32(byte)
                second += first
            }
            first %= modulus
            second %= modulus
            offset = end
        }
        return (second << 16) | first
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ crcTable[index]
        }
        return crc ^ 0xffff_ffff
    }
}

enum EvidenceDerivativeServiceBoundaryV1 {
    static let createsContentStore = false
    static let mutatesOriginalBytes = false
    static let privacyTransformPrecedesMarkup = true
    static let reduceMotionIsPresentationOnly = true
    static let usesNetworkOrDiagnosis = false
}
