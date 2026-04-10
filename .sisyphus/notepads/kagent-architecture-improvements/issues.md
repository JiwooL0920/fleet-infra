# Issues — kagent Architecture Improvements

## [2026-04-04T04:00] Task 2: Model Configuration Error
- **Issue**: Task 2 (agentgateway design doc) failed with "Model gemini-3-flash-preview is not supported"
- **Category**: writing
- **Session**: `ses_2a965ac99ffeymeULIO7oHa3v6`
- **Impact**: Task 2 blocked, but Tasks 3-6 can still proceed in parallel (same category, independent work)
- **Resolution needed**: Retry with correct model configuration OR allow default model to be used

## [2026-04-09] Task 15: Working tree noise during scoped commit
- **Issue**: Repository had unrelated modified/untracked files, requiring explicit file-scoped staging.
- **Impact**: Risk of accidental inclusion in commit if using broad `git add .`.
- **Resolution**: Staged only `apps/base/kagent/coordinator-agent.yaml` and task-15 evidence/notepad files.
