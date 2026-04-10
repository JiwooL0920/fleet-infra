# Learnings — kagent Architecture Improvements

## [2026-04-04T03:54] Task 1: OTEL Tracing Toggle
- **What worked**: Simple boolean toggle in HelmRelease (`otel.tracing.enabled: false` → `true`)
- **OTEL verification pattern**: Check Jaeger UI at http://jaeger.local after Flux reconcile + pod restart
- **Environment variables injected automatically**: OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME when tracing enabled
- **Flux reconcile pattern**: `flux reconcile kustomization services --with-source` forces immediate deployment

## [2026-04-04T04:00] Task 2: Design Doc Attempt (FAILED)
- **Model error**: `gemini-3-flash-preview` not supported by current configuration
- **Lesson**: Need to verify available models before delegating to writing category
- **Session preserved**: `ses_2a965ac99ffeymeULIO7oHa3v6` can be resumed for retry

## [2026-04-04T00:19] Task 2: agentgateway design doc created

### What Was Done
- Created `docs/kagent/design/agentgateway-requirements.md` (398 lines)
- Comprehensive technical design covering 4 agentgateway-dependent features
- Structured with 8 major sections: Overview, Problem Statement, Requirements (4 features), Architecture, Dependencies, Open Questions, Success Metrics, References

### Design Decisions
- **Structure**: Followed style of `docs/kagent/01-Architecture.md` — technical but accessible tone, clear headings, code examples where helpful
- **Coverage**: All 4 features thoroughly documented with Requirements, Acceptance Criteria, Dependencies
- **Dependency Matrix**: Created explicit table showing which features can be implemented independently vs. require others
- **Implementation Order**: Recommended phased approach (REPL foundation → Output/Cancellation parallel → Fail Closed final)

### Key Patterns
- Navigation links at top (following existing doc pattern)
- Structured requirements with R-number identifiers for traceability
- Acceptance criteria as testable checkboxes
- Open Questions section captures design decisions still pending
- Success Metrics quantify expected outcomes
- ASCII diagram shows component interaction

### Evidence
- File exists: ✅ `docs/kagent/design/agentgateway-requirements.md`
- Major sections: 8 (exceeds minimum 5)
- Feature coverage: 21 mentions of core features
- No code files in design/ directory: ✅ (clean docs-only)

### Commit
- Message: `docs(kagent): add agentgateway requirements design doc`
- Hash: 4f9a84d
- Pre-commit hooks: All passed (markdown-only file, no yaml/k8s validation needed)
## [2026-04-04T04:20] Task 4: multi-cluster provider design doc created

### Accomplishment
Created comprehensive design doc at docs/kagent/design/multi-cluster-provider.md with 10 major sections covering:
- Problem statement (single-cluster limitations)
- Architecture (meta-coordinator + per-cluster agents + shared gitops-agent)
- Routing logic (query classification, A2A tool naming conventions)
- Shared vs per-cluster agent rationale (gitops-agent shared because it operates on Git repo, not cluster APIs)
- Session scoping (cluster context tracking in ScyllaDB)
- 5-phase migration path (from single-cluster to federation)
- 5 open questions (meta-coordinator placement, scaling, failure isolation, cost allocation, RBAC)

### Key Technical Insights
1. **A2A tool expansion**: Current single-cluster uses tools like 'k8s-agent'; multi-cluster expands to 'k8s-agent-dev', 'k8s-agent-prod' as distinct A2A endpoints
2. **gitops-agent sharing**: Unlike other agents, gitops-agent has NO kubeconfig—it only needs GitHub token. Operates on fleet-infra Git repo, creating PRs that can affect multiple clusters atomically
3. **kubeconfig contexts**: Each cluster's agents run with distinct kubeconfig contexts pointing to their API servers, enforcing isolation via RBAC
4. **Session metadata storage**: Proposed using ScyllaDB (existing chat history backend) with cluster context as session attributes
5. **Graceful degradation**: Downtime in one cluster should not block queries about other clusters

### Pre-commit Hook Handling
- Pre-commit auto-fixed trailing whitespace on first attempt
- Re-committed successfully after auto-fixes applied
- All validation hooks passed (large files, EOF, merge conflicts, case conflicts)

### QA Evidence
- File exists: ✅
- Major sections (## headers): 10 (exceeds 5+ requirement)
- Keyword occurrences (cluster|routing|gitops.*shared|migration): 133 (exceeds 6+ requirement)
- No non-.md files in docs/kagent/design/: ✅
- Committed with exact message: 'docs(kagent): add multi-cluster provider design doc' ✅
- Pushed to develop: ✅ (commit 4926962)

### Design Patterns Applied
- Followed existing architecture doc style from docs/kagent/01-Architecture.md (Status, Date, Authors frontmatter)
- Used tables for component mapping and routing scenarios
- Included ASCII diagram for high-level architecture
- Added 'Related Documents' section linking to existing docs
- Added 'Changelog' section for future updates
- Structured with progressive disclosure: Problem → Architecture → Details → Migration → Open Questions
## [2026-04-04T04:21] Task 3: VCR testing fixtures design doc created

Created comprehensive design document for VCR-style testing fixtures at `docs/kagent/design/vcr-testing-fixtures.md`.

**Key Design Decisions:**
- OTEL-based recording recommended (non-invasive, production-ready)
- Fixture format: Per-scenario directories with JSON interaction files
- Mock MCP server with fuzzy matching for time-sensitive data
- 8 categories of priority scenarios identified (40+ total scenarios)
- CI integration via pytest/go test with automated fixture validation

**Document Structure:**
- 11 major sections covering problem statement → implementation → open questions
- 105 occurrences of core concepts (fixture, record, replay, scenario)
- Detailed architecture diagrams (ASCII art)
- Concrete file format examples and code snippets
- Recording workflow documentation
- CI integration strategy

**Technical Highlights:**
- Three recording mechanism options analyzed (OTEL, Proxy, Engine instrumentation)
- Fixture versioning strategy for MCP schema evolution
- Approval-gated tool handling for HITL scenarios
- Multi-agent coordination fixture structure
- Time-sensitive data handling strategies

Commit: dd3528c - "docs(kagent): add VCR testing fixtures design doc"
QA Evidence: .sisyphus/evidence/task-3-*.txt

## [2026-04-04T04:21] Task 5: permission keys design doc created
- Created comprehensive design doc with 71 permission level mentions, 47 requireApproval/session mentions
- Mapped all requireApproval gates from 3 agent CRDs to semantic permission levels
- Covered session lifecycle, multi-cluster scoping, escalation flows, and migration path
- Pre-commit hooks auto-fixed trailing whitespace - committed cleanly on second attempt
## [2026-04-04T04:21] Task 6: OTEL metrics design doc created

Created comprehensive design doc at docs/kagent/design/otel-agent-metrics.md covering:
- Trace span hierarchy: coordinator.session → intent_classify → agent.dispatch.{name} → tool.call.{name}
- Metrics catalog: 11 metrics (duration histograms, token counters, tool call counters)
- 3 implementation options: (1) upstream kagent code changes, (2) spanmetrics processor, (3) prompt engineering
- Grafana dashboard design with 5 rows: session overview, agent performance, token costs, tool execution, error tracking
- ServiceMonitor pattern reference from existing agentic-ai example
- No infrastructure changes (design doc only)

Evidence:
- 41 occurrences of trace hierarchy terms
- 66 occurrences of metrics terms (duration, token, success, failure, latency)
- Committed with exact message: 'docs(kagent): add OTEL agent metrics design doc'


## 2026-04-04 Baseline capture (Task 7)
- Verified `coordinator-agent` service exists in namespace `kagent` and all expected agent pods are Running.
- Captured 5 sequential baseline query attempts against `http://localhost:8000/v1/chat/completions` via port-forward to `svc/coordinator-agent:8000`.
- All five requests returned fast 404 JSON responses: `{"detail":"Not Found"}` (no `choices[0].message.content` payload).
- Coordinator exposes A2A endpoints (`/`, `/.well-known/agent-card.json`, `/.well-known/agent.json`) rather than OpenAI-compatible `/v1/chat/completions` on current runtime.
- Timing evidence was still recorded for all five queries and stored under `.sisyphus/evidence/baseline/`.

## [2026-04-09] Task 15: coordinator-agent orchestration policy append
- Appending to `systemMessage` with exact 6-space indentation preserved YAML block-scalar integrity.
- Inserting new policy sections immediately before `a2aConfig:` is safe and keeps existing instructions intact.
- Evidence checks via targeted `grep` counts are effective for proving section presence and key phrase coverage.
