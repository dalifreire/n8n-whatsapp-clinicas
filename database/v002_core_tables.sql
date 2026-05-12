-- ============================================================
-- v002_core_tables.sql
-- Tabelas do registry compartilhado (schema clinicas).
-- Depende de: v001_extensions_and_schema.sql
-- ============================================================

-- ------------------------------------------------------------
-- Função auxiliar de configuração padrão de prompt
-- (declarada aqui pois é usada como DEFAULT em assistant_configs)
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION clinicas.default_prompt_config()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
  SELECT '{
    "prompt_version": "v1",
    "layers": {
      "base": {"override": null, "extra_rules": []},
      "clinic": {"override": null, "extra_rules": []},
      "professional": {"override": null, "extra_rules": []},
      "persona": {"override": null, "extra_rules": []},
      "service": {"override": null, "extra_rules": []}
    },
    "tools_enabled": ["buscar_conhecimento", "consultar_agendamentos", "agendar_consulta"],
    "escalation": {"human_handoff_keywords": [], "emergency_keywords": []}
  }'::jsonb;
$$;

-- ------------------------------------------------------------
-- Tabelas core do registry
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS clinicas.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  address text,
  contact_phone text,
  business_hours jsonb DEFAULT '{}'::jsonb,
  instagram_handle text,
  metadata jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS clinicas.professionals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES clinicas.organizations(id) ON DELETE SET NULL,
  tenant_code varchar(64) UNIQUE NOT NULL,
  schema_name varchar(63) UNIQUE NOT NULL,
  full_name text NOT NULL,
  specialties text[] DEFAULT ARRAY[]::text[],
  credential_type text,
  credential_number text,
  status text NOT NULL DEFAULT 'trial',
  CONSTRAINT professionals_tenant_code_format CHECK (tenant_code ~ '^[a-z][a-z0-9-]{1,62}[a-z0-9]$'),
  CONSTRAINT professionals_schema_name_format CHECK (schema_name ~ '^[a-z][a-z0-9_]{0,62}$'),
  CONSTRAINT professionals_status_check CHECK (status IN ('active', 'suspended', 'trial', 'archived'))
);

CREATE INDEX IF NOT EXISTS idx_professionals_tenant_code ON clinicas.professionals(tenant_code);
CREATE INDEX IF NOT EXISTS idx_professionals_schema_name ON clinicas.professionals(schema_name);
CREATE INDEX IF NOT EXISTS idx_professionals_status ON clinicas.professionals(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_professionals_tenant_code_unique ON clinicas.professionals(tenant_code);
CREATE UNIQUE INDEX IF NOT EXISTS idx_professionals_schema_name_unique ON clinicas.professionals(schema_name);

CREATE TABLE IF NOT EXISTS clinicas.assistant_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  professional_id uuid NOT NULL UNIQUE REFERENCES clinicas.professionals(id) ON DELETE CASCADE,
  persona_name text DEFAULT 'Ana',
  tone text DEFAULT 'acolhedor',
  language text DEFAULT 'pt-BR',
  model text DEFAULT 'gpt-5.1',
  prompt_config jsonb DEFAULT clinicas.default_prompt_config(),
  status text NOT NULL DEFAULT 'active',
  CONSTRAINT assistant_configs_status_check CHECK (status IN ('active', 'disabled'))
);

CREATE INDEX IF NOT EXISTS idx_assistant_configs_professional ON clinicas.assistant_configs(professional_id);
CREATE INDEX IF NOT EXISTS idx_assistant_configs_status ON clinicas.assistant_configs(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_assistant_configs_professional_unique ON clinicas.assistant_configs(professional_id);

CREATE TABLE IF NOT EXISTS clinicas.whatsapp_instances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  professional_id uuid NOT NULL UNIQUE REFERENCES clinicas.professionals(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'whatsapp_cloud_api',
  provider_config jsonb DEFAULT '{}'::jsonb,
  phone_number text NOT NULL,
  status text NOT NULL DEFAULT 'disconnected',
  config jsonb DEFAULT '{}'::jsonb,
  CONSTRAINT whatsapp_instances_status_check CHECK (status IN ('connected', 'disconnected')),
  CONSTRAINT whatsapp_instances_provider_check CHECK (provider IN ('evolution', 'whatsapp_cloud_api'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_instances_professional_unique ON clinicas.whatsapp_instances(professional_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_instances_professional ON clinicas.whatsapp_instances(professional_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_instances_phone ON clinicas.whatsapp_instances(phone_number);
CREATE INDEX IF NOT EXISTS idx_whatsapp_instances_status ON clinicas.whatsapp_instances(status);

CREATE TABLE IF NOT EXISTS clinicas.message_dedupe (
  tenant_code varchar(64) NOT NULL,
  provider_message_id text NOT NULL,
  received_at timestamptz DEFAULT now(),
  PRIMARY KEY (tenant_code, provider_message_id)
);

CREATE TABLE IF NOT EXISTS clinicas.prompt_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  prompt_config jsonb NOT NULL DEFAULT clinicas.default_prompt_config(),
  status text NOT NULL DEFAULT 'active'
);

-- Row Level Security
ALTER TABLE clinicas.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinicas.professionals ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinicas.assistant_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinicas.whatsapp_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinicas.message_dedupe ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinicas.prompt_templates ENABLE ROW LEVEL SECURITY;
