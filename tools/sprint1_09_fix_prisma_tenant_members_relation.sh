#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEMA="apps/api/prisma/schema.prisma"
test -f "$SCHEMA" || { echo "❌ Missing $SCHEMA"; exit 1; }

echo "✅ Repo root: $ROOT"
echo "🔧 Patching Prisma schema: ensure Tenant has members Member[] ..."

node <<'NODE'
const fs = require("fs");
const p = "apps/api/prisma/schema.prisma";
let s = fs.readFileSync(p, "utf8");

const m = s.match(/model\s+Tenant\s*\{[\s\S]*?\n\}/);
if (!m) {
  console.error("❌ Could not find `model Tenant { ... }` in schema.prisma");
  process.exit(1);
}

const block = m[0];

// already has opposite field
if (/\n\s*members\s+Member\[\]\s*/.test(block)) {
  console.log("ℹ️ Tenant already has `members Member[]` — nothing to change.");
  process.exit(0);
}

// Insert near the end of Tenant model, before closing brace
const patched = block.replace(/\n\}\s*$/, "\n\n  // Opposite side of Member.tenant relation\n  members   Member[]\n}\n");

s = s.replace(block, patched);
fs.writeFileSync(p, s, "utf8");
console.log("✅ Added `members Member[]` to Tenant model.");
NODE

echo ""
echo "🧹 Formatting Prisma schema (best effort)..."
pnpm --filter api exec prisma format || true

echo ""
echo "✅ Now re-run migrate + generate:"
echo "  pnpm --filter api db:migrate -- --name sprint1_members"
echo "  pnpm --filter api db:generate"
