# This fork

`elysosss/srednoff-os-for-claude` is a fork of
[`srednoff888-art/srednoff-os-for-claude`](https://github.com/srednoff888-art/srednoff-os-for-claude).
SREDNOFF OS is upstream's work; the attribution in `README.md`, `LICENSE` and
`.claude-plugin/` is theirs and is left alone deliberately.

This file exists because a fork that silently diverges becomes unmaintainable. Everything
we change on purpose is listed here, so the next sync can tell a deliberate divergence
from drift.

## Install from here, not from upstream

Our machines run **this** fork. It carries fixes that upstream has not taken yet, so
installing from upstream is a downgrade:

```
/plugin marketplace add elysosss/srednoff-os-for-claude
/plugin install srednoff-os
```

That command in `README.md` and `README.ru.md` is repointed at this fork — the only edit
to those two files. It will conflict on every upstream sync; keep **our** side.

The checkout at `~/.claude/templates/claude-md-os` already has `origin` = this fork and
`upstream` = the original, and `~/.claude/registry` is a symlink into it. So a local
`git pull` already takes from us. The repointed command matters for a fresh install on a
new machine, which is the case that would otherwise silently get upstream's version.

## What we changed, and why

| Change | Why it is ours |
|---|---|
| `/plugin marketplace add` points at this fork | See above. Fork-local by nature — never propose upstream. |
| Anything else | Should be **upstream first.** |

## The rule for new work

A fix that would help anyone using SREDNOFF OS goes **upstream as a PR**, not into a
private divergence. We keep it on a branch here only until upstream takes it. Only
things that are true *because we are a fork* — the install source above — stay local
permanently.

`/home/adminn/dev/OS-CONTRIB-PROPOSAL.md` holds the current, evidence-checked list of
what is worth sending upstream and what was investigated and rejected.

## Things not to "tidy"

- **Upstream's authorship.** The `LICENSE` copyright, the `owner` block in
  `.claude-plugin/marketplace.json`, and the "Made by" line in both READMEs are upstream's
  credit for upstream's work. They stay.
- **The `~/.claude/registry` symlink.** Rules `70`/`80` read `~/.claude/registry/CORE-300.md`,
  a path the installer does not create. The symlink into this checkout is what makes skill
  selection work at all; without it, selection degrades silently.
