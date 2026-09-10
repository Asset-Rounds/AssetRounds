# V30 Current Task

Card 19 of 55 - Locale-aware search, sorting, and normalization

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Add versioned derived search normalization, CJK segmentation, Korean composition, diacritics, hostile Turkish/Arabic cases, stable tie-breakers, rebuild/recovery/erase/backup boundaries, and unmodified canonical identifiers.",
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
    "head": "d804f60308bcfdcaadf01780d429132e4bcbd77d",
    "tree": "0cde23d9cf27616f10d4465ef4ee5a9ac387791e"
  },
  "cardID": "V30-P02-C05",
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
    "V30-P01-C07",
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
        "path": "FieldEvidenceApp/Domain/Search/GlobalizedSearchNormalizationContractsV1.swift",
        "purpose": "Versioned derived-search normalization and stable tie-breaker contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Search/GlobalizedSearchNormalizationServiceV1.swift",
        "purpose": "CJK, Hangul, diacritic, Turkish, and Arabic normalization adapter.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P02_C05GlobalizedSearchTests.swift",
        "purpose": "Search rebuild, recovery, erase, backup, and canonical-identifier tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/Search/globalized-search-cases-v1.json",
        "purpose": "Locale-aware search and sorting fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1e9dbbed51414fdc966cec2b11710ee75ceb1a27",
        "expectedBSHA256": "abe2182a403cb10cc939ba24884973f9c91b8066c47a0cc500e1ad236169312f",
        "path": "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
        "purpose": "Version-forward existing search contracts for derived locale normalization and stable ties.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "b4182deee643168333d22bd4a4b12cfd67cd7c92",
        "expectedBSHA256": "ee649eee8f456857c9b722fe04b2028488c88c73169e8cad737b6f594fbc1ac2",
        "path": "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
        "purpose": "Version-forward existing persisted derived-search models without changing canonical identifiers.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c3cb1fa6103c35effc8b61e0d7016d753be7702a",
        "expectedBSHA256": "f253fdd2746c3ef862df86f7237433be9b46d42928835e373cd5f673664abe39",
        "path": "FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift",
        "purpose": "Route existing search coordination through versioned locale normalization.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "75c55074e9721a08c66748cdd171ae465b965b7d",
        "expectedBSHA256": "1a3b2362041a48b0ab300429df82a4d38feea0a1f4f109f7acf5e53ed57ed433",
        "path": "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
        "purpose": "Persist locale-normalized derived search rows only.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "450afe0ac8fb7f52c1961823ec4bcec35810297a",
        "expectedBSHA256": "2dc0505cabab6b611493108e6573b05aa7e13f1439f08d15478d795cce384a11",
        "path": "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
        "purpose": "Rebuild locale-normalized derived search safely from canonical records.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "791d3cebb57ddc4f8844cd0cc6cb5c96c929d4cb",
        "expectedBSHA256": "bedeea43e25cceba20b2ed35832e4feba24e9e7db08bdc6bbea33631a029b82d",
        "path": "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
        "purpose": "Restore/rebuild only derived search normalization state.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a498c81add042147f40c6a29e5d05c9c52e1657d",
        "expectedBSHA256": "0707f4aeffe62d6bfcfc025b41ac9af5e129833030c42bd664c044b69a761f9d",
        "path": "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
        "purpose": "Erase derived locale search state without affecting canonical data.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "83fc944c05720c0d132832077a3bf4d571a6284d",
        "expectedBSHA256": "d3a73015b8774d8bebf71f408093ca20a5ca00a077a55f2800e43003ac82975a",
        "path": "FieldEvidenceAppTests/V9_19LocalSearchTests.swift",
        "purpose": "Extend existing local-search normalization/rebuild coverage.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc13366c237192cc69bcea214813929be3544b4c",
        "expectedBSHA256": "cf25c460046ee10aa8a2f044cef5e117c18ff418f3272038eea9c1c9ba606f69",
        "path": "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
        "purpose": "Extend restore/rebuild coverage for derived search state.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P02-C05",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C07",
      "V30-P02-C02"
    ],
    "ordinal": 19,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Locale-aware search, sorting, and normalization"
  },
  "fenceSource": {
    "cardID": "V30-P02-C05",
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
  "next": "V30-P02-C06",
  "observedCoordination": {
    "head": "c4faa21169a2c8e1121a52bfaf3407f3e3e396d5",
    "ledgerDigest": "0e2d5f157b886d90b5a56a5070280f49959550d74c26e2efab49a4f9be0e9990",
    "sequence": 39
  },
  "ordinal": 19,
  "outcome": "Add versioned derived search normalization, CJK segmentation, Korean composition, diacritics, hostile Turkish/Arabic cases, stable tie-breakers, rebuild/recovery/erase/backup boundaries, and unmodified canonical identifiers.",
  "payloadDigest": "954ab6307ceab26025b734793bf423183ab61f4dff8ef7d53ce27a55e13e15d0",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P01-C07": {
      "candidate": {
        "base": "3a28f593e755ac952071777b7e8440457950a010",
        "baseTree": "7f67173942a087f86770b10ed8bf99041425ee4f",
        "changedPaths": [
          "FieldEvidenceApp/Domain/Globalization/LocaleFormatContractsV1.swift",
          "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
          "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
          "FieldEvidenceApp/Infrastructure/Localization/LocaleFormattingServiceV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
          "FieldEvidenceAppTests/Fixtures/V30/LocaleFormatting/formatting-grammar-cases-v1.json",
          "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
          "FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift",
          "FieldEvidenceAppTests/V30_P01_C07LocaleFormattingTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "36f9c62ef09bff21c47923add3ade6469a82650e",
        "tree": "0f8e0553b2f3780c1f052648b16dfd9c5b8b03f8"
      },
      "sequence": 28
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
  "sourceEndLine": 998,
  "sourceStartLine": 998,
  "title": "Locale-aware search, sorting, and normalization"
}
```
