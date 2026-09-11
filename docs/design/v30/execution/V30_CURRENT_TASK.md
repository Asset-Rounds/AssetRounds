# V30 Current Task

Card 22 of 55 - Authored-content and template-language model

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Distinguish app UI, admin templates, instructions, inspector/customer evidence, derived translations, report chrome, and licensed jurisdiction content. Preserve source and invalidate derived translations after edit/redaction.",
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
    "head": "60815291c28d232c021274fddd352fbe293296ef",
    "tree": "765ec10f2e1034f25b7fe91646d0bb34482ed886"
  },
  "cardID": "V30-P03-C01",
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
    "V30-P02-C02"
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
        "path": "FieldEvidenceApp/Domain/Globalization/AuthoredContentLanguageContractsV1.swift",
        "purpose": "App/UI/template/evidence/derived-translation/report-chrome content-language distinctions.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Globalization/AuthoredContentLanguageCoordinatorV1.swift",
        "purpose": "Source preservation and derived-translation invalidation coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C01AuthoredContentLanguageTests.swift",
        "purpose": "Edit/redaction/source/derived-language lifecycle tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/AuthoredContent/authored-content-language-cases-v1.json",
        "purpose": "Authored-content language fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "19f52a71cb2ded5ac20912bb8634263e7ace1ed6",
        "expectedBSHA256": "a0065b15ef7059867bb00377bd5b97cbcd2e9ac98c74ea0e154297410773f8bb",
        "path": "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
        "purpose": "Distinguish authored/source/derived/report-chrome language in existing document contracts.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "63991694cff079b0fe82f1ba941c15bf8dde2ffb",
        "expectedBSHA256": "faedec6276ef31928285437f049ea1ca34c4cacc35e52ccdcde10dc3d0c0c9c5",
        "path": "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
        "purpose": "Preserve source evidence and historical report snapshot identity across derived translations.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5319ade880b0d30fecb7cc84adc5033b042c536a",
        "expectedBSHA256": "7e75d221f29fbf8b7812bcbae7680098758b071e850c7fd45eddf64fbe0e62b2",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
        "purpose": "Register language provenance without creating a parallel report projection path.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c428c9c4f9128188bb9126d08df2fdab39fe71f3",
        "expectedBSHA256": "84cc28ffe7b87eee1459002852a04f8cca701af8726a94ca5bf032e0407759a1",
        "path": "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
        "purpose": "Invalidate derived translations after canonical edit/redaction through the actual writer boundary.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "ec7e9e1b615baa46195e1b56c1b69bd9b06a03cf",
        "expectedBSHA256": "c67a1362ecf340894d359affb6b4ffba52768c77f4e08d16ae913bfc0b61d19f",
        "path": "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
        "purpose": "Preserve authored/source/derived content provenance through the established content contract.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c7d11749e5e30978a538fad5480fec87a19b9fbb",
        "expectedBSHA256": "29a7de7e0efdf546ba87674f5730b62e07f8d5a6329fc93852fc675da0a613cd",
        "path": "FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift",
        "purpose": "Bind template/instruction language to the existing survey definition contract.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "d4a23964c37b46d021c758a05a16b1510b4d0038",
        "expectedBSHA256": "e012379cfaf64f4dc2315e32e1dc4584029fabcd9ddac0becca6306d8e1ef237",
        "path": "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
        "purpose": "Register content-language provenance through the existing content registry.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "ab0cd81f65c9822d53505491697f91d0de9d15b1",
        "expectedBSHA256": "62b1fd6dfefae68ec6beed96e5f743b132adfddc74d7bafdbd350e1a01bf4eb9",
        "path": "FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift",
        "purpose": "Preserve language provenance and no-translation-service boundary in packaged content execution.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "57f1e5a4a964646fd28eda62d995241973d8ac2c",
        "expectedBSHA256": "70ba681ed8b32543eceaca7bb44d7924921c28e62a93cd02ab5344ed4bf8ac27",
        "path": "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
        "purpose": "Preserve source/derived content provenance in final report snapshot encoding.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6dbfedde09fbd158b1f44a16e692f5e06e4be0ee",
        "expectedBSHA256": "d7a2b194dff13e4b63976a288f7ac5aa7561a56df17fb86f717dff1ed18c514d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
        "purpose": "Preserve authored source and derived-translation invalidation provenance in canonical backup output.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "54e9abdae8e0daea7810e286cac6de8fc08e71ab",
        "expectedBSHA256": "1c82f2bb1d449c0a21f65e3e2883c8cb16a06f6211c292aecf070c733c6341a0",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
        "purpose": "Restore authored source and derived-translation provenance without using current app language.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f302941d7a5ae65f10418aab396cc6091d98bd50",
        "expectedBSHA256": "4955715e9476fd26fa59131a14f681cae2cbe01405ba1893294a73e0185e30ce",
        "path": "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift",
        "purpose": "Regression-test source/content provenance invariants.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0b107dd4303f35eb4a4947c506de315edb10e551",
        "expectedBSHA256": "ac2dd39c003959211c0f310b519f8de3bda1459d6c74c6380a2fed29e00c77e6",
        "path": "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift",
        "purpose": "Regression-test template/instruction language semantics.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7124849b890d0baf1dd6b3027a65de125226b77d",
        "expectedBSHA256": "1db3b7674933f59f0085ad888cc97c5d422c4940e4852580e8140350272dddcc",
        "path": "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
        "purpose": "Regression-test report snapshot provenance.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P03-C01",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C04",
      "V30-P02-C02"
    ],
    "ordinal": 22,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Authored-content and template-language model"
  },
  "fenceSource": {
    "cardID": "V30-P03-C01",
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
  "next": "V30-P03-C02",
  "observedCoordination": {
    "head": "8b1e5cee0304f133e10529aecb8da8b2a0edc5dd",
    "ledgerDigest": "69dc1d9c80feefcc8a089431749286589408191da1d211af8ffebfc69dfb0c52",
    "sequence": 45
  },
  "ordinal": 22,
  "outcome": "Distinguish app UI, admin templates, instructions, inspector/customer evidence, derived translations, report chrome, and licensed jurisdiction content. Preserve source and invalidate derived translations after edit/redaction.",
  "payloadDigest": "cef49c992ee107020b44da84f9797c762cdcc797af81d41c801387e716e2afe4",
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
    "V30-P02-C02": {
      "candidate": {
        "base": "86eabf98abee15c8bd14ff5bfb61a149ab09f103",
        "baseTree": "ab8211eed89a7980d4f38246026800b72226afe3",
        "changedPaths": [
          "FieldEvidenceApp/Application/Globalization/UnicodeEvidenceSafetyCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/Globalization/UnicodeEvidenceSafetyContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
          "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/Unicode/unicode-evidence-hostile-cases-v1.json",
          "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
          "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
          "FieldEvidenceAppTests/V30_P02_C02UnicodeEvidenceSafetyTests.swift",
          "FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift",
          "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "69b57b7eae71dec8d3ab0ea2cb736fc1d828cfbe",
        "tree": "56016965f7f633eaf605460598e21910c1fc298b"
      },
      "sequence": 35
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 1006,
  "sourceStartLine": 1006,
  "title": "Authored-content and template-language model"
}
```
