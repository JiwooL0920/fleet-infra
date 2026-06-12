# Content Automation: Blog Posts and Homelab Docs

This document covers the two local automation scripts that keep content in
[jiwool0920.github.io](https://github.com/JiwooL0920/jiwool0920.github.io) in sync
with changes in this repo. Both scripts use your local `opencode` installation and
open cross-repo PRs via `gh` — no CI, no secrets, no auto-merge.

---

## Overview

| Command | What it does | When to run |
|---------|-------------|-------------|
| `make insight-draft SVC=<slug>` | AI-drafts prose fields of `service-insights/<slug>.yaml` | After adding a service or doing an architecture refactor |
| `make insight-draft-all` | Drafts all stubs that still have TODO placeholders | One-time bootstrap after adding many services |
| `make docs-gen` | Local preview: catalog → render → validate → `docs-output/` | Inspect rendered pages before publishing |
| `make update-docs` | Full pipeline + sync to blog repo + open PR | After insight YAML is ready to publish |
| `make blog-draft` | Generates a blog post from recent commits and opens a PR | After a notable infra change lands on develop |

**You always merge manually.** The workflow enforces the GitOps principle: AI drafts,
human reviews, CI deploys on merge.

---

## Component Docs pipeline

### Architecture

```mermaid
flowchart TD
    subgraph fleet["fleet-infra repo (source of truth)"]
        manifests["apps/base/&lt;svc&gt;/\nbase/services/&lt;svc&gt;.yaml\nclusters/stages/**/environment.env"]
        catalog_py["catalog.py"]
        catalog_json["service-catalog.json\n(chart, version, env vars,\ndependsOn, downstream)"]
        insights["service-insights/&lt;svc&gt;.yaml\n(prose, diagrams, ADR refs)"]
        templates["scripts/docgen/templates/*.j2\n(Jinja2)"]
        render_py["render.py"]
        validate_py["validate.py"]
        docs_output["docs-output/\n(gitignored — local preview only)"]
        tmp["&nbsp;/tmp/fleet-infra-docs-XXXX/\n(temp — discarded after sync)"]
    end

    subgraph opencode_scope["opencode scope (AI — prose only)"]
        insight_draft["insight-draft\n→ fills insight YAML fields"]
    end

    subgraph blog["jiwool0920.github.io repo (published output)"]
        blog_components["docs/projects/flux-infra/\n  components/loki.md\n  components/traefik.md\n  index.md\n  architecture.md"]
        watermark[".docs-sync-state.json\n(watermark)"]
    end

    manifests --> catalog_py --> catalog_json
    catalog_json --> render_py
    insights --> render_py
    templates --> render_py

    manifests -.->|context| insight_draft
    catalog_json -.->|context| insight_draft
    insight_draft -.->|writes prose fields| insights

    render_py -->|make docs-render| docs_output
    render_py -->|make update-docs| tmp
    tmp --> validate_py --> blog_components
    watermark -->|incremental: diff since this commit| catalog_py
    blog_components --> watermark
```

**`docs-output/`** is a local preview scratch space only — gitignored, never committed.
The blog repo is the authoritative home for rendered pages.

### Three input layers

| Layer | File(s) | Who writes it | Contains |
|-------|---------|--------------|---------|
| **Catalog** | `service-catalog.json` | `catalog.py` (auto) | Chart, version, namespace, env vars, `dependsOn`, downstream consumers — all extracted from manifests |
| **Insights** | `service-insights/<svc>.yaml` | `insight-draft` (AI) + human review | Prose intro, purpose, rationale, features, architecture diagrams, troubleshooting, ADR refs |
| **Templates** | `scripts/docgen/templates/*.j2` | Human | Jinja2 templates that merge catalog + insights into the final markdown |

Config values (CPU, memory, replicas, chart versions) always come from the catalog —
never from insights. This prevents drift: re-running `make catalog` always reflects the
current manifests.

### Makefile targets

```bash
# One-time setup: create Python venv and install deps
make docs-setup

# Step 1 — Extract live config values from manifests
make catalog                     # writes service-catalog.json

# Step 2 — AI-draft prose + diagrams for a service insight YAML
make insight-draft SVC=loki                        # initial draft (skips already-filled fields)
make insight-draft SVC=loki FORCE=1                # overwrite all fields (post-refactor)
make insight-draft SVC=loki FIELDS=architecture_diagrams   # re-draft one field only
make insight-draft SVC="loki jaeger"               # batch
make insight-draft-all                             # all stubs with TODO placeholders

# Step 3 — Local preview
make docs-render                 # renders to docs-output/ (absolute paths printed)
make docs-validate               # validates headings, tables, mermaid, TODOs
make docs-gen                    # catalog + validate-insights + render + validate

# Step 4 — Publish to blog repo
make update-docs                 # incremental: only services changed since watermark
make update-docs MODE=all        # full: all enabled services
```

### `insight-draft` — AI prose generation

`make insight-draft SVC=<slug>` calls `opencode` with:
- The service's Flux Kustomization and all manifests from `apps/base/<svc>/`
- The service's catalog entry (chart, version, env vars, `dependsOn`, downstream)
- Any ADR files that mention the service
- The `redis-sentinel.yaml` golden example as a style contract

OpenCode is instructed to draft **only** these YAML fields:

| Field | Description |
|-------|-------------|
| `intro` | 2-4 paragraph technical overview of the technology |
| `purpose` | Why this specific service exists in this platform |
| `purpose_rationale` | Why this tech over alternatives (omitted if obvious) |
| `features` | Key capabilities actually configured in the manifests |
| `architecture_diagrams` | `graph TD` topology + optional `sequenceDiagram` for flows |

**Hard constraint:** The LLM never writes config values — those come from
`service-catalog.json`. Every diagram edge must be traceable to a manifest or
catalog entry.

After drafting, `insight_schema.py` validates the YAML and the path is printed:
```
  insight → /Users/jiwoolee/Project/fleet-infra/service-insights/loki.yaml
```

#### Overwrite rules

| Invocation | Behavior |
|-----------|---------|
| `make insight-draft SVC=loki` | Skips already-filled fields — safe to re-run |
| `make insight-draft SVC=loki FORCE=1` | Overwrites all prose fields |
| `make insight-draft SVC=loki FIELDS=architecture_diagrams` | Re-drafts only that field |

### `update-docs` — Sync to blog repo

```mermaid
flowchart TD
    watermark{"Read watermark\n.docs-sync-state.json"}
    full["all enabled services"]
    incr["git diff watermark..HEAD\n(apps/base/, base/services/, service-insights/)\n→ affected services only"]
    catalog["catalog.py\n→ service-catalog.json"]
    render["render.py\n→ /tmp/fleet-infra-docs-XXXX/"]
    validate["validate.py\n→ 0 errors required"]
    copy["cp rendered pages\n→ blog repo"]
    advance["advance watermark\n→ .docs-sync-state.json"]
    branch["git checkout -b docs-sync/DATE"]
    commit["git add + commit"]
    pr["gh pr create"]

    watermark -->|absent or MODE=all| full --> catalog
    watermark -->|sha found| incr --> catalog
    catalog --> render --> validate --> copy --> advance --> branch --> commit --> pr
```

No LLM is invoked during `update-docs`. Generation is fully deterministic:
same inputs always produce the same output.

#### Watermark

Stored in the blog repo at `docs/projects/flux-infra/.docs-sync-state.json`:

```json
{
  "fleet_infra_commit": "<sha>",
  "synced_at": "2026-06-11T13:48:34Z"
}
```

Tracks which fleet-infra commit the docs were last synced from. On incremental runs,
only services whose files changed since that commit are re-rendered. The watermark
advances to `HEAD` and travels in the same PR as the doc updates — same pattern as
`release-please`'s manifest file.

### Environment overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `BLOG_REPO_DIR` | `~/Project/jiwool0920.github.io` | Path to local blog clone |
| `BLOG_REPO_GH` | `JiwooL0920/jiwool0920.github.io` | GitHub slug for PR creation |

---

## Blog Posts (`make blog-draft`)

**Script:** `scripts/blog-draft.sh`

Generates a `<!-- more -->`-fenced MkDocs Material post from recent commits and opens a
pull request in `jiwool0920.github.io`.

### Flow

```mermaid
flowchart TD
    range["git log + diff\n(HEAD~1..HEAD filtered to\napps/base/, base/services/, docs/adr/)"]
    prompt["Write prompt file\n(/tmp/blog-prompt.txt)"]
    gen["opencode run -f prompt\n--dangerously-skip-permissions"]
    validate{"Frontmatter\npresent?"}
    fail["Print raw output\nexit 1"]
    branch["blog repo: git checkout -b\nblog-draft/DATE-slug origin/main"]
    commit["cp draft → docs/blog/posts/DATE-slug.md\ngit commit + push"]
    pr["gh pr create\n--label blog-draft"]

    range --> prompt --> gen --> validate
    validate -->|no| fail
    validate -->|yes| branch --> commit --> pr
```

### Usage

```bash
# Default: draft from last commit
make blog-draft

# Draft from a wider range
make blog-draft RANGE=HEAD~3..HEAD

# Preview only (no PR, prints to stdout)
make docs-draft-blog
```

### Prerequisites

- `opencode` installed and authenticated
- `gh` authenticated (`gh auth status` shows JiwooL0920)
- Blog repo cloned at `~/Project/jiwool0920.github.io`

---

## Key design decisions

### LLM scope is strictly bounded

OpenCode is only used in two places:
1. `insight-draft` — drafts prose fields in `service-insights/<svc>.yaml`
2. `blog-draft` — drafts blog posts from commit diffs

Reference documentation (config values, port numbers, chart versions, dependency
graphs) is always derived deterministically from the manifests. This prevents the
hallucinated values and config drift that plagued earlier LLM-generated docs.

### No auto-merge, no CI

Both pipelines open PRs for human review. Same principle as the kagent `gitops-agent`:
AI drafts, human reviews, Flux/GitHub Pages deploys on merge.

### Why the watermark lives in the blog repo

The watermark describes the *documentation's* state, not the source repo's state.
Storing it in the blog repo means it travels in the same PR that updates the docs —
when the PR merges, the watermark merges too, and the next incremental run correctly
starts from that point.

---

## Troubleshooting

### `opencode` hangs

Use `--dangerously-skip-permissions` (already set in `insight_draft.py`). If it
still hangs, check that your `opencode.jsonc` provider is reachable (Ollama running,
or remote API key valid).

### "Branch already exists on origin"

A docs-sync PR is already open. Merge or close it first, or delete the remote branch:

```bash
gh api -X DELETE repos/JiwooL0920/jiwool0920.github.io/git/refs/heads/docs-sync/YYYY-MM-DD
```

### "Blog repo has uncommitted changes"

The script refuses to run if `docs/projects/flux-infra/` has uncommitted changes.
Commit or stash them first.

### Validation errors vs warnings

| Output | Meaning | Action |
|--------|---------|--------|
| `[WARN] N TODO placeholder(s) remain` | Insight stub not yet drafted | Run `make insight-draft SVC=<slug>` |
| `[ERROR] Empty table` | Template rendered a table with no rows | Check `service-catalog.json` for missing data |
| `[ERROR] Missing heading` | Required section absent | Check `service-insights/<svc>.yaml` schema |

### Re-drafting after a refactor

```bash
# Re-draw only the architecture diagram
make insight-draft SVC=loki FIELDS=architecture_diagrams

# Full rewrite of all prose
make insight-draft SVC=loki FORCE=1
```
