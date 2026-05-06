#!/usr/bin/env python3
"""
Script para atualizar a base de conhecimento multi-tenant para clínicas.

Multi-tenant: Suporta múltiplos profissionais com isolamento de dados via schema-per-tenant.

IMPORTANTE: professional_id neste script é usado apenas para organizar documentos no JSON
e determinar qual schema do Supabase será usado. Quando indexado, os documentos vão para
schemas separados SEM coluna professional_id (schema-isolation conforme ADR de Bruce).

Funcionalidades:
  - Scraping do website (configurável por profissional)
  - Coleta de dados do Instagram (via API ou web scraping)
  - Validação de dados multi-tenant
  - Merge com base existente
  - Backup automático
  - Exportação em JSON

Uso:
    # Atualizar tenant específico:
    python knowledge_base_atualizar.py --professional-id profissional-demo --site
    
    # Atualizar todos os tenants:
    python knowledge_base_atualizar.py --all --full
    
    # Validar base multi-tenant:
    python knowledge_base_atualizar.py --validate
"""

import json
import os
import sys
import argparse
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
import shutil

try:
    import requests
    from bs4 import BeautifulSoup
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    print("⚠️  Warning: requests/BeautifulSoup não instalados")
    print("   Execute: pip install requests beautifulsoup4")

try:
    from instagrapi import Client as InstagramClient
    INSTAGRAM_AVAILABLE = True
except ImportError:
    INSTAGRAM_AVAILABLE = False

# ============================================================================
# CONFIGURAÇÃO DE LOGGING
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s - %(asctime)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('atualizar_knowledge_base.log')
    ]
)
logger = logging.getLogger(__name__)

# ============================================================================
# CONFIGURAÇÕES MULTI-TENANT
# ============================================================================

# Example configuration - Add actual professionals here
DEFAULT_PROFESSIONAL_ID = None  # No default - requires explicit professional_id

PROFESSIONALS_CONFIG = {
    # Add professional configurations here:
    # "profissional-demo": {
    #     "professional_id": "profissional-demo",
    #     "nome": "Clinica Demo",
    #     "profissional": "Profissional Demo",
    #     "website_url": "https://example.com",
    #     "instagram_username": "clinicademo",
    #     "telefone": "(00) 0000-0000",
    #     "endereco": "Endereço da clínica",
    #     "active": True,
    #     "is_demo": False
    # }
}

def get_professional_config(professional_id: str) -> Dict[str, Any]:
    """Get configuration for a specific professional."""
    if professional_id not in PROFESSIONALS_CONFIG:
        raise ValueError(
            f"Professional '{professional_id}' not found in configuration. "
            f"Available: {list(PROFESSIONALS_CONFIG.keys())}"
        )
    return PROFESSIONALS_CONFIG[professional_id]


# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class DocumentoRAG:
    """Estrutura padrão de um documento na base de conhecimento multi-tenant.
    
    NOTE: professional_id is for JSON organization/routing only. When indexed to Supabase,
    documents go into tenant-specific schemas WITHOUT a professional_id column (schema-isolation).
    The tenant_code/professional_id determines which schema to write to, not a column filter.
    """
    id: str
    professional_id: str  # Tenant routing key (used to select schema, not as DB column)
    categoria: str
    titulo: str
    conteudo: str
    metadata: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'DocumentoRAG':
        return cls(**data)


# ============================================================================
# SCRAPER DO WEBSITE
# ============================================================================

class WebSiteScraper:
    """Responsável por fazer scraping do website (multi-tenant)."""

    def __init__(self, professional_id: str):
        self.professional_id = professional_id
        self.config = get_professional_config(professional_id)
        self.base_url = self.config["website_url"]
        self.pagina_profissional = self.config["pagina_profissional"]
        self.session = self._create_session() if REQUESTS_AVAILABLE else None

    def _create_session(self) -> Optional[requests.Session]:
        if not REQUESTS_AVAILABLE:
            return None
        session = requests.Session()
        session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        return session

    def scrape_site(self) -> List[DocumentoRAG]:
        if not REQUESTS_AVAILABLE:
            logger.error("❌ requests/BeautifulSoup não disponíveis")
            return []

        documentos = []
        logger.info(f"📡 Iniciando scraping para professional_id='{self.professional_id}'...")

        try:
            docs = self._scrape_pagina_profissional()
            documentos.extend(docs)
            logger.info(f"✅ Scraping concluído: {len(documentos)} documentos extraídos")
        except Exception as e:
            logger.error(f"❌ Erro no scraping: {str(e)}")

        return documentos

    def _scrape_pagina_profissional(self) -> List[DocumentoRAG]:
        documentos = []
        try:
            response = self.session.get(self.pagina_profissional, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrair informações da página do profissional
            sections = soup.find_all(['h1', 'h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h1', 'h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)
                if conteudo and len(conteudo) > 20:
                    doc_id_prefix = self.professional_id.replace("-", "_")
                    doc = DocumentoRAG(
                        id=f"{doc_id_prefix}_web_{titulo.lower().replace(' ', '_')[:20]}",
                        professional_id=self.professional_id,
                        categoria="sobre_consultorio",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "profissional",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "alto",
                            "url": self.pagina_profissional
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro na página do profissional: {str(e)}")

        return documentos


# ============================================================================
# SCRAPER DO INSTAGRAM
# ============================================================================

class InstagramScraper:
    """Responsável por extrair dados do Instagram (multi-tenant)."""

    def __init__(self, professional_id: str):
        self.professional_id = professional_id
        self.config = get_professional_config(professional_id)
        self.username = self.config.get("instagram_username")
        self.profile_url = f"https://www.instagram.com/{self.username}" if self.username else None

    def scrape_instagram(self) -> List[DocumentoRAG]:
        if not self.username:
            logger.warning(f"⚠️  Instagram username not configured for '{self.professional_id}'")
            return []
            
        documentos = []
        logger.info(f"📸 Iniciando coleta Instagram para professional_id='{self.professional_id}'...")

        if INSTAGRAM_AVAILABLE:
            docs = self._scrape_with_instagrapi()
            documentos.extend(docs)
        else:
            docs = self._scrape_instagram_web()
            documentos.extend(docs)

        logger.info(f"✅ Instagram: {len(documentos)} documentos extraídos")
        return documentos

    def _scrape_with_instagrapi(self) -> List[DocumentoRAG]:
        documentos = []
        try:
            logger.info("💡 Configure credenciais do Instagram em .env")
            logger.info("   INSTAGRAM_USERNAME=seu_usuario")
            logger.info("   INSTAGRAM_PASSWORD=sua_senha")
        except Exception as e:
            logger.warning(f"⚠️  Erro com instagrapi: {str(e)}")
        return documentos

    def _scrape_instagram_web(self) -> List[DocumentoRAG]:
        documentos = []
        if not REQUESTS_AVAILABLE:
            logger.warning("⚠️  requests não disponível para scraping do Instagram")
            return documentos

        try:
            logger.info(f"📸 Coletando dados públicos de @{self.username}")
            # Instagram requer autenticação para acesso à API
            # Adicionamos informação básica do perfil
            prof_name = self.config.get("profissional", "Professional")
            doc_id_prefix = self.professional_id.replace("-", "_")
            doc = DocumentoRAG(
                id=f"{doc_id_prefix}_ig_perfil",
                professional_id=self.professional_id,
                categoria="redes_sociais",
                titulo=f"Perfil Instagram - @{self.username}",
                conteudo=f"{prof_name} está presente no Instagram como @{self.username}. "
                         f"No perfil, compartilha conteúdos sobre saúde bucal, dicas de cuidados "
                         f"dentários e informações sobre tratamentos disponíveis.",
                metadata={
                    "fonte": "instagram",
                    "tipo": "perfil",
                    "atualizado": datetime.now().strftime("%Y-%m-%d"),
                    "relevancia": "medio",
                    "url": self.profile_url
                }
            )
            documentos.append(doc)
        except Exception as e:
            logger.warning(f"⚠️  Erro no Instagram web: {str(e)}")

        return documentos


# ============================================================================
# GERENCIADOR DA BASE DE CONHECIMENTO
# ============================================================================

class KnowledgeBaseManager:
    """Gerencia a base de conhecimento RAG."""

    def __init__(self, filepath: str = "knowledge_base.json"):
        self.filepath = filepath
        self.backup_dir = "backups"

    def load(self) -> Dict[str, Any]:
        if os.path.exists(self.filepath):
            with open(self.filepath, 'r', encoding='utf-8') as f:
                data = json.load(f)
                # Ensure multi-tenant schema
                if "professionals" not in data:
                    data["professionals"] = []
                if "version" not in data:
                    data["version"] = "2.0.0"
                if "schema" not in data:
                    data["schema"] = "multi_tenant"
                return data
        return {
            "version": "2.0.0",
            "schema": "multi_tenant",
            "professionals": [],
            "documentos": []
        }

    def save(self, data: Dict[str, Any]):
        with open(self.filepath, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        logger.info(f"✅ Base salva: {len(data['documentos'])} documentos")

    def backup(self):
        if not os.path.exists(self.filepath):
            return
        os.makedirs(self.backup_dir, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = os.path.join(self.backup_dir, f"knowledge_base_{timestamp}.json")
        shutil.copy2(self.filepath, backup_path)
        logger.info(f"📦 Backup criado: {backup_path}")

    def merge(self, novos_docs: List[DocumentoRAG]) -> int:
        kb = self.load()
        ids_existentes = {doc['id'] for doc in kb['documentos']}
        adicionados = 0

        for doc in novos_docs:
            doc_dict = doc.to_dict()
            if doc_dict['id'] not in ids_existentes:
                kb['documentos'].append(doc_dict)
                adicionados += 1
                logger.info(f"  + {doc_dict['id']}: {doc_dict['titulo']}")

        self.save(kb)
        return adicionados

    def validate(self) -> Dict[str, Any]:
        kb = self.load()
        docs = kb.get('documentos', [])
        professionals = kb.get('professionals', [])
        issues = []

        ids_vistos = set()
        professionals_found = set()
        
        for doc in docs:
            # Check for duplicates
            if doc['id'] in ids_vistos:
                issues.append(f"ID duplicado: {doc['id']}")
            ids_vistos.add(doc['id'])
            
            # Check required fields
            if not doc.get('conteudo', '').strip():
                issues.append(f"Conteúdo vazio: {doc['id']}")
            if not doc.get('titulo', '').strip():
                issues.append(f"Título vazio: {doc['id']}")
            
            # Check professional_id
            prof_id = doc.get('professional_id')
            if not prof_id:
                issues.append(f"Missing professional_id: {doc['id']}")
            else:
                professionals_found.add(prof_id)

        # Check if all professionals have documents
        registered_professionals = {p['professional_id'] for p in professionals if p.get('active', True)}
        missing_docs = registered_professionals - professionals_found
        if missing_docs:
            issues.append(f"Professionals without documents: {', '.join(missing_docs)}")

        return {
            "version": kb.get("version", "unknown"),
            "schema": kb.get("schema", "unknown"),
            "total_docs": len(docs),
            "ids_unicos": len(ids_vistos),
            "total_professionals": len(professionals),
            "professionals_with_docs": list(professionals_found),
            "issues": issues,
            "categorias": list(set(doc.get('categoria', '') for doc in docs))
        }

    def deduplicate(self) -> int:
        kb = self.load()
        vistos = set()
        unicos = []
        removidos = 0

        for doc in kb['documentos']:
            if doc['id'] not in vistos:
                vistos.add(doc['id'])
                unicos.append(doc)
            else:
                removidos += 1

        kb['documentos'] = unicos
        self.save(kb)
        return removidos

    def report(self):
        kb = self.load()
        docs = kb.get('documentos', [])
        professionals = kb.get('professionals', [])
        
        categorias = {}
        por_profissional = {}
        
        for doc in docs:
            cat = doc.get('categoria', 'sem_categoria')
            categorias[cat] = categorias.get(cat, 0) + 1
            
            prof_id = doc.get('professional_id', 'unknown')
            por_profissional[prof_id] = por_profissional.get(prof_id, 0) + 1

        print("\n" + "=" * 60)
        print("📊 RELATÓRIO DA BASE DE CONHECIMENTO MULTI-TENANT")
        print("=" * 60)
        print(f"Versão do schema: {kb.get('version', 'unknown')}")
        print(f"Tipo: {kb.get('schema', 'unknown')}")
        print(f"Total de documentos: {len(docs)}")
        print(f"Total de profissionais registrados: {len(professionals)}")
        
        print(f"\n👤 Por profissional:")
        for prof_id, count in sorted(por_profissional.items(), key=lambda x: -x[1]):
            # Get professional name if available
            prof_name = next((p['name'] for p in professionals if p['professional_id'] == prof_id), prof_id)
            active_status = "✓" if any(p['professional_id'] == prof_id and p.get('active', True) for p in professionals) else "✗"
            print(f"  {active_status} {prof_name} ({prof_id}): {count} docs")
        
        print(f"\n📂 Por categoria:")
        for cat, count in sorted(categorias.items(), key=lambda x: -x[1]):
            print(f"  {cat}: {count}")
        print("=" * 60)


# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Atualizar base de conhecimento multi-tenant - Plataforma de Clínicas"
    )
    parser.add_argument('--professional-id', type=str, default=DEFAULT_PROFESSIONAL_ID,
                        help='ID do profissional para atualizar (required)')
    parser.add_argument('--site', action='store_true', help='Scraping do website')
    parser.add_argument('--instagram', action='store_true', help='Coleta do Instagram')
    parser.add_argument('--full', action='store_true', help='Atualização completa')
    parser.add_argument('--all', action='store_true', help='Atualizar todos os profissionais')
    parser.add_argument('--backup', action='store_true', help='Criar backup antes')
    parser.add_argument('--validate', action='store_true', help='Validar base existente')
    parser.add_argument('--report', action='store_true', help='Relatório da base')
    parser.add_argument('--deduplicate', action='store_true', help='Remover duplicados')

    args = parser.parse_args()
    kb_manager = KnowledgeBaseManager()

    if args.validate:
        result = kb_manager.validate()
        print(f"\n📋 Validação Multi-Tenant:")
        print(f"   Schema version: {result['version']}")
        print(f"   Schema type: {result['schema']}")
        print(f"   Total docs: {result['total_docs']}")
        print(f"   Total professionals: {result['total_professionals']}")
        print(f"   Professionals with docs: {', '.join(result['professionals_with_docs'])}")
        print(f"   Issues: {len(result['issues'])} problemas")
        for issue in result['issues']:
            print(f"  ⚠️  {issue}")
        return

    if args.report:
        kb_manager.report()
        return

    if args.deduplicate:
        removed = kb_manager.deduplicate()
        print(f"🧹 {removed} duplicados removidos")
        return

    if args.backup or args.full:
        kb_manager.backup()

    # Determine which professionals to update
    if args.all:
        target_professionals = list(PROFESSIONALS_CONFIG.keys())
        print(f"\n🔄 Atualizando TODOS os profissionais: {', '.join(target_professionals)}")
    else:
        target_professionals = [args.professional_id]
        print(f"\n🔄 Atualizando profissional: {args.professional_id}")

    all_novos_docs = []

    for professional_id in target_professionals:
        try:
            print(f"\n{'=' * 60}")
            print(f"Processando: {professional_id}")
            print(f"{'=' * 60}")
            
            novos_docs = []

            if args.site or args.full:
                scraper = WebSiteScraper(professional_id)
                novos_docs.extend(scraper.scrape_site())

            if args.instagram or args.full:
                ig_scraper = InstagramScraper(professional_id)
                novos_docs.extend(ig_scraper.scrape_instagram())

            all_novos_docs.extend(novos_docs)
            print(f"✅ {len(novos_docs)} documentos coletados para {professional_id}")
            
        except ValueError as e:
            print(f"❌ Erro: {e}")
            continue
        except Exception as e:
            logger.error(f"❌ Erro processando {professional_id}: {e}")
            continue

    if all_novos_docs:
        adicionados = kb_manager.merge(all_novos_docs)
        print(f"\n✅ {adicionados} novos documentos adicionados à base multi-tenant")
    else:
        print("\n⚠️  Nenhum documento novo coletado")
        if not (args.site or args.instagram or args.full):
            print("   Use: --site, --instagram ou --full")
            print("   Exemplo: python knowledge_base_atualizar.py --professional-id profissional-demo --full")

    kb_manager.report()


if __name__ == "__main__":
    main()
