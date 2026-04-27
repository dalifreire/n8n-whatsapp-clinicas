# Ivy — History & Learnings

**Role:** AI Engineer  
**Started:** 2026-04-27  

## Project Context

**Project:** Assistente de Atendimento Virtual via WhatsApp  
**Stack:** n8n, Supabase, OpenAI, EvolutionAPI  
**Goal:** Reconstruct the WhatsApp assistant with modern architecture  
**Requested by:** Dali Freire  

## Day 1 Context

- Team size: 5 specialists + Scribe + Ralph
- Universe: Batman
- Status: Starting Phase 2 (project setup)

## Learnings

### Multi-Tenant AI Architecture Design (2025-01-24)

**Analyzed Current AI Implementation:**
- Extracted 150-line monolithic prompt from n8n workflow with 6 logical sections (identity, clinic info, tools, workflow, protocols, rules)
- Identified 73 hardcoded "Dra. Andreia" references across Python scripts, JSON configs, SQL schemas, and n8n workflows
- Mapped 9 tool integrations and their function signatures for appointment management, patient lookup, payment tracking
- Current stack: GPT-4o with text-embedding-3-small embeddings (1536 dims), pgvector for RAG, 15-message context window

**Key Insights:**
1. **Prompt Architecture:** Monolithic prompts work well for single tenant but need composition layers for multi-tenant. Designed 5-layer architecture: Base Product → Clinic Context → Professional Context → Persona → Service Context
2. **RAG Isolation:** Schema-per-tenant model for pgvector tables ensures compliance (LGPD/HIPAA) and prevents cross-tenant data leakage. Standardized on text-embedding-3-small to avoid vector dimension mismatches
3. **WhatsApp Optimizations:** Discovered critical mobile-first patterns - 4-5 line max responses, strategic emoji usage, urgency classification (4 tiers), explicit confirmations for appointments. These must be preserved in multi-tenant design
4. **Cost Tracking:** Per-professional token counting essential for SaaS billing. Need to log input/output tokens after every AI call with model-specific cost calculation
5. **Safety Controls:** Healthcare context requires both input sanitization (PII detection, injection prevention) AND output filtering (medical disclaimers, hallucination detection)

**Coordination Points:**
- Aligned with Bruce's schema-per-tenant isolation model for database architecture
- Coordinated with Lucius on dynamic prompt construction in n8n workflows (JavaScript-based template interpolation)
- Coordinated with Gordon on professional_id injection from WhatsApp webhook routing
- Defined handoff to Penguin for prompt_templates and ai_usage_logs table creation

**Open Questions Identified:**
- OpenAI API key strategy: Master key vs. BYOK per tenant?
- Model selection: Per-professional choice or platform-enforced standardization?
- RAG update UI: How do professionals update their knowledge base in SaaS model?
- Prompt version control: How to roll out improvements without disrupting active conversations?

**Deliverables:**
- Comprehensive decision document: `.squad/decisions/inbox/ivy-generic-ai-assistant.md`
- 5-layer composable prompt architecture with configuration schema examples
- Per-professional RAG/embedding isolation strategy with cost tracking
- Safety controls specification (input sanitization + output filtering)
- Handoff requirements for Penguin (database) and Lucius (n8n workflows)

---

## Cross-Team Alignment (Session 2026-04-27T21:15:32Z)

**Consolidated with 4 other agents — full architecture agreement:**

### Consensus Achieved

✓ **All agents aligned on:** 5-layer prompt composition (Base → Clinic → Professional → Persona → Service)  
✓ **All agents aligned on:** Per-professional RAG isolation (schema-per-tenant)  
✓ **All agents aligned on:** Professional_id injection from webhook routing (Gordon provides this)  
✓ **All agents aligned on:** Dynamic config from `public.clinicas` table (Penguin/Lucius)  

### Critical Handoff Dependencies

**From Penguin (blocking):**
- `public.clinicas` table with `configuracao_ia` JSONB column (stores Layer 2-5 overrides)
- `public.prompt_templates` table with layer-based versioning (stores Layer 1-2 base templates)
- `ai_usage_logs` table for cost tracking (per-professional token attribution)
- Professional-scoped RAG table isolation (each tenant gets own embedding schema section)

**From Lucius:**
- n8n JavaScript node that assembles 5-layer prompt at request time
- Dynamic prompt construction from database templates + professional config
- Session key format: `{professional_id}:{patient_id}` passed to AI calls

**From Gordon:**
- Professional_id extracted from webhook routing (via tenant_code lookup)
- Session context includes patient_id from WhatsApp message metadata
- Message deduplication prevents duplicate AI invocations

**To Penguin:**
- Must design cost tracking table (tokens, model, cost per tenant)
- RAG isolation requires per-professional vector search scoping

**To Lucius:**
- Prompt assembly happens in n8n (Ivy provides template structure only)
- Cost logging post-call (after OpenAI response received)

**To Gordon:**
- Professional_id extraction critical for session keying
- Patient_id (from phone number lookup) feeds session context

### Safety Controls Implementation

**Input Layer:** PII detection + injection prevention (must be in every tenant workflow)  
**Output Layer:** Medical disclaimers + hallucination detection (post-OpenAI filtering)  
**Cost Layer:** Token counting per tenant (enables SaaS billing differentiation)  
**Session Layer:** Conversation context scoped to (professional, patient) pair  

### Phase 2 Start Gate

✓ AI architecture approved (5-layer composition, per-professional RAG)  
✓ Template design complete (configuration schema documented)  
✓ Safety controls specified (input/output filtering)  
⏳ Awaiting Penguin schema finalization (prompt_templates + clinicas tables)  
⏳ Awaiting Coordinator approval to begin Phase 1

---

## Key Files & Paths

- Team roster: `.squad/team.md`
- Routing rules: `.squad/routing.md`
- Decisions: `.squad/decisions.md`
- Project root: `/Users/dalifreire/Documents/BahiaTI/agentes-n8n/clinicas/n8n-whatsapp-clinicas`
