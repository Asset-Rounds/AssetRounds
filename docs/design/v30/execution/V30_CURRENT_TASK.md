# V30 Current Task

Card 15 of 55 - English catalog normalization

Only the exact pre-issued fence below is writable. Embedded context is the active hydration. V4 authority/selector remain frozen. No Phase 10 access/polling or main mutation.

```json
{
  "acceptance": {
    "nativeEvidence": "NOT_EXECUTED_NO_NATIVE_CREDIT",
    "required": "Normalize required app-owned English text into semantic keys with comments, placeholders, plurals, variations, terminology, permission/accessibility/report coverage, and explicit literal dispositions.",
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
    "head": "020c9da6df9c2d9afe741290ecab1b1893d8b2ec",
    "tree": "a7b68fe27452c186cdd9e8c6a244a39c29b5c1ff"
  },
  "cardID": "V30-P02-C01",
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
    "V30-P01-C08"
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
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "69a33d27f8db846dd27ae5e554856a4e12e8aeaf",
        "expectedBSHA256": "67cbc936089d01bc772330600727ddea7d312a5a52cd8b16f5f3aff3577d8a53",
        "path": "FieldEvidenceApp/Resources/Localizable.xcstrings",
        "purpose": "Normalize app-owned English semantic keys, comments, placeholders, plurals, and literal dispositions.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceApp/Infrastructure/Localization/V30EnglishCatalogRegistryV1.swift",
        "purpose": "Typed V30 English catalog registry and semantic-key policy.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/V30_P02_C01EnglishCatalogNormalizationTests.swift",
        "purpose": "English semantic-key, placeholder, plural, and literal-disposition tests.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": null,
        "expectedBSHA256": null,
        "path": "FieldEvidenceAppTests/Fixtures/V30/EnglishCatalog/english-catalog-audit-v1.json",
        "purpose": "English catalog audit fixture.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "66b140364dbe91ac14a57aa49a9ace8cb9a51140",
        "expectedBSHA256": "c52cfb7a59f8a016c0a5b4dfb9e2b55a09ec73a94411eb3f09e1039c05ca5788",
        "path": "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
        "purpose": "Route normalized semantic English keys through the current typed catalog seam.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8cd93ce082652e054201409787ba27fb82c63013",
        "expectedBSHA256": "5d1982421bea62d1ec5339f5a279b6f1f552afa8d90f7dc16f01e389b575dc4f",
        "path": "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
        "purpose": "Enforce semantic-key/comment/placeholder/literal-disposition policy in the existing contract.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1134417b3f24bf056cef13cdb133ea61d34c43fc",
        "expectedBSHA256": "7b1c9163359202e97558078c3a782a03faa543ce7c14198ab1893e2fd65da5df",
        "path": "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
        "purpose": "Extend existing localization/accessibility key coverage.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "50e6a7e11ff107d608318498fa578d852b5c6b06",
        "expectedBSHA256": "7c33e08af4b67ffa60f4574192cca077548e9d1d5989f890be2a3a07c7fa8563",
        "path": "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "209f205aab77a68265f0601696a23a06f4d7ce4c",
        "expectedBSHA256": "60b2cd11ed0c07e7573906e4cc01e1e3bb4c5b496991eaa79c9874d343e6042d",
        "path": "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0fcac3c65ac2581c5912936215cd5c2a3b7ff1ed",
        "expectedBSHA256": "700ad042adb3f6cf69eb18e41e078ad0a59e049680bd42e71cd62ca14c7432a0",
        "path": "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "535a86a3312f537f13c10b5db3f7bed3ac0f3945",
        "expectedBSHA256": "fefb968c6900e8cf9abd054e09e424cac7510c56e82642657efda45fa81ff559",
        "path": "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f7a500dd414a35824117caa9dcd93c83909d1530",
        "expectedBSHA256": "f2290620946afbb1b60577db62203a5c99e3012b74943b5cbbe7c576c83a71e8",
        "path": "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "199911f3676695af27f475e62e2d9ea4fb05e34d",
        "expectedBSHA256": "bfa8424e5cd55367d34c80562567651e23107b7c01995604311fdb5578cebc7b",
        "path": "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5e0b1d333ff0124259a863674c7cb308365a13b6",
        "expectedBSHA256": "0e3a4d543e588ae24a0ed06aaf05d50081341602cdf1fe04b9ddfd0bb945a955",
        "path": "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0797274e09f174e1caca359c3ce6b030c41054e6",
        "expectedBSHA256": "57ffc1c79e02a1adad526837339c21baba35f4a41bd340ab547f64eebcc51fd8",
        "path": "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "9007a09c8dbca262ddbaa680e8bc6d906c3166c5",
        "expectedBSHA256": "217403ff65a8cde53dc0d1402d929720782232391d998eab48afc1fd72159c6c",
        "path": "FieldEvidenceApp/Features/Issues/IssueDetailView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "e830455b14706763c3f9be4a930cd27955ef0890",
        "expectedBSHA256": "d8b9376be21c1b441c5f166ed22b851c35de63d8ba056e82ae1d30f4628933e6",
        "path": "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "af1cea52cbd507b9a2c5ff4fcb823e8aa999b0ec",
        "expectedBSHA256": "dd5d6dddb6e58fbc86e9cbbf7318a8ad6d3271bd93117b4c72ac52d058381fd8",
        "path": "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c02680e9870fa348f1b8237f03f66496ff393418",
        "expectedBSHA256": "22387f27d46acfbf2e021b89e3f2bc2caf63fcdc95f8dc5cb6d2259d73ff3716",
        "path": "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5378ee6c73d8d86cce2c7a316fa23509d4d3250e",
        "expectedBSHA256": "e869176ccc9a768f1c351442c3e22d4a560bd7b39ab2ea209d85774c1079d26a",
        "path": "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "295917ff019fa349871946b8dcdeaa4727eb807d",
        "expectedBSHA256": "73161df4862a170d8232b61e922d7cb60d577e95d7e6727406ff754d83a80350",
        "path": "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "0b4f6740f4a5ecbb801ce2dd5bdd7c77f30afe92",
        "expectedBSHA256": "82f4862beabd981422629fad66065086571fc66d1f79d982df3deec683ade1a0",
        "path": "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "2f9e5a5b606e1170030b91d867374b55b6144d86",
        "expectedBSHA256": "007303e9c3ac6125a0833ecd045b5d4338ccc7c49832cd03a9692dcdac7ccc34",
        "path": "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f6b551d503a0af293cff966a1cb5d725a20f773d",
        "expectedBSHA256": "955f13980acd330d98aaa0ee13735bb6f6f2b3c45772fbe8e7ebf8b5c2269c1f",
        "path": "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "82bd8b590e238f8f5c5f119dd91b20dbd57893ea",
        "expectedBSHA256": "64e594839fbc4d3dfb2974539449c4644fe07cda52a1c30a06078ac8f427398a",
        "path": "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "424f869477fe107d1595763c951abef7193c9c6b",
        "expectedBSHA256": "64f745df1643d2271317756930f2cb003a9bc34bfba23a8cd70477a9a047aa7f",
        "path": "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "9945d02fd9c0680ee79e986fd2a90c3deee6ebeb",
        "expectedBSHA256": "ecf83578f59beef12e9aa03a0324acc7779f9847ff163d1ba5271c84a7f230af",
        "path": "FieldEvidenceApp/Features/Signs/NewSignView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "8844b6684eaf9c44866d9b81057cab872d2c37cd",
        "expectedBSHA256": "7f4ff80b1949f0d851358c732a6add07d9567f1e2f50f7701810fccf657e2b39",
        "path": "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "112133d2df57c5f734267a079987277866e74a84",
        "expectedBSHA256": "4b59bad89665bbf0b1b7c6189c09090f93e78d1b963152f344b9611490cf527f",
        "path": "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "21d5da5da6c3db7aae50b6e8eaf352de2ae5302a",
        "expectedBSHA256": "28c95fc0a9c84f29ef3e26f758f6c22eee92927ee5e9a40a650e62db1d9f11a7",
        "path": "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "78af1da11a91694d54dc4539c446685a7e12eb9d",
        "expectedBSHA256": "7b25a78ebd2a216ef538bc22260f8b85d1ef2b8d239e94c5f0e93c03eee24a04",
        "path": "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "3d3e9c1cd3e7aba2769e77ad4f31d5d60455c9fc",
        "expectedBSHA256": "0ab6b0d384018d5f5f670ba0e8d81f7d229245dbedec3b54d4050ad462abd18c",
        "path": "FieldEvidenceApp/Features/Accountability/SignoffEnrollmentView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "bf638ee402fa66340f4bc58256507759aa628e4c",
        "expectedBSHA256": "b3c898bbdb8fa3df3f5f9a89a717d2310311f486aa5b650b0fa5c48074e26748",
        "path": "FieldEvidenceApp/Features/Activities/InstallationWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "5ab810147d8aaa0e94da6cd455dc9ecaae4bbd7a",
        "expectedBSHA256": "9f104c1c7b05c372d8e66e2543c4ed8bbc36b68b46ba09de63a2279531da342d",
        "path": "FieldEvidenceApp/Features/Activities/PunchReviewWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "805e528fe1e4745c5890232408f1b0a02018d5f9",
        "expectedBSHA256": "9489c9a0fd1b270e65ee28960c2208afbf493daeb37b395d73113af2490b96cd",
        "path": "FieldEvidenceApp/Features/AssetImport/PartyContactSiteRoleImportView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "805c35253d3b2303912a36ceb615f4b685c2b14b",
        "expectedBSHA256": "a33abeeddadd8363ecc70d9762867953c63ed4b0a830b41e42ffbff4ea01b411",
        "path": "FieldEvidenceApp/Features/CheckRunner/EvidenceCurationView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "d6e32d1bd99c50baf61a8de049d9b1220253389a",
        "expectedBSHA256": "7a3654e928958350d6541cf571644d229fa5f15d4d3d23a6a51df5d76630fa9e",
        "path": "FieldEvidenceApp/Features/CheckRunner/EvidenceQualityCoachView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6888939c824917f828741644016683a65fe7e8ff",
        "expectedBSHA256": "44c6acd28391d5609e668c31266d19c593383a15517e2d874e018f3dd72234a1",
        "path": "FieldEvidenceApp/Features/Contacts/OperationalContactHandoffView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7c639ec9feca4c1828577a34a30b7a5dba188568",
        "expectedBSHA256": "c3dbc9b970e748ef24bede3438e219622ae11b6b3cf8059f6f75e122c9f0838f",
        "path": "FieldEvidenceApp/Features/Contacts/PartyContactSiteRoleWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "f05badc2ac2de4d0fd0f80287280bc14be76f767",
        "expectedBSHA256": "e1bb1925806ccc66854cd3eafc5c85a671ff53e284439502e374ec7edd400509",
        "path": "FieldEvidenceApp/Features/Dashboard/ExceptionReviewQueueView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6de539ccabeb8dee7a4738d3d4bb5fa8d9eac75d",
        "expectedBSHA256": "ed3ecf6828d75a66b0afe9d5e66bc251c50d9f0de962a5e94b38971b31daf564",
        "path": "FieldEvidenceApp/Features/Dashboard/OperationsDashboardView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "7e2e4fa68cae5bc27f6af6669f41726a73de1ac6",
        "expectedBSHA256": "f3557940a31b1251e7598c9384160a8da21f0057e1c5c660fb26817ea1226090",
        "path": "FieldEvidenceApp/Features/Integrations/IncumbentFileAdapterWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "75590cbd581d0f1181ac652f5a160e0ccc24a382",
        "expectedBSHA256": "080eff792318818d28b50d4f812907ebcfd7c5f39f7772a4c5c1e1398b2b272c",
        "path": "FieldEvidenceApp/Features/MyDay/MyDayWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "6700e9b81495184ac73d94e10f0c9201243829db",
        "expectedBSHA256": "e64e024f682bca17ff2ae207f7a512cdeb15ea4db56377b0b8ee23a971039342",
        "path": "FieldEvidenceApp/Features/PartsStock/PartsStockWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "1798cf7b2fd27e4005c2877083108b8362cd450f",
        "expectedBSHA256": "fd97a87be8b5e83f9458f2d8e517c79c552876f9adf5eed3e8472a876edc7af5",
        "path": "FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "cbf57069537bc9a75fc50aca6dc7f078ac2adbf2",
        "expectedBSHA256": "590e4210beb49052f753b6cdc4fa11d31339bbd317ad78fd139cca88d9657d16",
        "path": "FieldEvidenceApp/Features/ReviewExchange/RecipientReviewWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "79b9c8a323e8e2cc08ff5bee104dc7648ed1960d",
        "expectedBSHA256": "55a8bfe733a9aa5da7ebd768597f8be14d8ac46d0e1d9db9db0a4ae0758e53ac",
        "path": "FieldEvidenceApp/Features/Rounds/OfflineReadinessPreflightView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "e594bc96cd26e94f4732de20bde119895f30c02e",
        "expectedBSHA256": "15b47b3bd21e0eb4d797bdc33867c44ffe441b433a6ac5ec1bf1725e4c9e0c8c",
        "path": "FieldEvidenceApp/Features/Rounds/RoundSessionView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "3292ea5f900962eb6e493fe3a66dd018a240040e",
        "expectedBSHA256": "b0b87d4a73ef00818dbe639b8659fe81e343b65ceeb6b423db54025d2345eca2",
        "path": "FieldEvidenceApp/Features/Scheduling/AdvancedRecurrenceWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "89f07cd0696487a163efe1f016a0085cc6cf1340",
        "expectedBSHA256": "7b43b61c62700ab28e4f336371f911144235a00b85ee11339c5784b9591149a8",
        "path": "FieldEvidenceApp/Features/ServiceRequests/ServiceRequestWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "efbf333be80359a655156d8164ae65c986d1aa7c",
        "expectedBSHA256": "d079a41fc20f5a37f8207579071e5ee2d0cb4452567033fd0193bc37d21730cc",
        "path": "FieldEvidenceApp/Features/Settings/RatingSupportWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "c0ba876826f7041174b64ac8436980f149a85bf2",
        "expectedBSHA256": "372f7e93a319db04be167f890ed8347261549cb061642b7a63e37dc23d83da18",
        "path": "FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": true
      },
      {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": "b49bbe5142ca19143643cdf2fb1dc11efa8718e6",
        "expectedBSHA256": "7763f72a2b820861915cb6d814132cf7c3da9de0980997a44abefd6f1b8dd28b",
        "path": "FieldEvidenceApp/Features/WorkResources/ManualWorkResourceWorkflowView.swift",
        "purpose": "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow.",
        "serializedSharedPath": false
      }
    ],
    "cardID": "V30-P02-C01",
    "class": "IMPLEMENTATION",
    "directPrerequisites": [
      "V30-P01-C03",
      "V30-P01-C08"
    ],
    "ordinal": 15,
    "preAuthorizedOverlapTuples": [
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/App/FieldEvidenceAppApp.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "50e6a7e11ff107d608318498fa578d852b5c6b06",
        "expectedBSHA256": "7c33e08af4b67ffa60f4574192cca077548e9d1d5989f890be2a3a07c7fa8563",
        "path": "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/DesignSystem/WorklightComponents.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "209f205aab77a68265f0601696a23a06f4d7ce4c",
        "expectedBSHA256": "60b2cd11ed0c07e7573906e4cc01e1e3bb4c5b496991eaa79c9874d343e6042d",
        "path": "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "0fcac3c65ac2581c5912936215cd5c2a3b7ff1ed",
        "expectedBSHA256": "700ad042adb3f6cf69eb18e41e078ad0a59e049680bd42e71cd62ca14c7432a0",
        "path": "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "535a86a3312f537f13c10b5db3f7bed3ac0f3945",
        "expectedBSHA256": "fefb968c6900e8cf9abd054e09e424cac7510c56e82642657efda45fa81ff559",
        "path": "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "f7a500dd414a35824117caa9dcd93c83909d1530",
        "expectedBSHA256": "f2290620946afbb1b60577db62203a5c99e3012b74943b5cbbe7c576c83a71e8",
        "path": "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "199911f3676695af27f475e62e2d9ea4fb05e34d",
        "expectedBSHA256": "bfa8424e5cd55367d34c80562567651e23107b7c01995604311fdb5578cebc7b",
        "path": "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/CheckRunner/PreflightView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "5e0b1d333ff0124259a863674c7cb308365a13b6",
        "expectedBSHA256": "0e3a4d543e588ae24a0ed06aaf05d50081341602cdf1fe04b9ddfd0bb945a955",
        "path": "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "0797274e09f174e1caca359c3ce6b030c41054e6",
        "expectedBSHA256": "57ffc1c79e02a1adad526837339c21baba35f4a41bd340ab547f64eebcc51fd8",
        "path": "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Issues/IssueDetailView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "9007a09c8dbca262ddbaa680e8bc6d906c3166c5",
        "expectedBSHA256": "217403ff65a8cde53dc0d1402d929720782232391d998eab48afc1fd72159c6c",
        "path": "FieldEvidenceApp/Features/Issues/IssueDetailView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Issues/RecordWorkView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "e830455b14706763c3f9be4a930cd27955ef0890",
        "expectedBSHA256": "d8b9376be21c1b441c5f166ed22b851c35de63d8ba056e82ae1d30f4628933e6",
        "path": "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "af1cea52cbd507b9a2c5ff4fcb823e8aa999b0ec",
        "expectedBSHA256": "dd5d6dddb6e58fbc86e9cbbf7318a8ad6d3271bd93117b4c72ac52d058381fd8",
        "path": "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Reports/ReportDetailView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "c02680e9870fa348f1b8237f03f66496ff393418",
        "expectedBSHA256": "22387f27d46acfbf2e021b89e3f2bc2caf63fcdc95f8dc5cb6d2259d73ff3716",
        "path": "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Reports/ReportFailureView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "5378ee6c73d8d86cce2c7a316fa23509d4d3250e",
        "expectedBSHA256": "e869176ccc9a768f1c351442c3e22d4a560bd7b39ab2ea209d85774c1079d26a",
        "path": "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Reports/ReportsRootView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "295917ff019fa349871946b8dcdeaa4727eb807d",
        "expectedBSHA256": "73161df4862a170d8232b61e922d7cb60d577e95d7e6727406ff754d83a80350",
        "path": "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Settings/BackupExportView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "0b4f6740f4a5ecbb801ce2dd5bdd7c77f30afe92",
        "expectedBSHA256": "82f4862beabd981422629fad66065086571fc66d1f79d982df3deec683ade1a0",
        "path": "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "2f9e5a5b606e1170030b91d867374b55b6144d86",
        "expectedBSHA256": "007303e9c3ac6125a0833ecd045b5d4338ccc7c49832cd03a9692dcdac7ccc34",
        "path": "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Settings/EraseAllView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "f6b551d503a0af293cff966a1cb5d725a20f773d",
        "expectedBSHA256": "955f13980acd330d98aaa0ee13735bb6f6f2b3c45772fbe8e7ebf8b5c2269c1f",
        "path": "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Settings/FeedbackView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "82bd8b590e238f8f5c5f119dd91b20dbd57893ea",
        "expectedBSHA256": "64e594839fbc4d3dfb2974539449c4644fe07cda52a1c30a06078ac8f427398a",
        "path": "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Shell/AppShellView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "7e37497fe218c1471d0dfc1ec1cd90753ad6e6c3",
        "expectedBSHA256": "bb6d9bdadd23b6057f265ef30b477c378ae7c7f03680e0fa0e45a038184526a0",
        "path": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "424f869477fe107d1595763c951abef7193c9c6b",
        "expectedBSHA256": "64f745df1643d2271317756930f2cb003a9bc34bfba23a8cd70477a9a047aa7f",
        "path": "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Signs/NewSignView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "9945d02fd9c0680ee79e986fd2a90c3deee6ebeb",
        "expectedBSHA256": "ecf83578f59beef12e9aa03a0324acc7779f9847ff163d1ba5271c84a7f230af",
        "path": "FieldEvidenceApp/Features/Signs/NewSignView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Signs/SignDetailView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "8844b6684eaf9c44866d9b81057cab872d2c37cd",
        "expectedBSHA256": "7f4ff80b1949f0d851358c732a6add07d9567f1e2f50f7701810fccf657e2b39",
        "path": "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Signs/SignsRootView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "112133d2df57c5f734267a079987277866e74a84",
        "expectedBSHA256": "4b59bad89665bbf0b1b7c6189c09090f93e78d1b963152f344b9611490cf527f",
        "path": "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Subscription/PaywallView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "21d5da5da6c3db7aae50b6e8eaf352de2ae5302a",
        "expectedBSHA256": "28c95fc0a9c84f29ef3e26f758f6c22eee92927ee5e9a40a650e62db1d9f11a7",
        "path": "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      },
      {
        "boundedPurpose": "replace only app-owned English literal/accessibility copy in FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "cardID": "V30-P02-C01",
        "expectedBBlobOID": "78af1da11a91694d54dc4539c446685a7e12eb9d",
        "expectedBSHA256": "7b25a78ebd2a216ef538bc22260f8b85d1ef2b8d239e94c5f0e93c03eee24a04",
        "path": "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": "V30-P02-C01-ENGLISH-NORMALIZER"
      }
    ],
    "s10SharedPaths": [
      "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
      "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
      "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
      "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
      "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
      "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
      "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
      "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
      "FieldEvidenceApp/Features/Issues/IssueDetailView.swift",
      "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
      "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
      "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
      "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
      "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
      "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
      "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
      "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
      "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
      "FieldEvidenceApp/Features/Shell/AppShellView.swift",
      "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
      "FieldEvidenceApp/Features/Signs/NewSignView.swift",
      "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
      "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
      "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
      "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift"
    ],
    "status": "PRE_S10_PROVISIONAL_ELIGIBLE",
    "title": "English catalog normalization"
  },
  "fenceSource": {
    "cardID": "V30-P02-C01",
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
  "next": "V30-P02-C02",
  "observedCoordination": {
    "head": "4fb36879a352e3a161dcbd7c40af414a6d87e450",
    "ledgerDigest": "5c00a94e95f0e17c20f434c2c37b6c32acd138306eeaf436fe01f8f48486856f",
    "sequence": 31
  },
  "ordinal": 15,
  "outcome": "Normalize required app-owned English text into semantic keys with comments, placeholders, plurals, variations, terminology, permission/accessibility/report coverage, and explicit literal dispositions.",
  "payloadDigest": "bf666ee9da6ce094ae9f6fbe4cae6f9db3753b5212adfb2e4c9c3fcada9adfc0",
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
    "V30-P01-C08": {
      "candidate": {
        "base": "36f9c62ef09bff21c47923add3ade6469a82650e",
        "baseTree": "0f8e0553b2f3780c1f052648b16dfd9c5b8b03f8",
        "changedPaths": [
          "FieldEvidenceApp/Domain/Globalization/LocalizationCatalogReleaseContractsV1.swift",
          "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
          "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
          "FieldEvidenceApp/Infrastructure/Localization/LocalizationCatalogReleaseStoreV1.swift",
          "FieldEvidenceAppTests/Fixtures/V30/CatalogRelease/catalog-release-cases-v1.json",
          "FieldEvidenceAppTests/V30_P01_C08CatalogReleaseIntegrityTests.swift",
          "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
          "docs/design/v30/execution/V30_CI_SELECTION.json",
          "docs/design/v30/execution/V30_CURRENT_TASK.md",
          "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
          "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json"
        ],
        "head": "020c9da6df9c2d9afe741290ecab1b1893d8b2ec",
        "tree": "a7b68fe27452c186cdd9e8c6a244a39c29b5c1ff"
      },
      "sequence": 31
    }
  },
  "revision": 1,
  "selector": null,
  "selectorReason": "Windows-static provisional card; no native dispatch is selected.",
  "sourceEndLine": 994,
  "sourceStartLine": 994,
  "title": "English catalog normalization"
}
```
