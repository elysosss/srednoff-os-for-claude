---
name: dockerfile-best-practices-python
description: "Use this skill for authoring and reviewing Python Dockerfiles: multi-stage builds, layer ordering and cache hits, non-root runtime users, image size reduction, and .dockerignore hygiene. Trigger when a Python service needs a container image, an existing image is oversized or rebuilds slowly, or a review flags a container running as root."
---

# Dockerfile Best Practices for Python

Use this skill for infrastructure and backend tasks where a Python application is packaged into a container image. The guidance is registry- and cloud-neutral.

## Workflow

1. Establish the runtime facts: Python version, dependency manager, whether any dependency needs a compiler or system library, and what the process listens on.
2. Split the build into stages. A builder stage installs toolchains and resolves dependencies; the final stage copies only the installed artifacts and the application source.
3. Order instructions from least to most volatile: base image, system packages, dependency manifests, dependency install, then application code last.
4. Install dependencies from a locked manifest so rebuilds are reproducible, and disable the package cache in the final layer.
5. Create a dedicated unprivileged user and group, transfer ownership of what the process must write, and switch to that user before the entrypoint.
6. Write a `.dockerignore` before the first build; it controls both context upload time and accidental secret inclusion.
7. Build, inspect the resulting size and layer list, run the image, and confirm the process starts as the expected non-root user.
8. Report the final size, the cache behavior on a code-only change, and the base image tag pinned.

## Focus Checklist

- Base image is pinned to a specific tag or digest, never a floating `latest`.
- The final stage contains no compilers, headers, package caches, or build tooling.
- `.dockerignore` excludes version control, virtual environments, caches, test artifacts, local env files, and build output.
- A code-only edit rebuilds only the last layers; if it reinstalls dependencies, the ordering is wrong.
- The container runs as a non-root UID and does not need a writable application directory.
- Python is configured for containers: unbuffered output and no bytecode writing where it adds nothing.
- The entrypoint runs the application as PID 1 in exec form so signals reach it and shutdown is graceful.
- Build-time secrets use a build secret mechanism, never an `ARG` or `ENV` that persists into a layer.

## Guardrails

- Do not bake credentials, tokens, private keys, or `.env` files into any layer; deleted files remain in earlier layers.
- Do not push images to a shared registry without explicit confirmation.
- Do not install unpinned system packages when reproducibility matters.
- Do not assume a specific cloud registry, orchestrator, or managed build service; keep the Dockerfile portable.
- If the image cannot be built locally, state why and give the exact build and inspection commands to run.
