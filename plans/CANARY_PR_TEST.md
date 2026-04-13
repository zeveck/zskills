---
title: PR Mode Canary Test
created: 2026-04-13
status: active
---

# Plan: PR Mode Canary Test

## Overview

Trivial plan to exercise the PR mode pipeline end-to-end: named branch,
persistent worktree, push, `gh pr create`, `.landed` marker. The
implementation is deliberately minimal — we're testing the pipeline, not
the code.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Add canary file | ⬜ | | Trivial file creation |

## Phase 1 -- Add canary file

### Goal

Create a single test file to exercise the PR mode pipeline.

### Work Items

- [ ] Create `canary-test.txt` in the repo root with contents: `PR mode canary test — <timestamp>`
- [ ] Verify the file exists and has the expected contents

### Acceptance Criteria

- [ ] `canary-test.txt` exists with the canary message
- [ ] File is committed in the worktree

### Dependencies

None.
