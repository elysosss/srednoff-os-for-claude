---
name: writing-for-agents
description: Use this skill when creating or editing a document an agent will read - a skill, a CLAUDE.md or AGENTS.md, a rule file, or any doc reached through a pointer. Covers pointer wording, what goes in the file versus behind a pointer, completion criteria and pruning; do not use for documentation written for humans.
---

# Writing for Agents

Adapted from mattpocock/skills `writing-for-agents` and its `SKILL-MECHANICS.md` (MIT, see `registry/INSTALL-SOURCES.md`). Condensed and merged into one page.

The packaging differs between a skill, a `CLAUDE.md` and a linked doc; the writing does not. The aim is a document that makes the agent follow the same *process* every run.

## Context pointers

A **context pointer** is a line held in the agent's context that names out-of-context material and the condition for reaching it: a skill description, or a line in `CLAUDE.md` naming a doc. The pointer's wording, not its target, decides when and how reliably the material is reached.

- State what the material is and list the distinct **branches** that should trigger reaching it. Synonyms for one branch are one branch written twice - collapse them.
- Front-load the leading word; cut identity the body already carries.
- A must-have target behind a weak pointer is a variance bug: sharpen the wording first, inline the material only if that fails.
- Always-loaded pointers cost tokens on every turn, so prune them harder than bodies.

## Two budgets

- **Context load**: tokens and attention spent by always-loaded text, whether or not it fires.
- **Cognitive load**: what the human must remember exists. Spend it where human judgement matters.

Material behind a pointer escapes context load at the price of the pointer line; material with no pointer rides on cognitive load.

## Information hierarchy

Split content into **steps** (ordered actions) and **reference** (definitions, rules, facts consulted on demand), then place each piece on a ladder:

1. In-file steps - what the agent does, in order.
2. In-file reference - consulted on demand; a flat set of rules is fine.
3. Disclosed reference - a separate file reached by a pointer, loaded only when it fires.

Inline what every branch needs; push behind a pointer what only some branches reach. Reference left in the main file buries the steps and turns attending to them into a coin flip. Keep a concept's definition, rules and caveats under one heading (co-location). A document that is simply too long is **sprawl**: disclose reference behind pointers and split by branch or sequence.

## Steps and completion criteria

Every step ends on a **completion criterion**. Two properties matter:

- **Clarity**: can the agent tell done from not done? A vague bound ("understanding reached") invites ending the step early. Sharpen the bound first; hide later steps by splitting the sequence only if the bound stays fuzzy *and* rushing is observed - hiding works only across a real context boundary (a handoff or a subagent).
- **Demand**: how much it requires. "Every modified model accounted for" forces more work than "produce a change list".

The strongest criteria are checkable and exhaustive.

## Skill mechanics

- A **model-invoked** skill has a `description` that carries the trigger branches; it costs permanent context load and buys discoverability, including by other skills.
- A **user-invoked** skill sets `disable-model-invocation: true`; its description is a short human-facing line. No context load, but the human is the index. Pick model invocation only when the agent, or another skill, must reach it on its own.
- Reference needed by several skills belongs in one model-invoked reference skill, or a plain file outside the skill system when the skills are user-invoked.
- When user-invoked skills multiply, add a **router skill**: one user-invoked skill naming the others and when to use each. It can only hint.
- Split by sequence when later steps tempt the agent to rush the current one; split by invocation when a distinct trigger word should fire a piece on its own.

## Wording

- **Leading words**: one compact concept the model already knows (tight, red, tracer bullet) repeated as a token replaces a sentence spelled out at several sites. A made-up word recruits no priors; prefer an existing one.
- **Prompt the positive**: a prohibition drags the banned behaviour into context. State the target behaviour; keep a bare ban only as a hard guardrail that cannot be phrased positively, and pair it with the target.

## Pruning

- One meaning, one place. Duplication costs tokens and inflates a rule's prominence.
- The environment is a source of truth (`package.json` scripts, config, `--help`). A document that restates it is a cache - keep only what the agent cannot find by looking: the unwritten convention, the reason behind a choice, the gotcha.
- Check each line for relevance; stale lines settle as sediment because adding feels safe and removing feels risky.
- Hunt no-ops: an instruction the model already follows by default pays load to say nothing. Test against the model, not the reader; delete the whole sentence when it fails.

## Guardrails

- Rules in this repository live once: change `.claude/rules/*`, not a copy in `CLAUDE.md` (see the DEDUPED note there).
- Do not let a rewrite drop a hard safety rule (`50-security.md`) in the name of brevity.
