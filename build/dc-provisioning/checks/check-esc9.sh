#!/bin/bash
# Run from the attacker box, over the ligolo tunnel established via
# Plan 2's pivot path, using the svc_ldap credentials discovered through
# Plan 1's CHANGELOG.md migration-hint file.
set -euo pipefail
DC_IP="${1:-10.10.20.10}"
SVC_LDAP_PASSWORD="${2:?usage: check-esc9.sh <dc-ip> <svc_ldap-password>}"

certipy find -u svc_ldap -p "$SVC_LDAP_PASSWORD" -dc-ip "$DC_IP" -vulnerable -stdout \
    | tee /tmp/certipy-find.out

if grep -q "ESC9" /tmp/certipy-find.out; then
    echo "PASS: DonerupUserAuth flagged vulnerable to ESC9"
else
    echo "FAIL: certipy did not flag ESC9 - check msPKI-Enrollment-Flag and the Enroll ACL"
    exit 1
fi
