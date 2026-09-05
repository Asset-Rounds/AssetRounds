# V30 Current Task

Card 13 of 55 — Locale-aware formatting and input grammar

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Implement and test dates, instants/local time, DST, calendars, numbers, currency, percent, units, week rules, paper, addresses, phones, parsing, ambiguous-input rejection, and canonical round trips with Foundation locale-aware APIs.",
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
    "head": "3a28f593e755ac952071777b7e8440457950a010",
    "tree": "7f67173942a087f86770b10ed8bf99041425ee4f"
  },
  "cardID": "V30-P01-C07",
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
    "V30-P01-C04",
    "V30-P01-C05"
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
        "path": "FieldEvidenceApp/Domain/Globalization/LocaleFormatContractsV1.swift",
        "purpose": "Locale formatting and canonical-input grammar contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Localization/LocaleFormattingServiceV1.swift",
        "purpose": "Foundation-backed date/number/unit/phone/address formatter and parser.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P01_C07LocaleFormattingTests.swift",
        "purpose": "DST, calendar, number, unit, paper, parsing, and canonical round-trip tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/LocaleFormatting/formatting-grammar-cases-v1.json",
        "purpose": "Locale-hostile input grammar fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Route existing typed display formatting through the locale-aware contract without changing canonical values.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "19f52a71cb2ded5ac20912bb8634263e7ace1ed6",
        "expectedBSHA256": "a0065b15ef7059867bb00377bd5b97cbcd2e9ac98c74ea0e154297410773f8bb",
        "path": "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
        "purpose": "Bind document language, formatting locale, paper, and provenance to existing report contracts.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc88143bf623ba193458ef3eabcf6f56872df93f",
        "expectedBSHA256": "b47b36127800c20edba871c80f7b32614f674c8f99d22de1d3ddc3a2450efa05",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
        "purpose": "Use locale-aware display formatting in existing PDF/report rendering while preserving canonical snapshots.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "28e7f335a3337fb6e353a94181e67daab40b0a50",
        "expectedBSHA256": "b4b2627fe05210957e51e54a48841b0cd3b385bf1ba6a384e94e3f6b9a75ecf7",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
        "purpose": "Preserve canonical timestamps while selecting explicit human-readable report formatting.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "e830455b14706763c3f9be4a930cd27955ef0890",
        "expectedBSHA256": "d8b9376be21c1b441c5f166ed22b851c35de63d8ba056e82ae1d30f4628933e6",
        "path": "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
        "purpose": "Replace only locale-sensitive date/number input and display formatting in the existing record-work UI.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c48fbb8f39643d24cef00d49a5ed90313780c1f5",
        "expectedBSHA256": "8c7dd5d1412895266be2ad1c5bffe743c13db2b1c2074e2f35d5b0e6d947f310",
        "path": "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
        "purpose": "Replace only locale-sensitive date/number display formatting in the existing work coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "862a87c6d5fb3370c535c1a55a8ca077a6d94691",
        "expectedBSHA256": "29bf9d1baf9377b8f88440a5fdb65cb38aeed765b3d8d5f2b3c1980da15736b5",
        "path": "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
        "purpose": "Regression-test locale-formatted report recovery without canonical drift.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "86a55cf4145939361ebdf82af7b16f052ecdb1c4",
        "expectedBSHA256": "74e2ac75ce267ccc455d15c1780f7e0dfb6c8ff8c19433179719a29b2dd2c00e",
        "path": "FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift",
        "purpose": "Regression-test explicit report formatting and delivery behavior.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P01-C07",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C04",
      "V30-P01-C05"
    ],
    "ordinal": 13,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "replace only locale-sensitive date/number input or display formatting in FieldEvidenceApp/Features/Issues/RecordWorkView.swift; preserve Phase10 visual styling and workflow behavior",
        "cardID": "V30-P01-C07",
        "expectedBBlobOID": "e830455b14706763c3f9be4a930cd27955ef0890",
        "expectedBSHA256": "d8b9376be21c1b441c5f166ed22b851c35de63d8ba056e82ae1d30f4628933e6",
        "path": "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P01-C07-LOCALE-FORMAT-INTEGRATOR"
      },
      {
        "boundedPurpose": "replace only locale-sensitive date/number input or display formatting in FieldEvidenceApp/Features/Issues/WorkCoordinator.swift; preserve Phase10 visual styling and workflow behavior",
        "cardID": "V30-P01-C07",
        "expectedBBlobOID": "c48fbb8f39643d24cef00d49a5ed90313780c1f5",
        "expectedBSHA256": "8c7dd5d1412895266be2ad1c5bffe743c13db2b1c2074e2f35d5b0e6d947f310",
        "path": "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P01-C07-LOCALE-FORMAT-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
      "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Locale-aware formatting and input grammar"
  },
  "fenceSource": {
    "cardID": "V30-P01-C07",
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
  "next": "V30-P01-C08",
  "observedCoordination": {
    "head": "1638c8ed38af81dade54ba745ab4f24610700469",
    "ledgerDigest": "104cd56257212830e8e9395f5266af4d4cc7c81250f9845f91e722a491ddf32f",
    "sequence": 26
  },
  "ordinal": 13,
  "outcome": "Implement and test dates, instants/local time, DST, calendars, numbers, currency, percent, units, week rules, paper, addresses, phones, parsing, ambiguous-input rejection, and canonical round trips with Foundation locale-aware APIs.",
  "payloadDigest": "9da58a445765c5e872a977fe9d92d4f6b076336eac20d4df6734427b77eae6f2",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P01-C04": {
      "candidate": {
        "base": "e13882efbfce199ee97b70d9d9e73cc434ce9217",
        "baseTree": "0d6e32f5f1aa589b7189b0e9e4dc80e1c822473c",
        "changedPaths": [
          "FieldEvidenceApp/Application/Globalization/GlobalizationAxisCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
          "FieldEvidenceApp/Domain/Globalization/GlobalizationAxisContractsV1.swift",
          "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
          "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
          "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
          "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/GlobalizationAxes/axis-matrix-v1.json",
          "FieldEvidenceAppTests/V30_P01_C04GlobalizationAxisContractTests.swift",
          "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift"
        ],
        "head": "a96e445a572ef4a83b39f10899cc78df52ff9a23",
        "tree": "4107ccdc7b2c2dbd1b6829148797be67c2fecb13"
      },
      "sequence": 22
    },
    "V30-P01-C05": {
      "candidate": {
        "base": "a96e445a572ef4a83b39f10899cc78df52ff9a23",
        "baseTree": "4107ccdc7b2c2dbd1b6829148797be67c2fecb13",
        "changedPaths": [
          "FieldEvidenceApp/Application/Globalization/CanonicalIdentityAuditCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
          "FieldEvidenceApp/Domain/Globalization/CanonicalIdentityInvarianceV1.swift",
          "FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift",
          "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
          "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
          "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
          "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
          "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
          "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
          "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
          "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/CanonicalIdentity/en-us-identity-baseline-v1.json",
          "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
          "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
          "FieldEvidenceAppTests/V30_P01_C05CanonicalIdentityInvarianceTests.swift",
          "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "66ef581ea88ce2ee1d6cb35586574d5df5c94bf7",
        "tree": "4c5b3b3e0f72e9f4e947ceb75d1ac30e5db542f7"
      },
      "sequence": 24
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 987,
  "sourceStartLine": 987,
  "title": "Locale-aware formatting and input grammar"
}
```
