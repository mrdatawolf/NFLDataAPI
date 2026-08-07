import dotenv from 'dotenv';
import fs from 'node:fs';

dotenv.config();

export type SourceType = 'sqlite' | 'pglite';

export type SourceConfig = {
  name: string;
  type: SourceType;
  path: string;
  configured: boolean;
};

function readSource(name: string): SourceConfig {
  const prefix = name.toUpperCase();
  const type = (process.env[`${prefix}_TYPE`] || 'sqlite') as SourceType;
  const sourcePath = process.env[`${prefix}_PATH`] || '';

  if (type !== 'sqlite' && type !== 'pglite') {
    throw new Error(`${prefix}_TYPE must be "sqlite" or "pglite", got "${type}"`);
  }

  return { name, type, path: sourcePath, configured: sourcePath.length > 0 };
}

export const config = {
  port: Number(process.env.APIPORT || 3002),
  host: process.env.HOST || '0.0.0.0',
  dbPath: process.env.DB_PATH || './data/bronze.db',
  scanIntervalHours: Number(process.env.SCAN_INTERVAL_HOURS || 1),
  scanOnStart: process.env.SCAN_ON_START !== 'false',
  sources: [readSource('raptor'), readSource('sawfilers'), readSource('porter')]
};

export function sourceAvailable(source: SourceConfig): boolean {
  return source.configured && fs.existsSync(source.path);
}
