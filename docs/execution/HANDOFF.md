# Task Handoff — append-only log

Never edit or replace an earlier entry. The block between the explicit BEGIN/END markers is an exemplar, not an entry. Copy only the content between the markers (not the markers), replace every placeholder, and append that copy after all prior entries. Never fill or edit the exemplar or an earlier entry.

<!-- BEGIN HANDOFF ENTRY TEMPLATE -->

## `<Task ID>` — `<complete | blocked | stopped — CI NOT RUN>` — `<UTC timestamp>`

- Phase ID / phase branch / card position / phase-boundary card (`yes | no`):
- Program-autopilot state / exact phase-and-branch map / final owner-only boundary:
- Phase-autopilot state / exact authorized same-phase span:
- Predecessor IDs and evidence:
- Outcome:
- Exact build-plan path / SHA-256:
- Exact implementation-runbook path / SHA-256 / selected card:
- Authoring host OS/build:
- GitHub repository / visibility and private-solo branch-control posture / base branch / phase branch:
- Immutable phase-main base SHA `P` and evidence (`S0`: bootstrap `B`; later: prior accepted exact-main phase-close SHA):
- Integrated/card-base SHA `M` and evidence (within phase: prior green implementation; phase start: `P`; `S0.1`: predecessor iOS run N/A):
- Observed task-start authority SHA `A` and `M..A` authority-only diff result:
- Implementation commit SHA (the CI `head_sha`):
- Pre-existing dirty paths and owner/disposition:
- Workflow path / workflow file SHA-256 / trigger / frozen branch ref / actual expected ref-head SHA observed after `I`/`I2` and immediately before dispatch:
- CI selector task ID / tier / `runUISmoke` / workflow input equality result:
- Actions run ID / URL / `head_sha` / conclusion:
- Runner image / Xcode version+build / minimum iOS:
- Project or workspace / target / shared scheme / configuration:
- Simulator selector and actual model / OS / UDID; UI-smoke mode:
- Allowed GitHub/MCP tool methods and exact repository/ref/workflow arguments/operations from task:
- Owner-required posture from task and G0-observed effective sandbox / approval / command-network / trusted-config / GitHub-tool state:
- Card-owned implementation commit / phase-branch push / dispatch / inspection authorizations and actions actually performed:
- Boundary recovery state observed, when applicable (`HANDOFF pending | C on phase only | main=C no run | matching run in progress | main green | next A created`):
- Owned launch-smoke IDs:
- Project/persistent-schema delta actually used:

### Changed paths

-

### Verification

| Command or smoke | Run/job | Timeout | Exit code | Actual duration | Result | Artifact/evidence path and checksum |
|---|---|---:|---:|---:|---|---|
| | | | | | | |

Confirm that the successful run's `head_sha` exactly equals the implementation commit SHA. A stale or different-revision run is not evidence. This entry is not part of that implementation commit. Same-phase autopilot may commit it with only immediate-next CURRENT_TASK. At an authorized boundary it is committed alone before verified fast-forward main integration. The entry never self-records its containing commit or the later main run; the next phase's CURRENT_TASK records the accepted main SHA/run as predecessor evidence.

### Acceptance results

- Golden path `PASS | FAIL | NOT RUN` and checkpoints:
- Named alternate `PASS | FAIL | NOT RUN` and checkpoints:
- Accessibility spot check `PASS | FAIL | N/A—N8 changed no user-facing control | NOT RUN`:
- Exact terminal screen/data artifact `PASS | FAIL | NOT RUN`:
- Future controls verified omitted/inert `PASS | FAIL | NOT RUN`:

### Known bugs or limitations

- Bug ID / severity / disposition, or `NONE`:

### Blockers

-

### Next unstarted task

- Task ID only; it was not started:
- Next gate:
  - Within phase, autopilot enabled and transition flag `yes`: if the immediate next card is inside the exact span and uniquely resolvable, Codex commits/pushes only this HANDOFF append plus that next CURRENT_TASK, then runs fresh G0; a false flag or ambiguity leaves the append uncommitted and stops.
  - Phase boundary: when program autopilot and integration are `yes`, Codex commits/pushes this HANDOFF as C. `main=P` may fast-forward once; `main=C` resumes; any other value stops. Reuse matching C CI before dispatch; after green, create only an absent mapped next branch or resume an exact valid A, then fresh G0. After S9.1, report C/run in the goal final response and stop for owner S9.2/S9.3.

<!-- END HANDOFF ENTRY TEMPLATE -->
