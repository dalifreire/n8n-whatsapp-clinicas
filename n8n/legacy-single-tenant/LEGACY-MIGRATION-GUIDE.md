# Legacy Migration Guide (Historical)

Version: 2.1 (historical context aligned)

## Objetivo

Este documento registra o que era single-tenant e como isso foi absorvido pela arquitetura multi-tenant atual.

Importante: os exemplos antigos de schema de plataforma e nomenclatura de arquivos foram descontinuados.

## Situação Atual (Fonte Oficial)

- Schema de plataforma: `clinicas`
- Contrato de contexto: `clinicas.get_professional_context(p_tenant_code text)`
- Workflows ativos:
  - `n8n/WhatsApp - Assistente Clínica.json`
  - `n8n/WhatsApp - Enviar Lembretes Automáticos.json`
  - `n8n/tools/` (9 ferramentas)
- Setup SQL oficial: `database/SUPABASE_SETUP.sql`

## O que mudou em relação ao legado

1. Roteamento de webhook por tenant (`/webhook/{tenant_code}`)
2. Resolução de contexto no banco (tenant -> schema_name)
3. Queries dinâmicas por schema do tenant
4. Configuração de assistente/WhatsApp no schema `clinicas`
5. Seed inicial de produção para Dra. Andreia já embutida no setup

## Mapeamento de termos antigos

- Schema antigo de plataforma -> `clinicas`
- Pasta antiga de ferramentas genéricas -> `tools/`
- Nome antigo do workflow principal -> `WhatsApp - Assistente Clínica.json`
- Nome antigo do workflow de lembretes -> `WhatsApp - Enviar Lembretes Automáticos.json`

## Rollback (somente emergência)

1. Desativar workflows multi-tenant ativos
2. Importar arquivos deste diretório (`legacy-single-tenant/`)
3. Reconfigurar webhook legado na Evolution API

## Referências

- `n8n/README.md`
- `n8n/WORKFLOW-STRUCTURE.md`
- `doc/MULTI_TENANT_QUICK_START.md`
