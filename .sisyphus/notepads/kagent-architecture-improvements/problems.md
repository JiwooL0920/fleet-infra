# Problems — kagent Architecture Improvements

## [2026-04-04T04:00] Task 2 Model Error — ACTIVE
- **Problem**: `gemini-3-flash-preview` model not supported
- **Impact**: Task 2 blocked (agentgateway design doc)
- **Workaround**: Proceed with Tasks 3-6 in parallel (independent of Task 2)
- **Next action**: Retry Task 2 with session resume, allow default model or specify supported model
- **Session to resume**: `ses_2a965ac99ffeymeULIO7oHa3v6`

## [2026-04-09] Task 15 unresolved follow-up
- **Problem**: Evidence grep for READ classification can match both role table lines and appended policy lines, which may reduce precision of proof intent.
- **Impact**: Low; required checks still pass and confirm presence of expected keywords.
- **Next action**: If stricter evidence is required later, use anchored patterns scoped to appended section headings.
