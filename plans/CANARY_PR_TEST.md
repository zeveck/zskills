---
title: PR Mode Canary Test
created: 2026-04-13
status: active
---

# Plan: PR Mode Canary Test

## Overview

Multi-phase canary to exercise the PR mode pipeline end-to-end: persistent
worktree across phases, multiple commits accumulating on one branch, rebase
between phases, existing PR detection, and `.landed` marker writing.

The implementation is deliberately minimal — we're testing the pipeline,
not the code. All files go in a `canary/` directory for easy cleanup.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Hello script | ⬜ | | Create canary/hello.sh |
| 2 -- Math functions | ⬜ | | Create canary/math.sh |
| 3 -- README | ⬜ | | Create canary/README.md, push, PR update |

## Phase 1 -- Hello script

### Goal

Create a simple shell script in the canary directory.

### Work Items

- [ ] Create `canary/hello.sh` with a hello-world function and a self-test
- [ ] Make it executable (`chmod +x`)
- [ ] Run it to verify output

### Acceptance Criteria

- [ ] `canary/hello.sh` exists, is executable, and prints "Hello from canary!"
- [ ] File is committed in the worktree

### Dependencies

None.

## Phase 2 -- Math functions

### Goal

Add arithmetic functions to test multi-commit accumulation on the branch.

### Work Items

- [ ] Create `canary/math.sh` with `add` and `multiply` functions
- [ ] Add a self-test block that verifies `add 2 3` returns 5 and `multiply 4 5` returns 20
- [ ] Make it executable
- [ ] Run it to verify

### Acceptance Criteria

- [ ] `canary/math.sh` exists, is executable, self-test passes
- [ ] File is committed in the worktree (second commit on same branch)

### Dependencies

Phase 1.

## Phase 3 -- README

### Goal

Add a README and land the PR.

### Work Items

- [ ] Create `canary/README.md` describing the canary test files
- [ ] Verify all three files exist in the worktree

### Acceptance Criteria

- [ ] `canary/README.md` exists
- [ ] All three canary files committed on the branch
- [ ] PR updated (not duplicated) with all commits

### Dependencies

Phase 2.
