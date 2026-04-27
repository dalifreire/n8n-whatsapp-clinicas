# Gordon — History & Learnings

**Role:** Backend & WhatsApp Integration Engineer  
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

### 2026-04-27: Multi-Tenant WhatsApp Architecture Design

**Context:** Designed WhatsApp integration strategy to transform single-professional assistant (Dra. Andreia) into multi-tenant clinic product.

**Key Insights:**

1. **Instance-per-Professional Model**
   - Each professional gets dedicated WhatsApp phone + isolated database schema
   - Webhook routing via path-based strategy: `/webhook/{tenant_code}`
   - Central tenant registry in `clinic_core.tenants` table
   - Enables independent scaling and clear tenant isolation

2. **Idempotency is Critical**
   - WhatsApp delivers messages multiple times (especially EvolutionAPI)
   - Three-layer strategy: dedupe table, n8n workflow logic, provider config
   - `clinic_core.message_dedupe` table with 7-day retention
   - Prevents duplicate AI responses and double-billing

3. **Provider Tradeoffs**
   - **EvolutionAPI:** Fast MVP, cheap, but risky (unofficial API, ban risk)
   - **Cloud API:** Compliant, reliable, but requires Meta verification + higher cost
   - **Recommendation:** Hybrid approach with migration path (Evolution → Cloud)
   - Store `whatsapp_provider` in tenant table for flexibility

4. **Credential Management Anti-Patterns**
   - ❌ Never hardcode API keys in n8n workflows
   - ❌ Never export credentials in JSON files
   - ✅ Use n8n credential manager + tenant-specific naming
   - ✅ Store encrypted secrets in `clinic_core.tenant_credentials` (Penguin's domain)
   - ✅ Reference by name: `EvolutionAPI - {{ tenant_code }}`

5. **Schema Isolation Pattern**
   - Each tenant gets own PostgreSQL schema (e.g., `dra_andreia`, `dr_carlos`)
   - All workflows use `SET search_path TO <schema_name>` at entry point
   - RAG documents, conversations, users fully isolated
   - Shared infrastructure in `clinic_core` schema (tenants, credentials, dedupe)

6. **Onboarding Flow**
   - Estimated 30min per professional (after automation)
   - Sequence: Penguin (DB) → Gordon (WhatsApp) → Lucius (workflows) → Ivy (AI) → Gordon (health check)
   - Key bottleneck: QR code scanning for EvolutionAPI (requires professional's phone)
   - Cloud API: Meta Business verification can take days

7. **Monitoring Requirements**
   - Connection health tracking per tenant (detect disconnections)
   - Message flow metrics (last message timestamp, daily volume)
   - Failed message queue for retry logic
   - Rate limit tracking per tenant

8. **Handoff Dependencies**
   - **Penguin:** Must create core schema + provisioning functions before Lucius can test
   - **Lucius:** Must refactor workflows to be tenant-agnostic (replace hardcoded `dra_andreia`)
   - **Ivy:** Prompts must support `{{ professional_name }}`, `{{ specialty }}` variables
   - **Gordon:** Document both EvolutionAPI and Cloud API setup for ops team

**Decisions Made:**
- Dedicated webhook paths per tenant (not shared routing)
- Schema-per-tenant isolation (not row-level in shared tables)
- Hybrid provider strategy (Evolution for MVP, Cloud for premium)
- Centralized credential management via Supabase + n8n credential store

**Risks Identified:**
- EvolutionAPI account bans if Meta cracks down on unofficial APIs
- QR code reconnection required if EvolutionAPI sessions expire
- Migration complexity when moving tenant from Evolution → Cloud API
- Schema proliferation in Postgres (monitor with connection pooling)

**Next Session:**
- Review decision doc with Bruce (lead architect)
- Sync with Penguin on schema migration strategy
- Coordinate with Lucius on workflow refactoring approach

---

## Cross-Team Alignment (Session 2026-04-27T21:15:32Z)

**Consolidated with 4 other agents — full architecture agreement:**

### Consensus Reached

✓ **All agents aligned on:** Schema-per-professional isolation (Gordon's instance-per-prof matches)  
✓ **Dependency mapped:** Webhook path routing (`/webhook/{tenant_code}`) feeds into Lucius workflows  
✓ **Isolation cascade:** Message dedup in `clinic_core.message_dedupe` → tenanted workflow → tenanted schema  

### Critical Handoff Dependencies

**To Penguin (urgent):**
- Finalize `clinic_core.tenants` table schema (Gordon needs for webhook routing)
- Define RLS policies for WhatsApp credential isolation
- Migration path for existing `dra_andreia` schema

**From Penguin (waiting):**
- Schema design decision
- Multi-tenant table structures

**To Lucius:**
- Tenant detection from webhook path → parameterize all SQL queries
- Tool invocation should include tenant_code in function signature

**To Ivy:**
- Prompt composition should key on professional_id (Gordon provides this via webhook routing)
- Cost tracking table per tenant (required for SaaS billing)

### Questions Raised to Coordinator

1. EvolutionAPI multi-instance limits (how many simultaneous instances)?
2. QR code reconnection process for EvolutionAPI sessions (ops runbook needed)
3. Fallback strategy if EvolutionAPI becomes unavailable (Cloud API migration timeline)

### Phase 2 Start Gate

✓ Architecture approved by team  
⏳ Awaiting Coordinator sign-off  
⏳ Awaiting Penguin schema design finalization

---

## Key Files & Paths

- Team roster: `.squad/team.md`
- Routing rules: `.squad/routing.md`
- Decisions: `.squad/decisions.md`
- Project root: `/Users/dalifreire/Documents/BahiaTI/agentes-n8n/clinicas/n8n-whatsapp-clinicas`
