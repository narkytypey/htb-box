from app.sanitize import sanitize


def test_strips_ascii_metacharacters():
    assert sanitize("a(b)c*d\\e") == "abcde"


def test_converts_fullwidth_parens_to_ascii_after_blacklist():
    assert sanitize("（）＊") == "()*"


def test_normalizes_verified_username_payload():
    raw = "administrator）（|（sAMAccountName=administrator"
    expected = "administrator)(|(sAMAccountName=administrator"
    assert sanitize(raw) == expected


def test_normalizes_verified_password_payload():
    assert sanitize("）") == ")"
