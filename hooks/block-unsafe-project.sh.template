#!/bin/bash
# Block unsafe commands — PROJECT-SPECIFIC enforcement layer.
# This file is a template. Replace {{PLACEHOLDER}} values and remove
# sections that don't apply to your project.
#
# Register BOTH this file and block-unsafe-generic.sh in .claude/settings.json
# on the PreToolUse event, Bash matcher. The generic layer runs first.

INPUT=$(cat)

# jq is required to parse the JSON input.
if ! command -v jq &>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: block-unsafe-project.sh hook requires jq but it is not installed. Install jq or remove the hook. Denying all Bash commands as a safety precaution."}}'
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only filter Bash commands
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Block patterns -- each with a reason
block_with_reason() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# ─── CONFIGURE: remove this section if you don't use session logging ───
# git add .claude/logs/ (sweeps in all sessions' logs -- stage specific files)
if echo "$COMMAND" | grep -qE 'git\s+add\s+\.claude/logs/?(\s|$)'; then
  block_with_reason "BLOCKED: git add .claude/logs/ sweeps in ALL sessions' logs. Stage your session's logs by name: git add .claude/logs/*-<session-id>*.md"
fi

# ─── CONFIGURE: set your test command patterns ────────────────────────
# Piping test output (loses failures, forces re-runs -- capture to file instead)
# Replace the placeholder values with your actual test command patterns.
UNIT_TEST_CMD="{{UNIT_TEST_CMD}}"
FULL_TEST_CMD="{{FULL_TEST_CMD}}"

# Build grep pattern from configured test commands (fall back to generic if unconfigured)
if [[ "$UNIT_TEST_CMD" == '{{UNIT_TEST_CMD}}' ]] || [[ "$FULL_TEST_CMD" == '{{FULL_TEST_CMD}}' ]]; then
  # Placeholders not replaced -- use a generic pattern that catches common test runners
  TEST_PIPE_PATTERN='(npm\s+test(\s|$)|npm\s+run\s+test(:\S+)?(\s|$)|node\s+--test\s)'
else
  # Escape dots and special chars for grep
  ESCAPED_UNIT=$(printf '%s' "$UNIT_TEST_CMD" | sed 's/[.[\*^$()+?{|]/\\&/g' | sed 's/ /\\s+/g')
  ESCAPED_FULL=$(printf '%s' "$FULL_TEST_CMD" | sed 's/[.[\*^$()+?{|]/\\&/g' | sed 's/ /\\s+/g')
  TEST_PIPE_PATTERN="(${ESCAPED_UNIT}|${ESCAPED_FULL})"
fi

if echo "$COMMAND" | grep -qP "$TEST_PIPE_PATTERN" && \
   echo "$COMMAND" | grep -qP '\|'; then
  block_with_reason "Don't pipe test output -- it loses failure details. Instead: ${FULL_TEST_CMD:-npm run test:all} > .test-results.txt 2>&1 then read the file. To inspect results, grep the captured file."
fi

# ─── CONFIGURE: set your full test command ────────────────────────────
# Safety net: transcript-based verification on git commit
# Ensures tests were run before committing code files.
if echo "$COMMAND" | grep -qE '^git\s+commit'; then
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    if [[ "$FULL_TEST_CHECK" == '{{FULL_TEST_CMD}}' ]]; then
      # Placeholder not replaced -- warn but don't block
      echo "WARNING: {{FULL_TEST_CMD}} placeholder not configured in block-unsafe-project.sh" >&2
    else
      # Check if full test command was run in this session
      if ! grep -qF "$FULL_TEST_CHECK" "$TRANSCRIPT" 2>/dev/null; then
        # Check if any code files are being committed (skip check for content-only)
        CODE_FILES=$(git diff --cached --name-only 2>/dev/null | grep -E '\.(js|ts|css|html|rs|py|go|rb)$')
        if [ -n "$CODE_FILES" ]; then
          block_with_reason "BLOCKED: Committing code but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before committing. (Content-only commits are exempt.)"
        fi
      fi
    fi

    # ─── CONFIGURE: set your UI source paths, or remove this section if not applicable ───
    # Check if UI files changed but no playwright-cli verification
    UI_FILE_PATTERNS="{{UI_FILE_PATTERNS}}"
    if [[ "$UI_FILE_PATTERNS" != '{{UI_FILE_PATTERNS}}' ]]; then
      UI_FILES=$(git diff --cached --name-only 2>/dev/null | grep -E "$UI_FILE_PATTERNS")
      if [ -n "$UI_FILES" ]; then
        if ! grep -q 'playwright-cli' "$TRANSCRIPT" 2>/dev/null; then
          block_with_reason "BLOCKED: UI files changed but no playwright-cli verification found in session transcript. Verify UI changes before committing. Changed files: $(echo $UI_FILES | tr '\n' ', ')"
        fi
      fi
    fi
  fi
fi

# Safety net: transcript-based verification on git cherry-pick
# Cherry-picks replay existing commits and bypass the commit hook above.
if echo "$COMMAND" | grep -qE 'git\s+cherry-pick'; then
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    if [[ "$FULL_TEST_CHECK" == '{{FULL_TEST_CMD}}' ]]; then
      echo "WARNING: {{FULL_TEST_CMD}} placeholder not configured in block-unsafe-project.sh" >&2
    else
      if ! grep -qF "$FULL_TEST_CHECK" "$TRANSCRIPT" 2>/dev/null; then
        block_with_reason "BLOCKED: git cherry-pick but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before landing code on main."
      fi
    fi
  fi
fi

# No match — allow
exit 0
