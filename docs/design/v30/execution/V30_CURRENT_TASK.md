# V30 Current Task

Card 4 of 55 — Provisional candidate and reconciliation-manifest contract

Only the exact pre-issued fence below is writable. Embedded context is the active hydration; materialize its allowed context file after selection CAS. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Define per-card base/candidate head/tree/diff/evidence/path-overlap manifests, exact B/P/S lineage mappings, compatibility classes, invalidation rules, and replay/reimplementation requirements for P05.",
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
    "head": "2be5f8f58010c5813283ec9e69c17183733d462a",
    "tree": "1a4a1b6960adc634488b4aae0c1be0f030af63f4"
  },
  "cardID": "V30-P00-C04",
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
    "V30-P00-C02",
    "V30-P00-C03"
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
        "path": "docs/design/v30/contracts/V30ProvisionalCandidateReconciliationManifestV1.json",
        "purpose": "B/P/S candidate and replay contract.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "docs/design/v30/schemas/v30-provisional-candidate-reconciliation-manifest.schema.json",
        "purpose": "Schema for per-card candidate/reconciliation manifests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "Scripts/v30/validate_v30_provisional_candidate_manifest.py",
        "purpose": "Deterministic V30 candidate-manifest validator.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P00_C04CandidateReconciliationManifestTests.swift",
        "purpose": "Contract tests for B/P/S candidate mappings.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P00-C04",
    "class": "FOUNDATION",
    "directPrerequisites": [
      "V30-P00-C02",
      "V30-P00-C03"
    ],
    "ordinal": 4,
    "preAuthorizedOverlapTuples": [],
    "s10SharedPaths": [],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "Provisional candidate and reconciliation-manifest contract"
  },
  "fenceSource": {
    "cardID": "V30-P00-C04",
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
  "next": "V30-P00-C05",
  "observedCoordination": {
    "head": "1b52a07b27bd527eae6ac1d624871f7f0db1a96b",
    "ledgerDigest": "f06d4108c1c47d00ac912082a68eed82c7da863b241c0384acbfeafa0ede4d17",
    "sequence": 7
  },
  "ordinal": 4,
  "outcome": "Define per-card base/candidate head/tree/diff/evidence/path-overlap manifests, exact B/P/S lineage mappings, compatibility classes, invalidation rules, and replay/reimplementation requirements for P05.",
  "payloadDigest": "fd099be0058eb6dc18dc77344d56d4367d638b0c20f9474044800b81fac17fc6",
  "planningStatus": "PRE_S10_PROVISIONAL_ELIGIBLE",
  "preS10FinalCredit": false,
  "predecessorEvidence": {
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
    },
    "V30-P00-C03": {
      "candidate": {
        "base": "c7cc89bde7b7f232626a6e7c98f65feb9724813b",
        "changedPaths": [
          "docs/design/v30/execution/V30_PROVISIONAL_COORDINATION_GENESIS.json",
          "docs/design/v30/execution/contexts/V30-P00-C03-attempt-1.json",
          "docs/design/v30/execution/receipts/V30-P00-C03-genesis-validation-receipt.json"
        ],
        "head": "2be5f8f58010c5813283ec9e69c17183733d462a",
        "tree": "1a4a1b6960adc634488b4aae0c1be0f030af63f4"
      },
      "sequence": 7
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Static governance; hosted dispatch disabled until Card 5 pins the route",
  "sourceEndLine": 973,
  "sourceStartLine": 973,
  "title": "Provisional candidate and reconciliation-manifest contract"
}
```
