# Donerup — Insane-Depth Design (web-hop SSRF + AD-hop ESC8)

Date: 2026-08-28
Status: approved, ready for implementation planning
Scope: `build/web/app/` (new route + gate change), `build/dc-provisioning/`
(new script), `build/exploit/` (new/updated check scripts), `docs/donerup-writeup.md`
(follow-up once built — not part of this spec's implementation)

## Problem

Donerup's chain currently has two hops — web container, then the DC — each
carrying exactly one bug: LDAP injection gets an app-admin session, SSTI off
that session gets RCE; ESC9 (`NoSecurityExtension`) chained through
`GenericWrite`/Shadow Credentials is the only route to Domain Admin. Compared
against a real, currently-live Insane HTB machine (**Odyssey**), which stacks
two distinct bug classes in its web tier alone (NoSQL injection, then
prototype-pollution-driven RCE) before ever leaving the web host, Donerup's
two hops each read as a single well-executed idea rather than a chain — thin
for Insane by that yardstick.

The user confirmed the hop *count* should stay at two (no new hosts/VMs); the
depth *within* each hop should go up instead. Two decisions came out of
brainstorming:

1. **Web hop:** insert a second, distinct bug class between the LDAP
   injection and the SSTI — an app-admin session alone should not be enough
   to reach the SSTI-vulnerable endpoint.
2. **AD hop:** add ESC8 (coercion + NTLM relay to AD CS Web Enrollment) as a
   fully independent, parallel route to Domain Admin, alongside the existing
   ESC9 chain — not gating it, a second road to the same destination.

## Non-goals

- No new hosts, VMs, or Docker services. Both changes live inside the
  existing `web` container and the existing `DC01`/`Donerup-CA`.
- No dependency on Windows Server 2025 (that upgrade is separately blocked
  on the user sourcing licensed installation media — see
  `donerup_htb_machine_submission_compliance` project memory). Both new
  techniques must work against the current Server 2022 DC.
- No change to the LDAP injection mechanic itself, the ESC9/GenericWrite/
  Shadow-Credentials mechanics, DCSync, flag placement/permissions, or the
  network firewall's intended security boundary (VPN subnet still never
  reaches the AD VLAN directly).
- Difficulty rating stays Insane; this work raises depth within that rating,
  it does not retarget the box.

## Approach A — Web hop: SSRF between LDAP injection and SSTI

### New feature: Report Branding (the SSRF vector)

A new admin-panel feature, `POST /admin/branding`, accepting a standard
HTML form field `logo_url` — matching the plain-form style the rest of the
app already uses (`login.html`, `report_template.html`), not a JSON API.
On submit the server fetches that URL with `requests`
(already a pinned dependency — `build/web/requirements.txt`) to validate it
resolves to an image, for use as report letterhead. Two things make this
genuinely SSRF rather than a cosmetic feature:

- **No target validation.** No scheme allowlist beyond `http(s)`, no block
  on loopback/private/link-local ranges. This is the actual bug — a
  realistic "we only ever expected marketing to paste a CDN URL here"
  oversight.
- **Response-body leak on validation failure.** If the fetched
  `Content-Type` doesn't start with `image/`, the error response includes a
  truncated snippet (first ~1000 bytes) of the fetched body and the HTTP
  status code — "logo fetch failed: received `<snippet>`". This is the
  classic real-world pattern (an image-preview fetcher that's "helpful" in
  its error message) that turns blind SSRF into a readable one. Fetch must
  use a short timeout and a capped read size (`stream=True`, read only the
  first N bytes) so a slow/huge internal response can't hang or bloat the
  request — ties into the "avoid unstable elements" HTB best practice.
- New module: `build/web/app/branding.py` (mirrors the existing
  one-concern-per-module layout: `ldap_auth.py`, `ssti_render.py`, etc.),
  wired into `webapp.py` as a new route.

### Gate change: `/admin/report-template` becomes loopback-only

`build/web/app/webapp.py`'s `report_template()` currently gates on
`session.get("is_privileged")` (an app-role check sourced from the LDAP
directory's `memberOf`, per `ldap_auth.is_privileged`). That check is
**removed** and replaced with:

```python
if request.remote_addr not in ("127.0.0.1", "::1"):
    return "Forbidden: internal use only", 403
```

Deliberately reads `request.remote_addr` (Werkzeug's actual TCP peer
address) and **not** any `X-Forwarded-For`-style header — trusting a
forwarded header would make this a one-line `curl -H` bypass instead of a
real SSRF, undermining the whole point of the new bug class. Real player
traffic always arrives via the `proxy` container, so `remote_addr` is never
`127.0.0.1` for it; only a request the Flask/gunicorn process makes to
*itself* satisfies the check.

The template-content parameter changes from `request.form.get("template")`
to `request.values.get("template")` (Flask's combined args+form accessor) so
the same code path accepts the payload as a `POST` form field (the
still-existing direct-browser UI, now only reachable from loopback for
debugging) or a `GET` query string (what a `requests.get()`-based SSRF fetch
can forge). No other change to `ssti_render.py` / `ssti_blacklist.py` — the
SSTI mechanic and its blacklist-bypass are unchanged.

### Discoverability (staying inside the "Guessing yok" rule)

The admin panel keeps a visible link to Report Template (it's real existing
functionality, not deleted) alongside the new Report Branding feature.
Clicking it externally now returns the 403 above instead of the report
editor. That 403 is the derivable signal: the player already knows (from
having broken auth via LDAP injection) that this app has exploitable
assumptions, and "internal use only" next to a *separate* feature that
fetches arbitrary URLs is the natural next thing to connect. This uses no
new hint channel (no `CHANGELOG.md` change) — deliberately, since
`CHANGELOG.md` only becomes reachable *after* RCE, and the report-template
gate has to be discoverable *before* RCE, chronologically earlier in the
chain.

### Chain walk

1. LDAP injection → app-admin session (unchanged).
2. Admin panel → visit Report Template directly → `403 Forbidden: internal
   use only`. Signals a network-position requirement, not a role
   requirement.
3. Admin panel → Report Branding → submit `logo_url =
   http://127.0.0.1:5000/admin/report-template?template=<SSTI payload>`.
4. Server-side fetch runs from the Flask process itself → satisfies the
   loopback check → the SSTI blacklist-bypass payload executes exactly as
   documented in `docs/donerup-writeup.md` §3 today → command output lands
   in the branding endpoint's non-image response body.
5. Branding's "logo fetch failed" error reflects that body back to the
   attacker — readable (if noisy) command output.

## Approach B — AD hop: ESC8 as a parallel path to Domain Admin

### New DC role: AD CS Web Enrollment

`build/dc-provisioning/` gets a new script, `07-install-web-enrollment.ps1`,
run after `04-install-adcs-esc9.ps1` (the CA must exist first):

```powershell
Install-WindowsFeature Adcs-Web-Enrollment -IncludeManagementTools
Install-AdcsWebEnrollment -Force
```

Same idempotency pattern as `04`/`05` (check-then-act, safe to re-run). No
Extended Protection for Authentication (EPA) is configured — that omission
*is* the vulnerability, and it's the default state after this install, so no
active "weakening" step is needed the way `05-weaken-cert-binding.ps1` had
to explicitly lower `StrongCertificateBindingEnforcement`. Same DC, same CA
(`Donerup-CA`) already built by `04` — no new machine.

### Chain: coercion → relay → enrol as `DC01$` → PKINIT → DCSync

Uses the already-discovered `svc_ldap` credential (from the `CHANGELOG.md`
hint, per the existing chain — no new credential to find):

1. From the AD VLAN foothold (post-ligolo-pivot, same position the existing
   ESC9 chain starts from), authenticate an MS-EFSRPC coercion call
   (PetitPotam) as `svc_ldap` against `DC01`, forcing the DC's machine
   account (`DC01$`) to open an outbound SMB/HTTP authentication attempt
   toward an attacker-controlled listener.
2. Relay that captured NTLM authentication live to `Donerup-CA`'s HTTP
   enrollment endpoint (`certsrv`) using `ntlmrelayx.py -t
   http://dc01.donerup.htb/certsrv/certfnsh.asp --adcs -c
   DonerupUserAuth`-equivalent (or the default machine-auth template if
   `DonerupUserAuth` requires a UPN the relay session doesn't have — this
   needs empirical confirmation during implementation, see Risks below).
   The relayed session enrolls a certificate *as* `DC01$`.
3. `certipy auth -pfx dc01.pfx -dc-ip <DC_IP>` PKINITs as `DC01$` — a
   domain controller's machine account inherently holds replication rights,
   so the resulting TGT/NT hash goes straight to DCSync. No
   `GenericWrite`/Shadow-Credentials/UPN-swap step is used on this path —
   it's a fully independent route to the same `Administrator` secrets and
   `root.txt`.

### Verification artifact

New script `build/exploit/run-esc8-check.sh`, following the same pattern as
the existing `build/exploit/run-esc10-check.sh` (a real, runnable check
against the live DC — not a "manual instructions" placeholder, per the
lesson already learned once on ESC10). `full-chain-replay.sh` gets a new
phase invoking it, reported alongside the existing ESC9/DCSync phase as an
independent PASS/FAIL, not a gate on any other phase.

## Risks / open questions (for the implementation plan, not resolved here)

- **Firewall path for the coercion callback.** `DONERUP_AD_PIVOT`'s rule 3
  only `ACCEPT`s `AD_VLAN_SUBNET → INTERNAL_AD_SUBNET` traffic that is
  `ESTABLISHED,RELATED` — i.e. responses to connections the container
  initiated. A coercion-triggered callback is a **new** connection
  initiated *by* `DC01` outbound. Whether that traffic reaches an
  attacker-controlled listener (wherever it's placed — inside the `web`
  container, or via the attacker's own ligolo-tunnel presence) depends on
  exactly how that new-connection traffic is classified by the current
  chain and Docker's own `DOCKER-USER`/`FORWARD` defaults. This needs
  empirical verification against the live lab (same "closed empirically,
  not inferred" standard the rest of this box's AD work has used) — it may
  need an additional firewall rule permitting that specific new-connection
  direction, scoped as narrowly as the existing four rules are.
- **Coercion patch level.** Whether PetitPotam's authenticated form still
  works against this DC's current patch level needs a live check;
  unauthenticated coercion is not assumed available.
- **Template selection for the relayed enrollment.** `DonerupUserAuth`
  requires `SubjectAltRequireUpn` (per `04-install-adcs-esc9.ps1`); a
  machine-account NTLM relay session may not carry a UPN the same way a
  user session does. The relay may need to target the CA's default machine
  template instead of `DonerupUserAuth` — confirm which template the
  relayed enrollment actually needs during implementation; either is
  consistent with this design (the ESC8 exposure is the *Web Enrollment
  endpoint itself* lacking EPA, not the specific template).

## File-level change summary

| File | Change |
|---|---|
| `build/web/app/branding.py` | **New.** SSRF-vulnerable logo-URL fetcher. |
| `build/web/app/webapp.py` | New `/admin/branding` route; `report_template()` gate swapped from session role to loopback-only; `template` param read via `request.values`. |
| `build/web/app/templates/` | New branding UI fragment; admin nav updated to link both features. |
| `build/dc-provisioning/07-install-web-enrollment.ps1` | **New.** Installs AD CS Web Enrollment role. |
| `build/exploit/run-esc8-check.sh` | **New.** Live coercion→relay→PKINIT→DCSync check. |
| `build/exploit/full-chain-replay.sh` | New phase invoking the ESC8 check, reported independently. |
| `docs/donerup-writeup.md` | **Not in this spec** — updated once both paths are built and verified, so the writeup reflects what was actually run, not what was planned. |

## Testing

- Unit-level: `build/web/tests/` gets coverage for (a) the loopback gate
  rejecting a non-loopback `remote_addr` and accepting `127.0.0.1`, (b) the
  branding fetcher's missing-image-content-type error path including the
  response snippet, (c) `report_template()` still accepting `template` via
  query string.
- Integration: `full-chain-replay.sh` extended to drive the SSRF step
  end-to-end (branding → loopback fetch → SSTI payload → RCE) in place of
  the current direct-POST step, plus the new independent ESC8 phase.
- Both new checks must go **green against the live lab**, not just pass
  unit tests — consistent with how every other claim in this box's AD work
  has been verified (see `donerup_lab_environment_state` project memory:
  "closed empirically, not inferred").
