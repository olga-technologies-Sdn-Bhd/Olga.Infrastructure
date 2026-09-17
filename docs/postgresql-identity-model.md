# PostgreSQL identity model

## Authorization boundaries

Azure RBAC and PostgreSQL roles are independent. Azure RBAC on a Key Vault secret determines which managed identity can retrieve connection material. PostgreSQL grants determine what the resulting database login may do.

Azure Database for PostgreSQL Flexible Server does not expose the real PostgreSQL `SUPERUSER` attribute. Do not issue `ALTER ROLE ... SUPERUSER`. `olga_migration_admin` remains the Flexible Server administrator and must receive the maximum administrator capabilities Azure supports plus ownership-based control of every OLGA database object.

## Required database state

The database repository remains the source of truth for these existing `NOLOGIN` permission roles:

- `olga_ddl_admin`
- `olga_dml_writer`
- `olga_reader`

Its migration/bootstrap image must ensure:

```sql
GRANT olga_ddl_admin, olga_dml_writer, olga_reader
TO olga_migration_admin
WITH ADMIN OPTION;
```

`olga_ddl_admin` must own every OLGA schema, table, sequence, view, function, and procedure. Default privileges and ownership-transfer migrations must preserve that rule for newly created objects. Through Azure administrator capabilities, role membership administration, and ownership, `olga_migration_admin` must be able to create, alter, drop, select, insert, update, delete, execute, grant, and revoke throughout the OLGA database. Do not revoke OLGA privileges from it.

The migration image receives the administrator connection in `OLGA_POSTGRES_CONNECTION_STRING`, and the Terraform-managed DML login values in `OLGA_DML_USERNAME` and `OLGA_DML_PASSWORD`. Without logging either value, it must:

1. Create `olga_dml_user` with `LOGIN` when absent.
2. Update its password on every run through a parameter-safe mechanism so Terraform password rotation converges.
3. grant `olga_dml_writer` to `olga_dml_user`;
4. ensure it has `NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS`;
5. never grant `olga_ddl_admin`, `olga_reader`, Azure administrator permissions, or membership administration rights.

Role creation, object ownership, grants, default privileges, and password rotation must be idempotent. Terraform intentionally does not run SQL or duplicate the permission-role definitions.

## Secret and service mapping

| Consumer | Key Vault secret | PostgreSQL login |
| --- | --- | --- |
| Database migration job | `postgresql-migration-connection` | `olga_migration_admin` |
| Core API | `postgresql-dml-connection` | `olga_dml_user` |
| NLP API | `postgresql-dml-connection` | `olga_dml_user` |
| Applicable workers | `postgresql-dml-connection` | `olga_dml_user` |

The migration managed identity can additionally read the bootstrap-only `postgresql-dml-username` and `postgresql-dml-password` secrets. Runtime identities cannot read those secrets or the migration connection.

Development and production use different state files, PostgreSQL servers, Key Vaults, generated passwords, secrets, and identities. Never copy a secret version or Terraform state value between environments.
