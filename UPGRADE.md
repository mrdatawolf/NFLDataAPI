# Dependency Upgrade — 2026-07-31

Record of bringing every dependency to its latest stable major version, and
the process used to do it safely. Written to be portable across the sibling
Raptor/mill-data API projects that share this codebase's shape (Express +
PGlite/sqlite bronze ingestion + a small React viewer) and this same
dependency set.

## Target versions

| Package | Before | After |
|---|---|---|
| dotenv | 16.6.1 | 17.4.2 |
| concurrently | 9.2.4 | 10.0.4 |
| @types/node | 22.20.1 | 24.13.3 (see note below — do not blindly take "latest") |
| better-sqlite3 | 11.10.0 | 13.0.2 |
| @types/better-sqlite3 | 7.6.12 | 7.6.13 |
| @electric-sql/pglite | 0.2.17 | 0.5.4 |
| vite | 5.4.21 | 8.2.0 |
| @vitejs/plugin-react | 4.7.0 | 6.0.5 |
| react / react-dom | 18.3.1 | 19.2.8 |
| @types/react / @types/react-dom | 18.3.x | 19.2.x |
| express | 4.22.2 | 5.2.1 |
| @types/express | 4.17.25 | 5.0.6 |
| typescript | 5.9.3 | 7.0.2 (native/Go compiler) |

**`@types/node` gotcha:** don't just take `npm outdated`'s "Latest" column.
Run `node -v` first and pin `@types/node` to match your *actual* Node runtime
major, not whatever the newest published major is — types for a newer Node
than you're actually running can document APIs that don't exist in your
environment yet. Re-check this per repo/per environment; it won't be the
same number everywhere.

## Process

Upgrade in groups, not all at once — run typecheck + build + test after each
group and fix what breaks before moving to the next. This isolates which
upgrade caused which break instead of debugging everything at the end.

1. **Low-risk first:** `dotenv`, `concurrently`, `@types/node` (pinned per
   the note above).
2. **Native/DB modules:** `better-sqlite3` + `@types/better-sqlite3`,
   `@electric-sql/pglite`. Check changelogs for on-disk/ABI breaking changes
   before assuming data compatibility (see gotcha below).
3. **Vite + its React plugin together** (must stay compatible with each
   other): `vite`, `@vitejs/plugin-react`.
4. **React together with its types:** `react`, `react-dom`, `@types/react`,
   `@types/react-dom`.
5. **Express together with its types:** `express`, `@types/express`.
6. **TypeScript:** `typescript`.

After each group:
```
npm install
npx tsc -p tsconfig.server.json --noEmit
npx tsc -p client/tsconfig.json --noEmit   # if the client has its own tsconfig
npm run build
npm test
```

After the last group, do a full runtime smoke test, not just typecheck/build:
- Start the built server and hit every route, including one deliberately bad
  input (e.g. `?limit=notanumber`) and one deliberately unmatched path — the
  process should survive both and return sane responses (not a crash, not a
  200-with-HTML for an API 404).
- Start the Vite dev server and confirm the root path returns the real HTML
  shell with the dev-mode client script tags, not an error page.

## Gotchas hit in this repo (expect these in the siblings too)

**PGlite's on-disk format is not stable across pre-1.0 minor versions.**
Bumping `@electric-sql/pglite` (e.g. 0.2.x → 0.5.x) can leave an existing
`DB_PATH` data directory unreadable (`PGlite failed to initialize properly`)
even though no application code changed. If the bronze layer is regenerable
from source via a rescan, the fix is to rename/back up the old data directory
(don't delete — keep it until you're sure you don't need it) and let a fresh
one get created on next start. Check PGlite's release notes for a stated
migration path before assuming a rename-and-rescan is safe for a given jump —
this may not hold for every version gap.

**Express 5 (path-to-regexp v8) rejects a bare `'*'` wildcard route.** Any
SPA catch-all (`app.get('*', ...)`) throws at server startup with
`PathError: Missing parameter name at index 1: *`. Replace with
`app.get('/{*splat}', ...)` — the `{}` makes the wildcard segment optional so
it still matches `/` the same way `'*'` used to. Note `'/*splat'` **without**
braces does *not* match `/` — an easy way to silently break the root route if
you get this wrong. Verify empirically (curl `/` after the change) rather
than trusting it typechecks.

**Express 5 route params can now be `string | string[]`**, not just
`string` — repeatable named segments are supported, which changes the type
of `req.params.x`. Normalize defensively (a small helper that takes the
first value if an array) rather than casting the type away.

**Express 5 natively forwards rejected promises from async route handlers to
the error middleware.** If the app has a manual `asyncHandler`-style wrapper
that existed only to work around Express 4 not doing this, it's redundant
after the upgrade and can be removed — but verify this empirically (a quick
standalone test: async handler throws, confirm the error middleware catches
it with no wrapper) before relying on it, don't take it on faith.

**dotenv 17 prints an "injected env" banner by default.** Pass
`{ quiet: true }` to `dotenv.config()` at every call site if you don't want
the noise — purely cosmetic, not a functional change.

**TypeScript 7 (the native Go-based compiler)** typechecked this codebase
with zero new diagnostics — no code changes needed here. Still worth a full
`--noEmit` pass on every tsconfig in the repo since compiler behavior is a
from-scratch reimplementation, not a guaranteed no-op elsewhere.

**Test files leaking into the production build.** If tests live under
`server/**/*.test.ts` and `tsconfig.server.json` includes `server/**/*.ts`
with no exclude, they'll compile straight into `dist/`. Add
`"exclude": ["server/**/*.test.ts"]` to the server tsconfig. (Not caused by
this upgrade, but surfaced during verification — worth checking regardless
of whether you're mid-upgrade.)

## Result

Every package reached its latest major cleanly in this repo — nothing had to
be held back on an older major. That won't necessarily hold in a sibling repo
with different code paths (e.g. heavier use of an Express 4-only API, or
client code more sensitive to the React 19 changes) — re-run the full
group-by-group process and don't assume a clean pass here predicts a clean
pass there.
