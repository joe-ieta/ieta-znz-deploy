#!/usr/bin/env bash
set -euo pipefail

# Optional least-privilege PostgreSQL accounts for CDC Core (requirement R8).
# Roles follow the CDC capacity guide separation: ieta_core / ieta_cdc_writer / ieta_cdc_ops.
# Passwords come from the compose environment (root .env IETA_CORE_PASSWORD etc.).
# Runs only on first empty-volume initialization; skips itself when any password is empty.
# Default superuser (postgres) remains acceptable for development only; production must
# use these accounts or equivalent managed credentials.

if [[ -z "${IETA_CORE_PASSWORD:-}" || -z "${IETA_CDC_WRITER_PASSWORD:-}" || -z "${IETA_CDC_OPS_PASSWORD:-}" ]]; then
  echo "IETA_CORE_PASSWORD/IETA_CDC_WRITER_PASSWORD/IETA_CDC_OPS_PASSWORD not fully set; skipping optional CDC least-privilege role creation."
  exit 0
fi

create_role() {
  local name="$1" password="$2"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    -v role="$name" -v pass="$password" <<-EOSQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role') THEN
        CREATE ROLE :"role" LOGIN PASSWORD :'pass';
      ELSE
        ALTER ROLE :"role" WITH LOGIN PASSWORD :'pass';
      END IF;
    END
    \$\$;
EOSQL
}

create_role ieta_core "$IETA_CORE_PASSWORD"
create_role ieta_cdc_writer "$IETA_CDC_WRITER_PASSWORD"
create_role ieta_cdc_ops "$IETA_CDC_OPS_PASSWORD"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname ieta_cdc_core \
  -v core="ieta_core" -v writer="ieta_cdc_writer" -v ops="ieta_cdc_ops" <<-EOSQL
  CREATE SCHEMA IF NOT EXISTS ieta_cdc AUTHORIZATION :"core";
  GRANT USAGE, CREATE ON SCHEMA ieta_cdc TO :"writer";
  GRANT USAGE ON SCHEMA ieta_cdc TO :"ops";
  ALTER DEFAULT PRIVILEGES FOR ROLE :"core" IN SCHEMA ieta_cdc GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"writer";
  ALTER DEFAULT PRIVILEGES FOR ROLE :"core" IN SCHEMA ieta_cdc GRANT USAGE, SELECT ON SEQUENCES TO :"writer";
  ALTER DEFAULT PRIVILEGES FOR ROLE :"core" IN SCHEMA ieta_cdc GRANT SELECT ON TABLES TO :"ops";
EOSQL

echo "CDC least-privilege roles created: ieta_core (schema owner), ieta_cdc_writer (DML on schema ieta_cdc), ieta_cdc_ops (read-only)."
