# Multi-Tenant Platform Quick Start Guide

## Overview

A plataforma usa isolamento **schema-per-professional**.

- Metadados compartilhados: schema `clinicas`
- Dados operacionais: um schema por profissional (ex.: `clinicas_dra_andrea`)
- Contrato canônico de contexto: `clinicas.get_professional_context(p_tenant_code text)`

## Estrutura do Repositório

```text
n8n-whatsapp-clinicas/
  database/
    v001_extensions_and_schema.sql   -- extensões e schema clinicas
    v002_core_tables.sql             -- tabelas do registry compartilhado
    v003_platform_functions.sql      -- get_professional_context, tenants view
    v004_tenant_schema_template.sql  -- ensure_tenant_schema_objects (template por profissional)
    v005_provisioning.sql            -- provision_professional_schema, register_existing_tenant
    v006_reminder_dispatchers.sql    -- fetch_due_reminders_all, mark_reminder_sent
    v007_seed_dra_andrea.sql        -- carga inicial Dra. Andrea Mota
    v008_whatsapp_rate_limits.sql    -- rate limit por usuário e instância WhatsApp
  src/
    knowledge_base_atualizar.py
    knowledge_base_consultorio.py
    knowledge_base_indexar.py
  doc/
    MULTI_TENANT_QUICK_START.md
    KNOWLEDGE_BASE_MULTI_TENANT.md
    SUMMARY_MULTI_TENANT_KB.md
  n8n/
    WhatsApp - Assistente Clínica.json
    WhatsApp - Enviar Lembretes Automáticos.json
    tools/
```

## 1. Setup do Banco

Execute os scripts em ordem no Supabase SQL Editor:

```
v001_extensions_and_schema.sql
v002_core_tables.sql
v003_platform_functions.sql
v004_tenant_schema_template.sql
v005_provisioning.sql
v006_reminder_dispatchers.sql
v007_seed_dra_andrea.sql   ← carga inicial (opcional em ambientes sem Dra. Andrea)
v008_whatsapp_rate_limits.sql
```

Após execução completa:

- Schema `clinicas` com tabelas de plataforma: `organizations`, `professionals`, `assistant_configs`, `whatsapp_instances`, `message_dedupe`, `prompt_templates`
- Rate limit de entrada por usuário e instância WhatsApp: `whatsapp_rate_limit_buckets`, `whatsapp_rate_limit_blocks`, `clinicas.check_whatsapp_rate_limit(...)`
- Funções canônicas de contexto, provisionamento e lembretes
- Seed inicial da Dra. Andrea (`tenant_code = 'dra-andrea'`, schema `clinicas_dra_andrea`)

## 2. Verificações Rápidas

```sql
-- Profissionais registrados
SELECT tenant_code, schema_name, full_name, status
FROM clinicas.professionals
ORDER BY tenant_code;

-- Instâncias WhatsApp
SELECT p.tenant_code, wi.provider, wi.provider_config->>'instance_id' AS instance_id, wi.phone_number, wi.status
FROM clinicas.whatsapp_instances wi
JOIN clinicas.professionals p ON p.id = wi.professional_id
ORDER BY p.tenant_code;

-- Contrato de contexto (entrada canônica para n8n/Python)
SELECT *
FROM clinicas.get_professional_context(p_tenant_code := 'dra-andrea');

-- View de leitura baseada no contrato
SELECT tenant_code, schema_name, full_name, assistant_persona_name, whatsapp_status
FROM clinicas.tenants
ORDER BY tenant_code;
```

## 3. Padrão n8n (Obrigatório)

Fluxo mínimo recomendado para qualquer webhook:

1. Extrair `tenant_code` da rota (`/webhook/{tenant_code}`)
2. Carregar contexto via `clinicas.get_professional_context(...)`
3. Validar tenant ativo (contexto retornado + status)
4. Aplicar rate limit com `clinicas.check_whatsapp_rate_limit(...)` antes de transcrever áudio, chamar IA ou executar ferramentas
5. Usar `schema_name` retornado em todas as queries tenant-local

Exemplo de query de contexto:

```sql
SELECT * FROM clinicas.get_professional_context(p_tenant_code := $1);
```

Exemplo de query tenant-local (schema dinâmico validado do banco):

```sql
-- schema_name vindo do contexto, nunca de input livre
SELECT *
FROM {schema_name}.pacientes
WHERE telefone = $1;
```

## 4. Rate Limit por Instância WhatsApp

O workflow principal chama `clinicas.check_whatsapp_rate_limit(...)` logo após resolver o tenant pela instância WhatsApp. Se `allowed = false`, o fluxo para e não executa transcrição, embeddings, agente ou ferramentas.

Limites padrão por par `(instância WhatsApp, telefone do usuário)`:

- 12 mensagens por minuto
- 60 mensagens por hora
- 200 mensagens por dia
- 10 mídias por hora (`audio`, `image`, `video`, `document`, `sticker`)
- cooldown mínimo de 300 segundos

Para personalizar uma instância, use `whatsapp_instances.config->'rate_limit'`:

```sql
UPDATE clinicas.whatsapp_instances wi
SET config = jsonb_set(
  COALESCE(config, '{}'::jsonb),
  '{rate_limit}',
  '{"enabled": true, "per_minute": 8, "per_hour": 40, "per_day": 120, "media_per_hour": 6, "cooldown_seconds": 600}'::jsonb,
  true
)
FROM clinicas.professionals p
WHERE p.id = wi.professional_id
  AND p.tenant_code = 'dra-andrea';
```

Ver bloqueios ativos:

```sql
SELECT *
FROM clinicas.whatsapp_rate_limit_active_blocks
ORDER BY blocked_until DESC;
```

Limpeza periódica opcional:

```sql
SELECT * FROM clinicas.cleanup_whatsapp_rate_limits(7);
```

## 5. Provisionamento de Novo Profissional

### Opção A: Novo schema gerado pela plataforma

```sql
SELECT clinicas.provision_professional_schema(
  p_tenant_code := 'dr-carlos',
  p_schema_name := 'dr_carlos'
);
```
-- Instâncias WhatsApp
SELECT p.tenant_code, wi.provider, wi.provider_config->>'instance_id' AS instance_id, wi.phone_number, wi.status

```sql
UPDATE clinicas.professionals
SET full_name = 'Dr. Carlos Silva',
    credential_type = 'CRO',
    credential_number = '5678',
    status = 'active'
WHERE tenant_code = 'dr-carlos';

UPDATE clinicas.assistant_configs
SET persona_name = 'Carla',
    tone = 'acolhedor',
      p_schema_name := 'clinicas_dr_carlos'
    model = 'gpt-4o',
    status = 'active'
WHERE professional_id = (
  SELECT id FROM clinicas.professionals WHERE tenant_code = 'dr-carlos'
);

UPDATE clinicas.whatsapp_instances
SET provider = 'evolution',
    provider_instance_id = 'Dr Carlos Silva',
    phone_number = '5571888888888',
    status = 'connected'
WHERE professional_id = (
  SELECT id FROM clinicas.professionals WHERE tenant_code = 'dr-carlos'
);
```

### Opção B: Adotar schema legado existente

```sql
SELECT clinicas.register_existing_tenant(
  p_tenant_code := 'dr-carlos',
  p_schema_name := 'dr_carlos',
  p_full_name := 'Dr. Carlos Silva',
  p_credential_type := 'CRO',
  p_credential_number := '5678'
        provider_config = jsonb_build_object('instance_id', 'Dr Carlos Silva'),
```

## 6. Knowledge Base (Python)

Scripts atualizados em `src/`:

```bash
# Seed de documentos
PROFESSIONAL_ID=dr-carlos python src/knowledge_base_consultorio.py

# Indexação RAG por tenant
python src/knowledge_base_indexar.py --tenant-code dr-carlos
      p_schema_name := 'clinicas_dr_carlos',
# Atualização/scraping
python src/knowledge_base_atualizar.py --professional-id dr-carlos --full
```

## 7. Troubleshooting

### Tenant não encontrado

```sql
SELECT tenant_code, schema_name, status
FROM clinicas.professionals
WHERE tenant_code = 'dr-carlos';
```

### Contexto vazio

```sql
SELECT *
FROM clinicas.get_professional_context(p_tenant_code := 'dr-carlos');
```

Se não retornar linha, verifique `status` do profissional (`active`/`trial`) e relação com `assistant_configs` e `whatsapp_instances`.

### Schema inexistente

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'clinicas_dr_carlos';
```

## 8. Regras de Segurança

1. Nunca montar schema com input livre do usuário.
2. `schema_name` deve vir do banco (`clinicas.get_professional_context` / `clinicas.professionals`).
3. Aplicar rate limit antes de qualquer etapa com custo externo.
4. Manter RLS habilitado conforme setup.
5. Segregar credenciais e segredos fora de JSONs de workflow.

---

Last Updated: 2026-05-15
Version: 2.3 (scripts numerados v001–v008, rate limit por instância WhatsApp)
