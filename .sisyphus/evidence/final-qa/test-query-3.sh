#!/bin/bash
# Test Query 3: Cost analysis
curl -s -X POST http://localhost:8002/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "message/send",
    "params": {
      "message": {
        "role": "user",
        "messageId": "msg-f3-q3",
        "parts": [{"text": "what are the top cost namespaces?"}]
      },
      "sessionId": "f3-test-3"
    }
  }' | tee .sisyphus/evidence/final-qa/q3-response.json | jq -r '.result.message.parts[0].text // .error // .'
