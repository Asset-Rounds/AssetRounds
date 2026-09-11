# V30 Current Task

Card 24 of 55 - Forms, required-state, validation, and conditional semantics

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Localize existing field labels, instructions, required/optional/error states, choice order, validation, units, numerals, and condition meaning without weakening or reordering canonical rules.",
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
    "head": "de11273e4944974d644b6f5533f6137be7af9374",
    "tree": "13e88b512a214a551648f8a3576dbf0597bfd790"
  },
  "cardID": "V30-P03-C03",
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
    "V30-P02-C04",
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
        "path": "FieldEvidenceApp/Domain/Globalization/LocalizedFormSemanticsContractsV1.swift",
        "purpose": "Localized form label/required/optional/error/condition contracts preserving canonical rules.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Globalization/LocalizedFormSemanticsCoordinatorV1.swift",
        "purpose": "Form semantic resolution coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C03LocalizedFormSemanticsTests.swift",
        "purpose": "Required-state, choice-order, unit, numeral, and conditional-rule tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/Forms/localized-form-semantics-cases-v1.json",
        "purpose": "Localized form semantic fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "efa0d8d30548c9dcbbf724e9b5057f2ce5a7dced",
        "expectedBSHA256": "416e124c574a982c4ae8ebea4760065a09f79b18ddb61d516231afca34784edc",
        "path": "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
        "purpose": "Version-forward existing required/optional/error semantics without changing canonical rules.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c7d11749e5e30978a538fad5480fec87a19b9fbb",
        "expectedBSHA256": "29a7de7e0efdf546ba87674f5730b62e07f8d5a6329fc93852fc675da0a613cd",
        "path": "FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift",
        "purpose": "Preserve canonical conditional form rules while allowing localized presentation.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Resolve field labels/instructions/errors through existing typed catalog keys.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f7a500dd414a35824117caa9dcd93c83909d1530",
        "expectedBSHA256": "f2290620946afbb1b60577db62203a5c99e3012b74943b5cbbe7c576c83a71e8",
        "path": "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
        "purpose": "Localize existing field labels/required/error presentation without changing capture semantics.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5e0b1d333ff0124259a863674c7cb308365a13b6",
        "expectedBSHA256": "0e3a4d543e588ae24a0ed06aaf05d50081341602cdf1fe04b9ddfd0bb945a955",
        "path": "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
        "purpose": "Localize existing required/preflight presentation without changing workflow semantics.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "d5bf77dd1d6ce8c7123653c2cd3070c65ca73123",
        "expectedBSHA256": "b98b9730a65b87baa64b36696d117eed02ff820deeebb14fbc03612ca1c69e24",
        "path": "FieldEvidenceApp/Domain/InspectionKernel/ResponseFieldDefinitionV1.swift",
        "purpose": "Preserve canonical response field definition semantics while adding localized presentation.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "608289c8c58b80bb5c2f2f985cdee0d7a65f7d15",
        "expectedBSHA256": "a133a918665a2e8eaaf0241ca9e021ae1ce63478f1bc95d91c52a1d26d3074ac",
        "path": "FieldEvidenceApp/Domain/InspectionKernel/ResponseValueV1.swift",
        "purpose": "Preserve canonical response values across localized labels/units/numerals.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c14e3bd81b7c53ee5aefcf18fd3325c6405772a5",
        "expectedBSHA256": "692266ae13a9e9731504c8e30d82ebc6fef1aae6a4629881ffebfa2ea9e177c2",
        "path": "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift",
        "purpose": "Preserve canonical grammar/condition semantics under localized presentation.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a47729b0606d13aa25fa22eee1790e89bf9b23bc",
        "expectedBSHA256": "28fadd2c0bac751b75e1932020ecc697b63ef84337067f56b20b220a0aa1e35c",
        "path": "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGraphValidatorV1.swift",
        "purpose": "Validate localized presentation cannot change canonical workflow graph rules.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "b2bb1d99bab55b12df661417b613d99570224502",
        "expectedBSHA256": "4d081d00c3c9b4dec0849594faf08a40ed86cf3d4966986f8c889e939ba87f59",
        "path": "FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift",
        "purpose": "Coordinate existing survey definitions with localized presentation.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6125862fe5b0ba0551b336fb05228b0766b1c618",
        "expectedBSHA256": "f27aad32f9645e242cfbe5592c7f15a0f65141e62d0b6df9adacc09955593501",
        "path": "FieldEvidenceApp/Application/Workflow/GuidedSurveyFlowCoordinatorV1.swift",
        "purpose": "Coordinate required/error/conditional display through existing guided-survey flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "378d620a586e14076f6f3f2ffa4bae7476b439a0",
        "expectedBSHA256": "b5a7892156cb4fae3b2ae47b98af78c353e63033bb5d6ad6dbdc4bb022462756",
        "path": "FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift",
        "purpose": "Preserve lifecycle/snapshot behavior while adding localizable form presentation.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "ab0cd81f65c9822d53505491697f91d0de9d15b1",
        "expectedBSHA256": "62b1fd6dfefae68ec6beed96e5f743b132adfddc74d7bafdbd350e1a01bf4eb9",
        "path": "FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift",
        "purpose": "Preserve packaged form rule execution while localizing labels/instructions.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "199911f3676695af27f475e62e2d9ea4fb05e34d",
        "expectedBSHA256": "bfa8424e5cd55367d34c80562567651e23107b7c01995604311fdb5578cebc7b",
        "path": "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
        "purpose": "Localize existing outcome/error presentation only; preserve Phase10 visual styling and workflow semantics.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0b107dd4303f35eb4a4947c506de315edb10e551",
        "expectedBSHA256": "ac2dd39c003959211c0f310b519f8de3bda1459d6c74c6380a2fed29e00c77e6",
        "path": "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift",
        "purpose": "Regression-test localized survey definition semantics.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5ee7b099132d21ec001cce0a6af77d28e9262d1c",
        "expectedBSHA256": "1bae0d73ac2af2534eaaf68d25124e6e03e53f1dc8e3d19f4bb99140a1f8908b",
        "path": "FieldEvidenceAppTests/V9_83GuidedSurveyFlowTests.swift",
        "purpose": "Regression-test guided-survey required/error/condition semantics.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7efcd069543e34ed5c97ce19b8a9597e24d79e69",
        "expectedBSHA256": "325c7a5978713ff234146b5ba747bc9b2c2ed89ac58d08ff75e1f6ed3a8f1c80",
        "path": "FieldEvidenceAppTests/V9_13TypedResponseTests.swift",
        "purpose": "Regression-test typed response values across locale presentation.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P03-C03",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C07",
      "V30-P02-C04",
      "V30-P03-C01"
    ],
    "ordinal": 24,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "localize only existing field label/required/error presentation in FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift; preserve Phase10 visual styling and canonical workflow semantics",
        "cardID": "V30-P03-C03",
        "expectedBBlobOID": "f7a500dd414a35824117caa9dcd93c83909d1530",
        "expectedBSHA256": "f2290620946afbb1b60577db62203a5c99e3012b74943b5cbbe7c576c83a71e8",
        "path": "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C03-FORM-SEMANTICS-INTEGRATOR"
      },
      {
        "boundedPurpose": "localize only existing field label/required/error presentation in FieldEvidenceApp/Features/CheckRunner/PreflightView.swift; preserve Phase10 visual styling and canonical workflow semantics",
        "cardID": "V30-P03-C03",
        "expectedBBlobOID": "5e0b1d333ff0124259a863674c7cb308365a13b6",
        "expectedBSHA256": "0e3a4d543e588ae24a0ed06aaf05d50081341602cdf1fe04b9ddfd0bb945a955",
        "path": "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C03-FORM-SEMANTICS-INTEGRATOR"
      },
      {
        "boundedPurpose": "localize only existing field label/required/error presentation in FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift; preserve Phase10 visual styling and canonical workflow semantics",
        "cardID": "V30-P03-C03",
        "expectedBBlobOID": "199911f3676695af27f475e62e2d9ea4fb05e34d",
        "expectedBSHA256": "bfa8424e5cd55367d34c80562567651e23107b7c01995604311fdb5578cebc7b",
        "path": "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C03-FORM-SEMANTICS-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
      "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
      "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Forms, required-state, validation, and conditional semantics"
  },
  "fenceSource": {
    "cardID": "V30-P03-C03",
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
  "next": "V30-P03-C04",
  "observedCoordination": {
    "head": "dd40d3793fdb903016ad8739425dca55f6d08ff1",
    "ledgerDigest": "85d0cef8c563002f8fba6ba8187dffa2dae116f2f3f9ca6a85360e827c607855",
    "sequence": 49
  },
  "ordinal": 24,
  "outcome": "Localize existing field labels, instructions, required/optional/error states, choice order, validation, units, numerals, and condition meaning without weakening or reordering canonical rules.",
  "payloadDigest": "ef20ebc4a2a9c06df5e4776679e548b32170780519c90673579a7e8809aa2612",
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
  "sourceEndLine": 1008,
  "sourceStartLine": 1008,
  "title": "Forms, required-state, validation, and conditional semantics"
}
```
