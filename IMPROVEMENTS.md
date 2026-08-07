# Improvements

Findings from a senior-engineer code review, written to be portable across the
sibling Raptor/mill-data API projects that share this codebase's shape
(Express + PGlite/sqlite bronze ingestion + a small React viewer). Each item
describes what to check/fix and why, independent of any one repo's exact line
numbers. A "status in this repo" note is included per item for this specific
checkout; when copying this file into a sibling project, reset the status
column for that repo's own audit.

Status legend: **Fixed** / **Deferred** / **Not started**

---

## 1. Unhandled async errors can crash the whole process — Fixed

**Check:** Are Express route handlers `async` functions with no try/catch,
running on Express 4.x (which does not auto-catch rejected promises from
async handlers)? Is there a global error-handling middleware (4-arg
`(err, req, res, next)`) registered last? Is there a
`process.on('unhandledRejection', ...)` safety net?

**Why it matters:** If any of the above is missing, a single bad request
(malformed query param causing a thrown error, a transient DB error, etc.)
becomes an unhandled promise rejection. Since Node 15, unhandled rejections
terminate the process by default. That turns an ordinary input-validation bug
into a full outage — anyone who can send a request can take the service
down.

**Fix pattern:** Wrap every async route handler (an `asyncHandler` helper
that forwards rejections to `next(error)` is enough), add one global error
middleware at the end of the middleware chain that logs the error and returns
a safe response, and add process-level `unhandledRejection` /
`uncaughtException` listeners that log rather than let the default handler
kill the process. Also validate any `Number(req.query.x)` parsing — an
invalid string produces `NaN`, which should never reach a SQL `LIMIT`/`OFFSET`
parameter unchecked.

**Status in this repo:** Fixed. Added `asyncHandler` wrapper around every
route in `server/index.ts`, a global error-handling middleware, process-level
`unhandledRejection`/`uncaughtException` logging, and a `parseIntParam()`
helper used for all `limit`/`offset` query parsing so invalid input falls
back to a safe default instead of reaching the DB layer.

---

## 2. No authentication/authorization + wide-open CORS — DEFERRED (this repo)

**Check:** Is CORS enabled with no origin allowlist (e.g. `app.use(cors())`
with no options)? Does any route — especially ones that mutate state (trigger
ingestion) or return raw data — require no credential of any kind? Does the
service bind to `0.0.0.0` by default?

**Why it matters:** With open CORS and no auth, any web page a browser with
network access to the service loads can call these APIs cross-origin, and
anyone who can reach the port can read all landed data or trigger expensive
operations (e.g. a full source-DB scan) with no credential. This matters more
as soon as the service is reachable from anywhere beyond a single trusted
operator's machine.

**Fix pattern:** Add a minimal auth gate appropriate to the deployment (a
shared API key header is usually enough for an internal tool; something
stronger if it's ever exposed beyond a trusted network) and restrict CORS to
known origins instead of the default wide-open behavior.

**Status in this repo:** **Deferred, intentionally.** This instance is fully
internal and IT-only (not reachable outside the trusted network), so
auth/CORS hardening is not being implemented here right now. This item is
documented so it isn't forgotten, and so sibling projects with different
exposure can judge it for themselves rather than inherit this repo's
decision. Revisit if this instance's network exposure ever changes.

---

## 3. Unbounded full-table reads can OOM the process — Fixed

**Check:** Does the ingestion path ever do the equivalent of `SELECT *` and
materialize an entire source table into memory at once (e.g.
`.all()`/`result.rows` with no `LIMIT`)? Is there an existing pattern (a
watermark/incremental-read mechanism) for known-huge tables, and does it only
cover tables that have been explicitly enumerated?

**Why it matters:** Any table not on the "known huge, handled incrementally"
list is a memory-exhaustion risk the moment it grows past what fits
comfortably in process memory — which is exactly the situation for any
not-yet-profiled source (new source system, unknown schema, unknown row
counts). A full-table read that used to be safe can silently become an outage
as the source data grows, with no warning beforehand.

**Fix pattern:** At minimum, cap full-table reads at a safe row ceiling and
log a warning when a table hits the cap (pointing at the existing incremental
mechanism as the real fix), so the process degrades to
"this table may be truncated this cycle" instead of crashing. A fuller fix is
to profile/paginate all sources rather than special-casing only the tables
known to be huge today.

**Status in this repo:** Fixed. Added a `FULL_SCAN_ROW_CAP` (env-overridable,
default 500,000 rows) applied as a `LIMIT` in both `sqliteSource.readRows`
and `pgliteSource.readRows`; a warning is logged when a table's full scan
hits the cap, pointing at `INCREMENTAL_TABLES` as the real fix. This bounds
memory but does not by itself guarantee completeness for a table that
exceeds the cap — the warning is the signal to add that table to the
incremental list.

---

## 4. Raw exception messages returned to API callers — Fixed

**Check:** Do error handlers do anything like
`res.status(500).json({ error: error.message })`, passing the raw exception
text straight through to the HTTP response?

**Why it matters:** Raw error messages can leak internal detail — file
paths, SQL fragments, library internals — to whoever made the request. Minor
on its own, but combined with weak/no auth (see #2) it's free reconnaissance
for anyone probing the service, and it's a bad habit regardless.

**Fix pattern:** Log the full error server-side (with enough context to
debug), and return a generic, safe message to the caller. It's fine to
special-case a short list of known, intentionally-thrown, safe-to-show
messages (e.g. "a scan is already in progress") — the goal is to stop
*unexpected* exceptions from leaking, not to hide deliberate user-facing
errors.

**Status in this repo:** Fixed. The global error middleware and the
`/api/ingest/scan` handler now log full errors via `console.error` and return
a generic message for unexpected errors, while still surfacing a small
allowlist of known, safe, expected conditions (unknown source name, scan
already in progress) verbatim since those aren't leaking anything sensitive.

---

## 5. N+1 query pattern for per-table counts — Fixed

**Check:** Is there a "list tables, then loop and run one query per table"
pattern (e.g. `COUNT(*)` per table) that runs on every request to a summary
or listing endpoint?

**Why it matters:** Fine at small scale, but it means response time scales
linearly with the number of landing tables, and it runs redundantly on
endpoints that don't even need per-table counts (e.g. just checking a table
exists). This is the kind of thing that "quietly gets slow" as a source
system's table count grows.

**Fix pattern:** Batch the count into fewer round trips — e.g. build one
combined query (a `UNION ALL` of per-table counts, since the table list is
dynamic) instead of one query per table — or use a cheaper existence check
for callers that don't need row counts at all.

**Status in this repo:** Fixed. `listLandingTables()` in `server/db.ts` now
issues one query to list tables and a second combined query (`UNION ALL`)
to get all row counts at once, instead of one `COUNT(*)` per table.

---

## 6. No automated tests around data-integrity-critical logic — Fixed

**Check:** Is there test coverage for the hashing/dedupe logic that decides
whether a row is "new" on a rescan, the `ON CONFLICT ... DO NOTHING` dedupe
path, watermark/incremental-read advancement, and any identifier-sanitization
helpers (e.g. table-name cleaning used to build dynamic SQL identifiers)?

**Why it matters:** This is exactly the logic where a silent regression
(e.g. a change to how a hash is computed, or an off-by-one in watermark
advancement) would quietly duplicate or drop production data without any
visible error — it wouldn't crash, it would just be wrong, and wrong in a way
that's hard to notice until someone audits row counts.

**Fix pattern:** Add focused unit/integration tests for: hash stability
(same content in any key order hashes the same; different
source/table/content hashes differently), the dedupe-on-rescan behavior
(identical row lands once; a changed row lands as a new version), watermark
advancement across paginated reads, and identifier sanitization. Prefer a
zero/low-dependency test runner if the project doesn't already have one
(e.g. Node's built-in test runner) to keep the fix low-friction to copy
into sibling projects.

**Status in this repo:** Fixed. Added `server/db.test.ts` and
`server/ingest.test.ts` using Node's built-in `node:test` runner (run via
`tsx --test`, no new dependency). Each test file uses its own temp PGlite
data directory (via `fs.mkdtempSync` + `os.tmpdir()`, cleaned up after)
rather than the real dev bronze database. Coverage: `rowHash` stability and
uniqueness, `landRows` dedupe-on-conflict and new-version-on-change,
`ingestTable`'s watermark advancement across paginated reads, and
`landingTableName` sanitization. Run via `npm test`.

---

## 7. Frontend fetches don't surface failures — Fixed

**Check:** Do client-side data-loading functions check `response.ok` and
catch network failures, or do they assume every fetch succeeds and just
`.json()` the result?

**Why it matters:** When (not if) a request fails — network blip, backend
500, backend down for a deploy — the UI should say so. Silent failure (a
spinner that clears with nothing loaded, or a stale/empty view with no
explanation) makes every other bug in the system harder to diagnose, because
the person looking at the screen has no idea something went wrong.

**Fix pattern:** Check `response.ok` (and/or wrap in try/catch for network
errors), and surface a visible, dismissable error state in the UI rather than
only a console error.

**Status in this repo:** Fixed. `loadData()` and `loadRows()` in
`client/src/App.tsx` now check `response.ok`, catch thrown errors, and set an
`error` state that's rendered as an inline banner instead of failing
silently.

---

## 8. Blocking `alert()` for async operation results — Fixed

**Check:** Does the UI use `alert()`/`confirm()`/`prompt()` to report the
result of an async action?

**Why it matters:** Not a bug, but a UX rough edge users hit on every use —
blocking browser dialogs are jarring, can't be styled, and stack awkwardly if
triggered more than once. Cheap to fix while touching the surrounding code.

**Fix pattern:** Replace with inline UI state (a status/result banner in the
component) that updates in place.

**Status in this repo:** Fixed. `triggerScan()` in `client/src/App.tsx` now
sets a `scanResult` state (rendered inline, with a dismiss control) instead
of calling `alert()`.

---

## 9. Catch-all SPA route swallows unmatched API paths — Fixed

**Check:** If there's a catch-all `GET *` route for SPA client-side routing,
is it registered so that it also matches unmatched/typoed API paths (e.g.
`/api/whatever-that-doesnt-exist`), silently returning the SPA's `index.html`
(200, HTML) instead of a 404?

**Why it matters:** A moved or typoed API endpoint then looks like a
"successful" response (200 OK) until client code tries to parse HTML as JSON
and fails somewhere downstream — a confusing failure mode that hides what's
actually a straightforward routing bug.

**Fix pattern:** Add an explicit "unmatched `/api/*` path" handler that
returns 404 JSON, registered after all real API routes but before the
static-file/SPA catch-all.

**Status in this repo:** Fixed. `server/index.ts` now has an
`app.use('/api', ...)` 404 JSON handler registered after all real API routes
and before `express.static`/the SPA catch-all.

---

## 10. Bronze/append-only data-modeling gotcha undocumented — Fixed

**Check:** If the bronze/landing layer is append-only (a changed source row
lands as a *new* row rather than updating in place, keyed by a content hash),
is that documented anywhere a consumer of the raw/bronze API would see it?

**Why it matters:** Without this documented, it's genuinely confusing the
first time someone sees two, three, or a dozen rows in a bronze table that
all represent "the same" upstream record at different points in time. It's
correct behavior for a bronze layer, but only if the consumer knows to
dedupe by picking the latest version per business key themselves.

**Fix pattern:** A short note in the README/API docs (and ideally a code
comment near the landing/insert logic) stating explicitly: bronze tables are
append-only; a changed row lands as a new version; consumers must dedupe by
selecting the latest `ingested_at`/`batch_id` (or equivalent) per business
key.

**Status in this repo:** Fixed. Added a note to the README's Ingestion
section and a comment above `ensureLandingTable` in `server/db.ts`.

---

## Notes for applying this file to a sibling project

- Re-verify each item against that repo's actual code — line numbers and
  even whole mechanisms (e.g. the incremental-watermark pattern referenced in
  #3) may not exist there in the same form.
- Re-decide #2 independently per repo/deployment — don't inherit this repo's
  "deferred" status without checking that repo's actual network exposure.
- Reset the status column to **Not started** for items not yet addressed in
  the target repo.
