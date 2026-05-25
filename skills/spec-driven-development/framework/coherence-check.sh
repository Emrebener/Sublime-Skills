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
