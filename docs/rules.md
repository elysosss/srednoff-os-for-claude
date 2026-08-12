# The `.claude/rules/` directory

This file documents the rules directory; it deliberately lives in `docs/` rather than inside
`.claude/rules/`. Every `.md` file in that directory without a `paths:` field is loaded into
context on every session and inside every subagent - including a README - so documentation
about the rules would be paid for on every request, forever, to say something a maintainer
reads once.

Ten numbered files, always loaded every session (`00`-`90`), read as a set, not as
separate opt-in modules:

| File | Covers |
|---|---|
| `00-operating-system.md` | Principle #1, top-level operating stance |
| `10-github-research.md` | When/how to research GitHub before adopting external code |
| `20-connectors.md` | Connector/MCP usage stance |
| `30-user-briefing.md` | How to read and confirm task intent |
| `40-quality-gate.md` | Validation expectations before calling work done |
| `50-security.md` | Secret/destructive-action handling, swarm confirmation |
| `60-exec-plans.md` | Plan structure, failure-lifecycle for delegated work |
| `70-skills-registry.md` | PROFILE.lock, CORE-300 selection, quality modes, verification gate |
| `80-model-routing.md` | Haiku/Sonnet/Opus routing by required quality |
| `90-subagent-contract.md` | Final-disposition contract for delegated Agent/Task calls |

None of these ten carry a `paths:` frontmatter field. That is deliberate: they are
cross-cutting (security, model routing, skill selection) and must stay active regardless
of which file is being touched.

## What is loaded, and what only costs tokens when read

`CLAUDE.md` and `.claude/rules/*` are the always-loaded layer: a procedure written in both
places is paid for twice on every request, so each procedure belongs in exactly one of them,
and new guidance goes into the rule rather than into `CLAUDE.md`.

`.agent/*` is **not** loaded into context. Rules `10/20/30/40/60` each point at a longer
version of themselves under `.agent/` - that pairing is not context duplication, and
collapsing it saves nothing at session start. Those files cost tokens only when something
actually reads them.

## Path-scoped rules (native Claude Code feature)

`.claude/rules/*.md` files support an optional YAML frontmatter `paths:` field with glob
patterns. A rule with `paths:` only loads into context when Claude is working with a file
matching one of those globs - useful for a project-specific convention that would be noise
everywhere else in the repo.

```markdown
---
paths:
  - "src/api/**"
---

# API handler conventions

All handlers in this directory must validate input with Zod before doing anything else.
```

Add project-specific scoped rules as additional numbered (or unnumbered) files in
`.claude/rules/` - `init-claude-project.ps1`/`.sh` will not overwrite files it did not create.
Keep the shared core (`00`-`90` above) path-agnostic; scope only the rules you add on top
of them for a specific project's directory structure.
