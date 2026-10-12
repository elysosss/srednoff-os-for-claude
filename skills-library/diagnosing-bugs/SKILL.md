---
name: diagnosing-bugs
description: Use this skill for hard bugs and performance regressions - "diagnose this", "debug this", or something that is broken, throwing, failing, flaky or slow and the cause is not obvious. Build a red-capable feedback loop before forming any theory; do not use for typos or one-line fixes.
---

# Diagnosing Bugs

Adapted from mattpocock/skills `diagnosing-bugs` (MIT, see `registry/INSTALL-SOURCES.md`). The helper script of the original is not imported.

A discipline for bugs that resist reading the code. Skip a phase only when you can say why.

If the project has a `GLOSSARY.md` or ADRs for the area, read them before exploring.

## Redact first

Commands, outputs and captured artifacts are shown to the user and may be logged. Replace every secret with `<REDACTED>` before showing it; build loops against environment variables so the credential stays out of the output; quote only the lines that carry the signal. If redacted output is not enough to diagnose, say so and ask.

## Phase 1 - Build a feedback loop

This is the skill. With a tight pass/fail signal that goes red on this bug, the cause can be found; without one, staring at code does not help. Spend disproportionate effort here.

Ways to build a loop, roughly in order of preference:

1. A failing test at the seam that reaches the bug (unit, integration, e2e).
2. A curl or HTTP script against a running dev server.
3. A CLI call on a fixture input, diffed against a known-good snapshot.
4. A headless-browser script asserting on DOM, console or network.
5. Replay of a captured trace, request or event log through the code path in isolation.
6. A throwaway harness: the smallest subset of the system that exercises the path with one call.
7. A property or fuzz loop for "sometimes wrong output".
8. A bisection harness for "worked at state A, broken at state B" (`git bisect run`).
9. A differential loop: the same input through old and new version, or two configs, diffed.
10. Last resort: a human-in-the-loop script that asks the person for each manual step and records the answers, so the loop stays structured.

Tighten the loop: faster (cache setup, narrow scope), sharper (assert the exact symptom, not "did not crash"), more deterministic (pin time, seed random, isolate files, freeze network). A 30-second flaky loop is barely better than none; a 2-second deterministic one is a superpower.

Non-deterministic bugs: aim for a higher reproduction rate, not a clean repro - loop the trigger 100 times, add stress, narrow timing windows. A 50% flake is debuggable; 1% is not.

If no loop can be built, stop and say so, list what was tried, and ask for one of: access to the environment that reproduces it, a redacted artifact (HAR, log dump, core dump, recording), or permission to add temporary instrumentation. Do not hypothesise without a loop.

**Phase 1 is done when** one command has been run at least once (invocation and redacted output shown) and it is: red-capable (asserts the user's exact symptom), deterministic, fast, and runnable unattended. Reading code to build a theory before that command exists is the failure this skill prevents.

## Phase 2 - Reproduce and minimise

Run the loop and watch it go red. Confirm it shows the failure the **user** described, not a nearby one, and that it repeats. Then shrink the scenario: cut inputs, callers, config, data and steps one at a time, re-running after each cut, until every remaining element is load-bearing (removing any one makes the loop go green). Do not continue before the bug is reproduced and minimised.

## Phase 3 - Hypothesise

Write 3-5 ranked hypotheses before testing any. Each must be falsifiable: "If X is the cause, then changing Y makes the bug disappear / changing Z makes it worse." A hypothesis without a prediction is discarded or sharpened. Show the ranked list to the user; they often re-rank it instantly. Do not block on an answer if they are away.

## Phase 4 - Instrument

Each probe maps to one prediction; change one variable at a time. Prefer a debugger or REPL (one breakpoint beats ten logs), then targeted logs at the boundaries that separate hypotheses; never "log everything and grep". Tag every debug log with a unique prefix such as `[DEBUG-a4f2]` so cleanup is one grep. For performance regressions, measure first (timing harness, profiler, query plan), then bisect - logs mislead.

## Phase 5 - Fix and regression test

Write the regression test before the fix, but only at a **correct seam**: one where the test exercises the real bug pattern as it occurs at the call site. If the only reachable seam is too shallow, a test there gives false confidence - and the missing seam is itself a finding to report.

With a correct seam: turn the minimised repro into a failing test, watch it fail (if red was forced by mutating code or a fixture, diff against a pristine copy to prove the mutation landed), apply the fix, watch it pass, then re-run the Phase 1 loop on the original un-minimised scenario.

## Phase 6 - Clean up

Done only when: the original repro no longer reproduces; the regression test passes or the absence of a seam is documented; all tagged debug instrumentation is removed (grep the prefix); throwaway prototypes are deleted; and the commit or PR message states the hypothesis that turned out to be correct.

## Guardrails

- Never add production instrumentation, change production data or restart production services without explicit confirmation (`50-security.md`).
- Report failures as they are: if the bug is not reproduced or not fixed, say which phase stopped and why.
