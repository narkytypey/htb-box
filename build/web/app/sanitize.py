ASCII_BLACKLIST = ["(", ")", "*", "\\", "\x00"]

FULLWIDTH_MAP = str.maketrans({
    "（": "(",  # FULLWIDTH LEFT PARENTHESIS
    "）": ")",  # FULLWIDTH RIGHT PARENTHESIS
    "＊": "*",  # FULLWIDTH ASTERISK
})


def sanitize(raw: str) -> str:
    cleaned = raw
    for ch in ASCII_BLACKLIST:
        cleaned = cleaned.replace(ch, "")
    return cleaned.translate(FULLWIDTH_MAP)
