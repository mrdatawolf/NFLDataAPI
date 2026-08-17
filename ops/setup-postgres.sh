#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -f .env ]; then
  echo "ERROR: .env does not exist. Copy .env.example to .env and configure it first." >&2
  exit 1
fi

# Read only the keys needed for provisioning. Do not `source .env`: dotenv
# permits values that are not valid shell syntax, and a sourced file could
# execute arbitrary commands. The final definition of a repeated key wins.
read_dotenv_value() {
  local key=$1 line value=''
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [[ $line == "$key="* ]]; then
      value=${line#*=}
    fi
  done < .env

  if [[ $value == \"*\" && $value == *\" ]]; then
    value=${value:1:${#value}-2}
  elif [[ $value == \'*\' && $value == *\' ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

API_USER=$(read_dotenv_value PGUSER)
API_PASSWORD=$(read_dotenv_value PGPASSWORD)
BRONZE_DATABASE=$(read_dotenv_value BRONZE_PGDATABASE)
SILVER_DATABASE=$(read_dotenv_value SILVER_PGDATABASE)
BRONZE_OWNER=$(read_dotenv_value BRONZE_PGOWNER)
BRONZE_OWNER=${BRONZE_OWNER:-nfletl}

: "${API_USER:?PGUSER must be set in .env}"
: "${API_PASSWORD:?PGPASSWORD must be set in .env}"
: "${BRONZE_DATABASE:?BRONZE_PGDATABASE must be set in .env}"
: "${SILVER_DATABASE:?SILVER_PGDATABASE must be set in .env}"

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
