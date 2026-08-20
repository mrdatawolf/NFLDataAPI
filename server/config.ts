import dotenv from 'dotenv';

dotenv.config();

export const config = {
  port: Number(process.env.APIPORT || 3002),
  host: process.env.HOST || '0.0.0.0',
  bronze: {
    host: process.env.PGHOST || 'localhost',
    port: Number(process.env.PGPORT || 5432),
    user: process.env.PGUSER || 'nfldataapi',
    password: process.env.PGPASSWORD,
    database: process.env.BRONZE_PGDATABASE || 'bronze'
  },
  bronzeLimitDefault: Number(process.env.BRONZE_LIMIT_DEFAULT || 1000)
};
