-- ============================================================
-- v003_platform_functions.sql
-- Funções auxiliares da plataforma: validação de identifiers,
-- contexto canônico ADR §2 e view clinicas.tenants.
-- Depende de: v002_core_tables.sql
-- ============================================================

CREATE OR REPLACE FUNCTION clinicas.is_reserved_schema_name(p_schema_name text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
  SELECT p_schema_name IN ('information_schema', 'clinicas', 'public', 'auth', 'storage', 'vault', 'extensions')
     OR p_schema_name LIKE 'pg\_%' ESCAPE '\';
$$;

CREATE OR REPLACE FUNCTION clinicas.assert_valid_tenant_identifiers(
  p_tenant_code text,
  p_schema_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
BEGIN
  IF p_tenant_code IS NULL OR p_tenant_code !~ '^[a-z][a-z0-9-]{1,62}[a-z0-9]$' THEN
    RAISE EXCEPTION 'Invalid tenant_code %. Expected kebab-case matching ^[a-z][a-z0-9-]{1,62}[a-z0-9]$', p_tenant_code;
  END IF;

  IF p_schema_name IS NULL OR p_schema_name !~ '^[a-z][a-z0-9_]{0,62}$' THEN
    RAISE EXCEPTION 'Invalid schema_name %. Expected snake_case matching ^[a-z][a-z0-9_]{0,62}$', p_schema_name;
  END IF;

  IF clinicas.is_reserved_schema_name(p_schema_name) THEN
    RAISE EXCEPTION 'Schema name % is reserved and cannot be used for a tenant', p_schema_name;
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- Função canônica de contexto de profissional (ADR §2)
-- Ponto de entrada para n8n, Python e futuras APIs.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION clinicas.get_professional_context(p_tenant_code text)
RETURNS TABLE (
  professional_id          uuid,
  organization_id          uuid,
  tenant_code              text,
  schema_name              text,
  full_name                text,
  nome                     text,
  specialties              text[],
  credential_type          text,
  credential_number        text,
  professional_status      text,
  organization_name        text,
  organization_address     text,
  organization_phone       text,
  organization_hours       jsonb,
  organization_instagram   text,
  organization_metadata    jsonb,
  assistant_persona_name   text,
  assistant_tone           text,
  assistant_language       text,
  assistant_model          text,
  assistant_status         text,
  prompt_config            jsonb,
  whatsapp_provider        text,
  whatsapp_instance_id     text,
  whatsapp_phone_e164      text,
  whatsapp_status          text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
  SELECT
    p.id AS professional_id,
    p.organization_id,
    p.tenant_code::text,
    p.schema_name::text,
    p.full_name::text,
    p.full_name::text AS nome,
    p.specialties,
    p.credential_type::text,
    p.credential_number::text,
    p.status::text AS professional_status,
    o.name::text AS organization_name,
    o.address::text AS organization_address,
    o.contact_phone::text AS organization_phone,
    COALESCE(o.business_hours, '{}'::jsonb) AS organization_hours,
    o.instagram_handle::text AS organization_instagram,
    COALESCE(o.metadata, '{}'::jsonb) AS organization_metadata,
    ac.persona_name::text AS assistant_persona_name,
    ac.tone::text AS assistant_tone,
    COALESCE(ac.language, 'pt-BR')::text AS assistant_language,
    COALESCE(ac.model, 'gpt-4o')::text AS assistant_model,
    COALESCE(ac.status, 'disabled')::text AS assistant_status,
    COALESCE(ac.prompt_config, clinicas.default_prompt_config()) AS prompt_config,
    wi.provider::text AS whatsapp_provider,
    (wi.provider_config->>'instance_id')::text AS whatsapp_instance_id,
    wi.phone_number::text AS whatsapp_phone_e164,
    COALESCE(wi.status, 'disconnected')::text AS whatsapp_status
  FROM clinicas.professionals p
  LEFT JOIN clinicas.organizations o ON o.id = p.organization_id
  LEFT JOIN clinicas.assistant_configs ac ON ac.professional_id = p.id AND ac.status = 'active'
  LEFT JOIN clinicas.whatsapp_instances wi ON wi.professional_id = p.id
  WHERE p.tenant_code = p_tenant_code
    AND p.status NOT IN ('suspended', 'archived')
  LIMIT 1;
$$;

COMMENT ON FUNCTION clinicas.get_professional_context(text) IS 'Canonical ADR §2 tenant context entry point for n8n, Python, and future APIs.';

CREATE OR REPLACE VIEW clinicas.tenants AS
SELECT ctx.*
FROM clinicas.professionals p
CROSS JOIN LATERAL clinicas.get_professional_context(p.tenant_code::text) ctx;

COMMENT ON VIEW clinicas.tenants IS 'Read-only wrapper over clinicas.get_professional_context with the same ADR §2 columns.';
