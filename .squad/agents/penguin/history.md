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

---

## 2026-04-27: Multi-Tenant Database Schema Rework

**Task:** Transform single-tenant `dra_andreia` schema into generic multi-tenant platform supporting isolated assistants per professional.

**Deliverables:**
1. ✅ **SUPABASE_SETUP.sql** - New multi-tenant SQL with 5 parts:
   - Part 1: Platform Registry (`clinic_core` schema) - 6 tables for tenant management
   - Part 2: Tenant Management Functions - query helpers, registration, provisioning
   - Part 3: Preserved `dra_andreia` schema - complete original structure retained
   - Part 4: Migration examples - register existing tenant, provision new ones
   - Part 5: Helper queries for n8n/Python integration

2. ✅ **SUPABASE_SETUP_V1_SINGLE_TENANT.sql** - Backup of original for reference

**Architecture Decisions:**

### 1. Schema-Per-Professional Isolation
- Each professional gets own PostgreSQL schema (e.g., `prof_carlos_5678`)
- Strong data isolation for HIPAA/LGPD compliance
- Dra. Andreia's existing `dra_andreia` schema preserved without migration

### 2. Platform Registry Tables (clinic_core schema)
- **organizations**: Optional clinic grouping
- **professionals**: Primary tenant registry (schema_name, tenant_code, config)
- **whatsapp_instances**: 1:1 WhatsApp account per professional
- **assistant_configs**: AI settings (prompts, models, RAG config, enabled tools)
- **usage_logs**: Daily cost tracking per professional (messages, tokens, costs in cents)
- **audit_log**: Platform-wide security/compliance audit trail

### 3. Safe Dynamic Schema Operations
- **All** dynamic SQL uses `format('%I', schema_name)` for identifier safety
- Schema name validation: `^[a-z][a-z0-9_]{2,62}$` (lowercase alphanumeric + underscore)
- Tenant code validation: `^[a-z0-9][a-z0-9-]{1,98}[a-z0-9]$` (URL-safe)
- Rollback on error in provisioning functions

### 4. Key Functions Created

**get_professional_context(tenant_code|phone)**
- Query helper for n8n webhook router
- Input: tenant_code from `/webhook/{tenant_code}` OR phone number
- Returns: professional_id, schema_name, config, assistant_config, whatsapp_phone
- Used in EVERY n8n workflow to load tenant context

**register_existing_tenant()**
- Migrates existing schema (dra_andreia) into platform registry
- No data movement needed - just metadata registration
- Creates professional, whatsapp_instance, assistant_config entries

**provision_professional_schema(schema_name)**
- Creates isolated schema for new professional
- Core tables: conversas, usuarios, documentos (RAG), with RLS policies
- Creates schema-specific functions (atualizar_atualizado_em, buscar_documentos_similares)
- NOTE: Currently creates minimal viable schema; production needs full table set

### 5. Migration Strategy for Dra. Andreia
```sql
-- Step 1: Run full SUPABASE_SETUP.sql (creates clinic_core + preserves dra_andreia)
-- Step 2: Register as first tenant
SELECT clinic_core.register_existing_tenant(
  p_schema_name := 'dra_andreia',
  p_tenant_code := 'dra-andreia',
  p_full_name := 'Andreia Mota Mussi',
  p_credential_type := 'CRO',
  p_credential_number := '4407',
  p_phone := '7133537900',
  p_whatsapp_phone := '5571999887766',
  p_whatsapp_provider := 'evolution-api'
);
-- Step 3: Update n8n workflows to query tenant context first
-- Step 4: Add new professionals via provision_professional_schema()
```

### 6. n8n Integration Pattern
```
Webhook receives: /webhook/{tenant_code}
  ↓
Extract tenant_code from path
  ↓
Query: SELECT * FROM clinic_core.get_professional_context(p_tenant_code := tenant_code)
  ↓
Get: schema_name, professional_id, config, assistant_config
  ↓
Dynamic query to tenant schema:
  SELECT * FROM {schema_name}.conversas WHERE telefone = :phone
  (Use PostgreSQL node with safe parameterization)
  ↓
Track usage: INSERT INTO clinic_core.usage_logs (...)
```

### 7. Python RAG Scripts Integration
- Update `knowledge_base_indexar.py` to iterate `clinic_core.professionals`
- For each professional:
  - Connect to their schema (from `schema_name`)
  - Index documents in `{schema_name}.documentos`
  - Generate embeddings scoped to professional
- Isolation: Same phone can exist in multiple professionals' patient tables

**Handoffs to Team:**

**→ Lucius (n8n):**
- Inbound webhook router must extract tenant_code from path
- Every workflow needs `get_professional_context()` call first
- All database queries must use dynamic schema from context
- Update hardcoded `dra_andreia` refs in 70+ locations

**→ Ivy (AI/RAG):**
- Prompt templates now in `assistant_configs` table (5-layer system)
- RAG queries must use `{schema_name}.buscar_documentos_similares()`
- Update indexing scripts to loop professionals
- Assistant persona configurable per professional

**→ Gordon (WhatsApp):**
- Webhook routing pattern: `/webhook/{tenant_code}`
- Phone → professional mapping via `whatsapp_instances` table
- Each professional has isolated WhatsApp account

**Critical Files:**
- `/Users/dalifreire/Documents/BahiaTI/agentes-n8n/clinicas/n8n-whatsapp-clinicas/SUPABASE_SETUP.sql` (NEW - 2223 lines)
- `SUPABASE_SETUP_V1_SINGLE_TENANT.sql` (backup reference)
- Platform registry: `clinic_core` schema with 6 tables
- 21 functions created (3 platform functions + 18 preserved from dra_andreia)

**Production Notes:**
- `provision_professional_schema()` currently creates minimal schema
- For production: extend to create all 20+ tables from dra_andreia template
- Consider creating `tools/provision_tenant_full.sql` with complete structure
- Supabase Vault should store API keys (OpenAI, Evolution), not in config JSONB
- RLS policies currently basic (`auth.role() = 'authenticated'`)
- For JWT-based professional isolation, add `auth.jwt() ->> 'professional_id'` checks

**Testing Checklist:**
1. ✅ Schema validation regex patterns
2. ✅ Safe identifier formatting (format(%I))
3. ⏳ Provision test schema
4. ⏳ Register dra_andreia as tenant
5. ⏳ Query context by tenant_code
6. ⏳ Dynamic query to tenant schema from n8n

---

## 2026-04-27: Reminders Workflow Fix (B4 Resolution)

**Task:** Fix rejected generic reminders n8n workflow to align with Bruce's ADR schema contract.

**Problem:** The workflow was using string concatenation to inject schema names in static SQL (`FROM ' || t.schema_name || '.lembretes r`), which is syntactically invalid and a security risk (rejection defect B4).

**Solution Implemented:**

1. **Replaced SQL query** in "Buscar Lembretes Pendentes" node:
   - **Before:** Dynamic `CROSS JOIN LATERAL` with string concatenation on `schema_name`
   - **After:** Single call to `clinic_core.fetch_due_reminders_all(30)`
   - Eliminates all schema name interpolation from n8n SQL

2. **Updated column references** in "Preparar Mensagens" node:
   - Old columns: `telefone_paciente`, `nome_paciente`, `evolution_instance_name`, `tipo`, `mensagem`, `data_consulta`, `hora_consulta`, `nome_profissional`
   - New columns (ADR §4.2): `patient_phone_e164`, `patient_name`, `reminder_type`, `payload` (jsonb with template variables)
   - Preserved tenant context: `tenant_code`, `schema_name`, `professional_id`

3. **Added "Load Tenant Context" node** between message prep and WhatsApp send:
   - Calls `clinic_core.get_professional_context($tenant_code)` per reminder
   - Retrieves `whatsapp_instance_id` for Evolution API routing
   - Replaces hardcoded `evolution_instance_name` field

4. **Updated WhatsApp send node**:
   - Instance ID now from `$('Load Tenant Context').first().json.whatsapp_instance_id`
   - Phone and message from `$('Preparar Mensagens').item.json.*` (explicit node reference)

5. **Replaced UPDATE query** in "Marcar como Enviado" node:
   - **Before:** Direct `UPDATE {{ $json.schema_name }}.lembretes ...` (schema interpolation in n8n)
   - **After:** Call to `clinic_core.mark_reminder_sent($tenant_code, $reminder_id, 'enviado', $provider_message_id)`
   - All dynamic schema work now encapsulated in SQL function

**Alignment with ADR Contract:**
- ✅ §4.3: Single SQL call `clinic_core.fetch_due_reminders_all()` with no schema interpolation
- ✅ §4.4: Platform dispatcher function for marking sent
- ✅ §2: Uses `get_professional_context()` for tenant metadata
- ✅ No `' || schema_name || '` patterns anywhere
- ✅ Preserves tenant/professional context for downstream nodes
- ✅ JSON validated successfully

**Files Modified:**
- `n8n/WhatsApp - Enviar Lembretes Automáticos (Generic).json`
- `.squad/agents/penguin/history.md` (this file)
- `.squad/decisions/inbox/penguin-reminders-workflow-fix.md` (decision record)

**Dependencies on Lucius:**
- SQL functions `clinic_core.fetch_due_reminders_all()` and `clinic_core.mark_reminder_sent()` must be implemented per ADR §4.2 and §4.4
- Per-tenant function `<schema>.fetch_due_reminders()` created by provisioner (ADR §4.1)
- Per-tenant function `<schema>.mark_reminder_sent()` created by provisioner (ADR §4.4)

**Next Steps:**
1. Lucius implements the SQL functions in `SUPABASE_SETUP.sql`
2. End-to-end test with two tenants to verify isolation
3. Verify provider message ID capture from Evolution API response


## 2026-04-27: SQL Reference Cleanup - Generic Platform Hardening

**Task:** Remove Dra. Andreia references from active SQL/docs to ensure platform appears fully generic.

**Problem:** User concern - "ainda vejo muitas referencias a dra andreia no projeto" - legacy tenant references made product appear single-purpose instead of multi-tenant SaaS platform.

**Changes Made:**

1. **SUPABASE_SETUP.sql** (Active Setup):
   - ✅ Converted PART 6 legacy seed from active execution to commented example template
   - ✅ Replaced hardcoded `dra_andreia` schema with `your_existing_schema` placeholder
   - ✅ Replaced personal details with generic placeholders (Professional Full Name, tenant-code, etc.)
   - ✅ Added clear documentation: "Uncomment and customize if you need to adopt an existing schema"
   - **Result:** Zero Dra. Andreia references in active SQL - only in commented example block

2. **MULTI_TENANT_QUICK_START.md** (Team Integration Guide):
   - ✅ Section 2: "Register First Professional (Example)" - replaced specific Dra. Andreia registration with generic template
   - ✅ Architecture diagram: Replaced `dra_andreia` with `prof_joao_1234` (generic example)
   - ✅ Code examples: Changed `schema_name = 'dra_andreia'` to `'prof_joao_1234'`
   - ✅ Migration checklist: "Replace hardcoded schema names" instead of "Replace `dra_andreia`"
   - ✅ Python examples: Generic "hardcoded_schema" instead of "dra_andreia"
   - ✅ Next Steps: "Test with your first professional" instead of "Test with Dra. Andreia"
   - **Result:** Zero Dra. Andreia references - all examples use generic placeholders

3. **.gitignore** (Repo Cleanliness):
   - ✅ Added `*.backup` to ignore backup files (SUPABASE_SETUP.sql.backup)
   - ✅ Added `*_V1_SINGLE_TENANT.sql` to ignore old single-tenant versions
   - ✅ Added `.multi-tenant-migration-complete.txt` marker file
   - ✅ Added `atualizar_knowledge_base.log` (generated logs)
   - **Result:** Backup/migration artifacts no longer pollute repo listing

**Validation Results:**

```bash
# Active product files (SQL + Quick Start docs):
grep -i "andreia\|dra" SUPABASE_SETUP.sql | wc -l
# → 0 references (was 4 in active code)

grep -i "andreia\|dra" MULTI_TENANT_QUICK_START.md | wc -l  
# → 0 references (was 11)
```

**SQL Integrity Checks:**
- ✅ 23 functions defined (no duplicates)
- ✅ 9 clinic_core functions present and correct
- ✅ Extensions, schemas, tables, indexes all intact
- ✅ PART 6 legacy adoption block is valid commented SQL (ready to use if needed)

**Remaining References Analysis:**

**Acceptable (Legacy Context):**
- `n8n/legacy-dra-andreia/*` - Original workflows in clearly marked legacy folder (13 files)
- `.squad/agents/*/history.md` - Historical team logs (5 files)
- `.squad/decisions.md` - Architecture decision record with project history
- `knowledge_base.json`, `KNOWLEDGE_BASE_MULTI_TENANT.md`, `SUMMARY_MULTI_TENANT_KB.md` - Content files (not platform code)

**To be Refactored (Other Teams):**
- `knowledge_base_*.py` - Python RAG scripts (3 files) → Assigned to Ivy for multi-tenant loop refactor
- `n8n/MIGRATION-GUIDE.md`, `n8n/README.md`, `n8n/WORKFLOW-STRUCTURE.md` → Assigned to Lucius for doc updates

**Key Outcome:**
- ✅ Active platform setup (SUPABASE_SETUP.sql) is now **100% generic**
- ✅ Quick start guide uses only **generic professional placeholders**
- ✅ Backup files no longer clutter git status
- ✅ Legacy adoption path preserved as **optional commented example**
- ✅ Fresh installs look like multi-tenant SaaS platform, not dentist-specific tool

**Files Modified:**
- `SUPABASE_SETUP.sql` - Commented out Dra. Andreia seed block
- `MULTI_TENANT_QUICK_START.md` - All examples now generic
- `.gitignore` - Ignore backup/migration artifacts

**Handoffs:**
- **Ivy:** Refactor `knowledge_base_*.py` to iterate all professionals (not hardcoded)
- **Lucius:** Update n8n documentation (MIGRATION-GUIDE.md, README.md, WORKFLOW-STRUCTURE.md)

