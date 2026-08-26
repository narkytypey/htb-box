#!/bin/bash
# Run from the attacker box, over the ligolo tunnel established via
# Plan 2's pivot path, using the svc_ldap credentials discovered through
# Plan 1's CHANGELOG.md migration-hint file.
set -euo pipefail
DC_IP="${1:-10.10.20.10}"
SVC_LDAP_PASSWORD="${2:?usage: check-esc9.sh <dc-ip> <svc_ldap-password>}"

# set -e would otherwise kill the script the instant certipy exits non-zero
# (e.g. DC unreachable/timeout), before the check below ever runs - leaving
# this "check" script silent about why, exactly the failure mode already
# fixed for the SSH and tunnel-DNS checks in the end-to-end plan. Capture the
# exit code instead and report it explicitly.
set +e
certipy find -u svc_ldap -p "$SVC_LDAP_PASSWORD" -dc-ip "$DC_IP" -vulnerable -stdout \
    | tee /tmp/certipy-find.out
CERTIPY_EXIT=${PIPESTATUS[0]}
set -e

if [ "$CERTIPY_EXIT" -ne 0 ]; then
    echo "FAIL: certipy exited $CERTIPY_EXIT before completing enumeration (see /tmp/certipy-find.out)"
    exit 1
fi

if grep -q "ESC9" /tmp/certipy-find.out; then
    echo "PASS: DonerupUserAuth flagged vulnerable to ESC9"
else
    echo "FAIL: certipy did not flag ESC9 - check msPKI-Enrollment-Flag and the Enroll ACL"
    exit 1
fi
