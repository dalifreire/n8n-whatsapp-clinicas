#!/usr/bin/env python3
"""
Script para adicionar documentos de consultório odontológico à knowledge base.
Consultório da Dra. Andreia Mota Mussi - Itaigara, Salvador-BA.
"""

import json
import os
from datetime import datetime

KNOWLEDGE_BASE_PATH = os.path.join(os.path.dirname(__file__), "knowledge_base.json")

NOVOS_DOCUMENTOS = [
    # ============================================
    # AGENDAMENTO E CONSULTAS
    # ============================================
    {
        "id": "consult_001_agendamento",
        "categoria": "agendamento",
        "titulo": "Como Agendar uma Consulta",
        "conteudo": "Para agendar uma consulta com a Dra. Andreia Mota Mussi, você pode: 1) Enviar mensagem pelo WhatsApp informando o procedimento desejado e datas de preferência; 2) Ligar para (71) 3353-7900. Ao agendar, informe: nome completo, telefone, procedimento desejado e preferência de horário. O atendimento ocorre de segunda a sexta, das 08:00 às 18:00.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },
    {
        "id": "consult_002_primeira_consulta",
        "categoria": "agendamento",
        "titulo": "Primeira Consulta - O que Esperar",
        "conteudo": "Na primeira consulta, a Dra. Andreia realizará uma avaliação completa que inclui: exame clínico dos dentes e gengivas, análise de radiografias (se necessário), verificação de problemas como cáries, gengivite ou má oclusão, e elaboração de um plano de tratamento personalizado. Traga documentos pessoais, cartão do convênio (se tiver) e lista de medicamentos que utiliza. A consulta de avaliação dura aproximadamente 30 minutos.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },
    {
        "id": "consult_003_cancelamento",
        "categoria": "agendamento",
        "titulo": "Cancelamento e Reagendamento de Consultas",
        "conteudo": "Para cancelar ou reagendar sua consulta, entre em contato com pelo menos 24 horas de antecedência pelo WhatsApp ou telefone (71) 3353-7900. Cancelamentos de última hora ou faltas sem aviso podem impactar o atendimento a outros pacientes. Se precisar reagendar, comunique e buscaremos o melhor horário alternativo para você.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "consult_004_confirmacao",
        "categoria": "agendamento",
        "titulo": "Confirmação de Consultas",
        "conteudo": "Enviamos lembretes automáticos 24 horas antes da sua consulta via WhatsApp. Por favor, confirme sua presença respondendo SIM. Caso não possa comparecer, responda NÃO e entraremos em contato para reagendar. A confirmação nos ajuda a manter a agenda organizada e reduzir o tempo de espera.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },

    # ============================================
    # ESPECIALIDADES E PROCEDIMENTOS
    # ============================================
    {
        "id": "proc_001_especialidades",
        "categoria": "procedimentos",
        "titulo": "Especialidades Odontológicas Disponíveis",
        "conteudo": "A Dra. Andreia Mota Mussi oferece atendimento nas seguintes especialidades: Clínica Geral (avaliações, restaurações, limpezas), Prótese Dentária (coroas, pontes, dentaduras, próteses sobre implante), Reabilitação Oral (tratamentos completos para recuperação da função mastigatória e estética) e Estética Dental (clareamento, facetas, lentes de contato dental).",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },
    {
        "id": "proc_002_limpeza",
        "categoria": "procedimentos",
        "titulo": "Limpeza Dental (Profilaxia)",
        "conteudo": "A limpeza dental profissional (profilaxia) remove placa bacteriana e tártaro que a escovação não consegue eliminar. Recomenda-se fazer a cada 6 meses. O procedimento dura cerca de 30 minutos, é indolor e inclui polimento dos dentes. Após a limpeza, evite comer por 30 minutos.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "proc_003_restauracao",
        "categoria": "procedimentos",
        "titulo": "Restaurações Dentárias",
        "conteudo": "As restaurações em resina composta são usadas para tratar cáries e reparar dentes fraturados. O procedimento é feito com anestesia local, remoção da cárie e preenchimento com resina da cor do dente. Duração: 30-60 minutos dependendo do tamanho. Após o procedimento, sensibilidade leve é normal por alguns dias.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "proc_004_protese",
        "categoria": "procedimentos",
        "titulo": "Próteses Dentárias",
        "conteudo": "Tipos de próteses disponíveis: 1) Coroa unitária em porcelana - sobre dente preparado ou implante; 2) Ponte fixa - substitui dentes ausentes apoiando nos vizinhos; 3) Prótese parcial removível - para substituir vários dentes; 4) Prótese total/dentadura - para arcada completa. O processo envolve moldagem, prova e ajustes. A adaptação pode levar 2-4 semanas.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },
    {
        "id": "proc_005_clareamento",
        "categoria": "procedimentos",
        "titulo": "Clareamento Dental",
        "conteudo": "Oferecemos duas modalidades de clareamento: 1) Em consultório: resultado imediato em 90 minutos com gel de alta concentração e luz LED; 2) Caseiro supervisionado: kit com moldeira personalizada e gel para uso em casa por 2-3 semanas. Sensibilidade dental temporária é comum. Dieta branca por 48h após o tratamento (evitar café, vinho, açaí).",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "proc_006_facetas",
        "categoria": "procedimentos",
        "titulo": "Facetas e Lentes de Contato Dental",
        "conteudo": "As facetas de porcelana são finas lâminas coladas na frente dos dentes para corrigir cor, forma e alinhamento. Lentes de contato dental são ainda mais finas e exigem mínimo preparo do dente. Indicações: dentes manchados, espaçados, desalinhados ou lascados. Duração: pode durar mais de 10 anos com cuidados adequados.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "proc_007_reabilitacao",
        "categoria": "procedimentos",
        "titulo": "Reabilitação Oral",
        "conteudo": "A reabilitação oral é um tratamento completo que visa restaurar a função mastigatória, a estética e a saúde bucal do paciente. Pode envolver próteses, restaurações, tratamentos periodontais e outros procedimentos combinados. O plano é personalizado conforme a necessidade de cada paciente, com avaliação detalhada e planejamento em etapas.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },

    # ============================================
    # ORIENTAÇÕES PÓS-ATENDIMENTO
    # ============================================
    {
        "id": "orient_001_pos_extracao",
        "categoria": "orientacoes",
        "titulo": "Cuidados Pós-Extração Dentária",
        "conteudo": "Após a extração: 1) Morda a gaze por 30 minutos; 2) Aplique gelo no rosto (20min sim, 20min não) nas primeiras 24-48h; 3) Alimente-se com comida pastosa e fria por 3 dias; 4) NÃO cuspa com força, NÃO use canudo, NÃO fume por 7 dias; 5) NÃO faça bochecho vigoroso por 24h; 6) Tome os medicamentos conforme prescrito; 7) Escove normalmente, evitando a área operada; 8) Se houver sangramento excessivo ou dor intensa, entre em contato imediatamente.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },
    {
        "id": "orient_002_pos_restauracao",
        "categoria": "orientacoes",
        "titulo": "Cuidados Pós-Restauração",
        "conteudo": "Após uma restauração em resina: 1) A anestesia pode durar 2-4 horas - cuidado para não morder a bochecha ou lábio; 2) Evite alimentos muito duros nas primeiras 24h; 3) Sensibilidade ao frio/quente é normal por alguns dias; 4) Se a mordida parecer alta (um lado toca antes do outro), retorne para ajuste; 5) Mantenha boa higiene oral com escovação e fio dental.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "orient_003_pos_clareamento",
        "categoria": "orientacoes",
        "titulo": "Cuidados Pós-Clareamento",
        "conteudo": "Após o clareamento dental: 1) Dieta branca por 48h: evite café, chá, vinho, açaí, beterraba, molho de tomate, mostarda, refrigerante de cola; 2) Não fume; 3) Sensibilidade é esperada por 24-48h, use pasta para sensibilidade; 4) No clareamento caseiro: use a moldeira pelo tempo indicado, não exagere; 5) Resultados duram 1-3 anos dependendo dos hábitos.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "orient_004_pos_protese",
        "categoria": "orientacoes",
        "titulo": "Cuidados com Prótese Dentária",
        "conteudo": "Cuidados com próteses: 1) Prótese removível: remova para dormir, higienize com escova macia e sabão neutro, deixe imersa em água durante a noite; 2) Prótese fixa: escove normalmente, use fio dental com passador; 3) Retorne para revisões periódicas; 4) A adaptação leva de 2 a 4 semanas - desconforto inicial é normal; 5) Se houver dor persistente ou feridas, retorne para ajuste.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },

    # ============================================
    # SAÚDE BUCAL - PREVENÇÃO
    # ============================================
    {
        "id": "saude_001_escovacao",
        "categoria": "saude_bucal",
        "titulo": "Escovação Correta dos Dentes",
        "conteudo": "Escove os dentes pelo menos 3 vezes ao dia (após cada refeição principal) por no mínimo 2 minutos. Use escova macia e creme dental com flúor. Técnica: incline a escova 45 graus na gengiva, faça movimentos suaves de vai e vem ou circulares. Escove todas as superfícies: frente, trás e superfície de mastigação. Não esqueça de escovar a língua. Troque a escova a cada 3 meses.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "saude_002_fio_dental",
        "categoria": "saude_bucal",
        "titulo": "Uso do Fio Dental",
        "conteudo": "Use fio dental pelo menos 1 vez ao dia, preferencialmente à noite antes de dormir. O fio dental remove a placa e restos de alimentos entre os dentes, onde a escova não alcança. Técnica: use cerca de 40cm de fio, enrole nos dedos médios, deslize suavemente entre os dentes formando um 'C' ao redor de cada dente. Sangramento inicial é normal mas deve cessar em 1-2 semanas.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "saude_003_prevencao_carie",
        "categoria": "saude_bucal",
        "titulo": "Prevenção de Cáries",
        "conteudo": "Dicas para prevenir cáries: 1) Escovação 3x ao dia com creme dental com flúor; 2) Fio dental diário; 3) Reduza açúcar entre refeições; 4) Beba água após as refeições; 5) Visite o dentista a cada 6 meses para limpeza e avaliação; 6) Use enxaguante bucal com flúor; 7) Evite petiscar constantemente entre refeições.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },

    # ============================================
    # CONVÊNIOS E FINANCEIRO
    # ============================================
    {
        "id": "financ_001_convenios",
        "categoria": "financeiro",
        "titulo": "Convênios e Planos Aceitos",
        "conteudo": "Para verificar se seu convênio odontológico é aceito no consultório da Dra. Andreia, informe o nome do plano que confirmaremos. Pacientes com convênio devem trazer a carteirinha e documento de identidade. Alguns procedimentos podem ter coparticipação. Procedimentos estéticos geralmente não são cobertos por convênios.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "financ_002_formas_pagamento",
        "categoria": "financeiro",
        "titulo": "Formas de Pagamento",
        "conteudo": "Aceitamos as seguintes formas de pagamento: PIX (pagamento instantâneo), cartão de crédito (parcelamento em até 12x), cartão de débito, dinheiro e boleto bancário. Para tratamentos extensos, oferecemos condições especiais de parcelamento. Consulte as opções disponíveis para seu plano de tratamento.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "financ_003_orcamento",
        "categoria": "financeiro",
        "titulo": "Orçamento e Plano de Tratamento",
        "conteudo": "Após a consulta de avaliação, a Dra. Andreia elabora um plano de tratamento detalhado com orçamento completo. O orçamento inclui: procedimentos necessários, número de sessões estimado, valores individuais e total, e opções de parcelamento. O orçamento é apresentado para sua aprovação antes de iniciar qualquer tratamento.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },

    # ============================================
    # URGÊNCIA E EMERGÊNCIA
    # ============================================
    {
        "id": "urg_001_emergencia",
        "categoria": "urgencia",
        "titulo": "Atendimento de Urgência e Emergência",
        "conteudo": "Em caso de urgência odontológica (dor intensa, trauma dental, sangramento), entre em contato imediatamente pelo WhatsApp ou telefone (71) 3353-7900. Atendimentos de urgência são encaixados na agenda do dia quando possível. Fora do horário de funcionamento, procure um pronto-socorro com serviço odontológico. Emergências incluem: dor de dente insuportável, dente quebrado/avulsionado, abscesso/inchaço, sangramento que não para.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },
    {
        "id": "urg_002_dor_dente",
        "categoria": "urgencia",
        "titulo": "O que Fazer com Dor de Dente",
        "conteudo": "Se estiver com dor de dente: 1) Tome analgésico (dipirona ou paracetamol conforme orientação médica); 2) Aplique gelo no rosto do lado dolorido (NÃO aplique gelo ou remédio diretamente no dente); 3) Evite alimentos muito quentes, frios ou doces; 4) NÃO tome anti-inflamatório sem prescrição; 5) Agende consulta o mais breve possível.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },

    # ============================================
    # FAQ DO CONSULTÓRIO
    # ============================================
    {
        "id": "faq_001_dor_anestesia",
        "categoria": "faq",
        "titulo": "Os procedimentos doem? E a anestesia?",
        "conteudo": "A maioria dos procedimentos odontológicos é realizada com anestesia local e é indolor. A picada da anestesia causa desconforto mínimo e dura poucos segundos. Usamos anestesia tópica (gel) antes da injeção para reduzir a sensação. Após o procedimento, quando a anestesia passa (2-4 horas), pode haver sensibilidade ou dor leve, facilmente controlada com analgésicos.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "faq_002_frequencia_dentista",
        "categoria": "faq",
        "titulo": "Com que frequência devo ir ao dentista?",
        "conteudo": "Recomendamos visitar o dentista a cada 6 meses para avaliação e limpeza profissional. Essa frequência permite detectar problemas precocemente (cáries, doenças gengivais) quando são mais simples e baratos de tratar. Pacientes com histórico de problemas periodontais ou próteses podem precisar de visitas mais frequentes (a cada 3-4 meses).",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "faq_003_gestante",
        "categoria": "faq",
        "titulo": "Gestantes Podem Fazer Tratamento Dentário?",
        "conteudo": "Sim! Gestantes podem e devem manter o acompanhamento odontológico. O melhor período para procedimentos eletivos é o segundo trimestre (4º ao 6º mês). Procedimentos de urgência podem ser realizados em qualquer fase. Informe sempre sobre a gravidez. A anestesia local com lidocaína é segura. Radiografias são evitadas, mas podem ser feitas com proteção quando necessário.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
    {
        "id": "faq_004_medo_dentista",
        "categoria": "faq",
        "titulo": "Tenho Medo de Dentista, o que Fazer?",
        "conteudo": "O medo de dentista (odontofobia) é muito comum e tratável. A Dra. Andreia atende com acolhimento e cuidado para pacientes ansiosos. Dicas: 1) Converse abertamente sobre seu medo; 2) Combine um sinal (levantar a mão) para pausar quando precisar; 3) Use técnicas de respiração; 4) Traga fones de ouvido com música relaxante. Não deixe o medo impedir seu cuidado bucal.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },

    # ============================================
    # FUNCIONALIDADES DO ASSISTENTE
    # ============================================
    {
        "id": "assist_001_funcionalidades",
        "categoria": "assistente",
        "titulo": "O que o Assistente Virtual Pode Fazer",
        "conteudo": "Nosso assistente virtual pode ajudá-lo com: 1) Agendar, confirmar e cancelar consultas; 2) Verificar horários disponíveis; 3) Consultar seus próximos agendamentos; 4) Informações sobre procedimentos e especialidades; 5) Orientações pós-procedimento; 6) Informações sobre valores e formas de pagamento; 7) Consultar seu extrato financeiro; 8) Tirar dúvidas sobre saúde bucal; 9) Direcionamento para atendimento humano quando necessário.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "muito_alto"}
    },
    {
        "id": "assist_002_atendimento_humano",
        "categoria": "assistente",
        "titulo": "Atendimento Humano",
        "conteudo": "Se preferir falar com um atendente humano, basta pedir! Também direcionamos automaticamente para atendimento humano em casos de: emergências, reclamações, assuntos financeiros complexos, ou quando não conseguirmos resolver sua dúvida. O atendimento humano está disponível durante o horário comercial: segunda a sexta, 08:00 às 18:00.",
        "metadata": {"fonte": "manual", "atualizado": "2026-03-04", "relevancia": "alto"}
    },
]


def main():
    # Carregar knowledge base existente
    with open(KNOWLEDGE_BASE_PATH, 'r', encoding='utf-8') as f:
        kb = json.load(f)

    ids_existentes = {doc['id'] for doc in kb['documentos']}
    adicionados = 0

    for doc in NOVOS_DOCUMENTOS:
        if doc['id'] not in ids_existentes:
            kb['documentos'].append(doc)
            adicionados += 1
            print(f"  + {doc['id']}: {doc['titulo']}")
        else:
            print(f"  = {doc['id']}: já existe (pulando)")

    # Salvar
    with open(KNOWLEDGE_BASE_PATH, 'w', encoding='utf-8') as f:
        json.dump(kb, f, ensure_ascii=False, indent=2)

    print(f"\nTotal: {adicionados} documentos adicionados.")
    print(f"Knowledge base agora tem {len(kb['documentos'])} documentos.")


if __name__ == "__main__":
    main()
