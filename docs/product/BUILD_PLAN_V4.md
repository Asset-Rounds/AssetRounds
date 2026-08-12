# AssetRounds: Sign Inspection — Foundation & Build Plan V4

Status: **authoritative V4 launch plan**  
Product display/App Store title: **AssetRounds: Sign Inspection** — adopted; professional clearance remains an S9 release prerequisite  
Initial vertical: **illuminated sign service**  
Platform: **iPhone first, native SwiftUI**  
Launch mode: **single-user, local-first, no app account**

## 1. What V4 changes

V3 is a strong research and governance set, but it is too large to hand directly to a coding agent as a first-release build specification. Its effective surface includes 71 route/action pairs, 55 routes, 59 endpoints, 66 commands, 245 named authorities, and 76 tests. Much of that machinery protects team, guest, recipient, migration, account-deletion, claim-compiler, and future-vertical capabilities that have not earned launch scope.

V4 keeps the valuable evidence truths and removes unproven infrastructure from the launch target. The first app does one job unusually well:

> Help a sign professional complete a safe night check, save honest evidence, record visible work and rechecks, and produce a clear PDF history without losing the record.

This plan authorizes a bounded, device-local TestFlight/App Store product. It does **not** authorize hosted accounts, team sync, guest web capture, recipient links, or public claims for future verticals. The V3 files remain research references for later gated work; when they conflict with this launch plan, this V4 plan controls the first build.

Execution route: Codex authors on Windows; every Xcode build, automated test, and Simulator check runs on the pinned GitHub-hosted macOS workflow; hardware/release verification runs through TestFlight on a physical iPhone. V4's minimum deployment target is iOS 18.0; changing it requires a plan revision. “Local-first” describes app data, not the build computer. No owner-operated Mac, local Xcode, local Simulator, XcodeBuildMCP, or local signing identity is required.

## 2. Success definition

The first release succeeds when a target sign professional can, on a real iPhone:

1. Add a site and sign in under one minute.
2. Complete a two-photo after-dark check without training.
3. Record `No visible issue`, `Visible issue`, or `Could not verify` without implying diagnosis or compliance.
4. Save and reopen the report after force-quit or device restart.
5. Share a readable PDF.
6. Record work, perform a later recheck with new evidence, and preserve the earlier history.
7. Understand the subscription, trial, restore, and cancellation behavior.

The release does not need every rare edge case eliminated. It must not ship a primary-path crash, silent data loss, incorrect charge or entitlement, photo/privacy leak, false completion, broken PDF, inaccessible primary action, or unrecoverable erase/backup failure. Cosmetic and rare non-destructive defects may ship when recorded in `KNOWN_BUGS.md`.

## 3. Launch buyer and promise

### Buyer

- Primary payer/user: owner-operator or working manager at a small U.S. sign-service shop.
- Primary use moment: an after-dark illuminated-sign visit or follow-up.
- External system of record: the shop's existing CRM, job folder, email, or shared drive. V4 complements it through PDF export; it does not replace dispatch, CRM, invoicing, permitting, or electrical diagnosis.

### Plain-language promise

> Capture the right night views, record what is visibly true, and keep a professional report with the sign.

### Non-claims

The app does not prove electrical condition, code compliance, repair completion, image authenticity, astronomical darkness, safe access, external delivery, or human review. `Share` means the system share sheet opened; it never means another person received, opened, or read the report.

## 4. Scope: build, defer, and never infer

### Build now

- Fictional sample isolated from real data.
- Site and sign creation.
- Explicit site time-zone confirmation only when needed.
- Human after-dark and safe/authorized-position acknowledgements.
- Two-step photo runner: wide view, close view.
- Three honest outcomes: no visible issue, visible issue, could not verify.
- Local autosave, resume, low-storage and permission recovery.
- Immutable completed record and replace-only report correction.
- Visible issue → work record → evidence-bearing recheck.
- Chronological sign history and optional previous-report comparison.
- Local PDF generation, preview, Share, and Files export.
- One-sign/three-completed-report free evaluation.
- StoreKit 2 subscription paywall, trial, restore, manage subscription, lapse-safe read/export/delete.
- Backup/export, restore of the current V4 format, and erase all local data.
- Light/Dark appearance, Dynamic Type, VoiceOver basics, non-color status.
- In-app feedback entry and Apple-native quality/subscription analytics.

### Defer until observed demand

- App accounts, hosted sync, workspaces, team roles, invitations, assignments.
- Guest browser capture and recipient report links.
- Scheduled provider email, CSV, connectors, web dashboard, App Clip.
- Global Log tab, full-text search, recurrence, Work Plans, Night Rounds.
- Remote analytics SDKs, remote configuration, referral credits, in-app referral loops.
- AI diagnosis, automatic pass/fail, measurements, permits, estimates, invoicing, dispatch, routing.
- A public second vertical.

### Never infer

Codex may not add an adjacent feature because a framework makes it convenient. No new package, backend, account, entitlement, permission, analytics SDK, schema migration, App Store claim, or public vertical enters a task unless the active task contract names it.

## 5. Navigation and onboarding

### Navigation

Use two tabs and one settings entry:

1. **Signs** — resume card, sign list, sign detail, issue/work/recheck history, start action.
2. **Reports** — recent PDFs and filter by sign/site.
3. **Settings** — toolbar gear, not a tab.

Do not ship separate Today, Log, Work Items, or Review tabs. If real usage later shows many simultaneous signs, add a Today queue from observed needs rather than prebuilding it.

### Onboarding contract

Borrow the useful parts of high-converting consumer onboarding—one decision per screen, bold outcome copy, large choices, visible progress, and a personalized first result—without copying a long quiz or a manipulative hard paywall.

1. **Welcome**  
   Title: `Turn tonight's sign check into a clear report.`  
   Primary: **Add first sign**. Secondary: **View sample**. Returning user: **Restore data backup**. **Restore Purchases** is a separate accessible text action that restores paid access only and never implies records will return.
2. **New sign**  
   Required: customer/site name and sign name. Address is collapsed and optional. A confirmed IANA site time zone may be saved here; otherwise `Site.timeZoneID` remains null until the next screen. Primary: **Save and start check**.
3. **Ready for night check**  
   Show required time-zone selection/confirmation only when `Site.timeZoneID` is null, and persist the confirmed IANA value before draft creation. Two unchecked rows: dark enough for visible observation; safe and authorized position. Primary: **Begin check**. Secondary: **Cancel — no check started**.
4. **Capture**  
   `1 of 2 · Wide view`, then `2 of 2 · Close view`. Camera permission is requested here, not on launch. Provide Retake, Use photo, Choose from Photos, and Cannot complete.
   S3.6 may add exactly `NSCameraUsageDescription = Use the camera to add sign photos to reports stored on this iPhone.` `PhotosPicker` remains the ordinary import path and must not request broad photo-library permission.
5. **Outcome**  
   Large choices: No visible issue, Visible issue, Could not verify. Visible issue expands one short label and an optional note.
6. **Review**  
   Show thumbnails, outcome, note, and direct Edit links. **Save report** performs one atomic finalization.
7. **Value receipt**  
   `Report saved on this device.` Actions: View report, Share PDF, Done. No rating request, notification prompt, or paywall on this receipt.

Never automatically present a paywall during first-sign onboarding or on the value receipt. A paywall may appear only after an explicit attempt to use a gated action, such as adding a second concurrent sign or starting new value work after the local allowance. Contextual tips may appear beside the relevant control and may be dismissed. There is no forced slideshow, role quiz, team setup, account creation, or testimonial carousel.

## 6. Core workflow and state truth

### Check lifecycle

`draft → completed`

- Only one active draft per sign.
- Every committed field and accepted photo is saved before the runner advances.
- Force-quit resumes at the last committed step.
- Cancel before draft creation saves nothing and says `No check was started.`
- `Could not verify` completes an honest incomplete record but never creates a pass, accepted result, resolution, or billing event.

### Outcome choices

- **No visible issue** — no visible issue was recorded in the required views; not a professional certification.
- **Visible issue** — one or more visible conditions were recorded; issue label and note remain descriptive.
- **Could not verify** — reason key plus optional note; photos already captured remain attached to the incomplete record.

The post-draft `Could not verify` reason key is one of `conditions_changed`, `access_lost`, `unsafe_to_continue`, `required_view_obstructed`, `capture_unavailable`, or `other`. Preflight failures are different: if it is not dark enough, the position is unsafe/unauthorized, or a draft has not been created, the only result is Cancel with `No check was started.`

### Work and recheck

1. From a sign's open issue, **Record work** saves date, short description, optional note, and at most one optional `work_context` photo. That photo uses the pack copy `Add one optional photo showing the work performed.` It belongs only to the work record and can never satisfy a check or recheck evidence requirement.
2. Work changes the issue to **Recheck due**; it never closes the issue.
3. **Start recheck** uses the same time-context and two-photo runner with new evidence.
4. Recheck outcome: Resolved; Issue still visible; Original resolved, different visible issue; or Could not verify.
5. Resolution is based only on that recheck's saved evidence and explicit choice.
6. `Original resolved, different visible issue` atomically resolves the original issue and opens one new issue from the recheck. No outcome may leave the original issue's state implicit.

### Comparison

V4 comparison is deliberately narrow. First select the current report revision for each live `Packet.stableRootID`; correction revisions within one packet are never separate visits. Compare the current packet only with the immediately preceding distinct packet root for the same sign when that prior packet's substantive record has a strictly earlier completion instant. Use stable packet UUID as a deterministic tie-break only after filtering to distinct packet roots. If the relationship is ambiguous or either current revision lacks the required photo, omit comparison and show the chronological history instead.

### Report truth

- A completed report's source/snapshot/replacement content is immutable. Only its local PDF delivery fields may follow the bounded render-state transitions below.
- Editing a completed report creates a new report with forward-only `replacesReportID`; the prior report remains immutable in history and its replaced label is derived by the forward reference, never written back into the prior row.
- PDF bytes are generated from the snapshot, hashed, and cached. A later app or template update cannot silently rewrite history.
- PDF failure does not undo the completed record. Show **Retry report**.

## 7. Free evaluation, subscriptions, and payments

### Free evaluation

- One **concurrent live sign**. A never-paid installation may create a sign only when it has no other live `Asset` and fewer than three counted roots. Whole-sign deletion frees the concurrent sign slot, but its counted packet roots remain as non-visible tombstones. At three counted roots, deleting the sign does not permit another free sign or draft.
- Three completed report roots; corrections/replacements do not consume another slot.
- No timer and no app account.
- V4 has no individual packet/report-delete action. **Delete sign and all local history** removes one sign's complete referentially closed lineage and does not replenish the free evaluation.
- After the limit, all history remains readable, shareable, exportable, and erasable. Starting any new check, work, or recheck draft opens the paywall; an already-created draft may still be completed honestly.
- The evaluation-counted live/tombstoned Packet-root set is part of the local backup; there is no second counter or hidden usage ledger. A delete/reinstall without restoring that backup can reset the no-account evaluation; accept this bounded V1 abuse risk rather than adding fingerprinting, DeviceCheck, an account, or a backend solely to police three free reports.

| Event | Free-evaluation effect |
|---|---|
| Attempt to create a second sign while never paid | Do not create a Site/Asset/draft; show the closable monthly paywall, then return to existing history |
| Delete the only live sign before three roots, then create another | Permit one replacement live sign; retain every prior counted root tombstone |
| Attempt to create a sign when three roots are already counted | Do not create a Site/Asset/draft; show the closable monthly paywall |
| Finalize a check/recheck as no issue, visible issue, or Could not verify | Consume one report-root use exactly once at finalization, even if PDF generation later fails |
| Work record or report correction/replacement | No additional use |
| Delete sign and all local history | Delete the whole referentially closed sign lineage; retain one non-visible accounting tombstone per counted packet root; no use returns |
| Restore an older backup | Union every evaluation-counted stable root from current live packets/tombstones and restored live packets/tombstones; materialize a current-only root as a valid staged tombstone so use never decrements |
| Erase All or uninstall without restore | Reset local evaluation; do not cancel subscription; accepted bounded V1 limitation |
| Start 14-day trial | Only after StoreKit returns a verified purchased transaction, never on paywall view/tap/download |
| Former paid subscriber lapses | Do not reopen the free evaluation; existing data rights remain, an already-created draft may finish, and every new sign/check/work/recheck requires entitlement |

Whole-sign deletion uses this exact confirmation: `Delete this sign, its photos, and its reports from this app? This cannot be undone. Your free-report count will not reset. Erase All removes the remaining anonymous count.` The only actions are **Cancel** and destructive **Delete sign**. Tombstones retain only anonymous evaluation UUID/timestamp facts, never a site/sign label, address, note, photo, snapshot, or PDF.

### Pilot offer

The frozen V3 `$79/month for 25 accepted reports` offer remains a **separate historical research contract**, not a V4 TestFlight payment path and not a customer-facing V4 limit. TestFlight always uses Apple's sandbox commerce environment: a sandbox transaction never creates real revenue, never proves willingness to pay, and never enters the paid cohort. If the owner completes that V3 study, follow its lawful frozen route and keep its evidence isolated. It cannot validate V4.

V4 uses two clean steps. First, six of ten qualified shops sign the exact cancellable `$59.99/month, unlimited-local, one-purchaser, no-sync` commitment after seeing a real-job result; this is an **unpaid exact-offer commitment gate** that authorizes creation/activation of the monthly SKU and is never scored as payment. Second, actual paid evidence comes only from the monthly production StoreKit product during a low-marketing U.S. soft launch. Broad promotion waits until at least seven qualified subscribers have a settled, non-refunded first charge and renew once without selective discounts, no commerce release blocker exists, and the three-cycle contribution gate below passes. The cohort manifest freezes app version, product ID, one-month duration, `$59.99` U.S. base price, U.S. storefront, 14-day-trial eligibility, acquisition window, feature terms, exclusions, and refund cutoff before recruitment.

S7 coding is not blocked on the commitment study, Paid Apps Agreement, bank/tax setup, or a live App Store product. It uses the owner-frozen monthly product identifier in a checked-in local `.storekit` configuration and StoreKit Test/Sandbox fixtures. The six-of-ten gate controls production App Store Connect SKU creation/activation and production offer launch, not local implementation. Paid Apps, bank/tax, signing, and live product state are owner gates before the protected TestFlight/App Store route; none is required for unsigned Simulator CI.

Because V4 has no account or backend, use a consented manual paid-cohort ledger rather than pretending App Store aggregates identify a shop. Give each recruited shop a random roster ID. At first charge and renewal, retain an owner-reviewed subscription-status/purchase-history proof and, when the participant chooses, a dated diagnostic export; the commerce proof records product ID, app version, storefront, verified state/expiration, while the separate export contains only the counters permitted below. Reconcile cohort totals to App Store Payments and Financial Reports. A shop is a `qualified subscriber` only when roster eligibility, verified commerce proof, and aggregate reconciliation pass. Diagnostic counters are optional corroborating lower bounds: a positive value may support repeat-use evidence, while zero/absence never disproves use and never grants cohort/payment status. Day-30/60/90 evidence uses the same roster IDs and predeclared proof/checkpoints; later corrections are append-only. The contribution gate uses three consecutive **closed Apple fiscal months**, not rolling partial windows.

### Public App Store subscription configuration

Code one subscription group and read every localized name, duration, price, and eligibility value from StoreKit—never hardcode price copy.

- Subscription-group reference name: `FIELD_RECORD_SOLO_ACCESS_V1`; record the separate Apple-assigned group identifier when App Store Connect creates it. V4 initially loads the explicit monthly product ID rather than guessing a group ID.
- Localized subscription-group display name: `Solo Access`; App Name Display Option: `Use App Name` for the adopted app title `AssetRounds: Sign Inspection`. Do not submit the group until that title passes the existing S9 name-clearance gate.
- Monthly product: `<owner.reverse.domain>.fieldrecord.sub.solo.monthly.v1`.
- Monthly product reference name: `FIELD_RECORD_SOLO_MONTHLY_V1`; duration: **one month**; U.S. base-price intent: **$59.99** at the Apple price point selected in App Store Connect. Runtime UI still renders StoreKit's localized value.
- Recommended starting monthly hypothesis after the fresh unlimited-local **six-of-ten signed exact-offer commitment gate** passes: **$59.99/month**. This is a new, local-only offer; the V3 `$79/25` pilot cannot validate it. Paid-evidence status begins only after a settled production StoreKit charge.
- Future research may test a **$599.99/year** hypothesis after monthly day-90 retention and actual-cost evidence. V4 creates no annual product, ID, UI, enum, fixture, or annual-specific code. The monthly reducer simply reads StoreKit-provided product duration/price rather than assuming a hard-coded period.
- Introductory offer: **14 days free**, eligible once per subscription group.
- A 3-day trial is supported by Apple but is not the default: after-dark work may not occur within 72 hours, and current close competitors commonly offer 14 days. Test 3 days later only with enough traffic and a predeclared conversion/retention rule.

Included ongoing value: unlimited local signs, checks, rechecks, and report generation for the purchaser; local history and comparison; maintained sign templates/report capabilities; compatibility updates; and continued product support. Existing records remain available after lapse.

The StoreKit entitlement is restorable on the purchaser's Apple devices; the inspection database and photos are **device-local and do not sync**. State that distinction on the paywall and in Settings. Moving data to another device requires an explicit backup/export and restore until a separately approved sync product exists.

### Required purchase states

- Products loading; unavailable with retry.
- Eligible trial and ineligible standard price.
- Purchasing, user-cancelled, pending approval, verified success, unverified failure.
- Active, grace period, billing retry, expired, refunded/revoked.
- Restore Purchases.
- Manage Subscription.
- Offline: honor the last locally verified signed transaction only through its StoreKit expiration/revocation facts; do not invent a second grace timer. Refresh when network returns and never hide existing customer data.

Use `SubscriptionStoreView(productIDs:)` with only the monthly ID, verified `Transaction.currentEntitlements`, `Product.SubscriptionInfo.status`, verified renewal information, `Transaction.updates`, and subscription-status updates. Finish a verified transaction only after its local entitlement update is durably processed. `AppStore.sync()` runs only after an explicit **Restore Purchases** tap; ordinary startup reads StoreKit state. Use the system manage-subscription sheet. The app must use StoreKit In-App Purchase for its digital unlock. Do not add Stripe, web checkout, license keys, or an external-purchase link to the launch app.

S7.3 explicitly activates the separate **Restore Purchases** action on Welcome and in Settings. Both routes use the same explicit-sync coordinator and exact state UI; neither route mentions data recovery, and the Welcome **Restore data backup** action remains visually and semantically separate.

`EntitlementReducerV1` accepts only verified transaction, subscription-status, and renewal-info values for the exact monthly product. It outputs only `loading`, `entitled(active, until)`, `entitled(grace, until)`, `never_paid`, or `former_paid_inactive(reason=billing_retry|expired|refunded|revoked)`. A verified revocation/refund is inactive immediately; active trial/subscription and auto-renew-off remain entitled through the signed expiration; signed grace remains entitled only through its grace expiration; billing retry outside grace and expiration are inactive. When more than one verified status exists, select the latest product transaction by purchase instant, then expiration, and fail closed on an unresolved tie; never combine authority across products. Pending/unverified purchase results do not overwrite a still-valid verified cache. Offline cache grants access only through its recorded signed expiration/grace facts and never invents time. Any verified purchased transaction, including an introductory trial, makes `hasEverVerifiedPaid=true` before `finish()`; that flag never becomes false except Erase All/uninstall. Ordinary launch reads current facts without `AppStore.sync()`.

| Verified StoreKit state | New draft authority | Existing data/work |
|---|---|---|
| `subscribed` or active trial, including auto-renew off before expiration | Allow new signs/checks/work/rechecks through signed expiration | Allow all |
| `inGracePeriod` | Allow new signs/checks/work/rechecks through Apple's signed grace expiration | Allow all |
| purchase pending or unverified, never previously paid | Does not unlock; the remaining never-paid concurrent-sign/three-root evaluation still applies | Keep history/data rights |
| purchase pending or unverified, previously paid | Do not create a sign or draft until verified current authority exists | Keep history/data rights and allow an existing draft to finish |
| `inBillingRetryPeriod` outside grace, `expired`, `revoked`, or refunded | Block every new sign/check/work/recheck | Allow read/share/export/backup/whole-sign delete/erase, PDF retry/correction, and completion of a validated existing draft |

Enable Apple's **16-day Billing Grace Period for paid-to-paid renewals only** in sandbox and production. Family Sharing remains off. A cancelled auto-renewal stays active through its verified expiration; copy says `Active until` rather than implying immediate loss.

The paywall acceptance fixture must show the localized monthly product name, duration, full renewal price, `14 days free` when StoreKit says the purchaser is eligible, exact post-trial price/renewal disclosure, unlimited-local inclusion, device-local/no-sync boundary, Restore Purchases, Manage Subscription, Terms, Privacy, and a visible close-to-history action. Do not show annual savings or an annual product in V4.

Evaluation accounting is installation-scoped and monotonic between Erase All operations: completed check/recheck roots with `No visible issue`, `Visible issue`, or `Could not verify` each consume one of the three; work records and report corrections do not; PDF failure does not refund a finalized root; ordinary content/sign deletion does not decrement counted roots. Backup restore unions every current/restored `evaluationCounted=true` stable root whether it is live or tombstoned, so an older replacement backup cannot decrement use. User backup never restores entitlement. After any verified paid transaction exists, a lapse does not reopen the three-report evaluation; StoreKit remains the purchase-history authority.

One pure `DraftAccessPolicy` consumes a normalized access state (`loading`, `entitled`, `never_paid`, or `former_paid_inactive`), `liveAssetCount`, the set of live+tombstoned counted-root IDs, requested entry (`create_sign|check|work|recheck`), and an optional **repository-validated** existing draft. Its precedence is fixed: a valid existing draft returns `continue_existing`; current entitlement returns `allow`; former-paid inactive returns `block_paid`; never-paid returns `allow` only for the concurrent-sign/three-root rules above. `loading` first preserves a still-valid verified cache; when prior-paid status is known and no cache remains valid it returns `wait_for_store`; when no cache exists and `hasEverVerifiedPaid=false`, it applies the never-paid local evaluation so a fresh installation can complete its first report offline. A caller-supplied UUID never bypasses policy: the repository must prove that the draft exists, belongs to the requested sign/issue, was created before the current gate check, and is being continued rather than cloned. Corrections, read, preview, share, Files export, backup, whole-sign delete, and Erase All never call this policy.

### Price truth

$79 is market-familiar—CompanyCam Core and ServiceM8 Growing currently sit near that level—but those products include broader cloud/team/job-management value, while SignTracker is about $65 for 1–2 users. The recommended **$59.99 unlimited-local** hypothesis keeps a premium position below those broader offers; buyer willingness to pay is still unproven. It requires the signed exact-offer commitment gate and then separate production payment/renewal evidence. App Store prices can change in App Store Connect without a code change because the interface renders StoreKit values.

Before broad promotion, compute three complete monthly cycles from App Store Payments and Financial Reports. `TaxExclusiveCollectedBillings` is customer billings excluding sales tax; `SettledTaxNetProceeds` is Apple's settled proceeds after commission, refunds, and adjustments. Do not subtract a refund twice. `ContributionMargin = (SettledTaxNetProceeds - variable support labor at the frozen loaded hourly rate - incremental vendor/processing cost) / TaxExclusiveCollectedBillings`. Target at least 60% for all three cycles with at least seven renewing qualified shops; fixed development cost remains separate. Treat the standard 30% commission as the downside until Small Business Program enrollment and its effective date are verified. If the actual route cannot pass, stop and reprice/re-scope through a new offer rather than hiding the miss.

## 8. Premium, field-readable visual system

Color does not create conversion by itself. Research treats color effects as context-dependent, and Apple requires contrast, semantic roles, and both appearances. Premium perception here comes from restraint, consistent hierarchy, excellent photography, fast interaction, and honest state language.

### Direction: Worklight Precision

- Graphite and warm-neutral surfaces feel like a modern field instrument rather than a generic contractor dashboard.
- Teal is the interaction accent because it remains distinguishable from the red, amber, and green state system.
- Amber is reserved for attention and after-dark requirements; green for saved/resolved; red for destructive/error. None is used as the sole signal.
- Surfaces use quiet off-white or near-black, not gradients, neon decoration, glossy pseudo-metal, or dense dashboards.

### Semantic tokens

| Role | Light | Dark |
|---|---|---|
| Canvas | `#F3F5F6` | `#0B1114` |
| Surface | `#FFFFFF` | `#131B1F` |
| Raised surface | `#FFFFFF` | `#1A252A` |
| Primary text | `#11181C` | `#F5F7F8` |
| Secondary text | `#47565D` | `#B7C1C6` |
| Tertiary text | `#617077` | `#8F9DA4` |
| Interaction accent | `#006D75` | `#57CDD0` |
| On accent | `#FFFFFF` | `#071B1D` |
| Accent container | `#D8F1F2` | `#173B3E` |
| On accent container | `#0B4E53` | `#9DEBED` |
| Essential control stroke | `#74838A` | `#6B7D85` |
| Complete | `#125E39` on `#E2F3EA` | `#80E0AE` on `#153B2A` |
| Attention/after-dark | `#7A4300` on `#FFF0D6` | `#FFD08A` on `#402D12` |
| Blocked/destructive | `#8A1C14` on `#FDE7E5` | `#FFAEA5` on `#441E1C` |
| Information | `#164E8C` on `#E4EFFC` | `#A4CDFF` on `#193653` |

Verified examples include primary text/canvas at 16.39:1 light and 17.69:1 dark, secondary text/canvas at 6.96:1 light and 10.37:1 dark, primary buttons at 6.10:1 light and 9.34:1 dark, essential control strokes at 3.59:1 or better against light canvas and 3.65:1 or better against dark raised surfaces, and every status text/container pair at 6.79:1 or better. Implement tokens as named Color Sets with light, dark, and increased-contrast variants. Prefer Apple semantic background/label/separator colors when a custom token adds no information.

### Typography, spacing, and components

- All screens consume semantic tokens from one asset catalog/`DesignTokens` layer; feature code contains no raw hex values.
- The sign launch uses the exact Worklight Precision token set. A later vertical may replace only its accent pair, terminology, reference imagery, and pack content after contrast/release gates; status colors, type scale, spacing, evidence treatment, billing, privacy, and destructive patterns remain global.
- SF Pro through semantic Dynamic Type styles; no bundled display font in V4.
- Layout and text support every system Dynamic Type category; required actions may reflow/scroll but never clip or disappear. S8.2 exercises default and largest accessibility layouts in CI, and owner S9.2 repeats them on the physical-iPhone golden flow rather than claiming a full device matrix.
- 8-point spacing rhythm; 16-point card padding; 12-point standard corner radius.
- Minimum 44×44-point controls; full-width primary buttons in onboarding/runner.
- One primary action per screen. Secondary actions are text or bordered controls.
- Use SF Symbols with text for critical actions and states.
- Motion only explains save, step change, and replacement continuity; honor Reduce Motion.
- Increase Contrast strengthens token variants; Reduce Transparency makes any system-material navigation opaque; Reduce Motion replaces custom movement with opacity. VoiceOver announces selected choice, step progress, validation error, save completion, and the next actionable focus target.
- Never crop evidence deceptively. Preserve aspect ratio, timestamp, purpose, and source record.
- Respect system Light/Dark Mode rather than adding an app-specific appearance switch.
- Keep evidence and form surfaces opaque. System navigation/toolbars may use the platform material; theme color must never tint or filter evidence photos.

## 9. Smallest reusable architecture

### Technology

- SwiftUI.
- SwiftData for local structured data.
- PhotosUI plus a small camera adapter.
- Actor-isolated media file store in Application Support.
- PDFKit/Core Graphics deterministic renderer.
- StoreKit 2.
- UserNotifications only when a reminder task is separately authorized.
- OSLog, MetricKit, and App Store Connect web analytics/diagnostics; no third-party SDK at launch.

No command bus, generated schema registry, dynamic workflow DSL, policy compiler, remote configuration, generic form builder, or backend abstraction is required for V4.

### Persistent models

V4 has exactly **seven** SwiftData models. Every model has `schemaVersion=1`, a stable lowercase-canonical UUID `id`, and the exact camel-case property names below. There is no `Observation` model, observation array, generic answer value, or hidden form schema in V4.

1. `Site` — `id`, `schemaVersion`, `label`, nullable `address`, nullable `timeZoneID` (confirmed IANA value), `createdAt`, `updatedAt`.
2. `Asset` — `id`, `schemaVersion`, `siteID`, `packID`, `packSchemaVersion`, `packContentVersion`, `label`, `createdAt`, `updatedAt`.
3. `WorkflowRecord` — `id`, `schemaVersion`, `assetID`, nullable `packetID`, nullable `issueID`, nullable `parentRecordID`, immutable `recordRevisionRootID`, nullable `revisesRecordID`, nullable `evidenceSourceRecordID`, `revisionKind=original|clerical_correction`, `stage=check|work|recheck`, `state=draft|completed`, nullable `draftStepKey=wide|close|outcome|review`, `startedAt`, nullable `completedAt`, nullable frozen time fields `observedAtUTC`, `timeZoneID`, `utcOffsetMinutes`, `localDate`, `localTime`, `afterDarkAcknowledgementKey`, `afterDarkAcknowledgementCopy`, `afterDarkAcknowledgementVersion`, `afterDarkAcknowledgementAccepted`, `safePositionAcknowledgementKey`, `safePositionAcknowledgementCopy`, `safePositionAcknowledgementVersion`, `safePositionAcknowledgementAccepted`, `packID`, `packSchemaVersion`, `packContentVersion`, `pdfTemplateID`, `pdfTemplateVersion`, nullable `outcomeKey`, nullable `couldNotVerifyKey`, nullable `couldNotVerifyDisplaySnapshot`, nullable `couldNotVerifyRegistryVersion`, nullable `workPerformedLocalDate`, nullable `workDescription`, nullable `note`, and nullable unique `finalizationMutationID`. `pdfTemplateID/version` are always `field.evidence.pdf.worklight.v1/1`. All eight acknowledgement fields are nullable as a group for work and nonnull as a group for check/recheck.
4. `EvidenceFile` — `id`, `schemaVersion`, `recordID`, `purposeKey`, `relativePath`, `mimeType`, `byteCount`, `sha256`, `createdAt`, `thumbnailRelativePath`, `thumbnailByteCount`, `thumbnailSHA256`.
5. `Issue` — `id`, `schemaVersion`, `assetID`, `openedByRecordID`, immutable `labelKey`, immutable `labelDisplaySnapshot`, `status=open|recheck_due|resolved`, nullable `resolvedByRecordID`, `createdAt`, `updatedAt`.
6. `Packet` — `id`, `schemaVersion`, unique immutable `stableRootID`, nullable `currentRecordID`, `evaluationCounted`, nullable `contentDeletedAt`, `createdAt`. A live packet has `currentRecordID != null` and `contentDeletedAt == null`. A whole-sign-deletion tombstone has `currentRecordID == null`, `contentDeletedAt != null`, and retains only its packet ID/schema, stable root, evaluation flag, and created/deleted instants; it has no surviving Asset relationship.
7. `Report` — `id`, `schemaVersion`, `packetID`, `sourceRecordID`, `snapshotSchemaVersion`, immutable `snapshotRelativePath`, immutable `snapshotSHA256`, `pdfState=pending|ready|failed`, nullable `pdfRelativePath`, nullable `pdfSHA256`, `createdAt`, nullable forward-only `replacesReportID`. Source, snapshot, packet, creation, and replacement fields never mutate. Allowed delivery mutations are only `pending→ready|failed`, `failed→pending` after explicit Retry, then `pending→ready|failed`; `ready` is terminal. `ready` requires path, hash, and matching bytes. `pending`/`failed` require null PDF path/hash. Reverse replacement status is derived; no prior Report row is changed.

`WorkflowRecord` invariants are closed. A draft has `completedAt`, `outcomeKey`, `finalizationMutationID`, and `packetID` null. A completed record has a unique mutation ID and nonnull completion/outcome. Original records have `recordRevisionRootID == id`, `revisesRecordID == null`, and `evidenceSourceRecordID == null`. A check has `parentRecordID == null`; its `issueID` remains null unless its completed visible-issue outcome opens that issue. A completed check/recheck has a Packet; work never has one. A **completed** work record requires an Issue, `outcomeKey=work_recorded`, nonnull ISO local date and trimmed 1–160-character `workDescription`, optional trimmed 1–1000-character note, null preflight/CNV fields, and zero/one work photo; a work draft may leave outcome/date/description null until Save. Recheck requires an Issue and the exact lineage parent below. Check/recheck require both accepted acknowledgement snapshots and complete frozen time fields. Their raw outcomes are exactly `no_visible_issue|visible_issue|could_not_verify` for check and `resolved|issue_still_visible|original_resolved_different_issue|could_not_verify` for recheck. The three CNV fields are all nonnull only when outcome is `could_not_verify`, and all null otherwise. Work fields are both null outside work. Any nonnull note is trimmed and 1–1000 characters.

Issue lineage is one closed parent chain. Work may start only from an `open` Issue and sets `parentRecordID` to that Issue chain's latest completed substantive record. Recheck may start only from a `recheck_due` Issue and sets `parentRecordID` to that chain's latest completed substantive record, which is normally its work record and may be a prior CNV recheck. A completed child must have the same `assetID` and `issueID` as its parent except that `original_resolved_different_issue` may additionally open the one new Issue described below. `beginOrResumeDraft(assetID:requestedStage:issueID:)` first returns the Asset's sole existing draft, regardless of the newly requested route, so the UI resumes that draft instead of cloning it; only when none exists may it validate the requested stage/Issue state and create a new draft. Relationship validation and backup import enforce this exact chain.

A clerical correction is a completed check/recheck revision under the same packet/root. It may change only `note`; `revisesRecordID` points to the immediately prior current revision and `evidenceSourceRecordID` points directly to the original evidence-owning record across every correction generation. Stage, outcome, issue linkage, time/acknowledgements, work/CNV facts, pack/PDF-template versions, and evidence are copied exactly. It creates no EvidenceFile and cannot open, resolve, relabel, or replace an Issue. A substantive error requires a new recheck.

### Exact `ReportSnapshotV1`

`ReportSnapshotV1` is a closed Codable wire DTO, not a SwiftData model. It contains exactly these lexicographically encoded top-level keys; arrays are never null:

```text
acknowledgements : [AcknowledgementSnapshotV1]   // exactly two
asset             : AssetSnapshotV1
couldNotVerify    : CouldNotVerifySnapshotV1 | null
disclaimer        : String
display           : DisplaySnapshotV1
evidence          : [EvidenceSnapshotV1]
evidenceSourceRecordID : UUID string
history           : [HistoryEntrySnapshotV1]
issues            : [IssueSnapshotV1]
note              : String | null
outcome           : String
pack              : PackSnapshotV1
packetID          : UUID string
pdfTemplate       : PDFTemplateReferenceV1
reportID          : UUID string
site              : SiteSnapshotV1
snapshotCreatedAt : UTC instant string
snapshotSchemaVersion : 1
sourceApp         : SourceAppSnapshotV1
sourceRecordID    : UUID string
stableRootID      : UUID string
stage             : "check" | "recheck"
timeContext       : TimeContextSnapshotV1
```

Nested DTO keys are also exact:

- `AcknowledgementSnapshotV1 = {accepted: Bool, copy: String, key: String, version: String}`.
- `AssetSnapshotV1 = {label: String}`.
- `CouldNotVerifySnapshotV1 = {display: String, key: String, registryVersion: String}`.
- `DisplaySnapshotV1 = {assetSingular: String, checkSingular: String, issueSingular: String, outcome: String, stage: String}`. These are the exact PDF-visible strings resolved from the frozen pack/global outcome registry at finalization.
- `EvidenceSnapshotV1 = {byteCount: Int, createdAt: UTC instant, evidenceID: UUID, mimeType: "image/jpeg", purposeDisplay: String, purposeKey: String, recordID: UUID, relativePath: String, sha256: lowercase hex, thumbnailByteCount: Int, thumbnailRelativePath: String, thumbnailSHA256: lowercase hex}`.
- `HistoryEntrySnapshotV1 = {completedAt: UTC instant, couldNotVerify: CouldNotVerifySnapshotV1|null, evidenceIDs: [UUID], issueIDs: [UUID], note: String|null, outcome: String, outcomeDisplay: String, recordID: UUID, stage: "check"|"work"|"recheck", stageDisplay: String, workDescription: String|null, workPerformedLocalDate: "YYYY-MM-DD"|null}`. Both display fields freeze the exact pack/global-registry text for that historical record.
- `IssueSnapshotV1 = {createdAt: UTC instant, display: String, issueID: UUID, key: String, openedByRecordID: UUID, resolvedByRecordID: UUID|null, status: "open"|"recheck_due"|"resolved", updatedAt: UTC instant}`.
- `PackSnapshotV1 = {contentVersion: Int, id: String, schemaVersion: Int}`.
- `PDFTemplateReferenceV1 = {id: "field.evidence.pdf.worklight.v1", version: 1}`.
- `SiteSnapshotV1 = {address: String|null, label: String}`.
- `SourceAppSnapshotV1 = {build: String, version: String}`.
- `TimeContextSnapshotV1 = {localDate: "YYYY-MM-DD", localTime: "HH:mm:ss", observedAtUTC: UTC instant, timeZoneID: IANA String, utcOffsetMinutes: Int}`.

The acknowledgement array is always `[after_dark, safe_authorized_position]` in that order and both entries have `accepted=true`. `evidenceSourceRecordID` is always the effective evidence owner: `sourceRecord.evidenceSourceRecordID ?? sourceRecord.id`. Current evidence means only entries whose `recordID` equals that exact value; a missing current purpose is shown as missing and can never fall back to history. `issues` contains every issue reached by applying the effective source record's parent chain through that record, with status/resolution reconstructed at that cutoff rather than read from later mutable rows, and sorts by `createdAt`, then `issueID`.

When an issue exists, `history` contains only completed substantive original check/work/recheck ancestors that are **strictly earlier than** `evidenceSourceRecordID` in that parent chain; it excludes the current effective source and every clerical correction, then sorts by `completedAt`, then `recordID`. Otherwise it is empty. Each entry freezes `stageDisplay` and `outcomeDisplay`; render-time raw-key presentation or pack/registry lookup is forbidden. Each history `issueIDs` array is unique lowercase UUID order. Each history `evidenceIDs` array uses purpose order `wide_context`, `close_detail`, `work_context`, then evidence UUID. `evidence` contains every referenced immutable EvidenceFile exactly once: effective-source evidence first in purpose/UUID order, then previously unseen history evidence in history/purpose/UUID order. A top-level CNV object is nonnull only for a CNV outcome. Issue/history/work optionals use explicit JSON null.

A clerical correction builds from the immediately prior current Report snapshot, not from today's mutable Site/Asset/Issue rows. It may change only `reportID`, `sourceRecordID`, `snapshotCreatedAt`, `sourceApp`, and `note`; packet/root, effective evidence source, stage/outcome/display copy, acknowledgements/time, pack/template, evidence, history, issues, and disclaimer are byte-for-byte semantic copies before canonical re-encoding. This prevents later work or label edits from leaking into a note-only correction.

Canonical bytes are UTF-8, NFC-normalized text with LF line endings, no BOM, indentation, trailing whitespace, or trailing newline. Object keys are lexicographically sorted at every level; `/` is not escaped; only JSON-required control/quote/backslash escaping is allowed. UUIDs are lowercase canonical strings. UTC instants are RFC 3339 with exactly three fractional digits and `Z`; integers have no leading plus/zero padding; booleans are lowercase JSON literals; there are no floating-point fields. Every optional key is emitted with JSON null rather than omitted. A checked-in golden fixture plus expected SHA-256 is the encoder authority. The snapshot SHA-256 covers these exact bytes and is stored only on `Report`, never inside the snapshot.

`SnapshotValidatorV1` must recompute the canonical hash and match `Report.snapshotSHA256`; match report/packet/source/effective-evidence/root/template/pack relations; reject duplicate references; prove every relative path stays under the current data generation; and match each original and thumbnail ID, purpose/display, record, MIME, byte count, hash, and decoded canonical JPEG to its `EvidenceFile` and actual bytes. It also proves that current PDF evidence is exactly the set whose `recordID == evidenceSourceRecordID` and that history excludes that record. S4 receives only a validated snapshot plus its computed digest. It never looks up mutable labels, notes, time zones, pack copy, or issue display text during rendering.

### Exact `PDFTemplateV1`

`PDFTemplateV1` is `id=field.evidence.pdf.worklight.v1`, `version=1`. Every snapshot stores that reference, and the renderer fails closed on an unknown version. Coordinates use the Core Graphics lower-left origin on a U.S. Letter page `CGRect(x:0,y:0,width:612,height:792)`. The white content geometry is exact: outer margin 42 points; content rect `x=42,y=72,width=528,height=678`; footer rect `x=42,y=42,width=528,height=18`; and a 12-point clear gap between footer and content. Nothing may draw outside those rectangles. The print accent is `#006D75`; primary text is black; every status includes plain text and never relies on color.

The renderer uses only PDF built-in fonts: title Helvetica-Bold 22 with 27-point line height; section Helvetica-Bold 15 with 18-point line height; body Helvetica 10 with 14-point line height; caption Helvetica 8 with 11-point line height; footer Courier 7 with 9-point line height. Vertical spacing is 18 points after the title block, 12 before a section, 6 after a section heading, 6 between ordinary blocks, and 4 between an image and its label. Text wraps with Core Text inside the 528-point content width. A heading moves to the next page unless it can keep two following body lines. A paragraph may split only on a line boundary with at least two lines on each page when it has four or more lines. A history row never splits; its bounded geometry therefore always fits one page. Pagination is calculated in a deterministic first pass and drawn in a second pass.

Current evidence is selected only where `EvidenceSnapshotV1.recordID == ReportSnapshotV1.evidenceSourceRecordID`. Current originals use an aspect-fit box no larger than `528×288`; history uses only the validated thumbnails in up to three `160×120` aspect-fit boxes on one row with 12-point gaps. Images are never cropped, tinted, filtered, or upscaled; each image stays with its `purposeDisplay` and frozen `createdAt` caption. If a required current purpose is absent for CNV, render `Not captured — Could not verify`; never substitute a history image. A block that cannot fit moves to a new page before drawing. The two-line footer appears on every page: left side contains snapshot-created time and app/pack/template versions plus snapshot SHA-256; right side contains `Page n of N`.

Render order is identity/time using frozen display nouns; current `wide_context`; current `close_detail`; frozen stage/outcome/CNV/note; issues and strictly earlier chronological work/recheck history with referenced thumbnails; exact disclaimer; then the per-page footer. Formatting uses `en_US_POSIX`, Gregorian calendar, and the snapshot's already-frozen local/UTC strings—never the current locale, clock, zone, database, or pack lookup. PDF metadata uses snapshot-created time for creation/modification, fixed creator `FieldEvidenceApp PDFTemplateV1`, and no author/subject/keywords. The PDF SHA-256 is stored as Report metadata and never embedded in its own bytes. Byte identity is required for the same validated snapshot on the pinned OS/Xcode/renderer; cross-OS byte identity is not claimed. A ready PDF is immutable. Startup renders pending reports; a restored failed report stays failed until explicit Retry. Later app versions retain the V1 renderer for pending/failed historical regeneration.

Internal identifiers remain brand- and vertical-neutral. The adopted display name, sign terminology, and marketing words must never enter bundle IDs, database column names, file paths, analytics keys, or StoreKit entitlement names.

### Bundled vertical pack

Ship one immutable `IlluminatedSignPack` manifest in the app bundle. It may define:

- `schemaVersion`, `packID`, `contentVersion`, and neutral workflow key.
- Singular/plural display nouns and instructional copy keys.
- Closed issue-label and could-not-verify reason-key registries.
- Evidence purposes `wide_context`, `close_detail`, and optional work-only `work_context`, each with one short immutable display label and one instruction. A substantive completed check/recheck requires `wide_context` and `close_detail` exactly once and forbids `work_context`. A Could-not-verify check/recheck permits zero or one of each already-captured required purpose, never duplicates, and is labeled incomplete rather than evidence-complete. A work record permits zero or one `work_context` and cannot carry either check/recheck purpose.
- Time-context semantic key, acknowledgement copy/version, and exact non-certification disclaimer.

The manifest is a bundled, immutable, Codable value validated at launch; an unknown key/version fails the sample/runner closed and never guesses copy or requirements. It may not define navigation, PDF layout/section order, permissions, commands, persistence types, or arbitrary executable code. S1 owns the minimal sign manifest and loader; S3 consumes it in the runner and freezes every PDF-visible noun/label/copy into `ReportSnapshotV1`; S4 renders the validated snapshot with no pack lookup. S8 adds only one nonshipping exterior-light fixture and the zero-new-branch assertion. Do not build a pack marketplace, historical pack registry, or remote compiler.

### Exact `IlluminatedSignPack@1`

- `packID = field.evidence.illuminated_sign.v1`; `schemaVersion = 1`; `contentVersion = 1`; nouns are `sign/signs`, `check/checks`, `visible issue/visible issues`.
- Wide purpose key/display/instruction: `wide_context` / `Wide view` / `Take one wide photo showing the full sign and its surroundings.`
- Close purpose key/display/instruction: `close_detail` / `Close view` / `Take one close photo showing the sign face clearly.`
- Optional work purpose key/display/instruction: `work_context` / `Work photo` / `Add one optional photo showing the work performed.`
- Preflight acknowledgements: `after_dark` / `It is dark enough to observe the sign's visible illumination.` / `preflight.ack.en-US.v1`, then `safe_authorized_position` / `I am in a safe, authorized position to take these photos.` / `preflight.ack.en-US.v1`. Both must be checked before **Begin check** and persist in that exact order.
- Issue-label registry: `dark_section` → `Section appears dark`; `dim_or_uneven` → `Illumination appears dim or uneven`; `flicker_or_intermittent` → `Flicker or intermittent light`; `color_mismatch` → `Visible color mismatch`; `physical_damage` → `Visible physical damage`; `other_visible_condition` → `Other visible condition`.
- Could-not-verify registry version `cnv.reason.en-US.v1`: `conditions_changed` → `Conditions changed`; `access_lost` → `I lost safe access`; `unsafe_to_continue` → `It became unsafe to continue`; `required_view_obstructed` → `Required view is blocked`; `capture_unavailable` → `Camera or photo capture is unavailable`; `other` → `Another reason`. Persist the key, exact display snapshot, and version.
- Frozen stage displays are `check` → `Check` and `recheck` → `Recheck`. Frozen outcome displays are `no_visible_issue` → `No visible issue`; `visible_issue` → `Visible issue`; `could_not_verify` → `Could not verify`; `resolved` → `Resolved`; `issue_still_visible` → `Issue still visible`; and `original_resolved_different_issue` → `Original resolved, different visible issue`.
- Non-certification disclaimer: `This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification.`
- **Begin check** atomically creates the draft and frozen time-context snapshot. Before that commit, Cancel creates no record. After it, **Cannot complete** opens only the bounded Could-not-verify reason flow and preserves accepted photos.

| Final choice | Required state effect |
|---|---|
| Check · No visible issue | Finalize record/packet/report with no Issue; never claim certification |
| Check · Visible issue | Finalize and open exactly one Issue with selected key + display snapshot |
| Check/recheck · Could not verify | Finalize honest incomplete record; never open/resolve/pass; consumes one finalized evaluation root |
| Recheck · Resolved | Resolve the original Issue with this recheck ID |
| Recheck · Issue still visible | Return original Issue to `open`; do not create another Issue |
| Recheck · Original resolved, different visible issue | Require a newly selected closed-registry issue-label key and exact display snapshot; resolve original and open exactly one new Issue UUID in one finalization transaction (the category key may match, but the issue lineage is new) |

A recheck Could-not-verify result leaves the original Issue in `recheck_due`; it never changes the issue to open/resolved and never creates another Issue. A report correction points to the new clerical-correction WorkflowRecord, creates a replacement snapshot/PDF, and leaves the prior record/report readable. The PDF footer carries the immutable **report snapshot SHA-256**; the separately stored PDF SHA-256 is metadata and is never embedded into its own bytes.

## 10. Storage, crash consistency, and one-off bug prevention

These are implementation requirements, not optional polish:

1. Store relative media paths, never absolute sandbox URLs.
2. Write one accepted original+thumbnail pair as `.staging/evidence/<evidence-id>/{original.jpg,thumbnail.jpg}`, verify both, atomically rename that one directory to `evidence/<evidence-id>/`, then commit its EvidenceFile row with both byte counts and hashes. On launch, only after the current store validates, reconcile the exact staging/final bundle rules below; never delete by age or an unvalidated directory scan.
3. Validate available storage before camera capture and before backup/PDF generation.
4. Use one `finalizationMutationID` and the closed `FinalizationIntentV1` below; double taps or relaunch retries return the same record/packet/report IDs, instants, snapshot bytes, and counted root.
5. Completed report content never mutates. Only the bounded PDF delivery-state/path/hash transitions defined on `Report` are allowed; correction creates a new source revision and replacement Report.
6. Count evaluation-accounting packet roots, including content-deleted tombstones, not report revisions; ordinary deletion cannot replenish free evaluation. Erase All explicitly removes every tombstone and therefore resets the no-account evaluation on that installation.
7. Persist the observed instant, confirmed site time zone, resolved UTC offset, local date, local time, and acknowledgement copy/version. Never recompute historical local time from the current device zone.
8. Photos for recheck must belong to the new recheck record; prior photos cannot satisfy the requirement.
9. Entitlement lapse blocks a new sign or draft but never read, share, backup, whole-sign delete, erase, correction, PDF retry, or completion of a repository-validated already-started draft.
10. Local erase, App Store subscription management, future workspace deletion, and future account deletion are distinct operations.
11. Backup restore stages and validates a complete immutable data generation before an atomic current-generation pointer change; it never renames or deletes the active SwiftData store.
12. Report/share presentation creates no delivery/open/read receipt.

`FinalizationIntentV1` lives at `Application Support/FieldEvidenceOperations/finalization/<mutation-id>.json` and is canonical JSON with exactly these keys: `completedAt`, `finalizationMutationID`, `finalizationPayload`, `finalizationPayloadSHA256`, `generationID`, `packetID`, `phase`, `recordID`, `reportID`, `schemaVersion`, `snapshotCreatedAt`, `snapshotFinalRelativePath`, `snapshotSHA256`, `snapshotStagingRelativePath`, and `stableRootID`. `schemaVersion=1`; `phase=prepared|snapshot_promoted|database_committed`. `FinalizationPayloadV1` has exactly `issueInsert`, `issueTransition`, `packetAfter`, `packetBefore`, `reportInsert`, and `workflowRecordAfter`; the two inserts/transitions/prior Packet are explicit JSON null when inapplicable, and `issueTransition`, when present, is exactly `{after,before}`. This freezes correction Packet preconditions, replacement/revision/evidence-source IDs, and recheck resolution/new-issue effects rather than reconstructing them from current UI.

Before promotion, S3 freezes the payload/IDs/instants, writes canonical snapshot bytes to the named staging path, verifies both hashes, and atomically writes `prepared`. It promotes the same bytes and then atomically advances to `snapshot_promoted`; it performs one SwiftData save only when every frozen `packetBefore`/Issue precondition still matches. After save it advances to `database_committed` and removes staging/intent.

Recovery is a closed phase-and-presence matrix. At `prepared`: valid staging plus absent final resumes promotion; valid final with absent staging advances to `snapshot_promoted`; valid identical staging and final removes staging and advances; neither removes the intent and leaves the draft; any mismatched/unexpected bytes open maintenance. At `snapshot_promoted`, valid final bytes are mandatory; the unique mutation ID either proves the exact database transaction already committed or permits committing that exact frozen payload while preconditions still match. A failed precondition removes only the matching intent-owned final snapshot and intent, leaving the draft. At `database_committed`, matching rows plus final snapshot bytes/hash are mandatory before cleanup. A crash after database save but before phase update is recognized by mutation ID. Unknown phase, mismatched IDs/hash, a committed row without valid snapshot bytes, or more than one row for a mutation opens maintenance and never guesses. This is user-visible recoverable atomicity, not a claim that SwiftData and the filesystem share one transaction.

Whole-sign deletion uses canonical `DeletionIntentV1` at `FieldEvidenceOperations/deletion/<deletion-id>.json` with exactly `assetID`, `countedPacketTombstones`, `deletionID`, `generationID`, `phase`, `relativePaths`, and `schemaVersion`; phase is `prepared|database_committed`, paths are unique sorted generation-relative strings, and tombstones are the exact post-delete Packet DTOs. One SwiftData save deletes the Asset's complete referentially closed WorkflowRecord/EvidenceFile/Issue/Report lineage, deletes its Site only when no other Asset uses it, and replaces every counted Packet with the exact tombstone shape; only then are the listed files removed. Recovery cancels a prepared intent when the live Asset remains, recognizes an already-committed transaction by the tombstone set, and finishes exact-path cleanup after `database_committed`. V4 exposes no packet-only, report-only, or issue-fragment deletion that could strand parents or issue lineage.

`MediaContractV1` accepts one still frame from `public.jpeg`, `public.heic`, `public.heif`, or `public.png`; animated/multipage and RAW sources fail with an actionable import error. Source files are at most 80 MiB, at most 100,000,000 decoded pixels, and 1–16,384 pixels on each axis. Decode applies orientation, tone-maps HDR/wide-gamut/CMYK/grayscale into 8-bit sRGB, composites alpha on white, removes EXIF/GPS/IPTC/XMP/TIFF/orientation metadata, and writes a single-frame JPEG at quality `0.90`, no upscale, longest edge at most 4096, and at most 32 MiB. Thumbnail output is the same canonical pipeline at quality `0.75`, no upscale, longest edge at most 512, and at most 2 MiB. Allowed output metadata is only structural JFIF plus the selected sRGB ICC profile; forbidden metadata causes restore rejection rather than hash-changing re-encoding. Durable evidence is only `.jpg`/`image/jpeg`; JSON is `application/json`; ready reports are `application/pdf`. Validation sniffs decoded type and frame count, enforces these bounds/metadata, and matches original **and thumbnail** byte count/hash; it never trusts extension or declared MIME alone.

The exact live paths are `evidence/<evidence-id>/original.jpg` and `evidence/<evidence-id>/thumbnail.jpg`; backup maps them to `media/<evidence-id>.jpg` and `thumbnails/<evidence-id>.jpg` without changing bytes. After the store opens and validates, launch removes an abandoned `.staging/evidence/<id>` only when a matching valid final bundle exists or no EvidenceFile row exists; removes a final evidence bundle only when no row exists; and opens maintenance rather than deleting when a row exists but either final file/path/count/hash/decoded JPEG is missing or mismatched. This closes the move/save window without a media job framework.

One small `StoragePreflightService` is reused. It reads important-usage capacity for the actual target volume and requires the operation estimate plus a 64 MiB reserve. One evidence acceptance estimates 68 MiB for temporary/final original+thumbnail pairs; PDF estimates twice the referenced-image bytes plus 32 MiB; backup export estimates declared payload plus 20%; restore estimates twice declared payload plus 20% for staged package and generation. A failed preflight creates no row/file, leaves prior data readable, and exposes one retry/space-recovery state. These checks recur at capture/import, PDF, backup, and restore.

PDF promotion is deterministic by Report ID. A crash after final-file rename but before `ready` commit leaves a pending/failed row; startup removes that non-ready final PDF after verifying it is under the expected report path. Pending then rerenders; failed waits for explicit Retry. A ready row is accepted only when path/hash/bytes all match. This closes the PDF move/save window without a generic job framework.

### `V4Backup@1`

Use a user-selected FileWrapper directory package with extension `.fieldrecordbackup`; do not add a ZIP dependency. S6.2 requires the owner to replace and freeze exported UTI `<owner.reverse.domain>.fieldrecordbackup`, conforming to `com.apple.package`, in `UTExportedTypeDeclarations`; the placeholder cannot ship. Import obtains security-scoped access only long enough to coordinate-copy the selected package into staging, then releases it. Before export, show the sign/report/photo counts and this exact warning: `This backup contains sign details, notes, photos, and reports. It does not contain your subscription. Store and share it securely.` Export proceeds only after the user confirms a destination. V4 does not claim app-level backup encryption; protection after export depends on the destination the user selects. Exact members:

```text
manifest.json
records.json
media/<evidence-uuid>.jpg
thumbnails/<evidence-uuid>.jpg
snapshots/<report-uuid>.json
pdfs/<report-uuid>.pdf
```

Archive `media/` and `thumbnails/` are portable package names only. Export copies the exact validated live bytes from `evidence/<uuid>/original.jpg` and `evidence/<uuid>/thumbnail.jpg`; import recreates that one atomic live bundle and verifies both DTO hashes/counts before the EvidenceFile row is accepted.

`manifest.json` uses the snapshot canonical JSON rules and has exactly `backupSchemaVersion`, `consumedEvaluationRootIDs`, `declaredPayloadByteCount`, `entries`, `exportedAt`, `packs`, and `source`. Version is integer `1`; consumed roots are unique lowercase UUIDs sorted ascending and must equal the `evaluationCounted=true` Packet set in `records.json`; payload count excludes `manifest.json`; `entries` contains every other member exactly once as `{byteCount, mimeType, path, sha256}` sorted by path; `packs` entries are `{contentVersion, packID, schemaVersion}` sorted by pack ID/version; `source` is `{appBuild, appVersion, persistentSchemaVersion: 1, recordsSchemaVersion: 1}`. Paths are NFC, slash-separated, normalized, unique, nonsymlink, and cannot be absolute, empty-segmented, or contain `.`/`..`.

`records.json` uses the same canonical rules and exactly these top-level keys: `assets`, `evidenceFiles`, `issues`, `packets`, `recordsSchemaVersion`, `reports`, `sites`, `workflowRecords`. Version is integer `1`; every array sorts by element `id`; and each element contains exactly the same camel-case fields and nullability frozen in the seven-model contract above, encoded as stable DTO values rather than SwiftData internals. Relationships reference UUID strings only. Dates/UUIDs/hashes use the snapshot forms. A tombstone Packet encodes `currentRecordID:null` and its retained fields only; no omitted model key is permitted, so nonretained relationship content does not exist on Packet. A checked-in minimal-live, issue/recheck, correction, tombstone, pending-report, and ready-report fixture freezes this schema before S6.2.

Include current records, tombstones, original media, thumbnails, immutable report snapshots, pack/version references, and PDFs only for reports whose `pdfState=ready`. A ready report with missing/mismatched PDF bytes fails export. Pending/failed reports have no PDF entry; pending regenerates after restore, while failed remains failed until explicit Retry. Exclude StoreKit cache, diagnostics, operations/restore/erase journals, temporary/staging files, derived caches other than validated thumbnails/ready PDFs, OS metadata, and Keychain material; V4 writes no Keychain value. User backup can never grant paid access.

The data root is immutable-generation based:

```text
Application Support/FieldEvidenceData/current.json
Application Support/FieldEvidenceData/retired.json
Application Support/FieldEvidenceData/generations/<generation-uuid>/model.sqlite
Application Support/FieldEvidenceData/generations/<generation-uuid>/.staging/evidence/<evidence-uuid>/{original.jpg,thumbnail.jpg}
Application Support/FieldEvidenceData/generations/<generation-uuid>/evidence/<evidence-uuid>/{original.jpg,thumbnail.jpg}
Application Support/FieldEvidenceData/generations/<generation-uuid>/{snapshots,pdfs}/...
```

`current.json` is canonical `{"generationID":"<lowercase-uuid>","schemaVersion":1}`. `retired.json` is canonical `{"generationIDs":[...],"schemaVersion":1}` and contains only noncurrent generations awaiting next-cold-launch cleanup. Absence of the entire `FieldEvidenceData/` root is a fresh-install bootstrap; an existing root with a missing/malformed pointer is corruption and never silently bootstraps over prior bytes. S2.1 creates the first generation and one main-actor `StoreSessionCoordinator` that owns the current ModelContainer and a monotonically increasing UI generation token. Feature code receives the coordinator-provided context and never captures a permanent container or adds a repository/persistence abstraction. A restore opens a different immutable generation, swaps coordinator/root injection, and atomically replaces `current.json`; it never renames, overwrites, or deletes the active SQLite generation. Retired generations are deleted only on a later cold launch after confirming they are not current and no prior-process container exists. A missing/malformed pointer, a pointer to a missing generation, or more than one claimed current generation opens maintenance; the app never selects the newest directory by guess.

S2.1 owns one minimal full-screen `StartupMaintenanceView`, not a general recovery framework. Its closed reasons are `data_pointer_invalid`, `data_generation_missing`, `finalization_inconsistent`, `media_inconsistent`, `restore_inconsistent`, and `erase_inconsistent`. Exact title/copy are `Local data needs attention` and `The app stopped to avoid changing or losing local records.` It always offers **Retry checks** and **Recovery steps**. Recovery steps show this exact fallback: `If Retry cannot recover this device, delete and reinstall the app. This removes all local app data and does not cancel your Apple subscription. A backup stored outside this app can be restored from Welcome after reinstalling.` S6.4 activates **Restore data backup** and S6.6 activates typed-confirmation **Erase All** only after startup has proven a valid current generation and no active Restore/Erase intent; pointer-invalid, generation-missing, or active-journal states use the explicit reinstall route rather than operations whose nonoptional old-generation contract they cannot satisfy. It never offers raw-file editing, “use newest,” automatic deletion, or claims that reinstall preserves local bytes. Launch ordering is fixed: continue/validate an Erase intent before normal pointer checks; continue/validate Restore before opening the current generation; open and validate that generation; then reconcile finalization, deletion, media, and PDF state. An unknown/malformed intent stops at this surface before feature writes are enabled.

The restore journal is outside the data root at `Application Support/FieldEvidenceRestore/restore.json` and contains exactly `newGenerationID`, `newGenerationRelativePath`, `oldGenerationID`, `phase`, `restoreID`, `schemaVersion`, and `stagingGenerationRelativePath`. Version is 1 and phase is `prepared|generation_installed|pointer_switched|new_generation_validated`. `prepared` means the complete staged generation has passed package, model, relationship, media, snapshot, and capacity validation. `generation_installed` means that exact directory was atomically renamed under `FieldEvidenceData/generations/` while the old generation remained current. `pointer_switched` means canonical `current.json` names the new generation and coordinator/root injection is rebuilding. `new_generation_validated` means the new current container reopened and all IDs/files/hashes are readable; the old ID is added to `retired.json`, then stage/journal are removed.

Recovery checks both journal phase and exact pointer/directory presence. At `prepared`, an installed new directory with the old pointer is removed as a proven uncommitted generation; otherwise stage/journal are removed and old remains current. At `generation_installed`, old pointer + valid new directory resumes pointer switch, while new pointer + valid new directory advances as a crash-after-pointer-write; invalid new leaves/repoints old and removes only new. At `pointer_switched`, valid new remains/advances; invalid new atomically repoints old before new is removed. At `new_generation_validated`, new must be current/valid; old is retired and cleanup completes. Missing old when it is required, current pointing to neither named generation, an unexpected extra pointer transition, malformed journal, or unknown phase opens maintenance and deletes nothing. This presence matrix closes every journal-write/filesystem-write lag window.

The excluded commerce cache is canonical `Application Support/FieldEvidenceCommerce/entitlement.json` with exactly `schemaVersion=1`, `productID`, normalized `state`, nullable `expirationAt`, nullable `graceExpirationAt`, nullable `revocationAt`, `verifiedAt`, and monotonic `hasEverVerifiedPaid`. It contains no JWS, receipt, transaction ID, customer content, or backup authority. Only a verified transaction/status update changes it; a paywall view/tap, pending/unverified result, backup, or diagnostic import never does.

**Erase All** requires typed `ERASE` confirmation, immediately blocks every feature mutation, and writes outside all targets to `Application Support/FieldEvidenceErase/erase.json`. Canonical `EraseIntentV1` contains exactly `auxiliaryRoots`, `eraseID`, `generationIDsToDelete`, `newGenerationID`, `oldGenerationID`, `phase`, and `schemaVersion`. `auxiliaryRoots` is exactly `FieldEvidenceRestore/`, `FieldEvidenceOperations/`, `FieldEvidenceCommerce/`, the entire `FieldEvidenceDiagnostics/`, `Library/Caches/FieldEvidenceApp/`, `tmp/FieldEvidenceApp/`, and this app bundle ID's UserDefaults persistent domain. `generationIDsToDelete` is the unique sorted set of every validated existing generation ID, including old current, except the frozen new ID. Phase is `empty_generation_prepared|pointer_switched|session_activated|cleanup_complete`.

`empty_generation_prepared` means the frozen new generation exists, validates empty, and old remains current. The operation atomically points `current.json` to new and advances to `pointer_switched`; it rebuilds coordinator/root injection and advances only after the new empty container is active. At `session_activated`, it deletes only the frozen noncurrent generation IDs after the old container is no longer retained; if references have not drained, cleanup remains pending and completes on the next cold launch. It then empties `retired.json`, removes only the frozen auxiliary roots/default domain, recreates exact zero diagnostics, verifies the new store has zero live/tombstoned roots, advances to `cleanup_complete`, and removes the erase journal/root. Erase is not shown as complete before this verification.

Erase recovery is a closed phase/pointer/presence matrix. At `empty_generation_prepared`, old pointer + valid empty new resumes the pointer switch, while new pointer + valid empty new advances as a crash-after-pointer-write. At `pointer_switched`, old pointer + valid empty new performs the named switch, while new pointer + valid empty new rebuilds/activates the session. At `session_activated`, new must be the valid empty current generation; on a cold launch the coordinator opens it, then cleanup removes any remaining subset of only the frozen old-generation IDs and auxiliary roots before zero-diagnostics/store verification. At `cleanup_complete`, new must still be valid/current/empty; any remaining frozen cleanup is completed and reverified before the journal is removed. At every phase, a pointer naming neither frozen old nor new, a missing/nonempty/invalid new generation, an unexpected generation outside the frozen set, malformed intent, or unknown phase opens maintenance and deletes nothing. Relaunch processes this matrix before ordinary pointer maintenance. A phase-lagged but exactly named old/new pointer is resumable, not treated as a mismatch.

V4 has no Keychain value to remove and cannot erase Apple StoreKit state, OS unified logs, or user-exported Files. Erase never calls `AppStore.sync()`, cancellation, or subscription management. A still-active subscription is rediscovered by ordinary verified StoreKit refresh; offline absence of that refresh never invents entitlement.

Restore supports `backupSchemaVersion=1` only. It rejects missing/extra members, unknown schema/pack/template, path/symlink/duplicate violations, ID collision, byte/hash/MIME/canonical-media mismatch, broken relationships except the exact tombstone, inconsistent consumed roots, and insufficient capacity before current data changes. With current data, summary shows incoming/current counts/date/size, offers **Back up current data**, and requires **Replace current data**; cancel removes stage and changes nothing. The staged generation unions every current/restored counted stable root. A current-only root copies its current Packet `id`, stable root, evaluation flag, and created instant into a tombstone with replacement instant; an ID/stable-root collision with different facts rejects restore. A restored live root remains live and is not duplicated. After union validation, restore follows the generation journal above. Entitlement/diagnostics are never imported. Old/new schema migration is a later task, not hidden launch scope. S6.4 explicitly activates **Restore data backup** on Welcome and on `StartupMaintenanceView` only when the valid-current/no-active-journal precondition above holds; S6.5 adds the same entry in Settings for replacement restore. These routes all call the same importer/coordinator and never imply that Restore Purchases restores records.

## 11. Build slices and release gates

Each S-row is one ordered **phase train** containing the named Codex cards. Every card is still one `/goal`, owns one observable result plus at most one bounded alternate/failure family, records evidence, and stops; Codex never begins the next card itself. Cards in one phase run sequentially on the same owner-prepared phase branch: each new `CURRENT_TASK` pins the phase's green main base plus the immediately preceding green card SHA/run. The owner reviews each card before authorizing the next, but does not merge each card separately. After the final card, the owner merges once, verifies `main` points to the expected merge SHA, dispatches by the `main` ref with UI smoke enabled and no intervening push, and requires a green run with that exact `head_sha` before the next phase. This preserves bounded tasks without doubling merge/main-CI overhead.

| Phase | Ordered task-sized units and exact terminal boundary | Owned launch smokes |
|---|---|---|
| S0 Contract/repo lock | `S0.1` creates the checked-in project/shared scheme, synchronized source groups, minimal app/test scaffold, build/test/UI scripts, `run-with-timeout.sh`, and exact-schema `Scripts/ci-selection.json`; CI validates the tier/input, enforces step/total ceilings, and fails closed on missing evidence. Green unsigned implementation-SHA build/install/launch is the boundary. The owner bootstraps the supplied workflow on default first; that bootstrap SHA `B` is S0's base `M`, and predecessor iOS CI is explicitly N/A because project/scripts do not exist yet. | baseline |
| S1 Shell/design system | `S1.1` creates two tabs, Settings entry, semantic tokens/components, exact sign-pack loader, and isolated fixture shell; unknown pack/version fails closed. | 12 foundation |
| S2 Persistence/sign setup | `S2.1` creates only `Site`/`Asset`, immutable generation roots/current pointer, `StoreSessionCoordinator`, exact diagnostic-counter store, startup ordering, and the minimal maintenance surface. `S2.2` adds/reopens one site/sign with nullable-until-preflight IANA time zone; Start Check remains inert. | setup foundation |
| S3 Check runner | `S3.1` adds the remaining five models, exact issue parent chain, stage-aware sole-draft begin/resume, and preflight time-zone/time snapshot; the seven-model schema then freezes. `S3.2` canonical atomic imported-fixture evidence bundle with original+thumbnail integrity. `S3.3` outcome/review, render-complete `ReportSnapshotV1`, exact `FinalizationIntentV1`, and pending Report. `S3.4` resume/mutation idempotency and the complete finalization presence matrix. `S3.5` storage/write/interruption reconciliation. `S3.6` exact camera permission plus denial/Photos/Settings recovery. `S3.7` post-draft Could-not-verify. | 2–6 as assigned |
| S4 Report/history | `S4.1` validated-snapshot exact-geometry `PDFTemplateV1`, pending-render integration, and pinned-toolchain determinism. `S4.2` PDF failure/retry/crash-window recovery. `S4.3` value receipt/report detail/preview/Share/Files export. `S4.4` Reports index, sign/site filters, chronological/current-revision history, and immediately previous distinct-packet comparison. `S4.5` note-only clerical correction/replacement. | 1, 5, 8 as assigned |
| S5 Issue/work/recheck | `S5.1` work record with optional `work_context` photo and no resolution. `S5.2` evidence-bearing resolved/still-visible recheck. `S5.3` original-resolved/different-issue atomic transition. `S5.4` recheck Could-not-verify. | 6, 7 as assigned |
| S6 Backup/data rights | `S6.1` whole-sign lineage deletion, exact non-reset copy, and tombstones first. `S6.2` exported UTI plus deterministic `V4Backup@1`. `S6.3` security-scoped import/stage/hash/path/schema/relationship validation. `S6.4` activates Welcome/maintenance Restore data backup and owns empty-install immutable-generation restore plus pointer-journal recovery. `S6.5` adds Settings replacement restore, confirmation, and monotonic root union. `S6.6` uses a journaled empty-generation pointer switch for Erase All without deleting an active store. | 9 as assigned |
| S7 StoreKit/access | `S7.1` installs the local `.storekit` fixture, product loader, table-driven verified transaction processor, normalized reducer, transaction updates, durable cache, and offline interpretation **without purchase UI**. `S7.2` is the first purchasable paywall and owns localized trial/price disclosure plus verified/cancelled/pending/unverified/failed UI. `S7.3` activates Welcome/Settings Restore Purchases and owns Manage Subscription, renewal/auto-renew-off, signed grace, billing retry/lapse, refund/revocation, and lifecycle/offline status UI. `S7.4` owns one shared `DraftAccessPolicy`, including fresh-offline never-paid behavior, across concurrent-sign and new check/work/recheck entry points. `S7.5` owns lapse/data-rights/Erase-subscription-independence integration. | 10 across the phase |
| S8 Reuse/accessibility/learning | `S8.1` nonshipping exterior-light content-pack fixture proves frozen nouns/purpose copy reach snapshot/PDF with zero production branch. `S8.2` is verification-only complete golden-flow accessibility CI. `S8.3` privacy-safe OSLog/MetricKit plus exact owner-invoked diagnostic export. `S8.4` feedback email with review/consent plus no-mail copy/Files fallback. | 11, 12 as assigned |
| S9 Release | `S9.1` is the final Codex coding card: unsigned-CI-verified RC/privacy/metadata package and inactive protected TestFlight workflow; no upload. `S9.2` owner-dispatches the reviewed protected-main SHA, archives/signs/uploads once, and verifies the TestFlight build on iPhone. `S9.3` is owner-operated App Store Connect submission; no coding. | 12 plus owner evidence |

The canonical `V4_IMPLEMENTATION_RUNBOOK.md` expands this into **36 strictly ordered Codex coding cards plus two owner-only release gates**: 1+1+2+7+5+4+6+5+4+1 cards across S0–S9. This is not permission to run the program as one goal. Every card requires a green implementation-SHA run and owner review before the next card; owner merge and exact-main CI occur once per completed phase train. A failed card stops its train.

Hosted/team work is not S10. It requires a new product decision after observed cross-device/team demand.

## 12. Twelve must-pass launch smokes

1. Fresh install completes the full sign report offline.
2. Force-quit after each runner step resumes without silent loss or duplicate completion.
3. Camera denial offers Photos picker and Settings recovery; safe incomplete exit remains possible.
4. Disk-full/write/interruption tests preserve all prior commits and reconcile every named finalization/media/PDF phase-and-presence boundary without an orphan row, unowned durable file, or mismatched thumbnail.
5. Historical time remains correct across device-zone and DST changes.
6. Could not verify never creates pass, resolution, accepted result, or extra evaluation credit.
7. Work never resolves an issue; recheck requires evidence from the new record.
8. Report correction creates a replacement; prior snapshot/PDF/hash remain readable.
9. Whole-sign deletion shows the exact non-reset warning, removes its complete issue/work/recheck/report/file lineage, and retains one content-free tombstone for each counted root; backup/restore preserves those roots; journaled Erase All atomically activates one empty generation and removes every pre-erase generation, tombstone, staging/operation file, named auxiliary root, cache, and local default while never deleting an active store or cancelling the Apple subscription.
10. The table-driven StoreKit fixture covers eligible/ineligible trial disclosure, purchase/cancel/pending/unverified, renewal/auto-renew-off, signed grace, billing retry/lapse, refund/revocation, explicit restore, offline refresh, and fresh-install offline evaluation; authority changes never hide existing data or couple Erase to Apple billing.
11. The second content-pack fixture freezes its own nouns/purpose displays into snapshot/PDF through the same interfaces with zero new production entity, route, service, permission, pack lookup, or renderer branch.
12. CI validates the golden flow’s accessibility tree (primary labels/traits/order, selection/progress/error focus), default and largest accessibility Dynamic Type layouts, non-color status, and 44-point targets in Light and Dark Mode. S9.2 completes the physical-iPhone TestFlight check with real VoiceOver navigation, Increase Contrast, Reduce Transparency, and Reduce Motion; CI does not claim hardware or spoken-output proof.

Do not run a 76-test adversarial matrix for the first build. Add a regression test only when it protects a launch-blocking invariant or reproduces a real defect.

## 13. Quality budget and known bugs

### Release blockers

- Primary-path crash, hang, or blocked navigation.
- Silent data/photo/report loss or corruption.
- Incorrect purchase, entitlement, refund, trial, restore, or subscription disclosure.
- Privacy/security exposure or a photo crossing records.
- False success, auto-resolution, or misleading proof/delivery claim.
- Failure to reopen/read/share existing customer data after lapse.
- Inaccessible primary action.
- Broken CI archive/signing/upload, privacy policy, support URL, or App Review purchase path.

### May ship when documented

- Minor animation jitter.
- Cosmetic alignment or a nonblocking transition glitch.
- Preview-only fixture polish.
- A rare non-destructive layout issue outside the supported accessibility sizes, with a workaround and scheduled fix.

Every accepted bug must have severity, exact reproduction, affected version/state, workaround, decision owner, and revisit release. No `TODO` silently stands in for this record.

## 14. Analytics, feedback, and learning

Launch without a third-party analytics SDK. Use:

- App Store Connect Analytics for product-page conversion, trial starts, paid conversion, refunds, churn, retention, and crashes when available.
- App Store Connect web diagnostics and MetricKit for crashes, hangs, launch, memory, disk, and energy diagnostics.
- Privacy-safe local counters shown only in an owner-invoked diagnostic export. S2.1 creates canonical `Application Support/FieldEvidenceDiagnostics/counters.json` with exactly this schema and no arbitrary event key:

```json
{
  "first_sign_created": 0,
  "onboarding_completed": 0,
  "paywall_presented": 0,
  "purchase_result": {
    "cancelled": 0,
    "failed": 0,
    "pending": 0,
    "unverified": 0,
    "verified": 0
  },
  "recheck_completed": 0,
  "report_saved": 0,
  "report_share_sheet_presented": 0,
  "schemaVersion": 1
}
```

All values are nonnegative Int64 counters with saturating increment, written by atomic replacement. They are explicitly non-authoritative, best-effort lower-bound signals: the app attempts one increment after the related domain/entitlement/UI success, but a crash or counter-write failure may undercount because this JSON file does not share a transaction with SwiftData or StoreKit. There is no applied-ID store, retry ledger, access decision, payment decision, or exact-once claim. Unknown/malformed schema resets only this diagnostics file to the exact zero object and records a privacy-safe OSLog fault; domain data never changes. `first_sign_created` increments only on the installation's first committed sign transition. `onboarding_completed` increments only after the first newly created report's Value receipt is actually presented; sign creation alone is not completion. `report_saved` is attempted when finalization returns `created` for a new evaluation-counted check/recheck root, including CNV; it excludes work, correction, replay, and PDF retry. `recheck_completed` is attempted on that same `created` result for every recheck outcome, so normal execution attempts both counters. `report_share_sheet_presented` increments after the system sheet is actually presented; dismissal still counts, failed presentation does not. `paywall_presented` increments once per distinct modal presentation token, not on SwiftUI redraw. `purchase_result` is a closed histogram for explicit user-initiated purchase calls only: verified transaction durably processed, StoreKit user-cancelled, pending, unverified, or other terminal failed. Renewal updates, product loading, Restore Purchases, and Manage Subscription never increment it. Counter failure never rolls back domain or entitlement success.

- **Send feedback** in Settings: user-written email with app/version/device context; diagnostics attach only after explicit review and consent. If the system mail composer is unavailable, show **Copy support address** and optional **Save diagnostics to Files**; never fail silently, open a preattached `mailto:` URL, or add an email provider.

OSLog uses privacy annotations and no customer/site/sign labels, addresses, notes, photo paths, photo hashes, StoreKit transaction IDs, or report content. OSLog is never read back or attached. The owner-invoked `DiagnosticExportV1` is canonical JSON with exactly `app={build,version}`, `counters=<exact object above>`, `device={model,osVersion}`, `diagnosticSchemaVersion=1`, `generatedAt`, and nullable `metricKit={crashCount,hangCount,launchTimeMilliseconds,peakMemoryBytes}`. `launchTimeMilliseconds`, when present, is exactly `{under500,from500Through999,from1000Through1999,from2000Up}` with nonnegative counts; other MetricKit payload fields and raw diagnostics are discarded. The export has no raw image, report, database, backup, path/hash, label/note/address, StoreKit product/transaction/status, or credential. Product/storefront/verified-state/expiration evidence for the paid cohort comes from the separate owner-reviewed subscription proof, not this file. The user sees the exact preview before attaching and may continue without it. Backup excludes the entire diagnostics root; Erase All removes it. S8.3 adds only this adapter/export and does not retrofit an analytics framework.

Do not prompt for a rating during onboarding, at report save, after a crash, or after an entitlement action. A system rating prompt may be considered only after a later voluntary reopen and successful in-app report retrieval.

## 15. Backend and account decision

### V4 launch

No external database or backend account is needed. Use SwiftData plus the app's media directory. Do not add CloudKit, Firebase, Supabase, RevenueCat, PostHog, Sentry, or a custom API to the launch target.

### Later decision rule

- If evidence shows only same-person multi-device sync is needed, evaluate CloudKit first.
- If evidence shows team roles, guest browser links, web uploads, shared server authority, or non-Apple clients are needed, use a real backend; Supabase/Postgres is the preferred current candidate. Start on Pro rather than a pausing free production project.
- Add RevenueCat only when multi-platform entitlements, remote paywalls, or subscription-support burden justifies the extra service. Direct StoreKit remains the source for V4.
- Add Sentry or PostHog only as separate, privacy-reviewed instrumentation tasks.

Any app-account release must include complete in-app account deletion in that same release. Do not confuse local erase with account deletion.

## 16. Owner preparation checklist

| Needed by | Owner preparation |
|---|---|
| S0 | Windows authoring host; Actions-enabled GitHub repo/backups; named task branch/workflow; pinned hosted-macOS runner and expected stable Xcode build; fixed iOS 18.0 deployment target; project/shared scheme/configuration; Simulator model/OS selector; neutral bundle/SKU strategy; repository-scoped Codex/GitHub policy; installed exact-hash V4 implementation runbook and selected one-card `CURRENT_TASK`; exact CI selector/timeout/evidence contract from the runbook. No owner Mac is required. |
| S3 | S3.6 task explicitly permits the exact camera-purpose project setting above. A physical iPhone is needed only for the later owner-run camera/low-light gate; CI Simulator work uses deterministic imported fixtures. |
| S6 | Freeze the nonbrand exported package UTI by replacing `<owner.reverse.domain>.fieldrecordbackup`; keep the `.fieldrecordbackup` extension and package conformance. No cloud storage service or encryption vendor is required. |
| S7 | Freeze the monthly product ID/group/14-day-trial fixture, confirm the fixed 16-day paid-to-paid grace and Family Sharing off, and authorize the checked-in local `.storekit` fixture executed by CI; provide controlled HTTPS fixtures for `TermsURL`, `PrivacyURL`, and `SupportURL`. Unsigned local StoreKit implementation needs no Paid Apps Agreement, bank/tax completion, or active App Store product. Product views never hardcode price or eligibility. |
| S9 | Apple Account/Developer Program; six-of-ten commitment evidence before production SKU creation/activation; Paid Apps Agreement/bank/tax and verified Small Business Program status; live monthly product/group/storefront/14-day offer/grace configuration; owner-controlled domain/support email/privacy/terms/support pages; final App Store record; GitHub `app-store-connect` environment secrets on a supported repository/plan posture; owner-only manual dispatch restricted to the reviewed protected-`main` SHA; and signing/App Store Connect credentials. Do not claim a private-repository environment required reviewer unless the selected plan supports it. S9.1 adds only the inactive release workflow/privacy package; S9.2 owner-dispatches and verifies TestFlight on iPhone. |
| Evidence program | Ten qualified shops; after recent-job proof, separate 20-person comprehension and nonoverlapping 20-person pronunciation samples from those shops; at least eight qualified prototype participants including at least two accessibility-reliant participants. If the latter minimum is not met, the study is formative only and cannot release/re-score the UX accessibility evidence cap. |

Do not claim device sync—the subscription restores through StoreKit, while app data moves only through backup/restore. Planning cannot substitute for willingness-to-pay or retention evidence.

Do **not** sign up for Supabase, Firebase, Stripe, RevenueCat, PostHog, or Sentry for S0. They are not needed to build the device-local V4 app.

## 17. Score and evidence plan

The audited V3 readiness score remains **60.725 (60.7 displayed)**. Against the unchanged V3 rubric, only source-supported plan improvements produce an honest V4 planning ceiling of **61.025 (61.0 displayed)**, with specification quality **76.4714 (76.5 displayed)** and validation strength still **9.0**. Opportunity/business moves from 44.0 to 45.0; the overall lift is only **+0.300**. Better planning cannot honestly lift observed frequency, payment, acquisition, retention, prototype, or implementation criteria; evidence is the real lever.

Highest-leverage sequence:

1. **Ten-shop recent-job study and nested naming tests** — measures actor/job-frequency and naming uncertainty; ratings lift only when each frozen threshold passes. In the 20-person comprehension sample, after at least ten minutes of unrelated distractor work and before preference is revealed, ask each participant to recall the root without title, subtitle, icon, or choices. Pass the delayed unaided-recall gate only when at least 14 of 20 produce the exact or unambiguously phonetic root and no competing finalist has a higher recall count; spelling errors are analyzed separately in the nonoverlapping audio/spelling sample.
2. **At least eight-person moderated V4 prototype/accessibility test** — qualified roles, including at least two accessibility-reliant users; timed setup/check/report, errors, low light, Dynamic Type, and VoiceOver. Fewer than eight total or fewer than two accessibility-reliant participants is formative only and cannot release or re-score the frozen UX evidence cap.
3. **Independently reviewed executable device-local vertical slice** — force-quit, storage failure, whole-sign delete/Erase All, report replacement, StoreKit sandbox, the named offline entitlement smoke, and the second-pack fixture are launch evidence. Forced media-loss/corruption, derived-projection failure, security/abuse exercises, schema migration, and old/new report/portable-archive/backup compatibility are separately authorized post-V4 evidence tasks, not hidden S0–S9 launch scope. The nonshipping exterior-light fixture must run through the same pack/runner/snapshot/renderer interfaces with zero new production entity, route, service, permission, or renderer branch. This proves the bounded content-pack seam for nouns, copy, evidence purposes, and issue labels; it does not claim a generic workflow or untested observation engine. A partial spike informs the build but cannot release the architecture evidence cap.
4. **Exact-offer commitment, then paid evidence** — six of ten target shops must sign the exact cancellable `$59.99/month unlimited-local App Store` commitment before App Store Connect SKU creation/activation; this authorizes launch research but is not payment evidence. Actual paid evidence is collected only through production StoreKit after release and is reconciled with the consented roster protocol above. Trial starts and survey intent do not count. The legacy V3 `$79/25` pilot remains separate and cannot validate this offer.
5. **Day-30/60/90 cohorts** — repeat eligible use, refunds, support, actual App Store proceeds, customer benefit, and retention.
6. **Only then** evaluate acquisition channels, cloud/team need, guest capture, and a second public vertical.

Do not add features merely to increase a plan score. Every achieved evidence-sensitive/readiness re-score must cite observed or executable evidence from frozen source bytes; plan-quality changes must cite the frozen V4 section that supports them.

## 18. Codex execution authority

The mandatory installed companions are `../execution/CODEX_EXECUTION_CONTRACT_V4.md` and `../execution/V4_IMPLEMENTATION_RUNBOOK.md`. The new app repository receives its short root `AGENTS.md`, one frozen `CURRENT_TASK.md`, a known-bug register, the supplied unsigned CI workflow, and small smoke scripts. The runbook is a catalog, not blanket authority: `CURRENT_TASK.md` must pin its exact path, SHA-256, and one selected card ID. Each Codex task implements only that card, stays within named paths, and stops on any **unnamed** package, entitlement, backend, auth, payment behavior, migration, external action, or adjacent feature. A task-named branch push, CI trigger, run inspection, and artifact download are ordinary verification only when explicitly authorized; PR merge, TestFlight upload, deployment, and App Store mutation remain separate owner-authorized actions. After each card, the owner reviews its green implementation SHA and prepares the next card on the same ordered phase branch; after the phase's final card, the owner merges the phase train once and requires green CI on the exact resulting `main` SHA before the next phase.

Recommended opening in the new Codex task:

```text
/goal
Complete exactly the one active card named in docs/execution/CURRENT_TASK.md.
The implementation plan is already approved: do not enter /plan, redesign scope,
combine cards, improve adjacent code, or start the next card. Read AGENTS.md,
CURRENT_TASK.md, its exact SHA-256-pinned BUILD_PLAN_V4.md, and its exact
SHA-256-pinned V4_IMPLEMENTATION_RUNBOOK.md card before mutation. Perform the
read-only G0 checks first and stop if any required field, hash, phase-main base,
immediate predecessor-card SHA/run, authority-only task-start commit, dirty path, allowed path,
tool boundary, workflow/ref, runner/Xcode/runtime, project/scheme, Simulator
selector, or total budget is unresolved. If G0 passes, author on Windows and
implement only the selected card. When each remote operation is explicitly
authorized, commit and push only task-owned paths, dispatch the named unsigned
GitHub macOS workflow, and require a green run whose head_sha equals the exact
implementation commit. Inspect complete logs/artifacts on failure; make at most
one concrete task-scoped fix and rerun once. If the rerun is not green, stop and
handoff. Never claim local Xcode/Simulator proof, never use XcodeBuildMCP, never
merge/sign/upload/submit, append HANDOFF.md, name the next card, and stop.
```

## 19. Final V4 decision

Build the sign-first local app, not the V3 platform. Make the first report fast, the evidence durable, the subscription honest, and the history useful. Preserve neutral IDs and one small pack seam for later verticals, but do not pay the backend, team, guest, or generic-engine complexity cost until customers prove they need it.

This plan improves the odds of shipping and learning; it does not prove product-market fit or profitability. The paid pilot and retained cohorts must do that.
