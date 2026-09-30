# Known Bugs

Only low-severity, non-regressing defects outside the golden path may enter this file.
Codex must read this file before completing a task. A new entry requires explicit owner approval recorded in the task handoff, and the owner must also revise `CURRENT_TASK.md` to allow the exact `docs/execution/KNOWN_BUGS.md` path; approval alone is not write authorization. Codex cannot name itself as decision owner. Every discovered defect still appears in `HANDOFF.md`, including rejected blockers.

## Template

- ID:
- First affected version/build:
- Severity:
- Exact reproduction:
- User impact:
- Workaround:
- Why release is still acceptable:
- Decision owner/date:
- Required revisit version/gate:
- Status:

Never accept a primary-path crash/hang, data loss/corruption, privacy/security
exposure, incorrect payment/entitlement/permission state, blocked navigation,
inaccessible primary action, false completion, or protected CI archive/signing/upload failure.
