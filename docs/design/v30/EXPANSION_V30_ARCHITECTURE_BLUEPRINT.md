# AssetRounds V30 Globalization Foundation, Research, and Reconciliation Blueprint

## Document status

- Prepared: 2026-09-02
- Revision: R2 — pre-Phase-10 provisional implementation model
- Status: OWNER-DIRECTED, RESEARCHED ARCHITECTURE BLUEPRINT — EXECUTION REQUIRES THE SEPARATE OWNER HANDOFF/AUTHORITY PACKAGE
- Product: the existing AssetRounds iPhone app; this is not a second app, backend, or permanent fork
- Initial commercial market: United States only
- Initial binary goal: multilingual, offline-capable AssetRounds with evidence-backed U.S. language support
- Frozen V23 source head: acbfb68355f903fe98638b6ef22e4814e7b48328
- Frozen V23 source tree: 47e17fae6b73dccd5029ccf4ac7cca659196f225
- Frozen V23 coordination head: 51ef2b3d970a25b4c83df8c8238609316e37034e
- Frozen V23 coordination tree: 060c83c3d1489fc011b1c921f6c85bec2b074478
- Frozen V23 coordination observation: ledger sequence 626
- Planning branch: phase/v30-globalization-foundation
- Planning worktree: C:\AssetRounds-v30-globalization-foundation
- Provisional implementation branch: phase/v30-globalization
- Provisional implementation worktree: C:\AssetRounds-v30-globalization
- Post-Phase-10 reconciliation branch: phase/v30-globalization-reconciliation
- Post-Phase-10 reconciliation worktree: C:\AssetRounds-v30-globalization-reconciliation
- Intended activated authority root: docs/design/v30
- Canonical activated files: EXPANSION_V30_FOUNDATION_PLAN.md, EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md, EXPANSION_V30_HANDOFF.md, and NEXT_CODEX_SESSION_PROMPT.md
- Current R2 external blueprint: C:\Users\palat\OneDrive\Desktop\AssetRounds V30 Globalization\EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md
- Preserved R1 external blueprint: C:\Users\palat\OneDrive\Desktop\ASSETROUNDS_V30_GLOBALIZATION_FOUNDATION_BLUEPRINT.md
- Preserved post-Phase-10-only R1 SHA-256: 81c74f074ea2af4500883b56117813cc3f0c85ba059e7a568db1ef17e019c84c
- Superseded planning input retained as provenance: C:\Users\palat\OneDrive\Desktop\ASSETROUNDS_V24_GLOBALIZATION_FOUNDATION_BLUEPRINT.md
- V24 planning-input SHA-256: 370c378bbb3b567c465d217111e8de3342581916e260b234a32511e807c01d94

This document remains outside the Git repository until an owner message invokes a pre-existing, reviewed package. It cannot authorize, issue, amend, or supersede itself. The owner's 2026-09-02 direction permits a separate externally prepared `V30PreS10ProvisionalImplementationAuthorityV1` to create `phase/v30-globalization` at the exact frozen V23 head and to execute the bounded pre-S10 portion of this graph today. That authority and its manifest must already exist, match exactly, and be presented by the owner in the new Codex task before any V30 mutation.

Pre-S10 work is deliberately provisional. It may change V30-owned and explicitly fenced shared files only inside `C:\AssetRounds-v30-globalization`; it never reads, polls, builds, tests, or mutates `C:\AssetRounds`. It cannot accept a card, mutate `main`, claim Phase 10 compatibility, close V30, release, or promote a translation. After the owner reports Phase 10.6 complete, P05 performs a mandatory three-lineage reconciliation from frozen V23 (`B`), frozen V30 provisional work (`P`), and verified accepted Phase 10/V23 main (`S`). Only post-reconciliation P06/P07 evidence can earn final acceptance or integration credit. The R1 draft and V24 draft remain immutable provenance and are never merged wholesale.

## 1. Executive decision

AssetRounds can add a serious globalization foundation without losing V23 and without disturbing the Phase 10 checkout.

V30 is the successor globalization program. It supersedes the unactivated V24 planning proposal because the owner now wants an evidence-backed multilingual initial binary rather than an English-only globalization foundation. V30 is not V23 Card 147. V23 has a frozen 146-card register, 230-edge graph, package identity, path fences, receipts, and coordination history. Rewriting those facts would make earlier evidence ambiguous.

V30 will:

1. Preserve every accepted or provisional V23 commit, receipt, card ID, edge ID, status, and evidence classification.
2. Leave C:\AssetRounds and its active Phase 10 work completely alone; pre-S10 V30 work uses only the dedicated V30 worktree and frozen evidence.
3. After the owner reports Phase 10.6 complete, verify that completion from Git and hosted-CI evidence rather than trusting conversation text.
4. Reconcile accepted Phase 10.6 into V23 through the existing non-force process, with accepted Phase 10 owning only actual shared-path conflicts.
5. Preserve V23 Cards 135, 136, 141, and 146 under their exact OWNER_ACTION, MONITOR, and DEFER rules.
6. Create the isolated V30 provisional branch today from the exact frozen V23 head, then later create a separate reconciliation branch from the accepted post-Phase-10.6/V23 green main head and replay V30 card-scoped changes with provenance.
7. Reuse V23 localization, accessibility, report, search, persistence, and coordination seams instead of creating parallel systems.
8. Make language support work offline and extend through field workflows, errors, accessibility, reports, exports, backup, restore, search, and App Store metadata.
9. Keep app language, formatting region, authored-content language, report language, storefront country, and project jurisdiction as separate concepts.
10. Preserve language-neutral canonical data, identifiers, hashes, journals, receipts, and machine-readable exports.
11. Use Apple's device and per-app language resolution by default, expose the effective choice in AssetRounds Settings, and fall back to English when no supported match exists.
12. Require professional or native in-context review before any translated locale is called complete.

The initial commercial release remains U.S.-only. A multilingual binary does not claim that AssetRounds is available in another storefront or that a U.S. rule, qualification, standard, or inspection conclusion applies outside its evidenced jurisdiction.

### 1.1 One app, separate worktrees, one final main

There is exactly one AssetRounds product, one iOS app, and one eventual `main`. Phase 10 branding, accepted V23 expansion behavior, and accepted V30 globalization behavior are not separate apps or permanent forks.

The worktree roles are intentionally different:

| Worktree / branch | Role | Merge rule |
|---|---|---|
| `C:\AssetRounds` / active Phase 10 branch | Existing app and Phase 10 branding | Permanently forbidden to V30; post-trigger reconciliation uses only external accepted evidence and the named clean reconciliation worktree |
| `C:\AssetRounds-v23-expansion` / `phase/v23-expansion` | Frozen V23 expansion lineage | Reconciled first into the accepted Phase 10 lineage under predecessor authority |
| `C:\AssetRounds-v30-globalization-foundation` / `phase/v30-globalization-foundation` | Immutable R1 planning marker at the exact V23 head | Preserve for provenance; never merge this planning branch wholesale |
| `C:\AssetRounds-v30-globalization` / `phase/v30-globalization` | Provisional V30 implementation worktree created today from exact frozen V23 | Execute only P00–P04 under the owner handoff; commits and CI remain zero-credit provisional evidence |
| `C:\AssetRounds-v30-globalization-reconciliation` / `phase/v30-globalization-reconciliation` | Later clean reconciliation worktree created from verified accepted Phase-10.6/V23 green `main` | Replay or reimplement each V30 card-scoped delta, reverify, then become the only V30 lineage eligible for final acceptance and a non-force `main` fast-forward |

The integration path is strictly:

`frozen V23 B → provisional V30 P (P00–P04 today)` and, later, `accepted Phase 10.6 + reconciled V23 S → card-scoped V30 replay/reimplementation → accepted V30 green main`.

Today, before the owner reports Phase 10.6 complete, the safe in-scope work includes the full provisional implementation sequence P00–P04 in `C:\AssetRounds-v30-globalization`. An exact current-card fence may include an S10-reserved path only when its pre-existing external owner-authority tuple authorizes that path and the context labels it `S10_SHARED_RECONCILIATION_REQUIRED`; isolation prevents interference, while the later three-lineage reconciliation prevents silent conflict resolution. P05–P07 remain unavailable. Codex never codes V30 in `C:\AssetRounds` or in the planning worktree.

## 2. What the owner handoff may authorize now

This blueprint describes the owner's requested model but cannot activate itself. Only when the owner supplies the companion `NEXT_CODEX_SESSION_PROMPT.md` with the pre-existing matching external authority and manifest as a new-task message, and all exact package hashes validate, does that owner invocation authorize:

- creation of `phase/v30-globalization` and `C:\AssetRounds-v30-globalization` at exact frozen V23 head `acbfb68355f903fe98638b6ef22e4814e7b48328` / tree `47e17fae6b73dccd5029ccf4ac7cca659196f225`;
- installation of the all-and-only reviewed V30 authority, four immutable human package files, manifest-listed register/graph/locale/V24 projections, schemas, validators, Card 1 context/fence, and initial current-task/selector projections on only that branch;
- execution of the graph-enumerated 37-card pre-S10 provisional cohort, one selected card at a time, with exact path fences and append-only provisional receipts;
- static verification and task-pinned hosted macOS branch CI as development evidence only;
- preservation of every provisional commit, failed attempt, result, and reconciliation requirement.

Neither this blueprint nor the companion package authorizes:

- changing the active Phase 10 checkout;
- polling Phase 10 before the owner reports Phase 10.6 complete;
- editing the frozen V23 worktree or canonical V23 coordination history; the V30 branch may change its own descendants and uses a separate namespaced provisional ledger;
- selecting any card outside P00–P04 before the post-S10 gate;
- treating provisional translations or provisional CI as accepted;
- claiming a Windows iOS build or Simulator result;
- signing, uploading, releasing, submitting, or changing App Store availability;
- creating accounts, services, analytics, remote translation, or a backend;
- force-pushing, rebasing accepted evidence history, destructively resetting, or silently resolving unrelated ref movement;
- inventing legal, professional, native-speaker, licensed-standards, physical-device, owner, release, or monitoring evidence.

The graph-enumerated pre-S10 cohort may move through `PROVISIONAL_*` states after the owner handoff validates. The graph-enumerated post-S10 cohort remains `POST_S10_NOT_SELECTABLE`. Every pre-S10 result is refreshed, reconciled, or explicitly rejected in P05 and has no final implementation, acceptance, phase, merge, release, or successor credit before that point.

## 3. Source hierarchy and evidence labels

### 3.1 Precedence

Before any V30 branch, worktree, support-artifact, ledger, receipt, current-task, selector, or product mutation, the working session must read the applicable `AGENTS.md` from exact frozen V23 lineage `B` and then apply this order:

1. The current user message that supplies `NEXT_CODEX_SESSION_PROMPT.md`, plus the matching machine-readable owner authority and package manifest.
2. Repository `AGENTS.md` from exact `B`, except that the externally supplied owner V30 authority narrowly replaces the frozen predecessor's S9.1-only selection inside the dedicated V30 branch without changing any inherited predecessor authority file.
3. The exact selected `docs/design/v30/execution/V30_CURRENT_TASK.md`, its package-pinned V30 plan/runbook projection, and the accepted exact-hash four-file V30 package.
4. The accepted V23 package and frozen/append-only coordination history.
5. Accepted Phase 10.6 and exact-main Git/CI evidence, only after the owner trigger.
6. Official platform, demographic, workforce, legal, and standards sources captured by the active card.
7. Dated competitor documentation and shipped App Store binary evidence.
8. Customer reviews and support/community requests.
9. The verified 2026-08-12 AssetRounds keyword/vertical research package.
10. Analyst inference and hypotheses, always labeled.

The inherited `docs/execution/CURRENT_TASK.md`, V4 build plan, and V4 runbook remain frozen predecessor evidence in the provisional branch and are not edited or treated as V30 selection. Only `docs/design/v30/execution/V30_CURRENT_TASK.md` and `docs/design/v30/execution/V30_CI_SELECTION.json` are V30 execution projections; G3 creates them from authority-pinned bytes, and Card 1 never edits inherited V4 files. This owner-directed isolation avoids both self-authorization and collision with the S10-reserved execution files.

An older planning document, review, keyword score, or competitor claim cannot override current product truth or active execution authority.

### 3.2 Evidence labels

| Label | Meaning | Permitted use |
|---|---|---|
| PRODUCT_TRUTH | Exact accepted source/build behavior or exact active contract | Product and acceptance decisions within its stated boundary |
| OFFICIAL_MEASURED | Dated government, standards, or platform source with defined universe | Market or architecture input with source limitations |
| BINARY_OBSERVED | Language or behavior visible in a shipped App Store listing or exact inspected bundle | Evidence for that product/version/territory only |
| VENDOR_DOCUMENTED | Vendor help or product documentation | Product-pattern evidence; not proof of exact iOS bundle behavior |
| CUSTOMER_REPORTED | A dated review or support request | Pain-point signal; not independently verified behavior or representative prevalence |
| KEYWORD_MEASURED | Dated SEMrush, DataForSEO, SERP, or U.S. App Store observation | Acquisition and terminology input; never language-population or product-scope authority |
| ANALYST_INFERENCE | A reasoned synthesis from cited evidence | Planning recommendation only |
| HYPOTHESIS | An unvalidated bet | Research backlog only |
| OWNER_ACTION | A real owner/professional/legal/release act | Cannot be fabricated or performed by an implementation agent without authority |

### 3.3 Research limitations

- Public App Store review pages expose a small, changing, non-random sample. Absence of a complaint is not evidence that a problem does not exist.
- Vendor language lists can describe a web platform, help center, or phased rollout rather than the exact iOS binary.
- U.S. Census language-at-home data describes residents age five and over, not AssetRounds buyers, technicians, or construction workers.
- Hispanic ethnicity and foreign-born workforce data are not identical to Spanish-language preference.
- Keyword research in the supplied package is U.S.-English. It does not measure Spanish, Chinese, Vietnamese, Korean, or other language demand.
- Translation count is not market readiness. Support, legal, privacy, jurisdiction, terminology, accessibility, and report quality remain independent gates.

## 4. Frozen predecessor facts

### 4.1 V23 package

| Fact | Frozen value |
|---|---|
| Package ID | ASSETROUNDS-EXPANSION-V23-20260825 |
| Package digest | 99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570 |
| Card count | 146 |
| Direct edge count | 230 |
| Card register digest | edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd |
| Direct graph digest | 4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae |
| Lineage digest | 8c5a573df6b9242096e53983da9c78cc4cb2246e6ce4b504f1e4d45d42173283 |
| Impact projection digest | a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b |
| Card relation digest | 9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4 |
| Contract facet digest | b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f |
| Selector digest | 6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2 |
| V21 dependency-disposition digest | f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c |
| S10 reserved-path count | 86 |
| S10 reservation digest | 274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a |
| V5 static-preparation set | Exhausted |
| P06 checkpoint evidence | Provisional/static only |

### 4.2 Unfinished V23 cards

| Global card | Card ID | Classification | Current state | Direct prerequisites | V30 treatment |
|---:|---|---|---|---|---|
| 135 | V23-P05-C02 | OWNER_ACTION | NOT_STARTED | V23-P05-C01 | Preserve. Do not release a pre-globalization candidate merely to make V23 appear complete. Rebind or supersede only through explicit append-only post-reconciliation authority. |
| 136 | V23-P05-C03 | MONITOR | NOT_STARTED and unarmed | V23-P05-C02 | Preserve unarmed until a qualifying exact release and monitoring window exist. |
| 141 | V23-P06-C05 | DEFER | DEFERRED | V23-P00-C03 | Preserve. Re-enter only under its canonical trigger and new authority. |
| 146 | V23-P06-C10 | DEFER | DEFERRED | V23-P00-C03, V23-P03-C41, V23-P03-C42 | Preserve. Re-enter only under its canonical trigger and new authority. |

All four retain staticPreparation=false. No V30 research, code, catalog, merge, CI, linguistic review, or release activity may silently change those facts.

### 4.3 V24 disposition

The V24 draft is immutable, non-authoritative provenance. V30:

- retains its successor-program and safe-reconciliation design;
- retains separation of language, locale, authored content, report language, storefront, and jurisdiction;
- retains offline, Unicode, RTL, report, export, backup, and exact-head acceptance requirements;
- replaces its English-only initial scope with the V30 multilingual initial cohort;
- splits language implementation and acceptance into smaller, auditable cards;
- strengthens review-derived workflow protections;
- deletes all V24 execution names, IDs, branch assumptions, and proposed credit;
- never rewrites or deletes the V24 file.

The requirement-level V24 disposition matrix in Appendix A is part of this reviewed planning artifact. Before activation it must be emitted as a separate machine-readable projection, independently parsed, and hash-bound into the V30 structural projection. Every normative V24 requirement has exactly one disposition: `INCORPORATED_WITH_PROVENANCE`, `REJECTED_WITH_RATIONALE`, or `DEFERRED_UNCHANGED`. Incorporation transfers intent, never implementation or acceptance credit.

## 5. Current frozen-code audit

V23 already contains valuable foundations that V30 must extend:

- FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift defines typed keys, registry validation, shipping-locale policy, pseudo-locale exclusions, comments, plural constraints, and evidence.
- FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift binds typed keys to bundled resources.
- FieldEvidenceApp/Resources/Localizable.xcstrings is a valid Xcode String Catalog.
- FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift names RTL, pseudo-expansion, Dynamic Type, VoiceOver, Voice Control, Switch Control, non-color communication, and truthful error states.
- Report and accessible-document contracts already carry several locale, unit, display, layout, semantic-tree, and publication-provenance seams.
- Search, scheduling, measurements, contacts, OCR, dictation, voice, CSV, backup, and portable reports expose useful extension seams.

Measured gaps at frozen V23:

| Area | Frozen observation | V30 requirement |
|---|---|---|
| Catalog | 1,491 keys; source language en; only en localization | Add only evidence-approved, complete bundled locales |
| Xcode regions | developmentRegion en; knownRegions en and Base | Add declared languages through the shared project/catalog owner |
| Shipping policy | English-only and en-US assertions remain in several policies | Version forward deliberately; preserve historical interpretation |
| UI literals | At least 627 heuristic SwiftUI literal call sites | Inventory semantically; do not assume each is missing because Xcode can extract some literals |
| Language control | No AssetRounds language picker or effective-language row | Use system/per-app language; add an in-app discovery row and safe Settings deep link |
| Pseudolocales | Test-only en-XA, en-XB, ar-XB, en-XL, and en-XT seams exist | Turn them into complete test harnesses without shipping them |
| UI tests | Some V23 localization/accessibility tests remain explicit XCTSkip pending S10.6 | Reconcile UI first, then activate through exact hosted macOS cards |
| PDF | One deterministic path replaces non-ASCII with question marks; other paths use fixed Helvetica and U.S.-letter-like geometry | Unicode shaping, qualified embedded fonts, Letter/A4 policy, extraction, and deterministic replay |
| Historical IDs | Some registry versions embed en-US | Preserve bytes; do not rename evidence identities to appear locale-neutral |
| OCR/dictation | Some capability assertions are en-US | Make support truthful per locale and connectivity; translated UI must not imply unavailable capability |

The inventory must classify every text-bearing surface as:

1. app-owned user-facing copy that must use a stable key;
2. accessibility text;
3. report or export chrome;
4. user-authored evidence that remains verbatim;
5. administrator-authored template or instruction content;
6. machine-readable identifier or enum that must never translate;
7. legal, licensed, jurisdiction, or professional language with separate authority;
8. developer/debug text;
9. obsolete or unreachable text.

## 6. Research result: what field-app users care about

The consistent pattern across current App Store reviews, G2 review summaries, and vendor support material is not demand for more decorative features. It is trust in completing real field work.

| Rank | User need | Evidence strength | V30 response | Explicitly not authorized by V30 |
|---:|---|---|---|---|
| 1 | Fast, obvious mobile completion | Very strong | Protect primary flows under longer text, Dynamic Type, RTL, VoiceOver, translated actions, and error recovery | A new information architecture or work-order product |
| 2 | Offline work that does not disappear and syncs predictably | Very strong | Translate and expose pending, saved, synchronized, failed, conflict, and recovery states; preserve Unicode in queues and evidence | A new sync engine or cloud backend |
| 3 | Forms and procedures that match the job | Strong | Preserve required/optional semantics, conditional meaning, labels, validation, units, dates, and numerals in every locale | A new form builder or rules engine |
| 4 | Photos, notes, signatures, and reports as the operational record | Strong | Preserve photo/comment association, authored text, status, numbering, glyphs, and audit provenance through reports and sharing | A new e-signature service or media platform |
| 5 | Search, filters, scan context, and uncluttered navigation | Strong | Unicode-aware search, locale-aware sorting, stable identifiers, translated filters, and unambiguous scanner states | A new ranking engine, inventory system, or GIS product |
| 6 | Consistency across devices and exported outputs | Strong | Avoid localized workflow or report capability gaps; test exact mobile and document surfaces | A new web client |
| 7 | Clear assignments, reminders, time, and status | Moderate to strong | Localize existing notifications and status, and apply correct time-zone/calendar rules | New scheduling, routing, team accounts, or requester licensing |
| 8 | Accessibility and responsive support | Moderate | Localized semantic labels, focus, error announcements, contrast, touch targets, and help paths | New support staffing or enterprise services |

Representative customer-reported signals:

- SafetyCulture users reported freezing, unreliable photos/sync, and a need to translate English manually in a Spanish-language workflow.
- MaintainX users asked for mobile/web parity, editable templates, better report calculations, inventory reporting, and filters.
- UpKeep users reported slowness, lost comment drafts, task/timer inconsistency, and one-at-a-time photo uploads.
- ArcGIS Field Maps and Survey123 users described crashes, failed offline downloads, weak-signal problems, battery drain, and reauthentication loops.
- Site Audit Pro users asked for stronger PDF photo/comment association, numbering, multi-photo issues, closed-item handling, and less double entry.
- FastField feedback valued dictated notes and rapid daily summaries.

These are CUSTOMER_REPORTED observations from limited samples, not verified defect counts. Their design value is the repeated pattern: V30 must not make an already demanding field workflow less reliable or less legible merely to translate it.

Primary review and pattern sources:

- [SafetyCulture/Mitti U.S. reviews](https://apps.apple.com/us/app/mitti-by-safetyculture/id499999532?see-all=reviews)
- [SafetyCulture Chile reviews](https://apps.apple.com/cl/app/safetyculture-iauditor/id499999532?see-all=reviews)
- [MaintainX U.S. reviews](https://apps.apple.com/us/app/maintainx-work-orders/id1437854484?platform=iphone&see-all=reviews)
- [UpKeep U.S. reviews](https://apps.apple.com/us/app/upkeep-work-order-maintenance/id921799415?platform=iphone&see-all=reviews)
- [ArcGIS Field Maps U.S. reviews](https://apps.apple.com/us/app/arcgis-field-maps/id1515671684?platform=iphone&see-all=reviews)
- [ArcGIS Survey123 U.S. reviews](https://apps.apple.com/us/app/arcgis-survey123/id993015031?platform=iphone&see-all=reviews)
- [Site Audit Pro U.S. reviews](https://apps.apple.com/us/app/site-audit-pro/id430234732?see-all=reviews)
- [G2 MaintainX reviews](https://www.g2.com/products/maintainx/reviews)
- [MaintainX offline mode](https://help.getmaintainx.com/offline-mode)
- [GoCanvas synchronization behavior](https://help.gocanvas.com/hc/en-us/articles/26461887164183-What-does-it-mean-to-sync-my-device)

## 7. User-provided keyword and vertical research

### 7.1 Integrity

The supplied 2026-08-12 ZIP has SHA-256 c2593559ea72a161c3be940fdd982c6979b422b91665fe7197af868bde57e633 and contains twelve files: eleven hashed payloads plus PACKAGE_MANIFEST_SHA256.txt. Every recorded payload SHA-256 matched. At the captured audit and final recheck, the 267,111-byte embedded workbook was byte-identical to `C:\Users\palat\OneDrive\Desktop\Asset Rounds Research\ASSETROUNDS_KEYWORD_AND_VERTICAL_SCORECARD_2026-08-12.xlsx` at SHA-256 3d2bb847268bd69da5c1841a8d24b779b2db7e8414658f5be7f885d29006f01d. A separate zero-byte Desktop-root file with the same filename is not a source and is explicitly excluded. Activation must reverify the folder-scoped source rather than rely on this observation.

| Source | SHA-256 |
|---|---|
| ASSETROUNDS_VERTICAL_EXPANSION_REPORT_2026-08-12.md | 0db3f5110bc7a231b2a157f5e00d2efdee52ba00a108a85e68f2934e7315dfda |
| ASSETROUNDS_FUTURE_CODEX_VERTICAL_BRIEF_2026-08-12.md | 0d852b757db715f8394461fe8f897bd94408cb707f7b4397a15993d7d3ecde69 |
| normalized_research_dataset.json | 42f18e70a8c6d642e5190d8aba2ccf8a9ca9e6fccb84ed85211c938108c9e932 |
| semrush_evidence.json | 4ee890e47ea2c1093d7eacb620438783e1b3cadd913f249fdd15ef23406ed3cb |
| dataforseo_evidence.json | 17f659eaaa26036502f37e54d3a49507b1490369e41dec1ef47c15c9188d70f7 |
| dataforseo_blindspot_evidence.json | 78ee056d18c8de78807a2a626e5c64156e1cb5f91a90e49d1d9d6685b53e2830 |
| app_store_evidence.json | 53853863171042eda31725835676bd82041a559bd73144db949d28d0f062051d |
| app_store_blindspot_evidence.json | fcaf429be85ef42b3eb198485b75c16a2c4b50449d034f91ce92788ee687b89a |
| market_vertical_evidence.json | 7894c141d67be1ff58ca3fd45d8ad5e6c46378b49046d9735a4fc53e6be47743 |
| current_build_keyword_fit.json | 0c5c4f8de40b2007afb65953fe26b72ac1d5e27502aebee9b49a4ba4fd3d5dd7 |
| ASSETROUNDS_KEYWORD_AND_VERTICAL_SCORECARD_2026-08-12.xlsx | 3d2bb847268bd69da5c1841a8d24b779b2db7e8414658f5be7f885d29006f01d |

V30-P01-C01 must machine-verify every row again at package freeze instead of trusting prose.

### 7.2 What the package contributes

The package is valuable to V30 for:

- a claim-safe terminology seed for the current sign product;
- evidence labels that keep measured search data separate from product truth;
- a U.S.-English source-keyword hierarchy for later localized metadata research;
- future vertical terminology domains that must be versioned rather than hard-coded;
- proof that sign-first discoverability, reports, work history, recheck, and evidence are more important than becoming a generic inspection app;
- boundaries around specialist, certification, safety, legal, and compliance wording;
- a reusable rule that vertical nouns and content packs must not fork navigation, persistence, reports, or billing.

The workbook itself has nine sheets. Its main regions are:

| Sheet | Audited region/table | V30 relevance |
|---|---|---|
| Executive Dashboard | A1:J28, helper formulas through N31 | Canonical current/next vertical summary |
| Vertical Scorecard | A4:AJ23, VerticalScorecard | Formula-driven product-fit sequence and confidence shrinkage |
| Keyword Master | A4:R2020, KeywordMaster | 2,016 U.S.-English source-keyword rows |
| Current Sign Plan | A11:J63 plus metadata at A5:J8 | Claim-safe sign terminology and proposed metadata |
| SERP Competitors | A4:M148, SERPCompetitors | Dated U.S. search evidence |
| App Store Competitors | A4:O89, AppStoreCompetitors | 85 representative U.S. app records |
| Scoring Model | A4:G15 plus A18:G24 | Proposed weights and hard gates |
| Evidence & Sources | A4:H11 plus notes through row 29 | Provenance and evidence definitions |
| Checks | A1:F22 | All recorded checks passed |

The workbook contains 388 formulas across its formula-bearing sheets. A read-only formula-error scan found no REF, DIV/0, VALUE, NAME, or N/A errors. Its canonical product-fit sequence keeps Current Sign at Priority 0, then Exterior & Parking Lighting, Playground & Park Safety, Warehouse Rack Safety, Commercial Irrigation, and Facility Rounds. V30 does not activate those verticals; it uses the ordering only to namespace future terminology and prevent globalized copy from implying unshipped scope.

The package does not provide:

- non-English keyword demand;
- native-language terminology acceptance;
- a translation memory or glossary;
- permission to add a new vertical;
- proof of App Store conversion, profitability, or willingness to pay;
- current 2026-09 metadata rules without revalidation.

Claim-safe source vocabulary:

- Prefer inspection, check, visible condition, photo evidence, PDF report, recorded work, recheck, and night/after-dark.
- Qualify broad terms with sign, sign service, illuminated sign, or sign inspection.
- Do not translate a term into language that implies audit, certification, compliance, diagnosis, automatic pass/fail, repair complete, delivered, accepted, legal proof, photometric measurement, work-order system, or generic inspect-anything capability unless the exact shipped product later proves it.

The workbook's candidate title, subtitle, and keyword field are research inputs only. Each localized metadata set requires fresh native search/terminology work and current App Store Connect validation; literal translation receives no acceptance.

### 7.3 V30 use of keyword research

V30 must create a locale-aware acquisition-research contract rather than translating English keywords literally:

1. Preserve each English source phrase, source, date, country, intent, product-claim gate, and measured/idea-only status.
2. For each supported language, research how practitioners actually describe the workflow; do not assume literal equivalence.
3. Keep App Store name, subtitle, keyword field, screenshot copy, help copy, report terminology, and canonical business identifiers separate.
4. Exclude competitor trademarks, unshipped features, unsupported verticals, certification claims, and jurisdiction claims.
5. Revalidate current Apple metadata limits and duplication rules at the metadata card.
6. Treat every non-English keyword set as a new dated evidence record with a professional linguistic review.
7. Preserve sign-first positioning until an independently authorized vertical program changes product scope.

## 8. Official U.S. demand evidence

The 2024 ACS 1-year detailed tables provide the current national planning snapshot for the U.S. population age five and over:

| Language | Speak at home estimate, 2024 | Speak English less than very well | Planning interpretation |
|---|---:|---:|---|
| Spanish | 44,867,699 ±143,192 | 18,432,221 ±123,301 | Dominant P0 requirement |
| Chinese, including Mandarin and Cantonese | 3,734,956 ±51,891 | 1,895,001 ±26,853 | Population/access evidence only; the table does not identify dialect or script. Shipping both scripts is an owner-approved analyst inference, not a Census conclusion. |
| Tagalog/Filipino | 1,921,526 ±36,451 | 584,724 ±17,379 | Large audience, but Apple metadata/identifier and field-demand research keep it next-wave |
| Vietnamese | 1,599,409 ±35,915 | 918,210 ±26,456 | Required initial |
| Arabic | 1,484,439 ±47,591 | 513,293 ±25,498 | Important next-wave and required RTL architecture target |
| Korean | 1,150,701 ±31,218 | 565,989 ±18,638 | Required initial |
| Portuguese | 1,099,503 ±30,024 | 394,010 ±18,067 | pt-BR is the strongest low-friction next-wave candidate |
| French, including Cajun | 1,276,702 ±33,027 | 279,230 ±14,483 | Separate from Haitian Creole; next-wave |
| Haitian Creole | 1,041,231 ±42,340 | 454,970 ±21,691 | Separate language and regional next-wave candidate |
| Russian | 1,021,165 ±27,056 | 429,378 ±18,594 | Geography-driven next-wave |
| Polish | 508,512 ±20,329 | 185,755 ±10,255 | Geography-driven next-wave |

The older 2019 Census language report remains useful for long-term trends and metropolitan distribution, but V30 ranking uses the newer 2024 counts. ACS language-at-home and self-reported English ability are accessibility proxies, not direct measurements of a technician's preferred work language.

Sources:

- [2024 ACS C16001](https://data.census.gov/table/ACSDT1Y2024.C16001?q=C16001)
- [2024 ACS B16001](https://data.census.gov/table/ACSDT1Y2024.B16001?q=B16001)
- [Census Language Use in the United States: 2019](https://www.census.gov/content/dam/Census/library/publications/2022/acs/acs-50.pdf)
- [2024 ACS language classification definitions](https://www2.census.gov/programs-surveys/acs/tech_docs/subject_definitions/2024_ACSSubjectDefinitions.pdf)

Field-work relevance strengthens Spanish further. BLS 2024 Table 11 reports:

- 8.52 million construction/extraction workers, 41.6 percent Hispanic/Latino;
- 2.293 million construction laborers, 53.9 percent Hispanic/Latino;
- 1.279 million carpenters, 41.4 percent;
- 539,000 painters/paperhangers, 62.9 percent;
- 240,000 roofers, 68.2 percent;
- 4.901 million installation/maintenance/repair workers, 23.6 percent;
- 495,000 HVAC mechanics/installers, 25.4 percent;
- 725,000 general maintenance/repair workers, 23.2 percent.

Ethnicity is not language. These values are used only alongside explicit Spanish-language construction evidence:

- NIOSH reports that Hispanic workers make up roughly one-third of U.S. construction and identifies missing Spanish training material as a safety disparity.
- NIOSH notes that construction workers are more likely than the general workforce to be Hispanic and foreign-born.
- A 2023 NIOSH/CPWR review says Hispanic workers represented over 32 percent of construction, identifies terminology barriers, and notes that most construction-fall resources are available in English and Spanish, with some material also in Polish, Portuguese, and Vietnamese.
- BLS reported that foreign-born workers represented 19.1 percent of the 2025 labor force and were disproportionately represented in natural resources, construction, and maintenance occupations.

Sources:

- [NIOSH construction workforce and Spanish-material evidence](https://www.cdc.gov/niosh/construction/about/index.html)
- [NIOSH construction fall and language evidence](https://www.cdc.gov/niosh/bulletin/2023/falls-stand-down.html)
- [BLS Foreign-Born Workers: Labor Force Characteristics — 2025](https://www.bls.gov/news.release/archives/forbrn_05192026.pdf)
- [BLS 2024 occupation, race, and ethnicity Table 11](https://www.bls.gov/cps/data/aa2024/cpsaat11.htm)
- [CPWR Hispanic-worker research](https://www.cpwr.com/research/published-research/cpwr-reports/hispanic-workers/)

This evidence supports language prioritization. It does not prove that a specific AssetRounds buyer will choose a language, and it cannot replace interviews, support requests, analytics after launch, or translation/support capacity.

## 9. Initial V30 language decision

### 9.1 Decision rule

V30 does not rank languages by one number. It uses five independent lenses:

1. U.S. residents who use the language and the share with limited English ability.
2. Relevance to construction, maintenance, inspection, field service, and the current sign workflow.
3. Direct customer-language requests or failure reports.
4. Language declarations in current comparable iOS binaries, distinguished from broader vendor documentation.
5. Architectural coverage: Latin, CJK, bidirectional, segmentation, case, font, and report behavior.

The initial portfolio is intentionally smaller than the union of competitor language lists. A locale that ships creates ongoing obligations for every new key, error, report, help surface, accessibility label, screenshot, support workflow, and release. A broad but incomplete menu would be worse than a smaller complete cohort.

### 9.2 Required initial cohort

The recommended V30 completion cohort is five language families and six Xcode localizations:

| Priority | User-facing language | Canonical localization policy | Why it is required |
|---:|---|---|---|
| 1 | English | en source and final fallback; en-US launch formatting; en-GB hostile-format validation | Existing source language and U.S. launch baseline |
| 2 | Spanish | es base localization with U.S./Latin-American field terminology; es-US, es-MX, and es-419 formatting/terminology validation; U.S. App Store metadata uses Apple's supported Spanish localization | By far the largest U.S. non-English language, direct field/construction safety relevance, direct Spanish-review signal, and near-universal competitor coverage |
| 3 | Chinese, Simplified | zh-Hans; region remains separate | `ANALYST_INFERENCE / owner-approved cohort default`: ship both scripts so one script is not falsely presented as coverage for the other; this also qualifies non-Latin input, line breaking, search, fonts, and reports |
| 4 | Chinese, Traditional | zh-Hant; region remains separate | `ANALYST_INFERENCE / owner-approved cohort default`: independently translate and review this script; ACS does not identify script preference and does not itself require either script |
| 5 | Vietnamese | vi | Large U.S. language population, meaningful limited-English and construction-resource signal, and recurring field-app support |
| 6 | Korean | ko | Large U.S. population with material language-access need, recurring iOS field-app support, and additional CJK qualification value |

English is one family/localization. Chinese is one spoken-language family represented by two required script localizations. Therefore V30 has five language families and six declared-complete localizations.

This is a planning recommendation, not a shipping claim. The owner-approved bootstrap authority must pin the cohort before activation. V30-P01-C01 may refresh evidence, verify Xcode identifiers and support capacity, and confirm that exact pinned cohort; it cannot silently refreeze a different one. Any changed owner decision returns `AMENDMENT_REQUIRED`, earns no card credit, and requires an append-only package amendment, regenerated graph/structural projection, and explicit admission transition before downstream implementation. Removing a locale before activation requires an explicit owner rationale.

### 9.3 Why not simply select the next largest raw Census rows

| Language/group | Disposition | Reason |
|---|---|---|
| French | NEXT_WAVE | The Census row groups French, Haitian, Cajun, and related varieties, but a fr catalog does not serve Haitian Creole. French is extremely common among competitors and is a leading next-wave candidate, especially if Canada enters scope. |
| Tagalog/Filipino | NEXT_WAVE | The population is large, but the product must validate Apple's current language identifier/display name, practitioner terminology, demand, and support capacity. Use canonical fil if Apple/Xcode supports it; do not assume tl or that English proficiency removes user need. |
| Arabic | NEXT_WAVE, architecture-required now | Important U.S. language and real RTL target. V30 must be Arabic-ready and run hostile Arabic/bidi fixtures now, but a complete ar catalog requires dedicated professional review and support. Promote it when customer geography supports it. |
| Brazilian Portuguese | NEXT_WAVE | Strong construction relevance and competitor recurrence; use pt-BR, never generic Portuguese to imply pt-PT quality. |
| Russian and Polish | NEXT_WAVE | Relevant population and construction-resource signals; prioritize by customer geography and paid demand. |
| French Canada | CONDITIONAL_PROMOTION | If Canada becomes an initial commercial market, fr-CA must move into the required cohort and Canadian legal, privacy, support, units, report, and storefront work must also activate. |
| German, Italian, Dutch, Japanese, Turkish, Norwegian, Swedish, Czech, and others | FUTURE_RESEARCH | Many recur in global competitor portfolios, but that reflects broad international distribution more than U.S.-first AssetRounds demand. |

No language is treated as covered by a neighboring language. French is not Haitian Creole; Brazilian Portuguese is not European Portuguese; Simplified Chinese is not Traditional Chinese; Spanish terminology varies by region; and Arabic requires regional review when a country is activated.

### 9.4 Required next-wave ordering

The first re-entry study after V30 phase close evaluates, in this order:

1. pt-BR;
2. fil;
3. ar;
4. fr and fr-CA;
5. ru;
6. pl;
7. hi;
8. id;
9. ja;
10. tr.

This is a research order, not an automatic implementation order. Actual customers, geography, support tickets, language fallback observations, storefront strategy, professional-review capacity, and legal/jurisdiction readiness can change it through a recorded decision.

### 9.5 Competitor cross-check

The 2026-09-02 U.S. App Store snapshot covered Mitti/SafetyCulture, MaintainX, UpKeep, GoCanvas, Fulcrum, Fieldwire, ArcGIS Field Maps, ArcGIS Survey123, and Autodesk Construction Cloud/Forma.

Across those named current iOS listings:

- English appeared in nine of nine.
- Spanish, French, German, and Portuguese appeared in eight of nine.
- Russian and Simplified Chinese appeared in seven of nine.
- Korean appeared in five of nine.
- Arabic and Vietnamese appeared in four of nine.
- MaintainX was the important mismatch: its current U.S. iOS listing declared English while vendor documentation described a much broader platform language set.

This is a dated `ANALYST_PORTFOLIO_SIGNAL`, not runtime testing, demand, UX quality, translation completeness, metadata coverage, or global storefront proof. P01-C01 must append one evidence record per listing with the territory, exact URL, capture timestamp, visible app version/date or `NOT_VISIBLE`, Apple's raw ordered language field, separately normalized identifiers, source type, vendor-document discrepancy, and staleness. Every current row starts `BINARY_NOT_TESTED`; it can advance only through exact observed runtime evidence. Observations are current for at most 30 days, aging through day 90, stale afterward, and immediately refresh-required after a rename, major version, language-list change, or unresolved vendor/listing conflict. Competitor recurrence supports architecture and a next-wave register, but cannot outweigh U.S. audience fit or the cost of complete reports, help, accessibility, offline behavior, and support.

Current comparison sources:

- [Mitti by SafetyCulture App Store](https://apps.apple.com/us/app/mitti-by-safetyculture/id499999532)
- [MaintainX App Store](https://apps.apple.com/us/app/maintainx-cmms-eam/id1437854484)
- [UpKeep App Store](https://apps.apple.com/us/app/upkeep-work-order-maintenance/id921799415)
- [GoCanvas App Store](https://apps.apple.com/us/app/gocanvas-business-forms/id418917158)
- [Fulcrum App Store](https://apps.apple.com/us/app/fulcrum-gis-field-data-capture/id467758260)
- [Fieldwire App Store](https://apps.apple.com/us/app/fieldwire-construction-app/id780165517)
- [ArcGIS Field Maps App Store](https://apps.apple.com/us/app/arcgis-field-maps/id1515671684)
- [ArcGIS Survey123 App Store](https://apps.apple.com/us/app/arcgis-survey123/id993015031)
- [Autodesk Construction Cloud App Store](https://apps.apple.com/us/app/autodesk-construction-cloud/id498795789)

### 9.6 LocaleMarketMatrixV1

Binary resources, formatting tests, App Store metadata, storefront availability, project jurisdiction, support, and product claims are independent machine facts. The activated package must carry one `LocaleMarketMatrixV1` row per binary localization:

| Binary localization | Required formatting/profile tests | Permitted U.S. App Store metadata draft | Storefront | Project jurisdiction | Support status before acceptance | Claim status before acceptance |
|---|---|---|---|---|---|---|
| en | en-US; hostile en-GB; cross-axis calendar/numbering/unit cases | English (US) | United States only | United States | PLANNED_REQUIRED_INITIAL | NOT_SUPPORTED_UNTIL_ACCEPTED |
| es | es-US, es-MX, es-419; cross-axis es plus U.S. region | Spanish (Mexico) | United States only | United States | PLANNED_REQUIRED_INITIAL | NOT_SUPPORTED_UNTIL_ACCEPTED |
| zh-Hans | zh-Hans app language plus U.S. region; hostile region=CN formatting without changing resource identity | Chinese (Simplified) | United States only | United States | PLANNED_REQUIRED_INITIAL | NOT_SUPPORTED_UNTIL_ACCEPTED |
| zh-Hant | zh-Hant app language plus U.S. region; hostile region=TW formatting without changing resource identity | Chinese (Traditional) | United States only | United States | PLANNED_REQUIRED_INITIAL | NOT_SUPPORTED_UNTIL_ACCEPTED |
| vi | vi app language plus U.S. region; hostile region=VN formatting without changing resource identity | Vietnamese | United States only | United States | PLANNED_REQUIRED_INITIAL | NOT_SUPPORTED_UNTIL_ACCEPTED |
| ko | ko app language plus U.S. region; hostile region=KR formatting without changing resource identity | Korean | United States only | United States | PLANNED_REQUIRED_INITIAL | NOT_SUPPORTED_UNTIL_ACCEPTED |

All metadata values are localizable draft assets only until P06-C05 and owner release authority. Apple currently lists English (US) as the U.S. default and Spanish (Mexico), Simplified Chinese, Traditional Chinese, Korean, and Vietnamese as additional U.S. metadata languages; it does not offer an App Store metadata locale named Spanish (U.S.). The metadata label never changes the bundled resource identifier. Storefront remains U.S.-only, jurisdiction remains U.S., and no App Store Connect mutation occurs before P07-C02 owner action.

Every matrix revision binds its source date, Apple reference digest/capture, package revision, candidate head/tree, and owner decision. Unknown, unsupported, mismatched, or changed metadata capability creates HOLD; it cannot remove a required binary localization or activate another storefront implicitly.

Official source: [Apple App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations).

## 10. Language selection and fallback experience

### 10.1 System-first rule

AssetRounds follows Apple's language selection:

1. iOS compares the person's ordered preferred languages with the localizations declared by the app.
2. If the person selected a per-app language in Settings, iOS uses it.
3. If no supported match exists, AssetRounds uses English.
4. Region, calendar, numbering system, units, and time zone remain independent inputs.

At the frozen V23 head, AssetRounds has only English catalog content, so a Spanish-language iPhone receives English app UI. After accepted V30 completion, a Spanish-language device or per-app Spanish choice resolves to the bundled es catalog automatically. An unsupported language resolves to English.

Official sources:

- [Apple localization overview](https://developer.apple.com/documentation/xcode/localization)
- [How iOS determines the language for an app](https://developer.apple.com/library/archive/qa/qa1828/_index.html)
- [Apple language identifier fallback](https://developer.apple.com/library/archive/technotes/tn2418/)
- [Apple String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)

### 10.2 AssetRounds Settings row

AssetRounds Settings must include a localized Language & Region section that:

- displays the effective app language;
- displays the effective formatting region;
- explains that app language and worksite jurisdiction are different;
- opens the app's iOS Settings page when the system supports a per-app choice;
- returns safely after foregrounding and reports the new effective language;
- never claims an unsupported locale;
- remains usable offline;
- exposes a diagnostic support summary without personal data.

V30 does not use Bundle swizzling, private APIs, or a custom runtime localization override. An optional fully in-app picker is a future product decision only if Apple offers a supported public mechanism and research proves that the Settings handoff is inadequate.

### 10.3 Fallback contract

The logical fallback order is:

1. exact declared language/script/region resource;
2. declared base language resource when valid;
3. English;
4. a visible fail-closed diagnostic only in test/development builds.

Rules:

- `APP_OWNED_SHIPPING` means a frozen inventory item whose disposition is an app-owned, user-facing shipping surface in the declared cohort: visible UI, app-provided accessibility semantics, app-owned permission and notification copy, help, errors, recovery, destructive actions, report/export chrome, and approved localizable metadata draft assets.
- System-rendered OS UI, verbatim user/admin-authored content, imported evidence, machine-readable identifiers/enums, developer/debug text, test-only pseudolocales, obsolete or unreachable items, and explicit approved do-not-translate entries are outside `APP_OWNED_SHIPPING`; every exclusion still requires an inventory disposition and owner.
- A locale declared complete must have zero unresolved keys and zero unexpected English fallback for every `APP_OWNED_SHIPPING` item exercised by the frozen coverage matrix.
- An unresolved key is a stable key, missing-resource placeholder, or other unapproved unresolved value emitted by an `APP_OWNED_SHIPPING` render path.
- Unexpected English fallback is an English resolution in a declared-complete non-English language without an approved do-not-translate disposition or explicitly accepted fallback rule.
- Fallback observations are deterministic, privacy-preserving, and locally inspectable; no analytics SDK is introduced.
- A missing destructive, safety, permission, recovery, or data-loss warning is a release blocker.
- User-authored text is not a fallback resource and is never replaced.

### 10.4 Report language

Report language is separate from app language:

- default to the current app language when that report catalog is complete;
- permit an explicit supported report-language choice at export;
- preserve user-authored evidence exactly;
- record report language, formatting locale, time zone, calendar, units, paper size, catalog version, renderer version, and font release in provenance;
- fall back to English only under a visible, user-confirmed rule;
- never silently translate inspector notes, customer text, signatures, captions, or imported content.

## 11. Domain model and invariants

### 11.1 Proposed typed concepts

V30 should extend the existing V23 contracts with narrowly scoped, versioned types equivalent to:

| Concept | Required meaning |
|---|---|
| AppLanguageTagV1 | Canonical BCP 47 tag for a declared app localization |
| LanguageResolutionV1 | Requested, matched, effective, fallback reason, catalog release, and observation time |
| LocalePresentationProfileV1 | Region, calendar, numbering system, time zone, week rules, measurement system, currency, and paper policy |
| ReportLanguageSelectionV1 | Explicit report language and fallback confirmation |
| AuthoredContentLanguageV1 | Optional source-language declaration for user/admin content; UNKNOWN is allowed |
| TranslationDerivationV1 | Source hash, source language, target language, method, revision, reviewer, created time, and invalidation state |
| LocalizationCatalogReleaseV1 | Language, key-set version, content digest, source revision, compatibility, and supersession |
| TermbaseEntryV1 | Stable concept ID, approved terms, context, forbidden alternatives, do-not-translate rule, locale, and reviewer |
| JurisdictionReferenceV1 | Country/subdivision and licensed/versioned pack identity; never inferred from language |
| LanguageCapabilityMatrixV1 | UI, report, OCR, dictation, speech, search, fonts, offline, metadata, and support truth per locale |
| LocaleAcceptanceReceiptV1 | Exact catalog/build/test/reviewer evidence and zero-fallback acceptance |

These names are design intent, not permission to create parallel files. The active card must first map them to existing V23 types and reuse or version-forward those types when possible.

### 11.2 Six separate axes

The following are never collapsed into one locale string:

| Axis | Example | Controls | Must not control |
|---|---|---|---|
| App language | es | App-owned UI and accessibility copy | Jurisdiction, canonical IDs, authored evidence |
| Formatting locale | es-US | Dates, numbers, currency, week rules | Translation validity or standards |
| Authored-content language | es | A label on user/admin content | Automatic translation or canonical identity |
| Report language | en | App-owned report chrome | Source evidence text |
| Storefront country | US | App Store availability and metadata | Worksite jurisdiction |
| Project jurisdiction | US-PA | Licensed rules, packs, claims | App language or formatting |

### 11.3 Canonical-data invariance

Changing app language or formatting locale must not change:

- workspace, project, site, asset, sign, inspection, issue, work, or recheck identity;
- enum raw values or machine-readable field names;
- mutation and journal identity;
- evidence bytes and evidence hashes;
- backup identity and source-data digests;
- relationship keys or event order;
- standards/jurisdiction selection;
- source-authored notes, captions, signatures, labels, or imported values;
- eligibility, billing, or product identity.

Localized strings are presentation. A localized report is a derived artifact with explicit provenance. A derived translation is never canonical evidence.

### 11.4 Historical preservation

- Existing en-US-bearing version IDs remain unchanged.
- A new locale-aware version supersedes through an explicit link.
- Old records remain readable without rewriting their hashes.
- Historical report replay binds the original catalog, renderer, font, layout, time-zone, and formatting versions when available.
- If an old catalog cannot be loaded, the app reports the limitation; it does not silently regenerate a different artifact and call it identical.

## 12. String-catalog architecture

### 12.1 Key policy

- Keys are stable semantic identifiers, not English sentences.
- Keys do not contain customer data, asset IDs, or mutable copy.
- Every key has a developer comment with screen, meaning, subject, grammatical role, placeholders, plural/select behavior, accessibility use, and screenshot context.
- Identical English text with different meanings receives different keys.
- A changed English sentence does not force a new key unless semantics or placeholders change.
- Removed keys receive a recorded retired/superseded disposition; they are not silently reused.
- Permission strings, notifications, Settings, widgets/extensions if any, reports, help, errors, accessibility, and release metadata have explicit inventory owners.

### 12.2 Placeholder and grammar policy

- Use typed interpolation.
- Prove placeholder name, type, cardinality, and privacy classification match every locale.
- Use String Catalog plural and variation support rather than concatenation.
- Never assemble sentences from independently translated fragments.
- Do not assume English word order, capitalization, gender, number, articles, or punctuation.
- Keep numeric IDs and codes isolated with bidirectional-safe presentation.

### 12.3 Catalog release policy

V30 separates release machinery from a content-bearing catalog release. P01-C08 may introduce only the versioned release schema, validator, compatibility model, offline-loading contract, and migration rules. It may validate the pre-existing English/Base catalog, but it cannot claim a complete locale release, reviewer acceptance, final key-set/content digest, or final app-candidate binding.

The first content-bearing `LocalizationCatalogReleaseV1` set is created only by P04-C07 after English normalization, all required locale lanes, and shared catalog/project integration. Each such release binds:

- exact candidate head and tree;
- exact key-set digest;
- translation digest;
- locale and script;
- source English revision;
- termbase revision;
- professional translator and independent reviewer roles without embedding secrets;
- automated validation results;
- screenshot/in-context review evidence;
- fallback policy;
- compatibility and supersession;
- a complete content/provenance manifest.

A correction creates a new release revision and preserves the superseded release. A release is usable as acceptance evidence only for the exact candidate head/tree and exact catalog digests it names. Catalogs required at startup and during offline field work are bundled. V30 does not require a network translation service.

## 13. Locale-aware presentation and input

### 13.1 Dates, time, and time zones

- Store instants canonically and time zones as IANA identifiers where a zone is part of the domain.
- Display with Foundation formatters and explicit locale/time-zone/calendar inputs.
- Distinguish an instant from a local wall time.
- Reject or explicitly resolve nonexistent DST gap times.
- Disambiguate repeated DST overlap times.
- Avoid ambiguous numeric dates in destructive, contractual, or report-critical confirmation.
- Persist report-generation time zone and local offset.
- Test 12-hour/24-hour clocks, first-day-of-week variation, and multiple calendars without changing canonical records.

### 13.2 Numbers, money, percentages, and measurements

- Parse with a visible locale and unit context.
- Store canonical numeric values and explicit units.
- Reject ambiguous mixed separators rather than guessing.
- Round only at the presentation boundary under a versioned rule.
- Use StoreKit localized price/duration behavior for commerce; never construct prices by string.
- Support U.S. customary and metric display while preserving canonical values.

### 13.3 Paper, addresses, and phones

- Reports support U.S. Letter and A4 through explicit layout profiles.
- Address fields remain structured where the domain provides structure and freeform where structure would destroy data.
- Phone display can format for readability, but canonical storage never discards extensions, international prefix, or original user input without an explicit normalized value.
- Postal assumptions never select a jurisdiction or language.

### 13.4 Input and keyboards

- Preserve extended grapheme clusters, combining marks, emoji, CJK, Arabic, right-to-left text, and valid bidirectional content.
- Do not limit text by UTF-16 code-unit count when the product promise is character-oriented.
- Keep composed text safe during IME entry.
- Do not normalize evidence destructively.
- Use normalization only for derived search keys and record the algorithm version.

## 14. Unicode, RTL, layout, and accessibility

### 14.1 Unicode end to end

Unicode must survive:

- text entry and editing;
- local persistence and journals;
- search indexing and rebuild;
- filenames and attachment captions;
- QR/barcode-associated labels;
- backup and restore;
- JSON and CSV;
- PDF generation and extraction;
- printing, email, and share sheets;
- deterministic snapshots and reports.

No renderer may substitute a question mark for a supported scalar. Invalid text or unsupported glyphs must fail visibly in tests and safely in production.

### 14.2 Right-to-left readiness

Even though Arabic is next-wave, V30 foundation must:

- mirror directional layout with semantic leading/trailing APIs;
- preserve non-directional icons where mirroring would change meaning;
- keep serial numbers, dates, measurements, URLs, phone numbers, and codes readable in mixed-direction lines;
- prevent unsafe invisible-control abuse in identifiers and exports;
- validate navigation, back direction, lists, charts, reports, signatures, and focus order with a pseudo-RTL locale plus hostile Arabic fixtures;
- avoid claiming Arabic support until an ar catalog and human review pass.

### 14.3 CJK readiness

The required Chinese localizations and Korean must validate:

- font coverage and licensing;
- word/line breaking;
- no forced spaces;
- IME composition;
- search segmentation and stable tie-breaks;
- vertical and compact label pressure;
- PDF shaping, subset embedding, extraction, and printing;
- VoiceOver pronunciation context where controllable.

### 14.4 Dynamic layout

Every critical flow passes:

- smallest supported iPhone and largest relevant iPhone;
- portrait and every product-supported orientation;
- standard through largest accessibility Dynamic Type;
- longest real translations;
- deterministic expansion pseudolanguage;
- light, dark, and increased contrast where supported;
- keyboard shown and dismissed;
- no clipped action, hidden destructive warning, overlapping field, truncated status, or unreachable recovery path.

### 14.5 Localized accessibility

- Accessibility labels, values, hints, actions, headings, rotor order, and error announcements are localized.
- Visible text and accessibility text use the same semantic key family where meanings match.
- Scanner, photo, signature, progress, sync, conflict, and destructive states never rely on color alone.
- VoiceOver reading order follows semantic order after RTL mirroring.
- Translation quality review includes accessibility copy, not only visible labels.

## 15. Search, sorting, and identifiers

- Search is diacritic-aware without destroying exact evidence.
- Derived normalization has a version, deterministic rebuild, recovery, erase, backup, and restore rules.
- Chinese requires an explicit segmentation policy; character-substring fallback must be measured and documented.
- Korean composition remains intact.
- Turkish dotted/dotless I remains in hostile fixtures even while Turkish is not a required shipping locale.
- Arabic normalization fixtures must not erase meaning.
- Locale-aware display sorting uses a stable canonical tie-breaker.
- IDs, QR values, enum raw values, asset numbers, and machine keys are never translated.
- Search results show enough stable context that a translated label cannot cause selection of the wrong asset.

## 16. Authored content and translation boundaries

AssetRounds has at least four content layers:

1. App-owned UI and report chrome.
2. Owner/admin-authored templates, instructions, labels, and content packs.
3. Inspector/customer-authored notes, captions, signatures, and evidence.
4. Licensed or jurisdiction-specific standards and professional content.

Rules:

- V30 translates layer 1 for declared-complete locales.
- Layer 2 remains in its authored language unless separately translated and versioned by its owner.
- Layer 3 remains verbatim. A derived translation may coexist only under a future separately authorized service with provenance and invalidation.
- Layer 4 requires license, source, jurisdiction, reviewer, and version authority; translation never expands its legal scope.
- The UI visibly distinguishes app translation from authored content.
- Editing or redacting source content invalidates derived translations deterministically.
- No customer data is sent to a translation vendor during catalog work.

## 17. Reports, exports, backup, and historical replay

### 17.1 PDF and accessible documents

The renderer must:

- eliminate ASCII-only replacement;
- use qualified fonts with appropriate licenses and glyph coverage;
- shape bidirectional and CJK text correctly;
- embed or subset fonts deterministically where permitted;
- preserve photo/comment association, numbering, status, and pagination;
- support Letter and A4;
- retain selectable/extractable text where possible;
- preserve semantic reading order and accessibility metadata where the format supports it;
- include explicit document language and provenance;
- reproduce identical bytes when all versioned inputs and deterministic conditions are identical, or document the exact nondeterministic fields.

### 17.2 JSON and CSV

- Canonical JSON keys and enum values remain language-neutral.
- CSV machine export defaults to stable headers and locale-independent machine values.
- An optional localized-human CSV is a distinct artifact with a locale manifest.
- Escape formula-leading cells safely.
- Media and signatures use explicit references/manifests rather than disappearing from CSV.
- Import never infers canonical numbers or dates from ambiguous localized text.

### 17.3 Backup and restore

- Backups preserve source content, canonical data, catalog references, renderer/font versions, and derived-artifact provenance.
- Restore does not require the original app language.
- Missing historical resources produce an explicit limitation.
- Search indexes and rendered artifacts are rebuildable derived state unless the governing contract says otherwise.
- Erasure removes source and derived content according to existing data-right rules.

## 18. Offline, notifications, errors, and recovery

Globalization may not weaken offline behavior:

- every required catalog, destructive warning, sync/error state, and report shell is bundled;
- language switching never requires a network request for core app copy;
- queued evidence preserves Unicode and original authored language;
- pending/saved/syncing/synchronized/failed/conflicted/recovered states are distinguishable, localized, and accessible;
- notifications and deep links resolve to the same semantic state in every language;
- help, recovery, backup, restore, permissions, subscription, and data-loss copy is included in the surface inventory;
- a failed localized operation never falls back to a vague success message.

The card may harden localization of existing offline/sync behavior. It cannot create a new synchronization engine or backend.

## 19. Translation operations

### 19.1 Workflow

1. Freeze English source keys and semantic comments for one revision.
2. Freeze the termbase and do-not-translate list.
3. Export through Apple's supported localization workflow.
4. Translate with a qualified professional familiar with field inspection and construction terminology.
5. Validate placeholders, plurals, variants, file integrity, and key completeness mechanically.
6. Import into a locale-owned path fence.
7. Run pseudolanguage and locale-specific unit tests.
8. Capture deterministic in-context screenshots.
9. Obtain an independent native/professional review of critical workflows, reports, errors, destructive actions, accessibility, and metadata.
10. If review returns `CORRECTION_REQUIRED`, use the direct-child same-logical-card `correctionOf` law, correct append-only through the causal owner, create a new catalog release through P04-C07, create fresh P05-C04/P05-C05/P05-C06 receipts, and repeat P06-C01 and P06-C02 before any later P06 qualification or readiness card can receive credit. Repeat P05-C02 only when the replay map changes and P05-C03 only when V23 disposition changes.

Sources:

- [Preparing app text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)
- [Exporting localizations](https://developer.apple.com/documentation/xcode/exporting-localizations)
- [Creating screenshots for localizers](https://developer.apple.com/documentation/xcode/creating-screenshots-of-your-app-for-localizers)
- [Testing localizations](https://developer.apple.com/documentation/xcode/testing-localizations-when-running-your-app)

### 19.1.1 Same-candidate linguistic-review and reopen law

A locale-acceptance candidate is the tuple:

`(candidateHead, candidateTree, bundledCatalogDigest, perLocaleCatalogReleaseDigests, requiredKeySetDigest, termbaseDigest, renderedReviewArtifactDigests)`.

P06-C01 machine audit binds this complete tuple. P06-C02 reviews only that tuple and has exactly two terminal outcomes:

1. `ACCEPTED_NO_CORRECTION`: every required professional, independent, and bilingual-workflow receipt is hash-bound to the tuple; no catalog, source, termbase, fixture, report, or product byte changed after the reviewed artifact was generated.
2. `CORRECTION_REQUIRED`: the receipt identifies the affected locale/content digest and required correction, but provides no linguistic acceptance, implementation, verification, metadata, jurisdiction, or release credit.

A `CORRECTION_REQUIRED` result returns to the causal implementation owner through a direct-child correction candidate that retains the same logical card ID and records `correctionOf` the rejected exact tuple/receipt. A locale-only correction repeats the causal locale work and P04-C07, creates fresh P05-C04, P05-C05, and P05-C06 receipts, then repeats P06-C01 and P06-C02. A shared English source or termbase correction returns to its shared owner and repeats every affected locale lane before P04-C07. Repeat P05-C02 only when the B/P/S replay map changes; repeat P05-C03 only when V23-disposition evidence changes. All downstream P06 receipts are superseded for acceptance and retained append-only as provenance; no correction creates, skips, renumbers, or adds graph cards or edges.

P06-C03, P06-C04, P06-C05, P06-C06, and P06-C07 may consume only an `ACCEPTED_NO_CORRECTION` tuple. Every receipt they produce must name that same tuple. A head, tree, catalog digest, release digest, key-set digest, termbase digest, or rendered-artifact digest mismatch is fail-closed and requires the applicable audit, review, qualification, or integration to be rerun.

### 19.2 Termbase

The termbase must cover:

- AssetRounds product terms;
- sign, site, asset, inspection, round, issue, work, recheck, evidence, report, history, backup, restore, subscription, and status terms;
- actions versus nouns;
- severity and confidence language;
- allowed observation wording;
- forbidden certification, guarantee, diagnosis, legal, and compliance wording;
- abbreviations and unchanged identifiers;
- regional alternatives and reviewer notes;
- future vertical namespaces from the verified keyword research.

CPWR's Spanish research found that direct translations can fail when terms are not understandable across different Hispanic backgrounds. Therefore V30 Spanish review must test comprehension and regional neutrality, not merely grammatical correctness.

### 19.3 Translation supply-chain safety

- Translation vendors receive source strings, comments, screenshots with synthetic data, and the minimum needed context.
- No real customer, inspector, location, photo, report, contact, or account data leaves the repository for translation.
- Vendor deliverables have hashes, source revision, locale, translator role, reviewer role, license/usage terms, and receipt.
- Machine translation can assist a nonshipping draft only; it never earns linguistic acceptance.
- Corrections append a new catalog release and preserve the superseded one.

## 20. Card execution contract

Every selected card must be independently hydratable and auditable. The machine register and `docs/design/v30/execution/V30_CURRENT_TASK.md` must expand the following fields:

| Field | Requirement |
|---|---|
| cardID | Exact immutable V30-Pxx-Cyy identifier |
| ordinal | Unique integer 1 through 55 |
| class | FOUNDATION, IMPLEMENTATION, VERIFICATION, INTEGRATION, OWNER_ACTION, VALIDATE_NEXT, DEFER, or MONITOR |
| executionEpoch | PRE_S10_PROVISIONAL, POST_S10_RECONCILIATION, FINAL_ACCEPTANCE, or POST_ACCEPTANCE |
| directPrerequisites | Exact card IDs only; no ranges, prose, or implied edges |
| outcome | One measurable product or governance result |
| allowedPaths | Fully expanded repository-relative files; no globs, folders, brace expressions, or inferred app-root shorthand |
| forbiddenPaths | Explicit paths/surfaces that would create scope or ownership collisions |
| s10SharedPaths | Exact subset of allowedPaths that intersects the frozen 86-path reservation |
| base | Exact accepted or provisional predecessor head and tree appropriate to the epoch |
| authority | Exact package, plan, runbook, context, fence, ledger, projection, and receipt digests |
| selector | Exact hosted macOS tier and test selectors, or NONE with a reason |
| acceptance | Static, unit, UI, report, locale, linguistic, owner, or integration evidence appropriate to the class |
| credit | Canonical object `{provisionalDependencySatisfied,finalCredit,canonicalAcceptance,postS10SuccessorStart,mainIntegrationCredit,releaseCredit}`. Pre-S10 checkpoints may set only `provisionalDependencySatisfied=true`; every other field remains false. V24 provenance separately retains `noCredit=true` on all 97 disposition rows. |
| next | Sole immediate eligible successor or exact fan-out set after checkpoint/acceptance |

Rules:

- The owner-supplied companion prompt and package permit one current V30 card at a time in the dedicated V30 worktree.
- The machine register's 37-card `PRE_S10_PROVISIONAL` cohort may execute before Phase 10.6 only as provisional work. Its terminal pre-S10 state is `PROVISIONAL_CHECKPOINTED`, never `ACCEPTED`.
- The machine register's 18-card post-S10 cohort is not selectable before the owner reports Phase 10.6 complete and V30-P05-C01 independently verifies the exact accepted evidence.
- A pre-S10 card may touch an S10-reserved path only when pre-existing external owner authority contains the exact tuple `{cardID,path,expectedBBlobHashOrABSENT,boundedPurpose,writerLane,reconciliationObligation}` and the exact path is listed in that card's fence and `s10SharedPaths`; every such byte is automatically `S10_SHARED_RECONCILIATION_REQUIRED`. Blueprint prose, a card, or a generated context cannot enlarge this set. Missing or mismatched tuple is `CONFLICT_HOLD` with no mutation.
- The Phase 10 checkout `C:\AssetRounds` is never an allowed read, status, build, test, Git, process, or mutation target. The owner supplies the completion trigger; Codex does not poll it.
- The V30 provisional branch does not write the canonical V23 coordination repository. It uses a namespaced provisional ledger whose genesis imports V23 sequence 626 and the pinned digests as immutable observations.
- Parallel subagents may perform read-only preparation only. Exactly one selected card may mutate, checkpoint, transition, or hold the provisional writer at a time; no parallel agent may mutate under the same current card.
- A locale resource lane never edits shared project metadata; one integration lane owns shared catalog/project files.
- A card cannot raise its own file cap, broaden its class, alter prerequisites, or declare its own acceptance.
- Static preparation, Windows tests, provisional branch CI, post-S10 CI, professional review, exact-main integration, owner action, and release remain distinct evidence.
- A correction is a direct-child candidate retaining its logical card ID and `correctionOf`; it preserves all failed/superseded evidence and follows the closed locale/reconciliation reopen law in §19.1.
- A later card cannot be pre-implemented through a convenient seam.
- `provisionalDependencySatisfied` means only that a `PROVISIONAL_CHECKPOINTED` predecessor may unlock the next pre-S10 provisional card. It is distinct from `finalCredit`, `canonicalAcceptance`, and `postS10SuccessorStart`. P05 rehydrates and replays every P00–P04 card in order. A provisional checkpoint may become canonically accepted only after its reconciled head/tree and all invalidated evidence pass under separately supplied post-S10 authority.

## 21. Closed 55-card graph

The graph has 55 unique cards and 107 unique direct edges. The register marks exactly 37 cards `PRE_S10_PROVISIONAL_ELIGIBLE` after package activation and exactly 18 cards `POST_S10_NOT_SELECTABLE` until their named gates are satisfied. No pre-S10 result receives final implementation, acceptance, phase-close, main, release, or successor credit.

### P00 — Pre-S10 provisional authority and admission

The external owner message activates package installation; it is not a card and earns no credit. P00 validates that activation, creates the isolated governance lane, and admits exactly P01-C01.

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 1 | V30-P00-C01 — Provisional authority and isolated-lane validation | FOUNDATION | [] | Validate the owner-supplied pre-existing `V30PreS10ProvisionalImplementationAuthorityV1`, immutable-four-file package/manifest/support-artifact hashes, exact frozen V23 base, repository identity, clean dedicated worktree/branch, Phase 10 no-read/no-poll rule, and zero-credit posture. The closed bootstrap exception permits only external-owner-authorized branch/support installation, G3 ledger/activation receipt/current-task/selector genesis, and this validation; no product work. Any mismatch is a read-only hold. |
| 2 | V30-P00-C02 — Frozen V23/S10 reservation and provisional-fence proof | FOUNDATION | [V30-P00-C01] | Bind V23 head/tree, V23 package and coordination sequence/digests, the ordered 86-path S10 reservation, and the path classification algorithm. An overlap is allowed only when pre-existing external authority supplies its exact tuple `{cardID,path,expectedBBlobHashOrABSENT,boundedPurpose,writerLane,reconciliationObligation}` and the path is card-owned `S10_SHARED_RECONCILIATION_REQUIRED`; it can never earn pre-S10 acceptance. |
| 3 | V30-P00-C03 — Namespaced provisional coordination genesis validation | FOUNDATION | [V30-P00-C01,V30-P00-C02] | Validate, schema-seal, and exercise the sole G3-created expected-absent provisional-ledger genesis at the authority-pinned isolated coordination locator/ref, including distinct ID/writer generation/digest chain and immutable V23 observations. Never create a second genesis, mutate, or claim succession to the canonical V23 ledger. |
| 4 | V30-P00-C04 — Provisional candidate and reconciliation-manifest contract | FOUNDATION | [V30-P00-C02,V30-P00-C03] | Define per-card base/candidate head/tree/diff/evidence/path-overlap manifests, exact B/P/S lineage mappings, compatibility classes, invalidation rules, and replay/reimplementation requirements for P05. |
| 5 | V30-P00-C05 — Provisional CI and checkpoint contract | VERIFICATION | [V30-P00-C03,V30-P00-C04] | Freeze the permitted Windows-static and hosted-macOS development routes, exact selectors/artifacts, retry/correction law, and explicit statement that every result is provisional branch evidence only. Adapt only the isolated V30 branch copies of `.github/workflows/ios-ci.yml`, `Scripts/test-smoke.sh`, and `Scripts/ui-smoke.sh` to the typed V30 selector, under their exact frozen-B fences and S10 tuples. Never modify the inherited selector, active Phase 10 checkout/ref/runs, or main. Unavailable optional hosted diagnostics remain NOT_EXECUTED with no native credit and do not block static provisional coding. |
| 6 | V30-P00-C06 — Provisional execution admission | INTEGRATION | [V30-P00-C04,V30-P00-C05] | Seal package activation and provisional genesis with a separate CAS, project only V30-P01-C01 into the V30 current-task lane, and prove the complete graph-enumerated post-S10 cohort remains unselectable. No card acceptance, `main`, Phase 10, release, or successor credit. |

### P01 — Research freeze, inventory, and durable contracts

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 7 | V30-P01-C01 — Research manifest and initial-language confirmation | FOUNDATION | [V30-P00-C06] | Refresh official ACS/BLS/NIOSH/OSHA/Apple sources, competitor iOS declarations, vendor gaps, reviews, keyword evidence, support capacity, and U.S. geography. Confirm en, es, zh-Hans, zh-Hant, vi, and ko; a different cohort is `AMENDMENT_REQUIRED`. |
| 8 | V30-P01-C02 — Customer-needs and scope-disposition register | FOUNDATION | [V30-P01-C01] | Convert review/research themes into PRESERVE_IN_V30, VERIFY_EXISTING_BEHAVIOR, FUTURE_CARD, or REJECT_SCOPE. Bind the verified keyword package without authorizing new backends or modules. |
| 9 | V30-P01-C03 — Complete text-bearing surface inventory | FOUNDATION | [V30-P01-C02] | Inventory UI, accessibility, permissions, onboarding, help, errors, recovery, destructive actions, notifications, reports, PDFs, CSV/JSON, templates, content packs, labels, share/email/print, commerce, metadata, tests, developer text, user-authored content, and machine data. Give every item an owner and disposition. |
| 10 | V30-P01-C04 — Language, locale, content, report, storefront, and jurisdiction contracts | IMPLEMENTATION | [V30-P01-C01] | Version-forward existing V23 contracts for BCP 47 app language, formatting locale, IANA time zone, calendar, numbering, units, authored content, report language, storefront country, and jurisdiction. Prove the six axes are independent. |
| 11 | V30-P01-C05 — Canonical-data and historical-identity invariance | IMPLEMENTATION | [V30-P01-C04] | Enforce and test that language/formatting changes cannot alter IDs, raw enum values, mutations, journals, evidence hashes, backup identity, authored evidence, product identity, or jurisdiction. Preserve old en-US-bearing identities. |
| 12 | V30-P01-C06 — System-first resolution, fallback, and effective-language evidence | IMPLEMENTATION | [V30-P01-C03,V30-P01-C04] | Use Apple device/per-app resolution, no bundle swizzle, effective-language observation, safe app-Settings deep link, foreground/relaunch behavior, exact/base/English fallback, raw-key prevention, and privacy-preserving fallback diagnostics. |
| 13 | V30-P01-C07 — Locale-aware formatting and input grammar | IMPLEMENTATION | [V30-P01-C04,V30-P01-C05] | Implement and test dates, instants/local time, DST, calendars, numbers, currency, percent, units, week rules, paper, addresses, phones, parsing, ambiguous-input rejection, and canonical round trips with Foundation locale-aware APIs. |
| 14 | V30-P01-C08 — Catalog release mechanism, provenance schema, compatibility, and offline integrity | IMPLEMENTATION | [V30-P01-C03,V30-P01-C04,V30-P01-C05,V30-P01-C06] | Implement the versioned catalog-release schema, validator, compatibility/supersession/rollback, zero-network loading, fallback evidence, and historical lookup. No locale release or reviewer receipt is final before P04-C07 and P05 reconciliation. |

### P02 — English baseline, Unicode, adaptive UI, search, and Settings

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 15 | V30-P02-C01 — English catalog normalization | IMPLEMENTATION | [V30-P01-C03,V30-P01-C08] | Normalize required app-owned English text into semantic keys with comments, placeholders, plurals, variations, terminology, permission/accessibility/report coverage, and explicit literal dispositions. |
| 16 | V30-P02-C02 — Unicode input, persistence, journal, and evidence safety | IMPLEMENTATION | [V30-P01-C05] | Preserve grapheme clusters, combining marks, emoji, CJK, Korean, Arabic/bidi, filenames, contacts, notes, captions, labels, and imported text through persistence, events, snapshots, backup, restore, and erase. |
| 17 | V30-P02-C03 — RTL and bidirectional semantics | IMPLEMENTATION | [V30-P01-C06,V30-P02-C02] | Correct semantic mirroring, mixed identifiers/numbers, icon rules, navigation, lists, signatures, reports, focus order, invisible-control safety, and hostile Arabic/bidi fixtures without claiming Arabic shipping support. |
| 18 | V30-P02-C04 — Expansion, Dynamic Type, accessibility, and font policy | IMPLEMENTATION | [V30-P02-C01,V30-P02-C03] | Prevent clipping/unreachable controls, localize accessibility, qualify font fallback/licensing, preserve touch targets/contrast/focus/errors, and pass long-text and accessibility sizes. |
| 19 | V30-P02-C05 — Locale-aware search, sorting, and normalization | IMPLEMENTATION | [V30-P01-C07,V30-P02-C02] | Add versioned derived search normalization, CJK segmentation, Korean composition, diacritics, hostile Turkish/Arabic cases, stable tie-breakers, rebuild/recovery/erase/backup boundaries, and unmodified canonical identifiers. |
| 20 | V30-P02-C06 — Pseudo, RTL, long-text, and screenshot harness | VERIFICATION | [V30-P02-C03,V30-P02-C04,V30-P02-C05] | Activate deterministic expansion/RTL pseudolanguages, unresolved-key diagnostics, unexpected-fallback counters, screenshot fixtures, device/Dynamic Type matrix, and zero production analytics. Pre-S10 hosted results remain provisional. |
| 21 | V30-P02-C07 — Language & Region Settings and report-language controls | IMPLEMENTATION | [V30-P01-C06,V30-P01-C07,V30-P02-C04] | Add localized effective app-language/region display, iOS Settings handoff, truthful unsupported-language fallback, independent report-language selection, and clear language-versus-jurisdiction explanation. |

### P03 — Globalized workflows, content, outputs, and recovery

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 22 | V30-P03-C01 — Authored-content and template-language model | IMPLEMENTATION | [V30-P01-C04,V30-P02-C02] | Distinguish app UI, admin templates, instructions, inspector/customer evidence, derived translations, report chrome, and licensed jurisdiction content. Preserve source and invalidate derived translations after edit/redaction. |
| 23 | V30-P03-C02 — Offline and sync-state localization integrity | IMPLEMENTATION | [V30-P01-C08,V30-P02-C04] | Cover existing pending/saved/syncing/synchronized/failed/conflicted/recovered states, queued Unicode attachments, offline startup, accessible recovery, and notification truth without creating a new sync engine. |
| 24 | V30-P03-C03 — Forms, required-state, validation, and conditional semantics | IMPLEMENTATION | [V30-P01-C07,V30-P02-C04,V30-P03-C01] | Localize existing field labels, instructions, required/optional/error states, choice order, validation, units, numerals, and condition meaning without weakening or reordering canonical rules. |
| 25 | V30-P03-C04 — Unicode PDF and accessible-document renderer | IMPLEMENTATION | [V30-P01-C07,V30-P02-C04,V30-P03-C01] | Remove question-mark substitution, qualify and embed fonts, shape CJK/RTL, support Letter/A4, preserve photo/comment/status association, extraction, semantic order, provenance, and historical deterministic replay. |
| 26 | V30-P03-C05 — Stable JSON, CSV, export, and import contracts | IMPLEMENTATION | [V30-P01-C05,V30-P03-C01] | Preserve language-neutral machine keys/values, add explicit localized-human variants, locale manifests, formula safety, media references, unambiguous parsing, and exact canonical round trip. |
| 27 | V30-P03-C06 — Share, email, print, and label surfaces | IMPLEMENTATION | [V30-P02-C04,V30-P03-C04] | Localize app-owned chrome, subject/body templates, print controls, labels, and share summaries while preserving authored content and explicit document language. |
| 28 | V30-P03-C07 — OCR, dictation, speech, and assisted-input capability truth | IMPLEMENTATION | [V30-P01-C06,V30-P03-C01] | Freeze per-locale capability and online/offline truth. A translated label never implies recognition, dictation, speech, or grammar support unavailable to the exact OS/device/build. |
| 29 | V30-P03-C08 — Backup, restore, and historical catalog replay | IMPLEMENTATION | [V30-P01-C08,V30-P03-C04,V30-P03-C05] | Restore canonical/source content, catalog/font/renderer references, derived artifacts, search rebuild state, and explicit missing-resource limitations independent of current app language. |
| 30 | V30-P03-C09 — Onboarding, help, errors, permissions, notifications, support, and destructive actions | IMPLEMENTATION | [V30-P01-C06,V30-P02-C04,V30-P03-C02] | Close commonly missed surfaces with stable keys, contextual recovery, accessibility, notification/deep-link consistency, and no hidden English in critical states. |

### P04 — Translation operations and required language implementation

Locale lanes may use parallel read-only preparation only after exact nonoverlapping scopes exist. Exactly one P04 implementation card may be selected, mutate files, checkpoint, or transition at a time; its fence remains locale-exclusive. Each locale card owns only its resource, fixture, and locale-specific test paths. V30-P04-C07 is the sole writer to shared catalog/project metadata.

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 31 | V30-P04-C01 — Termbase, do-not-translate list, and secure review workflow | FOUNDATION | [V30-P02-C06,V30-P03-C03,V30-P03-C04,V30-P03-C05,V30-P03-C06,V30-P03-C09] | Freeze concept IDs, field terminology, claim boundaries, screenshots, placeholders, translation-vendor minimization, roles, import/export, correction/supersession, and future vertical namespaces. |
| 32 | V30-P04-C02 — U.S. Spanish | IMPLEMENTATION | [V30-P04-C01] | Complete the provisional es app/report/help/accessibility/permission/error/recovery/destructive/notification catalogs and metadata draft using U.S./Latin-American field terminology; validate es-US, es-MX, and es-419 behavior. No App Store mutation. |
| 33 | V30-P04-C03 — Simplified Chinese | IMPLEMENTATION | [V30-P04-C01] | Complete provisional zh-Hans catalogs and fixtures; qualify CJK typography, input, segmentation, line breaking, report shaping/extraction, accessibility, and terminology. |
| 34 | V30-P04-C04 — Traditional Chinese | IMPLEMENTATION | [V30-P04-C01] | Complete provisional zh-Hant catalogs and fixtures through independent script-appropriate translation/review; never mechanically convert zh-Hans and call it accepted. |
| 35 | V30-P04-C05 — Vietnamese | IMPLEMENTATION | [V30-P04-C01] | Complete provisional vi catalogs and fixtures; qualify diacritics, wrapping, search, input, fonts, PDF extraction, and field terminology. |
| 36 | V30-P04-C06 — Korean | IMPLEMENTATION | [V30-P04-C01] | Complete provisional ko catalogs and fixtures; qualify Hangul composition, search, line breaking, compact UI, fonts, reports, accessibility, and terminology. |
| 37 | V30-P04-C07 — Shared catalog, Xcode project, and provisional locale-release integration | INTEGRATION | [V30-P02-C07,V30-P03-C08,V30-P04-C02,V30-P04-C03,V30-P04-C04,V30-P04-C05,V30-P04-C06] | Integrate all six localizations once on the provisional branch, update known regions/shared metadata, create the complete provisional catalog-release set, bind candidate head/tree/capability matrix, regenerate deterministic fixtures, prove lane isolation, and freeze the branch for P05. |

### P05 — Mandatory Phase 10/V23 reconciliation and final-acceptance admission

P05 is unavailable until the owner reports Phase 10.6 complete. That report is a trigger, not proof. P05 independently verifies the accepted Phase 10 evidence, freezes the V30 provisional lineage, and reconciles three immutable inputs: frozen V23 `B`, provisional V30 `P`, and accepted Phase-10.6/V23 main `S`.

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 38 | V30-P05-C01 — Accepted Phase 10.6 and reconciliation preconditions | FOUNDATION | [V30-P04-C07] | After the owner trigger only, verify Phase 10.6 head/tree/refs, exact-head and exact-main CI, artifacts/checksums, handoff, known bugs, V23 package/coordination, current S10 reservation, frozen provisional branch/ledger, and explicit predecessor reconciliation authority. |
| 39 | V30-P05-C02 — Mandatory provisional-to-Phase10/V23 reconciliation replay | INTEGRATION | [V30-P05-C01] | Create a clean reconciliation worktree/branch from exact accepted `S`; replay each card-scoped provisional delta in order or reimplement authorized conflicts. Preserve old/new SHA and tree mappings. Phase 10 owns true brand/UI conflicts. Never merge the planning or provisional branch wholesale. |
| 40 | V30-P05-C03 — V23 unfinished-card disposition bridge | FOUNDATION | [V30-P05-C02] | Recompute V23 Cards 135, 136, 141, and 146 without changing their truthful OWNER_ACTION, MONITOR, or DEFER state or inventing evidence. |
| 41 | V30-P05-C04 — Reconciled candidate, fence, and provisional-evidence disposition | FOUNDATION | [V30-P05-C02,V30-P05-C03] | Recompute inventories, overlaps, ownership, and fences; classify every provisional result COMPATIBLE, CORRECTION_REQUIRED, SUPERSEDED, or OBSOLETE_WITH_RATIONALE. No provisional result is auto-promoted. |
| 42 | V30-P05-C05 — Reconciled exact-head hosted qualification | VERIFICATION | [V30-P05-C04] | Run all invalidated unit/UI/accessibility/localization/privacy/persistence/report/brand evidence on the exact reconciled candidate through the post-S10 authorized hosted route. Provisional CI cannot substitute. |
| 43 | V30-P05-C06 — Reconciliation close and P06 final-candidate admission | INTEGRATION | [V30-P05-C05] | Seal reconciled head/tree, replay map, artifacts, checksums, canonical-ledger adoption CAS, and per-card post-S10 admission receipts; select only P06-C01. This grants reconciled per-card implementation admission only, not V30 final-candidate acceptance or main-integration credit. Do not fast-forward main. |

### P06 — Linguistic, product, output, and U.S. readiness acceptance

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 44 | V30-P06-C01 — Complete-locale machine audit | VERIFICATION | [V30-P05-C06] | For en, es, zh-Hans, zh-Hant, vi, and ko, bind one exact locale-acceptance candidate tuple and prove complete required shipping keys, placeholders, plurals/variations, accessibility/help/report/error coverage, bundled offline resources, zero unresolved keys, zero unexpected fallback, and exact catalog digests. |
| 45 | V30-P06-C02 — Professional/native in-context linguistic acceptance | OWNER_ACTION | [V30-P06-C01] | Review only P06-C01's exact tuple. Require a professional translator and independent reviewer per non-English localization plus bilingual field-workflow review. Emit ACCEPTED_NO_CORRECTION or CORRECTION_REQUIRED under the same-candidate reopen law. |
| 46 | V30-P06-C03 — Multi-locale hosted UI and accessibility qualification | VERIFICATION | [V30-P02-C06,V30-P06-C01,V30-P06-C02] | On the exact accepted linguistic tuple, run macOS UI shards for every locale, device size, Dynamic Type, light/dark/contrast, keyboard state, VoiceOver semantics, pseudo-RTL, screenshots, and complete artifacts. |
| 47 | V30-P06-C04 — Reports, exports, offline, search, and canonical-invariance qualification | VERIFICATION | [V30-P03-C08,V30-P06-C01,V30-P06-C02] | On the exact accepted linguistic tuple, prove Unicode PDF/extraction, Letter/A4, export/import, backup/restore, offline launch/work/recovery, search, and identical canonical records/hashes/journals/jurisdiction across languages. |
| 48 | V30-P06-C05 — U.S. App Store metadata and localized screenshot package | IMPLEMENTATION | [V30-P06-C02,V30-P06-C03,V30-P06-C04] | Prepare accurate U.S. metadata/localizations, screenshots, support/privacy text, and claim-safe keyword evidence for the cohort; revalidate current Apple limits. No upload, submission, or foreign storefront activation. |
| 49 | V30-P06-C06 — U.S. jurisdiction, privacy, legal, and support readiness | OWNER_ACTION | [V30-P01-C04,V30-P06-C05] | Accept an evidence-backed United States row and fail-closed HOLD rows elsewhere for the exact P06-C05 tuple. Translation cannot broaden standards, qualifications, privacy, retention, export, support, or legal claims. |
| 50 | V30-P06-C07 — V30 exact-candidate acceptance | VERIFICATION | [V30-P06-C02,V30-P06-C03,V30-P06-C04,V30-P06-C06] | Accept only one exact tuple. Every language, catalog, UI, accessibility, output, offline, canonical-data, claims, reviewer, reconciliation, and hosted-CI receipt must bind the same head, tree, catalog release, key-set digest, and termbase digest. |

### P07 — Main integration, owner release, future languages, and monitoring

| # | Card | Class | Exact direct prerequisites | Required outcome and acceptance |
|---:|---|---|---|---|
| 51 | V30-P07-C01 — V30 phase close and exact-main qualification | INTEGRATION | [V30-P06-C07] | Append immutable handoff, non-force close the phase, verify phase ref, fast-forward main only under authority, run green exact-main UI-enabled CI, re-fetch, and bind artifacts/checksums. V30 product implementation completes here. |
| 52 | V30-P07-C02 — Initial release owner action | OWNER_ACTION | [V30-P07-C01] | Signing, TestFlight, App Store upload/submission, availability, and promotion only under separate owner authority. Not required to call V30 product implementation complete. |
| 53 | V30-P07-C03 — Next-language evidence refresh and re-entry register | VALIDATE_NEXT | [V30-P07-C01] | Re-score pt-BR, fil, ar, fr/fr-CA, ru, pl, hi, id, ja, tr, ht, and observed demand using customers, support, fallback diagnostics, geography, official data, competitor changes, review capacity, and storefront plans. |
| 54 | V30-P07-C04 — Future country, storefront, and jurisdiction activation | DEFER | [V30-P07-C01,V30-P07-C03] | Re-enter only with explicit country, legal, privacy, support, metadata, regional-pack, language, report, retention, and owner-availability authority. |
| 55 | V30-P07-C05 — Post-release locale monitor | MONITOR | [V30-P07-C02] | Arm only for an exact released build, U.S. storefront, locale cohort, observation window, metrics, privacy rule, rollback threshold, and owner response path. Monitoring cannot fabricate implementation or release credit. |

## 22. Graph invariants and topological checks

The activated machine graph must prove:

- exactly 55 unique card IDs;
- exactly 107 unique direct prerequisite edges;
- ordinals exactly 1 through 55 with no gaps or duplicates;
- every direct prerequisite exists;
- every prerequisite ordinal is lower than its consumer;
- no self-edge or cycle;
- no range shorthand;
- no edge inherited as V30 acceptance from V23 or V24;
- P00 has exactly one root; all nine P00 internal edges participate in the transitive eligibility gate whose sole terminal admission card is V30-P00-C06, while only the graph-declared direct prerequisites enter that card;
- P04 language cards fan out only from P04-C01 and converge only at P04-C07;
- P05 is the only lineage-reconciliation and canonical-admission bridge. Any graph-declared P00–P04 prerequisite referenced by a P06 card is a semantic-evidence dependency only and cannot bypass P05-C06, post-S10 authority, or reconciliation;
- P06-C07 depends on all required acceptance categories;
- P07-C05 cannot arm without P07-C02;
- OWNER_ACTION, DEFER, VALIDATE_NEXT, and MONITOR cannot be selected by ordinary implementation autopilot unless their explicit rules allow it;
- no card is treated as current before package activation;
- every checkpoint in the 37-card pre-S10 cohort carries `finalCredit=false` before V30-P05-C06;
- no context for any card in the 18-card post-S10 cohort can be emitted before the owner trigger and verified P05 prerequisites.

The graph verifier must fail closed on an unknown ID, missing edge, duplicated edge, changed class, changed outcome digest, malformed prerequisite, or unauthorized credit flag.

## 23. Card-level acceptance matrices

### 23.0 Shipping-string acceptance predicate

The §10.3 `APP_OWNED_SHIPPING` inventory and exclusions are authoritative for string acceptance. No item can be excluded merely because it is difficult to localize. The predicates are evaluated against the frozen shipping inventory and its exercised coverage matrix, never against every string the operating system, user, importer, test harness, or developer tool may render.

### 23.1 Catalog acceptance

For each declared-complete localization:

- 100 percent of frozen required `APP_OWNED_SHIPPING` keys translated or explicitly approved do-not-translate;
- 100 percent placeholder name/type/count compatibility;
- 100 percent locale-required plural and variation branches;
- zero unresolved localization keys in exercised `APP_OWNED_SHIPPING` paths;
- zero unexpected English fallback in exercised `APP_OWNED_SHIPPING` paths;
- zero test pseudolocales declared as shipping;
- exact catalog/key-set/termbase/reviewer digests;
- professional and independent in-context review;
- bundled offline availability;
- correction and supersession history.

### 23.2 Canonical invariance

Run the same golden workflows under all six localizations and prove equality of:

- source database records;
- IDs and raw enum values;
- mutation and journal identity;
- evidence bytes and hashes;
- backup source manifests and canonical hashes;
- machine JSON keys and values;
- jurisdiction and content-pack identity;
- source-authored evidence.

Explicitly localized derived outputs may differ only in fields named by their provenance contract.

### 23.3 Formatting matrix

At minimum:

- en-US and en-GB;
- es-US, es-MX, and es-419;
- zh-Hans with U.S. and at least one Chinese-region formatting profile;
- zh-Hant with U.S. and at least one Traditional-Chinese-region formatting profile;
- vi and ko;
- decimal point/comma hostile fixtures;
- 12-hour/24-hour time;
- DST gap and overlap;
- first weekday variation;
- Gregorian plus one non-default calendar hostile fixture;
- U.S. customary and metric display;
- Letter and A4;
- international phone/address samples;
- unambiguous canonical round trips.

Formatting tests do not claim a country is supported.

### 23.4 UI and accessibility matrix

- smallest supported iPhone and largest relevant iPhone;
- every supported orientation;
- standard and largest accessibility Dynamic Type;
- longest real translation plus expansion pseudo;
- left-to-right, pseudo-right-to-left, and mixed-direction identifiers;
- light, dark, and increased contrast;
- keyboard/IME composition;
- VoiceOver labels, values, actions, order, errors, and recovery;
- no clipped critical label, hidden action, overlapping field, ambiguous icon, off-screen warning, or unreachable recovery.

### 23.5 Report and export matrix

- accents, Vietnamese diacritics, Chinese scripts, Korean, emoji, combining marks, and mixed bidi hostile fixtures;
- no question-mark substitution;
- font embedding/subsetting and license evidence;
- extraction and reading order;
- Letter/A4 pagination;
- photo/comment/status/number association;
- preserved source content;
- explicit language/locale/time-zone/unit/catalog/font/renderer provenance;
- stable machine JSON/CSV;
- formula-safe CSV;
- deterministic regeneration for identical versioned inputs;
- historical replay and explicit missing-resource behavior.

### 23.6 Hosted verification

iOS builds, unit tests, Simulator UI tests, screenshots, accessibility paths, and report rendering acceptance run only through the task-authorized GitHub Actions macOS workflow.

Every recorded native run binds:

- branch ref and exact head SHA/tree;
- workflow and run ID/URL;
- runner image and Xcode build;
- Simulator model, OS, and UDID;
- exact selector object;
- build/unit/UI/report logs;
- result bundles and screenshots;
- relative checksums and artifact digest;
- no unexpected cancellation, missing evidence, or stale head.

Windows may run deterministic generators, source audits, schema checks, graph checks, catalog checks, and hygiene. It may not claim an Xcode or Simulator pass.

Before reconciliation, native branch runs are optional development diagnostics. Card 5 may adapt only the three authority-enumerated frozen-B workflow/helper copies on `phase/v30-globalization` to read the typed `selector` object inside `docs/design/v30/execution/V30_CI_SELECTION.json`. It preserves `Scripts/ci-selection.json` byte-for-byte and the task-pinned runner, Xcode/Simulator, watchdogs, product commands, checksums, artifacts, and non-cancelling concurrency. Use the already registered `.github/workflows/ios-ci.yml` path with the exact V30 branch ref; never install a new workflow on main or inspect/dispatch Phase 10 runs. A missing/unavailable route is `NOT_EXECUTED_NO_NATIVE_CREDIT`, not a pass. Required deterministic static checks may still permit a provisional checkpoint. Record every failed native candidate and diagnosis, apply only current-card corrections, and carry unresolved native work into mandatory post-reconciliation qualification. No provisional failure or unavailable route may be relabeled green or omitted.

## 24. Existing coordination writer and append-only governance

V30 must not create a competing canonical source of coordination truth.

Before Phase 10.6, the existing V23 coordination `main` and its frozen worktree are read-only. V30 uses a separate, clearly named `V30PreS10ProvisionalLedgerV1` at `docs/design/v30/execution/V30_PROVISIONAL_LEDGER.json` on `coord/v30-globalization-provisional`, in `C:\AssetRounds-v30-globalization-coordination`, based on the exact frozen head of `https://github.com/Asset-Rounds/AssetRounds-v23-coordination.git`. This dedicated coordination branch may receive only its authority-enumerated provisional writes; canonical V23 `main` remains untouched. The product branch contains only a read-only projection of that ledger. The provisional ledger cannot issue canonical V23/V30 acceptance and is never represented as a successor sequence of the V23 ledger. At provisional activation:

- bind coordination head `51ef2b3d970a25b4c83df8c8238609316e37034e`, tree `060c83c3d1489fc011b1c921f6c85bec2b074478`, sequence 626, ledger digest `973090852e843e895125bea8da87c7e1689611c46d8219a70c1749be49398067`, and projection digest `cf57849e8f7c245d38fd21a39da5938d10e13c9aca3976a71b7d3a3ee401f12d` as immutable predecessor observations;
- create a distinct authority-pinned isolated coordination locator/ref, expected-absent ledger ID, writer generation, serialized single-writer lane, sequence namespace, digest chain, request-ID domain, and projection; the G3 CAS must bind the expected old locator value `ABSENT` and must not be inferred from a directory scan;
- preserve every V23 attempt, transition, receipt, card row, and unfinished status without copying those records into mutable V30 state;
- append, never overwrite or relabel, provisional evidence;
- make every successful provisional write idempotently replayable and immediately read back;
- emit `finalCredit=false` for every pre-S10 transition.

At P05-C06, an authority-pinned adoption CAS may bind the frozen provisional tip to the then-current canonical predecessor and append V30 card admissions in original graph order. It does not renumber V23 or rewrite provisional records. A collision has no partial effect; the provisional ledger remains immutable after adoption.

Every mutation request binds:

- globally unique request ID;
- expected prior sequence;
- expected prior ledger digest;
- expected projection digest where applicable;
- exact card ID, attempt, state, revision, and path-fence digest;
- exact predecessor receipts and edge dispositions;
- exact Git head/tree for candidate, verification, or integration events;
- exact authority package and policy epoch.

On success, the serialized writer atomically appends one transition/receipt, advances the sequence once, reseals ledger/projection digests, and returns the exact committed result. A replay with the same request ID returns the same result. A mismatch produces no state change and no credit; the orchestrator rereads and either retries the identical idempotent request or submits an explicit successor/correction against the new state. Product-branch current-task and selector projections are separate authority-bound files and are never coordination-ledger locations.

If the existing accepted writer cannot provide the required atomicity in the post-S10 environment, P05 fails closed. V30 may then propose one narrowly scoped coordination-writer correction under explicit authority. The provisional ledger is a quarantined evidence log, not an unapproved server, database, or substitute canonical ledger.

## 25. Evidence and credit law

The activated package must carry this exact semantic rule:

UNSEALED, PROVISIONAL, STATIC, PLANNING, RESEARCH, GENERATED, FAILED, BLOCKED, CONFLICTED, DEFERRED, MONITOR, OWNER_ACTION, BRANCH-CI, OR INSTALLED evidence is not implementation, acceptance, phase-close, release, exact-main integration, or successor-start credit.

Additional rules:

- Every P00–P04 pre-S10 state, commit, receipt, review, test, and CI run has `finalCredit=false`, even when technically green.
- `PROVISIONAL_CHECKPOINTED` satisfies only the next provisional card's execution dependency. It does not satisfy the corresponding canonical acceptance dependency.
- P05 must bind each provisional card to a post-S10 reconciled head/tree and issue a separate canonical admission/acceptance record before that card can provide final implementation credit.
- IMPLEMENTATION credit requires accepted exact candidate evidence for that card.
- VERIFICATION credit does not rewrite implementation history.
- Professional/native review is linguistic evidence only.
- OWNER_ACTION requires the named real-world act and receipt.
- MONITOR is observation-only and never becomes implementation.
- DEFER remains ineligible until explicit re-entry authority.
- A branch build is not exact-main integration.
- A catalog's presence is not proof that every surface is translated.
- A translated UI is not a foreign storefront, jurisdiction, legal, OCR/dictation, support, or release claim.
- A retry or correction preserves earlier receipts and candidate bindings.
- Acceptance is exact-head/tree and exact-evidence bound; no evidence transfers to a different head automatically.

## 26. Pre-S10 execution, reconciliation, and activation state machine

### 26.0 Non-self-authorizing owner prerequisite

`V30PreS10ProvisionalImplementationAuthorityV1` is an owner-supplied, repository-external authority. This blueprint, its authors, a branch, a commit, a generated receipt, or a CI run cannot issue or amend it. The authority becomes actionable only when the owner sends the companion prompt as the user message in a new Codex task and all exact package hashes/pins validate.

The authority binds:

- repository `https://github.com/Asset-Rounds/AssetRounds.git`;
- frozen V23 head `acbfb68355f903fe98638b6ef22e4814e7b48328` and tree `47e17fae6b73dccd5029ccf4ac7cca659196f225`;
- frozen V23 coordination head/tree, sequence 626, ledger/projection digests, package/register/graph identities, and unfinished-card truth;
- the raw S10 reservation artifact SHA-256 `9f7c27431271728d167731d4af806c7449447dfbcc8bf46778102e2f9a89b576`, its 86 ordered paths, and content digest `274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a`;
- `phase/v30-globalization` and `C:\AssetRounds-v30-globalization`;
- the exhaustive source-to-destination map, all-and-only support-artifact list, core document/script/graph/card/locale/V24/fence hashes, allowed ref operations, authority-pinned installation request ID, isolated-coordination locator/CAS, path-fence law, CI law, recovery law, and zero-credit law. The bootstrap payloads bind the authority raw/content digests; the owner prompt binds the authority content digest; the downstream package manifest binds all 23 non-manifest files, including all four human documents, authority, and bootstrap payloads. The authority never hashes its downstream prompt, bootstrap outputs, or manifest, so the digest graph has no self-reference;
- `C:\AssetRounds` as a permanently forbidden observation and mutation target. The later owner trigger permits read-only validation of externally supplied accepted evidence only; it never permits V30 to access that checkout.

The package can neither self-issue authority nor define a new digest law during bootstrap. An absent or incompatible digest mechanism, any package-byte change, an authority amendment, or a changed support-artifact set requires a new externally owner-supplied successor package revision and authority/manifest; the current task stops without mutation. Absence, placeholder, stale handoff, hash mismatch, branch/worktree collision, unexpected ref, dirty/unowned work, or unclassifiable path ownership produces `PRE_S10_AUTHORITY_UNAVAILABLE_OR_MISMATCHED`. No mutation occurs.

### G0 — REVIEWED_EXTERNAL_PACKAGE

- Preserve the R1 post-S10-only file at SHA-256 `81c74f074ea2af4500883b56117813cc3f0c85ba059e7a568db1ef17e019c84c`.
- Preserve V24 as immutable superseded provenance.
- Validate the immutable four-file R2 human package, pre-existing authority/manifest, and every exhaustively enumerated support artifact byte.
- Verify the execution branch/worktree are absent or already exactly match the authorized installed state.
- Do not inspect `C:\AssetRounds` or poll Phase 10.

### G1 — OWNER_AUTHORITY_VALIDATED

The new task treats its user-sent companion prompt as owner direction and performs read-only validation:

1. Read the applicable `AGENTS.md` from exact frozen V23 `B`; retain inherited `docs/execution/CURRENT_TASK.md`, V4 plan, and V4 runbook as read-only predecessor evidence.
2. Recompute every immutable-four-file package SHA-256, manifest digest, and all-and-only support-artifact SHA-256.
3. Verify frozen V23 and coordination pins only in their named non-Phase-10 worktrees.
4. Verify the V30 target branch/worktree are absent, or prove exact idempotent continuation.
5. Verify no package placeholder and no permission to mutate `main`, Phase 10, the frozen V23 worktree, or canonical V23 coordination.
6. Validate `installationRequestID=ASSETROUNDS-V30-PRE-S10-20260902-R2/INSTALL`, every exact `bootstrapRequestIDs` entry, and the authority-pinned isolated coordination locator with expected ledger value `ABSENT`; do not allocate replacement bootstrap IDs or write a ledger before G3 creates it. Later request IDs must stay in the pinned namespace and retain their original input/result on retry.

### G2 — PROVISIONAL_BRANCH_AND_PACKAGE_INSTALLED

From exact frozen V23 head/tree:

1. Create local branch `phase/v30-globalization` and worktree `C:\AssetRounds-v30-globalization`.
2. Install all-and-only the manifest's immutable four human files, authority, manifest, 55-card register, 107-edge graph, locale and V24 projections, every enumerated schema/validator, and the hash-bound payload records for the Card 1 context/fence and initial V30 current-task/selector projections. Those payload records are support artifacts, not active execution locators; only G3 may materialize their exact bytes at `docs/design/v30/execution/V30_CURRENT_TASK.md` and `docs/design/v30/execution/V30_CI_SELECTION.json`.
3. Create one direct-child package-install commit; read back its parent/head/tree and complete diff.
4. Do not merge or cherry-pick the planning branch.
5. Do not change or push `main`, any Phase 10 ref, or `phase/v23-expansion`.

Installation is zero-credit. Failure before the commit leaves no install; failure after the commit resumes only through exact readback and the same idempotency key.

### G3 — PROVISIONAL_GENESIS_AND_CARD_1_SELECTION

Use authority-pinned expected-old-value operations and one serialized writer lane:

1. Create only the named isolated coordination branch/worktree from its exact frozen coordination head, using expected-absent branch creation. Then create the sole `V30PreS10ProvisionalLedgerV1` genesis in a direct-child coordination commit: the expected old Git ref is the frozen coordination head and the expected namespaced ledger value is `ABSENT`. Never use `ABSENT` as the old Git ref after branch creation. Import V23 coordination pins as immutable observations only. The exact ledger ID, writer generation, request namespace, and bootstrap request IDs come from the external authority.
2. Append and read back one activation receipt by a second coordination CAS, binding authority digest, immutable-four-file package digest, support-artifact digest set, install commit/tree/diff, branch/worktree, S10 reservation, and no-credit flags.
3. From the exact package-install commit, create one direct-child Card 1 selection-projection commit changing exactly the authority-pinned active Card 1 context, fence, execution-handoff genesis, read-only provisional-ledger projection, `docs/design/v30/execution/V30_CURRENT_TASK.md`, and `docs/design/v30/execution/V30_CI_SELECTION.json` bytes. Advance only `phase/v30-globalization` with an expected-old-value ref compare-and-swap against the exact install head. Never edit inherited V4 files.
4. In a later coordination CAS, select only V30-P00-C01 and bind the exact selection-projection commit/tree/diff and the six materialized projection digests.

Installation, ledger genesis, activation receipt, selection-projection commit, and ledger selection are separate idempotent operations. A failed compare-and-swap changes no ref or ledger. If the selection-projection commit exists but the final ledger CAS did not occur, it has no active-card authority; resume only by exact readback with the same installation request ID and expected hashes.

The coordination bootstrap may create only its three externally enumerated paths: the ledger, `docs/design/v30/execution/receipts/V30_G3_ACTIVATION_RECEIPT.json`, and `docs/design/v30/execution/receipts/V30_G3_CARD_001_SELECTION_RECEIPT.json`. Later provisional transitions append events and request-result records inside the single ledger file; they do not create another coordination writer, script, or unissued file. Receipt digests bind observed product commits and prior coordination state, never the future coordination commit that will contain the receipt. Card 1's product-side activation-validation receipt is a mirror, not another activation or ledger.

### G4 — PRE_S10_PROVISIONAL_EXECUTION

- Execute the graph-enumerated 37-card pre-S10 cohort in order, one selected card at a time.
- A terminal card result is `PROVISIONAL_CHECKPOINTED`; it may satisfy only the next provisional dependency.
- Every card records base/candidate head/tree, exact changed paths, tests, failures, branch CI, S10-path intersection, and a replay/reimplementation manifest.
- An S10-reserved file may be changed in the V30 worktree only when a pre-existing external owner authority exact tuple authorizes the card ID, path, expected frozen B blob/hash or `ABSENT`, bounded purpose, writer lane, and reconciliation obligation, and the path is explicitly card-fenced and labeled `S10_SHARED_RECONCILIATION_REQUIRED`. This changes no Phase 10 byte. Otherwise `CONFLICT_HOLD` has no partial effect.
- Hosted CI may run only through an authority-pinned V30 branch route. It is development evidence and cannot be reused as post-S10 acceptance.
- Shared catalog/project/selector files have one current-card integrator. Locale lanes may prepare read-only in parallel but exactly one selected card mutates/checkpoints/transitions at a time.
- Direct-child corrections preserve failed evidence. No force-push, merge commit, hidden squash, accepted-history rebase, release, or `main` mutation.

### G5 — PROVISIONAL_FROZEN_WAIT

After P04-C07, freeze:

- exact terminal provisional head/tree `P`;
- complete B..P commit/order/diff map;
- provisional ledger tip/digest;
- every S10-shared path and semantic-contract dependency;
- every passed, failed, superseded, unverified, human-review, and CI artifact.

The graph-enumerated 18-card post-S10 cohort remains unselectable. Codex does not poll Phase 10. The owner may continue Phase 10 for any duration and later provides the trigger.

### Trigger

The sole trigger is a new owner message that Phase 10.6 is complete and ready for reconciliation. The message is permission to verify; it is not acceptance evidence.

### G6 — ACCEPTED_PHASE10_AND_V23_BASE_VERIFIED

Only after the trigger and after a separately owner-supplied, pre-existing `V30PostS10ReconciliationAuthorityV1` validates. The owner completion message authorizes read-only verification only; it does not authorize a branch, replay, ledger adoption, package amendment, or post-G6 mutation. The post-S10 authority must bind the exact accepted `S` tuple, allowed reconciliation branch/worktree/ref operations, B/P/S replay rules, canonical writer/adoption CAS, current package digest, and exact post-S10 card contexts/fences.

1. Read the then-current repository authority and verify accepted Phase 10.6 implementation/verification/main heads, trees, refs, CI runs, artifacts, checksums, handoff, known bugs, and S10 reservation.
2. Execute the existing V23 reconciliation contract under explicit authority and verify V23 Cards 135, 136, 141, and 146 truthfully.
3. Require immutable receipts proving accepted S10 lineage, lossless V23 reconciliation preserving exactly 146 cards, 230 direct edges, and the unchanged unfinished states for Cards 135, 136, 141, and 146, plus green exact-main evidence at the post-Phase-10/V23 head/tree `S`.
4. Freeze `B`, `P`, and `S` as the three reconciliation inputs.

Any missing post-S10 authority or `S` receipt is a read-only hold. No G7, G8, G9, P05, P06, or P07 mutation begins from the owner completion message alone.

Missing or ambiguous evidence blocks. No conversation claim substitutes for Git/CI evidence.

### G7 — RECONCILIATION_BRANCH_CREATED

- Create `phase/v30-globalization-reconciliation` and `C:\AssetRounds-v30-globalization-reconciliation` from exact `S`.
- Verify both older worktrees remain untouched and `P` is frozen.
- Recompute B..P and B..S path/semantic overlap.
- Emit a complete matrix with `UNCHANGED_SAFE_REPLAY`, `S10_ALREADY_SATISFIES_WITH_PROOF`, `CONFLICT_REQUIRES_AUTHORIZED_REIMPLEMENTATION`, or `OBSOLETE_REJECTED_WITH_RATIONALE`.

### G8 — CARD_SCOPED_REPLAY_OR_REIMPLEMENTATION

- Process every card in the frozen provisional cohort in its original topological order.
- Replay a disjoint commit while recording original/new commit and tree, or reimplement a conflict in a new card-scoped commit.
- Accepted Phase 10 owns brand/design truth on actual conflicts; V30 localization semantics must then be reapplied and reverified rather than silently discarded.
- Never merge the provisional or planning branch wholesale.
- Rehydrate exact fences against `S`; preserve unrelated accepted bytes and all provisional provenance.

### G9 — POST_S10_VERIFICATION_AND_CANONICAL_ADOPTION

- Rerun every invalidated static, unit, UI, accessibility, localization, privacy, persistence, report, export, backup, offline, search, brand, and exact-head hosted check.
- Provisional CI and reviews remain zero-credit provenance.
- Through one authority-pinned canonical adoption CAS, bind the frozen provisional tip, current canonical predecessor, replay map, reconciled head/tree, and per-card admission receipts.
- A collision has no partial effect. After adoption the provisional ledger is immutable and only the canonical writer remains active.
- P05-C06 selects only P06-C01.

### G10 — FINAL_ACCEPTANCE_AND_MAIN

- Execute P06 against one exact reconciled locale-acceptance tuple.
- Professional/native review binds only that tuple and reopens on correction.
- P07-C01 is the first card permitted to fast-forward `main`, and only after exact phase-head and exact-main green evidence.
- P07-C02 release, P07-C04 foreign activation, and P07-C05 monitoring require their separate owner/trigger evidence.

V30 product implementation completes at accepted V30-P07-C01. Signing, TestFlight, App Store submission, availability, and release remain separate owner actions.

## 27. Package, hash, and supersession design

### 27.1 Canonical files

The immutable V30 human-readable design package contains exactly:

1. docs/design/v30/EXPANSION_V30_FOUNDATION_PLAN.md
2. docs/design/v30/EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md
3. docs/design/v30/EXPANSION_V30_HANDOFF.md
4. docs/design/v30/NEXT_CODEX_SESSION_PROMPT.md

The pre-existing external installation manifest additionally binds, as exhaustively enumerated support artifacts rather than extra human design files:

- `docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json`;
- `docs/design/v30/authority/V30PackageManifestV1.json`;
- the generated 55-card register, 107-edge graph, locale registry, V24 disposition projection, every validator/schema, the authority-pinned Card 1 context/fence, and the initial V30 current-task/selector projections.

External source filenames and installed repository paths are intentionally distinct. The external files `V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json` and `V30_PACKAGE_MANIFEST.json` install byte-for-byte at the two camel-case paths above. The manifest's exact source-to-install map is the sole translation between those names; neither naming form may be inferred or substituted.

The external unified blueprint is split by responsibility:

- Foundation Plan: product scope, research, language cohort, card graph, acceptance, deferrals.
- Architecture Blueprint: contracts, persistence, localization, UI, reports, search, governance, integration.
- Handoff: frozen lineage, current state, receipts, blockers, exact next action.
- Next Session Prompt: copy-ready orchestration and fail-closed rules.

### 27.2 Integrity

The pre-issued digest mechanism is `V30CanonicalJSONSHA256LFV1`: UTF-8, no BOM, sorted JSON object keys, compact separators, preserved array order, and one final LF. In `V30_PACKAGE_MANIFEST.json`, records are ordered by external source filename. `packageDigest` hashes the complete 23-record `files` array. `humanPackageDigest` hashes the four records for the Foundation Plan, Architecture Blueprint, Handoff, and Next Session Prompt, preserving their manifest order. `structuralProjectionDigest` hashes the four records for `V30_CARD_REGISTER.json`, `V30_DIRECT_DEPENDENCY_GRAPH.json`, `V30_LOCALE_REGISTRY.json`, and `V30_V24_DISPOSITION_PROJECTION.json`, preserving their manifest order. Each record contains exactly `path`, `sha256`, and `bytes`. The authority's `authorityContentDigest` uses the same canonical encoding over its full object excluding only `authorityContentDigest`. Bootstrap `payloadDigest` retains its separately pinned pretty-JSON encoding defined by the immutable bootstrap generator/validator; do not interchange these digest recipes.

- The external authority/manifest must already name an accepted digest mechanism for the immutable four-file package and its enumerated support artifacts; P00 and any card may not define, replace, reinterpret, or amend that law.
- Record raw SHA-256 for all four immutable human files and each enumerated support artifact.
- Record one deterministic structural projection digest for phases, cards, classes, outcomes, exact edges, initial locale registry, next-wave registry, and V24 dispositions.
- Verify the structural projection through two independent parses.
- Do not place a self-hash inside a file whose bytes it hashes.
- Create verification/activation receipts only after the commit/head/tree they name is observable.
- Execute external-package validation from the flat external package; the validator's read-only `--installed-root` mode checks the exact split installation map. Installed generator copies are immutable provenance, not a second flat package, and never run in `--apply` mode during card execution.
- Any material package or support-artifact byte change requires a new externally owner-supplied successor package revision, authority, and manifest; the current package remains immutable and execution stops. It is not an in-task amendment or a self-authored digest-law revision.

Execution history is not a fifth package file. It appends only to `docs/design/v30/execution/V30_EXECUTION_HANDOFF.md`; every entry binds the immutable package digest, exact authority ID/digest, selected-card context/fence digest, isolated or canonical ledger locator/sequence/digest, candidate head/tree, and receipt identities. It cannot amend package bytes. A successor package revision starts only from explicit external owner authority and retains prior package and execution-handoff provenance.

### 27.3 V24 supersession projection

The V30 package must bind:

- exact V24 path and SHA-256;
- complete V24 normative-requirement inventory;
- exactly one disposition per requirement;
- rationale and V30 target section/card for incorporated requirements;
- zero V24 implementation/acceptance credit;
- immutable retention of the V24 source.

## 28. Branch, worktree, and storage policy

| Location | Purpose | Policy |
|---|---|---|
| C:\AssetRounds | Active original/Phase 10 checkout | Do not touch or poll for V30 |
| C:\AssetRounds-v23-expansion | Frozen V23 product lineage | Read-only; use only pinned facts until owner-triggered reconciliation |
| C:\AssetRounds-v23-coordination | Existing canonical coordination lineage | Read-only before P05 canonical adoption |
| C:\AssetRounds-v24-globalization-foundation | Superseded V24 planning marker | Retain clean; never merge |
| C:\AssetRounds-v30-globalization-foundation | V30 planning marker at exact V23 head | Keep clean; never use as implementation base |
| C:\AssetRounds-v30-globalization | Provisional execution worktree from exact frozen V23 | Create at G2; P00–P04 only; never merge wholesale |
| C:\AssetRounds-v30-globalization-reconciliation | Post-S10 canonical V30 worktree from exact accepted S | Create at G7; replay/reimplement and run P05–P07 |
| OneDrive V30 package | Owner-reviewable source and fresh-task handoff | Becomes actionable only when sent by the owner and hash-validated |

Git worktree files are local until committed and pushed. External drafts, temporary extraction, downloaded CI artifacts, and scratch logs are not automatically durable Git history. The activated V30 package, product code, tests, and receipts eventually belong in the AssetRounds repository under exact card authority. Temporary research extracts do not.

## 29. Parallelization and ownership

Use up to the available safe concurrency, not token-burning duplication.

- The root orchestrator owns current-card selection, authority, Git integration, shared files, and final acceptance.
- Lightweight agents may inventory, extract, monitor, verify hashes, and run bounded hygiene.
- Substantive agents may own isolated implementation/test/tooling lanes.
- One independent audit lane reviews consequential contracts and graph/acceptance changes.
- No two agents edit the same path concurrently.
- Shared String Catalog metadata, project known regions, shared localization registries, common test support, and coordination state each have one writer.
- Locale agents receive exact resource/fixture/test files and cannot edit another locale.
- Every delegation states objective, exact path fence or read-only scope, authority pins, invariants, commands, prohibitions, and expected report.
- Agents reuse relevant context when safe, but a stale-context agent must reread the current card and pins.

Dependency-ready parallelism:

- P00 follows its exact nine-edge graph and serialized activation/CAS rules.
- P01 research, scope, and inventory may use read-only lanes, but contract writes follow exact prerequisites.
- P02 Unicode/search/UI lanes may parallelize only under nonoverlapping fences.
- P03 output/offline/content lanes may parallelize only after shared contracts exist.
- P04-C02, P04-C03, P04-C04, P04-C05, and P04-C06 may use simultaneous read-only preparation with disjoint locale ownership, but only one locale card may hold mutation/transition authority at a time.
- P04-C07 is a serialized shared integration.
- P05 replay analysis may parallelize read-only, but replay commits, shared-path resolutions, and canonical adoption are serialized.
- P06 hosted qualification may shard by locale/surface on the same exact head.
- Owner/native review can proceed per locale, but P06-C02 accepts only the complete required receipt set.

## 30. Research freshness and post-launch learning

### 30.1 Refresh schedule

| Evidence | Refresh point |
|---|---|
| ACS/BLS/NIOSH/OSHA | At P01-C01 using latest available official release; record year/universe |
| Apple platform and App Store docs | At architecture, metadata, and release cards |
| Competitor App Store language lists | At P01-C01 and P06-C05 |
| Vendor language/help claims | At P01-C01; retain listing mismatch separately |
| Reviews/support themes | Rolling 12-month sample at P01-C02 and before monitor arm |
| User keyword package | Preserve 2026-08-12 snapshot; rerun exact needed locale/metadata research at P06-C05 |
| Target-user interviews | Before P06-C02 linguistic acceptance |
| Legal/privacy/storefront evidence | At P06-C06 and every future-country re-entry |

### 30.2 Bilingual field validation

For each non-English required localization, linguistic acceptance should include:

- a qualified professional translator;
- an independent native/professional reviewer;
- at least two bilingual practitioners who can walk a critical real-world or realistic synthetic sign workflow;
- one supervisor/recipient review of the generated report;
- explicit notes on ambiguous, overly legal, overly technical, or regionally narrow terms;
- accessibility/error/destructive-state review, not only the golden path.

These are recommended acceptance criteria. The owner supplies or authorizes real participants and evidence; Codex does not fabricate them.

### 30.3 Privacy-preserving feedback

V30 adds no analytics SDK by default. Post-release learning may use:

- opt-in support diagnostics;
- local fallback/missing-key summaries the user can choose to share;
- App Store reviews;
- support tickets;
- owner interviews;
- exact crash and platform diagnostics already authorized by the product.

Any new telemetry requires a separate privacy/product card.

## 31. Country, jurisdiction, legal, and standards separation

The U.S.-only commercial row requires:

- supported app localizations;
- U.S. storefront metadata and screenshots;
- U.S. privacy and support readiness;
- truthful current product claims;
- existing explicitly licensed/versioned U.S. content or standards packs;
- no inference that language equals law.

Every non-U.S. country starts HOLD and requires:

- country/storefront owner decision;
- supported languages and report output;
- privacy/data handling/retention review;
- terms, disclosures, export compliance, taxes/commerce, and support review;
- accessibility review in each supported language;
- regional units, paper, addresses, dates, time zones, and metadata;
- licensed/current standards and professional qualification rules;
- App Store availability action under owner authority.

The European Union, United Kingdom, Canada, Mexico, Latin America, or another market is not activated merely because its language is in the binary.

Useful official starting points:

- [Apple App Store localization reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)
- [Apple localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information)
- [Apple manage App Store availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)
- [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)

## 32. Localized App Store and acquisition policy

- Metadata language is not necessarily identical to in-app language availability; record both.
- Research each locale's actual practitioner vocabulary and intent.
- Use current shipped behavior only.
- Do not use competitor trademarks.
- Do not duplicate name/subtitle/category terms into hidden keywords where current Apple rules advise against it.
- Do not claim work orders, routing, teams, cloud, compliance, certification, measurements, or new verticals because a translated keyword has demand.
- Screenshots must use synthetic data, current UI, correct language, correct device dimensions, and approved claims.
- Support/privacy URLs and help paths must be available and understandable for each metadata localization.
- A localized U.S. product page does not expand storefront geography.
- P06-C05 prepares evidence; P07-C02 is the only release action and remains owner-authorized.

## 33. Risk register and bug-prevention controls

| Risk | Failure mode | Preventive control | Blocking evidence |
|---|---|---|---|
| Phase 10 collision | Provisional V30 diverges from later accepted brand/UI work | Separate worktree, exact S10-shared labels, frozen replay manifest, mandatory P05 three-lineage reconciliation; S10 wins actual brand/UI conflicts | Unresolved path or semantic overlap |
| Frozen V23 rewrite | Card/receipt history becomes ambiguous | Successor package, append-only lineage, no Card 147 | Any changed V23 package identity |
| Planning/provisional branch misuse | Old V23 base enters main | Never merge either branch wholesale; P05 replays/reimplements card-scoped deltas onto accepted S | Planning/provisional merge commit in main ancestry |
| Incomplete localization | Hidden English/raw keys | Complete inventory, machine key audit, zero fallback | Any critical missing key |
| Language overclaim | Menu lists unreviewed language | Capability matrix and human receipt | Missing professional review |
| Spanish mistranslation | Literal or regionally narrow safety terms | U.S./Latin-American termbase plus bilingual field review | Ambiguous critical term |
| Chinese script conflation | zh-Hans presented as zh-Hant | Separate cards/catalogs/reviews | Mechanical conversion without review |
| Unicode loss | Question marks or corrupted evidence | End-to-end hostile corpus and renderer replacement | Any lost grapheme/glyph |
| Canonical data drift | Locale changes hashes/records | Cross-locale invariance suite | Any unexpected canonical difference |
| Hidden fallback | App silently mixes English | Local counters and zero-fallback acceptance | Unexpected fallback |
| Layout regression | Long text hides action/warning | Real/pseudo matrix, Dynamic Type, smallest device | Clipped/unreachable critical UI |
| RTL defect | Mirrored semantics or mixed IDs break | Pseudo-RTL, hostile Arabic/bidi fixtures | Navigation/report/identifier failure |
| Report mismatch | Photos/comments/status detach | Golden report semantics and extraction checks | Association or pagination loss |
| Offline regression | Catalog/state unavailable without network | Bundled resource/offline startup/workflow tests | Network dependency or lost queued data |
| Search corruption | Normalization mutates evidence | Derived versioned index only | Canonical mutation or nonrebuildable index |
| Stale research | Wrong language/metadata choice | P01/P05 refresh schedule | Expired or unscoped source |
| Vendor data exposure | Customer data sent for translation | Synthetic screenshots and minimum source context | Real customer data in vendor bundle |
| False jurisdiction | Translation implies global standards | Six-axis separation and country HOLD | Language-driven standards selection |
| False credit | Static/branch evidence called accepted | Explicit credit flags and receipt checks | Evidence class mismatch |
| Release too early | V23 Card 135 targets old candidate | Disposition bridge and post-V30 owner release | Pre-globalization release binding |

## 34. Deterministic validation of this blueprint

Before the external V30 draft is called reviewed:

1. Parse all card rows.
2. Verify 55 IDs and ordinals 1 through 55.
3. Verify unique IDs/ordinals.
4. Parse every prerequisite list.
5. Verify every referenced ID exists and precedes its consumer.
6. Topologically sort and prove acyclic.
7. Verify no range shorthand or malformed V30 ID.
8. Verify initial locale registry has exactly en, es, zh-Hans, zh-Hant, vi, and ko, with en-US and es-US presentation profiles kept separate from catalog identity.
9. Verify `LocaleMarketMatrixV1` has one row for each of those six resources and separates formatting, metadata, storefront, jurisdiction, support, and claim status.
10. Verify every locale has exactly one implementation card and converges at P04-C07.
11. Verify exactly 107 unique direct edges, the P00 nine-edge admission graph, P05 reconciliation bridge, P06 acceptance convergence, and P07 release lifecycle.
12. Verify all 97 V24 disposition records, their source anchors, one disposition each, valid V30 targets, and `noCredit=true`.
13. Verify V23 unfinished statuses and all recorded source hashes.
14. Verify all Markdown links have valid syntax and every official/review claim has a source.
15. Verify no trailing whitespace, no accidental placeholder, no conflicting card or edge count, and one final newline.
16. Verify the authority/handoff/package hashes, frozen V23/coordination/S10 pins, worktree/branch names, P00–P04 pre-S10 boundary, P05–P07 gate, shared-path labeling, and zero-credit flags.
17. Reject any permission for V30 to read or poll `C:\AssetRounds` at any time; the owner trigger permits only verification of externally supplied accepted evidence.
18. Independently review reconciliation, language selection, graph, privacy, claims, and no-credit semantics.
19. Keep C:\AssetRounds-v30-globalization-foundation clean.

Before activation, repeat the checks after splitting into four files, validate authority/support artifacts, and compare the semantic projection to this reviewed draft.

## 35. Recommended defaults and owner decision points

| Decision | Recommended default | Owner input becomes mandatory |
|---|---|---|
| Initial commercial geography | United States only | Before any foreign storefront |
| Initial complete localizations | en, es, zh-Hans, zh-Hant, vi, ko | Before bootstrap; P01-C01 confirms the pinned cohort. A different decision is `AMENDMENT_REQUIRED`. |
| First non-English priority | Spanish | Before translation commissioning |
| Language selection | Apple device/per-app selection plus in-app Settings discovery | Before any custom picker |
| Unsupported language | English fallback with truthful effective-language display | Before changing fallback |
| Report language | App language default, explicit supported export choice | Before report UX freeze |
| Authored content | Preserve source; no automatic translation | Before any translation service |
| Spanish style | U.S./Latin-American field Spanish with tested regional alternatives | At termbase review |
| Chinese scripts | Separate professional zh-Hans and zh-Hant | Before either is declared complete |
| Next wave | pt-BR, fil, ar, fr/fr-CA, ru, pl, hi, id, ja, tr, ht | At P07-C03 |
| Translation quality | Professional translation plus independent in-context review | Before P06-C02 acceptance |
| Telemetry | None added by V30 | Before any analytics/support diagnostics upload |
| Jurisdiction | Separate licensed/versioned packs; never language-derived | Before any non-U.S. claims |
| Release | Owner action after exact-main V30 acceptance | At P07-C02 |

## 36. Copy-ready pre-S10 Codex handoff summary

The complete owner-copyable prompt is the package file `NEXT_CODEX_SESSION_PROMPT.md`. Its operative summary is:

Start AssetRounds V30 today in a separate provisional branch/worktree without accessing or polling the active Phase 10 checkout. Treat this user message as owner direction to validate and install the exact hash-bound V30 R2 package. Create `phase/v30-globalization` and `C:\AssetRounds-v30-globalization` only from frozen V23 head `acbfb68355f903fe98638b6ef22e4814e7b48328` / tree `47e17fae6b73dccd5029ccf4ac7cca659196f225`. Do not use the planning worktree as an implementation base.

Read the package manifest, provisional authority, Foundation Plan, complete Architecture Blueprint, Handoff, and this prompt before mutation. Recompute all hashes. Verify frozen V23 and coordination pins only in their named non-Phase-10 worktrees. `C:\AssetRounds` is permanently forbidden as a read/status/build/test/Git/process target; my later Phase 10.6 completion message permits only verification of separately supplied accepted evidence and never access to that checkout.

Install the package, create the namespaced provisional ledger through G3, and start with Card 1: `V30-P00-C01 — Provisional authority and isolated-lane validation`. Execute the graph-enumerated 37-card pre-S10 cohort in order, one current card at a time. Exact fences may include a frozen S10-reserved file only when its pre-existing external owner-authority tuple permits it and it is marked `S10_SHARED_RECONCILIATION_REQUIRED`; this is safe because changes occur only on the isolated V30 branch, but it guarantees later reconciliation. Preserve every commit, failure, test, artifact, and old-to-future replay requirement.

All pre-S10 results are provisional. Green Windows checks or hosted macOS branch CI do not accept a card, prove Phase 10 compatibility, mutate `main`, close V30, promote a translation, or authorize release. The complete post-S10 cohort is not selectable. Stop at frozen V30-P04-C07 if Phase 10.6 is still incomplete.

When I later report Phase 10.6 complete, verify the exact accepted evidence rather than trusting the message as proof. Create a separate reconciliation branch/worktree from the accepted post-Phase-10/V23 green main, compare frozen V23 B, frozen V30 P, and accepted main S, then replay or reimplement every card-scoped V30 change. Never merge the provisional or planning branch wholesale. Phase 10 owns actual brand/UI conflicts; preserve V30 behavior by reapplying it against the accepted design and rerunning all invalidated tests. Only P06/P07 post-reconciliation evidence can accept V30 or integrate main.

Required complete localizations are en, es, zh-Hans, zh-Hant, vi, and ko. Use Apple system/per-app language resolution, an in-app Settings discovery row, and English fallback; no bundle swizzling. Keep app language, formatting locale, authored-content language, report language, storefront, and jurisdiction separate. The initial market/storefront/jurisdiction remains United States only. Translation cannot imply foreign legal/standards support or unsupported OCR/dictation/speech capability.

Give subagents exact nonoverlapping path ownership, pins, invariants, validation commands, prohibitions, and expected evidence. One integrator owns shared catalog/project paths; one writer owns the current provisional ledger. Never sign, upload, submit, release, activate a foreign storefront, fabricate owner/native/legal/physical evidence, force-push, or rewrite accepted history.

## 37. Completion definition

### 37.1 Blueprint and start-today package completion

This planning task is complete when:

- the R1 planning worktree exists at the exact frozen V23 head and remains clean;
- the R2 owner-copyable package names the separate provisional branch/worktree, first card, exact base, forbidden Phase 10 target, and post-S10 reconciliation path;
- the external document is source-backed and distinguishes evidence from inference;
- the user keyword package has been integrity-checked and correctly scoped;
- the initial language cohort and next-wave order are explicit;
- the 55-card, 107-direct-edge graph is unique, closed, acyclic, and topologically valid;
- V23, V24, Phase 10, coordination, branch, and no-credit rules are preserved;
- an independent audit finds no blocking ambiguity or malformed dependency;
- file hygiene and SHA-256 are reported.

This makes V30 ready to start in a new owner-authenticated Codex task. It does not mean V30 is implemented or accepted.

### 37.2 V30 product implementation completion

V30 product implementation completes at accepted V30-P07-C01 only when:

- accepted Phase 10.6 and all V23 history/receipts are preserved;
- V23 is reconciled without hidden loss or false promotion;
- Cards 135, 136, 141, and 146 have truthful dispositions;
- en, es, zh-Hans, zh-Hant, vi, and ko are bundled complete localizations;
- every required app-owned UI, accessibility, permission, help, error, recovery, notification, report, export, and Settings surface is covered;
- every locale has professional and independent in-context linguistic acceptance;
- Apple device/per-app selection and English fallback work;
- zero unresolved localization keys and zero unexpected fallback occur in exercised `APP_OWNED_SHIPPING` inventory paths;
- language, formatting, authored content, report, storefront, and jurisdiction remain independent;
- identical workflows preserve canonical records, hashes, journals, evidence, backup identity, and jurisdiction;
- Unicode survives input, search, persistence, reports, exports, backup, restore, print, email, and sharing;
- reports have qualified fonts, no question-mark substitution, correct extraction/layout, and historical provenance;
- offline startup/work/recovery and localized state truth pass;
- UI/accessibility and output matrices pass on the exact candidate;
- U.S. metadata/readiness is truthful and all foreign countries remain HOLD;
- exact-head phase and exact-main hosted iOS evidence is green and checksummed;
- branch/ref ancestry is clean and non-force;
- no signing, release, foreign availability, owner, or monitor evidence is implied.

### 37.3 Release completion

Release is separate. It requires V30-P07-C02 owner evidence for the exact accepted build and remains subject to signing, account, agreements, metadata, privacy, title, storefront, TestFlight/App Store, and promotion authority.

### 37.4 Future language or country completion

A next-wave locale or foreign country completes only after:

- P07-C03 or later research selects it;
- an append-only authority adds exact cards/edges/path fences;
- complete catalog/report/help/accessibility implementation;
- professional and independent native review;
- hosted exact-head UI/output/offline acceptance;
- privacy/legal/support/storefront/jurisdiction readiness;
- owner availability/release action;
- post-release monitor eligibility.

No architecture fixture or translated catalog alone provides that credit.

## 38. Research source index

### Apple

- [Localization overview](https://developer.apple.com/documentation/xcode/localization)
- [Preparing app text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)
- [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Plural localization](https://developer.apple.com/documentation/xcode/localizing-strings-that-contain-plurals)
- [How iOS selects app language](https://developer.apple.com/library/archive/qa/qa1828/_index.html)
- [Language identifiers and fallback](https://developer.apple.com/library/archive/technotes/tn2418/)
- [Testing localizations](https://developer.apple.com/documentation/xcode/testing-localizations-when-running-your-app)
- [Preparing interfaces](https://developer.apple.com/documentation/xcode/preparing-your-interface-for-localization)
- [Screenshots for localizers](https://developer.apple.com/documentation/xcode/creating-screenshots-of-your-app-for-localizers)
- [Exporting localizations](https://developer.apple.com/documentation/xcode/exporting-localizations)
- [Right-to-left design](https://developer.apple.com/design/human-interface-guidelines/right-to-left)
- [App Store localization reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)
- [Localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information)
- [Upload screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
- [Manage availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)

### U.S. language and field-workforce evidence

- [2024 ACS C16001](https://data.census.gov/table/ACSDT1Y2024.C16001?q=C16001)
- [2024 ACS B16001](https://data.census.gov/table/ACSDT1Y2024.B16001?q=B16001)
- [2019 Census language-use report](https://www.census.gov/content/dam/Census/library/publications/2022/acs/acs-50.pdf)
- [2024 ACS subject definitions](https://www2.census.gov/programs-surveys/acs/tech_docs/subject_definitions/2024_ACSSubjectDefinitions.pdf)
- [BLS 2024 Table 11](https://www.bls.gov/cps/data/aa2024/cpsaat11.htm)
- [BLS foreign-born workers 2025](https://www.bls.gov/news.release/archives/forbrn_05192026.pdf)
- [NIOSH Construction](https://www.cdc.gov/niosh/construction/about/index.html)
- [NIOSH fall-prevention language evidence](https://www.cdc.gov/niosh/bulletin/2023/falls-stand-down.html)
- [CPWR Hispanic-worker research](https://www.cpwr.com/research/published-research/cpwr-reports/hispanic-workers/)
- [OSHA publications](https://www.osha.gov/publications/)

### Competitor and workflow evidence

- [SafetyCulture languages](https://help.mitti.com/000027)
- [SafetyCulture multilingual templates](https://help.safetyculture.com/003515)
- [MaintainX languages](https://help.getmaintainx.com/supported-languages)
- [MaintainX offline mode](https://help.getmaintainx.com/offline-mode)
- [UpKeep languages](https://help.onupkeep.com/en/articles/122220-how-to-set-your-language-in-upkeep)
- [GoCanvas languages](https://help.gocanvas.com/hc/en-us/articles/35945394380823-GoCanvas-Supported-Languages)
- [Fulcrum language](https://help.fulcrumapp.com/en/articles/10646201-setting-the-language-for-the-fulcrum-mobile-app)
- [Fieldwire language](https://help.fieldwire.com/hc/en-us/articles/202632084-How-to-change-the-language-that-displays-in-Fieldwire)
- [ArcGIS Field Maps requirements](https://doc.arcgis.com/en/field-maps/get-started/requirements.htm)
- [ArcGIS Survey123 requirements](https://doc.arcgis.com/en/survey123/get-started/systemrequirements.htm)
- [Autodesk supported languages](https://help.autodesk.com/cloudhelp/ENU/Docs-About-ACC/files/Supported_Languages.html)

## 39. Final decision

V30 is possible, safe, and worth doing before AssetRounds' first public release.

The winning globalization strategy is not the longest language menu. It is a complete, native-feeling field workflow whose offline state, evidence, reports, search, accessibility, and recovery remain trustworthy in every language the app claims.

For the U.S.-first product, V30 therefore requires English, U.S. Spanish, Simplified Chinese, Traditional Chinese, Vietnamese, and Korean. Spanish is P0. Brazilian Portuguese, Filipino, Arabic, French, Russian, Polish, and Haitian Creole remain visible, ordered, and research-ready rather than forgotten.

The R1 planning branch preserves the exact V23 head and stays clean. The V30 provisional execution branch may now be created from that exact frozen V23 head so the 37-card pre-S10 cohort can be built today without touching Phase 10. After Phase 10.6, a separate reconciliation branch is born from accepted green main and becomes the only route to the 18-card post-S10 cohort, final acceptance, and main. That is how AssetRounds gains a durable global foundation now without sacrificing the work already completed.

## Appendix A — V24 normative-requirement disposition matrix

Source: `C:\Users\palat\OneDrive\Desktop\ASSETROUNDS_V24_GLOBALIZATION_FOUNDATION_BLUEPRINT.md`, raw SHA-256 `370c378bbb3b567c465d217111e8de3342581916e260b234a32511e807c01d94`.

This matrix contains 97 ordered requirement records. Every row has `noCredit=true`: V24 is immutable planning provenance and transfers no implementation, acceptance, CI, phase, merge, release, or successor-start credit. The source line anchors refer to the frozen V24 bytes above.

| # | V24 anchor | Normative requirement or outcome | Disposition | V30 target and rationale |
|---:|---|---|---|---|
| 1 | Status L6–17 | External planning artifact; no self-authorization; only an activated package may govern execution | INCORPORATED_WITH_PROVENANCE | §§2, 3.2, 26, 27; V30 preserves V24 as immutable provenance. |
| 2 | §1 L23–36 | Additive successor; never insert into or rewrite V23; preserve V23 history | INCORPORATED_WITH_PROVENANCE | §4.3, V30-P05-C02, G8; retained through card-scoped replay. |
| 3 | §1 L27–35 | Preserve commits/cards; reconcile S10; freeze base; separate language, locale, content, report, and jurisdiction | INCORPORATED_WITH_PROVENANCE | §11.2, V30-P01-C04, V30-P05-C01, V30-P05-C02; strengthened to six axes. |
| 4 | §1.1 L40 | Expand launch-country matrix if market exceeds the U.S. | DEFERRED_UNCHANGED | §§31–32 and §37.4; foreign-country activation remains owner-authorized future work. |
| 5 | §1.1 L42–49 | U.S./English-only initial shipping; future locales dormant | REJECTED_WITH_RATIONALE | §9.2 and V30-P04-C02, V30-P04-C03, V30-P04-C04, V30-P04-C05, V30-P04-C06; V30 uses six complete localizations but retains U.S.-only storefront scope. |
| 6 | §2 L53–62 | No credit, active-phase mutation, fabricated evidence, force/history rewrite, or automatic release/submission | INCORPORATED_WITH_PROVENANCE | §§2, 25, 26, 37.3; retained. |
| 7 | §3.2 L89–94 | Preserve V23 135/136/141/146 classes, prerequisites, static=false, and no automatic credit | INCORPORATED_WITH_PROVENANCE | §§4.2–4.3, V30-P05-C03, G6; retained. |
| 8 | §3.3 L98–106 | No pre-globalization release evidence; bind final owner release to successor candidate | INCORPORATED_WITH_PROVENANCE | V30-P05-C03, V30-P07-C02, §37.3; explicit post-globalization rebind/pending rule. |
| 9 | §4.1 L114–121 | Evolve existing V23 localization/accessibility/report/search seams; no parallel framework | INCORPORATED_WITH_PROVENANCE | §5, §11.1, §36; retained. |
| 10 | §4.2 L129–137 | Version-forward English-only shipping policy without weakening historical behavior | INCORPORATED_WITH_PROVENANCE | §§11.3–11.4, V30-P01-C05, V30-P01-C08; retained. |
| 11 | §4.2 L131; §4.3 L141–149 | Classify every user-visible surface; do not blindly replace literals | INCORPORATED_WITH_PROVENANCE | V30-P01-C03, V30-P02-C01; inventory and dispositions expanded. |
| 12 | §4.2 L134 | Activate localization/accessibility UI verification only on reconciled UI | INCORPORATED_WITH_PROVENANCE | V30-P02-C06, V30-P05-C05, V30-P06-C03; final evidence remains post-reconciliation. |
| 13 | §4.2 L135 | Replace ASCII-loss PDF behavior with Unicode/font/paper policy | INCORPORATED_WITH_PROVENANCE | §17.1, V30-P03-C04; retained. |
| 14 | §4.2 L137 | UI translation must not imply OCR, dictation, or grammar support | INCORPORATED_WITH_PROVENANCE | V30-P03-C07, §25; retained. |
| 15 | §5.3 L201–207 | Preserve source evidence; provenance-label translations; offline resources; Unicode; binary/exact-head proof; language is not jurisdiction | INCORPORATED_WITH_PROVENANCE | §§11, 14, 16–18, 23, 25; retained with tighter source-content rules. |
| 16 | §6.1 L213–218 | English fallback; exact/base/English/test diagnostic chain; no raw keys; zero fallback for a complete locale | INCORPORATED_WITH_PROVENANCE | §10.3, V30-P01-C06, §23.0–23.1; bounded to `APP_OWNED_SHIPPING`. |
| 17 | §6.2 L224–229 | English foundation plus V24's named future-wave portfolio | REJECTED_WITH_RATIONALE | §§9.2–9.4, V30-P04-C02, V30-P04-C03, V30-P04-C04, V30-P04-C05, V30-P04-C06, V30-P07-C03; V30 changes the initial cohort and research order. |
| 18 | §6.3 L235–240 | Variants only where copy differs; formatting independent | INCORPORATED_WITH_PROVENANCE | §§9.2–9.3, 11.2, 13; retained, while V24's exact future variants remain later scope. |
| 19 | §7.1 L246–253 | Apple system/per-app resolution; no bundle swizzle or hidden engine | INCORPORATED_WITH_PROVENANCE | §10.1, V30-P01-C06; retained. |
| 20 | §7.2 L257–272 | Effective-language Settings disclosure, iOS Settings handoff, truthful fallback, no side effects, atomic foreground/restart behavior | INCORPORATED_WITH_PROVENANCE | §10.2, V30-P01-C06, V30-P02-C07; retained and expanded. |
| 21 | §7.3 L276–285 | Independent app language, formatting, zone, calendar, units, jurisdiction, content, and report axes | INCORPORATED_WITH_PROVENANCE | §11.2, V30-P01-C04; retained and storefront added. |
| 22 | §8.1 L291 | IDs, raw enums, hashes, and schema keys remain language-neutral and stable | INCORPORATED_WITH_PROVENANCE | §11.3, V30-P01-C05, §23.2; retained. |
| 23 | §8.1 L292–297 | No translated canonical truth; typed canonical values; locale cannot alter identity; preserve source/historical evidence; stable semantic keys | INCORPORATED_WITH_PROVENANCE | §§11.3–11.4, §§16–17, V30-P01-C05, V30-P03-C01, V30-P03-C08; retained. |
| 24 | §8.1 L298 | No grammatical concatenation; typed placeholders and plural/select | INCORPORATED_WITH_PROVENANCE | §12.2, V30-P02-C01; retained. |
| 25 | §8.2 L302–307 | Language/device region never chooses jurisdiction; explicit versioned packs; never guess missing/expired rules | INCORPORATED_WITH_PROVENANCE | §§11.2, 16, 31, V30-P06-C06; retained. |
| 26 | §8.3 L311–315 | Shipping catalogs/report assets/capability manifests work offline; compatible signed optional updates; no unapproved network translation | INCORPORATED_WITH_PROVENANCE | §12.3, §18, V30-P01-C08, V30-P03-C02; retained. |
| 27 | §8.4 L318–322 | Contract-bounded normalization; preserve evidence; spoof/injection protection; nondestructive mixed-script warnings; translated-report provenance | INCORPORATED_WITH_PROVENANCE | §§14–17, V30-P02-C02, V30-P02-C03, V30-P03-C04, V30-P03-C05; retained. |
| 28 | §9 L326–353 | Map proposed models to existing architecture; version-forward only as needed; no duplicate abstraction | INCORPORATED_WITH_PROVENANCE | §11.1, V30-P01-C04, V30-P01-C05, V30-P01-C08; retained. |
| 29 | §10.1 L359–366 | String Catalog source of truth; semantic keys/comments; plurals/full messages; typed placeholders; complete surface inventory; DNT treatment | INCORPORATED_WITH_PROVENANCE | §12, V30-P01-C03, V30-P02-C01; retained and strengthened. |
| 30 | §10.2 L372–386 | Shipping catalog provenance, review, lint, screenshot, accessibility, exceptions, and exact-head receipt | INCORPORATED_WITH_PROVENANCE | §12.3, §19, V30-P01-C08, V30-P04-C01, V30-P06-C01, V30-P06-C02; retained. |
| 31 | §10.2 L388–390 | Machine translation is nonshipping unless reviewed; derived translation source binding and atomic stale/superseded/erase lifecycle | INCORPORATED_WITH_PROVENANCE | §§16, 19.3, V30-P03-C01, §25; retained without authorizing a translation service. |
| 32 | §10.3 L394–402 | English linguistic/consistency review and claim-safe terminology | INCORPORATED_WITH_PROVENANCE | §12, §19.2, V30-P02-C01, V30-P04-C01; retained. |
| 33 | §11 L406–427 | Locale formatting, zone/offset/DST, canonical values, unit/currency identity, Letter/A4, international address/phone, stable recurrence | INCORPORATED_WITH_PROVENANCE | §13, V30-P01-C07; retained. |
| 34 | §11.1 L431–440 | Explicit locale-bound parsing, ambiguity confirmation, DST choice, audit representation, canonical conversion/round trip, no reinterpretation | INCORPORATED_WITH_PROVENANCE | §§13.1–13.4, V30-P01-C07; retained. |
| 35 | §12.1 L446–452 | Semantic RTL layout, correct mirroring, mixed-direction tests, Dynamic Type, hit targets, VoiceOver order | INCORPORATED_WITH_PROVENANCE | §§14.2, 14.4, V30-P02-C03, V30-P02-C04; retained. |
| 36 | §12.2 L458–474 | Full named hostile Unicode fixture list, including future-language-specific samples | DEFERRED_UNCHANGED | §§14.1–14.3, V30-P02-C02, V30-P02-C03, V30-P07-C03; core Arabic/CJK fixtures incorporated, other language-specific fixtures defer. |
| 37 | §12.3 L478–486 | Preserve source; versioned derived search; locale normalization; no English-only stemming; stable ties; atomic rebuild; derived-data boundaries | INCORPORATED_WITH_PROVENANCE | §15, V30-P02-C05; retained. |
| 38 | §12.4 L490–499 | Complete-locale localized accessibility, control audits, non-color state, and native review | INCORPORATED_WITH_PROVENANCE | §14.5, V30-P02-C04, V30-P06-C02, V30-P06-C03; retained. |
| 39 | §13.1 L505–521 | Explicit report language plus locale/catalog/font/translation/fallback/source provenance; immutable historical replay | INCORPORATED_WITH_PROVENANCE | §10.4, §§11.4, 17, V30-P02-C07, V30-P03-C04, V30-P03-C08; retained. |
| 40 | §13.2 L525–536 | Unicode deterministic PDF, licensed fonts, bidi/CJK, Letter/A4, no clipping, semantics/extraction, provenance, and no unsupported conformance claim | INCORPORATED_WITH_PROVENANCE | §17.1, V30-P03-C04, V30-P06-C04; retained. |
| 41 | §13.3 L540–545 | Stable machine JSON/CSV; manifest-backed human CSV; ID-based import; formula protection; explicit delimiters | INCORPORATED_WITH_PROVENANCE | §17.2, V30-P03-C05; retained. |
| 42 | §13.4 L549–558 | Localize email/share/print/label/adapter surfaces while retaining machine IDs | INCORPORATED_WITH_PROVENANCE | §18, V30-P03-C06, V30-P03-C09; retained. |
| 43 | §14.1 L566–578 | Licensed, versioned, effective-dated, reviewed, traceable, offline, explicitly activated jurisdiction packs | INCORPORATED_WITH_PROVENANCE | §16, §31, V30-P06-C06; retained. |
| 44 | §14.2 L582–598 | Country/storefront readiness fields and fail-closed HOLD cross-product | INCORPORATED_WITH_PROVENANCE | §§31–32, V30-P06-C06, §§37.2, 37.4; retained. |
| 45 | §14.2 L602 | Legal conclusions require owner/professional evidence | INCORPORATED_WITH_PROVENANCE | V30-P06-C06, §25; retained. |
| 46 | §15 L606–619 | Binary/store metadata separation; localized metadata/screenshots/support/privacy/export/storefront evidence; reassess privacy/encryption changes | INCORPORATED_WITH_PROVENANCE | §32, V30-P06-C05, V30-P06-C06; retained. |
| 47 | §16 L623–625 | Proposed cards cannot execute until bootstrap freezes exact graph/fences/selectors/pins; no shorthand prerequisites | INCORPORATED_WITH_PROVENANCE | §§20–22 and G1–G4; retained with provisional and post-S10 gates. |
| 48 | §16.1 L638–649 | Closed class semantics and no-credit rules | INCORPORATED_WITH_PROVENANCE | §20 and §25; retained. |
| 49 | §16.2 L720–725 | Explicit eligibility for S10, bootstrap, future locales, legal review, and monitor | INCORPORATED_WITH_PROVENANCE | §21, §26, §37.4; retained under V30 IDs. |
| 50 | §16.2 L727 | Exact V24/V23 monitor nonoverlap receipt and flags | REJECTED_WITH_RATIONALE | V30-P05-C03, V30-P07-C05, §25; V30 removes V24 IDs, preserves V23 monitor truth, and uses a distinct V30 monitor. |
| 51 | §17 L731–739 | Sequential activation; fenced parallelism; one shared-resource owner; audit lane; static/Windows evidence is never iOS/release credit | INCORPORATED_WITH_PROVENANCE | §§20, 22, 25, 29; retained. |
| 52 | §18.1 L745–754 | Complete-locale criteria for keys, placeholders, plurals, unresolved keys/fallback, pseudolocale exclusion, digest, and receipt | INCORPORATED_WITH_PROVENANCE | §§23.0–23.1, V30-P06-C01, V30-P06-C02; retained with a bounded shipping predicate. |
| 53 | §18.2 L758–767 | Cross-language equality of canonical records, IDs, backup, schemas, jurisdiction, authored evidence, and derived-translation invalidation | INCORPORATED_WITH_PROVENANCE | §23.2, V30-P01-C05, V30-P03-C01, V30-P06-C04; retained. |
| 54 | §18.3 L771–784 | V24 formatting matrix including fr, de, pt, it, and nl locales | DEFERRED_UNCHANGED | §23.3, V30-P01-C07, V30-P07-C03; formatting architecture stays, but exact future-locale rows defer because V30's cohort differs. |
| 55 | §18.4 L788–796 | Expansion/RTL/device/orientation/Dynamic Type/contrast/VoiceOver/no-clipping UI matrix | INCORPORATED_WITH_PROVENANCE | §§14.4–14.5, §23.4, V30-P06-C03; retained. |
| 56 | §18.5 L800–812 | Script/font/PDF/history/machine-export/CSV output matrix; fixtures are not shipping proof | INCORPORATED_WITH_PROVENANCE | §23.5 and §25; retained. |
| 57 | §18.6 L816 | Hosted macOS exact-head iOS evidence only; Windows cannot claim Xcode/Simulator results | INCORPORATED_WITH_PROVENANCE | §23.6, V30-P06-C03, V30-P06-C04, V30-P06-C07; retained. |
| 58 | §19 G0/Trigger L824–842 | No pre-trigger polling; freeze admissions; verify S10 evidence/reservation/overlap; classify provisional evidence without promotion | INCORPORATED_WITH_PROVENANCE | G5–G6, V30-P05-C01, V30-P05-C04; retained while pre-S10 work remains isolated. |
| 59 | §19 G2–G4 L855–874 | Non-force reconciliation; preserve history; exact-main green CI; branch only from exact green main | INCORPORATED_WITH_PROVENANCE | G6–G9, V30-P05-C02, V30-P05-C03, V30-P05-C04, V30-P05-C05; retained. |
| 60 | §19 G5 L878–884 | Bootstrap package, single writer/CAS, token, freeze on mismatch, and only the next card | INCORPORATED_WITH_PROVENANCE | G1–G4, V30-P00-C01, V30-P00-C02, V30-P00-C03, V30-P00-C04, V30-P00-C05, V30-P00-C06; retained and strengthened with external owner authority. |
| 61 | §19 integrity L888–896 | V24-specific four-file digest algorithm and receipt timing | REJECTED_WITH_RATIONALE | §27.2; V30 requires accepted V23 digest reuse or a separately authorized versioned schema rather than adopting V24's custom algorithm. |
| 62 | §20 L900–908 | Worktree separation; existing single writer; local files are not presumed backed up | INCORPORATED_WITH_PROVENANCE | §28; retained with V30 paths. |
| 63 | §21 L916–924 | V24 owner defaults for language, translation, report, content, packs, and launch | REJECTED_WITH_RATIONALE | §§9, 35, 37.4; decision categories remain, but V30 changes the cohort and defaults. |
| 64 | §22 L930–934 | Full preflight, non-force reconciliation, no fabricated evidence, authoritative macOS CI, exact cards/fences | INCORPORATED_WITH_PROVENANCE | §§20, 25, 26, 36; retained. |
| 65 | §23.1 L940–955 | V24 U.S./English-only foundation completion definition | REJECTED_WITH_RATIONALE | §37.2; V30 requires six complete localizations while keeping U.S.-only availability and foreign HOLD. |
| 66 | §23.2 L959 | Future locale requires re-entry, complete catalog/output CI, readiness, review, owner availability; monitor gives no credit | INCORPORATED_WITH_PROVENANCE | §37.4, V30-P07-C03, V30-P07-C04, V30-P07-C05; retained. |
| 67 | P00-C01 L655 | Verify accepted S10/V23/coordination/refs/dirty/worktrees/digests/reservation | INCORPORATED_WITH_PROVENANCE | V30-P05-C01; same post-trigger evidence outcome. |
| 68 | P00-C02 L656 | Non-force V23 reconciliation; S10 wins recomputed shared conflicts; preserve nonoverlap/evidence | INCORPORATED_WITH_PROVENANCE | V30-P05-C02; same outcome plus provisional replay. |
| 69 | P00-C03 L657 | Recompute V23 135/136/141/146 without reclassification or fabrication | INCORPORATED_WITH_PROVENANCE | V30-P05-C03; same outcome. |
| 70 | P00-C04 L658 | Exact reconciled V23 generators/verifiers plus hosted iOS; no Windows iOS claim | INCORPORATED_WITH_PROVENANCE | V30-P05-C04, V30-P05-C05; evidence disposition and hosted qualification are split. |
| 71 | P00-C05 L659 | Authority adoption, one-use admission, single writer, only next card | INCORPORATED_WITH_PROVENANCE | V30-P00-C01, V30-P00-C02, V30-P00-C03, V30-P00-C04, V30-P00-C05, V30-P00-C06, V30-P05-C06; provisional admission and canonical adoption are distinct CAS sequences. |
| 72 | P01-C01 L665 | Typed BCP-47/IANA/ISO/calendar/unit/jurisdiction model | INCORPORATED_WITH_PROVENANCE | V30-P01-C04; same outcome. |
| 73 | P01-C02 L666 | Complete text classification, semantic English catalog/comments, no unexplained raw keys | INCORPORATED_WITH_PROVENANCE | V30-P01-C03, V30-P02-C01; split inventory from implementation. |
| 74 | P01-C03 L667 | System language/fallback/Settings/no mixed state/no swizzle | INCORPORATED_WITH_PROVENANCE | V30-P01-C06, V30-P02-C07; split resolution from UI. |
| 75 | P01-C04 L668 | Locale-aware formatting/input with canonical stability | INCORPORATED_WITH_PROVENANCE | V30-P01-C07; same outcome. |
| 76 | P01-C05 L669 | Bundled catalogs, digest, compatibility, no network dependency | INCORPORATED_WITH_PROVENANCE | V30-P01-C08, V30-P04-C07; machinery is separated from the first complete content release. |
| 77 | P01-C06 L670 | Historical en-US evidence and durable-identity compatibility | INCORPORATED_WITH_PROVENANCE | V30-P01-C05, V30-P03-C08; split invariance from replay. |
| 78 | P02-C01 L676 | International input/normalization/bidi safety/evidence fidelity | INCORPORATED_WITH_PROVENANCE | V30-P02-C02; same outcome. |
| 79 | P02-C02 L677 | RTL layout/direction/mixed text/navigation/report/focus | INCORPORATED_WITH_PROVENANCE | V30-P02-C03; same outcome. |
| 80 | P02-C03 L678 | Expansion/Dynamic Type/accessibility/non-Latin typography/font policy | INCORPORATED_WITH_PROVENANCE | V30-P02-C04; same outcome. |
| 81 | P02-C04 L679 | Derived locale search/sort/index lifecycle and canonical safety | INCORPORATED_WITH_PROVENANCE | V30-P02-C05; same outcome. |
| 82 | P02-C05 L680 | Pseudo/RTL/long-text/screenshots/missing-key/fallback harness with no analytics | INCORPORATED_WITH_PROVENANCE | V30-P02-C06; same outcome. |
| 83 | P03-C01 L686 | Authored-content language and derived-translation provenance/lifecycle | INCORPORATED_WITH_PROVENANCE | V30-P03-C01; same outcome. |
| 84 | P03-C02 L687 | Unicode accessible PDF, qualified font, Letter/A4, exact historical provenance | INCORPORATED_WITH_PROVENANCE | V30-P03-C04; same outcome. |
| 85 | P03-C03 L688 | Stable JSON/CSV/import plus localized human views and canonical round trip | INCORPORATED_WITH_PROVENANCE | V30-P03-C05; same outcome. |
| 86 | P03-C04 L689 | Separate UI/template/guidance/evidence/report/regional content | INCORPORATED_WITH_PROVENANCE | V30-P03-C01, V30-P03-C06; split model from surfaces. |
| 87 | P03-C05 L690 | Per-locale OCR/dictation/voice/speech truth; no implied support | INCORPORATED_WITH_PROVENANCE | V30-P03-C07; same outcome. |
| 88 | P04-C01 L696 | Termbase/style/vendor/review/fallback/offline/correction process | INCORPORATED_WITH_PROVENANCE | V30-P04-C01; same outcome. |
| 89 | P04-C02 L697 | Deferred es-MX/es-ES complete Spanish release | REJECTED_WITH_RATIONALE | V30-P04-C02; V30 implements base es with es-US/es-MX/es-419 validation and does not promise es-ES. |
| 90 | P04 locale-card block L698–702 | Deferred fr/de/pt/it/nl complete releases | DEFERRED_UNCHANGED | V30-P07-C03, §§9.3–9.4; retained as future research/re-entry, not initial cards. |
| 91 | P04-C08 L703 | Wave-2 validation for CJK/Turkish/Vietnamese/Russian/Arabic without shipping claim | REJECTED_WITH_RATIONALE | V30-P02-C02, V30-P02-C03, V30-P02-C04, V30-P02-C05, V30-P04-C03, V30-P04-C04, V30-P04-C05, V30-P04-C06, V30-P07-C03; CJK/Vietnamese/Korean become required, others remain readiness/next wave. |
| 92 | P05-C01 L709 | U.S./en row plus future HOLD; import/export/assisted-input truth; language is not jurisdiction | INCORPORATED_WITH_PROVENANCE | V30-P06-C06; same effect with a multilingual binary cohort. |
| 93 | P05-C02 L710 | U.S. metadata/screenshots plus future metadata workflow separate from binary | INCORPORATED_WITH_PROVENANCE | V30-P06-C05; same outcome. |
| 94 | P05-C03 L711 | Qualified U.S. legal/privacy/retention/export decisions; no fabricated conclusion | INCORPORATED_WITH_PROVENANCE | V30-P06-C06; same outcome. |
| 95 | P05-C04 L712 | Exact-head hosted UI for formatting/reports/offline/accessibility/pseudo/RTL/fallback | INCORPORATED_WITH_PROVENANCE | V30-P06-C03, V30-P06-C04; split UI from output qualification. |
| 96 | P05-C05 L713 | U.S./English linguistic, accessibility, and physical-device foundation acceptance | DEFERRED_UNCHANGED | V30-P06-C02, V30-P06-C03, V30-P06-C07; linguistic/accessibility/hosted acceptance is incorporated, while separate owner physical-device acceptance remains deferred until an authority provides a device and exact evidence contract. |
| 97 | P05-C06 L714 | Locale/storefront monitor; owner availability/rollback; no V23 duplication or automatic promotion | INCORPORATED_WITH_PROVENANCE | V30-P07-C05; monitor/no-credit behavior retained; V24's exact nonoverlap receipt is rejected separately in row 50. |

### Appendix A.1 Deterministic machine projection

At activation, convert the matrix into ordered records with exactly `sourceOrdinal`, `sourceStartLine`, `sourceEndLine`, `section`, `canonicalRequirement`, `disposition`, `rationale`, ordered `v30Targets`, and `noCredit:true`. Normalize the frozen source as UTF-8 without BOM and LF line endings; trim trailing spaces/tabs; collapse internal whitespace only in `canonicalRequirement`; retain raw source text separately. Sort by `sourceOrdinal`, serialize sorted-key compact JSON with one final LF, and SHA-256 those bytes.

The validator rejects a missing/duplicate ordinal, uncovered or multiply disposed normative requirement, invalid target, changed V24 source hash, overlapping anchor without an explicit shared-requirement ID, or any `noCredit` other than true. The projection records V24 and V30 source paths/hashes, record count 97, canonical-byte count, and digest, and is included in the V30 structural projection.
