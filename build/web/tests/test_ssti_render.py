import pytest

from app.ssti_render import render_report_template


def test_renders_realistic_prose_template():
    result = render_report_template("Hello {{name}}, your report is ready.", {"name": "Alice"})
    assert result == "Hello Alice, your report is ready."


def test_blocks_naive_payload():
    with pytest.raises(ValueError):
        render_report_template("{{ ''.__class__ }}", {})


def test_token_split_bypass_renders_class_object():
    result = render_report_template("{{''['_'~'_cla'~'ss_'~'_']}}", {})
    assert result == "<class 'str'>"


def test_tab_bypass_renders_set_variable():
    result = render_report_template("{%set\tx=1%}{{x}}", {})
    assert result == "1"
