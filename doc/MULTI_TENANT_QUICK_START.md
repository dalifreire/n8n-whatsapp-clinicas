# Multi-Tenant Platform Quick Start Guide

## Overview

The database is now multi-tenant with **schema-per-professional** isolation. Each healthcare professional gets their own isolated PostgreSQL schema, while shared platform metadata lives in `clinic_core`.

## Key Files

- **SUPABASE_SETUP.sql** - Complete multi-tenant setup (execute this in Supabase)
- **SUPABASE_SETUP_V1_SINGLE_TENANT.sql** - Original single-tenant backup (reference only)
- **This guide** - Quick start for team integration

## Architecture at a Glance

```
Platform (clinic_core schema)
  ├─ professionals (tenant registry)
  ├─ whatsapp_instances (1:1 with professional)
  ├─ assistant_configs (AI settings)
  └─ usage_logs (cost tracking)

Professional Schemas (isolated data)
  ├─ prof_joao_1234 (example professional)
  ├─ prof_carlos_5678 (example professional)
  └─ prof_maria_7890 (example professional)
      ├─ conversas
      ├─ usuarios
      ├─ documentos (RAG)
      ├─ pacientes
      ├─ agendamentos
      └─ ... (20+ tables)
```

## Setup Steps

### 1. Execute Multi-Tenant SQL

```sql
-- In Supabase SQL Editor
-- Paste entire SUPABASE_SETUP.sql and execute
-- This creates clinic_core and optionally adopts any existing tenant schemas
```

### 2. Register First Professional (Example)

```sql
-- Example: If you have an existing schema to adopt (optional)
SELECT clinic_core.register_existing_tenant(
  p_schema_name := 'existing_schema_name',  -- Replace with your schema
  p_tenant_code := 'tenant-code',            -- URL-safe identifier
  p_full_name := 'Professional Full Name',   -- e.g., 'Dr. João Silva'
  p_credential_type := 'CRM',                -- CRM, CRO, etc.
  p_credential_number := '12345',
  p_phone := '5511999887766',
  p_whatsapp_phone := '5511999887766',
  p_whatsapp_provider := 'evolution-api'
);
```

### 3. Verify Registration

```sql
-- Check professional was registered
SELECT * FROM clinic_core.professionals;

-- Check WhatsApp instance
SELECT * FROM clinic_core.whatsapp_instances;

-- Test context query (used by n8n) - replace 'tenant-code' with your actual code
SELECT * FROM clinic_core.get_professional_context(p_tenant_code := 'tenant-code');
```

## n8n Integration (Lucius)

### Pattern: Every Workflow Starts Here

```javascript
// Step 1: Extract tenant_code from webhook path
// Webhook: POST /webhook/{tenant_code}
const tenant_code = $node["Webhook"].json["headers"]["x-tenant-code"]; // or extract from path

// Step 2: Load professional context
const query = `SELECT * FROM clinic_core.get_professional_context(p_tenant_code := $1)`;
const context = await $supabase.query(query, [tenant_code]);

// Step 3: Use dynamic schema in all subsequent queries
const schema = context[0].schema_name; // e.g., 'prof_joao_1234'
const professional_id = context[0].professional_id;

// Step 4: Query tenant data
const conversations = await $supabase.query(
  `SELECT * FROM ${schema}.conversas WHERE telefone = $1 ORDER BY data_hora DESC LIMIT 10`,
  [patient_phone]
);

// Step 5: Track usage at end
await $supabase.query(`
  INSERT INTO clinic_core.usage_logs (
    professional_id, date, messages_received, ai_requests, openai_cost_cents, tokens_input, tokens_output
  ) VALUES ($1, CURRENT_DATE, 1, 1, $2, $3, $4)
  ON CONFLICT (professional_id, date) DO UPDATE SET
    messages_received = clinic_core.usage_logs.messages_received + 1,
    ai_requests = clinic_core.usage_logs.ai_requests + 1,
    openai_cost_cents = clinic_core.usage_logs.openai_cost_cents + EXCLUDED.openai_cost_cents,
    tokens_input = clinic_core.usage_logs.tokens_input + EXCLUDED.tokens_input,
    tokens_output = clinic_core.usage_logs.tokens_output + EXCLUDED.tokens_output
`, [professional_id, cost_cents, tokens_in, tokens_out]);
```

### Migration Checklist for n8n

- [ ] Create inbound webhook router workflow
  - Extract `tenant_code` from `/webhook/{tenant_code}`
  - Call `get_professional_context()`
  - Route to main assistant workflow with context

- [ ] Update ALL existing workflows:
  - Add context loading as first step
  - Replace hardcoded schema names with `{{$json.context.schema_name}}`
  - Add usage tracking at end

- [ ] Update these specific workflows:
  - WhatsApp webhook handler (main entry point)
  - Agendar Consulta
  - Consultar Agendamentos
  - Buscar Conhecimento (RAG)
  - Listar Procedimentos
  - Resumo Financeiro
  - (All 9 tool sub-workflows)

## Python RAG Integration (Ivy)

### Update knowledge_base_indexar.py

```python
import psycopg2

# Old: Single tenant (hardcoded schema)
# conn = psycopg2.connect(...)
# cursor.execute("INSERT INTO hardcoded_schema.documentos ...")

# New: Multi-tenant (dynamic schema per professional)
conn = psycopg2.connect(...)  # Same connection

# Get all active professionals
cursor.execute("SELECT id, schema_name, tenant_code FROM clinic_core.professionals WHERE active = true")
professionals = cursor.fetchall()

for prof_id, schema_name, tenant_code in professionals:
    print(f"Indexing knowledge base for {tenant_code} (schema: {schema_name})")
    
    # Load documents for this professional (from file or API)
    docs = load_documents_for_professional(tenant_code)
    
    # Generate embeddings
    embeddings = openai.Embedding.create(...)
    
    # Insert into professional's schema (using safe parameterization)
    query = f"INSERT INTO {schema_name}.documentos (titulo, conteudo, categoria, embedding) VALUES (%s, %s, %s, %s)"
    # IMPORTANT: Validate schema_name is from professionals table before string interpolation
    cursor.execute(query, (doc.title, doc.content, doc.category, embedding))
    
    conn.commit()
```

### RAG Query Pattern

```python
# In n8n/Python: Query RAG with tenant context
context = get_professional_context(tenant_code)
schema = context['schema_name']

# Safe query construction (schema validated from professionals table)
query = f"SELECT * FROM {schema}.buscar_documentos_similares($1, $2, $3)"
results = cursor.execute(query, [query_embedding, threshold, limit])
```

## Adding New Professionals

### Option A: Minimal Schema (Quick Test)

```sql
-- Step 1: Provision minimal schema
SELECT clinic_core.provision_professional_schema('prof_carlos_5678');

-- Step 2: Register professional
INSERT INTO clinic_core.professionals (
  schema_name, tenant_code, full_name, credential_type, credential_number, phone, status
) VALUES (
  'prof_carlos_5678', 'dr-carlos', 'Carlos Silva', 'CRM', '5678', '11987654321', 'active'
);

-- Step 3: Add WhatsApp instance
INSERT INTO clinic_core.whatsapp_instances (
  professional_id, provider, phone_number, webhook_path
) VALUES (
  (SELECT id FROM clinic_core.professionals WHERE tenant_code = 'dr-carlos'),
  'evolution-api', '5511987654321', '/webhook/dr-carlos'
);

-- Step 4: Configure assistant
INSERT INTO clinic_core.assistant_configs (
  professional_id, assistant_name, model
) VALUES (
  (SELECT id FROM clinic_core.professionals WHERE tenant_code = 'dr-carlos'),
  'Sofia', 'gpt-4o'
);
```

### Option B: Full Production Schema

For production with all 20+ tables, you need to extend `provision_professional_schema()` function or create a separate provisioning script. See notes in SUPABASE_SETUP.sql for table list.

## Common Queries

### Get All Active Professionals

```sql
SELECT 
  p.tenant_code,
  p.schema_name,
  p.full_name,
  p.phone,
  wi.phone_number as whatsapp,
  p.status,
  p.created_at
FROM clinic_core.professionals p
LEFT JOIN clinic_core.whatsapp_instances wi ON p.id = wi.professional_id
WHERE p.active = true
ORDER BY p.created_at;
```

### Get Daily Usage Summary

```sql
SELECT 
  p.full_name,
  p.tenant_code,
  ul.date,
  ul.messages_received,
  ul.ai_requests,
  ul.openai_cost_cents / 100.0 as openai_cost_usd,
  ul.total_cost_cents / 100.0 as total_cost_usd
FROM clinic_core.usage_logs ul
JOIN clinic_core.professionals p ON ul.professional_id = p.id
WHERE ul.date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY ul.date DESC, p.full_name;
```

### Check Professional's Conversation Count

```sql
-- Dynamic query (validate schema from professionals table first)
DO $$
DECLARE
  prof RECORD;
  conv_count INT;
BEGIN
  FOR prof IN SELECT schema_name, full_name FROM clinic_core.professionals WHERE active = true LOOP
    EXECUTE format('SELECT COUNT(*) FROM %I.conversas', prof.schema_name) INTO conv_count;
    RAISE NOTICE 'Professional: %, Conversations: %', prof.full_name, conv_count;
  END LOOP;
END;
$$;
```

## Security Notes

1. **Dynamic Schema Queries**: Always validate `schema_name` comes from `clinic_core.professionals` table before using in queries
2. **RLS Policies**: Currently basic (`auth.role() = 'authenticated'`); enhance with JWT-based professional isolation for production
3. **Secrets**: Store API keys in Supabase Vault, not in `config` JSONB
4. **Audit Log**: All provisioning and registration events logged in `clinic_core.audit_log`

## Troubleshooting

### "Schema does not exist" Error

```sql
-- Check if schema exists
SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'prof_carlos_5678';

-- Check professional registration
SELECT schema_name, status FROM clinic_core.professionals WHERE tenant_code = 'dr-carlos';
```

### "Professional not found" in n8n

```sql
-- Debug context query
SELECT * FROM clinic_core.get_professional_context(p_tenant_code := 'dr-carlos');

-- Check if professional active
SELECT active, status FROM clinic_core.professionals WHERE tenant_code = 'dr-carlos';
```

### WhatsApp webhook not routing

```sql
-- Check WhatsApp instance configuration
SELECT 
  p.tenant_code,
  wi.phone_number,
  wi.webhook_path,
  wi.connected,
  wi.provider
FROM clinic_core.whatsapp_instances wi
JOIN clinic_core.professionals p ON wi.professional_id = p.id;
```

## Next Steps

1. **Lucius**: Update n8n workflows (see integration pattern above)
2. **Ivy**: Update Python RAG indexing scripts (see Python pattern above)
3. **Team**: Test end-to-end with your first professional tenant
4. **Team**: Provision additional professionals as needed
5. **Penguin**: Extend `provision_professional_schema()` to create all 20+ tables

## Support

For questions or issues:
- See: `.squad/decisions/inbox/penguin-generic-tenant-db.md` (detailed decision doc)
- See: `.squad/agents/penguin/history.md` (technical notes)
- Contact: Penguin (Database Engineer)

---

**Last Updated:** 2026-04-27  
**Version:** 2.0 Multi-Tenant
