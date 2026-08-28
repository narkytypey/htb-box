#!/bin/sh
set -e

if [ ! -f /home/appuser/user.txt ]; then
    python3 -c "import secrets; print(secrets.token_hex(16))" > /home/appuser/user.txt
    chmod 400 /home/appuser/user.txt
    chown appuser:appuser /home/appuser/user.txt
fi

# Session signing key. Compose deliberately pins none (see the comment
# there): the RCE foothold exposes this process's environment, so any
# constant key would be one `env` away from a forged is_privileged
# session -- a shortcut straight past the LDAP injection the box is built
# around. A fresh key per container start costs only that logged-in
# sessions do not survive a restart, which for a box is the right trade.
if [ -z "${FLASK_SECRET_KEY:-}" ] || [ "$FLASK_SECRET_KEY" = "dev-only-not-for-prod" ]; then
    FLASK_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
    export FLASK_SECRET_KEY
fi

# The app needs this route for its own LDAP bind once real-LDAP mode is
# active (Plan 3) -- it is not added specifically to enable a pivot tool, though
# a pivot tool riding inside the container uses the same kernel route.
#
# AD_VLAN_SUBNET / INTERNAL_AD_SUBNET / INTERNAL_AD_GATEWAY_IP come in via
# compose from network/config.env -- nothing is hardcoded here.
#
# Which NIC (eth0/eth1/...) Compose attaches "internal-ad" to is not a
# documented contract and is not assumed here. Instead, find the
# interface that owns the internal-ad subnet by matching the kernel's
# own link-scope route table against INTERNAL_AD_SUBNET.
ad_vlan_iface=$(ip -4 -o route list scope link | awk -v subnet="$INTERNAL_AD_SUBNET" '$1 == subnet { print $3; exit }')

if ip route show "$AD_VLAN_SUBNET" | grep -q .; then
    : # route already present, nothing to do
elif [ -n "$ad_vlan_iface" ] && ip route add "$AD_VLAN_SUBNET" via "$INTERNAL_AD_GATEWAY_IP" dev "$ad_vlan_iface"; then
    : # route added successfully
else
    echo "WARN: failed to add AD VLAN route to $AD_VLAN_SUBNET via $INTERNAL_AD_GATEWAY_IP dev ${ad_vlan_iface:-<unresolved>}" >&2
fi

exec gosu appuser "$@"
