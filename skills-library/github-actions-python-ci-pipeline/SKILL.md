---
name: github-actions-python-ci-pipeline
description: "Use this skill for GitHub Actions CI on Python projects: a version matrix, dependency caching, lint, typecheck and test as separate steps, and artifact upload. Trigger when a Python repository needs a CI workflow, when the pipeline is slow because dependencies reinstall every run, when failures are hard to attribute to a stage, or when coverage and build artifacts must be published from CI."
---

# GitHub Actions Python CI Pipeline

Use this skill for CI and DevOps tasks specific to running a Python project's checks on GitHub Actions. Pipeline strategy in general is a separate concern; this covers the Python-specific shape.

## Workflow

1. Establish the supported Python versions from the project metadata, and the dependency manager and lock file actually in use.
2. Define the matrix over those versions, plus additional operating systems only if the project genuinely supports them. Exclude combinations that are known-unsupported rather than letting them fail.
3. Cache the dependency install keyed on the lock file hash and the interpreter version, so a lock change invalidates the cache and a code change does not.
4. Keep lint, typecheck, and test as separate named steps so a red run names the failing stage in the summary without opening logs.
5. Let tests keep running after a lint failure where that is useful, using per-step control rather than chaining everything into one shell line.
6. Upload artifacts worth keeping: the test report, coverage output, and any built distribution, each named so matrix entries do not overwrite each other.
7. Pin actions to a released version, restrict the workflow token to read permissions by default, and grant more only on the job that needs it.
8. Run the workflow on a branch, confirm timing and cache hit rate, and report the per-stage durations.

## Focus Checklist

- The matrix reflects what the package claims to support; a version in the metadata but not in CI is an untested claim.
- `fail-fast` is set deliberately: off when knowing every failing version matters, on when the first failure is enough.
- Cache keys include the lock file hash, interpreter version, and runner OS; a restore-key fallback is a prefix, not the same key.
- Concurrency is configured to cancel superseded runs on the same branch.
- A single canonical job handles lint and typecheck once rather than repeating them across every matrix entry.
- Long test suites are split or marked so the pull request path stays fast and the slow set runs on a schedule or on the main branch.
- Artifacts have a retention period; unbounded uploads accumulate cost.

## Guardrails

- Do not expose secrets to workflows triggered by forked pull requests, and do not interpolate untrusted branch or title text into shell commands.
- Do not publish packages, create releases, or push tags from CI without explicit confirmation and a protected environment.
- Do not grant write permissions to the workflow token broadly when one job needs them.
- Do not print environment dumps, tokens, or coverage payloads containing private data into build logs.
- If the workflow cannot be run here, state that and give the exact commands to reproduce each stage locally.
