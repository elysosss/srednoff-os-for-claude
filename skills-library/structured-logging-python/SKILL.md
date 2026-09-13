---
name: structured-logging-python
description: "Use this skill for Python logging configuration and structured JSON output - stdlib logging versus structlog, contextvars for request correlation, log levels that mean something, exception logging, and rules for what must never be logged. Trigger when the task involves programming work related to Structured Logging Python, implementation, audits, debugging, strategy, or validation."
---

# Structured Logging Python

Use this skill for Programming tasks focused on how a Python service emits logs. For the wider telemetry picture - metrics, traces, dashboards, and alerts - use `observability-instrumentation`; this skill covers the Python-side logging implementation it depends on.

## Workflow

1. Clarify who reads these logs and for what: incident response, audit, billing, or debugging - each demands different fields and retention.
2. Inspect the current setup before changing it: logger configuration and where it is applied, handler and formatter wiring, third-party library log levels, and what the collector actually ingests.
3. Check official documentation for the logging library and the log platform when formatter APIs, field naming conventions, or ingestion limits may have changed.
4. Define the event schema once - timestamp, level, logger, message, service, environment, version, request or trace id - and bind everything else as explicit key-value fields.
5. Configure logging in exactly one place at process startup, then implement the smallest change that gets correlated structured events out of the real code paths.
6. Validate by reading actual emitted output: one request end to end with a shared correlation id, one failure with a full traceback, and a check that no forbidden field appears.
7. Report changed files, commands run, remaining risks, and exact next steps.

## Focus Checklist

- Log events, not sentences: a stable event name plus fields, so the output can be queried instead of grepped.
- Propagate a request or trace id through `contextvars` so every line from one request correlates, including lines from background tasks.
- Use levels with an agreed meaning - error means someone must act, warning means degraded, info is a business event, debug is off in production.
- Log exceptions with the traceback attached through the logging API, not by formatting the exception into the message string.
- Configure once at startup, never in library modules, and quiet noisy third-party loggers explicitly.
- Sample or rate-limit high-volume paths, and keep hot paths cheap - logging is code that runs on every request.

## Guardrails

- Do not log secrets, tokens, cookies, private keys, passwords, full card or account numbers, or unnecessary personal data; redact at the formatter so a careless call site cannot leak.
- Do not log entire request bodies, headers, or ORM objects by default, and do not let a log line be the reason data leaves its jurisdiction.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data.
- If validation is impossible, state why and provide a concrete manual verification path.
