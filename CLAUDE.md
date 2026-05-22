# Sublime-Skills

A skill family for agent harnesses. Covers spec-driven feature
development, project bootstrap, architecture review, browser automation,
search, and workflow utilities. Designed to be adopted by individuals
and teams alike.

## Structure

Skills are grouped into category directories (e.g. `web-utilities/`). Each
skill lives in its own directory within a category, containing a `SKILL.md`
with YAML frontmatter (`name`, `description`) and instructions. Supporting
files (references, scripts, templates) sit alongside it. A new skill goes
into the category directory that fits it, or a new category if none does.

Every skill must also have a short summary entry in `README.md`, under its
"Skills" section — add one whenever a skill is created or collected, and
keep it current when the skill changes.

## Tool-agnostic authoring

Skills target any agent harness, not a specific one. When writing or
editing skill content:

- Use neutral phrasing for runtime mechanisms: "the harness's todo/task
  tool", "the harness's interactive question tool", "dispatch a fresh
  subagent", "load via your harness's skill mechanism".
- Do NOT prescribe specific tool names. No `TodoWrite`, `AskUserQuestion`,
  `Task` / `Agent` / `Skill` tool, no `subagent_type=general-purpose`, no
  naming `Read` / `Edit` / `Bash` tools by their harness-specific labels.
- Factual mappings (e.g., "CLAUDE.md — Claude Code's preferred name" in
  the memory-file conventions table) and factual data patterns (e.g.,
  OpenAI / Anthropic API key shapes in redaction rules, `OPENAI_*` /
  `ANTHROPIC_*` env-var examples) are fine when they help users identify
  their file or recognize a pattern — that's documentation, not
  prescription.
- One skill, `workflow/restrict-git-commands`, ships a Claude Code-specific
  `PreToolUse` hook script as an optional reference layer. Its primary
  SKILL.md still works via instruction on any harness; the hook is a
  drop-in for users who want deterministic enforcement.

## Multi-step skill families

Where a category contains a coordinated workflow (currently
`spec-driven-development/` and `project-bootstrap/`), the human-readable
explanation lives under `docs/`:

- `docs/bootstrap.md` — one-time project setup pipeline
- `docs/sdd/` — the SDD pipeline (`pipeline.md`, `skills.md`, `artifacts.md`,
  `state-and-config.md`, `operations.md`, `rationale.md`)

The `SKILL.md` files are the operational specs (what the agent executes);
the `docs/` files are the narrative reference. When they disagree, the
`SKILL.md` is authoritative.

## Project-level config

A project that adopts SDD stores its config at `.sublime-skills/config.yml`
(committed; created by `bootstrapping-project` from
`project-bootstrap/scaffolds/config.yml`). An optional sibling
`.sublime-skills/config-local.yml` (gitignored; also created by the
bootstrap, empty by default) acts as a per-developer overlay: any scalar
key set there shadows the matching key in `config.yml` when skills read
config.

All config access goes through the central scripts under
`spec-driven-development/scripts/` — `get-config-value.sh` for single
scalars, `discover-context.sh` for bulk paths, `validate-config.sh` for
structural checks. Do not introduce inline YAML parsing in skill files;
extend those scripts instead.
