"""SSRF-vulnerable logo fetcher for the Report Branding admin feature.

Deliberately has no target allowlist (no scheme restriction beyond what
`requests` itself requires, no block on loopback/private/link-local
ranges) and deliberately leaks a snippet of any non-image response body
back to the caller on failure -- this is the intentional bug. See
docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
Approach A, for the design rationale.
"""

MAX_PREVIEW_BYTES = 1000
FETCH_TIMEOUT_SECONDS = 5


class LogoFetchError(Exception):
    """Raised when the fetched URL's response doesn't look like an image.
    Carries the fetched status code and a body snippet -- the deliberate
    leak channel a caller (the /admin/branding route) surfaces to the
    admin in its own error response."""

    def __init__(self, status_code: int, snippet: str):
        self.status_code = status_code
        self.snippet = snippet
        super().__init__(f"fetch returned {status_code}, not an image")


def fetch_logo_preview(logo_url: str, http_get) -> bytes:
    """Fetch `logo_url` and return its bytes if it looks like an image.

    `http_get` mirrors `requests.get`'s signature and is injected rather
    than imported directly, matching this app's existing
    ldap_connection_factory dependency-injection pattern (see
    app/webapp.py) so tests never make a real network call.
    """
    resp = http_get(logo_url, timeout=FETCH_TIMEOUT_SECONDS, stream=True)
    content_type = resp.headers.get("Content-Type", "")
    buf = b""
    try:
        for piece in resp.iter_content(chunk_size=MAX_PREVIEW_BYTES):
            buf += piece
            if len(buf) >= MAX_PREVIEW_BYTES:
                break
    finally:
        # Must run even if iter_content raises mid-stream (a real
        # possibility when logo_url points at a non-HTTP service) -- a
        # bare post-loop close() would be skipped on that path and leak
        # the underlying socket.
        resp.close()
    buf = buf[:MAX_PREVIEW_BYTES]
    if not content_type.startswith("image/"):
        raise LogoFetchError(resp.status_code, buf.decode("utf-8", errors="replace"))
    return buf
