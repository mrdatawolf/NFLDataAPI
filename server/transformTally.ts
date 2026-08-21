import type { Pool, PoolClient } from 'pg';

type BronzeRow = {
  id: number;
  payload: Record<string, unknown>;
  row_hash: string;
  batch_id: string;
  ingested_at: Date | string;
};

type TableSpec = {
  bronzeTable: string;
  silverTable: string;
  conflictKey: string;
  columns: string[];
  normalize: (row: BronzeRow) => Record<string, unknown> | null;
};

const text = (value: unknown): string | null =>
  typeof value === 'string' && value.trim() ? value.trim() : null;
const number = (value: unknown): number | null => {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};
const integer = (value: unknown): number | null => {
  const parsed = number(value);
  return parsed !== null && Number.isInteger(parsed) ? parsed : null;
};

function lineage(row: BronzeRow, bronzeTable: string): Record<string, unknown> {
  return {
    source: 'tally',
    bronze_table: bronzeTable,
    bronze_id: row.id,
    bronze_row_hash: row.row_hash,
    bronze_batch_id: row.batch_id,
    bronze_ingested_at: row.ingested_at
  };
}

const specs: TableSpec[] = [
  {
    bronzeTable: 'tally__files', silverTable: 'tally_files', conflictKey: 'source_file_id',
    columns: ['source_file_id', 'filename', 'filename_date', 'report_datetime', 'loaded_at'],
    normalize: (row) => {
      const source_file_id = integer(row.payload.file_id);
      const filename = text(row.payload.filename);
      if (source_file_id === null || filename === null) return null;
      return { ...lineage(row, 'tally__files'), source_file_id, filename,
        filename_date: text(row.payload.filename_date), report_datetime: text(row.payload.report_datetime),
        loaded_at: text(row.payload.loaded_at) };
    }
  },
  {
    bronzeTable: 'tally__detail_lines', silverTable: 'tally_detail_lines', conflictKey: 'source_record_id',
    columns: ['source_record_id', 'source_file_id', 'wood_type', 'grade', 'thickness', 'width', 'length_ft', 'pieces', 'bd_ft'],
    normalize: (row) => {
      const source_record_id = integer(row.payload.id ?? row.payload._rowid);
      const source_file_id = integer(row.payload.file_id);
      const pieces = integer(row.payload.pieces); const bd_ft = number(row.payload.bd_ft);
      if (source_record_id === null || source_file_id === null || (pieces !== null && pieces < 0) || (bd_ft !== null && bd_ft < 0)) return null;
      return { ...lineage(row, 'tally__detail_lines'), source_record_id, source_file_id,
        wood_type: text(row.payload.wood_type), grade: text(row.payload.grade), thickness: text(row.payload.thickness),
        width: number(row.payload.width), length_ft: number(row.payload.length_ft), pieces, bd_ft };
    }
  },
  {
    bronzeTable: 'tally__summary', silverTable: 'tally_summaries', conflictKey: 'source_file_id',
    columns: ['source_file_id', 'time_start', 'time_run', 'time_no_production', 'board_input_pieces',
      'board_input_cuft', 'edger_bd_ft', 'trim_pass_count', 'trim_pass_bd_ft', 'average_length_ft',
      'fiber_ratio', 'recovery_bf_cf', 'recovery_lrf_bf_cm', 'lumber_value', 'lumber_value_deducts'],
    normalize: (row) => {
      const source_file_id = integer(row.payload.file_id);
      if (source_file_id === null) return null;
      return { ...lineage(row, 'tally__summary'), source_file_id, time_start: text(row.payload.time_start),
        time_run: text(row.payload.time_run), time_no_production: text(row.payload.time_no_production),
        board_input_pieces: integer(row.payload.board_input_pieces), board_input_cuft: number(row.payload.board_input_cuft),
        edger_bd_ft: number(row.payload.edger_bd_ft), trim_pass_count: integer(row.payload.trim_pass_count),
        trim_pass_bd_ft: number(row.payload.trim_pass_bd_ft), average_length_ft: number(row.payload.average_length_ft),
        fiber_ratio: number(row.payload.fiber_ratio), recovery_bf_cf: number(row.payload.recovery_bf_cf),
        recovery_lrf_bf_cm: number(row.payload.recovery_lrf_bf_cm), lumber_value: number(row.payload.lumber_value),
        lumber_value_deducts: number(row.payload.lumber_value_deducts) };
    }
  },
  {
    bronzeTable: 'tally__reject_reasons', silverTable: 'tally_reject_reasons', conflictKey: 'source_record_id',
    columns: ['source_record_id', 'source_file_id', 'reason', 'reject_count'],
    normalize: (row) => {
      const source_record_id = integer(row.payload.id ?? row.payload._rowid); const source_file_id = integer(row.payload.file_id);
      const reason = text(row.payload.reason); const reject_count = integer(row.payload.count);
      if (source_record_id === null || source_file_id === null || reason === null || reject_count === null || reject_count < 0) return null;
      return { ...lineage(row, 'tally__reject_reasons'), source_record_id, source_file_id, reason, reject_count };
    }
  },
  {
    bronzeTable: 'tally__solutions', silverTable: 'tally_solutions', conflictKey: 'source_record_id',
    columns: ['source_record_id', 'source_file_id', 'solution_number', 'board_count'],
    normalize: (row) => {
      const source_record_id = integer(row.payload.id ?? row.payload._rowid); const source_file_id = integer(row.payload.file_id);
      const solution_number = integer(row.payload.solution_number); const board_count = integer(row.payload.board_count);
      if ([source_record_id, source_file_id, solution_number, board_count].some((v) => v === null) || board_count! < 0) return null;
      return { ...lineage(row, 'tally__solutions'), source_record_id, source_file_id, solution_number, board_count };
    }
  }
];

const lineageColumns = ['source', 'bronze_table', 'bronze_id', 'bronze_row_hash', 'bronze_batch_id', 'bronze_ingested_at'];

async function upsertRows(client: PoolClient, spec: TableSpec, rows: Record<string, unknown>[]): Promise<number> {
  if (!rows.length) return 0;
  const columns = [...spec.columns, ...lineageColumns];
  let changed = 0;
  for (let start = 0; start < rows.length; start += 500) {
    const batch = rows.slice(start, start + 500);
    const values: unknown[] = [];
    const tuples = batch.map((row) => {
      const placeholders = columns.map((column) => { values.push(row[column]); return `$${values.length}`; });
      return `(${placeholders.join(', ')})`;
    });
    const updates = columns.filter((column) => !['source', spec.conflictKey].includes(column))
      .map((column) => `${column} = EXCLUDED.${column}`).concat('transformed_at = now()');
    const result = await client.query(
      `INSERT INTO silver.${spec.silverTable} (${columns.join(', ')}) VALUES ${tuples.join(', ')}
       ON CONFLICT (source, ${spec.conflictKey}) DO UPDATE SET ${updates.join(', ')}`,
      values
    );
    changed += result.rowCount ?? 0;
  }
  return changed;
}

export async function transformTally(bronze: Pool, silver: Pool): Promise<{ upserted: number; skipped: number }> {
  const client = await silver.connect();
  let upserted = 0; let skipped = 0;
  try {
    await client.query('BEGIN');
    for (const spec of specs) {
      const result = await bronze.query<BronzeRow>(
        `SELECT id, payload, row_hash, batch_id, ingested_at FROM bronze.${spec.bronzeTable} ORDER BY id`
      );
      const normalized = result.rows.map(spec.normalize);
      skipped += normalized.filter((row) => row === null).length;
      upserted += await upsertRows(client, spec, normalized.filter((row): row is Record<string, unknown> => row !== null));
    }
    await client.query('COMMIT');
    return { upserted, skipped };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
