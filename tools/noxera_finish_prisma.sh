#!/usr/bin/env bash
set -euo pipefail

# find repo root containing apps/api
ROOT="$PWD"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/apps/api" ]; do
  ROOT="$(dirname "$ROOT")"
done
[ -d "$ROOT/apps/api" ] || { echo "❌ Could not find apps/api from: $PWD"; exit 1; }
cd "$ROOT"
echo "✅ Repo root: $ROOT"

# make Prisma CLI env (mysql scheme) next to schema
[ -f apps/api/.env ] || { echo "❌ Missing apps/api/.env"; exit 1; }
mkdir -p apps/api/prisma
perl -pe 's/^(DATABASE_URL=)(\"?)mariadb:\/\//${1}${2}mysql:\/\//i' apps/api/.env > apps/api/prisma/.env
echo "✅ Wrote apps/api/prisma/.env (mysql:// for Prisma CLI)"

# sanity check schema exists
[ -f apps/api/prisma/schema.prisma ] || { echo "❌ Missing apps/api/prisma/schema.prisma"; exit 1; }
echo "✅ Found apps/api/prisma/schema.prisma"

echo "🧱 prisma db push..."
pnpm -C apps/api exec prisma db push

echo "⚙️ prisma generate..."
pnpm -C apps/api exec prisma generate

echo "🌱 seed..."
(cd apps/api && node tools/seed_first_plan.mjs)

echo ""
echo "✅ DONE."
echo "Now restart API (Ctrl+C then run dev again)."
echo ""
echo "Test login + tenants:"
echo "  curl -i -X POST http://localhost:3000/auth/session -H 'content-type: application/json' -d '{\"dev\":true}' -c /tmp/noxera.cookies"
echo "  curl -i http://localhost:3000/admin/tenants -b /tmp/noxera.cookies"
