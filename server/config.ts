import dotenv from 'dotenv';

dotenv.config();

export const config = {
  port: Number(process.env.APIPORT || 3002),
  host: process.env.HOST || '0.0.0.0',
  dbPath: process.env.DB_PATH || './data/bronze.db',
  bronzeLimitDefault: Number(process.env.BRONZE_LIMIT_DEFAULT || 1000)
};
