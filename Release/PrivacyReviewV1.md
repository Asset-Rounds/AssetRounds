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
