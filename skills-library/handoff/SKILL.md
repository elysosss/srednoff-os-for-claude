---
name: handoff
description: Use this skill when the user asks to hand the current work over to a fresh agent or session - "handoff", "write a handoff", "continue this in a new chat". Produces a short handoff document outside the workspace; do not use for project documentation or ADRs.
---

# Handoff

Adapted from mattpocock/skills `handoff` (MIT, see `registry/INSTALL-SOURCES.md`).

Use this skill when the current session must end but the work continues elsewhere. The output is one short document a fresh agent can start from.

## Workflow

1. Read the conversation for what matters to the next agent: the goal, the current state, decisions already made and why, what failed, and the next concrete step.
2. If the user passed a focus ("what will the next session be used for?"), tailor the document to it and drop the rest.
3. Link instead of copying: specs, plans, ExecPlans, ADRs, issues, PRs, commits and diffs are referenced by path or URL, never re-explained.
4. Add a **Suggested skills** section naming the skills the next agent should call through the Skill tool, and any rule files it must read first (for example `.claude/PROFILE.lock.md`).
5. Redact secrets and personal data before writing: API keys, tokens, passwords, cookies, private keys, personal identifiers. Write `<REDACTED>` in their place.
6. Save the document in the OS temporary directory (`$TMPDIR`, else `/tmp`; `%TEMP%` on Windows), not in the workspace, so it is never committed by accident. Tell the user the full path.

## Document shape

- **Goal** - one or two sentences.
- **State** - done, in progress, blocked; each with a path or link.
- **Decisions** - what was chosen and the reason, one line each.
- **Next step** - one concrete action the next agent can run first.
- **Suggested skills / files to read first.**

## Guardrails

- A handoff is a summary, not a transcript: keep it to roughly one page.
- Do not invent state. If something is unknown or unverified, say so in the document.
- If the user wants the handoff kept in the repository (for example an owner-maintained `HANDOFF.md`), update that file instead of creating a second source of truth.
