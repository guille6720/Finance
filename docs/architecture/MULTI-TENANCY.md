# Multi-tenancy

## Model

Every business record belongs to an `organization`.

Users access orgs through `organization_members` with roles:

`owner` · `admin` · `manager` · `operator` · `accountant` · `viewer`

## Isolation

- **RLS** on all tenant tables (deny by default)
- Helper functions: `is_org_member`, `has_org_role`, `can_mutate_org` (security definer)
- Server layer: `requireOrgContext` / `requireOrgPermission`
- Active org cookie: `active_organization_id`

Frontend filters alone are **never** sufficient.

## Cross-tenant guarantees

| Attempt | Expected |
|---------|----------|
| User A reads org B | 0 rows / 403 |
| User A updates org B | denied |
| Viewer mutates | denied |
| Operator performs owner-only | denied |

See `supabase/tests/rls_isolation.sql` and `tests/integration/tenant-isolation.test.ts`.

## Org switching

`switchOrganization` validates membership before setting the cookie and writes `organization.switched` audit event.
