---
name: memory-leak-detection-python
description: "Use this skill when a Python process grows in RSS without bound - tracemalloc snapshots, objgraph reference chains, gc diagnostics, reference cycles, caches that never evict, and native allocations that never return to the OS. Trigger when the task involves programming work related to Memory Leak Detection Python, implementation, audits, debugging, strategy, or validation."
---

# Memory Leak Detection Python

Use this skill for Programming tasks focused on unbounded memory growth in a long-running Python process. For CPU time use `python-profiling-cprofile-pyspy`; for eviction policy design in a deliberate cache use `cache-invalidation-design`.

## Workflow

1. Clarify the symptom precisely: which process, over what time window, how fast RSS climbs, and whether it ever plateaus or ends in an out-of-memory kill.
2. Separate a leak from normal behavior before investigating - allocator fragmentation, a warm cache reaching steady state, and a large one-off load all raise RSS without leaking.
3. Instrument the running process: take `tracemalloc` snapshots at intervals and diff them, and record `gc` counts and uncollectable objects alongside RSS.
4. Follow the diff to an owner - use `objgraph` or `gc.get_referrers` to trace the reference chain from a growing object type back to whatever is holding it alive.
5. Fix the retention, not the symptom: bound the container, drop the reference, break the cycle, or close the resource. Avoid manual `gc.collect` calls as a substitute for a fix.
6. Validate with a soak run long enough to show a flat RSS curve under representative load, and compare against the pre-fix curve.
7. Report the evidence, the fix, the soak results, remaining risks, and exact next steps.

## Focus Checklist

- Check the usual holders first: module-level dicts and lists, unbounded `lru_cache`, class attributes used as caches, logging handlers, event listeners, and never-cancelled tasks or threads.
- Look for reference cycles with `__del__` involved, and for closures or default arguments that capture more than intended.
- Distinguish Python-heap growth from native growth: if `tracemalloc` totals stay flat while RSS climbs, suspect a C extension, a driver, or allocator fragmentation.
- Confirm that connections, file handles, sessions, and subprocesses are closed on every path including the error path.
- Add a permanent guard after the fix - a memory metric, an alert threshold, or a bounded container - so a regression is visible early.
- Note when a scheduled restart is a legitimate mitigation, and label it as mitigation rather than a fix.

## Guardrails

- Do not take heap dumps or snapshots from production without explicit user confirmation, and treat any dump as sensitive data.
- Do not raise memory limits or add a restart loop to hide growth that has not been diagnosed.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data - object dumps commonly contain live request data.
- If validation is impossible, state why and provide a concrete manual verification path.
