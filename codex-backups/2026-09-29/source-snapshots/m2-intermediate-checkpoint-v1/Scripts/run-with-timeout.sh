#!/bin/bash

set -u

if [ "$#" -lt 2 ] || ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
  printf 'usage: %s <positive-seconds> <command> [args...]\n' "$0" >&2
  exit 64
fi

timeout_seconds="$1"
shift

state_dir="$(mktemp -d "${TMPDIR:-/tmp}/field-evidence-timeout.XXXXXX")"
timeout_marker="$state_dir/timed-out"
child_pid=''
watchdog_pid=''

relay_termination() {
  if [ -n "$child_pid" ]; then
    kill -TERM -- "-$child_pid" 2>/dev/null || true
  fi
}

cleanup() {
  if [ -n "$watchdog_pid" ]; then
    kill -TERM -- "-$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  rm -rf -- "$state_dir"
}

trap relay_termination HUP INT TERM

set -m
"$@" &
child_pid="$!"
set +m

set -m
(
  sleep "$timeout_seconds"
  : > "$timeout_marker"
  kill -TERM -- "-$child_pid" 2>/dev/null || exit 0

  elapsed=0
  while kill -0 -- "-$child_pid" 2>/dev/null && [ "$elapsed" -lt 5 ]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if kill -0 -- "-$child_pid" 2>/dev/null; then
    kill -KILL -- "-$child_pid" 2>/dev/null || true
  fi
) &
watchdog_pid="$!"
set +m

wait "$child_pid"
child_status="$?"

if [ -e "$timeout_marker" ]; then
  wait "$watchdog_pid" 2>/dev/null || true
  watchdog_pid=''
  exit_status=124
else
  kill -TERM -- "-$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  watchdog_pid=''
  exit_status="$child_status"
fi

cleanup
trap - HUP INT TERM
exit "$exit_status"
