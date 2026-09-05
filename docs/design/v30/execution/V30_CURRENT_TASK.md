# V30 Current Task

Card 12 of 55 — System-first resolution, fallback, and effective-language evidence

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Use Apple device/per-app resolution, no bundle swizzle, effective-language observation, safe app-Settings deep link, foreground/relaunch behavior, exact/base/English fallback, raw-key prevention, and privacy-preserving fallback diagnostics.",
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
    "head": "66ef581ea88ce2ee1d6cb35586574d5df5c94bf7",
    "tree": "4c5b3b3e0f72e9f4e947ceb75d1ac30e5db542f7"
  },
  "cardID": "V30-P01-C06",
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
    "V30-P01-C03",
    "V30-P01-C04"
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
        "path": "FieldEvidenceApp/Domain/Globalization/EffectiveLanguageContractsV1.swift",
        "purpose": "System-first effective-language and fallback contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Localization/SystemLanguageResolverV1.swift",
        "purpose": "Apple locale/per-app resolution adapter without bundle swizzling.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Settings/GlobalizationSettingsCoordinatorV1.swift",
        "purpose": "Safe Settings handoff and foreground/relaunch coordinator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P01_C06SystemLanguageResolutionTests.swift",
        "purpose": "Exact/base/English fallback and raw-key prevention tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/LanguageResolution/system-language-cases-v1.json",
        "purpose": "Deterministic system-language resolution fixtures.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8cd93ce082652e054201409787ba27fb82c63013",
        "expectedBSHA256": "5d1982421bea62d1ec5339f5a279b6f1f552afa8d90f7dc16f01e389b575dc4f",
        "path": "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
        "purpose": "Expand the existing shipping locale/fallback contract beyond its en-only baseline.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Replace the existing runtimeLanguage=en resolution seam with Apple system/per-app effective-language resolution.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "cbcdfe1281de6e98af13f1b12a0e32a6c7b9967b",
        "expectedBSHA256": "b7ae0570ef54ba29ddb7c308b3f5236e03045297abddc18c3be99ad0b77d0e12",
        "path": "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
        "purpose": "Persist only privacy-preserving device-local fallback diagnostics through the existing adapter.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "b311e66b05b19078c9823b59c91c1f9c81964d49",
        "expectedBSHA256": "ddb2bb5579ec9c091f268f09a3552b00318165e44e31f87940931acb8029e2f6",
        "path": "FieldEvidenceApp/Application/Ports/SettingsCapabilityPortsV1.swift",
        "purpose": "Expose the existing typed settings capability port for safe system-Settings handoff.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "purpose": "Wire only the V30 Language & Region Settings entry point; preserve Phase10-owned shell navigation and brand.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1134417b3f24bf056cef13cdb133ea61d34c43fc",
        "expectedBSHA256": "7b1c9163359202e97558078c3a782a03faa543ce7c14198ab1893e2fd65da5df",
        "path": "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
        "purpose": "Extend effective-language, fallback, and raw-key regression coverage.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P01-C06",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C03",
      "V30-P01-C04"
    ],
    "ordinal": 12,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "wire only the V30 Language & Region Settings entry point in FieldEvidenceApp/Features/Shell/AppShellView.swift; preserve Phase10 shell navigation and brand",
        "cardID": "V30-P01-C06",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P01-C06-SETTINGS-RESOLUTION-INTEGRATOR"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/Features/Shell/AppShellView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "System-first resolution, fallback, and effective-language evidence"
  },
  "fenceSource": {
    "cardID": "V30-P01-C06",
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
  "next": "V30-P01-C07",
  "observedCoordination": {
    "head": "621495eae5f016958b825a29d583c939dfa63e2c",
    "ledgerDigest": "28f0bc7450d17df31ea0b7f1c8a9e7a6052d2f348dd7ff10bd921be4f87b7d9d",
    "sequence": 24
  },
  "ordinal": 12,
  "outcome": "Use Apple device/per-app resolution, no bundle swizzle, effective-language observation, safe app-Settings deep link, foreground/relaunch behavior, exact/base/English fallback, raw-key prevention, and privacy-preserving fallback diagnostics.",
  "payloadDigest": "6a5f5d054d4e084c328f982ffc4be579d5d41a88ac498fc76116c4a20b6ca544",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P01-C03": {
      "candidate": {
        "base": "321eaf374c88ed7733549341c5de8d9505e4d76e",
        "baseTree": "c783e1ea1c28466025978aebf428dd7c43a1a5b2",
        "changedPaths": [
          "FieldEvidenceAppTests/V30_P01_C03TextSurfaceInventoryTests.swift",
          "Scripts/v30/validate_v30_text_surface_inventory.py",
          "docs/design/v30/inventory/V30TextBearingSurfaceInventoryV1.json",
          "docs/design/v30/inventory/V30TextSurfaceDispositionSchemaV1.json"
        ],
        "head": "e13882efbfce199ee97b70d9d9e73cc434ce9217",
        "tree": "0d6e32f5f1aa589b7189b0e9e4dc80e1c822473c"
      },
      "sequence": 20
    },
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
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 986,
  "sourceStartLine": 986,
  "title": "System-first resolution, fallback, and effective-language evidence"
}
```
