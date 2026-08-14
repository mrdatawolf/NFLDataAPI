import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import swaggerUi from 'swagger-ui-express';
import { config } from './config.js';
import { db, listLandingTables, landingTableName } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'nfldataapi' });
});

app.get('/api/sources', async (_req, res) => {
  const lastRuns = await db.query<{ source: string; finished_at: string; status: string; rows_inserted: number }>(`
    SELECT DISTINCT ON (source) source, finished_at, status, rows_inserted
    FROM bronze.ingest_runs
    ORDER BY source, id DESC;
  `);

  res.json({ sources: lastRuns.rows.map((run) => ({ name: run.source, last_run: run })) });
});

app.get('/api/summary', async (_req, res) => {
  const tables = await listLandingTables();
  const bySource: Record<string, { tables: number; rows: number }> = {};

  for (const table of tables) {
    const sourceName = table.table_name.split('__')[0];
    bySource[sourceName] ??= { tables: 0, rows: 0 };
    bySource[sourceName].tables += 1;
    bySource[sourceName].rows += table.row_count;
  }

  res.json({
    total_rows: tables.reduce((sum, table) => sum + table.row_count, 0),
    total_tables: tables.length,
    by_source: bySource
  });
});

app.get('/api/ingest/runs', async (req, res) => {
  const limit = Math.min(Number(req.query.limit || 50), 500);
  const result = await db.query(
    `SELECT id, source, started_at, finished_at, status, tables_scanned, rows_inserted, rows_skipped, error
     FROM bronze.ingest_runs ORDER BY id DESC LIMIT $1`,
    [limit]
  );
  res.json({ runs: result.rows });
});

app.get('/api/bronze/tables', async (_req, res) => {
  res.json({ tables: await listLandingTables() });
});

app.get('/api/bronze/:source/:table', async (req, res) => {
  const landing = landingTableName(req.params.source, req.params.table);
  const known = await listLandingTables();
  if (!known.some((table) => table.table_name === landing)) {
    res.status(404).json({ error: `No bronze table for ${req.params.source}/${req.params.table}` });
    return;
  }

  const limit = Math.min(Number(req.query.limit || config.bronzeLimitDefault), 10000);
  const offset = Number(req.query.offset || 0);
  const result = await db.query(
    `SELECT id, payload, batch_id, ingested_at FROM bronze."${landing}" ORDER BY id DESC LIMIT $1 OFFSET $2`,
    [limit, offset]
  );
  res.json({ table: landing, rows: result.rows, count: result.rows.length, offset });
});

const swaggerDocument = {
  openapi: '3.0.0',
  info: {
    title: 'NFLDataAPI',
    version: '0.1.0',
    description:
      'Unified mill-data API. Reads the bronze layer (Raptor, Saw Filers, Porter, Tally) landed by the sibling NFLETL project and serves the raw data. This repo does not ingest anything itself.'
  },
  paths: {
    '/health': {
      get: {
        summary: 'Health check',
        responses: { '200': { description: 'Service is up' } }
      }
    },
    '/api/sources': {
      get: {
        summary: 'Sources seen in bronze ingest history and their last run',
        responses: { '200': { description: 'Source list' } }
      }
    },
    '/api/summary': {
      get: {
        summary: 'Bronze row/table counts per source',
        responses: { '200': { description: 'Summary counts' } }
      }
    },
    '/api/ingest/runs': {
      get: {
        summary: 'Ingest run history (written by NFLETL)',
        parameters: [{ name: 'limit', in: 'query', schema: { type: 'integer', default: 50 } }],
        responses: { '200': { description: 'Recent runs, newest first' } }
      }
    },
    '/api/bronze/tables': {
      get: {
        summary: 'List bronze landing tables with row counts',
        responses: { '200': { description: 'Landing tables' } }
      }
    },
    '/api/bronze/{source}/{table}': {
      get: {
        summary: 'Browse raw rows landed from one source table',
        parameters: [
          { name: 'source', in: 'path', required: true, schema: { type: 'string' } },
          { name: 'table', in: 'path', required: true, schema: { type: 'string' } },
          { name: 'limit', in: 'query', schema: { type: 'integer', default: config.bronzeLimitDefault, maximum: 10000 } },
          { name: 'offset', in: 'query', schema: { type: 'integer', default: 0 } }
        ],
        responses: { '200': { description: 'Raw rows (payload JSONB + lineage columns)' }, '404': { description: 'Unknown bronze table' } }
      }
    }
  }
};

app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(swaggerDocument));

app.use(express.static(path.join(__dirname, '../client/dist')));

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, '../client/dist/index.html'));
});

app.listen(config.port, config.host, () => {
  console.log(`Server listening on http://${config.host}:${config.port}`);
});
