---
name: ss-bs-discovering-design
description: Use as an INLINE skill (NOT a dispatched subagent) loaded by ss-bs-bootstrapping-project at the design slot. Two interactive paths - Import an existing DESIGN.md (from refero.design / Specify / Tokens Studio / hand-authored) or Build collaboratively via code scan plus targeted user questions. Writes docs/DESIGN.md (or the configured path) atomically.
---

# Discovering Design

## Overview

You are loaded **inline** by `ss-bs-bootstrapping-project` (NOT dispatched as a subagent). Like the four sibling `discovering-*` skills in this family, design isn't well-suited to subagent extraction — the parts that matter most (theme intent, brand vibe, role rules, do's-and-don'ts philosophy) don't live in the code. They live in the user's head. So you stay in the coordinator's context and have a real conversation. Design is unique among the five in one way: it's the only one that also offers an **Import** path (because external tools like refero.design / Specify / Tokens Studio can generate ready-to-use DESIGN.md files); the other four are Build-only.

**Core principle:** Design is taste + code, not code alone. Don't pretend a CSS-grep can substitute for asking the user "what's this color reserved for?" or "what's the vibe?". Conversely, don't ask the user to type out what's already in their CSS — read it, propose it back, confirm.

**Announce at start:** "I'm using the ss-bs-discovering-design skill to set up DESIGN.md."

## When This Skill Runs

The coordinator (`ss-bs-bootstrapping-project`) loads this skill when its per-file loop reaches the design slot. The coordinator has already asked the user one of:

- "Project doesn't have a DESIGN.md yet. Create one?" (file missing → yes/no)
- "DESIGN.md exists. Skip / Extend / Replace?" (file present)

You're invoked when the user picked **Create / Extend / Replace** for design. The coordinator passes you:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, `replace`, or `audit`. Audit invokes the drift-check path (Step 1.6) and the drift-resolution Q0 in Step 3b.
- `EXISTING_CONTENT` — verbatim current DESIGN.md content (only for `extend` / `replace` / `audit`; empty otherwise)
- `FILE_PATH` — target write path (typically `docs/DESIGN.md`; honors `context.design_path` config override if non-default)
- **`SUGGEST`** — `on` or `off`. When `on` AND the Build path is taken, run Step 3a.5 (silent diagnose) and surface Q1.5 in Step 3b. When `off`, skip both — identical to pre-suggestion-pass behaviour. Import path always skips diagnose regardless of this flag. Defaulted by the coordinator from `suggest.default` in config and the opt-in question at bootstrap start. Always `on` in audit mode.

Audit mode primarily applies to artifacts produced via the **Build path** (where tokens, component variants, and provenance markers were written by this skill). If the existing DESIGN.md was produced via the **Import path**, drift detection is limited to "still exists as a file" only — content drift detection requires Build-path provenance markers that Import-path files do not carry.

## Hard Gates

- ALWAYS use the harness's interactive question tool for every yes/no or multi-choice question. Do NOT default to plain-text prompts that force the user to type a free-form answer when a structured choice exists.
- Ask ONE question per turn. Never bundle multiple unrelated questions in a single ask. The user reads one thing, decides one thing, moves on.
- Lead with multi-choice + a recommended option whenever the choice has clear alternatives. Free-form text input is reserved for genuinely open prompts (brand vibe in one sentence, accent-color philosophy, etc.).
- Do NOT use Mermaid, C4, PlantUML, or any other diagram syntax in the proposed DESIGN.md — text only.
- Do NOT propose user journey maps, persona docs, flow diagrams, wireframes, or UX research output. This skill is about the visual design system (tokens + components), not interaction design at the journey level.
- Do NOT propose motion-design or animation specs beyond what's literally in code. Observed `transition: 150ms ease` is OK to note; aspirational "use Lottie for onboarding" is not.
- Do NOT cite external design authorities ("Material says...", "Apple HIG says..."). Describe THIS project, not the design lineage.
- Do NOT invent tokens. If only 3 colors are defined, propose 3 — don't pad with `--color-muted-2`, `--color-muted-3` to look thorough.
- Do NOT skip the Import-vs-Build choice in `create` / `replace` modes. The user may already have a generated DESIGN.md they want to use; asking saves them a wasted Q&A round.
- Do NOT overwrite an existing DESIGN.md in `extend` mode. Extend merges; only `replace` overwrites.
- Do NOT exceed the diagnose budget: Step 3a.5 (when run) takes at most ~2 minutes of agent work and reads at most 10 additional files beyond what Step 3a read. If you need more reads, surface fewer suggestions instead of widening the budget.
- Do NOT surface diagnose candidates without specific file-path or count evidence. Abstract "best practice" suggestions are forbidden.
- Do NOT pad the Q1.5 list to fill a quota. If diagnose finds 0 strong candidates, Q1.5 is skipped silently — this is the correct outcome, not a bug.
- Do NOT use severity MUST for a diagnose candidate unless there is observable harm (broken tests, security risk, observed bug pattern). Weaker evidence defaults to SHOULD or INFO.
- Do NOT run diagnose in the Import path. Import means the user is bringing a pre-existing design file; diagnose would be inappropriate.
- In audit mode, do NOT skip Step 1.6 (drift check). It's the third operation alongside observe and diagnose; without it, audit is just "extend mode with SUGGEST=on".
- In audit mode, ask Q0 questions ONE drift item per question — do NOT bundle. Drift resolutions are nuanced individually.
- In audit mode, SUGGEST is always treated as `on` (regardless of input). This is documented in the Inputs section.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Ask: "Import existing file" vs. "Build         │
│     collaboratively"                                │
│   → Import path:  read user-supplied file → write   │
│   → Build path:                                     │
│       → Step 3a: silent code scan                   │
│       → Step 3a.5: silent diagnose (if SUGGEST=on)  │
│       → Step 3b: targeted questions (Q1, Q1.5 if   │
│                  SUGGEST, Q2+)                      │
│       → Step 3c-e: synthesize → review → write      │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Skip the Import question (extending doesn't     │
│     make sense via import — would just be replace)  │
│   → Build path with EXISTING_CONTENT as starting    │
│     point:                                          │
│       → Step 3a: silent code scan + existing content│
│       → Step 3a.5: silent diagnose (if SUGGEST=on)  │
│       → Step 3b: targeted questions on gaps + Q1.5  │
│       → Step 3c-e: synthesize → review → merge →   │
│                    write                            │
├─────────────────────────────────────────────────────┤
│ MODE = audit                                        │
│   → Step 3a: silent code scan                       │
│   → Step 3a.5: silent diagnose (always on for audit)│
│   → Step 1.6: drift check vs EXISTING_CONTENT       │
│       (Build-path files: full token + variant drift; │
│        Import-path files: file-existence check only) │
│   → Step 2: announce findings + drift + diagnoses   │
│   → Step 3b: Q0 (drift resolution) → Q1.5 → Q2+    │
│   → Step 3c-e: synthesize → review → write          │
└─────────────────────────────────────────────────────┘
```

## Step 1: For Create / Replace — Ask Import vs. Build

Use the question tool with these three options:

```
Question: "How would you like to build DESIGN.md?"

Options:
  - "Import an existing file"
       (Recommended if you've generated one at
        https://styles.refero.design, Specify, Tokens
        Studio, or have a hand-authored doc.)
  - "Build collaboratively from scratch"
       (I'll scan your codebase for tokens and ask
        targeted questions about anything code can't
        tell me.)
  - "Skip — actually, leave this file alone"
       (Bail out; report `skipped` back to the
        coordinator.)
```

For `extend` mode, skip this question and go straight to Step 3 (Build).

On **Skip:** report `skipped (declined mid-skill)` to the coordinator and exit.

## Step 2: Import Path

### 2a. Ask for the file path

```
Question: "What's the full path to the file?"

(Free-form text. Tilde and ~/ expansions are honored.)
```

### 2b. Verify the file

- Path resolves and exists
- File is readable
- File ends in `.md` (or warn if not)
- File is non-empty
- File is plausibly Markdown (starts with `#`, contains at least one `##` heading) — warn but don't block if it isn't

If any check fails, surface the issue and re-ask:

> "I couldn't read `<path>`: <reason>. Try a different path, or switch to building from scratch."

Offer two options at the re-ask: "Try another path" / "Switch to Build mode".

### 2c. Preview to the user

Print the first 60 lines of the file (or the whole file if shorter). After the preview, ask:

```
Question: "Use this file for docs/DESIGN.md?"

Options:
  - "Yes, copy it as-is" (Recommended)
  - "No, let me edit it locally first, then re-import"
  - "Cancel — go back to Import-vs-Build"
```

On "edit locally first": tell the user where to edit, then re-loop to 2a once they're ready.

On "cancel": loop back to Step 1.

### 2d. Atomic write

```bash
cp "$RESOLVED_PATH" "$FILE_PATH.tmp"
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

Report `created via import from <path>` to the coordinator. Done.

## Step 3: Build Path

### 3a. Code scan

Read silently (do NOT narrate every file you open; the user doesn't need a play-by-play). Look for, in priority order:

| Source | What to extract |
|---|---|
| `tailwind.config.{js,ts,cjs}` (v3) | `theme.colors`, `theme.extend.colors`, `theme.fontFamily`, `theme.spacing`, `theme.borderRadius`, `theme.boxShadow` |
| `@theme { ... }` blocks in CSS (Tailwind v4) | `--color-*`, `--font-*`, `--spacing-*`, `--radius-*`, `--shadow-*` declarations |
| Top-level CSS / SCSS / PostCSS files with `:root { ... }` | All `--*` custom properties; group by naming prefix |
| Theme files (`theme.{ts,js}`, `themes/*.ts`, `tokens.{json,ts,css}`, `design-tokens.json`) | Exported token objects |
| `package.json` deps | Detect: `tailwindcss`, `@radix-ui/*`, `@mui/*`, `@chakra-ui/*`, `@mantine/*`, `antd`, `bootstrap`, `styled-components`, `@emotion/*`, `@stitches/react`, `vanilla-extract`, `daisyui`, `panda-css` |
| `components/`, `ui/`, `app/components/`, `src/components/` | Component vocabulary (file/dir names) — confirms canonical set without opening every file |
| `.storybook/` configs and `*.stories.*` files | Variant lists |
| `README.md` and existing `docs/` for "design system" / "style guide" / "tokens" / "theme" mentions | User-authored hints |
| `prefers-color-scheme: dark` media queries, `data-theme` attributes, `dark:` Tailwind variants | Theme mode signals |

If `MODE = extend`: also read `EXISTING_CONTENT` and identify which sections are present, which are missing, and which look stale.

After the scan, compile in-memory:

- `framework`: e.g., `Tailwind v4 + shadcn/ui`, `vanilla CSS custom properties`, `styled-components`, `none`
- `theme_signal`: `light` / `dark` / `both` / `unclear`
- `color_tokens`: list of `(name, value, source-file)` triples
- `typography_signal`: detected font families + weights + sizes
- `spacing_signal`: scale and base unit
- `radius_signal`, `shadow_signal`, `surface_signal`
- `components_detected`: list of component names

Then announce in one short message what you found:

> "Here's what I picked up from the codebase: Tailwind v4 with 19 color tokens defined in `src/styles/globals.css`, Inter Variable + Berkeley Mono, an 8-step border-radius scale, and 9 named shadows. I see shadcn/ui components (Button with 4 variants, Card with 3, Input, Badge). Theme looks dark-mode primary. I'll ask you a handful of questions for the parts code can't tell me, then show you a draft."

If `SUGGEST=on` AND Step 3a.5 produced ≥1 candidate, extend the announcement with: "…and I noticed a few design-system gaps worth documenting — I'll surface those after we confirm the observed tokens."

If `MODE=audit`: "Audit mode. Scan + diagnose + drift check complete. Found N drift items (X token changes, Y variant drift, Z provenance re-evaluations) — I'll surface those first in the questions, then walk through observed candidates and suggestions as usual." If the existing file appears Import-path provenance (no markers found), add: "The existing DESIGN.md appears to have been imported rather than built — full token drift detection isn't available. I checked that the file still exists and will proceed with a fresh scan-based review."

If the scan turns up almost nothing (no framework, no custom properties, no components dir), say so:

> "I didn't find a design framework or token system in this codebase. Three possible reasons: (a) the project doesn't have a UI yet, (b) the UI is upstream / in a different repo, (c) the design system isn't formalized yet. I can still build a DESIGN.md from your answers if you'd like, but if there's no UI surface here, Skip is probably right."

Offer a choice: "Continue (I'll ask everything)" / "Skip (no UI surface)" / "Let me point you to where the UI actually lives" (which routes back to Step 2a as an Import-style flow).

### 3a.5: Silent Diagnose (only if `SUGGEST=on` and Build path was taken)

If `SUGGEST=off`, skip this step entirely and proceed to Step 3b.

Diagnose looks for design-system anti-patterns and missing-but-typically-valuable structural decisions. Every diagnose finding must be **evidence-cited** with specific file paths or concrete counts. Abstract "best practice" suggestions are not allowed.

#### 3a.5a. Design diagnose categories

For each category below, scan additional files if needed (within the budget — see Hard Gates). Scan each category for candidates. One strong candidate per category is the target; the aggregate cap of 5 is enforced in 3a.5b after dropping unsupported candidates.

- **Hex literals scattered through CSS.** ≥10 unique hex color literals across CSS/SCSS files with no central `:root` custom-properties block defining a palette. Evidence: file paths + a sample of the literals.
- **Inconsistent spacing (no scale).** Padding/margin values across components use ≥6 distinct numeric values not on any consistent scale (4/8/12/16 or 4/8/16/24 are common). Evidence: file paths + the values.
- **Only literal colors, no semantic roles.** Code uses raw hex values like `#3B82F6` directly in components instead of semantic tokens (`var(--color-primary)`). Evidence: file paths + raw-hex occurrence count.
- **Component variants in code but absent from doc.** A component (button, input) has 4+ distinct variants in code (variant="primary"|"secondary"|...) but no design doc mentions them. Evidence: component file + variant list.

#### 3a.5b. Compile candidate suggestions in memory

Each candidate must include:
- `severity`: one of `MUST`, `SHOULD`, `INFO` — see Hard Gates for the matching evidence bar
- `title`: one-line headline (e.g., "Centralize hex literals into CSS custom properties")
- `evidence`: specific file paths or counts (e.g., `src/components/Button.tsx:12, .../Card.tsx:8, .../Badge.tsx:5`)
- `proposed_addition`: exact markdown text to add to the artifact (a new token section, a new component variant block, etc.)

Drop any candidate that cannot be cited with specific evidence. Drop any candidate where the severity guess cannot be justified from the evidence (no MUST without observable harm).

If more than 5 candidates remain after dropping unsupported ones, rank by:
1. Severity (MUST > SHOULD > INFO)
2. Evidence count (more file paths / higher counts = stronger)
3. Impact (changes that prevent bugs > changes that improve consistency)

Surface the top 5. If 0 candidates remain, the candidate list is empty and Q1.5 in Step 3b is skipped silently.

## Step 1.6: Drift Check (only if `MODE=audit`)

Compare each documented token, component variant, and provenance entry in `EXISTING_CONTENT` against current code state. The goal is to detect entries that have gone stale.

**Scope rule:** Full drift detection requires Build-path provenance. If the file carries no provenance markers and appears to have been produced via Import path, limit the check to: "Does `FILE_PATH` still exist on disk?" If the file is gone, that is the only drift finding. Announce this scope limitation in Step 2.

### 1.6a. Drift categories for design

For each design-doc entry, check:

- **Token value drift.** Doc says `--color-primary: #3B82F6`; current CSS shows `#2563EB` or the variable no longer exists. Evidence: CSS file paths.
- **Token deleted.** A documented token has no occurrences in CSS / Tailwind config. Evidence: grep count.
- **New token undocumented.** A new `--color-*`, `--space-*`, or `--font-*` variable exists in CSS but isn't in DESIGN.md. Evidence: file paths.
- **Component variants drift.** Doc lists Button variants `{primary, secondary, danger}`; component shows `{primary, secondary, danger, ghost, link}`. Evidence: component file path.
- **Provenance re-evaluation.** Each suggestion-added token or rule — has the codebase converged on it?
  - If the original evidence pattern is STILL present, the suggestion is still aspirational — flag as INFO drift "still not enforced after N days".
  - If the original evidence pattern is GONE (the code has changed to match the aspiration), flag as INFO drift "aspiration met — provenance marker can be removed and entry promoted to normal".

### 1.6b. Compile drift findings in memory

Each finding: `kind` (token-value-changed / token-deleted / token-added / variant-drift / aspiration-met / aspiration-still-pending), `entry` (the doc text being challenged), `evidence` (file paths showing the current code state).

No cap on drift findings — every observable drift is surfaced. The user resolves each in Q0.

### 3b. Targeted questions

Ask only what code can't tell you. Skip questions where the code has already answered. One question per turn, multi-choice with a recommended option whenever possible.

The full question library — pick the relevant subset based on the scan:

**Q0 — Drift Resolution (only if `MODE=audit` AND Step 1.6 produced ≥1 drift finding)**

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

Record each resolution. Apply during Step 3c (Synthesize).

**Vibe / theme intent**

```
Question: "In one short sentence, what's the vibe of this design system?"

Free-form text. Examples to prime:
  - "Midnight Command Center — dark, focused, precise"
  - "Friendly and approachable — warm tones, soft edges"
  - "Editorial and quiet — generous whitespace, classic type"
  - "Default web — no strong identity yet"
```

(Skip if README already describes the project's design intent in a single line.)

**Theme mode (only if ambiguous from scan)**

```
Question: "Which theme(s) does the system target?"

Options:
  - "Dark only"
  - "Light only"
  - "Both (with user toggle or system-aware)"
  - "Not sure — I'll decide later"
```

**Accent color role (one per detected accent)**

For each non-neutral color the scan flagged as an accent:

```
Question: "I see `--color-neon-lime` (#e4f222) in the codebase. What's
its role?"

Options:
  - "Primary action / CTA — reserved for one purpose"
  - "Brand identity color — appears in logos, hero, accents"
  - "Status color (success / warning / etc.)"
  - "Decorative — no strict rule"
  - "Other (type it)"
```

(Cap at 5 questions of this shape — don't grill the user about every shade in a 20-color palette.)

**Typography intent**

```
Question: "Is Inter Variable the canonical primary face, or a temporary
default you might swap?"

Options:
  - "Canonical — locked in"
  - "Temporary — likely to change"
  - "Not sure"
```

(Only ask if there's reasonable doubt — e.g., the font is the JavaScript ecosystem default and isn't explicitly imported by name in source.)

**Component vocabulary (only if the components-dir scan was ambiguous)**

```
Question: "Which of these should land in DESIGN.md's Components section?"

Multi-select:
  - Button (primary, ghost, link, icon)
  - Card (default, elevated, nested)
  - Input (text, search)
  - Badge
  - Dialog / Modal
  - Toast / Alert
  - Navigation items
  - All of the above (Recommended)
```

**Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND Step 3a.5 produced ≥1 candidate)**

```
Question: "Here are some things I'd suggest adding even though they're
not currently codified. These are opinionated — pick any you want to
include:"

Options (multi-select, one option per Step 3a.5 candidate, plus a "None" escape):
  - [suggestion · <severity> · <evidence-summary>] <title>
    Evidence: <evidence>
    Proposed addition: <one-line summary of proposed_addition>
  - ... (one option per remaining candidate, up to 5)
  - "None of these — keep the design doc descriptive only"

Use the harness's multi-select question tool. Do not present as plain text.
```

If the user picks none, treat as "no suggestions accepted" and proceed to the next question. Accepted suggestions are carried into Step 3c (Synthesize) and rendered with provenance markers.

**Do's and don'ts (the philosophy layer)**

```
Question: "Are there one or two rules about THIS project's design that
you wish every contributor knew on day one?"

Free-form text. Examples to prime:
  - "Neon Lime is reserved for primary CTAs — never decorative"
  - "All cards use 6px radius — no exceptions"
  - "Dark backgrounds only — no white surfaces anywhere"
```

(This is the highest-value question — capture verbatim.)

**Imagery / illustration style (if observed evidence is sparse)**

```
Question: "Does this product use illustration / photography, or is it
strictly UI screenshots + icons?"

Options:
  - "UI screenshots + minimal icons (Recommended)"
  - "Illustrated — has a defined illustration style"
  - "Photography-led"
  - "Skip this section"
```

### 3c. Synthesize the draft

Compose a Markdown draft using the scan results + question answers. Section order (omit any section with no evidence + no answer):

1. **Title + one-line vibe** (from the vibe question)
2. **Theme** (light / dark / both / system-aware)
3. **Tokens — Colors** (table: name, value, token, role)
4. **Tokens — Typography** (font families with weights + scale)
5. **Tokens — Spacing & Shapes** (spacing scale, border radius, shadows)
6. **Surfaces** (only if a layered system exists)
7. **Components** (each with a one-line role + the tokens it uses)
8. **Do's and Don'ts** (the rules section — from the dos/donts question, augmented by usage patterns the scan revealed)
9. **Imagery** (if discussed)
10. **Layout** (only if page-level structure was evident from layout components)
11. **Quick Start** (CSS custom properties block, plus a Tailwind `@theme` block if Tailwind is in use)

Accepted Q1.5 suggestions are woven into the appropriate sections above and rendered with provenance markers (see Provenance markers subsection in Step 3e below). **The provenance markers must appear in the draft shown to the user at this Step 3c**, not added silently at Step 3e write time — the user reviews and approves the full content including provenance.

In audit mode, also incorporate Q0 drift resolutions:
- **Update doc to match code** — revise the relevant token value, variant list, or section to reflect current code state.
- **Keep doc** — leave the entry unchanged; annotate if helpful (e.g., "code diverged; expected to be fixed").
- **Remove entry** — delete the outdated token, variant, or section.
- **Clarify scope** — split the entry as the user described.
- **Promote to normal** (provenance re-evaluation) — remove the provenance blockquote / comment from the entry.
- **Keep aspirational; refresh date** — update the `YYYY-MM-DD` in the provenance marker to today's date.
- **Drop aspirational entry** — remove the section entirely.

Drafting guidelines:

- Omit sections with no evidence. A 4-section DESIGN.md is fine.
- Color table rows: name, hex (or whatever format source uses), token slug, one-line role. If the user's role answer was "Other (type it)", quote that text.
- Component descriptions: one sentence each. No code snippets longer than 2-3 lines.
- Quote the user's "vibe" sentence verbatim as the file's subtitle.
- Quote the user's "rules I wish everyone knew" verbatim in Do's and Don'ts.

### 3d. Show the draft and refine

Print the draft to the user. Then ask:

```
Question: "How does this look?"

Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip this file"
```

On **Tweak:** free-form text from the user; apply the changes; re-show; re-ask. Cap at **3 tweak iterations** before surfacing:

> "We've done three rounds and the draft still isn't matching what you want. Want to (a) keep the current draft anyway, (b) skip DESIGN.md for now, or (c) supply a file via the Import path instead?"

On **Start over:** restart Step 3 from the question loop with the user's answers carrying over; you don't need to re-scan code.

On **Abort:** report `skipped (declined mid-skill)` to the coordinator and exit.

### 3e. Atomic write

```bash
# Write to .tmp, then atomic mv
cat > "$FILE_PATH.tmp" <<EOF
<draft content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

For **`extend` mode:** the merged content (existing + new sections + refined existing sections) is what gets written, not just the additions. Splice carefully — don't duplicate headings.

Report to the coordinator one of:

- `created via build` (mode = create, full draft written)
- `extended via build` (mode = extend, merged content written)
- `replaced via build` (mode = replace, full draft written)
- `skipped (declined mid-skill)` (user aborted partway)

### Provenance markers for accepted Q1.5 suggestions

Accepted Q1.5 suggestions are rendered with provenance markers so that audit passes can recognize them. Design tokens use HTML comments (renders cleanly inside token blocks); component variant blocks use a three-line italic blockquote.

**Token sections** — append a provenance block immediately after the section heading and before the token table:

```markdown
## Tokens — Colors

<!-- provenance: added via bootstrap suggestion pass YYYY-MM-DD -->
<!-- evidence: <evidence summary> -->

### Primary · `--color-primary`
- Default: `#3B82F6` (blue-500)
- Hover: `#2563EB`
```

**Component variant blocks** — prepend a three-line blockquote immediately after the component heading:

```markdown
## Components

> _Added via bootstrap suggestion pass (YYYY-MM-DD)._
> _Evidence: <evidence summary>._
> _Component variants observed in code but previously undocumented._

### <Component Name>

...
```

Replace `YYYY-MM-DD` with today's date. The audit skill reads these markers on re-runs to ask whether gaps have since been addressed.

## Output Template

For reference, the canonical DESIGN.md skeleton. Use as a guide, omit empty sections, fill from scan + answers.

```markdown
# Design System

> <One-line vibe — verbatim from the user's vibe answer>

**Theme:** <dark | light | both | system-aware>

<Optional 1-2 sentence intro setting tone. Skip if the vibe line says enough.>

## Tokens — Colors

| Name | Value | Token | Role |
|------|-------|-------|------|
| <Name> | `<hex>` | `--color-<name>` | <one-line role> |

## Tokens — Typography

### <Font Name> · `--font-<slug>`
- **Substitute:** <fallback chain>
- **Weights:** <used weights only>
- **Sizes:** <sizes used in source>
- **Role:** <primary UI / monospace / display / etc.>

### Type Scale

| Role | Size | Line Height | Letter Spacing | Token |
|------|------|-------------|----------------|-------|

## Tokens — Spacing & Shapes

**Base unit:** <Npx>

### Spacing Scale
| Name | Value | Token |
|------|-------|-------|

### Border Radius
| Element | Value |
|---------|-------|

### Shadows
| Name | Value | Token |
|------|-------|-------|

## Surfaces

<Omit if no explicit surface system.>

| Level | Name | Value | Purpose |
|-------|------|-------|---------|

## Components

### <Component Name>
**Role:** <one-line>

<2-3 sentences with the token names used.>

## Do's and Don'ts

### Do
- <Rule — verbatim from the user, then ones inferred from usage>

### Don't
- <Rule — verbatim from the user, then ones inferred by absence>

## Layout

<Optional. Page-level structure if visible from layout components.>

## Imagery

<Optional. Style direction from the imagery question.>

## Quick Start

### CSS Custom Properties

```css
:root {
  /* Generated from extracted tokens */
}
```

### Tailwind v4 (only if Tailwind is in use)

```css
@theme {
  /* ... */
}
```
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the Import-vs-Build choice in create/replace mode | Always offer Import first — the user may have a generated file ready |
| Asking everything even when code has the answer | Read first, ask second; only ask what code can't reveal |
| Bundling multiple questions in one ask | One question per turn, structured choices when possible |
| Inventing tokens to "round out" the palette | Propose only what's in the code; if there are 3 colors, propose 3 |
| Citing external design authorities ("Material says...") | Describe THIS project; the lineage is irrelevant |
| Adding user journey maps or persona docs | Out of scope; visual design system only |
| Adding accessibility recommendations beyond what's evident | Defer to a future a11y document |
| Asking "what's the brand vibe" five times in different words | One question per topic; if the user said "minimal Nordic dark", stop probing |
| Looping past 3 tweak iterations | Surface to user with bail options |
| Overwriting in extend mode | Extend merges; only replace overwrites |
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest |
| Forgetting the provenance marker on an accepted Q1.5 suggestion | Audit relies on the marker to recognize bootstrap-added entries; without it, drift detection breaks |
| Running Step 3a.5 when SUGGEST=off | Skip Step 3a.5 entirely when off; do not run-but-suppress |
| Skipping Step 1.6 in audit mode | Drift detection is the audit's reason for existing |
| Bundling Q0 drift resolutions into one multi-select | Each item gets its own question — resolutions are not collectively decidable |
| Forgetting to refresh the provenance marker date when "Keep aspirational" is chosen | Audit needs the refresh to track time-since-last-evaluation |
| Forgetting to strip the provenance marker when "Promote to normal" is chosen | The marker is the audit's hook; promoting means removing it |

## Red Flags

- About to ask the user a question without using the question tool → STOP; use the structured ask
- About to ask two questions in one turn → STOP; split them
- About to start writing the file before showing a draft → STOP; show first, write second
- About to dispatch a subagent → STOP; you're inline, you do the work
- About to add a journey map → STOP; out of scope
- About to write "use animations to delight users" → STOP; describe code, not aspiration
- About to copy Material Design / HIG verbatim → STOP; describe THIS project
- About to import a file without previewing it to the user → STOP; preview, then confirm
- About to invent a token name not in the code → STOP; only document what exists or what the user explicitly named
- About to loop into a 4th tweak round → STOP; surface bail options
- About to overwrite an existing DESIGN.md in extend mode → STOP; merge

## Why This Skill Is Inline (Not a Subagent)

A subagent dispatch returns once and dies — it can't have a real conversation with the user. Design needs sustained back-and-forth: theme intent, brand vibe, role rules, and do's-and-don'ts don't live in the code; they live in the user's head, and they have to be drawn out one question at a time. So this skill stays inline.

The four sibling skills (`ss-bs-discovering-constitution`, `ss-bs-discovering-architecture`, `ss-bs-discovering-glossary`, `ss-bs-discovering-domain-model`) follow the same pattern for the same reason — each mixes code-derivable signal with user-held intent. Design is the only one with an additional **Import** path (because external tools like refero.design / Specify / Tokens Studio can generate ready-to-use DESIGN.md files); the other four are Build-only.
