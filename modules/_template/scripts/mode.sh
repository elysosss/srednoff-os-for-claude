#!/usr/bin/env bash
# Prints the module mode ("off" when state.json is missing, unreadable or has no mode).
# Shared by every hook of the module: reading the mode is the hook's first action, so a module
# in "off" changes nothing (empty stdout, exit 0). No jq: a hook must not depend on it to stay quiet.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode=""
if [ -f "$here/state.json" ]; then
  mode="$(sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$here/state.json" 2>/dev/null | head -n 1)"
fi
[ -n "$mode" ] || mode="off"
printf '%s\n' "$mode"
