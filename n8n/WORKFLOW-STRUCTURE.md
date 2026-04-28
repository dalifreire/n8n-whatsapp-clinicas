# Generic n8n Workflow Structure — Quick Reference

**Version:** 1.0  
**Date:** 2025-04-27  
**Status:** Ready for Deployment (pending database schema)

---

## File Structure

```
n8n/
├── WhatsApp - Assistente Clínica (Generic).json          # Main workflow (generic)
├── WhatsApp - Enviar Lembretes Automáticos (Generic).json # Reminder workflow (generic)
├── MIGRATION-GUIDE.md                                     # Full deployment guide
├── WORKFLOW-STRUCTURE.md                                  # This file
│
├── tools-generic/                                         # Generic tool workflows
│   ├── Ferramenta_ Agendar Consulta.json
│   ├── Ferramenta_ Buscar Horários Disponíveis.json
│   ├── Ferramenta_ Buscar Paciente.json
│   ├── Ferramenta_ Cancelar Consulta.json
│   ├── Ferramenta_ Consultar Agendamentos do Paciente.json
│   ├── Ferramenta_ Listar Dentistas e Procedimentos.json
│   ├── Ferramenta_ Listar Especialidades.json
│   ├── Ferramenta_ Reiniciar Conversa.json
│   └── Ferramenta_ Resumo Financeiro do Paciente.json
│
├── [LEGACY] legacy-dra-andreia/
│   ├── README.md
│   ├── LEGACY-MIGRATION-GUIDE.md                     # Legacy migration documentation
│   ├── [Original single-tenant workflow files]
│   └── tools/                                         # Original tools (archived)
        └── [9 original tool workflows]
```

---

## Webhook Routing

### Format
```
https://your-n8n.com/webhook/{tenant_code}
```

### Examples
- Tenant Demo: `https://your-n8n.com/webhook/tenant-demo`
- Professional A: `https://your-n8n.com/webhook/profissional-a`
- Professional B: `https://your-n8n.com/webhook/profissional-b`

### Configuration (EvolutionAPI)
Each professional's WhatsApp instance webhook should point to their unique URL.

---

## Tenant Configuration (Database)

### Required Table: `clinic_core.tenants`

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `id` | UUID | Primary key | `UUID` |
| `tenant_code` | VARCHAR | URL path identifier | `tenant-demo` |
| `schema_name` | VARCHAR | PostgreSQL schema | `tenant_demo` |
| `professional_id` | UUID | FK to professionals | `UUID` |
| `evolution_instance_name` | VARCHAR | WhatsApp instance | `Demo Professional Instance` |
| `whatsapp_phone` | VARCHAR | Phone number | `5571999999999` |
| `status` | VARCHAR | Tenant status | `active` |

### Example Row (Generic Tenant)
```sql
INSERT INTO clinic_core.tenants (tenant_code, schema_name, professional_id, evolution_instance_name, whatsapp_phone, status)
VALUES ('tenant-demo', 'tenant_demo', 'PROF-001', 'Demo Professional Instance', '5571999999999', 'active');
```

**Note:** For onboarding new tenants, use the generic pattern above. Legacy migration documentation is available in `legacy-dra-andreia/` directory.

---

## Workflow Execution Flow

### Main Workflow: Message Processing

```
1. Webhook Trigger
   ↓ Receives: POST /webhook/tenant-demo
   ↓ Extracts: tenant_code = "tenant-demo"
   
2. Extract Tenant Code
   ↓ Parses URL parameter
   ↓ Output: { tenant_code: "tenant-demo" }
   
3. Load Tenant Config
   ↓ Queries: SELECT * FROM clinic_core.tenants WHERE tenant_code = 'tenant-demo'
   ↓ Output: { tenant_id, schema_name, evolution_instance_name, ... }
   
4. Validate Tenant
   ↓ Checks: Is tenant active?
   ↓ If NO → Error response
   ↓ If YES → Continue
   
5. Compose AI Prompt
   ↓ Builds: 5-layer prompt from DB config + base template
   ↓ Output: { full_prompt, tenant_id, schema_name, ... }
   
6. Extract Message Data
   ↓ Parses: WhatsApp webhook payload
   ↓ Output: { sender_phone, sender_name, message_text, ... }
   
7. Validate Message Data
   ↓ Sanitizes and validates input
   
8. Generate Embedding (if RAG enabled)
   ↓ Calls: OpenAI embeddings API
   
9. RAG - Search Knowledge Base
   ↓ Queries: SELECT * FROM {{ schema_name }}.documentos WHERE ...
   ↓ Uses tenant-specific schema
   
10. AI Agent (OpenAI GPT-4)
    ↓ Prompt: Composed prompt + RAG context + message
    ↓ Tools: 9 workflow tools (all tenant-aware)
    ↓ Memory: {{ schema_name }}.n8n_chat_histories
    
11. Send Response
    ↓ Calls: Evolution API (tenant-specific instance)
    ↓ Delivers message to WhatsApp
```

---

## Dynamic Schema References

### Pattern
All database queries use dynamic schema injection:

```javascript
// In PostgreSQL node query parameter:
SELECT * FROM {{ $("Load Tenant Config").first().json.schema_name }}.table_name WHERE ...
```

### Examples

#### Before (Hardcoded - Legacy)
```sql
SELECT * FROM tenant_demo.pacientes WHERE telefone = $1
```

#### After (Dynamic)
```sql
SELECT * FROM {{ $("Load Tenant Config").first().json.schema_name }}.pacientes WHERE telefone = $1
```

### Usage in Different Node Types

1. **PostgreSQL Node (direct query)**
   ```sql
   SELECT * FROM {{ $("Load Tenant Config").first().json.schema_name }}.table_name
   ```

2. **Chat Memory Node**
   ```
   tableName: {{ $("Load Tenant Config").first().json.schema_name }}.n8n_chat_histories
   ```

3. **Tool Sub-workflows**
   ```javascript
   // Parent passes schema_name to tool:
   { schema_name: $("Load Tenant Config").first().json.schema_name }
   
   // Tool uses it:
   SELECT * FROM {{ $input.first().json.schema_name }}.table_name
   ```

---

## AI Prompt Composition (5 Layers)

The **Compose AI Prompt** node builds prompts dynamically:

### Layer Structure
```
Layer 1: Base Product Prompt (shared, hardcoded in workflow)
         ↓
Layer 2: Clinic Context (from clinic_core.organizations)
         ↓
Layer 3: Professional Context (from clinic_core.professionals)
         ↓
Layer 4: Assistant Persona (from professionals.configuracao_ia JSONB)
         ↓
Layer 5: Tools & Service Context (from tenant config)
```

### Example Output (Generic Tenant)
```
Você é um assistente virtual do consultório.

═══════════════════════════════════
🏥 INFORMAÇÕES DO CONSULTÓRIO
═══════════════════════════════════
- Clínica: Demo Healthcare Clinic
- Endereço: [From database]
- Telefone: [From database]
- Horário: [From database]

═══════════════════════════════════
👨‍⚕️ PROFISSIONAL
═══════════════════════════════════
- Nome: [From database]
- Especialidades: [From database]
- Registro: [From database]

[... more context layers from database ...]
```

**Note:** All values are pulled dynamically from database configuration for each tenant.

---

## Tool Invocation Pattern

### How Tools Receive Tenant Context

1. **Parent Workflow** (AI Agent node)
   - Calls sub-workflow tool
   - Passes parameters including `schema_name`
   
2. **Tool Workflow** (Execute Workflow Trigger node)
   - Receives parameters
   - Extracts `schema_name` from input
   
3. **Tool Query** (PostgreSQL node)
   - Uses dynamic schema reference
   - Example: `SELECT * FROM {{ $input.first().json.schema_name }}.pacientes`

### Example: Buscar Paciente Tool

**Input from parent:**
```json
{
  "patient_phone": "5571999999999",
  "schema_name": "tenant_demo"
}
```

**Tool query:**
```sql
SELECT * FROM {{ $input.first().json.schema_name }}.pacientes 
WHERE telefone = $1
```

**Actual executed query:**
```sql
SELECT * FROM tenant_demo.pacientes 
WHERE telefone = '5571999999999'
```

---

## Reminder Workflow Pattern

### Cross-Tenant Iteration

The reminder workflow uses **CROSS JOIN LATERAL** to query all tenants in one pass:

```sql
SELECT 
    t.tenant_code,
    t.schema_name,
    t.evolution_instance_name,
    r.*
FROM clinic_core.tenants t
CROSS JOIN LATERAL (
    -- This subquery executes per tenant with dynamic schema
    SELECT * FROM [SCHEMA_NAME].lembretes 
    WHERE status = 'pendente' AND agendado_para <= NOW()
) r
WHERE t.status = 'active'
```

### Advantages
- ✅ Single workflow handles all tenants
- ✅ Automatic scaling (new tenants auto-included)
- ✅ Efficient query execution
- ✅ Per-tenant Evolution instance routing

---

## Security Considerations

### 1. Schema Name Validation
**Problem:** SQL injection risk if schema name is user-controlled

**Solution:** Whitelist validation in Load Tenant Config node
```javascript
const allowedSchemas = ['tenant_demo', 'dr_carlos', 'dra_maria'];
if (!allowedSchemas.includes(schema_name)) {
  throw new Error('Invalid schema');
}
```

**Note:** In production, schema whitelist should be loaded from database, not hardcoded.

### 2. Tenant Isolation
**Problem:** Cross-tenant data leakage

**Solution:**
- PostgreSQL RLS policies on all tenant schemas
- Automated tests for data isolation
- Session keys include tenant_id: `${tenant_id}_${phone}`

### 3. Webhook Token Validation
**Problem:** Unauthorized webhook calls

**Solution:**
- Validate webhook signature (EvolutionAPI/Cloud API)
- Tenant must be `status='active'`
- Rate limiting per tenant

---

## Testing Scenarios

### Unit Tests (Single Tenant)
1. Send message to `/webhook/tenant-demo`
2. Verify tenant config loads correctly
3. Verify schema name matches tenant configuration
4. Verify AI prompt includes tenant professional info
5. Test each of 9 tools individually

### Integration Tests (Multi-Tenant)
1. Create second tenant (Dr. Carlos)
2. Send messages to both simultaneously
3. Verify no data leakage
4. Verify chat memories are isolated
5. Verify reminders sent from correct instances

### Stress Tests
1. Load test with 10 concurrent tenants
2. Verify connection pool handles load
3. Verify no query timeouts
4. Verify reminder workflow completes in < 5 minutes

---

## Troubleshooting Quick Reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Tenant not found" error | Invalid tenant_code | Check `clinic_core.tenants` table |
| SQL error "schema does not exist" | Schema not created | `CREATE SCHEMA {schema_name}` |
| Message sent from wrong instance | Instance name mismatch | Verify `evolution_instance_name` in DB |
| Chat memory leaking between tenants | Memory table not isolated | Create `n8n_chat_histories` in each schema |
| Tool queries fail | schema_name not passed | Check parent workflow passes `schema_name` |

---

## Next Steps for Deployment

1. **Penguin (Database):**
   - Create `clinic_core` schema
   - Create `tenants`, `professionals`, `organizations` tables
   - Insert seed data for first tenant
   - Create RLS policies

2. **Gordon (WhatsApp):**
   - Configure EvolutionAPI multi-instance routing
   - Update webhook URLs to generic pattern
   - Verify instance names match DB

3. **Lucius (n8n):**
   - Import generic workflows to n8n
   - Update PostgreSQL credentials
   - Test with configured tenant
   - Monitor logs for errors

4. **Team (Testing):**
   - Run unit tests (single tenant)
   - Run integration tests (multi-tenant)
   - Performance testing
   - Security audit

---

**Last Updated:** 2025-04-27  
**Author:** Lucius (n8n Workflow Specialist)  
**Companion Docs:** `README.md`
