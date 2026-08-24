# Donerup Auth — Migration Changelog

## Legacy MySQL auth (legacy-auth-db) — DEPRECATED

The old `legacy-auth-db` MySQL-backed authentication service is
deprecated. Authentication was migrated to the corporate LDAP
directory; `legacy-auth-db` is kept online only for a handful of
legacy read-only reports and will be decommissioned next quarter.
Do not rely on it for current credentials — its data is stale test
data from before the migration.

Live user authentication is handled entirely through LDAP, using the
`info` attribute as the legacy plaintext-equivalent credential value
carried over from the old `password_md5` column during the one-time
migration script. Bind configuration lives in this container's
environment (`LDAP_BIND_DN` / `LDAP_BIND_PASSWORD` / `LDAP_SERVER_HOST`).
