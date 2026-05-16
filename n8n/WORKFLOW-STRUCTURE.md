# Generic n8n Workflow Structure — Technical Reference

Version: 2.1

## Estrutura de Arquivos

```text
n8n/
  WhatsApp - Assistente Clínica.json
  WhatsApp - Enviar Lembretes Automáticos.json
  tools/
    Ferramenta_ Agendar Consulta.json
    Ferramenta_ Buscar Horários Disponíveis.json
    Ferramenta_ Buscar Paciente.json
    Ferramenta_ Cancelar Consulta.json
    Ferramenta_ Consultar Agendamentos do Paciente.json
    Ferramenta_ Listar Dentistas e Procedimentos.json
    Ferramenta_ Listar Especialidades.json
    Ferramenta_ Reiniciar Conversa.json
    Ferramenta_ Resumo Financeiro do Paciente.json
  legacy-single-tenant/
```

## Contrato de Contexto (Fonte da Verdade)

A entrada canônica para qualquer workflow multi-tenant é:

```sql
SELECT *
FROM clinicas.get_professional_context(p_tenant_code := $1);
```

Campos críticos usados pelo n8n:

- `tenant_code`
- `schema_name`
- `professional_id`
- `full_name`
- `assistant_persona_name`
- `assistant_model`
- `whatsapp_provider`
- `whatsapp_instance_id`
- `whatsapp_phone_e164`
- `whatsapp_status`

## Fluxo de Execução (Main Workflow)

1. Webhook recebe rota `/webhook/{tenant_code}`
2. Extrai `tenant_code`
3. Executa query de contexto (`clinicas.get_professional_context`)
4. Valida tenant apto (`professional_status` e `whatsapp_status`)
5. Aplica rate limit por usuário e instância WhatsApp
6. Monta prompt (configuração base + contexto da clínica/profissional)
7. Executa agente e ferramentas
8. Persiste histórico no schema do tenant
9. Envia resposta pela instância do tenant

## Rate Limit de Entrada

Antes de qualquer etapa com custo externo, o workflow chama:

```sql
SELECT *
FROM clinicas.check_whatsapp_rate_limit(
  p_tenant_code := $1,
  p_user_phone_e164 := $2,
  p_provider_message_id := $3,
  p_message_type := $4,
  p_whatsapp_phone_e164 := $5,
  p_request_metadata := $6::jsonb
);
```

Se `allowed = false`, o fluxo para sem transcrever áudio, chamar modelo, consultar vetores ou executar ferramentas.

Limites padrão por `(whatsapp_instances.id, telefone do usuário)`:

- `per_minute`: 12
- `per_hour`: 60
- `per_day`: 200
- `media_per_hour`: 10
- `cooldown_seconds`: 300

Overrides ficam em `clinicas.whatsapp_instances.config->'rate_limit'`.

## Padrão de Query Dinâmica por Schema

Regra: schema sempre vem do contexto carregado do banco.

Exemplo:

```sql
SELECT *
FROM {schema_name}.pacientes
WHERE telefone = $1;
```

```sql
INSERT INTO {schema_name}.conversas (telefone, nome, mensagem, resposta_ia)
VALUES ($1, $2, $3, $4);
```

```sql
SELECT *
FROM {schema_name}.buscar_documentos_similares($1::vector, $2, $3);
```

## Isolamento e Segurança

1. Nunca aceitar `schema_name` direto do usuário.
2. Sempre resolver `schema_name` via `clinicas.get_professional_context`.
3. Manter RLS habilitado (conforme setup SQL).
4. Preferir parâmetros SQL para dados de entrada (`$1`, `$2`, ...).

## Reminder Workflow

Padrão recomendado:

- Buscar lembretes pendentes via `clinicas.fetch_due_reminders_all(...)`
- Para cada item, enviar mensagem pelo provider do tenant
- Marcar status via `clinicas.mark_reminder_sent(...)`

Exemplo:

```sql
SELECT * FROM clinicas.fetch_due_reminders_all(30);
```

```sql
SELECT clinicas.mark_reminder_sent(
  p_tenant_code := $1,
  p_reminder_id := $2,
  p_status := 'enviado',
  p_provider_message_id := $3
);
```

## Checklist de Teste

- Webhook roteia corretamente por `tenant_code`
- Contexto retorna exatamente 1 tenant ativo
- Querys usam o `schema_name` esperado
- Ferramentas retornam dados somente do tenant
- Memória/histórico não vaza entre tenants
- Rate limit bloqueia antes do agente quando `allowed = false`
- Reminder workflow processa e atualiza status

## Comandos SQL de Diagnóstico

```sql
SELECT tenant_code, schema_name, full_name, professional_status, whatsapp_status
FROM clinicas.tenants
ORDER BY tenant_code;
```

```sql
SELECT p.tenant_code, wi.provider, wi.provider_config->>'instance_id' AS instance_id, wi.status
FROM clinicas.whatsapp_instances wi
JOIN clinicas.professionals p ON p.id = wi.professional_id;
```

```sql
SELECT *
FROM clinicas.get_professional_context(p_tenant_code := 'dra-andrea');
```

```sql
SELECT *
FROM clinicas.whatsapp_rate_limit_active_blocks
ORDER BY blocked_until DESC;
```
