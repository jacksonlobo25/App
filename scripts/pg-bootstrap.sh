#!/usr/bin/env bash
set -euo pipefail
DB_USER=${POSTGRES_USER:-dev}
DB_PASS=${POSTGRES_PASSWORD:-devpass}
DB_NAME=${POSTGRES_DB:-appdb}
PORT=${POSTGRES_PORT:-5432}
until pg_isready -U postgres -h 127.0.0.1 -p "${PORT}"; do sleep 1; done
psql -v ON_ERROR_STOP=1 -U postgres -h 127.0.0.1 -p "${PORT}" <<SQL
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}' CREATEDB CREATEROLE;
    END IF;
END $$;
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') THEN
    CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
    END IF;
END $$;
ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};
SQL
echo "PostgreSQL bootstrap complete: user=${DB_USER}, db=${DB_NAME}, port=${PORT}"