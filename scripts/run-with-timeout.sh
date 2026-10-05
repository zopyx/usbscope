#!/usr/bin/env bash
# Portable command timeout for macOS and Linux CI runners.
# Usage: run_with_timeout SECONDS COMMAND [ARGS...]
run_with_timeout() {
    local seconds="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$seconds" "$@"
        return $?
    fi

    "$@" &
    local child=$!
    (
        sleep "$seconds"
        kill -TERM "$child" 2>/dev/null || exit 0
        sleep 1
        kill -KILL "$child" 2>/dev/null || true
    ) &
    local watchdog=$!
    local status
    set +e
    wait "$child"
    status=$?
    set -e
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return "$status"
}
