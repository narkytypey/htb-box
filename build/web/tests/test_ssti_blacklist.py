from app.ssti_blacklist import is_blocked


def test_realistic_prose_template_is_not_blocked():
    assert is_blocked("Hello {{name}}, your report is ready.") is False


def test_naive_dunder_class_access_is_blocked():
    assert is_blocked("{{ ''.__class__ }}") is True


def test_token_split_bypass_is_not_blocked():
    assert is_blocked("{{''['_'~'_cla'~'ss_'~'_']}}") is False


def test_tab_bypasses_space_ban_in_set_statement():
    assert is_blocked("{%set\tx=1%}{{x}}") is False


def test_literal_space_inside_expression_is_blocked():
    assert is_blocked("{% set x = 1 %}{{x}}") is True
