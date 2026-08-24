import re

SSTI_BLACKLIST = [
    "__", "class", "mro", "subclasses", "import",
    "os.", "popen", "system", "eval", "exec", " ",
]

# Blacklist applies only inside {{ ... }} / {% ... %} — not the whole
# document. Scanning the whole raw text would block any template that
# contains a normal sentence, since prose needs spaces.
JINJA_EXPR_RE = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.DOTALL)


def is_blocked(raw_template: str) -> bool:
    for match in JINJA_EXPR_RE.finditer(raw_template):
        fragment = match.group(0)
        if any(token in fragment for token in SSTI_BLACKLIST):
            return True
    return False
