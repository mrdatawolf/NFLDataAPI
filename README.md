# NFLDataAPI

REST API and React viewer for the mill-data platform. The application reads
raw bronze data landed by the sibling
[NFLETL](https://github.com/mrdatawolf/NFLETL) service and owns the typed
silver layer. Both layers now run on PostgreSQL 17; PGlite is no longer used.

## Architecture

| Database | Owner | Purpose |
| --- | --- | --- |
| `bronze` | NFLETL | Append-only JSONB landing tables and ingestion lineage. NFLDataAPI has `SELECT` access only. |
| `silver` | NFLDataAPI | Typed, cleaned models populated by this repository. |

Each bronze source table is named `bronze.<source>__<table>` and contains a
raw `payload` plus `source`, `source_table`, `row_hash`, `batch_id`, and
`ingested_at` lineage columns. PostgreSQL provides safe concurrent access for
the NFLETL writer and API/transform readers.

Tally is a normalized five-table report feed rather than the same shape as
Porter's production tally. Its `files`, `summary`, `detail_lines`,
`reject_reasons`, and `solutions` records are joined by `file_id` and load to
matching typed silver tables. The transform maps reject `count` to
`reject_count`, converts duration strings to PostgreSQL intervals, retains
bronze lineage, and safely upserts repeat runs.

## Setup and running

1. Install PostgreSQL 17 and run NFLETL's bronze setup/ingestion.
2. Copy `.env.example` to `.env` and set the PostgreSQL connection values.
3. Run `./ops/setup-postgres.sh` to create/grant the application role and
   create the silver database/schema. See [SetupPG.md](SetupPG.md).
4. Run `npm install` and `npm run dev`.

The UI defaults to http://localhost:7301 and the API/Swagger UI to
http://localhost:7300/api/docs. `./start.sh` and `start.bat` build and launch
the production server.

## Silver ingestion

After NFLETL lands a Tally batch, run:

```bash
npm run transform:silver
```

The command reads bronze through the read-only pool and writes to the separate
silver pool. It processes all Tally rows idempotently, reports upsert/skipped
counts, and records each attempt in `silver.transform_runs`. Re-run
`ops/silver-schema.sql` before the transform when deploying schema changes.

## API

| Endpoint | Description |
| --- | --- |
| `GET /health` | Health check |
| `GET /api/sources` | Sources and their latest bronze ingestion run |
| `GET /api/summary` | Bronze row/table counts by source |
| `GET /api/ingest/runs` | NFLETL bronze ingestion history |
| `GET /api/bronze/tables` | Bronze landing tables and counts |
| `GET /api/bronze/{source}/{table}` | Paginated raw bronze rows |
| `GET /api/docs` | Swagger UI |

## Repository layout

```text
server/                 Express API and bronze-to-silver transform
client/                 React/Vite viewer
ops/silver-schema.sql   Idempotent typed silver DDL
ops/setup-postgres.*    PostgreSQL provisioning
```

## Production build

```bash
npm run build
npm start
```
