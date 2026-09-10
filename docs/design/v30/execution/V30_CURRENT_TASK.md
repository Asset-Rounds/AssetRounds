# V30 Current Task

Card 18 of 55 - Expansion, Dynamic Type, accessibility, and font policy

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Prevent clipping/unreachable controls, localize accessibility, qualify font fallback/licensing, preserve touch targets/contrast/focus/errors, and pass long-text and accessibility sizes.",
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
    "head": "0a7a4d9d82683a4b2aab06508623fc0a1f910586",
    "tree": "551a18514c114181227dcaf8010c0f1f55f1217a"
  },
  "cardID": "V30-P02-C04",
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
    "V30-P02-C01",
    "V30-P02-C03"
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
        "path": "FieldEvidenceApp/DesignSystem/GlobalizationAdaptiveLayoutPolicyV1.swift",
        "purpose": "Expansion, Dynamic Type, font fallback, touch-target, contrast, and focus policy.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Features/Globalization/GlobalizationAccessibilityPolicyV1.swift",
        "purpose": "Localized accessibility and long-text surface policy.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P02_C04AdaptiveAccessibilityTests.swift",
        "purpose": "Dynamic Type, expansion, VoiceOver, and font-policy tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/Accessibility/expansion-and-type-cases-v1.json",
        "purpose": "Long-text and accessibility-size fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "47dce913f9d74c67372fd74381193e30f6ed3ea8",
        "expectedBSHA256": "6dffb68fd94398664e9ca9a77a52ab8104be3763df03c061fc806438f93940c4",
        "path": "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
        "purpose": "Extend existing accessibility contract for Dynamic Type, localized labels, focus, and reachability.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "209f205aab77a68265f0601696a23a06f4d7ce4c",
        "expectedBSHA256": "60b2cd11ed0c07e7573906e4cc01e1e3bb4c5b496991eaa79c9874d343e6042d",
        "path": "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
        "purpose": "Apply only Dynamic Type, long-text, touch-target, and accessibility reachability behavior; preserve Phase10 visual tokens and branding.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "purpose": "Apply only Dynamic Type/long-text navigation reachability; preserve Phase10 shell visual composition.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0fcac3c65ac2581c5912936215cd5c2a3b7ff1ed",
        "expectedBSHA256": "700ad042adb3f6cf69eb18e41e078ad0a59e049680bd42e71cd62ca14c7432a0",
        "path": "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
        "purpose": "Apply only Dynamic Type/long-text and accessibility reachability to the backup recovery surface.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "535a86a3312f537f13c10b5db3f7bed3ac0f3945",
        "expectedBSHA256": "fefb968c6900e8cf9abd054e09e424cac7510c56e82642657efda45fa81ff559",
        "path": "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
        "purpose": "Apply only Dynamic Type/long-text and accessibility reachability to the backup validation surface.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f7a500dd414a35824117caa9dcd93c83909d1530",
        "expectedBSHA256": "f2290620946afbb1b60577db62203a5c99e3012b74943b5cbbe7c576c83a71e8",
        "path": "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
        "purpose": "Apply only Dynamic Type/long-text and accessibility reachability to capture controls.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "199911f3676695af27f475e62e2d9ea4fb05e34d",
        "expectedBSHA256": "bfa8424e5cd55367d34c80562567651e23107b7c01995604311fdb5578cebc7b",
        "path": "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
        "purpose": "Apply only Dynamic Type/long-text and accessibility reachability to outcome controls.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5e0b1d333ff0124259a863674c7cb308365a13b6",
        "expectedBSHA256": "0e3a4d543e588ae24a0ed06aaf05d50081341602cdf1fe04b9ddfd0bb945a955",
        "path": "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
        "purpose": "Apply only Dynamic Type/long-text and accessibility reachability to preflight controls.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0797274e09f174e1caca359c3ce6b030c41054e6",
        "expectedBSHA256": "57ffc1c79e02a1adad526837339c21baba35f4a41bd340ab547f64eebcc51fd8",
        "path": "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
        "purpose": "Apply only Dynamic Type/long-text and accessibility reachability to receipt controls.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1798cf7b2fd27e4005c2877083108b8362cd450f",
        "expectedBSHA256": "fd97a87be8b5e83f9458f2d8e517c79c552876f9adf5eed3e8472a876edc7af5",
        "path": "FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift",
        "purpose": "Apply Dynamic Type/long-text recovery accessibility behavior.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "e594bc96cd26e94f4732de20bde119895f30c02e",
        "expectedBSHA256": "15b47b3bd21e0eb4d797bdc33867c44ffe441b433a6ac5ec1bf1725e4c9e0c8c",
        "path": "FieldEvidenceApp/Features/Rounds/RoundSessionView.swift",
        "purpose": "Apply Dynamic Type/long-text round-session accessibility behavior.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1134417b3f24bf056cef13cdb133ea61d34c43fc",
        "expectedBSHA256": "7b1c9163359202e97558078c3a782a03faa543ce7c14198ab1893e2fd65da5df",
        "path": "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
        "purpose": "Extend localization/accessibility Dynamic Type regression coverage.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0c9a8a7625da998a7fc2d52fab0de080aa6e74ac",
        "expectedBSHA256": "fdd82805952e37a313c5f156aed6d53c48511a9e038fdeb8a7272ba611eb2694",
        "path": "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift",
        "purpose": "Extend established accessibility golden coverage.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P02-C04",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P02-C01",
      "V30-P02-C03"
    ],
    "ordinal": 18,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/DesignSystem/WorklightComponents.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "209f205aab77a68265f0601696a23a06f4d7ce4c",
        "expectedBSHA256": "60b2cd11ed0c07e7573906e4cc01e1e3bb4c5b496991eaa79c9874d343e6042d",
        "path": "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/Features/Shell/AppShellView.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "0fcac3c65ac2581c5912936215cd5c2a3b7ff1ed",
        "expectedBSHA256": "700ad042adb3f6cf69eb18e41e078ad0a59e049680bd42e71cd62ca14c7432a0",
        "path": "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "535a86a3312f537f13c10b5db3f7bed3ac0f3945",
        "expectedBSHA256": "fefb968c6900e8cf9abd054e09e424cac7510c56e82642657efda45fa81ff559",
        "path": "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "f7a500dd414a35824117caa9dcd93c83909d1530",
        "expectedBSHA256": "f2290620946afbb1b60577db62203a5c99e3012b74943b5cbbe7c576c83a71e8",
        "path": "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "199911f3676695af27f475e62e2d9ea4fb05e34d",
        "expectedBSHA256": "bfa8424e5cd55367d34c80562567651e23107b7c01995604311fdb5578cebc7b",
        "path": "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/Features/CheckRunner/PreflightView.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "5e0b1d333ff0124259a863674c7cb308365a13b6",
        "expectedBSHA256": "0e3a4d543e588ae24a0ed06aaf05d50081341602cdf1fe04b9ddfd0bb945a955",
        "path": "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      },
      {
        "boundedPurpose": "apply only Dynamic Type, long-text, touch-target, and accessibility reachability in FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift; preserve Phase10 visual tokens and branding",
        "cardID": "V30-P02-C04",
        "expectedBBlobOID": "0797274e09f174e1caca359c3ce6b030c41054e6",
        "expectedBSHA256": "57ffc1c79e02a1adad526837339c21baba35f4a41bd340ab547f64eebcc51fd8",
        "path": "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
      "FieldEvidenceApp/Features/Shell/AppShellView.swift",
      "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
      "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
      "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
      "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
      "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
      "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Expansion, Dynamic Type, accessibility, and font policy"
  },
  "fenceSource": {
    "cardID": "V30-P02-C04",
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
  "next": "V30-P02-C05",
  "observedCoordination": {
    "head": "40ca4c7bab5ef834682a912afe5190fa8e2bb672",
    "ledgerDigest": "e18024c48f80ebdaccc3be616c8887e5d58fd9f08cf905e25ac8ae78c513a0be",
    "sequence": 37
  },
  "ordinal": 18,
  "outcome": "Prevent clipping/unreachable controls, localize accessibility, qualify font fallback/licensing, preserve touch targets/contrast/focus/errors, and pass long-text and accessibility sizes.",
  "payloadDigest": "531313283e8a43eab0cc90edb73cda7973f20c10f4fb9eaf9c50ee04bd4120c7",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P02-C01": {
      "candidate": {
        "base": "020c9da6df9c2d9afe741290ecab1b1893d8b2ec",
        "baseTree": "a7b68fe27452c186cdd9e8c6a244a39c29b5c1ff",
        "changedPaths": [
          "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
          "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
          "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
          "FieldEvidenceApp/Features/Accountability/SignoffEnrollmentView.swift",
          "FieldEvidenceApp/Features/Activities/InstallationWorkflowView.swift",
          "FieldEvidenceApp/Features/Activities/PunchReviewWorkflowView.swift",
          "FieldEvidenceApp/Features/AssetImport/PartyContactSiteRoleImportView.swift",
          "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
          "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
          "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
          "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
          "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
          "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
          "FieldEvidenceApp/Features/Contacts/OperationalContactHandoffView.swift",
          "FieldEvidenceApp/Features/Contacts/PartyContactSiteRoleWorkflowView.swift",
          "FieldEvidenceApp/Features/Integrations/IncumbentFileAdapterWorkflowView.swift",
          "FieldEvidenceApp/Features/Issues/IssueDetailView.swift",
          "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
          "FieldEvidenceApp/Features/MyDay/MyDayWorkflowView.swift",
          "FieldEvidenceApp/Features/PartsStock/PartsStockWorkflowView.swift",
          "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
          "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
          "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
          "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
          "FieldEvidenceApp/Features/ReviewExchange/RecipientReviewWorkflowView.swift",
          "FieldEvidenceApp/Features/Scheduling/AdvancedRecurrenceWorkflowView.swift",
          "FieldEvidenceApp/Features/ServiceRequests/ServiceRequestWorkflowView.swift",
          "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
          "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
          "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
          "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
          "FieldEvidenceApp/Features/Settings/RatingSupportWorkflowView.swift",
          "FieldEvidenceApp/Features/Shell/AppShellView.swift",
          "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
          "FieldEvidenceApp/Features/Signs/NewSignView.swift",
          "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
          "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
          "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
          "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
          "FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift",
          "FieldEvidenceApp/Features/WorkResources/ManualWorkResourceWorkflowView.swift",
          "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
          "FieldEvidenceApp/Infrastructure/Localization/V30EnglishCatalogRegistryV1.swift",
          "FieldEvidenceApp/Resources/Localizable.xcstrings",
          "FieldEvidenceAppTests/Fixtures/V30/EnglishCatalog/english-catalog-audit-v1.json",
          "FieldEvidenceAppTests/V30_P02_C01EnglishCatalogNormalizationTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "86eabf98abee15c8bd14ff5bfb61a149ab09f103",
        "tree": "ab8211eed89a7980d4f38246026800b72226afe3"
      },
      "sequence": 33
    },
    "V30-P02-C03": {
      "candidate": {
        "base": "69b57b7eae71dec8d3ab0ea2cb736fc1d828cfbe",
        "baseTree": "56016965f7f633eaf605460598e21910c1fc298b",
        "changedPaths": [
          "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
          "FieldEvidenceApp/Features/Globalization/GlobalizationRTLSemanticsV1.swift",
          "FieldEvidenceApp/Features/Shell/AppShellView.swift",
          "FieldEvidenceApp/Infrastructure/Localization/BidirectionalTextSafetyV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/RTL/rtl-hostile-cases-v1.json",
          "FieldEvidenceAppTests/V30_P02_C03RTLSemanticsTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "0a7a4d9d82683a4b2aab06508623fc0a1f910586",
        "tree": "551a18514c114181227dcaf8010c0f1f55f1217a"
      },
      "sequence": 37
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 997,
  "sourceStartLine": 997,
  "title": "Expansion, Dynamic Type, accessibility, and font policy"
}
```
