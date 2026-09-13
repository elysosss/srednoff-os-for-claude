---
name: python-typing-and-mypy-strictness
description: "Use this skill for Python type hints, generics, Protocol, TypedDict, overloads, and strict mypy or pyright configuration, including gradual typing of untyped legacy modules. Trigger when the task involves programming work related to Python Typing And Mypy Strictness, implementation, audits, debugging, strategy, or validation."
---

# Python Typing And Mypy Strictness

Use this skill for Programming tasks focused on Python type annotations, structural typing, and raising type-checker strictness without stalling delivery. For the TypeScript equivalent use `typescript-strictness-migration`; for whole-codebase version upgrades use `legacy-python-codebase-modernization`.

## Workflow

1. Clarify the user outcome, constraints, target Python version, and definition of done.
2. Record the current baseline before changing anything: checker and version, config file, per-module overrides, and the error count from a clean run.
3. Check official mypy or pyright documentation when flag names, default behavior, or version support may have changed.
4. Pick the smallest strictness increment that is enforceable today, usually one flag or one package at a time, and compare proven open-source configs without copying incompatible code.
5. Annotate from the outside in: public signatures and data boundaries first, private helpers after, inference-friendly locals last.
6. Validate with a full type-check run plus the existing test suite, and confirm runtime behavior is unchanged.
7. Report the config diff, the new error count, remaining suppressions, risks, and next steps clearly.

## Focus Checklist

- Raise strictness per module or package via config overrides rather than flipping every flag repo-wide at once.
- Prefer `Protocol` for structural contracts and generics over duplicating concrete base classes.
- Model dict-shaped payloads with `TypedDict`, `NamedTuple`, or a validated model instead of `dict[str, Any]`.
- Use modern builtin generics or `from __future__ import annotations` consistently, matching the declared minimum version.
- Keep every suppression narrow: a specific error code, one line, and a reason comment.
- Wire the checker into CI at the strictness the repo actually passes, so the ratchet cannot slip backwards.

## Guardrails

- Do not silence type errors with bare `Any`, unscoped `# type: ignore`, or a `cast` when the correct fix is a corrected annotation.
- Do not change runtime behavior while annotating; typing work must stay behavior-preserving.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data.
- If validation is impossible, state why and provide a concrete manual verification path.
