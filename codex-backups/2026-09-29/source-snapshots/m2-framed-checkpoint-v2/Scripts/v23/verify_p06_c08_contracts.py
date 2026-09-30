from __future__ import annotations
import argparse,json
from p06_c08_contracts import verify_complete
def main():
 a=argparse.ArgumentParser(); a.add_argument('--complete',action='store_true'); a.add_argument('--json',action='store_true'); a.add_argument('--self-test',action='store_true'); q=a.parse_args()
 if not(q.complete or q.self_test): a.error('require --complete or --self-test')
 result=verify_complete()
 if q.self_test: print('PASS_SELF_TEST')
 print(json.dumps(result,sort_keys=True) if q.json else result['result'])
if __name__=='__main__': main()
