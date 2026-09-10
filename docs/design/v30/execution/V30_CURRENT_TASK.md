# V30 Current Task

Card 14 of 55 — Catalog release mechanism, provenance schema, compatibility, and offline integrity

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Implement the versioned catalog-release schema, validator, compatibility/supersession/rollback, zero-network loading, fallback evidence, and historical lookup. No locale release or reviewer receipt is final before P04-C07 and P05 reconciliation.",
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
    "head": "36f9c62ef09bff21c47923add3ade6469a82650e",
    "tree": "0f8e0553b2f3780c1f052648b16dfd9c5b8b03f8"
  },
  "cardID": "V30-P01-C08",
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
    "V30-P01-C03",
    "V30-P01-C04",
    "V30-P01-C05",
    "V30-P01-C06"
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
        "path": "FieldEvidenceApp/Domain/Globalization/LocalizationCatalogReleaseContractsV1.swift",
        "purpose": "Versioned catalog release, compatibility, supersession, rollback, and provenance contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Localization/LocalizationCatalogReleaseStoreV1.swift",
        "purpose": "Offline catalog release storage and historical lookup.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P01_C08CatalogReleaseIntegrityTests.swift",
        "purpose": "Offline integrity and historical lookup tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/CatalogRelease/catalog-release-cases-v1.json",
        "purpose": "Catalog release compatibility fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8cd93ce082652e054201409787ba27fb82c63013",
        "expectedBSHA256": "5d1982421bea62d1ec5339f5a279b6f1f552afa8d90f7dc16f01e389b575dc4f",
        "path": "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
        "purpose": "Make the existing catalog release/compatibility validation authoritative for versioned V30 releases.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Bind existing bundled catalog loading to offline release/provenance/rollback validation.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "69a33d27f8db846dd27ae5e554856a4e12e8aeaf",
        "expectedBSHA256": "67cbc936089d01bc772330600727ddea7d312a5a52cd8b16f5f3aff3577d8a53",
        "path": "FieldEvidenceApp/Resources/Localizable.xcstrings",
        "purpose": "Bind the existing source catalog to release digest and historical lookup metadata.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1134417b3f24bf056cef13cdb133ea61d34c43fc",
        "expectedBSHA256": "7b1c9163359202e97558078c3a782a03faa543ce7c14198ab1893e2fd65da5df",
        "path": "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
        "purpose": "Extend existing release/locale validation regression coverage.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P01-C08",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C03",
      "V30-P01-C04",
      "V30-P01-C05",
      "V30-P01-C06"
    ],
    "ordinal": 14,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Catalog release mechanism, provenance schema, compatibility, and offline integrity"
  },
  "fenceSource": {
    "cardID": "V30-P01-C08",
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
  "next": "V30-P02-C01",
  "observedCoordination": {
    "head": "d02682ce99608d7eba028802c79d35aae89d3265",
    "ledgerDigest": "f216c0bd80463419a20bdd5bbe8c67543332c135760e3c6e3a344e5667f9b889",
    "sequence": 28
  },
  "ordinal": 14,
  "outcome": "Implement the versioned catalog-release schema, validator, compatibility/supersession/rollback, zero-network loading, fallback evidence, and historical lookup. No locale release or reviewer receipt is final before P04-C07 and P05 reconciliation.",
  "payloadDigest": "bc527304912b227b8bbdc69981c515912390585e1c87e142e573187931838159",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P01-C03": {
      "candidate": {
        "base": "321eaf374c88ed7733549341c5de8d9505e4d76e",
        "baseTree": "c783e1ea1c28466025978aebf428dd7c43a1a5b2",
        "changedPaths": [
          "FieldEvidenceAppTests/V30_P01_C03TextSurfaceInventoryTests.swift",
          "Scripts/v30/validate_v30_text_surface_inventory.py",
          "docs/design/v30/inventory/V30TextBearingSurfaceInventoryV1.json",
          "docs/design/v30/inventory/V30TextSurfaceDispositionSchemaV1.json"
        ],
        "head": "e13882efbfce199ee97b70d9d9e73cc434ce9217",
        "tree": "0d6e32f5f1aa589b7189b0e9e4dc80e1c822473c"
      },
      "sequence": 20
    },
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
    },
    "V30-P01-C06": {
      "candidate": {
        "base": "66ef581ea88ce2ee1d6cb35586574d5df5c94bf7",
        "baseTree": "4c5b3b3e0f72e9f4e947ceb75d1ac30e5db542f7",
        "changedPaths": [
          "FieldEvidenceApp/Application/Ports/SettingsCapabilityPortsV1.swift",
          "FieldEvidenceApp/Application/Settings/GlobalizationSettingsCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/Globalization/EffectiveLanguageContractsV1.swift",
          "FieldEvidenceApp/Features/Shell/AppShellView.swift",
          "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
          "FieldEvidenceApp/Infrastructure/Localization/SystemLanguageResolverV1.swift",
          "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/LanguageResolution/system-language-cases-v1.json",
          "FieldEvidenceAppTests/V30_P01_C06SystemLanguageResolutionTests.swift",
          "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "3a28f593e755ac952071777b7e8440457950a010",
        "tree": "7f67173942a087f86770b10ed8bf99041425ee4f"
      },
      "sequence": 26
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 988,
  "sourceStartLine": 988,
  "title": "Catalog release mechanism, provenance schema, compatibility, and offline integrity"
}
```
