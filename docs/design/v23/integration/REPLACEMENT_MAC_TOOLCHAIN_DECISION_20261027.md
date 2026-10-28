# Decision 53 — replacement Mac macOS 27.2 / Xcode 27.1 compatibility

Owner-authorized October 27, 2026, relayed by receiving chat Asset Rounds Merge: “tell him to update what is needed to update merge gates or policy to make sure 27.2 works and xcode 27.1”. This authorizes compatibility work, not failed-test waivers, claimed runtime success, source-language/deployment-target changes or release. Native app builds/tests remain paused until the owner resumes them.

## Local setup and diagnostics

The replacement Mac may use stable macOS 27.2 and stable Xcode 27.1, with actual OS/build, Xcode/build, Swift compiler, SDK/build and simulator version/build recorded before execution. Published Xcode 27.1 build is 27A9275; confirm the installed binary. Keep existing Swift language mode and deployment targets. Prefer an available supported iPhone 17 runtime; iOS 27.0 is the compatibility candidate, not an observed local installation. The hosted image inventory lists iPhone 17 on iOS 27.0 and only iPhone Duo on iOS 27.1. Never request iPhone 17/iOS 27.1 blindly. Record actual supported device/runtime pairing with simctl after installation; no runtime build is invented here.

No local installation of Xcode 26.6 is required merely to reproduce the hosted gate pin. Use existing simplified DEVELOPMENT diagnostics and job-specific reviewed budgets after resumption. This decision itself does not qualify a compiler result or old Products, authorize a new ordinary hosted original, or discharge pending compilation/full coverage.

Before beginning an in-place macOS upgrade, confirm that fresh unique recovery records, patch bindings and work have been preserved in Dropbox. Keep original source, drafts, archives and histories intact; no erase/reformat or automatic Xcode project migration. Owner handles account sign-in, license acceptance, password and restart. OS upgrade is intended to retain files, not a guarantee against failure. Inspect the new environment and allocate isolated outputs afterward.

## Prospective hosted gate successor — authorized, not active yet

Root may implement and independently qualify an exact GitHub Xcode 27.1 successor across runner, dispatcher, validator, manifest and affected tests. Current implementation still pins Xcode 26.6/iOS26.2(23C54); those pins remain authoritative until the successor passes its required checks and cold qualification. Local macOS27.2 does not require the hosted OS to be27.2: hosted OS/image must be Apple-compatible and recorded exactly. GitHub's published current macOS27 image reports macOS27.0.1 and Xcode27.1/27A9275, with iPhone17/iOS27.0 available; this is availability evidence, not an executed qualification.

Before activating a successor, record actual exact Xcode/SDK/runtime builds, device, architecture and observed runner image; bind the expected toolchain to a checked-in manifest and reject drift in toolchain/runtime. Record and review runner image changes; GitHub labels alone do not immutably pin an image. Require complete app/test compilation and the existing cold payload-binding, safe-extraction, no-rebuild, complete-census and per-partition proofs. Run current affected CI/internal tooling checks and independent review. Keep old validators available for old evidence; do not globally relabel historical lanes or replace raw pins without their existing tests and provenance. A missing runtime/SDK build or execution kind blocks activation. Do not silently downgrade, switch device, or accept local results as hosted gates.

Gate 1 retains complete same-head coverage and all required passing methods, with only decision46's separately accepted exact named Phase1 exceptions. Gate 2 retains qualified critical-state UI evidence and existing budgets on the admitted successor. Gates 3 and4 retain independent integration review and genuine human owner review. Gate5 retains non-force main fast-forward and exact-main verification on that same admitted successor. All evidence binds to the frozen candidate; future exact-main remains due. No automatic screenshot/test rebaseline.

Decision24 remains limited to Phase1 functional DEBUG Simulator gates and their exact-main verification. Simulator protection remains unsupported; physical protection remains UNVERIFIED/DEFERRED and release-blocking. This amendment does not extend that exception beyond its existing scope.

All original/sole-collector/retention rules remain. Preserve consumed questions, failures, partials, HOLDs and ledgers. Toolchain-only changes do not erase failed tests or manufacture an ordinary retry; separate diagnostics retain existing retry authority and finite purposes. Mandatory full DEVELOPMENT coverage, all five gates, full V23/S10 scope and releaseReady=false remain. No signing, distribution, paid settings, PR, force-push or history rewrite.

## Current completion and remaining work

Policy supports the requested local OS/Xcode setup now. Native compatibility/compile behavior is UNVERIFIED until owner resumption and actual execution. Hosted executable migration/qualification is PENDING; no workflow, runner or validator pin is switched by this document. Exact new simulator and SDK builds still require observation. These pending hosted changes do not block authorized local setup or later isolated diagnostics.

Sources checked October27: https://support.apple.com/en-us/109033 ; https://apps.apple.com/us/app/xcode/id497799835 ; https://developer.apple.com/xcode/system-requirements ; https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md . Stable Xcode27.1 is distinct from27.2 RC. Source proposal and independent review remain preserved separately.
