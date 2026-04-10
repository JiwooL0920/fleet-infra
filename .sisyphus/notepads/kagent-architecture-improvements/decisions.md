# Decisions — kagent Architecture Improvements

## [2026-04-04T03:45] Classifier Architecture (from Interview)
- **Decision**: Thin routing layer (14b) with ONE tool: coordinator-agent
- **Rationale**: Classifier decomposes simple queries, passes complex/ambiguous to coordinator
- **Flow**: User → Classifier (14b) → Coordinator (72b) → Sub-agents
- **Fallthrough principle**: When in doubt, classifier must pass through to coordinator

## [2026-04-04T03:45] default-model-config Strategy
- **Decision**: NO explicit ModelConfig CR creation
- **Rationale**: Helm already manages `default-model-config` via helmrelease.yaml `providers.ollama` section
- **Risk avoided**: Helm/manual resource conflict if both try to manage same resource
- **Approach**: Keep existing Helm-managed pattern

## [2026-04-04T03:45] Phasing Strategy
- **Decision**: 3-phase approach with baseline capture BEFORE any prompt changes
- **Phase 1**: OTEL + design docs (no behavior change)
- **Phase 2**: Prompt updates (4 waves: baseline → read-only → write → coordinator)
- **Phase 3**: Classifier + regression validation
- **Rationale**: Allows rollback point before behavioral changes, enables regression comparison

## [2026-04-04T03:45] Prompt Change Safety
- **Decision**: Additive-only changes, never rewrite existing content
- **Rationale**: Preserves existing behavior while augmenting with new patterns
- **Pattern**: APPEND new sections at end of systemMessage YAML string
- **Guardrail**: One agent per commit for granular rollback

## [2026-04-09] Task 15: Coordinator policy insertion strategy
- **Decision**: Insert four required sections as an append-only block directly before `a2aConfig:`.
- **Rationale**: Maintains existing `systemMessage` semantics while extending orchestration behavior.
- **Validation**: Enforce with `kubectl apply --dry-run=client` plus grep-based evidence artifacts.
