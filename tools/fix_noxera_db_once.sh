#!/usr/bin/env bash
set -euo pipefail

# --- find repo root that contains apps/api ---
ROOT="$PWD"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/apps/api" ]; do
  ROOT="$(dirname "$ROOT")"
done
[ -d "$ROOT/apps/api" ] || { echo "❌ Could not find apps/api from: $PWD"; exit 1; }
cd "$ROOT"
echo "✅ Repo root: $ROOT"

ENV_FILE="apps/api/.env"
[ -f "$ENV_FILE" ] || { echo "❌ Missing $ENV_FILE"; exit 1; }

DB_LINE="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | tail -n 1 || true)"
[ -n "${DB_LINE:-}" ] || { echo "❌ DATABASE_URL missing in $ENV_FILE"; exit 1; }
echo "✅ $DB_LINE"

# Prisma CLI loads env from prisma/.env (next to schema), so copy & normalize scheme for CLI reliability.
mkdir -p apps/api/prisma
perl -pe 's/^(DATABASE_URL=)(\"?)mariadb:\/\//${1}${2}mysql:\/\//i' "$ENV_FILE" > apps/api/prisma/.env
echo "✅ Wrote apps/api/prisma/.env (normalized scheme for Prisma CLI)"

# --- locate schema.prisma ---
SCHEMA=""
if [ -f "apps/api/prisma/schema.prisma" ]; then
  SCHEMA="apps/api/prisma/schema.prisma"
else
  SCHEMA="$(find apps/api -maxdepth 5 -name schema.prisma -print -quit || true)"
fi
[ -n "${SCHEMA:-}" ] || { echo "❌ Could not find schema.prisma under apps/api"; exit 1; }
echo "✅ Prisma schema: $SCHEMA"

# --- patch PrismaService adapter init to NEVER use { url: databaseUrl } (this caused user '' / password NO) ---
PRISMA_SVC="apps/api/src/prisma/prisma.service.ts"
[ -f "$PRISMA_SVC" ] || { echo "❌ Missing $PRISMA_SVC"; exit 1; }

python3 - <<'PY'
import re
from pathlib import Path

p = Path("apps/api/src/prisma/prisma.service.ts")
s = p.read_text(encoding="utf-8")

# If already patched (no url-style adapter), skip safely.
if "url: databaseUrl" not in s and "Try the \"url\" style first" not in s:
    print("✅ PrismaService already patched (no url-style adapter found).")
    raise SystemExit(0)

new_fn = """function buildMariaDbAdapter(databaseUrl: string) {
  const u = new URL(databaseUrl);

  const host = u.hostname;
  const port = Number(u.port || "3306");
  const user = decodeURIComponent(u.username || "");
  const password = decodeURIComponent(u.password || "");
  const database = (u.pathname || "").replace(/^\\//, "");
  const connectionLimit = Number(process.env.DB_POOL_SIZE || "5");

  if (!user || !database) {
    throw new Error("DATABASE_URL missing username or database name");
  }

  return new PrismaMariaDb(
    { host, port, user, password, database, connectionLimit } as any
  );
}
"""

s2, n = re.subn(
    r"function\\s+buildMariaDbAdapter\\(databaseUrl: string\\)\\s*\\{[\\s\\S]*?\\n\\}",
    new_fn,
    s,
    count=1
)

if n != 1:
    raise SystemExit("❌ Patch failed: could not find buildMariaDbAdapter() function to replace.")

p.write_text(s2, encoding="utf-8")
print("✅ Patched PrismaService buildMariaDbAdapter() to parsed-fields mode.")
PY

echo "📦 Installing deps (workspace)..."
pnpm -w install

echo "🧱 prisma db push..."
pnpm -C apps/api exec prisma db push --schema "$SCHEMA"

echo "⚙️ prisma generate..."
pnpm -C apps/api exec prisma generate --schema "$SCHEMA"

echo "🌱 Writing + running seed (inside apps/api so @prisma/client resolves)..."
mkdir -p apps/api/tools
cat > apps/api/tools/seed_first_plan.mjs <<'EOF'
import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { PrismaMariaDb } from "@prisma/adapter-mariadb";

function adapterFromUrl(databaseUrl) {
  const u = new URL(databaseUrl);
  const host = u.hostname;
  const port = Number(u.port || "3306");
  const user = decodeURIComponent(u.username || "");
  const password = decodeURIComponent(u.password || "");
  const database = (u.pathname || "").replace(/^\//, "");
  const connectionLimit = Number(process.env.DB_POOL_SIZE || "5");
  return new PrismaMariaDb({ host, port, user, password, database, connectionLimit });
}

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("Missing DATABASE_URL");

const prisma = new PrismaClient({ adapter: adapterFromUrl(databaseUrl) });

async function main() {
  await prisma.plan.upsert({
    where: { tier: "TRIAL" },
    update: {
      name: "Trial",
      monthlyPriceCents: 0,
      seatsIncluded: 3,
      features: { churches: true, members: true, finance: false, checkin: false },
    },
    create: {
      tier: "TRIAL",
      name: "Trial",
      monthlyPriceCents: 0,
      seatsIncluded: 3,
      features: { churches: true, members: true, finance: false, checkin: false },
    },
  });
  console.log("✅ Seed OK: ensured TRIAL plan exists");
}

main()
  .catch((e) => { console.error("❌ Seed failed:", e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
EOF

(cd apps/api && node tools/seed_first_plan.mjs)

echo ""
echo "✅ FIXED."
echo "Now restart your API dev server (Ctrl+C then run it again)."
