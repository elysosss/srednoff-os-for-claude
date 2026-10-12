#!/usr/bin/env bash
# Template PreToolUse hook. Replace the body of the "on" branch with the module's logic.
# Contract (docs/specs/E1-module-format.md): first action is reading the mode; off, a missing
# or a broken state file -> exit 0 with empty stdout. Failing closed must be implemented here
# (own timeout + explicit deny), Claude Code treats a hook timeout or crash as fail-open.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="$(bash "$here/scripts/mode.sh" 2>/dev/null)"
[ -n "$mode" ] || mode="off"
[ "$mode" = "off" ] && exit 0

payload="$(cat)"
tool="$(printf '%s' "$payload" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
state_dir="$here/../.state/$(basename "$here")"
mkdir -p "$state_dir" 2>/dev/null || exit 0
printf '%s\t%s\n' "$mode" "${tool:-unknown}" >> "$state_dir/calls.log" 2>/dev/null
exit 0
