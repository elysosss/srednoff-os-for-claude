# This fork

`elysosss/srednoff-os-for-claude` is a fork of
[`srednoff888-art/srednoff-os-for-claude`](https://github.com/srednoff888-art/srednoff-os-for-claude).
SREDNOFF OS is upstream's work; the attribution in `README.md`, `LICENSE` and
`.claude-plugin/` is theirs and is left alone deliberately.

This file exists because a fork that silently diverges becomes unmaintainable. Everything
we change on purpose is listed here, so the next sync can tell a deliberate divergence
from drift.

## Current divergence: `docs/specs/` (planning only)

Apart from this file, the fork differs from upstream by one directory: `docs/specs/`, the
specs for the OS extensions (module format, secrets filter, doctor, probes, executors, ...),
added 2026-09-27. They are design documents, not code, and they live here because each one
is tracked by an issue in this fork. Implementation goes upstream as ordinary PRs, one spec
at a time; a PR links its spec rather than carrying it. When upstream wants the specs
themselves, they move over and this divergence is retired. Nothing under `docs/specs/` is
loaded into a Claude Code session or read by any script.

The old divergence, retired on 2026-09-13, is recorded below.

### Retired: the marketplace repoint

The fork started out repointing the
`/plugin marketplace add` command in both READMEs at this fork, on the stated grounds that
"it carries fixes that upstream has not taken yet, so installing from upstream is a
downgrade". **That reason has lapsed**: upstream merged all seven of our fixes on
2026-09-13 (#8-#14), so upstream is now the more complete of the two, and a fresh install
from this fork would be the downgrade. The command has been pointed back at upstream and
the divergence retired.

Keeping a divergence whose justification has evaporated is exactly the drift this file was
created to prevent.

## The rule for new work

A fix that would help anyone using SREDNOFF OS goes **upstream as a PR**, not into a
private divergence. Keep it on a branch here only until upstream takes it.

Working branches live in this fork and are opened as PRs against upstream. Merged so far:
`fix/bash-hooks-pcre-fail-open`, `fix/routing-pcre-locale-degradation`,
`fix/protect-secrets-multiedit-coverage`, `fix/hook-path-false-positives`,
`fix/dangerous-bash-coverage`, `fix/catalog-json-check-crlf`,
`docs/skill-count-and-release-drift` (2026-09-13); `feat/detect-python-devops-projects`,
`feat/python-devops-skills`, `feat/discovery-catalog-and-no-ai-slop`,
`feat/observation-log`, `feat/delegation-reminder-hook` (2026-09-15).

## Things not to "tidy"

- **Upstream's authorship.** The `LICENSE` copyright, the `owner` block in
  `.claude-plugin/marketplace.json`, and the "Made by" line in both READMEs are upstream's
  credit for upstream's work. They stay.
- **The `~/.claude/registry` symlink** (on a machine where the OS is installed globally).
  Rules `70`/`80` read `~/.claude/registry/CORE-300.md`, a path the installer does not
  create. Without it, skill selection degrades silently.
