# agentgateway Requirements and Design

**Related**: [[01-Architecture]] | **Status**: Design Phase

---

## Overview

This document defines technical requirements and design considerations for agentgateway-dependent features. The agentgateway component serves as the interactive shell and session manager for agent conversations, handling connection lifecycle, streaming, rate limiting, cost tracking, and security boundaries.

Four major features depend on agentgateway infrastructure:

1. **Fail Closed Security Model** (#3) - Session-scoped write permissions for A2A protocol
2. **Thread Cancellation** (#5) - AbortSignal propagation through agent tool calls
3. **Two Output Representations** (#8) - Dual JSON/Markdown response formats
4. **agentgateway as REPL** (#13) - Interactive session management and orchestration

This document provides the foundation for implementing these capabilities in a coordinated manner.

---

## Problem Statement

### Current State

The kagent platform currently lacks a unified session management layer for agent interactions. Key gaps include:

- **Security**: No session-scoped permission model for destructive operations in A2A protocol
- **User Control**: No mechanism to cancel in-flight agent operations or propagate cancellation signals
- **Output Flexibility**: Single output format forces choice between machine-readable JSON or human-readable Markdown
- **Session Management**: No centralized component for managing connection lifecycle, state, and resource limits

### Target State

agentgateway will provide:

- Session-aware security boundaries with ephemeral permission grants
- Standard cancellation protocol using AbortSignal through the agent call chain
- Content-type negotiation for dual output formats (same data, different representations)
- REPL-like session orchestration with streaming, rate limiting, and cost tracking

---

## Feature Requirements

### 1. Fail Closed Security Model (#3)

**Objective**: Ensure destructive operations require explicit, session-scoped authorization that never persists.

#### Requirements

**R1.1** Default Deny Policy
- All write/destructive operations denied by default
- Read-only operations permitted without additional authorization
- Applies to A2A protocol tool invocations (kubectl apply, helm install, etc.)

**R1.2** Session-Scoped Permissions
- Write permissions granted per-session via user approval (HITL mechanism)
- Permissions live only in session memory
- Permissions expire when session terminates (connection close, timeout, explicit end)
- No persistent permission storage (no database writes, no CRD updates)

**R1.3** Granular Authorization
- Permission grants scoped to specific tool + resource + namespace
- Example: `kubectl apply` on `deployment/my-app` in `my-namespace` ✅
- Broader permissions require separate approval
- Wildcard permissions (`*`) not supported in v1

**R1.4** Audit Trail
- Log all permission requests (approved and denied)
- Include: timestamp, session ID, requesting agent, tool, resource, decision
- Logs sent to standard output for aggregation by observability stack

#### Acceptance Criteria

- [ ] Agent attempts `kubectl apply` without approval → Operation blocked, user prompted
- [ ] User approves operation → Permission granted for session, operation executes
- [ ] Session ends → Permission no longer valid
- [ ] Agent attempts same operation in new session → Requires re-approval
- [ ] Read-only operations (`kubectl get`) → No approval required

#### Dependencies

- agentgateway session management (Feature #13)
- UI/CLI approval interface (HITL mechanism exists, needs session-aware extension)

---

### 2. Thread Cancellation (#5)

**Objective**: Allow users to cancel in-flight agent operations with graceful cleanup.

#### Requirements

**R2.1** AbortSignal Propagation
- User cancellation triggers AbortSignal in agentgateway
- Signal propagates through A2A protocol to downstream agents
- All agents in call chain receive cancellation signal
- Follows standard JavaScript AbortController API pattern

**R2.2** Timeout-Based Abort
- Configurable grace period for agents to complete cleanup (default: 10 seconds)
- Agents exceeding timeout forcibly terminated
- Partial results returned if available

**R2.3** Cancellation Notice
- User receives explicit notification: "Operation cancelled by user"
- Partial results included if agent made progress before cancellation
- Agents report which sub-tasks completed vs. aborted

**R2.4** Tool Call Interruption
- In-progress tool calls receive cancellation signal
- Tools supporting cancellation (e.g., long HTTP requests) abort cleanly
- Tools without cancellation support killed after timeout

#### Acceptance Criteria

- [ ] User cancels during multi-agent A2A workflow → All agents stop within timeout
- [ ] Agent in progress returns partial results (e.g., "Processed 3 of 10 files before cancel")
- [ ] Hung agent exceeds timeout → Forcibly terminated, error logged
- [ ] Cancellation during tool call → Tool receives signal and aborts if supported

#### Dependencies

- agentgateway session management (Feature #13)
- Engine support for AbortSignal in Python and Go ADKs
- MCP protocol extension for cancellation signals (if tools need notification)

---

### 3. Two Output Representations (#8)

**Objective**: Provide machine-readable JSON and human-readable Markdown from same agent response.

#### Requirements

**R3.1** Dual Format Generation
- Agent response contains single semantic payload
- Output rendered as both JSON (structured) and Markdown (formatted)
- Content parity: Same information, different presentations

**R3.2** Content-Type Negotiation
- Client specifies desired format via `Accept` header
  - `Accept: application/json` → JSON response
  - `Accept: text/markdown` → Markdown response
- Default format: Markdown (human-friendly)

**R3.3** JSON Schema
- Structured response with fields:
  - `status` (success, partial, error)
  - `message` (brief summary)
  - `data` (structured payload - arrays, objects)
  - `metadata` (session ID, agent name, timestamp, cost)

**R3.4** Markdown Schema
- Formatted response with sections:
  - Header: Agent name, timestamp
  - Summary: Brief result description
  - Details: Formatted payload (tables, lists, code blocks)
  - Footer: Metadata (cost, duration)

**R3.5** Streaming Support
- Both formats support Server-Sent Events (SSE) streaming
- JSON: Incremental updates to `data` field
- Markdown: Progressive content chunks (compatible with chat UI)

#### Acceptance Criteria

- [ ] Client requests JSON (`Accept: application/json`) → Receives structured JSON response
- [ ] Client requests Markdown (`Accept: text/markdown`) → Receives formatted Markdown
- [ ] Same semantic data in both formats (verified by test suite)
- [ ] Streaming enabled → Incremental updates in requested format
- [ ] Invalid `Accept` header → Default to Markdown with warning

#### Dependencies

- agentgateway routing and content negotiation logic
- Engine response formatting in Python/Go ADKs

---

### 4. agentgateway as REPL (#13)

**Objective**: Provide interactive shell for agent conversations with session management and resource controls.

#### Requirements

**R4.1** Session Management
- Unique session ID per connection
- Session state stored in memory (conversation history, permissions, context)
- Session timeout configurable (default: 30 minutes idle, 4 hours max)
- Session cleanup on disconnect or timeout

**R4.2** Connection Lifecycle
- WebSocket or HTTP/2 for persistent connections
- Graceful reconnection with session resume (5-minute grace period)
- Connection health checks (ping/pong heartbeat)

**R4.3** Streaming Protocol
- Server-Sent Events (SSE) for response streaming
- Event types: `message` (content), `metadata` (status updates), `error` (failures)
- Backpressure handling for slow clients

**R4.4** Rate Limiting
- Per-session request rate limit (default: 10 requests/minute)
- Per-user request limit across sessions (default: 100 requests/hour)
- 429 Too Many Requests response with retry-after header

**R4.5** Cost Tracking
- Track token usage per session (input + output tokens)
- Track cost per session (tokens × model pricing)
- Expose metrics via `/metrics` endpoint (Prometheus format)
- Include cost in response metadata

**R4.6** Observability
- Structured logging: session lifecycle events, errors, rate limit hits
- Metrics: active sessions, requests/sec, token usage, error rate
- Distributed tracing: trace ID propagated through A2A calls

#### Acceptance Criteria

- [ ] User connects → Assigned session ID, state initialized
- [ ] User sends message → Response streamed via SSE
- [ ] User disconnects → Session cleaned up within timeout window
- [ ] User exceeds rate limit → 429 response, backoff applied
- [ ] Session metrics visible in Grafana dashboard
- [ ] Reconnection within grace period → Session state restored

#### Dependencies

- Kubernetes Service and Deployment for agentgateway component
- Redis or in-memory store for session state (evaluate tradeoffs)
- Prometheus metrics endpoint
- Ingress/LoadBalancer configuration for external access

---

## Architecture Overview

### Component Interaction

```
┌──────────────┐
│   User/CLI   │
└──────┬───────┘
       │ WebSocket/HTTP
       ▼
┌─────────────────────────────────────┐
│         agentgateway (REPL)         │
│  ┌─────────────────────────────┐   │
│  │  Session Manager            │   │◄── Feature #13
│  │  - Connection lifecycle     │   │
│  │  - Rate limiting            │   │
│  │  - Cost tracking            │   │
│  └──────────────┬──────────────┘   │
│  ┌──────────────▼──────────────┐   │
│  │  Security Layer (Fail Closed)│  │◄── Feature #3
│  │  - Session-scoped perms     │   │
│  │  - Approval gates           │   │
│  └──────────────┬──────────────┘   │
│  ┌──────────────▼──────────────┐   │
│  │  Output Formatter           │   │◄── Feature #8
│  │  - JSON renderer            │   │
│  │  - Markdown renderer        │   │
│  └──────────────┬──────────────┘   │
│  ┌──────────────▼──────────────┐   │
│  │  Cancellation Handler       │   │◄── Feature #5
│  │  - AbortSignal propagation  │   │
│  └──────────────┬──────────────┘   │
└─────────────────┼───────────────────┘
                  │ A2A Protocol
                  ▼
          ┌───────────────┐
          │  Agent Engine │
          │  (Python/Go)  │
          └───────────────┘
```

### Deployment Model

**Kubernetes Resources**:
- Deployment: `agentgateway` (2-3 replicas for HA)
- Service: ClusterIP or LoadBalancer (external access)
- ConfigMap: Configuration (timeouts, rate limits, defaults)
- ServiceMonitor: Prometheus scraping

**Technology Stack** (Recommended):
- Language: Go (low latency, efficient for proxy/gateway pattern)
- Framework: Gin or Chi (HTTP routing, middleware)
- Session Store: In-memory (simplicity) or Redis (HA, persistence)
- Streaming: gorilla/websocket or stdlib HTTP/2

---

## Dependency Matrix

| Feature                         | Depends On                     | Blocks                | Can Implement Independently? |
|---------------------------------|--------------------------------|-----------------------|------------------------------|
| **#13 REPL (Session Manager)**  | None (foundation)              | #3, #5, #8           | ✅ Yes                       |
| **#3 Fail Closed Security**     | #13 (session state)            | None                  | ❌ Needs session context     |
| **#5 Thread Cancellation**      | #13 (session ID, signal prop)  | None                  | ❌ Needs session tracking    |
| **#8 Two Output Representations** | #13 (response routing)       | None                  | ⚠️ Partial (needs routing)  |

**Recommended Implementation Order**:
1. **Phase 1**: Feature #13 (REPL/Session Manager) - Foundation
2. **Phase 2**: Features #8 (Output) and #5 (Cancellation) - Parallel tracks
3. **Phase 3**: Feature #3 (Fail Closed) - Requires mature session layer

---

## Open Questions

### Security

**Q1**: Should session permissions support time-based expiration (e.g., 5-minute approval window)?
- **Context**: Prevents lingering permissions if user forgets to close session
- **Tradeoff**: Adds complexity, may interrupt long-running workflows

**Q2**: How to handle permission revocation mid-operation?
- **Scenario**: User approves `kubectl apply`, then clicks "Revoke" while operation in progress
- **Options**: (a) Allow completion, (b) Cancel immediately, (c) Warn user

### Performance

**Q3**: Session state storage: In-memory vs. Redis?
- **In-memory**: Faster, simpler, but lost on pod restart (sessions dropped)
- **Redis**: Persistent, HA-friendly, adds latency and dependency

**Q4**: What are acceptable latency targets for agentgateway?
- **Suggested**: P50 < 50ms, P99 < 200ms (excluding LLM inference time)

### Protocol

**Q5**: Should AbortSignal include cancellation reason?
- **Options**: (a) Simple boolean abort, (b) Reason string ("user_cancelled", "timeout", "rate_limit")
- **Impact**: Helps agents decide whether to save partial results

**Q6**: Can agents request format preference override?
- **Scenario**: Agent knows downstream consumer needs JSON, but user client sends `Accept: text/markdown`
- **Options**: (a) Agent wins, (b) Client wins, (c) Negotiation protocol

### Observability

**Q7**: What granularity for cost tracking?
- **Options**: (a) Per-session total, (b) Per-message detail, (c) Per-agent breakdown in A2A chain
- **Tradeoff**: Granularity vs. storage/performance cost

**Q8**: Should rate limiting be global, per-user, or per-agent?
- **Context**: Multi-tenant scenarios may need user-level quotas
- **Current**: Per-session and per-user proposed

---

## Success Metrics

### User Experience

- **Cancellation latency**: P95 < 2 seconds from user click to operation stopped
- **Session reliability**: < 1% unexpected session drops
- **Approval friction**: < 5 seconds average from approval request to grant

### System Performance

- **Gateway latency**: P99 < 200ms (excluding LLM time)
- **Session capacity**: 1000+ concurrent sessions per replica
- **Rate limit accuracy**: Zero false positives (legitimate requests blocked)

### Security

- **Permission leaks**: Zero incidents of cross-session permission reuse
- **Audit completeness**: 100% of write operations logged with decision

---

## References

### Related Documentation

- [[01-Architecture]] - Overall kagent system architecture
- [[03-Tools-and-MCP]] - MCP server integration and tool invocation
- `docs/architecture/controller-reconciliation.md` - Concurrency model

### Issue References

- Issue #3: Fail Closed Security Model
- Issue #5: Thread Cancellation Support
- Issue #8: Two Output Representations (JSON + Markdown)
- Issue #13: agentgateway as REPL

### External Resources

- [AbortController API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/AbortController)
- [HTTP Content Negotiation (RFC 7231)](https://tools.ietf.org/html/rfc7231#section-5.3)
- [Server-Sent Events (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events)

---

**Next Steps**: Review this design with stakeholders, resolve open questions, prioritize implementation phases.
