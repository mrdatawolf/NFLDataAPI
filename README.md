# NFLDataAPI

Unified mill-data API. Pulls disparate vendor data — production/tally, downtime/machine status, and maintenance/saw records — from three source systems into one common PGlite database and serves it over a REST API with a small React viewer.

## Sources

| Source | What it is | Engine | Status |
| --- | --- | --- | --- |
| **Raptor** | Existing ETL/API system; we read its database directly | set in `.env` | path pending |
| **Saw Filers** | Saw filing room app (Prisma-managed) | SQLite | clone in `Examples/SawFilers/` |
| **Porter** | Vendor system we don't have access to yet | PGlite (mock) | mocked via `npm run seed:porter` |

Sources are configured entirely in `.env` (`<SOURCE>_TYPE` = `sqlite` or `pglite`, `<SOURCE>_PATH` = file/dir). A source with an empty path is skipped. **Always point at a clone of the production database, never the live one** — clones go in `Examples/`, which is gitignored.

## Architecture (medallion)

This repo currently implements the **bronze** layer only:

- One PGlite database (`DB_PATH`) with a `bronze` schema.
- Each source table lands in `bronze.<source>__<table>` (e.g. `bronze.sawfilers__benching`) as raw JSONB payloads with lineage columns: `source`, `source_table`, `batch_id`, `ingested_at`, `row_hash`.
- Landing is schema-agnostic — connectors discover tables at scan time, so we don't need to know a vendor's schema in advance (important since Porter's real shape is unknown).
- Rescans are idempotent: `row_hash` (SHA-256 of the row content) dedupes, so only new/changed rows insert. For SQLite sources the source `rowid` is included in the payload, which keeps otherwise-identical rows distinct.

**Silver** (conformed models unifying production, downtime, and maintenance across the three vendors) and **gold** (serving/aggregate views) are deliberately deferred until all three real schemas are visible side by side — the bronze JSONB gives us everything needed to design them without re-ingesting. Volume is low (thousands of rows/day), so full-table rescans with hash dedupe are fine; watermark-based incremental ingest is a future optimization.

## Ingestion

- Auto-scan on startup (`SCAN_ON_START`) and every `SCAN_INTERVAL_HOURS`.
- On demand: `POST /api/ingest/scan` (optionally `?source=raptor|sawfilers|porter`) or the **Run scan** button in the UI.
- Every run is recorded in `bronze.ingest_runs`.

## Running locally

1. `npm install`
2. Copy `.env.example` to `.env` and adjust paths.
3. `npm run seed:porter` — creates the mock Porter PGlite database (add `-- --fresh` to wipe and reseed).
4. `npm run dev`
   - UI: http://localhost:7301 (Vite dev, `DEVPORT`)
   - API + Swagger docs: http://localhost:7300/api/docs (`APIPORT`)

Or use `./start.sh` / `start.bat`, which checks prerequisites, builds, and launches the production build (single process serving API + client on `APIPORT`).

## API

| Endpoint | Description |
| --- | --- |
| `GET /health` | Health check |
| `GET /api/sources` | Configured sources, availability, last ingest run |
| `GET /api/summary` | Bronze row/table counts per source |
| `POST /api/ingest/scan` | Ingest all (or one) source into bronze |
| `GET /api/ingest/runs` | Ingest run history |
| `GET /api/bronze/tables` | List bronze landing tables with counts |
| `GET /api/bronze/{source}/{table}` | Browse raw landed rows (paginated) |
| `GET /api/docs` | Swagger UI |

## Layout

```
server/            Express API + ingest
  config.ts        env parsing, source registry
  db.ts            unified PGlite (bronze schema, landing tables)
  ingest.ts        scan orchestrator (hash-dedupe landing, run history)
  sources/         connectors: sqliteSource, pgliteSource
  mock/seedPorter.ts  Porter stand-in database seeder
client/            React 18 + Vite viewer (summary, scan trigger, bronze browser)
Examples/          gitignored clones of source databases
data/              gitignored runtime databases (bronze + porter mock)
```

## Production build

```
npm run build
npm start
```
