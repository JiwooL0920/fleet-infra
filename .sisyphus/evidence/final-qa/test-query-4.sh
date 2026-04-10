#!/bin/bash
# Test Query 4: Security check
curl -s -X POST http://localhost:8002/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": 4,
    "method": "message/send",
    "params": {
      "message": {
        "role": "user",
        "messageId": "msg-f3-q4",
        "parts": [{"text": "check for security vulnerabilities"}]
      },
      "sessionId": "f3-test-4"
    }
  }' | tee .sisyphus/evidence/final-qa/q4-response.json | jq -r '.result.message.parts[0].text // .error // .'
