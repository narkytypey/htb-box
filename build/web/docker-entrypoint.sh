#!/bin/sh
set -e

if [ ! -f /home/appuser/user.txt ]; then
    python3 -c "import secrets; print(secrets.token_hex(16))" > /home/appuser/user.txt
    chmod 400 /home/appuser/user.txt
fi

exec "$@"
