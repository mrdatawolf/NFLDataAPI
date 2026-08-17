\set ON_ERROR_STOP on

-- Required psql variables:
--   api_password  Password for the nfldataapi login.
-- Optional variables:
--   api_user      Defaults to nfldataapi.
--   bronze_db     Defaults to bronze.
--   bronze_owner  Defaults to nfletl.
--   silver_db     Defaults to silver.

\if :{?api_user}
\else
  \set api_user nfldataapi
\endif
\if :{?bronze_db}
\else
  \set bronze_db bronze
\endif
\if :{?bronze_owner}
\else
  \set bronze_owner nfletl
\endif
\if :{?silver_db}
\else
  \set silver_db silver
\endif
\if :{?api_password}
\else
  \echo 'ERROR: api_password is required.'
  \echo 'Run with: psql ... --set=api_password="your-password" --file=ops/setup-postgres.sql'
  \quit 2
\endif

\echo 'Creating or updating the NFLDataAPI login...'
SELECT format('CREATE ROLE %I LOGIN', :'api_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'api_user')
\gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'api_user', :'api_password')
\gexec

\echo 'Granting read-only access to bronze...'
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'bronze_db', :'api_user')
\gexec

\connect :bronze_db
SELECT format('GRANT USAGE ON SCHEMA bronze TO %I', :'api_user')
\gexec
SELECT format('GRANT SELECT ON ALL TABLES IN SCHEMA bronze TO %I', :'api_user')
\gexec
SELECT format(
  'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA bronze GRANT SELECT ON TABLES TO %I',
  :'bronze_owner', :'api_user'
)
\gexec

\echo 'Creating silver with NFLDataAPI as owner...'
\connect postgres
SELECT format('CREATE DATABASE %I OWNER %I', :'silver_db', :'api_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'silver_db')
\gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'silver_db', :'api_user')
\gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'silver_db', :'api_user')
\gexec

\connect :silver_db
SELECT format('GRANT ALL ON SCHEMA public TO %I', :'api_user')
\gexec
SELECT format('ALTER SCHEMA silver OWNER TO %I', :'api_user')
WHERE EXISTS (SELECT FROM pg_namespace WHERE nspname = 'silver')
\gexec
-- Repair objects left behind by an interrupted or older setup run that
-- created silver objects as the postgres administrator.
SELECT format('ALTER TABLE %I.%I OWNER TO %I', schemaname, tablename, :'api_user')
FROM pg_tables
WHERE schemaname = 'silver'
\gexec
SELECT format('ALTER SEQUENCE %I.%I OWNER TO %I', sequence_schema, sequence_name, :'api_user')
FROM information_schema.sequences
WHERE sequence_schema = 'silver'
\gexec
SET ROLE :"api_user";
\ir silver-schema.sql
RESET ROLE;

\echo 'PostgreSQL database, role, and silver schema provisioning complete.'
SELECT current_setting('server_version') AS server_version,
       current_database() AS database,
       pg_get_userbyid(datdba) AS owner
FROM pg_database
WHERE datname = current_database();
