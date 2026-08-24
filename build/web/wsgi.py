import os

from app.ldap_connection import get_ldap_connection_factory
from app.webapp import create_app

app = create_app(
    ldap_connection_factory=get_ldap_connection_factory(),
    secret_key=os.environ.get("FLASK_SECRET_KEY", "dev-only-not-for-prod"),
)
