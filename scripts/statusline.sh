#!/usr/bin/env bash
# zskills statusline — colored progress bars for context window + rate limits
# No external dependencies (no jq) — uses bash string manipulation for JSON.
#
# Claude Code pipes JSON to stdin with context_window.used_percentage,
# rate_limits.five_hour.used_percentage, rate_limits.seven_day.used_percentage.
#
# Usage: configured in .claude/settings.json:
#   { "statusLine": { "type": "command", "command": "bash <path>/statusline.sh" } }
#
# Colors (configurable via env vars):
#   STATUSLINE_CTX_COLOR  — context window (default: magenta \033[35m)
#   STATUSLINE_5H_COLOR   — 5-hour rate limit (default: blue \033[34m)
#   STATUSLINE_7D_COLOR   — 7-day rate limit (default: green \033[32m)
#   STATUSLINE_BAR_WIDTH  — bar width in blocks (default: 10)

INPUT=$(cat)

# Extract a percentage from a specific section of JSON.
# Strategy: find the section key, take everything after it, then find
# the first "used_percentage" in that substring. This handles nested
# objects correctly because we search forward from the section key.
extract_section_pct() {
  local section_key="$1"
  local json="$2"

  # Find the section key and take everything after it
  local after="${json#*\"$section_key\"}"
  # If the key wasn't found, after == json (no change)
  if [ "$after" = "$json" ]; then
    return
  fi

  # Find the first used_percentage after this section key
  if [[ "$after" =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+\.?[0-9]*) ]]; then
    printf '%.0f' "${BASH_REMATCH[1]}"
  fi
}

# Build a colored bar for a percentage (0-100)
make_bar() {
  local pct="$1"
  local color="$2"
  local width="${STATUSLINE_BAR_WIDTH:-10}"
  local filled=$(( (pct * width + 99) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width

  local reset="\033[0m"
  local bar=""
  for i in $(seq 1 "$width"); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}█"
    else
      bar="${bar}░"
    fi
  done

  printf "${color}${bar}${reset} %d%%" "$pct"
}

# Extract percentages by section
ctx_pct=$(extract_section_pct "context_window" "$INPUT")
five_pct=$(extract_section_pct "five_hour" "$INPUT")
week_pct=$(extract_section_pct "seven_day" "$INPUT")

# Build output
CTX_COLOR="${STATUSLINE_CTX_COLOR:-\033[35m}"   # magenta
FIVE_COLOR="${STATUSLINE_5H_COLOR:-\033[34m}"    # blue
WEEK_COLOR="${STATUSLINE_7D_COLOR:-\033[32m}"    # green

parts=()

if [ -n "$ctx_pct" ]; then
  parts+=("$(make_bar "$ctx_pct" "$CTX_COLOR")")
fi

if [ -n "$five_pct" ]; then
  parts+=("$(make_bar "$five_pct" "$FIVE_COLOR")")
fi

if [ -n "$week_pct" ]; then
  parts+=("$(make_bar "$week_pct" "$WEEK_COLOR")")
fi

printf '%b' "$(IFS='  '; echo "${parts[*]}")"
