# AssetRounds App Review checklist V1

This checklist describes the unsigned S9.1 candidate. It is not evidence of signing, upload, TestFlight installation, or App Store submission.

## Repository-derived checks

- [x] App bundle ID is `com.palatis3.fieldrecord`; unit/UI test bundle IDs are separately frozen.
- [x] Deployment target is iOS 18.0 and the current project display name is `AssetRounds`.
- [x] The sole subscription product identifier in code and the CI StoreKit fixture is `com.palatis3.fieldrecord.sub.solo.monthly.v1`.
- [x] Device data does not sync with the subscription. Backup/restore is the only cross-install data-transfer path.
- [x] Whole-sign deletion and Erase All preserve the frozen evaluation/tombstone rules; Erase does not cancel Apple billing.
- [x] Privacy manifest and source review are present; no app-developed tracking, silent upload, backend, account, analytics SDK, or advertising SDK is claimed.
- [x] The TestFlight workflow is manual-only, SHA-pinned, exact-main gated, single-upload, and inactive during S9.1.
- [x] The twelve launch-smoke categories have traceable accepted CI evidence in `LaunchSmokeEvidenceIndexV1.json`.

## Pending before owner S9.2

- [ ] Confirm Apple Account access and active Apple Developer Program membership.
- [ ] Professionally clear and freeze the final App Store title; `AssetRounds: Sign Inspection` is only the current candidate.
- [ ] Supply six-of-ten commitment evidence before activating the production subscription.
- [ ] Complete Paid Apps, banking, tax, and verified Small Business Program status.
- [ ] Configure the live monthly product/group/storefront/price, 14-day offer, 16-day paid-to-paid grace, and Family Sharing off.
- [ ] Supply the owner domain, support email, and live privacy, terms, and support HTTPS URLs.
- [ ] Create and identify the final App Store record; freeze the release marketing version and monotonically increasing build number.
- [ ] Configure the `app-store-connect` GitHub environment on a supported repository/plan posture and supply its five named credentials. Do not commit credentials.
- [ ] Confirm the Apple Developer team, a named Sandbox tester, and a physical iPhone for the owner-run gate.

## Pending before owner S9.3

- [ ] Finalize description, subtitle, keywords, categories, screenshots, subscription presentation, copyright, and localization metadata.
- [ ] Complete App Review contact/notes and any requested review instructions. The app has no account or demo-login requirement.
- [ ] Complete App Privacy, age-rating, content-rights where requested, and export-compliance answers from the exact archive and observed network behavior.
- [ ] Reconcile the final archive privacy report with `PrivacyReviewV1.md`; change claims if the binary differs.

## Physical TestFlight gate

On the exact uploaded build, verify fresh-install offline report creation, low-light camera and denial/import recovery, draft resume, PDF/Share/Files, correction, deletion, backup/restore/Erase, feasible Sandbox purchase/trial/cancel/restore/manage behavior, lapse data rights, live links, no-sync copy, VoiceOver navigation, default/largest accessibility sizes, 44-point targets, Light/Dark, Increase Contrast, Reduce Transparency, and Reduce Motion. A blocker becomes a new scoped card; never patch the already uploaded commit.
