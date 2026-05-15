-- ============================================================
-- v005_provisioning.sql
-- Funções de provisionamento de tenant:
--   - provision_professional_schema: cria novo tenant do zero
--   - register_existing_tenant: adota schema já existente (migrações legadas)
-- Depende de: v004_tenant_schema_template.sql
-- ============================================================

CREATE OR REPLACE FUNCTION clinicas.provision_professional_schema(
  p_tenant_code text,
  p_schema_name text DEFAULT NULL,
  p_organization_id uuid DEFAULT NULL,
  p_seed_demo_data boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = clinicas, public, extensions, pg_temp
AS $$
DECLARE
  v_schema_name text;
  v_professional_id uuid;
  v_existing_schema text;
BEGIN
  v_schema_name := COALESCE(p_schema_name, left(concat('clinicas_', replace(p_tenant_code, '-', '_')), 63));
  PERFORM clinicas.assert_valid_tenant_identifiers(p_tenant_code, v_schema_name);

  SELECT id, schema_name INTO v_professional_id, v_existing_schema
  FROM clinicas.professionals
  WHERE tenant_code = p_tenant_code;

  IF v_professional_id IS NOT NULL THEN
    IF v_existing_schema <> v_schema_name THEN
      RAISE EXCEPTION 'Tenant % already registered with schema %, not %', p_tenant_code, v_existing_schema, v_schema_name;
    END IF;
    PERFORM clinicas.ensure_tenant_schema_objects(v_schema_name);
    RETURN v_professional_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = v_schema_name) THEN
    RAISE EXCEPTION 'Schema % already exists. Use register_existing_tenant to adopt an existing schema.', v_schema_name;
  END IF;

  PERFORM clinicas.ensure_tenant_schema_objects(v_schema_name);

  INSERT INTO clinicas.professionals (
    organization_id, tenant_code, schema_name, full_name, specialties,
    credential_type, credential_number, status
  ) VALUES (
    p_organization_id,
    p_tenant_code,
    v_schema_name,
    initcap(replace(p_tenant_code, '-', ' ')),
    ARRAY[]::text[],
    NULL,
    NULL,
    CASE WHEN p_seed_demo_data THEN 'trial' ELSE 'active' END
  )
  RETURNING id INTO v_professional_id;

  INSERT INTO clinicas.assistant_configs (professional_id, persona_name, tone, language, model, prompt_config, status)
  VALUES (v_professional_id, 'Ana', 'acolhedor', 'pt-BR', 'gpt-4o', clinicas.default_prompt_config(), 'active')
  ON CONFLICT (professional_id) DO NOTHING;

  INSERT INTO clinicas.whatsapp_instances (professional_id, provider, provider_config, phone_number, status)
  VALUES (v_professional_id, 'evolution', '{}'::jsonb, 'nao-informado', 'disconnected')
  ON CONFLICT (professional_id) DO NOTHING;

  RETURN v_professional_id;
END;
$$;

COMMENT ON FUNCTION clinicas.provision_professional_schema(text, text, uuid, boolean) IS 'ADR §5 provisioner: validates identifiers, creates full tenant schema, and registers the professional.';

CREATE OR REPLACE FUNCTION clinicas.register_existing_tenant(
  p_tenant_code text,
  p_schema_name text,
  p_organization_id uuid DEFAULT NULL,
  p_full_name text DEFAULT NULL,
  p_credential_type text DEFAULT NULL,
  p_credential_number text DEFAULT NULL,
  p_specialties text[] DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_whatsapp_phone text DEFAULT NULL,
  p_whatsapp_provider text DEFAULT 'evolution',
  p_whatsapp_instance_id text DEFAULT NULL,
  p_whatsapp_phone_e164 text DEFAULT NULL,
  p_assistant_persona_name text DEFAULT 'Ana',
  p_assistant_tone text DEFAULT 'acolhedor',
  p_assistant_language text DEFAULT 'pt-BR',
  p_assistant_model text DEFAULT 'gpt-4o',
  p_prompt_config jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = clinicas, public, extensions, pg_temp
AS $$
DECLARE
  v_professional_id uuid;
  v_other_tenant text;
  v_whatsapp_phone_final text;
BEGIN
  PERFORM clinicas.assert_valid_tenant_identifiers(p_tenant_code, p_schema_name);

  IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = p_schema_name) THEN
    RAISE EXCEPTION 'Schema % does not exist; register_existing_tenant adopts existing schemas only', p_schema_name;
  END IF;

  SELECT tenant_code INTO v_other_tenant
  FROM clinicas.professionals
  WHERE schema_name = p_schema_name AND tenant_code <> p_tenant_code;

  IF v_other_tenant IS NOT NULL THEN
    RAISE EXCEPTION 'Schema % is already registered to tenant %', p_schema_name, v_other_tenant;
  END IF;

  v_whatsapp_phone_final := NULLIF(trim(COALESCE(p_whatsapp_phone_e164, p_whatsapp_phone, p_phone, '')), '');

  PERFORM clinicas.ensure_tenant_schema_objects(p_schema_name);

  INSERT INTO clinicas.professionals (
    organization_id, tenant_code, schema_name, full_name, specialties,
    credential_type, credential_number, status
  ) VALUES (
    p_organization_id,
    p_tenant_code,
    p_schema_name,
    COALESCE(p_full_name, initcap(replace(p_tenant_code, '-', ' '))),
    COALESCE(p_specialties, ARRAY[]::text[]),
    p_credential_type,
    p_credential_number,
    'active'
  )
  ON CONFLICT (tenant_code) DO UPDATE SET
    organization_id = EXCLUDED.organization_id,
    schema_name = EXCLUDED.schema_name,
    full_name = EXCLUDED.full_name,
    specialties = EXCLUDED.specialties,
    credential_type = EXCLUDED.credential_type,
    credential_number = EXCLUDED.credential_number,
    status = 'active'
  RETURNING id INTO v_professional_id;

  INSERT INTO clinicas.assistant_configs (
    professional_id, persona_name, tone, language, model, prompt_config, status
  ) VALUES (
    v_professional_id,
    p_assistant_persona_name,
    p_assistant_tone,
    COALESCE(p_assistant_language, 'pt-BR'),
    COALESCE(p_assistant_model, 'gpt-4o'),
    COALESCE(p_prompt_config, clinicas.default_prompt_config()),
    'active'
  )
  ON CONFLICT (professional_id) DO UPDATE SET
    persona_name = EXCLUDED.persona_name,
    tone = EXCLUDED.tone,
    language = EXCLUDED.language,
    model = EXCLUDED.model,
    prompt_config = EXCLUDED.prompt_config,
    status = 'active';

  INSERT INTO clinicas.whatsapp_instances (
    professional_id, provider, provider_config, phone_number, status
  ) VALUES (
    v_professional_id,
    CASE
      WHEN COALESCE(p_whatsapp_provider, 'evolution') IN ('evolution-api', 'evolution_api') THEN 'evolution'
      WHEN COALESCE(p_whatsapp_provider, 'evolution') IN ('cloud-api', 'cloudapi') THEN 'whatsapp_cloud_api'
      ELSE COALESCE(p_whatsapp_provider, 'evolution')
    END,
    jsonb_strip_nulls(jsonb_build_object('instance_id', p_whatsapp_instance_id)),
    COALESCE(v_whatsapp_phone_final, 'nao-informado'),
    CASE WHEN v_whatsapp_phone_final IS NULL THEN 'disconnected' ELSE 'connected' END
  )
  ON CONFLICT (professional_id) DO UPDATE SET
    provider = EXCLUDED.provider,
    provider_config = EXCLUDED.provider_config,
    phone_number = EXCLUDED.phone_number,
    status = EXCLUDED.status;

  RETURN v_professional_id;
END;
$$;

COMMENT ON FUNCTION clinicas.register_existing_tenant(text, text, uuid, text, text, text, text[], text, text, text, text, text, text, text, text, text, jsonb) IS 'Adopts an existing tenant schema without recreating it; used for legacy seed schemas and migrations.';
