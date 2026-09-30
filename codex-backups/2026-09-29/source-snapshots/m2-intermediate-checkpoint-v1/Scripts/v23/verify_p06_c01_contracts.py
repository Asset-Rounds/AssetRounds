import argparse
import ast
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import p06_c01_contracts as c

p=argparse.ArgumentParser(); p.add_argument("--complete",action="store_true"); p.add_argument("--json",action="store_true"); a=p.parse_args(); failures=[]
try:
    c.verify_identities(); c.validate_protocol(c.protocol()); c.self_test()
    corpus=c.load(c.CORPUS)
    if corpus != c.corpus() or tuple(case['id'] for case in corpus['cases']) != c.CASES or not corpus.get('syntheticOnly') or corpus.get('realTerminalValidationResult') is not False: raise ValueError('corpus semantics differ')
    hostile = {case['id']: case for case in corpus['cases'] if case['kind'] == 'hostile'}
    expected_hostile = {
        c.CASES[2]: ('malformed shallow organization', 'REJECT_NO_STUDY'),
        c.CASES[3]: ('duplicate local identity', 'REJECT_NO_STUDY'),
        c.CASES[4]: ('backend or customer-data escape', 'REJECT_OUT_OF_SCOPE'),
    }
    if {key: (value['input'], value['expected']) for key, value in hostile.items()} != expected_hostile: raise ValueError('hostile corpus disposition differs')
    if tuple(corpus['forbiddenResults']) != c.FORBIDDEN: raise ValueError('forbidden terminal results differ')
    expected={path:c.pretty(value) for path,value in c.documents().items()}
    for path,data in expected.items():
        if not (c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=data: failures.append('artifact-drift:'+path)
    for path in c.SCRIPTS:
        ast.parse((c.ROOT/path).read_text(encoding='utf-8'))
    n=c.counts()
    if n['changedPathCount'] != len(c.OWNED) or n['missingOwnedPathCount'] or n['unownedChangedPathCount'] or n['s10ReservationOverlapCount']: failures.append('path-fence')
except Exception as exc:
    failures.append('contracts:'+str(exc)); n=c.counts() if 'c' in globals() else {}
result={"cardID":c.CARD,"result":"FAIL_STATIC" if failures else "PASS_STATIC_PROVISIONAL","disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","completeRequested":a.complete,"failures":failures,"counts":n,"authority":c.authority(),"observedCandidate":c.observed_candidate(),"flags":c.FLAGS,"noRealStudy":True,"noProductionPath":True}
print(json.dumps(result,sort_keys=True,indent=2) if a.json else result['result'])
raise SystemExit(bool(failures))
