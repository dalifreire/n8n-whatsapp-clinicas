-- ============================================================
-- v008_whatsapp_rate_limits.sql
-- Rate limit por usuário em cada instância WhatsApp.
-- Objetivo: bloquear abuso antes de transcrição, IA e ferramentas,
-- reduzindo risco de DoS e descontrole de custos.
-- Depende de: v007_seed_dra_andrea.sql
-- ============================================================

DROP VIEW IF EXISTS clinicas.whatsapp_rate_limit_active_blocks;
DROP FUNCTION IF EXISTS clinicas.check_whatsapp_rate_limit(text, text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS clinicas.cleanup_whatsapp_rate_limits(int);

CREATE OR REPLACE FUNCTION clinicas.default_whatsapp_rate_limit_config()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
  SELECT '{
    "enabled": true,
    "per_minute": 12,
    "per_hour": 60,
    "per_day": 200,
    "media_per_hour": 10,
    "cooldown_seconds": 300,
    "retention_days": 7
  }'::jsonb;
$$;

COMMENT ON FUNCTION clinicas.default_whatsapp_rate_limit_config() IS 'Default cost-control limits for inbound WhatsApp messages per user and instance.';

CREATE TABLE IF NOT EXISTS clinicas.whatsapp_rate_limit_buckets (
  whatsapp_instance_id uuid NOT NULL REFERENCES clinicas.whatsapp_instances(id) ON DELETE CASCADE,
  tenant_code varchar(64) NOT NULL,
  user_phone_e164 text NOT NULL,
  bucket_start timestamptz NOT NULL,
  message_type text NOT NULL DEFAULT 'unknown',
  request_count integer NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  denied_count integer NOT NULL DEFAULT 0 CHECK (denied_count >= 0),
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (whatsapp_instance_id, user_phone_e164, bucket_start, message_type)
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_rate_limit_buckets_key_time
  ON clinicas.whatsapp_rate_limit_buckets (whatsapp_instance_id, user_phone_e164, bucket_start DESC);

CREATE INDEX IF NOT EXISTS idx_whatsapp_rate_limit_buckets_tenant_time
  ON clinicas.whatsapp_rate_limit_buckets (tenant_code, bucket_start DESC);

CREATE TABLE IF NOT EXISTS clinicas.whatsapp_rate_limit_blocks (
  whatsapp_instance_id uuid NOT NULL REFERENCES clinicas.whatsapp_instances(id) ON DELETE CASCADE,
  tenant_code varchar(64) NOT NULL,
  user_phone_e164 text NOT NULL,
  blocked_until timestamptz NOT NULL,
  reason text NOT NULL,
  last_provider_message_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (whatsapp_instance_id, user_phone_e164)
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_rate_limit_blocks_until
  ON clinicas.whatsapp_rate_limit_blocks (blocked_until DESC);

ALTER TABLE clinicas.whatsapp_rate_limit_buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinicas.whatsapp_rate_limit_blocks ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION clinicas.cleanup_whatsapp_rate_limits(p_retention_days int DEFAULT 7)
RETURNS TABLE (deleted_buckets integer, deleted_blocks integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = clinicas, pg_temp
AS $$
DECLARE
  v_retention_days int;
BEGIN
  v_retention_days := GREATEST(COALESCE(p_retention_days, 7), 1);

  DELETE FROM clinicas.whatsapp_rate_limit_buckets buckets
  WHERE buckets.bucket_start < date_trunc('day', now() - make_interval(days => v_retention_days));
  GET DIAGNOSTICS deleted_buckets = ROW_COUNT;

  DELETE FROM clinicas.whatsapp_rate_limit_blocks blocks
  WHERE blocks.blocked_until < now() - make_interval(days => v_retention_days);
  GET DIAGNOSTICS deleted_blocks = ROW_COUNT;

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION clinicas.cleanup_whatsapp_rate_limits(int) IS 'Removes old WhatsApp rate limit buckets and expired block records.';

CREATE OR REPLACE FUNCTION clinicas.check_whatsapp_rate_limit(
  p_tenant_code text,
  p_user_phone_e164 text,
  p_provider_message_id text DEFAULT NULL,
  p_message_type text DEFAULT 'unknown',
  p_whatsapp_phone_e164 text DEFAULT NULL,
  p_request_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  allowed boolean,
  tenant_code text,
  whatsapp_instance_registry_id uuid,
  whatsapp_instance_provider_id text,
  whatsapp_phone_e164 text,
  user_phone_e164 text,
  reason text,
  retry_after_seconds integer,
  limit_per_minute integer,
  limit_per_hour integer,
  limit_per_day integer,
  limit_media_per_hour integer,
  count_current_minute integer,
  count_current_hour integer,
  count_current_day integer,
  count_media_current_hour integer,
  blocked_until timestamptz,
  config jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = clinicas, public, pg_temp
AS $$
DECLARE
  v_now timestamptz := now();
  v_tenant_code varchar(64);
  v_instance_pk uuid;
  v_instance_provider_id text;
  v_whatsapp_phone text;
  v_user_phone text;
  v_provider_message_id text;
  v_message_type text;
  v_config jsonb;
  v_enabled boolean;
  v_limit_per_minute int;
  v_limit_per_hour int;
  v_limit_per_day int;
  v_limit_media_per_hour int;
  v_cooldown_seconds int;
  v_minute_start timestamptz;
  v_hour_start timestamptz;
  v_day_start timestamptz;
  v_count_minute int := 0;
  v_count_hour int := 0;
  v_count_day int := 0;
  v_count_media_hour int := 0;
  v_allowed boolean := true;
  v_reason text;
  v_retry_after_seconds int := 0;
  v_blocked_until timestamptz;
  v_active_block_reason text;
  v_inserted_rows int := 0;
BEGIN
  v_user_phone := NULLIF(regexp_replace(COALESCE(p_user_phone_e164, ''), '[^0-9+]', '', 'g'), '');
  v_provider_message_id := NULLIF(trim(COALESCE(p_provider_message_id, '')), '');
  v_message_type := COALESCE(NULLIF(lower(trim(p_message_type)), ''), 'unknown');

  SELECT
    p.tenant_code,
    wi.id,
    wi.provider_config->>'instance_id',
    wi.phone_number,
    clinicas.default_whatsapp_rate_limit_config() || COALESCE(wi.config->'rate_limit', '{}'::jsonb)
  INTO
    v_tenant_code,
    v_instance_pk,
    v_instance_provider_id,
    v_whatsapp_phone,
    v_config
  FROM clinicas.professionals p
  JOIN clinicas.whatsapp_instances wi ON wi.professional_id = p.id
  WHERE p.status NOT IN ('suspended', 'archived')
    AND (
      (NULLIF(trim(COALESCE(p_tenant_code, '')), '') IS NOT NULL AND p.tenant_code = p_tenant_code)
      OR (
        NULLIF(trim(COALESCE(p_tenant_code, '')), '') IS NULL
        AND NULLIF(trim(COALESCE(p_whatsapp_phone_e164, '')), '') IS NOT NULL
        AND wi.phone_number = p_whatsapp_phone_e164
      )
    )
  ORDER BY CASE WHEN p.tenant_code = p_tenant_code THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_instance_pk IS NULL THEN
    RETURN QUERY SELECT
      false, NULL::text, NULL::uuid, NULL::text, p_whatsapp_phone_e164::text, v_user_phone,
      'tenant_or_instance_not_found'::text, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
      NULL::timestamptz, clinicas.default_whatsapp_rate_limit_config();
    RETURN;
  END IF;

  IF v_user_phone IS NULL THEN
    RETURN QUERY SELECT
      false, v_tenant_code::text, v_instance_pk, v_instance_provider_id, v_whatsapp_phone, NULL::text,
      'invalid_user_phone'::text, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
      NULL::timestamptz, v_config;
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_instance_pk::text), hashtext(v_user_phone));

  IF v_provider_message_id IS NOT NULL THEN
    INSERT INTO clinicas.message_dedupe (tenant_code, provider_message_id, received_at)
    VALUES (v_tenant_code, v_provider_message_id, v_now)
    ON CONFLICT ON CONSTRAINT message_dedupe_pkey DO NOTHING;
    GET DIAGNOSTICS v_inserted_rows = ROW_COUNT;

    IF v_inserted_rows = 0 THEN
      RETURN QUERY SELECT
        false, v_tenant_code::text, v_instance_pk, v_instance_provider_id, v_whatsapp_phone, v_user_phone,
        'duplicate_provider_message'::text, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
        NULL::timestamptz, v_config;
      RETURN;
    END IF;
  END IF;

  v_enabled := COALESCE(lower(v_config->>'enabled') NOT IN ('false', '0', 'off', 'no'), true);

  IF NOT v_enabled THEN
    RETURN QUERY SELECT
      true, v_tenant_code::text, v_instance_pk, v_instance_provider_id, v_whatsapp_phone, v_user_phone,
      NULL::text, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
      NULL::timestamptz, v_config;
    RETURN;
  END IF;

  v_limit_per_minute := GREATEST(CASE WHEN COALESCE(v_config->>'per_minute', '') ~ '^\d+$' THEN (v_config->>'per_minute')::int ELSE 12 END, 1);
  v_limit_per_hour := GREATEST(CASE WHEN COALESCE(v_config->>'per_hour', '') ~ '^\d+$' THEN (v_config->>'per_hour')::int ELSE 60 END, 1);
  v_limit_per_day := GREATEST(CASE WHEN COALESCE(v_config->>'per_day', '') ~ '^\d+$' THEN (v_config->>'per_day')::int ELSE 200 END, 1);
  v_limit_media_per_hour := GREATEST(CASE WHEN COALESCE(v_config->>'media_per_hour', '') ~ '^\d+$' THEN (v_config->>'media_per_hour')::int ELSE 10 END, 0);
  v_cooldown_seconds := GREATEST(
    CASE
      WHEN COALESCE(v_config->>'cooldown_seconds', '') ~ '^\d+$' THEN (v_config->>'cooldown_seconds')::int
      WHEN COALESCE(v_config->>'cooldown_minutes', '') ~ '^\d+$' THEN ((v_config->>'cooldown_minutes')::int * 60)
      ELSE 300
    END,
    1
  );

  v_minute_start := date_trunc('minute', v_now);
  v_hour_start := date_trunc('hour', v_now);
  v_day_start := date_trunc('day', v_now);

  INSERT INTO clinicas.whatsapp_rate_limit_buckets AS target_buckets (
    whatsapp_instance_id,
    tenant_code,
    user_phone_e164,
    bucket_start,
    message_type,
    request_count,
    first_seen_at,
    last_seen_at
  ) VALUES (
    v_instance_pk,
    v_tenant_code,
    v_user_phone,
    v_minute_start,
    v_message_type,
    1,
    v_now,
    v_now
  )
  ON CONFLICT ON CONSTRAINT whatsapp_rate_limit_buckets_pkey
  DO UPDATE SET
    tenant_code = EXCLUDED.tenant_code,
    request_count = target_buckets.request_count + 1,
    last_seen_at = EXCLUDED.last_seen_at;

  SELECT
    COALESCE(SUM(buckets.request_count) FILTER (WHERE buckets.bucket_start >= v_minute_start), 0)::int,
    COALESCE(SUM(buckets.request_count) FILTER (WHERE buckets.bucket_start >= v_hour_start), 0)::int,
    COALESCE(SUM(buckets.request_count) FILTER (WHERE buckets.bucket_start >= v_day_start), 0)::int,
    COALESCE(SUM(buckets.request_count) FILTER (
      WHERE buckets.bucket_start >= v_hour_start
        AND buckets.message_type IN ('audio', 'image', 'video', 'document', 'sticker')
    ), 0)::int
  INTO v_count_minute, v_count_hour, v_count_day, v_count_media_hour
  FROM clinicas.whatsapp_rate_limit_buckets buckets
  WHERE buckets.whatsapp_instance_id = v_instance_pk
    AND buckets.user_phone_e164 = v_user_phone
    AND buckets.bucket_start >= v_day_start;

  SELECT blocks.blocked_until, blocks.reason
  INTO v_blocked_until, v_active_block_reason
  FROM clinicas.whatsapp_rate_limit_blocks blocks
  WHERE blocks.whatsapp_instance_id = v_instance_pk
    AND blocks.user_phone_e164 = v_user_phone
    AND blocks.blocked_until > v_now;

  IF v_blocked_until IS NOT NULL THEN
    v_allowed := false;
    v_reason := COALESCE(v_active_block_reason, 'rate_limited');
    v_retry_after_seconds := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_blocked_until - v_now)))::int);
  ELSIF v_count_minute > v_limit_per_minute THEN
    v_allowed := false;
    v_reason := 'per_minute_exceeded';
    v_retry_after_seconds := GREATEST(
      v_cooldown_seconds,
      CEIL(EXTRACT(EPOCH FROM ((v_minute_start + interval '1 minute') - v_now)))::int
    );
    v_blocked_until := v_now + make_interval(secs => v_retry_after_seconds);
  ELSIF v_count_hour > v_limit_per_hour THEN
    v_allowed := false;
    v_reason := 'per_hour_exceeded';
    v_retry_after_seconds := GREATEST(
      v_cooldown_seconds,
      CEIL(EXTRACT(EPOCH FROM ((v_hour_start + interval '1 hour') - v_now)))::int
    );
    v_blocked_until := v_now + make_interval(secs => v_retry_after_seconds);
  ELSIF v_count_day > v_limit_per_day THEN
    v_allowed := false;
    v_reason := 'per_day_exceeded';
    v_retry_after_seconds := GREATEST(
      v_cooldown_seconds,
      CEIL(EXTRACT(EPOCH FROM ((v_day_start + interval '1 day') - v_now)))::int
    );
    v_blocked_until := v_now + make_interval(secs => v_retry_after_seconds);
  ELSIF v_message_type IN ('audio', 'image', 'video', 'document', 'sticker')
    AND v_count_media_hour > v_limit_media_per_hour THEN
    v_allowed := false;
    v_reason := 'media_per_hour_exceeded';
    v_retry_after_seconds := GREATEST(
      v_cooldown_seconds,
      CEIL(EXTRACT(EPOCH FROM ((v_hour_start + interval '1 hour') - v_now)))::int
    );
    v_blocked_until := v_now + make_interval(secs => v_retry_after_seconds);
  ELSE
    DELETE FROM clinicas.whatsapp_rate_limit_blocks blocks
    WHERE blocks.whatsapp_instance_id = v_instance_pk
      AND blocks.user_phone_e164 = v_user_phone
      AND blocks.blocked_until <= v_now;
  END IF;

  IF NOT v_allowed THEN
    UPDATE clinicas.whatsapp_rate_limit_buckets buckets
    SET denied_count = buckets.denied_count + 1,
        last_seen_at = v_now
    WHERE buckets.whatsapp_instance_id = v_instance_pk
      AND buckets.user_phone_e164 = v_user_phone
      AND buckets.bucket_start = v_minute_start
      AND buckets.message_type = v_message_type;

    INSERT INTO clinicas.whatsapp_rate_limit_blocks AS target_blocks (
      whatsapp_instance_id,
      tenant_code,
      user_phone_e164,
      blocked_until,
      reason,
      last_provider_message_id,
      metadata,
      created_at,
      updated_at
    ) VALUES (
      v_instance_pk,
      v_tenant_code,
      v_user_phone,
      v_blocked_until,
      v_reason,
      v_provider_message_id,
      COALESCE(p_request_metadata, '{}'::jsonb),
      v_now,
      v_now
    )
    ON CONFLICT ON CONSTRAINT whatsapp_rate_limit_blocks_pkey
    DO UPDATE SET
      tenant_code = EXCLUDED.tenant_code,
      blocked_until = GREATEST(target_blocks.blocked_until, EXCLUDED.blocked_until),
      reason = EXCLUDED.reason,
      last_provider_message_id = EXCLUDED.last_provider_message_id,
      metadata = EXCLUDED.metadata,
      updated_at = EXCLUDED.updated_at;
  END IF;

  RETURN QUERY SELECT
    v_allowed,
    v_tenant_code::text,
    v_instance_pk,
    v_instance_provider_id,
    v_whatsapp_phone,
    v_user_phone,
    v_reason,
    v_retry_after_seconds,
    v_limit_per_minute,
    v_limit_per_hour,
    v_limit_per_day,
    v_limit_media_per_hour,
    v_count_minute,
    v_count_hour,
    v_count_day,
    v_count_media_hour,
    CASE WHEN v_allowed THEN NULL::timestamptz ELSE v_blocked_until END,
    v_config;
END;
$$;

COMMENT ON FUNCTION clinicas.check_whatsapp_rate_limit(text, text, text, text, text, jsonb) IS 'Consumes one inbound WhatsApp quota unit and returns whether the message may continue to costly processing.';

CREATE OR REPLACE VIEW clinicas.whatsapp_rate_limit_active_blocks AS
SELECT
  b.tenant_code,
  p.full_name,
  wi.provider,
  wi.provider_config->>'instance_id' AS whatsapp_instance_id,
  wi.phone_number AS whatsapp_phone_e164,
  b.user_phone_e164,
  b.blocked_until,
  b.reason,
  b.last_provider_message_id,
  b.updated_at,
  b.metadata
FROM clinicas.whatsapp_rate_limit_blocks b
JOIN clinicas.whatsapp_instances wi ON wi.id = b.whatsapp_instance_id
JOIN clinicas.professionals p ON p.id = wi.professional_id
WHERE b.blocked_until > now();

COMMENT ON VIEW clinicas.whatsapp_rate_limit_active_blocks IS 'Operational view of users currently blocked by WhatsApp rate limits.';