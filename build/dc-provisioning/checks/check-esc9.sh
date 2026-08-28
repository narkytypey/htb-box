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
# /tmp is sticky and Linux's fs.protected_regular blocks an O_CREAT write to
# a file owned by another uid there, so a leftover from a run under a
# different user makes tee fail with EACCES while certipy still prints to
# stdout -- and the grep below would then read the STALE file and report a
# PASS for a run that captured nothing. Clear it first, and treat a capture
# failure as fatal instead of falling through to whatever is on disk.
rm -f /tmp/certipy-find.out

set +e
certipy find -u svc_ldap -p "$SVC_LDAP_PASSWORD" -dc-ip "$DC_IP" -vulnerable -stdout \
    | tee /tmp/certipy-find.out
# PIPESTATUS is rebuilt by every command, a plain assignment included, so
# both elements must be captured in one expansion -- reading ${PIPESTATUS[1]}
# on the next line finds the assignment's own status array instead, and is
# an unbound variable under set -u.
CERTIPY_PIPE=("${PIPESTATUS[@]}")
CERTIPY_EXIT=${CERTIPY_PIPE[0]}
TEE_EXIT=${CERTIPY_PIPE[1]}
set -e

if [ "$TEE_EXIT" -ne 0 ] || [ ! -s /tmp/certipy-find.out ]; then
    echo "FAIL: could not capture certipy output to /tmp/certipy-find.out (tee exit $TEE_EXIT) - refusing to grade this run on a stale file"
    exit 1
fi

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
