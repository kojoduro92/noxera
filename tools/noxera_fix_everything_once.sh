#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Find repo root (must contain apps/api)
# -----------------------------
ROOT="$PWD"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/apps/api" ]; do
  ROOT="$(dirname "$ROOT")"
done
[ -d "$ROOT/apps/api" ] || { echo "❌ Could not find repo root containing apps/api from: $PWD"; exit 1; }
cd "$ROOT"
echo "✅ Repo root: $ROOT"

API_ENV="$ROOT/apps/api/.env"
[ -f "$API_ENV" ] || { echo "❌ Missing apps/api/.env"; exit 1; }

# -----------------------------
# Read + sanitize DATABASE_URL
# - remove quotes
# - remove trailing semicolon
# - force mysql:// scheme (Prisma requires mysql/postgresql/etc, NOT mariadb)
# -----------------------------
RAW="$(grep -E '^DATABASE_URL=' "$API_ENV" | tail -n 1 | cut -d= -f2- || true)"
RAW="$(echo "$RAW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# strip wrapping quotes
if [[ "$RAW" =~ ^\".*\"$ ]]; then RAW="${RAW:1:${#RAW}-2}"; fi
if [[ "$RAW" =~ ^\'.*\'$ ]]; then RAW="${RAW:1:${#RAW}-2}"; fi

# remove trailing ;
RAW="${RAW%;}"

# convert mariadb:// -> mysql://
RAW="${RAW/mariadb:\/\//mysql:\/\/}"

if [[ "$RAW" != mysql://* ]]; then
  echo "❌ DATABASE_URL must start with mysql:// after normalization"
  echo "   Found: $RAW"
  exit 1
fi

echo "✅ Normalized DATABASE_URL: $RAW"

# -----------------------------
# Write normalized DATABASE_URL back to apps/api/.env (no quotes)
# (prevents runtime weirdness too)
# -----------------------------
TMP="$(mktemp)"
awk -v url="$RAW" '
  BEGIN { done=0 }
  /^DATABASE_URL=/ { print "DATABASE_URL=" url; done=1; next }
  { print }
  END { if (!done) print "DATABASE_URL=" url }
' "$API_ENV" > "$TMP"
mv "$TMP" "$API_ENV"
echo "✅ Updated apps/api/.env (DATABASE_URL unquoted + mysql://)"

# -----------------------------
# Choose schema (prefer apps/api/prisma/schema.prisma; fallback prisma/schema.prisma)
# We'll FORCE --schema to avoid prisma.config.ts surprises.
# -----------------------------
SCHEMA=""
if [ -f "$ROOT/apps/api/prisma/schema.prisma" ]; then
  SCHEMA="$ROOT/apps/api/prisma/schema.prisma"
elif [ -f "$ROOT/prisma/schema.prisma" ]; then
  SCHEMA="$ROOT/prisma/schema.prisma"
else
  echo "❌ Could not find schema at apps/api/prisma/schema.prisma or prisma/schema.prisma"
  exit 1
fi
echo "✅ Using schema: $SCHEMA"

SCHEMA_DIR="$(dirname "$SCHEMA")"
# Prisma loads env from schema folder; ensure clean .env there too
echo "DATABASE_URL=$RAW" > "$SCHEMA_DIR/.env"
echo "✅ Wrote $SCHEMA_DIR/.env (for Prisma CLI)"

# -----------------------------
# Ensure MariaDB container is running
# - try docker compose service "mariadb"
# - fallback to container name noxera-mariadb
# -----------------------------
if docker compose ps --services 2>/dev/null | grep -qx "mariadb"; then
  if ! docker compose ps -q mariadb | grep -q .; then
    echo "🐳 Starting docker compose mariadb..."
    docker compose up -d mariadb
  fi
else
  # fallback: container name
  if ! docker ps --format '{{.Names}}' | grep -qx "noxera-mariadb"; then
    if docker ps -a --format '{{.Names}}' | grep -qx "noxera-mariadb"; then
      echo "🐳 Starting existing container: noxera-mariadb"
      docker start noxera-mariadb >/dev/null
    else
      echo "⚠️ Could not find docker compose service 'mariadb' or container 'noxera-mariadb'."
      echo "   Run: docker ps"
      exit 1
    fi
  fi
fi

# quick DB ping (best-effort)
echo "🔌 DB ping (best effort)..."
USERPASS_HOSTDB="${RAW#mysql://}"
USERPASS="${USERPASS_HOSTDB%@*}" || true
DB_USER="${USERPASS%%:*}" || true
DB_PASS="${USERPASS#*:}" || true

if docker compose ps --services 2>/dev/null | grep -qx "mariadb"; then
  docker compose exec -T mariadb mariadb -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1;" >/dev/null 2>&1 || true
else
  docker exec -i noxera-mariadb mariadb -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1;" >/dev/null 2>&1 || true
fi
echo "✅ DB container looks up."

# -----------------------------
# Run Prisma (force schema + force DATABASE_URL env)
# -----------------------------
echo "🧱 prisma db push..."
DATABASE_URL="$RAW" pnpm -C apps/api exec prisma db push --schema "$SCHEMA"

echo "⚙️ prisma generate..."
DATABASE_URL="$RAW" pnpm -C apps/api exec prisma generate --schema "$SCHEMA"

# -----------------------------
# Seed (must run where @prisma/client is available)
# -----------------------------
if [ -f "$ROOT/apps/api/tools/seed_first_plan.mjs" ]; then
  echo "🌱 seed (apps/api/tools/seed_first_plan.mjs)..."
  (cd apps/api && DATABASE_URL="$RAW" node tools/seed_first_plan.mjs)
elif [ -f "$ROOT/tools/seed_first_plan.mjs" ]; then
  echo "🌱 seed (copying root tools/seed_first_plan.mjs into apps/api/tools)..."
  mkdir -p "$ROOT/apps/api/tools"
  cp -f "$ROOT/tools/seed_first_plan.mjs" "$ROOT/apps/api/tools/seed_first_plan.mjs"
  (cd apps/api && DATABASE_URL="$RAW" node tools/seed_first_plan.mjs)
else
  echo "⚠️ Seed file not found (apps/api/tools/seed_first_plan.mjs or tools/seed_first_plan.mjs). Skipping seed."
fi

echo ""
echo "✅ FIXED."
echo "Now restart your API server (Ctrl+C then run it again)."
echo ""
echo "Test session + tenants (adjust port if needed):"
echo "  curl -i -X POST http://localhost:3000/auth/session -H 'content-type: application/json' -d '{\"dev\":true}' -c /tmp/noxera.cookies"
echo "  curl -i http://localhost:3000/admin/tenants -b /tmp/noxera.cookies"
