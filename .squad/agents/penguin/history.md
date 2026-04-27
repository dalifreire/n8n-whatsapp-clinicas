# Penguin — History & Learnings

**Role:** Database Engineer  
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

### 2026-04-27: Multi-Tenant Architecture Analysis

**Task:** Design data model and isolation strategy for generic clinic assistant product.

**Key Findings:**
1. **Current State:** Single-tenant schema (`dra_andreia`) hardcoded for one dentist with ~1133 lines of SQL
2. **Existing Tables:** conversations, usuarios, avaliacoes, escalacoes, metricas, documentos (RAG), dentistas, pacientes, procedimentos, agendamentos, planos_tratamento, itens_tratamento, registros_financeiros, lembretes, prontuarios, prescricoes
3. **RAG Implementation:** pgvector with OpenAI embeddings (text-embedding-3-small), vector similarity search via `buscar_documentos_similares()`
4. **RLS Current:** Basic policies checking `auth.role() = 'authenticated'` — not sufficient for multi-tenant isolation

**Design Decisions:**
- **Isolation Model:** Professional-level (primary) with optional organization-level sharing
- **Core Hierarchy:** Organization → Professional (1:many) → Assistant Instance (1:1) → WhatsApp Account (1:1)
- **RLS Strategy:** JWT claims with `professional_id`; all queries scoped to professional
- **Migration Path:** Gradual (add professional_id to existing tables) vs. Clean Slate (rebuild)
- **Naming:** `public` schema for multi-tenant core; keep `dra_andreia` for legacy migration period

**Critical Questions for Dali:**
1. Should professionals within same org share patient records? (HIPAA/LGPD implications)
2. Knowledge base sharing strategy (per professional vs. organization-wide)
3. Migration timeline preference (gradual/safe vs. fast/disruptive)
4. Multi-language support requirements
5. Pricing model (per professional or per organization)

**Handoffs:**
- **Ivy:** RAG query scoping with professional_id; refactor indexing scripts; system prompt templates
- **Lucius:** JWT generation for professional context; workflow isolation architecture; n8n instance routing
- **Gordon:** Webhook routing by phone number; EvolutionAPI multi-instance setup; conversation history isolation

**Deliverable:** Comprehensive proposal document at `.squad/decisions/inbox/penguin-multitenant-data-model.md`

**Next Steps:**
1. Wait for Dali's answers to Q1-Q5
2. Finalize schema based on business requirements
3. Write detailed migration scripts with rollbacks
4. Create RLS testing suite

---

## Cross-Team Alignment (Session 2026-04-27T21:15:32Z)

**Consolidated with 4 other agents — full architecture agreement:**

### Consensus Achieved

✓ **All agents aligned on:** Professional-level isolation (primary boundary)  
✓ **All agents aligned on:** Schema-per-tenant vs. RLS (chose schema for compliance)  
✓ **All agents aligned on:** Dynamic schema loading in n8n (Lucius will implement)  

### Critical Handoff Dependencies

**Penguin → All (blocking):**
- Must finalize `clinic_core.tenants` registry schema
- Must design `public.clinicas` config table (for Lucius + Ivy)
- Must design `public.prompt_templates` versioning (for Ivy)
- RLS policies on all tenant-scoped tables

**From Bruce:** Architecture approved (3-tier model)  
**From Gordon:** Webhook routing pattern feeds tenant_id (`/webhook/{tenant_code}`)  
**From Lucius:** Workflow parameterization requires schema name + config loading  
**From Ivy:** Prompt templates + RAG scoping requires professional_id access  

### Critical Questions (Blocking Implementation)

1. **Patient sharing:** Can same phone exist in multiple professionals' records?
2. **KB scope:** Per-professional or clinic-wide (affects embedding isolation)?
3. **Pricing model:** Per-professional or per-clinic (affects billing table design)?
4. **Multilingual:** Needed? (impacts embedding model selection)

### Phase 2 Start Gate

✓ Data model proposed (multi-tenant, professional-scoped)  
⏳ Awaiting Coordinator answers to Q1-Q5  
⏳ Awaiting Bruce/Dali approval to proceed to implementation

---

## Key Files & Paths

- Team roster: `.squad/team.md`
- Routing rules: `.squad/routing.md`
- Decisions: `.squad/decisions.md`
- Project root: `/Users/dalifreire/Documents/BahiaTI/agentes-n8n/clinicas/n8n-whatsapp-clinicas`
