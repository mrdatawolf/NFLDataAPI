\set ON_ERROR_STOP on

-- Initial typed silver models based on the live Porter and Tally bronze
-- payloads observed on 2026-08-17. Every table retains bronze lineage so a
-- row can be traced back or safely upserted after another ingestion run.

CREATE SCHEMA IF NOT EXISTS silver;

CREATE TABLE IF NOT EXISTS silver.production_tallies (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL,
  source_record_id TEXT NOT NULL,
  machine TEXT NOT NULL,
  product TEXT NOT NULL,
  shift TEXT,
  recorded_at TIMESTAMPTZ NOT NULL,
  piece_count INTEGER NOT NULL CHECK (piece_count >= 0),
  volume_bf NUMERIC(14, 2) NOT NULL CHECK (volume_bf >= 0),
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_record_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);
CREATE INDEX IF NOT EXISTS production_tallies_recorded_at_idx
  ON silver.production_tallies (recorded_at);
CREATE INDEX IF NOT EXISTS production_tallies_machine_idx
  ON silver.production_tallies (machine);

CREATE TABLE IF NOT EXISTS silver.downtime_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL,
  source_record_id TEXT NOT NULL,
  machine TEXT NOT NULL,
  category TEXT,
  reason TEXT,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  duration_seconds NUMERIC GENERATED ALWAYS AS
    (CASE WHEN ended_at IS NULL THEN NULL ELSE EXTRACT(EPOCH FROM ended_at - started_at) END) STORED,
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  UNIQUE (source, source_record_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);
CREATE INDEX IF NOT EXISTS downtime_events_started_at_idx
  ON silver.downtime_events (started_at);
CREATE INDEX IF NOT EXISTS downtime_events_machine_idx
  ON silver.downtime_events (machine);

CREATE TABLE IF NOT EXISTS silver.saw_maintenance (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL,
  source_record_id TEXT NOT NULL,
  saw_number TEXT NOT NULL,
  action TEXT NOT NULL,
  performed_at TIMESTAMPTZ NOT NULL,
  performed_by TEXT,
  notes TEXT,
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_record_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);
CREATE INDEX IF NOT EXISTS saw_maintenance_performed_at_idx
  ON silver.saw_maintenance (performed_at);
CREATE INDEX IF NOT EXISTS saw_maintenance_saw_number_idx
  ON silver.saw_maintenance (saw_number);

CREATE TABLE IF NOT EXISTS silver.tally_files (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'tally',
  source_file_id BIGINT NOT NULL,
  filename TEXT NOT NULL,
  filename_date DATE,
  report_datetime TIMESTAMP,
  loaded_at TIMESTAMP,
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_file_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);
CREATE INDEX IF NOT EXISTS tally_files_report_datetime_idx
  ON silver.tally_files (report_datetime);

CREATE TABLE IF NOT EXISTS silver.tally_detail_lines (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'tally',
  source_record_id BIGINT NOT NULL,
  source_file_id BIGINT NOT NULL,
  wood_type TEXT,
  grade TEXT,
  thickness TEXT,
  width NUMERIC(10, 3),
  length_ft NUMERIC(10, 3),
  pieces INTEGER CHECK (pieces IS NULL OR pieces >= 0),
  bd_ft NUMERIC(14, 3) CHECK (bd_ft IS NULL OR bd_ft >= 0),
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_record_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);
CREATE INDEX IF NOT EXISTS tally_detail_lines_file_idx
  ON silver.tally_detail_lines (source, source_file_id);

CREATE TABLE IF NOT EXISTS silver.tally_summaries (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'tally',
  source_file_id BIGINT NOT NULL,
  time_start TEXT,
  time_run INTERVAL,
  time_no_production INTERVAL,
  board_input_pieces INTEGER,
  board_input_cuft NUMERIC,
  edger_bd_ft NUMERIC,
  trim_pass_count INTEGER,
  trim_pass_bd_ft NUMERIC,
  average_length_ft NUMERIC,
  fiber_ratio NUMERIC,
  recovery_bf_cf NUMERIC,
  recovery_lrf_bf_cm NUMERIC,
  lumber_value NUMERIC,
  lumber_value_deducts NUMERIC,
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_file_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);

CREATE TABLE IF NOT EXISTS silver.tally_reject_reasons (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'tally',
  source_record_id BIGINT NOT NULL,
  source_file_id BIGINT NOT NULL,
  reason TEXT NOT NULL,
  reject_count INTEGER NOT NULL CHECK (reject_count >= 0),
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_record_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);
CREATE INDEX IF NOT EXISTS tally_reject_reasons_file_idx
  ON silver.tally_reject_reasons (source, source_file_id);

CREATE TABLE IF NOT EXISTS silver.tally_solutions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'tally',
  source_record_id BIGINT NOT NULL,
  source_file_id BIGINT NOT NULL,
  solution_number INTEGER NOT NULL,
  board_count INTEGER NOT NULL CHECK (board_count >= 0),
  bronze_table TEXT NOT NULL,
  bronze_id BIGINT NOT NULL,
  bronze_row_hash TEXT NOT NULL,
  bronze_batch_id TEXT NOT NULL,
  bronze_ingested_at TIMESTAMPTZ NOT NULL,
  transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_record_id),
  UNIQUE (bronze_table, bronze_id),
  UNIQUE (bronze_row_hash)
);
CREATE INDEX IF NOT EXISTS tally_solutions_file_idx
  ON silver.tally_solutions (source, source_file_id);

CREATE TABLE IF NOT EXISTS silver.transform_runs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  status TEXT NOT NULL CHECK (status IN ('running', 'ok', 'error')),
  rows_upserted INTEGER NOT NULL DEFAULT 0,
  error TEXT
);
