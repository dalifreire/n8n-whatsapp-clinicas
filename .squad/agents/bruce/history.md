# Bruce — History & Learnings

**Role:** Lead Architect  
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

### [2026-04-27] Platform Pivot Architecture

**Decision:** Multi-tenant SaaS platform for clinic assistants  
**Approach:** Schema-per-tenant isolation with shared infrastructure

**Key Architectural Patterns:**
1. **Schema-per-tenant isolation** for healthcare data compliance (HIPAA/LGPD)
   - Each professional gets isolated PostgreSQL schema: `prof_{uuid}`
   - Strong data boundaries, predictable performance
   - Trade-off: Migration complexity increases with N tenants

2. **Dynamic N8N workflow routing** via context injection
   - Single generic workflow receives professional slug via webhook
   - Queries `platform.professionals` for metadata (schema_name, config)
   - All DB queries use dynamic schema prefix: `${schemaName}.tableName`
   - Maintains single codebase while supporting N professionals

3. **Phased migration strategy** - controlled rebuild vs. big-bang
   - Build platform foundation first (Phases 0-3)
   - Migrate existing Dra. Andreia in Phase 4 (de-risk)
   - Validate with second professional in Phase 5
   - Rollback capability at each phase gate

**Technical Constraints Identified:**
- EvolutionAPI multi-instance limits (Gordon to research)
- Supabase schema quotas on current plan
- OpenAI rate limits for bulk RAG indexing
- N8N credential management across tenant-aware workflows

**Critical Success Factors:**
- Zero cross-tenant data leaks (RLS policies + integration tests)
- <1 hour onboarding time for new professional (automation)
- Preserve existing Dra. Andreia functionality during migration
- Clear rollback plan at each phase

**User Preferences (Dali):**
- Wants incremental professional onboarding (not all at once)
- Same infrastructure for cost efficiency
- Product: sell to clinics, add professionals gradually

---

## Key Files & Paths

- Team roster: `.squad/team.md`
- Routing rules: `.squad/routing.md`
- Decisions: `.squad/decisions.md`
- Project root: `/Users/dalifreire/Documents/BahiaTI/agentes-n8n/clinicas/n8n-whatsapp-clinicas`
- Architecture proposal: `.squad/decisions/inbox/bruce-generic-platform-architecture.md`

**Current Stack Analysis:**
- Database: Supabase PostgreSQL with pgvector (RAG embeddings)
- Orchestration: N8N workflows (1520 lines main workflow + 9 tool workflows)
- AI: OpenAI API (text-embedding-3-small + GPT for conversations)
- WhatsApp: EvolutionAPI integration
- Indexing: Python scripts (indexar, atualizar, consultorio)
- Current schema: `dra_andreia` (hardcoded for single dentist)

**Schema Structure (Current):**
- `dra_andreia.conversas` - conversation history
- `dra_andreia.usuarios` - patient records
- `dra_andreia.documentos` - RAG knowledge base with vector embeddings
- `dra_andreia.avaliacoes` - satisfaction ratings
- `dra_andreia.escalacoes` - human handoff tracking
- `dra_andreia.metricas` - daily aggregated metrics

**Knowledge Base Assets:**
- 7 base documents (about, contact, hours, specialties, social)
- 40+ extended documents (appointments, procedures, FAQs, post-op care)
- Categories: agendamento, procedimentos, orientacoes, saude_bucal, financeiro, urgencia, faq, assistente
- All documents dentist-specific (need genericization)

---

## Cross-Team Alignment (Session 2026-04-27T21:15:32Z)

**All 5 agents completed Phase 1 design independently, then consolidated:**

### Consensus on Core Architecture

✓ **All agents aligned on:** Platform → Clinic → Professional 3-tier model  
✓ **All agents aligned on:** Schema-per-professional isolation (strong compliance)  
✓ **All agents aligned on:** Single shared infrastructure (n8n, Supabase, OpenAI)

### Critical Dependencies Identified

**Penguin → Others:** Database schema must be designed first
- Gordon needs `clinic_core.tenants` table (WhatsApp routing)
- Lucius needs `public.clinicas` config table (dynamic workflows)
- Ivy needs `public.prompt_templates` table (5-layer composition)

**Gordon → Lucius:** WhatsApp routing pattern enables workflow isolation
- Webhook path `/webhook/{tenant_code}` feeds tenant_id to workflows
- Message deduplication in `clinic_core.message_dedupe` prevents double-processing

**Lucius → Ivy:** Dynamic prompt construction in n8n links to AI layers
- n8n JavaScript builds 5-layer prompt from database config
- Supports Ivy's template versioning strategy

**Ivy → All:** Safety controls propagate across stack
- Input sanitization (PII detection, injection prevention)
- Output filtering (medical disclaimers)
- Cost tracking per tenant for billing

### Key Business Questions (to Coordinator)

1. Patient sharing across professionals in same clinic?
2. Knowledge base: per-professional or clinic-wide?
3. Pricing: per-professional or per-clinic?
4. Multilingual support needed?

### Phase 2 Readiness

All agents report **ready for implementation** pending:
- Coordinator approval of 5 core decisions
- Clarification on business questions (patient sharing, KB scope)
- Dra. Andreia confirmed as validation target
