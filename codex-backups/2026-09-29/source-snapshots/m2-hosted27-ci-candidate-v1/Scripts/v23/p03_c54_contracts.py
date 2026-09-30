#!/usr/bin/env python3
"""Fail-closed C54 encrypted portable-envelope tooling."""
from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
import sys
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

CARD = "V23-P03-C54"
ORDINAL = 85
BASE_HEAD = "efdd77f67e8184cc8d32673f0bf4ba06385d5965"
BASE_TREE = "38547059ec0f7931903014bad7234567836d1b94"
COORDINATION_HEAD = "1001ebfba07212c659c42caae88afa5dbc0be63c"
COORDINATION_TREE = "9f131dd4bb6cf3bca780ab4b642f3c2fd066070a"
CAS_SEQUENCE = 360
CONTEXT_DIGEST = "6ff43b0c6ea104ca91a63e9e14312ad8fc12ecabc542b41f00fce33286c99d05"
FENCE_DIGEST = "be5dc8f42a5b026596149b405814a3e6c96f1a500ce2750339a439c18364fcec"
PREREQUISITE_DIGEST = "a032ac617bf796226769f1bfb4c1c98ce77b7e71a3b6a851d907bdec6b68e1cb"
TRANSITION_DIGEST = "daee87982c8b8185c8e17bcf47efdfd020b747c63ccb1799eed931686f01d7b3"
CORRECTION_RECEIPT_DIGEST = "bae9195a6ca691b81f00c091ea78c1630143595c7272f6822474f5c3bb9da1de"
CORRECTION_TRANSITION_DIGEST = "aace65272552486b3efacb151926920f11c8d865bc048ce57f785037b70aab39"
LEDGER_DIGEST = "0a6f663c832ddedabd22b64b4a4a39f397458e6d587c89fd3f1e14625e08b923"
PROJECTION_DIGEST = "2cf7b0a1c83cc1cd38f22eb525ac27c334d6dd8176aa6e301bc78724ca2460f3"
PRIOR_C08_FENCE = "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5"
HYDRATION = Path(r"C:\AssetRounds-v23-coordination\contexts\V23-P03-C54-attempt-1\BootstrapPathFenceV1.json")

SCHEMA = "Scripts/v23/encrypted-portable-envelope.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P03C54EncryptedPortableEnvelopeContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P03C54EncryptedPortableEnvelopeEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P03C54BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P03-C54-tooling-manifest.json"
SCRIPTS = (
    "Scripts/v23/p03_c54_contracts.py",
    "Scripts/v23/generate_p03_c54_contracts.py",
    "Scripts/v23/verify_p03_c54_contracts.py",
)
IMPLEMENTATION = (
    "FieldEvidenceApp/Domain/FileExchange/EncryptedPortableEnvelopeContractsV1.swift",
    "FieldEvidenceApp/Application/FileExchange/EncryptedPortableEnvelopeCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/FileExchange/EncryptedPortableEnvelopeCryptoV1.swift",
    "FieldEvidenceApp/Infrastructure/FileExchange/EncryptedPortableEnvelopeLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_62EncryptedPortableEnvelopeTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/EncryptedEnvelope/V22P03C54EncryptedPortableEnvelopeCorpusV1.json",
)
GENERATED = (CONTRACT, EVIDENCE, BRAND, MANIFEST)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
FLAGS = {
    key: False
    for key in (
        "activation",
        "native",
        "hosted",
        "adoption",
        "acceptance",
        "release",
        "nativeAcceptance",
        "hostedAcceptance",
        "physicalEvidence",
        "phase10PollingDuringParallelExecution",
    )
}

SUPPORT_PATHS = (
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/MetricKitDiagnosticsAdapter.swift",
    "FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift",
    "FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/DeviceLifecycleCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/S2PersistenceLedgerTests.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/SystemHealthContractsV1.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Diagnostics/V21P02C08SystemHealthOperationalDiagnosticsCorpusV1.json",
    "FieldEvidenceApp/Info.plist",
)


def pretty(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()


def _text(root: Path, path: str) -> str:
    candidate = root / path
    if not candidate.is_file():
        raise ValueError("C54 source absent:" + path)
    return candidate.read_text(encoding="utf-8")


def _tokens(text: str, tokens: tuple[str, ...], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(label + " missing:" + ",".join(missing))


def _hydration() -> dict[str, Any]:
    if not HYDRATION.is_file():
        raise ValueError("C54 hydration absent")
    value = json.loads(HYDRATION.read_text(encoding="utf-8"))
    if value.get("cardID") != CARD or value.get("fenceDigest") != FENCE_DIGEST:
        raise ValueError("C54 hydration authority differs")
    return value


_H = _hydration()
EXISTING = tuple(_H["existingPaths"])
NEW = tuple(_H["newPaths"])
FENCE = EXISTING + NEW


def _declaration(text: str, name: str) -> str:
    match = re.search(r"\b(?:struct|enum|actor|final\s+class|class)\s+" + re.escape(name) + r"\b", text)
    if not match:
        raise ValueError("C54 declaration absent:" + name)
    tail = text[match.start():]
    next_match = re.search(r"\n(?:struct|enum|actor|final\s+class|class)\s+[A-Za-z_]", tail[1:])
    return tail if not next_match else tail[: next_match.start() + 1]


def _strict_decoder(text: str, name: str) -> None:
    body = _declaration(text, name)
    if "init(from decoder" not in body or "validate" not in body:
        raise ValueError("C54 strict validating decoder absent:" + name)


def _ordered(text: str, tokens: tuple[str, ...], label: str) -> None:
    positions = [text.find(token) for token in tokens]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        raise ValueError(label + " ordering differs:" + ",".join(tokens))


def _function_region(text: str, name: str, next_name: str | None = None) -> str:
    match = re.search(r"\bfunc\s+" + re.escape(name) + r"\b", text)
    if not match:
        raise ValueError("C54 function absent:" + name)
    if next_name is None:
        return text[match.start():]
    next_match = re.search(
        r"\bfunc\s+" + re.escape(next_name) + r"\b",
        text[match.end():],
    )
    if not next_match:
        raise ValueError("C54 function absent:" + next_name)
    return text[match.start(): match.end() + next_match.start()]


def _release_projection(text: str) -> str:
    """Remove DEBUG-only regions before checking canonical production APIs."""
    output: list[str] = []
    debug_depth = 0
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#if DEBUG"):
            debug_depth += 1
            continue
        if stripped.startswith("#if") and debug_depth:
            debug_depth += 1
            continue
        if stripped.startswith("#endif") and debug_depth:
            debug_depth -= 1
            continue
        if stripped.startswith("#else") and debug_depth == 1:
            debug_depth = 0
            continue
        if debug_depth == 0:
            output.append(line)
    return "\n".join(output)


def _source_behavior(root: Path) -> None:
    contracts, coordinator, crypto, lifecycle, tests, fixture = (
        _text(root, path) for path in IMPLEMENTATION
    )
    _tokens(
        contracts,
        (
            "EncryptedPortableEnvelopeProtocolReleaseV1",
            "EncryptedEnvelopeKDFProfileV1",
            "EncryptedEnvelopeAEADProfileV1",
            "EncryptedEnvelopeSealReceiptV1",
            "EncryptedEnvelopeOpenReceiptV1",
            "PassphrasePolicyV1",
            "EphemeralSecretHandlingDispositionV1",
            "EncryptionExportComplianceDispositionV1",
            "ReviewExchangeProtectionV1",
            "WORKSPACE_BACKUP",
            "REVIEW_REQUEST",
            "REVIEW_RESPONSE",
            "600_000",
            "1_048_576",
            "UInt32.max",
            "wrongPassphraseOrDamagedEnvelope",
            "EncryptedEnvelopeBoundedSeekableSourceV1",
            "EncryptedEnvelopeProtectedScratchSinkV1",
            "innerProtocolVersion",
            "EncryptedPortableEnvelopeExternalFailureV1",
            "neutralShareTitle",
            "maximumOperationalScratchByteCount: UInt64 = 4_294_967_296",
            "maximumEnvelopeByteCount: maximumOperationalScratchByteCount",
            "clearWithExplicitWarning",
            "passphraseEncryptedV1",
        ),
        "C54 released domain contracts",
    )
    for name in ("EncryptedEnvelopeSealReceiptV1", "EncryptedEnvelopeOpenReceiptV1"):
        _strict_decoder(contracts, name)
        body = _declaration(contracts, name)
        for forbidden in (
            r"\blet\s+passphrase\s*:",
            r"\blet\s+derivedKey\s*:",
            r"\blet\s+plaintextSHA256\s*:",
            r"\blet\s+scratchPath\s*:",
        ):
            if re.search(forbidden, body):
                raise ValueError("C54 secret-bearing receipt:" + name + ":" + forbidden)
        _tokens(
            body,
            ("innerProtocolVersion", "canonicalFrameCount", "cleanupDisposition", "init(finalizing facts:"),
            "C54 canonical receipt release/frame/cleanup truth " + name,
        )

    outcome_body = _declaration(contracts, "EncryptedPortableEnvelopeExternalFailureV1")
    for outcome in ("cancelled", "resourceLimit", "unsupportedRelease", "wrongPassphraseOrDamagedEnvelope"):
        if not re.search(r"\bcase\s+" + outcome + r"\b", outcome_body):
            raise ValueError("C54 outward outcome missing:" + outcome)
    if len(re.findall(r"\bcase\s+[A-Za-z_]", outcome_body)) != 4:
        raise ValueError("C54 outward failure set is not closed at four plus success")

    filename_body = _declaration(contracts, "EncryptedPortableEnvelopeFilenameV1")
    _tokens(
        filename_body,
        ("genericKind", "publicEnvelopeID", "neutralFileName", "neutralShareTitle"),
        "C54 neutral filename/share title",
    )
    for function_name in ("neutralFileName", "neutralShareTitle"):
        if not re.search(
            function_name
            + r"\s*\(\s*innerKind\s*:.*?publicEnvelopeID\s*:",
            filename_body,
            re.S,
        ):
            raise ValueError("C54 dynamic kind/public-ID naming absent:" + function_name)
    _tokens(
        contracts,
        (
            "EncryptedEnvelopeErrorCategoryV1",
            "externalFailure(for error:",
            "-> EncryptedPortableEnvelopeExternalFailureV1",
        ),
        "C54 internal-to-closed-external failure mapping",
    )

    _tokens(
        crypto,
        (
            "CryptoKit",
            "CommonCrypto",
            "Security",
            "CCKeyDerivationPBKDF",
            "kCCPRFHmacAlgSHA256",
            "AES.GCM",
            "SecRandomCopyBytes",
            "bigEndian",
            "structuralPreflight",
            "deriveKey",
            "authenticate",
            "iterations == EncryptedEnvelopeKDFProfileV1.released.iterationCount",
            "EncryptedEnvelopeBoundedSeekableSourceV1",
            "EncryptedEnvelopeProtectedScratchSinkV1",
            "structuralPreflight(source:",
            "sealStreaming(",
            "openStreaming(",
        ),
        "C54 system cryptography and bounded preflight",
    )
    _ordered(crypto, ("structuralPreflight", "deriveKey", "authenticate"), "C54 open pipeline")
    production_crypto = _release_projection(crypto)
    canonical_release = "\n".join((contracts, coordinator, production_crypto, lifecycle))
    for forbidden in (
        r"EncryptedPortableEnvelope(?:SealResult|OpenResult|CryptographicSeal|CryptographicOpen|ShareReady|AuthenticatedInner)V1",
        r"func\s+seal\s*\(\s*plaintext\s*:\s*Data",
        r"func\s+open\s*\(\s*envelope\s*:\s*Data",
        r"\blet\s+(?:plaintext|envelope|responseBytes)\s*:\s*Data\b",
    ):
        if re.search(forbidden, canonical_release):
            raise ValueError("C54 obsolete whole-Data canonical surface:" + forbidden)
    seal_region = _function_region(production_crypto, "sealStreaming", "openStreaming")
    open_region = _function_region(production_crypto, "openStreaming", "preflightSeal")
    if not re.search(
        r"validateSourceInner\(.*?checkedCancellation\(cancellation\).*?deriveKey",
        seal_region,
        re.S,
    ):
        raise ValueError("C54 source inner/version/cancellation does not precede seal KDF")
    _tokens(
        seal_region,
        ("innerProtocolVersion", "validateSourceInner", "validateReopenedInner"),
        "C54 seal inner protocol validation",
    )
    _tokens(
        contracts,
        ("validateReleased(for: innerKind)", "canonicalHeaderBytes == expectedHeaderBytes"),
        "C54 released inner version and canonical header binding",
    )
    _ordered(
        open_region,
        (
            "structuralPreflight(",
            "decodePublicHeader",
            "EncryptedPortableEnvelopeAuthenticatedManifestV1",
            "checkedCancellation(cancellation)",
            "deriveKey",
        ),
        "C54 open metadata/version/cancellation before KDF",
    )
    for frame_name, next_name in (("sealFrame", "openFrame"), ("openFrame", "sealStreaming")):
        frame_region = _function_region(production_crypto, frame_name, next_name)
        _tokens(
            frame_region,
            ("encodePublicHeader(publicHeader)", "frameHeaderData", "authenticatedData"),
            "C54 canonical-header per-frame AAD " + frame_name,
        )
    _tokens(
        contracts,
        (
            "canonicalHeaderSHA256",
            "everyFrameAuthenticatesCanonicalHeader",
            "facts.authenticatedManifest.publicHeader == facts.publicHeader",
            "facts.authenticatedManifest.canonicalHeaderSHA256 == facts.canonicalHeaderSHA256",
        ),
        "C54 manifest and receipt header digest binding",
    )
    if not re.search(
        r"func\s+openStreaming\b.*?structuralPreflight\(.*?source:.*?readExactly\(.*?atOffset:\s*0.*?deriveKey.*?openFrame",
        production_crypto,
        re.S,
    ):
        raise ValueError("C54 streaming open lacks bounded first pass before KDF/authenticated second pass")
    if re.search(r"func\s+openStreaming\b[^\{]*confirmation\s*:", production_crypto, re.S):
        raise ValueError("C54 open reader incorrectly requires passphrase confirmation")
    if not re.search(r"min\(frameLimit,\s*remaining\).*?readExactly", production_crypto, re.S):
        raise ValueError("C54 streaming seal does not bound source reads to the released frame limit")
    if not re.search(r"openFrame.*?appendStreamingBytes", production_crypto, re.S):
        raise ValueError("C54 streaming open does not authenticate each bounded frame before sink append")
    if re.search(r"\b(?:URLSession|WebSocket|Network)\b", crypto):
        raise ValueError("C54 crypto introduces networking")

    _tokens(
        coordinator,
        (
            "EncryptedPortableEnvelopeCoordinatorV1",
            "structuralPreflight",
            "sealStreaming",
            "openStreaming",
            "publishAndCleanupSeal",
            "cleanupOpen",
            "EncryptedPortableEnvelopeFinalizedSealV1",
            "finalized.receipt",
            "EncryptedEnvelopeOpenReceiptV1(finalizing:",
            "cachedSeal",
            "cachedOpen",
            "effect:.noEffect",
            "protectReviewResponse",
            "readLegacyClear",
            "topologyAndResourcePreflightBeforeKDFAllocationPreviewOrWrite=true",
            "EncryptedEnvelopeBoundedSeekableSourceV1",
            "EncryptedEnvelopeProtectedScratchSinkV1",
            "legacyClearReader",
            "EncryptedPortableEnvelopeAuthenticatedInnerConsumerV1",
            "EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1",
            "stageAuthenticatedInner",
            "throwing commit leaves no canonical mutation",
            "EncryptedPortableEnvelopePublicationTransactionV1",
            "stageEncryptedEnvelope",
            "shareTitle:String,cancellation:any EncryptedEnvelopeCancellationCheckingV1",
            "leave no externally visible artifact",
            "EncryptedPortableEnvelopeRequestIdentityV1",
            "sourceSHA256",
            "sourceByteCount",
            "passphraseOwnerID",
            "limits:EncryptedPortableEnvelopeResourceLimitsV1",
            "memoryOwnerID",
            "busy:Set<EncryptedPortableEnvelopeOperationIdentityV1>",
            "CheckedContinuation<Void,Never>",
        ),
        "C54 validation-before-publication coordinator",
    )
    if not re.search(r"func\s+sealLocked\b.*?sealStreaming.*?publishAndCleanupSeal.*?finalized\.receipt.*?terminal\[", coordinator, re.S):
        raise ValueError("C54 coordinator seal does not publish/cleanup before final receipt and terminal cache")
    if not re.search(
        r"func\s+openLocked\b.*?structuralPreflight.*?openStreaming.*?stageAuthenticatedInner"
        r".*?cleanupOpen.*?OpenReceiptV1\(finalizing:.*?\.commit\(\).*?terminal\[",
        coordinator,
        re.S,
    ):
        raise ValueError("C54 coordinator open does not stage/authenticate/cleanup/receipt/commit in order")
    if not re.search(
        r"func\s+open\b.*?cleanupOpen.*?EncryptedEnvelopeOpenReceiptV1",
        coordinator,
        re.S,
    ):
        raise ValueError("C54 open receipt cleanup truth is minted before lifecycle cleanup")
    if not re.search(r"cachedSeal.*?value\.identity\s*==\s*identity.*?throw", coordinator, re.S):
        raise ValueError("C54 seal retry lacks exact-same identity reuse and divergent rejection")
    if not re.search(r"executionMode\s*==\s*\.retry.*?effect:\s*\.noEffect", coordinator, re.S):
        raise ValueError("C54 relaunch retry lacks explicit no-effect disposition")
    for operation_name, worker_name in (("seal", "sealLocked"), ("open", "openLocked")):
        if not re.search(
            r"func\s+" + operation_name + r"\b.*?await\s+acquire\(request\.operation\).*?"
            + worker_name,
            coordinator,
            re.S,
        ):
            raise ValueError("C54 operation coalescing absent:" + operation_name)
    identity_body = _declaration(coordinator, "EncryptedPortableEnvelopeRequestIdentityV1")
    _tokens(
        identity_body,
        ("sourceSHA256", "sourceByteCount", "innerKind", "innerProtocolVersion", "reviewProtectionMode", "passphraseOwnerID", "limits", "context"),
        "C54 terminal source identity",
    )
    request_identity = _function_region(coordinator, "requestIdentity", "readExactly")
    _tokens(
        request_identity,
        ("SHA256", "1_048_576", "checkCancellation", "readExactly", "sourceSHA256", "passphrase.memoryOwnerID", "limits:limits"),
        "C54 bounded cancellation-aware source identity",
    )
    _tokens(
        coordinator,
        ("transaction.rollback()", "transaction.commit()"),
        "C54 authenticated-inner two-phase handoff",
    )

    _tokens(
        lifecycle,
        (
            "EncryptedPortableEnvelopeLifecycleAdapterV1",
            "recoverEncryptedPortableEnvelopeScratch",
            "revokeEncryptedPortableEnvelopeSecrets",
            "eraseEncryptedPortableEnvelopeScratch",
            "startupRecoveryDeletesInterruptedAttempts=true",
            "cancelBackgroundAppLockProtectedDataAndPressureClearSecrets=true",
            "EncryptedPortableEnvelopeProtectedFileScratchV1",
            "StoragePreflightService",
            "OwnedStorageLedgerV1",
            "topology.envelopeByteCount<=ScratchDataPurposeV1.source.maximumByteCount",
            "EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared.register",
            "EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared.unregister",
            "cleanupFailedOperations",
            "stageEncryptedEnvelope",
            "commitPublication",
            "rollbackPublication",
            "isIndependentFromProtectedScratch",
            "facts.encryptedFileSHA256",
            "EncryptedEnvelopeSealReceiptV1(finalizing:",
            "finalizing",
            "resources.cancellation.checkCancellation()",
            "completeOpenFinalization",
            "abandonOpenFinalization",
            "completeFinalizationAuthority",
            "if let cancellation=finalizing[operation]",
            "attachAcquiredLease",
            "isCancellationRequested",
            "revocationDepth",
            "eraseInProgress",
            "guard revocationDepth == 0,!eraseInProgress",
            "guard await EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared.register",
            "persistentLifecycleBlocksLateClaimsUntilResume=true",
            "actorRevocationGateBlocksReentrantClaims=true",
            "revocationGeneration",
            "admittedGeneration",
            "revocationGeneration == admittedGeneration",
            "revocationGenerationExhausted",
            "revocationGenerationFencesRegistrationOvertake=true",
        ),
        "C54 lifecycle and protected scratch",
    )
    publish_region = _function_region(lifecycle, "publishAndCleanupSeal", "cleanupOpen")
    if not re.search(
        r"stageEncryptedEnvelope.*?stagedSource.*?isIndependentFromProtectedScratch.*?"
        r"published\.encryptedEnvelopeByteCount\(\).*?facts\.encryptedFileSHA256.*?"
        r"finish\(operation:.*?published\.encryptedEnvelopeByteCount\(\).*?"
        r"facts\.encryptedFileSHA256.*?EncryptedEnvelopeSealReceiptV1\(finalizing:.*?"
        r"commitPublication.*?published\.encryptedEnvelopeByteCount\(\).*?"
        r"rollbackPublication",
        publish_region,
        re.S,
    ):
        raise ValueError("C54 independent publication pre/post verification and rollback differs")
    finish_region = _function_region(lifecycle, "finish", "ensureDeviceLifecycleRegistration")
    _tokens(
        finish_region,
        (
            "for lease in attempt.leases",
            "releaseScratchLease",
            "cleanupFailed=true",
            "releaseEncryptedPortableEnvelope",
            "attempt.secret.clear()",
            "removeDeviceLifecycleRegistrationIfIdle",
        ),
        "C54 best-effort complete lifecycle cleanup",
    )
    revocation_region = _function_region(
        lifecycle,
        "revokeEncryptedPortableEnvelopeSecrets",
        "eraseEncryptedPortableEnvelopeScratch",
    )
    _tokens(
        revocation_region,
        (
            "revocationDepth += 1",
            "for attempt in attempts",
            "active.removeAll",
            "for lease in attempt.leases",
            "releaseScratchLease",
            "revocationDepth -= 1",
        ),
        "C54 best-effort revocation cleanup",
    )
    executable = "\n".join(
        line
        for line in "\n".join((contracts, coordinator, crypto, lifecycle)).splitlines()
        if not line.lstrip().startswith("//")
    )
    for forbidden in (
        r"\b(?:UserDefaults|Keychain|SwiftData)\b[^\n]*(?:passphrase|derivedKey)",
        r"\b(?:telemetry|analytics|upload|delivery|nonrepudiation|tamperproof)\b[^\n]*(?:=|:)\s*true\b",
        r"serviceRequest[^\n]*(?:permitted|supported|accepted)\s*=\s*true",
    ):
        if re.search(forbidden, executable, re.I):
            raise ValueError("C54 forbidden behavior:" + forbidden)

    exact_methods = (
        "testV23P03C54G01PublishedCryptoVectorsAndThreeKindsPreserveExactInnerBytes",
        "testV23P03C54A01NFCBoundsEmptyMaximumAndMultiframeCompatibilityRemainClosed",
        "testV23P03C54H01HostileTopologyResourcesProfilesKindsAndDamageFailClosed",
        "testV23P03C54I01InterruptionRandomAndStorageFailuresLeaveNoPartialSuccessOrSecrets",
        "testV23P03C54R01CrashCleanupRetryReopenReceiptsAndExportDispositionRemainStrict",
    )
    _tokens(tests, exact_methods, "C54 meaningful G/A/H/I/R methods")
    discovered_methods = tuple(
        re.findall(r"\bfunc\s+(testV23P03C54[GAHIR]\d{2}[A-Za-z0-9_]*)\s*\(", tests)
    )
    if discovered_methods != exact_methods:
        raise ValueError("C54 evidence selector set/order differs")
    for prefix in ("G01", "A01", "H01", "I01", "R01"):
        if tests.count("testV23P03C54" + prefix) != 1:
            raise ValueError("C54 evidence method cardinality:" + prefix)
    _tokens(
        tests,
        (
            "1_048_576",
            "structuralPreflight",
            "derivePBKDF2Key",
            "sealAES256GCM",
            "openAES256GCM",
            "wrongPassphraseOrDamagedEnvelope",
            "validateInner:",
            "revokeEncryptedPortableEnvelopeSecrets",
            "recoverEncryptedPortableEnvelopeScratch",
            "legacyClearReadersRemainAvailable",
            "clearWithExplicitWarning",
            "JSONEncoder",
            "JSONDecoder",
            "EncryptedPortableEnvelopeCoordinatorV1(",
            "protectReviewResponse(",
            "maximumReadByteCount",
            "readLegacyClear(",
            "DeviceLifecycleCoordinatorV1",
            "EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared",
            "retryReceipt",
            "divergent reuse",
            "noEffect",
            "async let coalescedA",
            "async let coalescedB",
            "stageAuthenticatedInner",
            "rollbackPublication",
            "commitPublication",
            "activeRegistrationCount",
            "canonicalHeaderSHA256",
            "mutateAfterFirstRead",
            "shortRead",
            "C54RevokingPublicationProbe",
            "C54ExplicitCancellingPublicationProbe",
            "C54CancellingInnerConsumerProbe",
            "cancellation during authenticated-inner commit",
            "different passphrase owner",
            "different resource limits",
            "Data(repeating: 0x54, count: 127)",
            "persistentEdges",
            "persistent lifecycle edge must reject a brand-new secret claim",
            "activeBlockCount",
            "rejectedRegistrationCount",
            "rejectedLeaseCount",
            "C54ResetGate",
            "eraseBlockWhileResetPaused",
            "erase reset must hold admission closed until both reset stores finish",
            "resetRejectedTerminalCount",
            "encryptedPortableEnvelopeResetAlreadyInProgress",
            "overlapping device-local reset must fail closed",
        ),
        "C54 behavioral test coverage",
    )
    _tokens(fixture, (CARD, *EVIDENCE_IDS, "publishedVectors", "pbkdf2HMACSHA256", "aesGCM", "hostileCases", "interruptions"), "C54 corpus")
    fixture_value = json.loads(fixture)
    aes_vectors = fixture_value.get("publishedVectors", {}).get("aesGCM", [])
    if len(aes_vectors) < 2 or any(len(item.get("keyHex", "")) != 64 for item in aes_vectors):
        raise ValueError("C54 fixture lacks published AES-256-GCM vectors")
    if any(item.get("iterations") == 600000 for item in fixture_value.get("publishedVectors", {}).get("pbkdf2HMACSHA256", [])) is False:
        raise ValueError("C54 fixture lacks the released 600000-iteration PBKDF2 vector")


def _support_behavior(root: Path) -> None:
    texts = {path: _text(root, path) for path in SUPPORT_PATHS}
    _tokens(texts[SUPPORT_PATHS[0]], ("C54EncryptedPortableEnvelopeDiagnosticsStoreBoundaryV1", "createsPersistentEnvelopeRecord = false", "persistsPassphrases = false"), "C54 diagnostics store")
    _tokens(texts[SUPPORT_PATHS[1]], ("C54EncryptedPortableEnvelopeDiagnosticPrivacyBoundaryV1", "wrongPassphraseOrDamage"), "C54 diagnostic export")
    _tokens(texts[SUPPORT_PATHS[2]], ("recordC54EncryptedEnvelopeFailure", "recordC54EncryptedEnvelopeLifecycle"), "C54 diagnostic logging")
    _tokens(texts[SUPPORT_PATHS[3]], ("C54EncryptedPortableEnvelopeMetricKitBoundaryV1", "rawMetricKitPayloadRetained = false", "passphrasesRetained = false"), "C54 MetricKit boundary")
    _tokens(texts[SUPPORT_PATHS[4]], ("encryptedPortableEnvelopeRequiredBytes", "checkEncryptedPortableEnvelope", "c54PreflightPrecedesKDFAllocationPreviewAndWrite = true"), "C54 storage preflight")
    _tokens(texts[SUPPORT_PATHS[5]], ("reserveEncryptedPortableEnvelope", "releaseEncryptedPortableEnvelope", "EncryptedPortableEnvelopeProtectedFileScratchV1", "ProtectedFilePolicyV1.verify", "c54CreatesParallelStoreOrRoot = false"), "C54 storage ledger")
    _tokens(
        texts[SUPPORT_PATHS[6]],
        (
            "EncryptedPortableEnvelopeSecretLifecycleRegistryV1",
            "EncryptedPortableEnvelopeLifecycleRegistrationTokenV1",
            "revokeEncryptedPortableEnvelopeSecrets",
            "recoverEncryptedPortableEnvelopeScratch",
            "persistentBlocks",
            "revocationDepth",
            "guard revocationDepth == 0, persistentBlocks.isEmpty else { return false }",
            "activeBlockCount",
            "resumeEncryptedPortableEnvelopeOperations",
            "if reason == .sceneBackground { persistentBlocks.remove(.appLock) }",
            "case .sceneBackground, .appLock, .protectedDataUnavailable, .erase: true",
            "encryptedPortableEnvelopeResetInProgress",
            "encryptedPortableEnvelopeResetAlreadyInProgress",
        ),
        "C54 production lifecycle registry and startup cleanup",
    )
    device_handle_region = _function_region(
        texts[SUPPORT_PATHS[6]], "handle", "resetDeviceLocalState"
    )
    _ordered(
        device_handle_region,
        (
            "state = transition.current",
            "try await recoverDeviceLocalStateIfNeeded()",
            "resumeEncryptedPortableEnvelopeOperations",
        ),
        "C54 lifecycle resume follows truthful state and successful local recovery",
    )
    reset_region = _function_region(
        texts[SUPPORT_PATHS[6]], "resetDeviceLocalState", "cancelEncryptedPortableEnvelopeOperation"
    )
    _ordered(
        reset_region,
        (
            "guard !encryptedPortableEnvelopeResetInProgress",
            "encryptedPortableEnvelopeResetInProgress = true",
            "reason: .erase",
            "resetScratchData()",
            "resetOperationalSupport()",
            "resumeEncryptedPortableEnvelopeOperations",
        ),
        "C54 erase admission remains blocked through successful reset",
    )
    _tokens(texts[SUPPORT_PATHS[7]], ("C54EncryptedPortableEnvelopeEraseAllBoundaryV1", "eraseScratch"), "C54 Erase")
    _tokens(texts[SUPPORT_PATHS[8]], ("C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1", 'envelopeSession = "NONPERSISTENT"'), "C54 nonpersistent classification")
    _tokens(texts[SUPPORT_PATHS[9]], ("testV23P03C54EraseRemovesOnlyAppOwnedEnvelopeScratchAndCreatesNoCanonicalRows",), "C54 Erase test")
    _tokens(texts[SUPPORT_PATHS[10]], ("testV23P03C54EncryptedEnvelopeSecretsScratchAndSessionsNeverBecomeSyncTruth",), "C54 sync test")
    _tokens(texts[SUPPORT_PATHS[11]], ("testV23P03C54EncryptedEnvelopeAddsNoPersistentModelWriterOrLedgerFamily",), "C54 persistence test")
    _tokens(
        texts[SUPPORT_PATHS[12]],
        (
            "C54EncryptedPortableEnvelopeDiagnosticStageV1",
            "C54EncryptedPortableEnvelopeDiagnosticCategoryV1",
            "case .importData, .source: return 4_294_967_296",
        ),
        "C54 diagnostic vocabulary and scratch cap",
    )
    _tokens(texts[SUPPORT_PATHS[13]], ("testV23P03C54ReceiptsAndDiagnosticsCannotLeakPassphraseKeyOrCustomerMetadata",), "C54 diagnostic privacy test")
    plist_value = plistlib.loads((root / SUPPORT_PATHS[15]).read_bytes())
    exported = [
        value
        for value in plist_value.get("UTExportedTypeDeclarations", [])
        if value.get("UTTypeIdentifier") == "com.assetrounds.encrypted-envelope"
    ]
    expected_export = {
        "UTTypeConformsTo": ["public.data"],
        "UTTypeDescription": "AssetRounds Encrypted Envelope",
        "UTTypeIdentifier": "com.assetrounds.encrypted-envelope",
        "UTTypeTagSpecification": {
            "public.filename-extension": ["arenvelope"],
            "public.mime-type": "application/vnd.assetrounds.encrypted-envelope",
        },
    }
    if exported != [expected_export]:
        raise ValueError("C54 exported UTI registration differs")
    document_types = [
        value
        for value in plist_value.get("CFBundleDocumentTypes", [])
        if value.get("LSItemContentTypes") == ["com.assetrounds.encrypted-envelope"]
    ]
    expected_document = {
        "CFBundleTypeExtensions": ["arenvelope"],
        "CFBundleTypeMIMETypes": ["application/vnd.assetrounds.encrypted-envelope"],
        "CFBundleTypeName": "AssetRounds Encrypted Envelope",
        "CFBundleTypeRole": "Viewer",
        "LSHandlerRank": "Owner",
        "LSItemContentTypes": ["com.assetrounds.encrypted-envelope"],
    }
    if document_types != [expected_document]:
        raise ValueError("C54 encrypted-envelope document registration differs")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING), len(NEW), len(FENCE)) != (16, 14, 30):
        raise ValueError("C54 fence cardinality")
    if NEW != (*IMPLEMENTATION, *SCRIPTS, SCHEMA, *GENERATED):
        raise ValueError("C54 hydration new paths differ")
    if len(set(FENCE)) != 30 or any(FLAGS.values()):
        raise ValueError("C54 fence or flags")
    if _H["priorFenceProof"]["fenceCount"] != 83 or _H["priorFenceProof"]["priorOwnedPathCount"] != 1356:
        raise ValueError("C54 prior inventory differs")
    if _H["priorFenceProof"]["authorizedOverlapCount"] != 217 or _H["priorFenceProof"]["unauthorizedOverlapCount"] != 0:
        raise ValueError("C54 overlap authority differs")
    if tuple(_H["priorFenceProof"]["semanticPrerequisiteCardIDs"]) != ("V23-P02-C08",):
        raise ValueError("C54 prerequisite card differs")
    if tuple(_H["priorFenceProof"]["semanticPrerequisiteFenceDigests"]) != (PRIOR_C08_FENCE,):
        raise ValueError("C54 prerequisite fence differs")
    _tokens(_text(root, SCHEMA), (CARD, "V23P03C54EncryptedPortableEnvelopeContractV1"), "C54 schema")
    _source_behavior(root)
    _support_behavior(root)


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "fenceCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "fenceCorrectionTransitionDigest": CORRECTION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": LEDGER_DIGEST,
        "coordinationProjectionDigest": PROJECTION_DIGEST,
        "registerOrdinal": ORDINAL,
        "directPrerequisiteFences": {"V23-P02-C08": PRIOR_C08_FENCE},
        "priorFenceCount": 83,
        "priorOwnedPathCount": 1356,
        "authorizedOverlapCount": 217,
        "unauthorizedOverlapCount": 0,
        "inheritedV21PayloadPresent": False,
    }


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    common = {
        "cardID": CARD,
        "authority": authority(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "statusFlags": FLAGS,
        "priorPrerequisiteProof": {
            "cards": ["V23-P02-C08"],
            "fences": {"V23-P02-C08": PRIOR_C08_FENCE},
            "liveResealRequired": False,
        },
        "s10ReservationOverlapCount": 0,
        "s10ReservedPathCount": 86,
    }
    outputs = {
        CONTRACT: pretty(
            {
                "schema": "V23P03C54EncryptedPortableEnvelopeContractV1",
                "schemaVersion": 1,
                **common,
                "semantics": {
                    "protocolVersion": 1,
                    "innerKindCount": 3,
                    "serviceRequestInnerKindPermitted": False,
                    "pbkdf2HMACSHA256Iterations": 600000,
                    "saltByteCount": 32,
                    "derivedKeyByteCount": 32,
                    "aesGCMKeyBitCount": 256,
                    "maximumPlaintextFrameBytes": 1048576,
                    "tagByteCount": 16,
                    "noncePrefixByteCount": 8,
                    "frameIndexByteCount": 4,
                    "minimumFrameCount": 1,
                    "maximumFrameCount": 4294967295,
                    "minimumPassphraseScalarCount": 15,
                    "maximumPassphraseScalarCount": 256,
                    "maximumPassphraseUTF8Bytes": 1024,
                    "structuralPreflightBeforeKDF": True,
                    "authenticatedInnerValidationBeforePreviewOrWrite": True,
                    "wrongPassphraseAndDamageShareExternalError": True,
                    "secretFreeReceiptTypeCount": 2,
                    "externalOutcomeCount": 5,
                    "clearLegacyReadersPreserved": True,
                    "deterministicCryptoInjectionInRelease": False,
                    "canonicalProductionStreaming": True,
                    "maximumOperationalScratchBytes": 4294967296,
                    "maximumSourceReadBytes": 1048576,
                    "boundedFirstPassBeforeKDFAndSink": True,
                    "dynamicNeutralFilenameAndShareTitle": True,
                    "authenticatedInnerProtocolVersion": True,
                    "openPassphraseConfirmationRequired": False,
                    "finalReceiptAfterLifecycleCleanup": True,
                    "productionLifecycleRegistryWired": True,
                    "sameSessionRetryReturnsSameEffectAndReceipt": True,
                    "divergentRetryFailsClosed": True,
                    "absentRelaunchRetryReturnsNoEffect": True,
                    "obsoleteWholeDataCanonicalSymbolsAbsent": True,
                    "canonicalHeaderBoundToEveryFrameAndReceipt": True,
                    "preKDFInnerVersionAndCancellationValidated": True,
                    "dynamicKindAndPublicIDFilenameAndTitle": True,
                    "authenticatedInnerStagedBeforeCleanupCommittedAfter": True,
                    "sameOperationWorkCoalesced": True,
                    "terminalCacheBindsSourceIdentity": True,
                    "bestEffortCleanupAndPublicationRollback": True,
                    "exactUTIRegistration": True,
                    "exactEvidenceSelectors": True,
                    "transactionalPublicationPrivateUntilCommit": True,
                    "lifecycleRevocationFencesPublicationAndImport": True,
                    "retryIdentityBindsPassphraseOwnerAndLimits": True,
                    "undersizedEnvelopeClassifiedAsDamage": True,
                    "publicationStageReceivesCancellation": True,
                    "asyncPreparationCannotResurrectCancelledAttempt": True,
                    "revocationDuringCleanupIsNotStorageCorruption": True,
                    "lifecycleRegistryBlocksLateClaimsUntilResume": True,
                    "revocationGateBlocksActorReentrantClaims": True,
                    "revocationGenerationFencesRegistrationOvertake": True,
                    "eraseAdmissionBlockedThroughSuccessfulReset": True,
                },
            }
        ),
        EVIDENCE: pretty(
            {
                "schema": "V23P03C54EncryptedPortableEnvelopeEvidenceReceiptV1",
                "schemaVersion": 1,
                **common,
                "cases": list(EVIDENCE_IDS),
                "journey": "FJ11",
                "nativeCompileRan": False,
                "hostedDispatchEnabled": False,
                "physicalLockedState": "REQUIRED_PENDING_OWNER",
            }
        ),
        BRAND: pretty(
            {
                "schema": "V23P03C54BrandImpactManifestV1",
                "schemaVersion": 1,
                **common,
                "uiSurfaceDelta": True,
                "brandSurfaceDelta": True,
                "customerIdentityVerified": False,
                "deliveryOrLegalSignatureClaimed": False,
                "perfectZeroizationClaimed": False,
                "networkOrTelemetryFlow": False,
                "exportComplianceExemptionClaimed": False,
            }
        ),
    }
    files = []
    for path in FENCE:
        if path == MANIFEST:
            continue
        data = outputs[path] if path in outputs else (root / path).read_bytes()
        files.append({"path": path, "byteCount": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    outputs[MANIFEST] = pretty(
        {
            "schema": "V23P03C54ToolingManifestV1",
            "schemaVersion": 1,
            **common,
            "existingPathCount": 16,
            "newPathCount": 14,
            "fencePathCount": 30,
            "files": files,
        }
    )
    return outputs
