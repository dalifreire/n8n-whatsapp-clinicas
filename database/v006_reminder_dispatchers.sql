-- ============================================================
-- v006_reminder_dispatchers.sql
-- Funções globais de despacho de lembretes:
--   - fetch_due_reminders_all: varre todos os tenants ativos
--   - mark_reminder_sent: marca lembrete enviado em tenant específico
-- Depende de: v005_provisioning.sql
-- ============================================================

CREATE OR REPLACE FUNCTION clinicas.fetch_due_reminders_all(p_window_minutes int DEFAULT 30)
RETURNS TABLE (
  tenant_code        text,
  schema_name        text,
  professional_id    uuid,
  reminder_id        uuid,
  patient_id         uuid,
  patient_phone_e164 text,
  patient_name       text,
  appointment_id     uuid,
  scheduled_at       timestamptz,
  reminder_type      text,
  payload            jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
DECLARE
  tenant_rec record;
  reminder_rec record;
BEGIN
  FOR tenant_rec IN
    SELECT t.tenant_code, t.schema_name, t.professional_id
    FROM clinicas.tenants t
    WHERE t.professional_status IN ('active', 'trial')
  LOOP
    FOR reminder_rec IN
      EXECUTE format(
        'SELECT reminder_id, patient_id, patient_phone_e164, patient_name, appointment_id, scheduled_at, reminder_type, payload FROM %I.fetch_due_reminders($1)',
        tenant_rec.schema_name
      ) USING p_window_minutes
    LOOP
      tenant_code := tenant_rec.tenant_code;
      schema_name := tenant_rec.schema_name;
      professional_id := tenant_rec.professional_id;
      reminder_id := reminder_rec.reminder_id;
      patient_id := reminder_rec.patient_id;
      patient_phone_e164 := reminder_rec.patient_phone_e164;
      patient_name := reminder_rec.patient_name;
      appointment_id := reminder_rec.appointment_id;
      scheduled_at := reminder_rec.scheduled_at;
      reminder_type := reminder_rec.reminder_type;
      payload := reminder_rec.payload;
      RETURN NEXT;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION clinicas.mark_reminder_sent(
  p_tenant_code text,
  p_reminder_id uuid,
  p_status text DEFAULT 'enviado',
  p_provider_message_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
DECLARE
  v_schema_name text;
BEGIN
  SELECT p.schema_name INTO v_schema_name
  FROM clinicas.professionals p
  WHERE p.tenant_code = p_tenant_code
    AND p.status NOT IN ('suspended', 'archived');

  IF v_schema_name IS NULL THEN
    RAISE EXCEPTION 'Tenant % not found or not serviceable', p_tenant_code;
  END IF;

  EXECUTE format('SELECT %I.mark_reminder_sent($1, $2, $3)', v_schema_name)
  USING p_reminder_id, p_status, p_provider_message_id;
END;
$$;
