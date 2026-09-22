# V30 Current Task

Card 27 of 55 - Share, email, print, and label surfaces

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation. Three exact shared UI paths are S10_SHARED_RECONCILIATION_REQUIRED under the recorded tuples.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Localize app-owned chrome, subject/body templates, print controls, labels, and share summaries while preserving authored content and explicit document language.",
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
    "head": "3f902a774e978c8c5c5c953f1e59298c7f9da29b",
    "tree": "068d703866f816bd065962c79991f960ac1091e1"
  },
  "cardID": "V30-P03-C06",
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
    "V30-P02-C04",
    "V30-P03-C04"
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
        "path": "FieldEvidenceApp/Features/Globalization/GlobalizedSharePrintLabelSurfacesV1.swift",
        "purpose": "Share/email/print/label chrome and explicit document-language surfaces.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Reporting/GlobalizedShareDeliveryCoordinatorV1.swift",
        "purpose": "Localized subject/body/summary delivery coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C06SharePrintLabelTests.swift",
        "purpose": "Share, email, print, label, and authored-content preservation tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/Share/globalized-share-print-label-cases-v1.json",
        "purpose": "Share/print/label fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "445b88c91a7d901f2c978440a11c2278a44ebccf",
        "expectedBSHA256": "87e230a01acd36b88a6f138826f1052ab1d0327ce90bd3c01d66f95f4ad9670c",
        "path": "FieldEvidenceApp/Application/Reporting/ShopReportProfileCoordinatorV1.swift",
        "purpose": "Select localized share/email/print chrome without changing report content identity.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "28e7f335a3337fb6e353a94181e67daab40b0a50",
        "expectedBSHA256": "b4b2627fe05210957e51e54a48841b0cd3b385bf1ba6a384e94e3f6b9a75ecf7",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
        "purpose": "Deliver explicit document language and localized subject/body templates through existing delivery code.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "2b96a63848c5b77eef63055baf58ed12ba60cca4",
        "expectedBSHA256": "243ffe889a67d5ddb032325d35854f3bd4a1fb84ebb23fa3c7069836e53da2ac",
        "path": "FieldEvidenceApp/Features/Reporting/ShopProfileOpenEvidenceHandoffView.swift",
        "purpose": "Localize existing open-evidence handoff/share presentation.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "86c9dffb92cdee4a97fe346770053dc4cba12dbb",
        "expectedBSHA256": "5eb0d7928d4a757e65a0355657fb8b1f0f8d0eefe5c294bb575fb6a02289d1a2",
        "path": "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift",
        "purpose": "Localize app-owned mail chrome while preserving authored content.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "82bd8b590e238f8f5c5f119dd91b20dbd57893ea",
        "expectedBSHA256": "64e594839fbc4d3dfb2974539449c4644fe07cda52a1c30a06078ac8f427398a",
        "path": "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
        "purpose": "Localize feedback/share action chrome without changing Phase10 settings styling.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "b68419345153053c5e63dfb8edd585f38cbcd6d8",
        "expectedBSHA256": "ed062fa1c2ab895c483799ad66fbc7e5f7ff7b2e0420092af7ea68cc0c5e32f9",
        "path": "FieldEvidenceApp/Domain/Labels/AssetLabelContractsV1.swift",
        "purpose": "Add explicit document-language/chrome semantics through the existing asset-label contract.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "50b87e2a2fdbcc4b1c35b339751d6e3a645bfa6a",
        "expectedBSHA256": "f9964963a642838adf677240c70dd272b1730d70238572aade876d5fa5e55d24",
        "path": "FieldEvidenceApp/Application/Labels/AssetLabelCoordinatorV1.swift",
        "purpose": "Route localized label generation through the existing label coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "43612cd6cbe36ba197220e03d1b0a00721b5f1e1",
        "expectedBSHA256": "354f10a16f9173e583d361f27bd2341a5ab26e2c6ab4247109859fe837025818",
        "path": "FieldEvidenceApp/Infrastructure/Reporting/AssetLabelLifecycleAdapterV1.swift",
        "purpose": "Preserve label lifecycle/provenance with localized app-owned chrome.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "2f35aa6105f83fa7e390622a6dc89c12087aec6e",
        "expectedBSHA256": "aafee8825fc36969967009bf10a2dce241474b4e525f40352ed6bcf9fb549aa9",
        "path": "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift",
        "purpose": "Compose existing delivery/mail/label localization seams without a parallel sending flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c02680e9870fa348f1b8237f03f66496ff393418",
        "expectedBSHA256": "22387f27d46acfbf2e021b89e3f2bc2caf63fcdc95f8dc5cb6d2259d73ff3716",
        "path": "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
        "purpose": "Localize only existing report share/print chrome in the detail surface; preserve Phase10 styling.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "295917ff019fa349871946b8dcdeaa4727eb807d",
        "expectedBSHA256": "73161df4862a170d8232b61e922d7cb60d577e95d7e6727406ff754d83a80350",
        "path": "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
        "purpose": "Localize only existing report share/print chrome in the root surface; preserve Phase10 styling.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "86a55cf4145939361ebdf82af7b16f052ecdb1c4",
        "expectedBSHA256": "74e2ac75ce267ccc455d15c1780f7e0dfb6c8ff8c19433179719a29b2dd2c00e",
        "path": "FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift",
        "purpose": "Regression-test report delivery with explicit document language.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "100b60c05ee9858cbd1ec3d231d25364349d6828",
        "expectedBSHA256": "973fd0ace49699d6fa8dfadbe0a94804b023c08c298b09ed20abe57602b937b3",
        "path": "FieldEvidenceAppTests/V9_93AssetLabelOutputTests.swift",
        "purpose": "Regression-test localized label output and provenance.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6b12a81b0a65e56baa9fab53bcaa614e9b8ac012",
        "expectedBSHA256": "314fe6f1387c418a90387f24a9576b2fa1482a8da80e6c19dbd4aa8c01e1a70f",
        "path": "FieldEvidenceAppTests/V9_52AssetLabelTests.swift",
        "purpose": "Regression-test asset-label lifecycle semantics.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P03-C06",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P02-C04",
      "V30-P03-C04"
    ],
    "ordinal": 27,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "localize only feedback/share action chrome in FeedbackView; preserve Phase10 settings styling and user-authored content",
        "cardID": "V30-P03-C06",
        "expectedBBlobOID": "82bd8b590e238f8f5c5f119dd91b20dbd57893ea",
        "expectedBSHA256": "64e594839fbc4d3dfb2974539449c4644fe07cda52a1c30a06078ac8f427398a",
        "path": "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C06-SHARE-SURFACE-INTEGRATOR"
      },
      {
        "boundedPurpose": "localize only existing report share/print chrome in FieldEvidenceApp/Features/Reports/ReportDetailView.swift; preserve Phase10 styling and report content identity",
        "cardID": "V30-P03-C06",
        "expectedBBlobOID": "c02680e9870fa348f1b8237f03f66496ff393418",
        "expectedBSHA256": "22387f27d46acfbf2e021b89e3f2bc2caf63fcdc95f8dc5cb6d2259d73ff3716",
        "path": "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C06-SHARE-SURFACE-INTEGRATOR"
      },
      {
        "boundedPurpose": "localize only existing report share/print chrome in FieldEvidenceApp/Features/Reports/ReportsRootView.swift; preserve Phase10 styling and report content identity",
        "cardID": "V30-P03-C06",
        "expectedBBlobOID": "295917ff019fa349871946b8dcdeaa4727eb807d",
        "expectedBSHA256": "73161df4862a170d8232b61e922d7cb60d577e95d7e6727406ff754d83a80350",
        "path": "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P03-C06-SHARE-SURFACE-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
      "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
      "FieldEvidenceApp/Features/Reports/ReportsRootView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Share, email, print, and label surfaces"
  },
  "fenceSource": {
    "cardID": "V30-P03-C06",
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
  "next": "V30-P03-C07",
  "observedCoordination": {
    "head": "7ea49a6feb8cdf5d75950cf0b0c8d5619fd43df3",
    "ledgerDigest": "0e2f3ed322b46b17ab34c5ce35e12d40439f045ac47fef00b21de7f51f2d3b34",
    "sequence": 55
  },
  "ordinal": 27,
  "outcome": "Localize app-owned chrome, subject/body templates, print controls, labels, and share summaries while preserving authored content and explicit document language.",
  "payloadDigest": "59290b451a58fd67aaaf3100915b58f3bbeaea13cc8cfa714c55018084b72ef7",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
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
    "V30-P03-C04": {
      "candidate": {
        "base": "45eb5bb4dca6b32f3434d57ccada1059bf8fb0e6",
        "baseTree": "2bd1a2364e17c9185812e43439c95870eb21e29e",
        "changedPaths": [
          "FieldEvidenceApp/Application/Reporting/AccessibleDocumentCoordinatorV1.swift",
          "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
          "FieldEvidenceApp/Domain/Reporting/GlobalizedAccessibleDocumentContractsV1.swift",
          "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/AccessibleDocumentLifecycleAdapterV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/GlobalizedAccessibleDocumentRendererV1.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
          "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/Reports/globalized-accessible-document-cases-v1.json",
          "FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift",
          "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
          "FieldEvidenceAppTests/V30_P03_C04GlobalizedAccessibleDocumentTests.swift",
          "FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "77b1538aad3ff7229b7f3edcca4045dda7b3e711",
        "tree": "5d967a47111b63f0d3db3f91793abde0bc08b486"
      },
      "sequence": 53
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 1011,
  "sourceStartLine": 1011,
  "title": "Share, email, print, and label surfaces"
}
```
