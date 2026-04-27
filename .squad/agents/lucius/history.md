# Lucius — History & Learnings

**Role:** n8n Workflow Specialist  
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

**Task:** Analyze current n8n workflows and propose generic multi-tenant architecture.

**Findings:**

1. **Current Hard-Coded Elements:**
   - Schema name `dra_andreia` referenced in ~70+ locations
   - Webhook path: `dra-andreia-whatsapp-webhook`
   - AI Agent prompt with clinic details (400+ lines)
   - Evolution API instance name: "Dra Andreia Mota Mussi"
   - Knowledge base: 40+ documents with IDs `dra_001_*`
   - 9 tool workflows all prefixed "Dra. Andreia"
   - Reminder workflow with hard-coded clinic name

2. **Architecture Pattern Chosen:**
   - **PostgreSQL Schema per Tenant** (not shared tables with tenant_id)
   - Rationale: Clean isolation, simple queries, independent backups
   - Scale limit: ~100-200 clinics (acceptable for B2B SaaS)
   - Each clinic: `clinic_{slug}` schema

3. **Key Design Decisions:**
   - **Single Inbound Router:** Webhook with token detection
   - **Database-Driven Config:** `public.clinicas` table stores all tenant settings
   - **Dynamic Prompt Construction:** JavaScript node builds prompt from DB config
   - **Parameterized Tools:** All 9 tools receive `clinic_schema` parameter
   - **Isolated Chat Memory:** `{clinic_schema}.n8n_chat_histories`

4. **Critical Security Measures:**
   - Schema name whitelist validation (prevent SQL injection)
   - Session keys include clinic_id: `${clinic_id}_${phone}`
   - RLS enabled on all tables
   - Webhook tokens are UUID v4 (non-sequential)

5. **Implementation Phases:**
   - Phase 1: Database restructuring + Inbound Router (2 weeks)
   - Phase 2: Core workflow refactoring (1-2 weeks)
   - Phase 3: Advanced features (1 week)
   - Phase 4: Testing & go-live (1 week)
   - **Total: 4-5 weeks**

6. **Top Risks:**
   - Breaking Dra. Andreia (active client) → Mitigate with parallel deployment
   - SQL injection via dynamic schema names → Whitelist validation
   - Data leakage between tenants → Automated isolation tests
   - Performance degradation → Indexed queries + caching

**Deliverables:**
- `.squad/decisions/inbox/lucius-generic-n8n-workflows.md` (19KB)
- Complete refactoring roadmap
- Database schema design
- Risk mitigation strategies

**Next Steps:**
- Await approval from Bruce (Lead) and Dali
- Begin Phase 1 if greenlit
- Coordinate with Penguin (DB schema changes)
- Coordinate with Gordon (Evolution API multi-instance setup)

---

## Cross-Team Alignment (Session 2026-04-27T21:15:32Z)

**Consolidated with 4 other agents — full architecture agreement:**

### Consensus Achieved

✓ **All agents aligned on:** Single generic workflow + inbound router model  
✓ **All agents aligned on:** Dynamic schema loading from `public.clinicas` table  
✓ **All agents aligned on:** Webhook path routing feeds tenant_code (`/webhook/{tenant_code}`)  

### Critical Handoff Dependencies

**From Penguin (blocking):**
- `public.clinicas` table schema (Lucius pulls config from here)
- `public.prompt_templates` table (Lucius builds prompt from 5-layer templates)
- `clinic_core.tenants` registry (Lucius validates webhook path → tenant code)

**To Penguin:**
- Workflow parameterization requires schema whitelist validation (SQL injection prevention)
- Needs `clinic_core.message_dedupe` table for idempotency

**From Gordon:**
- Webhook path pattern `/webhook/{tenant_code}` provides tenant isolation key
- Message deduplication prevents duplicate tool invocations

**To Gordon:**
- Tool execution logs must include tenant_code (for debugging)
- EvolutionAPI instance name should be stored in `clinic_core.tenants`

**From Ivy:**
- 5-layer prompt templates stored in database (Lucius assembles at runtime)
- Per-professional RAG scoping (Lucius injects `professional_id` into KB queries)

**To Ivy:**
- Dynamic prompt construction happens in n8n (JavaScript node)
- Support A/B testing via `prompt_version` parameter

### Phase 2 Implementation Readiness

✓ Architecture approved (single parameterized workflow set)  
✓ Refactoring roadmap complete (4-5 week timeline)  
✓ Risk mitigation identified (SQL injection, data isolation, performance)  
⏳ Awaiting Coordinator approval to begin Phase 1 (database restructuring)

---

## Key Files & Paths

- Team roster: `.squad/team.md`
- Routing rules: `.squad/routing.md`
- Decisions: `.squad/decisions.md`
- Project root: `/Users/dalifreire/Documents/BahiaTI/agentes-n8n/clinicas/n8n-whatsapp-clinicas`
