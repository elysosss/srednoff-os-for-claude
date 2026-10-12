# This fork

`elysosss/srednoff-os-for-claude` is a fork of
[`srednoff888-art/srednoff-os-for-claude`](https://github.com/srednoff888-art/srednoff-os-for-claude).
SREDNOFF OS is upstream's work; the attribution in `README.md`, `LICENSE` and
`.claude-plugin/` is theirs and is left alone deliberately.

This file exists because a fork that silently diverges becomes unmaintainable. It says
what the fork is for, how its branches work, and which divergences are on purpose, so the
next sync can tell a deliberate divergence from drift.

Start-here for whoever continues the work (any machine): [`docs/fork/README.md`](docs/fork/README.md).
Every owner decision is logged in [`docs/fork/DECISIONS.md`](docs/fork/DECISIONS.md).

## What this fork is (since 2026-10-12)

**A programmer-focused distribution of SREDNOFF OS.** Upstream is built "for everything"
(marketing, SEO, business and engineering alike); this fork's `main` is the owner's working
build: upstream plus modules and tooling for software development - the extension specs in
`docs/specs/` (module format, secrets filter, executors, doctor and probes, the agent-dev
playbook D1-D10). The OS is installed into the owner's projects from this fork's `main`,
per project folder only.

This replaces the earlier rule "everything goes upstream as a PR" (until 2026-10-12).

## How the branches work

| What | Branch | Rule |
|---|---|---|
| Working build | `main` (this fork) | upstream + fork work; projects install from here |
| Upstream sync | `main` ← `upstream/main` | **merge**, never rebase; after each new upstream merge, as its own commit |
| Fork work | `feat/<id>-...` from **`main`** | PR into **this fork**, fork CI green, merge |
| Contribution | `up/<topic>` from **`upstream/main`** | self-contained changes only; PR to upstream; reaches `main` via the next sync (or a cherry-pick if upstream is slow) |

What goes upstream: things useful to any SREDNOFF OS user - bugs in the OS itself and
improvements that do not depend on fork code. Issues carry the label
`upstream-candidate`. Everything programmer-specific stays here, label `fork-only`.

To keep syncs and cherry-picks cheap:
- fork code lives in **new** files and directories (`modules/`, `docs/specs/`,
  `docs/fork/`, `scripts/os-module.*`); edits to upstream files are minimal and in
  commits of their own;
- a commit is either an upstream candidate or fork-only, never both.

## Versioning

The fork's build version is in [`FORK-VERSION`](FORK-VERSION):
`v<upstream version>+elysosss.<N>`. `registry/version.json` is upstream's and is not
edited here, so syncs do not conflict on it. Bump `N` on every significant merge into
`main`.

## Current deliberate divergence

- `FORK.md`, `FORK-VERSION` - this file and the build version.
- `docs/fork/` - plan, state, decision log, history (not deployed into projects;
  `init-claude-project` ships an allow-list that excludes `docs/`).
- `docs/specs/` - specs for the fork's extensions, each tracked by an issue in this fork.
- Implemented fork modules will be listed here as they land.

### Retired: the marketplace repoint (2026-09-13)

The fork started out repointing the `/plugin marketplace add` command in both READMEs at
this fork, on the grounds that it carried fixes upstream had not taken yet. Upstream merged
them all, so the repoint was reverted. Keeping a divergence whose justification has
evaporated is exactly the drift this file exists to prevent.

## Contributed upstream so far

All merged: #4-#7 (2026-09-08), #8-#14 (2026-09-13), #15-#19 (2026-09-15), #20
(2026-09-28). Branches: `fix/init-never-clobbers-real-files`, `fix/bash-hooks-pcre-fail-open`,
`fix/routing-pcre-locale-degradation`, `fix/protect-secrets-multiedit-coverage`,
`fix/hook-path-false-positives`, `fix/dangerous-bash-coverage`, `fix/catalog-json-check-crlf`,
`docs/skill-count-and-release-drift`, `feat/detect-python-devops-projects`,
`feat/python-devops-skills`, `feat/discovery-catalog-and-no-ai-slop`,
`feat/observation-log`, `feat/delegation-reminder-hook`, `fix/ci-profile-tags-tox`.

## Things not to "tidy"

- **Upstream's authorship.** The `LICENSE` copyright, the `owner` block in
  `.claude-plugin/marketplace.json`, and the "Made by" line in both READMEs are upstream's
  credit for upstream's work. They stay.
- **No global install.** The OS is installed per project folder only; nothing is written to
  `~/.claude/{CLAUDE.md,code_review.md,templates,registry}` on the owner's machines. Checks
  that expect that layout run against a temporary HOME (see `docs/fork/README.md`).
