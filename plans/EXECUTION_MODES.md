---
title: Execution Modes
created: 2026-04-12
status: active
---

# Plan: Execution Modes

## Overview

Add three landing modes to zskills skills: **cherry-pick** (default, existing behavior), **PR** (push feature branch + `gh pr create`), and **direct** (work on main, no landing step). Includes a config file (`.claude/zskills-config.json`) that `/update-zskills` reads, a `main_protected` hook that blocks commits/cherry-picks/pushes to main, and propagation through the skill chain (`/run-plan`, `/fix-issues`, `/research-and-go`, `/draft-plan`, `/do`, `/commit`, `/research-and-plan`).

The tracking system is DONE and working. This plan builds on top of it. Tracking uses `.zskills/tracking/`, pipeline association uses `.zskills-tracked` in worktrees and `ZSKILLS_PIPELINE_ID=` in transcripts, and verification agents commit (not impl agents).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Config File + /update-zskills | ⬜ | | Schema, dogfood config, template merge |
| 2 -- main_protected Hook Enforcement | ⬜ | | Access control, separate from tracking; push hook fix |
| 3a -- Argument Detection + Config Reading + Direct Mode | ⬜ | | Small: detection, config, direct mode |
| 3b -- PR Mode Implementation | ⬜ | | Large: persistent worktree, push+PR landing |
| 4 -- /fix-issues PR Landing | ⬜ | | Per-issue branches, PR creation |
| 5 -- Pipeline Propagation | ⬜ | | research-and-go, research-and-plan, draft-plan, do, commit, CLAUDE_TEMPLATE |

---

## Phase 1 -- Config File + /update-zskills

### Goal

Define the `.claude/zskills-config.json` schema, create the zskills dogfood config, and modify `/update-zskills` to read the config, merge with auto-detected values, and fill CLAUDE_TEMPLATE.md and hook templates from config values instead of raw placeholders.

### Work Items

#### 1.1 -- Define `.claude/zskills-config.json` schema

Create `.claude/zskills-config.json` for the zskills repo itself (dogfood). The schema:

```json
{
  "project_name": "zskills",
  "timezone": "America/New_York",
  "source_layout": "skills/ — skill definitions, hooks/ — hook scripts, scripts/ — helpers",

  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },

  "testing": {
    "unit_cmd": "bash tests/test-hooks.sh",
    "full_cmd": "bash scripts/test-all.sh",
    "output_file": ".test-results.txt",
    "file_patterns": ["tests/**/*.sh"]
  },

  "dev_server": {
    "cmd": "",
    "port_script": "",
    "main_repo_path": "/workspaces/zskills"
  },

  "ui": {
    "file_patterns": "",
    "auth_bypass": ""
  }
}
```

**Allowed values for `execution.landing`:** `"cherry-pick"` (default), `"pr"`, `"direct"`.

**Allowed values for `execution.main_protected`:** `true`, `false` (default).

**`execution.branch_prefix`:** String prepended to plan slug for branch names. Default `"feat/"`. Examples: `"feat/"`, `"agent/"`, `""` (empty string = no prefix).

- [ ] Create `.claude/zskills-config.json` with the zskills dogfood values above
- [ ] Verify the file is valid JSON: `python3 -c "import json; json.load(open('.claude/zskills-config.json'))"`

#### 1.2 -- Add config reading to `/update-zskills`

Modify `skills/update-zskills/SKILL.md` to add a config-reading step that runs after Step 0 (Locate Portable Assets) and before the Audit.

The skill text must instruct the agent to:

1. Check if `.claude/zskills-config.json` exists in the target project root.
2. If it exists, read it and extract values for template filling.
3. If it does not exist, auto-detect values from the project (current behavior).
4. Apply the **merge algorithm**: for each config field, config non-empty string wins; auto-detected value fills gaps; empty string means "not applicable."

Add this section after Step 0 in `skills/update-zskills/SKILL.md`:

```markdown
## Step 0.5 — Read Config

Check if `.claude/zskills-config.json` exists in the target project root (`$PROJECT_ROOT`).

**If it exists:**
1. Read the file content.
2. Extract values using bash regex (no jq dependency):
   ```bash
   CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
   # Extract a string value (note: ([^\"]*) allows empty strings):
   if [[ "$CONFIG_CONTENT" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     UNIT_CMD="${BASH_REMATCH[1]}"
   fi
   # Extract a boolean value:
   if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
     MAIN_PROTECTED="${BASH_REMATCH[1]}"
   fi
   ```
3. For each template placeholder, use the config value if non-empty.

**If it does not exist:**
1. Auto-detect values from the project (existing behavior).
2. Present the auto-detected values to the user and instruct them to create
   the config file:
   ```
   ! cat > .claude/zskills-config.json <<'EOF'
   { ... auto-detected values ... }
   EOF
   ```
   **Important:** `.claude/zskills-config.json` is protected by Claude Code's
   built-in permission system — agent writes trigger a prompt. Since `/update-zskills`
   runs interactively with the user, the user approves the prompt. The agent presents the values and instructs
   the user to create the file using the `!` prefix (user action).

**Merge algorithm pseudocode:**
```
for each field F in schema:
  if config[F] is non-empty string (or true/false for booleans):
    use config[F]
  else if auto_detect[F] is non-empty:
    use auto_detect[F]
  else:
    mark as empty → template section gets commented out
```
```

- [ ] Add Step 0.5 to `skills/update-zskills/SKILL.md` after Step 0
- [ ] Add extraction examples for all config fields used by templates
- [ ] Config creation uses `!` user-action prefix (agent cannot write config directly)

#### 1.3 -- Template filling from config

Modify the template-filling logic in `/update-zskills` to use config values. The placeholders in `CLAUDE_TEMPLATE.md` and `hooks/block-unsafe-project.sh.template` that map to config fields:

| Placeholder | Config path | Example |
|-------------|-------------|---------|
| `{{UNIT_TEST_CMD}}` | `testing.unit_cmd` | `npm run test` |
| `{{FULL_TEST_CMD}}` | `testing.full_cmd` | `npm run test:all` |
| `{{UI_FILE_PATTERNS}}` | `ui.file_patterns` | `src/(components|ui)/.*\\.tsx?$` |
| `{{DEV_SERVER_CMD}}` | `dev_server.cmd` | `npm start` |
| `{{PORT_SCRIPT}}` | `dev_server.port_script` | `scripts/port.sh` |
| `{{MAIN_REPO_PATH}}` | `dev_server.main_repo_path` | `/workspaces/my-app` |
| `{{AUTH_BYPASS}}` | `ui.auth_bypass` | `localStorage.setItem(...)` |

**Empty value handling:** When a config field is empty string `""`, the corresponding template section is commented out with a TODO marker:

```bash
# Example: if UI_FILE_PATTERNS is empty, comment out the UI verification section
# in block-unsafe-project.sh:
#
# Before:
#   UI_FILE_PATTERNS="src/components/.*\.tsx?$"
#   if [[ "$UI_FILE_PATTERNS" != ... ]]; then
#     ...
#   fi
#
# After (empty):
#   # TODO: Configure UI file patterns in .claude/zskills-config.json
#   # UI_FILE_PATTERNS=""
```

The existing template already handles unconfigured placeholders (checks for `{{` prefix), so this is backward compatible. The config just provides cleaner values.

- [ ] Update `/update-zskills` template-filling instructions to use config values
- [ ] Ensure empty config values produce commented-out sections with TODO markers
- [ ] Verify backward compatibility: no config = auto-detect (unchanged behavior)

#### 1.4 -- Sync installed copies

After modifying source files, sync the installed copies:

- [ ] Copy `skills/update-zskills/SKILL.md` to `.claude/skills/update-zskills/SKILL.md`
- [ ] Verify installed copy matches source: `diff skills/update-zskills/SKILL.md .claude/skills/update-zskills/SKILL.md`

### Design & Constraints

- **No jq dependency.** All JSON reading uses bash regex. The config is flat enough that `[[ "$content" =~ \"key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]` works for strings (note `*` not `+` to allow empty strings) and `[[ "$content" =~ \"key\"[[:space:]]*:[[:space:]]*(true|false) ]]` works for booleans. **Caveat:** bash regex may match the wrong key if two keys share a suffix (e.g., `"landing"` could match inside a longer key). This is acceptable for the current flat schema but should be improved if the config grows nested objects with ambiguous key names.
- **Claude Code-protected.** `.claude/zskills-config.json` is protected by Claude Code's built-in permission system on all tools (Bash, Write, Edit). Agent writes trigger a permission prompt. No custom hook needed.
- **Config is optional.** No config = current behavior. Config is a progressive enhancement.
- **Config created by user action.** When no config exists, `/update-zskills` auto-detects values and presents them to the user with instructions to create the file using `! cat > .claude/zskills-config.json <<'EOF' ... EOF`.

### Acceptance Criteria

- [ ] `.claude/zskills-config.json` exists in zskills repo with valid JSON
- [ ] `skills/update-zskills/SKILL.md` has Step 0.5 that reads config
- [ ] Template placeholders map to config fields
- [ ] Empty config values produce commented-out template sections
- [ ] No config = auto-detect (backward compatible)
- [ ] Config creation uses user action, not agent write
- [ ] Installed skill copy synced

### Dependencies

None. This is the foundation phase.

---

## Phase 2 -- main_protected Hook Enforcement

### Goal

Add `main_protected` enforcement to `hooks/block-unsafe-project.sh.template`. When `execution.main_protected: true` in `.claude/zskills-config.json`, block `git commit` on main, `git cherry-pick` on main, and `git push` to main. Allow everything on feature branches. This is ACCESS CONTROL, separate from tracking (PROCESS CONTROL).

Also fix the push tracking hook's code-files detection to work before upstream is set (`@{u}` fails before first `git push -u`).

### Work Items

#### 2.1 -- Add main_protected check function

Insert a helper function near the top of `hooks/block-unsafe-project.sh.template` (after the `block_with_reason` and `extract_transcript` functions) that reads `main_protected` from config at runtime:

```bash
# ─── main_protected access control ───
# Reads config at runtime (not baked in during /update-zskills).
# Changing the config takes effect immediately.
is_main_protected() {
  local config_file
  local repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  config_file="$repo_root/.claude/zskills-config.json"
  if [ -f "$config_file" ]; then
    local content
    content=$(cat "$config_file" 2>/dev/null) || return 1
    if [[ "$content" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      return 0
    fi
  fi
  return 1
}

is_on_main() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ "$branch" == "main" || "$branch" == "master" ]]
}
```

- [ ] Add `is_main_protected` function to hook template
- [ ] Add `is_on_main` function to hook template
- [ ] Functions use bash regex only (no jq)
- [ ] Config is read at runtime (not baked in)

#### 2.2 -- Block git commit on main when protected

Insert before the existing `git commit` block (which handles test checks and tracking enforcement). The main_protected check must come first because it is a hard block — no exemptions for content-only commits.

```bash
# ─── main_protected: block git commit on main ───
if [[ "$INPUT" =~ git[[:space:]]+commit ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Create a feature branch or use PR mode. To change: edit .claude/zskills-config.json"
fi
```

- [ ] Add git commit block before existing commit checks
- [ ] Block fires before test/tracking checks (hard block, no exemptions)

#### 2.3 -- Block git cherry-pick on main when protected

Insert before the existing `git cherry-pick` block:

```bash
# ─── main_protected: block git cherry-pick on main ───
if [[ "$INPUT" =~ git[[:space:]]+cherry-pick ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Cherry-pick to a feature branch instead. To change: edit .claude/zskills-config.json"
fi
```

- [ ] Add git cherry-pick block before existing cherry-pick checks

#### 2.4 -- Block git push to main when protected

Insert before the existing `git push` block. This checks if the push target is main:

```bash
# ─── main_protected: block git push to main ───
if [[ "$INPUT" =~ git[[:space:]]+push([[:space:]]|\") ]] && is_main_protected; then
  # Check if pushing to main/master (explicit refspec or default branch)
  if is_on_main; then
    # On main branch, default push targets main
    if [[ ! "$INPUT" =~ origin[[:space:]]+[a-zA-Z] ]] || [[ "$INPUT" =~ origin[[:space:]]+(main|master) ]]; then
      block_with_reason "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
    fi
  fi
fi
```

Note: the push regex uses `([[:space:]]|\")` to match the existing push tracking hook pattern (line 346 of the current template).

- [ ] Add git push block that detects push-to-main
- [ ] Push regex uses `([[:space:]]|\")` consistent with existing pattern

#### 2.5 -- Fix push tracking hook: code-files detection before upstream

The existing push tracking hook (line 378) uses `@{u}..HEAD` to find code files, which fails before the first `git push -u` (no upstream set). Fix: use `git diff main..HEAD` as fallback when `@{u}` is not available.

```bash
# In the existing git push tracking block, replace:
#   PUSH_DIFF=$(git diff --name-only @{u}..HEAD 2>/dev/null)
# With:
PUSH_DIFF=$(git diff --name-only @{u}..HEAD 2>/dev/null)
if [ -z "$PUSH_DIFF" ]; then
  # Fallback: compare against main (works before first push -u)
  PUSH_DIFF=$(git diff --name-only main..HEAD 2>/dev/null)
fi
```

- [ ] Add fallback from `@{u}..HEAD` to `main..HEAD` for code-files detection
- [ ] Verify: push tracking works on branches that have never been pushed

#### 2.6 -- Sync installed hook copy

After modifying the template, sync the installed copy:

```bash
# Copy template to installed location, replacing placeholders with current values
cp hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh
# Then apply current placeholder values from the installed copy
```

The sync process: read the existing installed copy to extract current placeholder values (grep for the `UNIT_TEST_CMD=`, `FULL_TEST_CMD=`, `UI_FILE_PATTERNS=` assignments), then copy the template and replace placeholders with those values.

- [ ] Sync installed hook copy with template
- [ ] Verify: `diff <(grep -v '^#.*CONFIGURE' hooks/block-unsafe-project.sh.template) <(grep -v '^#.*CONFIGURE' .claude/hooks/block-unsafe-project.sh)` shows only placeholder differences

#### 2.7 -- Tests

Add tests to `tests/test-hooks.sh` for main_protected enforcement. Write full test bodies (no stubs):

```bash
# Test: main_protected blocks commit on main
test_main_protected_blocks_commit_on_main() {
  setup_project_test
  # Create config with main_protected: true
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  # Simulate being on main branch
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_blocked "$RESULT" "main branch is protected"
}

# Test: main_protected allows commit on feature branch
test_main_protected_allows_commit_on_feature_branch() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b feat/test
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_allowed "$RESULT"
}

# Test: main_protected false allows commit on main
test_main_protected_false_allows_commit_on_main() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": false}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  # Should not be blocked by main_protected (may be blocked by other checks)
  [[ "$RESULT" != *"main branch is protected"* ]] || fail "Should not block when main_protected is false"
}

# Test: no config file allows commit on main
test_no_config_allows_commit_on_main() {
  setup_project_test
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  [[ "$RESULT" != *"main branch is protected"* ]] || fail "Should not block when no config"
}

# Test: main_protected blocks cherry-pick on main
test_main_protected_blocks_cherry_pick_on_main() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git cherry-pick abc123"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_blocked "$RESULT" "main branch is protected"
}

# Test: main_protected blocks push to main
test_main_protected_blocks_push_to_main() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_blocked "$RESULT" "Cannot push to main"
}

# Test: push tracking works before first push (no upstream)
test_push_tracking_no_upstream() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills/tracking"
  cd "$TEST_TMPDIR" && git init && git checkout -b feat/test
  # Create a tracking marker so enforcement is active
  echo "test-pipeline" > "$TEST_TMPDIR/.zskills-tracked"
  touch "$TEST_TMPDIR/.zskills/tracking/step.phase1.test-pipeline.implement"
  # No upstream set — @{u} will fail, should fall back to main..HEAD
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat/test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" LOCAL_ROOT="$TEST_TMPDIR" bash "$HOOK")
  # Should attempt enforcement (may block on missing verify, that's correct)
  echo "$RESULT"  # For debugging
}
```

- [ ] Add at least 7 tests: commit/cherry-pick/push on main blocked, commit on feature branch allowed, main_protected false allowed, no config allowed, push tracking without upstream
- [ ] All test bodies are complete (no empty stubs)
- [ ] Run tests: `bash tests/test-hooks.sh > .test-results.txt 2>&1`
- [ ] All tests pass (including pre-existing tests)

### Design & Constraints

- **Runtime config read.** The hook reads `main_protected` from `.claude/zskills-config.json` at runtime, NOT baked in during `/update-zskills`. Changing the config takes effect immediately without re-running `/update-zskills`.
- **ACCESS CONTROL vs PROCESS CONTROL.** `main_protected` is access control (who can write to main). Tracking enforcement is process control (did you follow the workflow). Both can be active simultaneously and are independent. Ordering: main_protected fires first (hard block), then tracking enforcement fires (process block). If both are active on main, the user sees the main_protected error first.
- **No exemptions.** When `main_protected` is true, ALL commits/cherry-picks/pushes to main are blocked, including content-only commits. The point is to force PR-based workflow.
- **Backward compatible.** No config file = no protection (current behavior).
- **Push regex consistency.** Use `([[:space:]]|\")` pattern for push detection, matching the existing hook's pattern on line 346.

### Acceptance Criteria

- [ ] `is_main_protected` reads config at runtime with bash regex
- [ ] `git commit` on main blocked when `main_protected: true`
- [ ] `git cherry-pick` on main blocked when `main_protected: true`
- [ ] `git push` to main blocked when `main_protected: true`
- [ ] All three allowed on feature branches when `main_protected: true`
- [ ] All three allowed on main when `main_protected: false` or no config
- [ ] Push tracking code-files detection works before first push (fallback to `main..HEAD`)
- [ ] At least 7 new tests pass with full bodies
- [ ] Pre-existing tests still pass
- [ ] Installed hook copy synced

### Dependencies

Phase 1 (config file must exist for dogfood testing, though the hook also handles missing config).

---

## Phase 3a -- Argument Detection + Config Reading + Direct Mode

### Goal

Add `pr` and `direct` landing mode argument detection to `/run-plan`, config-based default reading, and direct mode implementation. This is the small, self-contained foundation that Phase 3b builds on.

### Work Items

#### 3a.1 -- Argument detection

Add `pr` and `direct` to the argument detection block in `skills/run-plan/SKILL.md`. Same pattern as `auto`, `finish`, `stop` — case-insensitive, last token.

Add to the "Detection" section (after the existing `auto` detection):

```markdown
- `pr` (case-insensitive) — PR landing mode
- `direct` (case-insensitive) — direct landing mode
- Neither `pr` nor `direct` — read config default (`execution.landing`),
  or `cherry-pick` if no config

**Landing mode resolution:**
1. Explicit argument wins: `pr` or `direct` in $ARGUMENTS
2. Config default: read `.claude/zskills-config.json` `execution.landing` field
3. Fallback: `cherry-pick`

```bash
# Detect landing mode
LANDING_MODE="cherry-pick"  # default
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  # Read config default
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      CFG_LANDING="${BASH_REMATCH[1]}"
      if [ -n "$CFG_LANDING" ]; then
        LANDING_MODE="$CFG_LANDING"
      fi
    fi
  fi
fi
```

**Validation:**
```bash
# direct + main_protected → error
if [[ "$LANDING_MODE" == "direct" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      echo "ERROR: direct mode is incompatible with main_protected: true. Use pr mode or change config."
      exit 1
    fi
  fi
fi
```
```

- [ ] Add `pr` and `direct` to argument detection in SKILL.md
- [ ] Add landing mode resolution logic (argument > config > fallback)
- [ ] Add `direct` + `main_protected` conflict check
- [ ] Strip `pr`/`direct` from arguments before passing to downstream processing

#### 3a.2 -- Config reading for branch_prefix

Add config reading for `branch_prefix` with support for empty string values:

```bash
# Read branch prefix from config (default: feat/)
BRANCH_PREFIX="feat/"
if [ -f "$PROJECT_ROOT/.claude/zskills-config.json" ]; then
  CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
  # ([^\"]*) allows empty string match — empty prefix means no prefix
  if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  fi
fi
```

Note: the regex uses `([^\"]*)` (zero or more) not `([^\"]+)` (one or more), so `"branch_prefix": ""` correctly sets `BRANCH_PREFIX` to empty string.

- [ ] Read `branch_prefix` from config with `([^\"]*)` regex (allows empty string)
- [ ] Default to `"feat/"` when not in config
- [ ] Empty string `""` results in no prefix (branches named just `plan-slug`)

#### 3a.3 -- Direct mode

Add `### Execution: direct` as a recognized directive. This is NOT a rename of `### Execution: main` (that directive does not exist in the current codebase). It is a new directive.

Direct mode means no worktree — agent works directly on main, commits go to main immediately, Phase 6 landing is a no-op.

Add to the execution mode detection in Phase 2:

```markdown
### Direct mode (Phase 2)

When `LANDING_MODE` is `direct`:
- Do NOT create a worktree
- Agent works directly on main (current working directory)
- `### Execution: direct` in phase text is the recognized directive
- Phase 6: no-op (work is already on main, nothing to land)
- `.landed` marker: not written (no worktree to mark)

**Validation (already checked in 3a.1):** `direct` + `main_protected: true` → error before dispatch.
```

- [ ] Add `### Execution: direct` as a recognized directive in SKILL.md
- [ ] Direct mode skips worktree creation in Phase 2
- [ ] Direct mode Phase 6 is a no-op
- [ ] Direct mode works on main directly

#### 3a.4 -- Sync installed copies

- [ ] Copy `skills/run-plan/SKILL.md` to `.claude/skills/run-plan/SKILL.md`
- [ ] Verify installed copy matches source

### Design & Constraints

- **`direct` not `main`.** The keyword is `direct` because `main` collides with plan filenames containing "main" (e.g., `plans/MAIN_MENU.md`).
- **`([^\"]*)` not `([^\"]+)`.** The branch_prefix regex must allow empty string matches. `([^\"]+)` requires at least one character, which would silently fail on `"branch_prefix": ""` and fall through to the default.
- **Add, not rename.** The old plan said "rename ### Execution: main to direct" but `### Execution: main` does not exist in the current codebase. This is adding a new directive.

### Acceptance Criteria

- [ ] `pr` and `direct` detected as arguments (case-insensitive)
- [ ] Config default read when no argument specified
- [ ] `direct` + `main_protected: true` → error
- [ ] `branch_prefix` empty string handled correctly
- [ ] `### Execution: direct` recognized as a directive
- [ ] Direct mode: no worktree, Phase 6 no-op
- [ ] Installed skill copy synced

### Dependencies

Phase 1 (config file for `branch_prefix` and `landing` default).
Phase 2 (main_protected check for `direct` + `main_protected` validation).

---

## Phase 3b -- PR Mode Implementation

### Goal

Implement PR mode for `/run-plan`: persistent worktree with named feature branch, all phases accumulating on the same branch, and Phase 6 landing via push + `gh pr create`. Mixed mode ban enforcement.

### Work Items

#### 3b.1 -- PR mode: persistent worktree with named branch

Add PR mode worktree setup to Phase 2 (Dispatch Implementation). When `LANDING_MODE` is `pr`:

```markdown
### PR mode worktree setup (Phase 2)

**Branch naming:** `{branch_prefix}{plan-slug}`
- `branch_prefix` from config (`execution.branch_prefix`), default `"feat/"` (read in 3a.2)
- `plan-slug` derived from plan file path: lowercase, hyphens, no extension
  - `plans/THERMAL_DOMAIN.md` → `thermal-domain`
  - `plans/ADD_FILTER_BLOCK.md` → `add-filter-block`

```bash
# Derive plan slug
PLAN_FILE="plans/THERMAL_DOMAIN.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')

BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
```

**Worktree creation — orchestrator creates manually, NOT via `isolation: "worktree"`:**

The orchestrator creates the worktree directly with `git worktree add`. Do NOT use
`isolation: "worktree"` in the Agent tool — that creates auto-named worktrees which
are NOT deterministic and do NOT persist across cron turns.

```bash
# Check if worktree already exists (resuming a previous run)
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing PR worktree at $WORKTREE_PATH"
else
  # Create worktree on a named branch
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main 2>/dev/null \
    || git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
  # First form: create new branch from main
  # Second form: branch already exists (resume after worktree was pruned)
fi
```

**Dispatching agents to the worktree:**
Dispatch agents WITHOUT `isolation: "worktree"`. Instead, point them to the
worktree path directly. The worktree is already created; agents just work in it.

**One branch per plan.** All phases accumulate on the same branch. The worktree persists across cron turns for chunked execution. Do NOT create a new worktree per phase.

**Pipeline association:** Write `.zskills-tracked` in the worktree (same as cherry-pick mode):
```bash
echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
```
```

- [ ] Add PR mode worktree setup to Phase 2 dispatch
- [ ] Orchestrator creates worktree manually with `git worktree add -b`
- [ ] Do NOT use `isolation: "worktree"` — agents dispatched without isolation to the worktree path
- [ ] Branch naming uses config `branch_prefix` + plan slug
- [ ] Worktree path is deterministic: `/tmp/<project>-pr-<plan-slug>`
- [ ] Worktree reuse: check if exists before creating (resume support)
- [ ] Pipeline association via `.zskills-tracked`

#### 3b.2 -- PR mode: Phase 6 landing (push + PR)

Replace the cherry-pick landing logic in Phase 6 with push + PR creation when `LANDING_MODE` is `pr`:

```markdown
### PR mode landing (Phase 6)

```bash
cd "$WORKTREE_PATH"

# Check for existing remote branch
if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
  echo "Remote branch $BRANCH_NAME already exists. Pushing updates."
  git push origin "$BRANCH_NAME"
else
  git push -u origin "$BRANCH_NAME"
fi

# Check for existing PR
EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  echo "PR #$EXISTING_PR already exists for $BRANCH_NAME. Updated with latest push."
  PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
else
  # Create PR
  PR_URL=$(gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base main \
    --head "$BRANCH_NAME")
fi

# Verify PR was created/exists before writing .landed marker
if [ -z "$PR_URL" ]; then
  echo "WARNING: PR creation failed. Branch pushed but PR not created."
  echo "Manual fallback: gh pr create --base main --head $BRANCH_NAME"
  # Write partial .landed marker
  cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: partial
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr-failed
branch: $BRANCH_NAME
pr:
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"
else
  echo "PR: $PR_URL"
  # Write full .landed marker
  cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: full
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"
fi
```

**Error handling:**
- `gh auth` failure → report branch name and manual instructions:
  `"Push succeeded. Create PR manually: gh pr create --base main --head $BRANCH_NAME"`
- Push failure → invoke Failure Protocol (network, permissions)
- Existing PR → update with push, do not create duplicate
- PR creation fails (empty PR_URL) → write `.landed` with `status: partial`, `method: pr-failed`

**PR title:** `[plan-slug] Phase N: <phase title>` for single phase, or `[plan-slug] <plan title>` for finish mode.

**PR body:** Include plan name, phases completed, and link to report file.
```

- [ ] Add PR landing to Phase 6 with push + `gh pr create`
- [ ] Handle existing remote branch (push updates)
- [ ] Handle existing PR (update, don't duplicate)
- [ ] Handle `gh auth` failure (fallback to manual instructions)
- [ ] Verify PR was created before writing full `.landed` marker
- [ ] PR creation failure → `.landed` with `status: partial`, `method: pr-failed`
- [ ] Write `.landed` marker with `method: pr`, `branch:`, `pr:` fields on success
- [ ] PR title and body formatting

#### 3b.3 -- Mixed mode ban in PR plans

When the plan-level landing mode is `pr`, individual phases cannot use `### Execution: direct`. Delegate is always OK.

```markdown
**Mixed mode validation (Phase 2):**
When `LANDING_MODE` is `pr`, scan the current phase text:
- `### Execution: direct` → ERROR: "Mixed execution modes not allowed in PR
  plans. All phases must use worktree or delegate mode."
- `### Execution: delegate ...` → OK (delegate manages its own isolation)
- `### Execution: worktree` or no directive → OK (default)
```

- [ ] Add mixed mode validation in Phase 2 dispatch
- [ ] `### Execution: direct` in a PR plan → error
- [ ] `### Execution: delegate` in a PR plan → allowed

#### 3b.4 -- Sync installed copies

- [ ] Copy `skills/run-plan/SKILL.md` to `.claude/skills/run-plan/SKILL.md`
- [ ] Verify installed copy matches source

### Design & Constraints

- **Persistent worktree, NOT isolation parameter.** The orchestrator creates the worktree manually with `git worktree add -b`. Do NOT use `isolation: "worktree"` — that creates auto-named worktrees that are not deterministic and do not persist across cron turns.
- **Agents dispatched without isolation.** After the orchestrator creates the worktree, agents are dispatched pointing to the worktree path, WITHOUT the `isolation: "worktree"` parameter.
- **Never checkout branches in main directory.** Branch checkout in main causes stash data loss, tracking enforcement deadlock, and progress tracking failure across cron turns. Always use worktrees.
- **Verification agent commits.** Same as cherry-pick mode — impl agent writes code, verification agent verifies and commits. The tracking system enforces this regardless of landing mode.
- **One PR per plan.** All phases go into one PR. Agent never waits for merge mid-execution.
- **Verify before marking landed.** Always check that `PR_URL` is non-empty before writing `status: full`. If PR creation failed, write `status: partial` with `method: pr-failed` so cleanup tooling knows the state.

### Acceptance Criteria

- [ ] PR mode creates persistent worktree at `/tmp/<project>-pr-<plan-slug>` via manual `git worktree add`
- [ ] Agents dispatched WITHOUT `isolation: "worktree"`
- [ ] PR mode branch name: `{branch_prefix}{plan-slug}`
- [ ] PR mode worktree reuse on resume
- [ ] PR mode Phase 6: push + `gh pr create`
- [ ] PR creation verified before writing full `.landed` marker
- [ ] PR failure → `.landed` with `status: partial`, `method: pr-failed`
- [ ] PR mode `.landed` marker has `method: pr` fields on success
- [ ] Mixed mode ban enforced in PR plans
- [ ] Installed skill copy synced

### Dependencies

Phase 3a (argument detection, config reading, branch_prefix).

---

## Phase 4 -- /fix-issues PR Landing

### Goal

Add `pr` and `direct` landing mode arguments to `/fix-issues`. PR mode creates per-issue named branches with worktrees, pushes each, and creates PRs with `Fixes #NNN` linking. Direct mode works on main (existing behavior with the `direct` keyword).

### Work Items

#### 4.1 -- Argument detection

Add `pr` and `direct` to argument detection in `skills/fix-issues/SKILL.md`. Same pattern as Phase 3a:

```markdown
**Landing mode detection (same as /run-plan):**
- `pr` (case-insensitive) in $ARGUMENTS → PR mode
- `direct` (case-insensitive) in $ARGUMENTS → direct mode
- Neither → config default → `cherry-pick` fallback
- `direct` + `main_protected: true` → error

Strip `pr`/`direct` from arguments before parsing N, focus, etc.

```bash
# Same detection logic as /run-plan (3a.1)
LANDING_MODE="cherry-pick"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  # Read config default (same as /run-plan)
fi
```
```

- [ ] Add `pr` and `direct` to argument detection in `/fix-issues`
- [ ] Add `direct` + `main_protected` conflict check
- [ ] Strip landing mode from arguments before parsing

#### 4.2 -- Per-issue named branches in PR mode

When `LANDING_MODE` is `pr`, each issue gets its own worktree with a named branch:

```markdown
**Per-issue branch naming:**
- Branch: `fix/issue-NNN` (e.g., `fix/issue-42`)
- Worktree: `/tmp/<project>-fix-issue-NNN`
- One PR per issue with `Fixes #NNN` in the body

```bash
ISSUE_NUM=42
BRANCH_NAME="fix/issue-${ISSUE_NUM}"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

# Orchestrator creates worktree manually (same as /run-plan PR mode)
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing fix worktree at $WORKTREE_PATH"
else
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main 2>/dev/null \
    || git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
fi

# Pipeline association
echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
```
```

- [ ] Per-issue branch naming: `fix/issue-NNN`
- [ ] Per-issue worktree: `/tmp/<project>-fix-issue-NNN`
- [ ] Orchestrator creates worktree manually (not isolation parameter)
- [ ] Worktree reuse on resume

#### 4.3 -- Phase 6: push + PR per issue

In the fix-issues landing phase, when `LANDING_MODE` is `pr`:

```markdown
**PR creation per issue (Phase 6):**

```bash
for issue in "${FIXED_ISSUES[@]}"; do
  ISSUE_NUM="$issue"
  BRANCH_NAME="fix/issue-${ISSUE_NUM}"
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

  cd "$WORKTREE_PATH"
  git push -u origin "$BRANCH_NAME"

  EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$EXISTING_PR" ]; then
    echo "PR #$EXISTING_PR already exists for issue #$ISSUE_NUM"
    PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
  else
    PR_URL=$(gh pr create \
      --title "Fix #${ISSUE_NUM}: ${ISSUE_TITLE}" \
      --body "$(cat <<EOF
Fixes #${ISSUE_NUM}

## Changes
${CHANGE_SUMMARY}

## Test plan
- [ ] Verify the fix resolves the original issue
- [ ] All existing tests pass
EOF
)" \
      --base main \
      --head "$BRANCH_NAME")
  fi

  # Verify PR was created before writing full .landed marker
  if [ -z "$PR_URL" ]; then
    cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: partial
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
method: pr-failed
branch: $BRANCH_NAME
issue: $ISSUE_NUM
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  else
    cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: full
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
issue: $ISSUE_NUM
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  fi
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"

  echo "Issue #$ISSUE_NUM → PR: $PR_URL"
done
```
```

- [ ] Push + PR creation for each fixed issue
- [ ] PR body includes `Fixes #NNN` for auto-close linking
- [ ] Handle existing PRs (update, don't duplicate)
- [ ] Verify PR created before writing full `.landed` marker
- [ ] PR failure → `.landed` with `status: partial`, `method: pr-failed`
- [ ] `.landed` marker with `method: pr`, `issue:` field on success

#### 4.4 -- /fix-report: PR-aware review flow

Update `skills/fix-issues/SKILL.md` (the `/fix-report` section) to be PR-aware:

- When reviewing completed sprints, check `.landed` markers for `method: pr`
- Report PR URLs alongside issue numbers
- Sprint summary includes PR links

- [ ] `/fix-report` checks `.landed` markers for `method: pr`
- [ ] Sprint report includes PR URLs

#### 4.5 -- Sync installed copies

- [ ] Copy `skills/fix-issues/SKILL.md` to `.claude/skills/fix-issues/SKILL.md`
- [ ] Verify installed copy matches source

### Design & Constraints

- **One PR per issue.** Each issue gets its own branch and PR. This allows independent review and merging, unlike `/run-plan` where all phases share one branch.
- **`Fixes #NNN` linking.** GitHub auto-closes issues when the PR is merged.
- **Verification agent commits.** Same as all modes — tracking enforces this.
- **PR-aware sprint report.** `/fix-report` must show PR URLs so the user can review them.
- **Verify before marking.** Same as /run-plan: check PR_URL is non-empty before writing `status: full`.

### Acceptance Criteria

- [ ] `pr` and `direct` detected as arguments in `/fix-issues`
- [ ] Per-issue branches: `fix/issue-NNN`
- [ ] Per-issue worktrees: `/tmp/<project>-fix-issue-NNN`
- [ ] Phase 6 creates one PR per fixed issue with `Fixes #NNN`
- [ ] PR failure → `.landed` with `status: partial`, `method: pr-failed`
- [ ] `.landed` markers have `method: pr`, `issue:` fields on success
- [ ] `/fix-report` shows PR URLs
- [ ] Installed skill copy synced

### Dependencies

Phase 1 (config file).
Phase 2 (main_protected validation).
Phase 3a (landing mode detection pattern — reuse the same approach).

---

## Phase 5 -- Pipeline Propagation

### Goal

Propagate execution mode awareness through the skill chain: `/research-and-go` detects mode and passes it in the cron prompt, `/research-and-plan` passes mode context to `/draft-plan`, `/draft-plan` embeds landing hints, `/do` gets a `pr` option, `/commit` gets a `pr` subcommand, `CLAUDE_TEMPLATE.md` documents execution modes, and `/update-zskills` audits for execution mode rules.

### Work Items

#### 5.1 -- /research-and-go: detect mode and pass to /run-plan

Modify `skills/research-and-go/SKILL.md` to detect `pr` or `direct` in the goal text and pass it through to the `/run-plan` cron prompt:

```markdown
**Landing mode detection in /research-and-go:**

Scan the goal text for `pr` or `direct` (case-insensitive, word boundary).
If found, append the keyword to the `/run-plan` cron prompt:

```bash
# In the cron prompt construction:
LANDING_ARG=""
if [[ "$GOAL" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]; then
  LANDING_ARG="pr"
elif [[ "$GOAL" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]|[.!?]) ]]; then
  LANDING_ARG="direct"
fi

# Cron prompt includes landing mode:
# /run-plan plans/GENERATED_PLAN.md finish auto $LANDING_ARG every 4h now
```
```

- [ ] Detect `pr`/`direct` in goal text
- [ ] Pass landing mode to `/run-plan` cron prompt
- [ ] Sync installed copy

#### 5.2 -- /research-and-plan: pass mode context to /draft-plan

Modify `skills/research-and-plan/SKILL.md` to detect `pr` or `direct` in the goal text and pass it through to `/draft-plan`:

```markdown
**Landing mode propagation in /research-and-plan:**

If the user's goal includes `pr` or `direct`, pass this context to `/draft-plan`
so generated plans include appropriate landing hints.

When constructing the /draft-plan invocation, append the detected landing mode:
- `/draft-plan output plans/X.md rounds 2 <description>. Landing mode: pr`
```

- [ ] Detect `pr`/`direct` in goal text
- [ ] Pass landing mode context to `/draft-plan` invocations
- [ ] Sync installed copy

#### 5.3 -- /draft-plan: embed landing hints

Modify `skills/draft-plan/SKILL.md` to embed landing hints in generated plans when the config specifies a non-default landing mode:

```markdown
**Landing hints in generated plans:**

When generating a plan, check `.claude/zskills-config.json` for `execution.landing`:
- If `"pr"`: add a note at the top of the plan:
  `> **Landing mode: PR** — This plan targets PR-based landing. All phases
  > use worktree isolation with a named feature branch.`
- If `"direct"`: add a note:
  `> **Landing mode: direct** — This plan targets direct-to-main landing.
  > No worktree isolation.`
- If `"cherry-pick"` or absent: no note (default behavior).

This is a hint for the implementing agent, not enforcement. The `/run-plan`
argument always takes precedence.
```

- [ ] Read config `execution.landing` in `/draft-plan`
- [ ] Embed landing hint in generated plan when non-default
- [ ] Sync installed copy

#### 5.4 -- /do: `pr` option

Modify `skills/do/SKILL.md` to accept a `pr` argument:

```markdown
**PR mode for /do:**

`/do <task> pr` creates a worktree with a named branch, does the work,
pushes, and creates a PR. Same as `/run-plan` PR mode but for single tasks.

- Branch name: `{branch_prefix}{task-slug}` (task slug derived from first
  few words of task description, lowercased, hyphenated)
- Worktree: `/tmp/<project>-do-<task-slug>`
- Orchestrator creates worktree manually (not isolation parameter)
- After work + verification: push + `gh pr create`
- Verify PR created before writing `.landed` marker
- `.landed` marker with `method: pr` on success, `method: pr-failed` on failure
```

- [ ] Add `pr` argument detection to `/do`
- [ ] PR mode creates named worktree, pushes, creates PR
- [ ] Verify PR created before writing full `.landed` marker
- [ ] Sync installed copy

#### 5.5 -- /commit: `pr` subcommand

Modify `skills/commit/SKILL.md` to accept a `pr` subcommand:

```markdown
**PR subcommand for /commit:**

`/commit pr` pushes the current branch and creates a PR to main.

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Cannot create PR from main. Create a feature branch first."
  exit 1
fi

git push -u origin "$BRANCH"

EXISTING_PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
  echo "PR already exists: $PR_URL"
else
  PR_URL=$(gh pr create --base main --head "$BRANCH" --fill)
  echo "Created PR: $PR_URL"
fi
```

This is a convenience command for manual PR creation from any feature branch.
```

- [ ] Add `pr` subcommand to `/commit`
- [ ] Push current branch + create PR
- [ ] Error if on main/master
- [ ] Handle existing PR
- [ ] Sync installed copy

#### 5.6 -- CLAUDE_TEMPLATE.md: document execution modes

Add a section to `CLAUDE_TEMPLATE.md` documenting execution modes:

```markdown
## Execution Modes

Three landing modes control how agent work reaches main:

| Mode | Keyword | How it works |
|------|---------|-------------|
| Cherry-pick | (default) | Work in auto-named worktree, cherry-pick to main |
| PR | `pr` | Work in named worktree, push branch, create PR |
| Direct | `direct` | Work directly on main, no landing step |

**Usage:** Append keyword to any execution skill:
- `/run-plan plans/X.md finish auto pr`
- `/fix-issues 10 pr`
- `/research-and-go Build an RPG. pr`
- `/do Add dark mode. pr`

**Config default:** Set in `.claude/zskills-config.json`:
```json
{
  "execution": {
    "landing": "pr",
    "main_protected": true,
    "branch_prefix": "feat/"
  }
}
```

When `main_protected: true`, agents cannot commit, cherry-pick, or push
to main. Use PR mode or feature branches.
```

- [ ] Add execution modes section to `CLAUDE_TEMPLATE.md`
- [ ] Document all three modes with usage examples
- [ ] Document config defaults

#### 5.7 -- /update-zskills: audit execution mode rules

Add execution mode key phrases to the `/update-zskills` audit checklist. The audit checks CLAUDE.md for required rules — add checks for execution mode documentation:

```markdown
**Execution mode audit items:**
- "Execution Modes" section exists in CLAUDE.md
- "main_protected" mentioned if config has it enabled
- "PR" and "direct" keywords documented
- `.claude/zskills-config.json` referenced
```

- [ ] Add execution mode audit items to `/update-zskills`
- [ ] Sync installed copy

#### 5.8 -- Sync all installed copies

- [ ] `skills/research-and-go/SKILL.md` → `.claude/skills/research-and-go/SKILL.md`
- [ ] `skills/research-and-plan/SKILL.md` → `.claude/skills/research-and-plan/SKILL.md`
- [ ] `skills/draft-plan/SKILL.md` → `.claude/skills/draft-plan/SKILL.md`
- [ ] `skills/do/SKILL.md` → `.claude/skills/do/SKILL.md`
- [ ] `skills/commit/SKILL.md` → `.claude/skills/commit/SKILL.md`
- [ ] `CLAUDE_TEMPLATE.md` updated
- [ ] `skills/update-zskills/SKILL.md` → `.claude/skills/update-zskills/SKILL.md`
- [ ] Verify all installed copies match sources

### Design & Constraints

- **Propagation, not re-implementation.** Each skill in this phase reuses the same landing mode detection pattern from Phase 3a. No new patterns.
- **Config hints, not enforcement.** `/draft-plan` embeds hints in plans, but `/run-plan` arguments always take precedence.
- **`/commit pr` is a convenience.** It's for manual use from any feature branch, not tied to the pipeline.
- **CLAUDE_TEMPLATE.md is documentation.** It tells the LLM about execution modes so it can make informed decisions.
- **`/research-and-plan` included.** Was missing from the original plan (review finding R4). It passes mode context to `/draft-plan`.

### Acceptance Criteria

- [ ] `/research-and-go` detects mode in goal and passes to `/run-plan` cron prompt
- [ ] `/research-and-plan` detects mode and passes to `/draft-plan`
- [ ] `/draft-plan` embeds landing hints for non-default modes
- [ ] `/do pr` creates worktree, pushes, creates PR
- [ ] `/commit pr` pushes and creates PR from current branch
- [ ] `CLAUDE_TEMPLATE.md` documents all three execution modes
- [ ] `/update-zskills` audit includes execution mode checks
- [ ] All installed skill copies synced and verified

### Dependencies

Phase 3a (landing mode detection pattern).
Phase 3b (/run-plan PR mode, for consistency).
Phase 4 (fix-issues PR mode, for sprint report PR URLs).

---

## Do NOT Repeat These Anti-Patterns

These are the 9 mistakes from the old plan. Each is a hard constraint — violating any of them means the implementation is wrong.

1. **No worktree exemption for tracking.** The tracking system enforces in worktrees via `git-common-dir` resolution. Do not add any code that skips tracking checks in worktrees.

2. **No branch checkout in main directory.** Never use `git checkout <branch>` in the main working directory. It causes stash data loss, tracking enforcement deadlock, and progress tracking failure across cron turns. Always use `git worktree add` for isolation.

3. **No staleness bypass.** Tracking enforcement is unconditional. Do not add "skip if stale" logic that lets agents bypass tracking by waiting.

4. **No `.zskills-tracked` on main for orchestrators.** Orchestrators on main use `echo "ZSKILLS_PIPELINE_ID=..."` (transcript-based). `.zskills-tracked` is for worktree agents only (written by the orchestrator before dispatch). Do not write `.zskills-tracked` in the main repo root from the orchestrator's own session.

5. **No glob matching for sentinels.** Pipeline scoping uses exact suffix matching: `[[ "$base" != *".$PIPELINE_ID" ]]`. Do not use `find -name "*pattern*"` or shell glob expansion for marker lookups.

6. **`direct` not `main` as keyword.** The keyword for direct-to-main execution is `direct`, not `main`. `main` collides with plan filenames containing "main" (e.g., `plans/MAIN_MENU.md`, `plans/FIX_MAIN_LOOP.md`).

7. **Verification agent commits, not impl agent.** The implementation agent writes code and does NOT commit. The verification agent verifies (runs tests, reviews) and commits if verification passes. This is enforced by the tracking system regardless of landing mode.

8. **Two-tier pipeline guard, not three.** Pipeline association uses exactly two tiers: (1) `.zskills-tracked` file in LOCAL repo root, (2) `ZSKILLS_PIPELINE_ID=` in transcript. There is no third tier. Do not add additional tiers.

9. **`.zskills/tracking`, not `.claude/tracking`.** All tracking state lives under `.zskills/tracking/`. The `.claude/` directory triggers permission prompts when agents write to it. Do not use `.claude/tracking/` for any purpose.
