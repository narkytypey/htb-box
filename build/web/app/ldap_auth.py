LDAP_BASE_DN = "dc=donerup,dc=htb"
FILTER_TEMPLATE = "(&(sAMAccountName={username})(info={password}))"


def build_filter(username: str, password: str) -> str:
    return FILTER_TEMPLATE.format(username=username, password=password)


def _single_value(attr):
    """ldap3 hands attributes back as a scalar or a list depending on the
    backend; normalise to one string (or None)."""
    value = getattr(attr, "value", attr)
    if isinstance(value, (list, tuple)):
        value = value[0] if value else None
    return value


def authenticate(conn, username: str, password: str):
    """Authentication-by-search: bind as svc_ldap (conn is already bound),
    search with the filter, and treat a matching entry as success.

    Returns (ok, member_of, account_name). `account_name` is the
    sAMAccountName as the *directory* reports it, never the submitted
    string -- callers must use it for anything user-visible, since the
    submitted value may be an injection payload (spec S4.1).
    """
    filt = build_filter(username, password)
    conn.search(LDAP_BASE_DN, filt, attributes=["memberOf", "sAMAccountName"])
    if not conn.entries:
        return False, [], None
    entry = conn.entries[0]
    member_of = list(entry.memberOf) if "memberOf" in entry else []
    account_name = (
        _single_value(entry.sAMAccountName) if "sAMAccountName" in entry else None
    )
    return True, member_of, account_name


def is_privileged(member_of) -> bool:
    return any("Domain Admins" in dn for dn in member_of)
