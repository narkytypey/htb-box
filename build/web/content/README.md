# Donerup Store Portal

Portal build 2026.2.4. Owned by IT Operations (Merve Kaya, EMP-1004).

The portal is the single sign-on front end for store reporting. It runs as
a container behind the corporate TLS proxy and resolves all staff
credentials against the corporate directory. Nothing is stored locally.

## Contents of this directory

- `docs/store-ops-runbook.md` - how store managers file shift reports
- `tickets/` - exported service desk tickets kept with the deployment for
  context on outstanding issues
- `data/stores.csv` - the store list the portal renders on the dashboard

## Support

Access requests and password problems go to the IT Service Desk. Do not
raise them against this repository - directory accounts are not managed
here.
