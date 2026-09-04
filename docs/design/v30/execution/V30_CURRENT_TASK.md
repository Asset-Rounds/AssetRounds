# V30 Current Task

Card 10 of 55 — Language, locale, content, report, storefront, and jurisdiction contracts

Only the exact pre-issued fence below is writable. Embedded context is the active hydration; create a separate context file only if the exact fence names it. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Version-forward existing V23 contracts for BCP 47 app language, formatting locale, IANA time zone, calendar, numbering, units, authored content, report language, storefront country, and jurisdiction. Prove the six axes are independent.",
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
    "head": "e13882efbfce199ee97b70d9d9e73cc434ce9217",
    "tree": "0d6e32f5f1aa589b7189b0e9e4dc80e1c822473c"
  },
  "cardID": "V30-P01-C04",
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
    "V30-P01-C01"
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
        "path": "FieldEvidenceApp/Domain/Globalization/GlobalizationAxisContractsV1.swift",
        "purpose": "Independent BCP-47, formatting, zone, calendar, content, report, storefront, and jurisdiction contracts.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Application/Globalization/GlobalizationAxisCoordinatorV1.swift",
        "purpose": "Axis resolution coordinator without a parallel framework.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P01_C04GlobalizationAxisContractTests.swift",
        "purpose": "Six-axis independence and canonical-value tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/GlobalizationAxes/axis-matrix-v1.json",
        "purpose": "Deterministic axis-matrix fixture.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8cd93ce082652e054201409787ba27fb82c63013",
        "expectedBSHA256": "5d1982421bea62d1ec5339f5a279b6f1f552afa8d90f7dc16f01e389b575dc4f",
        "path": "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
        "purpose": "Version-forward the existing typed locale/catalog contract for the six independent globalization axes.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f28f90aa7b8b19519412ed879788166d01309008",
        "expectedBSHA256": "8e9814f0a5164b72aea2ba7f7b710e2bd4b20f1b14a3f6ee9306047218a2505d",
        "path": "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
        "purpose": "Define device-local versus workspace-canonical globalization preference disposition in the existing settings contract.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "cbcdfe1281de6e98af13f1b12a0e32a6c7b9967b",
        "expectedBSHA256": "b7ae0570ef54ba29ddb7c308b3f5236e03045297abddc18c3be99ad0b77d0e12",
        "path": "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
        "purpose": "Persist only the allowed device-local globalization preference state through the existing adapter.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "19f52a71cb2ded5ac20912bb8634263e7ace1ed6",
        "expectedBSHA256": "a0065b15ef7059867bb00377bd5b97cbcd2e9ac98c74ea0e154297410773f8bb",
        "path": "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
        "purpose": "Add report language/formatting/provenance axes to the existing document contract.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "783f2db48da3032b9ce3217bfaf45900ae1e4cc4",
        "expectedBSHA256": "376a46bed52cccd33fe686f09f60f8f2948afb297f2dbc42305e0fa6e4a475fd",
        "path": "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
        "purpose": "Preserve language-independent canonical report projection identity while adding display metadata.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8639bed99bec1503f63f556fb044f4ac493be506",
        "expectedBSHA256": "d66914b0fd97a95fa7af39ab1502911775a23b883d4be5233cdb4ee778183dba",
        "path": "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
        "purpose": "Bind backup identity/disposition to language-neutral canonical data.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1134417b3f24bf056cef13cdb133ea61d34c43fc",
        "expectedBSHA256": "7b1c9163359202e97558078c3a782a03faa543ce7c14198ab1893e2fd65da5df",
        "path": "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
        "purpose": "Extend existing localization contract regression coverage.",
        "serializedSharedPath": true
      }
    ],
    "cardID": "V30-P01-C04",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C01"
    ],
    "ordinal": 10,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Language, locale, content, report, storefront, and jurisdiction contracts"
  },
  "fenceSource": {
    "cardID": "V30-P01-C04",
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
  "next": "V30-P01-C05",
  "observedCoordination": {
    "head": "19de9a7180038ac444eea3251577fb0154a6a4da",
    "ledgerDigest": "63a9715d615189ce459402523ec620a22aba31067198f62d5c9e46e3067f74d2",
    "sequence": 20
  },
  "ordinal": 10,
  "outcome": "Version-forward existing V23 contracts for BCP 47 app language, formatting locale, IANA time zone, calendar, numbering, units, authored content, report language, storefront country, and jurisdiction. Prove the six axes are independent.",
  "payloadDigest": "577204a19f4cc79446fc51e3c4bf8a4661ef27ac279c67faa2d085c1628273bb",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P01-C01": {
      "candidate": {
        "base": "bd231bd0daf11ac5f7842c2eab2164c8f0dc8e28",
        "baseTree": "0f9353ec92fab121aa3b33740996e6305d5b8a71",
        "changedPaths": [
          "FieldEvidenceAppTests/V30_P01_C01ResearchCohortTests.swift",
          "docs/design/v30/research/V30CompetitorCapabilityEvidenceV1.json",
          "docs/design/v30/research/V30InitialLanguageCohortV1.json",
          "docs/design/v30/research/V30ResearchManifestV1.json"
        ],
        "head": "d52cbd38e19b51bcd8c83f6d5fca768ace817d90",
        "tree": "84da9fd23f74d859e51b53e031fff4ad2d79693b"
      },
      "sequence": 16
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; Card5 hosted route is pinned but no native dispatch is selected.",
  "sourceEndLine": 984,
  "sourceStartLine": 984,
  "title": "Language, locale, content, report, storefront, and jurisdiction contracts"
}
```
