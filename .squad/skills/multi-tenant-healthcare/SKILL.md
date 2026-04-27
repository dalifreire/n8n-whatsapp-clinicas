# SKILL: Multi-Tenant Healthcare Platform Architecture

**Category:** Architecture Pattern  
**Domain:** Healthcare SaaS, Data Isolation  
**Extracted from:** Generic Clinic Assistant Platform pivot  
**Author:** Bruce (Lead Architect)  
**Date:** 2026-04-27  

---

## Pattern Description

**Problem:** Building a multi-tenant SaaS platform for healthcare professionals where each tenant requires strong data isolation for regulatory compliance (HIPAA, LGPD, GDPR).

**Solution:** Schema-per-tenant isolation in PostgreSQL with dynamic query routing through shared application layer.

---

## When to Use

✅ **Use this pattern when:**
- Building healthcare/medical SaaS platforms
- Regulatory compliance requires strict data isolation
- Each tenant has similar schema structure but isolated data
- Tenant count < 1000 (schema limits)
- Need independent tenant backups/restores
- Performance isolation important (noisy neighbor problem)

❌ **Don't use when:**
- Tenant count > 10,000+ (schema proliferation)
- Tenants share data frequently (cross-tenant queries needed)
- Schema changes are very frequent (N migrations = complexity)
- Non-sensitive data with relaxed compliance requirements

---

## Architecture Components

### 1. Platform Schema (Shared Metadata)
```sql
CREATE SCHEMA platform;

CREATE TABLE platform.tenants (
  id UUID PRIMARY KEY,
  name VARCHAR(255),
  slug VARCHAR(100) UNIQUE,
  schema_name VARCHAR(100) UNIQUE,
  active BOOLEAN DEFAULT true,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 2. Tenant Schema Template (Isolated Data)
```sql
CREATE SCHEMA tenant_abc123;

CREATE TABLE tenant_abc123.users (
  id BIGSERIAL PRIMARY KEY,
  email VARCHAR(255),
  data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 3. Dynamic Query Routing (Application Layer)
```javascript
const tenant = await db.query(`
  SELECT schema_name FROM platform.tenants 
  WHERE slug = $1 AND active = true
`, [tenantSlug]);

await db.query(`
  SELECT * FROM ${tenant.schema_name}.users WHERE email = $1
`, [email]);
```

---

## Key Decision: Schema-per-tenant vs Row-level

**Recommendation:** Use **schema-per-tenant** for healthcare due to compliance/isolation needs.

| Aspect              | Schema-per-tenant            | Row-level (single schema)          |
|---------------------|------------------------------|------------------------------------|
| **Isolation**       | ✅ Strong (schema boundary)  | ⚠️  Weaker (application logic)     |
| **Compliance**      | ✅ Easier to audit           | ⚠️  Complex audit trails           |
| **Performance**     | ✅ Isolated (no cross-impact)| ⚠️  Noisy neighbor risk            |
| **Scaling**         | ⚠️  Limited by schema count  | ✅ Unlimited tenants               |

---

## References

- [PostgreSQL Multi-tenancy Best Practices](https://www.postgresql.org/docs/current/ddl-schemas.html)
- HIPAA Compliance: "minimum necessary" principle → schema isolation preferred

---

**Full documentation:** See extended version in project wiki for implementation details, testing strategy, and common pitfalls.
