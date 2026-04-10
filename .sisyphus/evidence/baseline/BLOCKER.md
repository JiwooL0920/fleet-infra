# Baseline Capture Blocker

## Issue
kagent coordinator-agent receives A2A JSONRPC `message/send` requests successfully but NEVER calls the Ollama LLM, making baseline capture impossible.

## Evidence

### 1. A2A Endpoint Works (JSONRPC)
- Port-forwarded `kubectl port-forward -n kagent pod/coordinator-agent-7b8bf465b-clbjj 8080:8080`
- Sent JSONRPC request:
```bash
curl -X POST http://localhost:8080/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"message/send","id":200,"params":{"message":{"messageId":"internal-test-200","role":"user","parts":[{"type":"text","text":"test from inside pod"}]}}}'
```
- **Result**: Session created successfully (logs show `POST http://kagent-controller.kagent:8083/api/sessions` 201 Created)
- **Problem**: No subsequent Ollama API call (`POST http://host.docker.internal:11434/api/chat`)
- **Logs**: Show "Event from an unknown agent: system" warning, then nothing

### 2. OpenAI Endpoint Does NOT Exist
- Plan referenced endpoint: `POST http://localhost:8000/v1/chat/completions`
- Referenced in plan at line 697-708 as the correct method from `docs/kagent/02-Getting-Started.md:514-526`
- **Result**: `{"detail":"Not Found"}` (404)
- **Attempted all port combinations**: 8000, 8080, both fail or timeout

### 3. Ollama IS Reachable
```bash
kubectl exec -n kagent coordinator-agent-7b8bf465b-clbjj -- curl -s http://host.docker.internal:11434/api/tags
```
Returns 5 models including `qwen2.5:72b` and `qwen2.5:14b-kagent` — Ollama is healthy.

### 4. Previous Successful LLM Call
Coordinator logs show ONE successful Ollama call at `2026-04-04 05:14:52,943`:
```
httpx - INFO - HTTP Request: POST http://host.docker.internal:11434/api/chat "HTTP/1.1 200 OK"
```
This proves the integration CAN work, but subsequent A2A requests do NOT trigger inference.

## Root Cause Hypothesis
kagent agent-engine (Google ADK-based A2A server) has a bug where:
1. A2A `message/send` requests create sessions/tasks in kagent-controller
2. But the coordinator-agent runner does NOT invoke the LLM for these sessions
3. The "Event from an unknown agent: system" warning suggests a routing/session-state issue

## Attempted Workarounds
- [x] Direct pod port-forward (vs service) — same result
- [x] Unique messageId per request — no effect
- [x] Shorter/simpler queries ("ping") — still no LLM call
- [x] Test from inside pod (eliminate network) — same behavior

## Blocker Impact
- **Task 7 (Baseline Capture)** cannot complete — NO agent responses to record
- **Task 18 (Regression Comparison)** cannot execute — requires baseline
- **All prompt improvement tasks (8-15)** have no QA verification path

## Next Steps Required
1. **Investigate kagent agent-engine source code** to understand why A2A messages don't trigger LLM calls
2. **Check kagent-controller logs** for session/task state issues
3. **File upstream bug report** if this is a known issue
4. **Alternative**: If there's a working CLI/SDK for querying kagent, use that instead

## Timestamp
2026-04-04 05:17 UTC
