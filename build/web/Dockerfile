FROM python:3.12-slim

RUN useradd --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY wsgi.py .
COPY CHANGELOG.md /home/appuser/CHANGELOG.md
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chown -R appuser:appuser /app /home/appuser

USER appuser

EXPOSE 5000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "wsgi:app"]
