import pytest
import requests

from app.branding import LogoFetchError, fetch_logo_preview


class _FakeResponse:
    def __init__(self, status_code, content_type, body):
        self.status_code = status_code
        self.headers = {"Content-Type": content_type}
        self._body = body
        self.closed = False

    def iter_content(self, chunk_size):
        if self._body:
            yield self._body[:chunk_size]

    def close(self):
        self.closed = True


def _fake_get(status_code, content_type, body):
    def http_get(url, timeout=None, stream=None):
        assert timeout is not None, "must pass a timeout to the fetch"
        assert stream is True, "must stream so a huge response can't be buffered whole"
        return _FakeResponse(status_code, content_type, body)
    return http_get


def test_fetch_logo_preview_returns_bytes_for_a_real_image():
    http_get = _fake_get(200, "image/png", b"\x89PNG\r\n\x1a\n" + b"rest-of-file")
    result = fetch_logo_preview("http://cdn.example.com/logo.png", http_get)
    assert result.startswith(b"\x89PNG")


def test_fetch_logo_preview_raises_and_carries_snippet_for_non_image_response():
    http_get = _fake_get(200, "text/html", b"<html>not an image</html>")
    with pytest.raises(LogoFetchError) as exc_info:
        fetch_logo_preview("http://127.0.0.1:5000/admin/report-template", http_get)
    assert exc_info.value.status_code == 200
    assert "not an image" in exc_info.value.snippet


def test_fetch_logo_preview_response_is_always_closed():
    http_get = _fake_get(200, "image/png", b"\x89PNG")
    responses = []

    def tracking_get(url, timeout=None, stream=None):
        resp = _FakeResponse(200, "image/png", b"\x89PNG")
        responses.append(resp)
        return resp

    fetch_logo_preview("http://cdn.example.com/logo.png", tracking_get)
    assert responses[0].closed is True


def test_fetch_logo_preview_caps_the_read_at_max_preview_bytes():
    huge_body = b"x" * 5000
    http_get = _fake_get(200, "text/html", huge_body)
    with pytest.raises(LogoFetchError) as exc_info:
        fetch_logo_preview("http://internal/huge", http_get)
    assert len(exc_info.value.snippet) <= 1000


class _MultiChunkResponse:
    def __init__(self, status_code, content_type, chunks):
        self.status_code = status_code
        self.headers = {"Content-Type": content_type}
        self._chunks = chunks
        self.closed = False

    def iter_content(self, chunk_size):
        for chunk in self._chunks:
            yield chunk

    def close(self):
        self.closed = True


def test_fetch_logo_preview_accumulates_multiple_chunks_up_to_the_cap():
    """A chunked/compressed response can yield many small pieces well under
    MAX_PREVIEW_BYTES each. Taking only the first piece would silently
    truncate the leaked content far short of the documented ~1000-byte
    window -- the fetch must accumulate across pieces, capped at
    MAX_PREVIEW_BYTES total, not unbounded."""
    chunks = [b"a" * 400, b"b" * 400, b"c" * 400]  # 1200 bytes across 3 pieces
    http_get = lambda url, timeout=None, stream=None: _MultiChunkResponse(
        200, "text/html", chunks
    )
    with pytest.raises(LogoFetchError) as exc_info:
        fetch_logo_preview("http://internal/multi", http_get)
    snippet = exc_info.value.snippet
    assert len(snippet) == 1000
    assert snippet.startswith("a" * 400 + "b" * 400)
    assert snippet.endswith("c" * 200)


def test_fetch_logo_preview_propagates_real_connection_errors():
    # No fake here on purpose: a malformed URL makes the real `requests`
    # library raise synchronously before any network I/O happens, so this
    # is a fast, network-free way to prove real requests.RequestException
    # instances are not swallowed.
    with pytest.raises(requests.exceptions.MissingSchema):
        fetch_logo_preview("not-a-url", requests.get)
