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
3. Obter `schema_name` do contexto
4. Executar queries tenant-local usando `{schema_name}.tabela`
5. Responder via instância WhatsApp do tenant

## SQL de Verificação

```sql
SELECT tenant_code, schema_name, full_name, professional_status
FROM clinicas.tenants
ORDER BY tenant_code;
```

```sql
SELECT p.tenant_code, wi.provider, wi.provider_instance_id, wi.phone_number, wi.status
FROM clinicas.whatsapp_instances wi
JOIN clinicas.professionals p ON p.id = wi.professional_id
ORDER BY p.tenant_code;
```

## Importação no n8n

1. Importar `WhatsApp - Assistente Clínica.json`
2. Importar `WhatsApp - Enviar Lembretes Automáticos.json`
3. Importar os 9 workflows em `tools/`
4. Atualizar credenciais PostgreSQL e APIs

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
SELECT p.tenant_code, wi.provider_instance_id, wi.phone_number, wi.status
FROM clinicas.whatsapp_instances wi
JOIN clinicas.professionals p ON p.id = wi.professional_id
WHERE p.tenant_code = 'dr-carlos';
```

## Referências

- `WORKFLOW-STRUCTURE.md` (referência técnica)
- `legacy-single-tenant/README.md` (contexto histórico)
- `../doc/MULTI_TENANT_QUICK_START.md` (guia operacional)
