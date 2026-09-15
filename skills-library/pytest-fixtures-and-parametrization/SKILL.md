---
name: pytest-fixtures-and-parametrization
description: "Use this skill for pytest structure and mechanics - fixture scope and teardown, conftest layering, parametrize and ids, markers and selection, monkeypatch, and plugin choices for slow or flaky suites. Trigger when the task involves programming work related to Pytest Fixtures And Parametrization, implementation, audits, debugging, strategy, or validation."
---

# Pytest Fixtures And Parametrization

Use this skill for Programming tasks focused on how a pytest suite is organized and executed. For deciding which test layers a system needs use `test-architect-agent`; for randomized input generation use `property-based-testing`.

## Workflow

1. Clarify the user outcome, the pain being solved - slow, flaky, unreadable, or hard to extend - and the definition of done.
2. Inspect the suite before changing it: every `conftest.py` and the directory it governs, existing fixtures, markers, plugins, and the runtime profile from a durations report.
3. Check official pytest and plugin documentation when fixture semantics, marker registration, or plugin flags may have changed between versions.
4. Identify the real cost driver: repeated expensive setup, per-test IO, over-broad fixture scope leaking state, or a suite that could run in parallel but does not.
5. Implement the smallest production-ready change, usually correcting fixture scope, replacing copy-pasted test bodies with `parametrize`, and moving shared setup into the nearest `conftest.py`.
6. Validate by running the full suite, then re-running in reversed or random order to prove the tests are still independent.
7. Report changed files, commands run, remaining risks, and exact next steps.

## Focus Checklist

- Match fixture scope to the cost and mutability of the resource: session or module for expensive read-only setup, function scope for anything a test mutates.
- Clean up inside the fixture with `yield` plus teardown, so a failing test cannot leave state behind.
- Put each fixture in the narrowest `conftest.py` that needs it; a root conftest that imports the world slows collection for everyone.
- Use `parametrize` with readable ids for input tables, and indirect parametrization when the value must flow through a fixture.
- Register markers in configuration, keep slow or external-dependency tests behind an opt-in marker, and keep the default run fast and hermetic.
- Prefer the built-in `monkeypatch`, `tmp_path`, and `caplog` fixtures over hand-rolled setup, and add a plugin only when it solves a measured problem.

## Guardrails

- Do not let tests share mutable state through a broad-scope fixture; order dependence is a latent failure, not a passing suite.
- Do not point tests at real production services, live credentials, or a shared database without explicit user confirmation.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data.
- If validation is impossible, state why and provide a concrete manual verification path.
