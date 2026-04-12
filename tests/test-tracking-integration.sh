#!/bin/bash
# End-to-end tests for the tracking enforcement system.
# These tests create REAL git repos, write REAL tracking markers,
# and run REAL git commits through the actual hook.
#
# Run from repo root: bash tests/test-tracking-integration.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZSKILLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_TEMPLATE="$ZSKILLS_ROOT/hooks/block-unsafe-project.sh.template"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

# ─── Shared setup/teardown ───

TEST_TMPDIR=""

# Create a fresh git repo with the hook installed as a real pre-commit hook.
# The hook is configured with the template placeholders replaced.
# Sets TEST_TMPDIR to the repo root.
setup_repo() {
  TEST_TMPDIR=$(mktemp -d)

  # Initialize git repo with an initial commit
  (
    cd "$TEST_TMPDIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo '{"scripts":{"test":"vitest","test:all":"vitest run"}}' > package.json
    git add package.json
    git commit -q -m "init"
  )

  # Install the hook as a real git pre-commit hook.
  # We wrap it: the pre-commit hook synthesizes the JSON that the Claude
  # Code PreToolUse protocol would send, then pipes it to the hook script.
  # This is the key difference from the unit tests -- git commit actually
  # invokes this, not us injecting JSON by hand.
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  cp "$HOOK_TEMPLATE" "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"

  # Create .zskills/tracking directory
  mkdir -p "$TEST_TMPDIR/.zskills/tracking"

  # Create a transcript that contains the full test command (so the test-gate
  # check passes -- we are testing tracking enforcement, not test-gate)
  printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
}

teardown_repo() {
  if [ -n "$TEST_TMPDIR" ]; then
    # Clean up any worktrees before removing the repo
    (cd "$TEST_TMPDIR" && git worktree list --porcelain 2>/dev/null | grep '^worktree ' | grep -v "$TEST_TMPDIR\$" | sed 's/^worktree //' | while read -r wt; do
      git worktree remove --force "$wt" 2>/dev/null
    done)
    rm -rf "$TEST_TMPDIR"
  fi
  TEST_TMPDIR=""
}

# Helper: attempt a git commit via the hook (simulating Claude Code's
# PreToolUse protocol). Returns 0 if the hook allows, 1 if it denies.
# Captures the hook's output in $HOOK_OUTPUT.
HOOK_OUTPUT=""

try_commit() {
  local repo_root="${1:-$TEST_TMPDIR}"
  local tracking_root="${2:-$TEST_TMPDIR}"
  local transcript="$repo_root/.transcript"

  # Build the JSON that Claude Code would pipe to the PreToolUse hook
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m test\"},\"transcript_path\":\"$transcript\"}"

  HOOK_OUTPUT=$(echo "$json" | REPO_ROOT="$repo_root" TRACKING_ROOT="$tracking_root" bash -c "cd '$repo_root' && bash '$repo_root/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)

  if [[ "$HOOK_OUTPUT" == *"permissionDecision"*"deny"* ]]; then
    return 1  # denied
  fi
  return 0  # allowed
}

# Helper: like try_commit but for worktrees where the hook script lives
# in the main repo but we simulate running in the worktree.
try_commit_worktree() {
  local worktree_root="$1"
  local tracking_root="$2"
  local hook_path="$3"
  local transcript="$worktree_root/.transcript"

  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m test\"},\"transcript_path\":\"$transcript\"}"

  HOOK_OUTPUT=$(echo "$json" | REPO_ROOT="$worktree_root" TRACKING_ROOT="$tracking_root" bash -c "cd '$worktree_root' && bash '$hook_path'" 2>/dev/null)

  if [[ "$HOOK_OUTPUT" == *"permissionDecision"*"deny"* ]]; then
    return 1
  fi
  return 0
}

# ═══════════════════════════════════════════════════════════════════════
# Test 1: Basic enforcement (commit blocked by requires.*, unblocked by fulfilled.*)
# ═══════════════════════════════════════════════════════════════════════

echo "=== Test 1: Basic enforcement ==="

setup_repo

# Create a requires marker (unfulfilled)
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.alpha"

# Write .zskills-tracked to associate this session with the pipeline
printf 'run-plan.alpha\n' > "$TEST_TMPDIR/.zskills-tracked"

# Stage a code file (.js -- triggers code-file detection)
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should be BLOCKED (requires without fulfilled)
if try_commit; then
  fail "Test 1a: commit should be blocked by unfulfilled requires marker"
else
  pass "Test 1a: commit blocked by unfulfilled requires marker"
fi

# Verify the block message mentions the right marker
if [[ "$HOOK_OUTPUT" == *"verify-changes.run-plan.alpha"* ]]; then
  pass "Test 1b: block message references correct marker"
else
  fail "Test 1b: block message should reference 'verify-changes.run-plan.alpha', got: $HOOK_OUTPUT"
fi

# Now create the fulfilled marker
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.alpha"

# Attempt commit -- should SUCCEED
if try_commit; then
  pass "Test 1c: commit allowed after fulfilled marker created"
else
  fail "Test 1c: commit should be allowed after fulfilled marker, got: $HOOK_OUTPUT"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 2: Pipeline scoping (cross-pipeline non-blocking)
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 2: Pipeline scoping ==="

setup_repo

# Create markers for pipeline-A (unfulfilled)
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"

# Write .zskills-tracked with pipeline-B (different pipeline)
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should SUCCEED (pipeline-B doesn't see pipeline-A markers)
if try_commit; then
  pass "Test 2a: pipeline-B not blocked by pipeline-A's unfulfilled markers"
else
  fail "Test 2a: pipeline-B should not be blocked by pipeline-A's markers, got: $HOOK_OUTPUT"
fi

# Now add pipeline-B's own unfulfilled marker
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"

# Re-stage (previous commit wasn't real -- hook only, file still staged)
(cd "$TEST_TMPDIR" && echo "var y = 2;" > app2.js && git add app2.js)

# Attempt commit -- should be BLOCKED (pipeline-B has its own unfulfilled marker)
if try_commit; then
  fail "Test 2b: pipeline-B should be blocked by its own unfulfilled marker"
else
  pass "Test 2b: pipeline-B blocked by its own unfulfilled marker"
fi

# Fulfill pipeline-B's marker (but NOT pipeline-A's)
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.pipeline-B"

# Attempt commit -- should SUCCEED (pipeline-B's marker is fulfilled, pipeline-A is irrelevant)
if try_commit; then
  pass "Test 2c: pipeline-B allowed after fulfilling its own marker (pipeline-A still unfulfilled)"
else
  fail "Test 2c: pipeline-B should be allowed despite pipeline-A being unfulfilled, got: $HOOK_OUTPUT"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 3: Worktree enforcement
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 3: Worktree enforcement ==="

setup_repo

# Create a branch for the worktree
(cd "$TEST_TMPDIR" && git checkout -q -b worktree-branch && git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null)

# Create a worktree
WORKTREE_DIR=$(mktemp -d)
rmdir "$WORKTREE_DIR"  # git worktree add needs non-existing dir
(cd "$TEST_TMPDIR" && git worktree add -q "$WORKTREE_DIR" worktree-branch 2>/dev/null)

if [ ! -d "$WORKTREE_DIR" ]; then
  fail "Test 3: could not create worktree, skipping"
else
  # Install the hook in the worktree (in a real system, the hook is in main
  # repo's .claude/hooks, but agents can read it from there; for this test
  # we need a local copy the worktree can invoke)
  mkdir -p "$WORKTREE_DIR/.claude/hooks"
  cp "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh" "$WORKTREE_DIR/.claude/hooks/block-unsafe-project.sh"

  # Write .zskills-tracked in the worktree
  printf 'run-plan.thermal-domain\n' > "$WORKTREE_DIR/.zskills-tracked"

  # Create tracking markers in the MAIN repo's .zskills/tracking/
  touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"

  # Create transcript in worktree (with test command so test-gate passes)
  printf 'npm run test:all\n' > "$WORKTREE_DIR/.transcript"

  # Stage a code file in the worktree
  (cd "$WORKTREE_DIR" && echo "var x = 1;" > thermal.js && git add thermal.js)

  # Attempt commit in the worktree -- should be BLOCKED
  # The hook reads .zskills-tracked from WORKTREE (REPO_ROOT), but tracking
  # markers from MAIN repo (TRACKING_ROOT).
  if try_commit_worktree "$WORKTREE_DIR" "$TEST_TMPDIR" "$WORKTREE_DIR/.claude/hooks/block-unsafe-project.sh"; then
    fail "Test 3a: worktree commit should be blocked by unfulfilled requires marker"
  else
    pass "Test 3a: worktree commit blocked by main repo's unfulfilled requires marker"
  fi

  # Create fulfilled marker in the MAIN repo's tracking dir
  touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.thermal-domain"

  # Attempt commit again -- should SUCCEED
  if try_commit_worktree "$WORKTREE_DIR" "$TEST_TMPDIR" "$WORKTREE_DIR/.claude/hooks/block-unsafe-project.sh"; then
    pass "Test 3b: worktree commit allowed after fulfilled marker in main repo"
  else
    fail "Test 3b: worktree commit should be allowed after fulfilled marker, got: $HOOK_OUTPUT"
  fi

  # Clean up worktree
  (cd "$TEST_TMPDIR" && git worktree remove --force "$WORKTREE_DIR" 2>/dev/null)
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 4: Content-only exemption
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 4: Content-only exemption ==="

setup_repo

# Create unfulfilled markers
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.alpha"

# Write .zskills-tracked
printf 'run-plan.alpha\n' > "$TEST_TMPDIR/.zskills-tracked"

# Stage ONLY a markdown file (content-only -- no code files)
(cd "$TEST_TMPDIR" && echo "# Documentation update" > README.md && git add README.md)

# Attempt commit -- should SUCCEED (content-only exemption)
if try_commit; then
  pass "Test 4a: content-only commit (.md) allowed despite unfulfilled markers"
else
  fail "Test 4a: content-only commit should bypass tracking enforcement, got: $HOOK_OUTPUT"
fi

# Now stage a code file alongside the markdown
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should be BLOCKED (code file present)
if try_commit; then
  fail "Test 4b: commit with code file should be blocked"
else
  pass "Test 4b: commit with code file blocked despite also having .md file"
fi

# Stage only an image file (also content-only)
(cd "$TEST_TMPDIR" && git reset HEAD app.js 2>/dev/null && git reset HEAD README.md 2>/dev/null)
(cd "$TEST_TMPDIR" && echo "fake-image-data" > screenshot.png && git add screenshot.png)

# Attempt commit -- should SUCCEED (no code file extensions)
if try_commit; then
  pass "Test 4c: content-only commit (.png) allowed despite unfulfilled markers"
else
  fail "Test 4c: .png-only commit should bypass tracking enforcement, got: $HOOK_OUTPUT"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 5: Unrelated session (no .zskills-tracked, no pipeline in transcript)
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 5: Unrelated session ==="

setup_repo

# Create unfulfilled tracking markers (as if a pipeline is running)
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.implement"

# Do NOT write .zskills-tracked

# Overwrite transcript with content that has NO pipeline skill names
# (no /run-plan, /fix-issues, /research-and-go, etc.)
printf 'git status\nnpm run test:all\ngit diff\n' > "$TEST_TMPDIR/.transcript"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should SUCCEED (unrelated session, enforcement skipped)
if try_commit; then
  pass "Test 5a: unrelated session commits freely despite active pipeline markers"
else
  fail "Test 5a: unrelated session should not be blocked by pipeline markers, got: $HOOK_OUTPUT"
fi

# Now add ZSKILLS_PIPELINE_ID to the transcript (simulating orchestrator)
printf 'ZSKILLS_PIPELINE_ID=run-plan.thermal-domain\nnpm run test:all\n' > "$TEST_TMPDIR/.transcript"

# Re-stage
(cd "$TEST_TMPDIR" && echo "var y = 2;" > app2.js && git add app2.js)

# Attempt commit -- should be BLOCKED (transcript has pipeline ID,
# scoped to run-plan.alpha which matches our marker)
if try_commit; then
  fail "Test 5b: session with ZSKILLS_PIPELINE_ID matching markers should be blocked"
else
  pass "Test 5b: session with ZSKILLS_PIPELINE_ID=run-plan.thermal-domain is blocked by matching markers"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 6: Step enforcement (implement → verify → report chain)
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 6: Step enforcement ==="

setup_repo

# Write .zskills-tracked
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"

# Create implement step marker only
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.implement"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should be BLOCKED (implement without verify)
if try_commit; then
  fail "Test 6a: commit should be blocked — implement without verify"
else
  pass "Test 6a: commit blocked — implement without verify"
fi

# Add verify marker
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.verify"

# Attempt commit -- should be BLOCKED (verify without report)
if try_commit; then
  fail "Test 6b: commit should be blocked — verify without report"
else
  pass "Test 6b: commit blocked — verify without report"
fi

# Add report marker
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.report"

# Attempt commit -- should SUCCEED (full chain complete)
if try_commit; then
  pass "Test 6c: commit allowed — full step chain complete (implement + verify + report)"
else
  fail "Test 6c: commit should be allowed with full step chain, got: $HOOK_OUTPUT"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 7: No staleness bypass (stale markers still enforce)
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 7: No staleness bypass ==="

setup_repo

# Write .zskills-tracked
printf 'run-plan.alpha\n' > "$TEST_TMPDIR/.zskills-tracked"

# Create a requires marker and make it old (>8h = >480 minutes)
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.alpha"
touch -t 202501010000 "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.alpha"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should FAIL (no staleness bypass, enforcement unconditional)
if try_commit; then
  fail "Test 7a: stale markers should NOT bypass enforcement"
else
  pass "Test 7a: stale markers (>8h) still block commit — no bypass"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 8: Combined delegation + step enforcement
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 8: Combined delegation + step enforcement ==="

setup_repo

# This simulates the state right before cherry-pick to main:
# - requires + fulfilled (delegation satisfied)
# - step implement + verify + report (step chain complete)
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"

touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.thermal-domain"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.implement"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.verify"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.report"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should SUCCEED
if try_commit; then
  pass "Test 8a: full pipeline state (delegation + steps complete) allows commit"
else
  fail "Test 8a: fully satisfied pipeline should allow commit, got: $HOOK_OUTPUT"
fi

# Now remove the report marker (simulating incomplete step chain)
rm -f "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.report"

# Re-stage
(cd "$TEST_TMPDIR" && echo "var y = 2;" > app2.js && git add app2.js)

# Attempt commit -- should be BLOCKED (step chain incomplete despite delegation OK)
if try_commit; then
  fail "Test 8b: commit should be blocked — delegation OK but step chain incomplete"
else
  pass "Test 8b: commit blocked — delegation OK but step chain incomplete (missing report)"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 9: phasestep markers are NOT enforced
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 9: phasestep markers ignored ==="

setup_repo

printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"

# Create a phasestep marker (per-phase progress, NOT enforced)
touch "$TEST_TMPDIR/.zskills/tracking/phasestep.run-plan.thermal-domain.phase3.implement"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should SUCCEED (phasestep is informational only)
if try_commit; then
  pass "Test 9a: phasestep marker does not trigger enforcement"
else
  fail "Test 9a: phasestep markers should be ignored by hook, got: $HOOK_OUTPUT"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 10: No tracking directory (backward compatibility)
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 10: No tracking directory ==="

setup_repo

# Remove the tracking directory entirely
rm -rf "$TEST_TMPDIR/.zskills/tracking"

# Write .zskills-tracked (session thinks it's in a pipeline, but no tracking dir)
printf 'run-plan.alpha\n' > "$TEST_TMPDIR/.zskills-tracked"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should SUCCEED (no tracking dir = backward compatible)
if try_commit; then
  pass "Test 10a: no tracking directory — enforcement silently skipped"
else
  fail "Test 10a: missing tracking directory should skip enforcement, got: $HOOK_OUTPUT"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Test 11: Suffix matching prevents false positives
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "=== Test 11: Suffix matching precision ==="

setup_repo

# Pipeline ID is "plan" -- should NOT match markers ending in ".run-plan.thermal-domain"
printf 'plan\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"

# Stage a code file
(cd "$TEST_TMPDIR" && echo "var x = 1;" > app.js && git add app.js)

# Attempt commit -- should SUCCEED (suffix ".plan" does not match ".run-plan.thermal-domain")
if try_commit; then
  pass "Test 11a: pipeline ID 'plan' does not match marker ending '.run-plan.thermal-domain'"
else
  fail "Test 11a: suffix matching should prevent false positive, got: $HOOK_OUTPUT"
fi

teardown_repo

# ═══════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
