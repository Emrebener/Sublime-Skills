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
  "architecture": "ARCHITECTURE.md",
  "context": null,
  "glossary": "docs/GLOSSARY.md",
  "domain": null,
  "context_map": null,
  "readme": "README.md",
  "is_monorepo": false,
  "spec_dir": "docs/specs",
  "adr_dir": "docs/adr",
  "adrs": ["docs/adr/0001-jwt-sessions.md", "docs/adr/0002-postgresql.md"],
  "active_states": ["docs/specs/003-user-auth/state.json"]
}
```

A `null` value means the file does not exist at any default location. `spec_dir` and `adr_dir` reflect the resolved paths after honoring any `.sdd/config.yml → paths.*` overrides; the `adrs` and `active_states` arrays are searches against those resolved directories.

### Default search paths (first match wins)

| Field | Paths checked |
|---|---|
| `constitution` | `docs/constitution.md`, `constitution.md` |
| `architecture` | `ARCHITECTURE.md`, `docs/ARCHITECTURE.md`, `docs/architecture.md` |
| `context` | `CONTEXT.md`, `docs/CONTEXT.md` |
| `glossary` | `GLOSSARY.md`, `docs/GLOSSARY.md`, `docs/glossary.md` |
| `domain` | `DOMAIN.md`, `docs/DOMAIN.md` |
| `context_map` | `CONTEXT-MAP.md`, `docs/CONTEXT-MAP.md` |
| `readme` | `README.md` |
| `adrs` | All `.md` files directly under `<adr_dir>/` (default `docs/adr/`) |
| `active_states` | All `state.json` files at `<spec_dir>/*/state.json` (default `docs/specs/*/state.json`) |

### Overrides

The script reads two path overrides from `.sdd/config.yml → paths.*`:

```yaml
paths:
  spec_dir: docs/features   # affects `spec_dir` and `active_states`
  adr_dir: docs/decisions   # affects `adr_dir` and `adrs`
  handoff_dir: ...           # NOT read here; consumed by generating-handoff directly
```

The script uses a minimal awk-based YAML extractor for these specific keys only. Anything more complex (nested structures, lists, anchors) is parsed by the skills themselves. Override resolution: config value → script default.

Convention-file overrides (`context.constitution_paths`, `context.architecture_paths`, etc.) are honored by individual skills that read the config directly — this script reports only the default-search-path matches.

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

For lists like `context.constitution_paths: [...]`, the skill must parse the
YAML itself. This helper covers the common case (single scalar lookup) — it's
not a general-purpose YAML library.

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
