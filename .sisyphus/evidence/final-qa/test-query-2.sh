#!/bin/bash
# Test Query 2: Show flux kustomizations status
curl -s -X POST http://localhost:8002/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "message/send",
    "params": {
      "message": {
        "role": "user",
        "messageId": "msg-f3-q2",
        "parts": [{"text": "show flux kustomizations status"}]
      },
      "sessionId": "f3-test-2"
    }
  }' | tee .sisyphus/evidence/final-qa/q2-response.json | jq -r '.result.message.parts[0].text // .error // .'
