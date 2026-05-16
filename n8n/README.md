# n8n Workflows — Generic Multi-Tenant Clinic Assistant

Version: 2.1
Status: Ready for deployment with schema `clinicas`

## Arquivos Ativos

- `WhatsApp - Assistente Clínica.json`
- `WhatsApp - Enviar Lembretes Automáticos.json`
- `tools/` (9 workflows de ferramentas)

Arquivos históricos (somente referência):

- `legacy-single-tenant/`

## Pré-requisitos

1. Banco provisionado com `database/SUPABASE_SETUP.sql`
2. Credenciais PostgreSQL no n8n
3. Evolution API configurada por tenant

## Fluxo Padrão

1. Webhook em `/webhook/{tenant_code}`
2. Carregar contexto com `clinicas.get_professional_context(p_tenant_code := $1)`
3. Aplicar `clinicas.check_whatsapp_rate_limit(...)` por usuário e instância WhatsApp
4. Obter `schema_name` do contexto
5. Executar queries tenant-local usando `{schema_name}.tabela`
6. Responder via instância WhatsApp do tenant

## Rate Limit de Entrada

O workflow `WhatsApp - Assistente Clínica.json` bloqueia mensagens acima do limite antes de transcrever áudio, chamar OpenAI, consultar vetores ou executar ferramentas. A chave de controle é o par `(whatsapp_instances.id, telefone do usuário)`, então o mesmo paciente tem limites independentes ao falar com instâncias diferentes.

Configuração padrão:

- 12 mensagens por minuto
- 60 mensagens por hora
- 200 mensagens por dia
- 10 mídias por hora
- cooldown mínimo de 300 segundos

Ajuste por tenant em `clinicas.whatsapp_instances.config->'rate_limit'`.

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
  AND p.tenant_code = 'dra-andreia';
```

Bloqueios ativos:

```sql
SELECT *
FROM clinicas.whatsapp_rate_limit_active_blocks
ORDER BY blocked_until DESC;
```

## SQL de Verificação

```sql
SELECT tenant_code, schema_name, full_name, professional_status
FROM clinicas.tenants
ORDER BY tenant_code;
```

```sql
SELECT p.tenant_code, wi.provider, wi.provider_config->>'instance_id' AS instance_id, wi.phone_number, wi.status
FROM clinicas.whatsapp_instances wi
JOIN clinicas.professionals p ON p.id = wi.professional_id
ORDER BY p.tenant_code;
```

## Importação no n8n

1. Importar `WhatsApp - Assistente Clínica.json`
2. Importar `WhatsApp - Enviar Lembretes Automáticos.json`
3. Importar os 9 workflows em `tools/`
4. Atualizar credenciais PostgreSQL e APIs
5. Executar `database/v008_whatsapp_rate_limits.sql` antes de ativar o workflow principal

## Onboarding de Novo Tenant

Use o banco para provisionar o tenant:

```sql
SELECT clinicas.provision_professional_schema(
  p_tenant_code := 'dr-carlos',
  p_schema_name := 'dr_carlos'
);
```

Depois, configure a instância WhatsApp desse tenant em `clinicas.whatsapp_instances`.

## Troubleshooting

### Tenant não carregado

```sql
SELECT *
FROM clinicas.get_professional_context(p_tenant_code := 'dr-carlos');
```

### Schema inválido

```sql
SELECT schema_name
FROM clinicas.professionals
WHERE tenant_code = 'dr-carlos';
```

### Instância WhatsApp inconsistente

```sql
SELECT p.tenant_code, wi.provider_config->>'instance_id' AS instance_id, wi.phone_number, wi.status
FROM clinicas.whatsapp_instances wi
JOIN clinicas.professionals p ON p.id = wi.professional_id
WHERE p.tenant_code = 'dr-carlos';
```

## Referências

- `WORKFLOW-STRUCTURE.md` (referência técnica)
- `legacy-single-tenant/README.md` (contexto histórico)
- `../doc/MULTI_TENANT_QUICK_START.md` (guia operacional)
