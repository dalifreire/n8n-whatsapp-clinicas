# Multi-Tenant Platform Quick Start Guide

## Overview

A plataforma usa isolamento schema-per-professional.

- Metadados compartilhados: schema `clinicas`
- Dados operacionais: um schema por profissional (ex.: `dra_andreia`)
- Contrato canônico de contexto: `clinicas.get_professional_context(p_tenant_code text)`

## Estrutura Atual

```text
n8n-whatsapp-clinicas/
  database/
    SUPABASE_SETUP.sql
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

Execute o script completo:

```sql
-- Supabase SQL Editor
-- arquivo: database/SUPABASE_SETUP.sql
```

Esse script cria:

- schema `clinicas`
- tabelas de plataforma: `organizations`, `professionals`, `assistant_configs`, `whatsapp_instances`, `message_dedupe`, `prompt_templates`
- funções canônicas (contexto, provisionamento, reminders)
- seed inicial da Dra. Andreia (`tenant_code = 'dra-andreia'`, schema `dra_andreia`)

## 2. Verificações Rápidas

```sql
-- Profissionais registrados
SELECT tenant_code, schema_name, full_name, status
FROM clinicas.professionals
ORDER BY tenant_code;

-- Instâncias WhatsApp
SELECT p.tenant_code, wi.provider, wi.provider_instance_id, wi.phone_number, wi.status
FROM clinicas.whatsapp_instances wi
JOIN clinicas.professionals p ON p.id = wi.professional_id
ORDER BY p.tenant_code;

-- Contrato de contexto (entrada canônica para n8n/Python)
SELECT *
FROM clinicas.get_professional_context(p_tenant_code := 'dra-andreia');

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
4. Usar `schema_name` retornado em todas as queries tenant-local

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

## 4. Provisionamento de Novo Profissional

### Opção A: Novo schema gerado pela plataforma

```sql
SELECT clinicas.provision_professional_schema(
  p_tenant_code := 'dr-carlos',
  p_schema_name := 'dr_carlos'
);
```

Depois ajuste dados cadastrais/configuração:

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
    language = 'pt-BR',
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
);
```

## 5. Knowledge Base (Python)

Scripts atualizados em `src/`:

```bash
# Seed de documentos
PROFESSIONAL_ID=dr-carlos python src/knowledge_base_consultorio.py

# Indexação RAG por tenant
python src/knowledge_base_indexar.py --tenant-code dr-carlos

# Atualização/scraping
python src/knowledge_base_atualizar.py --professional-id dr-carlos --full
```

## 6. Troubleshooting

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
WHERE schema_name = 'dr_carlos';
```

## 7. Regras de Segurança

1. Nunca montar schema com input livre do usuário.
2. `schema_name` deve vir do banco (`clinicas.get_professional_context` / `clinicas.professionals`).
3. Manter RLS habilitado conforme setup.
4. Segregar credenciais e segredos fora de JSONs de workflow.

---

Last Updated: 2026-05-06
Version: 2.1 (aligned with `database/SUPABASE_SETUP.sql`)
