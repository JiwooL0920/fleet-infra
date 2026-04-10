#!/bin/bash
# Test Query 1: List pods in kagent namespace
curl -s -X POST http://localhost:8002/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "message/send",
    "params": {
      "message": {
        "role": "user",
        "messageId": "msg-f3-q1",
        "parts": [{"text": "list pods in kagent namespace"}]
      },
      "sessionId": "f3-test-1"
    }
  }' | tee .sisyphus/evidence/final-qa/q1-response.json | jq -r '.result.message.parts[0].text // .error // .'
