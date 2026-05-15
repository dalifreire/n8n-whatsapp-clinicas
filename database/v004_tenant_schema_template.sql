-- ============================================================
-- v004_tenant_schema_template.sql
-- Função ensure_tenant_schema_objects: cria todas as tabelas,
-- índices, triggers e funções dentro do schema do profissional.
-- Chamada por provision_professional_schema e register_existing_tenant.
-- Depende de: v003_platform_functions.sql
-- ============================================================

CREATE OR REPLACE FUNCTION clinicas.ensure_tenant_schema_objects(p_schema_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = clinicas, public, extensions, pg_temp
AS $$
DECLARE
  tbl text;
BEGIN
  PERFORM clinicas.assert_valid_tenant_identifiers('aaa', p_schema_name);

  EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.atualizar_atualizado_em()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      NEW.atualizado_em = CURRENT_TIMESTAMP;
      RETURN NEW;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS %I.usuarios (
      id bigserial PRIMARY KEY,
      telefone varchar(20) UNIQUE NOT NULL,
      nome varchar(255),
      email varchar(255),
      primeira_interacao timestamptz DEFAULT now(),
      ultima_interacao timestamptz DEFAULT now(),
      total_interacoes int DEFAULT 1,
      metadados jsonb,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS %I.conversas (
      id bigserial PRIMARY KEY,
      telefone varchar(20) NOT NULL,
      nome varchar(255),
      mensagem text NOT NULL,
      resposta_ia text NOT NULL,
      contexto_rag jsonb,
      data_hora timestamptz DEFAULT now(),
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS %I.n8n_chat_histories (
      id bigserial PRIMARY KEY,
      session_id text NOT NULL,
      message jsonb NOT NULL
    );

    CREATE TABLE IF NOT EXISTS %I.avaliacoes (
      id bigserial PRIMARY KEY,
      id_conversa bigint REFERENCES %I.conversas(id) ON DELETE CASCADE,
      nota int CHECK (nota >= 1 AND nota <= 5),
      comentario text,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS %I.escalacoes (
      id bigserial PRIMARY KEY,
      id_conversa bigint REFERENCES %I.conversas(id) ON DELETE CASCADE,
      telefone varchar(20) NOT NULL,
      motivo text,
      status varchar(50) DEFAULT 'pendente',
      atribuido_a varchar(255),
      resolvido_em timestamptz,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS %I.metricas (
      id bigserial PRIMARY KEY,
      data_metrica date DEFAULT CURRENT_DATE,
      total_mensagens int DEFAULT 0,
      respostas_sucesso int DEFAULT 0,
      respostas_falha int DEFAULT 0,
      tempo_resposta_medio float,
      usuarios_unicos int DEFAULT 0,
      satisfacao_media float,
      metadados jsonb,
      criado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.documentos (
      id bigserial PRIMARY KEY,
      titulo varchar(500),
      text text NOT NULL,
      categoria varchar(255),
      metadata jsonb,
      embedding vector(1536),
      fonte varchar(255),
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.dentistas (
      id bigserial PRIMARY KEY,
      nome varchar(255) NOT NULL,
      cro varchar(20) UNIQUE NOT NULL,
      especialidade varchar(255),
      especialidades text[],
      telefone varchar(20),
      email varchar(255),
      ativo boolean DEFAULT true,
      dias_trabalho int[] DEFAULT '{1,2,3,4,5}',
      inicio_jornada time DEFAULT '08:00',
      fim_jornada time DEFAULT '18:00',
      inicio_almoco time DEFAULT '12:00',
      fim_almoco time DEFAULT '13:00',
      duracao_consulta_minutos int DEFAULT 30,
      metadados jsonb DEFAULT '{}'::jsonb,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.pacientes (
      id bigserial PRIMARY KEY,
      nome varchar(255) NOT NULL,
      cpf varchar(14) UNIQUE,
      data_nascimento date,
      telefone varchar(20) NOT NULL,
      telefone_secundario varchar(20),
      email varchar(255),
      endereco text,
      contato_emergencia_nome varchar(255),
      contato_emergencia_telefone varchar(20),
      alergias text[],
      condicoes_medicas text[],
      medicamentos text[],
      tipo_sanguineo varchar(5),
      convenio varchar(255),
      numero_convenio varchar(50),
      observacoes text,
      ativo boolean DEFAULT true,
      cadastrado_via varchar(50) DEFAULT 'whatsapp',
      usuario_id bigint REFERENCES %I.usuarios(id),
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.procedimentos (
      id bigserial PRIMARY KEY,
      codigo varchar(20) UNIQUE,
      nome varchar(255) NOT NULL,
      descricao text,
      categoria varchar(100),
      duracao_media_min int DEFAULT 30,
      preco_base decimal(10,2),
      requer_anestesia boolean DEFAULT false,
      instrucoes_pos_op text,
      ativo boolean DEFAULT true,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.agendamentos (
      id bigserial PRIMARY KEY,
      id_paciente bigint REFERENCES %I.pacientes(id),
      id_dentista bigint REFERENCES %I.dentistas(id),
      id_procedimento bigint REFERENCES %I.procedimentos(id),
      data_consulta date NOT NULL,
      hora_consulta time NOT NULL,
      hora_fim time,
      duracao_min int DEFAULT 30,
      status varchar(30) DEFAULT 'agendado',
      motivo_status text,
      observacoes text,
      lembrete_enviado boolean DEFAULT false,
      confirmado_em timestamptz,
      cancelado_em timestamptz,
      agendado_via varchar(50) DEFAULT 'whatsapp',
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.planos_tratamento (
      id bigserial PRIMARY KEY,
      id_paciente bigint NOT NULL REFERENCES %I.pacientes(id),
      id_dentista bigint NOT NULL REFERENCES %I.dentistas(id),
      titulo varchar(255) NOT NULL,
      descricao text,
      status varchar(30) DEFAULT 'proposto',
      total_estimado decimal(10,2),
      total_sessoes int,
      sessoes_concluidas int DEFAULT 0,
      aprovado_em timestamptz,
      iniciado_em timestamptz,
      concluido_em timestamptz,
      observacoes text,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.itens_tratamento (
      id bigserial PRIMARY KEY,
      id_plano_tratamento bigint NOT NULL REFERENCES %I.planos_tratamento(id) ON DELETE CASCADE,
      id_procedimento bigint REFERENCES %I.procedimentos(id),
      numero_dente varchar(10),
      descricao text,
      status varchar(30) DEFAULT 'pendente',
      preco decimal(10,2),
      id_agendamento bigint REFERENCES %I.agendamentos(id),
      concluido_em timestamptz,
      observacoes text,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.registros_financeiros (
      id bigserial PRIMARY KEY,
      id_paciente bigint NOT NULL REFERENCES %I.pacientes(id),
      id_plano_tratamento bigint REFERENCES %I.planos_tratamento(id),
      id_agendamento bigint REFERENCES %I.agendamentos(id),
      tipo varchar(20) NOT NULL,
      valor decimal(10,2) NOT NULL,
      forma_pagamento varchar(50),
      parcelas int DEFAULT 1,
      descricao text,
      data_vencimento date,
      pago_em timestamptz,
      status varchar(20) DEFAULT 'pendente',
      numero_recibo varchar(50),
      observacoes text,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.lembretes (
      id bigserial PRIMARY KEY,
      id_paciente bigint NOT NULL REFERENCES %I.pacientes(id),
      id_agendamento bigint REFERENCES %I.agendamentos(id),
      tipo varchar(50) NOT NULL,
      agendado_para timestamptz NOT NULL,
      canal varchar(20) DEFAULT 'whatsapp',
      mensagem text,
      status varchar(20) DEFAULT 'pendente',
      enviado_em timestamptz,
      tentativas int DEFAULT 0,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.prontuarios (
      id bigserial PRIMARY KEY,
      id_paciente bigint NOT NULL REFERENCES %I.pacientes(id),
      id_dentista bigint NOT NULL REFERENCES %I.dentistas(id),
      id_agendamento bigint REFERENCES %I.agendamentos(id),
      data_registro date DEFAULT CURRENT_DATE,
      queixa_principal text,
      exame_clinico text,
      diagnostico text,
      procedimento_realizado text,
      numero_dente varchar(10),
      materiais_utilizados text,
      prescricoes_texto text,
      observacoes text,
      proximos_passos text,
      anexos jsonb DEFAULT '[]'::jsonb,
      criado_em timestamptz DEFAULT now(),
      atualizado_em timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS %I.prescricoes (
      id bigserial PRIMARY KEY,
      id_paciente bigint NOT NULL REFERENCES %I.pacientes(id),
      id_dentista bigint NOT NULL REFERENCES %I.dentistas(id),
      id_prontuario bigint REFERENCES %I.prontuarios(id),
      data_prescricao date DEFAULT CURRENT_DATE,
      medicamentos jsonb NOT NULL,
      instrucoes text,
      valido_ate date,
      criado_em timestamptz DEFAULT now()
    );
  $ddl$,
    p_schema_name,
    p_schema_name,
    p_schema_name,
    p_schema_name, p_schema_name,
    p_schema_name, p_schema_name,
    p_schema_name,
    p_schema_name,
    p_schema_name,
    p_schema_name, p_schema_name,
    p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name
  );

  EXECUTE format($ddl$
    CREATE INDEX IF NOT EXISTS idx_usuarios_telefone ON %I.usuarios(telefone);
    CREATE INDEX IF NOT EXISTS idx_usuarios_email ON %I.usuarios(email);
    CREATE INDEX IF NOT EXISTS idx_usuarios_ultima_interacao ON %I.usuarios(ultima_interacao DESC);
    CREATE INDEX IF NOT EXISTS idx_conversas_telefone ON %I.conversas(telefone);
    CREATE INDEX IF NOT EXISTS idx_conversas_data_hora ON %I.conversas(data_hora DESC);
    CREATE INDEX IF NOT EXISTS idx_n8n_chat_histories_session_id ON %I.n8n_chat_histories(session_id);
    CREATE INDEX IF NOT EXISTS idx_avaliacoes_conversa ON %I.avaliacoes(id_conversa);
    CREATE INDEX IF NOT EXISTS idx_escalacoes_status ON %I.escalacoes(status);
    CREATE INDEX IF NOT EXISTS idx_metricas_data ON %I.metricas(data_metrica DESC);
    CREATE INDEX IF NOT EXISTS idx_documentos_embedding ON %I.documentos USING ivfflat (embedding vector_cosine_ops);
    CREATE INDEX IF NOT EXISTS idx_documentos_categoria ON %I.documentos(categoria);
    CREATE INDEX IF NOT EXISTS idx_dentistas_cro ON %I.dentistas(cro);
    CREATE INDEX IF NOT EXISTS idx_dentistas_especialidade ON %I.dentistas(especialidade);
    CREATE INDEX IF NOT EXISTS idx_dentistas_ativo ON %I.dentistas(ativo) WHERE ativo = true;
    CREATE INDEX IF NOT EXISTS idx_pacientes_cpf ON %I.pacientes(cpf);
    CREATE INDEX IF NOT EXISTS idx_pacientes_telefone ON %I.pacientes(telefone);
    CREATE INDEX IF NOT EXISTS idx_pacientes_nome ON %I.pacientes(nome);
    CREATE INDEX IF NOT EXISTS idx_pacientes_ativo ON %I.pacientes(ativo) WHERE ativo = true;
    CREATE INDEX IF NOT EXISTS idx_procedimentos_codigo ON %I.procedimentos(codigo);
    CREATE INDEX IF NOT EXISTS idx_procedimentos_categoria ON %I.procedimentos(categoria);
    CREATE INDEX IF NOT EXISTS idx_agendamentos_paciente ON %I.agendamentos(id_paciente);
    CREATE INDEX IF NOT EXISTS idx_agendamentos_dentista ON %I.agendamentos(id_dentista);
    CREATE INDEX IF NOT EXISTS idx_agendamentos_data ON %I.agendamentos(data_consulta);
    CREATE INDEX IF NOT EXISTS idx_agendamentos_status ON %I.agendamentos(status);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_agendamentos_sem_conflito ON %I.agendamentos(id_dentista, data_consulta, hora_consulta) WHERE status NOT IN ('cancelado', 'faltou');
    CREATE INDEX IF NOT EXISTS idx_planos_tratamento_paciente ON %I.planos_tratamento(id_paciente);
    CREATE INDEX IF NOT EXISTS idx_itens_tratamento_plano ON %I.itens_tratamento(id_plano_tratamento);
    CREATE INDEX IF NOT EXISTS idx_registros_financeiros_paciente ON %I.registros_financeiros(id_paciente);
    CREATE INDEX IF NOT EXISTS idx_registros_financeiros_status ON %I.registros_financeiros(status);
    CREATE INDEX IF NOT EXISTS idx_lembretes_agendado ON %I.lembretes(agendado_para) WHERE status = 'pendente';
    CREATE INDEX IF NOT EXISTS idx_lembretes_paciente ON %I.lembretes(id_paciente);
    CREATE INDEX IF NOT EXISTS idx_prontuarios_paciente ON %I.prontuarios(id_paciente);
    CREATE INDEX IF NOT EXISTS idx_prescricoes_paciente ON %I.prescricoes(id_paciente);
  $ddl$,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name,
    p_schema_name, p_schema_name, p_schema_name
  );

  FOR tbl IN
    SELECT unnest(ARRAY[
      'usuarios', 'conversas', 'avaliacoes', 'escalacoes', 'documentos',
      'dentistas', 'pacientes', 'procedimentos', 'agendamentos',
      'planos_tratamento', 'itens_tratamento', 'registros_financeiros',
      'lembretes', 'prontuarios'
    ])
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS atualizar_atualizado_em ON %I.%I; CREATE TRIGGER atualizar_atualizado_em BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION %I.atualizar_atualizado_em();',
      p_schema_name, tbl, p_schema_name, tbl, p_schema_name
    );
  END LOOP;

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.atualizar_stats_usuario()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      INSERT INTO usuarios (telefone, nome, primeira_interacao, ultima_interacao, total_interacoes)
      VALUES (NEW.telefone, NEW.nome, now(), now(), 1)
      ON CONFLICT (telefone) DO UPDATE SET
        ultima_interacao = now(),
        total_interacoes = usuarios.total_interacoes + 1,
        nome = COALESCE(EXCLUDED.nome, usuarios.nome);
      RETURN NEW;
    END;
    $fn$;

    DROP TRIGGER IF EXISTS atualizar_stats_na_conversa ON %I.conversas;
    CREATE TRIGGER atualizar_stats_na_conversa
      AFTER INSERT ON %I.conversas
      FOR EACH ROW
      EXECUTE FUNCTION %I.atualizar_stats_usuario();
  $ddl$, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I._stable_uuid(p_value text)
    RETURNS uuid
    LANGUAGE sql
    IMMUTABLE
    SET search_path = %I, pg_temp
    AS $fn$
      SELECT concat(
        substr(md5(COALESCE(p_value, '')), 1, 8), '-',
        substr(md5(COALESCE(p_value, '')), 9, 4), '-',
        substr(md5(COALESCE(p_value, '')), 13, 4), '-',
        substr(md5(COALESCE(p_value, '')), 17, 4), '-',
        substr(md5(COALESCE(p_value, '')), 21, 12)
      )::uuid;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.buscar_documentos_similares(
      query_embedding vector,
      match_threshold float DEFAULT 0.1,
      match_count int DEFAULT 3
    )
    RETURNS TABLE (
      id bigint,
      titulo varchar,
      text text,
      categoria varchar,
      metadata jsonb,
      similaridade float
    )
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = %I, public, extensions, pg_temp
    AS $fn$
    BEGIN
      RETURN QUERY
      SELECT
        d.id,
        d.titulo,
        d.text,
        d.categoria,
        d.metadata,
        (1 - (d.embedding <=> query_embedding))::float AS similaridade
      FROM documentos d
      WHERE d.embedding IS NOT NULL
        AND (1 - (d.embedding <=> query_embedding)) > match_threshold
      ORDER BY d.embedding <=> query_embedding
      LIMIT match_count;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.fetch_due_reminders(p_window_minutes int DEFAULT 30)
    RETURNS TABLE (
      reminder_id uuid,
      patient_id uuid,
      patient_phone_e164 text,
      patient_name text,
      appointment_id uuid,
      scheduled_at timestamptz,
      reminder_type text,
      payload jsonb
    )
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      RETURN QUERY
      SELECT
        _stable_uuid(r.id::text) AS reminder_id,
        _stable_uuid(p.id::text) AS patient_id,
        p.telefone::text AS patient_phone_e164,
        p.nome::text AS patient_name,
        CASE WHEN r.id_agendamento IS NULL THEN NULL ELSE _stable_uuid(r.id_agendamento::text) END AS appointment_id,
        r.agendado_para AS scheduled_at,
        r.tipo::text AS reminder_type,
        jsonb_build_object(
          'mensagem', r.mensagem,
          'canal', r.canal,
          'tentativas', r.tentativas,
          'data_consulta', a.data_consulta,
          'hora_consulta', a.hora_consulta
        ) AS payload
      FROM lembretes r
      JOIN pacientes p ON p.id = r.id_paciente
      LEFT JOIN agendamentos a ON a.id = r.id_agendamento
      WHERE r.status = 'pendente'
        AND r.agendado_para <= now() + make_interval(mins => p_window_minutes)
      ORDER BY r.agendado_para;
    END;
    $fn$;

    CREATE OR REPLACE FUNCTION %I.mark_reminder_sent(
      p_reminder_id uuid,
      p_status text DEFAULT 'enviado',
      p_provider_message_id text DEFAULT NULL
    )
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      UPDATE lembretes
      SET status = COALESCE(p_status, 'enviado'),
          enviado_em = CASE WHEN COALESCE(p_status, 'enviado') IN ('enviado', 'sent') THEN now() ELSE enviado_em END,
          tentativas = COALESCE(tentativas, 0) + 1,
          atualizado_em = now()
      WHERE _stable_uuid(id::text) = p_reminder_id;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.reiniciar_conversa(p_session_id text)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      DELETE FROM n8n_chat_histories WHERE session_id = p_session_id;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.obter_slots_disponiveis(
      p_id_dentista bigint,
      p_data date,
      p_duracao_min int DEFAULT 30
    )
    RETURNS TABLE (slot_inicio time, slot_fim time)
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = %I, public, extensions, pg_temp
    AS $fn$
    DECLARE
      v_inicio_jornada time;
      v_fim_jornada time;
      v_inicio_almoco time;
      v_fim_almoco time;
      v_slot_atual time;
      v_dias_trabalho int[];
      v_dia_semana int;
    BEGIN
      SELECT inicio_jornada, fim_jornada, inicio_almoco, fim_almoco, dias_trabalho
      INTO v_inicio_jornada, v_fim_jornada, v_inicio_almoco, v_fim_almoco, v_dias_trabalho
      FROM dentistas
      WHERE id = p_id_dentista AND ativo = true;

      IF NOT FOUND THEN
        RETURN;
      END IF;

      v_dia_semana := EXTRACT(DOW FROM p_data)::int;
      IF NOT (v_dia_semana = ANY(v_dias_trabalho)) THEN
        RETURN;
      END IF;

      v_slot_atual := v_inicio_jornada;
      WHILE v_slot_atual + make_interval(mins => p_duracao_min) <= v_fim_jornada LOOP
        IF v_slot_atual >= v_inicio_almoco AND v_slot_atual < v_fim_almoco THEN
          v_slot_atual := v_fim_almoco;
          CONTINUE;
        END IF;

        IF v_slot_atual < v_inicio_almoco AND v_slot_atual + make_interval(mins => p_duracao_min) > v_inicio_almoco THEN
          v_slot_atual := v_fim_almoco;
          CONTINUE;
        END IF;

        IF NOT EXISTS (
          SELECT 1 FROM agendamentos a
          WHERE a.id_dentista = p_id_dentista
            AND a.data_consulta = p_data
            AND a.status NOT IN ('cancelado', 'faltou')
            AND (
              (a.hora_consulta <= v_slot_atual AND a.hora_consulta + make_interval(mins => a.duracao_min) > v_slot_atual)
              OR
              (v_slot_atual <= a.hora_consulta AND v_slot_atual + make_interval(mins => p_duracao_min) > a.hora_consulta)
            )
        ) THEN
          slot_inicio := v_slot_atual;
          slot_fim := v_slot_atual + make_interval(mins => p_duracao_min);
          RETURN NEXT;
        END IF;

        v_slot_atual := v_slot_atual + make_interval(mins => p_duracao_min);
      END LOOP;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.obter_agendamentos_paciente(
      p_telefone varchar,
      p_status varchar DEFAULT NULL,
      p_limite int DEFAULT 5
    )
    RETURNS TABLE (
      id_agendamento bigint,
      data_consulta date,
      hora_consulta time,
      duracao_min int,
      status varchar,
      nome_dentista varchar,
      especialidade_dentista varchar,
      nome_procedimento varchar,
      observacoes text
    )
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      RETURN QUERY
      SELECT a.id, a.data_consulta, a.hora_consulta, a.duracao_min, a.status,
             d.nome, d.especialidade, pr.nome, a.observacoes
      FROM agendamentos a
      JOIN pacientes p ON a.id_paciente = p.id
      JOIN dentistas d ON a.id_dentista = d.id
      LEFT JOIN procedimentos pr ON a.id_procedimento = pr.id
      WHERE p.telefone = p_telefone
        AND (p_status IS NULL OR a.status = p_status)
        AND a.data_consulta >= CURRENT_DATE
      ORDER BY a.data_consulta, a.hora_consulta
      LIMIT p_limite;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.obter_resumo_financeiro_paciente(p_telefone varchar)
    RETURNS TABLE (
      total_cobrado decimal,
      total_pago decimal,
      total_pendente decimal,
      total_atrasado decimal,
      proximos_vencimentos jsonb
    )
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      RETURN QUERY
      WITH paciente AS (
        SELECT id FROM pacientes WHERE telefone = p_telefone LIMIT 1
      ),
      resumo AS (
        SELECT
          COALESCE(SUM(CASE WHEN f.tipo = 'cobranca' THEN f.valor ELSE 0 END), 0) AS cobrado,
          COALESCE(SUM(CASE WHEN f.tipo = 'pagamento' THEN f.valor ELSE 0 END), 0) AS pago,
          COALESCE(SUM(CASE WHEN f.tipo = 'cobranca' AND f.status = 'pendente' THEN f.valor ELSE 0 END), 0) AS pendente,
          COALESCE(SUM(CASE WHEN f.tipo = 'cobranca' AND f.status = 'atrasado' THEN f.valor ELSE 0 END), 0) AS atrasado
        FROM registros_financeiros f
        JOIN paciente p ON f.id_paciente = p.id
      ),
      proximos AS (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('valor', f.valor, 'vencimento', f.data_vencimento, 'descricao', f.descricao) ORDER BY f.data_vencimento), '[]'::jsonb) AS itens
        FROM registros_financeiros f
        JOIN paciente p ON f.id_paciente = p.id
        WHERE f.status = 'pendente'
          AND f.tipo = 'cobranca'
          AND f.data_vencimento >= CURRENT_DATE
      )
      SELECT r.cobrado, r.pago, r.pendente, r.atrasado, p.itens
      FROM resumo r, proximos p;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.buscar_paciente_por_telefone(p_telefone varchar)
    RETURNS TABLE (
      id_paciente bigint,
      nome varchar,
      telefone varchar,
      data_nascimento date,
      alergias text[],
      condicoes_medicas text[],
      convenio varchar,
      ultima_consulta date,
      total_agendamentos bigint,
      tratamentos_ativos bigint
    )
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    BEGIN
      RETURN QUERY
      SELECT p.id, p.nome, p.telefone, p.data_nascimento, p.alergias,
             p.condicoes_medicas, p.convenio, MAX(a.data_consulta),
             COUNT(DISTINCT a.id),
             COUNT(DISTINCT tp.id) FILTER (WHERE tp.status IN ('aprovado', 'em_andamento'))
      FROM pacientes p
      LEFT JOIN agendamentos a ON p.id = a.id_paciente
      LEFT JOIN planos_tratamento tp ON p.id = tp.id_paciente
      WHERE p.telefone = p_telefone AND p.ativo = true
      GROUP BY p.id, p.nome, p.telefone, p.data_nascimento, p.alergias, p.condicoes_medicas, p.convenio;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.listar_especialidades_disponiveis()
    RETURNS TABLE (especialidade varchar, dentistas_disponiveis bigint, nomes_dentistas text)
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = %I, public, extensions, pg_temp
    AS $fn$
    BEGIN
      RETURN QUERY
      SELECT sub.esp, COUNT(DISTINCT sub.dentista_id), STRING_AGG(DISTINCT sub.dentista_nome, ', ' ORDER BY sub.dentista_nome)
      FROM (
        SELECT UNNEST(CASE WHEN d.especialidades IS NOT NULL AND array_length(d.especialidades, 1) > 0 THEN d.especialidades ELSE ARRAY[d.especialidade] END)::varchar AS esp,
               d.id AS dentista_id,
               d.nome AS dentista_nome
        FROM dentistas d
        WHERE d.ativo = true
      ) sub
      GROUP BY sub.esp
      ORDER BY sub.esp;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.criar_agendamento_whatsapp(
      p_telefone_paciente varchar,
      p_nome_paciente varchar,
      p_id_dentista bigint,
      p_id_procedimento bigint,
      p_data date,
      p_horario time,
      p_observacoes text DEFAULT NULL
    )
    RETURNS TABLE (sucesso boolean, mensagem text, id_agendamento bigint)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    DECLARE
      v_id_paciente bigint;
      v_duracao int;
      v_id_agendamento bigint;
    BEGIN
      SELECT id INTO v_id_paciente FROM pacientes WHERE telefone = p_telefone_paciente;

      IF v_id_paciente IS NULL THEN
        INSERT INTO pacientes (nome, telefone, cadastrado_via)
        VALUES (p_nome_paciente, p_telefone_paciente, 'whatsapp')
        RETURNING id INTO v_id_paciente;
      END IF;

      SELECT duracao_media_min INTO v_duracao FROM procedimentos WHERE id = p_id_procedimento;
      v_duracao := COALESCE(v_duracao, 30);

      IF EXISTS (
        SELECT 1 FROM agendamentos a
        WHERE a.id_dentista = p_id_dentista
          AND a.data_consulta = p_data
          AND a.status NOT IN ('cancelado', 'faltou')
          AND (
            (a.hora_consulta <= p_horario AND a.hora_consulta + make_interval(mins => a.duracao_min) > p_horario)
            OR
            (p_horario <= a.hora_consulta AND p_horario + make_interval(mins => v_duracao) > a.hora_consulta)
          )
      ) THEN
        sucesso := false;
        mensagem := 'Horário indisponível. Por favor, escolha outro horário.';
        id_agendamento := NULL;
        RETURN NEXT;
        RETURN;
      END IF;

      INSERT INTO agendamentos (id_paciente, id_dentista, id_procedimento, data_consulta, hora_consulta, hora_fim, duracao_min, observacoes, agendado_via)
      VALUES (v_id_paciente, p_id_dentista, p_id_procedimento, p_data, p_horario, p_horario + make_interval(mins => v_duracao), v_duracao, p_observacoes, 'whatsapp')
      RETURNING id INTO v_id_agendamento;

      INSERT INTO lembretes (id_paciente, id_agendamento, tipo, agendado_para, mensagem)
      VALUES (
        v_id_paciente,
        v_id_agendamento,
        'consulta_24h',
        (p_data::timestamp + p_horario - interval '1 day'),
        concat('Olá ', p_nome_paciente, '! Lembramos que você tem consulta amanhã às ', p_horario::text, '. Confirme sua presença respondendo SIM.')
      );

      sucesso := true;
      mensagem := concat('Consulta agendada com sucesso para ', to_char(p_data, 'DD/MM/YYYY'), ' às ', p_horario::text, '!');
      id_agendamento := v_id_agendamento;
      RETURN NEXT;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %I.cancelar_agendamento(
      p_id_agendamento bigint,
      p_telefone_paciente varchar,
      p_motivo text DEFAULT NULL
    )
    RETURNS TABLE (sucesso boolean, mensagem text)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = %I, pg_temp
    AS $fn$
    DECLARE
      v_agend record;
    BEGIN
      SELECT a.*, p.telefone INTO v_agend
      FROM agendamentos a
      JOIN pacientes p ON a.id_paciente = p.id
      WHERE a.id = p_id_agendamento AND p.telefone = p_telefone_paciente;

      IF NOT FOUND THEN
        sucesso := false;
        mensagem := 'Agendamento não encontrado.';
        RETURN NEXT;
        RETURN;
      END IF;

      IF v_agend.status IN ('cancelado', 'concluido') THEN
        sucesso := false;
        mensagem := concat('Este agendamento já está ', v_agend.status, '.');
        RETURN NEXT;
        RETURN;
      END IF;

      UPDATE agendamentos
      SET status = 'cancelado', motivo_status = p_motivo, cancelado_em = now()
      WHERE id = p_id_agendamento;

      UPDATE lembretes
      SET status = 'cancelado', atualizado_em = now()
      WHERE id_agendamento = p_id_agendamento AND status = 'pendente';

      sucesso := true;
      mensagem := 'Agendamento cancelado com sucesso.';
      RETURN NEXT;
    END;
    $fn$;
  $ddl$, p_schema_name, p_schema_name);

  EXECUTE format($ddl$
    CREATE OR REPLACE VIEW %I.resumo_conversas AS
      SELECT DATE(data_hora) AS data,
             COUNT(*) AS total_conversas,
             COUNT(DISTINCT telefone) AS usuarios_unicos,
             AVG(LENGTH(resposta_ia)) AS tamanho_medio_resposta,
             MIN(data_hora) AS primeira_conversa,
             MAX(data_hora) AS ultima_conversa
      FROM %I.conversas
      GROUP BY DATE(data_hora)
      ORDER BY data DESC;

    CREATE OR REPLACE VIEW %I.resumo_usuarios AS
      SELECT u.telefone,
             u.nome,
             COUNT(c.id) AS total_mensagens,
             MAX(c.data_hora) AS ultima_interacao,
             MIN(c.data_hora) AS primeira_interacao,
             EXTRACT(EPOCH FROM (MAX(c.data_hora) - MIN(c.data_hora))) / NULLIF(COUNT(c.id) - 1, 0) / 3600 AS horas_entre_mensagens_media
      FROM %I.usuarios u
      LEFT JOIN %I.conversas c ON u.telefone = c.telefone
      GROUP BY u.id, u.telefone, u.nome
      ORDER BY total_mensagens DESC;

    CREATE OR REPLACE VIEW %I.profissionais_clinica AS SELECT * FROM %I.dentistas;
  $ddl$, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name, p_schema_name);

  FOR tbl IN
    SELECT unnest(ARRAY[
      'usuarios', 'conversas', 'n8n_chat_histories', 'avaliacoes', 'escalacoes',
      'metricas', 'documentos', 'dentistas', 'pacientes', 'procedimentos',
      'agendamentos', 'planos_tratamento', 'itens_tratamento',
      'registros_financeiros', 'lembretes', 'prontuarios', 'prescricoes'
    ])
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', p_schema_name, tbl);
  END LOOP;
END;
$$;

COMMENT ON FUNCTION clinicas.ensure_tenant_schema_objects(text) IS 'Creates/patches the full tenant-local table and function surface required by ADR §5.1/§5.2.';
