# V30 Current Task

Card 3 of 55 — Namespaced provisional coordination genesis validation

Only the exact pre-issued fence below is writable. Embedded context is the active hydration; materialize its allowed context file after selection CAS. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Validate, schema-seal, and exercise the sole G3-created expected-absent provisional-ledger genesis at the authority-pinned isolated coordination locator/ref, including distinct ID/writer generation/digest chain and immutable V23 observations. Never create a second genesis, mutate, or claim succession to the canonical V23 ledger.",
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
    "head": "e50deb9f62591b1a746cb61afebedcd2e0bb6068",
    "tree": "fb124f2644b5da95914591dcf778fd9d1787188b"
  },
  "cardID": "V30-P00-C03",
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
    "V30-P00-C01",
    "V30-P00-C02"
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
        "path": "docs/design/v30/execution/V30_PROVISIONAL_COORDINATION_GENESIS.json",
        "purpose": "Sole G3-created isolated coordination genesis record.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/execution/contexts/V30-P00-C03-attempt-1.json",
        "purpose": "Card 3 ledger-genesis validation context.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/execution/receipts/V30-P00-C03-genesis-validation-receipt.json",
        "purpose": "Schema-sealed genesis validation receipt.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P00-C03",
    "class": "FOUNDATION",
    "directPrerequisites": [
      "V30-P00-C01",
      "V30-P00-C02"
    ],
    "ordinal": 3,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Namespaced provisional coordination genesis validation"
  },
  "fenceSource": {
    "cardID": "V30-P00-C03",
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
  "next": "V30-P00-C04",
  "observedCoordination": {
    "head": "84d7e8a207bb88f508ef3e533dd9f8e4d7713368",
    "ledgerDigest": "5af093a1d41d221eb011ec63fd8b28d17e5d8756145bd06a417afcb307743fde",
    "sequence": 5
  },
  "ordinal": 3,
  "outcome": "Validate, schema-seal, and exercise the sole G3-created expected-absent provisional-ledger genesis at the authority-pinned isolated coordination locator/ref, including distinct ID/writer generation/digest chain and immutable V23 observations. Never create a second genesis, mutate, or claim succession to the canonical V23 ledger.",
  "payloadDigest": "981cca19deabfdd72174f86fc56f92afc27b4885c297259825b7f7953c1c1149",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
    "V30-P00-C01": {
      "candidate": {
        "base": "d2a153ba730e1894eb82b7cd3cc56e8ff2c3d2bb",
        "changedPaths": [
          "docs/design/v30/execution/V30_PROVISIONAL_ACTIVATION_RECEIPT.json",
          "docs/design/v30/execution/receipts/V30-P00-C01-validation-receipt.json"
        ],
        "head": "33566fa40a36903c11b7bab461e1531d8930cfbe",
        "tree": "aa7ec303155a7caeb376ac23a36967f215d2043b"
      },
      "sequence": 3
    },
    "V30-P00-C02": {
      "candidate": {
        "base": "1374269994a871236703d5e006fb86f34bb06b68",
        "changedPaths": [
          "docs/design/v30/execution/contexts/V30-P00-C02-attempt-1.json",
          "docs/design/v30/execution/proofs/V30-P00-C02-reservation-and-fence-proof.json",
          "docs/design/v30/execution/receipts/V30-P00-C02-fence-proof-receipt.json"
        ],
        "head": "e50deb9f62591b1a746cb61afebedcd2e0bb6068",
        "tree": "fb124f2644b5da95914591dcf778fd9d1787188b"
      },
      "sequence": 5
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Static governance; hosted dispatch disabled until Card 5 pins the route",
  "sourceEndLine": 972,
  "sourceStartLine": 972,
  "title": "Namespaced provisional coordination genesis validation"
}
```
