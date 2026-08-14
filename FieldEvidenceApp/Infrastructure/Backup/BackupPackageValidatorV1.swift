import Darwin
import Foundation
import PDFKit

enum BackupPackageValidationErrorV1: Error, Equatable {
    case invalidPackage
}

struct BackupValidationSummaryV1: Equatable, Sendable {
    let incomingSignCount: Int
    let incomingReportCount: Int
    let incomingPhotoCount: Int
    let exportedAt: Date
    let declaredPayloadByteCount: Int
    let packs: [V4BackupPackV1]
    let consumedRootCount: Int
    let liveSlotCount: Int
    let tombstonedSlotCount: Int
}

struct ValidatedV4BackupPackageV1: Equatable, Sendable {
    let stagedPackageURL: URL
    let manifest: V4BackupManifestV1
    let records: V4BackupRecordsV1
    let members: [String: Data]
    let summary: BackupValidationSummaryV1
}

struct BackupPackageValidatorV1 {
    private let fileManager: FileManager
    private let signPack: SignPack

    init(
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1
    ) {
        self.fileManager = fileManager
        self.signPack = signPack
    }

    func validate(stagedPackageURL: URL) throws -> ValidatedV4BackupPackageV1 {
        do {
            return try validatePackage(stagedPackageURL: stagedPackageURL)
        } catch {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }
}

private extension BackupPackageValidatorV1 {
    func validatePackage(stagedPackageURL: URL) throws -> ValidatedV4BackupPackageV1 {
        let root = stagedPackageURL.standardizedFileURL
        guard stagedPackageURL.isFileURL,
              root.pathExtension == "fieldrecordbackup",
              root.lastPathComponent == root.lastPathComponent.precomposedStringWithCanonicalMapping,
              try itemType(root) == .directory else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        let manifestData = try anchoredRead(
            "manifest.json",
            root: root,
            identity: rootIdentity
        )
        let decoder = BackupCanonicalDecoderV1()
        let manifest = try decoder.decodeManifest(manifestData)
        let expectedFiles = Set(["manifest.json"] + manifest.entries.map(\.path))
        let expectedDirectories = Set(manifest.entries.compactMap { entry in
            entry.path == "records.json" ? nil : entry.path.split(separator: "/").first.map(String.init)
        })
        let enumerated = try enumerate(root: root)
        guard enumerated.files == expectedFiles,
              enumerated.directories == expectedDirectories,
              try ReportPDFAnchoredFile.rootIdentity(at: root) == rootIdentity else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }

        var members = ["manifest.json": manifestData]
        for entry in manifest.entries {
            let bytes = try anchoredRead(entry.path, root: root, identity: rootIdentity)
            guard bytes.count == entry.byteCount,
                  CanonicalJSONV1.sha256(bytes) == entry.sha256 else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            members[entry.path] = bytes
        }
        guard members.count == expectedFiles.count,
              let recordsData = members["records.json"] else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let records = try decoder.decodeRecords(recordsData)
        try validateGraph(records, manifest: manifest)
        try validateOwnedMembers(records, manifest: manifest, members: members)
        try validateReports(records, members: members)
        guard try ReportPDFAnchoredFile.rootIdentity(at: root) == rootIdentity else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }

        let liveSlots = records.packets.filter { $0.currentRecordID != nil }.count
        let tombstones = records.packets.filter { $0.currentRecordID == nil }.count
        return ValidatedV4BackupPackageV1(
            stagedPackageURL: root,
            manifest: manifest,
            records: records,
            members: members,
            summary: .init(
                incomingSignCount: records.assets.count,
                incomingReportCount: records.reports.count,
                incomingPhotoCount: records.evidenceFiles.count,
                exportedAt: manifest.exportedAt,
                declaredPayloadByteCount: manifest.declaredPayloadByteCount,
                packs: manifest.packs,
                consumedRootCount: manifest.consumedEvaluationRootIDs.count,
                liveSlotCount: liveSlots,
                tombstonedSlotCount: tombstones
            )
        )
    }

    struct Enumeration {
        var files = Set<String>()
        var directories = Set<String>()
    }

    enum ItemType { case directory, regular }

    func enumerate(root: URL) throws -> Enumeration {
        var result = Enumeration()
        let roots = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )
        var folded = Set<String>()
        for value in roots {
            let name = value.lastPathComponent
            try validateComponent(name)
            guard folded.insert(fold(name)).inserted else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            switch try itemType(value) {
            case .regular:
                guard name == "manifest.json" || name == "records.json",
                      result.files.insert(name).inserted else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
            case .directory:
                guard ["media", "thumbnails", "snapshots", "pdfs"].contains(name),
                      result.directories.insert(name).inserted else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
                let children = try fileManager.contentsOfDirectory(
                    at: value,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                guard !children.isEmpty else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
                var childFolded = Set<String>()
                for child in children {
                    let childName = child.lastPathComponent
                    try validateComponent(childName)
                    guard childFolded.insert(fold(childName)).inserted,
                          try itemType(child) == .regular else {
                        throw BackupPackageValidationErrorV1.invalidPackage
                    }
                    let relative = "\(name)/\(childName)"
                    guard result.files.insert(relative).inserted else {
                        throw BackupPackageValidationErrorV1.invalidPackage
                    }
                }
            }
        }
        return result
    }

    func itemType(_ url: URL) throws -> ItemType {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        switch information.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFREG:
            guard information.st_nlink == 1 else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            return .regular
        default:
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }

    func validateComponent(_ value: String) throws {
        guard !value.isEmpty,
              value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"),
              value == value.precomposedStringWithCanonicalMapping,
              !value.unicodeScalars.contains(where: {
                  $0.value < 0x20 || $0.value == 0x7f
              }),
              value.removingPercentEncoding == value else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }

    func fold(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    func anchoredRead(
        _ path: String,
        root: URL,
        identity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> Data {
        guard validRelativePath(path) else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        return try ReportPDFAnchoredFile.readRegularFile(
            at: root.appendingPathComponent(path),
            within: root,
            rootIdentity: identity
        )
    }

    func validRelativePath(_ value: String) -> Bool {
        guard value == value.precomposedStringWithCanonicalMapping,
              !value.hasPrefix("/"), !value.contains("\\"),
              value.removingPercentEncoding == value else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
                && !component.unicodeScalars.contains(where: {
                    $0.value < 0x20 || $0.value == 0x7f
                })
        }
    }
}

private extension BackupPackageValidatorV1 {
    func validateGraph(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        let allIDs = records.sites.map(\.id) + records.assets.map(\.id)
            + records.workflowRecords.map(\.id) + records.evidenceFiles.map(\.id)
            + records.issues.map(\.id) + records.packets.map(\.id)
            + records.reports.map(\.id)
        guard Set(allIDs).count == allIDs.count else { throw invalid() }
        let sites = Dictionary(uniqueKeysWithValues: records.sites.map { ($0.id, $0) })
        let assets = Dictionary(uniqueKeysWithValues: records.assets.map { ($0.id, $0) })
        let workflow = Dictionary(uniqueKeysWithValues: records.workflowRecords.map { ($0.id, $0) })
        let issues = Dictionary(uniqueKeysWithValues: records.issues.map { ($0.id, $0) })
        let packets = Dictionary(uniqueKeysWithValues: records.packets.map { ($0.id, $0) })
        let reports = Dictionary(uniqueKeysWithValues: records.reports.map { ($0.id, $0) })
        let exactPack = signPack
        guard records.sites.allSatisfy({ site in
                  site.schemaVersion == 1
                    && site.updatedAt >= site.createdAt
                    && validRequiredTrimmed(site.label, maximum: .max)
                    && (site.address.map({
                        validRequiredTrimmed($0, maximum: .max)
                    }) ?? true)
                    && (site.timeZoneID.map({ value in
                        value == value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ) && TimeZone.knownTimeZoneIdentifiers.contains(value)
                    }) ?? true)
                    && records.assets.contains(where: { $0.siteID == site.id })
              }),
              records.assets.allSatisfy({ asset in
                  asset.schemaVersion == 1
                    && asset.updatedAt >= asset.createdAt
                    && validRequiredTrimmed(asset.label, maximum: .max)
                    && sites[asset.siteID] != nil
                    && asset.packID == exactPack.packID
                    && asset.packSchemaVersion == exactPack.schemaVersion
                    && asset.packContentVersion == exactPack.contentVersion
              }),
              records.evidenceFiles.allSatisfy({ $0.schemaVersion == 1 }),
              records.issues.allSatisfy({ $0.schemaVersion == 1 }),
              records.packets.allSatisfy({ $0.schemaVersion == 1 }),
              records.reports.allSatisfy({ $0.schemaVersion == 1 }),
              records.workflowRecords.allSatisfy({ $0.schemaVersion == 1 }) else {
            throw invalid()
        }

        for record in records.workflowRecords {
            guard assets[record.assetID] != nil,
                  let kind = WorkflowRevisionKind(rawValue: record.revisionKind),
                  WorkflowStage(rawValue: record.stage) != nil,
                  let state = WorkflowState(rawValue: record.state),
                  record.packID == exactPack.packID,
                  record.packSchemaVersion == exactPack.schemaVersion,
                  record.packContentVersion == exactPack.contentVersion,
                  record.pdfTemplateID == "field.evidence.pdf.worklight.v1",
                  record.pdfTemplateVersion == 1,
                  record.parentRecordID.map({ workflow[$0]?.assetID == record.assetID }) ?? true,
                  record.issueID.map({ issues[$0]?.assetID == record.assetID }) ?? true else {
                throw invalid()
            }
            switch state {
            case .draft:
                guard record.completedAt == nil, record.packetID == nil,
                      record.finalizationMutationID == nil,
                      record.outcomeKey == nil,
                      validDraftSemantics(
                          record,
                          workflow: workflow,
                          issues: issues
                      ) else {
                    throw invalid()
                }
            case .completed:
                guard record.completedAt.map({ $0 >= record.startedAt }) == true,
                      record.finalizationMutationID != nil,
                      record.outcomeKey != nil,
                      record.draftStepKey == nil,
                      validCompletedSemantics(record),
                      record.packetID.map({ packets[$0] != nil }) ?? true else {
                    throw invalid()
                }
            }
            guard let root = workflow[record.recordRevisionRootID],
                  root.assetID == record.assetID,
                  root.revisionKind == WorkflowRevisionKind.original.rawValue,
                  root.recordRevisionRootID == root.id,
                  root.revisesRecordID == nil,
                  root.evidenceSourceRecordID == nil else { throw invalid() }
            switch kind {
            case .original:
                guard record.recordRevisionRootID == record.id,
                      record.revisesRecordID == nil,
                      record.evidenceSourceRecordID == nil else { throw invalid() }
            case .clericalCorrection:
                guard let revisedID = record.revisesRecordID,
                      let revised = workflow[revisedID],
                      record.recordRevisionRootID != record.id,
                      record.evidenceSourceRecordID == record.recordRevisionRootID,
                      validCorrection(record, prior: revised, root: root) else {
                    throw invalid()
                }
            }
        }
        try requireAcyclic(records.workflowRecords, id: \.id, next: \.parentRecordID)
        try requireAcyclic(records.workflowRecords, id: \.id, next: \.revisesRecordID)
        guard unique(records.workflowRecords.compactMap(\.revisesRecordID)),
              unique(records.workflowRecords.compactMap(\.finalizationMutationID)),
              records.assets.allSatisfy({ asset in
                  records.workflowRecords.filter {
                      $0.assetID == asset.id
                        && $0.state == WorkflowState.draft.rawValue
                  }.count <= 1
              }) else {
            throw invalid()
        }

        let allowedPurposes = Set(exactPack.evidencePurposes.map(\.key))
        for evidence in records.evidenceFiles {
            let id = uuid(evidence.id)
            guard let owner = workflow[evidence.recordID],
                  owner.revisionKind == WorkflowRevisionKind.original.rawValue,
                  evidence.createdAt >= owner.startedAt,
                  owner.completedAt.map({ evidence.createdAt <= $0 }) ?? true,
                  allowedPurposes.contains(evidence.purposeKey),
                  evidence.mimeType == "image/jpeg",
                  evidence.byteCount >= 0, evidence.thumbnailByteCount >= 0,
                  evidence.relativePath == "evidence/\(id)/original.jpg",
                  evidence.thumbnailRelativePath == "evidence/\(id)/thumbnail.jpg",
                  lowercaseHash(evidence.sha256), lowercaseHash(evidence.thumbnailSHA256) else {
                throw invalid()
            }
        }
        for record in records.workflowRecords {
            let owned = records.evidenceFiles.filter { $0.recordID == record.id }
            guard unique(owned.map(\.purposeKey)) else { throw invalid() }
            if record.state == WorkflowState.completed.rawValue {
                switch WorkflowStage(rawValue: record.stage) {
                case .check, .recheck:
                    let required = Set(["wide_context", "close_detail"])
                    if record.outcomeKey == "could_not_verify" {
                        guard Set(owned.map(\.purposeKey)).isSubset(of: required) else {
                            throw invalid()
                        }
                    } else if record.revisionKind == WorkflowRevisionKind.original.rawValue {
                        guard Set(owned.map(\.purposeKey)) == required else { throw invalid() }
                    }
                case .work:
                    guard Set(owned.map(\.purposeKey)).isSubset(of: ["work_context"]),
                          owned.count <= 1 else { throw invalid() }
                case nil:
                    throw invalid()
                }
            } else if record.state == WorkflowState.draft.rawValue {
                guard validDraftEvidence(record, owned: owned) else {
                    throw invalid()
                }
            }
        }
        for issue in records.issues {
            guard assets[issue.assetID] != nil,
                  let opened = workflow[issue.openedByRecordID],
                  opened.assetID == issue.assetID,
                  signPack.issueLabels.filter({
                      $0.key == issue.labelKey
                        && $0.display == issue.labelDisplaySnapshot
                  }).count == 1,
                  ((opened.outcomeKey == "visible_issue" && opened.issueID == issue.id)
                    || opened.outcomeKey == "original_resolved_different_issue"),
                  issue.updatedAt >= issue.createdAt,
                  IssueStatus(rawValue: issue.status) != nil,
                  try validCurrentIssueState(issue, workflow: workflow) else {
                throw invalid()
            }
        }
        guard unique(records.issues.map(\.openedByRecordID)),
              records.assets.allSatisfy({ asset in
            records.issues.filter {
                $0.assetID == asset.id
                    && $0.status != IssueStatus.resolved.rawValue
            }.count <= 1
        }) else {
            throw invalid()
        }
        for packet in records.packets {
            let ownedRecords = records.workflowRecords.filter { $0.packetID == packet.id }
            let ownedReports = records.reports.filter { $0.packetID == packet.id }
            if let currentID = packet.currentRecordID {
                let replacedIDs = Set(ownedReports.compactMap(\.replacesReportID))
                let reportTips = ownedReports.filter { !replacedIDs.contains($0.id) }
                let reportSourceIDs = ownedReports.map(\.sourceRecordID)
                guard packet.contentDeletedAt == nil,
                      packet.evaluationCounted,
                      let current = workflow[currentID], current.packetID == packet.id,
                      ownedRecords.allSatisfy({ $0.assetID == current.assetID }),
                      ownedReports.allSatisfy({ workflow[$0.sourceRecordID]?.assetID == current.assetID }),
                      unique(reportSourceIDs),
                      Set(reportSourceIDs) == Set(ownedRecords.map(\.id)),
                      reportTips.count == 1,
                      reportTips[0].sourceRecordID == currentID,
                      ownedReports.filter({ replacedIDs.contains($0.id) }).allSatisfy({
                          $0.pdfState == ReportPDFState.ready.rawValue
                      }) else {
                    throw invalid()
                }
                var visited = Set<UUID>()
                var chainReport: V4BackupReportDTO? = reportTips[0]
                while let value = chainReport {
                    guard visited.insert(value.id).inserted,
                          let source = workflow[value.sourceRecordID] else {
                        throw invalid()
                    }
                    if let priorID = value.replacesReportID {
                        guard let prior = reports[priorID],
                              prior.packetID == packet.id,
                              let priorSource = workflow[prior.sourceRecordID],
                              source.revisionKind
                                == WorkflowRevisionKind.clericalCorrection.rawValue,
                              source.revisesRecordID == priorSource.id,
                              source.recordRevisionRootID
                                == priorSource.recordRevisionRootID else {
                            throw invalid()
                        }
                        chainReport = prior
                    } else {
                        guard source.revisionKind
                                == WorkflowRevisionKind.original.rawValue,
                              source.revisesRecordID == nil,
                              source.completedAt == packet.createdAt else {
                            throw invalid()
                        }
                        chainReport = nil
                    }
                }
                guard visited.count == ownedReports.count else { throw invalid() }
            } else {
                guard packet.evaluationCounted,
                      let contentDeletedAt = packet.contentDeletedAt,
                      packet.createdAt <= contentDeletedAt,
                      ownedRecords.isEmpty, ownedReports.isEmpty else { throw invalid() }
            }
        }
        for report in records.reports {
            guard let packet = packets[report.packetID],
                  let source = workflow[report.sourceRecordID],
                  source.packetID == packet.id,
                  source.state == WorkflowState.completed.rawValue,
                  let sourceCompletedAt = source.completedAt,
                  report.createdAt >= sourceCompletedAt,
                  ReportPDFState(rawValue: report.pdfState) != nil,
                  report.snapshotSchemaVersion == 1,
                  report.snapshotRelativePath == "snapshots/\(uuid(report.id)).json",
                  lowercaseHash(report.snapshotSHA256) else { throw invalid() }
            if let replacedID = report.replacesReportID {
                guard let replaced = reports[replacedID],
                      replaced.packetID == report.packetID,
                      replaced.createdAt < report.createdAt else { throw invalid() }
            }
        }
        try requireAcyclic(records.reports, id: \.id, next: \.replacesReportID)
        guard unique(records.reports.compactMap(\.replacesReportID)) else { throw invalid() }

        let counted = records.packets.filter(\.evaluationCounted)
            .map(\.stableRootID).sorted { uuid($0) < uuid($1) }
        let expectedPacks: [V4BackupPackV1] =
            records.assets.isEmpty && records.workflowRecords.isEmpty
            ? []
            : [.init(
                contentVersion: exactPack.contentVersion,
                packID: exactPack.packID,
                schemaVersion: exactPack.schemaVersion
            )]
        guard unique(records.packets.map(\.stableRootID)),
              counted == manifest.consumedEvaluationRootIDs,
              manifest.packs == expectedPacks else { throw invalid() }
    }

    func validCurrentIssueState(
        _ issue: V4BackupIssueDTO,
        workflow: [UUID: V4BackupWorkflowRecordDTO]
    ) throws -> Bool {
        guard let opening = workflow[issue.openedByRecordID],
              opening.revisionKind == WorkflowRevisionKind.original.rawValue,
              opening.state == WorkflowState.completed.rawValue,
              let openingCompletedAt = opening.completedAt,
              openingCompletedAt == issue.createdAt else {
            return false
        }
        let ordinaryOpening = opening.stage == WorkflowStage.check.rawValue
            && opening.outcomeKey == "visible_issue"
            && opening.issueID == issue.id
        let differentIssueOpening = opening.stage == WorkflowStage.recheck.rawValue
            && opening.outcomeKey == "original_resolved_different_issue"
            && opening.issueID != issue.id
        guard ordinaryOpening || differentIssueOpening else { return false }

        let relevant = workflow.values.filter {
            $0.revisionKind == WorkflowRevisionKind.original.rawValue
                && ($0.id == opening.id || $0.issueID == issue.id)
        }
        let substantive = relevant.filter {
            $0.state == WorkflowState.completed.rawValue
        }
        let drafts = relevant.filter { $0.state == WorkflowState.draft.rawValue }
        guard drafts.count <= 1 else { return false }
        var chain = [opening]
        var visited: Set<UUID> = [opening.id]
        var current = opening
        while true {
            let children = substantive.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else { return false }
            guard let child = children.first else { break }
            guard visited.insert(child.id).inserted,
                  child.assetID == issue.assetID,
                  child.issueID == issue.id,
                  child.state == WorkflowState.completed.rawValue,
                  let parentCompletedAt = current.completedAt,
                  child.startedAt >= parentCompletedAt,
                  child.completedAt.map({ $0 >= parentCompletedAt }) == true else {
                return false
            }
            chain.append(child)
            current = child
        }
        guard visited.count == substantive.count else { return false }

        var expectedStatus = IssueStatus.open.rawValue
        var expectedResolvedByRecordID: UUID?
        var expectedUpdatedAt = openingCompletedAt
        for record in chain.dropFirst() {
            guard let completedAt = record.completedAt else { return false }
            switch WorkflowStage(rawValue: record.stage) {
            case .work:
                guard expectedStatus == IssueStatus.open.rawValue else {
                    return false
                }
                expectedStatus = IssueStatus.recheckDue.rawValue
                expectedResolvedByRecordID = nil
                expectedUpdatedAt = completedAt
            case .recheck:
                guard expectedStatus == IssueStatus.recheckDue.rawValue else {
                    return false
                }
                switch record.outcomeKey {
                case "resolved", "original_resolved_different_issue":
                    expectedStatus = IssueStatus.resolved.rawValue
                    expectedResolvedByRecordID = record.id
                    expectedUpdatedAt = completedAt
                case "issue_still_visible":
                    expectedStatus = IssueStatus.open.rawValue
                    expectedResolvedByRecordID = nil
                    expectedUpdatedAt = completedAt
                case "could_not_verify":
                    break
                default:
                    return false
                }
            case .check, nil:
                return false
            }
        }
        if let draft = drafts.first {
            guard draft.assetID == issue.assetID,
                  draft.issueID == issue.id,
                  draft.parentRecordID == chain.last?.id else {
                return false
            }
            switch WorkflowStage(rawValue: draft.stage) {
            case .work:
                guard expectedStatus == IssueStatus.open.rawValue else {
                    return false
                }
            case .recheck:
                guard expectedStatus == IssueStatus.recheckDue.rawValue else {
                    return false
                }
            case .check, nil:
                return false
            }
        }
        return issue.status == expectedStatus
            && issue.resolvedByRecordID == expectedResolvedByRecordID
            && issue.updatedAt == expectedUpdatedAt
    }

    func validateOwnedMembers(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1,
        members: [String: Data]
    ) throws {
        var expected = Set(["manifest.json", "records.json"])
        let normalizer = MediaNormalizerV1()
        for evidence in records.evidenceFiles {
            let id = uuid(evidence.id)
            let originalPath = "media/\(id).jpg"
            let thumbnailPath = "thumbnails/\(id).jpg"
            guard let original = members[originalPath],
                  let thumbnail = members[thumbnailPath],
                  original.count == evidence.byteCount,
                  thumbnail.count == evidence.thumbnailByteCount,
                  CanonicalJSONV1.sha256(original) == evidence.sha256,
                  CanonicalJSONV1.sha256(thumbnail) == evidence.thumbnailSHA256 else {
                throw invalid()
            }
            _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
            _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            expected.insert(originalPath)
            expected.insert(thumbnailPath)
        }
        for report in records.reports {
            let id = uuid(report.id)
            expected.insert("snapshots/\(id).json")
            switch ReportPDFState(rawValue: report.pdfState) {
            case .ready:
                let path = "pdfs/\(id).pdf"
                guard report.pdfRelativePath == path,
                      let hash = report.pdfSHA256,
                      lowercaseHash(hash),
                      let bytes = members[path],
                      CanonicalJSONV1.sha256(bytes) == hash,
                      let document = PDFDocument(data: bytes),
                      document.pageCount > 0 else { throw invalid() }
                expected.insert(path)
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else { throw invalid() }
            case nil:
                throw invalid()
            }
        }
        guard Set(members.keys) == expected,
              Set(manifest.entries.map(\.path)) == expected.subtracting(["manifest.json"]) else {
            throw invalid()
        }
    }
}

private extension BackupPackageValidatorV1 {
    func validDraftSemantics(
        _ record: V4BackupWorkflowRecordDTO,
        workflow: [UUID: V4BackupWorkflowRecordDTO],
        issues: [UUID: V4BackupIssueDTO]
    ) -> Bool {
        let hasNoAcknowledgements = acknowledgementPresence(record).allSatisfy { !$0 }
        let hasNoTime = timeFields(record).allSatisfy { !$0 }
        let captureStep = record.draftStepKey.flatMap {
            WorkflowDraftStep(rawValue: $0)
        }
        let validCaptureStep = captureStep == .wide
            || captureStep == .close
            || captureStep == .outcome
        guard record.couldNotVerifyKey == nil,
              record.couldNotVerifyDisplaySnapshot == nil,
              record.couldNotVerifyRegistryVersion == nil,
              record.workPerformedLocalDate == nil,
              record.workDescription == nil,
              record.note == nil else { return false }
        switch WorkflowStage(rawValue: record.stage) {
        case .check:
            return record.parentRecordID == nil && record.issueID == nil
                && validCaptureStep
                && validFrozenTimeAndAcknowledgements(record)
        case .recheck:
            return record.parentRecordID != nil && record.issueID != nil
                && validCaptureStep
                && validFrozenTimeAndAcknowledgements(record)
                && validDraftParentAuthority(
                    record,
                    workflow: workflow,
                    issues: issues
                )
        case .work:
            return record.parentRecordID != nil && record.issueID != nil
                && record.draftStepKey == nil
                && hasNoAcknowledgements && hasNoTime
                && validDraftParentAuthority(
                    record,
                    workflow: workflow,
                    issues: issues
                )
        case nil:
            return false
        }
    }

    func validDraftParentAuthority(
        _ record: V4BackupWorkflowRecordDTO,
        workflow: [UUID: V4BackupWorkflowRecordDTO],
        issues: [UUID: V4BackupIssueDTO]
    ) -> Bool {
        guard let parentID = record.parentRecordID,
              let issueID = record.issueID,
              let parent = workflow[parentID],
              let issue = issues[issueID],
              parent.assetID == record.assetID,
              issue.assetID == record.assetID,
              parent.revisionKind == WorkflowRevisionKind.original.rawValue,
              parent.state == WorkflowState.completed.rawValue,
              let parentCompletedAt = parent.completedAt,
              parent.finalizationMutationID != nil,
              parent.packID == record.packID,
              parent.packSchemaVersion == record.packSchemaVersion,
              parent.packContentVersion == record.packContentVersion,
              parent.issueID == issue.id || issue.openedByRecordID == parent.id,
              record.startedAt >= parentCompletedAt,
              record.startedAt >= issue.updatedAt else {
            return false
        }
        return true
    }

    func validFrozenTimeAndAcknowledgements(
        _ record: V4BackupWorkflowRecordDTO
    ) -> Bool {
        guard signPack.acknowledgements.count == 2,
              signPack.acknowledgements[0].key == "after_dark",
              signPack.acknowledgements[1].key == "safe_authorized_position",
              let observedAtUTC = record.observedAtUTC,
              let timeZoneID = record.timeZoneID,
              observedAtUTC == record.startedAt,
              let frozen = try? TimeContextRule.freeze(
                  observedAtUTC: observedAtUTC,
                  confirmedTimeZoneID: timeZoneID
              ),
              frozen.utcOffsetMinutes == record.utcOffsetMinutes,
              frozen.localDate == record.localDate,
              frozen.localTime == record.localTime,
              record.afterDarkAcknowledgementKey
                == signPack.acknowledgements[0].key,
              record.afterDarkAcknowledgementCopy
                == signPack.acknowledgements[0].copy,
              record.afterDarkAcknowledgementVersion
                == signPack.acknowledgements[0].version,
              record.afterDarkAcknowledgementAccepted == true,
              record.safePositionAcknowledgementKey
                == signPack.acknowledgements[1].key,
              record.safePositionAcknowledgementCopy
                == signPack.acknowledgements[1].copy,
              record.safePositionAcknowledgementVersion
                == signPack.acknowledgements[1].version,
              record.safePositionAcknowledgementAccepted == true else {
            return false
        }
        return true
    }

    func validCorrection(
        _ record: V4BackupWorkflowRecordDTO,
        prior: V4BackupWorkflowRecordDTO,
        root: V4BackupWorkflowRecordDTO
    ) -> Bool {
        record.schemaVersion == prior.schemaVersion
            && record.assetID == prior.assetID
            && record.packetID == prior.packetID
            && record.issueID == prior.issueID
            && record.parentRecordID == prior.parentRecordID
            && record.recordRevisionRootID == prior.recordRevisionRootID
            && prior.recordRevisionRootID == root.id
            && record.stage == prior.stage
            && record.state == prior.state
            && record.draftStepKey == prior.draftStepKey
            && record.startedAt == prior.startedAt
            && record.completedAt == prior.completedAt
            && record.observedAtUTC == prior.observedAtUTC
            && record.timeZoneID == prior.timeZoneID
            && record.utcOffsetMinutes == prior.utcOffsetMinutes
            && record.localDate == prior.localDate
            && record.localTime == prior.localTime
            && record.afterDarkAcknowledgementKey
                == prior.afterDarkAcknowledgementKey
            && record.afterDarkAcknowledgementCopy
                == prior.afterDarkAcknowledgementCopy
            && record.afterDarkAcknowledgementVersion
                == prior.afterDarkAcknowledgementVersion
            && record.afterDarkAcknowledgementAccepted
                == prior.afterDarkAcknowledgementAccepted
            && record.safePositionAcknowledgementKey
                == prior.safePositionAcknowledgementKey
            && record.safePositionAcknowledgementCopy
                == prior.safePositionAcknowledgementCopy
            && record.safePositionAcknowledgementVersion
                == prior.safePositionAcknowledgementVersion
            && record.safePositionAcknowledgementAccepted
                == prior.safePositionAcknowledgementAccepted
            && record.packID == prior.packID
            && record.packSchemaVersion == prior.packSchemaVersion
            && record.packContentVersion == prior.packContentVersion
            && record.pdfTemplateID == prior.pdfTemplateID
            && record.pdfTemplateVersion == prior.pdfTemplateVersion
            && record.outcomeKey == prior.outcomeKey
            && record.couldNotVerifyKey == prior.couldNotVerifyKey
            && record.couldNotVerifyDisplaySnapshot
                == prior.couldNotVerifyDisplaySnapshot
            && record.couldNotVerifyRegistryVersion
                == prior.couldNotVerifyRegistryVersion
            && record.workPerformedLocalDate == prior.workPerformedLocalDate
            && record.workDescription == prior.workDescription
            && record.note != prior.note
    }

    func validDraftEvidence(
        _ record: V4BackupWorkflowRecordDTO,
        owned: [V4BackupEvidenceFileDTO]
    ) -> Bool {
        switch WorkflowStage(rawValue: record.stage) {
        case .work:
            return record.draftStepKey == nil && owned.isEmpty
        case .check, .recheck:
            guard let step = record.draftStepKey.flatMap({
                WorkflowDraftStep(rawValue: $0)
            }) else { return false }
            let purposes = Set(owned.map(\.purposeKey))
            guard purposes.count == owned.count,
                  purposes.isSubset(of: ["wide_context", "close_detail"]) else {
                return false
            }
            switch step {
            case .wide:
                return owned.isEmpty
            case .close:
                return purposes == ["wide_context"]
            case .outcome:
                return !purposes.contains("close_detail")
                    || purposes.contains("wide_context")
            case .review:
                return false
            }
        case nil:
            return false
        }
    }

    func validCompletedSemantics(_ record: V4BackupWorkflowRecordDTO) -> Bool {
        let hasNoAcknowledgements = acknowledgementPresence(record).allSatisfy { !$0 }
        let hasNoTime = timeFields(record).allSatisfy { !$0 }
        let hasAnyCNV = record.couldNotVerifyKey != nil
            || record.couldNotVerifyDisplaySnapshot != nil
            || record.couldNotVerifyRegistryVersion != nil
        let hasCompleteCNV = record.couldNotVerifyKey != nil
            && record.couldNotVerifyDisplaySnapshot != nil
            && record.couldNotVerifyRegistryVersion != nil
        guard (record.outcomeKey == "could_not_verify") == hasCompleteCNV,
              hasCompleteCNV || !hasAnyCNV,
              validOptionalTrimmed(record.note, maximum: 1_000) else { return false }
        if hasCompleteCNV {
            guard record.couldNotVerifyRegistryVersion == signPack.couldNotVerifyReasons.version,
                  signPack.couldNotVerifyReasons.entries.contains(where: {
                      $0.key == record.couldNotVerifyKey
                        && $0.display == record.couldNotVerifyDisplaySnapshot
                  }) else { return false }
        }
        switch WorkflowStage(rawValue: record.stage) {
        case .check:
            return record.parentRecordID == nil && record.packetID != nil
                && ["no_visible_issue", "visible_issue", "could_not_verify"]
                    .contains(record.outcomeKey ?? "")
                && ((record.outcomeKey == "visible_issue") == (record.issueID != nil))
                && record.workPerformedLocalDate == nil && record.workDescription == nil
                && validFrozenTimeAndAcknowledgements(record)
        case .recheck:
            return record.parentRecordID != nil && record.issueID != nil
                && record.packetID != nil
                && [
                    "resolved", "issue_still_visible",
                    "original_resolved_different_issue", "could_not_verify",
                ].contains(record.outcomeKey ?? "")
                && record.workPerformedLocalDate == nil && record.workDescription == nil
                && validFrozenTimeAndAcknowledgements(record)
        case .work:
            return record.parentRecordID != nil && record.issueID != nil
                && record.packetID == nil && record.outcomeKey == "work_recorded"
                && record.workPerformedLocalDate.map(validLocalDate) == true
                && validRequiredTrimmed(record.workDescription, maximum: 160)
                && hasNoAcknowledgements && hasNoTime
        case nil:
            return false
        }
    }

    func acknowledgementPresence(_ value: V4BackupWorkflowRecordDTO) -> [Bool] {
        [
            value.afterDarkAcknowledgementKey != nil,
            value.afterDarkAcknowledgementCopy != nil,
            value.afterDarkAcknowledgementVersion != nil,
            value.afterDarkAcknowledgementAccepted != nil,
            value.safePositionAcknowledgementKey != nil,
            value.safePositionAcknowledgementCopy != nil,
            value.safePositionAcknowledgementVersion != nil,
            value.safePositionAcknowledgementAccepted != nil,
        ]
    }

    func timeFields(_ value: V4BackupWorkflowRecordDTO) -> [Bool] {
        [
            value.observedAtUTC != nil,
            value.timeZoneID != nil,
            value.utcOffsetMinutes != nil,
            value.localDate != nil,
            value.localTime != nil,
        ]
    }

    func validOptionalTrimmed(_ value: String?, maximum: Int) -> Bool {
        guard let value else { return true }
        return validRequiredTrimmed(value, maximum: maximum)
    }

    func validRequiredTrimmed(_ value: String?, maximum: Int) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == trimmed && !value.isEmpty && value.count <= maximum
    }

    func validLocalDate(_ value: String) -> Bool {
        guard value.range(
            of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
            options: .regularExpression
        ) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    func stageDisplay(_ value: String) -> String? {
        if value == WorkflowStage.work.rawValue { return "Work" }
        let matches = signPack.stageDisplays.filter { $0.key == value }
        return matches.count == 1 ? matches[0].display : nil
    }

    func outcomeDisplay(_ value: String?) -> String? {
        guard let value else { return nil }
        if value == "work_recorded" { return "Work recorded" }
        let matches = signPack.outcomeDisplays.filter { $0.key == value }
        return matches.count == 1 ? matches[0].display : nil
    }

    func frozenCouldNotVerify(
        _ record: V4BackupWorkflowRecordDTO
    ) -> CouldNotVerifySnapshotV1? {
        guard let key = record.couldNotVerifyKey,
              let display = record.couldNotVerifyDisplaySnapshot,
              let version = record.couldNotVerifyRegistryVersion else {
            return nil
        }
        return CouldNotVerifySnapshotV1(
            display: display,
            key: key,
            registryVersion: version
        )
    }

    func validateReports(_ records: V4BackupRecordsV1, members: [String: Data]) throws {
        let workflow = Dictionary(uniqueKeysWithValues: records.workflowRecords.map { ($0.id, $0) })
        let packets = Dictionary(uniqueKeysWithValues: records.packets.map { ($0.id, $0) })
        let evidence = Dictionary(uniqueKeysWithValues: records.evidenceFiles.map { ($0.id, $0) })
        let issues = Dictionary(uniqueKeysWithValues: records.issues.map { ($0.id, $0) })
        let assets = Dictionary(uniqueKeysWithValues: records.assets.map { ($0.id, $0) })
        let sites = Dictionary(uniqueKeysWithValues: records.sites.map { ($0.id, $0) })
        for report in records.reports {
            guard let bytes = members["snapshots/\(uuid(report.id)).json"],
                  CanonicalJSONV1.sha256(bytes) == report.snapshotSHA256,
                  let source = workflow[report.sourceRecordID],
                  let packet = packets[report.packetID],
                  let asset = assets[source.assetID],
                  let site = sites[asset.siteID] else { throw invalid() }
            let snapshot = try ReportSnapshotEncoderV1().decode(bytes)
            let effectiveSourceID = source.evidenceSourceRecordID ?? source.id
            guard snapshot.reportID == report.id,
                  snapshot.sourceRecordID == source.id,
                  snapshot.evidenceSourceRecordID == effectiveSourceID,
                  snapshot.packetID == packet.id,
                  snapshot.stableRootID == packet.stableRootID,
                  snapshot.snapshotSchemaVersion == report.snapshotSchemaVersion,
                  snapshot.snapshotCreatedAt == report.createdAt,
                  snapshot.stage == source.stage,
                  snapshot.outcome == source.outcomeKey,
                  snapshot.note == source.note,
                  snapshot.couldNotVerify == frozenCouldNotVerify(source),
                  snapshot.pack.id == signPack.packID,
                  snapshot.pack.schemaVersion == signPack.schemaVersion,
                  snapshot.pack.contentVersion == signPack.contentVersion,
                  snapshot.pdfTemplate.id == source.pdfTemplateID,
                  snapshot.pdfTemplate.version == source.pdfTemplateVersion,
                  snapshot.asset.label == asset.label,
                  snapshot.site.label == site.label,
                  snapshot.site.address == site.address,
                  snapshot.disclaimer == signPack.disclaimer,
                  snapshot.display.assetSingular == signPack.nouns.asset.singular,
                  snapshot.display.checkSingular == signPack.nouns.check.singular,
                  snapshot.display.issueSingular == signPack.nouns.issue.singular,
                  snapshot.display.stage == stageDisplay(source.stage),
                  snapshot.display.outcome == outcomeDisplay(source.outcomeKey),
                  snapshot.timeContext.observedAtUTC == source.observedAtUTC,
                  snapshot.timeContext.timeZoneID == source.timeZoneID,
                  snapshot.timeContext.utcOffsetMinutes == source.utcOffsetMinutes,
                  snapshot.timeContext.localDate == source.localDate,
                  snapshot.timeContext.localTime == source.localTime else { throw invalid() }
            try validateAcknowledgements(snapshot, source: source)

            guard let effective = workflow[effectiveSourceID],
                  let effectiveCompletedAt = effective.completedAt else {
                throw invalid()
            }
            let chain = try parentChain(endingAt: effective, workflow: workflow)
            let expectedIssues = try issueSnapshots(
                effectiveSourceID: effectiveSourceID,
                assetID: source.assetID,
                workflow: workflow,
                issues: issues
            )
            let expectedHistory = expectedIssues.isEmpty
                ? []
                : Array(chain.dropLast()).sorted(by: recordChronology)
            guard expectedHistory.allSatisfy({ record in
                      record.completedAt.map { $0 < effectiveCompletedAt } == true
                  }),
                  snapshot.history.map(\.recordID) == expectedHistory.map(\.id),
                  !snapshot.history.contains(where: { $0.recordID == effective.id }),
                  snapshot.issues == expectedIssues else {
                throw invalid()
            }

            var orderedEvidence = records.evidenceFiles.filter {
                $0.recordID == effectiveSourceID
            }.sorted(by: evidenceOrder)
            var seenEvidenceIDs = Set(orderedEvidence.map(\.id))
            for (history, record) in zip(snapshot.history, expectedHistory) {
                let historyEvidence = records.evidenceFiles.filter {
                    $0.recordID == record.id
                }.sorted(by: evidenceOrder)
                guard record.assetID == source.assetID,
                      record.state == WorkflowState.completed.rawValue,
                      record.completedAt == history.completedAt,
                      record.stage == history.stage,
                      record.outcomeKey == history.outcome,
                      history.couldNotVerify == frozenCouldNotVerify(record),
                      record.note == history.note,
                      record.workDescription == history.workDescription,
                      record.workPerformedLocalDate == history.workPerformedLocalDate,
                      history.stageDisplay == stageDisplay(record.stage),
                      history.outcomeDisplay == outcomeDisplay(record.outcomeKey),
                      history.evidenceIDs == historyEvidence.map(\.id),
                      history.issueIDs == (try historyIssueIDs(
                          record: record,
                          assetID: source.assetID,
                          issues: issues
                      )) else {
                    throw invalid()
                }
                for row in historyEvidence where seenEvidenceIDs.insert(row.id).inserted {
                    orderedEvidence.append(row)
                }
            }
            guard snapshot.evidence.map(\.evidenceID) == orderedEvidence.map(\.id) else {
                throw invalid()
            }
            for (value, row) in zip(snapshot.evidence, orderedEvidence) {
                guard evidence[value.evidenceID]?.id == row.id,
                      value.recordID == row.recordID,
                      value.purposeKey == row.purposeKey,
                      value.mimeType == row.mimeType,
                      value.byteCount == row.byteCount,
                      value.sha256 == row.sha256,
                      value.relativePath == row.relativePath,
                      value.thumbnailByteCount == row.thumbnailByteCount,
                      value.thumbnailSHA256 == row.thumbnailSHA256,
                      value.thumbnailRelativePath == row.thumbnailRelativePath,
                      value.createdAt == row.createdAt,
                      signPack.evidencePurposes.first(where: { $0.key == row.purposeKey })?.display
                        == value.purposeDisplay else { throw invalid() }
            }
        }
    }

    func historyIssueIDs(
        record: V4BackupWorkflowRecordDTO,
        assetID: UUID,
        issues: [UUID: V4BackupIssueDTO]
    ) throws -> [UUID] {
        var result = Set(record.issueID.map { [$0] } ?? [])
        result.formUnion(issues.values.compactMap {
            $0.openedByRecordID == record.id ? $0.id : nil
        })
        guard result.allSatisfy({ issues[$0]?.assetID == assetID }) else {
            throw invalid()
        }
        return result.sorted { uuid($0) < uuid($1) }
    }

    func recordChronology(
        _ lhs: V4BackupWorkflowRecordDTO,
        _ rhs: V4BackupWorkflowRecordDTO
    ) -> Bool {
        guard let left = lhs.completedAt, let right = rhs.completedAt else {
            return false
        }
        return left < right || (left == right && uuid(lhs.id) < uuid(rhs.id))
    }

    func evidenceOrder(
        _ lhs: V4BackupEvidenceFileDTO,
        _ rhs: V4BackupEvidenceFileDTO
    ) -> Bool {
        let left = purposeOrder(lhs.purposeKey)
        let right = purposeOrder(rhs.purposeKey)
        return left == right ? uuid(lhs.id) < uuid(rhs.id) : left < right
    }

    func purposeOrder(_ value: String) -> Int {
        switch value {
        case "wide_context": 0
        case "close_detail": 1
        case "work_context": 2
        default: 3
        }
    }

    func issueSnapshots(
        effectiveSourceID: UUID,
        assetID: UUID,
        workflow: [UUID: V4BackupWorkflowRecordDTO],
        issues: [UUID: V4BackupIssueDTO]
    ) throws -> [IssueSnapshotV1] {
        guard let effective = workflow[effectiveSourceID],
              effective.assetID == assetID,
              effective.revisionKind == WorkflowRevisionKind.original.rawValue else {
            throw invalid()
        }
        let chain = try parentChain(endingAt: effective, workflow: workflow)
        var issueIDs = Set(chain.compactMap(\.issueID))
        issueIDs.formUnion(issues.values.compactMap { issue in
            chain.contains(where: { $0.id == issue.openedByRecordID })
                ? issue.id
                : nil
        })

        var result: [IssueSnapshotV1] = []
        for issueID in issueIDs {
            guard let issue = issues[issueID],
                  issue.assetID == assetID,
                  let opening = chain.first(where: {
                      $0.id == issue.openedByRecordID
                  }),
                  issue.createdAt == opening.completedAt,
                  signPack.issueLabels.filter({
                      $0.key == issue.labelKey
                        && $0.display == issue.labelDisplaySnapshot
                  }).count == 1 else {
                throw invalid()
            }
            var status = IssueStatus.open.rawValue
            var resolvedByRecordID: UUID?
            var updatedAt = issue.createdAt
            for record in chain where record.issueID == issue.id {
                guard let completedAt = record.completedAt else { throw invalid() }
                switch WorkflowStage(rawValue: record.stage) {
                case .work:
                    status = IssueStatus.recheckDue.rawValue
                    resolvedByRecordID = nil
                    updatedAt = completedAt
                case .recheck:
                    switch record.outcomeKey {
                    case "resolved", "original_resolved_different_issue":
                        status = IssueStatus.resolved.rawValue
                        resolvedByRecordID = record.id
                        updatedAt = completedAt
                    case "issue_still_visible":
                        status = IssueStatus.open.rawValue
                        resolvedByRecordID = nil
                        updatedAt = completedAt
                    case "could_not_verify":
                        break
                    default:
                        throw invalid()
                    }
                case .check:
                    guard record.id == issue.openedByRecordID else { throw invalid() }
                case nil:
                    throw invalid()
                }
            }
            result.append(IssueSnapshotV1(
                createdAt: issue.createdAt,
                display: issue.labelDisplaySnapshot,
                issueID: issue.id,
                key: issue.labelKey,
                openedByRecordID: issue.openedByRecordID,
                resolvedByRecordID: resolvedByRecordID,
                status: status,
                updatedAt: updatedAt
            ))
        }
        return result.sorted {
            $0.createdAt < $1.createdAt
                || ($0.createdAt == $1.createdAt
                    && uuid($0.issueID) < uuid($1.issueID))
        }
    }

    func parentChain(
        endingAt record: V4BackupWorkflowRecordDTO,
        workflow: [UUID: V4BackupWorkflowRecordDTO]
    ) throws -> [V4BackupWorkflowRecordDTO] {
        var reversed: [V4BackupWorkflowRecordDTO] = []
        var current: V4BackupWorkflowRecordDTO? = record
        var seen = Set<UUID>()
        while let value = current {
            guard seen.insert(value.id).inserted,
                  value.assetID == record.assetID,
                  value.revisionKind == WorkflowRevisionKind.original.rawValue else {
                throw invalid()
            }
            reversed.append(value)
            if let parentID = value.parentRecordID {
                guard let parent = workflow[parentID] else { throw invalid() }
                current = parent
            } else {
                current = nil
            }
        }
        return reversed.reversed()
    }

    func validateAcknowledgements(
        _ snapshot: ReportSnapshotV1,
        source: V4BackupWorkflowRecordDTO
    ) throws {
        guard snapshot.acknowledgements.count == signPack.acknowledgements.count else {
            throw invalid()
        }
        let stored = [
            (
                source.afterDarkAcknowledgementKey,
                source.afterDarkAcknowledgementCopy,
                source.afterDarkAcknowledgementVersion,
                source.afterDarkAcknowledgementAccepted
            ),
            (
                source.safePositionAcknowledgementKey,
                source.safePositionAcknowledgementCopy,
                source.safePositionAcknowledgementVersion,
                source.safePositionAcknowledgementAccepted
            ),
        ]
        for index in snapshot.acknowledgements.indices {
            let value = snapshot.acknowledgements[index]
            let expected = signPack.acknowledgements[index]
            let row = stored[index]
            guard value.key == expected.key, value.copy == expected.copy,
                  value.version == expected.version, value.accepted,
                  row.0 == value.key, row.1 == value.copy,
                  row.2 == value.version, row.3 == value.accepted else { throw invalid() }
        }
    }

    func requireAcyclic<T>(
        _ values: [T],
        id: KeyPath<T, UUID>,
        next: KeyPath<T, UUID?>
    ) throws {
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0[keyPath: id], $0) })
        for value in values {
            var seen = Set<UUID>()
            var cursor: UUID? = value[keyPath: id]
            while let current = cursor {
                guard seen.insert(current).inserted, let row = byID[current] else { throw invalid() }
                cursor = row[keyPath: next]
            }
        }
    }

    func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
    func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }
    func lowercaseHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
    func invalid() -> BackupPackageValidationErrorV1 { .invalidPackage }
}
