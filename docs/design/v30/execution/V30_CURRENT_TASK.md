# V30 Current Task

Card 9 of 55 — Complete text-bearing surface inventory

Only the exact pre-issued fence below is writable. Embedded context is the active hydration; create a separate context file only if the exact fence names it. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Inventory UI, accessibility, permissions, onboarding, help, errors, recovery, destructive actions, notifications, reports, PDFs, CSV/JSON, templates, content packs, labels, share/email/print, commerce, metadata, tests, developer text, user-authored content, and machine data. Give every item an owner and disposition.",
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
    "head": "321eaf374c88ed7733549341c5de8d9505e4d76e",
    "tree": "c783e1ea1c28466025978aebf428dd7c43a1a5b2"
  },
  "cardID": "V30-P01-C03",
  "class": "FOUNDATION",
  "credit": {
    "canonicalAcceptance": false,
    "finalCredit": false,
    "mainIntegrationCredit": false,
    "postS10SuccessorStart": false,
    "provisionalDependencySatisfied": false,
    "releaseCredit": false
  },
  "directPrerequisites": [
    "V30-P01-C02"
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
        "path": "docs/design/v30/inventory/V30TextBearingSurfaceInventoryV1.json",
        "purpose": "Exhaustive owned text-bearing surface inventory.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/inventory/V30TextSurfaceDispositionSchemaV1.json",
        "purpose": "Schema for owner/disposition records.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "Scripts/v30/validate_v30_text_surface_inventory.py",
        "purpose": "Inventory coverage and ownership validator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P01_C03TextSurfaceInventoryTests.swift",
        "purpose": "Text-surface inventory evidence.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P01-C03",
    "class": "FOUNDATION",
    "directPrerequisites": [
      "V30-P01-C02"
    ],
    "ordinal": 9,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Complete text-bearing surface inventory"
  },
  "fenceSource": {
    "cardID": "V30-P01-C03",
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
  "next": "V30-P01-C04",
  "observedCoordination": {
    "head": "d7bdbc360bb676ec7180acd51dd0e20e81f8a4e5",
    "ledgerDigest": "6c2d515cfa2d2e9b8a5786f19c17003bd547882a84ee97d368f0a5a0be8acace",
    "sequence": 18
  },
  "ordinal": 9,
  "outcome": "Inventory UI, accessibility, permissions, onboarding, help, errors, recovery, destructive actions, notifications, reports, PDFs, CSV/JSON, templates, content packs, labels, share/email/print, commerce, metadata, tests, developer text, user-authored content, and machine data. Give every item an owner and disposition.",
  "payloadDigest": "9bbd274dfb7c18e0ab9663d4963faa337434c3b4490a6a293f6d25a9d7d8192d",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P01-C02": {
      "candidate": {
        "base": "f12031577888e980f300a41787ce46c946ea13c9",
        "baseTree": "ae8384a385b0c588928af500ce78a3dc508d74ac",
        "changedPaths": [
          "FieldEvidenceAppTests/V30_P01_C02ScopeDispositionTests.swift",
          "docs/design/v30/research/V30CustomerNeedsScopeDispositionRegisterV1.json",
          "docs/design/v30/research/V30KeywordEvidenceBindingV1.json"
        ],
        "head": "321eaf374c88ed7733549341c5de8d9505e4d76e",
        "tree": "c783e1ea1c28466025978aebf428dd7c43a1a5b2"
      },
      "sequence": 18
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; Card5 hosted route is pinned but no native dispatch is selected.",
  "sourceEndLine": 983,
  "sourceStartLine": 983,
  "title": "Complete text-bearing surface inventory"
}
```
