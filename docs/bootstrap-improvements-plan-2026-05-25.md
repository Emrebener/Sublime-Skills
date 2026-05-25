# Bootstrap Pipeline Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve the project-bootstrap pipeline from descriptive-only to descriptive-or-prescriptive: add a guarded suggestion-pass mechanic to every discovery skill, add two new discovery skills (testing, memory-file), add a sibling audit skill, and add a cross-artifact coherence check, per the design in `docs/bootstrap-improvements-2026-05-25.md`.

**Architecture:** All discovery skills keep their existing 6-step shape; the suggestion pass is a new optional Step 1.5 + Q1.5 gated by a `SUGGEST` parameter threaded from the coordinator. Audit re-uses the same discovery skills via a new `MODE=audit` value adding a Step 1.6 drift check and a Q0 drift-resolution question. The coherence check lives as a reusable framework script invoked by both bootstrap (end-of-run) and audit (start-of-run).

**Tech Stack:** Markdown (SKILL.md authoring), Bash + Python 3 + PyYAML (framework scripts, matching the existing `validate-config.sh` pattern), YAML (config scaffold). No new dependencies.

**Reference docs:** Design lives at `docs/bootstrap-improvements-2026-05-25.md`. Existing bootstrap narrative at `docs/bootstrap.md`. Each task below quotes the relevant spec sections; the spec is the source of truth for rationale.

---

## File Structure

**New files:**
- `skills/project-bootstrap/ss-bs-discovering-testing/SKILL.md` — produces `docs/TESTING.md`
- `skills/project-bootstrap/ss-bs-discovering-memory-file/SKILL.md` — produces the agent memory file
- `skills/project-bootstrap/ss-bs-auditing-project/SKILL.md` — sibling coordinator for audit re-runs
- `skills/spec-driven-development/framework/coherence-check.sh` — Tier 1 structural checks across artifacts

**Modified files:**
- `skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md` — add opt-in switch, expand todo list to 14 items, add coherence step, add testing + memory-file stages to per-file loop, add config-migration sub-step
- `skills/project-bootstrap/ss-bs-discovering-{constitution,architecture,glossary,domain-model,design}/SKILL.md` — each: add Step 1.5 diagnose (gated by SUGGEST), add Q1.5, add provenance-marker handling in Step 4/6, add `MODE=audit` support (Step 1.6 drift + Q0)
- `skills/project-bootstrap/scaffolds/config.yml` — add `context.testing_path`, add `suggest:` block
- `skills/spec-driven-development/framework/validate-config.sh` — accept new keys
- `skills/spec-driven-development/framework/discover-context.sh` — emit `testing` key

**Documentation updates:**
- `README.md` — entries for new skills
- `docs/bootstrap.md` — narrative update for 7-artifact pipeline and audit sibling
- `docs/CONTEXT-FILES.md` — add TESTING.md and memory-file rows

**Phase boundaries** (each phase ends in working software the engineer can commit and stop at):
- **Phase 1** — Foundation (config + framework): scaffold and validator accept new keys
- **Phase 2** — Suggestion pass prototype (architecture skill only)
- **Phase 3** — Suggestion pass generalized to the other 4 existing skills
- **Phase 4** — New discovery skills (testing, memory-file) with suggestion pass built in
- **Phase 5** — Coherence check framework script
- **Phase 6** — Bootstrap coordinator updates wire everything together
- **Phase 7** — Audit MODE added to all 7 discovery skills
- **Phase 8** — Audit coordinator skill
- **Phase 9** — Documentation

---

## Phase 1: Foundation — Config & Framework

### Task 1: Add `context.testing_path` and `suggest.default` to the config scaffold

**Files:**
- Modify: `skills/project-bootstrap/scaffolds/config.yml`

Spec reference: Section 11.1.

- [ ] **Step 1: Read the current scaffold to confirm exact line ranges**

Run: `cat skills/project-bootstrap/scaffolds/config.yml`
Note the current shape: `context:` block has 5 path keys; no `suggest:` block exists.

- [ ] **Step 2: Add `testing_path` key inside the `context:` block, slotted between architecture and glossary**

Edit `skills/project-bootstrap/scaffolds/config.yml`:

```yaml
context:
  constitution_path: docs/constitution.md       # project-wide principles (MUST/SHALL rules)
  architecture_path: docs/ARCHITECTURE.md       # system structure overview
  testing_path: docs/TESTING.md                 # test strategy (frameworks, fixtures, coverage)
  glossary_path: docs/GLOSSARY.md               # canonical domain vocabulary
  domain_path: docs/DOMAIN.md                   # conceptual entities and relationships
  design_path: docs/DESIGN.md                   # visual design system (colors, type, spacing, components)
```

- [ ] **Step 3: Append a new `suggest:` block at the end of the file (before EOF)**

Append to `skills/project-bootstrap/scaffolds/config.yml`:

```yaml

# ── Suggestion pass default (bootstrap and audit) ──────────────────
# How the coordinators handle the prescriptive diagnose pass that
# each discovering-X skill optionally runs to propose improvements
# the project hasn't codified yet.
suggest:
  # ask = coordinator asks once at bootstrap start (preserves current UX)
  # on  = always run diagnose; no question
  # off = never run diagnose
  default: ask
```

- [ ] **Step 4: Verify the file is valid YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('skills/project-bootstrap/scaffolds/config.yml'))" && echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add skills/project-bootstrap/scaffolds/config.yml
git commit -m "Bootstrap config scaffold: add testing_path and suggest.default"
```

---

### Task 2: Update `validate-config.sh` to accept the new keys

**Files:**
- Modify: `skills/spec-driven-development/framework/validate-config.sh`
- Test (ad-hoc shell tests): no test directory exists today; tests run inline against `/tmp/` fixture configs

Spec reference: Section 11.3.

- [ ] **Step 1: Write the failing test for `testing_path` acceptance**

Create `/tmp/test-config-1.yml` with:

```yaml
context:
  constitution_path: null
  architecture_path: null
  testing_path: null
  glossary_path: null
  domain_path: null
  design_path: null
branching:
  branch_pattern: "feat/{short-name}"
grill:
  question_cap: 10
memory_file:
  path: null
  character_limit: 40000
suggest:
  default: ask
```

Run: `./skills/spec-driven-development/framework/validate-config.sh /tmp/test-config-1.yml && echo PASS || echo FAIL`
Expected (before any code change): FAIL (validator rejects unknown `testing_path` and `suggest` keys).

- [ ] **Step 2: Locate the python branch's key allowlist in `validate-config.sh`**

Run: `grep -n "constitution_path\|design_path" skills/spec-driven-development/framework/validate-config.sh`
Identify the line(s) listing the recognized `context.*_path` keys in both the python-path validation and the awk fallback.

- [ ] **Step 3: Add `testing_path` to the python-path allowlist**

In the python validation section of `validate-config.sh`, find the set/list that enumerates the valid `context.*` keys (typically a tuple like `("constitution_path", "architecture_path", "glossary_path", "domain_path", "design_path")`) and add `"testing_path"` slotted between architecture and glossary:

```python
("constitution_path", "architecture_path", "testing_path", "glossary_path", "domain_path", "design_path")
```

- [ ] **Step 4: Add `testing_path` to the awk fallback allowlist**

In the awk fallback section of the same script, find the equivalent allowlist (likely a regex or string-set of recognized key names) and add `testing_path`. The exact form depends on the current awk implementation — read the surrounding lines and follow the established pattern.

- [ ] **Step 5: Add `suggest.default` recognition with allowed-value validation**

In the python branch, after the existing top-level block validation (where `branching`, `grill`, `memory_file` are recognized), add `suggest` as a recognized top-level block with one allowed key `default` whose value must be one of `"ask"`, `"on"`, `"off"`. Emit `FAIL: suggest.default must be one of ask|on|off (got: <value>)` for any other value.

Concrete python addition (place alongside the existing block handlers):

```python
if "suggest" in cfg:
    sb = cfg["suggest"]
    if not isinstance(sb, dict):
        findings.append("FAIL: suggest must be a mapping")
    else:
        unknown = set(sb.keys()) - {"default"}
        for k in unknown:
            findings.append(f"FAIL: suggest.{k} is not a recognized key")
        if "default" in sb and sb["default"] not in ("ask", "on", "off"):
            findings.append(f"FAIL: suggest.default must be one of ask|on|off (got: {sb['default']!r})")
```

- [ ] **Step 6: Add `suggest:` recognition to the awk fallback**

In the awk fallback, add `suggest` to the set of recognized top-level blocks so it doesn't trigger an "unknown block" finding. The awk fallback can skip detailed value validation — the python path is the primary validator and the fallback only catches gross structural errors.

- [ ] **Step 7: Re-run the Step 1 test to verify it now passes**

Run: `./skills/spec-driven-development/framework/validate-config.sh /tmp/test-config-1.yml && echo PASS || echo FAIL`
Expected: PASS.

- [ ] **Step 8: Write a negative test for invalid `suggest.default` value**

Create `/tmp/test-config-2.yml` — copy `/tmp/test-config-1.yml` and change `default: ask` to `default: maybe`:

```bash
sed 's/default: ask/default: maybe/' /tmp/test-config-1.yml > /tmp/test-config-2.yml
```

Run: `./skills/spec-driven-development/framework/validate-config.sh /tmp/test-config-2.yml; echo "exit: $?"`
Expected: exit code 1, stderr includes `FAIL: suggest.default must be one of ask|on|off (got: 'maybe')`.

- [ ] **Step 9: Verify existing configs still validate (regression check)**

Run: `./skills/spec-driven-development/framework/validate-config.sh skills/project-bootstrap/scaffolds/config.yml && echo PASS || echo FAIL`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add skills/spec-driven-development/framework/validate-config.sh
git commit -m "validate-config.sh: accept testing_path and suggest.default keys"
```

---

### Task 3: Update `discover-context.sh` to emit a `testing` key

**Files:**
- Modify: `skills/spec-driven-development/framework/discover-context.sh`

Spec reference: Section 11.4.

- [ ] **Step 1: Read current emission shape**

Run: `cat skills/spec-driven-development/framework/discover-context.sh | head -100`
Identify the JSON-construction logic that emits keys for `constitution`, `architecture`, `glossary`, `domain`, `design`. Note the pattern (likely reads each `context.<name>_path` from config, checks existence, emits the resolved path or `null`).

- [ ] **Step 2: Write a quick verification harness**

Create a temporary repo state with a config that has `testing_path: docs/TESTING.md` and the file existing:

```bash
WORK=$(mktemp -d) && cd "$WORK" && git init -q
mkdir -p .sublime-skills docs
cp "$OLDPWD/skills/project-bootstrap/scaffolds/config.yml" .sublime-skills/config.yml
touch docs/TESTING.md docs/constitution.md
"$OLDPWD/skills/spec-driven-development/framework/discover-context.sh"
cd "$OLDPWD" && rm -rf "$WORK"
```

Expected (before code change): JSON output that includes `"constitution": "docs/constitution.md"` but no `testing` key.

- [ ] **Step 3: Add `testing` to the discovery logic**

In `discover-context.sh`, locate the loop or sequence of emissions for the 5 existing keys. Add a 6th emission for `testing`, mirroring the existing pattern exactly:
- Read `context.testing_path` from the merged config (use the same config-reading approach the existing keys use).
- If null → emit `"testing": null`.
- If a path → check existence; emit `"testing": "<path>"` if exists, `"testing": null` if not.

The key name in JSON output is `testing` (no `_path` suffix, matching the existing convention where `constitution_path` config → `constitution` key in JSON).

- [ ] **Step 4: Re-run the verification harness**

Repeat the Step 2 commands.
Expected: JSON output includes `"testing": "docs/TESTING.md"`.

- [ ] **Step 5: Verify on the actual repo (regression — testing key should be absent because no `docs/TESTING.md` exists yet in this repo)**

Run: `./skills/spec-driven-development/framework/discover-context.sh | python3 -m json.tool`
Expected: `testing` key present with value `null` (because no `docs/TESTING.md` exists and no `testing_path` in the live `.sublime-skills/config.yml` — but the scaffold has it, so depending on this repo's own config the value may resolve to null OR an existing-file path).

- [ ] **Step 6: Commit**

```bash
git add skills/spec-driven-development/framework/discover-context.sh
git commit -m "discover-context.sh: emit testing key"
```

---

**Phase 1 complete.** Framework now accepts the new config keys and the discovery script reports the testing artifact. No skill changes yet; existing bootstrap continues to work bit-for-bit.

---

## Phase 2: Suggestion Pass Prototype — Architecture Skill

The architecture skill is the prototype per spec Section 13 ("What I'd build first" → architectural anti-patterns are most visible). All other discovery skills will follow this pattern in Phase 3.

### Task 4: Add suggestion pass to `ss-bs-discovering-architecture`

**Files:**
- Modify: `skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md`

Spec reference: Sections 6.1–6.6, 6.2 (architecture row).

- [ ] **Step 1: Read the existing skill end-to-end**

Run: `cat skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md`
Note section anchors: the Hard Gates section, the "Top-Level Flow" diagram, Step 1 (with substeps 1a–1i), Step 2 announcement template, Step 3 (Q1–Q5), Step 4 draft/show, Step 6 atomic write.

- [ ] **Step 2: Add a SUGGEST input parameter to the inputs documentation**

Find the section that documents inputs the coordinator passes (typically near the top, alongside `MODE`, `EXISTING_CONTENT`, `FILE_PATH`, `REPO_ROOT`). Add `SUGGEST` as a fourth input:

```markdown
**`SUGGEST`** — `on` or `off`. When `on`, run Step 1.5 (silent diagnose) and surface Q1.5 in Step 3. When `off`, skip both — identical to pre-suggestion-pass behaviour. Defaulted by the coordinator from `suggest.default` in config and the opt-in question at bootstrap start. Always `on` in audit mode.
```

- [ ] **Step 3: Update the Top-Level Flow diagram to show Step 1.5 conditionally**

Find the Top-Level Flow ASCII block. Insert a Step 1.5 row in both branches (create/replace and extend):

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan (layout, build, …)     │
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │  ← NEW
│   → Step 2: announce findings (+ diagnoses)         │
│   → Step 3: targeted questions (Q1, Q1.5 if SUGGEST,│
│             then Q2-Q5)                             │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1: silent code scan + read EXISTING_CONTENT│
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │  ← NEW
│   → Step 2: announce findings + gaps + diagnoses    │
│   → Step 3: targeted questions on gaps + Q1.5       │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write of merged content          │
└─────────────────────────────────────────────────────┘
```

- [ ] **Step 4: Insert a complete Step 1.5 section between Step 1 and Step 2**

Locate the end of Step 1 (after substep 1i "Compile candidate sections in memory"). Insert this new section:

````markdown
## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip this step entirely and proceed to Step 2.

Diagnose looks for anti-patterns and missing-but-typically-valuable structural decisions in the architecture. Every diagnose finding must be **evidence-cited** with specific file paths or concrete counts. Abstract "you should do X" findings are not allowed.

### 1.5a. Architecture diagnose categories

For each category below, scan additional files if needed (within the budget — see Hard Gates). Generate at most 5 candidate suggestions total across all categories, ranked by severity → evidence strength → impact.

- **Cross-service direct DB access.** If multiple services share a single DB and at least one service reads another's tables directly. Evidence: list at least 2-3 file paths showing the cross-table reads.
- **Synchronous service chains where async would add resilience.** Service A makes HTTP calls to service B inside a request handler with no queueing or fallback. Evidence: file paths showing the synchronous calls.
- **Shared mutable state across modules.** Module-level mutable maps, singletons, or DI containers being mutated post-init from multiple call sites. Evidence: file paths to definitions + call sites.
- **Missing boundaries / ownership for shared code.** A `common/`, `shared/`, or `lib/` directory imported by all services with no documented ownership rules. Evidence: directory path + import counts.
- **Missing API gateway for public surfaces.** Multiple services exposing public HTTP endpoints with no routing/auth layer in front. Evidence: list the services + their `app.listen`/equivalent.

### 1.5b. Compile candidate suggestions in memory

Each candidate must include:
- `severity`: one of `MUST`, `SHOULD`, `INFO` — see Hard Gates for the matching evidence bar
- `title`: one-line headline (e.g., "Declare cross-service DB access policy")
- `evidence`: specific file paths or counts (e.g., `services/billing/src/invoice.ts:34, .../report.ts:88, .../sync.ts:12`)
- `proposed_addition`: exact markdown text to add to the artifact (a new section, a new component entry, etc.)

Drop any candidate that cannot be cited with specific evidence. Drop any candidate where the severity guess cannot be justified from the evidence (no MUST without observable harm).

If more than 5 candidates remain after dropping unsupported ones, rank by:
1. Severity (MUST > SHOULD > INFO)
2. Evidence count (more file paths / higher counts = stronger)
3. Impact (changes that prevent bugs > changes that improve consistency)

Surface the top 5. If 0 candidates remain, the candidate list is empty and Q1.5 in Step 3 is skipped silently.
````

- [ ] **Step 5: Modify Step 2 (Announce Findings) to mention diagnose**

Find the Step 2 section. Add a sentence to the example announcement (or a new conditional) so it covers the case where Step 1.5 produced suggestions:

> "If `SUGGEST=on` AND Step 1.5 produced ≥1 candidate, extend the announcement with: '…and I noticed a few things worth considering that aren't currently codified — I'll show those after we confirm the observed candidates.'"

Insert this paragraph immediately after the existing example announcement block in Step 2.

- [ ] **Step 6: Modify Step 3 to insert Q1.5 between Q1 and Q2**

Find the Q1 block in Step 3 (multi-select for observed candidates). After Q1's closing ``` ``` fence, insert this Q1.5 block:

````markdown
### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND Step 1.5 produced ≥1 candidate)

```
Question: "Here are some things I'd suggest adding even though they're
not currently codified. These are opinionated — pick any you want to
include:"

Multi-select. For each Step 1.5 candidate, list as:
  - [suggestion · <severity> · <evidence-summary>] <title>
    Evidence: <evidence>
    Proposed addition: <one-line summary of proposed_addition>

Always include "None of these — keep the doc descriptive only" as the last option.
```

If the user picks none, treat as "no suggestions accepted" and proceed to Q2. Accepted suggestions are carried into Step 4 (Draft & Show) and rendered with provenance markers.
````

- [ ] **Step 7: Modify Step 4 (Draft & Show to User) to include accepted suggestions**

Find Step 4's draft-synthesis bullet list (which currently mentions scan findings, Q1 confirmations, Q2-Q5 answers). Add a new bullet:

```markdown
- Accepted Q1.5 suggestions (rendered as new sections / new component entries with provenance markers — see Step 6)
```

- [ ] **Step 8: Modify Step 6 (Atomic Write) to document the provenance marker format for accepted suggestions**

At the end of Step 6, add this subsection:

````markdown
### Provenance markers for accepted Q1.5 suggestions

Each accepted Q1.5 suggestion becomes a regular section in the artifact (e.g., a new "Boundaries" subsection, a new "Components" entry, or a new top-level recommendation block). Append a provenance line at the end of the section using this exact format:

```markdown
> _Added via bootstrap suggestion pass (YYYY-MM-DD)._ _Evidence: <evidence
> summary from the Q1.5 candidate>. Not currently enforced — declared here as
> an aspirational architectural rule._
```

Replace `YYYY-MM-DD` with today's date. The audit skill reads this marker on re-runs to ask whether the aspiration has been realized in code.
````

- [ ] **Step 9: Update Hard Gates with diagnose budgets**

Find the Hard Gates section. Append:

```markdown
- Do NOT exceed the diagnose budget: Step 1.5 (when run) takes at most ~2 minutes of agent work and reads at most 10 additional files beyond what Step 1 read. If you need more reads, surface fewer suggestions instead of widening the budget.
- Do NOT surface diagnose candidates without specific file-path or count evidence. Abstract "best practice" suggestions are forbidden.
- Do NOT pad the Q1.5 list to fill a quota. If diagnose finds 0 strong candidates, Q1.5 is skipped silently — this is the correct outcome, not a bug.
- Do NOT use severity MUST/SHALL for a diagnose candidate unless there is observable harm (broken tests, security risk, observed bug pattern). Weaker evidence defaults to SHOULD or INFO.
```

- [ ] **Step 10: Update Common Mistakes table with suggestion-pass-specific rows**

Find the Common Mistakes table near the end of the skill. Add these rows:

```markdown
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest |
| Forgetting the provenance marker on an accepted Q1.5 suggestion | Audit relies on the marker to recognize aspirational entries; without it, drift detection breaks |
| Running Step 1.5 when SUGGEST=off | Skip Step 1.5 entirely when off; do not run-but-suppress |
```

- [ ] **Step 11: Structural verification — check all required additions are present**

Run:

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md
grep -q "Step 1.5: Silent Diagnose" "$SKILL" && echo "Step 1.5: OK" || echo "Step 1.5: MISSING"
grep -q "Q1.5 — Confirm suggested additions" "$SKILL" && echo "Q1.5: OK" || echo "Q1.5: MISSING"
grep -q "SUGGEST" "$SKILL" && echo "SUGGEST input: OK" || echo "SUGGEST input: MISSING"
grep -q "Added via bootstrap suggestion pass" "$SKILL" && echo "Provenance marker: OK" || echo "Provenance marker: MISSING"
grep -q "diagnose budget\|diagnose findings" "$SKILL" && echo "Budget docs: OK" || echo "Budget docs: MISSING"
```

Expected: all five lines print `OK`.

- [ ] **Step 12: Manual readability check**

Open `skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md` in an editor. Read from top to bottom. Confirm:
- The skill still makes sense to someone reading it for the first time
- Step 1.5 is clearly bracketed as conditional on `SUGGEST=on`
- The Q1.5 block visually distinguishes "observed" (Q1) from "suggested" (Q1.5)
- The provenance marker format is exact and unambiguous

If any of these read poorly, edit inline.

- [ ] **Step 13: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md
git commit -m "discovering-architecture: add suggestion pass (Step 1.5 + Q1.5)"
```

---

**Phase 2 complete.** One discovery skill now has the full suggestion pass. The coordinator doesn't yet thread `SUGGEST=on` (Phase 6), so this skill behaves identically to today unless invoked manually with `SUGGEST=on`.

---

## Phase 3: Generalize Suggestion Pass to the Other 4 Existing Skills

Tasks 5–8 apply the same suggestion-pass mechanism (Step 1.5, Q1.5, provenance markers, diagnose budget) to the remaining four discovery skills. The step structure mirrors Task 4 but each task spells out its own per-skill diagnose categories and provenance-marker placement.

### Task 5: Add suggestion pass to `ss-bs-discovering-constitution`

**Files:**
- Modify: `skills/project-bootstrap/ss-bs-discovering-constitution/SKILL.md`

Spec reference: Sections 6.1–6.6, 6.2 (constitution row).

- [ ] **Step 1: Read the existing skill end-to-end**

Run: `cat skills/project-bootstrap/ss-bs-discovering-constitution/SKILL.md`

- [ ] **Step 2: Add `SUGGEST` input parameter**

Insert at the top of the file alongside existing inputs (`MODE`, `EXISTING_CONTENT`, `FILE_PATH`, `REPO_ROOT`):

```markdown
**`SUGGEST`** — `on` or `off`. When `on`, run Step 1.5 (silent diagnose) and surface Q1.5 in Step 3. When `off`, skip both — identical to pre-suggestion-pass behaviour. Defaulted by the coordinator from `suggest.default` in config and the opt-in question at bootstrap start. Always `on` in audit mode.
```

- [ ] **Step 3: Update the Top-Level Flow diagram**

In the ASCII flow block, add Step 1.5 rows in both branches (create/replace and extend):

```
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │  ← NEW
│   → Step 2: announce findings (+ diagnoses)         │
│   → Step 3: targeted questions (Q1, Q1.5 if SUGGEST,│
│             then Q2-Q4)                             │
```

- [ ] **Step 4: Insert Step 1.5 (Silent Diagnose) between Step 1 and Step 2**

Insert this complete section after Step 1's substep 1g ("Compile candidate principles in memory"):

````markdown
## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip this step entirely and proceed to Step 2.

Diagnose looks for principles that the project's evidence suggests *should* exist but currently don't. Every diagnose finding must cite specific file paths or counts.

### 1.5a. Constitution diagnose categories

- **Missing principle where the stack implies one.** Example: the project has Stripe + Sentry + Auth0 integrations but no codified input-validation discipline. Evidence: list the integrations + count of unvalidated handlers.
- **Weak severity that should be stronger.** A lint rule is set to `warn` rather than `error`, a coverage threshold is logged but not gating merge, or a security check exists but doesn't fail the build. Evidence: file path + the exact "weak" config value.
- **Contradictions between an existing stated principle and observed code.** (Extend mode only.) The existing constitution claims X but the code does not-X consistently. Evidence: principle quote + file paths showing not-X.

### 1.5b. Compile candidate suggestions in memory

Each candidate must include `severity` (MUST/SHOULD/INFO with the matching evidence bar — see Hard Gates), `title`, `evidence` (file paths or counts), and `proposed_addition` (exact markdown for a new principle entry).

Drop unsupported candidates. Cap at 5; rank by severity → evidence → impact. If 0 candidates remain, Q1.5 is skipped silently.
````

- [ ] **Step 5: Modify Step 2 (Announce Findings) to mention diagnose**

In Step 2, append after the existing example announcement:

> "If `SUGGEST=on` AND Step 1.5 produced ≥1 candidate, extend the announcement with: '…and I noticed a few principles worth declaring even though they're not currently codified. I'll surface those after we confirm the observed ones.'"

- [ ] **Step 6: Insert Q1.5 between Q1 and Q2 in Step 3**

After Q1's closing fence (multi-select of observed candidate principles), insert:

````markdown
### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND Step 1.5 produced ≥1 candidate)

```
Question: "Here are some principles I'd suggest adding even though they're
not currently codified. These are opinionated — pick any you want to include:"

Multi-select. For each Step 1.5 candidate, list as:
  - [suggestion · <severity> · <evidence-summary>] <title>
    Evidence: <evidence>
    Proposed addition: <one-line summary>

Always include "None of these — keep the constitution descriptive only" as the last option.
```

Accepted suggestions carry into Step 4 with provenance markers.
````

- [ ] **Step 7: Modify Step 4's draft-synthesis to include accepted suggestions**

In Step 4's bullet list of inputs to the draft synthesis, add:

```markdown
- Accepted Q1.5 suggestions (rendered as additional Principle entries with provenance markers — see Step 6)
```

Cap the final principles list at 7 total (existing rule). If observed + accepted suggestions exceed 7, ask the user which to drop.

- [ ] **Step 8: Modify Step 6 to document the provenance marker format**

At the end of Step 6, append:

````markdown
### Provenance markers for accepted Q1.5 suggestions

Each accepted Q1.5 suggestion becomes a new Principle entry in the artifact. Place the provenance line inside the Principle's `**Evidence:**` field:

```markdown
### Principle N — <Title>

**Severity:** <MUST | SHALL | SHOULD>

**Statement:** <statement text>

**Evidence:** Not currently enforced — added via bootstrap suggestion pass (YYYY-MM-DD). <evidence summary from the Q1.5 candidate>.

**Rationale:** <rationale text>
```

Replace `YYYY-MM-DD` with today's date. The audit skill reads this marker on re-runs to ask whether the principle is still aspirational or the code has caught up.
````

- [ ] **Step 9: Update Hard Gates with diagnose budgets**

Append to Hard Gates:

```markdown
- Do NOT exceed the diagnose budget: Step 1.5 takes at most ~2 minutes and reads at most 10 additional files beyond Step 1's reads.
- Do NOT surface diagnose candidates without specific file-path or count evidence.
- Do NOT pad the Q1.5 list to fill a quota. Zero strong candidates → Q1.5 skipped silently.
- Do NOT use MUST/SHALL severity without observable harm (broken tests, security risk, bug pattern).
```

- [ ] **Step 10: Update Common Mistakes**

Append to the Common Mistakes table:

```markdown
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank and drop the rest |
| Forgetting the provenance marker | Audit needs the marker for drift detection |
| Running Step 1.5 when SUGGEST=off | Skip Step 1.5 entirely when off |
```

- [ ] **Step 11: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-constitution/SKILL.md
grep -q "Step 1.5: Silent Diagnose" "$SKILL" && echo "Step 1.5: OK" || echo "MISSING Step 1.5"
grep -q "Q1.5 — Confirm suggested additions" "$SKILL" && echo "Q1.5: OK" || echo "MISSING Q1.5"
grep -q "SUGGEST" "$SKILL" && echo "SUGGEST input: OK" || echo "MISSING SUGGEST"
grep -q "Added via bootstrap suggestion pass" "$SKILL" && echo "Provenance: OK" || echo "MISSING provenance"
grep -q "diagnose budget\|diagnose findings\|Step 1.5 takes" "$SKILL" && echo "Budget: OK" || echo "MISSING budget"
```

All five should print `OK`.

- [ ] **Step 12: Manual readability check** — read top to bottom; confirm flow, gate clarity, marker format.

- [ ] **Step 13: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-constitution/SKILL.md
git commit -m "discovering-constitution: add suggestion pass (Step 1.5 + Q1.5)"
```

---

### Task 6: Add suggestion pass to `ss-bs-discovering-glossary`

**Files:**
- Modify: `skills/project-bootstrap/ss-bs-discovering-glossary/SKILL.md`

Spec reference: Sections 6.1–6.6, 6.2 (glossary row).

- [ ] **Step 1: Read the existing skill** — `cat skills/project-bootstrap/ss-bs-discovering-glossary/SKILL.md`

- [ ] **Step 2: Add `SUGGEST` input parameter** — same content as Task 5 Step 2.

- [ ] **Step 3: Update the Top-Level Flow diagram** — insert Step 1.5 rows as in Task 5 Step 3 (the diagram pattern is identical across skills; the question numbering reflects each skill's existing Q2-Q4 range).

- [ ] **Step 4: Insert Step 1.5 with glossary-specific diagnose categories**

Insert after Step 1's substep 1f ("Compile candidate list in memory"):

````markdown
## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip this step entirely and proceed to Step 2.

Diagnose looks for vocabulary problems in the codebase that a canonical glossary would resolve. Every finding must cite specific file paths or counts.

### 1.5a. Glossary diagnose categories

- **Term inconsistencies (synonyms used as if interchangeable).** Two or more terms used for the same concept across multiple files. Evidence: each term + at least 3 file paths showing it used in equivalent contexts (e.g., `user` in 8 places, `account` in 6, both referring to the authenticated subject).
- **High-traffic acronyms with no definition.** An acronym (2-5 uppercase letters) appearing in ≥10 files with no expansion or definition in any current doc. Evidence: the acronym + occurrence count.
- **Aliases that should be unified.** A term appears with multiple syntactic variants (snake_case vs camelCase, singular vs plural in identifier names) suggesting unintended divergence. Evidence: each variant + file paths.

### 1.5b. Compile candidate suggestions in memory

Each candidate: `severity` (typically SHOULD/INFO for glossary — MUST is rare), `title`, `evidence` (term variants + paths), `proposed_addition` (the canonical term to use plus aliases to document).

Drop unsupported. Cap at 5. Rank by severity → evidence → impact. If 0, Q1.5 is skipped.
````

- [ ] **Step 5: Modify Step 2 to mention diagnose** — same content as Task 5 Step 5, adjusted: "…and I noticed a few vocabulary inconsistencies worth resolving. I'll surface those after we confirm the observed terms."

- [ ] **Step 6: Insert Q1.5 between Q1 and Q2** — same content as Task 5 Step 6, with "constitution" replaced by "glossary" in the "None of these" option.

- [ ] **Step 7: Modify Step 4's draft-synthesis to include accepted suggestions** — same as Task 5 Step 7, but accepted suggestions become additional Term entries.

- [ ] **Step 8: Modify Step 6 with provenance marker format (glossary-specific placement)**

For glossary, the provenance marker is appended as a one-line italic note at the end of the term's definition block, since glossary entries don't have a structured `Evidence:` field:

````markdown
### <Term> · `<slug>`

<Definition text, 1-3 sentences.>

**Aliases:** <comma-separated list, if any>

> _Added via bootstrap suggestion pass (YYYY-MM-DD)._ _Evidence: <evidence summary>. The team has not yet standardized on this term._
````

- [ ] **Step 9: Update Hard Gates with diagnose budgets** — same content as Task 5 Step 9.

- [ ] **Step 10: Update Common Mistakes** — same content as Task 5 Step 10.

- [ ] **Step 11: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-glossary/SKILL.md
grep -q "Step 1.5: Silent Diagnose" "$SKILL" && echo "Step 1.5: OK" || echo "MISSING Step 1.5"
grep -q "Q1.5 — Confirm suggested additions" "$SKILL" && echo "Q1.5: OK" || echo "MISSING Q1.5"
grep -q "SUGGEST" "$SKILL" && echo "SUGGEST input: OK" || echo "MISSING SUGGEST"
grep -q "Added via bootstrap suggestion pass" "$SKILL" && echo "Provenance: OK" || echo "MISSING provenance"
grep -q "diagnose budget\|Step 1.5 takes" "$SKILL" && echo "Budget: OK" || echo "MISSING budget"
```

- [ ] **Step 12: Manual readability check**

- [ ] **Step 13: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-glossary/SKILL.md
git commit -m "discovering-glossary: add suggestion pass (Step 1.5 + Q1.5)"
```

---

### Task 7: Add suggestion pass to `ss-bs-discovering-domain-model`

**Files:**
- Modify: `skills/project-bootstrap/ss-bs-discovering-domain-model/SKILL.md`

Spec reference: Sections 6.1–6.6, 6.2 (domain row).

- [ ] **Step 1: Read the existing skill** — `cat skills/project-bootstrap/ss-bs-discovering-domain-model/SKILL.md`

- [ ] **Step 2: Add `SUGGEST` input parameter** — same content as Task 5 Step 2.

- [ ] **Step 3: Update the Top-Level Flow diagram** — same pattern as Task 5 Step 3.

- [ ] **Step 4: Insert Step 1.5 with domain-specific diagnose categories**

Insert after Step 1's substep 1h ("Compile candidates in memory"):

````markdown
## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip and proceed to Step 2.

Diagnose looks for modeling smells in the codebase that documenting the domain would clarify. Every finding must cite specific file paths or counts.

### 1.5a. Domain diagnose categories

- **God entities (too many attributes / relationships).** An entity (DB table or class) with >15 attributes or >5 outgoing relationships. Evidence: schema file + attribute count.
- **Anemic models (entities with no behaviour).** An entity used only as a data bag — all logic lives in services that operate on it. Evidence: entity definition + count of service files that mutate it externally.
- **Missing aggregate roots.** Three or more entities with a clear ownership hierarchy (e.g., `Order`, `OrderItem`, `OrderEvent`) all defined as top-level entities with no aggregate-root documentation. Evidence: list the entities + the ownership signal (foreign keys, embedded relationships).
- **Undocumented state machines.** An entity has 4+ distinct status values used in code (case statements, enum values, status string comparisons) with no documented transitions. Evidence: file paths showing the status values.

### 1.5b. Compile candidate suggestions in memory

Each candidate: `severity`, `title`, `evidence` (paths + counts), `proposed_addition` (a new Entity section or a Lifecycle subsection).

Drop unsupported. Cap at 5. Rank by severity → evidence → impact. If 0, Q1.5 skipped.
````

- [ ] **Step 5: Modify Step 2** — same pattern as Task 5 Step 5, with: "…and I noticed a few domain-modeling clarifications worth documenting…"

- [ ] **Step 6: Insert Q1.5** — same content as Task 5 Step 6, "domain model" in the None-of-these option.

- [ ] **Step 7: Modify Step 4's draft-synthesis** — accepted suggestions become new Entity entries or new Lifecycle subsections within existing entities.

- [ ] **Step 8: Modify Step 6 with provenance marker (domain-specific placement)**

For domain entries, provenance is appended as a `> _Note:_` block at the end of the Entity section:

````markdown
## <Entity Name>

**Attributes:** <list>

**Lifecycle:** <states>

**Relationships:** <list>

> _Added via bootstrap suggestion pass (YYYY-MM-DD)._ _Evidence: <evidence summary>. This entity / lifecycle is observable in code but was previously undocumented._
````

- [ ] **Step 9: Update Hard Gates** — same content as Task 5 Step 9.

- [ ] **Step 10: Update Common Mistakes** — same content as Task 5 Step 10.

- [ ] **Step 11: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-domain-model/SKILL.md
grep -q "Step 1.5: Silent Diagnose" "$SKILL" && echo "Step 1.5: OK" || echo "MISSING"
grep -q "Q1.5 — Confirm suggested additions" "$SKILL" && echo "Q1.5: OK" || echo "MISSING"
grep -q "SUGGEST" "$SKILL" && echo "SUGGEST: OK" || echo "MISSING"
grep -q "Added via bootstrap suggestion pass" "$SKILL" && echo "Provenance: OK" || echo "MISSING"
grep -q "diagnose budget\|Step 1.5 takes" "$SKILL" && echo "Budget: OK" || echo "MISSING"
```

- [ ] **Step 12: Manual readability check**

- [ ] **Step 13: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-domain-model/SKILL.md
git commit -m "discovering-domain-model: add suggestion pass (Step 1.5 + Q1.5)"
```

---

### Task 8: Add suggestion pass to `ss-bs-discovering-design`

**Files:**
- Modify: `skills/project-bootstrap/ss-bs-discovering-design/SKILL.md`

Spec reference: Sections 6.1–6.6, 6.2 (design row).

- [ ] **Step 1: Read the existing skill** — `cat skills/project-bootstrap/ss-bs-discovering-design/SKILL.md`

- [ ] **Step 2: Add `SUGGEST` input parameter** — same content as Task 5 Step 2.

- [ ] **Step 3: Update the Top-Level Flow diagram** — same pattern as Task 5 Step 3.

The design skill has two paths (Import and Build per its existing flow). Step 1.5 applies only to the Build path — Import skips diagnose because we're importing a pre-existing design file. Document this explicitly in the diagram update.

- [ ] **Step 4: Insert Step 1.5 with design-specific diagnose categories**

Insert in the Build path after Step 3a's code scan:

````markdown
## Step 3a.5: Silent Diagnose (only if `SUGGEST=on` AND build path)

If `SUGGEST=off` OR import path, skip this step.

Diagnose looks for design-system gaps and ad-hoc patterns that tokenization would resolve. Every finding must cite specific file paths or counts.

### 3a.5a. Design diagnose categories

- **Hex literals scattered through CSS.** ≥10 unique hex color literals across CSS/SCSS files with no central `:root` custom-properties block defining a palette. Evidence: file paths + a sample of the literals.
- **Inconsistent spacing (no scale).** Padding/margin values across components use ≥6 distinct numeric values not on any consistent scale (4/8/12/16 or 4/8/16/24 are common). Evidence: file paths + the values.
- **Only literal colors, no semantic roles.** Code uses raw hex values like `#3B82F6` directly in components instead of semantic tokens (`var(--color-primary)`). Evidence: file paths + raw-hex occurrence count.
- **Component variants in code but absent from doc.** A component (button, input) has 4+ distinct variants in code (variant="primary"|"secondary"|...) but no design doc mentions them. Evidence: component file + variant list.

### 3a.5b. Compile candidate suggestions in memory

Each: `severity`, `title`, `evidence`, `proposed_addition` (new token block, new component-variants section). Drop unsupported. Cap 5. Rank. If 0, Q1.5 skipped.
````

- [ ] **Step 5: Modify the announce step (Build path) to mention diagnose**

In Step 3a or 3b (announce), append: "If `SUGGEST=on` AND Step 3a.5 produced ≥1 candidate, extend the announcement: '…and I noticed a few design-system gaps worth documenting — I'll surface those after we confirm the observed tokens.'"

- [ ] **Step 6: Insert Q1.5 in the targeted-questions section (Build path)**

After Q1 (or its equivalent — confirm observed tokens) and before the next question, insert the Q1.5 block. Use "design" in the None-of-these option.

- [ ] **Step 7: Modify the draft step to include accepted suggestions**

Accepted suggestions become new entries in `## Tokens — Colors`, `## Tokens — Typography`, etc., or a new `## Component variants` block.

- [ ] **Step 8: Modify the atomic-write step with provenance marker (design-specific placement)**

For design tokens, the provenance marker is a YAML/HTML comment placed immediately above the block (markdown comments don't render, but the audit script can grep for them):

````markdown
## Tokens — Colors

<!-- provenance: added via bootstrap suggestion pass 2026-05-25 -->
<!-- evidence: 18 hex literals scattered across src/components/*.css; no palette block existed -->

### Primary · `--color-primary`
- Default: `#3B82F6` (blue-500)
- Hover: `#2563EB`

### Secondary · `--color-secondary`
…
````

For Component variants, the provenance is a one-line italic note at the start of the component block (visible in rendered markdown).

- [ ] **Step 9: Update Hard Gates** — same content as Task 5 Step 9, plus a design-specific row:

```markdown
- Do NOT run diagnose in the Import path. Import means the user is bringing a pre-existing design file; diagnose would be inappropriate.
```

- [ ] **Step 10: Update Common Mistakes** — same content as Task 5 Step 10.

- [ ] **Step 11: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-design/SKILL.md
grep -q "Step 3a.5\|Silent Diagnose" "$SKILL" && echo "Step 1.5: OK" || echo "MISSING"
grep -q "Q1.5\|Confirm suggested additions" "$SKILL" && echo "Q1.5: OK" || echo "MISSING"
grep -q "SUGGEST" "$SKILL" && echo "SUGGEST: OK" || echo "MISSING"
grep -q "provenance:.*suggestion pass\|Added via bootstrap suggestion" "$SKILL" && echo "Provenance: OK" || echo "MISSING"
grep -q "diagnose budget\|takes at most ~2 minutes" "$SKILL" && echo "Budget: OK" || echo "MISSING"
```

- [ ] **Step 12: Manual readability check** — verify the import-path skip is clear; verify the Build-path diagnose-then-tokens flow reads coherently.

- [ ] **Step 13: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-design/SKILL.md
git commit -m "discovering-design: add suggestion pass (build path only)"
```

---

**Phase 3 complete.** All five existing discovery skills now support the suggestion pass when invoked with `SUGGEST=on`. The coordinator (Phase 6) wires this together so the user actually sees the opt-in.

---

## Phase 4: New Discovery Skills (Testing + Memory File)

Both new skills follow the canonical 6-step shape established in `skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md` (the prototype). Read that file before authoring either new skill — it is the structural template. Each task below provides the per-skill content (frontmatter, inputs, Step 1 substeps, Step 1.5 diagnose categories, Step 3 questions, output template, edge cases) and references the template for everything else.

### Task 9: Create `ss-bs-discovering-testing` skill

**Files:**
- Create: `skills/project-bootstrap/ss-bs-discovering-testing/SKILL.md`

Spec reference: Section 7.

- [ ] **Step 1: Read the architecture skill (the template)**

Run: `cat skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md`
Identify the canonical sections in order: frontmatter (`name`, `description`), Overview, When This Skill Runs, Hard Gates, Inputs, Top-Level Flow, Step 1 (with substeps), Step 1.5 (added in Phase 2), Step 2, Step 3 (Q1-Q5), Step 4, Step 5, Step 6, Output Template, Common Mistakes, Red Flags, Why This Skill Is Inline.

- [ ] **Step 2: Create the directory**

Run: `mkdir -p skills/project-bootstrap/ss-bs-discovering-testing`

- [ ] **Step 3: Author the SKILL.md frontmatter and Overview**

Create `skills/project-bootstrap/ss-bs-discovering-testing/SKILL.md` starting with:

```markdown
---
name: ss-bs-discovering-testing
description: Use during project bootstrap (or audit) to discover, propose, and write the project's test-strategy convention file at docs/TESTING.md (or wherever context.testing_path resolves). Scans test directories, runner configs, CI test commands, coverage tooling, and mocking patterns; optionally proposes improvements when SUGGEST=on. One of seven discovery skills loaded inline by ss-bs-bootstrapping-project; never dispatched as a subagent.
---

# Discovering Testing Conventions

## Overview

You discover, draft, and write the project's testing convention file. Output: `docs/TESTING.md` (or whatever `context.testing_path` resolves to). You are loaded inline by `ss-bs-bootstrapping-project` or `ss-bs-auditing-project`. Your job is the per-file scan, user conversation, and atomic write — the coordinator handles surrounding workflow.

**Announce at start:** "I'm using the ss-bs-discovering-testing skill to draft your project's test strategy."
```

- [ ] **Step 4: Author the When This Skill Runs and Hard Gates sections**

Append:

```markdown
## When This Skill Runs

- Bootstrap stage 3 (between architecture and glossary) when the coordinator's per-file loop reaches the testing artifact.
- Audit, when the user picks the testing stage from the scope question.

## Hard Gates

- Do NOT skip Step 1's silent scan even if you "already know" what the project uses. The scan grounds Step 2's announcement and Step 3's questions.
- Do NOT exceed the diagnose budget: Step 1.5 (when run) takes at most ~2 minutes and reads at most 10 additional files beyond what Step 1 read.
- Do NOT surface diagnose candidates without specific file-path or count evidence.
- Do NOT pad Q1.5 to fill a quota. Zero strong candidates → Q1.5 skipped silently.
- Do NOT run Step 1.5 when SUGGEST=off; skip it entirely.
- Do NOT write the artifact until the user has approved the draft (or accepted it as-is after the 3-iteration tweak cap).
- ALWAYS use the harness's interactive question tool for Q1, Q1.5, Q2, Q3, Q4 (and Q5 in extend mode). Do not fall back to a plain-text prompt.
- ALWAYS write atomically: `<path>.tmp` then `mv`.
```

- [ ] **Step 5: Author the Inputs and Top-Level Flow sections**

Append:

````markdown
## Inputs (from coordinator)

- `REPO_ROOT` — absolute path to repo root
- `MODE` — `create | extend | replace | audit`
- `EXISTING_CONTENT` — (extend / replace / audit) verbatim current `docs/TESTING.md` content
- `FILE_PATH` — target path (typically `docs/TESTING.md`)
- `SUGGEST` — `on` or `off`. When `on`, run Step 1.5 and surface Q1.5. Always `on` in audit mode.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan (test dirs, runner,    │
│             CI commands, coverage, mocking, fixtures)│
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │
│   → Step 2: announce findings (+ diagnoses)         │
│   → Step 3: targeted questions (Q1, Q1.5 if SUGGEST,│
│             Q2 commands, Q3 mocking, Q4 fixtures)   │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1 + Step 1.5 + read EXISTING_CONTENT       │
│   → Step 2: announce findings + gaps                │
│   → Step 3: questions on gaps + Q1.5                │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine                                  │
│   → Step 6: atomic write of merged content          │
├─────────────────────────────────────────────────────┤
│ NEW-PROJECT MODE (scan found near-empty)            │
│   → Skip Step 1.5 (no code to diagnose against)     │
│   → Step 2: announce "no tests yet"                 │
│   → Step 3: starter-strategy Q&A (see Step 3.NP)    │
│   → Step 4-6: synthesize starter TESTING.md         │
└─────────────────────────────────────────────────────┘
```
````

- [ ] **Step 6: Author Step 1 (silent scan substeps)**

Append:

````markdown
## Step 1: Code Scan (Silent — No User Narration Yet)

Read what exists. Don't narrate to the user — announce once in Step 2.

### 1a. Test directories

Look for: `tests/`, `test/`, `__tests__/`, `spec/`, `e2e/`, `integration/`, language-specific (`*_test.go` files at any level for Go).

### 1b. Test runner config

Read whichever exist:
- **JavaScript/TypeScript:** `jest.config.*`, `vitest.config.*`, `playwright.config.*`, `karma.conf.*`, `mocharc.*`
- **Python:** `pytest.ini`, `pyproject.toml [tool.pytest]`, `setup.cfg [tool:pytest]`, `conftest.py`
- **Ruby:** `.rspec`, `spec_helper.rb`
- **Go:** test deps in `go.mod` (testify, gomock)
- **Rust:** dev-dependencies in `Cargo.toml`
- **JVM:** `build.gradle` test config, `pom.xml` surefire/failsafe config

Extract: framework name, config path, parallelism settings.

### 1c. Test naming patterns

Sample 5-10 test files from one test dir. Note conventions: `*.test.ts` vs `*.spec.ts`, `test_*.py` vs `*_test.py`, `*Spec.kt` vs `*Test.kt`.

### 1d. CI test commands

Read CI workflow files (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `azure-pipelines.yml`, `Jenkinsfile`, `buildkite/*.yml`). Extract: the command(s) invoked to run tests, the matrix (parallel shards, OS, language version).

### 1e. Coverage tooling

Look for: `c8`, `nyc`, `istanbul`, `coverage.py`, `simplecov`, `tarpaulin`, `cargo-llvm-cov` in deps + their configs (`.nycrc`, `coveragerc`, `simplecov.rb`, etc.).

### 1f. Coverage thresholds

Look in:
- Coverage tool config (`.nycrc statements`, `coverage.report fail_under`)
- CI workflow gates (a `coverage:` job that uses a threshold flag)

Note whether the threshold is enforced (fails the build) or informational (warns only).

### 1g. Mocking framework signal

Grep for imports:
- `jest.mock`, `vi.mock`, `sinon`, `nock`
- `unittest.mock`, `pytest-mock`, `responses`, `vcrpy`
- `mockall`, `mockito` (Rust), `gomock`, `testify/mock`

Note dominant style: heavy-mocking (jest.mock at file top), targeted-mocking (sinon stubs in setup), no-mocking (real DB / containers).

### 1h. Fixture / factory patterns

Look for: `factories/`, `fixtures/` directories; `factory_bot`, `factoryboy`, `faker`, `fishery`, `cypress/fixtures/`. Sample one factory file to extract the pattern.

### 1i. Test categorization

Note structural signals: `unit/` vs `integration/` vs `e2e/` directories, or tag/marker conventions (`@pytest.mark.integration`, `describe.skip(...)`, `if (process.env.E2E)`).

### 1j. Mode-specific reads

- **`create` / `replace`:** ignore `EXISTING_CONTENT`. Build candidates from scratch.
- **`extend`:** read `EXISTING_CONTENT`. Identify which sections of the canonical template are missing or outdated.
- **`audit`:** see Step 1.6 (added in Phase 7) for drift checks.

### 1k. Compile candidate sections in memory

Hold:
- Test categories observed + a one-line description each
- Runner + framework + config path
- Coverage tooling + current threshold + gating status
- Mocking style (one of: heavy / targeted / no-mocking; plus a one-paragraph rationale based on what you saw)
- Fixture/factory location + pattern
- Naming convention(s)

If the scan found <2 tests total, set a `new_project_mode = true` flag for Step 2.
````

- [ ] **Step 7: Author Step 1.5 (diagnose) and Step 2 (announce)**

Append:

````markdown
## Step 1.5: Silent Diagnose (only if `SUGGEST=on` AND not new-project mode)

If `SUGGEST=off` OR `new_project_mode = true`, skip this step.

Diagnose looks for test-strategy gaps. Every finding must cite specific file paths or counts.

### 1.5a. Testing diagnose categories

- **Missing test categories.** Only unit tests exist; no integration coverage of the API/repo/service layer. Evidence: list the existing categories + which architectural components from ARCHITECTURE.md (if it exists) are uncovered.
- **Large untested critical files.** Files in `src/` >200 LOC with no matching test file. Evidence: 3-5 specific paths.
- **Heavy mocking smell.** DB or other core dependency mocked in >80% of tests where it could be exercised against a real instance. Evidence: mock-usage count + total test count.
- **CI gate gap.** Tests run in CI but no coverage gate, OR a coverage gate exists as `warn` not `fail`. Evidence: CI file path + the relevant config block.
- **Naming inconsistency.** Both `*.test.ts` and `*.spec.ts` (or analogous splits) used in the same project. Evidence: counts of each.

### 1.5b. Compile candidate suggestions in memory

Each: `severity` (SHOULD typical for testing; MUST when a known-broken or known-flaky case exists; INFO for nice-to-haves), `title`, `evidence`, `proposed_addition` (text for the relevant TESTING.md section).

Drop unsupported. Cap 5. Rank by severity → evidence → impact. If 0, Q1.5 skipped.

## Step 2: Announce Findings

One short message (3-6 sentences). State what you scanned and the headline finding.

**Normal mode example:**
> "Here's what I picked up from the codebase: Vitest as the runner (vitest.config.ts), tests under `tests/{unit,integration}/`, naming `*.test.ts`, coverage via v8 (c8) with threshold gate at 80% in CI. Mocking is targeted via vi.mock (used in 14 of 87 tests). Fixtures live in `tests/fixtures/` as plain JSON. I'll ask a few targeted questions, then show you a draft."

**With SUGGEST=on and diagnose hits:**
> "…and I noticed a few testing-strategy gaps worth considering — I'll surface those after we confirm the observed setup."

**New-project mode (scan found <2 tests):**
> "I didn't find a test suite — looks like this is a new or pre-test project. I can still draft a starter TESTING.md, but I'll need to ask you a few decisions about the strategy you want to set rather than scan for it. Want to continue?"
````

- [ ] **Step 8: Author Step 3 (targeted questions) including the new-project mode Q&A**

Append:

````markdown
## Step 3: Targeted Questions

Ask one question per turn. Skip a question if the scan already answered it.

### Q1 — Confirm observed test setup (multi-select)

```
Question: "Here's the testing setup I observed. Which should land in TESTING.md as-is?"

Multi-select. List the scan candidates one-line each:
  - [observed] Test categories: unit, integration
  - [observed] Runner: Vitest (vitest.config.ts)
  - [observed] Coverage: v8 with 80% gate in CI
  - [observed] Mocking: targeted via vi.mock (14 of 87 tests)
  - [observed] Fixtures: tests/fixtures/ JSON files
  - "All of the above (Recommended)"
```

### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND ≥1 diagnose candidate)

Same shape as the Q1.5 block in `ss-bs-discovering-architecture`. Use "testing" in the "None of these — keep TESTING.md descriptive only" option.

### Q2 — Canonical test commands (multi-select from CI extraction)

```
Question: "From CI, I extracted these test commands. Which should be documented as canonical in TESTING.md?"

Multi-select with at least:
  - "Run all: <CI's primary test command>"
  - "Run filtered: <CI's pattern-filtered variant if any>"
  - "Run with coverage: <CI's coverage variant if any>"
  - Free-form fallback for "I'll specify"
```

### Q3 — Mocking philosophy (multi-choice)

```
Question: "How does this project approach mocking? (One sentence summary will land in TESTING.md.)"

Single-select:
  - "Mock as little as possible — real DB, real network (via VCR/wiremock), in-process fakes only for time/randomness" (Recommended for backend services with substantial integration coverage)
  - "Mock externals only — HTTP, queues, third-party SDKs. Real DB. Real internal modules."
  - "Mock liberally — fast unit tests over isolated functions; separate integration suite covers wiring"
  - Free-form fallback
```

### Q4 — Fixture / factory location (free-form, scan default)

```
Question: "Where do test fixtures and factories live? (Scan found: tests/fixtures/. Edit if different.)"

Free-form text, pre-filled with the scan's default.
```

### Q5 — (extend mode only) Resolve conflicts

For each conflict between EXISTING_CONTENT and the scan (e.g., file says "Jest" but scan shows Vitest):

```
Question: "Your existing TESTING.md says '<X>', but the code shows '<Y>'. What's right?"

Options:
  - "The doc is right — the code changed but the doc is correct intent"
  - "The code is right — update the doc"
  - "Both — they describe different cases; I'll clarify"
```

### Step 3.NP — New-Project Starter Q&A (only if `new_project_mode = true`)

Skip Q1, Q1.5, Q5. Ask:

```
NP-Q1: "Which test categories will this project have?"
  Multi-select: unit / integration / e2e / property-based / load
  Recommended: unit + integration for backend; unit + e2e for frontend.

NP-Q2: "Which runner / framework?"
  Multi-choice from the language ecosystem:
    JS/TS: Vitest (Recommended) / Jest / Mocha / Playwright (for e2e)
    Python: pytest (Recommended) / unittest
    Go: standard library testing (Recommended) / Ginkgo
    Rust: cargo test (Recommended) / nextest
    JVM: JUnit 5 (Recommended) / TestNG / Spock

NP-Q3: "Coverage target?"
  Multi-choice: none / 60% / 70% / 80% (Recommended) / 90% / I'll set later

NP-Q4: "Mocking philosophy?" (same as Q3 above)

NP-Q5: "Fixture / factory pattern?"
  Multi-choice: factory functions (Recommended) / static fixture files / library-based (factory_bot, factoryboy)
```

Skip free-form questions if defaults from Q1-Q5 suffice; only ask each NP-Q if the user has signal to provide.
````

- [ ] **Step 9: Author Step 4-6 and the Output Template**

Append:

````markdown
## Step 4: Draft & Show to User

Synthesize the draft using:
- Q1 confirmations (observed setup)
- Q1.5 accepted suggestions (rendered with provenance markers — see Step 6)
- Q2 canonical commands
- Q3 mocking philosophy paragraph
- Q4 fixture location
- (extend mode) Q5 conflict resolutions
- (new-project mode) NP-Q1 through NP-Q5

Use the Output Template below. Show the full draft to the user, then ask:

```
Question: "How does this look?"
Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip TESTING.md"
```

## Step 5: Refine (Tweak Loop, cap 3)

**On Tweak:** capture user's notes; apply; re-show; re-ask Step 4. Cap at 3 iterations. After 3:

> "We've done three rounds and the draft still isn't matching what you want. Want to:
> (a) keep the current draft anyway,
> (b) skip TESTING.md for now, or
> (c) supply the file yourself — you write the markdown, I'll save it?"

**On Start over:** restart Step 3 from Q1 (scan findings carry over; user answers reset).

**On Abort:** report `skipped (declined mid-skill)` to the coordinator and exit.

## Step 6: Atomic Write & Report Outcome

```bash
cat > "$FILE_PATH.tmp" <<'EOF'
<draft content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

For **extend** mode: merge `EXISTING_CONTENT` + new sections / refinements into a single document, then write atomically.

### Provenance markers for accepted Q1.5 suggestions

Each accepted Q1.5 suggestion becomes a new entry in the relevant TESTING.md section (a new category, a stricter coverage target, a stricter mocking rule, etc.). Append a provenance line at the end of the section as a one-line italic note:

```markdown
> _Added via bootstrap suggestion pass (YYYY-MM-DD)._ _Evidence: <evidence summary>. Not currently enforced — declared here as an aspirational test-strategy improvement._
```

## Output Template

```markdown
# Testing

## Test categories

- **Unit** — `<command>` — `<path pattern>`
- **Integration** — `<command>` — `<path pattern>`
- (etc.)

## Runner & framework

- **Framework:** <name + version>
- **Config:** `<path>`
- **Run all:** `<command>`
- **Run filtered:** `<command pattern>`

## Coverage

- **Tool:** <name>
- **Current:** <%> (as of YYYY-MM-DD)
- **Target:** <%>
- **CI gate:** <yes / no — fails build at <threshold>%>

## Mocking philosophy

<One-paragraph rule from Q3.>

## Fixtures & factories

- **Location:** `<path>`
- **Pattern:** <factory function | fixture file | library-based>

## Conventions

- **File naming:** `<pattern>`
- **One assertion per test / multiple OK:** <pick one>
- **Setup/teardown:** <pattern>
- (etc.)
```

Report outcome to coordinator:
- `created` — file written via the normal path (or "created via new-project starter" when new-project mode)
- `extended` — merged content written
- `replaced` — full draft written over previous content
- `skipped (declined mid-skill)` — user bailed out
````

- [ ] **Step 10: Author Common Mistakes, Red Flags, Why Inline**

Append:

```markdown
## Common Mistakes

| Mistake | Fix |
|---|---|
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest |
| Forgetting the provenance marker | Audit needs the marker for drift detection |
| Running diagnose in new-project mode | Skip diagnose when scan found <2 tests; use NP-Q&A instead |
| Skipping the mocking-philosophy question because "the scan tells me" | The scan tells you what's *current*; Q3 asks what's *intended*. Ask. |
| Writing run commands not actually present in CI | Q2 multi-selects from CI extraction; don't invent. If CI commands look wrong, ask the user. |

## Red Flags

- About to skip the silent scan because "I know this project uses Jest" → STOP; the scan grounds Step 2's claims
- About to run Step 1.5 when SUGGEST=off → STOP; skip entirely
- About to write the file before user approval → STOP; Step 4 approval is mandatory
- About to fall back to a plain-text prompt for any question → STOP; use the harness's question tool

## Why This Skill Is Inline (Not a Subagent)

The per-file conversation is interactive: scan → announce → ask → draft → refine. A subagent would break the back-and-forth — the user has signal the agent needs (preferences, intent, context not visible from code) that only flows through live conversation. Inline loading preserves the interactive flow inside the coordinator's turn.
```

- [ ] **Step 11: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-testing/SKILL.md
test -f "$SKILL" && echo "File: OK" || echo "MISSING FILE"
grep -q "^name: ss-bs-discovering-testing" "$SKILL" && echo "Frontmatter name: OK" || echo "MISSING"
grep -q "^description: " "$SKILL" && echo "Frontmatter description: OK" || echo "MISSING"
for s in "## Overview" "## Hard Gates" "## Inputs" "## Top-Level Flow" "## Step 1" "## Step 1.5" "## Step 2" "## Step 3" "## Step 4" "## Step 5" "## Step 6" "## Output Template" "## Common Mistakes" "## Red Flags"; do
  grep -qF "$s" "$SKILL" && echo "$s: OK" || echo "MISSING $s"
done
grep -q "new_project_mode\|new-project mode" "$SKILL" && echo "New-project mode: OK" || echo "MISSING new-project mode"
```

All lines should print `: OK`.

- [ ] **Step 12: Manual readability check** — read top to bottom; confirm 6-step flow is clear and matches the architecture template's shape.

- [ ] **Step 13: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-testing/
git commit -m "Add ss-bs-discovering-testing skill (docs/TESTING.md)"
```

---

### Task 10: Create `ss-bs-discovering-memory-file` skill

**Files:**
- Create: `skills/project-bootstrap/ss-bs-discovering-memory-file/SKILL.md`

Spec reference: Section 8.

- [ ] **Step 1: Read both the architecture skill (template) and the existing `ss-sdd-maintaining-memory-file`**

Run:
```bash
cat skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md
cat skills/spec-driven-development/ss-sdd-maintaining-memory-file/SKILL.md
```

The architecture skill is the structural template. The maintaining-memory-file skill is the closest existing peer — it owns the same artifact incrementally; your skill owns the same artifact from-scratch / full-refresh. Read both to understand the boundaries and the canonical 4-section structure (Project conventions / Domain vocabulary / NEVER-MUST / Pointers).

- [ ] **Step 2: Create the directory**

Run: `mkdir -p skills/project-bootstrap/ss-bs-discovering-memory-file`

- [ ] **Step 3: Author the SKILL.md frontmatter and Overview**

Create `skills/project-bootstrap/ss-bs-discovering-memory-file/SKILL.md`:

```markdown
---
name: ss-bs-discovering-memory-file
description: Use during project bootstrap (or audit) to discover, propose, and write the project's agent memory file (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md). Runs last in the bootstrap sequence so it can synthesize pointers to the other six artifacts (constitution, architecture, testing, glossary, domain, design) rather than duplicate them. One of seven discovery skills loaded inline by ss-bs-bootstrapping-project; never dispatched as a subagent. Distinct from ss-sdd-maintaining-memory-file, which updates the same file incrementally during SDD feature runs.
---

# Discovering the Agent Memory File

## Overview

You discover, draft, and write the project's agent memory file — `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, or `.agents.md` (the user picks if multiple are possible). Output: a single file, configured path written back to `.sublime-skills/config.yml`'s `memory_file.path`. You are loaded inline by `ss-bs-bootstrapping-project` (last stage) or `ss-bs-auditing-project`.

You synthesize pointers to the other six artifacts (constitution, architecture, testing, glossary, domain, design) plus a small set of canonical project conventions, vocabulary highlights, NEVER/MUST rules (seeded from the constitution), and run commands extracted from the project's task runner.

**Announce at start:** "I'm using the ss-bs-discovering-memory-file skill to draft your project's agent memory file."
```

- [ ] **Step 4: Author When This Skill Runs, Hard Gates, Inputs**

Append:

````markdown
## When This Skill Runs

- Bootstrap stage 7 (last) when the per-file loop reaches the memory-file artifact. Runs after constitution, architecture, testing, glossary, domain, design have been settled (created/extended/replaced/skipped).
- Audit, when the user picks the memory-file stage from the scope question.

## Hard Gates

- Do NOT run before the other 6 discovery stages have completed in this bootstrap run. The skill synthesizes pointers; running early means pointers reference files that may not exist yet.
- Do NOT maintain multiple memory files. Bootstrap maintains exactly one. If the project has CLAUDE.md + AGENTS.md side-by-side, ask which is canonical and leave the others alone (Step 0).
- Do NOT exceed the `memory_file.character_limit` from config (default 40000). If the synthesized draft is >90% of the limit, ask the user which sections to trim.
- Do NOT duplicate content from the other artifacts — link instead. The Pointers section is the linkdump; the Domain vocabulary section should point at GLOSSARY.md after 3-5 sample terms.
- Do NOT exceed the diagnose budget: Step 1.5 takes at most ~2 minutes and reads at most 10 additional files.
- Do NOT run Step 1.5 when SUGGEST=off.

## Inputs (from coordinator)

- `REPO_ROOT` — absolute path to repo root
- `MODE` — `create | extend | replace | audit`
- `EXISTING_CONTENT` — verbatim current memory-file content (when one exists)
- `FILE_PATH` — target path (resolved by Step 0; passed in by coordinator if `memory_file.path` is set, otherwise null and Step 0 detects)
- `SUGGEST` — `on` or `off`
````

- [ ] **Step 5: Author Top-Level Flow with Step 0**

Append:

````markdown
## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 0: detect target file (new substep)        │
│   → Step 1: silent scan (read 6 other artifacts +   │
│             run commands + README)                  │
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │
│   → Step 2: announce findings                       │
│   → Step 3: Q1 (sections), Q1.5 (suggestions),      │
│             Q2 (pointers), Q3 (free-form conv),     │
│             Q4 (NEVER/MUST)                         │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine (cap 3)                          │
│   → Step 6: atomic write + write path back to       │
│             memory_file.path in config              │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Same as above but Step 1 reads EXISTING_CONTENT │
└─────────────────────────────────────────────────────┘
```

## Step 0: Detect Target File

Determine which memory file to maintain.

### 0a. Check the config

If `memory_file.path` in `.sublime-skills/config.yml` is set to a path, use it. Skip 0b-0d.

### 0b. Auto-detect existing files

If `memory_file.path` is null, look for these in repo root, in this order:
- `CLAUDE.md`
- `AGENTS.md`
- `GEMINI.md`
- `.agents.md`

### 0c. Multiple exist — ask which is canonical

If 2+ exist, ask:

```
Question: "I see multiple agent memory files: <list>. Which is canonical for bootstrap to maintain? (The others will be left alone — bootstrap only maintains one.)"

Multi-choice: list each file found, "I maintain them manually — skip" as bailout.
```

Record the choice. The non-chosen files are untouched.

### 0d. None exist — ask which to create

If 0 exist, ask:

```
Question: "Which agent memory file should I create?"

Multi-choice:
  - "CLAUDE.md (Claude Code's preferred name)" (Recommended)
  - "AGENTS.md (vendor-neutral)"
  - "GEMINI.md (Gemini CLI's preferred name)"
  - ".agents.md (alternative neutral name)"
```

### 0e. Set FILE_PATH and write to config

Set `FILE_PATH = <chosen path>`. After Step 6, write this back to `.sublime-skills/config.yml`'s `memory_file.path` so subsequent SDD runs don't re-detect. Use the existing config-edit pattern from `ss-bs-bootstrapping-project` (targeted Edit, not full regen).
````

- [ ] **Step 6: Author Step 1 (silent scan)**

Append:

````markdown
## Step 1: Code Scan (Silent — No User Narration Yet)

### 1a. Read the other 6 artifacts

For each of `constitution_path`, `architecture_path`, `testing_path`, `glossary_path`, `domain_path`, `design_path` in `.sublime-skills/config.yml`: if not null AND file exists, read it. Hold contents in memory.

These are the source material for the Pointers section (every existing artifact becomes a pointer) and for seeding NEVER/MUST (constitution's MUST principles) and for the vocabulary highlights (3-5 most-prominent glossary terms).

### 1b. Run commands

Read whichever task-runner files exist:
- `package.json` (`scripts.{test,lint,build,dev,start}`)
- `Makefile` (target lines)
- `justfile`, `Taskfile.yml`
- `pyproject.toml [tool.poetry.scripts]` or `[project.scripts]`
- `Cargo.toml` `[[bin]]` declarations + common cargo aliases

Extract: test command, lint command, build command, run/dev command. If multiple competing commands exist for one role (e.g. `test` and `test:ci`), pick the one CI uses (cross-reference with CI workflow files).

### 1c. Existing memory file (extend mode only)

Read `EXISTING_CONTENT`. Note: which canonical sections exist (Project conventions / Domain vocabulary / NEVER-MUST / Pointers / Commands); which are missing; whether anything has gone stale relative to the just-written artifacts.

### 1d. Repo root README

Read `README.md`'s first heading + first paragraph. Extract: project name (heading) and 1-sentence description (first paragraph). Used for the memory file's top-of-document one-liner.

### 1e. Compile candidate content in memory

Hold:
- Project name + one-liner (from README)
- Pointers: list of `[Title](path) — one-line summary` for each existing artifact
- Conventions seed: 3-7 stable patterns derivable from constitution + architecture (test framework, error-handling style, logging convention, etc.)
- Vocabulary seed: 3-5 terms from GLOSSARY.md (most-frequent in code)
- NEVER/MUST seed: each MUST/SHALL/NEVER principle from constitution
- Commands: test/lint/build/run/dev
````

- [ ] **Step 7: Author Step 1.5, Step 2, Step 3**

Append:

````markdown
## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip and proceed to Step 2.

Diagnose looks for memory-file problems specific to the agent-memory role. Every finding must cite specific file paths or counts.

### 1.5a. Memory-file diagnose categories

- **Missing pointers to artifacts that exist.** EXISTING_CONTENT has no pointer to an artifact that's present in the config and on disk. Evidence: artifact path + memory-file content snippet.
- **Stale entries (contradicting current code).** A convention line says "use Pytest" but `package.json` shows Vitest. Evidence: memory-file quote + code path.
- **Items better as hooks than as memory.** A rule like "always run tests before commit" is fragile as a memory line; suggest a pre-commit hook + remove from memory. Evidence: the memory-file line.
- **Rules creeping in that belong in the constitution.** A "MUST" in memory has stronger home in `docs/constitution.md`. Evidence: the memory-file line + whether constitution already covers it.

### 1.5b. Compile candidate suggestions

Each: `severity`, `title`, `evidence`, `proposed_addition` OR `proposed_removal` (memory-file diagnose can suggest *removing* stale lines, not only adding).

Drop unsupported. Cap 5. If 0, Q1.5 skipped.

## Step 2: Announce Findings

One short message (3-6 sentences). Examples:

> "Here's what I picked up: project is 'Sublime-Skills, a skill family for agent harnesses' (from README). Other artifacts on disk: constitution, architecture, testing, glossary, domain — design was skipped this run. CI uses `pnpm test` and `pnpm lint`. I'll synthesize the memory file with pointers to those + a starter convention list + the constitution's MUSTs as NEVER/MUST. A few questions, then a draft."

With SUGGEST=on diagnose hits, extend: "…and I found a few stale entries in the existing memory file worth resolving."

## Step 3: Targeted Questions

### Q1 — Which canonical sections to include (multi-select)

```
Question: "Which sections should the memory file have?"
Multi-select (all recommended for non-trivial projects):
  - "Project conventions" (stable patterns: framework, error handling, logging)
  - "Domain vocabulary" (3-5 terms + pointer to GLOSSARY.md)
  - "NEVER / MUST" (hard rules; seeded from constitution)
  - "Pointers" (linkdump to docs/{constitution, ARCHITECTURE, …})
  - "Commands" (test, lint, build, run, dev)
  - "All of the above (Recommended)"
```

### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND ≥1 diagnose candidate)

Same shape as the Q1.5 block in `ss-bs-discovering-architecture`. Use "memory file" in the None-of-these option. Note: for memory file, suggestions can also be *removals* (stale lines to delete) — render those as `[suggestion · removal · …]`.

### Q2 — Confirm auto-extracted pointers (multi-select)

```
Question: "Which artifacts should be pointed to from the memory file?"
Multi-select, pre-checked for all that exist:
  - "docs/constitution.md"
  - "docs/ARCHITECTURE.md"
  - "docs/TESTING.md"
  - "docs/GLOSSARY.md"
  - "docs/DOMAIN.md"
  - "docs/DESIGN.md"
  - "README.md"
  - "docs/adr/"
  - "docs/specs/"
  - Free-form additions
```

### Q3 — Free-form additions for "project conventions"

```
Question: "Anything the agent should know about working in this project that isn't visible from the other artifacts? Examples: which tests are flaky, how to handle DB migrations locally, oncall expectations."
Free-form. Skip if nothing to add.
```

### Q4 — Confirm NEVER/MUST list

```
Question: "Here are the NEVER/MUST rules I'd seed from the constitution. Confirm or prune:"
Multi-select pre-checked. List each MUST/SHALL/NEVER principle. Allow free-form additions.
```
````

- [ ] **Step 8: Author Step 4-6 with the config-writeback substep**

Append:

````markdown
## Step 4: Draft & Show to User

Synthesize using:
- Project name + one-liner (from Step 1)
- Q1 sections chosen
- Q1.5 accepted suggestions (additions and removals — see Step 6 for provenance handling)
- Q2 confirmed pointers
- Q3 free-form additions
- Q4 confirmed NEVER/MUST list
- Step 1 commands (auto-included if "Commands" section was chosen in Q1)

Use the Output Template (below). Show the full draft. If draft length is >90% of `memory_file.character_limit`, surface a warning and ask which sections to trim. Then:

```
Question: "How does this look?"
Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip the memory file"
```

## Step 5: Refine (Tweak Loop, cap 3)

Same shape as the testing skill's Step 5.

## Step 6: Atomic Write & Config Writeback

```bash
cat > "$FILE_PATH.tmp" <<'EOF'
<draft content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

### Provenance markers for accepted Q1.5 additions

Each accepted Q1.5 addition becomes a regular line in the relevant section. Append a HTML comment on the line after, since memory files prefer minimal visual noise:

```markdown
- <new line content>
<!-- provenance: bootstrap suggestion 2026-05-25; evidence: <summary> -->
```

For *removals* accepted in Q1.5, simply omit the line from the synthesized draft — no marker needed.

### Config writeback (Step 0e follow-through)

If Step 0e identified a new path (i.e. `memory_file.path` in config was null at start), edit `.sublime-skills/config.yml` to set `memory_file.path: <chosen path>`. Use a targeted Edit (find the existing `path: null` line under `memory_file:` and replace), not a full regen.

After the edit, run `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh"` to confirm the edit didn't break the config. Halt and surface if validation fails.

## Output Template

```markdown
# <Project Name>

<One-sentence description from README.>

## Project conventions

- <Convention 1>
- <Convention 2>
- (3-7 entries total)

## Domain vocabulary

(See [GLOSSARY.md](docs/GLOSSARY.md) for the full vocabulary.)

Key terms:
- **<Term>** — <brief gloss>
- (3-5 entries)

## NEVER / MUST

- NEVER <hard rule>
- MUST <hard rule>
- (each rule traceable to a constitution principle or an explicit Q4 free-form addition)

## Pointers

- [Constitution](docs/constitution.md) — principles
- [Architecture](docs/ARCHITECTURE.md) — system shape
- [Testing](docs/TESTING.md) — test strategy
- [Glossary](docs/GLOSSARY.md) — vocabulary
- [Domain Model](docs/DOMAIN.md) — entities
- [Design System](docs/DESIGN.md) — visual tokens
- [ADRs](docs/adr/) — architectural decisions
- [Specs](docs/specs/) — per-feature SDD artifacts

## Commands

```bash
<test command>
<lint command>
<build command>
<run / dev command>
```
```

Report outcome to coordinator: `created` / `extended` / `replaced` / `skipped (declined mid-skill)`. Also report the resolved `FILE_PATH` so the coordinator's report mentions it.
````

- [ ] **Step 9: Author Common Mistakes, Red Flags, Why Inline**

Append:

```markdown
## Common Mistakes

| Mistake | Fix |
|---|---|
| Running before the other 6 artifacts are settled | Memory file is the LAST stage; coordinator orders this. If you're being invoked early, ask the coordinator why. |
| Maintaining multiple memory files | Bootstrap maintains one. Ask which is canonical; leave the others alone. |
| Duplicating content from the other artifacts | Link, don't duplicate. Domain vocabulary should be 3-5 terms + pointer, not the full glossary. |
| Forgetting the config writeback in Step 6 | If you set FILE_PATH via Step 0d (none existed), `memory_file.path` MUST be written back to config. |
| Exceeding character_limit | Warn at 90%; refuse to write past 100%. Trim with the user first. |
| Surfacing diagnose candidates without evidence | Drop them; only evidence-cited candidates pass the gate. |

## Red Flags

- About to write the file before the other 6 stages are done → STOP; check coordinator ordering
- About to skip the config writeback → STOP; subsequent SDD runs will mis-detect
- About to maintain a second memory file in this run → STOP; bootstrap is one-per-project
- About to copy the full glossary into the memory file → STOP; link instead
- About to run Step 1.5 when SUGGEST=off → STOP; skip

## Why This Skill Is Inline (Not a Subagent)

Like the other discovery skills, the per-file conversation needs back-and-forth. Additionally, this skill reads the just-written content of the other 6 artifacts — it must run in the same coordinator context where those writes happened, with the same file-system view.
```

- [ ] **Step 10: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-memory-file/SKILL.md
test -f "$SKILL" && echo "File: OK" || echo "MISSING FILE"
grep -q "^name: ss-bs-discovering-memory-file" "$SKILL" && echo "Frontmatter name: OK" || echo "MISSING"
for s in "## Overview" "## When This Skill Runs" "## Hard Gates" "## Inputs" "## Top-Level Flow" "## Step 0" "## Step 1" "## Step 1.5" "## Step 2" "## Step 3" "## Step 4" "## Step 5" "## Step 6" "## Output Template" "## Common Mistakes" "## Red Flags"; do
  grep -qF "$s" "$SKILL" && echo "$s: OK" || echo "MISSING $s"
done
grep -q "Config writeback\|memory_file.path" "$SKILL" && echo "Config writeback: OK" || echo "MISSING writeback"
grep -q "character_limit" "$SKILL" && echo "Character budget: OK" || echo "MISSING budget"
```

All lines should print `: OK`.

- [ ] **Step 11: Manual readability check** — Step 0 (detect) is the unusual one; verify it's clearly the first thing the skill does, before any reads.

- [ ] **Step 12: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-memory-file/
git commit -m "Add ss-bs-discovering-memory-file skill"
```

---

**Phase 4 complete.** Two new discovery skills exist and can be invoked. Coordinator wiring (Phase 6) is still needed before they're reachable from a normal bootstrap run.

---

## Phase 5: Coherence Check Framework Script

### Task 11: Create `framework/coherence-check.sh`

**Files:**
- Create: `skills/spec-driven-development/framework/coherence-check.sh`

Spec reference: Section 10 (Tier 1 checks).

The coherence checker is a single reusable framework script invoked by both bootstrap (end-of-run) and audit (start-of-run). It reads `.sublime-skills/config.yml` to learn the artifact paths, then runs the Tier 1 structural checks documented in spec Section 10.1.

- [ ] **Step 1: Write the script skeleton with usage and exit codes**

Create `skills/spec-driven-development/framework/coherence-check.sh`:

```bash
#!/usr/bin/env bash
# Cross-artifact coherence check across the 7 bootstrap artifacts.
#
# Reads .sublime-skills/config.yml to learn each artifact path, then runs
# Tier 1 structural / pointer checks per docs/bootstrap-improvements-2026-05-25.md
# Section 10.1. Findings are written to stdout in a canonical format that
# the coordinator surfaces verbatim to the user.
#
# Usage:
#   coherence-check.sh [config-path]
#
# Default config-path: <repo-root>/.sublime-skills/config.yml
#
# Exit codes:
#   0 — no findings (artifact set is internally consistent)
#   1 — findings present (at least one CRITICAL, WARNING, or INFO)
#   2 — config file not found
#   3 — usage error
#   4 — internal error (e.g. python3 missing and YAML unparseable)
#
# Output format (stdout): one finding per block, blank line between blocks:
#
#   [CRITICAL] short title
#     context: <where the issue was observed, file paths, etc.>
#     fix: <one-line remediation hint>
#
# Final summary line on stdout: "coherence-check: N findings (X CRITICAL, Y WARNING, Z INFO)"
# (or "coherence-check: PASS (0 findings)" when clean).

set -u

usage() {
  echo "Usage: $0 [config-path]" >&2
  exit 3
}

if [ $# -gt 1 ]; then
  usage
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG="${1:-$REPO_ROOT/.sublime-skills/config.yml}"

if [ ! -f "$CONFIG" ]; then
  echo "coherence-check: config not found at $CONFIG" >&2
  exit 2
fi

# Require python3 for YAML parsing — coherence checks need accurate parsing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "coherence-check: requires python3 (for YAML parsing)" >&2
  exit 4
fi

# Run the checks in a python helper for maintainability.
python3 - "$CONFIG" "$REPO_ROOT" <<'PYEOF'
import sys, os, re, yaml, glob

config_path, repo_root = sys.argv[1], sys.argv[2]

try:
    with open(config_path) as f:
        cfg = yaml.safe_load(f) or {}
except yaml.YAMLError as e:
    print(f"coherence-check: failed to parse config YAML: {e}", file=sys.stderr)
    sys.exit(4)

findings = []  # list of (severity, title, context, fix)

def add(sev, title, context, fix):
    findings.append((sev, title, context, fix))

# Resolve artifact paths from config.
ctx = cfg.get("context", {}) or {}
artifact_keys = ["constitution_path", "architecture_path", "testing_path",
                 "glossary_path", "domain_path", "design_path"]
artifact_paths = {}
for k in artifact_keys:
    p = ctx.get(k)
    if p:
        artifact_paths[k] = os.path.join(repo_root, p) if not os.path.isabs(p) else p

# Memory file path (separate config namespace).
mf_path = (cfg.get("memory_file") or {}).get("path")
if mf_path:
    memory_file = os.path.join(repo_root, mf_path) if not os.path.isabs(mf_path) else mf_path
else:
    memory_file = None

# ── Check 1: Every artifact path mentioned in any artifact exists on disk ──
# (References within artifacts to docs/ paths must resolve.)
ref_re = re.compile(r'\]\(([^)]+\.md)\)')
for key, path in artifact_paths.items():
    if not os.path.exists(path):
        continue  # the artifact itself doesn't exist; not a coherence concern
    with open(path) as f:
        content = f.read()
    for m in ref_re.finditer(content):
        ref = m.group(1)
        # Skip external URLs.
        if ref.startswith("http://") or ref.startswith("https://"):
            continue
        # Resolve relative to artifact's directory.
        target = os.path.normpath(os.path.join(os.path.dirname(path), ref))
        if not os.path.exists(target):
            rel_artifact = os.path.relpath(path, repo_root)
            add("CRITICAL",
                f"unresolvable pointer in {rel_artifact}",
                f"link target {ref!r} (resolved as {os.path.relpath(target, repo_root)}) does not exist",
                f"either remove the link or create the target file")

# Memory file pointers check (extends Check 1 to the memory file)
if memory_file and os.path.exists(memory_file):
    with open(memory_file) as f:
        content = f.read()
    for m in ref_re.finditer(content):
        ref = m.group(1)
        if ref.startswith(("http://", "https://")):
            continue
        target = os.path.normpath(os.path.join(os.path.dirname(memory_file), ref))
        if not os.path.exists(target):
            add("CRITICAL",
                f"unresolvable pointer in memory file",
                f"link target {ref!r} (resolved as {os.path.relpath(target, repo_root)}) does not exist",
                f"re-run ss-bs-discovering-memory-file to refresh pointers, OR create the missing artifact")

# ── Check 2: Memory file Pointers section references every existing artifact ──
if memory_file and os.path.exists(memory_file):
    with open(memory_file) as f:
        mf_content = f.read()
    for key, path in artifact_paths.items():
        if not os.path.exists(path):
            continue  # artifact doesn't exist; nothing to point to
        # Look for the artifact's basename or relative path in the memory file's links.
        rel = os.path.relpath(path, os.path.dirname(memory_file))
        basename = os.path.basename(path)
        if rel not in mf_content and basename not in mf_content:
            add("WARNING",
                f"memory file missing pointer to {basename}",
                f"{basename} exists at {os.path.relpath(path, repo_root)} but is not referenced in the memory file",
                f"re-run ss-bs-discovering-memory-file in extend mode to add the pointer")

# ── Check 3: Every entity in DOMAIN.md is defined in GLOSSARY.md ──
domain_path = artifact_paths.get("domain_path")
glossary_path = artifact_paths.get("glossary_path")
if domain_path and glossary_path and os.path.exists(domain_path) and os.path.exists(glossary_path):
    with open(domain_path) as f:
        domain_content = f.read()
    with open(glossary_path) as f:
        glossary_content = f.read().lower()
    # Entity names are H2 headings in DOMAIN.md per its output template.
    entity_re = re.compile(r'^##\s+([A-Z][A-Za-z0-9]+)\s*$', re.MULTILINE)
    for m in entity_re.finditer(domain_content):
        entity = m.group(1)
        if entity.lower() not in glossary_content:
            add("WARNING",
                f"vocabulary gap: {entity!r} in DOMAIN.md, missing from GLOSSARY.md",
                f"DOMAIN.md defines entity {entity!r} but GLOSSARY.md has no matching term",
                f"re-run ss-bs-discovering-glossary in extend mode to add the definition")

# ── Check 4: Every architectural component in ARCHITECTURE.md is mentioned in TESTING.md ──
arch_path = artifact_paths.get("architecture_path")
testing_path = artifact_paths.get("testing_path")
if arch_path and testing_path and os.path.exists(arch_path) and os.path.exists(testing_path):
    with open(arch_path) as f:
        arch_content = f.read()
    with open(testing_path) as f:
        testing_content = f.read().lower()
    # Components are H3 entries under "## Components" per architecture's template.
    comp_section = re.search(r'^##\s+Components\s*$(.+?)^##\s', arch_content, re.MULTILINE | re.DOTALL)
    if comp_section:
        comp_re = re.compile(r'^###\s+([A-Za-z][A-Za-z0-9_\- ]+?)(?:\s*[·—].*)?$', re.MULTILINE)
        for m in comp_re.finditer(comp_section.group(1)):
            comp = m.group(1).strip()
            if comp.lower() not in testing_content:
                add("INFO",
                    f"testing/architecture coverage: {comp!r} not mentioned in TESTING.md",
                    f"ARCHITECTURE.md lists component {comp!r}; TESTING.md doesn't address its testing",
                    f"re-run ss-bs-discovering-testing in extend mode to address")

# ── Check 5: Constitution principles citing an evidence file → file exists ──
const_path = artifact_paths.get("constitution_path")
if const_path and os.path.exists(const_path):
    with open(const_path) as f:
        const_content = f.read()
    # Heuristic: lines like "Evidence: ... `path/to/file`" or "Evidence: ... path/to/file" or .eslintrc, package.json etc.
    evidence_re = re.compile(r'\*\*Evidence:\*\*([^\n]+)', re.IGNORECASE)
    path_token_re = re.compile(r'`([^`]+)`')
    for m in evidence_re.finditer(const_content):
        line = m.group(1)
        for token in path_token_re.finditer(line):
            t = token.group(1)
            # Only check things that look like file paths (contain / or end in known extensions).
            if "/" in t or any(t.endswith(ext) for ext in [".json", ".yml", ".yaml", ".toml", ".ini", ".js", ".ts"]):
                target = os.path.join(repo_root, t)
                if not os.path.exists(target):
                    add("CRITICAL",
                        f"constitution cites missing file: {t!r}",
                        f"a principle's Evidence field references {t!r} which does not exist in the repo",
                        f"either update/remove the principle, or restore the file")

# ── Check 6: Constitution principles do not contradict each other (within file) ──
# (Heuristic: detect MUST X and MUST not-X for same X. Hard to do perfectly; skip if no
# obvious contradiction detector; surface as INFO so users know to review.)
# Conservative implementation: look for principles using the word "throw" alongside
# principles using the word "Result" — known common conflict pattern. Extend over time.
if const_path and os.path.exists(const_path):
    with open(const_path) as f:
        const_content = f.read().lower()
    if "must throw" in const_content and ("must return result" in const_content or "must use result" in const_content):
        add("WARNING",
            "constitution principles may contradict each other",
            "both 'MUST throw' and 'MUST use Result' wording detected — these are typically incompatible",
            "re-read both principles and reconcile (or scope each to a different layer)")

# ── Check 7: Suggestion-pass provenance markers older than 6 months (audit-only — coordinator decides) ──
# Always run the check; emit INFO findings; the coordinator filters audit-only findings if needed.
import datetime
prov_re = re.compile(r'Added via bootstrap suggestion pass \((\d{4}-\d{2}-\d{2})\)', re.IGNORECASE)
prov_re2 = re.compile(r'provenance:.*?(\d{4}-\d{2}-\d{2})', re.IGNORECASE)
cutoff = datetime.date.today() - datetime.timedelta(days=180)
for key, path in list(artifact_paths.items()) + ([("memory_file", memory_file)] if memory_file else []):
    if not path or not os.path.exists(path):
        continue
    with open(path) as f:
        content = f.read()
    for m in list(prov_re.finditer(content)) + list(prov_re2.finditer(content)):
        try:
            d = datetime.date.fromisoformat(m.group(1))
        except ValueError:
            continue
        if d < cutoff:
            rel = os.path.relpath(path, repo_root)
            add("INFO",
                f"old suggestion in {rel} ({d.isoformat()})",
                f"a suggestion-pass entry from {d.isoformat()} is >6 months old without follow-up",
                f"audit: re-evaluate whether this aspiration has been realized or should be retired")

# ── Emit findings ──
sev_order = {"CRITICAL": 0, "WARNING": 1, "INFO": 2}
findings.sort(key=lambda x: sev_order[x[0]])

for sev, title, context, fix in findings:
    print(f"[{sev}] {title}")
    print(f"  context: {context}")
    print(f"  fix: {fix}")
    print()

counts = {"CRITICAL": 0, "WARNING": 0, "INFO": 0}
for f in findings:
    counts[f[0]] += 1

if not findings:
    print("coherence-check: PASS (0 findings)")
    sys.exit(0)
else:
    summary = ", ".join(f"{counts[s]} {s}" for s in ("CRITICAL", "WARNING", "INFO") if counts[s])
    print(f"coherence-check: {len(findings)} findings ({summary})")
    sys.exit(1)
PYEOF
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x skills/spec-driven-development/framework/coherence-check.sh`

- [ ] **Step 3: Write the first failing test — clean fixture should pass**

Create `/tmp/coherence-test-clean/` as a minimal repo fixture:

```bash
rm -rf /tmp/coherence-test-clean && mkdir -p /tmp/coherence-test-clean && cd /tmp/coherence-test-clean
git init -q
mkdir -p .sublime-skills docs
cat > .sublime-skills/config.yml <<'EOF'
context:
  constitution_path: docs/constitution.md
  architecture_path: null
  testing_path: null
  glossary_path: null
  domain_path: null
  design_path: null
branching:
  branch_pattern: "feat/{short-name}"
grill:
  question_cap: 10
memory_file:
  path: null
  character_limit: 40000
suggest:
  default: ask
EOF
cat > docs/constitution.md <<'EOF'
# Constitution

## Principles

### Principle 1 — Example

**Severity:** MUST

**Statement:** Example principle.

**Evidence:** Observed across the codebase.

**Rationale:** Example.
EOF
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh"
echo "exit: $?"
cd "$OLDPWD"
```

Expected: stdout contains `coherence-check: PASS (0 findings)`, exit code 0.

- [ ] **Step 4: Write the second test — unresolvable pointer should produce CRITICAL**

```bash
rm -rf /tmp/coherence-test-broken && mkdir -p /tmp/coherence-test-broken && cd /tmp/coherence-test-broken
git init -q
mkdir -p .sublime-skills docs
# Reuse the clean config but add a memory file with a broken pointer.
cp /tmp/coherence-test-clean/.sublime-skills/config.yml .sublime-skills/config.yml
# Set memory_file.path to CLAUDE.md so the check runs.
sed -i 's|path: null|path: CLAUDE.md|' .sublime-skills/config.yml
cat > docs/constitution.md <<'EOF'
# Constitution
EOF
cat > CLAUDE.md <<'EOF'
# Project
## Pointers
- [Design System](docs/DESIGN.md) — visual tokens
EOF
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh"
echo "exit: $?"
cd "$OLDPWD"
```

Expected: stdout includes `[CRITICAL] unresolvable pointer in memory file` and `link target 'docs/DESIGN.md' ... does not exist`, exit code 1.

- [ ] **Step 5: Write the third test — missing pointer to existing artifact should produce WARNING**

```bash
rm -rf /tmp/coherence-test-warn && mkdir -p /tmp/coherence-test-warn && cd /tmp/coherence-test-warn
git init -q
mkdir -p .sublime-skills docs
cp /tmp/coherence-test-clean/.sublime-skills/config.yml .sublime-skills/config.yml
sed -i 's|path: null|path: CLAUDE.md|' .sublime-skills/config.yml
sed -i 's|architecture_path: null|architecture_path: docs/ARCHITECTURE.md|' .sublime-skills/config.yml
cat > docs/constitution.md <<'EOF'
# Constitution
EOF
cat > docs/ARCHITECTURE.md <<'EOF'
# Architecture
EOF
cat > CLAUDE.md <<'EOF'
# Project
## Pointers
- [Constitution](docs/constitution.md) — principles
EOF
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh"
echo "exit: $?"
cd "$OLDPWD"
```

Expected: stdout includes `[WARNING] memory file missing pointer to ARCHITECTURE.md`, exit code 1.

- [ ] **Step 6: Write the fourth test — vocabulary gap (DOMAIN entity missing from GLOSSARY) should produce WARNING**

```bash
rm -rf /tmp/coherence-test-vocab && mkdir -p /tmp/coherence-test-vocab && cd /tmp/coherence-test-vocab
git init -q
mkdir -p .sublime-skills docs
cp /tmp/coherence-test-clean/.sublime-skills/config.yml .sublime-skills/config.yml
sed -i 's|domain_path: null|domain_path: docs/DOMAIN.md|' .sublime-skills/config.yml
sed -i 's|glossary_path: null|glossary_path: docs/GLOSSARY.md|' .sublime-skills/config.yml
cat > docs/DOMAIN.md <<'EOF'
# Domain

## PurchaseOrder

Attributes: id, total
EOF
cat > docs/GLOSSARY.md <<'EOF'
# Glossary

## O

### Order
A customer's purchase request.
EOF
cat > docs/constitution.md <<'EOF'
# Constitution
EOF
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh"
echo "exit: $?"
cd "$OLDPWD"
```

Expected: stdout includes `[WARNING] vocabulary gap: 'PurchaseOrder' in DOMAIN.md, missing from GLOSSARY.md`, exit code 1.

- [ ] **Step 7: Write the fifth test — invalid config path returns exit 2**

```bash
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh" /nonexistent/path.yml
echo "exit: $?"
```

Expected: stderr `coherence-check: config not found at /nonexistent/path.yml`, exit code 2.

- [ ] **Step 8: Run all 5 tests in sequence to confirm**

```bash
echo "=== Test 1 (clean): "
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh" /tmp/coherence-test-clean/.sublime-skills/config.yml ; echo "exit: $?"

echo "=== Test 2 (broken pointer): "
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh" /tmp/coherence-test-broken/.sublime-skills/config.yml ; echo "exit: $?"

echo "=== Test 3 (missing pointer): "
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh" /tmp/coherence-test-warn/.sublime-skills/config.yml ; echo "exit: $?"

echo "=== Test 4 (vocabulary gap): "
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh" /tmp/coherence-test-vocab/.sublime-skills/config.yml ; echo "exit: $?"

echo "=== Test 5 (missing config): "
"$OLDPWD/skills/spec-driven-development/framework/coherence-check.sh" /nonexistent/path.yml ; echo "exit: $?"
```

Expected: tests 1 → exit 0; tests 2-4 → exit 1 with the specific finding text in stdout; test 5 → exit 2.

- [ ] **Step 9: Run on this project's actual config (regression / sanity)**

```bash
./skills/spec-driven-development/framework/coherence-check.sh
echo "exit: $?"
```

Expected: the script runs cleanly against this repo (which doesn't have all artifacts; many checks will pass trivially). Exit may be 0 or 1 depending on this repo's actual state — verify findings are reasonable.

- [ ] **Step 10: Clean up fixtures**

```bash
rm -rf /tmp/coherence-test-clean /tmp/coherence-test-broken /tmp/coherence-test-warn /tmp/coherence-test-vocab
```

- [ ] **Step 11: Commit**

```bash
git add skills/spec-driven-development/framework/coherence-check.sh
git commit -m "Add coherence-check.sh framework script"
```

---

**Phase 5 complete.** The coherence checker exists as a reusable framework script. Bootstrap coordinator (Phase 6) and audit coordinator (Phase 8) both invoke it.

---

## Phase 6: Bootstrap Coordinator Updates

### Task 12: Update `ss-bs-bootstrapping-project` for the new pipeline shape

**Files:**
- Modify: `skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md`

Spec reference: Section 5.

The coordinator gains: a new Step 2 (opt-in switch), 2 new stages in the per-file loop (testing + memory-file), a new Step 8 (coherence check), a config-migration sub-step for re-runs against pre-update configs. The renumbering: existing Step 2 → Step 3, existing Step 8 (commit) → Step 10, existing Step 9 (report) → Step 11.

- [ ] **Step 1: Read the existing coordinator end-to-end**

Run: `cat skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md`
Identify the current Checklist (9 items), the per-stage Step 2 walk-through (with Step 1.5 todo-build sub-step), the config-copy and config-edit steps, the existing commit message.

- [ ] **Step 2: Update the frontmatter description and the Overview section**

Modify the `description:` line to mention 7 artifacts and the opt-in switch:

```yaml
description: Use to set up a project for spec-driven development - walks the user through each convention file (constitution, architecture, testing, glossary, domain, design) and the agent memory file (CLAUDE.md/AGENTS.md/GEMINI.md/.agents.md) by loading the matching ss-bs-discovering-<topic> inline skill for each, then scaffolds .sublime-skills/config.yml and supporting directories. Asks once at the top whether to run the prescriptive suggestion pass alongside the descriptive scan. User-invoked, not part of the SDD pipeline.
```

In the Overview section, update "five convention files" → "seven convention files" (constitution, architecture, testing, glossary, domain, design, memory-file), and mention the opt-in.

- [ ] **Step 3: Update the "What This Skill Doesn't Do" section**

No content changes needed beyond reviewing — the existing rules still hold. Verify and add this row if absent:

```markdown
- It does NOT maintain multiple memory files. The bootstrap maintains exactly one (the user picks via ss-bs-discovering-memory-file's Step 0 when ambiguous).
```

- [ ] **Step 4: Update the Hard Gates section**

Add these rows to the existing Hard Gates:

```markdown
- Do NOT skip Step 2 (the opt-in switch). It threads `SUGGEST` into every discovering-X skill and must be asked exactly once per run (or read from config when `suggest.default` is `on` or `off`).
- Do NOT thread `SUGGEST=on` if the user picked "Descriptive only" or if config sets `suggest.default: off`.
- Do NOT skip Step 8 (coherence check). The check is mandatory before commit; the user can choose how to act on findings but cannot bypass the check itself.
```

- [ ] **Step 5: Replace the Checklist with the new 11-item list**

Find the current Checklist section. Replace with:

```markdown
## Checklist

Proceed through these in order:

1. Detect existing setup via discovery script
2. Suggestion-pass opt-in switch (one question; threads `SUGGEST=on|off` into every discovering-X invocation)
3. Per-file loop for the 7 convention files (constitution → architecture → testing → glossary → domain → design → memory-file): for each, detect → ask → load the matching `ss-bs-discovering-<topic>` skill inline → record outcome
4. Create supporting directories (`docs/adr/`, `docs/specs/`) with stub READMEs
5. Copy config scaffold to `.sublime-skills/config.yml`, create empty `.sublime-skills/config-local.yml`, and create `.sublime-skills/.gitignore` with both entries
6. Edit config to reflect reality (set `context.<name>_path` to null for skipped files; adjust if non-default paths)
7. Run `validate-config.sh`; fix-and-retry on FAIL (cap 3 attempts)
8. Run `coherence-check.sh`; surface findings; offer Address/Acknowledge/Show options (cap 3 coherence loops)
9. Ensure `.sublime-skills/.gitignore` contains state.json + config-local.yml entries
10. Single commit
11. Report and direct user to `ss-sdd-coordinator`
```

- [ ] **Step 6: Insert a new "Step 2: Suggestion-pass Opt-in Switch" section**

Insert this section between the existing Step 1 (Detect Existing Setup) and what was Step 2 (Per-File Loop) — renumbering the per-file loop to Step 3:

````markdown
## Step 2: Suggestion-Pass Opt-In Switch

Read `suggest.default` from `.sublime-skills/config.yml` (or from the scaffold's default `ask` if the file doesn't exist yet — the scaffold copy happens in Step 5, so on first run, treat `default` as `ask`).

- **`default: on`** — set `SUGGEST=on` for the run; skip the question; log "Suggestion pass: on (from config)" in the todo list.
- **`default: off`** — set `SUGGEST=off` for the run; skip the question.
- **`default: ask`** — ask:

```
Question: "Before the per-file walkthrough, one preference question:

Do you want me to also propose improvements where I see opportunities, or
just document what exists?"

Options:
  - "Descriptive only — document what's there (fastest, safest)"
  - "Descriptive + suggestions (Recommended — flags anti-patterns and
    missing-but-typically-valuable patterns, cited from evidence)"
  - "Skip bootstrap and run audit mode instead (for established projects
    where you want the deeper read)"
```

Map answers:
- "Descriptive only" → `SUGGEST=off`
- "Descriptive + suggestions" → `SUGGEST=on`
- "Skip bootstrap and run audit mode" → halt bootstrap, invoke `ss-bs-auditing-project`, exit

Hold `SUGGEST` for the duration of the run and pass it into every `ss-bs-discovering-<topic>` invocation in Step 3.
````

- [ ] **Step 7: Update the existing "Step 1.5: Build the Todo List" to add the new items**

Find Step 1.5 (Build the Todo List). Update the list to 14 items reflecting the new stages and coherence check:

```markdown
1. Constitution (`docs/constitution.md`)
2. Architecture (`docs/ARCHITECTURE.md`)
3. Testing (`docs/TESTING.md`)
4. Glossary (`docs/GLOSSARY.md`)
5. Domain model (`docs/DOMAIN.md`)
6. Design (`docs/DESIGN.md`)
7. Agent memory file (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md — discovery skill picks the canonical one)
8. Create `docs/adr/`, `docs/specs/` with READMEs
9. Copy config scaffold to `.sublime-skills/config.yml`, create empty `.sublime-skills/config-local.yml`, and create `.sublime-skills/.gitignore` with both entries
10. Edit config to reflect skipped files
11. Run `validate-config.sh` (fix-and-retry loop)
12. Run `coherence-check.sh` (cap 3 loops if Address chosen)
13. Ensure `.sublime-skills/.gitignore` contains state.json + config-local.yml entries
14. Commit
```

- [ ] **Step 8: Renumber and update Step 2 (Per-File Loop) → Step 3, expand stage order**

Rename the section heading from `## Step 2: Per-File Loop` to `## Step 3: Per-File Loop`. Update the iteration order in the section's opening sentence:

```markdown
Iterate convention files in this order: **constitution, architecture, testing, glossary, domain, design, memory-file.** For each:
```

Update the routing table (under "Load the Matching `discovering-X` Skill Inline") to include the new skills:

```markdown
| Convention file | Skill loaded (inline) |
|---|---|
| Constitution | `ss-bs-discovering-constitution` |
| Architecture | `ss-bs-discovering-architecture` |
| Testing | `ss-bs-discovering-testing` |
| Glossary | `ss-bs-discovering-glossary` |
| Domain model | `ss-bs-discovering-domain-model` |
| Design | `ss-bs-discovering-design` |
| Memory file | `ss-bs-discovering-memory-file` |
```

Update the inputs documentation passed to each discovering-X skill to include `SUGGEST`:

```
Load skill: ss-bs-discovering-<topic>

REPO_ROOT:        <absolute path to repo root>
MODE:             create | extend | replace
SUGGEST:          on | off  ← NEW, from Step 2
EXISTING_CONTENT: (only for extend / replace)
FILE_PATH:        <target path>
```

In the per-file detection logic, add default paths for the two new stages:
- Testing: `docs/TESTING.md`
- Memory file: resolved by the discovery skill's Step 0 (use `memory_file.path` from config if set, else auto-detect, else ask the user)

- [ ] **Step 9: Renumber subsequent steps (3 → 4, 4 → 5, 5 → 6, 6 → 7) and insert new Step 8 (Coherence Check)**

Renumber the existing "Step 3: Create Supporting Directories" → "Step 4: Create Supporting Directories". Same for the next three (Copy Config → Step 5, Edit Config → Step 6, Validate → Step 7).

Insert a new section between Validate and Gitignore Housekeeping:

````markdown
## Step 8: Cross-Artifact Coherence Check

Run the coherence checker:

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/coherence-check.sh"
```

| Exit code | Meaning | Action |
|---|---|---|
| `0` (PASS) | No findings; artifacts are internally consistent | Proceed to Step 9. |
| `1` (findings present) | One or more findings on stdout | Surface ALL findings verbatim to the user (do not summarize). Then ask the options below. |
| `2` (config missing) | Should not happen — Step 5 just created config | Halt and surface as serious error. |
| `3` (usage error) | Coordinator bug | Halt and surface. |
| `4` (internal error) | python3 missing or YAML unparseable | Halt and surface; coherence check is mandatory for bootstrap. |

### When findings are present

Ask:

```
Question: "How would you like to proceed?"
Options:
  - "Address findings now" (Recommended if any CRITICAL)
  - "Acknowledge and commit as-is"
  - "Show details for one finding"
```

**Address findings now:**
1. For each finding, identify the relevant `discovering-X` skill (the finding's "fix" line names it).
2. Loop back into Step 3's per-file loop with `MODE=extend` for just those skills.
3. After all addressed, re-run `coherence-check.sh`.
4. If new findings appear, ask the same question again.
5. **Cap at 3 coherence loops.** After the third, surface:

   > "We've done three rounds of coherence fixes and findings remain. Want to:
   > (a) commit with the remaining findings noted in the conversation, or
   > (b) abort the bootstrap (no commit)?"

**Acknowledge and commit as-is:** proceed to Step 9. Findings are NOT added to the commit message.

**Show details for one finding:** the user picks one; expand the context lines. Then re-ask the three options.
````

- [ ] **Step 10: Renumber the remaining steps (7 → 9, 8 → 10, 9 → 11)**

Renumber existing "Step 7: Gitignore Housekeeping" → "Step 9". Renumber existing "Step 8: Commit" → "Step 10". Renumber existing "Step 9: Report" → "Step 11".

In the new Step 10 (Commit), update the `git add` line to include the two new artifacts:

```bash
git add docs/constitution.md docs/ARCHITECTURE.md docs/TESTING.md docs/GLOSSARY.md docs/DOMAIN.md docs/DESIGN.md \
        <memory-file-path-from-step-7> \
        docs/adr/ docs/specs/ \
        .sublime-skills/config.yml .sublime-skills/.gitignore
git commit -m "chore: initialize SDD project context"
```

Note: `<memory-file-path-from-step-7>` is whatever `discovering-memory-file` resolved (CLAUDE.md, AGENTS.md, etc.) — only include if that stage created/modified a file.

- [ ] **Step 11: Add a config-migration sub-step to Step 5 for re-runs against pre-update configs**

Find the new Step 5 (Copy Config Scaffold). The current re-run logic uses `[ -f config.yml ] || cp scaffold` — so on re-run, the existing config is preserved. But the existing config from a pre-update bootstrap lacks `context.testing_path` and the entire `suggest:` block. Add this migration sub-step at the top of Step 5:

````markdown
### 5a. Migrate pre-update configs (re-run only)

If `.sublime-skills/config.yml` already exists, check for missing keys introduced in this bootstrap version:

```bash
CONFIG=.sublime-skills/config.yml
NEEDS_MIGRATION=false
grep -q "^  testing_path:" "$CONFIG" || NEEDS_MIGRATION=true
grep -q "^suggest:" "$CONFIG" || NEEDS_MIGRATION=true
```

If `NEEDS_MIGRATION=true`, ask the user:

```
Question: "Your config is from an older bootstrap version that doesn't know about the testing artifact or the suggestion-pass switch. Add the missing keys with safe defaults?"
Options:
  - "Yes — add testing_path: null and suggest.default: ask" (Recommended)
  - "No — abort bootstrap so I can review manually"
```

On Yes: use `Edit` to insert the missing keys.
- For `testing_path`, insert below `architecture_path` in the `context:` block:
  ```yaml
    testing_path: null                            # added by config-migration
  ```
- For the `suggest:` block, append at end of file:
  ```yaml

  suggest:
    default: ask
  ```

On No: halt with a clear message: "Aborted: please add testing_path and suggest.default to config manually, then re-run bootstrap."

After migration (or if no migration needed), continue with the existing Step 5 logic.
````

- [ ] **Step 12: Update the Step 11 (Report) template to list 7 artifacts**

Replace the report block in Step 11 (was Step 9):

```
SDD bootstrap complete.

Convention files:
- docs/constitution.md — <outcome>
- docs/ARCHITECTURE.md — <outcome>
- docs/TESTING.md — <outcome>
- docs/GLOSSARY.md — <outcome>
- docs/DOMAIN.md — <outcome>
- docs/DESIGN.md — <outcome>
- <memory-file-path> — <outcome>

Directories:
- docs/adr/ (with README)
- docs/specs/ (with README)

Config:
- .sublime-skills/config.yml created/migrated and validated (PASS)
- .sublime-skills/.gitignore created with state.json and config-local.yml entries
- Skipped files have their context.<name>_path set to null
- Suggestion pass: <on / off> (this run)

Coherence check: <PASS | N findings (acknowledged | addressed in N loops)>

Next steps:
- Run the ss-sdd-coordinator skill to start your first feature
- Or, re-run ss-bs-bootstrapping-project later to extend a convention file
- Or, run ss-bs-auditing-project for a deeper opinionated re-evaluation
```

- [ ] **Step 13: Update Common Mistakes**

Append to the Common Mistakes table:

```markdown
| Skipping Step 2 (opt-in switch) | Mandatory — threads SUGGEST through every stage |
| Skipping Step 8 (coherence check) | Mandatory — check before commit; user decides how to act |
| Looping coherence fixes more than 3 times | Cap is 3; surface "commit-with-remaining or abort" after the third |
| Adding coherence findings to the commit message | Findings are conversation-only; do not pollute commit log |
| Forgetting to thread SUGGEST into a discovering-X invocation | Every discovering-X call MUST include SUGGEST (on or off); auditable in transcript |
| Ignoring the config-migration sub-step on re-runs | Pre-update configs lack testing_path / suggest block; migrate or abort |
```

- [ ] **Step 14: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md
grep -q "Suggestion-Pass Opt-In Switch" "$SKILL" && echo "Step 2 opt-in: OK" || echo "MISSING"
grep -q "Cross-Artifact Coherence Check\|coherence-check.sh" "$SKILL" && echo "Coherence check: OK" || echo "MISSING"
grep -q "ss-bs-discovering-testing" "$SKILL" && echo "Testing stage: OK" || echo "MISSING"
grep -q "ss-bs-discovering-memory-file" "$SKILL" && echo "Memory-file stage: OK" || echo "MISSING"
grep -q "Migrate pre-update configs\|NEEDS_MIGRATION" "$SKILL" && echo "Config migration: OK" || echo "MISSING"
grep -q "14 items\|14 stages\|7 convention files\|seven convention files" "$SKILL" && echo "Updated counts: OK" || echo "MISSING"
```

All lines should print `OK`.

- [ ] **Step 15: End-to-end manual sanity check on a fresh fixture**

This is a manual integration test. Spin up a throwaway fixture repo and walk through the updated coordinator mentally (don't actually invoke a real Claude session — just read the skill from top to bottom in sequence as if executing). Confirm:
- Step 2 question is asked exactly once and the answer is held throughout
- Per-file loop covers all 7 stages in the documented order
- Coherence check runs after validate-config but before commit
- The 3-loop cap on coherence fixes has a clear exit path
- The report at Step 11 mentions all the new pieces

- [ ] **Step 16: Commit**

```bash
git add skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md
git commit -m "ss-bs-bootstrapping-project: 7-artifact pipeline + opt-in + coherence"
```

---

**Phase 6 complete.** The bootstrap coordinator now wires testing, memory-file, suggestion-pass opt-in, and coherence check end-to-end. A user can run bootstrap and get the full new experience.

---

## Phase 7: Audit MODE in Every Discovery Skill

The audit coordinator (Phase 8) re-uses every discovery skill via a new `MODE=audit` value. Each discovery skill needs:
1. `MODE=audit` listed in the Inputs section
2. A new branch in the Top-Level Flow diagram for audit
3. A new Step 1.6 (Drift check) that compares the existing artifact against current code state
4. A new Q0 (Drift resolution) in Step 3 that asks the user what to do with each drift finding
5. Provenance-marker re-evaluation logic (for entries marked "added via bootstrap suggestion pass"): is it still aspirational, or has the code caught up?

Tasks 13-19 apply this pattern to each of the 7 skills. Task 13 (architecture) provides the full canonical pattern. Tasks 14-19 use the same step structure (read, add audit branch, add Step 1.6, add Q0, add provenance re-eval, verify, commit) but spell out their skill-specific drift signals and provenance-eval logic.

### Task 13: Add `MODE=audit` to `ss-bs-discovering-architecture`

**Files:**
- Modify: `skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md`

Spec reference: Section 9.3 (architecture row in the drift table).

- [ ] **Step 1: Read the (Phase 2-updated) skill end-to-end**

Run: `cat skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md`

- [ ] **Step 2: Update the Inputs section to accept `MODE=audit`**

In the `MODE` input description, expand the list:

```markdown
**`MODE`** — `create | extend | replace | audit`. `audit` invokes the drift-check path (Step 1.6) and the drift-resolution Q0 in Step 3.
```

- [ ] **Step 3: Add an audit branch to the Top-Level Flow diagram**

Append a third branch:

```
├─────────────────────────────────────────────────────┤
│ MODE = audit                                        │
│   → Step 1: silent code scan                        │
│   → Step 1.5: silent diagnose (always on for audit) │
│   → Step 1.6: drift check vs EXISTING_CONTENT       │  ← NEW
│   → Step 2: announce findings + drift + diagnoses   │
│   → Step 3: Q0 (drift resolution) → Q1 → Q1.5 → ... │
│   → Step 4-6: as usual                              │
└─────────────────────────────────────────────────────┘
```

- [ ] **Step 4: Insert Step 1.6 (Drift Check) between Step 1.5 and Step 2**

Insert this section (only runs when `MODE=audit`):

````markdown
## Step 1.6: Drift Check (only if `MODE=audit`)

Compare each entry in `EXISTING_CONTENT` against current code state. The goal is to detect entries that have gone stale.

### 1.6a. Drift categories for architecture

For each architecture-doc entry, check:

- **Component drift.** The doc lists components C1, C2, C3; the repo currently has C1, C2, C4, C5. Drift items: C3 (removed?) and C4, C5 (added?). Evidence: directory listing or service-config file paths.
- **Topology drift.** The doc says "k8s deploy with ingress nginx"; current `k8s/` shows `traefik` ingress instead. Evidence: file paths.
- **Data store drift.** The doc lists Postgres + Redis; `docker-compose.yml` now also lists ClickHouse. Evidence: compose file path + line.
- **Integration drift.** The doc lists Stripe + SendGrid; current `.env.example` adds `SLACK_WEBHOOK_URL` (new integration) or no longer mentions `SENDGRID_*` (removed). Evidence: file path + grep diff.
- **Boundary drift.** The doc's "out of scope" list mentions services no longer present (or omits things now out of scope). Evidence: relevant file paths.
- **Provenance re-evaluation.** For each section/component carrying an "Added via bootstrap suggestion pass (YYYY-MM-DD)" marker, check whether the underlying evidence is still present:
  - If the original evidence pattern (e.g. "cross-service direct DB access in services/billing/src/invoice.ts:34") is STILL present, the suggestion is still aspirational — flag as INFO drift "still not enforced after N days".
  - If the original evidence pattern is GONE (the code has changed to match the aspiration), flag as INFO drift "aspiration met — provenance marker can be removed and entry promoted to normal".

### 1.6b. Compile drift findings in memory

Each finding: `kind` (component-added / component-removed / topology-change / store-added / store-removed / integration-added / integration-removed / boundary-stale / aspiration-met / aspiration-still-pending), `entry` (the doc text being challenged), `evidence` (file paths showing the current code state).

No cap on drift findings — every observable drift is surfaced. The user resolves each in Q0.
````

- [ ] **Step 5: Modify Step 2 (Announce Findings) to mention drift count for audit**

In the audit-mode announcement (or add a new sentence to the existing announcement when MODE=audit), include the drift count:

> "Audit mode. Scan + diagnose + drift check complete. Found N drift items (X component changes, Y topology changes, Z provenance re-evaluations) — I'll surface those first in the questions, then walk through observed candidates and suggestions as usual."

- [ ] **Step 6: Insert Q0 (Drift Resolution) at the start of Step 3 in audit mode**

In Step 3, before Q1, insert this Q0 block (gated on `MODE=audit AND drift findings ≥ 1`):

````markdown
### Q0 — Drift Resolution (only if `MODE=audit` AND Step 1.6 produced ≥1 drift finding)

Ask one question per drift finding (do NOT bundle — drift items often have nuanced individual resolutions):

```
Question: "Drift detected: <entry summary>. Current code state: <evidence>. What's the right resolution?"

Options:
  - "Update the doc to match code"
  - "Keep the doc — code is wrong / will be fixed"
  - "Remove the entry — no longer applies"
  - "Both — clarify scope (split into multiple entries)"
```

For **provenance re-evaluation** findings, the question is different:

```
Question: "Aspirational entry '<title>' was added on <date>. Evidence at that time: <original evidence>. Current code state: <current evidence>. Has this aspiration been realized?"

Options:
  - "Yes — code has caught up. Remove the provenance marker (promote to normal)."
  - "No — code still has the original problem. Keep as aspirational; refresh the marker date."
  - "Drop the entry — we've decided not to pursue this aspiration."
```

Record each resolution. Apply during Step 4 (Draft Synthesis).
````

- [ ] **Step 7: Modify Step 4 (Draft & Show) to apply drift resolutions and provenance re-evals**

In Step 4's bullet list of inputs to the draft synthesis, add:

```markdown
- Q0 drift resolutions (per drift item: update / keep / remove / clarify)
- Q0 provenance re-evaluations (per aspirational entry: promote / refresh / drop)
```

Apply the resolutions when synthesizing — e.g. "update the doc" means use the current-code value; "remove the entry" means omit it; "promote to normal" means strip the `> _Added via bootstrap suggestion pass …_` marker.

- [ ] **Step 8: Update Hard Gates and Common Mistakes for audit mode**

Append to Hard Gates:

```markdown
- In audit mode, do NOT skip Step 1.6 (drift check). It's the third operation alongside observe and diagnose; without it, audit is just "extend mode with SUGGEST=on".
- In audit mode, ask Q0 questions ONE drift item per question — do NOT bundle. Drift resolutions are nuanced individually.
- In audit mode, SUGGEST is always treated as `on` (regardless of input). Document this in the inputs section if not already obvious.
```

Append to Common Mistakes:

```markdown
| Skipping Step 1.6 in audit mode | Drift detection is the audit's reason for existing |
| Bundling Q0 drift resolutions into one multi-select | Each item gets its own question — resolutions are not collectively decidable |
| Forgetting to refresh the provenance marker date when "Keep aspirational" is chosen | Audit needs the refresh to track time-since-last-evaluation |
| Forgetting to strip the provenance marker when "Promote to normal" is chosen | The marker is the audit's hook; promoting means removing it |
```

- [ ] **Step 9: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md
grep -q "MODE = audit\|MODE=audit" "$SKILL" && echo "Audit branch: OK" || echo "MISSING"
grep -q "Step 1.6\|Drift Check" "$SKILL" && echo "Step 1.6: OK" || echo "MISSING"
grep -q "Q0 — Drift Resolution\|Q0 — Drift" "$SKILL" && echo "Q0: OK" || echo "MISSING"
grep -q "provenance re-evaluation\|Promote to normal\|aspiration been realized" "$SKILL" && echo "Provenance re-eval: OK" || echo "MISSING"
```

All lines should print `OK`.

- [ ] **Step 10: Commit**

```bash
git add skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md
git commit -m "discovering-architecture: add MODE=audit (drift check + Q0)"
```

---

### Task 14: Add `MODE=audit` to `ss-bs-discovering-constitution`

Follow the same step structure as Task 13. The per-skill content below replaces Steps 4 (Step 1.6 substeps) and 6 (Q0 wording) where the content is skill-specific. All other steps (Inputs update, Top-Level Flow audit branch, Step 4 modifications, Hard Gates / Common Mistakes additions, structural verification grep, commit) use the same wording as Task 13.

**Step 4 substitute — Step 1.6 substeps for constitution:**

````markdown
### 1.6a. Drift categories for constitution

- **Evidence-file removed.** A principle's `**Evidence:**` field cites `<path>` (e.g. `.eslintrc.json`); that file no longer exists. Evidence: the principle title + the missing path.
- **Evidence-rule weakened or removed.** A principle cites a lint rule "no-any: error"; current `.eslintrc.json` shows `no-any: warn` or omits it. Evidence: the principle + the current rule state.
- **Code now contradicts a stated principle.** A MUST principle says "API handlers MUST validate via Zod"; current `src/api/*.ts` shows N handlers without Zod calls. Evidence: handler counts.
- **Provenance re-evaluation.** Each principle marked "Added via bootstrap suggestion pass (YYYY-MM-DD)" → has the underlying evidence (the unenforced pattern) been remedied?
````

**Step 6 substitute — Q0 wording for constitution:** use the canonical Q0 template from Task 13, with "<entry summary>" being the principle title.

**Skill-specific commit message:** `discovering-constitution: add MODE=audit (drift check + Q0)`

- [ ] All steps from Task 13 applied with the substitutions above. Use the same step ordering and same verification grep (replacing the skill path).

---

### Task 15: Add `MODE=audit` to `ss-bs-discovering-glossary`

Same structure as Task 13 with these substitutions:

**Step 4 substitute — Step 1.6 substeps for glossary:**

````markdown
### 1.6a. Drift categories for glossary

- **Term no longer used in code.** A defined term has zero occurrences in current source. Evidence: grep count = 0.
- **Term renamed in code.** A defined term has zero occurrences but a clear successor term has high occurrences (e.g. "Order" → 0 occurrences, "PurchaseOrder" → 47 occurrences). Evidence: both counts.
- **New high-traffic term undefined.** A new term (not in glossary) appears ≥10 times in code. Evidence: term + occurrence count.
- **Provenance re-evaluation.** Each term added via suggestion pass — is it actually being used now? Has the inconsistency it was meant to resolve been resolved?
````

**Skill-specific commit message:** `discovering-glossary: add MODE=audit (drift check + Q0)`

- [ ] All other steps from Task 13 applied with the substitutions above.

---

### Task 16: Add `MODE=audit` to `ss-bs-discovering-domain-model`

Same structure as Task 13 with these substitutions:

**Step 4 substitute — Step 1.6 substeps for domain-model:**

````markdown
### 1.6a. Drift categories for domain-model

- **Entity removed.** A documented entity has no matching DB table, ORM model, or type definition in current code. Evidence: search results.
- **Entity added (undocumented).** A new DB table or ORM model exists with no corresponding entity in DOMAIN.md. Evidence: schema file paths.
- **Lifecycle states drift.** A documented entity's state list `{Draft, Submitted}` vs current code's enum `{Draft, Submitted, Cancelled, Shipped}`. Evidence: enum file path.
- **Relationship cardinality drift.** Doc says `User 1:N Order`; current FK is unique (1:1) or has been moved to a join table (N:N). Evidence: schema diff.
- **Provenance re-evaluation.** Each suggestion-added entity / lifecycle — does the code now match the documented model?
````

**Skill-specific commit message:** `discovering-domain-model: add MODE=audit (drift check + Q0)`

- [ ] All other steps from Task 13 applied with the substitutions above.

---

### Task 17: Add `MODE=audit` to `ss-bs-discovering-design`

Same structure as Task 13 with these substitutions:

**Step 4 substitute — Step 1.6 substeps for design:**

````markdown
### 1.6a. Drift categories for design

- **Token value drift.** Doc says `--color-primary: #3B82F6`; current CSS shows `#2563EB` or the variable no longer exists. Evidence: CSS file paths.
- **Token deleted.** A documented token has no occurrences in CSS / Tailwind config. Evidence: grep count.
- **New token undocumented.** A new `--color-*`, `--space-*`, or `--font-*` variable exists in CSS but isn't in DESIGN.md. Evidence: file paths.
- **Component variants drift.** Doc lists Button variants `{primary, secondary, danger}`; component shows `{primary, secondary, danger, ghost, link}`. Evidence: component file path.
- **Provenance re-evaluation.** Each suggestion-added token or rule — has the codebase converged on it?

Audit mode in this skill runs only against existing DESIGN.md (Build path lineage). If the existing file was imported (Import path), drift check is limited to "still exists as a file" only — content drift detection requires Build-path provenance.
````

**Skill-specific commit message:** `discovering-design: add MODE=audit (drift check + Q0)`

- [ ] All other steps from Task 13 applied with the substitutions above.

---

### Task 18: Add `MODE=audit` to `ss-bs-discovering-testing`

Same structure as Task 13 with these substitutions:

**Step 4 substitute — Step 1.6 substeps for testing:**

````markdown
### 1.6a. Drift categories for testing

- **Runner / framework drift.** Doc says "Jest"; current `package.json` shows "Vitest". Evidence: dep diff.
- **Command drift.** Doc's "Run all: pnpm test"; current CI uses `pnpm test:ci`. Evidence: CI file path.
- **Coverage threshold drift.** Doc says "80% gate in CI"; current CI shows 60% or no gate. Evidence: CI file path.
- **Mocking philosophy drift.** Doc says "Mock externals only"; current tests show heavy DB mocking. Evidence: mock-usage count.
- **Category coverage drift.** Doc lists "unit + integration + e2e"; current repo has no `e2e/` directory. Evidence: directory listing.
- **Provenance re-evaluation.** Each suggestion-added category / coverage target / philosophy — has reality caught up?
````

**Skill-specific commit message:** `discovering-testing: add MODE=audit (drift check + Q0)`

- [ ] All other steps from Task 13 applied with the substitutions above.

---

### Task 19: Add `MODE=audit` to `ss-bs-discovering-memory-file`

Same structure as Task 13 with these substitutions:

**Step 4 substitute — Step 1.6 substeps for memory-file:**

````markdown
### 1.6a. Drift categories for memory-file

- **Pointer to deleted file.** A pointer like `[Architecture](docs/ARCHITECTURE.md)` resolves to a missing file. (Overlaps with coherence-check Tier 1; surface here too so the user can fix in audit context.)
- **Convention line contradicted by code.** A convention says "use Pytest" but the code uses Vitest. Evidence: code path.
- **Stale command.** A `## Commands` entry uses a command name no longer present in package.json / Makefile. Evidence: task-runner file path.
- **Glossary section terms out of sync.** The 3-5 highlighted terms in the memory file no longer match the most-frequent glossary terms. Evidence: glossary current state.
- **NEVER/MUST drift.** A NEVER/MUST line that no longer maps to any constitution principle (constitution may have dropped or weakened it). Evidence: constitution diff.
- **Provenance re-evaluation.** Suggestion-added lines or removals carry HTML-comment provenance — re-evaluate whether each is still warranted.
````

**Skill-specific commit message:** `discovering-memory-file: add MODE=audit (drift check + Q0)`

- [ ] All other steps from Task 13 applied with the substitutions above.

---

**Phase 7 complete.** Every discovery skill now supports the audit MODE. The audit coordinator (Phase 8) wires them together.

---

## Phase 8: Audit Coordinator Skill

### Task 20: Create `ss-bs-auditing-project` skill

**Files:**
- Create: `skills/project-bootstrap/ss-bs-auditing-project/SKILL.md`

Spec reference: Section 9.

The audit coordinator re-uses every discovery skill via `MODE=audit, SUGGEST=on`, leads with the coherence check, and commits stage-by-stage. Read the bootstrap coordinator first — the audit coordinator is structurally similar but with key differences (coherence-first, per-stage commits, no config-copy / dir-creation).

- [ ] **Step 1: Read the (Phase 6-updated) bootstrap coordinator as the structural template**

Run: `cat skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md`
Note the sections you'll mirror: Overview, Hard Gates, Checklist, Step-by-step, Common Mistakes, Red Flags. Note the differences you'll diverge on (see Spec Section 9.2).

- [ ] **Step 2: Create the directory**

Run: `mkdir -p skills/project-bootstrap/ss-bs-auditing-project`

- [ ] **Step 3: Author the frontmatter and Overview**

Create `skills/project-bootstrap/ss-bs-auditing-project/SKILL.md`:

```markdown
---
name: ss-bs-auditing-project
description: Use to re-evaluate an already-bootstrapped project for drift, incoherence, and improvement opportunities. Sibling to ss-bs-bootstrapping-project — re-uses the same per-file discovery skills via MODE=audit with SUGGEST=on always. Leads with the cross-artifact coherence check; commits stage-by-stage so the user can accept some changes and decline others. Run cases: quarterly project health checks, post-refactor sweeps, new-contributor onboarding prep, ad-hoc "this doc feels stale" investigations.
---

# Auditing Project

## Overview

You are the coordinator for project audit. You re-evaluate an already-bootstrapped project — drift, incoherence, improvement opportunities. The per-file discovery skills (the seven `ss-bs-discovering-<topic>` skills) are loaded inline in audit mode; you don't reach inside their work, you route to them.

**Audit ≠ bootstrap re-run.** Bootstrap re-run with SUGGEST=on adds missing entries and surfaces suggestions, but doesn't compare the existing artifact against current code state. Audit does — that's the drift check (Step 1.6 per discovery skill). Audit also commits stage-by-stage, so the user can accept some changes and decline others.

**Announce at start:** "I'm using the ss-bs-auditing-project skill to audit your bootstrap artifacts for drift and opportunities."
```

- [ ] **Step 4: Author "What This Skill Doesn't Do" and Hard Gates**

Append:

```markdown
## What This Skill Doesn't Do

- It does NOT bootstrap a project that has no artifacts yet. That's `ss-bs-bootstrapping-project`. Audit's preflight verifies config + ≥1 artifact and redirects if missing.
- It does NOT auto-fix problems in the codebase. Audit suggests changes to documentation; humans make code changes.
- It does NOT bundle commits. Each audited stage is its own commit so the user can accept selectively.
- It does NOT persist a report file. Findings and summary are conversation-only.
- It does NOT maintain multiple memory files (same constraint as bootstrap — one per project).

## Hard Gates

- Do NOT run on an un-bootstrapped project. Preflight (Step 1) hard-gates this.
- Do NOT skip Step 2 (cross-artifact coherence). It drives the per-stage loop's prioritization.
- Do NOT bundle audit changes into one commit. Each stage gets its own commit so the user can accept selectively.
- Do NOT persist the audit report to a file. Conversation-only.
- Do NOT dispatch any discovery skill as a subagent. All seven are loaded inline (same constraint as bootstrap).
- Do NOT run audit on every stage by default. Step 3 asks the user which stages to revisit; respect the choice.
- ALWAYS surface coherence findings verbatim. Do not summarize.
- ALWAYS pass `SUGGEST=on` to every discovery skill invocation (audit's prescriptive-by-default rule).
- ALWAYS use the harness's interactive question tool for Step 3 (scope picker) and per-stage user prompts.
- ALWAYS use the harness's todo/task tool. Build the audit todo list right after Step 2's coherence pass — one todo per chosen stage + final coherence re-check + summary report.
```

- [ ] **Step 5: Author the Checklist**

Append:

````markdown
## Checklist

1. Preflight (verify config + ≥1 artifact; redirect to bootstrap if missing)
2. Cross-artifact coherence pass (Tier 1 — runs FIRST, drives the loop)
3. User picks scope (one of: prioritized fix / user-picks / full audit / report-only)
4. Build the audit todo list (one item per chosen stage + final coherence re-check + summary)
5. Per-stage audit loop: for each picked stage, load discovering-X with `MODE=audit, SUGGEST=on`; commit immediately on stage completion
6. Final coherence re-check
7. Summary report (conversation-only)
````

- [ ] **Step 6: Author Step 1 (Preflight)**

Append:

````markdown
## Step 1: Preflight

### 1a. Verify config exists and validates

```bash
test -f .sublime-skills/config.yml || {
  echo "No bootstrap config at .sublime-skills/config.yml — this project hasn't been bootstrapped."
  echo "Run ss-bs-bootstrapping-project first."
  exit 1
}
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh"
```

If config is missing → halt; redirect user to `ss-bs-bootstrapping-project`. Do NOT auto-invoke bootstrap from here (that would surprise the user — confirm interactively).

If validate-config fails → halt; surface the findings; suggest `ss-bs-bootstrapping-project` re-run to fix config issues (audit cannot proceed against an invalid config).

### 1b. Verify at least one artifact exists

Run `discover-context.sh`; parse the JSON; check that at least one of the 7 paths resolves to an existing file (memory_file path is also checked).

If 0 artifacts exist:

```
Question: "Config exists but no artifacts have been created yet. Audit needs at least one artifact to evaluate. Options:"
  - "Run bootstrap instead (recommended)"
  - "Continue anyway — I'll skip stages with no artifact"
```

On "Run bootstrap instead" → halt; surface the recommendation.
On "Continue anyway" → proceed; per-stage loop will skip stages whose artifact doesn't exist.
````

- [ ] **Step 7: Author Step 2 (Cross-Artifact Coherence Pass)**

Append:

````markdown
## Step 2: Cross-Artifact Coherence Pass

Run the coherence checker:

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/coherence-check.sh"
```

Exit codes are the same as in bootstrap Step 8. Audit's response differs:

| Exit code | Meaning | Action |
|---|---|---|
| `0` | No findings | Surface "Coherence check: PASS (0 findings)." Continue to Step 3 — user may still want a per-stage audit even with clean coherence. |
| `1` | Findings present | Surface ALL findings verbatim (do not summarize). The findings drive Step 3's prioritized-fix option. |
| `2-4` | Config/internal error | Halt; surface; ask user to resolve before re-running audit. |

Coherence findings are CRITICAL/WARNING/INFO per the script's output. Group them by which stage's discovering-X skill would fix them (extract from the `fix:` lines).
````

- [ ] **Step 8: Author Step 3 (User Picks Scope)**

Append:

````markdown
## Step 3: User Picks Scope

```
Question: "How would you like to proceed?"

Options:
  - "Fix the top N coherence findings stage-by-stage (Recommended)" — auto-orders by where findings cluster; covers the stages with the most CRITICAL/WARNING findings first
  - "I'll pick which stages to revisit" — multi-select from the 7 stages
  - "Run a full audit on every stage" — invoke all 7 in audit mode
  - "Skip — I just wanted the report" — exit with the coherence findings as the report
```

Record the chosen stages list. If "Skip", jump to Step 7 (summary report) immediately.

For "Fix the top N":
- If 0 coherence findings, fall back to "I'll pick" (auto-prioritization has nothing to order by).
- Otherwise, the prioritized list is: stages with ≥1 CRITICAL first, then stages with WARNING, then stages with INFO.

For "I'll pick":

```
Question: "Which stages would you like to audit?"
Multi-select from: Constitution / Architecture / Testing / Glossary / Domain / Design / Memory file
(Pre-check stages with coherence findings.)
```
````

- [ ] **Step 9: Author Step 4 (Build the Audit Todo List)**

Append:

````markdown
## Step 4: Build the Audit Todo List

Using the harness's todo/task tool, create one todo per chosen stage + two trailing todos:

1. <Stage 1 from Step 3's chosen list>
2. <Stage 2>
... etc ...
N. Final coherence re-check
N+1. Summary report

Mark each todo `in_progress` when you start it and `completed` when done. Do not batch.
````

- [ ] **Step 10: Author Step 5 (Per-Stage Audit Loop)**

Append:

````markdown
## Step 5: Per-Stage Audit Loop

For each stage in the chosen list, in priority order:

### 5a. Load the discovering-X skill in audit mode

```
Load skill: ss-bs-discovering-<topic>

REPO_ROOT:        <absolute path>
MODE:             audit
SUGGEST:          on    ← always on for audit
EXISTING_CONTENT: <verbatim current artifact content from config'd path>
FILE_PATH:        <config'd path>
```

The skill runs its full audit flow (Step 1 silent scan + Step 1.5 diagnose + Step 1.6 drift check + Step 2 announce + Step 3 Q0 → Q1 → Q1.5 → ... → Step 4 draft + Step 5 refine + Step 6 atomic write).

### 5b. Skill returns one of these outcomes

- `audited (changes made)` — the artifact was updated; FILE_PATH points to the new content
- `audited (no changes)` — drift / diagnose / Q1 produced no updates; the file is byte-identical to before
- `skipped (declined mid-skill)` — user aborted within the skill

### 5c. Commit immediately on `audited (changes made)`

```bash
git add <FILE_PATH>
git commit -m "audit: update <basename of FILE_PATH> — <one-line summary of what changed>"
```

The one-line summary comes from the skill's report: e.g., "declare cross-service boundaries", "fix 2 drift items + 1 suggestion accepted".

### 5d. No commit on `audited (no changes)` or `skipped`

Just record in the audit summary that the stage was reviewed (no changes) or declined.

### 5e. Move to the next todo

Mark the current todo `completed`; move to next.
````

- [ ] **Step 11: Author Step 6 (Final Coherence Re-Check) and Step 7 (Summary Report)**

Append:

````markdown
## Step 6: Final Coherence Re-Check

Re-run `coherence-check.sh`. Compare findings to the Step 2 findings:
- Findings present in Step 2 but NOT in Step 6 — resolved.
- Findings in both — still outstanding (user declined the relevant stage, or the fix didn't address the issue).
- Findings new in Step 6 — introduced by audit changes (rare but possible).

## Step 7: Summary Report (Conversation-Only)

Surface this to the user verbatim (one block):

```
Audit complete.

Stages updated:
- <basename> — <drift items fixed: N, suggestions accepted: M> (committed: <short sha>)
- <basename> — ...

Stages reviewed, no changes:
- <basename> — no drift, 0 suggestions accepted

Stages declined:
- <basename> — user declined to revisit

Coherence check progression:
- Before audit: <N findings (X CRITICAL, Y WARNING, Z INFO)>
- After audit:  <N findings (X CRITICAL, Y WARNING, Z INFO)>
- Resolved: <list>
- Outstanding: <list>
- New: <list, if any>

Next steps:
- The bootstrap config is unchanged (audit doesn't touch config; re-run ss-bs-bootstrapping-project to address any config-level changes).
- Outstanding coherence findings can be addressed by running ss-bs-bootstrapping-project in re-run mode and selecting the relevant stages, OR by running ss-bs-auditing-project again on just those stages.
```

Do NOT persist this report. The user can copy from conversation if they want a record. Do not create any new files at this step.
````

- [ ] **Step 12: Author Common Mistakes and Red Flags**

Append:

```markdown
## Common Mistakes

| Mistake | Fix |
|---|---|
| Running audit on an un-bootstrapped project | Preflight should hard-gate; if it doesn't, fix the preflight — never auto-fall-through to bootstrap |
| Summarizing coherence findings instead of verbatim | Always verbatim — the script's format is the canonical surface |
| Bundling per-stage changes into one commit | Each stage = one commit; user must be able to accept selectively |
| Passing SUGGEST=off in audit mode | Audit is prescriptive-by-default; always SUGGEST=on |
| Auto-invoking bootstrap when preflight fails | Halt and redirect interactively; don't surprise the user |
| Persisting the audit report to docs/.audit-report-*.md | Conversation-only — no file lifecycle |

## Red Flags

- About to dispatch a discovering-X as a subagent → STOP; inline only
- About to write a per-stage commit message that doesn't describe what changed → STOP; the message is the user's audit trail
- About to skip a stage's commit because "the change feels small" → STOP; commit anyway, even tiny changes
- About to combine the coherence re-check into the summary report → STOP; they're separate, run the check before composing the summary
- About to bundle multiple stages' diffs into one commit → STOP; per-stage only
```

- [ ] **Step 13: Structural verification**

```bash
SKILL=skills/project-bootstrap/ss-bs-auditing-project/SKILL.md
test -f "$SKILL" && echo "File: OK" || echo "MISSING FILE"
grep -q "^name: ss-bs-auditing-project" "$SKILL" && echo "Frontmatter: OK" || echo "MISSING"
for s in "## Overview" "## Hard Gates" "## Checklist" "## Step 1: Preflight" "## Step 2: Cross-Artifact Coherence Pass" "## Step 3: User Picks Scope" "## Step 4" "## Step 5: Per-Stage Audit Loop" "## Step 6" "## Step 7: Summary Report" "## Common Mistakes" "## Red Flags"; do
  grep -qF "$s" "$SKILL" && echo "$s: OK" || echo "MISSING $s"
done
grep -q "coherence-check.sh" "$SKILL" && echo "Coherence integration: OK" || echo "MISSING"
grep -q "MODE: *audit\|MODE=audit" "$SKILL" && echo "Audit MODE invocation: OK" || echo "MISSING"
grep -q "Commit immediately\|Per-stage commits" "$SKILL" && echo "Per-stage commits: OK" || echo "MISSING"
```

All lines should print `: OK`.

- [ ] **Step 14: End-to-end manual sanity check on a fixture repo**

This is a manual read-through (no actual Claude session). Create a fixture with the same structure as the Phase 5 coherence tests but ALSO with config and a few existing artifacts. Walk through the skill top-to-bottom mentally. Confirm:
- Preflight hard-gates the no-config case
- Coherence runs FIRST, not last
- Step 3's scope picker is asked before any per-stage work
- Per-stage commits happen in Step 5c
- Summary in Step 7 is conversation-only

- [ ] **Step 15: Commit**

```bash
git add skills/project-bootstrap/ss-bs-auditing-project/
git commit -m "Add ss-bs-auditing-project skill"
```

---

**Phase 8 complete.** The audit coordinator exists and can be invoked. All 7 discovery skills support its audit mode. The end-to-end audit workflow is functional.

---

## Phase 9: Documentation Updates

### Task 21: Update `README.md` with the new skills

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Locate the "Skills" section in README.md**

Run: `grep -n "^## \|^### " README.md | head -30`
Find where existing project-bootstrap skill entries live.

- [ ] **Step 2: Add three new entries**

Add (alphabetized within the existing project-bootstrap group):

```markdown
- **ss-bs-auditing-project** — Re-evaluates an already-bootstrapped project for drift, incoherence, and improvement opportunities. Sibling to ss-bs-bootstrapping-project; re-uses the discovery skills via MODE=audit with SUGGEST=on. Commits stage-by-stage. Run cases: quarterly health checks, post-refactor sweeps, doc-staleness investigations.

- **ss-bs-discovering-memory-file** — Discovers, drafts, and writes the project's agent memory file (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md). Runs last in the bootstrap sequence so it can synthesize pointers to the other six artifacts rather than duplicate them.

- **ss-bs-discovering-testing** — Discovers, drafts, and writes the project's testing convention file at docs/TESTING.md. Scans test directories, runner configs, CI commands, coverage tooling, and mocking patterns; optionally proposes improvements when SUGGEST=on.
```

- [ ] **Step 3: Update existing project-bootstrap skill entries to mention the suggestion-pass capability**

For each existing entry (`ss-bs-bootstrapping-project`, `ss-bs-discovering-constitution`, `ss-bs-discovering-architecture`, `ss-bs-discovering-glossary`, `ss-bs-discovering-domain-model`, `ss-bs-discovering-design`), append a brief mention if not present:

> "Supports an opt-in prescriptive 'suggestion pass' (SUGGEST=on) that flags anti-patterns and missing-but-typically-valuable patterns, cited from evidence."

For `ss-bs-bootstrapping-project` specifically, also mention: "Pipeline now covers 7 artifacts (constitution → architecture → testing → glossary → domain → design → memory file) and runs a cross-artifact coherence check before commit."

- [ ] **Step 4: Add a "Slash commands" entry if any new commands are introduced**

This plan does not add any new slash commands. Skip this step.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "README: document new bootstrap skills and pipeline shape"
```

---

### Task 22: Update `docs/bootstrap.md` narrative

**Files:**
- Modify: `docs/bootstrap.md`

- [ ] **Step 1: Read the existing narrative**

Run: `cat docs/bootstrap.md`
Note: which sections describe the pipeline shape, the per-file loop, the artifact list, the commit flow.

- [ ] **Step 2: Update the artifact list to 7**

Find any place that enumerates "5 convention files" or lists constitution/architecture/glossary/domain/design. Update to enumerate 7: constitution, architecture, **testing**, glossary, domain, design, **memory file**.

- [ ] **Step 3: Add a section describing the suggestion-pass opt-in**

Insert a new subsection (after the existing "What bootstrap does" / equivalent overview, before any per-file detail):

```markdown
## Descriptive vs prescriptive — the suggestion pass

Bootstrap is **descriptive by default**: it captures what the codebase already does and codifies it. With the suggestion-pass opt-in (asked once at the top of the run), it also runs an evidence-grounded prescriptive pass per discovery skill — flagging anti-patterns and missing-but-typically-valuable patterns, each cited from specific file paths or counts in the codebase. The user picks which suggestions to accept; accepted ones land in the artifact with a provenance marker so audit can re-evaluate later.

See `docs/bootstrap-improvements-2026-05-25.md` for the full design.
```

- [ ] **Step 4: Add a section describing the coherence check**

Insert after the suggestion-pass section:

```markdown
## Cross-artifact coherence check

After all 7 stages complete and config is validated, bootstrap runs a structural coherence check across the artifacts. Findings are surfaced verbatim with severity (CRITICAL / WARNING / INFO) and a one-line fix hint. The user decides how to act: address now (loops back into the relevant discovery skills), acknowledge and commit, or expand a finding for details.

Coherence is also the first step of `ss-bs-auditing-project` (the sibling skill for re-evaluating existing projects).
```

- [ ] **Step 5: Add a brief "What audit does differently" section pointing to the audit skill**

Insert at the end of the doc:

```markdown
## Audit — re-evaluating an established project

`ss-bs-auditing-project` is bootstrap's sibling for projects that have been live for a while. Differences from bootstrap re-run:
- Coherence runs FIRST, not last (drives the per-stage loop).
- Suggestion pass is always on (no opt-out — that's why you ran audit).
- Drift detection compares artifact content vs current code state.
- Per-stage commits enable selective acceptance.

Audit shares the same per-file discovery skills via a new `MODE=audit` value.
```

- [ ] **Step 6: Commit**

```bash
git add docs/bootstrap.md
git commit -m "docs/bootstrap.md: narrative update for 7-artifact pipeline + audit"
```

---

### Task 23: Update `docs/CONTEXT-FILES.md` with the two new artifact rows

**Files:**
- Modify: `docs/CONTEXT-FILES.md`

- [ ] **Step 1: Read the existing file**

Run: `cat docs/CONTEXT-FILES.md`
Identify the structure (likely one section per artifact: constitution, architecture, glossary, domain, design; plus the agent memory file).

- [ ] **Step 2: Add a `docs/TESTING.md` section**

Slot between architecture and glossary (matching the pipeline order). Use the same structural pattern as the existing sections. Content per spec Section 7:

```markdown
## 3. `docs/TESTING.md` — the **test strategy** layer

**Owner skill:** `ss-bs-discovering-testing`
**Authority:** Reference for engineers writing new tests; consumed by SDD pipeline when verifying test coverage of new features.

**Should contain:**
- **Test categories** — unit / integration / e2e, with the command and path pattern for each
- **Runner & framework** — name, config path, run command, filtered-run command
- **Coverage** — tool, current %, target %, gated in CI?
- **Mocking philosophy** — one-paragraph rule (mock-as-little-as-possible / externals-only / liberal)
- **Fixtures & factories** — location + pattern
- **Conventions** — file naming, test-per-behavior, setup/teardown

**May contain:**
- CI matrix details (Node versions, OS, sharding)
- Performance budgets per test category
- Flaky test register + retry policy
- Test-data privacy rules

**Should NOT contain:** code conventions unrelated to tests (those go in constitution or memory); per-feature test plans (those live in `docs/specs/`).
```

Note: since this adds a new section in the middle, renumber subsequent existing sections (glossary 3→4, domain 4→5, design 5→6, memory 6→7, ADR 7→8, etc. — whatever the current numbering is).

- [ ] **Step 3: Update the memory-file section to reflect that bootstrap now produces it**

In the existing memory-file section, update "owner" / "trigger" language:

```markdown
**Owner skill (bootstrap / audit):** `ss-bs-discovering-memory-file` — for full draft / refresh during bootstrap or audit
**Owner skill (incremental):** `ss-sdd-maintaining-memory-file` — for incremental additions during SDD feature runs
```

If the existing section doesn't mention bootstrap producing the file, add a "Bootstrap responsibility" note: "The agent memory file is the seventh and final stage of bootstrap. It synthesizes pointers to the other six artifacts."

- [ ] **Step 4: Add a brief paragraph at the top mentioning the 7-artifact pipeline**

If the doc has an introduction, add: "Bootstrap covers 7 artifacts (constitution, architecture, testing, glossary, domain, design, memory file) plus supporting directories (`docs/adr/`, `docs/specs/`)."

- [ ] **Step 5: Commit**

```bash
git add docs/CONTEXT-FILES.md
git commit -m "docs/CONTEXT-FILES.md: add TESTING.md row + update memory-file section"
```

---

**Phase 9 complete.** All documentation reflects the new 7-artifact pipeline, the audit sibling, and the suggestion-pass capability. The implementation is fully shippable end-to-end.

---

## Implementer Self-Review Checklist

After completing all phases, run this final review pass before declaring done:

- [ ] **All 23 tasks are committed** — run `git log --oneline | head -30` and confirm 23+ new commits since this plan was started.
- [ ] **All 7 discovery skills support `SUGGEST=on` AND `MODE=audit`** — for each of the 7 discovery skill SKILL.md files, grep for both: `grep -l "SUGGEST" skills/project-bootstrap/ss-bs-discovering-*/SKILL.md` should list all 7; same for `grep -l "MODE = audit\|MODE=audit" skills/project-bootstrap/ss-bs-discovering-*/SKILL.md`.
- [ ] **Bootstrap end-to-end smoke** — spin up a throwaway fixture repo with a simple package.json + one constitution file, set `$SUBLIME_SKILLS_HOME`, invoke `ss-bs-bootstrapping-project` (via the agent harness), walk through to completion. Verify: opt-in question appears, all 7 stages are walked, coherence runs, single bundled commit lands.
- [ ] **Audit end-to-end smoke** — on the same fixture, invoke `ss-bs-auditing-project`. Verify: preflight passes, coherence runs first, scope picker appears, per-stage commits land (one per stage updated), summary surfaces.
- [ ] **Validator regression** — `./skills/spec-driven-development/framework/validate-config.sh skills/project-bootstrap/scaffolds/config.yml` should pass.
- [ ] **Coherence-check regression** — re-run the 5 fixture tests from Task 11 Step 8. All should produce the expected outputs.
- [ ] **README and docs/ updates land** — `grep -l "ss-bs-discovering-testing\|ss-bs-discovering-memory-file\|ss-bs-auditing-project" README.md docs/bootstrap.md docs/CONTEXT-FILES.md` — should list all three docs.
- [ ] **No broken cross-references** — `grep -rn "ss-bs-discovering-\|ss-bs-auditing-\|ss-bs-bootstrapping-" skills/ docs/ | grep -v "SKILL.md:" | head -50` — visually scan for typos in skill names.








