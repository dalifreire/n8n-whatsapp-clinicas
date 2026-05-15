-- ============================================================
-- v007_seed_dra_andreia.sql
-- Carga inicial da profissional Dra. Andreia Mota Mussi.
-- Este script é idempotente: pode ser re-executado sem efeito
-- colateral (todos os INSERTs usam ON CONFLICT / WHERE NOT EXISTS).
-- Depende de: v006_reminder_dispatchers.sql
-- ============================================================

DO $$
DECLARE
  v_org_id  uuid;
  v_prof_id uuid;
BEGIN
  -- 1. Organização
  INSERT INTO clinicas.organizations (name, address, contact_phone, business_hours, instagram_handle, metadata)
  SELECT
    'Consultório Dra. Andreia Mota Mussi',
    'Av. Antônio Carlos Magalhães, 585 – Ed. Pierre Fauchard, Sala 709 - Itaigara, Salvador - BA, CEP 41825-907',
    '(71) 3353-7900',
    '{"weekdays": "Segunda a Sexta, das 08:00 às 18:00", "weekend": "Sáb/Dom/Feriados: Fechado"}'::jsonb,
    '@andreapereiramota',
    '{"docencia": "Corpo docente do curso de residência em Reabilitação Oral - ABO-BA"}'::jsonb
  WHERE NOT EXISTS (
    SELECT 1
    FROM clinicas.organizations
    WHERE name = 'Consultório Dra. Andreia Mota Mussi'
  )
  RETURNING id INTO v_org_id;

  IF v_org_id IS NULL THEN
    SELECT id INTO v_org_id
    FROM clinicas.organizations
    WHERE name = 'Consultório Dra. Andreia Mota Mussi'
    LIMIT 1;
  END IF;

  -- 2. Schema + profissional (idempotente via provision)
  v_prof_id := clinicas.provision_professional_schema(
    p_tenant_code     := 'dra-andreia',
    p_schema_name     := 'clinicas_dra_andreia',
    p_organization_id := v_org_id
  );

  -- 3. Dados da profissional
  UPDATE clinicas.professionals SET
    full_name         = 'Dra. Andreia Mota Mussi',
    specialties       = ARRAY[
      'Prótese Dentária',
      'Prevenção de Doenças Bucais',
      'Restaurações em Resina',
      'Limpeza Dental',
      'Facetas em Cerâmica e Resina',
      'Próteses Removíveis',
      'Prótese Fixa sobre Dente',
      'Prótese sobre Implante',
      'Reabilitação Oral'
    ],
    credential_type   = 'CRO',
    credential_number = '4407',
    status            = 'active'
  WHERE id = v_prof_id;

  -- 4. Configuração do assistente DeIA
  UPDATE clinicas.assistant_configs SET
    persona_name = 'DeIA',
    tone         = 'acolhedor',
    language     = 'pt-BR',
    model        = 'gpt-5.1',
    prompt_config = '{
      "prompt_version": "v1",
      "layers": {
        "base": {"override": null, "extra_rules": []},
        "clinic": {"override": null, "extra_rules": [
          "A clínica fica no Ed. Pierre Fauchard, Sala 709, Itaigara, Salvador - BA.",
          "O horário de atendimento é de segunda a sexta, das 08:00 às 18:00."
        ]},
        "professional": {"override": null, "extra_rules": [
          "A Dra. Andreia Mota Mussi é especialista em Prótese Dentária.",
          "Atua com prevenção de doenças bucais, restaurações em resina, limpeza dental, facetas em cerâmica e resina, próteses removíveis, prótese fixa sobre dente e prótese sobre implante.",
          "A Dra. Andreia integra o corpo docente do curso de residência em Reabilitação Oral da ABO-BA."
        ]},
        "persona": {"override": null, "extra_rules": [
          "Seu nome é DeIA, inspirado no apelido Déa/Deia da Dra. Andreia.",
          "Atenda com linguagem clara, acolhedora, profissional e objetiva."
        ]},
        "service": {"override": null, "extra_rules": []}
      },
      "tools_enabled": [
        "buscar_conhecimento",
        "buscar_paciente",
        "agendar_consulta",
        "cancelar_consulta",
        "listar_horarios",
        "consultar_agendamentos",
        "listar_dentistas",
        "resumo_financeiro",
        "reiniciar_conversa",
        "listar_especialidades"
      ],
      "escalation": {
        "human_handoff_keywords": ["atendente", "humano", "secretaria", "recepção"],
        "emergency_keywords": ["dor intensa", "sangramento", "trauma", "urgência", "emergência"]
      }
    }'::jsonb,
    status       = 'active'
  WHERE professional_id = v_prof_id;

  -- 5. Carga inicial do schema da profissional
  INSERT INTO clinicas_dra_andreia.dentistas (
    nome, cro, especialidade, especialidades, telefone, ativo,
    dias_trabalho, inicio_jornada, fim_jornada, inicio_almoco, fim_almoco,
    duracao_consulta_minutos, metadados
  ) VALUES (
    'Dra. Andreia Mota Mussi',
    '4407',
    'Prótese Dentária',
    ARRAY[
      'Prótese Dentária',
      'Prevenção de Doenças Bucais',
      'Restaurações em Resina',
      'Limpeza Dental',
      'Facetas em Cerâmica e Resina',
      'Próteses Removíveis',
      'Prótese Fixa sobre Dente',
      'Prótese sobre Implante',
      'Reabilitação Oral'
    ],
    '(71) 3353-7900',
    true,
    ARRAY[1,2,3,4,5],
    '08:00',
    '18:00',
    '12:00',
    '13:00',
    30,
    '{"docencia": "Corpo docente do curso de residência em Reabilitação Oral - ABO-BA"}'::jsonb
  )
  ON CONFLICT (cro) DO UPDATE SET
    nome = EXCLUDED.nome,
    especialidade = EXCLUDED.especialidade,
    especialidades = EXCLUDED.especialidades,
    telefone = EXCLUDED.telefone,
    ativo = EXCLUDED.ativo,
    dias_trabalho = EXCLUDED.dias_trabalho,
    inicio_jornada = EXCLUDED.inicio_jornada,
    fim_jornada = EXCLUDED.fim_jornada,
    inicio_almoco = EXCLUDED.inicio_almoco,
    fim_almoco = EXCLUDED.fim_almoco,
    duracao_consulta_minutos = EXCLUDED.duracao_consulta_minutos,
    metadados = EXCLUDED.metadados,
    atualizado_em = now();

  INSERT INTO clinicas_dra_andreia.procedimentos (codigo, nome, categoria, duracao_media_min, ativo)
  VALUES
    ('PREV-001', 'Prevenção de Doenças Bucais', 'prevenção', 30, true),
    ('LIMP-001', 'Limpeza Dental', 'prevenção', 30, true),
    ('REST-001', 'Restauração em Resina', 'dentística', 45, true),
    ('FACE-001', 'Facetas em Cerâmica e Resina', 'estética', 60, true),
    ('PROT-001', 'Prótese Removível', 'prótese', 60, true),
    ('PROT-002', 'Prótese Fixa sobre Dente', 'prótese', 60, true),
    ('PROT-003', 'Prótese sobre Implante', 'prótese', 60, true),
    ('REAB-001', 'Reabilitação Oral', 'reabilitação oral', 60, true)
  ON CONFLICT (codigo) DO UPDATE SET
    nome = EXCLUDED.nome,
    categoria = EXCLUDED.categoria,
    duracao_media_min = EXCLUDED.duracao_media_min,
    ativo = EXCLUDED.ativo,
    atualizado_em = now();

  -- 6. Instância WhatsApp (WhatsApp Cloud API)
  UPDATE clinicas.whatsapp_instances SET
    provider             = 'whatsapp_cloud_api',
    provider_config      = jsonb_build_object('instance_id', 'Dra Andreia Mota Mussi'),
    status               = 'disconnected'
  WHERE professional_id = v_prof_id;

  RAISE NOTICE 'Seed: Dra. Andreia Mota Mussi registrada (professional_id: %)', v_prof_id;
END;
$$;
