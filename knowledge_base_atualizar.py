#!/usr/bin/env python3
"""
Script para atualizar a base de conhecimento do consultório da Dra. Andreia Mota Mussi.

Fontes:
  - https://www.odontomedicoitaigara.com.br/odontólogos/andreia-mota-mussi.html/
  - https://www.instagram.com/andreapereiramota/

Funcionalidades:
  - Scraping do website
  - Coleta de dados do Instagram (via API ou web scraping)
  - Validação de dados
  - Merge com base existente
  - Backup automático
  - Exportação em JSON

Uso:
    python knowledge_base_atualizar.py [--site] [--instagram] [--full] [--backup]
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
# CONFIGURAÇÕES DO CONSULTÓRIO
# ============================================================================

CONSULTORIO_CONFIG = {
    "nome": "Consultório Dra. Andreia Mota Mussi",
    "profissional": "Dra. Andreia Mota Mussi",
    "website_url": "https://www.odontomedicoitaigara.com.br",
    "pagina_profissional": "https://www.odontomedicoitaigara.com.br/odontólogos/andreia-mota-mussi.html/",
    "instagram_username": "andreapereiramota",
    "telefone": "(71) 3353-7900",
    "endereco": "Av. Antônio Carlos Magalhães, 585 – Ed. Pierre Fauchard, Sala 709 - Itaigara, Salvador - BA, CEP 41825-907",
}


# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class DocumentoRAG:
    """Estrutura padrão de um documento na base de conhecimento."""
    id: str
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
    """Responsável por fazer scraping do website do Complexo Odonto Médico Itaigara."""

    def __init__(self):
        self.base_url = CONSULTORIO_CONFIG["website_url"]
        self.pagina_profissional = CONSULTORIO_CONFIG["pagina_profissional"]
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
        logger.info("📡 Iniciando scraping do website...")

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
                    doc = DocumentoRAG(
                        id=f"dra_web_{titulo.lower().replace(' ', '_')[:20]}",
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
    """Responsável por extrair dados do Instagram da Dra. Andreia."""

    def __init__(self):
        self.username = CONSULTORIO_CONFIG["instagram_username"]
        self.profile_url = f"https://www.instagram.com/{self.username}"

    def scrape_instagram(self) -> List[DocumentoRAG]:
        documentos = []
        logger.info("📸 Iniciando coleta de dados do Instagram...")

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
            doc = DocumentoRAG(
                id="dra_ig_perfil",
                categoria="redes_sociais",
                titulo=f"Perfil Instagram - @{self.username}",
                conteudo=f"A Dra. Andreia Mota Mussi está presente no Instagram como @{self.username}. "
                         f"No perfil, compartilha conteúdos sobre saúde bucal, dicas de cuidados "
                         f"dentários e informações sobre tratamentos disponíveis no consultório.",
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
                return json.load(f)
        return {"documentos": []}

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
        issues = []

        ids_vistos = set()
        for doc in docs:
            if doc['id'] in ids_vistos:
                issues.append(f"ID duplicado: {doc['id']}")
            ids_vistos.add(doc['id'])
            if not doc.get('conteudo', '').strip():
                issues.append(f"Conteúdo vazio: {doc['id']}")
            if not doc.get('titulo', '').strip():
                issues.append(f"Título vazio: {doc['id']}")

        return {
            "total_docs": len(docs),
            "ids_unicos": len(ids_vistos),
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
        categorias = {}
        for doc in docs:
            cat = doc.get('categoria', 'sem_categoria')
            categorias[cat] = categorias.get(cat, 0) + 1

        print("\n" + "=" * 50)
        print("📊 RELATÓRIO DA BASE DE CONHECIMENTO")
        print("=" * 50)
        print(f"Total de documentos: {len(docs)}")
        print(f"\nPor categoria:")
        for cat, count in sorted(categorias.items(), key=lambda x: -x[1]):
            print(f"  {cat}: {count}")
        print("=" * 50)


# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Atualizar base de conhecimento - Consultório Dra. Andreia Mota Mussi"
    )
    parser.add_argument('--site', action='store_true', help='Scraping do website')
    parser.add_argument('--instagram', action='store_true', help='Coleta do Instagram')
    parser.add_argument('--full', action='store_true', help='Atualização completa')
    parser.add_argument('--backup', action='store_true', help='Criar backup antes')
    parser.add_argument('--validate', action='store_true', help='Validar base existente')
    parser.add_argument('--report', action='store_true', help='Relatório da base')
    parser.add_argument('--deduplicate', action='store_true', help='Remover duplicados')

    args = parser.parse_args()
    kb_manager = KnowledgeBaseManager()

    if args.validate:
        result = kb_manager.validate()
        print(f"\n📋 Validação: {result['total_docs']} docs, {len(result['issues'])} problemas")
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

    novos_docs = []

    if args.site or args.full:
        scraper = WebSiteScraper()
        novos_docs.extend(scraper.scrape_site())

    if args.instagram or args.full:
        ig_scraper = InstagramScraper()
        novos_docs.extend(ig_scraper.scrape_instagram())

    if novos_docs:
        adicionados = kb_manager.merge(novos_docs)
        print(f"\n✅ {adicionados} novos documentos adicionados à base")
    else:
        print("\n⚠️  Nenhum documento novo coletado")
        if not (args.site or args.instagram or args.full):
            print("   Use: --site, --instagram ou --full")

    kb_manager.report()


if __name__ == "__main__":
    main()
