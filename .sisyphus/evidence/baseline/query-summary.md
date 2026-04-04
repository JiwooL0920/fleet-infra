# Baseline Query Summary
Date: 2026-04-04
Agent: coordinator-agent
Endpoint: http://localhost:8000/v1/chat/completions (port-forward to svc/coordinator-agent:8000)

| # | Query | Response Time (s) | Agents Invoked | Trace ID | Pass/Fail |
|---|-------|-------------------|----------------|----------|-----------|
| 1 | List all pods in kagent namespace | 0.003644 | N/A (endpoint returned 404) | N/A | Fail |
| 2 | Show flux kustomization status | 0.003918 | N/A (endpoint returned 404) | N/A | Fail |
| 3 | Top 5 expensive namespaces | 0.004408 | N/A (endpoint returned 404) | N/A | Fail |
| 4 | Check security vulnerabilities | 0.005869 | N/A (endpoint returned 404) | N/A | Fail |
| 5 | PostgreSQL cluster status | 0.003536 | N/A (endpoint returned 404) | N/A | Fail |

## Validation Notes
- All five requests were sent sequentially with `stream:false` and `--max-time 180`.
- All response files are valid JSON, but contain `{"detail":"Not Found"}` and do not include `choices[0].message.content`.
- Jaeger API files are present but empty (`jaeger.local` was not reachable from this shell context).
