import requests
from flask import Flask, render_template, request, session, redirect, url_for

from .sanitize import sanitize
from .ldap_auth import authenticate, is_privileged
from .ssti_render import render_report_template
from .branding import LogoFetchError, fetch_logo_preview


def create_app(ldap_connection_factory, secret_key="dev-only-not-for-prod", http_get=requests.get):
    app = Flask(__name__)
    app.config["SECRET_KEY"] = secret_key
    app.config["LDAP_CONNECTION_FACTORY"] = ldap_connection_factory
    app.config["HTTP_GET"] = http_get

    @app.route("/login", methods=["GET"])
    def login_form():
        # Spec S3: seed the LDAP theme here so the first step is derivable by
        # enumeration rather than guessed (S1, "Guessing yok"). Deliberately
        # a *theme* hint only -- it names the directory backend, never the
        # vulnerable field or the sanitiser weakness, which is what keeps
        # S4.1's Insane rating intact. See templates/login.html.
        return render_template("login.html")

    @app.route("/login", methods=["POST"])
    def login():
        raw_username = request.form.get("username", "")
        raw_password = request.form.get("password", "")
        username = sanitize(raw_username)
        password = sanitize(raw_password)

        conn = app.config["LDAP_CONNECTION_FACTORY"]()
        ok, member_of, account_name = authenticate(conn, username, password)
        if not ok:
            return "Invalid credentials", 401

        # Store what the directory resolved to, not what was submitted -- on
        # the intended injection path the submitted value IS the payload, and
        # echoing it back would both break the portal illusion and reflect
        # attacker input into the response (spec S4.1).
        session["username"] = account_name or "unknown"
        session["is_privileged"] = is_privileged(member_of)
        return redirect(url_for("dashboard"))

    @app.route("/dashboard")
    def dashboard():
        if "username" not in session:
            return redirect(url_for("login_form"))
        # dashboard.html renders standalone (no base.html) and deliberately
        # ends the response body right after the account name -- see the
        # comment in that template for why nothing may follow it.
        return render_template("dashboard.html", account_name=session["username"])

    @app.route("/admin/report-template", methods=["GET", "POST"])
    def report_template():
        # This used to gate on session["is_privileged"]. The real story
        # now (spec docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
        # Approach A): a nightly batch job renders ops-requested report
        # templates by calling this route locally, so nobody ever added
        # session auth to it -- it is internal-only by IP instead.
        # request.remote_addr is Werkzeug's actual TCP peer address; it
        # deliberately never trusts X-Forwarded-For, or a header would
        # forge this check trivially instead of requiring real SSRF.
        # (Proven by test_report_template_ignores_a_forged_x_forwarded_for_header.)
        if request.remote_addr not in ("127.0.0.1", "::1"):
            return render_template("forbidden.html"), 403
        raw_template = request.values.get("template")
        if raw_template is None:
            return render_template("report_template.html")
        try:
            rendered = render_report_template(raw_template, {})
        except ValueError:
            return "Blocked pattern detected", 400
        return rendered

    @app.route("/admin/branding", methods=["GET", "POST"])
    def branding():
        if not session.get("is_privileged"):
            return "Forbidden", 403
        if request.method == "GET":
            return render_template("branding.html")
        logo_url = request.form.get("logo_url", "")
        try:
            fetch_logo_preview(logo_url, app.config["HTTP_GET"])
        except LogoFetchError as exc:
            return (
                f"Logo fetch failed: received (status {exc.status_code}): {exc.snippet}",
                400,
            )
        except requests.RequestException as exc:
            return f"Logo fetch failed: {exc}", 400
        return render_template("branding.html", success=True)

    return app
