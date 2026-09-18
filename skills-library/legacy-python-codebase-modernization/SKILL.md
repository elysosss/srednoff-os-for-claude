---
name: legacy-python-codebase-modernization
description: "Use this skill to modernize an aging Python codebase in stages - raising the minimum interpreter version, replacing abandoned dependencies, introducing typing and linting on a ratchet, and retiring dead code with evidence. Trigger when the task involves programming work related to Legacy Python Codebase Modernization, implementation, audits, debugging, strategy, or validation."
---

# Legacy Python Codebase Modernization

Use this skill for Programming tasks focused on sequencing an upgrade of an old Python project so that every step ships independently. For reading unfamiliar code before changing it use `codebase-archaeologist-agent`; for behavior-preserving code shape work use `refactoring-coach-agent`.

## Workflow

1. Clarify the driver and the endpoint: an end-of-life interpreter, a security advisory, hiring pain, or a blocked feature - each implies a different stopping point.
2. Inventory the current state before planning: interpreter version, dependency ages and maintenance status, test coverage on the critical paths, CI reality, and which modules actually run in production.
3. Check official upgrade notes - the interpreter changelog for removed APIs and behavior changes, and each major dependency for its own migration guide.
4. Establish a safety net first: get the existing test suite green and add characterization tests around the paths you cannot afford to break.
5. Sequence in small shippable steps - interpreter version, then dependency upgrades one at a time, then tooling on a ratchet, then typing, then dead-code removal - each with its own release and rollback.
6. Validate each step independently with tests, linting, type checks, and a staged rollout before starting the next one.
7. Report what moved, what is deliberately left behind, the remaining risks, and the exact next step.

## Focus Checklist

- Upgrade the interpreter before the libraries where possible, so dependency versions can be chosen against the final target.
- Apply new tooling as a ratchet: enforce on changed files or per-package first, never as one repo-wide reformat mixed with behavior changes.
- Keep mechanical rewrites in separate commits from behavior changes, so review and bisect stay usable.
- Prove code is dead before deleting it - import graph, coverage from a real run, and production telemetry - rather than assuming from naming.
- Re-check pinned transitive dependencies for known advisories while versions are moving anyway.
- Write down what was intentionally not modernized and why, so the next contributor does not re-litigate it.

## Guardrails

- Do not mix a version upgrade, a reformat, and a refactor in one change set.
- Do not delete code, endpoints, or database columns that still have live usage, and confirm removals with the user before shipping them.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data - old codebases often hold credentials in tracked files.
- If validation is impossible, state why and provide a concrete manual verification path.
