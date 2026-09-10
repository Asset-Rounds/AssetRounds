# AssetRounds privacy review V1

Status: unsigned S9.1 review complete; final App Store privacy answers remain an explicit owner-provided S9.3 input.

## Built-product truth

- `PrivacyInfo.xcprivacy` is an app-target resource and declares no tracking domains, no app-developed tracking, and no collected-data types.
- The launch target contains no custom backend, account system, cloud sync, analytics SDK, advertising SDK, remote logger, or silent diagnostic uploader.
- Sign details, addresses, notes, normalized photos, snapshots, PDFs, entitlement cache, and diagnostics remain device-local unless the person explicitly exports a backup/PDF/diagnostic file or sends editable feedback through the system mail composer.
- Backup, restore, PDF, diagnostic, and feedback exports are initiated by the person and use system destination or composer surfaces. Feedback attachment consent is explicit and the reviewed diagnostic contains only bounded app/device context and local counters.
- StoreKit talks to Apple through system frameworks. The checked-in `.storekit` catalog is CI-only and does not establish production commerce or data-collection truth.
- Terms, privacy, and support links open only after an explicit tap. Their production URLs and the support address remain pending release inputs; the app fails closed while they are absent.

## Required-reason APIs

| Category | Reasons | Source-evidenced use |
|---|---|---|
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` | `StoragePreflightService` checks capacity before observable media, report, backup, restore, and generation writes. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1`, `3B52.1` | Descriptor-pinned storage validates metadata for app-container files and for backup/package destinations explicitly selected by the person. |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Erase removes app-only local defaults; no app-group or cross-app defaults are read. |

The app source does not use system-boot-time APIs. The reasons above are limited to the behaviors Apple describes for app-container metadata, user-granted document metadata, observable low-space checks, and app-only defaults. Review against Apple’s current required-reason documentation again immediately before S9.2.

## Data-boundary review

| Boundary | Result |
|---|---|
| Camera and Photos | Accepted images are normalized locally; source metadata is removed and evidence stays in the active local generation. |
| Reports and backups | Files leave the app only after an explicit Share/Files/export/restore action. The backup warning states that customer content is included and subscription state is excluded. |
| Diagnostics | Only the six-key sanitized diagnostic schema is previewed; raw logs, database rows, media, reports, backups, paths, hashes, StoreKit details, and credentials are excluded. |
| Feedback | The message is editable. Attach supplies exactly the reviewed sanitized JSON only after explicit consent; Don't Attach supplies no attachment. There is no provider, background send, or `mailto:` fallback. |
| Commerce | Direct StoreKit supplies product and signed-transaction truth. No purchase identifier or StoreKit payload is exported by app diagnostics or backups. |
| Erase | Erase clears local generations, commerce cache, diagnostics, and defaults without cancelling or synchronizing the Apple subscription. |

## Owner gates

Before TestFlight/App Store submission, the owner must validate the final archive privacy report and network behavior, provide the live privacy/terms/support pages and support email, and complete App Store Connect privacy answers from the exact tested binary. Empty collected-data declarations must be changed if the final binary or owner-operated support flow adds collection not evidenced by this source review.


## S10.6 branded candidate preparation — 2026-09-10

Status: source review prepared; unsigned S10.6 build and tests pending. Release remains blocked. The S9.1 review above is preserved as historical evidence.

The source inventory in `docs/design/s10/evidence/s10.6/privacy-supply-chain-review.json` binds 36 inspected files and the exact 12 runtime brand assets to native product E `0adebd72ae0226a80e14eaf515ca133072fb1c76`. No package references or vendored frameworks were found in that source tree. Source privacy declarations and their required-reason values are unchanged. This inventory does not establish final archive contents or runtime network behavior.

Accepted S10.4 automated evidence is K `e2189af36a89caf815cf078756341c1f1542f7df`, receipt C `0d54add4a5d09ec3b54483a1fc2a55d8eea8b0e3`. Its 469 current-profile visual approvals and 42 accessibility rows remain historical exact-E evidence. Minimum-profile verification stays owner-deferred. Physical S10.5 remains DEFERRED under the owner's development-build timing instruction; no installation or physical result has been supplied.

The store plan now identifies five unedited screenshot candidates from the accepted current Light run, with original artifact paths and PNG hashes. They are not approved store creative. The frozen 1206-by-2622 set fits Apple's 6.3-inch specification, but the required 6.5-inch set (when no 6.9-inch set is provided) is missing. [Apple screenshot specification, checked 2026-09-10](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

The accepted asset-use grant remains separate from pending dated trademark, name, claim and URL clearance. Final version/build, live pages, privacy answers, production commerce, archive privacy/supply-chain review, physical proof, final F25 evidence and all six stage receipts remain required. `s10-store-readiness.json` remains planned and `s10-evidence-lock.json` remains a template. Four stage receipts exist; neither a PhysicalExperience nor a Release receipt is manufactured by this preparation.


## Prospective S10.5 non-blocking deferral — 2026-09-10

The owner has superseded the earlier blocking treatment of S10.5. Physical verification is now a non-blocking follow-up deferred until after App Store release, with resumption only on an explicit future owner request. App Store availability does not itself schedule or authorize a test. This applies to S10.6, S10 phase completion and the expansion integration prerequisite; it does not authorize an immediate merge or main update.

S10.5 remains DEFERRED, with no fabricated installation, result, PASS or PhysicalExperience E/K/C receipt. Five real accepted stages (Inventory, ComponentSystem, Migration, AutomatedLab and Release), together with the explicit S10.5 deferral, are the prospective checkpoint requirement. Only four stages are currently accepted; Release is still pending. The nominal six-card program and original accepted evidence remain unchanged.

S10.4 minimum profiles and smoke remain indefinitely deferred and require explicit owner instruction to resume. Other store, privacy, legal, current-candidate CI and owner-only S9.2/S9.3 checks remain applicable. Release is still blocked by the remaining unprovided facts, not by S10.5. The sections above are preserved as historical preparation context.


## Verified unsigned S10.6 preparation — 2026-09-10

Original GitHub run [34527590250](https://github.com/Asset-Rounds/AssetRounds/actions/runs/34527590250) passed at exact preparation head `0a48504502994fdb8a5d73c9e8cc307aba210821`: unsigned build-for-testing, all five selected S10.6 unit tests, and the one continuous branded UI smoke. Its original artifact `10172675373` has SHA256 `49EF4F73EB8E5F7CB827EF77A0B2CCC08499425CDCE9469119D2474E4952E09D`; all 102 listed files matched their checksums. The terminal screenshot SHA256 is `2E200B14E17E1F7632F5F7CF63681FB898C658124C02D08E1CBBF69835A83A7C`. Full original commands, environment, expiry, test-result hashes and audit identity are bound in `privacy-supply-chain-review.json` under `unsigned_preparation_ci`.

The actual runner image was `macos26/20260831.0337.3`, with Xcode 26.6/17F113 and iPhone 17/iOS 26.2/23C54. Simulator UDID: `F007E22E-9AEC-4FE9-8477-78ED0F8133C7`. App and project source bytes remain identical to accepted S10.4 native E `0adebd72ae0226a80e14eaf515ca133072fb1c76`. Original earlier preparation run 34525551221 remains independently bound to `df52d7517806192b8ccff46923d1add1680ec75f` in the template evidence lock; it is not current-head evidence.

The owner separately attested ownership of the AssetRounds name on 2026-09-10 and stated that the website and URLs will be created after this work. That dated statement is bound in `owner_name_attestation`; live URLs remain pending. The statement does not supply separate trademark-clearance evidence or a review of the five store claims, and those statuses have not been promoted.

This verifies the preparation contract, including nonblocking deferred physical status. It does not validate a final five-stage evidence lock, supply a final archive/network report, approve App Store creatives or claims, perform human visual review, or close missing legal/live release inputs. The final F25 release gate remains pending. Store state remains `planned`, the lock remains `template`, Release has no checkpoint, and release readiness remains false. S10.5 and S10.4 minimum coverage remain deferred under their separate owner instructions; there is no automatic resumption.

### Scoped owner visual review — September 10, 2026

The owner `palatis3` approved the five frozen 6.3-inch store candidates and the exact I2 terminal Settings screenshot from run `34527590250`: “Yes i approve of what you sent me”. The six image hashes and dated approval are sealed in `owner-s10.6-five-store-slots-and-i2-terminal-visual-approval-20260910` (receipt SHA256 `8247DC6DBB69DF93F31AE2D785C778BC9A4A36487177EF83DE968A26945EC645`) and embedded in the S10.6 privacy/supply-chain review. This closes visual review for those exact files. Separate dated clearance and later owner release facts remain pending; an unseen later candidate screenshot requires its own review.

The owner also stated, dated September 10, 2026: “I owj the website and working on getting llc. Confirm it as if today”. The website-ownership attestation and in-progress LLC formation are bound by `owner-website-llc-attestation-20260910` (receipt SHA256 `837164D7E626B3A743A44E5C3BFB553444DB05A42444DE8EAC8A1180685A1AA5`). No domain value, completed LLC registration, or separate clearance result was supplied.

### Verified S10.6 phase-contract candidate — September 10, 2026

Original run [34536261005](https://github.com/Asset-Rounds/AssetRounds/actions/runs/34536261005) passed at exact candidate `75a8856c21e7a4aae5a8e48b40a68bdef6874d94`: unsigned build, five selected unit methods and one branded UI smoke. Artifact `10175949736` has SHA256 `F1FE86BACB1D30EAB5C24435B6D4B77F0E8BD4D9B0A5F58A50D1C3C6C85F3467`; all 102 artifact files matched their manifest. The selected tests cover actual pending evidence plus bounded synthetic ready/receipt cases; synthetic authenticated inputs do not prove external acceptance. The terminal screenshot SHA256 is `C8833192DCB2CFC5479657F6276CF7BDDE69AD216A226D274932E459F677F888` and its human review is pending.

The prior five store-image approvals and exact I2 terminal approval remain bound to their original six files. Separate dated clearance is still pending, the stage index still has four accepted predecessors, and no Release receipt or formal phase/main acceptance is claimed. Later owner archive/live/submission facts remain pending and actual release readiness remains false. The complete original commands, observed toolchain, Simulator identity and immutable result hashes are recorded in `unsigned_preparation_ci`.

### Owner approval and three-clearance waiver — September 10, 2026

The owner approved the displayed I5 Settings terminal image from run `34536261005`, SHA256 `C8833192DCB2CFC5479657F6276CF7BDDE69AD216A226D274932E459F677F888`, and directed main integration with no dated name, trademark or URL clearance prerequisite. Receipt `owner-s10.6-terminal-approval-clearance-waiver-main-integration-20260910`, SHA256 `BD23286FA03EC456B50D637E4DE11FCDAB34383A466FDFAD40F75CBAF8F365E7`, preserves the exact instruction. Those three obligations are `OWNER_WAIVED` for S10.6/main; underlying legal facts remain unprovided/NOT_CLEARED. This is not a positive legal clearance result or approval of an unseen future image.

The five unchanged store claims are supported by a dated factual review of 17 native source blobs and accepted S10.4 state/task evidence at their historical heads. Report `s10.6-five-store-claims-source-substantiation-20260910`, SHA256 `F22626D85C6A661758F0DE512C63B5B7873B7ABA9AD9040E0FC53FB1D4033C41`, includes exact claim text/state IDs, source and evidence bindings, and limitations. It supplies product-claim substantiation, not professional/legal clearance or a physical-device result.

The amended unit contract requires a fresh exact-head ordinary F25 result. Its final F25 state is therefore NOT_RUN while the previous successful I5 run and newly approved I5 image remain truthful historical evidence. Store-image approval, actual source/built privacy and twelve-asset evidence, four predecessor receipts and the physical deferral remain unchanged. Later owner-release facts stay pending and actual releaseReady remains false.
