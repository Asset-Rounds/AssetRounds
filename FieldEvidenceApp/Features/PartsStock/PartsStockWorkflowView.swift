import Foundation
import SwiftUI

/// Presentation-only state for one balance/location row.
///
/// The canonical projection and location are supplied by C55's lifecycle
/// adapter. This value does not replay movements or make a zero assumption for
/// an absent projection.
struct PartsStockWorkflowBalancePresentationV1: Equatable, Sendable, Identifiable {
    let projection: StockBalanceProjectionV1
    let location: StockStorageLocationV1

    var id: UUID { location.locationID }

    init(projection: StockBalanceProjectionV1, location: StockStorageLocationV1) throws {
        try projection.validate()
        try location.validate()
        guard projection.workspaceID == location.workspaceID,
              projection.locationID == location.locationID else {
            throw PartsStockFailureV1.crossWorkspace
        }
        self.projection = projection
        self.location = location
    }
}

/// A catalog row combines the validated C44 detail contract with caller-bound
/// balance projections. It is a display value, not a second stock authority.
struct PartsStockWorkflowCatalogItemV1: Equatable, Sendable, Identifiable {
    let detail: PartsStockWorkflowCatalogDetailV1
    let balances: [PartsStockWorkflowBalancePresentationV1]

    var id: UUID { detail.part.partID }

    init(
        detail: PartsStockWorkflowCatalogDetailV1,
        balances: [PartsStockWorkflowBalancePresentationV1] = []
    ) throws {
        self.detail = detail
        self.balances = balances.sorted { $0.location.locationID.uuidString < $1.location.locationID.uuidString }
        guard Set(balances.map(\.id)).count == balances.count,
              balances.allSatisfy({
            $0.projection.workspaceID == detail.part.workspaceID
                && $0.projection.partID == detail.part.partID
                && $0.projection.unit == detail.part.canonicalUnit
        }) else {
            throw PartsStockFailureV1.crossWorkspace
        }
    }
}

/// A return candidate is always anchored to one accepted Use receipt. The
/// view only renders candidates supplied by the canonical query; it cannot
/// construct an unbound positive return.
struct PartsStockWorkflowReturnPresentationV1: Equatable, Sendable, Identifiable {
    let id: UUID
    let sourceUse: StockUseOnWorkReceiptV1
    let predecessorFrontier: StockReturnFrontierSnapshotV1?
    let destination: StockStorageLocationV1
    let workLabel: String
    let outstandingQuantity: StockQuantityV1
    let eligible: Bool

    init(
        id: UUID = UUID(),
        sourceUse: StockUseOnWorkReceiptV1,
        predecessorFrontier: StockReturnFrontierSnapshotV1? = nil,
        destination: StockStorageLocationV1,
        workLabel: String,
        outstandingQuantity: StockQuantityV1,
        eligible: Bool = true
    ) throws {
        try sourceUse.validate()
        try predecessorFrontier?.validate()
        try destination.validate()
        try outstandingQuantity.validate(for: sourceUse.movement.unit)
        let priorReturned = predecessorFrontier?.resultingReturnedMantissa ?? 0
        let (expectedOutstanding, overflow) = sourceUse.movement.quantity.mantissa.subtractingReportingOverflow(priorReturned)
        guard id != Self.zero,
              !overflow,
              destination.workspaceID == sourceUse.workspaceID,
              sourceUse.movement.quantity.scale == outstandingQuantity.scale,
              outstandingQuantity.mantissa > 0,
              outstandingQuantity.mantissa == expectedOutstanding,
              predecessorFrontier.map({ $0.sourceUseReceiptID == sourceUse.receiptID }) ?? true else {
            throw PartsStockFailureV1.invalidTransition
        }
        self.id = id
        self.sourceUse = sourceUse
        self.predecessorFrontier = predecessorFrontier
        self.destination = destination
        self.workLabel = workLabel
        self.outstandingQuantity = outstandingQuantity
        self.eligible = eligible
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

enum PartsStockWorkflowAvailabilityV1: String, CaseIterable, Equatable, Sendable {
    case ready = "READY"
    case loading = "LOADING"
    case featureDisabled = "FEATURE_DISABLED"
    case offline = "OFFLINE"
    case protectedData = "PROTECTED_DATA"
    case storageUnavailable = "STORAGE_UNAVAILABLE"
    case interrupted = "INTERRUPTED"
    case stale = "STALE"
    case unavailable = "UNAVAILABLE"
}

enum PartsStockWorkflowScanAvailabilityV1: String, CaseIterable, Equatable, Sendable {
    case available = "AVAILABLE"
    case unavailable = "UNAVAILABLE"
    case permissionDenied = "PERMISSION_DENIED"
    case unsupported = "UNSUPPORTED"
}

enum PartsStockWorkflowLookupResultV1: String, CaseIterable, Equatable, Sendable {
    case idle = "IDLE"
    case found = "FOUND"
    case ambiguous = "AMBIGUOUS"
    case notFound = "NOT_FOUND"
    case foreign = "FOREIGN"
    case stale = "STALE"
    case manualFallback = "MANUAL_FALLBACK"
}

struct PartsStockWorkflowLookupPresentationV1: Equatable, Sendable {
    let query: PartsStockWorkflowLookupV1?
    let result: PartsStockWorkflowLookupResultV1
    let matchedPartID: UUID?
    let message: String?

    init(
        query: PartsStockWorkflowLookupV1? = nil,
        result: PartsStockWorkflowLookupResultV1 = .idle,
        matchedPartID: UUID? = nil,
        message: String? = nil
    ) {
        self.query = query
        self.result = result
        self.matchedPartID = matchedPartID
        self.message = message
    }
}

enum PartsStockWorkflowDraftStateV1: String, CaseIterable, Equatable, Sendable {
    case absent = "ABSENT"
    case active = "ACTIVE"
    case dirty = "DIRTY"
    case checkpointed = "CHECKPOINTED"
    case interrupted = "INTERRUPTED"
    case protectedData = "PROTECTED_DATA"
    case unavailable = "UNAVAILABLE"
}

/// Draft presentation is intentionally separate from canonical stock state.
/// Text edits and checkpoints must be handed to the existing draft authority.
struct PartsStockWorkflowDraftPresentationV1: Equatable, Sendable {
    let draftID: UUID?
    let revision: UInt64?
    let materialText: String
    let state: PartsStockWorkflowDraftStateV1
    let canCheckpoint: Bool
    let message: String?

    init(
        draftID: UUID? = nil,
        revision: UInt64? = nil,
        materialText: String = "",
        state: PartsStockWorkflowDraftStateV1 = .absent,
        canCheckpoint: Bool = false,
        message: String? = nil
    ) {
        self.draftID = draftID
        self.revision = revision
        self.materialText = materialText
        self.state = state
        self.canCheckpoint = canCheckpoint
        self.message = message
    }
}

enum PartsStockWorkflowCSVStateV1: String, CaseIterable, Equatable, Sendable {
    case idle = "IDLE"
    case previewing = "PREVIEWING"
    case previewReady = "PREVIEW_READY"
    case committing = "COMMITTING"
    case receiptConfirmed = "RECEIPT_CONFIRMED"
    case cancelled = "CANCELLED"
    case failed = "FAILED"
}

struct PartsStockWorkflowCSVPresentationV1: Equatable, Sendable {
    let importState: PartsStockWorkflowCSVStateV1
    let exportState: PartsStockWorkflowCSVStateV1
    let importPlan: PartsStockWorkflowCSVImportPlanV1?
    let importResult: PartsStockWorkflowCSVImportResultV1?
    let importAvailable: Bool
    let exportAvailable: Bool
    let message: String?

    init(
        importState: PartsStockWorkflowCSVStateV1 = .idle,
        exportState: PartsStockWorkflowCSVStateV1 = .idle,
        importPlan: PartsStockWorkflowCSVImportPlanV1? = nil,
        importResult: PartsStockWorkflowCSVImportResultV1? = nil,
        importAvailable: Bool = false,
        exportAvailable: Bool = true,
        message: String? = nil
    ) {
        self.importState = importState
        self.exportState = exportState
        self.importPlan = importPlan
        self.importResult = importResult
        self.importAvailable = importAvailable
        self.exportAvailable = exportAvailable
        self.message = message
    }

    var schemaIdentifier: String { PartsStockWorkflowCatalogV1.identifier }
}

enum PartsStockWorkflowOperationStateV1: String, CaseIterable, Equatable, Sendable {
    case idle = "IDLE"
    case awaitingReceipt = "AWAITING_RECEIPT"
    case receiptConfirmed = "RECEIPT_CONFIRMED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case stale = "STALE"
}

struct PartsStockWorkflowOperationPresentationV1: Equatable, Sendable {
    let state: PartsStockWorkflowOperationStateV1
    let message: String?

    init(
        state: PartsStockWorkflowOperationStateV1 = .idle,
        message: String? = nil
    ) {
        self.state = state
        self.message = message
    }
}

/// Caller-supplied history context for the contained surface. This is not a
/// replay authority and does not create, confirm, or amend a stock event.
struct PartsStockWorkflowHistoryPresentationV1: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let detail: String

    init(id: UUID = UUID(), title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// A typed command boundary for the contained view. The receiving owner is
/// responsible for building the exact C55 mutation, expected revision,
/// MutationID, and work-resource successor before invoking the canonical
/// writer. The view never writes a store itself.
enum PartsStockWorkflowCommandV1: Equatable, Sendable {
    case openCatalog
    case search(PartsStockWorkflowLookupV1)
    case scan
    case selectPart(UUID)
    case count(UUID)
    case adjust(UUID)
    case transfer(UUID)
    case use(partID: UUID, quantityText: String, materialText: String)
    case reviewReturn(UUID)
    case `return`(returnID: UUID, sourceUseReceiptID: UUID, quantityText: String)
    case archive(UUID)
    case importCSV
    case exportCSV
    case checkpointDraft(String)
    case retry
    case cancel
}

/// C44's caller-supplied presentation graph. All canonical data is supplied
/// by C55/C08/C21/C36 adapters; these values only decide what the view can
/// truthfully render and which typed closure command it may request.
struct PartsStockWorkflowProjectionV1: Equatable, Sendable {
    let featurePolicy: LocalStockFeaturePolicyV1
    let availability: PartsStockWorkflowAvailabilityV1
    let catalog: [PartsStockWorkflowCatalogItemV1]
    let selectedPartID: UUID?
    let lookup: PartsStockWorkflowLookupPresentationV1?
    let returns: [PartsStockWorkflowReturnPresentationV1]
    let draft: PartsStockWorkflowDraftPresentationV1?
    let csv: PartsStockWorkflowCSVPresentationV1
    let operation: PartsStockWorkflowOperationPresentationV1
    let history: [PartsStockWorkflowHistoryPresentationV1]
    let scanAvailability: PartsStockWorkflowScanAvailabilityV1
    let errorMessage: String?

    init(
        featurePolicy: LocalStockFeaturePolicyV1 = .enabled,
        availability: PartsStockWorkflowAvailabilityV1 = .ready,
        catalog: [PartsStockWorkflowCatalogItemV1] = [],
        selectedPartID: UUID? = nil,
        lookup: PartsStockWorkflowLookupPresentationV1? = nil,
        returns: [PartsStockWorkflowReturnPresentationV1] = [],
        draft: PartsStockWorkflowDraftPresentationV1? = nil,
        csv: PartsStockWorkflowCSVPresentationV1 = .init(),
        operation: PartsStockWorkflowOperationPresentationV1 = .init(),
        history: [PartsStockWorkflowHistoryPresentationV1] = [],
        scanAvailability: PartsStockWorkflowScanAvailabilityV1 = .unavailable,
        errorMessage: String? = nil
    ) {
        self.featurePolicy = featurePolicy
        self.availability = availability
        self.catalog = catalog
        self.selectedPartID = selectedPartID
        self.lookup = lookup
        self.returns = returns
        self.draft = draft
        self.csv = csv
        self.operation = operation
        self.history = history
        self.scanAvailability = scanAvailability
        self.errorMessage = errorMessage
    }

    var selectedItem: PartsStockWorkflowCatalogItemV1? {
        guard let selectedPartID else { return nil }
        return catalog.first { $0.id == selectedPartID }
    }

    var eligibleReturns: [PartsStockWorkflowReturnPresentationV1] {
        returns.filter(\.eligible)
    }
}

typealias PartsStockWorkflowModelV1 = PartsStockWorkflowProjectionV1

/// Contained C44 presentation surface for Work-local Parts & Stock.
///
/// This view owns no route, root registration, persistence, writer, camera
/// permission, network lookup, telemetry, customer report, or identity
/// authority. Before S10.6 it is intentionally a no-launch surface. All
/// mutations are typed requests sent to the incumbent owner through
/// `onCommand`, and only that owner can return a canonical receipt.
@MainActor
struct PartsStockWorkflowView: View {
    static let cardID = "V23-P04-C44"
    static let containedSurfaceOnly = true
    static let activationEnabled = false
    static let adoptionEnabled = false
    static let appShellAdoptionEnabled = false
    static let nativeLaunchAdoptionEnabled = false
    static let liveAdoptionEnabled = false
    static let s10_6LiveAdoptionEnabled = false
    static let writeThroughView = false
    static let lookupIsZeroWrite = C44PartsStockWorkflowBoundaryV1.lookupIsZeroWrite
    static let onlyExplicitUseMutatesStock = C44PartsStockWorkflowBoundaryV1.onlyExplicitUseMutatesStock
    static let reportsExcludeBalancesAndInternalLocations =
        C44PartsStockWorkflowBoundaryV1.reportsExcludeBalancesAndInternalLocations

    static let screenAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.screen"
    static let workRootAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.work-root"
    static let availabilityAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.availability"
    static let searchAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.search"
    static let lookupAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.lookup"
    static let catalogAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.catalog"
    static let detailAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.detail"
    static let lowStockAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.low-stock"
    static let countAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.count"
    static let adjustAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.adjust"
    static let transferAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.transfer"
    static let useAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.use"
    static let returnAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.return"
    static let archiveAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.archive"
    static let draftAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.draft"
    static let csvAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.csv"
    static let historyAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.history"
    static let statusAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.status"
    static let errorAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.error"
    static let boundariesAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.boundaries"
    static let searchFieldAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.search.field"
    static let manualLookupFieldAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.lookup.manual-field"
    static let scanAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.lookup.scan"
    static let importAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.csv.import"
    static let exportAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.csv.export"
    static let checkpointAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.draft.checkpoint"
    static let useQuantityAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.use.quantity"
    static let useMaterialAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.use.material"
    static let returnQuantityAccessibilityIdentifier = "v23.p04.c44.parts-stock-workflow.return.quantity"
    static let historyEntryAccessibilityIdentifierPrefix = "v23.p04.c44.parts-stock-workflow.history.entry."
    static let catalogItemAccessibilityIdentifierPrefix = "v23.p04.c44.parts-stock-workflow.catalog.item."
    static let balanceAccessibilityIdentifierPrefix = "v23.p04.c44.parts-stock-workflow.detail.balance."
    static let returnCandidateAccessibilityIdentifierPrefix = "v23.p04.c44.parts-stock-workflow.return.candidate."

    static let fixedAccessibilityIdentifiers = [
        screenAccessibilityIdentifier,
        workRootAccessibilityIdentifier,
        availabilityAccessibilityIdentifier,
        searchAccessibilityIdentifier,
        lookupAccessibilityIdentifier,
        catalogAccessibilityIdentifier,
        detailAccessibilityIdentifier,
        lowStockAccessibilityIdentifier,
        countAccessibilityIdentifier,
        adjustAccessibilityIdentifier,
        transferAccessibilityIdentifier,
        useAccessibilityIdentifier,
        returnAccessibilityIdentifier,
        archiveAccessibilityIdentifier,
        draftAccessibilityIdentifier,
        csvAccessibilityIdentifier,
        historyAccessibilityIdentifier,
        statusAccessibilityIdentifier,
        errorAccessibilityIdentifier,
        boundariesAccessibilityIdentifier,
        searchFieldAccessibilityIdentifier,
        manualLookupFieldAccessibilityIdentifier,
        scanAccessibilityIdentifier,
        importAccessibilityIdentifier,
        exportAccessibilityIdentifier,
        checkpointAccessibilityIdentifier,
        useQuantityAccessibilityIdentifier,
        useMaterialAccessibilityIdentifier,
        returnQuantityAccessibilityIdentifier
    ]

    let model: PartsStockWorkflowProjectionV1
    let onCommand: @MainActor (PartsStockWorkflowCommandV1) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var keyboardFocus: KeyboardField?
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?

    @State private var searchText: String
    @State private var manualLookupText: String
    @State private var useQuantityText = ""
    @State private var useMaterialText = ""
    @State private var draftMaterialText: String
    @State private var returnQuantityText = ""
    @State private var selectedReturnID: UUID?
    @State private var localErrorMessage: String?
    @State private var localOperationMessage: String?

    private enum KeyboardField: Hashable {
        case search
        case manualLookup
        case useQuantity
        case useMaterial
        case draftMaterial
        case returnQuantity
    }

    private enum AccessibilityTarget: Hashable {
        case heading
        case search
        case manualLookup
        case selectedPart
        case returnQuantity
        case error
        case status
    }

    init(
        model: PartsStockWorkflowProjectionV1,
        onCommand: @escaping @MainActor (PartsStockWorkflowCommandV1) -> Void = { _ in }
    ) {
        self.model = model
        self.onCommand = onCommand
        _searchText = State(initialValue: model.lookup?.query?.queryText ?? "")
        _manualLookupText = State(initialValue: "")
        _draftMaterialText = State(initialValue: model.draft?.materialText ?? "")
    }

    init(
        projection: PartsStockWorkflowProjectionV1,
        onCommand: @escaping @MainActor (PartsStockWorkflowCommandV1) -> Void = { _ in }
    ) {
        self.init(model: projection, onCommand: onCommand)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                workEntry
                availability
                searchAndLookup
                lowStock
                catalog
                if let selectedItem = model.selectedItem {
                    detail(for: selectedItem)
                }
                returnSection
                history
                draft
                csv
                truthBoundaries
                errorSummary
                operationStatus
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.partsStockNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .onAppear {
            accessibilityFocus = model.errorMessage == nil ? .heading : .error
        }
        .onChange(of: model.errorMessage) { _, newValue in
            if newValue != nil {
                accessibilityFocus = .error
            }
        }
        .onChange(of: model.operation.state) { _, _ in
            if model.operation.message != nil {
                accessibilityFocus = .status
            }
        }
        .onChange(of: model.selectedPartID) { _, _ in
            useQuantityText = ""
            useMaterialText = ""
            accessibilityFocus = .selectedPart
        }
        .environment(\.layoutDirection, layoutDirection)
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var writesAllowed: Bool {
        guard model.featurePolicy.allowsWrites else { return false }
        switch model.availability {
        case .ready, .offline:
            return model.operation.state != .awaitingReceipt
        case .loading, .featureDisabled, .protectedData, .storageUnavailable,
             .interrupted, .stale, .unavailable:
            return false
        }
    }

    private var canRead: Bool {
        switch model.availability {
        case .protectedData, .storageUnavailable, .loading, .unavailable:
            return false
        case .ready, .featureDisabled, .offline, .interrupted, .stale:
            return true
        }
    }

    private var displayedErrorMessage: String? {
        localErrorMessage ?? model.errorMessage
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var workEntry: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockWorkEntryHeading), identifier: Self.workRootAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockWorkEntryDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(BundledLocalizationCatalogV1.v30Text(.partsStockOpenCatalog)) {
                send(.openCatalog, message: BundledLocalizationCatalogV1.v30Text(.partsStockCatalogRequested))
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!canRead)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockOpenCatalogHint))
            .accessibilityIdentifier("\(Self.workRootAccessibilityIdentifier).open")
        }
        .accessibilityElement(children: .contain)
    }

    private var availability: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockAvailabilityHeading), identifier: Self.availabilityAccessibilityIdentifier)
            WorklightStatusBadge(kind: availabilityKind, text: availabilityText)
            Text(availabilityDetail)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.featurePolicy == .readExportRecoveryOnly {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockWritesDisabled))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var searchAndLookup: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockSearchHeading), identifier: Self.searchAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockSearchDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            TextField(BundledLocalizationCatalogV1.v30Text(.partsStockSearchPlaceholder), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($keyboardFocus, equals: .search)
                .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.partsStockSearchLabel))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockSearchHint))
                .accessibilityIdentifier(Self.searchFieldAccessibilityIdentifier)
            Button(BundledLocalizationCatalogV1.v30Text(.partsStockSearchCatalog)) {
                submitSearch()
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!canRead)
            .keyboardShortcut("f", modifiers: [.command])
            .accessibilityIdentifier("\(Self.searchAccessibilityIdentifier).submit")

            Text(BundledLocalizationCatalogV1.v30Text(.partsStockSearchBoundary))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.informationText)
                .fixedSize(horizontal: false, vertical: true)

            lookupControls
            lookupResult
        }
        .accessibilityElement(children: .contain)
    }

    private var lookupControls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            switch model.scanAvailability {
            case .available:
                Button(BundledLocalizationCatalogV1.v30Text(.partsStockScanCode)) {
                    send(.scan, message: BundledLocalizationCatalogV1.v30Text(.partsStockScanRequested))
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canRead)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockScanHint))
                .accessibilityIdentifier(Self.scanAccessibilityIdentifier)
            case .permissionDenied:
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockCameraDenied))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.scanAccessibilityIdentifier)
            case .unavailable, .unsupported:
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockScanUnavailable))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.scanAccessibilityIdentifier)
            }

            TextField(BundledLocalizationCatalogV1.v30Text(.partsStockManualLookupPlaceholder), text: $manualLookupText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($keyboardFocus, equals: .manualLookup)
                .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.partsStockManualLookupLabel))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockManualLookupHint))
                .accessibilityIdentifier(Self.manualLookupFieldAccessibilityIdentifier)
            Button(BundledLocalizationCatalogV1.v30Text(.partsStockManualLookupButton)) {
                submitManualLookup()
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!canRead)
            .accessibilityIdentifier("\(Self.lookupAccessibilityIdentifier).manual-submit")
        }
        .accessibilityIdentifier(Self.lookupAccessibilityIdentifier)
    }

    @ViewBuilder
    private var lookupResult: some View {
        if let lookup = model.lookup, lookup.result != .idle {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockLookupResultHeading), identifier: "\(Self.lookupAccessibilityIdentifier).result")
                Text(lookup.message ?? lookupResultText(lookup.result))
                    .font(.body)
                    .foregroundStyle(lookup.result == .found ? DesignTokens.Colors.primaryText : DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
                if let matchedPartID = lookup.matchedPartID {
                    Text(BundledLocalizationCatalogV1.v30PartsStockMatchedItem(partID: shortID(matchedPartID)))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(Self.lookupAccessibilityIdentifier).result")
        }
    }

    private var lowStock: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockLowStockHeading), identifier: Self.lowStockAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockLowStockDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            let attentionRows = model.catalog.flatMap { item in
                item.detail.attention
                    .filter { $0.isBelowPreferred || isUnknown($0.balance) }
                    .map { (item, $0) }
            }
            if attentionRows.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockNoLowStockAttention))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.catalog) { item in
                    let rows = item.detail.attention.filter { $0.isBelowPreferred || isUnknown($0.balance) }
                    ForEach(rows, id: \.locationID) { attention in
                        let location = item.balances.first { $0.id == attention.locationID }?.location.label
                            ?? BundledLocalizationCatalogV1.v30PartsStockStorageLocation(locationID: shortID(attention.locationID))
                        Label(
                            lowStockText(item: item, attention: attention, location: location),
                            systemImage: isUnknown(attention.balance) ? "questionmark.circle" : "exclamationmark.triangle.fill"
                        )
                        .font(.body)
                        .foregroundStyle(isUnknown(attention.balance) ? DesignTokens.Colors.attentionText : DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var catalog: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockCatalogHeading), identifier: Self.catalogAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockCatalogDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if model.catalog.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockNoCatalogItems))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.catalog) { item in
                    Button {
                        send(.selectPart(item.id), message: BundledLocalizationCatalogV1.v30PartsStockPartSelected(name: item.detail.part.displayName))
                    } label: {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            Text(item.detail.part.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DesignTokens.Colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(BundledLocalizationCatalogV1.v30PartsStockCatalogSummary(unit: unitText(item.detail.part.canonicalUnit), identityCount: item.detail.part.productIdentities.count, revision: String(item.detail.part.revision)))
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.detail.part.archived ? BundledLocalizationCatalogV1.v30Text(.partsStockArchivedDefinition) : BundledLocalizationCatalogV1.v30Text(.partsStockActiveDefinition))
                                .font(.footnote)
                                .foregroundStyle(item.detail.part.archived ? DesignTokens.Colors.attentionText : DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityLabel(BundledLocalizationCatalogV1.v30PartsStockViewDetails(name: item.detail.part.displayName))
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockViewDetailsHint))
                    .accessibilityIdentifier("\(Self.catalogItemAccessibilityIdentifierPrefix)\(item.id.uuidString.lowercased())")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func detail(for item: PartsStockWorkflowCatalogItemV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockDetailHeading), identifier: Self.detailAccessibilityIdentifier)
                .accessibilityFocused($accessibilityFocus, equals: .selectedPart)
            Text(BundledLocalizationCatalogV1.v30PartsStockDetailSummary(name: item.detail.part.displayName, revision: String(item.detail.part.revision)))
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockCanonicalUnit), value: unitText(item.detail.part.canonicalUnit))
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockProductIdentities), value: item.detail.part.productIdentities.isEmpty ? BundledLocalizationCatalogV1.v30Text(.partsStockNoneSupplied) : item.detail.part.productIdentities.map(\.value).joined(separator: ", "))
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockPreferredMinimum), value: item.detail.part.preferredMinimum.map { quantityText($0, unit: item.detail.part.canonicalUnit) } ?? BundledLocalizationCatalogV1.v30Text(.partsStockNotSupplied))

            if item.balances.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockNoBalanceProjection))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(BundledLocalizationCatalogV1.v30Text(.partsStockBalanceProjections))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    ForEach(item.balances) { balance in
                        let value = balanceText(balance.projection)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(balance.location.label)
                                .font(.body)
                                .foregroundStyle(DesignTokens.Colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(value)
                                .font(.footnote)
                                .foregroundStyle(balance.projection.balance == .unknown ? DesignTokens.Colors.attentionText : DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("\(Self.balanceAccessibilityIdentifierPrefix)\(balance.id.uuidString.lowercased())")
                    }
                }
            }

            Text(BundledLocalizationCatalogV1.v30Text(.partsStockDetailBoundary))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.informationText)
                .fixedSize(horizontal: false, vertical: true)

            explicitActions(for: item)
        }
        .accessibilityElement(children: .contain)
    }

    private func explicitActions(for item: PartsStockWorkflowCatalogItemV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockActionsHeading), identifier: "\(Self.detailAccessibilityIdentifier).actions")
            actionButton(
                title: BundledLocalizationCatalogV1.v30Text(.partsStockCount),
                command: .count(item.id),
                identifier: Self.countAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived,
                hint: BundledLocalizationCatalogV1.v30Text(.partsStockCountHint)
            )
            actionButton(
                title: BundledLocalizationCatalogV1.v30Text(.partsStockAdjust),
                command: .adjust(item.id),
                identifier: Self.adjustAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived,
                hint: BundledLocalizationCatalogV1.v30Text(.partsStockAdjustHint)
            )
            actionButton(
                title: BundledLocalizationCatalogV1.v30Text(.partsStockTransfer),
                command: .transfer(item.id),
                identifier: Self.transferAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived,
                hint: BundledLocalizationCatalogV1.v30Text(.partsStockTransferHint)
            )
            useEditor(for: item)
            actionButton(
                title: BundledLocalizationCatalogV1.v30Text(.partsStockArchive),
                command: .archive(item.id),
                identifier: Self.archiveAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived && archiveIsEligible(item),
                hint: archiveIsEligible(item)
                    ? BundledLocalizationCatalogV1.v30Text(.partsStockArchiveHint)
                    : BundledLocalizationCatalogV1.v30Text(.partsStockArchiveUnavailableHint)
            )
            if item.detail.part.archived {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockArchivedDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !archiveIsEligible(item) {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockArchiveBlocked))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("\(Self.detailAccessibilityIdentifier).actions")
    }

    private func useEditor(for item: PartsStockWorkflowCatalogItemV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockUseHeading), identifier: Self.useAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockUseDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField(BundledLocalizationCatalogV1.v30Text(.partsStockUseQuantityPlaceholder), text: $useQuantityText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .focused($keyboardFocus, equals: .useQuantity)
                .accessibilityLabel(BundledLocalizationCatalogV1.v30PartsStockUseQuantityLabel(unit: unitText(item.detail.part.canonicalUnit)))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockUseQuantityHint))
                .accessibilityIdentifier(Self.useQuantityAccessibilityIdentifier)
            TextField(BundledLocalizationCatalogV1.v30Text(.partsStockMaterialPlaceholder), text: $useMaterialText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($keyboardFocus, equals: .useMaterial)
                .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.partsStockMaterialLabel))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockMaterialHint))
                .accessibilityIdentifier(Self.useMaterialAccessibilityIdentifier)
            Button(BundledLocalizationCatalogV1.v30Text(.partsStockUseButton)) {
                submitUse(for: item)
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!writesAllowed || item.detail.part.archived)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockUseButtonHint))
            .accessibilityIdentifier("\(Self.useAccessibilityIdentifier).submit")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var returnSection: some View {
        if model.eligibleReturns.isEmpty {
            WorklightCard {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockReturnBoundaryHeading), identifier: Self.returnAccessibilityIdentifier)
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockNoReturnDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
        } else {
            WorklightCard {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockReturnHeading), identifier: Self.returnAccessibilityIdentifier)
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockReturnDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.eligibleReturns) { candidate in
                    returnCandidate(candidate)
                }
                if let candidate = selectedReturnCandidate {
                    returnEditor(candidate)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func returnCandidate(_ candidate: PartsStockWorkflowReturnPresentationV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(candidate.workLabel)
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockUseReceipt), value: shortID(candidate.sourceUse.receiptID))
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockUsed), value: quantityText(candidate.sourceUse.movement.quantity, unit: candidate.sourceUse.movement.unit))
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockOutstanding), value: quantityText(candidate.outstandingQuantity, unit: candidate.sourceUse.movement.unit))
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockDestination), value: candidate.destination.label)
            Button(BundledLocalizationCatalogV1.v30Text(.partsStockReviewReturn)) {
                selectedReturnID = candidate.id
                returnQuantityText = quantityTextWithoutUnit(candidate.outstandingQuantity)
                accessibilityFocus = .returnQuantity
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!writesAllowed)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockReviewReturnHint))
            .accessibilityIdentifier("\(Self.returnCandidateAccessibilityIdentifierPrefix)\(candidate.id.uuidString.lowercased())")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(Self.returnCandidateAccessibilityIdentifierPrefix)\(candidate.id.uuidString.lowercased()).row")
    }

    private func returnEditor(_ candidate: PartsStockWorkflowReturnPresentationV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockReturnQuantityHeading), identifier: "\(Self.returnAccessibilityIdentifier).editor")
            Text(BundledLocalizationCatalogV1.v30PartsStockReturning(destination: candidate.destination.label, quantity: quantityText(candidate.outstandingQuantity, unit: candidate.sourceUse.movement.unit)))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField(BundledLocalizationCatalogV1.v30Text(.partsStockReturnQuantityPlaceholder), text: $returnQuantityText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .focused($keyboardFocus, equals: .returnQuantity)
                .accessibilityLabel(BundledLocalizationCatalogV1.v30PartsStockReturnQuantityLabel(destination: candidate.destination.label))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockReturnQuantityHint))
                .accessibilityIdentifier(Self.returnQuantityAccessibilityIdentifier)
            Button(BundledLocalizationCatalogV1.v30PartsStockReturnButton(destination: candidate.destination.label)) {
                submitReturn(candidate)
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!writesAllowed)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockReturnButtonHint))
            .accessibilityIdentifier("\(Self.returnAccessibilityIdentifier).submit")
        }
        .accessibilityElement(children: .contain)
    }

    private var history: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockHistoryHeading), identifier: Self.historyAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockHistoryDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.history.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockNoHistory))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.history) { entry in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(entry.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(entry.detail)
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("\(Self.historyEntryAccessibilityIdentifierPrefix)\(entry.id.uuidString.lowercased())")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var draft: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockDraftHeading), identifier: Self.draftAccessibilityIdentifier)
            if let draft = model.draft, draft.state != .absent {
                Text(draftStateText(draft.state))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let draftID = draft.draftID {
                    valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockDraft), value: shortID(draftID))
                }
                if let revision = draft.revision {
                    valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockDraftRevision), value: "\(revision)")
                }
                TextField(BundledLocalizationCatalogV1.v30Text(.partsStockDraftMaterialPlaceholder), text: $draftMaterialText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($keyboardFocus, equals: .draftMaterial)
                    .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.partsStockDraftMaterialLabel))
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockDraftMaterialHint))
                    .accessibilityIdentifier("\(Self.draftAccessibilityIdentifier).material")
                Button(BundledLocalizationCatalogV1.v30Text(.partsStockCheckpointDraft)) {
                    submitDraftCheckpoint()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!draft.canCheckpoint)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockCheckpointHint))
                .accessibilityIdentifier(Self.checkpointAccessibilityIdentifier)
                if let message = draft.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockDraftPreservationDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockNoDraft))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var csv: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockCsvHeading), identifier: Self.csvAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30PartsStockCsvSchema(schema: model.csv.schemaIdentifier))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockImport), value: csvStateText(model.csv.importState, rows: model.csv.importPlan?.rows.count ?? model.csv.importResult?.expectedRowCount))
            valueRow(BundledLocalizationCatalogV1.v30Text(.partsStockExport), value: csvStateText(model.csv.exportState, rows: nil))
            if let message = model.csv.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(BundledLocalizationCatalogV1.v30Text(.partsStockPreviewCsvImport)) {
                sendWrite(.importCSV, message: BundledLocalizationCatalogV1.v30PartsStockImportPreviewRequested(identifier: PartsStockWorkflowCatalogV1.identifier))
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!model.csv.importAvailable || !writesAllowed)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockPreviewCsvHint))
            .accessibilityIdentifier(Self.importAccessibilityIdentifier)
            Button(BundledLocalizationCatalogV1.v30Text(.partsStockExportCsv)) {
                send(.exportCSV, message: BundledLocalizationCatalogV1.v30PartsStockExportRequested(identifier: PartsStockWorkflowCatalogV1.identifier))
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!model.csv.exportAvailable || !canRead)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partsStockExportCsvHint))
            .accessibilityIdentifier(Self.exportAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
    }

    private var truthBoundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockBoundariesHeading), identifier: Self.boundariesAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockReportBoundary))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockAccessibilityDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockDynamicTypeDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.partsStockContainmentBoundary))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var errorSummary: some View {
        if let displayedErrorMessage {
            WorklightCard {
                Label(BundledLocalizationCatalogV1.v30Text(.partsStockActionNeedsAttention), systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(displayedErrorMessage)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .error)
                Text(BundledLocalizationCatalogV1.v30Text(.partsStockRecoveryDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.errorAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private var operationStatus: some View {
        let message = localOperationMessage ?? model.operation.message
        if let message {
            WorklightCard {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.partsStockOperationStatusHeading), identifier: Self.statusAccessibilityIdentifier)
                Text(message)
                    .font(.body)
                    .foregroundStyle(operationColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .status)
                Text(operationBoundaryText)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        command: PartsStockWorkflowCommandV1,
        identifier: String,
        enabled: Bool,
        hint: String
    ) -> some View {
        Button(title) {
            sendWrite(command, message: BundledLocalizationCatalogV1.v30PartsStockActionRequested(action: title))
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
        .disabled(!enabled)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    private func sectionHeading(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func valueRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Text(value)
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var selectedReturnCandidate: PartsStockWorkflowReturnPresentationV1? {
        guard let selectedReturnID else { return nil }
        return model.eligibleReturns.first { $0.id == selectedReturnID }
    }

    private func submitSearch() {
        localErrorMessage = nil
        guard searchText.utf8.count <= PartsStockLimitsV1.maximumSearchQueryBytes else {
            presentError(BundledLocalizationCatalogV1.v30PartsStockSearchTooLong(byteCount: PartsStockLimitsV1.maximumSearchQueryBytes), focus: .search)
            return
        }
        send(.search(.manualText(searchText)), message: BundledLocalizationCatalogV1.v30Text(.partsStockSearching))
    }

    private func submitManualLookup() {
        localErrorMessage = nil
        let value = manualLookupText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            presentError(BundledLocalizationCatalogV1.v30Text(.partsStockEnterCode), focus: .manualLookup)
            return
        }
        guard value.utf8.count <= PartsStockLimitsV1.maximumSearchQueryBytes else {
            presentError(BundledLocalizationCatalogV1.v30Text(.partsStockCodeTooLong), focus: .manualLookup)
            return
        }
        send(.search(.manualText(value)), message: BundledLocalizationCatalogV1.v30Text(.partsStockLookingUpCode))
    }

    private func submitUse(for item: PartsStockWorkflowCatalogItemV1) {
        localErrorMessage = nil
        guard !useQuantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentError(BundledLocalizationCatalogV1.v30Text(.partsStockEnterUseQuantity), focus: .useQuantity)
            return
        }
        sendWrite(
            .use(partID: item.id, quantityText: useQuantityText, materialText: useMaterialText),
            message: BundledLocalizationCatalogV1.v30PartsStockUseRequested(name: item.detail.part.displayName)
        )
    }

    private func submitReturn(_ candidate: PartsStockWorkflowReturnPresentationV1) {
        localErrorMessage = nil
        let quantity = returnQuantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quantity.isEmpty else {
            presentError(BundledLocalizationCatalogV1.v30Text(.partsStockEnterReturnQuantity), focus: .returnQuantity)
            return
        }
        sendWrite(
            .return(returnID: candidate.id, sourceUseReceiptID: candidate.sourceUse.receiptID, quantityText: quantity),
            message: BundledLocalizationCatalogV1.v30PartsStockReturnRequested(destination: candidate.destination.label)
        )
    }

    private func submitDraftCheckpoint() {
        guard model.draft?.canCheckpoint == true else {
            presentError(BundledLocalizationCatalogV1.v30Text(.partsStockCheckpointUnavailable), focus: .error)
            return
        }
        send(.checkpointDraft(draftMaterialText), message: BundledLocalizationCatalogV1.v30Text(.partsStockCheckpointRequested))
    }

    private func send(_ command: PartsStockWorkflowCommandV1, message: String) {
        localErrorMessage = nil
        localOperationMessage = message
        accessibilityFocus = .status
        onCommand(command)
    }

    private func sendWrite(_ command: PartsStockWorkflowCommandV1, message: String) {
        guard writesAllowed else {
            presentError(writeDisabledText, focus: .error)
            return
        }
        send(command, message: message)
    }

    private func presentError(_ message: String, focus: AccessibilityTarget) {
        localErrorMessage = message
        localOperationMessage = nil
        accessibilityFocus = focus
    }

    private var availabilityKind: WorklightStatusKind {
        switch model.availability {
        case .ready: return .complete
        case .offline, .featureDisabled, .interrupted, .stale: return .attention
        case .loading: return .information
        case .protectedData, .storageUnavailable, .unavailable: return .blocked
        }
    }

    private var availabilityText: String {
        switch model.availability {
        case .ready: return BundledLocalizationCatalogV1.v30Text(.partsStockStateReady)
        case .loading: return BundledLocalizationCatalogV1.v30Text(.partsStockStateLoading)
        case .featureDisabled: return BundledLocalizationCatalogV1.v30Text(.partsStockStateFeatureDisabled)
        case .offline: return BundledLocalizationCatalogV1.v30Text(.partsStockStateOffline)
        case .protectedData: return BundledLocalizationCatalogV1.v30Text(.partsStockStateProtectedData)
        case .storageUnavailable: return BundledLocalizationCatalogV1.v30Text(.partsStockStateStorageUnavailable)
        case .interrupted: return BundledLocalizationCatalogV1.v30Text(.partsStockStateInterrupted)
        case .stale: return BundledLocalizationCatalogV1.v30Text(.partsStockStateStale)
        case .unavailable: return BundledLocalizationCatalogV1.v30Text(.partsStockStateUnavailable)
        }
    }

    private var availabilityDetail: String {
        switch model.availability {
        case .ready:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateReadyDescription)
        case .loading:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateLoadingDescription)
        case .featureDisabled:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateFeatureDisabledDescription)
        case .offline:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateOfflineDescription)
        case .protectedData:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateProtectedDataDescription)
        case .storageUnavailable:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateStorageUnavailableDescription)
        case .interrupted:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateInterruptedDescription)
        case .stale:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateStaleDescription)
        case .unavailable:
            return BundledLocalizationCatalogV1.v30Text(.partsStockStateUnavailableDescription)
        }
    }

    private var writeDisabledText: String {
        if model.featurePolicy == .readExportRecoveryOnly {
            return BundledLocalizationCatalogV1.v30Text(.partsStockWriteDisabled)
        }
        switch model.availability {
        case .protectedData:
            return BundledLocalizationCatalogV1.v30Text(.partsStockWriteProtectedDataUnavailable)
        case .storageUnavailable:
            return BundledLocalizationCatalogV1.v30Text(.partsStockWriteStorageUnavailable)
        case .stale, .interrupted:
            return BundledLocalizationCatalogV1.v30Text(.partsStockWriteStale)
        default:
            return BundledLocalizationCatalogV1.v30Text(.partsStockWriteUnavailable)
        }
    }

    private var operationColor: Color {
        switch model.operation.state {
        case .receiptConfirmed: return DesignTokens.Colors.completeText
        case .failed, .stale: return DesignTokens.Colors.blockedText
        case .cancelled: return DesignTokens.Colors.attentionText
        case .idle, .awaitingReceipt: return DesignTokens.Colors.informationText
        }
    }

    private var operationBoundaryText: String {
        switch model.operation.state {
        case .receiptConfirmed:
            return BundledLocalizationCatalogV1.v30Text(.partsStockOperationReceipt)
        case .failed, .stale:
            return BundledLocalizationCatalogV1.v30Text(.partsStockOperationFailure)
        case .cancelled:
            return BundledLocalizationCatalogV1.v30Text(.partsStockOperationCancelled)
        case .awaitingReceipt:
            return BundledLocalizationCatalogV1.v30Text(.partsStockOperationPending)
        case .idle:
            return BundledLocalizationCatalogV1.v30Text(.partsStockOperationNoStatus)
        }
    }

    private func lookupResultText(_ result: PartsStockWorkflowLookupResultV1) -> String {
        switch result {
        case .idle: return BundledLocalizationCatalogV1.v30Text(.partsStockLookupIdle)
        case .found: return BundledLocalizationCatalogV1.v30Text(.partsStockLookupFound)
        case .ambiguous: return BundledLocalizationCatalogV1.v30Text(.partsStockLookupAmbiguous)
        case .notFound: return BundledLocalizationCatalogV1.v30Text(.partsStockLookupNotFound)
        case .foreign: return BundledLocalizationCatalogV1.v30Text(.partsStockLookupForeign)
        case .stale: return BundledLocalizationCatalogV1.v30Text(.partsStockLookupStale)
        case .manualFallback: return BundledLocalizationCatalogV1.v30Text(.partsStockLookupManualFallback)
        }
    }

    private func lowStockText(
        item: PartsStockWorkflowCatalogItemV1,
        attention: StockAttentionProjectionV1,
        location: String
    ) -> String {
        let balance: String
        switch attention.balance {
        case .unknown:
            balance = BundledLocalizationCatalogV1.v30Text(.partsStockUnknownBalance)
        case .known(let quantity):
            balance = quantityText(quantity, unit: item.detail.part.canonicalUnit)
        }
        return BundledLocalizationCatalogV1.v30PartsStockBalanceAccessibility(name: item.detail.part.displayName, location: location, balance: balance)
    }

    private func balanceText(_ projection: StockBalanceProjectionV1) -> String {
        switch projection.balance {
        case .unknown:
            return BundledLocalizationCatalogV1.v30Text(.partsStockUnknownBalanceDescription)
        case .known(let quantity):
            return BundledLocalizationCatalogV1.v30PartsStockBalance(quantity: quantityText(quantity, unit: projection.unit), revision: String(projection.locationRevision))
        }
    }

    private func archiveIsEligible(_ item: PartsStockWorkflowCatalogItemV1) -> Bool {
        guard !item.balances.isEmpty else { return false }
        return item.balances.allSatisfy {
            guard case .known(let quantity) = $0.projection.balance else { return false }
            return quantity.mantissa == 0
        }
    }

    private func isUnknown(_ balance: StockBalanceV1) -> Bool {
        if case .unknown = balance { return true }
        return false
    }

    private func quantityText(_ quantity: StockQuantityV1, unit: StockUnitV1) -> String {
        "\(quantityTextWithoutUnit(quantity)) \(unitText(unit))"
    }

    private func quantityTextWithoutUnit(_ quantity: StockQuantityV1) -> String {
        let digits = String(quantity.mantissa)
        guard quantity.scale > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, quantity.scale - digits.count + 1)) + digits
        let split = padded.index(padded.endIndex, offsetBy: -quantity.scale)
        return String(padded[..<split]) + "." + String(padded[split...])
    }

    private func unitText(_ unit: StockUnitV1) -> String {
        unit.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    private func csvStateText(_ state: PartsStockWorkflowCSVStateV1, rows: Int?) -> String {
        let base: String
        switch state {
        case .idle: base = BundledLocalizationCatalogV1.v30Text(.partsStockCsvIdle)
        case .previewing: base = BundledLocalizationCatalogV1.v30Text(.partsStockCsvPreviewing)
        case .previewReady: base = BundledLocalizationCatalogV1.v30Text(.partsStockCsvPreviewReady)
        case .committing: base = BundledLocalizationCatalogV1.v30Text(.partsStockCsvCommitting)
        case .receiptConfirmed: base = BundledLocalizationCatalogV1.v30Text(.partsStockCsvReceiptConfirmed)
        case .cancelled: base = BundledLocalizationCatalogV1.v30Text(.partsStockCsvCancelled)
        case .failed: base = BundledLocalizationCatalogV1.v30Text(.partsStockCsvFailed)
        }
        guard let rows else { return base }
        return BundledLocalizationCatalogV1.v30PartsStockCsvRows(state: base, rows: rows)
    }

    private func draftStateText(_ state: PartsStockWorkflowDraftStateV1) -> String {
        switch state {
        case .absent: return BundledLocalizationCatalogV1.v30Text(.partsStockDraftAbsent)
        case .active: return BundledLocalizationCatalogV1.v30Text(.partsStockDraftActive)
        case .dirty: return BundledLocalizationCatalogV1.v30Text(.partsStockDraftDirty)
        case .checkpointed: return BundledLocalizationCatalogV1.v30Text(.partsStockDraftCheckpointed)
        case .interrupted: return BundledLocalizationCatalogV1.v30Text(.partsStockDraftInterrupted)
        case .protectedData: return BundledLocalizationCatalogV1.v30Text(.partsStockDraftProtectedData)
        case .unavailable: return BundledLocalizationCatalogV1.v30Text(.partsStockDraftUnavailable)
        }
    }

    private func shortID(_ value: UUID) -> String {
        String(value.uuidString.prefix(8)).lowercased()
    }
}
