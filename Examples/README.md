# Examples

Clones of the source databases used for local development. Everything in this
folder except this README is gitignored because these are copies of production
data.

Expected layout:

```
Examples/
  SawFilers/app-db.sqlite3   # clone of the saw filing room app database (Prisma/SQLite)
  Raptor/...                 # clone of the Raptor database (path set in .env)
```

Point the `*_PATH` variables in `.env` at these files/directories.
