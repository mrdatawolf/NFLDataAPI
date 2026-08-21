import { db, silverDb } from './db.js';
import { transformTally } from './transformTally.js';

let runId: number | undefined;
try {
  const run = await silverDb.query<{ id: number }>(
    `INSERT INTO silver.transform_runs (source, status) VALUES ('tally', 'running') RETURNING id`
  );
  runId = run.rows[0].id;
  const result = await transformTally(db, silverDb);
  await silverDb.query(
    `UPDATE silver.transform_runs SET finished_at = now(), status = 'ok', rows_upserted = $1, rows_skipped = $2 WHERE id = $3`,
    [result.upserted, result.skipped, runId]
  );
  console.log(`Tally silver transform complete: ${result.upserted} upserted, ${result.skipped} skipped.`);
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  if (runId !== undefined) {
    await silverDb.query(
      `UPDATE silver.transform_runs SET finished_at = now(), status = 'error', error = $1 WHERE id = $2`,
      [message, runId]
    ).catch(() => undefined);
  }
  console.error(`Tally silver transform failed: ${message}`);
  process.exitCode = 1;
} finally {
  await Promise.all([db.end(), silverDb.end()]);
}
