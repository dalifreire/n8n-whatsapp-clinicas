# n8n Workflows Migration Guide — Generic Multi-Tenant Architecture

**Version:** 1.0  
**Date:** 2025-04-27  
**Author:** Lucius (n8n Workflow Specialist)

---

## Overview

This guide documents the transformation of Dra. Andreia-specific n8n workflows into a generic multi-tenant clinic assistant platform.

## What Changed

### 1. Main Workflow: `WhatsApp - Assistente Clínica (Generic).json`

**Key Changes:**
- ✅ Webhook path changed from `dra-andreia-whatsapp-webhook` to `webhook/:tenant_code`
- ✅ Added **Extract Tenant Code** node to parse URL parameter
- ✅ Added **Load Tenant Config** node to query `clinic_core.tenants` table
- ✅ Added **Validate Tenant** node to ensure tenant is active
- ✅ Added **Compose AI Prompt** node with 5-layer dynamic composition
- ✅ All database queries now use `{{ $("Load Tenant Config").first().json.schema_name }}.table_name`
- ✅ PostgreSQL Chat Memory uses dynamic schema: `{{ $("Load Tenant Config").first().json.schema_name }}.n8n_chat_histories`
- ✅ Evolution API instance name is dynamic: `{{ $("Load Tenant Config").first().json.evolution_instance_name }}`

**Before:**
```
Webhook (dra-andreia-whatsapp-webhook)
  ↓
Extract Message Data
  ↓
Validate Message
  ↓
...
```

**After:**
```
Webhook (webhook/:tenant_code)
  ↓
Extract Tenant Code
  ↓
Load Tenant Config (queries clinic_core.tenants)
  ↓
Validate Tenant (checks if active)
  ↓
Compose AI Prompt (5-layer dynamic prompt)
  ↓
Extract Message Data
  ↓
Validate Message
  ↓
...
```

### 2. Reminder Workflow: `WhatsApp - Enviar Lembretes Automáticos (Generic).json`

**Key Changes:**
- ✅ Query now iterates through ALL active tenants in `clinic_core.tenants`
- ✅ Uses dynamic schema references: `t.schema_name`
- ✅ Evolution instance name pulled from tenant config
- ✅ Messages use professional name from database, not hardcoded

**Before:**
```sql
SELECT ... FROM dra_andreia.lembretes ...
```

**After:**
```sql
SELECT 
    t.tenant_code,
    t.schema_name,
    t.evolution_instance_name,
    ...
FROM clinic_core.tenants t
CROSS JOIN LATERAL (
    SELECT ... FROM [dynamic_schema].lembretes ...
) r
WHERE t.status = 'active'
```

### 3. Tool Workflows: `n8n/tools-generic/`

**All 9 tools refactored:**
1. Agendar Consulta
2. Buscar Horários Disponíveis
3. Buscar Paciente
4. Cancelar Consulta
5. Consultar Agendamentos do Paciente
6. Listar Dentistas e Procedimentos
7. Listar Especialidades
8. Reiniciar Conversa
9. Resumo Financeiro do Paciente

**Key Changes:**
- ✅ Workflow names changed from "Dra. Andreia / Ferramenta:" to "Tool:"
- ✅ All SQL queries use dynamic schema: `{{ $input.first().json.schema_name }}.table_name`
- ✅ Parent workflow passes `schema_name` to each tool invocation

**Before:**
```sql
SELECT * FROM dra_andreia.pacientes WHERE telefone = $1
```

**After:**
```sql
SELECT * FROM {{ $input.first().json.schema_name }}.pacientes WHERE telefone = $1
```

---

## Database Schema Requirements

### Required Tables (clinic_core schema)

#### `clinic_core.tenants`
```sql
CREATE TABLE clinic_core.tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_code VARCHAR(100) UNIQUE NOT NULL,  -- e.g., 'dra-andreia', 'dr-carlos'
    schema_name VARCHAR(100) NOT NULL,         -- e.g., 'dra_andreia', 'dr_carlos'
    professional_id UUID REFERENCES clinic_core.professionals(id),
    evolution_instance_name VARCHAR(255),      -- Evolution API instance name
    whatsapp_phone VARCHAR(20),
    status VARCHAR(20) DEFAULT 'active',       -- 'active', 'suspended', 'trial'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### `clinic_core.professionals`
```sql
CREATE TABLE clinic_core.professionals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES clinic_core.organizations(id),
    nome VARCHAR(255) NOT NULL,
    especialidades TEXT,
    registro_profissional VARCHAR(50),  -- CRO, CRM, etc.
    configuracao_ia JSONB,              -- AI assistant config (persona, tools, etc.)
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### `clinic_core.organizations`
```sql
CREATE TABLE clinic_core.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome VARCHAR(255) NOT NULL,
    endereco TEXT,
    telefone VARCHAR(20),
    horario_funcionamento TEXT,
    instagram VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Deployment Steps

### Phase 1: Database Preparation
1. Create `clinic_core` schema
2. Create tables: `tenants`, `professionals`, `organizations`
3. Insert seed data for Dra. Andreia (see below)

### Phase 2: Import Generic Workflows
1. Import `WhatsApp - Assistente Clínica (Generic).json` into n8n
2. Import `WhatsApp - Enviar Lembretes Automáticos (Generic).json`
3. Import all 9 tools from `n8n/tools-generic/`
4. Update PostgreSQL credentials in all workflows

### Phase 3: Configure Webhook
1. Activate generic main workflow
2. Copy webhook URL (format: `https://your-n8n.com/webhook/webhook/:tenant_code`)
3. Configure EvolutionAPI webhooks for each tenant:
   - Dra. Andreia: `https://your-n8n.com/webhook/dra-andreia`
   - Dr. Carlos: `https://your-n8n.com/webhook/dr-carlos`

### Phase 4: Test with Dra. Andreia
1. Send test message to Dra. Andreia's WhatsApp
2. Verify tenant config is loaded correctly
3. Verify database queries use correct schema (`dra_andreia`)
4. Verify AI prompt is composed correctly
5. Test all 9 tools

---

## Seed Data: Dra. Andreia

```sql
-- 1. Create organization
INSERT INTO clinic_core.organizations (id, nome, endereco, telefone, horario_funcionamento, instagram)
VALUES (
    'ORG-001',
    'Consultório Dra. Andreia Mota Mussi',
    'Av. Antônio Carlos Magalhães, 585 – Ed. Pierre Fauchard, Sala 709 - Itaigara, Salvador - BA, CEP 41825-907',
    '(71) 3353-7900',
    'Segunda a Sexta, das 08:00 às 18:00 | Sáb/Dom/Feriados: Fechado',
    '@andreapereiramota'
);

-- 2. Create professional
INSERT INTO clinic_core.professionals (id, organization_id, nome, especialidades, registro_profissional, configuracao_ia)
VALUES (
    'PROF-001',
    'ORG-001',
    'Dra. Andreia Mota Mussi',
    'Clínico Geral e Prótese Dentária',
    'CRO 4407',
    '{
        "assistant_name": "Ana",
        "personality": "educada, profissional, acolhedora e eficiente",
        "language": "pt-BR",
        "tools_enabled": ["buscar_paciente", "agendar_consulta", "cancelar_consulta", "listar_horarios", "consultar_agendamentos", "listar_dentistas", "resumo_financeiro", "reiniciar_conversa", "listar_especialidades"],
        "prompt_version": "v1"
    }'::jsonb
);

-- 3. Create tenant
INSERT INTO clinic_core.tenants (id, tenant_code, schema_name, professional_id, evolution_instance_name, whatsapp_phone, status)
VALUES (
    'TENANT-001',
    'dra-andreia',
    'dra_andreia',
    'PROF-001',
    'Dra Andreia Mota Mussi',
    '5571999999999',
    'active'
);
```

---

## Adding a New Professional

### Example: Dr. Carlos (Pediatric Dentist)

```sql
-- 1. Create professional record
INSERT INTO clinic_core.professionals (organization_id, nome, especialidades, registro_profissional, configuracao_ia)
VALUES (
    'ORG-001',  -- Same clinic as Dra. Andreia
    'Dr. Carlos Silva',
    'Odontopediatria',
    'CRO 5678',
    '{
        "assistant_name": "Carla",
        "personality": "alegre, paciente, especialista em crianças",
        "language": "pt-BR",
        "tools_enabled": ["buscar_paciente", "agendar_consulta", "cancelar_consulta"],
        "prompt_version": "v1"
    }'::jsonb
)
RETURNING id;  -- Save this ID

-- 2. Create schema for Dr. Carlos
CREATE SCHEMA dr_carlos;

-- 3. Copy table structure from dra_andreia schema
-- (Run all CREATE TABLE statements from dra_andreia but in dr_carlos schema)

-- 4. Create tenant record
INSERT INTO clinic_core.tenants (tenant_code, schema_name, professional_id, evolution_instance_name, whatsapp_phone, status)
VALUES (
    'dr-carlos',
    'dr_carlos',
    '[ID from step 1]',
    'Dr Carlos Silva',
    '5571888888888',
    'active'
);

-- 5. Configure EvolutionAPI
-- Point Dr. Carlos' WhatsApp webhook to: https://your-n8n.com/webhook/dr-carlos
```

---

## Testing Checklist

- [ ] Webhook accepts requests at `/webhook/{tenant_code}`
- [ ] Tenant config is loaded from database
- [ ] Invalid tenant codes are rejected
- [ ] AI prompt is composed with correct professional details
- [ ] Database queries use correct schema (no cross-tenant leakage)
- [ ] Chat memory is isolated per tenant
- [ ] Evolution API sends messages from correct instance
- [ ] All 9 tools work with dynamic schema
- [ ] Reminders are sent for all active tenants
- [ ] Each tenant only sees their own patients/appointments

---

## Rollback Plan

If issues occur:
1. Deactivate generic workflows
2. Re-activate original workflows:
   - `WhatsApp / Dra. Andreia - Assistente Consultório v1`
   - `WhatsApp / Dra. Andreia - Enviar Lembretes Automáticos`
3. Original workflows remain untouched in `n8n/` directory

---

## Architecture Decisions

Refer to `.squad/decisions.md` for full context:
- Decision 1: Platform 3-tier model (Platform → Clinic → Professional)
- Decision 2: Schema-per-professional isolation
- Decision 3: Instance-per-professional WhatsApp
- Decision 4: Parameterized workflow set (this implementation)
- Decision 5: 5-layer AI prompt composition

---

## Support & Troubleshooting

### Common Issues

**Issue:** "Tenant not found" error
- **Cause:** `tenant_code` in webhook URL doesn't match database
- **Fix:** Check `clinic_core.tenants` table, verify `tenant_code` and `status='active'`

**Issue:** SQL errors about missing schema
- **Cause:** `schema_name` in tenants table doesn't exist
- **Fix:** Create schema with `CREATE SCHEMA {schema_name}`

**Issue:** Evolution API fails to send message
- **Cause:** `evolution_instance_name` mismatch
- **Fix:** Verify instance name in EvolutionAPI matches `tenants` table

**Issue:** Chat memory not isolated
- **Cause:** Chat memory table not created in tenant schema
- **Fix:** Create `n8n_chat_histories` table in each tenant schema

---

## Files Modified

### Created (Generic Workflows)
- `n8n/WhatsApp - Assistente Clínica (Generic).json`
- `n8n/WhatsApp - Enviar Lembretes Automáticos (Generic).json`
- `n8n/tools-generic/` (9 tool workflows)

### Preserved (Original Workflows)
- `n8n/WhatsApp _ Dra. Andreia - Assistente Consultório v1.json`
- `n8n/WhatsApp _ Dra. Andreia - Enviar Lembretes Automáticos.json`
- `n8n/tools/` (9 original tool workflows)

### Documentation
- `n8n/MIGRATION-GUIDE.md` (this file)

---

**Next Steps:**
1. Review this migration guide with team
2. Coordinate with Penguin for database schema creation
3. Coordinate with Gordon for EvolutionAPI multi-instance setup
4. Deploy to staging environment
5. Test with Dra. Andreia as first tenant
6. Document any issues/learnings
7. Plan production rollout

---

**Contact:** Lucius (n8n Workflow Specialist)  
**Last Updated:** 2025-04-27
