# Team Decisions — Generic Clinic Platform Architecture

**Version:** 2  
**Last Updated:** 2026-04-27T21:15:32Z  
**Status:** Active — Phase 1 (Design) Complete, Phase 2 (Implementation) Pending Coordinator Approval

---

## [2026-04-27T17:20:09-03:00] User Directive

**By:** Dali Freire (via Copilot)  
**What:** Transform project from dentist-specific reference to generic multi-tenant platform. Enable isolated assistants per professional, sold/added progressively using shared infrastructure.  
**Why:** Strategic pivot to generic SaaS clinic assistant product  
**Status:** ✓ Accepted — Squad design complete

---

## [2026-04-27 17:05–21:15] Squad Architecture Design Phase

### Summary

Five specialist agents completed isolated analyses:
- **Bruce:** Platform architecture (3-tier model, schema isolation)
- **Gordon:** WhatsApp integration (instance-per-professional, webhook routing)
- **Penguin:** Database design (multi-tenant RLS, entity model)
- **Lucius:** Workflow generalization (70+ hardcoded refs → parameterized)
- **Ivy:** AI assistant composition (5-layer prompt, per-prof RAG)

**Outcome:** Comprehensive multi-tenant architecture proposal ready for implementation.

---

## [APPROVED] Decision 1: Platform Architecture — 3-Tier Model

**Owner:** Bruce (Lead Architect)  
**Date:** 2026-04-27  
**Priority:** CRITICAL  
**Status:** PROPOSED → Awaiting Coordinator Approval  

### The Model: Platform → Clinic → Professional

```
Platform (Shared Infrastructure)
  └─ Clinic (Tenant Container)
      └─ Professional (Isolation Unit)
          ├─ WhatsApp Instance (isolated phone)
          ├─ Assistant Config (isolated)
          ├─ Knowledge Base / RAG (professional-scoped)
          ├─ Conversation History (professional-scoped)
          ├─ Patient Records (professional-scoped)
          └─ Appointments (professional-scoped)
```

### Shared Infrastructure Components

- **n8n Orchestration:** Single instance, multi-workflow (tenant-aware routing)
- **Supabase/PostgreSQL:** Single database, multi-schema (schema-per-professional)
- **OpenAI API:** Shared key, usage tracked per professional/tenant
- **EvolutionAPI Gateway:** Multi-instance manager with tenant routing
- **Python Batch Jobs:** Tenant-aware indexing, embedding generation

### Key Benefits

1. ✓ Cost-efficient shared infrastructure
2. ✓ Regulatory compliance (LGPD/HIPAA) via schema isolation
3. ✓ Professional independence (no cross-contamination)
4. ✓ Simple backup/restore per professional
5. ✓ Predictable performance (no cross-tenant interference)

### Phase 2 Validation Path

Use Dra. Andreia as first migration target after platform base ready.

---

## [APPROVED] Decision 2: Tenant Isolation — Schema-Per-Professional

**Owner:** Penguin (Database Engineer)  
**Date:** 2026-04-27  
**Priority:** CRITICAL  
**Status:** PROPOSED → Awaiting Coordinator Approval  

### Why Schema-Per-Professional (vs Alternatives)

- ✓ Strong data isolation (healthcare compliance)
- ✓ Easy backup/restore per professional
- ✓ Predictable performance (no cross-tenant query impact)
- ✓ Simple migration from current `dra_andreia` schema
- ⚠ Migration complexity (N schemas)
- ⚠ Connection pool management

### Tenant Hierarchy

```
organizations (clinic/group)
  ├─ professionals (individual practitioners)
  │   ├─ assistant_instances (1:1 per professional)
  │   ├─ whatsapp_instances (dedicated account)
  │   ├─ patients (professional-scoped)
  │   ├─ conversations (professional-scoped)
  │   ├─ appointments (professional-scoped)
  │   ├─ documentos + embeddings (RAG, professional-scoped)
  │   └─ ... (all tables per-professional)
```

### Platform Registry (Shared `clinic_core` Schema)

**Table: `clinic_core.tenants`**
- Central tenant registry
- Phone number → professional mapping
- Webhook path routing
- Subscription/trial tracking
- Provider config (EvolutionAPI instance, Cloud API IDs)
- Status (active, suspended, trial)

### Data Isolation Boundaries

1. **Organization Level:** Optional grouping (clinic name, shared settings)
2. **Professional Level:** PRIMARY ISOLATION UNIT
   - Each professional has own schema
   - RLS policies enforce professional boundaries
3. **Patient Uniqueness:** `(professional_id, phone)` compound key
   - Same phone valid for different professionals
   - Enables clinic-wide contact reuse

### Row-Level Security (RLS)

- PostgreSQL RLS policies on `professionals` table
- Professional user can only access own tenant data
- Cascading constraints prevent cross-professional queries

---

## [APPROVED] Decision 3: WhatsApp Integration — Instance-Per-Professional

**Owner:** Gordon (Backend & WhatsApp)  
**Date:** 2026-04-27  
**Priority:** CRITICAL  
**Status:** PROPOSED → Awaiting Coordinator Approval  

### Instance Model

Each professional gets:
- **Dedicated WhatsApp Business Account** (unique phone number)
- **Unique tenant ID** (e.g., `dra-andreia`, `dr-carlos`)
- **Isolated database schema** per tenant
- **Routing infrastructure** for message flow

### Webhook Routing Pattern (CHOSEN)

**Pattern:** `/webhook/{tenant_code}`

**Advantages:**
- ✓ Simple routing logic (tenant code in path)
- ✓ Easy debugging (tenant visible in logs)
- ✓ Natural isolation
- ✓ Works with both EvolutionAPI and Cloud API

**Example:**
```
https://your-domain.com/webhook/dra-andreia
https://your-domain.com/webhook/dr-carlos
https://your-domain.com/webhook/dra-maria

n8n: Single generic webhook handler extracts tenant_code and routes
```

### Idempotency & Message Deduplication

- **Message ID mapping:** Store provider msg_id → conversation_id
- **Duplicate detection:** Check before processing
- **Webhook timeout handling:** Built-in retry mechanism
- **State machine:** Conversation states tracked per tenant

### Secrets Management (Zero-Trust)

- ✓ All API keys → Supabase Vault (never hardcoded)
- ✓ Per-professional encryption keys
- ✓ Webhook signature verification (provider validation)
- ✓ Audit logging for all auth events

### MVP & Evolution

**MVP:** EvolutionAPI-first (simpler deployment, better for testing)  
**Phase 3+:** Official WhatsApp Cloud API (premium/compliance tier)

---

## [APPROVED] Decision 4: Workflow Generalization — Parameterized Set

**Owner:** Lucius (n8n Specialist)  
**Date:** 2026-04-27  
**Priority:** CRITICAL  
**Status:** PROPOSED → Awaiting Coordinator Approval  

### Current State: 70+ Hardcoded References

**Identified across workflows, schema, prompts, tools:**

```
Example Current Workflow:
- Webhook path: "dra-andreia-whatsapp-webhook"
- Database schema: "dra_andreia" (~70 SQL queries)
- Prompt: Hardcoded "Dra. Andreia Mota Mussi", "Ana", CRO 4407, hours, address
- Evolution instance: "Dra Andreia Mota Mussi"
- Knowledge base IDs: Pattern "dra_001_"
```

### Proposed Architecture: Generic Parameterized Workflows

**Model:** One generic workflow set + inbound router, all tenant-aware

**Components:**

1. **Inbound Router Workflow**
   - Receives webhook at `/webhook/{tenant_code}`
   - Extracts tenant ID from path
   - Loads tenant config from database
   - Routes to main assistant workflow
   
2. **Generic Assistant Workflow** (tenant-parameterized)
   - Receives tenant_id as context
   - Loads professional config dynamically
   - Builds prompt from 5-layer template system (see Decision 5)
   - Executes shared tool set with tenant injection
   - Stores conversation in tenant schema
   - Tracks cost per tenant
   
3. **Parameterized Tools** (Sub-workflows)
   - Accept tenant_id as parameter
   - Query tenant-specific schema dynamically
   - Return results in standard format
   - Example: "Agendar Consulta" → refactored to `schedule_appointment({tenant_id}, params)`

### Phased Implementation

**Phase 1 (MVP):** Router + core assistant flow (existing tools disabled)  
**Phase 2:** Tool generalization (9 tools refactored with tenant injection)  
**Phase 3:** Advanced features (scheduling engine rewrite, payment integration)

---

## [APPROVED] Decision 5: AI Assistant Architecture — 5-Layer Composition

**Owner:** Ivy (AI Engineer)  
**Date:** 2026-04-27  
**Priority:** CRITICAL  
**Status:** PROPOSED → Awaiting Coordinator Approval  

### Problem: 73 Hardcoded AI Elements

Current prompt hardcodes:
- Persona: "Ana"
- Professional: "Dra. Andreia Mota Mussi", CRO 4407, specialties
- Location: Full address, phone, Instagram
- Hours: Specific schedule
- Tools: 9 hardcoded sub-workflows
- Schema: References to `dra_andreia.*` tables

### Solution: 5-Layer Composable Prompt Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 1: Base Product Prompt (Shared)                        │
│   • Core conversation protocols, WhatsApp optimizations      │
│   • General safety rules, escalation guidelines              │
│   • Tool usage framework                                      │
└──────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────┐
│ Layer 2: Clinic Context (from clinics table)                │
│   • Clinic-level policies, team info, service offerings     │
└──────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────┐
│ Layer 3: Professional Context (individual practitioner)      │
│   • Name, credentials (CRO/CRM), specialties, preferences    │
│   • Enabled tools and individual protocols                   │
└──────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────┐
│ Layer 4: Assistant Persona (custom identity)                │
│   • Name, personality, tone, communication style            │
│   • Language preferences                                     │
└──────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────┐
│ Layer 5: Service Context (operational)                      │
│   • Hours, contact (phone, address), social media           │
│   • Location-specific information                            │
└──────────────────────────────────────────────────────────────┘
```

### Storage & Versioning

- **Layer Templates:** `public.prompt_templates` (versioned by layer)
- **Professional Overrides:** `public.clinicas.configuracao_ia` (JSONB)
- **Dynamic Construction:** n8n JavaScript engine (references Lucius doc)
- **A/B Testing:** `prompt_version` field for experimentation

### RAG & Knowledge Base Isolation

**Current:** All docs in single `dra_andreia.documentos` table

**Target:** Per-professional pgvector isolation

- Each professional gets own KB schema section
- Embeddings indexed by professional_id
- Similarity search scoped to professional only
- Supports custom embedding models per professional (future)

### Session Management

**Session Key:** `{professional_id}:{patient_id}`

- Conversation history keyed by (professional, patient)
- Context window: 15 messages (configurable per professional)
- Memory not shared across patients/professionals

### Safety & Compliance

**Guardrails:**
- Content filtering (inappropriate language)
- Escalation rules (medical emergencies → human escalation)
- LGPD compliance (data residency, retention policies)
- Cost tracking (per-professional attribution)

**Model Support:**
- Base: GPT-4o (configurable)
- Per-professional override capability
- A/B testing support via `prompt_version`

---

## [OPEN] Business Questions Requiring Coordinator Input

**From:** Penguin (Database), team consensus  
**Impact:** Schema design, billing model, feature scope  

1. **Patient Sharing Across Professionals**
   - Can same patient contact multiple professionals in same clinic?
   - **Impact:** Unique constraint design, contact deduplication
   
2. **Knowledge Base Scope**
   - Per-professional KB or shared across clinic?
   - **Impact:** Schema isolation, embedding management, update complexity
   
3. **Pricing Model**
   - Per-professional or per-clinic subscription?
   - **Impact:** Billing tables, usage aggregation, cost tracking
   
4. **Multilingual Support**
   - Languages needed? (Portuguese, English, Spanish, etc.)
   - **Impact:** Prompt composition, RAG embedding models, API costs

---

## Proposed Migration Timeline

**Phase 1 (Current):** ✓ Architecture Design Complete  
**Phase 2 (Pending Approval):** Implement platform base (~2–3 weeks)
- Create `clinic_core.tenants` registry
- Build generic workflows + inbound router
- Migrate Dra. Andreia as validation
- Deploy to staging environment

**Phase 3:** Full tool migration & optimization (~3–4 weeks)
- Refactor 9 existing tools for multi-tenant use
- RAG isolation implementation
- Performance tuning & cost optimization

**Phase 4:** Sales & Onboarding
- Marketing materials
- Onboarding workflows
- Professional signup portal

---

## Decision Approval Flow

| Decision | Owner | Status | Coordinator Approval |
|----------|-------|--------|----------------------|
| Platform 3-tier model | Bruce | PROPOSED | Pending |
| Tenant isolation (schema-per-prof) | Penguin | PROPOSED | Pending |
| WhatsApp instance-per-prof | Gordon | PROPOSED | Pending |
| Workflow generalization | Lucius | PROPOSED | Pending |
| AI 5-layer composition | Ivy | PROPOSED | Pending |

**Next Step:** Coordinator review & approval of all 5 decisions before Phase 2 begins.

---

## Notes

- All detailed proposals available in `.squad/orchestration-log/` and `.squad/agents/{name}/` directories
- Team consensus on all architectural decisions
- Ready to proceed with implementation upon approval
