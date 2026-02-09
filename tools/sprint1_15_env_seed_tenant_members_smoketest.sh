#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

API_ENV="$ROOT/apps/api/.env"
mkdir -p "$(dirname "$API_ENV")"
touch "$API_ENV"

echo "✅ Repo root: $ROOT"

# Find the MariaDB container
CID="$(docker ps --format '{{.ID}} {{.Names}} {{.Image}}' | awk '$2=="noxera-mariadb"{print $1; exit}')"
if [[ -z "${CID:-}" ]]; then
  CID="$(docker ps --format '{{.ID}} {{.Names}} {{.Image}}' | awk '$3 ~ /^mariadb:/{print $1; exit}')"
fi
if [[ -z "${CID:-}" ]]; then
  echo "❌ Could not find MariaDB container (expected name: noxera-mariadb)."
  docker ps
  exit 1
fi

echo "🐳 DB container: $CID"

# Determine host port mapped to 3306
PORT="$(docker port "$CID" 3306/tcp 2>/dev/null | head -n1 | sed 's/.*://')"
if [[ -z "${PORT:-}" ]]; then PORT="3307"; fi

ENVV="$(docker inspect "$CID" --format '{{range .Config.Env}}{{println .}}{{end}}')"

DB_USER="$(echo "$ENVV" | awk -F= '/^(MARIADB_USER|MYSQL_USER)=/ {print $2; exit}')"
DB_PASS="$(echo "$ENVV" | awk -F= '/^(MARIADB_PASSWORD|MYSQL_PASSWORD)=/ {print $2; exit}')"
DB_NAME="$(echo "$ENVV" | awk -F= '/^(MARIADB_DATABASE|MYSQL_DATABASE)=/ {print $2; exit}')"
ROOT_PASS="$(echo "$ENVV" | awk -F= '/^(MARIADB_ROOT_PASSWORD|MYSQL_ROOT_PASSWORD)=/ {print $2; exit}')"

# Sensible fallbacks
[[ -z "${DB_NAME:-}" ]] && DB_NAME="noxera"

# Prefer app user if present, otherwise fall back to root
if [[ -z "${DB_USER:-}" || -z "${DB_PASS:-}" ]]; then
  if [[ -n "${ROOT_PASS:-}" ]]; then
    DB_USER="root"
    DB_PASS="$ROOT_PASS"
  else
    # last fallback (only if container didn't expose creds)
    DB_USER="${DB_USER:-noxera}"
    DB_PASS="${DB_PASS:-noxera}"
  fi
fi

DATABASE_URL="mysql://${DB_USER}:${DB_PASS}@127.0.0.1:${PORT}/${DB_NAME}"
SHADOW_DATABASE_URL="mysql://${DB_USER}:${DB_PASS}@127.0.0.1:${PORT}/${DB_NAME}_shadow"

echo "🔧 Ensuring apps/api/.env has DATABASE_URL + SHADOW_DATABASE_URL"
if ! grep -q '^DATABASE_URL=' "$API_ENV"; then
  echo "DATABASE_URL=\"$DATABASE_URL\"" >> "$API_ENV"
  echo "✅ Added DATABASE_URL"
else
  echo "ℹ️ DATABASE_URL already present"
fi

if ! grep -q '^SHADOW_DATABASE_URL=' "$API_ENV"; then
  echo "SHADOW_DATABASE_URL=\"$SHADOW_DATABASE_URL\"" >> "$API_ENV"
  echo "✅ Added SHADOW_DATABASE_URL"
else
  echo "ℹ️ SHADOW_DATABASE_URL already present"
fi

echo ""
echo "🔎 DATABASE_URL now:"
grep -E '^DATABASE_URL=|^SHADOW_DATABASE_URL=' "$API_ENV" || true

echo ""
echo "▶ Prisma generate"
pnpm --filter api db:generate

echo ""
echo "▶ Prisma seed (creates baseline data: plans/roles/etc)"
pnpm --filter api db:seed

echo ""
echo "🔎 Checking API is running..."
if ! curl -sf http://localhost:3000/health >/dev/null 2>&1; then
  echo "❌ API is not running on :3000"
  echo "Start it in another terminal:"
  echo "  pnpm --filter api dev"
  exit 1
fi
echo "✅ API reachable"

echo ""
echo "▶ Create dev session cookie"
curl -s -X POST http://localhost:3000/auth/session \
  -H 'content-type: application/json' \
  -d '{"dev":true}' \
  -c /tmp/noxera.cookies >/dev/null

echo "▶ List tenants"
TENANTS_JSON="$(curl -s http://localhost:3000/admin/tenants -b /tmp/noxera.cookies)"
echo "$TENANTS_JSON" | jq '.total, (.items[0] // null)'

TENANT_ID="$(echo "$TENANTS_JSON" | jq -r '.items[0].id // empty')"
if [[ -z "${TENANT_ID:-}" ]]; then
  echo ""
  echo "❌ Still no tenants."
  echo "This is expected if seed doesn't create a tenant."
  echo "Create ONE tenant using the superadmin UI:"
  echo "  pnpm --filter web-superadmin dev"
  echo "  Open: http://localhost:3001/churches/new"
  echo "Then rerun:"
  echo "  curl -s http://localhost:3000/admin/tenants -b /tmp/noxera.cookies | jq"
  exit 1
fi

echo ""
echo "✅ Using tenant id: $TENANT_ID"

echo ""
echo "▶ Members smoke test (create + list)"
curl -s -X POST "http://localhost:3000/members" \
  -b /tmp/noxera.cookies \
  -H "content-type: application/json" \
  -H "x-tenant-id: $TENANT_ID" \
  -d '{"firstName":"John","lastName":"Mensah","phone":"+233000000000","status":"ACTIVE"}' | jq

curl -s "http://localhost:3000/members?page=1&pageSize=20" \
  -b /tmp/noxera.cookies \
  -H "x-tenant-id: $TENANT_ID" | jq

echo ""
echo "✅ OK: tenant + members endpoints working."
