from flask import Flask, request, session, redirect, url_for

from .sanitize import sanitize
from .ldap_auth import authenticate, is_privileged


def create_app(ldap_connection_factory, secret_key="dev-only-not-for-prod"):
    app = Flask(__name__)
    app.config["SECRET_KEY"] = secret_key
    app.config["LDAP_CONNECTION_FACTORY"] = ldap_connection_factory

    @app.route("/login", methods=["GET"])
    def login_form():
        return (
            '<form method="post" action="/login">'
            '<input name="username">'
            '<input name="password" type="password">'
            '<button type="submit">Sign in</button></form>'
        )

    @app.route("/login", methods=["POST"])
    def login():
        raw_username = request.form.get("username", "")
        raw_password = request.form.get("password", "")
        username = sanitize(raw_username)
        password = sanitize(raw_password)

        conn = app.config["LDAP_CONNECTION_FACTORY"]()
        ok, member_of = authenticate(conn, username, password)
        if not ok:
            return "Invalid credentials", 401

        session["username"] = username
        session["is_privileged"] = is_privileged(member_of)
        return redirect(url_for("dashboard"))

    @app.route("/dashboard")
    def dashboard():
        if "username" not in session:
            return redirect(url_for("login_form"))
        return f"Welcome, {session['username']}"

    return app
