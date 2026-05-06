#!/usr/bin/env python3
"""
Script para indexar documentos na base de conhecimento do Supabase usando pgvector.
Multi-tenant: suporta múltiplos profissionais com isolamento de dados via schema-per-tenant.

IMPORTANTE: Execute SUPABASE_SETUP.sql ANTES de rodar este script!

Este script:
1. Valida que a tabela 'documentos' existe no Supabase
2. Carrega documentos JSON da base de conhecimento (multi-tenant)
3. Gera embeddings usando OpenAI API
4. Armazena embeddings no Supabase PostgreSQL com pgvector
5. Mantém um índice pronto para buscas de similaridade (schema-isolation only)

SCHEMA ISOLATION: RAG isolation is schema-per-tenant. No professional_id column in documentos.

Requisitos:
- OPENAI_API_KEY
- SUPABASE_HOST
- SUPABASE_USER
- SUPABASE_PASSWORD
- SUPABASE_DB_NAME
- TENANT_CODE (required - no default)

Setup:
    1. Execute SUPABASE_SETUP.sql no Supabase Dashboard
    2. Instale: pip install openai psycopg2-binary
    3. Configure variáveis de ambiente
    4. Execute este script

Uso:
    # Indexar tenant específico (REQUIRED):
    python knowledge_base_indexar.py --tenant-code profissional-demo
    
    # Indexar tenant específico:
    python knowledge_base_indexar.py --tenant-code dr-carlos
    
    # Indexar todos os tenants:
    python knowledge_base_indexar.py --all
"""

import json
import os
import sys
import argparse
from typing import List, Dict, Any, Optional
import psycopg2
from openai import OpenAI

# Configuration
KNOWLEDGE_BASE_FILE = "knowledge_base.json"
EMBEDDING_MODEL = "text-embedding-3-small"
BATCH_SIZE = 10
MAX_TEXT_CHARS = 30000
DEFAULT_TENANT_CODE = "tenant-demo"  # Default for demo/migration mode - override with --tenant-code

# Environment variables
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
SUPABASE_HOST = os.getenv("SUPABASE_HOST")
SUPABASE_USER = os.getenv("SUPABASE_USER")
SUPABASE_PASSWORD = os.getenv("SUPABASE_PASSWORD")
SUPABASE_DB_NAME = os.getenv("SUPABASE_DB_NAME")
SUPABASE_PORT = os.getenv("SUPABASE_PORT")
TENANT_CODE = os.getenv("TENANT_CODE", os.getenv("PROFESSIONAL_ID", None))  # No default - requires explicit tenant


def validate_config():
    """Validate that all required environment variables are set."""
    if not OPENAI_API_KEY:
        print("❌ Error: OPENAI_API_KEY not set")
        sys.exit(1)
    if not SUPABASE_PASSWORD:
        print("❌ Error: SUPABASE_PASSWORD not set")
        sys.exit(1)
    print("✅ Configuration validated")


def get_tenant_schema(tenant_code: str) -> str:
    """Get database schema name from tenant_code."""
    # Schema naming convention: replace hyphens with underscores
    return tenant_code.replace("-", "_")


def load_knowledge_base(tenant_code: Optional[str] = None) -> tuple[List[Dict[str, Any]], List[str]]:
    """Load documents from JSON knowledge base.
    
    Args:
        tenant_code: Filter documents by tenant_code/professional_id. If None, load all.
        
    Returns:
        Tuple of (documents, list of tenant_codes found)
    """
    if not os.path.exists(KNOWLEDGE_BASE_FILE):
        print(f"❌ Error: {KNOWLEDGE_BASE_FILE} not found")
        print("   Execute primeiro: python knowledge_base_consultorio.py")
        sys.exit(1)

    with open(KNOWLEDGE_BASE_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    all_documents = data.get("documentos", [])
    
    # Check schema version
    schema_version = data.get("version", "1.0.0")
    if not schema_version.startswith("2."):
        print(f"⚠️  Warning: Knowledge base schema version {schema_version} may not support multi-tenant")
    
    # Extract list of tenants from metadata
    professionals_meta = data.get("professionals", [])
    available_tenants = [p["professional_id"] for p in professionals_meta if p.get("active", True)]
    
    # Filter by tenant_code if specified
    if tenant_code:
        # professional_id in JSON is equivalent to tenant_code
        documents = [doc for doc in all_documents if doc.get("professional_id") == tenant_code]
        if len(documents) == 0:
            print(f"❌ Error: No documents found for tenant='{tenant_code}'")
            print(f"   Available tenants: {available_tenants}")
            sys.exit(1)
        print(f"✅ Loaded {len(documents)} documents for tenant '{tenant_code}'")
    else:
        documents = all_documents
        print(f"✅ Loaded {len(documents)} documents (all tenants)")
    
    if len(documents) == 0:
        print("⚠️  No documents found in knowledge base!")
        print("   Run: python knowledge_base_consultorio.py")
    else:
        sample = documents[0]
        tenant = sample.get("professional_id", "MISSING")
        print(f"   Sample document: tenant={tenant}, id={sample.get('id')}")
    
    # Extract unique tenant_codes from filtered documents (professional_id in JSON = tenant_code)
    found_tenants = list(set(doc.get("professional_id", "unknown") for doc in documents))
    
    return documents, found_tenants


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


def validate_documents_table(conn, schema_name: str):
    """Validate that documents table exists with correct schema.
    
    Args:
        schema_name: Database schema name for the tenant
    """
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_schema = %s AND table_name = 'documentos'
            );
        """, (schema_name,))

        table_exists = cur.fetchone()[0]

        if not table_exists:
            print(f"❌ Error: '{schema_name}.documentos' table does not exist in Supabase")
            print("   Please execute SUPABASE_SETUP.sql first or create schema for this tenant")
            sys.exit(1)

        # Check for embedding column
        cur.execute("""
            SELECT column_name, data_type
            FROM information_schema.columns
            WHERE table_schema = %s AND table_name = 'documentos' 
            AND column_name = 'embedding';
        """, (schema_name,))

        columns = {row[0]: row[1] for row in cur.fetchall()}
        
        if 'embedding' not in columns:
            print(f"❌ Error: 'embedding' column not found in {schema_name}.documentos")
            sys.exit(1)

        print(f"✅ Documents table schema validated for '{schema_name}' (schema-isolation)")
        return True
    except Exception as e:
        print(f"❌ Error validating table: {e}")
        sys.exit(1)


def store_documents(conn, documents: List[Dict[str, Any]], embeddings: List[List[float]], schema_name: str):
    """Store documents with embeddings in Supabase.
    
    Args:
        schema_name: Database schema name for the tenant (schema-isolation only)
    """
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

        # Schema-isolation: no professional_id column needed
        insert_query = f"""
            INSERT INTO {schema_name}.documentos (titulo, conteudo, categoria, metadados, embedding, fonte)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT DO NOTHING;
        """

        for i in range(0, len(data), BATCH_SIZE):
            batch = data[i:i + BATCH_SIZE]
            cur.executemany(insert_query, batch)
            conn.commit()
            print(f"✅ Inserted batch {i // BATCH_SIZE + 1}/{(len(data) + BATCH_SIZE - 1) // BATCH_SIZE}")

        print(f"\n✅ Stored {len(data)} documents with embeddings in '{schema_name}'")
    except Exception as e:
        print(f"❌ Error storing documents: {e}")
        sys.exit(1)


def test_similarity_search(conn, schema_name: str):
    """Test that similarity search works.
    
    Args:
        schema_name: Database schema name for the tenant (schema-isolation)
    """
    try:
        cur = conn.cursor()

        test_text = "Quais são os horários de atendimento?"
        embedding = generate_embeddings([test_text])[0]

        # Schema-isolation: no professional_id filtering needed
        query = f"""
            SELECT conteudo, metadados->>'titulo' as titulo,
                   1 - (embedding <=> %s::vector) as similaridade
            FROM {schema_name}.documentos
            ORDER BY embedding <=> %s::vector
            LIMIT 3;
        """
        cur.execute(query, (embedding, embedding))

        results = cur.fetchall()

        if results:
            print(f"✅ Similarity search working in '{schema_name}'!")
            print("   Sample results:")
            for row in results:
                content, title, similarity = row
                print(f"   - {title}: {similarity:.2%} similarity")
        else:
            print("⚠️  No documents found in similarity search")
    except Exception as e:
        print(f"⚠️  Warning in similarity search test: {e}")


def main():
    """Main execution flow."""
    parser = argparse.ArgumentParser(
        description="Index knowledge base documents for multi-tenant clinic platform (schema-isolation)"
    )
    parser.add_argument(
        '--tenant-code',
        type=str,
        default=None,
        help=f'Tenant code to index (default: env TENANT_CODE or {DEFAULT_TENANT_CODE})'
    )
    parser.add_argument(
        '--professional-id',
        type=str,
        default=None,
        dest='tenant_code_legacy',
        help='(Deprecated: use --tenant-code) Legacy alias for tenant code'
    )
    parser.add_argument(
        '--all',
        action='store_true',
        help='Index all tenants in knowledge base'
    )
    
    args = parser.parse_args()
    
    # Determine which tenant(s) to index
    if args.all:
        target_tenant = None
        print("=" * 60)
        print("Multi-Tenant Clinic Platform - RAG Indexing (ALL)")
        print("Schema Isolation Mode: schema-per-tenant")
        print("=" * 60)
    else:
        # Support legacy --professional-id flag
        target_tenant = args.tenant_code or args.tenant_code_legacy or TENANT_CODE
        if not target_tenant:
            print("❌ Error: No tenant specified")
            print("   Use --tenant-code <code> or set TENANT_CODE environment variable")
            print("   Example: python knowledge_base_indexar.py --tenant-code profissional-demo")
            sys.exit(1)
        print("=" * 60)
        print(f"Multi-Tenant Clinic Platform - RAG Indexing")
        print(f"Tenant: {target_tenant}")
        print(f"Schema Isolation Mode: schema-per-tenant")
        print("=" * 60)

    print("\n📋 Validating configuration...")
    validate_config()

    print(f"\n📚 Loading knowledge base '{KNOWLEDGE_BASE_FILE}'...")
    documents, found_tenants = load_knowledge_base(target_tenant)

    if not documents:
        print("❌ No documents to index")
        sys.exit(1)

    print(f"\n   Found tenants: {', '.join(found_tenants)}")

    print("\n🔗 Connecting to Supabase...")
    conn = connect_supabase()

    print("\n🔧 Checking pgvector extension...")
    ensure_pgvector_extension(conn)

    # Process each tenant separately (schema-per-tenant isolation)
    for tenant_code in found_tenants:
        print(f"\n{'=' * 60}")
        print(f"Processing tenant: {tenant_code}")
        print(f"{'=' * 60}")
        
        schema_name = get_tenant_schema(tenant_code)
        tenant_documents = [doc for doc in documents if doc.get("professional_id") == tenant_code]
        
        print(f"\n✔️  Validating documents table schema for '{schema_name}'...")
        validate_documents_table(conn, schema_name)

        print(f"\n📊 Generating embeddings for {len(tenant_documents)} documents...")
        texts = [doc.get("conteudo", "") for doc in tenant_documents]
        embeddings = generate_embeddings(texts)

        print(f"\n📦 Storing documents with embeddings in '{schema_name}'...")
        print(f"   Total documents to insert: {len(tenant_documents)}")
        print(f"   Batch size: {BATCH_SIZE}")
        print(f"   Isolation: schema-per-tenant (no professional_id column)")
        store_documents(conn, tenant_documents, embeddings, schema_name)

        print(f"\n🔍 Testing similarity search for '{schema_name}'...")
        test_similarity_search(conn, schema_name)

    conn.close()

    print("\n" + "=" * 60)
    print("✅ RAG INDEXING COMPLETE!")
    print("=" * 60)
    print(f"📍 Indexed {len(found_tenants)} tenant(s): {', '.join(found_tenants)}")
    print("📍 Documents are now queryable via Supabase pgvector")
    print("📍 Isolation: Schema-per-tenant (no professional_id filtering needed)")
    print("📍 Use n8n workflow with tenant_code to select correct schema")
    print("=" * 60)


if __name__ == "__main__":
    main()
