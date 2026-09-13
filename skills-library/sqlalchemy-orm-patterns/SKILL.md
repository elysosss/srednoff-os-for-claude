---
name: sqlalchemy-orm-patterns
description: "Use this skill for SQLAlchemy 2.0 ORM work: session lifecycle, unit of work boundaries, relationship loading strategies, and N+1 query elimination. Trigger when the task involves declarative models, repository or service layers, slow ORM-backed endpoints, detached instance errors, or a move from legacy Query API to 2.0 select() style."
---

# SQLAlchemy ORM Patterns

Use this skill for backend and data tasks where SQLAlchemy 2.0 models, sessions, and loading strategies decide correctness and latency.

## Workflow

1. Confirm the SQLAlchemy version and API style in use: 2.0 `select()` plus `Session.execute`, or the legacy `Query` API. Do not mix styles inside one module.
2. Read the model definitions first. Note `relationship()` declarations, their default loading strategy, and every `lazy=` override.
3. Establish one clear session boundary per unit of work: open, do the work, commit or roll back, close. Prefer an explicit context manager or a framework-scoped dependency over a module-level global session.
4. Reproduce the reported problem with SQL echoed or logged, so the actual statement count is evidence and not a guess.
5. Fix loading strategy at the query site, not by flipping a global default: `selectinload` for collections, `joinedload` for many-to-one, `raiseload` to make accidental lazy loads fail loudly in tests.
6. Re-run the same scenario and compare statement counts before and after.
7. Report the changed queries, the new statement count, and any behavior that now requires an eagerly loaded attribute.

## Focus Checklist

- One session per request or per task; never share a session across threads, tasks, or background jobs.
- Commit and rollback are owned by the outermost caller, not by helper functions that happen to write.
- Objects accessed after the session closes are expired; either load what the caller needs inside the boundary or return plain data structures.
- Collection access in a loop is the usual N+1 source; check serializers and template rendering, not only the query itself.
- Prefer explicit `select()` with typed `Mapped[]` annotations over implicit attribute-based querying.
- Bulk writes go through `insert()`/`update()` statements rather than per-object flushes when volume is high.
- Keep transaction scope short; long-held sessions hold connections and locks.

## Guardrails

- Do not run destructive or schema-changing statements against a real database without explicit confirmation.
- Do not change a relationship's default loading strategy globally to fix one endpoint; the blast radius is every query touching that model.
- Do not silence detached-instance or lazy-load errors by keeping sessions open indefinitely.
- Do not place credentials or connection strings in code; read them from configuration.
- If profiling against real data is impossible, say so and provide a manual reproduction path with echoed SQL.
