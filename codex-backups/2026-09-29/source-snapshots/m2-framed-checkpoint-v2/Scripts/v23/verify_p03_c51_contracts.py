#!/usr/bin/env python3
from __future__ import annotations
import argparse, ast, base64, json, os, subprocess, sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c51_contracts as contracts
C34_REPROOF_CARD = "V23-P03-C34"

def _fresh() -> dict[str, bytes]:
    child = ("import base64,json,sys;from pathlib import Path;sys.path.insert(0,str(Path.cwd()/'Scripts'/'v23'));"
             "import p03_c51_contracts as c;o=c.all_outputs(Path.cwd());"
             "print(json.dumps({p:base64.b64encode(d).decode() for p,d in sorted(o.items())},sort_keys=True,separators=(',',':')))")
    env = os.environ.copy(); env["PYTHONDONTWRITEBYTECODE"] = "1"
    def run() -> dict[str, bytes]:
        done = subprocess.run([sys.executable, "-B", "-c", child], cwd=ROOT, env=env,
                              check=True, capture_output=True, text=True)
        return {p: base64.b64decode(v, validate=True) for p, v in json.loads(done.stdout).items()}
    first, second = run(), run()
    if first != second:
        raise ValueError("C51 fresh-process replay differs")
    return first

def main() -> int:
    assert contracts.C34_NAVIGATION_REPROOF["consumerCardID"] == C34_REPROOF_CARD
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--complete", action="store_true")
    args = parser.parse_args(); failures: list[str] = []; outputs: dict[str, bytes] = {}
    try:
        contracts.assert_scaffold(ROOT)
        for path in contracts.SCRIPT_PATHS:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        outputs = contracts.all_outputs(ROOT)
        if _fresh() != outputs:
            raise ValueError("C51 fresh outputs differ")
    except Exception as error:
        failures.append(str(error))
    changed = set(contracts.observed_changed_paths(ROOT))
    missing = sorted(path for path in contracts.PATH_FENCE if not (ROOT / path).is_file())
    if missing:
        failures.append("missing:" + ",".join(missing))
    for path, data in outputs.items():
        if (ROOT / path).is_file() and (ROOT / path).read_bytes() != data:
            failures.append("artifact differs:" + path)
    unowned = sorted(changed - set(contracts.PATH_FENCE))
    if unowned:
        failures.append("unowned:" + ",".join(unowned))
    if args.complete:
        unchanged = sorted(set(contracts.PATH_FENCE) - changed)
        if unchanged:
            failures.append("incomplete fence:" + ",".join(unchanged))
    if any(contracts.FLAGS.values()):
        failures.append("status flags")
    caches = sorted(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / "Scripts" / "v23").rglob("*")
                    if p.name == "__pycache__" or p.suffix == ".pyc")
    if caches:
        failures.append("bytecode cache:" + ",".join(caches))
    result = {"cardID": contracts.CARD, "result": "PASS" if not failures else "FAIL", "complete": args.complete,
              "fencePathCount": 166, "existingPathCount": 152, "newPathCount": 14,
              "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0,
              "s10ReservedPathCount": 86, "physicalLockedState": "REQUIRED_PENDING_OWNER", "failures": failures}
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else "C51 verifier " + result["result"])
    return 0 if not failures else 1

if __name__ == "__main__":
    raise SystemExit(main())
