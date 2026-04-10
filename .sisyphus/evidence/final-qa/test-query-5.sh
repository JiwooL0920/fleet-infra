#!/bin/bash
# Test Query 5: GitOps PR creation (read-only test - will not create actual PR)
curl -s -X POST http://localhost:8002/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": 5,
    "method": "message/send",
    "params": {
      "message": {
        "role": "user",
        "messageId": "msg-f3-q5",
        "parts": [{"text": "explain how you would create a branch for fixing the redis config"}]
      },
      "sessionId": "f3-test-5"
    }
  }' | tee .sisyphus/evidence/final-qa/q5-response.json | jq -r '.result.message.parts[0].text // .error // .'
