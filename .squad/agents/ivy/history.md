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

### Generalized Multi-Tenant Knowledge Base (2025-01-24)

**Task:** Generalize AI/RAG knowledge base layer for multi-professional support while keeping Dra. Andreia as seed tenant.

**Changes Made:**

1. **knowledge_base.json** — Added multi-tenant schema v2.0.0:
   - Added `professionals` array with metadata (professional_id, name, specialty, active status, is_seed flag)
   - Added `professional_id` field to all existing documents (mapped to "dra-andreia")
   - Schema version 2.0.0 signals multi-tenant support to all scripts
   - Backwards compatible: existing 7 documents preserved with professional_id

2. **knowledge_base_indexar.py** — Generalized indexing with professional isolation:
   - Added `--professional-id` CLI arg (default: env PROFESSIONAL_ID or "dra-andreia")
   - Added `--all` flag to index all professionals in knowledge base
   - Dynamic schema name resolution: `get_professional_schema(professional_id)` → converts "dra-andreia" to "dra_andreia"
   - `load_knowledge_base()` filters documents by professional_id, validates schema version
   - `validate_documents_table()` checks for professional_id column, warns if missing (legacy support)
   - `store_documents()` includes professional_id in INSERT (falls back to legacy if column missing)
   - `test_similarity_search()` scopes queries by professional_id
   - Per-professional embedding generation and storage in isolated schemas
   - Clear error messages when professional_id not found

3. **knowledge_base_atualizar.py** — Multi-tenant web scraping and update:
   - Converted `CONSULTORIO_CONFIG` to `PROFESSIONALS_CONFIG` dict (keyed by professional_id)
   - Added `get_professional_config(professional_id)` with validation
   - `WebSiteScraper` and `InstagramScraper` classes now accept professional_id in constructor
   - Document IDs auto-prefixed with professional_id (e.g., "dra_andreia_web_...")
   - CLI args: `--professional-id`, `--all` to update multiple professionals
   - `KnowledgeBaseManager.load()` ensures multi-tenant schema on load
   - `validate()` checks for missing professional_id, verifies registered professionals have documents
   - `report()` shows per-professional document counts with active status indicators

4. **knowledge_base_consultorio.py** — Generic document templates:
   - Added `DEFAULT_PROFESSIONAL_ID` from env (fallback: "dra-andreia")
   - All 42 generic documents now include `professional_id: DEFAULT_PROFESSIONAL_ID`
   - Documents are now templates for any professional (scheduling, procedures, health tips, FAQ)
   - Script can be run with `PROFESSIONAL_ID=dr-carlos python knowledge_base_consultorio.py` for new tenants

**Architecture Decisions:**
- **Professional ID as Isolation Key:** professional_id (e.g., "dra-andreia", "dr-carlos") is primary tenant identifier
- **Schema Naming Convention:** professional_id with hyphens → database schema with underscores (dra-andreia → dra_andreia)
- **Seed Tenant Pattern:** Dra. Andreia marked with `is_seed: true` in professionals array, serves as demo/reference
- **Backwards Compatibility:** Scripts detect schema version, fall back gracefully if professional_id column missing
- **Default Behavior:** All scripts default to "dra-andreia" if no professional specified (env or CLI)
- **Clear Error Messages:** Scripts fail fast with helpful messages when professional_id not found, listing available options

**Testing & Validation:**
- Python syntax validated: all 3 scripts compile without errors
- Validation test: 7 docs, 1 professional, 0 issues ✓
- Report test: Shows per-professional breakdown with active status ✓
- Backwards compatibility: existing seed tenant (dra-andreia) preserved

**Coordination Notes:**
- **To Penguin (Database):** Need professional_id column in {schema}.documentos tables for full multi-tenant isolation
- **To Lucius (n8n):** Workflows must pass professional_id when calling indexing/query scripts (via env or CLI args)
- **To Bruce (Architecture):** Confirmed schema-per-professional naming convention (hyphen to underscore conversion)

**Key File Paths:**
- Knowledge base: `knowledge_base.json` (schema v2.0.0)
- Indexing script: `knowledge_base_indexar.py` (multi-tenant aware)
- Update script: `knowledge_base_atualizar.py` (web scraping per professional)
- Seed documents: `knowledge_base_consultorio.py` (generic templates)

**User Preferences Learned:**
- Prefer kebab-case for professional IDs (human-readable identifiers)
- Keep Portuguese content for Brazilian market
- Maintain backwards compatibility where feasible
- Fail fast with clear errors rather than silent fallbacks to wrong data

---

## Main Workflow Fix — Post-Rejection Revision (2026-04-27)

**Context:** Bruce rejected Lucius's generic main workflow for defects B5 (invalid JS escapes in prompt composition) and B6 (hardcoded `dra_andreia`). Lucius locked out; Ivy assigned to fix prompt/persistence nodes.

**Changes Made:**

1. **Load Tenant Config (B3 contract alignment)**
   - Changed from ad-hoc JOIN query to canonical `clinic_core.get_professional_context($1)` function
   - Now consumes standardized output fields: `full_name`, `nome`, `specialties`, `credential_type/number`, `organization_name/address/phone/hours/instagram`, `assistant_persona_name`, `assistant_tone`, `prompt_config`, `whatsapp_instance_id`, `whatsapp_phone_e164`
   - Ensures all tenants route through single contract point (Bruce's ADR §2)

2. **Compose AI Prompt (B5 JS syntax fix)**
   - Replaced all `\`` (escaped backticks) with proper `` ` `` in template literals
   - 12 template strings now syntactically valid JavaScript after JSON decode
   - Updated field references to match canonical schema: `organization_name` (was `clinic_name`), `full_name`/`nome` alias, `specialties` array, `credential_type`+`credential_number`, `assistant_persona_name` (was `assistant_name`), `assistant_tone`, `prompt_config` (was `ai_config`)
   - Preserved 5-layer architecture: Base → Clinic → Professional → Persona → Tools
   - Added array handling for `specialties` (supports both array and string legacy formats)
   - Added Instagram `@` prefix handling for `organization_instagram`
   - Returns: `professional_id`, `tenant_code`, `schema_name`, `whatsapp_instance_id` (aligned with canonical fields)

3. **Salvar Conversa no BD (B6 hardcode removal)**
   - Changed `schema.value` from literal `"dra_andreia"` to `"={{ $('Load Tenant Config').first().json.schema_name }}"`
   - Changed `mode` from `"list"` to `"id"` (expression-based schema selection)
   - Removed `cachedResultName: "dra_andreia"`
   - Conversation persistence now tenant-scoped dynamically; second professional will write to their own schema

**Architecture Decisions:**
- **Contract adherence:** All workflow nodes now consume only the fields exposed by `get_professional_context()`. No ad-hoc queries against platform tables.
- **Field name consistency:** Prompt composition uses canonical English names (`full_name`, `specialties`, `organization_*`) but preserves Portuguese alias `nome` for backwards compat with Layer 4 overrides.
- **Graceful degradation:** Prompt layers fall back to sensible defaults when optional fields (`organization_name`, `organization_hours`) are NULL.
- **JSON structure handling:** `organization_hours` is JSONB; stringified in prompt. `specialties` is text[] in DB; joined with `, ` in prompt.

**Validation:**
- JSON syntax valid (jq parse successful)
- 0 escaped backticks remain in jsCode (was causing `SyntaxError` on first run)
- 12 proper backticks present (6 template literal pairs)
- `Load Tenant Config` query matches Bruce's ADR function signature exactly
- `Salvar Conversa no BD` schema reference is expression-based, no hardcoded tenant

**Coordination:**
- Ivy now blocked until Lucius delivers matching SQL with `clinic_core.get_professional_context()` implementation and Penguin delivers reminders dispatcher
- Assumes Penguin's SQL will create `<schema>.conversas` table matching the legacy `dra_andreia.conversas` structure (telefone, nome, mensagem, resposta_ia, contexto_rag columns)
- Workflow passes `whatsapp_instance_id` (not `evolution_instance_name`) to downstream send nodes — assumes Gordon/Lucius coordinate on Evolution/CloudAPI adapter

**Defects Closed:**
- ✅ B5: `Compose AI Prompt` JS syntax now valid (proper template literals)
- ✅ B6: `Salvar Conversa no BD` no longer hardcodes `dra_andreia`
- ✅ B3 (partial, Ivy's scope): Workflow reads canonical contract shape; SQL implementation is Lucius's deliverable

**Key Learnings:**
- **n8n JSON escaping:** When embedding JavaScript in n8n JSON, template literal backticks must be bare `` ` `` in the `jsCode` string field. The `\`` pattern survives JSON encoding but becomes `\` + `` ` `` after parsing, which is invalid JS. Always test deserialized JS before committing.
- **Expression-mode schema selection:** n8n Postgres node's `schema` parameter supports `mode: "id"` with n8n expression syntax (`={{ ... }}`). This enables dynamic schema routing without SQL injection risk (n8n evaluates expression, then passes schema name to Postgres protocol).
- **JSONB in prompts:** Bruce's ADR stores `organization_hours` as JSONB (structured: `{"mon": [["08:00","18:00"]], ...}`). For prompt injection, `JSON.stringify()` is safest short-term (human-readable dict in AI context). Long-term: dedicated formatter function for natural language ("Seg-Sex 08:00-18:00").
- **Array fields in Postgres:** `specialties text[]` must be handled as array in prompt composition. Used `Array.isArray()` check + `.join(', ')` with fallback to string for legacy single-value data.
- **Canonical function contract is non-negotiable:** Bruce's ADR §2 rule #2: "One entry point per consumer concern." Workflows must NOT query `clinic_core.professionals` / `organizations` directly, even if it seems simpler. All access through `get_professional_context()`. This is the integration contract; breaking it fails code review.

---

## Generic Product Cleanup — Dra. Andreia Reference Removal (2026-04-27)

**Context:** User (Dali) reported "ainda vejo muitas referencias a dra andreia no projeto" — requested cleanup to present generic clinic assistant product, not hardcoded to one dentist.

**Task:** Remove Dra. Andreia as default/identity. Keep only as optional demo data, clearly isolated.

**Changes Made:**

1. **knowledge_base.json** (2.5KB)
   - Moved all 7 Dra. Andreia documents from active `professionals`/`documentos` arrays to new `_demo_data` section
   - Active base now empty: `"professionals": []`, `"documentos": []`
   - Demo professional marked with `"active": false, "is_demo_data": true`
   - Clear separation: product ships empty, historical data preserved for migration reference only

2. **knowledge_base_indexar.py**
   - Changed `DEFAULT_TENANT_CODE` from `"dra-andreia"` to `"tenant-demo"` with comment "Default for demo/migration mode"
   - Removed default fallback: `TENANT_CODE = os.getenv(..., None)` — REQUIRES explicit tenant
   - Added error message when no tenant specified: "Use --tenant-code <code> or set TENANT_CODE environment variable"
   - Updated docstring examples: `dra-andreia` → `profissional-demo`
   - Updated CLI help text to clarify no default

3. **knowledge_base_atualizar.py**
   - Changed `DEFAULT_PROFESSIONAL_ID` from `"dra-andreia"` to `None`
   - Cleared `PROFESSIONALS_CONFIG` dict — now empty template with commented examples
   - Commented out Dra. Andreia config with key `"_dra-andreia"` (underscore prefix = disabled)
   - Added generic example config `"profissional-demo"` in comments
   - Updated docstring examples and error messages to use generic names

4. **knowledge_base_consultorio.py**
   - Removed default: `DEFAULT_PROFESSIONAL_ID = os.getenv(..., None)` — REQUIRES explicit env var
   - Added validation: Script exits with error if PROFESSIONAL_ID not set
   - Genericized all 42 template documents:
     - "Para agendar uma consulta com a Dra. Andreia" → "Para agendar uma consulta"
     - "A Dra. Andreia realizará" → "O profissional realizará"
     - "no consultório da Dra. Andreia" → "no consultório"
     - Added placeholders: "[Preencha horário de atendimento específico do profissional]"
   - Updated docstring examples

5. **KNOWLEDGE_BASE_MULTI_TENANT.md**
   - Replaced all examples: `dra-andreia` → `profissional-demo`, `dr-carlos` → `clinica-exemplo`
   - Removed "Index Seed Tenant (Dra. Andreia)" section
   - Removed "default: dra-andreia" language from CLI reference
   - Updated backwards compatibility section to emphasize no defaults
   - Removed references to Dra. Andreia being preserved as seed tenant

6. **SUMMARY_MULTI_TENANT_KB.md**
   - Updated summary to reflect "Generic multi-tenant base ready" status
   - Changed "Dra. Andreia preserved as seed tenant" → "Historical seed data preserved in _demo_data (inactive)"
   - Removed handoffs to team (outdated from previous session)
   - Emphasized no hardcoded defaults throughout
   - Updated all examples to use generic names

7. **MULTI_TENANT_QUICK_START.md**
   - Updated architecture diagram: `dra_andreia (existing, preserved)` → `profissional_demo (example)`
   - Changed registration example from Dra. Andreia → Dra. Maria (generic example professional)
   - Updated all SQL queries to use `dra-maria` instead of `dra-andreia`
   - Changed context query example to use generic tenant code

**Validation:**
- ✅ Python syntax: All 3 scripts compile without errors
- ✅ JSON structure: Valid JSON, 0 active professionals, 0 active documents, 1 demo professional in `_demo_data`
- ✅ Reference audit: 0 active references to "andreia" in product code/docs (excluding comments and _demo_data)
- ✅ Demo data: Preserved in JSON `_demo_data` section with clear "Historical seed data - for reference only" comment

**Architecture Decisions:**
- **No silent defaults:** Scripts fail fast with helpful error if tenant not specified, rather than silently defaulting to any professional
- **Empty product base:** knowledge_base.json ships empty (0 professionals, 0 documents) — clean slate for new onboarding
- **Demo data isolation:** Dra. Andreia data moved to `_demo_data` object with `active: false` — clearly marked as historical/reference
- **Generic templates:** All 42 template documents use placeholder text requiring customization — no professional-specific content
- **Clear examples:** All documentation uses neutral names (`profissional-demo`, `clinica-exemplo`, `dra-maria`) — no product identity bias

**User Preference Learned:**
- Generic product presentation critical for SaaS offering
- Historical/migration data should be explicitly isolated, not mixed with active product defaults
- Clear error messages preferred over silent fallback to wrong tenant
- Template documents should have obvious placeholder text requiring customization

**Testing Notes:**
- Empty knowledge base will require professional addition before indexing
- Scripts correctly error when no tenant specified (tested with missing env var)
- Demo data in `_demo_data` is not loaded by scripts (confirmed by JSON parsing logic)

---


### Final Reference Cleanup for Generic Product (2026-04-27)

**Context:** After previous multi-tenant migration, coordinator identified remaining client references in active KB files. User requested complete cleanup to make repo look generic without real client data.

**Remaining Issues Found:**
- `knowledge_base_atualizar.py`: Commented example with real client names/URLs/Instagram handle
- `knowledge_base_atualizar.py`: `Dr./Dra. Demo` placeholder text triggered policy search
- `knowledge_base.json`: `_demo_data` section contained full client professional and documents data
- `KNOWLEDGE_BASE_MULTI_TENANT.md`: `Dr./Dra. Demo` placeholder text
- `SUMMARY_MULTI_TENANT_KB.md`: References to previous cleanup steps mentioning client name

**Actions Taken:**
1. Removed commented client example from `PROFESSIONALS_CONFIG` in `knowledge_base_atualizar.py`
2. Replaced placeholder text with `"Profissional Demo"` and `"Clinica Demo"` (avoiding `Dr./Dra.` trigger)
3. Completely removed `_demo_data` section from `knowledge_base.json` - active JSON now truly empty and generic
4. Updated documentation examples to use neutral placeholders
5. Validated JSON and Python syntax - both clean
6. Ran scoped search across allowed KB/script/doc files - zero matches for banned patterns

**Result:** Active knowledge base files are now completely generic with no real client references. Repo can be used as product template without any client-specific data exposure.

**Validation:** `grep -niE "(andreia|mota|mussi|dra[._ -]?andreia|dra\.)" knowledge_base*.{py,json} *.md` returns zero matches.

