# Legacy Archive: Dra. Andreia (Single-Tenant)

**Status:** Archived - Original single-tenant implementation  
**Date Archived:** 2026-04-27  
**Superseded By:** Generic multi-tenant workflows in `n8n/`

---

## Contents

This directory contains the **original single-tenant workflows** specific to Dra. Andreia Mota Mussi. These files are preserved for:
- ✅ Historical reference
- ✅ Emergency rollback (if needed)
- ✅ Migration comparison
- ✅ Documentation of original architecture

---

## Files

### Workflows
- `WhatsApp _ Dra. Andreia - Assistente Consultório v1.json` — Original main workflow
- `WhatsApp _ Dra. Andreia - Enviar Lembretes Automáticos.json` — Original reminder workflow
- `n8n-main-original.json` — Original complete export (if available)

### Tools
- `tools/` directory — 9 original tool workflows with hardcoded "Dra. Andreia" prefix

---

## Key Characteristics (Original Architecture)

### Hardcoded Elements
- **Schema name:** `dra_andreia` (70+ references)
- **Webhook path:** `dra-andreia-whatsapp-webhook`
- **Evolution instance:** "Dra Andreia Mota Mussi"
- **AI Prompt:** 400+ lines with clinic-specific details
- **Knowledge base:** Documents prefixed `dra_001_*`

### Limitations
- ❌ Single professional only
- ❌ Requires workflow duplication for new professionals
- ❌ No dynamic configuration
- ❌ Manual prompt updates
- ❌ Hardcoded database queries

---

## Migration to Generic

The current generic architecture addresses these limitations:
- ✅ Multi-tenant support (unlimited professionals)
- ✅ Dynamic schema loading from database
- ✅ Webhook routing by tenant code
- ✅ Database-driven AI configuration
- ✅ Parameterized tool workflows

**See:** `n8n/MIGRATION-GUIDE.md` for complete migration documentation.

---

## Usage

### DO NOT IMPORT to Production
These workflows are for reference only. Use the generic workflows in `n8n/` for all new deployments.

### Emergency Rollback Only
If critical issues occur with generic workflows:
1. Import `WhatsApp _ Dra. Andreia - Assistente Consultório v1.json`
2. Import `WhatsApp _ Dra. Andreia - Enviar Lembretes Automáticos.json`
3. Import all tools from `tools/` directory
4. Update webhook in EvolutionAPI back to: `dra-andreia-whatsapp-webhook`

**Rollback Time:** ~10 minutes  
**Contact:** Lucius (n8n Specialist) for rollback assistance

---

## Historical Context

**Original Deployment:** 2024-2025  
**Client:** Dra. Andreia Mota Mussi (Dentista)  
**Location:** Salvador, Bahia, Brazil  
**Success:** Processed 1000+ patient interactions successfully

This single-tenant implementation proved the concept and business value, leading to the multi-tenant platform initiative.

---

**Preserved by:** Lucius (n8n Workflow Specialist)  
**Archive Date:** 2026-04-27  
**Reason:** Multi-tenant refactoring complete
