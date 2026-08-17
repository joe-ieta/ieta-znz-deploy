-- Optional minimal-privilege roles for IETA CDC Core (PostgreSQL metadata database).
-- NOT executed automatically: the postgres docker-entrypoint initdb glob only runs
-- *.sql/*.sh files directly under init/postgres/, so this file is skipped while it
-- lives in the optional/ subdirectory.
--
-- Apply on a fresh or existing deployment, e.g.:
--   docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml \
--     exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 \
--     < init/postgres/optional/01-ieta-cdc-minimal-privileges.sql
-- Or copy it into init/postgres/ before the FIRST startup of an empty volume.
-- Replace the placeholder passwords before any non-local deployment.
--
-- Role separation follows the CDC Core capacity guide:
--   ieta_core       DDL+DML on the ieta_cdc_core database (schema owner)
--   ieta_cdc_writer DML only on tables owned/created by ieta_core
--   ieta_cdc_ops    read-only plus monitoring

CREATE ROLE ieta_core LOGIN PASSWORD 'change-me-ieta-core';
CREATE ROLE ieta_cdc_writer LOGIN PASSWORD 'change-me-ieta-cdc-writer';
CREATE ROLE ieta_cdc_ops LOGIN PASSWORD 'change-me-ieta-cdc-ops';

ALTER DATABASE ieta_cdc_core OWNER TO ieta_core;

GRANT USAGE ON SCHEMA public TO ieta_cdc_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ieta_cdc_writer;
ALTER DEFAULT PRIVILEGES FOR ROLE ieta_core IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ieta_cdc_writer;

GRANT pg_read_all_data TO ieta_cdc_ops;
GRANT pg_monitor TO ieta_cdc_ops;
