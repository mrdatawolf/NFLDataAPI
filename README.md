# NFLDataAPI

Read-only REST API + small React viewer over a unified mill-data bronze
layer (production/tally, downtime/machine status, and maintenance/saw
records) in PGlite. This repo does not ingest anything — all ingestion
(Raptor, Saw Filers, Porter) and tally-report parsing lives in the sibling
[NFLETL](https://github.com/mrdatawolf/NFLETL) project, which writes the same
bronze PGlite database this repo reads.

## Architecture (medallion)

- One PGlite database (`DB_PATH`) with a `bronze` schema, owned by NFLETL.
  **`DB_PATH` here must resolve to the same directory as NFLETL's `DB_PATH`**
  — this app opens that directory read-only.
- Each source table lands in `bronze.<source>__<table>` (e.g.
  `bronze.sawfilers__benching`) as raw JSONB payloads with lineage columns:
  `source`, `source_table`, `batch_id`, `ingested_at`, `row_hash`.
- **Silver** (conformed models unifying production, downtime, and maintenance
  across vendors) and **gold** (serving/aggregate views) are deliberately
  deferred until all real schemas are visible side by side.

### Known risk: concurrent access to bronze.db

PGlite isn't built for multi-process concurrent access the way WAL-mode
SQLite or a real Postgres server is. NFLETL (writer) and this app (reader)
are separate processes opening the same PGlite data directory — a scan
running in NFLETL at the same moment this app is serving a request could hit
lock contention. Untested under load; worth watching if errors show up
during NFLETL scan windows.

## Running locally

1. `npm install`
2. Copy `.env.example` to `.env` and point `DB_PATH` at the same bronze
   directory NFLETL writes to.
3. Run NFLETL at least once (see its README) so the bronze schema and some
   data exist — this app doesn't create anything itself.
4. `npm run dev`
   - UI: http://localhost:7301 (Vite dev, `DEVPORT`)
   - API + Swagger docs: http://localhost:7300/api/docs (`APIPORT`)

Or use `./start.sh` / `start.bat`, which checks prerequisites, builds, and
launches the production build (single process serving API + client on
`APIPORT`).

## API

| Endpoint | Description |
| --- | --- |
| `GET /health` | Health check |
| `GET /api/sources` | Sources seen in bronze ingest history and their last run |
| `GET /api/summary` | Bronze row/table counts per source |
| `GET /api/ingest/runs` | Ingest run history (written by NFLETL) |
| `GET /api/bronze/tables` | List bronze landing tables with counts |
| `GET /api/bronze/{source}/{table}` | Browse raw landed rows (paginated) |
| `GET /api/docs` | Swagger UI |

## Layout

```
server/            Express API (read-only)
  config.ts        env parsing
  db.ts            bronze PGlite connection + read helpers
client/            React 18 + Vite viewer (summary, bronze browser)
data/              gitignored — the bronze PGlite directory (or a symlink/mount to NFLETL's)
```

## Production build

```
npm run build
npm start
```
