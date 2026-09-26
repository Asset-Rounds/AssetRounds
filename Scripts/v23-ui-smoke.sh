#!/bin/bash
set -euo pipefail
test "${NATIVE_SELECTION_ID:?}" = v23-ui-batch-rui1
test "${CI_NATIVE_ACCEPTANCE_CONTRACT:?}" = v23.integration.current-native.v1
test "${CI_RUNNER_PROVIDER:?}:${CI_RUNNER_LABEL:?}" = github:macos-26
test "${CI_TIER:?}:${CI_RUN_UI_SMOKE:?}:${CI_UI_TIMEOUT_SECONDS:?}" = RUI1:true:900
exec python3 Scripts/v23-ui-evidence.py run
