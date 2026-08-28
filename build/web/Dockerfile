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
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chown -R appuser:appuser /app /home/appuser

EXPOSE 5000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "wsgi:app"]
