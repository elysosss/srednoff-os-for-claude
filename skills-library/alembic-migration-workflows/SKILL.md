---
name: alembic-migration-workflows
description: "Use this skill for Alembic migration workflows: autogenerate review, revision branching and merges, downgrade paths, data migrations, and zero-downtime rollout ordering. Trigger when a revision must be authored or reviewed, autogenerate produced a suspicious diff, heads have diverged after a merge, or a schema change must ship without taking the application offline."
---

# Alembic Migration Workflows

Use this skill for data tasks where Alembic revisions are authored, reviewed, or rolled out against a live database.

## Workflow

1. Check the current state first: which revision the target database is on, and whether the repository has a single head or several.
2. Generate a candidate revision with autogenerate, then read every generated line. Autogenerate is a draft, not an answer.
3. Correct what autogenerate cannot see: server defaults, enum value changes, index names, constraint naming conventions, column type widenings, and anything owned by an extension or another service.
4. Write the downgrade body deliberately. If a downgrade is genuinely impossible, say so in the revision docstring instead of leaving a silent stub.
5. Keep schema changes and data backfills in separate revisions when the backfill is large, so a failed backfill does not strand the schema half-applied.
6. Plan the rollout order for anything running without downtime: additive change first, application deploy that writes both shapes, backfill, then the destructive cleanup in a later release.
7. Apply the revision against a scratch copy, then downgrade and upgrade again to prove both directions work.
8. Report the revision id, its parent, the SQL it emits, the lock profile, and the rollback path.

## Focus Checklist

- Autogenerate diffs are reviewed line by line; unexplained drops are treated as bugs until proven otherwise.
- Multiple heads are resolved with an explicit merge revision, never by editing `down_revision` by hand after the fact.
- Data migrations use core statements against lightweight table definitions, not application ORM models, so the revision keeps working after the models change.
- Long-running operations on large tables are checked for table-level locks; prefer concurrent index creation and nullable-first column addition where the engine supports it.
- `NOT NULL` arrives in a later step, after the backfill, never in the same statement that adds the column.
- Batch mode is used where the engine cannot alter columns in place.
- Every revision is idempotent enough to be re-run after a partial failure, or is documented as requiring manual cleanup.

## Guardrails

- Do not run upgrade or downgrade against production without explicit confirmation and a verified backup.
- Do not include a destructive drop in the same release that stops writing to the dropped object.
- Do not edit a revision that has already been applied anywhere shared; write a follow-up revision instead.
- Do not embed secrets or environment-specific connection strings in revision files.
- If the migration cannot be rehearsed on realistic data volume, state that gap and give a manual verification path.
