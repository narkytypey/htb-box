# Donerup IT — Migration Changelog

## Legacy till auth (`legacy-auth-db`) — DEPRECATED

Before the franchise consolidation, every Donerup shop ran its own
MySQL-backed login for the till/POS system — one `users` table per
location, plain `password_md5` column, no directory integration at
all. `legacy-auth-db` is what's left of that: kept online only for a
handful of legacy read-only shift reports, and slated for
decommission next quarter. Don't rely on it for current credentials —
its data is stale test data from before the corporate rollout, not
anything a real employee still uses.

Staff authentication for everything that matters now goes through the
corporate LDAP directory. The one-time migration script carried each
shop's old `password_md5` value forward as-is into the `info`
attribute on the matching directory account — a stopgap, not a
redesign, so treat `info` as the legacy plaintext-equivalent
credential until the real password-reset rollout reaches this region.
Bind configuration for the directory lives in this container's
environment (`LDAP_BIND_DN` / `LDAP_BIND_PASSWORD` / `LDAP_SERVER_HOST`).
