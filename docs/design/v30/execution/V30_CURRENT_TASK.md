# V30 Current Task

Card 28 of 55 - OCR, dictation, speech, and assisted-input capability truth

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation. No S10 shared paths are authorized for this card.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Freeze per-locale capability and online/offline truth. A translated label never implies recognition, dictation, speech, or grammar support unavailable to the exact OS/device/build.",
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
    "head": "4fa30b15d50e5bdd6a090c426ec9fd2d5628f864",
    "tree": "cc1def7d18773709375388ba7bfea281361370c2"
  },
  "cardID": "V30-P03-C07",
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
        "path": "FieldEvidenceApp/Domain/Globalization/AssistedInputCapabilityContractsV1.swift",
        "purpose": "Per-locale OS/device/build capability truth contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Globalization/AssistedInputCapabilityCoordinatorV1.swift",
        "purpose": "Truthful OCR/dictation/speech capability resolver.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P03_C07AssistedInputCapabilityTests.swift",
        "purpose": "Unavailable capability and translated-label truth tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/AssistedInput/assisted-input-capability-cases-v1.json",
        "purpose": "Per-locale capability matrix fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "e9bd0a023512ea2a7757506c3f257741eba4115d",
        "expectedBSHA256": "6ca1daa0afe5f1e717e9ba6595882c97ca38174e5bb1c549776e6949dc42f1db",
        "path": "FieldEvidenceApp/Application/Assistance/OCRProposalCoordinatorV1.swift",
        "purpose": "Expose per-locale OCR truth through the existing assistance capability seam.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "723d18181853e872e86e63ce39836b8951422cdc",
        "expectedBSHA256": "650bdd12dfb843a978fbde360faae2a8905b9801869d887efe1efc9546bbe7f4",
        "path": "FieldEvidenceApp/Domain/VoiceStructuring/VoiceStructuringContractsV1.swift",
        "purpose": "Represent exact OS/device/build speech/dictation capability without implying support.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c0ba876826f7041174b64ac8436980f149a85bf2",
        "expectedBSHA256": "372f7e93a319db04be167f890ed8347261549cb061642b7a63e37dc23d83da18",
        "path": "FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift",
        "purpose": "Render truthful assisted-input capability state in the existing voice surface.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "cd491b6b9af2f7ca7adbfdf41346312f44bcc3d5",
        "expectedBSHA256": "11bf44c2d34d8051bd4c79ad9643b8cc24abad209a24131412185b0cc9bce6e1",
        "path": "FieldEvidenceApp/Domain/Assistance/OCRProposalContractsV1.swift",
        "purpose": "Expose locale capability truth through the existing OCR proposal contract.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "3b93d1b3e7c7dfd09e81ebd99431739562bd1346",
        "expectedBSHA256": "070fc442bbf4d53d18500e6b430b6d0c738d08ec00b81231ee26a8be0b360b3f",
        "path": "FieldEvidenceApp/Infrastructure/Assistance/OCRProposalLifecycleAdapterV1.swift",
        "purpose": "Route truthful OCR capability through the existing lifecycle adapter.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a753e7ef045c44daa414c24f823074a9c8af8a91",
        "expectedBSHA256": "3cc0904a9bb6f9e28f0b5910754ed442a1bf59f50381b52096584d2d21f02926",
        "path": "FieldEvidenceApp/Domain/Assistance/DictationLocationProposalContractsV1.swift",
        "purpose": "Expose locale capability truth through existing dictation proposal contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5b45d80ad7e06019f3ad5d88c04e16c9dee49eaa",
        "expectedBSHA256": "622c0bbee789f3743a85a4f800c3a3838e16a145d6fbca4613b35edbcc36b8d7",
        "path": "FieldEvidenceApp/Application/Assistance/DictationLocationProposalCoordinatorV1.swift",
        "purpose": "Coordinate truthful dictation capability through the existing coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7fa83bf0402c6ff94f14277b8f54243ffc12af0f",
        "expectedBSHA256": "9bd140c90407820ff6fc186985a7481ffddedaca3e2fbec5beb8fa4ade4fc647",
        "path": "FieldEvidenceApp/Infrastructure/Assistance/DictationLocationProposalLifecycleAdapterV1.swift",
        "purpose": "Route truthful dictation lifecycle state without implying unsupported recognition.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "9b07602815af05100569c84cfeee6da50430e736",
        "expectedBSHA256": "46e9d97e0d6540cca1cfb4bb9783193ab5144246b1247c58cfc5803494e5c148",
        "path": "FieldEvidenceApp/Domain/VoiceCapture/StructuredVoiceCaptureContractsV1.swift",
        "purpose": "Represent exact structured voice capture capability truth.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "2761180c681e70851b5c1d92a27dd9d9af0cba12",
        "expectedBSHA256": "775d44f62d257b8748136a7eacd6b95a2a382c784c2275052fbdd1bd212dbafa",
        "path": "FieldEvidenceApp/Application/VoiceCapture/VoicePushToTalkCoordinatorV1.swift",
        "purpose": "Coordinate exact voice capability truth through the existing capture flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "9b609e5b08e00e34375af481bd1800f7de1f6cf3",
        "expectedBSHA256": "03d56670fa477ce24e561bb32c59c67ca162bfcad5f0195aabc2f647c3f3b638",
        "path": "FieldEvidenceApp/Infrastructure/VoiceCapture/OnDevicePushToTalkVoiceCaptureAdapterV1.swift",
        "purpose": "Read OS/device capability truth from the existing on-device adapter.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1c962c0c9eeb9821031652933c8d0213eebe8eb1",
        "expectedBSHA256": "35cd045a4e992749380e583bb16578309debc268837b8341b0a118f5cc24344a",
        "path": "FieldEvidenceApp/Application/VoiceStructuring/VoiceStructuringServiceV1.swift",
        "purpose": "Preserve truthful voice structuring capability semantics.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "fc49c2c1db4a85b5d4c489823dd04b3c69ad5ea2",
        "expectedBSHA256": "d29505d9df235de5e6eabf0b56e4780182d32c2cc445c8570c43ff434ca88f4b",
        "path": "FieldEvidenceApp/Infrastructure/System/SystemCapabilityAdaptersV1.swift",
        "purpose": "Bind exact OS/device/build capability evidence through the existing system adapter.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c77b5a7f8f07bd6a4501ac1aafa8a16027c05f49",
        "expectedBSHA256": "9f5a02ea8b3886a9cce19513357071a8349999da388a0e9bbf50f39951ac8834",
        "path": "FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift",
        "purpose": "Represent unavailable locale capability without translated-label overclaim.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c13bf071b08bd2ea99f2d5f81ab28f738aea0470",
        "expectedBSHA256": "e05082ff9ea78e1540e1c40e3d15045cb4ec95e9a5d8947540532c3d4acaeb77",
        "path": "FieldEvidenceAppTests/V9_86OCRProposalTests.swift",
        "purpose": "Regression-test OCR capability truth.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5f8298038ce95e7b33a3126470f4b9faa5212fb5",
        "expectedBSHA256": "6051d524b8b6e93b509b4f4445206575ea778b76dc67f075c1aaa4488734aeaa",
        "path": "FieldEvidenceAppTests/V9_87DictationLocationProposalTests.swift",
        "purpose": "Regression-test dictation capability truth.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "a15df49b07e60a6a880757d15d989cc2611d15bb",
        "expectedBSHA256": "d217fbe0f59eaf7c9ddf56db38fa5a86370f6378c00123a8c800a9722f284e73",
        "path": "FieldEvidenceAppTests/V9_108StructuredVoiceCaptureTests.swift",
        "purpose": "Regression-test voice capture capability truth.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c164c01fc99331fa785836302b1e168f4cf01276",
        "expectedBSHA256": "f9ec728e6e744df08790995eb7dd24e10997414c95f38369a476da2ae6e73084",
        "path": "FieldEvidenceAppTests/V9_64StructuredVoiceProposalTests.swift",
        "purpose": "Regression-test structured voice proposal truth.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P03-C07",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C06",
      "V30-P03-C01"
    ],
    "ordinal": 28,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "OCR, dictation, speech, and assisted-input capability truth"
  },
  "fenceSource": {
    "cardID": "V30-P03-C07",
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
  "next": "V30-P03-C08",
  "observedCoordination": {
    "head": "4ad2526542d23bb14414234cb9986506da09a99d",
    "ledgerDigest": "b3ea3c3dd84112bb7b50404a237c11b0e54952d1cbd37530a6f48b4ab5278502",
    "sequence": 57
  },
  "ordinal": 28,
  "outcome": "Freeze per-locale capability and online/offline truth. A translated label never implies recognition, dictation, speech, or grammar support unavailable to the exact OS/device/build.",
  "payloadDigest": "3b420df6e90f3ce33e70d1e9267048c9fba050c998215edbc62f8d89b5767e60",
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
  "sourceEndLine": 1012,
  "sourceStartLine": 1012,
  "title": "OCR, dictation, speech, and assisted-input capability truth"
}
```
