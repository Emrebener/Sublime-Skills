# SDD Shared Scripts

Utility scripts shared across the spec-driven-development skill family.

## `discover-context.sh`

Discovers project convention/context files and existing SDD state files.
Skills call this script once and then `Read` the listed files as needed.

### Run

```bash
./spec-driven-development/scripts/discover-context.sh
```

Outputs JSON. Example:

```json
{
  "repo_root": "/abs/path/to/repo",
  "config": ".sdd/config.yml",
  "constitution": "docs/constitution.md",
  "architecture": "docs/ARCHITECTURE.md",
  "glossary": "docs/GLOSSARY.md",
  "domain": null,
  "design": "docs/DESIGN.md",
  "readme": "README.md",
  "spec_dir": "docs/specs",
  "adr_dir": "docs/adr",
  "adrs": ["docs/adr/0001-jwt-sessions.md", "docs/adr/0002-postgresql.md"],
  "active_states": ["docs/specs/003-user-auth/state.json"]
}
```

### Source of truth: `.sdd/config.yml`

The script reads every path from `.sdd/config.yml` — there is **no auto-fallback search**. If config is missing or a key is null/unset, the corresponding field is `null` in the output. For each configured context path, the script verifies the file exists on disk before returning it; missing files become `null`.

| JSON field | Config key | Notes |
|---|---|---|
| `constitution` | `context.constitution_path` | scalar path or null |
| `architecture` | `context.architecture_path` | scalar path or null |
| `glossary` | `context.glossary_path` | scalar path or null |
| `domain` | `context.domain_path` | scalar path or null |
| `design` | `context.design_path` | scalar path or null |
| `spec_dir` | `paths.spec_dir` | also drives `active_states` lookups |
| `adr_dir` | `paths.adr_dir` | also drives the `adrs` array |
| `readme` | (hardcoded `README.md`) | the one universal location; not configurable |
| `adrs` | — | all `.md` files directly under `<adr_dir>/` |
| `active_states` | — | all `state.json` files at `<spec_dir>/*/state.json` |

### YAML extractor limitations

The script uses a minimal awk-based YAML extractor — handles flat `block: \n  key: value` only. No lists, nested objects beyond one level, anchors, or multi-line block scalars. Sufficient for the singular scalar paths in `.sdd/config.yml`'s `paths:` and `context:` blocks. Skills that need list-typed or multi-line config values parse the YAML themselves.

### Bootstrapping

A project without `.sdd/config.yml` is unbootstrapped — `discover-context.sh` will return null for almost everything. Run `bootstrapping-project` (in the `project-bootstrap` skill family) to scaffold the config; it copies the canonical scaffold at `project-bootstrap/scaffolds/config.yml` verbatim, then walks the user through each convention file.

## Validation Scripts

Each writer skill in the SDD family invokes a validator as part of its
inline self-review step. Validators are intentionally simple bash + grep —
they catch gross format violations, not semantic problems.

### `validate-spec.sh`

```bash
./spec-driven-development/scripts/validate-spec.sh <path-to-spec.md>
```

Checks: required sections, FR-### / SC-### / story priority presence,
duplicate FR / SC ID detection, acceptance scenarios per story, placeholder
patterns, forbidden diagram syntaxes (Mermaid, PlantUML, C4), line-count guard.
Exit 0 on pass, 1 on critical failures (warnings don't fail the exit code).

### `validate-plan.sh`

```bash
./spec-driven-development/scripts/validate-plan.sh <path-to-plan.md>
```

Checks: required sections (Goal, Architecture, Tech Stack, File
Structure, Phases), T### task IDs present, duplicate T### detection,
Requirements traceability per task, `[NO-TDD]` markers have reasons on the
next line, placeholder patterns, forbidden diagram syntaxes, line-count guard.

### `validate-handoff.sh`

```bash
./spec-driven-development/scripts/validate-handoff.sh <path-to-handoff.md>
```

Checks: filename pattern (`YYYY-MM-DD-<kebab>.md`, strips trailing `.tmp` for the
pattern check), required sections, unredacted secret patterns (OpenAI/AWS/GitHub
tokens, JWTs, private keys, URLs with credentials, sensitive env-var
assignments), placeholder patterns, soft length guard. Critical failures here
are most often unredacted secrets — re-run redaction before retrying.

### `validate-config.sh`

```bash
./spec-driven-development/scripts/validate-config.sh [config-path]
```

Validates `.sdd/config.yml` end-to-end. Default path: `<repo-root>/.sdd/config.yml`.

Checks: YAML parses; all six top-level blocks present (`paths`, `context`,
`preflight`, `grill`, `memory_file`, `finishing`); required scalar keys per
block; every `context.<name>_path` is null OR points to an existing file
(orphan paths fail); `finishing.mode` enum membership; numeric and type sanity
on remaining fields; rejection of unknown `context.*_path` keys (catches stale
schema).

Exit codes: `0` PASS, `1` FAIL (findings on stderr, `FAIL:`/`WARN:` prefixed),
`2` config file not found, `3` usage error.

Used by `bootstrapping-project` (fix-and-retry loop after scaffold copy) and
the SDD coordinator's Step 2 halt check. Prefers `python3` + PyYAML for full
YAML parsing; falls back to an awk-based shallow scanner when those aren't
available.

## `get-config-value.sh`

Reads a single scalar value from `.sdd/config.yml`. Intended for skills that
need one or two config values and don't want to inline YAML parsing.

```bash
./spec-driven-development/scripts/get-config-value.sh <block> <key> [config-path]
```

Examples:

```bash
./scripts/get-config-value.sh finishing test_command       # "make test"
./scripts/get-config-value.sh preflight use_worktree       # "true"
./scripts/get-config-value.sh grill question_cap           # "15"
./scripts/get-config-value.sh paths handoff_dir            # "docs/handoff"
```

Exit codes:
- `0` — value found (printed to stdout, no trailing newline)
- `2` — config file missing, or block/key not found
- `3` — usage error

**Limitations:**
- Only handles flat `block: \n  key: value` structures (one level of indent)
- Does NOT handle nested objects, lists, anchors, multi-line block scalars
  (`|`, `>`), references, or comments inside values
- For anything more complex, skills should use a proper YAML parser
  (`yq`, `python -c "import yaml"`, etc.)

For list-typed or multi-line config values (e.g., `finishing.pr_body_template`),
the skill must parse the YAML itself. This helper covers the common case
(single scalar lookup) — it's not a general-purpose YAML library.

## State File Schema

`state-schema.md` and `state-schema.json` are the canonical schema for
`<spec_dir>/<feature_id>/state.json`. Both define exactly the same shape; the
`.md` is human-readable (field tables, lifecycle, worked example) and the
`.json` is JSON Schema Draft 2020-12 for objective validation.

Skills that read or write the state file (sdd-coordinator, inspecting-state,
writing-specs, writing-plans, implementing-plans, testing-implementation,
generating-handoff, receiving-review-findings, finishing-sdd) MUST match this
schema. Drift between a skill's behavior and these files is a bug; fix the
schema files first if the change is intentional, or fix the skill if it
diverged accidentally.

If a JSON Schema validator is available in your environment (`ajv`,
`python -m jsonschema`, etc.), you can validate a state file against the schema
directly:

```bash
# example with python's jsonschema
python -m jsonschema -i docs/specs/003-user-auth/state.json \
  spec-driven-development/scripts/state-schema.json
```

`inspecting-state` performs a structural validation pass; this script-level
check is an additional independent verification.
