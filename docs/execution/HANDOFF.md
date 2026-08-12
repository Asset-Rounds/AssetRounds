# Task Handoff — append-only log

Never edit or replace an earlier entry. The block between the explicit BEGIN/END markers is an exemplar, not an entry. Copy only the content between the markers (not the markers), replace every placeholder, and append that copy after all prior entries. Never fill or edit the exemplar or an earlier entry.

<!-- BEGIN HANDOFF ENTRY TEMPLATE -->

## `<Task ID>` — `<complete | blocked | stopped — CI NOT RUN>` — `<UTC timestamp>`

- Phase ID / phase branch / card position / phase-boundary card (`yes | no`):
- Predecessor IDs and evidence:
- Outcome:
- Exact build-plan path / SHA-256:
- Exact implementation-runbook path / SHA-256 / selected card:
- Authoring host OS/build:
- GitHub repository / visibility and private-solo branch-control posture / base branch / phase branch:
- Integrated/base SHA `M` and evidence (within phase: prior green implementation; phase start: green `main`; `S0.1`: bootstrap `B` and predecessor iOS run N/A):
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
- Owned launch-smoke IDs:
- Project/persistent-schema delta actually used:

### Changed paths

-

### Verification

| Command or smoke | Run/job | Timeout | Exit code | Actual duration | Result | Artifact/evidence path and checksum |
|---|---|---:|---:|---:|---|---|
| | | | | | | |

Confirm that the successful run's `head_sha` exactly equals the implementation commit SHA. A stale or different-revision run is not evidence. This appended entry is not part of that implementation commit. Within a phase, the owner later commits this entry together with the next hydrated CURRENT_TASK as the next authority-preparation commit; at a phase boundary, the owner commits it alone as phase-close bookkeeping before merge. This entry never tries to record the future commit SHA that will contain itself: the next G0 observes its authority SHA, while git history records a phase-close SHA.

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
- Owner next gate:
  - Within phase: review; commit only this prior HANDOFF append plus the next hydrated CURRENT_TASK on the same phase branch; no main merge or iOS rerun; next card uses this card's green implementation SHA as `M`.
  - Phase boundary: commit this HANDOFF append alone; owner merges the phase branch; under the private-solo rule, owner alone verifies `refs/heads/main` points to the expected merge SHA, permits no intervening push/history rewrite, dispatches the `main` ref with `run_ui_smoke=true`, and requires a green matching `head_sha`; unexpected ref movement stops; start the next phase branch from that SHA.

<!-- END HANDOFF ENTRY TEMPLATE -->
