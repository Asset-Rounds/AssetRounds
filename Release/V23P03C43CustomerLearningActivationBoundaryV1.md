# V23-P03-C43 customer-learning activation boundary V1

Status: `DISABLED_NO_COLLECTION`

Maximum owner disposition recognized by this artifact: `OWNER_ACCEPTED_PENDING_SEPARATE_IMPLEMENTATION_CARD`

This document freezes a vendor-neutral customer-learning and acquisition-measurement policy boundary. It does not activate collection, authorize an implementation, create a customer-work record, or claim Release acceptance.

## Authority binding

- Card: `V23-P03-C43`
- Coordinated authority head: `40fdf45f071dacd8b47dea518e071a2b07510a5f`
- Hydrated context digest: `1bfab05155a2de75d1e088662d0b70619d11bf6840c5c68761f6fe768738a924`
- Path-fence digest: `0c4c80889e7b193b538751905fde435df24d298022d25828acfdc5354aa69649`

## Static contract boundary

The following are dormant, versioned policy declarations or release evidence, not product-event records:

- `CustomerLearningQuestionV1`
- `CustomerLearningMetricDefinitionV1`
- `MeasurementPurposeV1`
- `AcquisitionSourceVocabularyV1`
- `MeasurementSourceKindV1`
- `MeasurementActivationDecisionV1`
- `MeasurementCollectionDispositionV1`
- `ZeroCollectionConformanceReceiptV1`

Contract releases and owner decision records have immutable version-and-digest identity. A later release may supersede them, but must not silently redefine an accepted release. Their static existence does not constitute collection and does not enroll them in customer-work persistence.

`MeasurementActivationDecisionV1` cannot authorize product analytics in this card. Even an owner-accepted decision is bounded to `OWNER_ACCEPTED_PENDING_SEPARATE_IMPLEMENTATION_CARD`. Activation requires a later, separately authorized implementation card and its own exact privacy, consent or lawful-basis, retention, withdrawal, deletion, export, Erase, processor, security, offline, failure, Release-membership, kill-switch, and removal proof.

## Purpose and source separation

The following source kinds remain nonjoinable by default:

- `APP_STORE_CONNECT_AGGREGATE`
- `EXPLICIT_FIELD_RESEARCH`
- `REBUILDABLE_OPERATIONAL_RECEIPT_PROJECTION`
- `FUTURE_CONSENTED_PRODUCT_ANALYTICS`

No source identity, record, stable identifier, cohort, or person identity may be converted or joined across these sources. Operational Party, Site, contact, signoff, actor, asset, session, work, support, commerce, device, or accessibility identity is not a customer-learning, attribution, campaign, marketing, or subscriber identity.

Existing canonical receipts remain operational truth. They are not analytics events and are not automatically read, copied, projected, counted, or reclassified for customer-learning purposes. `REBUILDABLE_OPERATIONAL_RECEIPT_PROJECTION` is only a future source descriptor; any evaluator in this card is TestSupport-only, consumes synthetic receipts, and leaves no Release storage.

`CustomerLearningMetricDefinitionV1` is purpose-separated from the shipping operational `MetricDefinitionV1` authority. No type alias, adapter, import, projection, protocol conformance, shared registry, identity conversion, or common persistence family may bridge them.

## Nonpersistent and absence-proved lifecycle

Every C43 product-runtime lifecycle surface has the following disposition:

| Surface | Disposition | Required boundary |
|---|---|---|
| Event instances and raw event store | `NONPERSISTENT_NO_CANONICAL_WRITE`; `ABSENCE_PROVED` | No product instrumentation, event row, event file, cache, queue, or stable user/device event identity. |
| Operational-receipt learning projection | `NONPERSISTENT_NO_CANONICAL_WRITE`; `ABSENCE_PROVED` | No production receipt reader, scheduler, runtime invoker, projection store, checkpoint, cache, or automatic rebuild. |
| Workspace writer, receipt, journal, and replay | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No command, entity kind, post-image, mutation receipt, journal entry, replay path, or effect-before-receipt recovery is created for C43. |
| SwiftData schema and migration | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No model row, schema-version increment, migration stage, marker, backfill, or compatibility mapping. |
| Backup, restore, import, clone, and fork | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No archive member, backup record, restore materialization, rebind, lineage copy, or historic product record. |
| Delete, retention, and Erase | `NOT_APPLICABLE`; `ABSENCE_PROVED` | There is no collected C43 product data to retain or remove. A future activation must enroll these behaviors before first collection. |
| Search, report, diagnostic, support, and open export | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No customer-learning index, result, dashboard, report field, diagnostic payload, support payload, or exported measurement record. |
| Integration event, replication, and projection | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No event contract, local-change entry, projection checkpoint, sync classification, transport, or downstream consumer. |
| Product UI and routing | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No feature screen, dashboard, settings switch, route, permission prompt, collection copy, or analytics claim. |
| Provider and network lifecycle | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No analytics, attribution, advertising, experimentation, or customer-learning SDK, adapter, endpoint, domain, credential, background uploader, campaign-token handler, or remote activation flag. |

There is no advertising identifier use, fingerprint, hashed-email identity, cross-app or cross-device stable person identifier, hidden experiment assignment, customer-content dimension, or cross-source identity join. Missing, delayed, privacy-thresholded, or suppressed data is never converted to zero and never described as complete or causal.

App Store Connect acquisition and campaign reports remain owner-operated external aggregate evidence. The app does not receive campaign tokens or write attribution. Explicit field research remains an owner-run activity outside canonical customer work and does not create an in-app research participant or analytics record.

## Legitimate non-C43 system behavior

The `DISABLED_NO_COLLECTION` claim is scoped to C43 customer-learning, product analytics, acquisition attribution, advertising, tracking, and experimentation. It does not relabel unrelated accepted platform behavior:

- Local MetricKit support diagnostics remain bounded, noncustomer operational diagnostics. They are not C43 events or metric inputs, are not silently uploaded, and may leave the app only through an explicit, reviewed support-export action.
- StoreKit commerce remains the separate Apple system commerce path. Purchase and entitlement processing is not C43 acquisition attribution or product analytics, and StoreKit identifiers or payloads may not be copied into C43 definitions, diagnostics, backups, or exports.
- Explicit user-directed backup, report, diagnostic, feedback, and system share handoffs remain classified by their actual accepted purposes. They do not establish C43 collection, transmission, attribution, or tracking authority.

These carve-outs do not permit their data, identifiers, receipts, counters, or results to be reused for customer-learning.

## Evidence status

### Available from static repository inspection

The following can be evaluated without executing a Release candidate:

- Dormant contract shape, closed disposition, purpose separation, and nonjoinable source vocabulary.
- Absence of C43 SwiftData rows, schema/migration enrollment, writer commands, journal kinds, backup members, deletion routes, UI routes, provider adapters, and product-event storage in source.
- Dependency and project declarations for prohibited analytics, attribution, advertising, and experimentation packages.
- Source references to prohibited endpoints, domains, campaign-token handlers, identifiers, uploaders, and remote activation paths.
- Separation from operational receipts, local MetricKit support diagnostics, StoreKit commerce, and operational `MetricDefinitionV1`.

This document records the policy and the scope of those static checks. It does not itself certify their result for a future exact Release archive.

### Pending and expressly unclaimed here

The following require the exact Release candidate and are `PENDING_EXACT_CANDIDATE_EVIDENCE`:

- Compiled archive, linked binary, embedded framework, resource, privacy-manifest, string, symbol, dependency, endpoint, domain, entitlement, and background-task scans.
- Controlled runtime network observation proving zero C43 collection and zero C43 transmission.
- Runtime observation proving no production receipt reader, scheduler, invoker, persisted projection, campaign-token ingestion, hidden experiment assignment, or background uploader.
- Reconciliation of every actual Apple service and explicit user-directed export/share/support flow with the exact privacy policy and App Privacy answers.
- Exact-head evidence artifacts and the final `ZeroCollectionConformanceReceiptV1`.

No archive, runtime-network, App Privacy, or Release-acceptance result is claimed by this static artifact. Failure of any pending check keeps product analytics and attribution at `DISABLED_NO_COLLECTION`, fails the candidate, and requires removal of the discovered path and any data before new exact-candidate proof.

## Activation hard stop

A bundled policy edit, remote flag, vendor installation, owner preference, consent copy, or this document cannot activate collection. Stop on any proposed collection, transmission, processor, ad-network, tracking, identity join, provider choice, public disclosure change, or inability to prove the disabled state. The conservative fallback is always no collection while unrelated accepted product behavior continues.
