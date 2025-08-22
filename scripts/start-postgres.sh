#!/usr/bin/env bash
set -euo pipefail
PG_MAJOR=$(cat /etc/postgresql/PG_MAJOR)
CONF=/etc/postgresql/${PG_MAJOR}/main/postgresql.conf
PORT=${POSTGRES_PORT:-5432}
exec /usr/lib/postgresql/${PG_MAJOR}/bin/postgres \
    -D "${PGDATA}" -c config_file="${CONF}" -c "port=${PORT}"