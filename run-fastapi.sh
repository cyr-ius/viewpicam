#!/bin/sh
set -euo pipefail
cd /app

PATH=/env/bin:$PATH

LOG_LEVEL="${LOG_LEVEL:-info}"


if [ ! -f "./config/.secret_key" ]; then
    secret=$(python -c 'import secrets; print(secrets.token_hex())')
    echo SECRET_KEY=${secret} >> "./config/.secret_key"
fi

/bin/sh -c "alembic upgrade head"
exec fastapi run app/main.py &
