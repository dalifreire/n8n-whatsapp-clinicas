# Project Context

- **Project:** n8n-whatsapp-clinicas
- **Created:** 2026-04-27

## Core Context

Agent Scribe initialized and ready for work.

## Recent Updates

📌 Team initialized on 2026-04-27

## Learnings

### Reference Cleanup Phase (2026-04-27)

**Learning 1: Policy-First Cleanup Works**
- Bruce defined classification rubric (BLOCKING/ACCEPTABLE/NOISE) *before* execution agents
- Result: Clear rejection criteria, coordination between SQL/Python/n8n teams, auditable trail
- Pattern: Publish policy gate before delegating; prevents mid-stream debates

**Learning 2: Mechanical Smoke Test > Manual Review**
- Zero-match grep (case-insensitive, explicit exclusions) caught drift between "we say cleaned" and "we actually cleaned all"
- Exclusion rules (`.squad/**`, `legacy-single-tenant/**`, `*.backup`) are explicit and auditable
- Pattern: Bake mechanical criteria into policy gate ADR from day 1

**Learning 3: Preserve Context, Neutralize Exposure**
- Archive reorganization (`legacy-dra-andreia/` → `legacy-single-tenant/`) preserves rollback + removes client exposure
- Project memory (`.squad/` history) left untouched per NOISE bucket definition
- Pattern: Use "neutralization" (renaming) not deletion for historical artifacts; lets future ops recover without rewriting history

**Learning 4: Rejection Lockout Pattern Holds for Cleanup**
- Multi-tenant gate showed that forcing each defect class onto an agent who hadn't written the rejected version surfaced contract violations
- Cleanup phase verified: having one agent (Lucius, Ivy) execute across all three layers (SQL, n8n, KB) helped spot cross-layer consistency issues
- Pattern: Keep agent ownership tight for cleanup passes; don't dilute across too many hands mid-pass
