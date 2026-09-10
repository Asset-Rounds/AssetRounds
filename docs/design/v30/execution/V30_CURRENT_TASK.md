# V30 Current Task

Card 17 of 55 - RTL and bidirectional semantics

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Correct semantic mirroring, mixed identifiers/numbers, icon rules, navigation, lists, signatures, reports, focus order, invisible-control safety, and hostile Arabic/bidi fixtures without claiming Arabic shipping support.",
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
    "head": "69b57b7eae71dec8d3ab0ea2cb736fc1d828cfbe",
    "tree": "56016965f7f633eaf605460598e21910c1fc298b"
  },
  "cardID": "V30-P02-C03",
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
    "V30-P01-C06",
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
        "path": "FieldEvidenceApp/Infrastructure/Localization/BidirectionalTextSafetyV1.swift",
        "purpose": "Bidirectional rendering, isolation, and mixed-identifier safety policy.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Features/Globalization/GlobalizationRTLSemanticsV1.swift",
        "purpose": "Semantic mirroring/focus/navigation rendering helper.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P02_C03RTLSemanticsTests.swift",
        "purpose": "RTL layout, mixed direction, and invisible-control safety tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/RTL/rtl-hostile-cases-v1.json",
        "purpose": "Arabic/bidi hostile fixtures without Arabic-shipping claim.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "47dce913f9d74c67372fd74381193e30f6ed3ea8",
        "expectedBSHA256": "6dffb68fd94398664e9ca9a77a52ab8104be3763df03c061fc806438f93940c4",
        "path": "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
        "purpose": "Extend existing semantic accessibility contracts for RTL/bidi focus/order safety.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c8d7b6f4eebff67d288c26d3bf3b6a3449ceb27d",
        "expectedBSHA256": "e2bffbc3c9a6069c935d3e6b6c92db808435203a51f7dbe441d4013bcf7d4cad",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
        "purpose": "Remove ASCII-only/bidi-unsafe deterministic PDF behavior and preserve canonical report identity.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "d8dcc7fe5f5bca80bf21e964ad411aaac2baa837",
        "expectedBSHA256": "444d71a74c2b4336ffd4ab7e46850fcb7ee7afc7edaebb1bf311d0431e6d99b4",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
        "purpose": "Preserve bidi-safe JSON display variants without changing machine keys.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc88143bf623ba193458ef3eabcf6f56872df93f",
        "expectedBSHA256": "b47b36127800c20edba871c80f7b32614f674c8f99d22de1d3ddc3a2450efa05",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
        "purpose": "Apply bidi-safe document layout/rendering through the existing renderer.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "209f205aab77a68265f0601696a23a06f4d7ce4c",
        "expectedBSHA256": "60b2cd11ed0c07e7573906e4cc01e1e3bb4c5b496991eaa79c9874d343e6042d",
        "path": "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
        "purpose": "Apply only semantic RTL direction, focus, and touch ordering; preserve Phase10 visual tokens and brand composition.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "purpose": "Apply only semantic tab/navigation ordering for RTL; preserve Phase10 shell visual composition.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P02-C03",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C06",
      "V30-P02-C02"
    ],
    "ordinal": 17,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "apply only semantic RTL/bidi direction, focus, or touch ordering in FieldEvidenceApp/DesignSystem/WorklightComponents.swift; preserve Phase10 visual tokens and brand composition",
        "cardID": "V30-P02-C03",
        "expectedBBlobOID": "209f205aab77a68265f0601696a23a06f4d7ce4c",
        "expectedBSHA256": "60b2cd11ed0c07e7573906e4cc01e1e3bb4c5b496991eaa79c9874d343e6042d",
        "path": "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C03-RTL-SEMANTICS-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only semantic RTL/bidi direction, focus, or touch ordering in FieldEvidenceApp/Features/Shell/AppShellView.swift; preserve Phase10 visual tokens and brand composition",
        "cardID": "V30-P02-C03",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C03-RTL-SEMANTICS-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
      "FieldEvidenceApp/Features/Shell/AppShellView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "RTL and bidirectional semantics"
  },
  "fenceSource": {
    "cardID": "V30-P02-C03",
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
  "next": "V30-P02-C04",
  "observedCoordination": {
    "head": "facd85e69c7756ba71be0bf57e426a29c7c1450c",
    "ledgerDigest": "926e27c1c8503871c821dce5dcdff1cbdbe7305ef6169fd5b4cf01abc10d96ff",
    "sequence": 35
  },
  "ordinal": 17,
  "outcome": "Correct semantic mirroring, mixed identifiers/numbers, icon rules, navigation, lists, signatures, reports, focus order, invisible-control safety, and hostile Arabic/bidi fixtures without claiming Arabic shipping support.",
  "payloadDigest": "0a7f35020a6448fb374f76e349304a11f5e6038999d2cefcc69653c18c755213",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
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
  "sourceEndLine": 996,
  "sourceStartLine": 996,
  "title": "RTL and bidirectional semantics"
}
```
