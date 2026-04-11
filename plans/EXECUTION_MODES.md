---
title: Execution Modes — Landing Strategy + Config File
created: 2026-04-11
status: active
---

# Plan: Execution Modes — Landing Strategy + Config File

## Overview

Add execution mode support across zskills: three landing strategies (cherry-pick, pr, direct) controlled by a project config file (`.claude/zskills-config.json`). The config centralizes the scattered `{{PLACEHOLDER}}` system into a single source of truth. Hook enforcement prevents violations (e.g., `main_protected` blocks direct commits to main). Skills read the config to determine landing behavior; per-invocation arguments override the config default.

Key insight: the landing strategy is orthogonal to isolation. In PR mode, the agent works in a **persistent worktree** on a named feature branch (`feat/<plan-slug>`). The worktree persists across cron turns, accumulating all phases. Main is never modified — no stash/pop needed, no branch checkout in the main working directory. At the end, the agent pushes the feature branch and creates a PR. This leverages the existing worktree exemption (tracking enforcement skips worktrees because `.claude/tracking/` is absent there).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Config File + /update-zskills | ⬚ | | Schema, generation, dogfood |
| 2 — Hook Enforcement | ⬚ | | main_protected, landing mode |
| 3a — Argument Detection + Config Reading | ⬚ | | Mode detection, validation, branch naming |
| 3b — PR Mode Implementation | ⬚ | | Worktree management, dispatch, landing |
| 4 — /fix-issues + /fix-report | ⬚ | | Per-issue PR landing |
| 5 — Pipeline Propagation | ⬚ | | research-and-go, draft-plan, etc. |

---

## Phase 1 — Config File + /update-zskills Integration

### Goal

Create `.claude/zskills-config.json` as the single source of truth for project settings. Modify `/update-zskills` to read the config and generate CLAUDE.md + hooks from it, centralizing the `{{PLACEHOLDER}}` system.

### Work Items

- [ ] Define the config JSON schema with all fields
- [ ] Create the zskills dogfood config at `/workspaces/zskills/.claude/zskills-config.json`
- [ ] Modify `/update-zskills` SKILL.md: Step 2 (auto-detect) now writes/updates the config file. Step 3+ reads config to fill templates.
- [ ] Implement config merge algorithm: read config → auto-detect → for each field, config non-empty wins → auto-detected fills gaps → write merged config back
- [ ] If config exists: read it, merge with auto-detected values, use merged result for template generation
- [ ] If config doesn't exist: auto-detect values (current behavior), WRITE the config, then use it
- [ ] Handle empty config values: when a config value is empty string, the template section containing it gets commented out with a `TODO` marker (e.g., `# TODO: configure unit_cmd in .claude/zskills-config.json`)
- [ ] Test: run /update-zskills on zskills repo, verify generated CLAUDE.md matches config values
- [ ] Test: delete config, run /update-zskills, verify config is created with auto-detected values
- [ ] Test: verify empty-string config values produce commented-out template sections

### Design & Constraints

**Config file location:** `.claude/zskills-config.json` (alongside settings.json)

**Config file format:** Standard pretty-printed JSON (one field per line, 2-space indentation). Must be human-editable.

**Full config schema:**
```json
{
  "project_name": "my-app",
  "timezone": "America/New_York",
  "source_layout": "- `src/` — source code\n- `tests/` — test files",

  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },

  "testing": {
    "unit_cmd": "npm run test",
    "full_cmd": "npm run test:all",
    "output_file": ".test-results.txt",
    "file_patterns": ["tests/**/*.test.js"]
  },

  "dev_server": {
    "cmd": "npm start",
    "port_script": "scripts/port.sh",
    "main_repo_path": "/workspaces/my-app"
  },

  "ui": {
    "file_patterns": "src/(components|editor|ui)/.*\\.(tsx?|css|scss)$",
    "auth_bypass": "localStorage.setItem('auth', 'bypass')"
  }
}
```

**Field details:**

- `execution.landing`: `"cherry-pick"` (default) | `"pr"` | `"direct"`. Controls how agent work reaches main.
- `execution.main_protected`: boolean. When true, hooks block commits, cherry-picks, and pushes on main.
- `execution.branch_prefix`: string. Prefix for auto-generated branch names (default `"feat/"`).
- `testing.*`: replaces `{{UNIT_TEST_CMD}}`, `{{FULL_TEST_CMD}}`, `{{TEST_OUTPUT_FILE}}`, `{{TEST_FILE_PATTERNS}}` placeholders.
- `dev_server.*`: replaces `{{DEV_SERVER_CMD}}`, `{{PORT_SCRIPT}}`, `{{MAIN_REPO_PATH}}` placeholders.
- `ui.*`: replaces `{{UI_FILE_PATTERNS}}`, `{{AUTH_BYPASS}}` placeholders.
- All fields optional. Missing fields -> /update-zskills auto-detects or omits.

**Config merge algorithm (explicit):**

1. Read `.claude/zskills-config.json` (if exists)
2. Auto-detect values from project files (package.json, Cargo.toml, etc.)
3. For each field: if config has a non-empty value, use it; otherwise use auto-detected value
4. Write merged result back to config file
5. Use merged result for template generation

This means: user-set values in config are never overwritten by auto-detection. Auto-detection only fills gaps.

**Empty value handling:**

When a config value is empty string (e.g., `"unit_cmd": ""`), the corresponding template section is commented out:
```markdown
# TODO: configure unit_cmd in .claude/zskills-config.json
# **Capture test output to a file:**
# `{{UNIT_TEST_CMD}} > .test-results.txt 2>&1`
```

**Mapping from config to template placeholders:**

| Config Path | Template Placeholder |
|---|---|
| `project_name` | `{{PROJECT_NAME}}` |
| `timezone` | `{{TIMEZONE}}` |
| `source_layout` | `{{SOURCE_LAYOUT}}` |
| `execution.landing` | (new — no existing placeholder) |
| `execution.main_protected` | (new — no existing placeholder) |
| `execution.branch_prefix` | (new — no existing placeholder) |
| `testing.unit_cmd` | `{{UNIT_TEST_CMD}}` |
| `testing.full_cmd` | `{{FULL_TEST_CMD}}` |
| `testing.output_file` | `{{TEST_OUTPUT_FILE}}` |
| `testing.file_patterns` | `{{TEST_FILE_PATTERNS}}` |
| `dev_server.cmd` | `{{DEV_SERVER_CMD}}` |
| `dev_server.port_script` | `{{PORT_SCRIPT}}` |
| `dev_server.main_repo_path` | `{{MAIN_REPO_PATH}}` |
| `ui.file_patterns` | `{{UI_FILE_PATTERNS}}` |
| `ui.auth_bypass` | `{{AUTH_BYPASS}}` |

**How /update-zskills changes:**

Current flow:
1. Auto-detect values from project files (package.json, etc.)
2. Read CLAUDE_TEMPLATE.md, replace {{PLACEHOLDER}} values
3. Write CLAUDE.md
4. Copy hooks with values filled in

New flow:
1. Check for `.claude/zskills-config.json`
2. If exists: read it. Merge with auto-detected values (config wins, auto-detect fills gaps). Write merged config back.
3. If doesn't exist: auto-detect values, write config file, confirm with user.
4. Read CLAUDE_TEMPLATE.md, replace {{PLACEHOLDER}} values from config. Comment out sections with empty values.
5. Write CLAUDE.md
6. Copy hooks with values filled in from config

**Backward compatibility:** If no config file exists, behavior is identical to current. Auto-detection still works. The config is written as a side-effect so subsequent runs use it.

**Zskills dogfood config** (`.claude/zskills-config.json` for this repo):
```json
{
  "project_name": "zskills",
  "timezone": "America/New_York",
  "source_layout": "Skill distribution repo. skills/ for source definitions, .claude/skills/ for installed copies, hooks/ for hook templates, scripts/ for helpers.",

  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },

  "testing": {
    "unit_cmd": "",
    "full_cmd": "",
    "output_file": ".test-results.txt",
    "file_patterns": []
  },

  "dev_server": {
    "cmd": "",
    "port_script": "scripts/port.sh",
    "main_repo_path": "/workspaces/zskills"
  },

  "ui": {
    "file_patterns": "",
    "auth_bypass": ""
  }
}
```

### Acceptance Criteria

- [ ] `.claude/zskills-config.json` schema defined with all fields documented
- [ ] `/update-zskills` SKILL.md reads config file when present
- [ ] `/update-zskills` SKILL.md auto-detects and writes config when absent
- [ ] Config merge algorithm implemented: config non-empty wins, auto-detect fills gaps
- [ ] Empty config values produce commented-out template sections with TODO markers
- [ ] Config values correctly map to all CLAUDE_TEMPLATE.md placeholders
- [ ] Config values correctly map to hook template placeholders
- [ ] Zskills dogfood config created and committed
- [ ] Backward compatible: running /update-zskills without a config works identically to current behavior
- [ ] Config file is pretty-printed JSON (one field per line, 2-space indent)

### Dependencies

None — this is the foundation phase.

---

## Phase 2 — Hook Enforcement for main_protected

### Goal

Add `main_protected` enforcement to the hook template. When enabled, the hook blocks commits on main, cherry-picks on main, and pushes to main — forcing all landing through PRs.

### Work Items

- [ ] Add main_protected section to `block-unsafe-project.sh.template`
- [ ] Hook reads `main_protected` from `.claude/zskills-config.json` at runtime
- [ ] Block patterns: `git commit` on main, `git cherry-pick` on main, `git push` on main (branch check, not refspec)
- [ ] Allow `git commit` on non-main branches (feature branches, worktree branches)
- [ ] Add test cases to `tests/test-hooks.sh`: main_protected blocks commit/cherry-pick/push on main
- [ ] Add test cases: main_protected allows commit on feature branch
- [ ] Add test cases: main_protected false or absent allows all operations
- [ ] Sync installed hook copy (`.claude/hooks/block-unsafe-project.sh`)

**To disable:** Set `main_protected: false` in `.claude/zskills-config.json`. Takes effect immediately (hook reads config at runtime, not baked in).

### Design & Constraints

**Hook reads config at runtime** (not baked in by /update-zskills). This means changing `main_protected` in the config takes effect immediately without re-running /update-zskills.

**Config reading in bash** (no jq — per cross-platform-hooks plan):
```bash
# Read main_protected from config
MAIN_PROTECTED=false
CONFIG_FILE="$REPO_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null) || CONFIG_CONTENT=""
  if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
    MAIN_PROTECTED=true
  fi
fi
```

**Similarly, read landing mode:**
```bash
LANDING_MODE="cherry-pick"
if [ -f "$CONFIG_FILE" ]; then
  if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    LANDING_MODE="${BASH_REMATCH[1]}"
  fi
fi
```

**Block patterns when main_protected=true:**
```bash
if $MAIN_PROTECTED; then
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
  
  # Block commits on main
  if [ "$CURRENT_BRANCH" = "main" ] && [[ "$INPUT" =~ git[[:space:]]+commit ]]; then
    block_with_reason "BLOCKED: main is protected (main_protected=true in .claude/zskills-config.json). Work on a feature branch instead."
  fi
  
  # Block cherry-picks on main
  if [ "$CURRENT_BRANCH" = "main" ] && [[ "$INPUT" =~ git[[:space:]]+cherry-pick ]]; then
    block_with_reason "BLOCKED: main is protected. Landing is via PR, not cherry-pick. Use 'pr' landing mode."
  fi
  
  # Block push while on main (simple branch check, not refspec matching)
  if [ "$CURRENT_BRANCH" = "main" ] && [[ "$INPUT" =~ git[[:space:]]+push ]]; then
    block_with_reason "BLOCKED: main is protected. Push your feature branch and create a PR."
  fi
fi
```

**Placement in hook:** BEFORE the tracking enforcement section. main_protected is an access check; tracking is a process check. Access first.

**What's NOT blocked:**

- Commits on feature branches (that's the whole point)
- Pushes of feature branches (agent is on feat/x, not main, when pushing)
- `gh pr create` and `gh pr merge` (these are the allowed path)
- `git checkout main` (reading/navigating is fine)
- `git pull` on main (keeping local main up to date)

**Edge case — `landing: "pr"` implies `main_protected: true`?**

No. They're independent. You could have `landing: "pr"` (default to PR) but `main_protected: false` (allow overriding to cherry-pick per-invocation). Enforcement is opt-in.

### Acceptance Criteria

- [ ] Hook reads `main_protected` from config at runtime (not baked in)
- [ ] With `main_protected: true`: `git commit` on main is blocked
- [ ] With `main_protected: true`: `git cherry-pick` on main is blocked
- [ ] With `main_protected: true`: `git push` on main is blocked (using branch check)
- [ ] With `main_protected: true`: `git commit` on feature branches is allowed
- [ ] With `main_protected: true`: `git push` on feature branches is allowed
- [ ] With `main_protected: false` or no config: all current behavior unchanged
- [ ] Hook reads `landing` mode from config (for use by other hook sections)
- [ ] Test cases added to `tests/test-hooks.sh` covering all block/allow scenarios
- [ ] Rollback documented: set `main_protected: false` to disable

### Dependencies

Phase 1 (config file must exist for hook to read).

---

## Phase 3a — Argument Detection + Config Reading

### Goal

Add `pr` and `direct` as recognized arguments to `/run-plan`. Implement config reading, validation, and branch name derivation. This phase is pure detection and plumbing — no mode-specific execution logic.

### Work Items

- [ ] Add `pr` and `direct` keyword detection to /run-plan's arguments section
- [ ] Add config-reading logic: read `execution.landing` from `.claude/zskills-config.json`
- [ ] Implement argument-overrides-config precedence
- [ ] Validate: `direct` argument + `main_protected: true` in config -> reject with explanation
- [ ] Derive branch name for PR mode: `{branch_prefix}{plan-slug}` (deterministic from plan file path)
- [ ] Rename existing `### Execution: main` directive to `### Execution: direct` in /run-plan's SKILL.md
- [ ] Test: `pr` detected case-insensitively from arguments
- [ ] Test: `direct` detected case-insensitively from arguments
- [ ] Test: config default used when no argument provided
- [ ] Test: `direct` + `main_protected: true` rejected

### Design & Constraints

**Argument detection** — same pattern as `auto`, `finish`, `stop`:

Add to the Detection section:
```
- `pr` (case-insensitive) — PR landing mode (persistent worktree + feature branch + PR)
- `direct` (case-insensitive) — direct landing mode (work on main, no worktree)
- Neither -> use config default (`execution.landing`), or `cherry-pick` if no config
```

**Why `direct` not `main`:** The keyword `main` collides with plan file paths containing "main" (e.g., `plans/MAIN_REFACTOR.md`). Using `direct` avoids false matches. All internal references use `direct` consistently: argument keyword, config value, `### Execution: direct` directive.

**Reading config default:**
```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG_FILE="$REPO_ROOT/.claude/zskills-config.json"
LANDING_MODE="cherry-pick"
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null) || CONFIG_CONTENT=""
  if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    LANDING_MODE="${BASH_REMATCH[1]}"
  fi
fi
# Argument overrides config (detect as LAST token to avoid substring false positives)
if [[ "$ARGUMENTS" =~ [[:space:]]pr$ ]] || [[ "$ARGUMENTS" =~ ^pr$ ]]; then LANDING_MODE="pr"; fi
if [[ "$ARGUMENTS" =~ [[:space:]]direct$ ]] || [[ "$ARGUMENTS" =~ ^direct$ ]]; then LANDING_MODE="direct"; fi
```

**Validation:**
```
if LANDING_MODE == "direct" and main_protected == true:
  Report: "Cannot use direct mode — main is protected (main_protected=true in .claude/zskills-config.json). Use 'pr' mode or set main_protected: false."
  Exit.
```

**Branch naming for PR mode:**
```
Plan file: plans/THERMAL_DOMAIN.md
Slug: thermal-domain (lowercase, hyphens)
Branch prefix from config: feat/
Full branch name: feat/thermal-domain
Worktree path: /tmp/zskills-pr-thermal-domain
```
Derivation is deterministic — every cron turn computes the same name from the plan file path. No state to pass between turns.

### Acceptance Criteria

- [ ] `pr` and `direct` detected as arguments (case-insensitive, last-token matching)
- [ ] Config default read from `.claude/zskills-config.json`
- [ ] `direct` + `main_protected: true` -> rejected with clear error
- [ ] Branch name derived deterministically from plan slug + config prefix
- [ ] Worktree path derived deterministically: `/tmp/<project>-pr-<plan-slug>`
- [ ] `### Execution: main` renamed to `### Execution: direct` in SKILL.md
- [ ] Test cases for argument detection, config reading, validation

### Dependencies

Phase 1 (config file for reading defaults), Phase 2 (hooks enforce main_protected).

---

## Phase 3b — PR Mode Implementation

### Goal

Implement PR mode execution using persistent worktrees on named feature branches. Handle worktree lifecycle (create/resume/land), cron turn management, error recovery, and PR creation. Also clean up direct mode as the renamed existing behavior.

### Work Items

- [ ] Implement worktree creation: `git worktree add -b feat/<slug> /tmp/<project>-pr-<slug> main`
- [ ] Implement worktree resume: detect existing worktree, enter it, read progress
- [ ] Handle existing feature branch from failed run (see error recovery below)
- [ ] /run-plan's Phase 2 (implement): dispatch agent to worktree path (no `isolation: "worktree"`)
- [ ] CWD safety: dispatched agents verify CWD with `pwd` as first action
- [ ] /run-plan's Phase 3 (verify): verification runs inside the worktree naturally
- [ ] /run-plan's Phase 4 (update tracker): tracker updates committed in worktree
- [ ] /run-plan's Phase 5 (report): report mentions PR URL when in PR mode
- [ ] /run-plan's Phase 6 (land): push + PR creation with error handling
- [ ] /run-plan's Phase 5c (chunked): cron turn enters existing worktree, reads progress, continues
- [ ] Finish mode: all phases in one session, one worktree, one PR at end
- [ ] Direct mode: clean up existing behavior (rename internal references from "main mode" to "direct mode")
- [ ] Mixed execution mode handling: ban `### Execution: direct` inside a PR-mode plan (reject with error)
- [ ] Write `.landed` marker after PR creation
- [ ] Document cleanup instructions after PR merge
- [ ] Test: PR mode creates worktree with correct branch name
- [ ] Test: PR mode resumes existing worktree across cron turns
- [ ] Test: PR mode creates PR with correct base/head
- [ ] Test: direct mode works same as existing behavior
- [ ] Test: mixed execution modes rejected in PR plans

### Design & Constraints

**PR mode uses persistent worktrees (not branch checkout).**

The branch-checkout approach (stash → checkout → work → checkout main → pop) has three fatal flaws:
1. Stash/pop cycle already caused data loss in this project's history
2. Tracking enforcement fires on feature branch commits in the main working directory (deadlock)
3. Progress tracker on the wrong branch in chunked mode (plan file reverts to stale main version)

Persistent worktrees solve all three:
- Main working directory **never modified** — no stash needed
- Tracking enforcement skipped in worktrees (existing exemption: worktree root lacks `.claude/tracking/`)
- Progress tracker in the worktree is accurate (plan file updated in place)
- Verification runs in the worktree naturally

**Worktree lifecycle:**

```bash
# Deterministic path and branch name (computed from plan file):
PLAN_SLUG="thermal-domain"
BRANCH_NAME="feat/$PLAN_SLUG"
WORKTREE_PATH="/tmp/zskills-pr-$PLAN_SLUG"

# --- Create (first turn) ---
if [ -d "$WORKTREE_PATH" ]; then
  # Worktree already exists — resume (see below)
elif git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
  # Branch exists but no worktree (failed run recovery)
  git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
else
  # Fresh start
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main
fi

# --- Resume (subsequent turns) ---
cd "$WORKTREE_PATH"
pwd  # CWD safety verification
# Read plan file — has accurate progress from previous turns
# Determine next phase, dispatch agent, update progress, commit
```

**Error recovery — existing feature branch from failed run:**

When creating a worktree, if the branch already exists:
1. Check if worktree already exists at the expected path → if yes, enter and resume
2. If branch exists but no worktree: `git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"` (checkout existing branch, don't create new)
3. Compare branch tip with main: if diverged by more than 50 commits, warn the user and ask for confirmation before continuing

**Dispatching agents to the worktree:**

```
Dispatch implementation agent:
  - Working directory: /tmp/zskills-pr-thermal-domain
  - NO isolation: "worktree" (worktree already exists)
  - Agent commits freely to the feature branch
  - Agent's first action: verify CWD with pwd
```

**Chunked turns (cron):**

Each cron turn:
```
1. Compute branch name and worktree path from plan file path (deterministic)
2. Check if worktree exists at /tmp/zskills-pr-<slug>
   - If yes: enter it
   - If no: create it (first turn)
3. Read plan file in worktree (has accurate progress from previous turns)
4. Determine next phase (LLM comprehension of progress tracker)
5. If all phases done -> landing (see below) -> exit
6. Dispatch implementation agent to worktree path (no isolation)
7. Agent works, commits to feature branch in worktree
8. Update plan progress tracker (Phase N -> done)
9. Commit tracker update to feature branch
10. Schedule next turn via CronCreate
```

No stash, no branch checkout in main. Main working directory is untouched throughout.

**Landing (final phase):**

When all phases are complete OR explicit land request:
```bash
cd "$WORKTREE_PATH"

# Check if remote branch already exists
if git ls-remote --exit-code origin "$BRANCH_NAME" >/dev/null 2>&1; then
  git push origin "$BRANCH_NAME"
else
  git push -u origin "$BRANCH_NAME"
fi

# Check if PR already exists for this branch
EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number -q '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  echo "PR #$EXISTING_PR already exists for $BRANCH_NAME"
  PR_URL=$(gh pr view "$EXISTING_PR" --json url -q '.url')
else
  # Check gh authentication
  if ! gh auth status >/dev/null 2>&1; then
    echo "WARNING: gh not authenticated. Branch pushed to origin/$BRANCH_NAME."
    echo "Create PR manually: gh pr create --base main --head $BRANCH_NAME"
  else
    gh pr create \
      --title "feat: Thermal domain support" \
      --body "$(cat <<'EOF'
## Summary
Implements thermal domain support with conduction, convection, and radiation.

### Phases completed
- Phase 1: Core infrastructure
- Phase 2: Component implementation
- Phase 3: Integration tests

## Test plan
- [ ] All unit tests pass
- [ ] Manual verification of thermal blocks

Generated by /run-plan
EOF
    )" \
      --base main \
      --head "$BRANCH_NAME"
    
    # Verify PR was created
    PR_URL=$(gh pr view "$BRANCH_NAME" --json url -q '.url')
    if [ -z "$PR_URL" ]; then
      echo "ERROR: PR creation may have failed. Check: gh pr list --head $BRANCH_NAME"
    fi
  fi
fi
```

PR title derived from plan title. PR body includes phase summary and test plan.

**`.landed` marker for PR mode:**

```bash
cat > "$WORKTREE_PATH/.landed" <<LANDED
status: full
method: pr
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
branch: $BRANCH_NAME
pr: $PR_URL
LANDED
```

Uses `status: full` with `method: pr` field (not a new status value). This is compatible with existing cleanup tooling that checks for `status: full`.

**Cleanup after PR merge:**

After PR creation, the worktree and branch remain for user review. After the PR merges:
```bash
# User or cleanup automation runs:
git worktree remove /tmp/zskills-pr-thermal-domain
git branch -d feat/thermal-domain
```

The `.landed` marker with `status: full` signals that cleanup is safe. The `method: pr` field tells cleanup tools to verify the PR is merged before removing.

**Cron scheduling in PR mode:**

Phase 5c works identically to cherry-pick mode: schedule next turn via CronCreate. Each turn enters the existing worktree. The final turn creates the PR instead of cherry-picking. No cron scheduled after the final turn.

**Direct mode — /run-plan's Phase 2 and Phase 6:**

Direct mode is the existing `### Execution: direct` behavior (formerly `### Execution: main`), now available as a top-level argument:
- Phase 2: dispatch without `isolation: "worktree"`, agent works on main, commits directly
- Phase 6: no-op (work already on main)
- No branch creation, no PR, no cherry-pick

**Cherry-pick mode (default, unchanged):**

Current behavior. Worktree isolation, cherry-pick to main, `.landed` marker.

**Mixed execution modes in PR plans:**

If the top-level mode is `pr` and an individual phase says `### Execution: direct`, this is **rejected with an error**:
```
ERROR: Phase 3 uses '### Execution: direct' but plan-level mode is 'pr'.
Mixed execution modes are not supported in PR plans. All phases must
use the PR worktree. Remove the '### Execution: direct' directive or
switch to cherry-pick mode.
```

Exception: `### Execution: delegate` is always allowed (delegate skills manage their own isolation regardless of plan-level mode).

**Non-chunked `finish` mode with PR:**

In non-chunked `finish auto pr`: all phases run in one session in the persistent worktree. The orchestrator creates the worktree once, runs all phases sequentially, then pushes + PRs at the end. Simpler than chunked because no cron turns to manage.

### Acceptance Criteria

- [ ] PR mode: persistent worktree created with correct branch name at deterministic path
- [ ] PR mode: existing worktree resumed across cron turns
- [ ] PR mode: existing branch without worktree recovered correctly
- [ ] PR mode: agent dispatched to worktree path, commits on feature branch
- [ ] PR mode: main working directory unchanged during pipeline execution
- [ ] PR mode: `git push -u origin <branch>` + `gh pr create` at end
- [ ] PR mode: error handling for push failure, existing PR, gh auth failure
- [ ] PR mode: progress tracker accurate across chunked cron turns
- [ ] PR mode: `.landed` marker written with `status: full` and `method: pr`
- [ ] PR mode: mixed `### Execution: direct` rejected in PR plans
- [ ] PR mode: `### Execution: delegate` still allowed in PR plans
- [ ] Direct mode: works same as existing behavior (renamed from "main mode")
- [ ] Cherry-pick mode: fully backward compatible (default)
- [ ] Finish mode: one worktree, all phases, one PR
- [ ] CWD safety: dispatched agents verify working directory
- [ ] Test cases for worktree creation, resume, landing, error recovery

### Dependencies

Phase 3a (argument detection, branch naming), Phase 1 (config), Phase 2 (hooks).

---

## Phase 4 — /fix-issues + /fix-report PR Landing

### Goal

Add PR landing support to `/fix-issues` and `/fix-report`. In PR mode, each issue gets its own branch and PR with "Fixes #NNN" linking. One PR per issue, not one PR for the whole sprint.

### Work Items

- [ ] Add `pr` and `direct` keyword detection to /fix-issues arguments
- [ ] Read config default (same pattern as /run-plan in Phase 3a)
- [ ] /fix-issues Phase 3 (execute): create per-issue worktrees with named branches using `git worktree add -b`
- [ ] Dispatch agents pointing to worktree paths (no `isolation: "worktree"`)
- [ ] /fix-issues Phase 6 (land) with `auto pr`: push each branch + create PR per issue
- [ ] /fix-issues Phase 6 without `auto`: defer to /fix-report (existing behavior)
- [ ] PR body template: include issue title, fix description, test results, "Fixes #NNN"
- [ ] /fix-report: PR-aware review flow — check PR status, merge/close PRs
- [ ] Sprint report: include PR URLs instead of cherry-pick commit hashes
- [ ] Test: per-issue worktrees created with correct branch names
- [ ] Test: parallel agents work in separate worktrees
- [ ] Test: PR creation includes "Fixes #NNN" linking
- [ ] Test: /fix-report reads PR status correctly

### Design & Constraints

**Branch naming per issue:**
```
Issue #123: "Parser error on empty input"
Branch: fix/issue-123
Worktree: /tmp/fix-issue-123
```
Simple, deterministic, human-readable.

**Per-issue worktrees with named branches:**

/fix-issues dispatches PARALLEL agents (up to 3 at a time). Use `git worktree add -b` to create each worktree with a named branch directly:

```bash
# For each issue in the batch:
git worktree add -b fix/issue-123 /tmp/fix-issue-123 main
git worktree add -b fix/issue-456 /tmp/fix-issue-456 main

# Dispatch agents pointing to these worktree paths (no isolation: "worktree")
# Agents work in parallel, each in their own worktree

# After agents return — worktrees persist until landing
```

This is cleaner than the branch-rename approach (`git branch -m` inside a worktree). Named branches are created upfront, and the worktree path is deterministic.

**Phase 6 (land) in PR mode:**
```bash
for each worktree with successful fixes:
  cd /tmp/fix-issue-$ISSUE_NUM
  BRANCH=$(git branch --show-current)
  
  # Push with error handling
  if ! git push -u origin "$BRANCH"; then
    echo "ERROR: Failed to push $BRANCH. Skipping PR creation."
    continue
  fi
  
  # Check for existing PR
  EXISTING_PR=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)
  if [ -n "$EXISTING_PR" ]; then
    echo "PR #$EXISTING_PR already exists for $BRANCH"
    PR_URL=$(gh pr view "$EXISTING_PR" --json url -q '.url')
  else
    gh pr create \
      --title "Fix #$ISSUE_NUM: $ISSUE_TITLE" \
      --body "$(cat <<EOF
Fixes #$ISSUE_NUM

## What changed
$FIX_DESCRIPTION

## Test results
$TEST_RESULTS

Generated by /fix-issues sprint
EOF
    )" \
      --base main \
      --head "$BRANCH"
    
    PR_URL=$(gh pr view "$BRANCH" --json url -q '.url')
  fi
  
  # Write .landed marker
  cat > "/tmp/fix-issue-$ISSUE_NUM/.landed" <<LANDED
status: full
method: pr
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
branch: $BRANCH
pr: $PR_URL
LANDED
done
```

**Sprint report changes:**

Current report has cherry-pick columns. PR mode adds PR URL:
```markdown
### Fixed
| # | Title | Branch | PR |
|---|-------|--------|-----|
| #123 | Parser error | fix/issue-123 | https://github.com/owner/repo/pull/45 |
```

**/fix-report PR-aware flow:**

Currently /fix-report reviews worktrees and cherry-picks. In PR mode:
1. Check PR status for each fix: `gh pr view fix/issue-NNN --json state`
2. Present: "PR #45 for issue #123 — open/merged/closed"
3. Options: merge PR (`gh pr merge --squash`), close PR (`gh pr close`), request changes
4. After merging: clean up worktree + branch (`git worktree remove /tmp/fix-issue-NNN && git branch -d fix/issue-NNN`)

### Acceptance Criteria

- [ ] `pr` and `direct` detected as /fix-issues arguments
- [ ] Per-issue worktrees created with `git worktree add -b fix/issue-NNN`
- [ ] Parallel agents work (separate worktrees, no branch checkout conflicts)
- [ ] Phase 6 auto pr: push + PR per issue with "Fixes #NNN"
- [ ] Error handling: push failure, existing PR, gh auth failure
- [ ] Sprint report includes PR URLs
- [ ] /fix-report can check PR status and merge/close
- [ ] `.landed` marker with `status: full` and `method: pr`
- [ ] Cherry-pick mode: fully backward compatible

### Dependencies

Phase 1 (config), Phase 2 (hooks), Phase 3a (argument detection pattern).

---

## Phase 5 — Pipeline Propagation

### Goal

Propagate landing mode through the pipeline skills: `/research-and-go`, `/research-and-plan`, `/draft-plan`, `/do`, `/commit`. Document execution modes in CLAUDE_TEMPLATE.md.

### Work Items

- [ ] `/research-and-go`: detect `pr`/`direct` as standalone last token in goal description, pass to /run-plan cron prompt
- [ ] `/research-and-plan`: pass landing mode context to /draft-plan invocations
- [ ] `/draft-plan`: when config specifies a non-default landing mode, embed hint in generated plan's Design & Constraints section
- [ ] `/do`: add `pr` option — creates worktree with named branch, works, pushes, PRs. Slug derived from task description (lowercase, hyphens, max 40 chars).
- [ ] `/commit`: add `pr` subcommand — push current branch + create PR. Edge cases: on main (error: "create a feature branch first"), detached HEAD (error), no commits ahead of main (error: "nothing to PR")
- [ ] CLAUDE_TEMPLATE.md: add "Execution Modes" section documenting the three landing strategies
- [ ] Update /update-zskills audit: add key phrases for execution mode rules
- [ ] Test: `/research-and-go` correctly appends `pr`/`direct` to cron prompt
- [ ] Test: `/do pr` creates worktree, works, pushes, creates PR
- [ ] Test: `/commit pr` on main branch produces error
- [ ] Test: `/commit pr` with no commits ahead of main produces error

### Design & Constraints

**/research-and-go changes:**

Detect landing mode as a standalone last token in the goal description (case-insensitive). Use word-boundary matching to avoid false positives (e.g., "improve **pr**inting" should not match):
```bash
# Match "pr" or "direct" only as standalone last token
if [[ "$ARGUMENTS" =~ [[:space:]]pr$ ]] || [[ "$ARGUMENTS" =~ ^pr$ ]]; then
  LANDING_SUFFIX="pr"
elif [[ "$ARGUMENTS" =~ [[:space:]]direct$ ]] || [[ "$ARGUMENTS" =~ ^direct$ ]]; then
  LANDING_SUFFIX="direct"
fi
```

Include in the cron prompt:
```
prompt: "Run /run-plan <meta-plan-path> finish auto pr"
# or "... finish auto direct" for direct mode
# or "... finish auto" for cherry-pick (default)
```

The landing mode propagates through the cron to /run-plan, which handles it.

**/research-and-plan changes:**

When invoking `/draft-plan` for each sub-plan, pass the landing mode as context:
```
When generating plans, note that this project uses PR-based landing
(configured in .claude/zskills-config.json). Generated plans should
not include cherry-pick instructions.
```

**/draft-plan changes:**

When the config specifies `landing: "pr"`, include in generated plans:
```markdown
### Design & Constraints
...
**Landing:** This project uses PR-based landing. Each sub-plan's work
accumulates on a feature branch in a persistent worktree and lands via PR.
Do not cherry-pick to main.
```

This is a hint, not a directive. The `/run-plan` argument (or config default) controls actual behavior.

**/do changes:**

`/do` already supports `worktree` and `push`. Add `pr`:
```
/do Fix the button offset pr
```

Creates worktree with named branch `feat/fix-button-offset` at `/tmp/<project>-do-fix-button-offset`, works, commits, pushes, creates PR. Slug derived from task description: lowercase, hyphens, max 40 chars, stripped of stop words.

**/commit changes:**

Add `pr` subcommand:
```
/commit pr
```

Edge cases:
- On main branch: error "Cannot create PR from main. Create a feature branch first."
- Detached HEAD: error "Cannot create PR from detached HEAD."
- No commits ahead of main (`git log main..HEAD` empty): error "No commits ahead of main. Nothing to PR."
- Happy path: pushes current branch, creates PR with auto-generated title from branch name.

**CLAUDE_TEMPLATE.md changes:**

Add after the Git Rules section:
```markdown
## Execution Modes

Landing strategy is configured in `.claude/zskills-config.json` under
`execution.landing`. Three modes:

- **cherry-pick** (default) — Agent works in a worktree. Cherry-picks to main to land.
- **pr** — Agent works in a persistent worktree on a feature branch. Pushes branch and creates a PR to land. Main stays untouched until PR merges.
- **direct** — Agent works directly on main. Commits land immediately.

Override per-invocation: `/run-plan plans/X.md finish auto pr`

When `execution.main_protected` is true, hooks block direct commits,
cherry-picks, and pushes to main. All landing must go through PRs.
```

### Acceptance Criteria

- [ ] `/research-and-go` passes landing mode through cron prompt (standalone last-token detection)
- [ ] `/research-and-plan` passes mode context to /draft-plan
- [ ] `/draft-plan` includes landing hints in generated plans when applicable
- [ ] `/do pr` works end-to-end (worktree with named branch, work, push, PR)
- [ ] `/do pr` slug derivation: lowercase, hyphens, max 40 chars
- [ ] `/commit pr` pushes and creates PR from current branch
- [ ] `/commit pr` error cases handled: on main, detached HEAD, no commits ahead
- [ ] CLAUDE_TEMPLATE.md documents execution modes
- [ ] /update-zskills audit checks for execution mode rules

### Dependencies

Phase 1 (config), Phase 3b (/run-plan PR mode implementation for testing).

---

## Key Rules

- **Backward compatible.** No config = current behavior (cherry-pick). Nothing breaks for existing users.
- **Config is source of truth.** /update-zskills reads it, hooks read it, skills read it. One place for settings.
- **Arguments override config.** `/run-plan ... pr` overrides `landing: "cherry-pick"` in config.
- **main_protected is access control.** It blocks actions on main regardless of landing mode or `auto` flag.
- **Persistent worktree = isolation in PR mode.** The feature branch lives in a worktree at `/tmp/<project>-pr-<slug>`. Main working directory is never modified.
- **One worktree per plan, one worktree per issue.** Plans accumulate phases in one persistent worktree. Issues get individual worktrees with named branches.
- **Deterministic paths and branch names.** Derived from plan slug or issue number. No state to pass between turns.
- **`direct` not `main`.** The argument keyword is `direct` to avoid collision with plan paths containing "main".
- **No mixed modes in PR plans.** If plan-level mode is `pr`, individual phases cannot use `### Execution: direct`. Delegate is always allowed.
- **`.landed` marker uses `method: pr`.** Standard `status: full` with additional `method: pr`, `branch:`, and `pr:` fields. Compatible with existing cleanup tooling.
