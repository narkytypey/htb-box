LDAP_BASE_DN = "dc=donerup,dc=htb"
FILTER_TEMPLATE = "(&(sAMAccountName={username})(info={password}))"


def build_filter(username: str, password: str) -> str:
    return FILTER_TEMPLATE.format(username=username, password=password)


def authenticate(conn, username: str, password: str):
    """Authentication-by-search: bind as svc_ldap (conn is already bound),
    search with the filter, and treat a matching entry as success."""
    filt = build_filter(username, password)
    conn.search(LDAP_BASE_DN, filt, attributes=["memberOf", "sAMAccountName"])
    if not conn.entries:
        return False, []
    entry = conn.entries[0]
    member_of = list(entry.memberOf) if "memberOf" in entry else []
    return True, member_of


def is_privileged(member_of) -> bool:
    return any("Domain Admins" in dn for dn in member_of)
