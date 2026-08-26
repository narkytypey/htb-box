# Donerup — Portal Skin Design

Date: 2026-08-27
Status: approved, ready for implementation planning
Scope: `build/web/app/` presentation layer only

## Problem

`donerup-htb-insane-design-v2.md` §3 names the player-facing application
"Donerup Enterprise SSO" and calls for a "corporate LDAP directory"
reference in the login page. Neither exists. Every route in
`build/web/app/webapp.py` returns an inline HTML string: the login page is
a bare three-element form, `dashboard` returns the literal text
`Welcome, {username}`, and the admin panel is a naked `<textarea>`. There
are no templates, no stylesheet, and no branding anywhere in the build.

Two consequences:

1. **The portal illusion never forms.** A player who works the LDAP
   injection lands on unstyled text at the exact moment of foothold.
2. **Step 1 is guesswork.** With no LDAP reference on the login page,
   nothing points toward the directory theme, violating the spec's own §1
   principle *"Guessing yok"* — every step must be derivable from the
   previous one by enumeration.

## Non-goals

- TLS, ports 80/443, and the nginx proxy. That work landed separately in
  `build/proxy/`; this design consumes it and changes nothing about it.
- Any change to the exploit chain's behavior. See "Exploit contract" below.
- JavaScript, binary assets, or a build pipeline.

## Approach

Replace the inline HTML strings with real Jinja templates plus one
stylesheet.

`create_app` calls `Flask(__name__)` where `__name__` is `app.webapp`, so
`app/templates/` and `app/static/` resolve automatically, and the web
Dockerfile's existing `COPY app/ ./app/` ships both. **No Dockerfile,
compose, requirements, or proxy change is required.** The proxy's
`location /` is a blanket `proxy_pass`, so `/static/css/portal.css` is
reachable through it without configuration.

Two alternatives were considered and rejected:

- **A `layout()` string-wrapper helper.** Smaller diff, but HTML by string
  concatenation is the pattern that left the app bare in the first place,
  and it keeps markup tangled with control flow.
- **A full frontend** with logo assets and JS. YAGNI — nothing in the chain
  needs it, and binary assets bloat a repo whose value is the exploit path.

## File layout

```
build/web/app/
  templates/
    base.html              layout: wordmark, chrome, footer, {% block %}
    login.html             sign-in card + error state
    dashboard.html         signed-in landing
    report_template.html   report editor + render result
  static/css/portal.css    single stylesheet
```

## Pages

- **base.html** — "Donerup Enterprise SSO" wordmark, muted corporate
  palette, shared footer. All pages extend it.
- **login.html** — centred sign-in card. The `<form>` keeps
  `action="/login"`, `method="post"`, and the field names `username` and
  `password` exactly. Footer carries the §3 hint:

  > Authentication provided by Donerup Corporate Directory (LDAP) ·
  > Contact the IT Service Desk for access.

  This is set dressing a real portal would carry. It seeds the directory
  theme without naming the vulnerable field or the technique, preserving
  the Insane difficulty rating §4.1 depends on.
- **dashboard.html** — `Welcome, {{ username }}` inside the layout. Jinja
  autoescaping covers the account-name escaping requirement.
- **report_template.html** — `<textarea name="template">`, a result panel
  rendering `{{ rendered|safe }}` on POST, and a "Blocked pattern detected"
  error state on the 400 path.
- **The 403 path is skinned too.** A non-privileged user reaching
  `/admin/report-template` currently gets the bare string `Forbidden`. It
  renders inside the layout as an access-denied notice instead — it is a
  page players reach on the normal path, and leaving it bare would break
  the illusion in the same way the dashboard did. The 403 status is
  unchanged; only the body is.

## Exploit contract

The skin is cosmetic. These are frozen:

- Route paths and methods: `GET|POST /login`, `GET /dashboard`,
  `GET|POST /admin/report-template`.
- Form field names: `username`, `password`, `template`.
- Status codes: 401 invalid credentials, 403 non-privileged, 400 blocked
  pattern, 200 render.
- **SSTI output stays raw via `|safe`.** Escaping it would make
  `<class 'str'>` visible in a browser instead of being swallowed as an
  unknown tag — nicer to look at, but it changes the payload's output
  bytes and breaks the `class 'str'` assertion in both the unit test and
  the integration smoke test. A cosmetic pass must not shift what the
  verified chain returns, least of all for a step the verification record
  says has never run against a real DC. Players hit this panel through
  curl and Burp far more than a browser.
- **The failed-login page does not echo the submitted username.** A real
  portal would repopulate the field, but on the intended path the
  submitted value *is* the injection payload; repopulating it would create
  exactly the reflection sink
  `test_dashboard_never_echoes_the_injection_payload` exists to prevent.
  Fidelity loses to the chain here, deliberately.
- Templates must use path-relative `url_for`. Do not set `SERVER_NAME` or
  generate absolute URLs — behind the TLS proxy those would emit `http://`
  locations into an HTTPS session.

## Test changes

One assertion changes. In `test_dashboard_never_echoes_the_injection_payload`,
the layout appends closing markup after the greeting, so
`resp.data.rstrip().endswith(b"Welcome, administrator")` can no longer
hold. Replace that single line with:

```python
assert b"Welcome, administrator" in resp.data
assert "administrator）（|（sAMAccountName=administrator".encode() not in resp.data
```

The existing fragment loop stays. This sharpens the test's intent — the
complete payload is now asserted absent, not merely four fragments of it —
rather than loosening it.

No other test changes. `test_login_page_seeds_the_ldap_theme` is already
present and currently red; the login footer turns it green, and its
giveaway list (`inject`, `fullwidth`, `full-width`, `bypass`, `sanitiz`)
constrains the hint's wording. `integration_smoke.py` already asserts the
login page contains `ldap`; the same footer satisfies it. Both are written
to, not modified.

## Verification

1. `pytest` green in `build/web/`, including the currently-red hint test.
2. `integration_smoke.py` green against the running stack through the
   proxy at `https://localhost`.
