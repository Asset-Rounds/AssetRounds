#!/usr/bin/env python3
"""Read-only validation of V30 provisional candidate/reconciliation evidence."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "docs/design/v30/contracts/V30ProvisionalCandidateReconciliationManifestV1.json"
SCHEMA = ROOT / "docs/design/v30/schemas/v30-provisional-candidate-reconciliation-manifest.schema.json"
AUTHORITY = ROOT / "docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json"
FENCES = ROOT / "docs/design/v30/authority/V30PreS10PathFencesV1.json"


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], stderr=subprocess.PIPE)


def shape(value, spec, at="manifest"):
    """Check only the closed schema vocabulary used by this contract."""
    allowed = {"$schema", "title", "type", "properties", "required", "additionalProperties",
               "items", "minItems", "uniqueItems", "pattern", "const", "enum"}
    require(set(spec) <= allowed, f"{at}: unsupported schema keyword")
    types = {"object": dict, "array": list, "string": str, "integer": int, "boolean": bool,
             "null": type(None)}
    require(type(value) is types[spec["type"]], f"{at}: type")
    if "const" in spec:
        require(value == spec["const"], f"{at}: constant")
    if "enum" in spec:
        require(value in spec["enum"], f"{at}: enum")
    if isinstance(value, dict):
        require(set(spec["required"]) <= value.keys(), f"{at}: missing field")
        require(spec["additionalProperties"] is False, f"{at}: open schema")
        require(value.keys() <= spec["properties"].keys(), f"{at}: unknown field")
        for key, item in value.items():
            shape(item, spec["properties"][key], f"{at}.{key}")
    elif isinstance(value, list):
        require(len(value) >= spec.get("minItems", 0), f"{at}: too few items")
        if spec.get("uniqueItems"):
            encoded = [json.dumps(x, sort_keys=True) for x in value]
            require(len(encoded) == len(set(encoded)), f"{at}: duplicate item")
        for index, item in enumerate(value):
            shape(item, spec["items"], f"{at}[{index}]")
    elif isinstance(value, str) and "pattern" in spec:
        require(re.fullmatch(spec["pattern"], value) is not None, f"{at}: pattern")


def observed_file(head, path):
    require(not path.startswith(("/", "\\")) and ".." not in Path(path).parts
            and not any(c in path for c in "*?{}[]\\:"), "non-relative or unexpanded path")
    result = git("ls-tree", head, "--", path).decode().strip()
    if not result:
        return {"state": "ABSENT", "blobOID": "", "sha256": ""}
    metadata, actual_path = result.split("\t", 1)
    mode, kind, oid = metadata.split()
    require(actual_path == path and kind == "blob" and mode == "100644", "non-regular file")
    return {"state": "PRESENT", "blobOID": oid, "sha256": sha(git("cat-file", "blob", oid))}


def validate(document):
    shape(document, json.loads(SCHEMA.read_text(encoding="utf-8")))
    authority = json.loads(AUTHORITY.read_text(encoding="utf-8"))
    fences = json.loads(FENCES.read_text(encoding="utf-8"))
    require(document["authorityID"] == authority["authorityID"], "authority ID")
    require(document["authorityContentDigest"] == authority["authorityContentDigest"], "authority digest")
    require(document["schemaSHA256"] == sha(SCHEMA.read_bytes()), "schema hash")
    require(document["fenceSHA256"] == sha(FENCES.read_bytes()), "fence hash")
    require(document["B"] == {"head": authority["frozenV23"]["head"], "tree": authority["frozenV23"]["tree"]}, "frozen B")
    require(all(flag is False for flag in document["credit"].values()), "provisional credit")
    require(document["P"] == {"head": None, "tree": None, "state": "NOT_FROZEN_PRE_S10"}, "terminal P is not frozen")
    require(document["S"] == {"head": None, "tree": None, "state": "POST_S10_AUTHORITY_REQUIRED"}, "accepted S is locked")
    require([row["cardID"] for row in document["cards"]] == document["referenceCardIDs"], "incomplete reference cohort")
    by_card = {card["cardID"]: card for card in fences["cards"]}
    tuples = {(t["cardID"], t["path"]): t for t in authority["pathFenceAuthority"]["s10SharedReconciliationTuples"]}
    seen_cards = set()
    last_ordinal = 0
    for row in document["cards"]:
        card_id = row["cardID"]
        require(card_id in by_card and card_id not in seen_cards, "unknown or duplicate card")
        seen_cards.add(card_id)
        fence = by_card[card_id]
        require(fence["ordinal"] > last_ordinal, "card order")
        last_ordinal = fence["ordinal"]
        require(row["directPrerequisites"] == fence["directPrerequisites"], "prerequisites")
        for binding in (row["base"], row["candidate"]):
            require(git("rev-parse", binding["head"] + "^{tree}").decode().strip() == binding["tree"], "head/tree")
        base, head = row["base"]["head"], row["candidate"]["head"]
        history = row["candidateHistory"]
        validate_history(history, row["base"], row["candidate"])
        for item in history:
            require(git("rev-parse", item["head"] + "^{tree}").decode().strip() == item["tree"], "history head/tree")
            require(git("rev-list", "--parents", "-n", "1", item["head"]).decode().split()[1:] == [item["parent"]], "history direct child, no merge")
        git("merge-base", "--is-ancestor", document["B"]["head"], base)
        actual = git("diff", "--name-only", base, head).decode().splitlines()
        paths = [entry["path"] for entry in row["changedPaths"]]
        require(paths == sorted(set(paths)) and paths == actual, "changed paths")
        allowed = {entry["path"]: entry for entry in fence["allowedPaths"]}
        for item in history:
            historical_paths = git("diff", "--name-only", item["parent"], item["head"]).decode().splitlines()
            require(set(historical_paths) <= allowed.keys(), "unfenced historical change")
            require(item["changedPaths"] == historical_paths, "historical changed paths")
            historical_shared = sorted(set(historical_paths) & set(authority["phase10Isolation"]["reservedPaths"]))
            require(item["s10SharedPaths"] == historical_shared, "historical shared paths")
            for path in historical_shared:
                tup = tuples.get((card_id, path))
                frozen = observed_file(document["B"]["head"], path)
                require(tup is not None and tup in fence["preAuthorizedOverlapTuples"] and path in fence["s10SharedPaths"], "historical overlap authority")
                require(tup["expectedBBlobOID"] == frozen["blobOID"] and tup["expectedBSHA256"] == frozen["sha256"], "historical overlap frozen blob")
        shared = sorted(set(paths) & set(authority["phase10Isolation"]["reservedPaths"]))
        require(row["s10SharedPaths"] == shared, "reserved intersection")
        for entry in row["changedPaths"]:
            path = entry["path"]
            require(path in allowed, "unfenced path")
            require(entry["old"] == observed_file(base, path), "old blob/hash")
            require(entry["new"] == observed_file(head, path), "new blob/hash")
            expected = "S10_SHARED_RECONCILIATION_REQUIRED" if path in shared else "V30_PROVISIONAL_OWNED"
            require(entry["classification"] == expected, "ownership classification")
            if path in shared:
                require(path in fence["s10SharedPaths"], "missing shared membership")
                frozen = observed_file(document["B"]["head"], path)
                tup = tuples.get((card_id, path))
                require(tup is not None and tup in fence["preAuthorizedOverlapTuples"], "missing overlap tuple")
                require(tup["expectedBBlobOID"] == frozen["blobOID"] and tup["expectedBSHA256"] == frozen["sha256"], "frozen overlap blob")
                require(entry["authorityTupleSHA256"] == sha((json.dumps(tup, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()), "overlap tuple hash")
            else:
                require(entry["authorityTupleSHA256"] == "", "unnecessary overlap tuple")
        require(row["reconciliation"]["originalCandidate"] == row["candidate"], "original candidate mapping")
        evidence_heads = set()
        for evidence in row["evidence"]:
            require(evidence["head"] in {item["head"] for item in history}, "evidence candidate")
            evidence_heads.add(evidence["head"])
            file = observed_file(evidence["head"], evidence["path"])
            require(file["state"] == "PRESENT" and file["sha256"] == evidence["sha256"], "evidence hash")
        require(evidence_heads == {item["head"] for item in history}, "missing historical evidence")
        for item in history:
            bindings = [{"path": e["path"], "sha256": e["sha256"]} for e in row["evidence"] if e["head"] == item["head"]]
            require(item["immutableReceiptBindings"] == bindings and bool(bindings), "historical receipt bindings")
    return {"result": "PASS", "cards": len(seen_cards), "finalCredit": False}


def validate_history(history, base, candidate):
    require(bool(history), "empty history")
    seen = set()
    parent = base["head"]
    for index, item in enumerate(history):
        require(item["head"] not in seen, "duplicate history head")
        seen.add(item["head"])
        require(item["parent"] == parent, "history parent chain")
        require(item["correctionOf"] == ("" if index == 0 else parent), "correction link")
        require(item["state"] in {"FAILED", "SUPERSEDED", "UNVERIFIED", "PROVISIONAL_CHECKPOINTED"}, "history state")
        require(index == len(history) - 1 or item["state"] != "PROVISIONAL_CHECKPOINTED", "premature checkpoint")
        parent = item["head"]
    require({k: history[-1][k] for k in ("head", "tree")} == candidate, "history candidate mapping")
    require(history[-1]["state"] == "PROVISIONAL_CHECKPOINTED", "missing checkpoint")


def self_test(document):
    validate(document)
    mutations = {
        "credit": lambda x: x["credit"].update(finalCredit=True),
        "fake accepted S": lambda x: x["S"].update(head=x["B"]["head"]),
        "unknown field": lambda x: x.update(accepted=True),
        "wrong B": lambda x: x["B"].update(head="0" * 40),
        "duplicate card": lambda x: x["cards"].append(copy.deepcopy(x["cards"][0])),
        "omitted predecessor": lambda x: x["cards"].pop(0),
        "wrong parent": lambda x: x["cards"][0].update(base=x["cards"][0]["candidate"]),
        "wrong tree": lambda x: x["cards"][0]["candidate"].update(tree=x["B"]["tree"]),
        "omitted path": lambda x: x["cards"][0]["changedPaths"].pop(),
        "duplicate path": lambda x: x["cards"][0]["changedPaths"].append(copy.deepcopy(x["cards"][0]["changedPaths"][0])),
        "wrong blob": lambda x: x["cards"][0]["changedPaths"][0]["new"].update(sha256="0" * 64),
        "wrong ownership": lambda x: x["cards"][0]["changedPaths"][0].update(classification="S10_SHARED_RECONCILIATION_REQUIRED"),
        "wrong evidence": lambda x: x["cards"][0]["evidence"][0].update(sha256="0" * 64),
        "premature compatibility": lambda x: x["cards"][0]["reconciliation"].update(compatibility="UNCHANGED_SAFE_REPLAY"),
        "lost history": lambda x: x["cards"][0].update(candidateHistory=[]),
        "wrong historical tree": lambda x: x["cards"][0]["candidateHistory"][0].update(tree="0" * 40),
        "changed correction link": lambda x: x["cards"][0]["candidateHistory"][0].update(correctionOf=x["B"]["head"]),
        "lost historical evidence": lambda x: x["cards"][0].update(evidence=[]),
        "lost receipt binding": lambda x: x["cards"][0]["candidateHistory"][0].update(immutableReceiptBindings=[]),
        "erased historical path": lambda x: x["cards"][0]["candidateHistory"][0].update(changedPaths=[]),
        "invented S evidence": lambda x: x["S"].update(evidence=[]),
        "invented replay": lambda x: x["cards"][0]["reconciliation"].update(replayedCandidate=x["B"]),
        "weakened replay": lambda x: x["policy"].update(wholesaleMergeAllowed=True),
    }
    for name, mutate in mutations.items():
        altered = copy.deepcopy(document)
        mutate(altered)
        try:
            validate(altered)
        except (ValueError, subprocess.CalledProcessError):
            continue
        raise ValueError(f"self-test admitted {name}")
    # Pure contract vectors, not fabricated Git/CI candidates or stored evidence.
    history = [{"head": "a", "tree": "ta", "parent": "base", "correctionOf": "", "state": "FAILED"},
               {"head": "b", "tree": "tb", "parent": "a", "correctionOf": "a", "state": "SUPERSEDED"},
               {"head": "c", "tree": "tc", "parent": "b", "correctionOf": "b", "state": "PROVISIONAL_CHECKPOINTED"}]
    validate_history(history, {"head": "base"}, {"head": "c", "tree": "tc"})
    try:
        validate_history(history[1:], {"head": "base"}, {"head": "c", "tree": "tc"})
    except ValueError:
        pass
    else:
        raise ValueError("self-test admitted erased failed history")
    # Inject a synthetic intermediate Git response; no commit/ref/artifact is created.
    # The final net diff stays valid while an intermediate candidate touches an
    # unfenced file, which must be rejected by the full validator.
    from unittest.mock import patch
    altered = copy.deepcopy(document)
    row = altered["cards"][0]
    first = copy.deepcopy(row["candidateHistory"][0])
    first.update(head="f" * 40, state="FAILED", changedPaths=["unfenced.txt"])
    last = row["candidateHistory"][0]
    last.update(parent=first["head"], correctionOf=first["head"])
    row["candidateHistory"].insert(0, first)
    real_git = git
    def synthetic_git(*args):
        if args == ("rev-parse", first["head"] + "^{tree}"):
            return first["tree"].encode()
        if args[:3] == ("rev-list", "--parents", "-n"):
            if args[-1] == first["head"]:
                return (first["head"] + " " + first["parent"]).encode()
            if args[-1] == last["head"]:
                return (last["head"] + " " + first["head"]).encode()
        if args == ("diff", "--name-only", first["parent"], first["head"]):
            return b"unfenced.txt\n"
        return real_git(*args)
    with patch(__name__ + ".git", side_effect=synthetic_git):
        try:
            validate(altered)
        except ValueError as error:
            require(str(error) == "unfenced historical change", "wrong intermediate-history rejection")
        else:
            raise ValueError("self-test admitted hidden historical change")
    return {"result": "PASS", "goldenReferenceCards": len(document["cards"]), "rejectedCases": list(mutations), "correctionChain": "PASS_WITH_ERASED_FAILURE_REJECTED", "intermediateUnfencedChange": "REJECTED_BY_FULL_VALIDATOR", "nativeCredit": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    document = json.loads(CONTRACT.read_text(encoding="utf-8"))
    print(json.dumps(self_test(document) if args.self_test else validate(document), indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"FAIL: {error}")
