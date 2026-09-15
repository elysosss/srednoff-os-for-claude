---
name: python-packaging-pyproject-poetry-uv
description: "Use this skill for Python dependency management and release: pyproject.toml metadata, uv or Poetry workflows, lock files, reproducible environments, version constraints, and publishing to an index with trusted publishing. Trigger when the task involves programming work related to Python Packaging Pyproject Poetry Uv, implementation, audits, debugging, strategy, or validation."
---

# Python Packaging Pyproject Poetry Uv

Use this skill for Programming tasks focused on dependency resolution, environment reproducibility, and package release. For scaffolding a new CLI package and its console scripts use `python-cli-package-builder`; this skill covers the dependency and publishing side of the same file.

## Workflow

1. Clarify the user outcome: application or library, supported Python versions, target index, and definition of done.
2. Inspect what already exists before changing anything: `pyproject.toml`, any lock file, leftover `setup.py`, `requirements*.txt`, tool sections, and how CI installs dependencies.
3. Check official documentation for the chosen tool and the current packaging specifications when build backends, metadata fields, or index behavior may have changed.
4. Choose one dependency manager and one build backend for the repository and say why; two managers in one repo is the usual source of drift.
5. Make the smallest production-ready change, keeping constraints honest: libraries stay permissive, applications pin through a committed lock file.
6. Validate by building the artifacts, installing them into a clean environment, importing the package, running the entry points, and confirming CI reproduces the same resolution.
7. Report changed files, commands run, remaining risks, and exact next steps.

## Focus Checklist

- Keep metadata complete and accurate: name, version source, `requires-python`, license, readme, classifiers, and declared entry points.
- Commit the lock file for applications and CI, and split dev, test, and docs dependencies into groups or extras instead of one flat list.
- Inspect the built wheel contents, not just the build log; missing package data and stray top-level modules only show up in the artifact.
- Prefer trusted publishing from CI over a long-lived API token, and do a dry run against a test index first.
- Make releases repeatable: a tag drives the version, CI builds once, and that same artifact is what gets uploaded.
- When replacing an older tool, document the migration path and how contributors refresh their local environment.

## Guardrails

- Do not publish to a public index, delete a release, or yank a version without explicit user confirmation.
- Do not store index credentials or API tokens in the repository, in `pyproject.toml`, or in CI logs.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data.
- If validation is impossible, state why and provide a concrete manual verification path.
