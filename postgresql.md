# PostgreSQL migration status

The migration from embedded PGlite to PostgreSQL 17 is complete.

- NFLETL owns and writes the `bronze` database.
- NFLDataAPI connects to bronze as the `nfldataapi` role with read-only
  grants enforced by PostgreSQL.
- NFLDataAPI owns the separate `silver` database and its typed models.
- The application uses a separate `pg.Pool` for each database because a
  PostgreSQL connection is bound to one database.
- `DB_PATH`, shared data directories, and the old multi-process PGlite lock
  risk no longer apply.

Connection settings are `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`,
`BRONZE_PGDATABASE`, and `SILVER_PGDATABASE`. Provisioning and verification
commands are documented in [SetupPG.md](SetupPG.md).

The Tally silver transform is implemented in `server/transformTally.ts` and
run with `npm run transform:silver`. It consumes the five normalized Tally
bronze tables and writes their typed counterparts in silver.
