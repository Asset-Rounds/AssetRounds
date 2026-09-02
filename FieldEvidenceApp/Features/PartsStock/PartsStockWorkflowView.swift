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
        .navigationTitle("Parts & Stock")
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
            Text("Parts & Stock")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("A Work-local catalog for explicit count, adjustment, transfer, use, return, and archive actions. It does not prove identity, ownership, valuation, delivery, or authority.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var workEntry: some View {
        WorklightCard {
            sectionHeading("Work entry", identifier: Self.workRootAccessibilityIdentifier)
            Text("Visible path: Work → Parts & Stock → catalog or search → item detail. Use and Return remain contextual actions in the supplied work/material lineage.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Parts & Stock catalog") {
                send(.openCatalog, message: "Requested the Parts & Stock catalog. No route-open or live-root adoption is claimed.")
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!canRead)
            .accessibilityHint("Opens the contained catalog view when the caller supplies the route. It does not register a new root.")
            .accessibilityIdentifier("\(Self.workRootAccessibilityIdentifier).open")
        }
        .accessibilityElement(children: .contain)
    }

    private var availability: some View {
        WorklightCard {
            sectionHeading("Availability", identifier: Self.availabilityAccessibilityIdentifier)
            WorklightStatusBadge(kind: availabilityKind, text: availabilityText)
            Text(availabilityDetail)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.featurePolicy == .readExportRecoveryOnly {
                Text("Writes are disabled by the supplied feature policy. Catalog reads, export, recovery, and existing drafts remain preserved.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var searchAndLookup: some View {
        WorklightCard {
            sectionHeading("Search and lookup", identifier: Self.searchAccessibilityIdentifier)
            Text("Search uses the Work-local catalog and stock-namespaced product identities. Typing or scanning is query-only and never creates a movement, receipt, or durable scan record.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Search parts or product code", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($keyboardFocus, equals: .search)
                .accessibilityLabel("Search parts or product code")
                .accessibilityHint("Searches local catalog names and stock product identities. It does not change stock.")
                .accessibilityIdentifier(Self.searchFieldAccessibilityIdentifier)
            Button("Search catalog") {
                submitSearch()
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!canRead)
            .keyboardShortcut("f", modifiers: [.command])
            .accessibilityIdentifier("\(Self.searchAccessibilityIdentifier).submit")

            Text("Typing or scanning a material line changes no stock. Only the explicit Use from stock action can request a stock mutation.")
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
                Button("Scan stock code") {
                    send(.scan, message: "Requested a stock-code scan. Scanning remains query-only; no stock effect is claimed.")
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canRead)
                .accessibilityHint("Scans a stock-namespaced code for local lookup. Manual lookup remains available.")
                .accessibilityIdentifier(Self.scanAccessibilityIdentifier)
            case .permissionDenied:
                Text("Camera access was not granted for stock lookup. Enter a stock code manually; manual lookup has the same local, zero-write semantics.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.scanAccessibilityIdentifier)
            case .unavailable, .unsupported:
                Text("Scan is unavailable here. Enter a stock code manually; no scan permission or network lookup is required.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.scanAccessibilityIdentifier)
            }

            TextField("Enter stock code manually", text: $manualLookupText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($keyboardFocus, equals: .manualLookup)
                .accessibilityLabel("Enter stock code manually")
                .accessibilityHint("Manual lookup is the complete fallback when scanning is unavailable. It does not change stock.")
                .accessibilityIdentifier(Self.manualLookupFieldAccessibilityIdentifier)
            Button("Look up code manually") {
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
                sectionHeading("Lookup result", identifier: "\(Self.lookupAccessibilityIdentifier).result")
                Text(lookup.message ?? lookupResultText(lookup.result))
                    .font(.body)
                    .foregroundStyle(lookup.result == .found ? DesignTokens.Colors.primaryText : DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
                if let matchedPartID = lookup.matchedPartID {
                    Text("Matched catalog item: \(shortID(matchedPartID))")
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
            sectionHeading("Low-stock attention", identifier: Self.lowStockAccessibilityIdentifier)
            Text("Preferred minimum produces an in-app attention only. It is not purchase, reorder, valuation, or availability truth.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            let attentionRows = model.catalog.flatMap { item in
                item.detail.attention
                    .filter { $0.isBelowPreferred || isUnknown($0.balance) }
                    .map { (item, $0) }
            }
            if attentionRows.isEmpty {
                Text("No below-preferred or unknown balance attention is supplied.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.catalog) { item in
                    let rows = item.detail.attention.filter { $0.isBelowPreferred || isUnknown($0.balance) }
                    ForEach(rows, id: \.locationID) { attention in
                        let location = item.balances.first { $0.id == attention.locationID }?.location.label
                            ?? "Storage location \(shortID(attention.locationID))"
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
            sectionHeading("Catalog", identifier: Self.catalogAccessibilityIdentifier)
            Text("Catalog definitions are Work-local. Select an item to review its supplied unit, product identities, balance projections, and explicit actions.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if model.catalog.isEmpty {
                Text("No catalog items are supplied. This surface does not create a part implicitly from a search, scan, material line, or report.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.catalog) { item in
                    Button {
                        send(.selectPart(item.id), message: "Selected \(item.detail.part.displayName). The supplied detail remains the source of truth.")
                    } label: {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            Text(item.detail.part.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DesignTokens.Colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Unit: \(unitText(item.detail.part.canonicalUnit)); product identities: \(item.detail.part.productIdentities.count); revision: \(item.detail.part.revision)")
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.detail.part.archived ? "Archived catalog definition" : "Active catalog definition")
                                .font(.footnote)
                                .foregroundStyle(item.detail.part.archived ? DesignTokens.Colors.attentionText : DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityLabel("View details for \(item.detail.part.displayName)")
                    .accessibilityHint("Opens the supplied item detail and its explicit stock actions.")
                    .accessibilityIdentifier("\(Self.catalogItemAccessibilityIdentifierPrefix)\(item.id.uuidString.lowercased())")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func detail(for item: PartsStockWorkflowCatalogItemV1) -> some View {
        WorklightCard {
            sectionHeading("Item detail", identifier: Self.detailAccessibilityIdentifier)
                .accessibilityFocused($accessibilityFocus, equals: .selectedPart)
            Text("\(item.detail.part.displayName), supplied catalog revision \(item.detail.part.revision)")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow("Canonical unit", value: unitText(item.detail.part.canonicalUnit))
            valueRow("Product identities", value: item.detail.part.productIdentities.isEmpty ? "None supplied" : item.detail.part.productIdentities.map(\.value).joined(separator: ", "))
            valueRow("Preferred minimum", value: item.detail.part.preferredMinimum.map { quantityText($0, unit: item.detail.part.canonicalUnit) } ?? "Not supplied")

            if item.balances.isEmpty {
                Text("No balance projection is supplied. An absent projection is UNKNOWN, not zero; count is required before a quantity-affecting operation.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text("Balance projections")
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

            Text("Typing or scanning a material line only edits the supplied work draft. Stock changes only after an explicit Use from stock request is accepted by the canonical owner.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.informationText)
                .fixedSize(horizontal: false, vertical: true)

            explicitActions(for: item)
        }
        .accessibilityElement(children: .contain)
    }

    private func explicitActions(for item: PartsStockWorkflowCatalogItemV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading("Explicit actions", identifier: "\(Self.detailAccessibilityIdentifier).actions")
            actionButton(
                title: "Count",
                command: .count(item.id),
                identifier: Self.countAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived,
                hint: "Records an explicit opening or physical count through the canonical stock owner. UNKNOWN is never treated as zero."
            )
            actionButton(
                title: "Adjust",
                command: .adjust(item.id),
                identifier: Self.adjustAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived,
                hint: "Requests a reasoned adjustment only when the supplied source balance is known."
            )
            actionButton(
                title: "Transfer",
                command: .transfer(item.id),
                identifier: Self.transferAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived,
                hint: "Requests one atomic transfer between two supplied known locations."
            )
            useEditor(for: item)
            actionButton(
                title: "Archive",
                command: .archive(item.id),
                identifier: Self.archiveAccessibilityIdentifier,
                enabled: writesAllowed && !item.detail.part.archived && archiveIsEligible(item),
                hint: archiveIsEligible(item)
                    ? "Archives only after every affected location is supplied as known zero."
                    : "Archive is unavailable until every affected location is known zero or its explicit unknown disposition is handled by the canonical owner."
            )
            if item.detail.part.archived {
                Text("This catalog definition is archived. History remains readable; no new quantity-affecting operation is available.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !archiveIsEligible(item) {
                Text("Archive is blocked until all affected locations are known zero. UNKNOWN is not a zero balance and is never silently abandoned.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("\(Self.detailAccessibilityIdentifier).actions")
    }

    private func useEditor(for item: PartsStockWorkflowCatalogItemV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading("Use from stock", identifier: Self.useAccessibilityIdentifier)
            Text("Use is explicit and contextual to this catalog item and supplied work/material line. The canonical owner must recheck the known source balance and work revision before decrementing stock.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Quantity to use", text: $useQuantityText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .focused($keyboardFocus, equals: .useQuantity)
                .accessibilityLabel("Quantity to use in \(unitText(item.detail.part.canonicalUnit))")
                .accessibilityHint("Enter an exact nonnegative quantity. No stock changes while typing.")
                .accessibilityIdentifier(Self.useQuantityAccessibilityIdentifier)
            TextField("Material line or work note", text: $useMaterialText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($keyboardFocus, equals: .useMaterial)
                .accessibilityLabel("Material line or work note")
                .accessibilityHint("Typing this line does not change stock. It is sent only when Use from stock is explicitly requested.")
                .accessibilityIdentifier(Self.useMaterialAccessibilityIdentifier)
            Button("Use from stock") {
                submitUse(for: item)
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!writesAllowed || item.detail.part.archived)
            .accessibilityHint("Requests the only stock-decrementing action in this surface. A durable canonical receipt must be supplied before any effect is shown.")
            .accessibilityIdentifier("\(Self.useAccessibilityIdentifier).submit")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var returnSection: some View {
        if model.eligibleReturns.isEmpty {
            WorklightCard {
                sectionHeading("Return boundary", identifier: Self.returnAccessibilityIdentifier)
                Text("No eligible prior Use is supplied. No standalone Return action is available. A Return can appear only after one exact Use receipt, its work-material lineage, an outstanding quantity, and a known destination are supplied.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
        } else {
            WorklightCard {
                sectionHeading("Return against a prior Use", identifier: Self.returnAccessibilityIdentifier)
                Text("Return is bound to an eligible prior Use. Each candidate shows its outstanding quantity and destination; the canonical owner rejects stale, concurrent, duplicate, or overflow returns without a partial effect.")
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
            valueRow("Use receipt", value: shortID(candidate.sourceUse.receiptID))
            valueRow("Used", value: quantityText(candidate.sourceUse.movement.quantity, unit: candidate.sourceUse.movement.unit))
            valueRow("Outstanding", value: quantityText(candidate.outstandingQuantity, unit: candidate.sourceUse.movement.unit))
            valueRow("Destination", value: candidate.destination.label)
            Button("Review return for this Use") {
                selectedReturnID = candidate.id
                returnQuantityText = quantityTextWithoutUnit(candidate.outstandingQuantity)
                accessibilityFocus = .returnQuantity
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!writesAllowed)
            .accessibilityHint("Opens the quantity field for a Return bound to this exact prior Use. It is not a standalone Return.")
            .accessibilityIdentifier("\(Self.returnCandidateAccessibilityIdentifierPrefix)\(candidate.id.uuidString.lowercased())")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(Self.returnCandidateAccessibilityIdentifierPrefix)\(candidate.id.uuidString.lowercased()).row")
    }

    private func returnEditor(_ candidate: PartsStockWorkflowReturnPresentationV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading("Return quantity", identifier: "\(Self.returnAccessibilityIdentifier).editor")
            Text("Returning to \(candidate.destination.label). Remaining amount for this Use: \(quantityText(candidate.outstandingQuantity, unit: candidate.sourceUse.movement.unit)).")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Quantity to return", text: $returnQuantityText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .focused($keyboardFocus, equals: .returnQuantity)
                .accessibilityLabel("Quantity to return to \(candidate.destination.label)")
                .accessibilityHint("Enter a positive quantity no greater than this Use's outstanding amount. The canonical owner checks the ordered return frontier.")
                .accessibilityIdentifier(Self.returnQuantityAccessibilityIdentifier)
            Button("Return to \(candidate.destination.label)") {
                submitReturn(candidate)
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!writesAllowed)
            .accessibilityHint("Requests a Return against the selected prior Use. It cannot create a free-form positive movement or exceed the outstanding quantity.")
            .accessibilityIdentifier("\(Self.returnAccessibilityIdentifier).submit")
        }
        .accessibilityElement(children: .contain)
    }

    private var history: some View {
        WorklightCard {
            sectionHeading("History", identifier: Self.historyAccessibilityIdentifier)
            Text("History here is caller-supplied immutable context. It does not replay movements, create a new stock event, or make a balance, delivery, approval, identity, or legal-effect claim.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.history.isEmpty {
                Text("No history projection is supplied. This view does not reconstruct events or infer a receipt.")
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
            sectionHeading("Draft preservation", identifier: Self.draftAccessibilityIdentifier)
            if let draft = model.draft, draft.state != .absent {
                Text(draftStateText(draft.state))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let draftID = draft.draftID {
                    valueRow("Draft", value: shortID(draftID))
                }
                if let revision = draft.revision {
                    valueRow("Draft revision", value: "\(revision)")
                }
                TextField("Material line draft", text: $draftMaterialText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($keyboardFocus, equals: .draftMaterial)
                    .accessibilityLabel("Material line draft")
                    .accessibilityHint("Typing or editing this draft never changes stock. Checkpointing remains an explicit caller action.")
                    .accessibilityIdentifier("\(Self.draftAccessibilityIdentifier).material")
                Button("Checkpoint draft") {
                    submitDraftCheckpoint()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!draft.canCheckpoint)
                .accessibilityHint("Requests the existing draft authority to checkpoint this text. The view does not claim Saved until the caller supplies a confirmed state.")
                .accessibilityIdentifier(Self.checkpointAccessibilityIdentifier)
                if let message = draft.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("If protected data, storage, cancellation, interruption, or relaunch occurs, the caller-supplied draft remains the source of truth. Uncheckpointed text is not presented as saved.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No draft is supplied. This surface does not create, discard, or infer a draft from a catalog search or typed material line.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var csv: some View {
        WorklightCard {
            sectionHeading("Catalog CSV", identifier: Self.csvAccessibilityIdentifier)
            Text("Exact schema: \(model.csv.schemaIdentifier). Import is preview-first and validates the complete source before any canonical command. Export is deterministic catalog data only.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow("Import", value: csvStateText(model.csv.importState, rows: model.csv.importPlan?.rows.count ?? model.csv.importResult?.expectedRowCount))
            valueRow("Export", value: csvStateText(model.csv.exportState, rows: nil))
            if let message = model.csv.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Preview CSV import") {
                sendWrite(.importCSV, message: "Requested exact \(PartsStockWorkflowCatalogV1.identifier) import preview. Preview is zero-write; no catalog change is claimed.")
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!model.csv.importAvailable || !writesAllowed)
            .accessibilityHint("Previews the exact catalog CSV schema before an explicit canonical import command. It does not write during preview.")
            .accessibilityIdentifier(Self.importAccessibilityIdentifier)
            Button("Export catalog CSV") {
                send(.exportCSV, message: "Requested deterministic \(PartsStockWorkflowCatalogV1.identifier) export. No delivery, sync, or provider result is claimed.")
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(!model.csv.exportAvailable || !canRead)
            .accessibilityHint("Exports exact catalog definitions. Balances and internal storage locations are omitted.")
            .accessibilityIdentifier(Self.exportAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
    }

    private var truthBoundaries: some View {
        WorklightCard {
            sectionHeading("Truth and accessibility boundaries", identifier: Self.boundariesAccessibilityIdentifier)
            Text("Customer-safe work-material reports contain only reviewed material snapshots. They never contain stock balances or internal storage locations.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("All actions have visible labels and text fallbacks for VoiceOver, Voice Control, Switch Control, keyboard, and motor access. No scan is required; manual lookup is complete. Quantity and revision errors are returned to the caller without a partial canonical effect.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("At Accessibility Dynamic Type sizes content reflows vertically without truncation. Leading alignment, system controls, and text-based labels support RTL. Reduce Motion removes view-owned state-change animation.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("This contained surface has zero live root adoption before S10.6. It does not claim a route, store write, network lookup, camera permission, receipt, delivery, approval, identity, or legal effect.")
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
                Label("Action needs attention", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(displayedErrorMessage)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .error)
                Text("No partial stock, catalog, draft, import, or return effect is inferred. Review the supplied projection and retry the same typed command when the owner reports a recoverable state.")
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
                sectionHeading("Operation status", identifier: Self.statusAccessibilityIdentifier)
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
            sendWrite(command, message: "Requested explicit \(title) for the selected catalog item. Waiting for the canonical owner; no completion is inferred.")
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
            presentError("Search text is too long. Enter at most \(PartsStockLimitsV1.maximumSearchQueryBytes) UTF-8 bytes.", focus: .search)
            return
        }
        send(.search(.manualText(searchText)), message: "Searching the Work-local catalog. Search is zero-write.")
    }

    private func submitManualLookup() {
        localErrorMessage = nil
        let value = manualLookupText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            presentError("Enter a stock code for manual lookup. No stock change occurs while typing.", focus: .manualLookup)
            return
        }
        guard value.utf8.count <= PartsStockLimitsV1.maximumSearchQueryBytes else {
            presentError("The stock code is too long for local lookup.", focus: .manualLookup)
            return
        }
        send(.search(.manualText(value)), message: "Looking up the stock code locally. Lookup is zero-write and does not create a scan record.")
    }

    private func submitUse(for item: PartsStockWorkflowCatalogItemV1) {
        localErrorMessage = nil
        guard !useQuantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentError("Enter a quantity before requesting Use from stock. Typing the material line alone never changes stock.", focus: .useQuantity)
            return
        }
        sendWrite(
            .use(partID: item.id, quantityText: useQuantityText, materialText: useMaterialText),
            message: "Requested explicit Use from stock for \(item.detail.part.displayName). Waiting for a canonical receipt; no decrement is claimed yet."
        )
    }

    private func submitReturn(_ candidate: PartsStockWorkflowReturnPresentationV1) {
        localErrorMessage = nil
        let quantity = returnQuantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quantity.isEmpty else {
            presentError("Enter a positive return quantity no greater than the outstanding amount for this Use.", focus: .returnQuantity)
            return
        }
        sendWrite(
            .return(returnID: candidate.id, sourceUseReceiptID: candidate.sourceUse.receiptID, quantityText: quantity),
            message: "Requested a Return against the selected prior Use to \(candidate.destination.label). The canonical owner must verify the ordered frontier; no return effect is claimed yet."
        )
    }

    private func submitDraftCheckpoint() {
        guard model.draft?.canCheckpoint == true else {
            presentError("This draft cannot be checkpointed in the current supplied state.", focus: .error)
            return
        }
        send(.checkpointDraft(draftMaterialText), message: "Requested a draft checkpoint. No Saved claim is made until the existing draft authority supplies its result.")
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
        case .ready: return "Ready for supplied local catalog work"
        case .loading: return "Loading supplied local state"
        case .featureDisabled: return "Writes disabled; read, export, and recovery preserved"
        case .offline: return "Offline local operation"
        case .protectedData: return "Protected data unavailable"
        case .storageUnavailable: return "Local storage unavailable"
        case .interrupted: return "Interrupted; recovery needed"
        case .stale: return "Stale projection; reload needed"
        case .unavailable: return "Parts & Stock unavailable"
        }
    }

    private var availabilityDetail: String {
        switch model.availability {
        case .ready:
            return "The caller supplied a local projection. Every quantity-affecting action still requires an explicit command and a canonical receipt."
        case .loading:
            return "The projection is not ready. No catalog mutation, draft save, import, return, or stock effect is claimed."
        case .featureDisabled:
            return "The feature policy preserves catalog reads, exact export, recovery, and existing drafts while blocking new Count, Adjust, Transfer, Use, Return, and Archive writes."
        case .offline:
            return "This workflow is device-local and has no network dependency. Local reads, manual lookup, drafts, and owner-approved writes can remain available; no remote availability is inferred."
        case .protectedData:
            return "Protected local data is unavailable. The last readable state is not reconstructed, and no write is attempted. Retry after the caller reports protected data available."
        case .storageUnavailable:
            return "Local storage is unavailable or below its preflight requirement. Existing state remains untouched; retry after storage recovery."
        case .interrupted:
            return "An operation was interrupted. Reload canonical projections before retrying; this view never infers a partial effect."
        case .stale:
            return "The supplied revision is stale. Reload the catalog and operation frontier before retrying the same intent."
        case .unavailable:
            return "The caller could not supply a valid local Parts & Stock projection. No operation is available."
        }
    }

    private var writeDisabledText: String {
        if model.featurePolicy == .readExportRecoveryOnly {
            return "Parts & Stock writes are disabled. Catalog reads, exact export, recovery, and existing drafts remain available; no stock effect is claimed."
        }
        switch model.availability {
        case .protectedData:
            return "Protected data is unavailable. No write was attempted; the existing draft and canonical state remain the source of truth."
        case .storageUnavailable:
            return "Local storage is unavailable. No write was attempted and no partial effect is claimed."
        case .stale, .interrupted:
            return "The supplied projection is not current. Reload before retrying; no partial effect is claimed."
        default:
            return "This action is unavailable in the current supplied state. No write was attempted."
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
            return "The caller supplied a canonical receipt. This view reports that fact only; it does not infer additional balance, work, delivery, or customer-report effects."
        case .failed, .stale:
            return "The operation did not produce a confirmed canonical effect. Review the error and reload before retrying."
        case .cancelled:
            return "Cancellation makes no completion or stock-effect claim."
        case .awaitingReceipt:
            return "Waiting for the canonical owner. A request is not a receipt and does not prove a stock effect."
        case .idle:
            return "No canonical operation status is supplied."
        }
    }

    private func lookupResultText(_ result: PartsStockWorkflowLookupResultV1) -> String {
        switch result {
        case .idle: return "No lookup has been performed."
        case .found: return "A matching local catalog item was found."
        case .ambiguous: return "More than one local item matched. Choose an exact catalog item; no stock effect occurred."
        case .notFound: return "No local catalog item matched. Manual entry remains available; no network lookup was attempted."
        case .foreign: return "The code does not belong to this Work-local catalog. No cross-workspace item was adopted."
        case .stale: return "The lookup became stale. Reload the local catalog before selecting an item."
        case .manualFallback: return "Manual lookup is required. It remains a complete zero-write fallback."
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
            balance = "UNKNOWN; count required"
        case .known(let quantity):
            balance = quantityText(quantity, unit: item.detail.part.canonicalUnit)
        }
        return "\(item.detail.part.displayName), \(location): \(balance)"
    }

    private func balanceText(_ projection: StockBalanceProjectionV1) -> String {
        switch projection.balance {
        case .unknown:
            return "Balance: UNKNOWN; count required before quantity-affecting actions"
        case .known(let quantity):
            return "Balance: \(quantityText(quantity, unit: projection.unit)); revision \(projection.locationRevision)"
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
        case .idle: base = "Not prepared"
        case .previewing: base = "Preview in progress"
        case .previewReady: base = "Preview ready; no write"
        case .committing: base = "Explicit commit in progress"
        case .receiptConfirmed: base = "Canonical receipt confirmed"
        case .cancelled: base = "Cancelled; no completion claimed"
        case .failed: base = "Failed; prior state preserved"
        }
        guard let rows else { return base }
        return "\(base), \(rows) row\(rows == 1 ? "" : "s")"
    }

    private func draftStateText(_ state: PartsStockWorkflowDraftStateV1) -> String {
        switch state {
        case .absent: return "No draft supplied"
        case .active: return "Draft supplied"
        case .dirty: return "Draft has uncheckpointed edits"
        case .checkpointed: return "Draft checkpoint supplied"
        case .interrupted: return "Draft interrupted; recovery supplied"
        case .protectedData: return "Draft held while protected data is unavailable"
        case .unavailable: return "Draft unavailable; no draft claim made"
        }
    }

    private func shortID(_ value: UUID) -> String {
        String(value.uuidString.prefix(8)).lowercased()
    }
}
