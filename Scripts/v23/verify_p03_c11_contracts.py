#!/usr/bin/env python3
"""Fail-closed static verifier for provisional V23-P03-C11 tooling."""
from __future__ import annotations

import base64
import copy
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import unquote

sys.dont_write_bytecode = True
import p03_c11_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git(root: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args], check=check, capture_output=True, text=True,
        encoding="utf-8",
    )
    return result.stdout.strip()


def load(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf"), f"BOM forbidden: {path}")
    duplicates: list[str] = []

    def pairs(rows: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in rows:
            if key in value:
                duplicates.append(key)
            value[key] = item
        return value

    value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    require(not duplicates and isinstance(value, dict), f"invalid/duplicate JSON object: {path}")
    return value


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def resolve_local_ref(document: dict[str, Any], reference: Any, label: str) -> Any:
    require(isinstance(reference, str) and (reference == "#" or reference.startswith("#/")),
            f"non-local schema ref: {label}: {reference!r}")
    target: Any = document
    if reference == "#":
        return target
    for encoded in reference[2:].split("/"):
        token = unquote(encoded).replace("~1", "/").replace("~0", "~")
        if isinstance(target, dict):
            require(token in target, f"unresolved schema ref: {label}: {reference}")
            target = target[token]
        elif isinstance(target, list):
            require(token.isdigit() and int(token) < len(target),
                    f"unresolved schema ref index: {label}: {reference}")
            target = target[int(token)]
        else:
            raise VerificationError(f"schema ref traverses scalar: {label}: {reference}")
    return target


def audit_local_refs(document: dict[str, Any], label: str) -> int:
    resolved: set[str] = set()

    def audit(reference: Any, active: set[str]) -> None:
        target = resolve_local_ref(document, reference, label)
        assert isinstance(reference, str)
        resolved.add(reference)
        if reference in active:
            return
        for node in walk(target):
            if isinstance(node, dict) and "$ref" in node:
                audit(node["$ref"], active | {reference})

    for node in walk(document):
        if isinstance(node, dict) and "$ref" in node:
            audit(node["$ref"], set())
    return len(resolved)


def changed_paths(root: Path) -> set[str]:
    status = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True, encoding="utf-8",
    ).stdout
    rows = status.splitlines()
    result: set[str] = set()
    for row in rows:
        if len(row) < 4:
            continue
        raw = row[3:].replace("\\", "/")
        if " -> " in raw:
            result.update(part.strip() for part in raw.split(" -> "))
        else:
            result.add(raw)
    return result


def independently_generated(root: Path) -> dict[str, bytes]:
    command = [sys.executable, "-B", str(root / contracts.SCRIPT_PATHS[1]), "--dump-json"]
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    first = subprocess.run(command, cwd=root, env=environment, check=True,
                           capture_output=True, text=True, encoding="utf-8")
    second = subprocess.run(command, cwd=root, env=environment, check=True,
                            capture_output=True, text=True, encoding="utf-8")
    require(first.stdout == second.stdout, "independent subprocess generation is not deterministic")
    decoded = json.loads(first.stdout)
    require(isinstance(decoded, dict), "dump-json output is not an object")
    return {path: base64.b64decode(value, validate=True) for path, value in decoded.items()}


def validate_json_schema_net(root: Path, fixture: dict[str, Any]) -> int:
    assembly = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/JsonSchema.Net.dll"
    require(assembly.is_file(), "pinned offline JsonSchema.Net assembly unavailable")
    require(sha256(assembly.read_bytes()) == "1243dc7749d37818beadf8967c3963082ba00efe05877e3f180346e9f56007a0",
            "pinned offline JsonSchema.Net digest differs")
    positives: list[dict[str, Any]] = [fixture]
    optional = copy.deepcopy(fixture)
    for row in optional["postCheckpointChanges"]:
        row.pop("contentSHA256", None)
        row.pop("reversesMutationID", None)
    for row in optional["contentCases"]:
        row.pop("observedSHA256", None)
        row.pop("resumeSHA256", None)
    positives.append(optional)
    negatives: list[tuple[str, dict[str, Any]]] = []
    value = copy.deepcopy(fixture)
    value["unexpected"] = True
    negatives.append(("UNKNOWN_TOP_LEVEL_FIELD", value))
    value = copy.deepcopy(fixture)
    value["checkpoint"]["unexpected"] = True
    negatives.append(("UNKNOWN_NESTED_FIELD", value))
    value = copy.deepcopy(fixture)
    del value["checkpoint"]
    negatives.append(("MISSING_REQUIRED_TOP_LEVEL_FIELD", value))
    value = copy.deepcopy(fixture)
    value["schemaVersion"] = 2
    negatives.append(("FUTURE_SCHEMA_VERSION", value))
    value = copy.deepcopy(fixture)
    value["postCheckpointChanges"][0]["contentSHA256"] = "not-a-sha"
    negatives.append(("INVALID_OPTIONAL_HASH", value))
    value = copy.deepcopy(fixture)
    value["pages"][0]["sequences"][1] = value["pages"][0]["sequences"][0]
    negatives.append(("DUPLICATE_PAGE_SEQUENCE", value))
    value = copy.deepcopy(fixture)
    value["rollback"]["providerStateCreated"] = True
    negatives.append(("FORBIDDEN_PROVIDER_STATE", value))
    value = copy.deepcopy(fixture)
    value["destinationReplicaIDs"][0] = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    negatives.append(("WRONG_DESTINATION_REPLICA", value))
    with tempfile.TemporaryDirectory(prefix="v23-p03-c11-schema-") as temporary:
        temp = Path(temporary)
        rows: list[dict[str, Any]] = []
        schema_path = (root / contracts.SCHEMA_PATH).resolve()
        for index, instance in enumerate(positives):
            target = temp / f"positive-{index}.json"
            target.write_bytes(contracts.pretty(instance))
            rows.append({"label": f"POSITIVE_{index}", "instance": str(target.resolve()), "expected": True})
        for index, (label, instance) in enumerate(negatives):
            target = temp / f"negative-{index}.json"
            target.write_bytes(contracts.pretty(instance))
            rows.append({"label": label, "instance": str(target.resolve()), "expected": False})
        index_path = temp / "index.json"
        index_path.write_bytes(contracts.pretty({"schema": str(schema_path), "rows": rows}))
        quote = lambda path: "'" + str(path).replace("'", "''") + "'"
        script = (
            f"Add-Type -Path {quote(assembly)}; $o=[Json.Schema.EvaluationOptions]::new(); "
            f"$i=Get-Content -LiteralPath {quote(index_path)} -Raw|ConvertFrom-Json; "
            "$sn=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $i.schema -Raw));"
            "$mr=[Json.Schema.MetaSchemas]::Draft202012.Evaluate($sn,$o);"
            "if(-not $mr.IsValid){throw 'schema meta-validation failed'};"
            "$s=[Json.Schema.JsonSchema]::FromFile($i.schema);"
            "foreach($x in $i.rows){$n=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $x.instance -Raw));"
            "$r=$s.Evaluate($n,$o);if($r.IsValid -ne [bool]$x.expected){throw ('instance '+$x.label)}};'PASS'"
        )
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script],
                                capture_output=True, text=True, encoding="utf-8")
        require(result.returncode == 0 and result.stdout.strip().endswith("PASS"),
                f"pinned schema validation failed: {result.stderr.strip()}")
    return len(positives) + len(negatives)


def fixture_invariants(root: Path, value: dict[str, Any]) -> None:
    path = root / contracts.FIXTURE
    raw = path.read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf") and raw.decode("utf-8").endswith(("\n", "\r\n")),
            "fixture must be BOM-free UTF-8 text with a terminal line ending")
    required = {
        "schema", "schemaVersion", "fixedSeed", "workspaceID", "sourceReplicaID",
        "destinationReplicaIDs", "bounds", "checkpoint", "postCheckpointChanges",
        "pages", "replaySchedules", "contentCases", "conflictCases", "reversal",
        "crashMatrix", "replicaSchedules", "scale", "rollback", "releaseAbsence",
    }
    require(set(value) == required, "fixture top-level field closure differs")
    require(value["schema"] == "V21P03C11ChangeJournalCheckpointReplayCorpusV1" and
            value["schemaVersion"] == 1 and value["fixedSeed"] == contracts.FIXED_SEED,
            "fixture identity/version differs")
    require(value["workspaceID"] == contracts.WORKSPACE_ID and
            value["sourceReplicaID"] == contracts.SOURCE_REPLICA_ID and
            value["destinationReplicaIDs"] == contracts.DESTINATION_REPLICA_IDS,
            "fixture workspace/replica binding differs")
    bounds = value["bounds"]
    require(bounds == {
        "maximumPageItems": 3, "maximumPageBytes": 65536, "maximumGapPages": 2,
        "maximumReplayAttempts": 4, "scaleAssetCount": 10000, "scalePageItems": 128,
        "scaleExpectedPageCount": 79, "scaleMaximumResidentBytes": 16777216,
    }, "fixture bounds differ")
    checkpoint = value["checkpoint"]
    require(checkpoint["revision"] == checkpoint["cursorSequence"] == 40 and
            checkpoint["complete"] is True and checkpoint["verified"] is True and
            checkpoint["schemaRelease"] == "KERNEL_PERSISTENCE_V4" and
            checkpoint["packageID"] == "kernel_persistence_v4" and
            checkpoint["packageSchemaVersion"] == 4 and
            checkpoint["packageContentVersion"] == 1,
            "checkpoint completeness/frontier differs")
    require(len(value["postCheckpointChanges"]) == 6 and
            [row["sequence"] for row in value["postCheckpointChanges"]] == list(range(41, 47)),
            "post-checkpoint sequence closure differs")
    changes = value["postCheckpointChanges"]
    require(changes[1]["kind"] == "CONTENT_ATTACH" and changes[1]["contentSHA256"] is not None,
            "content dependency change differs")
    reversal_change = next(row for row in changes if row["kind"] == "SEMANTIC_REVERSAL")
    require(reversal_change["reversesMutationID"] == changes[0]["mutationID"],
            "semantic reversal lineage differs")
    pages = value["pages"]
    require(len(pages) == 2 and pages[0]["afterSequence"] == 40 and
            pages[0]["sequences"] == [41, 42, 43] and
            pages[1]["afterSequence"] == 43 and pages[1]["sequences"] == [44, 45, 46] and
            pages[1]["isTerminal"] is True and
            [sequence for page in pages for sequence in page["sequences"]] == list(range(41, 47)),
            "bounded pages/frontier differ")
    schedule_dispositions = {row["id"]: row["expectedDisposition"]
                             for row in value["replaySchedules"]}
    require(schedule_dispositions == {
        "golden-checkpoint-then-post-r": "APPLIED_TO_46",
        "duplicate-and-reordered": "GAP_BUFFERED_THEN_APPLIED_DUPLICATES_IGNORED",
        "bounded-gap-resume": "DURABLE_GAP_RESUMED_TO_46",
        "gap-overflow": "REJECTED_GAP_BOUND_EXCEEDED_NO_EFFECT",
    }, "replay schedule dispositions differ")
    content = {row["id"]: row for row in value["contentCases"]}
    require(content["content-missing-then-resumed"]["observedSHA256"] is None and
            content["content-missing-then-resumed"]["expectedDisposition"] == "DEFERRED_THEN_APPLIED" and
            content["content-corrupt-then-resumed"]["observedSHA256"] !=
            content["content-corrupt-then-resumed"]["resumeSHA256"],
            "missing/corrupt content semantics differ")
    conflict = {row["id"]: row["expectedDisposition"] for row in value["conflictCases"]}
    require(conflict == {
        "old-backup-tombstone": "TOMBSTONED_NO_RESURRECTION",
        "same-field-manual": "UNRESOLVED_STABLE_CONFLICT_ID",
        "delete-versus-update": "DELETE_WINS_NO_RESURRECTION",
        "resolution-before-competitors": "CAUSALLY_DEFERRED_THEN_RESOLVED",
        "late-third-competitor": "EARLIER_BASIS_REMAINS_RESOLVED_SUCCESSOR_CONFLICT_CREATED",
    }, "conflict matrix differs")
    require(value["reversal"]["targetMutationID"] == changes[0]["mutationID"] and
            value["reversal"]["reversalMutationID"] == reversal_change["mutationID"] and
            value["reversal"]["expectedCompactionDisposition"] ==
            "BASIS_AND_BOTH_RECEIPT_IDENTITIES_RETAINED", "reversal/compaction closure differs")
    require({row["boundary"] for row in value["crashMatrix"]} == {
        "CHECKPOINT_PREPARED", "CHECKPOINT_COMMITTED", "PAGE_PREPARED", "PAGE_COMMITTED",
        "REPLAY_AFTER_EFFECT_BEFORE_CURSOR", "ACTIVATION_PRE_POINTER", "ACTIVATION_POST_POINTER",
        "COMPACTION_PRE_REPLACEMENT", "COMPACTION_POST_REPLACEMENT",
    }, "crash matrix boundary closure differs")
    require([row["id"] for row in value["replicaSchedules"]] ==
            ["two-replica-golden", "three-replica-adversarial"] and
            [len(row["replicas"]) for row in value["replicaSchedules"]] == [2, 3],
            "replica schedule closure differs")
    require(value["scale"] == {
        "assetCount": 10000, "seed": 230311,
        "generationRule": contracts.SCALE_GENERATION_RULE,
        "labelRule": "Asset-%05d", "pageItemLimit": 128, "expectedPageCount": 79,
        "expectedFinalRevision": 10000,
        "expectedNormalizedMetadataSHA256": value["scale"]["expectedNormalizedMetadataSHA256"],
        "maximumResidentBytes": 16777216,
    }, "scale envelope differs")
    require(value["rollback"] == {
        "policy": "CONTENT_ROLLBACK_ONLY", "incompleteDerivedCheckpointsDiscardable": True,
        "acceptedReceiptsImmutable": True, "releasedSchemaDowngradeAllowed": False,
        "providerStateCreated": False,
    }, "rollback posture differs")
    require(value["releaseAbsence"]["forbiddenProductionSymbols"] ==
            contracts.FORBIDDEN_PRODUCTION_SYMBOLS and
            value["releaseAbsence"]["forbiddenProductionPaths"] ==
            contracts.FORBIDDEN_PRODUCTION_PATHS, "release-absence canaries differ")
    for row in changes:
        for key in ("canonicalInputSHA256",):
            require(re.fullmatch(r"[0-9a-f]{64}", row[key]) is not None,
                    f"invalid change digest: {key}")
        for key in ("contentSHA256",):
            require(row.get(key) is None or re.fullmatch(r"[0-9a-f]{64}", row[key]),
                    f"invalid nullable change digest: {key}")


def source_codable_parity(root: Path) -> dict[str, Any]:
    path = root / "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift"
    source = path.read_text(encoding="utf-8")
    starts = list(re.finditer(r"(?m)^(?:struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)\b", source))
    sections = {
        match.group(1): source[match.start(): (starts[index + 1].start()
                                                if index + 1 < len(starts) else len(source))]
        for index, match in enumerate(starts)
    }
    for type_id, expected in contracts.CODABLE_FIELDS.items():
        section = sections.get(type_id)
        require(section is not None, f"missing Swift Codable type: {type_id}")
        match = re.search(r"CodingKeys:[^{]+\{(?P<body>.*?)\}", section, re.S)
        require(match is not None, f"missing CodingKeys: {type_id}")
        actual: list[str] = []
        for case_body in re.findall(r"\bcase\s+([^}\n]+)", match.group("body")):
            actual.extend(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", case_body))
        require(actual == expected, f"Swift CodingKeys differ for {type_id}: {actual}")
        require(
            "ChangeJournalClosedCodingV1.requireExact" in section
            or "ChangeJournalClosedCodingV1.requireClosed" in section,
            f"closed Codable decoder missing for {type_id}",
        )
    for type_id, expected in contracts.CODABLE_ENUMS.items():
        section = sections.get(type_id)
        require(section is not None, f"missing Swift enum: {type_id}")
        actual = re.findall(r'\bcase\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"([A-Z_]+)"', section)
        require(actual == expected, f"Swift enum values differ for {type_id}: {actual}")
    for optional in ("previousBatchSHA256", "portablePlan", "reversingMutationID",
                     "basisSHA256", "conflictIdentity", "reversalBasis",
                     "portableReversalPlan", "semanticReversalReceipt", "reasonCode"):
        require("decodeIfPresent" in sections[next(type_id for type_id, fields in contracts.CODABLE_FIELDS.items()
                                                    if optional in fields)],
                f"missing decodeIfPresent for optional field: {optional}")
    return {"typeCount": len(contracts.CODABLE_FIELDS), "enumCount": len(contracts.CODABLE_ENUMS)}


def source_and_test_checks(root: Path) -> dict[str, Any]:
    source_parity = source_codable_parity(root)
    local = (root / "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift").read_text(encoding="utf-8")
    required_local_tokens = (
        "WorkspaceSnapshotManifestV1", "ChangeBatchV1", "ChangeCursorV1",
        "ChangeJournalFailureV1", "checkpoint", "replay", "compaction",
        "replayReceipts", "alreadyApplied", "workspaceID", "ReplicaID",
    )
    for token in required_local_tokens:
        require(token.lower() in local.lower(), f"local journal source lacks required seam: {token}")
    for token in ("URL" + "Session", "Cloud" + "Kit", "Provider" + "Outbox",
                  "Network" + "Transport", "Cloud" + "Attachment", "signed" + "URL"):
        require(token not in local, f"forbidden external scope symbol in local journal: {token}")
    test = (root / contracts.TEST_PATH).read_text(encoding="utf-8")
    methods = re.findall(r"\bfunc\s+(testV9_ChangeJournalCheckpointReplay[A-Za-z0-9_]*)\s*\(",
                         test)
    require(methods == contracts.TEST_METHODS, f"exact five test methods differ: {methods}")
    for token in ("V21P03C11ChangeJournalCheckpointReplayCorpusV1",
                  "ReplicaConvergenceScenarioV1", "ReplicaDeliveryScheduleV1",
                  "ReplicaConvergenceReceiptV1", "Bundle", "JSONDecoder",
                  "assertSHA256"):
        require(token in test, f"test source lacks required static evidence seam: {token}")
    require(test.count("func testV9_ChangeJournalCheckpointReplay") == 5,
            "test count differs")
    return source_parity


def forbidden_scope_scan(root: Path) -> None:
    # Build symbols by concatenation so this verifier does not trip over its own
    # scanner literals.  The fixture intentionally contains the three production
    # absence canaries and is checked separately above.
    tokens = [
        "URL" + "Session", "Cloud" + "Kit", "Fire" + "base", "Provider" + "Outbox",
        "Network" + "Transport", "Cloud" + "Attachment", "signed" + "URL",
        "service" + "Credential", "tenant" + "Membership", "remote" + "Sync",
        "upload" + "State", "CK" + "Record", "CK" + "Container", "NW" + "Connection",
    ]
    inspect_paths = [path for path in contracts.PATH_FENCE if path != contracts.FIXTURE]
    for relative in inspect_paths:
        raw = (root / relative).read_bytes()
        text = raw.decode("utf-8")
        for token in tokens:
            require(token not in text, f"forbidden external scope symbol {token}: {relative}")
        require(re.search(r"(?:nativeCompileRan|hostedDispatchEnabled|acceptanceCredit|releaseCredit|"
                          r"adoptionEnabled|phase10PollingDuringParallelExecution)\s*[:=]\s*true",
                          text, re.I) is None,
                f"forbidden provisional capability claim: {relative}")


def verify_contract_and_evidence(root: Path, schema: dict[str, Any],
                                 contract: dict[str, Any], evidence: dict[str, Any]) -> None:
    unsigned = dict(contract)
    seal = unsigned.pop("artifactDigest", None)
    require(seal == sha256(contracts.pretty(unsigned)), "contract artifact seal differs")
    require(contract["authority"] == contracts.authority() and
            contract["pathFence"] == contracts.PATH_FENCE and
            contract["sourcePaths"] == contracts.SOURCE_PATHS and
            contract["toolPaths"] == contracts.TOOL_PATHS and
            contract["generatedPaths"] == contracts.GENERATED_PATHS,
            "contract authority/path projection differs")
    require(contract["evidenceIDs"] == contracts.EVIDENCE_IDS and
            [row["method"] for row in contract["testMethods"]] == contracts.TEST_METHODS and
            contract["codableProjection"] == contracts.codable_projection(),
            "contract test/Codable projection differs")
    require(contract["failureCases"] == contracts.FAILURE_CASES and
            contract["semanticScope"] == contracts.SEMANTIC_SCOPE,
            "contract semantic/failure projection differs")
    expected_sources = contracts.source_rows(root)
    require(contract["sourceArtifacts"] == expected_sources and
            contract["fixtureArtifact"] == {
                "path": contracts.FIXTURE, "bytes": (root / contracts.FIXTURE).stat().st_size,
                "sha256": sha256((root / contracts.FIXTURE).read_bytes()),
            }, "contract source/fixture hash closure differs")
    for flag in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled",
                 "acceptanceEnabled", "acceptanceCredit", "releaseCredit",
                 "phase10PollingDuringParallelExecution"):
        require(contract[flag] is False, f"forbidden contract claim: {flag}")
    unsigned = dict(evidence)
    seal = unsigned.pop("artifactDigest", None)
    require(seal == sha256(contracts.pretty(unsigned)), "evidence artifact seal differs")
    require(evidence["authority"] == contracts.authority() and evidence["result"] == "PASS" and
            evidence["verificationMode"] == "STATIC_ONLY" and
            evidence["evidenceIDs"] == contracts.EVIDENCE_IDS and
            evidence["testMethods"] == contracts.TEST_METHODS,
            "evidence identity/posture differs")
    require(evidence["sourceArtifacts"] == expected_sources and
            evidence["fixtureArtifact"]["sha256"] == contract["fixtureArtifact"]["sha256"] and
            evidence["schemaArtifact"]["sha256"] == sha256(contracts.pretty(schema)) and
            evidence["contractArtifact"]["sha256"] == sha256(contracts.pretty(contract)),
            "evidence digest closure differs")
    require(set(evidence["checks"]) == {
        "EXACT_AUTHORITY_AND_13_PATH_FENCE", "BASE_HEAD_TREE_AND_EXISTENCE_PARTITION",
        "S10_ZERO_OVERLAP_AND_EXTERNAL_SCOPE_ABSENCE", "CANONICAL_FIXTURE_AND_FIXED_SEMANTIC_VECTORS",
        "STRICT_DRAFT_2020_12_META_SCHEMA_AND_POSITIVE_NEGATIVE_INSTANCES",
        "SWIFT_CODABLE_CODINGKEYS_AND_OPTIONAL_MISSING_NULL_PARITY",
        "EXACT_FIVE_EVIDENCE_IDS_AND_TEST_METHODS", "MANIFEST_BYTE_DIGEST_CLOSURE",
        "INDEPENDENT_SUBPROCESS_GENERATION_REPEATABILITY", "PYTHON_CACHE_ABSENCE",
    }, "evidence check inventory differs")
    for flag in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled",
                 "acceptanceEnabled", "acceptanceCredit", "releaseCredit",
                 "phase10PollingDuringParallelExecution"):
        require(evidence[flag] is False, f"forbidden evidence claim: {flag}")


def verify_manifest(root: Path, generated: dict[str, bytes]) -> None:
    manifest = load(root / contracts.MANIFEST)
    unsigned = dict(manifest)
    seal = unsigned.pop("artifactDigest", None)
    require(seal == sha256(contracts.pretty(unsigned)), "manifest artifact seal differs")
    require(manifest["authority"] == contracts.authority() and
            manifest["pathFence"] == contracts.PATH_FENCE and
            manifest["existingPaths"] == contracts.EXISTING_PATHS and
            manifest["newPaths"] == contracts.NEW_PATHS and
            manifest["pathFenceCount"] == 13 and
            manifest["sourcePathCount"] == 6 and manifest["toolPathCount"] == 7 and
            manifest["generatedArtifactCount"] == 4 and
            manifest["manifestInputCount"] == 12,
            "manifest fence/count projection differs")
    rows = manifest["artifacts"]
    require([row["path"] for row in rows] == contracts.MANIFEST_INPUT_PATHS and
            len(rows) == 12 and
            manifest["artifactSetDigest"] == sha256(contracts.canonical(rows)),
            "manifest artifact ordering/set seal differs")
    for row in rows:
        expected = generated.get(row["path"])
        if expected is None:
            expected = (root / row["path"]).read_bytes()
        require(row["bytes"] == len(expected) and row["sha256"] == sha256(expected),
                f"manifest artifact digest differs: {row['path']}")
    require(manifest["activeS10ReservationPathCount"] == 86 and
            manifest["s10FenceOverlapPaths"] == [] and
            manifest["evidenceIDs"] == contracts.EVIDENCE_IDS,
            "manifest S10/evidence projection differs")
    for flag in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled",
                 "acceptanceEnabled", "acceptanceCredit", "releaseCredit",
                 "phase10PollingDuringParallelExecution"):
        require(manifest[flag] is False, f"forbidden manifest claim: {flag}")


def verify(root: Path) -> dict[str, Any]:
    require(git(root, "rev-parse", "HEAD") == contracts.APP_BASE_HEAD,
            "application base head differs")
    require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE,
            "application base tree differs")
    require(len(contracts.PATH_FENCE) == 13 and len(set(contracts.PATH_FENCE)) == 13,
            "exact 13-path fence differs")
    require(contracts.PATH_FENCE == contracts.SOURCE_PATHS + contracts.TOOL_PATHS,
            "path fence partition/order differs")
    require(len(contracts.SOURCE_PATHS) == 6 and len(contracts.TOOL_PATHS) == 7 and
            len(contracts.GENERATED_PATHS) == 4, "source/tool/generated counts differ")
    require(changed_paths(root) == set(contracts.PATH_FENCE),
            "full changed-path fence differs")
    for relative in contracts.PATH_FENCE:
        require((root / relative).is_file(), f"missing fenced path: {relative}")
        exists = subprocess.run(
            ["git", "-C", str(root), "cat-file", "-e", f"{contracts.APP_BASE_HEAD}:{relative}"],
            capture_output=True,
        )
        require((exists.returncode == 0) == (relative in contracts.EXISTING_PATHS),
                f"base existence differs: {relative}")
    require(len(contracts.ACTIVE_S10_RESERVED_PATHS) == 86 and
            len(set(contracts.ACTIVE_S10_RESERVED_PATHS)) == 86 and
            not (set(contracts.PATH_FENCE) & set(contracts.ACTIVE_S10_RESERVED_PATHS)),
            "S10 reservation overlap or inventory differs")
    caches = [path for path in root.rglob("*")
              if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo")]
    require(not caches, f"Python cache leaked: {caches}")
    value = load(root / contracts.FIXTURE)
    fixture_invariants(root, value)
    schema = load(root / contracts.SCHEMA_PATH)
    require(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema" and
            schema["$id"] == "https://assetrounds.invalid/schemas/v23/change-journal-checkpoint-replay.schema.json" and
            schema["$ref"] == "#/$defs/corpus" and
            schema["$defs"]["corpus"]["additionalProperties"] is False,
            "schema dialect/root projection differs")
    require(audit_local_refs(schema, contracts.SCHEMA_PATH) >= 1,
            "schema local reference closure unexpectedly weak")
    for node in walk(schema):
        if isinstance(node, dict) and node.get("type") == "object" and "properties" in node:
            require(node.get("additionalProperties") is False,
                    "open object in strict schema")
    contract = load(root / contracts.CONTRACT_PATH)
    evidence = load(root / contracts.EVIDENCE_PATH)
    verify_contract_and_evidence(root, schema, contract, evidence)
    source_checks = source_and_test_checks(root)
    forbidden_scope_scan(root)
    expected = contracts.all_outputs(root)
    require(contracts.all_outputs(root) == expected, "in-process generation is not deterministic")
    require(independently_generated(root) == expected,
            "independent subprocess generation differs")
    for relative, raw in expected.items():
        require((root / relative).read_bytes() == raw,
                f"stale generated artifact: {relative}")
    sample_count = validate_json_schema_net(root, value)
    verify_manifest(root, expected)
    return {
        "result": "PASS", "cardID": contracts.CARD, "verificationMode": "STATIC_ONLY",
        "pathFenceCount": 13, "strictSchemaCount": 1, "sampleValidationCount": sample_count,
        "evidenceIDCount": 5, "codableTypeCount": source_checks["typeCount"],
        "codableEnumCount": source_checks["enumCount"], "nativeCompileRan": False,
        "hostedDispatchEnabled": False, "adoptionEnabled": False, "acceptanceCredit": False,
        "releaseCredit": False, "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError,
            ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C11 verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
