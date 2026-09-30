# V23-P03-C44 communication-consent activation boundary V1

Status: `DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION`

This document freezes the customer-communication, research-participation, and marketing-contact boundary for `V23-P03-C44`. It is a static Release policy artifact. It does not enroll a person, collect or transmit an address, authorize a provider, activate delivery, create customer-work truth, or claim final Release acceptance.

## Static contract boundary

The following are dormant, provider-neutral contract schemas or Release evidence only:

- `MarketingContactV1`
- `CommunicationConsentReceiptV1`
- `CommunicationPreferenceV1`
- `SuppressionRecordV1`
- `ContactSourceV1`
- `ConsentDisclosureReleaseV1`
- `EmailServiceProviderAdapterV1`
- `ZeroSubscriberTransmissionConformanceReceiptV1`

There are no live instances of these types in the Release product. Contract and disclosure releases have immutable version-and-digest identity and may be superseded, never silently edited. `EmailServiceProviderAdapterV1` is an unbound future application port; this card supplies no Release adapter, fake-backed production behavior, network client, credential source, provider state, or delivery authority.

## Exact purpose separation

The closed communication purposes are:

- `NEWSLETTER`
- `PRODUCT_UPDATE`
- `RESEARCH_INVITATION`
- `TRANSACTIONAL_OR_SUPPORT`

`MarketingContactV1` may arise only from independent, affirmative enrollment for `NEWSLETTER`, `PRODUCT_UPDATE`, or `RESEARCH_INVITATION`. Consent for one purpose, channel, or topic never authorizes another.

`TRANSACTIONAL_OR_SUPPORT` is an exclusion and routing classification on an existing operational channel. It never creates a marketing contact, communication-consent receipt, marketing preference, suppression record, subscriber identity, or provider audience.

None of the following implies enrollment or consent:

- an operational Party, Site, contact, role, actor, signoff, or local address;
- feedback or support contact, including an explicitly composed support message;
- purchase, entitlement, app use, or local operational activity;
- report sharing, backup or diagnostic export, or another user-directed handoff;
- an imported or locally stored address;
- participation in one research conversation;
- silence, a prechecked state, an inferred role, or unrelated acceptance.

Operational Party and Site data remains local customer-work truth. It may not be copied, projected, converted, automatically compared, or hashed into a subscriber record.

There is no type alias, adapter, projection, protocol conformance, shared registry, shared identifier, import path, or identity conversion between C44 and either:

- C43 customer-learning, acquisition-measurement, or analytics contracts; or
- a current or future operational `ServiceContactPointV1`.

An operational contact point stays operational. A customer-learning identity stays purpose-separated. Neither becomes a marketing or research subscriber.

## Consent and contact truth

The dormant future consent schema preserves the exact entered or deliverable address and channel. It also binds a separately versioned normalization/comparison-policy release, purpose and topics, consenting actor, source and source release, disclosure release and digest, presented locale, affirmative method, occurred and recorded times, verification status and time, jurisdiction and documented lawful-basis disposition, expiry when applicable, predecessor, and append-only withdrawal history.

No implementation may strip plus tags or assume local-part case or Unicode equivalence without an explicit provider-compatible policy. Ambiguous collisions are `REVIEW_REQUIRED`. A stale disclosure, unknown authority, inferred consent, or consent recorded after withdrawal is not silently accepted.

This card defines no live activation or expiry transition. The presence of an optional expiry field in the static schema does not authorize automatic expiry, renewal, reenrollment, send, or deletion behavior.

## Preference, withdrawal, and suppression truth

A later preference center must make unsubscribe and withdrawal easy for each nontransactional purpose. Withdrawal for one purpose cannot be treated as consent or withdrawal for another, and withdrawal history is append-only.

`SuppressionRecordV1` is a future minimum do-not-contact record, not a marketing audience. Its bounded contract contains only purpose and channel, a reviewed service-side keyed pseudonymous lookup token, source, withdrawal reason and time, normalization-policy release, and an explicit retention decision. Its purpose is to prevent deletion, reimport, list replacement, provider migration, or retry from silently reenrolling a person.

A plain address hash is forbidden. Email, hashed email, and a keyed suppression token remain Contact Info and personal data. They are never anonymous, irreversible, nonpersonal, a customer identifier, or an advertising audience. Suppression truth cannot be repurposed for targeting, measurement, retargeting, lookalikes, or list enrichment.

Sharing any address list with an ad network is a separate tracking decision. It cannot inherit newsletter, product-update, research, support, purchase, app-use, or local-contact authority.

## Zero live product lifecycle

| Surface | Current disposition | Boundary |
|---|---|---|
| Contact, consent, preference, suppression, and provider instances | `ABSENT` | No live instance, subscriber repository, provider state, list, cache, queue, or file. |
| SwiftData schema and migration | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No row, schema increment, migration stage, marker, backfill, or compatibility mapping. |
| Workspace writer, journal, replay, and receipt recovery | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No command, mutation receipt, event, post-image, journal entry, replay path, or fabricated workspace receipt. |
| Backup, restore, import, clone, fork, and open export | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No C44 archive member, restore materialization, identity rebind, lineage copy, list import/export, or subscriber export. |
| Delete, retention, and Erase | `NOT_APPLICABLE`; `ABSENCE_PROVED` | There is no live C44 data to remove or retain. Future suppression survival and personal-data deletion boundaries require later owner authority. |
| Search, report, diagnostics, support export, and projection | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No address, consent, preference, token, subscriber, audience, or provider fact enters these surfaces. |
| Signup, preference, marketing, or research UI | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No view, setting, route, URL handler, permission, signup, preference center, campaign surface, or marketing claim. |
| Provider, delivery, and network | `NOT_APPLICABLE`; `ABSENCE_PROVED` | No provider implementation or SDK, backend, endpoint, domain, credential, send queue, background task, webhook, automatic upload, audience export, or transmission. |

No device-local preference, operational workspace row, system handoff result, or diagnostic counter may be relabeled as C44 consent or subscriber truth.

## Legitimate non-C44 behavior

The disabled subscriber claim is scoped to C44 collection, enrollment, marketing or research delivery, provider transmission, and audience use. It does not mislabel unrelated accepted platform behavior:

- MessageUI support feedback is an explicit, editable, user-directed system handoff. Attachment choice is not marketing or research consent, and composer acceptance is not subscriber enrollment or proof of delivery.
- StoreKit commerce is separate Apple system commerce behavior. Purchase or entitlement state is not consent, a marketing source, or provider audience authority.
- MetricKit supplies bounded local noncustomer operational diagnostics. Its platform subscriber terminology does not mean a communication subscriber, and its results may not feed C44.
- Local notification and reminder behavior is local operational scheduling. It is not a mailing list, remote send queue, marketing message, research invitation, or consent signal.
- Explicit user-directed report, backup, diagnostic, feedback, and system-share handoffs remain classified by their own accepted purposes and do not activate C44.

These behaviors provide no bridge for addresses, identifiers, receipts, counters, or outcomes into C44.

## Later activation and lifecycle gate

Only a separate owner-authorized implementation card may activate collection or transmission. It must name controlled backend or provider-hosted signup ownership and close, before the first subscriber is accepted:

- disclosure, affirmative enrollment, verification, jurisdiction, and lawful-basis validation;
- easy per-purpose preference change, unsubscribe, and withdrawal;
- atomic enrollment and idempotent provider reconciliation;
- withdrawal before and after send, provider outage and retry, duplicates, webhooks, bounce, complaint, abuse, and deliverability behavior;
- retention, deletion, minimum suppression survival, export, and Erase reconciliation;
- processor and destination review, security and threat-model changes, credential rotation, audit, rollback, provider migration, and provider exit;
- privacy policy and App Privacy changes, exact Release membership, and complete removal proof.

Provider or API secrets never enter the iOS app. Except for the exact independently consented address and channel required for future delivery, a provider may receive no operational Party or Site record, physical or service address, relationship, Site, asset, note, photo, evidence, report, GPS, barcode, package, work, inspection, repair, actor, qualification, or local-contact-graph data.

This static boundary deliberately does not invent clone/fork handling or expiry transitions. Those behaviors remain unresolved until the later owner-authorized card names their actual storage, service authority, privacy basis, and reconciliation semantics.

## Evidence status

### Static evidence available now

Repository inspection can establish the dormant contract shape and disabled disposition, purpose nontransitivity, Party/Site/C43/`ServiceContactPointV1` separation, absence of live C44 storage and runtime owners in source, and absence of declared provider dependencies, credentials, endpoints, send services, signup routes, and subscriber settings in source-controlled declarations.

Static fixtures may validate consent/nonconsent truth tables, address-comparison ambiguity, disclosure and locale pinning, withdrawal history shape, keyed-token personal-data truth, suppression against reenrollment in a future-contract model, and an unbound provider port. Fixtures remain TestSupport-only and create no Release storage or transmission.

This document records the required boundary. It does not itself certify an exact native Release archive or runtime result.

### Pending and unclaimed

The following require the exact native Release candidate and remain `PENDING_EXACT_CANDIDATE_EVIDENCE`:

- compiled archive and linked-binary inspection;
- embedded framework, package, dependency, resource, privacy-manifest, and symbol inspection;
- public and localized string, route, settings, URL-handler, and permission inspection;
- background-task, credential, entitlement, endpoint, domain, and provider scan;
- controlled runtime-network observation proving zero C44 subscriber collection and zero C44 transmission;
- runtime observation proving no signup, repository, provider adapter, send queue, automatic enrollment, audience export, or hidden delivery path;
- exact privacy-policy and App Privacy reconciliation for actual Apple services and explicit user-directed handoffs;
- exact-head evidence artifacts and the final `ZeroSubscriberTransmissionConformanceReceiptV1`.

No native-archive, linked-binary, runtime-network, public-copy, App Privacy, or Release-acceptance result is claimed here. This artifact does not mint `ZeroSubscriberTransmissionConformanceReceiptV1`.

If any live enrollment, provider state, transmission, credential, signup, send, or audience path is discovered, the candidate fails. The path and any data must be removed or reconciled under actual authority before new exact-candidate proof.

## Hard stop

A static contract, bundled policy edit, remote flag, provider installation, operational contact, support interaction, purchase, app use, imported address, or this document cannot activate C44. Stop on inferred consent, ambiguous disclosure or lawful basis, provider/backend/credential/send scope, customer-work transmission, advertising-audience conflation, or inability to prove `DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION`. The conservative fallback is no subscriber collection or transmission while unrelated accepted behavior continues.
