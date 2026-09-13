---
name: python-profiling-cprofile-pyspy
description: "Use this skill to profile Python CPU and wall-clock time with cProfile, py-spy, and flame graphs - choosing the right profiler, sampling a live production process, and reading the output before optimizing anything. Trigger when the task involves programming work related to Python Profiling Cprofile Pyspy, implementation, audits, debugging, strategy, or validation."
---

# Python Profiling Cprofile Pyspy

Use this skill for Programming tasks focused on measuring where Python time actually goes. For the optimization strategy that follows the measurement use `performance-optimization`; for memory growth rather than CPU time use `memory-leak-detection-python`.

## Workflow

1. Clarify the user outcome: which operation is slow, how slow is acceptable, and the definition of done as a number, not a feeling.
2. Establish a reproducible baseline before touching code - a benchmark script, a replayed request, or a marked window in production traffic - and record the current timing.
3. Pick the profiler for the question: deterministic `cProfile` for a reproducible local path, sampling `py-spy` for a live or production process that must not be restarted, and `--gil` or thread views when concurrency is suspected.
4. Read the profile top-down: cumulative time first to find the responsible call tree, total time second to find the hot leaf, and a flame graph when the call tree is deep.
5. Change one thing at a time and re-measure against the same baseline; keep changes that show a real delta and revert the rest.
6. Validate with the benchmark, the test suite, and a check that the win holds under realistic input size and concurrency.
7. Report the before and after numbers, the commands used, remaining risks, and exact next steps.

## Focus Checklist

- Rule out the non-CPU explanations first: blocking IO, N+1 queries, serialization, cold caches, and lock contention look like slow code but are not.
- Remember the profiler's own cost - `cProfile` inflates call-heavy code, so use sampling when absolute timings matter.
- Profile something representative: warm the process, use production-sized input, and discard the first iteration.
- Attribute time to your own code, not to the interpreter frames beneath it; third-party hot spots usually mean a misuse one level up.
- Save the raw profile output as an artifact so the comparison after the change is like-for-like.
- Stop when the target is met and say what the next bottleneck would be, instead of micro-tuning past the point of value.

## Guardrails

- Do not attach a profiler to a production process without explicit user confirmation, and prefer a sampling profiler with a known overhead budget when you do.
- Do not accept an optimization without a measured before and after on the same workload.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data - profiles and stack samples can contain request payloads.
- If validation is impossible, state why and provide a concrete manual verification path.
