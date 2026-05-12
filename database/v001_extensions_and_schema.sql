-- ============================================================
-- v001_extensions_and_schema.sql
-- Extensões PostgreSQL e criação do schema compartilhado clinicas.
-- Deve ser executado primeiro, pois todos os scripts dependem
-- da extensão vector e do schema clinicas.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE SCHEMA IF NOT EXISTS clinicas;

-- Remove assinaturas de funções/views rejeitadas ou legadas antes de recriar
-- o contrato ADR. Garante idempotência nas execuções subsequentes.
DROP VIEW IF EXISTS clinicas.tenants;
DROP FUNCTION IF EXISTS clinicas.get_professional_context(text);
DROP FUNCTION IF EXISTS clinicas.get_professional_context(varchar, varchar);
DROP FUNCTION IF EXISTS clinicas.provision_professional_schema(varchar);
DROP FUNCTION IF EXISTS clinicas.provision_professional_schema(text, text, uuid, boolean);
DROP FUNCTION IF EXISTS clinicas.register_existing_tenant(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar);
DROP FUNCTION IF EXISTS clinicas.fetch_due_reminders_all(int);
DROP FUNCTION IF EXISTS clinicas.mark_reminder_sent(text, uuid, text, text);
