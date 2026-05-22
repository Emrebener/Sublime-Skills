---
name: receiving-review-findings
description: Use inline by the SDD coordinator when a reviewer subagent returns its findings for a spec or plan (Stages 3, 5, 9, 10). Guides how to evaluate findings, decide what to fix vs push back on, and avoid performative agreement.
---

# Receiving Review Findings

## Overview

Review feedback is *input to evaluate*, not orders to follow. The coordinator's job is to read the findings carefully, verify they're real, fix what's real, push back on what isn't, and surface to the user anything that needs human judgment.

**Core principle:** Verify before fixing. No performative agreement. Technical correctness over social comfort.

**Announce at start:** "I'm using the receiving-review-findings skill to process the reviewer's findings."

## When to Use

The coordinator loads this skill inline whenever a reviewer subagent returns output, in any of:
- Stage 3 — auto spec-review findings
- Stage 5 — optional 2nd spec-review findings
- Stage 9 — auto plan-review findings
- Stage 10 — optional 2nd plan-review findings

This skill does NOT cover per-task reviewer findings during implementation — `implementing-plans` handles those with its own re-dispatch-implementer loop. Per-task reviews are about delegating fixes to a fresh implementer; this skill is about the coordinator directly handling the artifact (spec or plan).

## Hard Gates

- Do NOT begin editing the artifact before reading ALL findings end-to-end first
- Do NOT use phrases like "great point", "you're absolutely right", "thanks for catching that" — they're performative and worthless. State what you'll do, or push back.
- Do NOT silently ignore a finding because "the user will probably catch it" — every finding gets handled or pushed back, with a reason
- Do NOT proceed to the next stage with an unresolved CRITICAL or HIGH finding

## Checklist

1. Read all findings end-to-end before reacting
2. Categorize: which are CRITICAL, HIGH, MEDIUM, LOW
3. For each CRITICAL and HIGH: verify it's a real issue, then fix or push back
4. For each MEDIUM: decide if trivial-fix-now or defer-to-open-questions
5. For each LOW: note in passing; usually skip
6. Re-dispatch reviewer if material changes were made (per stage protocol)
7. Surface to user if a finding needs human judgment
8. Update state file if state changed (e.g., fix iterations counted)

## Step 1: Read Without Reacting

Read the entire findings report end-to-end before opening any file to edit. Why: findings can be related; partial reading leads to fix-then-undo cycles.

## Step 2: Categorize by Severity

The reviewer skill puts findings in CRITICAL / HIGH / MEDIUM / LOW buckets. Treat them as:

| Severity | Treatment |
|---|---|
| CRITICAL | Must be addressed. Verify, then fix or push back. Block stage advance until resolved. |
| HIGH | Must be addressed. Same as CRITICAL. |
| MEDIUM | Advisory. Fix if trivial. Otherwise add to spec/plan Open Questions section or accept and document. |
| LOW | Note. Usually skip. Fix only if it's a one-character correction. |

If the reviewer mis-categorized something obviously (e.g., a typo flagged as CRITICAL), don't escalate it back to them — just treat it at the right level. Reviewers can be miscalibrated; you're the next reader.

## Step 3: Verify Each CRITICAL/HIGH Before Acting

For each CRITICAL or HIGH finding:

1. **Read the section the finding cites** in the spec or plan. Is the issue actually there?
2. **Check against project context** — does the finding contradict the constitution or a prior ADR? (If yes, the finding is more important; the project's principles override.)
3. **Check against discovery context** — was this decision deliberately made and recorded? (If yes, the finding might be wrong; reviewer may have missed context.)
4. **Decide:**
   - **Real and the spec/plan is wrong** → fix
   - **Real but it was a deliberate decision** → push back to the reviewer (next dispatch) with reasoning, OR document in the artifact why it's deliberate
   - **Not real** → the reviewer is wrong; document why and proceed

**Forbidden response patterns:**
- "Great point! Let me fix that..." → just state the fix
- "You're absolutely right..." → if they're right, just fix it; if not, push back
- Blind implementation before verification → always verify first
- "I'll address all of these" without per-item evaluation → evaluate each separately

## Step 4: Apply Fixes

If you're fixing a finding:

- **For spec issues:** edit the spec file directly. The coordinator has the discovery context; you can resolve most issues without re-running discovery.
- **For plan issues:** edit the plan file directly. Same logic.
- **If the issue is too substantive** (e.g., the spec is fundamentally underspecified in a way that requires going back to the user): STOP applying fixes. Surface to the user (see Step 7).
- Always use atomic writes (write to `.tmp`, then `mv`) for any artifact edit.

## Step 5: When to Push Back

Push back when:
- The finding contradicts a deliberate decision recorded in the discovery context, an ADR, or the constitution
- The reviewer is missing context that's in another section the reviewer didn't read
- The finding is technically incorrect (e.g., reviewer says "X is unmeasurable" but X has a concrete metric two lines down)
- The finding violates YAGNI ("you should also handle [scenario]" where the scenario is out-of-scope)

How to push back:
- Don't argue with the reviewer's text (they're a subagent, they don't read replies)
- Document the disagreement in the spec/plan inline (e.g., as a sentence: "Note: deferred per ADR-0007") so future readers know the issue was considered and dismissed
- Track the push-back in the state file:
  ```json
  {
    "reviewer_pushbacks": [
      {
        "stage": "spec_auto_review",
        "finding": "<short identifier>",
        "reason": "<your technical reasoning>"
      }
    ]
  }
  ```

## Step 6: Re-Dispatch Reviewer if Material Changes Were Made

If you applied fixes to address CRITICAL or HIGH findings, re-dispatch the same reviewer (per the stage's protocol — typically capped at 2 fix iterations before escalating to user).

If you only made MEDIUM/LOW changes (or only pushed back), no re-dispatch is needed; proceed to next stage.

## Step 7: Surface to User When Findings Need Judgment

Some findings require the user, not the coordinator. Surface them when:
- A finding implies the spec needs decomposition (multiple subsystems) — user's call
- A finding identifies a scope creep that the user requested but didn't realize was creep — user's call
- A finding contradicts a recent user statement — clarify with user, not by guessing

Format:

> "The reviewer found <N> CRITICAL/HIGH issues I can't resolve without your input:
>
> 1. <Finding summary>: <Why it needs your input>
> 2. ...
>
> Options:
> - Address them now (tell me what to do for each)
> - Return to spec/plan stage and revise — I'll re-run discovery if needed
> - Override the reviewer (you'll need to give a reason; it goes in `reviewer_pushbacks`)"

Wait for the user's direction.

## Step 8: Escalate on Cap Hit

The spec/plan review fix-loop is capped at **2 iterations** (a hard ceiling — not config-overridable). At cap hit, you have:
- Iteration 1: reviewer returned Issues Found → coordinator applied fixes → re-dispatched reviewer
- Iteration 2: reviewer returned Issues Found again → coordinator applied fixes → re-dispatched reviewer
- (If iteration 2's re-dispatch returns Issues Found again, the cap is hit)

At this point, do NOT iterate further. The pattern of unresolved findings says one of:
- The artifact has a fundamental gap that needs human input, not more polishing
- The reviewer is miscalibrated for this artifact's domain
- Findings and fixes are oscillating (fix A creates issue B; fix B re-creates issue A)

Surface to user explicitly with the full history. Format:

> "Spec/plan review hit its fix-loop cap (2 iterations) with unresolved findings.
>
> **Fix history:**
> - Iteration 1: reviewer flagged [N] CRITICAL/HIGH. Coordinator applied: [brief summary]. Re-review: [N] new/remaining issues.
> - Iteration 2: applied [brief summary]. Re-review: [N] still flagged.
>
> **Currently unresolved (CRITICAL/HIGH only):**
> 1. <Finding summary> — <last attempted fix and why it didn't satisfy the reviewer>
> 2. ...
>
> **Options:**
> 1. **Iterate with my guidance** — you tell me exactly how to address each finding; I apply your edits literally (no further evaluation), commit, and we move on without another auto-review
> 2. **Override the reviewer** — you say why each finding doesn't actually apply; I record each push-back in `reviewer_pushbacks` (with your reason) and we advance to the next stage
> 3. **Accept the current state** — proceed despite unresolved findings; I record them in `reviewer_pushbacks` as 'accepted with known issues' and advance
> 4. **Abort the stage** — pause the SDD run; you investigate manually and re-invoke when ready"

Wait for user's selection. Whatever they choose:
- Update `state.json`:
  ```json
  {
    "spec_auto_review_iterations": 2,
    "reviewer_pushbacks": [
      { "stage": "spec_auto_review", "finding": "<id>", "reason": "<user-provided or 'cap-hit-iterate-with-guidance'>" }
    ]
  }
  ```
- Do NOT re-dispatch the reviewer on iteration 3. The cap is hard.

The same protocol applies to plan review (Stage 9 / 10) — substitute `plan_auto_review_iterations`.

## Step 8: Update State

After processing, update the state file (atomic write) with any tracked information:

```json
{
  "<stage>_review_iterations": <N>,
  "reviewer_pushbacks": [...],
  "updated_at": "<ISO-8601 timestamp>"
}
```

**Do NOT commit.** Through Stages 2–10, state.json updates are written atomically but remain uncommitted. The `choosing-feature-branch` skill at Stage 12 batch-commits the accumulated state alongside the SDD planning artifacts. (From Stage 13 onward, normal per-stage commits resume.)

## Common Mistakes

| Mistake | Fix |
|---|---|
| Performative agreement ("great point!") | State the fix or push back; no agreement theater |
| Reading findings and immediately editing without verification | Always verify against artifact + project context first |
| Fixing CRITICAL while ignoring HIGH because "I'll batch the HIGHs" | Each CRITICAL/HIGH gets per-item evaluation; no batching to defer real work |
| Treating LOW findings as required | LOW is "could fix"; usually skip |
| Re-dispatching reviewer after every minor change | Only re-dispatch if material changes (CRITICAL/HIGH fixes); MEDIUM/LOW alone don't warrant re-review |
| Silently dismissing a finding without documenting why | Push-backs go in `reviewer_pushbacks` in state file; never silent |
| Looping more than the stage's cap without escalating | Each stage has a cap (typically 2-3); escalate to user when hit |

## Red Flags

- About to type "You're absolutely right" anywhere → STOP; delete; state the fix
- About to "address all findings" without per-item evaluation → STOP; evaluate each
- About to dispatch a 3rd fix-review iteration (cap is 2) → STOP; follow Step 8's escalation protocol
- About to silently skip a HIGH finding → STOP; either fix or push back with reasoning
- About to edit the artifact based only on the reviewer's quote, without reading the full section → STOP; read the full section first
- About to ask the reviewer "could you clarify?" → STOP; reviewer is a subagent, you can't have a conversation; re-dispatch with a focused REVIEW_FOCUS instead
