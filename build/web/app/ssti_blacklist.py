SSTI_BLACKLIST = [
    "__", "class", "mro", "subclasses", "import",
    "os.", "popen", "system", "eval", "exec", " ",
]

_OPEN_DELIMS = {"{{": "}}", "{%": "%}"}


def _extract_jinja_fragments(text: str):
    # Blacklist applies only inside {{ ... }} / {% ... %} -- not the whole
    # document. Scanning the whole raw text would block any template that
    # contains a normal sentence, since prose needs spaces.
    #
    # A plain non-greedy regex (`\{\{.*?\}\}`) stops at the *first* literal
    # "}}", including one that appears inside a quoted string inside the
    # expression -- e.g. {{("}}"~"").__class__...}} scans as the harmless
    # fragment {{("}} and the real payload after it is never blacklist-
    # checked. Walk the string by hand and skip over quoted spans so the
    # fragment boundary matches what Jinja's own lexer would parse.
    fragments = []
    i, n = 0, len(text)
    while i < n:
        starts = [(text.find(d, i), d) for d in _OPEN_DELIMS if text.find(d, i) != -1]
        if not starts:
            break
        start, open_delim = min(starts, key=lambda pair: pair[0])
        close_delim = _OPEN_DELIMS[open_delim]
        j = start + 2
        quote = None
        while j < n:
            ch = text[j]
            if quote:
                if ch == "\\":
                    j += 2
                    continue
                if ch == quote:
                    quote = None
            elif ch in ("'", '"'):
                quote = ch
            elif text[j:j + 2] == close_delim:
                j += 2
                break
            j += 1
        fragments.append(text[start:j])
        i = j
    return fragments


def is_blocked(raw_template: str) -> bool:
    for fragment in _extract_jinja_fragments(raw_template):
        if any(token in fragment for token in SSTI_BLACKLIST):
            return True
    return False
