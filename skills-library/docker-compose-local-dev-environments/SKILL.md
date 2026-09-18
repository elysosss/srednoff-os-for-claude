---
name: docker-compose-local-dev-environments
description: "Use this skill for Docker Compose local development environments: service healthchecks, dependency ordering, volumes for code and data, environment variables driven by a checked-in .env.example, and optional profiles. Trigger when a repository needs a one-command local stack, when services start before their dependencies are ready, or when onboarding a new developer breaks on missing configuration."
---

# Docker Compose Local Dev Environments

Use this skill for infrastructure tasks where Compose defines the local development stack. Target outcome: a fresh clone comes up with one command and no undocumented setup.

## Workflow

1. List the services actually needed to develop: the application, its datastore, and only the supporting services a developer cannot stub.
2. Define each dependency with a real healthcheck that queries the service itself, not a port probe that passes before the service can answer.
3. Wire `depends_on` with a health condition so the application waits for readiness rather than for container creation.
4. Separate volume kinds: a bind mount for source code to get live reload, a named volume for datastore state, and no bind mount for dependency directories that differ between host and container.
5. Put every configurable value in the environment, commit a `.env.example` with safe placeholder values and comments, and keep the real `.env` untracked.
6. Group optional services behind profiles so the default `up` stays fast and the extras are opt-in.
7. Verify from a clean state: remove volumes, copy the example env, bring the stack up, and confirm every service reports healthy and the application reaches its dependencies.
8. Report the commands, the service list, exposed ports, and what the reset procedure is.

## Focus Checklist

- `docker compose up` from a clean clone works after copying one example file; anything else belongs in the file, not in a developer's head.
- Healthchecks have sane interval, timeout, retries, and a start period for slow-booting datastores.
- The application still retries its own connections; `depends_on` reduces races, it does not remove them.
- Ports bound on the host are documented and chosen to avoid collisions with common local services.
- Named volumes are listed explicitly so state can be reset deliberately.
- Compose files stay development-focused; production concerns live in the deployment manifests, not here.
- Overrides for personal preferences go in a local override file that is not committed.

## Guardrails

- Do not commit real credentials, tokens, or a populated `.env`; only the example file is tracked.
- Do not remove volumes or prune resources without explicit confirmation, since that deletes local data.
- Do not expose a development stack on a non-loopback interface by default.
- Do not present a Compose file as a production deployment; say plainly that it is not one.
- If the stack cannot be started in this environment, state that and give the exact verification commands.
