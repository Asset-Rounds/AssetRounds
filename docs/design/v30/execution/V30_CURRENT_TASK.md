# V30 Current Task

Card 25 of 55 - Unicode PDF and accessible-document renderer

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Remove question-mark substitution, qualify and embed fonts, shape CJK/RTL, support Letter/A4, preserve photo/comment/status association, extraction, semantic order, provenance, and historical deterministic replay.",
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
    "head": "45eb5bb4dca6b32f3434d57ccada1059bf8fb0e6",
    "tree": "2bd1a2364e17c9185812e43439c95870eb21e29e"
  },
  "cardID": "V30-P03-C04",
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
        "path": "FieldEvidenceApp/Domain/Reporting/GlobalizedAccessibleDocumentContractsV1.swift",
        "purpose": "Unicode/PDF/document language/font/paper/provenance contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Reporting/GlobalizedAccessibleDocumentRendererV1.swift",
        "purpose": "Unicode shaping, font, Letter/A4, semantic-order, and replay renderer.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C04GlobalizedAccessibleDocumentTests.swift",
        "purpose": "CJK/RTL extraction, font, paper, association, and replay tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/Reports/globalized-accessible-document-cases-v1.json",
        "purpose": "Report rendering/extraction fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "19f52a71cb2ded5ac20912bb8634263e7ace1ed6",
        "expectedBSHA256": "a0065b15ef7059867bb00377bd5b97cbcd2e9ac98c74ea0e154297410773f8bb",
        "path": "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
        "purpose": "Version-forward existing accessible-document contracts for Unicode/font/paper/provenance.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc88143bf623ba193458ef3eabcf6f56872df93f",
        "expectedBSHA256": "b47b36127800c20edba871c80f7b32614f674c8f99d22de1d3ddc3a2450efa05",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
        "purpose": "Implement Unicode shaping/font embedding and Letter/A4 behavior in the actual PDF renderer.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c8d7b6f4eebff67d288c26d3bf3b6a3449ceb27d",
        "expectedBSHA256": "e2bffbc3c9a6069c935d3e6b6c92db808435203a51f7dbe441d4013bcf7d4cad",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
        "purpose": "Remove existing ASCII question-mark substitution in the deterministic PDF path.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0a1849d7f3957676e55a017661a73c3d5a1c81f5",
        "expectedBSHA256": "f9c9b25e7b682586a22591fe2c3905055262a139a1c1506f5bcab0d0def82f75",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
        "purpose": "Use globalized renderer through the existing report render seam.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "9294d71d5ed0168e4b6c7b3be2e0cad7154c21bf",
        "expectedBSHA256": "d0f78088ec989738be1d752d8668f28cfd191d7b6503ffba85ca523deb2b46f7",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/AccessibleDocumentLifecycleAdapterV1.swift",
        "purpose": "Preserve existing document lifecycle/provenance on globalized output.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7ba2628cc8e12c56597dce13dfa0fc9de78c1e27",
        "expectedBSHA256": "43f18e8713db41db6d1555b5b0a024cd82463e2ee06afffd14109bd2b2a20785",
        "path": "FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift",
        "purpose": "Extend accessible document renderer regression coverage.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "783f2db48da3032b9ce3217bfaf45900ae1e4cc4",
        "expectedBSHA256": "376a46bed52cccd33fe686f09f60f8f2948afb297f2dbc42305e0fa6e4a475fd",
        "path": "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
        "purpose": "Preserve canonical projection identity while adding Unicode/display provenance.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5ce1e8b1e1de3137b596b314eb6902ffbeafff33",
        "expectedBSHA256": "77b43f39aff3189791f9c33b7b5c02456fa9a3357e85b58758a32f19ae4f2cf9",
        "path": "FieldEvidenceApp/Application/Reporting/AccessibleDocumentCoordinatorV1.swift",
        "purpose": "Route globalized documents through the existing accessible-document coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fe2466b4df4800d217767dd392c885b08cfb0f51",
        "expectedBSHA256": "1f8e0cc7a9eaa8ddddfff5383ae6b0ecc94bbc4c73252f9466889c6ffe466b5d",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
        "purpose": "Preserve historical deterministic replay and provenance through the existing history seam.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a491e4dbd6152574f518f25fbac5f9847eba953b",
        "expectedBSHA256": "e79601a65510f115a2aaf0e6c537532d96ec277ddac08fff939880c62f9cd35e",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
        "purpose": "Validate Unicode/globalized render inputs before output generation.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "ea98ec9c1c6c5ff43df541e687df886a772b2f01",
        "expectedBSHA256": "a7cbc5e4090a05d465d2c93d47ac17ab0dd8548a43c1d12b6f6ab95fcb90c5aa",
        "path": "FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift",
        "purpose": "Regression-test deterministic renderer identity after Unicode support.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "862a87c6d5fb3370c535c1a55a8ca077a6d94691",
        "expectedBSHA256": "29bf9d1baf9377b8f88440a5fdb65cb38aeed765b3d8d5f2b3c1980da15736b5",
        "path": "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
        "purpose": "Regression-test Unicode PDF recovery.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P03-C04",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C07",
      "V30-P02-C04",
      "V30-P03-C01"
    ],
    "ordinal": 25,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Unicode PDF and accessible-document renderer"
  },
  "fenceSource": {
    "cardID": "V30-P03-C04",
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
  "next": "V30-P03-C05",
  "observedCoordination": {
    "head": "3a7901ab7c280e23cbc5e914e621ddd03e6a0a28",
    "ledgerDigest": "f4598503b1db9dbd0bcf81fe87220949c4194bf7d85fa6d57d34cc3b09bf31a9",
    "sequence": 51
  },
  "ordinal": 25,
  "outcome": "Remove question-mark substitution, qualify and embed fonts, shape CJK/RTL, support Letter/A4, preserve photo/comment/status association, extraction, semantic order, provenance, and historical deterministic replay.",
  "payloadDigest": "31ed1000be591ddfc1ea6dbeb55cd16ea3eebf0c2c7fa4be55119a4eea1e8850",
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
  "sourceEndLine": 1009,
  "sourceStartLine": 1009,
  "title": "Unicode PDF and accessible-document renderer"
}
```
