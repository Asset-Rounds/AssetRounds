# V30 Current Task

Card 21 of 55 - Language & Region Settings and report-language controls

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Add localized effective app-language/region display, iOS Settings handoff, truthful unsupported-language fallback, independent report-language selection, and clear language-versus-jurisdiction explanation.",
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
    "head": "ccf39e0e3eaa74bbc5ad4ee64372f10101f38b4a",
    "tree": "69048994543c2634af1d61287b12b18d4c80054c"
  },
  "cardID": "V30-P02-C07",
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
    "V30-P01-C07",
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
        "path": "FieldEvidenceApp/Features/Settings/GlobalizationSettingsViewV1.swift",
        "purpose": "Localized effective-language/region and report-language settings view.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Domain/Reporting/ReportLanguageContractsV1.swift",
        "purpose": "Independent report-language selection contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Reporting/ReportLanguageCoordinatorV1.swift",
        "purpose": "Report-language and jurisdiction disclosure coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P02_C07LanguageRegionSettingsTests.swift",
        "purpose": "Language, region, report-language, and jurisdiction-separation tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f28f90aa7b8b19519412ed879788166d01309008",
        "expectedBSHA256": "8e9814f0a5164b72aea2ba7f7b710e2bd4b20f1b14a3f6ee9306047218a2505d",
        "path": "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
        "purpose": "Add typed language/region/report-language preference semantics to existing settings contracts.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "cbcdfe1281de6e98af13f1b12a0e32a6c7b9967b",
        "expectedBSHA256": "b7ae0570ef54ba29ddb7c308b3f5236e03045297abddc18c3be99ad0b77d0e12",
        "path": "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
        "purpose": "Persist allowed device-local language/report preferences through the existing adapter.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "b311e66b05b19078c9823b59c91c1f9c81964d49",
        "expectedBSHA256": "ddb2bb5579ec9c091f268f09a3552b00318165e44e31f87940931acb8029e2f6",
        "path": "FieldEvidenceApp/Application/Ports/SettingsCapabilityPortsV1.swift",
        "purpose": "Expose typed language/region settings capability through the established port.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8cd93ce082652e054201409787ba27fb82c63013",
        "expectedBSHA256": "5d1982421bea62d1ec5339f5a279b6f1f552afa8d90f7dc16f01e389b575dc4f",
        "path": "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
        "purpose": "Bind Settings effective language to existing catalog/fallback contracts.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Resolve effective language and localized settings labels through the existing catalog.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "19f52a71cb2ded5ac20912bb8634263e7ace1ed6",
        "expectedBSHA256": "a0065b15ef7059867bb00377bd5b97cbcd2e9ac98c74ea0e154297410773f8bb",
        "path": "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
        "purpose": "Add independent report-language selection to existing document contracts.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0a1849d7f3957676e55a017661a73c3d5a1c81f5",
        "expectedBSHA256": "f9c9b25e7b682586a22591fe2c3905055262a139a1c1506f5bcab0d0def82f75",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
        "purpose": "Select explicit report language/formatting at the existing render seam.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "28e7f335a3337fb6e353a94181e67daab40b0a50",
        "expectedBSHA256": "b4b2627fe05210957e51e54a48841b0cd3b385bf1ba6a384e94e3f6b9a75ecf7",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
        "purpose": "Preserve explicit report language through existing delivery behavior.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "purpose": "Wire only the Globalization Settings route; preserve Phase10 shell navigation/brand composition.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P02-C07",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C06",
      "V30-P01-C07",
      "V30-P02-C04"
    ],
    "ordinal": 21,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "wire only the V30 Globalization Settings route; preserve Phase10 shell navigation and brand composition",
        "cardID": "V30-P02-C07",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C07-SETTINGS-SURFACE-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/Features/Shell/AppShellView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Language & Region Settings and report-language controls"
  },
  "fenceSource": {
    "cardID": "V30-P02-C07",
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
  "next": "V30-P03-C01",
  "observedCoordination": {
    "head": "2f3deb6d919422af0bcc72e46223d3027c8dc208",
    "ledgerDigest": "c21bc029fcca5d6222ed46a493ef85a25fee454732c6d8db143c15e0edf306a5",
    "sequence": 43
  },
  "ordinal": 21,
  "outcome": "Add localized effective app-language/region display, iOS Settings handoff, truthful unsupported-language fallback, independent report-language selection, and clear language-versus-jurisdiction explanation.",
  "payloadDigest": "e68cdde0d994725ea91ef0b8188548fd9be7ade49cb0ddc4630a17eeb72b097e",
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
  "sourceEndLine": 1000,
  "sourceStartLine": 1000,
  "title": "Language & Region Settings and report-language controls"
}
```
