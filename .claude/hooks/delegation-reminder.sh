#!/usr/bin/env bash
# UserPromptSubmit hook - inject the delegation checklist from 90-subagent-contract.md into
# context on every prompt.
#
# Why a hook and not a line in a rule: the rule states the CONTRACT for a delegated call
# (goal, boundaries, output limit, final disposition) - it does not say when delegating is
# the right move at all, and a one-time instruction at session start is exactly the passive
# signal that 70-skills-registry.md documents as unreliable. This does not force anything
# either - only a PreToolUse hook can deny - but the prompt arrives with the triggers in
# view rather than 40 messages back.
#
# Deliberately dependency-free: no jq, no grep -P, no hook-lib. It cannot fail open the way
# the scanning hooks can, because it decides nothing.
#
# Wire: bash .claude/hooks/delegation-reminder.sh
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Delegation check (90-subagent-contract.md). Before doing a multi-step task yourself, ask whether it splits:\n- Vetting external sources, licences or documentation -> subagent.\n- Sweeping many files to answer one question -> Explore subagent.\n- Drafting N independent artifacts (skills, fixtures, docs) -> one subagent per batch, launched in parallel in a SINGLE message.\n- Anything serial for more than about five tool calls that has independent halves -> split it.\nKeep for yourself: precise edits to files under review, git and PR operations, final integration and verification.\nContract: give each agent a goal, boundaries, an output format and a line limit; agents write to a scratch directory, not into the repository; every delegated call ends with an explicit disposition (done/blocked/deferred/failed) that you report.\nDo not delegate what you can finish in one or two tool calls - a cold agent re-derives context you already hold."}}
JSON
