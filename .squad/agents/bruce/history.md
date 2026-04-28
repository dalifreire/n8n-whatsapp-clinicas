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

### [2026-04-27] Multi-Tenant Implementation Review — REJECTED

**Verdict:** Blocking review of Penguin/Ivy/Lucius generic-platform pivot. See `.squad/decisions/inbox/bruce-multi-tenant-review.md` for full breakdown.

**Key learnings:**

1. **Three agents working in parallel without a shared schema contract drift fast.** Penguin shipped `clinic_core.professionals` (full_name / specialties / credential_*); Lucius shipped n8n queries against a phantom `clinic_core.tenants` with `nome / especialidades / configuracao_ia`; Ivy shipped a `professional_id` column the SQL never declares. Concept aligned, artifacts diverged. Architect must publish the column-level contract *before* implementation forks, not after.

2. **Big SQL files concatenated by hand will silently include unterminated `format(')` strings.** `create_tenant_tables` opens a dynamic-SQL string for the `conversas` DDL and never closes it; the rest of the V1 dentist-specific DDL was pasted in below, which means the "generic" provisioner actually re-introduces hardcoded `dra_andreia` references. Always lint generated SQL by attempting to compile the function in a throwaway Postgres before declaring done.

3. **`CREATE OR REPLACE FUNCTION` does not allow changing return signatures.** Two copies of `get_professional_context` with different `RETURNS TABLE` columns will hard-fail. Duplicate-header smell = stop and dedupe before review.

4. **String concatenation cannot inject schema names into static SQL.** Lucius's reminders workflow (`FROM ' || t.schema_name || '.lembretes`) can't work — Postgres needs the relation resolved at parse time. Pattern for cross-tenant batch jobs: tenant loop in the orchestrator + `SECURITY DEFINER` function per schema using `EXECUTE format('%I', …)`.

5. **JSON-encoded `jsCode` in n8n Code nodes loses backticks.** Storing template literals as `\`` in JSON gives `\` + `` ` `` after parse, which is invalid JS. Either escape via `String.fromCharCode(96)` / use single-quote concatenation, or generate the JSON via a serializer that handles backticks safely.

6. **Reviewer rejection lockout is healthier than I expected.** Forcing reassignment (Lucius owns the SQL rewrite, Penguin owns the reminders SQL fix, Ivy owns the prompt-composition fix) gives every agent a chance to feel the contract from the consumer side, which is exactly where the gaps showed up.

7. **`provision_professional_schema` is the real product surface.** If it doesn't create every table the tools/reminders/chat-memory touch, the platform supports exactly one tenant — the legacy one. Tool inventory must drive the provisioner template, not the other way around.

### [2026-04-27] Schema Contract ADR Published

**Artifact:** `.squad/decisions/inbox/bruce-schema-contract-adr.md` — blocking contract for Penguin/Lucius/Ivy revisions.

**Key contract calls locked in:**
- External id: `tenant_code` (kebab, regex-validated). Internal id: `schema_name` (snake, regex + reserved-prefix check). Mapping is 1:1 and immutable post-provisioning.
- Single read entry point: `clinic_core.get_professional_context(tenant_code)` function (with `clinic_core.tenants` as a thin read-only view wrapper). Killed the "every consumer invents its own join" pattern that produced B3.
- `full_name` is the source of truth; `nome` survives as a pure alias on the function/view output to avoid prompt-template churn mid-pivot. Cheap blast-radius reduction; sunset deferred to a future ADR.
- RAG: schema isolation only — `documentos` has no `professional_id` column. Indexer drops the column logic. Compliance argument for the redundant column did not survive scrutiny (double-bookkeeping that was silently disabled in prod anyway).
- Reminders: per-schema `fetch_due_reminders(window)` + platform dispatcher `clinic_core.fetch_due_reminders_all(window)` doing the `format('%I', …) EXECUTE` loop. n8n calls the dispatcher once. Closes B4.
- Provisioner contract: §5.1 enumerates the 16 tenant tables and 4 tenant functions the tools/reminders/chat-memory actually touch; the provisioner is "done" only when all of them exist after one call.

**Heuristic (worth promoting to wisdom.md later):** when three agents diverge on a multi-tenant rewrite, the architect's first artifact must be a *column-level* contract, not a *concept-level* one. Concept-level alignment ("schema-per-tenant, central registry") is the cheap part — agents will still independently pick `nome` vs `full_name` and `evolution_instance_name` vs `provider_instance_id`. The ADR has to enumerate every field consumers depend on or the divergence repeats.


### [2026-04-27] Final Multi-Tenant Gate — APPROVED

**Artifact:** `.squad/decisions/inbox/bruce-final-multi-tenant-gate.md`

**Outcome:** B1–B8 verified resolved against the actual files (not just summary docs). SQL/n8n/Python all converge on `clinic_core.get_professional_context(tenant_code)` as the single read entry point, and on the §2.1 column set. Lockout-induced reassignment (Lucius→SQL, Penguin→reminders, Ivy→main workflow, Gordon→RAG/indexer) produced a cleaner landing than a same-author retry would have. Lockout lifted.

**Key learnings:**

1. **Contract-driven re-review is fast.** With the schema contract ADR published *before* the revision pass, gating the second submission was a column-by-column conformance check — minutes, not hours. The first review (without a contract) cost a full reading of every file.

2. **Reviewer must verify against artifacts, not against fix-decision docs.** Each agent's fix decision claimed compliance; in the actual files I found one real drift (indexer derives `schema_name` from string convention rather than from `get_professional_context`, F1) and confirmed compliance everywhere else. Fix-summary docs are persuasion; files are evidence.

3. **One acceptable F-class follow-up doesn't cost you the gate.** F1 (indexer schema resolution) violates the ADR §6 Python checklist on the letter, but the rejection scope (B8: `professional_id` column hack) is genuinely closed, the hot path is correct, and the indexer is offline tooling. Holding the merge for a non-hot-path purity issue would punish the team for the wrong reason. Filed as a backlog item instead.

4. **Lockout pattern worth keeping.** Forcing defect ownership onto a non-author agent makes each agent feel the contract from the consumer side — exactly where the gaps showed up. Use again for future multi-agent rewrites where contract drift is the failure mode.

5. **Hygiene is genuinely non-blocking when the platform code is clean.** `__pycache__`, `.DS_Store`, empty log file, marker file, `SUPABASE_SETUP.sql.backup`, three overlapping multi-tenant md docs — all real, none architecturally consequential. Bundled into F2 for Scribe's next pass; did not let them block the gate.

### [2026-04-27] Reference Cleanup Policy Published

**Artifact:** `.squad/decisions/inbox/bruce-reference-cleanup-policy.md`

**Trigger:** Dali — "ainda vejo muitas referencias a dra andreia no projeto."

**Verdict shape:** Three buckets, one rubric.
- BLOCKING: Andreia as default product identity on the active code path — KB script defaults (`DEFAULT_TENANT_CODE`, `DEFAULT_PROFESSIONAL_ID`, argparse fallbacks), credential name fields in the generic n8n main workflow, any `dra_andreia.<table>` literal outside the seed block.
- ACCEPTABLE: explicit, labelled seed/example data — `SUPABASE_SETUP.sql:1449–1453` (needs a `-- SEED:` header), Andreia entries scoped under a tenant record in `knowledge_base.json`, Andreia-as-worked-example in migration docs, frozen V1/original exports.
- NOISE: `.squad/**`, backups, `__pycache__`, log/marker files. Out of scope; will not be counted.

**Final-gate test:** case-insensitive `andreia` grep across the active surface (excluding `.squad/`, `*.backup`, `*_V1_SINGLE_TENANT.sql`, `n8n-main-original.json`, `n8n/MIGRATION-GUIDE.md`, and labelled seed blocks) must return zero hits. Justified ACCEPTABLE survivors must be enumerated in the cleanup handoff — same F1-style discipline we used at the multi-tenant gate.

**Key learnings:**

1. **"Just grep and delete" is the wrong instinct on a multi-tenant pivot.** A naive sweep would corrupt valid seed data, frozen rollback artifacts, and team memory. Reviewer's first job on a "too many references" complaint is to publish the rubric — what kinds of mention are evidence of a defect vs. evidence of correct seed scoping vs. evidence of project history. Without that, every cleanup pass risks deleting the audit trail or, worse, leaving the actual defects in place because the noisy hits ran out the clock.

2. **Seed-tenant references and product-identity references look the same to grep.** They are distinguished by *position*: gated under `IF EXISTS` in the provisioner = seed; sitting in `DEFAULT_PROFESSIONAL_ID` = product identity. The rubric has to be positional, not lexical.

3. **`.squad/` is non-negotiable.** Rewriting history to remove Andreia would destroy the *reason* the multi-tenant pivot exists. Any cleanup ADR I write should be loud about this so well-meaning agents don't try to "tidy up" history.

4. **Reviewer test phrasings are cheap and effective.** "If I deleted the Andreia tenant tomorrow, does this code still work for dr-carlos?" and "Does this file ship to a customer or run in production?" both compile down to one-line judgments and dodge the bikeshed about whether a particular doc passage feels too Andreia-flavored.
