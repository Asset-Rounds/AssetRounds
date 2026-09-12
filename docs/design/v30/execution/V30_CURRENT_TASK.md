# V30 Current Task

Card 26 of 55 - Stable JSON, CSV, export, and import contracts

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Preserve language-neutral machine keys/values, add explicit localized-human variants, locale manifests, formula safety, media references, unambiguous parsing, and exact canonical round trip.",
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
    "head": "77b1538aad3ff7229b7f3edcca4045dda7b3e711",
    "tree": "5d967a47111b63f0d3db3f91793abde0bc08b486"
  },
  "cardID": "V30-P03-C05",
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
    "V30-P01-C05",
    "V30-P03-C01"
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
        "path": "FieldEvidenceApp/Domain/ImportExport/GlobalizedMachineExportContractsV1.swift",
        "purpose": "Language-neutral machine export/import and localized-human variant contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/ImportExport/GlobalizedMachineExportAdapterV1.swift",
        "purpose": "Locale manifests, formula safety, media references, and canonical round-trip adapter.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C05GlobalizedMachineExportTests.swift",
        "purpose": "JSON/CSV/import stable-key and exact round-trip tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/ImportExport/globalized-machine-export-cases-v1.json",
        "purpose": "Export/import locale-manifest fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "961ca6ad753a73aff61c9b574ef0af11319e5f1f",
        "expectedBSHA256": "38629e4a55a5d5d07ebc7159de15ccd6ffe45edfeddae777db40cdab32ab850b",
        "path": "FieldEvidenceApp/Domain/ImportExport/ImportBulkContractsV1.swift",
        "purpose": "Preserve language-neutral machine keys and add explicit localized-human variants in existing import/export contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "382c11ed2c1e1676fd987613cfb2115649cf204d",
        "expectedBSHA256": "620600e8ddfb3844f13433a66e75bb45e1e1020a1336003f654217736a3f3473",
        "path": "FieldEvidenceApp/Infrastructure/ImportExport/ImportBulkLifecycleAdapterV1.swift",
        "purpose": "Apply locale manifests/formula safety/media references through the existing import/export lifecycle seam.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "d8dcc7fe5f5bca80bf21e964ad411aaac2baa837",
        "expectedBSHA256": "444d71a74c2b4336ffd4ab7e46850fcb7ee7afc7edaebb1bf311d0431e6d99b4",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
        "purpose": "Preserve stable JSON machine fields and add bounded human display metadata.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "ed958cc6b4b16f0ef0c6523dd44226453c43d47b",
        "expectedBSHA256": "295cc34f95eb9b3bad1e40dae524131ea77bbbb975e37714cef39ea1b8ac7c3b",
        "path": "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
        "purpose": "Keep diagnostic/export machine data stable across language changes.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "48e816bbe971ef570667572d3faa380c0e3e2241",
        "expectedBSHA256": "6e30e95f92b4427205f63e68650acf948bfe29115b250782e06abdbb46ed1c41",
        "path": "FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift",
        "purpose": "Extend existing import/export round-trip regression coverage.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "d1848b8298b82ca30070ed3453faa5de532654d1",
        "expectedBSHA256": "867636d904e5088b6e334ed1893725ab7df947e588ebcd43eaf3629cca95cfeb",
        "path": "FieldEvidenceApp/Application/ImportExport/ImportBulkCoordinatorV1.swift",
        "purpose": "Route stable machine/localized-human import-export semantics through the existing coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66066190eb633d3a8b7513c0a8d07d2732064044",
        "expectedBSHA256": "3d33b479173d30c56245f48fa46db2637b388ff27eb4e5220944979932fce4bf",
        "path": "FieldEvidenceApp/Infrastructure/ImportExport/EntityIdentityResolutionLifecycleAdapterV1.swift",
        "purpose": "Preserve stable identity during localized import/export normalization.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6dbfedde09fbd158b1f44a16e692f5e06e4be0ee",
        "expectedBSHA256": "d7a2b194dff13e4b63976a288f7ac5aa7561a56df17fb86f717dff1ed18c514d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
        "purpose": "Keep machine export/backup canonical encoding language-neutral.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "54e9abdae8e0daea7810e286cac6de8fc08e71ab",
        "expectedBSHA256": "1c82f2bb1d449c0a21f65e3e2883c8cb16a06f6211c292aecf070c733c6341a0",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
        "purpose": "Keep machine import/backup canonical decoding language-neutral.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "14416e89d89568aa00881fdaf08302f423aed468",
        "expectedBSHA256": "15a454955e266afcf8f3277111bd45d7ba939f8d89ba9add5c93ecb7fd2d1d6f",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
        "purpose": "Export locale manifests without changing canonical backup fields.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "e563b9940061485c693f82f967dcd04b67227b48",
        "expectedBSHA256": "0706245f5d51f835246b66a0cca19783ff524f1b7a5a7ef57c56e9b0e7fb94f9",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
        "purpose": "Import locale manifests without changing canonical backup fields.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0bf7f754158823aaa93879f35bcb2993355fef2e",
        "expectedBSHA256": "e65a95dd10cb1e1fde2673f80271bf5aea7257867f253fbc91c7d658b25378b5",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
        "purpose": "Validate locale manifests/formula safety without changing canonical machine fields.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7aba91ae3ce2c9e70f5b499ce217481d4490d0a0",
        "expectedBSHA256": "d1c72a9ad7dcc747384bb3c65dd312a65686592905da86868ca2c6b23a7bb8bd",
        "path": "FieldEvidenceAppTests/V9_95PartyContactSiteRoleImportTests.swift",
        "purpose": "Regression-test stable imported identifiers under localized-human variants.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1cb8997fae05384aac4eb8ade5df2651d32cfcee",
        "expectedBSHA256": "ab692ca95973359dda379bfbf01911ad157c2a1c5f6878b214214091462ad640",
        "path": "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
        "purpose": "Regression-test machine export/backup locale manifest boundaries.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P03-C05",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C05",
      "V30-P03-C01"
    ],
    "ordinal": 26,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Stable JSON, CSV, export, and import contracts"
  },
  "fenceSource": {
    "cardID": "V30-P03-C05",
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
  "next": "V30-P03-C06",
  "observedCoordination": {
    "head": "4a0ed48fc412bbde6e4464d7f775104ab9cb23a8",
    "ledgerDigest": "76b7e7602efc93ef5951fb5efa861b46d51197b90a8b0aeee36857567bcbc6fd",
    "sequence": 53
  },
  "ordinal": 26,
  "outcome": "Preserve language-neutral machine keys/values, add explicit localized-human variants, locale manifests, formula safety, media references, unambiguous parsing, and exact canonical round trip.",
  "payloadDigest": "7f78beab4c9fb30ccf6a97d05e889adf143b26ecb3cf4b4502756a62b91b92ce",
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
    },
    "V30-P03-C01": {
      "candidate": {
        "base": "60815291c28d232c021274fddd352fbe293296ef",
        "baseTree": "765ec10f2e1034f25b7fe91646d0bb34482ed886",
        "changedPaths": [
          "FieldEvidenceApp/Application/Globalization/AuthoredContentLanguageCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
          "FieldEvidenceApp/Domain/Globalization/AuthoredContentLanguageContractsV1.swift",
          "FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift",
          "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
          "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
          "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
          "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/AuthoredContent/authored-content-language-cases-v1.json",
          "FieldEvidenceAppTests/V30_P03_C01AuthoredContentLanguageTests.swift",
          "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift",
          "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
          "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "c004b4bdd19bc037e3373e7f3a8f508343e5dca0",
        "tree": "7d63520aabb3424f3a2fea35b0bd268400a7517d"
      },
      "sequence": 47
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 1010,
  "sourceStartLine": 1010,
  "title": "Stable JSON, CSV, export, and import contracts"
}
```
