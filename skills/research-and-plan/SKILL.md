---
name: research-and-plan
argument-hint: "[output FILE] <broad goal description>"
description: >-
  Decompose a broad goal into a sequence of executable sub-plans. Researches
  the domain, identifies sub-problems and dependencies, then produces a
  meta-plan where each phase delegates to /run-plan.
  Usage: /research-and-plan [output FILE] <description...>
---

# /research-and-plan [output FILE] \<description...> — Meta-Plan Decomposer

Breaks broad goals into focused sub-plans, each drafted via `/draft-plan`
and executed via `/run-plan`. The output is a meta-plan file whose phases
are pure delegation — no drafting happens during execution.

**Ultrathink throughout.**

## Arguments

- **output FILE** (optional) — meta-plan output path. Default:
  `plans/<SLUG>_META.md` (slug from description).
- **description** (required) — everything after recognized keywords.

**Detection:** `output` + path = explicit file. First token ending `.md` =
output file (prepend `plans/` if no `/`). Everything else = description.

**Escalation from `/draft-plan`:** If the invoking context mentions a
research file at `/tmp/draft-plan-research-*.md`, read it — that research
feeds Step 1 and avoids redundant exploration.

## Step 1 — Decomposition Research

Three focused investigations. If a research file was passed from
`/draft-plan`, start from it — validate and extend rather than starting
from scratch.

### 1a. Domain survey — Dispatch Explore agents to map the scope: what the
goal encompasses, what exists already, natural sub-domains, shared
infrastructure needed across sub-problems.

### 1b. Dependency analysis — Build a dependency graph: which sub-problems
are independent (parallelizable), which are sequential, and whether shared
prerequisites exist (e.g., "generalize the port system" before new domains).

### 1c. Scope sizing — Estimate each sub-problem's size. If a sub-plan
would need 8+ phases, split further. Each must be completable by
`/run-plan finish auto` in one session. Mark in-scope vs. out-of-scope.

**Present the decomposition to the user and wait for confirmation:**
> Decomposition complete. I identified N sub-problems:
> 1. **Sub-problem A** — [one-line description] (est. N phases)
> 2. **Sub-problem B** — [one-line description] (est. M phases, depends on A)
> ...
>
> Dependency graph: A -> B -> D, A -> C (independent of B)
>
> In scope: [list]. Out of scope: [list].
>
> Approve this decomposition? I'll draft sub-plans for each.

Do NOT proceed until the user confirms. They may reorder, drop, merge,
or add sub-problems.

## Step 2 — Draft All Sub-Plans

After user approval, draft each sub-plan by dispatching `/draft-plan`
agents sequentially. Each runs in its own context and gets full
adversarial review.

For each sub-problem:

1. Determine the sub-plan output path: `plans/<SLUG>_<N>.md` (or let the
   user specify).
2. If research from Step 1 was written to a file, pass that path to the
   `/draft-plan` agent so it has the decomposition context.
3. Dispatch: `/draft-plan output <path> <sub-problem description>`

**Staleness notes for dependent sub-plans.** Sub-plans that depend on
earlier ones get this in their Dependencies section:

```markdown
### Dependencies
- Plan A must be complete. **Note:** This plan was drafted before Plan A
  was implemented. APIs and data structures referenced here are based on
  Plan A's design, not actual code. `/run-plan` may refresh this plan
  before execution.
```

This tells `/run-plan` to offer a plan refresh (interactive) or
auto-refresh (auto mode) before implementing — ensuring the plan reflects
actual code, not predictions.

## Step 3 — Adversarial Review of the Decomposition

One round of review focused on the **decomposition itself** (not the
individual sub-plans — those already got reviewed by `/draft-plan`).

Dispatch two agents in parallel:

### Reviewer agent
- Are the sub-problem boundaries clean? (No shared work split across plans)
- Is the dependency ordering correct?
- Are there missing sub-problems? (Infrastructure, integration testing,
  documentation?)
- Is scope sizing realistic?

### Devil's advocate agent
- **Wrong split** — would a different decomposition be simpler?
- **Hidden coupling** — do sub-plans share assumptions that will break if
  one changes?
- **Missing glue** — who integrates the sub-plans? Is there a final
  integration phase?
- **Deferred complexity** — is the hardest part buried in the last sub-plan?

Address every finding: fix the decomposition or justify why it's not a
problem. If the decomposition changes, update affected sub-plans.

## Step 4 — Write the Meta-Plan

After all sub-plans are drafted and the decomposition is reviewed, write
the meta-plan. Every phase is pure delegation — `/run-plan` executes
sub-plans, no `/draft-plan` during execution.

### Meta-plan template

```markdown
# Meta-Plan: <Title>

## Overview
[What this meta-plan accomplishes and the decomposition rationale]

## Decomposition
[Sub-problems identified, dependency graph, scope rationale]

## Sub-Plans
| Plan | Phases | Dependencies | Notes |
|------|--------|--------------|-------|
| [SUB_PLAN_A.md](SUB_PLAN_A.md) | N | None | |
| [SUB_PLAN_B.md](SUB_PLAN_B.md) | M | A | May need refresh after A |

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Implement: <sub-problem A> | ⬚ | | |
| 2 — Implement: <sub-problem B> | ⬚ | | |

## Phase N — Implement: <Sub-problem X>

### Goal
Execute the plan for <sub-problem X>.

### Execution: delegate /run-plan plans/<SUB_PLAN_X>.md finish auto

### Acceptance Criteria
- [ ] All phases in the sub-plan are marked Done
- [ ] All tests pass on main after landing
- [ ] Plan report exists with verification results

### Dependencies
[List prerequisite phases. Dependent sub-plans may auto-refresh.]

## Plan Quality
**Drafting process:** /research-and-plan with decomposition review
**Sub-plans:** Each drafted via /draft-plan with adversarial review
**Decomposition review:** 1 round (reviewer + devil's advocate)
```

Repeat the `Phase N` template for each sub-problem. First phase has
`Dependencies: None`. Dependent phases list their prerequisites and note
that the sub-plan may auto-refresh to reflect actual implementation.

### Finalization

1. Write the meta-plan to the output path.
2. Update `plans/PLAN_INDEX.md` if it exists (add a row to "Ready to Run").
   If it doesn't exist, suggest `/plans rebuild`.
3. Present the result:
   > Meta-plan written to `plans/<FILE>.md` with N sub-plans.
   > Sub-plans: [list with paths]
   >
   > Execute with: `/run-plan plans/<FILE>.md`
   > Or with scheduling: `/run-plan plans/<FILE>.md auto every 4h now`

## Key Rules

- **Pure delegation in the meta-plan.** Every phase uses
  `### Execution: delegate /run-plan`. No `delegate /draft-plan` — all
  drafting happens upfront in Step 2.
- **User confirms the decomposition.** Step 1 ends with a checkpoint.
  Do not draft sub-plans until the user approves the split.
- **Staleness notes on dependent sub-plans.** Sub-plans drafted before
  their dependencies are implemented get explicit warnings so `/run-plan`
  knows to refresh.
- **Adversarial review targets the decomposition.** Individual sub-plans
  get their own review via `/draft-plan`. Step 3 reviews the split itself.
- **Respect constraints.** No external solvers, no bundlers, no
  dependencies without approval. These apply to every sub-plan.
- **Each sub-plan must be session-completable.** If a sub-plan needs 8+
  phases, split it further.
