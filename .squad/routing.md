# Work Routing

## Primary Routing Rules

| Signal | Primary | Backup | Notes |
|--------|---------|--------|-------|
| Architecture, decisions, tech lead | Bruce | — | Final approval gate |
| WhatsApp API, EvolutionAPI, integração | Gordon | Bruce | Protocol-level work |
| n8n workflows, automações, orquestração | Lucius | Bruce | Workflow design & implementation |
| IA, prompts, RAG, embedding | Ivy | Bruce | Conversational logic |
| Database, Supabase, PostgreSQL, schema | Penguin | Bruce | Data layer decisions |
| Session logs, decisions, memory | Scribe | — | Fire-and-forget |
| Work queue, backlog monitoring | Ralph | — | Continuous loop |
| Code review, architecture review | Bruce | — | Blocker gate |

## Skill-Aware Routing

Check `.squad/skills/` before spawning. Relevant skills are inputs to routing.

## Multi-Agent Work

When a task touches 3+ domains → fan-out in parallel:
- Example: "Build auth with WhatsApp" → Gordon (WhatsApp) + Ivy (IA prompt) + Penguin (DB) simultaneously

