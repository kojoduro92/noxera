#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "✅ Repo root: $ROOT"
echo "🧾 Node: $(node -v)"
echo "🧾 pnpm: $(pnpm -v)"
echo ""

echo "=== apps ==="
ls -la apps || true
echo ""

echo "=== apps/api/package.json scripts ==="
node -e 'const p=require("./apps/api/package.json"); console.log(Object.keys(p.scripts||{}).sort().map(k=>`${k}: ${p.scripts[k]}`).join("\n") || "(no scripts)")'
echo ""

echo "=== Find Prisma schema ==="
SCHEMA="$(find apps/api -maxdepth 4 -name "schema.prisma" | head -n 1 || true)"
echo "schema: ${SCHEMA:-NOT FOUND}"
if [ -n "${SCHEMA:-}" ]; then
  echo ""
  echo "--- Does schema already have Member model? ---"
  grep -n "model Member" "$SCHEMA" || echo "NO: model Member not found"
  echo ""
  echo "--- Does schema have AuditLog model? ---"
  grep -n "model Audit" "$SCHEMA" || echo "NO: model Audit* not found"
fi
echo ""

echo "=== Find Nest AppModule ==="
APPMOD="$(find apps/api/src -maxdepth 3 -name "app.module.ts" | head -n 1 || true)"
echo "app.module.ts: ${APPMOD:-NOT FOUND}"
echo ""

echo "=== Find PrismaService location ==="
PRISMA_SVC="$(find apps/api/src -name "prisma.service.ts" | head -n 1 || true)"
if [ -z "${PRISMA_SVC:-}" ]; then
  PRISMA_SVC="$(grep -RIl "extends PrismaClient" apps/api/src | head -n 1 || true)"
fi
echo "prisma service: ${PRISMA_SVC:-NOT FOUND}"
echo ""

echo "=== Top-level API modules (folders) ==="
find apps/api/src -maxdepth 2 -type d | sed 's|^| - |'
echo ""
