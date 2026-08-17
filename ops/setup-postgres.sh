#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -f .env ]; then
  echo "ERROR: .env does not exist. Copy .env.example to .env and configure it first." >&2
  exit 1
fi

# Export the dotenv values for this process. Values containing #, spaces, or
# shell metacharacters must be quoted in .env (for example PGPASSWORD='abc#123').
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${PGUSER:?PGUSER must be set in .env}"
: "${PGPASSWORD:?PGPASSWORD must be set in .env}"
: "${BRONZE_PGDATABASE:?BRONZE_PGDATABASE must be set in .env}"
: "${SILVER_PGDATABASE:?SILVER_PGDATABASE must be set in .env}"

API_USER=$PGUSER
API_PASSWORD=$PGPASSWORD
BRONZE_DATABASE=$BRONZE_PGDATABASE
SILVER_DATABASE=$SILVER_PGDATABASE
BRONZE_OWNER=${BRONZE_PGOWNER:-nfletl}

# The setup connection is made as the local postgres administrator. Remove the
# application's PG* connection variables so they cannot redirect that admin
# connection or try to authenticate it as nfldataapi.
unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD

if [ "$(id -un)" = "postgres" ]; then
  ADMIN_COMMAND=(psql -d postgres)
elif command -v sudo >/dev/null 2>&1; then
  ADMIN_COMMAND=(sudo -u postgres psql -d postgres)
else
  echo "ERROR: run this script as postgres or install/configure sudo." >&2
  echo "For a remote server, use the manual administrator command in SetupPG.md." >&2
  exit 1
fi

"${ADMIN_COMMAND[@]}" \
  --set=api_user="$API_USER" \
  --set=api_password="$API_PASSWORD" \
  --set=bronze_db="$BRONZE_DATABASE" \
  --set=bronze_owner="$BRONZE_OWNER" \
  --set=silver_db="$SILVER_DATABASE" \
  --file=ops/setup-postgres.sql
