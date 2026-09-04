# V30 Current Task

Card 11 of 55 — Canonical-data and historical-identity invariance

Only the exact pre-issued fence below is writable. Embedded context is the active hydration; create a separate context file only if the exact fence names it. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Enforce and test that language/formatting changes cannot alter IDs, raw enum values, mutations, journals, evidence hashes, backup identity, authored evidence, product identity, or jurisdiction. Preserve old en-US-bearing identities.",
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
    "head": "a96e445a572ef4a83b39f10899cc78df52ff9a23",
    "tree": "4107ccdc7b2c2dbd1b6829148797be67c2fecb13"
  },
  "cardID": "V30-P01-C05",
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
    "V30-P01-C04"
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
        "path": "FieldEvidenceApp/Domain/Globalization/CanonicalIdentityInvarianceV1.swift",
        "purpose": "Language/locale invariance assertions for canonical identity.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Globalization/CanonicalIdentityAuditCoordinatorV1.swift",
        "purpose": "Audit coordinator for journals, evidence, backup, and jurisdiction invariance.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P01_C05CanonicalIdentityInvarianceTests.swift",
        "purpose": "Canonical-ID and historical identity regression tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/CanonicalIdentity/en-us-identity-baseline-v1.json",
        "purpose": "Frozen en-US identity baseline fixture.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f28f90aa7b8b19519412ed879788166d01309008",
        "expectedBSHA256": "8e9814f0a5164b72aea2ba7f7b710e2bd4b20f1b14a3f6ee9306047218a2505d",
        "path": "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
        "purpose": "Prove language/formatting changes cannot change canonical settings identity.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f867ebe231a7f998ee89069ca4ce357999efae87",
        "expectedBSHA256": "664647c16a9df7342a123b755f41fc041987a439bf5f55f8a70dafc142fd856b",
        "path": "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
        "purpose": "Preserve language-neutral journal event identity and raw values.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a54f89f2b61e470eaa66c2bee7142bdddf83c832",
        "expectedBSHA256": "c320713b856bd0a2674ebcbbccc280712993932618ea05dbff321c06d0a19c64",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
        "purpose": "Enforce canonical mutation-journal identity across locale changes.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "45d5e58ec81cfb61136c895c1756d643a47508ec",
        "expectedBSHA256": "2445e1dcfaeedca8d3304999391dca01bf63cf3a7bc8a9aaeb9f492ef9713d0a",
        "path": "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
        "purpose": "Preserve replication journal bytes and replay identity across locale changes.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c428c9c4f9128188bb9126d08df2fdab39fe71f3",
        "expectedBSHA256": "84cc28ffe7b87eee1459002852a04f8cca701af8726a94ca5bf032e0407759a1",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
        "purpose": "Keep canonical writer receipt/identity invariant under display locale changes.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8639bed99bec1503f63f556fb044f4ac493be506",
        "expectedBSHA256": "d66914b0fd97a95fa7af39ab1502911775a23b883d4be5233cdb4ee778183dba",
        "path": "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
        "purpose": "Keep backup identity language-neutral and historically stable.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6dbfedde09fbd158b1f44a16e692f5e06e4be0ee",
        "expectedBSHA256": "d7a2b194dff13e4b63976a288f7ac5aa7561a56df17fb86f717dff1ed18c514d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
        "purpose": "Keep canonical backup encoding independent of UI language and formatting locale.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "54e9abdae8e0daea7810e286cac6de8fc08e71ab",
        "expectedBSHA256": "1c82f2bb1d449c0a21f65e3e2883c8cb16a06f6211c292aecf070c733c6341a0",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
        "purpose": "Keep canonical backup decoding independent of current UI language.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0bf7f754158823aaa93879f35bcb2993355fef2e",
        "expectedBSHA256": "e65a95dd10cb1e1fde2673f80271bf5aea7257867f253fbc91c7d658b25378b5",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
        "purpose": "Validate canonical backup identity without translated-data assumptions.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "791d3cebb57ddc4f8844cd0cc6cb5c96c929d4cb",
        "expectedBSHA256": "bedeea43e25cceba20b2ed35832e4feba24e9e7db08bdc6bbea33631a029b82d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
        "purpose": "Restore canonical identity without rewriting language-neutral data.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c09d86700bb161118f54d96289e0c6167255fc8f",
        "expectedBSHA256": "25a59f8401631f6cbe358b3391dc0617660c03b7d3706b8b65e32aee122581ed",
        "path": "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
        "purpose": "Regression-test journal/checkpoint identity invariance.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "71deca029b00137b1484f24cf9cffbf4a2e92c35",
        "expectedBSHA256": "a49ce814c521231a87e5bafb83171ba4643c34389732ec794cbefc4dc2eaa813",
        "path": "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
        "purpose": "Regression-test backup validation identity invariance.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc13366c237192cc69bcea214813929be3544b4c",
        "expectedBSHA256": "cf25c460046ee10aa8a2f044cef5e117c18ff418f3272038eea9c1c9ba606f69",
        "path": "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
        "purpose": "Regression-test atomic restore identity invariance.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P01-C05",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C04"
    ],
    "ordinal": 11,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Canonical-data and historical-identity invariance"
  },
  "fenceSource": {
    "cardID": "V30-P01-C05",
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
  "next": "V30-P01-C06",
  "observedCoordination": {
    "head": "a827ef11d6c8785c5031cde9f209884815a94e06",
    "ledgerDigest": "b1bc2461e3be47bb310480f651f838e12f7c1d5ce08de1e7eaa1fb7bdf64a606",
    "sequence": 22
  },
  "ordinal": 11,
  "outcome": "Enforce and test that language/formatting changes cannot alter IDs, raw enum values, mutations, journals, evidence hashes, backup identity, authored evidence, product identity, or jurisdiction. Preserve old en-US-bearing identities.",
  "payloadDigest": "d4c1a2e7714f9f1b516f6b023237c02c07968844bf1c51394a73433536c4dcae",
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
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 985,
  "sourceStartLine": 985,
  "title": "Canonical-data and historical-identity invariance"
}
```
