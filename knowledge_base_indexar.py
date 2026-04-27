#!/usr/bin/env python3
"""
Script para indexar documentos na base de conhecimento do Supabase usando pgvector.
Consultório Dra. Andreia Mota Mussi.

IMPORTANTE: Execute SUPABASE_SETUP.sql ANTES de rodar este script!

Este script:
1. Valida que a tabela 'documentos' existe no Supabase
2. Carrega documentos JSON da base de conhecimento
3. Gera embeddings usando OpenAI API
4. Armazena embeddings no Supabase PostgreSQL com pgvector
5. Mantém um índice pronto para buscas de similaridade

Requisitos:
- OPENAI_API_KEY
- SUPABASE_HOST
- SUPABASE_USER
- SUPABASE_PASSWORD
- SUPABASE_DB_NAME

Setup:
    1. Execute SUPABASE_SETUP.sql no Supabase Dashboard
    2. Instale: pip install openai psycopg2-binary
    3. Configure variáveis de ambiente
    4. Execute este script

Uso:
    python knowledge_base_indexar.py
"""

import json
import os
import sys
from typing import List, Dict, Any
import psycopg2
from openai import OpenAI

# Configuration
KNOWLEDGE_BASE_FILE = "knowledge_base.json"
EMBEDDING_MODEL = "text-embedding-3-small"
BATCH_SIZE = 10
MAX_TEXT_CHARS = 30000
DB_SCHEMA = "dra_andreia"

# Environment variables
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
SUPABASE_HOST = os.getenv("SUPABASE_HOST")
SUPABASE_USER = os.getenv("SUPABASE_USER")
SUPABASE_PASSWORD = os.getenv("SUPABASE_PASSWORD")
SUPABASE_DB_NAME = os.getenv("SUPABASE_DB_NAME")
SUPABASE_PORT = os.getenv("SUPABASE_PORT")


def validate_config():
    """Validate that all required environment variables are set."""
    if not OPENAI_API_KEY:
        print("❌ Error: OPENAI_API_KEY not set")
        sys.exit(1)
    if not SUPABASE_PASSWORD:
        print("❌ Error: SUPABASE_PASSWORD not set")
        sys.exit(1)
    print("✅ Configuration validated")


def load_knowledge_base() -> List[Dict[str, Any]]:
    """Load documents from JSON knowledge base."""
    if not os.path.exists(KNOWLEDGE_BASE_FILE):
        print(f"❌ Error: {KNOWLEDGE_BASE_FILE} not found")
        print("   Execute primeiro: python knowledge_base_consultorio.py")
        sys.exit(1)

    with open(KNOWLEDGE_BASE_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    documents = data.get("documentos", [])
    print(f"✅ Loaded {len(documents)} documents from knowledge base")

    if len(documents) == 0:
        print("⚠️  No documents found in knowledge base!")
        print("   Run: python knowledge_base_consultorio.py")
    else:
        print(f"   Sample document: {documents[0]}")

    return documents


def truncate_text(text: str, max_chars: int = MAX_TEXT_CHARS) -> str:
    """Truncate text to stay within the model's token limit."""
    if len(text) <= max_chars:
        return text
    truncated = text[:max_chars]
    last_period = truncated.rfind('. ')
    if last_period > max_chars * 0.8:
        truncated = truncated[:last_period + 1]
    return truncated


def _embed_single(client, text: str) -> List[float]:
    """Embed a single text, truncating if necessary."""
    text = truncate_text(text)
    response = client.embeddings.create(model=EMBEDDING_MODEL, input=[text])
    return response.data[0].embedding


def generate_embeddings(texts: List[str]) -> List[List[float]]:
    """Generate embeddings for a list of texts using OpenAI API."""
    client = OpenAI(api_key=OPENAI_API_KEY)

    indexed_texts = [(i, text) for i, text in enumerate(texts) if text and len(text.strip()) > 10]

    if not indexed_texts:
        print("❌ No valid texts to generate embeddings")
        sys.exit(1)

    print(f"📝 Processing {len(indexed_texts)} valid texts (filtered from {len(texts)})")

    oversized = [(i, t) for i, t in indexed_texts if len(t) > MAX_TEXT_CHARS]
    if oversized:
        print(f"⚠️  {len(oversized)} text(s) exceed {MAX_TEXT_CHARS} chars and will be truncated")

    all_embeddings: List[List[float]] = [None] * len(texts)
    batch_size = min(3, len(indexed_texts))
    skipped = 0

    for batch_start in range(0, len(indexed_texts), batch_size):
        batch = indexed_texts[batch_start:batch_start + batch_size]
        batch_num = batch_start // batch_size + 1
        orig_indices = [i for i, _ in batch]
        batch_texts = [truncate_text(t) for _, t in batch]

        print(f"🔍 Batch {batch_num}: Processing {len(batch_texts)} texts")
        print(f"   First text preview: {batch_texts[0][:50]}...")

        try:
            response = client.embeddings.create(model=EMBEDDING_MODEL, input=batch_texts)
            for k, item in enumerate(response.data):
                all_embeddings[orig_indices[k]] = item.embedding
            print(f"✅ Batch {batch_num} completed")
        except Exception as batch_err:
            print(f"⚠️  Batch {batch_num} failed ({batch_err}). Retrying individually...")
            for orig_idx, text in batch:
                try:
                    all_embeddings[orig_idx] = _embed_single(client, text)
                    print(f"   ✅ Item {orig_idx} recovered")
                except Exception as item_err:
                    print(f"   ❌ Item {orig_idx} skipped: {item_err}")
                    all_embeddings[orig_idx] = None
                    skipped += 1

    if skipped:
        print(f"⚠️  {skipped} document(s) skipped due to embedding errors")

    filled = sum(1 for e in all_embeddings if e is not None)
    print(f"✅ Generated {filled} total embeddings")
    return all_embeddings


def connect_supabase():
    """Connect to Supabase PostgreSQL."""
    try:
        conn = psycopg2.connect(
            host=SUPABASE_HOST,
            port=SUPABASE_PORT,
            database=SUPABASE_DB_NAME,
            user=SUPABASE_USER,
            password=SUPABASE_PASSWORD
        )
        print("✅ Connected to Supabase PostgreSQL")
        return conn
    except Exception as e:
        print(f"❌ Error connecting to Supabase: {e}")
        sys.exit(1)


def ensure_pgvector_extension(conn):
    """Ensure pgvector extension is enabled."""
    try:
        cur = conn.cursor()
        cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
        conn.commit()
        print("✅ pgvector extension enabled")
    except Exception as e:
        print(f"⚠️  Note: {e}")


def validate_documents_table(conn):
    """Validate that documents table exists with correct schema."""
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_schema = %s AND table_name = 'documentos'
            );
        """, (DB_SCHEMA,))

        table_exists = cur.fetchone()[0]

        if not table_exists:
            print(f"❌ Error: '{DB_SCHEMA}.documentos' table does not exist in Supabase")
            print("   Please execute SUPABASE_SETUP.sql first")
            sys.exit(1)

        cur.execute("""
            SELECT column_name, data_type
            FROM information_schema.columns
            WHERE table_schema = %s AND table_name = 'documentos' AND column_name = 'embedding';
        """, (DB_SCHEMA,))

        result = cur.fetchone()
        if not result:
            print(f"❌ Error: 'embedding' column not found in {DB_SCHEMA}.documentos")
            sys.exit(1)

        print("✅ Documents table schema validated")
        return True
    except Exception as e:
        print(f"❌ Error validating table: {e}")
        sys.exit(1)


def store_documents(conn, documents: List[Dict[str, Any]], embeddings: List[List[float]]):
    """Store documents with embeddings in Supabase."""
    try:
        cur = conn.cursor()

        data = []
        skipped = 0
        for doc, embedding in zip(documents, embeddings):
            if embedding is None:
                skipped += 1
                continue
            title = doc.get("titulo", "")
            content = doc.get("conteudo", "")
            category = doc.get("categoria", "")
            source = doc.get("metadata", {}).get("fonte", "")
            metadata = {
                "updated": doc.get("metadata", {}).get("atualizado", "")
            }
            data.append((title, content, category, json.dumps(metadata), embedding, source))

        if skipped:
            print(f"⚠️  Skipping {skipped} document(s) with missing embeddings")

        insert_query = f"""
            INSERT INTO {DB_SCHEMA}.documentos (titulo, conteudo, categoria, metadados, embedding, fonte)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT DO NOTHING;
        """

        for i in range(0, len(data), BATCH_SIZE):
            batch = data[i:i + BATCH_SIZE]
            cur.executemany(insert_query, batch)
            conn.commit()
            print(f"✅ Inserted batch {i // BATCH_SIZE + 1}/{(len(data) + BATCH_SIZE - 1) // BATCH_SIZE}")

        print(f"\n✅ Stored {len(data)} documents with embeddings in Supabase")
    except Exception as e:
        print(f"❌ Error storing documents: {e}")
        sys.exit(1)


def test_similarity_search(conn):
    """Test that similarity search works."""
    try:
        cur = conn.cursor()

        test_text = "Quais são os horários de atendimento?"
        embedding = generate_embeddings([test_text])[0]

        cur.execute(f"""
            SELECT conteudo, metadados->>'titulo' as titulo,
                   1 - (embedding <=> %s::vector) as similaridade
            FROM {DB_SCHEMA}.documentos
            ORDER BY embedding <=> %s::vector
            LIMIT 3;
        """, (embedding, embedding))

        results = cur.fetchall()

        if results:
            print("✅ Similarity search working!")
            print("   Sample results:")
            for content, title, similarity in results:
                print(f"   - {title}: {similarity:.2%} similarity")
        else:
            print("⚠️  No documents found in similarity search")
    except Exception as e:
        print(f"⚠️  Warning in similarity search test: {e}")


def main():
    """Main execution flow."""
    print("=" * 60)
    print("Dra. Andreia Mota Mussi - RAG Indexing - Supabase pgvector")
    print("=" * 60)

    print("\n📋 Validating configuration...")
    validate_config()

    print(f"\n📚 Loading knowledge base '{KNOWLEDGE_BASE_FILE}'...")
    documents = load_knowledge_base()

    if not documents:
        print("❌ No documents to index")
        sys.exit(1)

    print("\n🔗 Connecting to Supabase...")
    conn = connect_supabase()

    print("\n🔧 Checking pgvector extension...")
    ensure_pgvector_extension(conn)

    print("\n✔️  Validating documents table schema...")
    validate_documents_table(conn)

    print("\n📊 Generating embeddings...")
    texts = [doc.get("conteudo", "") for doc in documents]
    embeddings = generate_embeddings(texts)

    print("\n📦 Storing documents with embeddings...")
    print(f"   Total documents to insert: {len(documents)}")
    print(f"   Batch size: {BATCH_SIZE}")
    store_documents(conn, documents, embeddings)

    print("\n🔍 Testing similarity search...")
    test_similarity_search(conn)

    conn.close()

    print("\n" + "=" * 60)
    print("✅ RAG INDEXING COMPLETE!")
    print("=" * 60)
    print("📍 Documents are now queryable via Supabase pgvector")
    print("📍 Use N8n workflow to access indexed documents")
    print("=" * 60)


if __name__ == "__main__":
    main()
