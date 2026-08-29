FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends gosu iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /usr/sbin/nologin appuser

# HTB machine submission requirement: shell history must be redirected to
# /dev/null. A shell reached via the RCE foothold has no login profile to
# source HISTFILE from, so the env var alone would not cover it -- the
# symlink is what actually stops history writes regardless of how the shell
# got started.
ENV HISTFILE=/dev/null
RUN ln -sf /dev/null /root/.bash_history \
    && ln -sf /dev/null /home/appuser/.bash_history

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY wsgi.py .
COPY CHANGELOG.md /home/appuser/CHANGELOG.md
COPY content/ /home/appuser/portal/
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chown -R appuser:appuser /app /home/appuser

EXPOSE 5000

ENTRYPOINT ["docker-entrypoint.sh"]
# --workers 2 (not gunicorn's default of 1): the /admin/branding SSRF
# fetches back into this same container on 127.0.0.1:5000 (spec
# docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
# Approach A). With a single sync worker, the outer /admin/branding request
# occupies the only worker and the inner loopback request can never be
# accepted -- a self-deadlock that resolves only via the fetch's own
# timeout, discovered by the live integration smoke test
# (build/web/tests/integration_smoke.py) timing out instead of getting a
# real response. Two workers let the outer request hold one while the inner
# loopback request is served by the other.
# --threads 4 (gunicorn auto-promotes the sync worker class to gthread once
# threads > 1): 2 workers alone is still only 2 concurrent request slots
# total, and the SSRF chain consumes both simultaneously by construction
# (the outer /admin/branding request + the inner loopback request it
# triggers) -- so two overlapping branding requests, or one slow
# logo_url, would degrade or hang the exploit for players. 2 workers x 4
# threads gives 8 concurrent slots. Safe because render_report_template
# builds a fresh Environment() per call and the LDAP connection factory
# builds a new Connection per request -- no shared mutable state in the
# request path.
CMD ["gunicorn", "--workers", "2", "--threads", "4", "--bind", "0.0.0.0:5000", "wsgi:app"]
