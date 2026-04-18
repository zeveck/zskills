# Session B handoff — Ship to public zskills

**Purpose**: get the current solid state out the door before RESTRUCTURE. This session should do README + installer-preset UX + push, then stop. RESTRUCTURE is a separate Session C with its own safety-net phase.

**Read this file, not the prior-session transcript.** It's self-contained. Delete this file when Session B completes.

---

## State snapshot at handoff

- **Main HEAD**: `81c7e89` (post-hook scope policy)
- **Unpushed**: 2 commits on local main ahead of origin
  - `81c7e89` fix(hook): scope-based destructive-op policy (permit /tmp/, block wide)
  - `e9687ea` chore: remove canary artifacts (workflow validation complete)
- **Tests**: 386/386 pass, mirrors in sync
- **Untracked on disk (user's, leave alone)**: `DOC_PARTY_COMPARISON.md`, `plans/CREATE_WORKTREE_SKILL.md`, `plans/RESTRUCTURE_RUN_PLAN.md`, `plans/ZSKILLS_MONITOR_PLAN.md`
- **No worktrees, no orphan branches** — clean repo

---

## What landed in the prior session (for README context)

Major wins to document:
- **UNIFY_TRACKING_NAMES** — per-pipeline subdir scheme (`.zskills/tracking/$PIPELINE_ID/`) instead of flat basenames; fixes parallel-pipeline collisions
- **Chunked `finish auto`** with +5-min cron spacing (`b172366`) — each phase runs as its own cron-fired turn
- **CI auto-fix cycle** — PR CI fails → fix agent → re-push → auto-merge (validated by CI_FIX_CYCLE_CANARY)
- **Parallel pipelines** — two concurrent `/run-plan` sessions on the same repo without collision (validated by PARALLEL_CANARYA/B)
- **Worktree orphan recovery** — preflight sweep of landed worktrees, `git worktree prune` for stale registry entries
- **Scope-based destructive-op policy** — permits `rm -rf /tmp/specific-dir` etc., blocks wide scope / variable expansion
- **7 bug fixes in Phase 6 PR-mode landing** — `--watch` exit-code unreliability re-check, push error-checking, PR_URL → PR_NUMBER extraction, etc.
- **Post-run-invariants** — 7-invariant mechanical gate after each run (worktree gone, branches deleted, plan report exists, no lingering 🟡, etc.)

Ready-but-not-run canary plans in `plans/`:
- `CANARY9_FINAL_VERIFY.md` — cross-branch final-verify gate
- `CANARY11_SCOPE_VIOLATION.md` (+ test plan) — verifier scope-flag catch
- `REBASE_CONFLICT_CANARY.md` — manual two-session
- `CHUNKED_CRON_CANARY.md` — ran successfully once, could re-run

---

## Session B scope (in priority order)

### 1. README update (highest value)

Current `README.md` predates most of the above. Topics to cover:

- **What zskills is** (probably already there; verify it mentions plan-driven dev + skill orchestration)
- **Landing modes**: cherry-pick / PR / direct — when to use each
- **Config file** (`.claude/zskills-config.json`): each field, what it means, default values. Reference `zskills-config.schema.json` alongside.
- **Tracking scheme** (Option B): per-pipeline subdirs at `.zskills/tracking/$PIPELINE_ID/`; what each marker prefix means (`requires.*`, `fulfilled.*`, `step.*`, `meta.*`); how the hook enforces them.
- **Hook policies**: destructive-op scope (permit `/tmp/`, block wide), tracking enforcement, push blocks on main, clear-tracking exec block
- **Canary suite**: brief mention of each canary and what it validates (tests/test-canary-failures.sh, e2e-parallel-pipelines.sh, manual canaries in plans/)
- **First-run guide**: walk a new user through install → configure → first plan → PR merged. Include the preset flag (see #2 below).

Suggested structure: what → install → configure → first run → advanced (canary suite, parallel pipelines, etc.). Existing README has some of this.

### 2. Installer preset UX

Modify `skills/update-zskills/SKILL.md` (+ mirror to `.claude/skills/update-zskills/SKILL.md`) to support preset flags and a greenfield interactive prompt.

**Presets** (names are proposals, refine):

| Preset | `execution.landing` | `execution.main_protected` | Git-push block on main? |
|---|---|---|---|
| `cherry-pick` (default) | `"cherry-pick"` | `false` | disabled |
| `locked-main-pr` | `"pr"` | `true` | **enabled** |
| `direct` | `"direct"` | `false` | disabled |

**Invocation modes**:

- `/update-zskills preset=locked-main-pr` → use that preset, no prompt
- `/update-zskills preset=cherry-pick` → explicit default, no prompt
- `/update-zskills` **and no existing `.claude/zskills-config.json`** → **ask the user** (see prompt below); write config accordingly
- `/update-zskills` **and existing config** → respect it, DON'T re-ask (idempotent re-install)

**Greenfield prompt** (plain conversational text, no AskUserQuestion per CLAUDE.md):

```
How should /run-plan land changes?
  (1) cherry-pick — each phase squash-lands directly to main (simple, solo)
  (2) locked-main-pr — plans become feature branches + PRs, CI, auto-merge
      (locked main, shared repo)
  (3) direct — work on main, no worktree isolation (minimal, risky)

Default: (1). Pick one, or accept the default.
```

If user picks (2), one follow-up:
```
Enable git-push block on main? (recommended for shared repos) [Y/n]
```

### 3. Push to public zskills

After README + installer updates land locally:
- Verify tests still green (386/386 minimum, may go higher with new installer tests)
- Verify mirrors in sync
- `git push` (user triggers — don't push autonomously)

---

## What NOT to do in Session B

- **Don't start RESTRUCTURE.** That's Session C. Keep README + installer preset as the entire scope.
- **Don't add new features** beyond the preset UX. Scope creep will blow context.
- **Don't push autonomously.** Stage and commit, user pushes.
- **Don't touch the 4 untracked user files** on disk (listed above).

---

## Rules reminders (from CLAUDE.md)

- Never `git add .` or `git add -A`. Stage by name.
- Never `git commit --no-verify`.
- Never push without explicit user permission in the current scope.
- Don't use AskUserQuestion — ask in plain conversation text.
- Mirror discipline: editing `skills/X/SKILL.md` MUST be followed by `cp skills/X/SKILL.md .claude/skills/X/SKILL.md`. CI's drift check catches mismatches (`.github/workflows/test.yml`).
- If hook placeholders are in `.claude/hooks/block-unsafe-project.sh` but no test infra, the preflight gate stays silent. The UI_FILE_PATTERNS sentinel is intentional (this project has no UI).

## Test commands

```bash
bash tests/run-all.sh                    # unit + integration, ~30s, 386 pass
RUN_E2E=1 bash tests/run-all.sh          # + e2e-parallel-pipelines (~2s extra), 397
```

Both should stay green at session end.

---

## Expected outputs at end of Session B

1. `README.md` — updated for current capabilities
2. `skills/update-zskills/SKILL.md` (+ mirror) — preset flags + greenfield prompt
3. Possibly `tests/test-hooks.sh` or a new test file — installer preset tests (parse preset flag, write config correctly)
4. All tests pass
5. Clean commits, ready for user to `git push`

Estimated scope: 1–2 hours focused work.

---

## Session C preview (do NOT start in B)

Session C = RESTRUCTURE /run-plan with safety net first:
- **A**. Add `tests/test-skill-conformance.sh` — greps for critical patterns RESTRUCTURE must preserve
- **C**. Run representative canaries as "before-RESTRUCTURE baseline"
- Then actual RESTRUCTURE (extract `scripts/compute-cron-fire.sh`, split /run-plan into modes/ + references/, etc.)
- Re-run canaries after, diff for parity

---

Good luck.
