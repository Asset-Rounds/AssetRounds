# V30 Current Task

Card 23 of 55 - Offline and sync-state localization integrity

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Cover existing pending/saved/syncing/synchronized/failed/conflicted/recovered states, queued Unicode attachments, offline startup, accessible recovery, and notification truth without creating a new sync engine.",
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
    "head": "c004b4bdd19bc037e3373e7f3a8f508343e5dca0",
    "tree": "7d63520aabb3424f3a2fea35b0bd268400a7517d"
  },
  "cardID": "V30-P03-C02",
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
    "V30-P02-C04"
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
        "path": "FieldEvidenceApp/Domain/Globalization/LocalizedSyncStateContractsV1.swift",
        "purpose": "Existing sync state localization truth contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Localization/LocalizedSyncStateRendererV1.swift",
        "purpose": "Pending/saved/syncing/failed/conflict/recovery localization renderer.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C02OfflineSyncLocalizationTests.swift",
        "purpose": "Offline startup, Unicode attachment, recovery, and notification truth tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/SyncStates/localized-sync-state-cases-v1.json",
        "purpose": "Existing sync-state locale fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Localize current pending/saved/syncing/failed/recovery state copy through the existing catalog.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "ae673d8b72d17198b9853d4f482638551d36f308",
        "expectedBSHA256": "470424a46a97f48a80efaa7a72e81a6f52311369386027fa298d0807e8488e15",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift",
        "purpose": "Preserve localized offline startup/recovery state truth through existing startup routing.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5673ad8f967e053323eb7186af6d812153314e7a",
        "expectedBSHA256": "2e37f0a2961f7051f6d751c4f926d1814eeeace3d456394e49ec1b76d0d45bb7",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
        "purpose": "Preserve localized sync/session state truth through the existing coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "45d5e58ec81cfb61136c895c1756d643a47508ec",
        "expectedBSHA256": "2445e1dcfaeedca8d3304999391dca01bf63cf3a7bc8a9aaeb9f492ef9713d0a",
        "path": "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
        "purpose": "Preserve Unicode sync-state evidence without a new sync engine.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0fcac3c65ac2581c5912936215cd5c2a3b7ff1ed",
        "expectedBSHA256": "700ad042adb3f6cf69eb18e41e078ad0a59e049680bd42e71cd62ca14c7432a0",
        "path": "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
        "purpose": "Render existing recovery/sync-state truth with typed localized messages only.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "2145a692c1100c6345a312ac9255d40041e034e3",
        "expectedBSHA256": "972709e5b3dcc357e11552e01e5f0d2a1e3ee2bbb96c243f4ec7486d11590c78",
        "path": "FieldEvidenceApp/Domain/Replication/SyncClassificationRegistryV1.swift",
        "purpose": "Localize only existing sync classifications without creating a new sync engine.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "3b45dc04e00db9e01f152dedd30c687f3f7f68e9",
        "expectedBSHA256": "60488d3bd40ae65f1c8933c399c46f00525cd799aef6d73b10e64728562c88be",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
        "purpose": "Use the current typed sync-classification catalog as the localization source.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "2809457f13087d6d76d9ea7ec4e20a2392069a9d",
        "expectedBSHA256": "628058e22fc146dfda05c841d54d40be7b26132d1d220c4069e567556feb2f1b",
        "path": "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
        "purpose": "Preserve localized sync event truth at the existing projection boundary.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a54f89f2b61e470eaa66c2bee7142bdddf83c832",
        "expectedBSHA256": "c320713b856bd0a2674ebcbbccc280712993932618ea05dbff321c06d0a19c64",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
        "purpose": "Preserve sync-state evidence/recovery identity through the mutation journal.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1798cf7b2fd27e4005c2877083108b8362cd450f",
        "expectedBSHA256": "fd97a87be8b5e83f9458f2d8e517c79c552876f9adf5eed3e8472a876edc7af5",
        "path": "FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift",
        "purpose": "Render localized offline/recovery state through the existing recovery surface.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "424f869477fe107d1595763c951abef7193c9c6b",
        "expectedBSHA256": "64f745df1643d2271317756930f2cb003a9bc34bfba23a8cd70477a9a047aa7f",
        "path": "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
        "purpose": "Render only existing offline startup/recovery state with typed localized text; preserve Phase10 visual styling.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c09d86700bb161118f54d96289e0c6167255fc8f",
        "expectedBSHA256": "25a59f8401631f6cbe358b3391dc0617660c03b7d3706b8b65e32aee122581ed",
        "path": "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
        "purpose": "Regression-test localized sync state without journal drift.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1134417b3f24bf056cef13cdb133ea61d34c43fc",
        "expectedBSHA256": "7b1c9163359202e97558078c3a782a03faa543ce7c14198ab1893e2fd65da5df",
        "path": "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
        "purpose": "Regression-test sync-state localization/accessibility.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P03-C02",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C08",
      "V30-P02-C04"
    ],
    "ordinal": 23,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "render only existing recovery/sync-state truth with typed localized messages; preserve Phase10 visual styling",
        "cardID": "V30-P03-C02",
        "expectedBBlobOID": "0fcac3c65ac2581c5912936215cd5c2a3b7ff1ed",
        "expectedBSHA256": "700ad042adb3f6cf69eb18e41e078ad0a59e049680bd42e71cd62ca14c7432a0",
        "path": "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C02-SYNC-STATE-INTEGRATOR"
      },
      {
        "boundedPurpose": "render only existing offline startup/recovery state with typed localized text; preserve Phase10 visual styling and shell behavior",
        "cardID": "V30-P03-C02",
        "expectedBBlobOID": "424f869477fe107d1595763c951abef7193c9c6b",
        "expectedBSHA256": "64f745df1643d2271317756930f2cb003a9bc34bfba23a8cd70477a9a047aa7f",
        "path": "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C02-SYNC-STATE-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
      "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Offline and sync-state localization integrity"
  },
  "fenceSource": {
    "cardID": "V30-P03-C02",
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
  "next": "V30-P03-C03",
  "observedCoordination": {
    "head": "db73b9b02644536f59067dfe8c0aeb97cdf5184d",
    "ledgerDigest": "eb151919345c191dd26f66e512407eac984aa16a549e46b3f041a94a62b5f119",
    "sequence": 47
  },
  "ordinal": 23,
  "outcome": "Cover existing pending/saved/syncing/synchronized/failed/conflicted/recovered states, queued Unicode attachments, offline startup, accessible recovery, and notification truth without creating a new sync engine.",
  "payloadDigest": "417893dadf53077be55511f2e4a6c959c5511ed4ae77b7ed08aaa3796deae1be",
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
    "V30-P02-C04": {
      "candidate": {
        "base": "0a7a4d9d82683a4b2aab06508623fc0a1f910586",
        "baseTree": "551a18514c114181227dcaf8010c0f1f55f1217a",
        "changedPaths": [
          "FieldEvidenceApp/DesignSystem/GlobalizationAdaptiveLayoutPolicyV1.swift",
          "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
          "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
          "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
          "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
          "FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift",
          "FieldEvidenceApp/Features/Rounds/RoundSessionView.swift",
          "FieldEvidenceApp/Features/Shell/AppShellView.swift",
          "FieldEvidenceAppTests/Fixtures/V30/Accessibility/expansion-and-type-cases-v1.json",
          "FieldEvidenceAppTests/V30_P02_C04AdaptiveAccessibilityTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "d804f60308bcfdcaadf01780d429132e4bcbd77d",
        "tree": "0cde23d9cf27616f10d4465ef4ee5a9ac387791e"
      },
      "sequence": 39
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 1007,
  "sourceStartLine": 1007,
  "title": "Offline and sync-state localization integrity"
}
```
