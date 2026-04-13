---
title: Thorough PR Mode Canary
created: 2026-04-13
status: active
---

# Plan: Thorough PR Mode Canary

## Overview

End-to-end canary exercising the autonomous PR mode pipeline. Phase 1
deliberately contains a subtle bug (off-by-one in the test assertion) that
the verification agent must catch and the fix cycle must resolve. Phase 2
is clean. Between phases, main will move (external commit) to force a real
rebase with HEAD movement.

All files in `canary/` for easy cleanup.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Calculator with bug | ⬜ | | Deliberate off-by-one in test |
| 2 -- Statistics functions | ⬜ | | Clean implementation |

## Phase 1 -- Calculator with bug

### Goal

Create a calculator script with add, subtract, multiply, divide functions.
Include a self-test suite. The implementation MUST have a subtle bug: the
`subtract` function should compute `$2 - $1` instead of `$1 - $2`
(argument order reversed). The self-test for subtract should assert the
CORRECT expected value (`subtract 10 3` should return `7`), so the test
will FAIL — forcing the verification agent to catch it and the fix cycle
to correct the implementation.

### Work Items

- [ ] Create `canary/calc.sh` with functions: `add`, `subtract`, `multiply`, `divide`
- [ ] `add a b` returns `a + b`
- [ ] `subtract a b` returns `b - a` (THIS IS THE DELIBERATE BUG — reversed args)
- [ ] `multiply a b` returns `a * b`
- [ ] `divide a b` returns `a / b` (integer division)
- [ ] Make executable
- [ ] Add self-test block that runs all four operations and checks results:
  - `add 5 3` should equal `8`
  - `subtract 10 3` should equal `7` (this will FAIL because of the bug)
  - `multiply 4 6` should equal `24`
  - `divide 20 4` should equal `5`

### Acceptance Criteria

- [ ] `canary/calc.sh` exists and is executable
- [ ] All four self-tests PASS (the bug must be fixed before this criterion is met)
- [ ] File is committed in the worktree

### Dependencies

None.

## Phase 2 -- Statistics functions

### Goal

Add statistics functions that build on the calculator.

### Work Items

- [ ] Create `canary/stats.sh` that sources `calc.sh`
- [ ] `mean` function: takes N numbers, returns their average (integer)
- [ ] `sum` function: takes N numbers, returns their sum
- [ ] Add self-test block:
  - `sum 1 2 3 4 5` should equal `15`
  - `mean 10 20 30` should equal `20`
- [ ] Make executable

### Acceptance Criteria

- [ ] `canary/stats.sh` exists and is executable
- [ ] Self-tests pass
- [ ] File is committed in the worktree

### Dependencies

Phase 1.
