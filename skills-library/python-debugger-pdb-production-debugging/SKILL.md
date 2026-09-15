---
name: python-debugger-pdb-production-debugging
description: "Use this skill for hands-on Python debugging - pdb and ipdb sessions, breakpoint and post-mortem workflows, faulthandler and signal dumps, attaching to a stuck or remote process, and reconstructing a production incident from a traceback. Trigger when the task involves programming work related to Python Debugger Pdb Production Debugging, implementation, audits, debugging, strategy, or validation."
---

# Python Debugger Pdb Production Debugging

Use this skill for Programming tasks focused on the mechanics of inspecting a running or crashed Python process. For the general reproduce-isolate-fix method use `debugging-error-recovery` or `staff-debugger-agent`; this skill covers the Python tooling those methods call for.

## Workflow

1. Clarify what is actually observed: the exception and full traceback, the affected request or job, the frequency, and what changed before it started.
2. Read the traceback properly before running anything - innermost frame for the mechanism, the chain of `raise ... from` for the original cause, and the outermost application frame for the code you own.
3. Try to reproduce locally with the same input, and drop into a post-mortem session on the failure rather than adding print statements.
4. If it only happens in a live process, choose a non-invasive tool first: a sampling stack dump or a `faulthandler` signal handler beats an interactive breakpoint on a serving process.
5. Narrow to the smallest failing case, confirm the mechanism by inspecting state in the frame, then apply the minimal fix at the root cause.
6. Validate with a regression test that fails without the fix, plus the existing suite, and remove every debugging hook you introduced.
7. Report the root cause, the fix, the verification commands, remaining risks, and exact next steps.

## Focus Checklist

- Use `breakpoint()` rather than hard-coded imports so the debugger is configurable and easy to grep for before shipping.
- Know the small set of commands that does most of the work: step into versus step over, up and down the frame stack, continue to a condition, and inspecting locals and the exception chain.
- Prefer conditional breakpoints over stepping through thousands of iterations to reach the interesting one.
- For a hung process, capture stacks for all threads and check the event loop or lock ownership before assuming an infinite loop.
- Capture evidence while the process is still alive - stacks, locals, environment, recent log lines - because a restart destroys it.
- Feed the finding back into the system: an assertion, a log line, or a metric that would have made this incident obvious in minutes.

## Guardrails

- Do not leave `breakpoint()`, `pdb.set_trace()`, or a remote debug port in code that can reach production; a debugger prompt on a live process blocks it and exposes state.
- Do not attach to, pause, or restart a production process without explicit user confirmation and an agreed blast radius.
- Do not perform destructive, paid, production, publishing, account-changing, or externally visible actions without explicit user confirmation.
- Do not expose secrets, private keys, tokens, cookies, personal data, or confidential business data - frame locals and tracebacks routinely contain all of them.
- If validation is impossible, state why and provide a concrete manual verification path.
