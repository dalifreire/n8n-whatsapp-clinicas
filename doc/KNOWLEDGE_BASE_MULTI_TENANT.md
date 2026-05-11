# Multi-Tenant Knowledge Base — Usage Guide

**Version:** 2.0.0  
**Status:** Ready for integration with database layer  
**Scope:** AI/RAG knowledge base for multi-professional clinic platform

---

## Overview

The knowledge base supports **isolated assistants per professional** with schema-per-tenant architecture. Each professional has their own document set, embeddings, and database schema isolation.

---

## Quick Start

### 1. Add a New Professional

**Step 1:** Add config to `src/knowledge_base_atualizar.py`:

```python
PROFESSIONALS_CONFIG = {
    "profissional-demo": {
        "professional_id": "profissional-demo",
        "nome": "Clinica Demo",
        "profissional": "Profissional Demo",
        "website_url": "https://example.com",
        "instagram_username": "clinicademo",
        "telefone": "(00) 0000-0000",
        "endereco": "Endereço da clínica",
        "active": True,
        "is_demo": False
    }
}
```

**Step 2:** Generate seed documents:

```bash
PROFESSIONAL_ID=profissional-demo python src/knowledge_base_consultorio.py
```

**Step 3:** Index for new professional:

```bash
python src/knowledge_base_indexar.py --tenant-code profissional-demo
```

**Step 4:** (Optional) Scrape professional's website/social:

```bash
python src/knowledge_base_atualizar.py --professional-id profissional-demo --full
```

---

## CLI Reference

### src/knowledge_base_indexar.py

Generate embeddings and store in Supabase pgvector.

```bash
# Index specific professional (REQUIRED)
python src/knowledge_base_indexar.py --tenant-code profissional-demo

# Index all professionals in knowledge base
python src/knowledge_base_indexar.py --all

# Use environment variable
TENANT_CODE=profissional-demo python src/knowledge_base_indexar.py
```

**Environment Variables:**
- `TENANT_CODE` — Professional to index (REQUIRED - no default)
- `OPENAI_API_KEY` — OpenAI API key for embeddings
- `SUPABASE_HOST`, `SUPABASE_PASSWORD`, etc. — Database config

---

### src/knowledge_base_atualizar.py

Scrape professional's website/social media and update knowledge base.

```bash
# Update specific professional
python src/knowledge_base_atualizar.py --professional-id profissional-demo --full

# Update all professionals
python src/knowledge_base_atualizar.py --all --site --instagram

# Validate multi-tenant schema
python src/knowledge_base_atualizar.py --validate

# Show per-professional stats
python src/knowledge_base_atualizar.py --report
```

**Flags:**
- `--site` — Scrape professional's website
- `--instagram` — Scrape Instagram profile
- `--full` — Both website and Instagram
- `--validate` — Check schema integrity
- `--report` — Show document counts per professional
- `--backup` — Create backup before updating

---

### src/knowledge_base_consultorio.py

Add generic seed documents (scheduling, procedures, FAQ) for a professional.

```bash
# Add documents for specific professional (REQUIRED)
PROFESSIONAL_ID=profissional-demo python src/knowledge_base_consultorio.py
```

**Note:** Edit `NOVOS_DOCUMENTOS` array to customize document content per professional. Replace placeholder text with actual clinic information.

---

## Schema Structure

### knowledge_base.json

```json
{
  "version": "2.0.0",
  "schema": "multi_tenant",
  "description": "Generic clinic assistant knowledge base",
  "professionals": [
    {
      "professional_id": "profissional-demo",
      "name": "Nome do Profissional",
      "specialty": "Especialidade",
      "active": true,
      "metadata": {}
    }
  ],
  "documentos": [
    {
      "id": "prof_001_sobre",
      "professional_id": "profissional-demo",
      "categoria": "sobre_consultorio",
      "titulo": "...",
      "conteudo": "...",
      "metadata": { ... }
    }
  ],
  "_demo_data": {
    "_comment": "Historical seed data for migration purposes"
  }
}
```

**Required Fields:**
- `professional_id` — Isolation key (kebab-case: "profissional-demo", "clinica-exemplo")
- `id` — Document unique ID (prefix with professional_id to avoid collisions)
- `categoria` — Document category
- `titulo`, `conteudo` — Title and content
- `metadata` — Source, update date, etc.

---

## Database Schema

### Per-Professional Isolation

Each professional gets their own PostgreSQL schema:

- `profissional-demo` → `profissional_demo` schema
- `clinica-exemplo` → `clinica_exemplo` schema

### Required Table Structure

```sql
CREATE SCHEMA IF NOT EXISTS profissional_demo;

CREATE TABLE profissional_demo.documentos (
    id BIGSERIAL PRIMARY KEY,
    titulo TEXT,
    conteudo TEXT,
    categoria VARCHAR(100),
    metadados JSONB,
    embedding vector(1536),        -- text-embedding-3-small
    fonte VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_documentos_embedding ON profissional_demo.documentos USING ivfflat(embedding vector_cosine_ops);
```

---

## Naming Conventions

| Scope | Format | Example |
|-------|--------|---------|
| Professional ID | kebab-case | `profissional-demo`, `clinica-exemplo` |
| Database Schema | underscore-case | `profissional_demo`, `clinica_exemplo` |
| Document ID Prefix | underscore-case | `prof_001_sobre`, `clinica_002_horario` |
| Config Key | kebab-case | `PROFESSIONALS_CONFIG["profissional-demo"]` |

**Conversion:** Handled automatically by `get_tenant_schema(tenant_code)`.

---

## Integration Points

### n8n Workflows

Pass `tenant_code` when invoking scripts:

```javascript
// Environment variable injection
{{ $node["webhook"].json["tenant_code"] }}

// Shell command
TENANT_CODE={{tenant_code}} python src/knowledge_base_indexar.py
```

### RAG Queries

Scope similarity search to professional schema:

```sql
SELECT conteudo, titulo, 
       1 - (embedding <=> $1::vector) as similaridade
FROM profissional_demo.documentos
ORDER BY embedding <=> $1::vector
LIMIT 5;
```

---

## Backwards Compatibility

**Migration from single-tenant:**
- Historical data preserved in `_demo_data` section of knowledge_base.json
- Scripts require explicit tenant specification (no silent defaults)
- Clear error messages guide users to specify tenant_code

**Migration path:**
1. Add professional configuration to `PROFESSIONALS_CONFIG`
2. Generate documents with `PROFESSIONAL_ID` env var
3. Index with `--tenant-code` flag
4. Update n8n workflows to pass tenant_code

---

## Validation & Testing

### Validate Knowledge Base

```bash
python src/knowledge_base_atualizar.py --validate
```

**Checks:**
- Schema version 2.0.0
- All documents have `professional_id`
- No duplicate document IDs
- All active professionals have documents

### Report Stats

```bash
python src/knowledge_base_atualizar.py --report
```

**Output:**
- Total documents
- Documents per professional
- Documents per category
- Active/inactive professional status

---

## Troubleshooting

### Error: "Professional 'xxx' not found"

**Cause:** `professional_id` not in `PROFESSIONALS_CONFIG`  
**Fix:** Add professional config to `src/knowledge_base_atualizar.py`

### Error: "No documents found for professional"

**Cause:** Knowledge base missing documents for that professional  
**Fix:** Run `src/knowledge_base_consultorio.py` with correct `PROFESSIONAL_ID`

### Error: "No tenant specified"

**Cause:** TENANT_CODE not provided  
**Fix:** Use `--tenant-code` flag or set TENANT_CODE environment variable

---

## Next Steps

1. **Add Professional Config:** Edit `PROFESSIONALS_CONFIG` in `src/knowledge_base_atualizar.py`
2. **Generate Documents:** Run `src/knowledge_base_consultorio.py` with PROFESSIONAL_ID
3. **Index Documents:** Run `src/knowledge_base_indexar.py` with --tenant-code
4. **Update n8n:** Configure workflows to pass tenant_code from routing

---

**Questions?** See `.squad/decisions/` for detailed architecture decisions.
