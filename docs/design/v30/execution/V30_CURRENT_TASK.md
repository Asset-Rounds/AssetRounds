# V30 Current Task

Card 29 of 55 - Backup, restore, and historical catalog replay

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation. No S10 shared paths are authorized for this card.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Restore canonical/source content, catalog/font/renderer references, derived artifacts, search rebuild state, and explicit missing-resource limitations independent of current app language.",
    "staticEvidence": "Current-card fenced proof and receipt; exact committed paths/hashes"
  },
  "attempt": 1,
  "authority": {
    "authorityContentDigest": "ab585279a32cb8e53b5656af6efb264a85ced24116ace3b1de9f56a14f19cec6",
    "authorityID": "ASSETROUNDS-V30-PRE-S10-20260902-R2",
    "manifestSHA256": "78d893786105d4645d145b548e939c1e9ce3b54bb1f937dcfc5eaae23ca82e64",
    "packageDigest": "0ab3257b4825025f75f576bc0a61f3122a818f949fd664441eea3adc43b60325"
  },
  "base": {
    "head": "3c0dfd33cac5b4d12a98c0b44c699639150cc560",
    "tree": "5be4c1a16a938fb1e0c8305437f41e8290eda2ea"
  },
  "cardID": "V30-P03-C08",
  "class": "IMPLEMENTATION",
  "credit": {
    "canonicalAcceptance": false,
    "finalCredit": false,
    "mainIntegrationCredit": false,
    "postS10SuccessorStart": false,
    "provisionalDependencySatisfied": false,
    "releaseCredit": false
  },
  "directPrerequisites": [
    "V30-P01-C08",
    "V30-P03-C04",
    "V30-P03-C05"
  ],
  "executionEpoch": "PRE_S10_PROVISIONAL",
  "fence": {
    "allowedPaths": [
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/execution/V30_CURRENT_TASK.md",
        "purpose": "Single selected-card projection; transition only after the current card's provisional checkpoint.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/execution/V30_CI_SELECTION.json",
        "purpose": "V30-only provisional selector projection; never the inherited Scripts/ci-selection.json.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json",
        "purpose": "Read-only/current-tip projection of the isolated external provisional coordination ledger; never a canonical ledger.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
        "purpose": "Append-only V30 provisional handoff evidence.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Domain/Backup/GlobalizedCatalogReplayContractsV1.swift",
        "purpose": "Catalog/font/renderer/source/replay/missing-resource backup contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Backup/GlobalizedCatalogReplayAdapterV1.swift",
        "purpose": "Historical catalog/replay and explicit limitation adapter.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C08GlobalizedCatalogReplayTests.swift",
        "purpose": "Restore/replay/search-rebuild/current-language independence tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/Backup/globalized-catalog-replay-cases-v1.json",
        "purpose": "Backup/restore catalog replay fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6dbfedde09fbd158b1f44a16e692f5e06e4be0ee",
        "expectedBSHA256": "d7a2b194dff13e4b63976a288f7ac5aa7561a56df17fb86f717dff1ed18c514d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
        "purpose": "Include catalog/font/renderer provenance only without changing canonical source content.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "54e9abdae8e0daea7810e286cac6de8fc08e71ab",
        "expectedBSHA256": "1c82f2bb1d449c0a21f65e3e2883c8cb16a06f6211c292aecf070c733c6341a0",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
        "purpose": "Restore catalog/font/renderer provenance independently of current app language.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "14416e89d89568aa00881fdaf08302f423aed468",
        "expectedBSHA256": "15a454955e266afcf8f3277111bd45d7ba939f8d89ba9add5c93ecb7fd2d1d6f",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
        "purpose": "Export historical catalog replay references through the existing backup path.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "e563b9940061485c693f82f967dcd04b67227b48",
        "expectedBSHA256": "0706245f5d51f835246b66a0cca19783ff524f1b7a5a7ef57c56e9b0e7fb94f9",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
        "purpose": "Import historical catalog replay references through the existing backup path.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "791d3cebb57ddc4f8844cd0cc6cb5c96c929d4cb",
        "expectedBSHA256": "bedeea43e25cceba20b2ed35832e4feba24e9e7db08bdc6bbea33631a029b82d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
        "purpose": "Restore catalog replay and explicit missing-resource limitations.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0bf7f754158823aaa93879f35bcb2993355fef2e",
        "expectedBSHA256": "e65a95dd10cb1e1fde2673f80271bf5aea7257867f253fbc91c7d658b25378b5",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
        "purpose": "Validate catalog replay references and missing-resource limits.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "9da2ac8413b999eb702b1c99407234fc7bbdb62a",
        "expectedBSHA256": "03cfe4e421016895cd1fd6cef4075eb2ff8ac464e7f888c6d382b649770aae3e",
        "path": "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
        "purpose": "Carry catalog/font/renderer references through streaming archive boundaries.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "450afe0ac8fb7f52c1961823ec4bcec35810297a",
        "expectedBSHA256": "2dc0505cabab6b611493108e6573b05aa7e13f1439f08d15478d795cce384a11",
        "path": "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
        "purpose": "Rebuild derived search state after historical catalog restore.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1cb8997fae05384aac4eb8ade5df2651d32cfcee",
        "expectedBSHA256": "ab692ca95973359dda379bfbf01911ad157c2a1c5f6878b214214091462ad640",
        "path": "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
        "purpose": "Extend backup export evidence for catalog replay.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "71deca029b00137b1484f24cf9cffbf4a2e92c35",
        "expectedBSHA256": "a49ce814c521231a87e5bafb83171ba4643c34389732ec794cbefc4dc2eaa813",
        "path": "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
        "purpose": "Extend backup validation evidence for catalog replay.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc13366c237192cc69bcea214813929be3544b4c",
        "expectedBSHA256": "cf25c460046ee10aa8a2f044cef5e117c18ff418f3272038eea9c1c9ba606f69",
        "path": "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
        "purpose": "Extend restore evidence for historical catalog replay.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8639bed99bec1503f63f556fb044f4ac493be506",
        "expectedBSHA256": "d66914b0fd97a95fa7af39ab1502911775a23b883d4be5233cdb4ee778183dba",
        "path": "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
        "purpose": "Bind historical catalog replay to the canonical V4 backup contract.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "91fb0e76cb1f7771b0b0c88a60b6da989e3cd59e",
        "expectedBSHA256": "85bf0383d287ba2c5b3d26dca116f47c07ca31f065540bd7d8bb0771e929b2cf",
        "path": "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
        "purpose": "Bind historical catalog replay to the canonical V4 backup import contract.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "94faa3ceda6b5ba290c5736b807fc03faa183e9c",
        "expectedBSHA256": "fab9f77f8be9d336082634279e675a2728deb38ce5f6d00fd203e8976d9a339d",
        "path": "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
        "purpose": "Preserve restore identity independent of current language/catalog.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fbf23b7be50f1309dd38a142cf422727d929a3dc",
        "expectedBSHA256": "4fe20ecb85d7f508de887e604ed1b526ece97675b21724af5ff87407f4fcecf2",
        "path": "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
        "purpose": "Register catalog replay through the existing kernel restore registry.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Restore historical catalog references through the existing bundled catalog seam.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8cd93ce082652e054201409787ba27fb82c63013",
        "expectedBSHA256": "5d1982421bea62d1ec5339f5a279b6f1f552afa8d90f7dc16f01e389b575dc4f",
        "path": "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
        "purpose": "Validate historical catalog compatibility and explicit missing-resource limitations.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fe2466b4df4800d217767dd392c885b08cfb0f51",
        "expectedBSHA256": "1f8e0cc7a9eaa8ddddfff5383ae6b0ecc94bbc4c73252f9466889c6ffe466b5d",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
        "purpose": "Preserve historical report replay against catalog/font/renderer references.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "b5e778c0bb5bba83defe92b1fe4ca863991897b7",
        "expectedBSHA256": "e0f85f00733d46efce46576466ab568ebbeac59aba0d53015dbcda713e3eb6a8",
        "path": "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
        "purpose": "Regression-test restore identity independent of current language.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c09d86700bb161118f54d96289e0c6167255fc8f",
        "expectedBSHA256": "25a59f8401631f6cbe358b3391dc0617660c03b7d3706b8b65e32aee122581ed",
        "path": "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
        "purpose": "Regression-test checkpoint/replay behavior after catalog restore.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P03-C08",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C08",
      "V30-P03-C04",
      "V30-P03-C05"
    ],
    "ordinal": 29,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Backup, restore, and historical catalog replay"
  },
  "fenceSource": {
    "cardID": "V30-P03-C08",
    "path": "docs/design/v30/authority/V30PreS10PathFencesV1.json",
    "sha256": "3f83225f60b283d8cbe2d18a9ea6401577546595315764ca1d1b156a220bcb1a"
  },
  "forbiddenPaths": [
    "C:/AssetRounds",
    "docs/execution/CURRENT_TASK.md",
    "docs/product/BUILD_PLAN_V4.md",
    "docs/execution/V4_IMPLEMENTATION_RUNBOOK.md",
    "Scripts/ci-selection.json"
  ],
  "next": "V30-P03-C09",
  "observedCoordination": {
    "head": "4579e49b18db394c913e03c5e9d687becda83f12",
    "ledgerDigest": "80566bc6d954ea0bc8688d3813eb37870ba62d242a25863e9fc66990ed469e8c",
    "sequence": 59
  },
  "ordinal": 29,
  "outcome": "Restore canonical/source content, catalog/font/renderer references, derived artifacts, search rebuild state, and explicit missing-resource limitations independent of current app language.",
  "payloadDigest": "f94c107ae21dee2b6f47fa6b2eb520896a9637fde0704ebb4eeb2d4b7345b5c7",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P01-C08": {
      "candidate": {
        "base": "36f9c62ef09bff21c47923add3ade6469a82650e",
        "baseTree": "0f8e0553b2f3780c1f052648b16dfd9c5b8b03f8",
        "changedPaths": [
          "FieldEvidenceApp/Domain/Globalization/LocalizationCatalogReleaseContractsV1.swift",
          "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
          "FieldEvidenceApp/Infrastructure/Localization/LocalizationCatalogReleaseStoreV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/CatalogRelease/catalog-release-cases-v1.json",
          "FieldEvidenceAppTests/V30_P01_C08CatalogReleaseIntegrityTests.swift",
          "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "020c9da6df9c2d9afe741290ecab1b1893d8b2ec",
        "tree": "a7b68fe27452c186cdd9e8c6a244a39c29b5c1ff"
      },
      "sequence": 31
    },
    "V30-P03-C04": {
      "candidate": {
        "base": "45eb5bb4dca6b32f3434d57ccada1059bf8fb0e6",
        "baseTree": "2bd1a2364e17c9185812e43439c95870eb21e29e",
        "changedPaths": [
          "FieldEvidenceApp/Application/Reporting/AccessibleDocumentCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
          "FieldEvidenceApp/Domain/Reporting/GlobalizedAccessibleDocumentContractsV1.swift",
          "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/AccessibleDocumentLifecycleAdapterV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/GlobalizedAccessibleDocumentRendererV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/Reports/globalized-accessible-document-cases-v1.json",
          "FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift",
          "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
          "FieldEvidenceAppTests/V30_P03_C04GlobalizedAccessibleDocumentTests.swift",
          "FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "77b1538aad3ff7229b7f3edcca4045dda7b3e711",
        "tree": "5d967a47111b63f0d3db3f91793abde0bc08b486"
      },
      "sequence": 53
    },
    "V30-P03-C05": {
      "candidate": {
        "base": "77b1538aad3ff7229b7f3edcca4045dda7b3e711",
        "baseTree": "5d967a47111b63f0d3db3f91793abde0bc08b486",
        "changedPaths": [
          "FieldEvidenceApp/Application/ImportExport/ImportBulkCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/ImportExport/GlobalizedMachineExportContractsV1.swift",
          "FieldEvidenceApp/Domain/ImportExport/ImportBulkContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/ImportExport/GlobalizedMachineExportAdapterV1.swift",
          "FieldEvidenceApp/Infrastructure/ImportExport/ImportBulkLifecycleAdapterV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/ImportExport/globalized-machine-export-cases-v1.json",
          "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
          "FieldEvidenceAppTests/V30_P03_C05GlobalizedMachineExportTests.swift",
          "FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "3f902a774e978c8c5c5c953f1e59298c7f9da29b",
        "tree": "068d703866f816bd065962c79991f960ac1091e1"
      },
      "sequence": 55
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 1013,
  "sourceStartLine": 1013,
  "title": "Backup, restore, and historical catalog replay"
}
```
