# Migrating off PGlite to real PostgreSQL

This is phase 2 of the migration described in NFLETL's
[`postgresql.md`](../NFLETL/postgresql.md) — read that first for the "why"
(the 2026-08-17 `bronze.db` corruption incident and PGlite's lack of
crash-safety guarantees). NFLETL has already moved to a real Postgres 17
server for `bronze`; this doc covers moving this repo's read path off PGlite
to match, plus wiring for the `silver` database this repo will eventually own.

Assumption for this work: the Postgres 17 server is already running, and the
`bronze` database is already fully rebuilt and populated by NFLETL before any
code here changes — this repo never writes to or bootstraps `bronze`.

## Target architecture (recap)

| Database | Owner | This repo's access |
| --- | --- | --- |
| `bronze` | NFLETL | `nfldataapi` role, `SELECT` only |
| `silver` | this repo (deferred) | `nfldataapi` role, full read/write, once silver work starts |

Same Postgres role (`nfldataapi`) used for both — Postgres roles are
cluster-wide, so one role can hold different grants in different databases.
A single connection is still bound to one database at a time, so this repo
needs its own connection **pool per database**, not one pool doing both.

Per the existing README, silver's actual schema is **deliberately deferred**
until real source schemas are visible side by side — this migration only
needs to get the *connection* plumbing in place, not design silver tables.

## Host/ops prerequisites (not app-managed)

Done once against the already-running server, alongside (or as an extension
of) the role setup in NFLETL's doc:

1. Create the `nfldataapi` role if it doesn't already exist (NFLETL's setup
   may have created it already for the bronze grant).
2. `GRANT CONNECT ON DATABASE bronze TO nfldataapi;` +
   `GRANT SELECT ON ALL TABLES IN SCHEMA bronze TO nfldataapi;` (NFLETL's
   `ALTER DEFAULT PRIVILEGES` should already cover future tables — confirm
   rather than re-grant).
3. Creating the `silver` database and granting `nfldataapi` ownership of it
   is **not required for this phase** — defer until silver schema work
   actually starts, to avoid an empty, unused database hanging around.

## App changes

### `server/config.ts`

- Drop `dbPath`.
- Add connection config for the bronze pool, reusing shared libpq env vars
  for host/user/password and a dedicated var for the database name (since a
  single `PGDATABASE` can't serve two pools):
  ```
  PGHOST=localhost
  PGPORT=5432
  PGUSER=nfldataapi
  PGPASSWORD=
  BRONZE_PGDATABASE=bronze
  ```
- Leave a `SILVER_PGDATABASE` var documented but unused/commented out in
  `.env.example` until the silver pool is actually added.

### `server/db.ts`

- Swap `@electric-sql/pglite` for `pg`, same as NFLETL:
  ```ts
  import { Pool } from 'pg';
  export const db = new Pool({ database: config.bronze.database });
  ```
  (`Pool` falls back to `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD` env vars for
  any field not passed explicitly, so only `database` needs overriding here.)
- Add the same preflight connectivity check pattern NFLETL uses in
  `initDb()` — a trivial `SELECT 1` on startup that throws a clear
  `host:port/database as user` error instead of letting a connection failure
  surface as an opaque stack trace.
- No schema bootstrap needed here — this repo never creates bronze tables,
  only queries them. `listLandingTables()`, `landingTableName()`, and all
  the `server/index.ts` route handlers keep their existing SQL unchanged;
  they only depend on `db.query()`, not on PGlite specifically.
- Because `nfldataapi` only has `SELECT` on `bronze`, any accidental write
  (there currently are none) would be rejected by Postgres itself — the
  read-only contract becomes enforced by the database, not just by the
  `README`'s comment as it is today.

### `server/index.ts`

- No route logic changes expected — every handler already goes through
  `db.query()`/`listLandingTables()`. Verify after the swap that error
  handling still makes sense (`pg` error shapes differ slightly from
  PGlite's).

## Not in scope for this phase

- Silver schema design and the `silver` pool/connection — tracked as future
  work per the README's existing "deliberately deferred" stance. When that
  work starts, add a second `Pool({ database: config.silver.database })` in
  `db.ts`, provision the `silver` database per the ops step above, and give
  this repo its own idempotent bootstrap DDL (mirroring NFLETL's
  `initDb()` pattern) at that point — not now.

## Cleanup once this phase is done

- Update `README.md`: drop the "Known risk: concurrent access to bronze.db"
  section (no longer applicable — real Postgres handles concurrent
  connections natively) and the `DB_PATH`/PGlite-directory language in
  "Architecture" and "Layout".
- Update `.env.example` and `start.sh`/`start.bat` prerequisite checks if
  they reference `DB_PATH` or PGlite directly.
