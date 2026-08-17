# PostgreSQL setup for NFLDataAPI

NFLDataAPI uses one PostgreSQL 17 server with two databases:

| Database | Owner | Purpose |
| --- | --- | --- |
| `bronze` | `nfletl` | Raw landing data written by the sibling NFLETL project; NFLDataAPI has read-only access. |
| `silver` | `nfldataapi` | Typed, cleaned data built and owned by NFLDataAPI. |

Run the NFLETL PostgreSQL setup and bronze ingestion first. The commands
below then provision this application's role, bronze grants, and silver
database, and the initial typed silver tables. The scripts are idempotent and
can be rerun after restoring a backup or adding bronze tables.

## Configure the application first

Copy the example environment file and edit the copy:

```bash
cp .env.example .env
```

Set the connection values in `.env` before provisioning:

```dotenv
PGHOST=localhost
PGPORT=5432
PGUSER=nfldataapi
PGPASSWORD='choose-a-development-password'
BRONZE_PGDATABASE=bronze
SILVER_PGDATABASE=silver
```

Quotes around `PGPASSWORD` are recommended when it contains `#`, spaces, or
shell metacharacters. The wrapper reads only the required PostgreSQL keys and
does not execute or source `.env`. Keep `.env` uncommitted.

## Automated local setup

Run the wrapper from the repository root:

```bash
./ops/setup-postgres.sh
```

The wrapper loads `.env`, uses its `PGUSER` and `PGPASSWORD` to create/update
the application login, then connects through `sudo` as the local `postgres`
administrator. It creates the silver database and tables and grants read-only
bronze access.

The earlier `read -rsp ... NFLDATAAPI_DB_PASSWORD` example did not require a
pre-existing variable: `read` would have prompted for and assigned it. The
wrapper removes that extra temporary variable and makes `.env` the single
source of application connection settings.

For PostgreSQL on another host, run the SQL file with an administrator
connection and pass the values explicitly:

```bash
psql -h DB_HOST -U postgres -d postgres \
  --set=api_user=nfldataapi \
  --set=api_password='the-password-from-.env' \
  --set=bronze_db=bronze \
  --set=bronze_owner=nfletl \
  --set=silver_db=silver \
  --file=ops/setup-postgres.sql
```

The script intentionally requires the API password on every run so a copied
development environment never inherits an undocumented credential. It loads
[`ops/silver-schema.sql`](ops/silver-schema.sql), which can also be run by
itself against an existing `silver` database when the table definitions
change.

The same login connects to both databases, but the
application uses a separate connection pool for each one because PostgreSQL
connections cannot switch databases.

## Verification

```bash
PGPASSWORD='your-password' psql -h localhost -U nfldataapi -d bronze \
  -c 'SELECT count(*) FROM bronze.ingest_runs;'

PGPASSWORD='your-password' psql -h localhost -U nfldataapi -d silver \
  -c 'SELECT current_database(), current_user;'
```

An attempted write to a bronze table should fail. Do not test this against a
real row; the grants can be inspected safely instead:

```sql
SELECT has_schema_privilege('nfldataapi', 'bronze', 'USAGE'),
       has_table_privilege('nfldataapi', 'bronze.ingest_runs', 'SELECT'),
       has_table_privilege('nfldataapi', 'bronze.ingest_runs', 'INSERT');
```

Expected values are `true`, `true`, and `false`.
