---
name: python-dataclasses-pydantic-validation
description: "Use this skill for Python data modeling and input validation - Pydantic v2 models, validators and settings, dataclasses versus attrs, request and config schema design, serialization, and clear validation errors. Trigger when the task involves programming work related to Python Dataclasses Pydantic Validation, implementation, audits, debugging, strategy, or validation."
---

# Python Dataclasses Pydantic Validation

Use this skill for Programming tasks focused on modeling data at the boundary: validating untrusted input, turning it into typed domain objects, and serializing it back. For static typing strategy use `python-typing-and-mypy-strictness`; for schema evolution in storage use `database-schema-migration-auditor`.

## Workflow

1. Clarify the user outcome, the trust level of each input, the library already in use, and the definition of done.
2. Inspect existing models before adding new ones: duplicated shapes, manual dict parsing, and validation scattered across handlers are the usual findings.
3. Check official Pydantic documentation when behavior may differ between v1 and v2; validator decorators, model config, aliases, and serialization all changed.
4. Decide per model: a plain dataclass for internal value objects, a validating model for anything crossing a trust boundary.
5. Implement the smallest production-ready change, keeping validation at the edge and the domain layer free of parsing logic.
6. Validate with tests for the accept path, the reject path, and the round trip, asserting on error shape as well as on success.
7. Report changed files, commands run, remaining risks, and exact next steps.

## Focus Checklist

- Parse once at the boundary into a typed object, then pass that object inward instead of re-validating dicts at every layer.
- Keep request, response, and persistence models separate when their fields genuinely differ, so internal fields are never exposed by accident.
- Be explicit about strictness: coercion rules, unknown-field handling, optional versus nullable, and defaults that must not be mutable or shared.
- Use field and model validators for cross-field rules and keep them pure - no IO, no network calls inside validation.
- Shape errors for the consumer: stable machine-readable codes, field paths, and messages that never echo the rejected value back when it may be a secret.
- Validate settings and environment configuration through the same models, so a bad deploy fails at startup rather than at first request.

## Guardrails

- Do not put raw invalid input, credentials, or personal data into validation error messages, logs, or API responses.
- Do not use mutable default values, and do not disable validation to make a failing test pass.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data.
- If validation is impossible, state why and provide a concrete manual verification path.
