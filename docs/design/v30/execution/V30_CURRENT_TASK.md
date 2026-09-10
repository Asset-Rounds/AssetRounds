# V30 Current Task

Card 16 of 55 - Unicode input, persistence, journal, and evidence safety

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Preserve grapheme clusters, combining marks, emoji, CJK, Korean, Arabic/bidi, filenames, contacts, notes, captions, labels, and imported text through persistence, events, snapshots, backup, restore, and erase.",
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
    "head": "86eabf98abee15c8bd14ff5bfb61a149ab09f103",
    "tree": "ab8211eed89a7980d4f38246026800b72226afe3"
  },
  "cardID": "V30-P02-C02",
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
        "path": "FieldEvidenceApp/Domain/Globalization/UnicodeEvidenceSafetyContractsV1.swift",
        "purpose": "Unicode preservation and spoof-safe display contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Globalization/UnicodeEvidenceSafetyCoordinatorV1.swift",
        "purpose": "Boundary audit coordinator for persistence, journal, backup, restore, and erase.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P02_C02UnicodeEvidenceSafetyTests.swift",
        "purpose": "Grapheme, CJK, emoji, bidi, filename, and evidence-preservation tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/Unicode/unicode-evidence-hostile-cases-v1.json",
        "purpose": "Hostile Unicode preservation fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c428c9c4f9128188bb9126d08df2fdab39fe71f3",
        "expectedBSHA256": "84cc28ffe7b87eee1459002852a04f8cca701af8726a94ca5bf032e0407759a1",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
        "purpose": "Preserve Unicode at the canonical writer boundary.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f867ebe231a7f998ee89069ca4ce357999efae87",
        "expectedBSHA256": "664647c16a9df7342a123b755f41fc041987a439bf5f55f8a70dafc142fd856b",
        "path": "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
        "purpose": "Preserve Unicode in journal contract payloads and canonical identity.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a54f89f2b61e470eaa66c2bee7142bdddf83c832",
        "expectedBSHA256": "c320713b856bd0a2674ebcbbccc280712993932618ea05dbff321c06d0a19c64",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
        "purpose": "Preserve Unicode through mutation journal persistence and recovery.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "45d5e58ec81cfb61136c895c1756d643a47508ec",
        "expectedBSHA256": "2445e1dcfaeedca8d3304999391dca01bf63cf3a7bc8a9aaeb9f492ef9713d0a",
        "path": "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
        "purpose": "Preserve Unicode through local replication journal records.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6dbfedde09fbd158b1f44a16e692f5e06e4be0ee",
        "expectedBSHA256": "d7a2b194dff13e4b63976a288f7ac5aa7561a56df17fb86f717dff1ed18c514d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
        "purpose": "Preserve Unicode in canonical backup encoding.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "54e9abdae8e0daea7810e286cac6de8fc08e71ab",
        "expectedBSHA256": "1c82f2bb1d449c0a21f65e3e2883c8cb16a06f6211c292aecf070c733c6341a0",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
        "purpose": "Preserve Unicode in canonical backup decoding.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0bf7f754158823aaa93879f35bcb2993355fef2e",
        "expectedBSHA256": "e65a95dd10cb1e1fde2673f80271bf5aea7257867f253fbc91c7d658b25378b5",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
        "purpose": "Validate Unicode-preserving backup package boundaries.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "791d3cebb57ddc4f8844cd0cc6cb5c96c929d4cb",
        "expectedBSHA256": "bedeea43e25cceba20b2ed35832e4feba24e9e7db08bdc6bbea33631a029b82d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
        "purpose": "Preserve Unicode through restore and recovery.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "647167b7ea7d595b2798fca418b3bc0117cd596e",
        "expectedBSHA256": "fb2f5c449afd336d972afa95797256f5ea7b9ffab12e4707ad27b17bfd64bf21",
        "path": "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift",
        "purpose": "Preserve Unicode filenames/captions through evidence bundle storage.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "382c11ed2c1e1676fd987613cfb2115649cf204d",
        "expectedBSHA256": "620600e8ddfb3844f13433a66e75bb45e1e1020a1336003f654217736a3f3473",
        "path": "FieldEvidenceApp/Infrastructure/ImportExport/ImportBulkLifecycleAdapterV1.swift",
        "purpose": "Preserve Unicode through bulk import lifecycle boundaries.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66066190eb633d3a8b7513c0a8d07d2732064044",
        "expectedBSHA256": "3d33b479173d30c56245f48fa46db2637b388ff27eb4e5220944979932fce4bf",
        "path": "FieldEvidenceApp/Infrastructure/ImportExport/EntityIdentityResolutionLifecycleAdapterV1.swift",
        "purpose": "Preserve Unicode through entity identity import/recovery boundaries.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c09d86700bb161118f54d96289e0c6167255fc8f",
        "expectedBSHA256": "25a59f8401631f6cbe358b3391dc0617660c03b7d3706b8b65e32aee122581ed",
        "path": "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
        "purpose": "Regression-test journal Unicode survival.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "71deca029b00137b1484f24cf9cffbf4a2e92c35",
        "expectedBSHA256": "a49ce814c521231a87e5bafb83171ba4643c34389732ec794cbefc4dc2eaa813",
        "path": "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
        "purpose": "Regression-test backup Unicode survival.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc13366c237192cc69bcea214813929be3544b4c",
        "expectedBSHA256": "cf25c460046ee10aa8a2f044cef5e117c18ff418f3272038eea9c1c9ba606f69",
        "path": "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
        "purpose": "Regression-test restore Unicode survival.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "48e816bbe971ef570667572d3faa380c0e3e2241",
        "expectedBSHA256": "6e30e95f92b4427205f63e68650acf948bfe29115b250782e06abdbb46ed1c41",
        "path": "FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift",
        "purpose": "Regression-test import Unicode survival.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P02-C02",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C05"
    ],
    "ordinal": 16,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Unicode input, persistence, journal, and evidence safety"
  },
  "fenceSource": {
    "cardID": "V30-P02-C02",
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
  "next": "V30-P02-C03",
  "observedCoordination": {
    "head": "9caf635edfd3a220afb9e49ba6aa4a06df48ee00",
    "ledgerDigest": "d208d038e62a5f3ceea3d41c9adb4e478cdd23c87022d054dde300a37bc930b2",
    "sequence": 33
  },
  "ordinal": 16,
  "outcome": "Preserve grapheme clusters, combining marks, emoji, CJK, Korean, Arabic/bidi, filenames, contacts, notes, captions, labels, and imported text through persistence, events, snapshots, backup, restore, and erase.",
  "payloadDigest": "b288ede5a4475430743c673e4b4cc452ddb5fb1ffab90b85b7b58308f2fd05b9",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
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
  "sourceEndLine": 995,
  "sourceStartLine": 995,
  "title": "Unicode input, persistence, journal, and evidence safety"
}
```
