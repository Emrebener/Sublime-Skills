# SDD Framework

Shared utility scripts and the canonical state-file schema for the spec-driven-development skill family. The scripts live here alongside `state-schema.md` / `state-schema.json` (the human-readable + machine-readable schema pair) because they're all framework internals consumed by the skills.

## `discover-context.sh`

Discovers project convention/context files and existing SDD state files.
Skills call this script once and then `Read` the listed files as needed.

### Run

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/discover-context.sh"
```

Outputs JSON. Example:

```json
{
  "repo_root": "/abs/path/to/repo",
  "config": ".sublime-skills/config.yml",
  "config_local": ".sublime-skills/config-local.yml",
  "constitution": "docs/CONSTITUTION.md",
  "architecture": "docs/ARCHITECTURE.md",
  "glossary": "docs/GLOSSARY.md",
  "domain": null,
  "design": "docs/DESIGN.md",
  "readme": "README.md",
  "spec_dir": "docs/specs",
  "adr_dir": "docs/adr",
  "adrs": ["docs/adr/0001-jwt-sessions.md", "docs/adr/0002-postgresql.md"],
  "active_state": ".sublime-skills/state.json"
}
```

### Source of truth: `.sublime-skills/config.yml` + `config-local.yml`

Context paths are read from `.sublime-skills/config.yml`, with `.sublime-skills/config-local.yml` overlaid per-key when present (overlay wins). There is **no auto-fallback search**. If both files are missing or a key is null/unset in both, the corresponding field is `null` in the output. For each configured context path, the script verifies the file exists on disk before returning it; missing files become `null`. `spec_dir` and `adr_dir` are fixed constants (`docs/specs` and `docs/adr` respectively) — they are emitted for debugging convenience, not read from config.

| JSON field | Config key | Notes |
|---|---|---|
| `constitution` | `context.constitution_path` | scalar path or null |
| `architecture` | `context.architecture_path` | scalar path or null |
| `glossary` | `context.glossary_path` | scalar path or null |
| `domain` | `context.domain_path` | scalar path or null |
| `design` | `context.design_path` | scalar path or null |
| `spec_dir` | fixed at `docs/specs` — emitted for debugging only | spec output directory for SDD artifacts |
| `adr_dir` | fixed at `docs/adr` — emitted for debugging only | also drives the `adrs` array |
| `readme` | (hardcoded `README.md`) | the one universal location; not configurable |
| `adrs` | — | all `.md` files directly under `docs/adr/` |
| `active_state` | — | path to `.sublime-skills/state.json` if it exists, else `null` |
| `config_local` | — | path to `.sublime-skills/config-local.yml` if present, else null |

### YAML extractor limitations

Scalar `context.*_path` reads are delegated to the sibling `get-config-value.sh`, which is the single source of truth for both YAML extraction and overlay (`config-local.yml` shadows `config.yml`) semantics. Its extractor is awk-based and handles flat `block: \n  key: value` only — no lists, no nested objects beyond one level, no anchors, no multi-line block scalars. Sufficient for the singular scalar paths in `.sublime-skills/config.yml`'s `context:` block. Skills that need list-typed or multi-line config values parse the YAML themselves.

### Bootstrapping

A project without `.sublime-skills/config.yml` is unbootstrapped — `discover-context.sh` will return null for almost everything. Run `ss-bs-bootstrapping-project` (in the `project-bootstrap` skill family) to scaffold the config; it copies the canonical scaffold at `skills/project-bootstrap/scaffolds/config.yml` verbatim, then walks the user through each convention file.

## Validation Scripts

Each writer skill in the SDD family invokes a validator as part of its
inline self-review step. Validators are intentionally simple bash + grep —
they catch gross format violations, not semantic problems.

### `validate-spec.sh`

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-spec.sh" <path-to-spec.md>
```

Checks: required sections, FR-### / SC-### / story priority presence,
duplicate FR / SC ID detection, acceptance scenarios per story, placeholder
patterns, forbidden diagram syntaxes (Mermaid, PlantUML, C4), line-count guard.
Exit 0 on pass, 1 on critical failures (warnings don't fail the exit code).

### `validate-plan.sh`

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-plan.sh" <path-to-plan.md>
```

Checks: required sections (Goal, Architecture, Tech Stack, File
Structure, Phases), T### task IDs present, duplicate T### detection,
Requirements traceability per task, `[NO-TDD]` markers have reasons on the
next line, placeholder patterns, forbidden diagram syntaxes, line-count guard.

### `validate-handoff.sh`

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-handoff.sh" <path-to-handoff.md>
```

Checks: filename pattern (`YYYY-MM-DD-<kebab>.md`, strips trailing `.tmp` for the
pattern check), required sections, unredacted secret patterns (OpenAI/AWS/GitHub
tokens, JWTs, private keys, URLs with credentials, sensitive env-var
assignments), placeholder patterns, soft length guard. Critical failures here
are most often unredacted secrets — re-run redaction before retrying.

### `validate-config.sh`

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh" [config-path]
```

Validates `.sublime-skills/config.yml` end-to-end. Default path: `<repo-root>/.sublime-skills/config.yml`. If a sibling `.sublime-skills/config-local.yml` exists, it's overlaid onto the base config per-key and validation runs against the merged result.

Checks: YAML parses (both files); all four top-level blocks present in the base
(`context`, `branching`, `grill`, `memory_file`); required scalar
keys per block in the merged result; every `context.<name>_path` is null OR
points to an existing file (orphan paths fail); numeric and type sanity on
remaining fields; rejection of unknown `context.*_path` keys (catches stale
schema). The overlay is additionally checked for unknown blocks and unknown
keys; findings sourced from it are prefixed with `config-local.yml:`.

Empty (zero-byte) `config-local.yml` is treated as "no overrides."

Exit codes: `0` PASS, `1` FAIL (findings on stderr, `FAIL:`/`WARN:` prefixed),
`2` config file not found, `3` usage error.

Used by `ss-bs-bootstrapping-project` (fix-and-retry loop after scaffold copy) and
by `ss-sdd-preflight` (Stage 0 of the SDD pipeline; HALT on non-zero
exit). Prefers `python3` + PyYAML for full
YAML parsing + overlay merge; falls back to an awk-based shallow scanner when
those aren't available (the fallback validates base config only and emits a
`WARN` if `config-local.yml` exists).

## `get-config-value.sh`

Reads a single scalar value from the layered config. `config-local.yml` is consulted first; if the key is present there (including as `null`), that value wins. Otherwise the read falls through to `config.yml`. Intended for skills that need one or two config values and don't want to inline YAML parsing.

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" <block> <key> [config-path]
```

Examples:

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" branching branch_pattern     # "feat/{short-name}"
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" grill question_cap           # "15"
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" memory_file character_limit  # "40000"
```

Exit codes:
- `0` — value found (printed to stdout, no trailing newline)
- `2` — config file missing, or block/key absent in both layers
- `3` — usage error

**Limitations:**
- Only handles flat `block: \n  key: value` structures (one level of indent)
- Does NOT handle nested objects, lists, anchors, multi-line block scalars
  (`|`, `>`), references, or comments inside values
- For anything more complex, skills should use a proper YAML parser
  (`yq`, `python -c "import yaml"`, etc.)

For list-typed or multi-line config values, the skill must parse the YAML
itself. This helper covers the common case (single scalar lookup) — it's not
a general-purpose YAML library.

## State File Schema

`state-schema.md` and `state-schema.json` are the canonical schema for
`.sublime-skills/state.json` (the single global, gitignored state file).
Both define exactly the same shape; the
`.md` is human-readable (field tables, lifecycle, worked example) and the
`.json` is JSON Schema Draft 2020-12 for objective validation.

Skills that read or write the state file (ss-sdd-coordinator, ss-sdd-writing-specs,
ss-sdd-writing-plans, ss-sdd-implementing-plans, ss-sdd-testing-implementation, ss-sdd-generating-handoff,
ss-sdd-receiving-review-findings, ss-sdd-finishing) MUST match this schema. Drift
between a skill's behavior and these files is a bug; fix the schema files
first if the change is intentional, or fix the skill if it diverged
accidentally.

If a JSON Schema validator is available in your environment (`ajv`,
`python -m jsonschema`, etc.), you can validate a state file against the schema
directly:

```bash
# example with python's jsonschema
python -m jsonschema -i .sublime-skills/state.json \
  spec-driven-development/framework/state-schema.json
```

The schema files are the contract; running a JSON Schema validator against a
state file is the most reliable check for drift.
