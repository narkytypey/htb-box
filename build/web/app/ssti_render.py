from jinja2 import Environment

from .ssti_blacklist import is_blocked


def render_report_template(raw_template: str, context: dict) -> str:
    if is_blocked(raw_template):
        raise ValueError("blocked pattern detected")
    env = Environment()
    template = env.from_string(raw_template)
    return template.render(**context)
