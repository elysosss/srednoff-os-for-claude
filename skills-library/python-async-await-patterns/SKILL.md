---
name: python-async-await-patterns
description: "Use this skill for asyncio design and repair - TaskGroup, structured concurrency, cancellation and timeouts, blocking calls inside the event loop, and the deadlocks they cause. Trigger when the task involves programming work related to Python Async Await Patterns, implementation, audits, debugging, strategy, or validation."
---

# Python Async Await Patterns

Use this skill for Programming tasks focused on asyncio correctness: task lifetime, cancellation, structured concurrency, and event-loop starvation. For generic latency and throughput work use `performance-optimization`; for CPU profiling use `python-profiling-cprofile-pyspy`.

## Workflow

1. Clarify the user outcome, the concurrency requirement, the target Python version, and the definition of done.
2. Map the async surface before changing anything: entry points, long-lived tasks, background loops, sync-to-async bridges, and every third-party client that only claims to be async.
3. Check official asyncio and library documentation when API availability differs by version, especially `TaskGroup`, `timeout`, and cancellation semantics.
4. Reproduce the failure deterministically where possible: a hang, an unawaited-coroutine warning, a task that dies silently, or latency that collapses under load.
5. Implement the smallest production-ready change: give every task an owner, a timeout, and a cancellation path.
6. Validate with targeted async tests, a load or soak run when contention is the complaint, and a check that no task leaks after shutdown.
7. Report changed files, commands run, remaining risks, and exact next steps.

## Focus Checklist

- Own every task: prefer `TaskGroup` or an explicit supervisor over a bare `create_task` whose result nobody awaits.
- Treat `CancelledError` as a control signal, never as a generic exception to swallow; re-raise after cleanup.
- Push blocking work - file IO, synchronous HTTP clients, CPU loops, drivers without async support - into a thread or process executor.
- Bound concurrency with a semaphore or a queue instead of fanning out unbounded tasks per request.
- Check the usual deadlocks: awaiting while holding a lock, nested event-loop entry, a sync wrapper calling back into the running loop, and unbounded queues with no consumer.
- Make shutdown explicit: drain queues, cancel children, await completion with a timeout, and close clients.

## Guardrails

- Do not call blocking code directly inside a coroutine, and do not use `time.sleep` where `asyncio.sleep` belongs.
- Do not suppress cancellation to force work to finish; raise the design question instead.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data.
- If validation is impossible, state why and provide a concrete manual verification path.
