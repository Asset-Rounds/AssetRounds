# Static lifecycle cases — no execution credit

| Actual attempt situation | Gate result | Meaning and separate finish requirement |
| --- | --- | --- |
| Newly observing, zero descriptors | throw | Not terminal. |
| Observing with owned descriptors | throw | Open resources retained; no closing performed. |
| Terminal with at least one recorded open descriptor | throw | Remaining usable resources prevent handoff predicate. |
| Successful observer has returned; terminal, both sets empty | pass resource predicate | Genuine private Factory/publication receipts and nonpoisoned owner still separately required. |
| Refused observer completed cleanup; terminal, both sets empty | pass resource predicate | Does not imply observation success. Positive receipts and nonpoisoned owner must fail where observation/refusal invalidated them. |
| Binding proof failed but owned closes succeeded; terminal, both sets empty | pass resource predicate | Real poisoned operation/source cannot finish based on this check. |
| During last pre-close proof or actual close, final slot already popped | may pass recorded predicate | Not close-return proof. Finish must be after completed calls and positive Factory/publication receipts, outside G/scanning; coordinated Migration guards exclude this reentry. |
| Any uncertain state, including empty open set | throw | Permanent uncertainty state is not terminal. |
| Failed close with retained actual uncertain descriptor | throw | Exact uncertain evidence retained; no retry/inspection/release. |
| Duplicate descriptor integer fenced into uncertainty | throw | No alias adoption, reuse or close authority. |
| Terminal with any retained uncertain descriptor | throw | Both resource arrays must be empty independently of state. |
| Repeated gate call on settled state | same predicate | Read-only, no revival, state transition or effect. |
| External EX/activity/Registry/Coordinator association still held | gate does not inspect it | Only genuine Migration finish owns external association release after its full separate proof. |

All rows are source/lifecycle analysis, not unit/runtime tests. DEBUG/nonDEBUG parse proves syntax only. No new success marker, lifecycle redefinition or test/predicate weakening.
