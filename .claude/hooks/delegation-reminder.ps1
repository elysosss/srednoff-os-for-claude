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
# Deliberately dependency-free: no hook-lib, no external binaries. It cannot fail open the
# way the scanning hooks can, because it decides nothing.
#
# Wire: powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/delegation-reminder.ps1
$ErrorActionPreference = "SilentlyContinue"

$context = @(
  "Delegation check (90-subagent-contract.md). Before doing a multi-step task yourself, ask whether it splits:"
  "- Vetting external sources, licences or documentation -> subagent."
  "- Sweeping many files to answer one question -> Explore subagent."
  "- Drafting N independent artifacts (skills, fixtures, docs) -> one subagent per batch, launched in parallel in a SINGLE message."
  "- Anything serial for more than about five tool calls that has independent halves -> split it."
  "Keep for yourself: precise edits to files under review, git and PR operations, final integration and verification."
  "Contract: give each agent a goal, boundaries, an output format and a line limit; agents write to a scratch directory, not into the repository; every delegated call ends with an explicit disposition (done/blocked/deferred/failed) that you report."
  "Do not delegate what you can finish in one or two tool calls - a cold agent re-derives context you already hold."
) -join "`n"

$out = @{ hookSpecificOutput = @{
  hookEventName    = "UserPromptSubmit"
  additionalContext = $context
} } | ConvertTo-Json -Depth 6 -Compress

Write-Output $out
