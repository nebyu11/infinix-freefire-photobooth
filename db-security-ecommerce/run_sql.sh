#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_sql.sh - run one or more SQL scripts with sqlcmd (Linux / macOS / Docker).
# Windows users: use run_sql.ps1 instead (same idea, PowerShell syntax).
#
# Usage:
#   ./run_sql.sh                       # run ALL scripts 01..07 in order
#   ./run_sql.sh sql/03_rbac.sql       # run a single script
#
# Why a runner? The scripts use sqlcmd variables such as $(APP_PASSWORD)
# so that NO real password is written inside the .sql files. This runner
# reads the values from .env and passes them with  -v NAME="value".
# Scripts run as "sa" (the administrator) because they create logins,
# certificates and keys. The web app itself NEVER uses sa.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

# Read .env line by line (values may contain spaces, so we don't 'source' it)
declare -A ENV
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  ENV["$key"]="$value"
done < .env

VARS=(APP_PASSWORD LEGACY_APP_PASSWORD STAFF_PASSWORD DEMO_USER_PASSWORD
      MASTER_KEY_PASSWORD CERT_BACKUP_PASSWORD)
VAR_ARGS=()
for v in "${VARS[@]}"; do VAR_ARGS+=(-v "$v=${ENV[$v]}"); done

if [[ $# -eq 0 ]]; then
  set -- sql/01_schema.sql sql/02_password_policy.sql sql/03_rbac.sql \
         sql/04_abac.sql sql/05_stored_procedures.sql sql/06_tde.sql sql/07_mfa.sql
fi

for f in "$@"; do
  echo "=================== Running $f ==================="
  # -C  trust the server's self-signed TLS certificate (local lab only)
  # -b  stop with an error code if a statement fails unexpectedly
  # -I  QUOTED_IDENTIFIER ON (required for filtered indexes / computed columns)
  # -W  trim trailing spaces so result columns are readable
  sqlcmd -S "${ENV[DB_SERVER]}" -U sa -P "${ENV[SA_PASSWORD]}" -C -b -I -W \
         "${VAR_ARGS[@]}" -i "$f"
done
