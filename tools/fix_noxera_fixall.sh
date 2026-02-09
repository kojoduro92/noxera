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

# Prisma CLI reads env from prisma/.env next to schema; normalize mariadb:// -> mysql:// for CLI only
mkdir -p apps/api/prisma
perl -pe 's/^(DATABASE_URL=)(\"?)mariadb:\/\//${1}${2}mysql:\/\//i' "$ENV_FILE" > apps/api/prisma/.env
echo "✅ Wrote apps/api/prisma/.env (normalized scheme for Prisma CLI)"

# --- locate schema.prisma ---
SCHEMA=""
if [ -f "apps/api/prisma/schema.prisma" ]; then
  SCHEMA="apps/api/prisma/schema.prisma"
else
  SCHEMA="$(find apps/api -maxdepth 6 -name schema.prisma -print -quit || true)"
fi
[ -n "${SCHEMA:-}" ] || { echo "❌ Could not find schema.prisma under apps/api"; exit 1; }
echo "✅ Prisma schema: $SCHEMA"

# --- PATCH PrismaService adapter: replace url-style adapter with parsed-fields adapter ---
python3 - <<'PY'
from pathlib import Path
import re

def find_prisma_service():
    # preferred path
    p = Path("apps/api/src/prisma/prisma.service.ts")
    if p.exists():
        return p
    # common alternative locations
    hits = list(Path("apps/api/src").rglob("prisma.service.ts"))
    if hits:
        return hits[0]
    # last resort: any file containing both PrismaMariaDb + class PrismaService
    for f in Path("apps/api/src").rglob("*.ts"):
        try:
            t = f.read_text(encoding="utf-8")
        except:
            continue
        if "PrismaMariaDb" in t and "class PrismaService" in t and "extends PrismaClient" in t:
            return f
    return None

p = find_prisma_service()
if not p:
    raise SystemExit("❌ Could not locate PrismaService file under apps/api/src")

s = p.read_text(encoding="utf-8")

# Already fixed?
if re.search(r"new\s+PrismaMariaDb\s*\(\s*\{\s*host\s*:", s):
    print(f"✅ PrismaService already uses parsed-fields adapter: {p}")
    raise SystemExit(0)

# We specifically patch the url-style adapter usage
pat = re.compile(r"return\s+new\s+PrismaMariaDb\s*\(\s*\{\s*url\s*:\s*databaseUrl\s*\}[\s\S]*?\)\s*;", re.M)
m = pat.search(s)
if not m:
    # try a slightly different var name if used (e.g. url)
    pat2 = re.compile(r"return\s+new\s+PrismaMariaDb\s*\(\s*\{\s*url\s*:\s*\w+\s*\}[\s\S]*?\)\s*;", re.M)
    m2 = pat2.search(s)
    if not m2:
        raise SystemExit(f"❌ Patch failed: could not find 'PrismaMariaDb({{ url: ... }})' in {p}")
    m = m2

replacement = """const u = new URL(databaseUrl);
    const host = u.hostname;
    const port = Number(u.port || "3306");
    const user = decodeURIComponent(u.username || "");
    const password = decodeURIComponent(u.password || "");
    const database = (u.pathname || "").replace(/^\\//, "");
    const connectionLimit = Number(process.env.DB_POOL_SIZE || "5");

    if (!user || !database) {
      throw new Error("DATABASE_URL missing username or database name");
    }

    return new PrismaMariaDb({ host, port, user, password, database, connectionLimit } as any);"""

s2 = s[:m.start()] + replacement + s[m.end():]
p.write_text(s2, encoding="utf-8")
print(f"✅ Patched PrismaService url-style adapter → parsed-fields adapter in: {p}")
PY

echo "📦 Installing deps (workspace)..."
pnpm -w install

echo "🧱 prisma db push..."
pnpm -C apps/api exec prisma db push --schema "$SCHEMA"

echo "⚙️ prisma generate..."
pnpm -C apps/api exec prisma generate --schema "$SCHEMA"

echo "🌱 Seed (inside apps/api so @prisma/client resolves)..."
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
    update: { name: "Trial", monthlyPriceCents: 0, seatsIncluded: 3, features: { churches: true, members: true } },
    create: { tier: "TRIAL", name: "Trial", monthlyPriceCents: 0, seatsIncluded: 3, features: { churches: true, members: true } },
  });
  console.log("✅ Seed OK: ensured TRIAL plan exists");
}

main()
  .catch((e) => { console.error("❌ Seed failed:", e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
EOF

(cd apps/api && node tools/seed_first_plan.mjs)

echo ""
echo "✅ FIXED DB + PRISMA + SEED."
echo ""
echo "NEXT:"
echo "1) Restart API dev server (Ctrl+C then start again)"
echo ""
echo "2) Create dev session + test tenants (use the right port):"
echo "   curl -i -X POST http://localhost:3000/auth/session -H 'content-type: application/json' -d '{\"dev\":true}' -c /tmp/noxera.cookies"
echo "   curl -i http://localhost:3000/admin/tenants -b /tmp/noxera.cookies"
echo ""
echo "If your API runs on 3001, replace 3000 -> 3001 in both commands."
