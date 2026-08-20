import { Pool } from 'pg';
import { config } from './config.js';

// Read-only consumer of the bronze database. PostgreSQL grants enforce that
// schema creation and all writes remain owned by the sibling NFLETL service.
export const db = new Pool(config.bronze);

export async function initDb(): Promise<void> {
  try {
    await db.query('SELECT 1');
  } catch (error) {
    await db.end().catch(() => undefined);
    const target = `${config.bronze.host}:${config.bronze.port}/${config.bronze.database}`;
    const reason = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Unable to connect to PostgreSQL at ${target} as ${config.bronze.user}: ${reason}`,
      { cause: error }
    );
  }
}

// Landing tables are one-per-source-table, named bronze.<source>__<table>.
export function landingTableName(source: string, table: string): string {
  const clean = (value: string) => value.toLowerCase().replace(/[^a-z0-9_]/g, '_');
  return `${clean(source)}__${clean(table)}`;
}

export async function listLandingTables(): Promise<{ table_name: string; row_count: number }[]> {
  const tables = await db.query<{ table_name: string }>(`
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'bronze' AND table_name LIKE '%\\_\\_%'
    ORDER BY table_name;
  `);

  const results: { table_name: string; row_count: number }[] = [];
  for (const row of tables.rows) {
    const count = await db.query<{ count: number }>(
      `SELECT COUNT(*)::int AS count FROM bronze."${row.table_name}"`
    );
    results.push({ table_name: row.table_name, row_count: count.rows[0].count });
  }
  return results;
}
