# Sublime-Skills

A skill family for agent harnesses. Covers spec-driven feature
development, project bootstrap, architecture review, browser automation,
search, and workflow utilities. Designed to be adopted by individuals
and teams alike.

## Structure

Skills are grouped into category directories (e.g. `skills/web-utilities/`). Each
skill lives in its own directory within a category, containing a `SKILL.md`
with YAML frontmatter (`name`, `description`) and instructions. Supporting
files (references, scripts, templates) sit alongside it. A new skill goes
into the category directory that fits it, or a new category if none does.

Every skill must also have a short summary entry in `README.md`, under its
"Skills" section — add one whenever a skill is created or collected, and
keep it current when the skill changes.

## Slash commands

Slash commands live as flat `.md` files under the top-level `commands/`
directory — one file per command, no per-command directory. The filename
(without `.md`) becomes the command name as invoked in Claude Code
(`commands/ss-agile-populate-issues.md` → `/ss-agile-populate-issues`).
Commands are a flat namespace in Claude Code (`~/.claude/commands/<name>.md`),
so they sit at the repo top level rather than nested in category dirs.
Add a short entry in `README.md`'s "Slash commands" section whenever a new
one lands.

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
- One skill, `skills/workflow/restrict-git-commands`, ships a Claude Code-specific
  `PreToolUse` hook script as an optional reference layer. Its primary
  SKILL.md still works via instruction on any harness; the hook is a
  drop-in for users who want deterministic enforcement.

## Multi-step skill families

Where a category contains a coordinated workflow (currently
`skills/spec-driven-development/` and `skills/project-bootstrap/`), the human-readable
explanation lives under `docs/`:

- `docs/bootstrap.md` — one-time project setup pipeline
- `docs/sdd/` — the SDD pipeline (`pipeline.md`, `skills.md`, `artifacts.md`,
  `state-and-config.md`, `operations.md`, `rationale.md`)

The `SKILL.md` files are the operational specs (what the agent executes);
the `docs/` files are the narrative reference. When they disagree, the
`SKILL.md` is authoritative.

## Project-level config

A project that adopts SDD stores its config at `.sublime-skills/config.yml`
(committed; created by `ss-bs-bootstrapping-project` from
`skills/project-bootstrap/scaffolds/config.yml`). An optional sibling
`.sublime-skills/config-local.yml` (gitignored; also created by the
bootstrap, empty by default) acts as a per-developer overlay: any scalar
key set there shadows the matching key in `config.yml` when skills read
config.

All config access goes through the central scripts under
`skills/spec-driven-development/framework/` — `get-config-value.sh` for single
scalars, `discover-context.sh` for bulk paths, `validate-config.sh` for
structural checks. Do not introduce inline YAML parsing in skill files;
extend those scripts instead.

## Script invocation convention

Every script invocation in skill prose — regardless of which category the
script belongs to — must be addressed via `$SUBLIME_SKILLS_HOME`, the env
var that points at this repo's root on the user's machine. Skills assume
the var is exported; they don't try to autodiscover the install path.

Three categories of scripts coexist in the repo; the addressing rule is
uniform across all of them:

| Location | Purpose | Caller |
|---|---|---|
| `scripts/` | Operate Sublime-Skills itself (install, uninstall) | The user, from a terminal |
| `skills/spec-driven-development/framework/` | SDD pipeline internals — config readers, validators | SDD skills, via `$SUBLIME_SKILLS_HOME` |
| `<skill>/scripts/` | Skill-private helpers (e.g. `skills/workflow/restrict-git-commands/scripts/`) | That skill only, or the user copying out |

Canonical invocation patterns:

- First invocation in a SKILL.md or doc:
  `"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/<script>.sh`
  — the `:?` guard makes a missing var fail loudly with a clear message.
- Subsequent invocations in the same file:
  `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/<script>.sh"`
  — plain expansion; the first invocation's guard already gated execution.

Never write `./skills/...`, `skills/...`, `./scripts/...`, or any other
cwd-relative form referencing repo paths —
those forms assume cwd is this repo, which breaks the moment skills are
placed centrally (`~/.claude/skills/`) and run from a user project. The
scripts themselves keep using `$0` + `git rev-parse` internally, so they
need no change; only the invocations from skill prose do.

The setup instructions for `SUBLIME_SKILLS_HOME` and the install/uninstall
scripts live in `docs/SETUP.md`.
