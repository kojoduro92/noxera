#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

API="http://localhost:3000"
TENANT_ID="${TENANT_ID:-tnt_001}"

echo "✅ Repo root: $ROOT"
echo "✅ Using tenant: $TENANT_ID"
echo ""

echo "🔎 0) Health"
curl -fsS "$API/health" >/dev/null
echo "✅ API reachable"
echo ""

echo "🔎 1) Prisma direct smoke (bypasses HTTP/guards) — via pnpm workspace"
pnpm --filter api exec node - <<'NODE'
const fs = require("fs");
const path = require("path");

function readDatabaseUrl() {
  const p = path.resolve("apps/api/.env");
  const txt = fs.readFileSync(p, "utf8");
  const line = txt.split("\n").find(l => l.startsWith("DATABASE_URL="));
  if (!line) throw new Error("DATABASE_URL missing in " + p);
  let url = line.slice("DATABASE_URL=".length).trim();
  if ((url.startsWith('"') && url.endsWith('"')) || (url.startsWith("'") && url.endsWith("'"))) url = url.slice(1, -1);
  return url;
}

const { PrismaClient } = require("@prisma/client");

const url = readDatabaseUrl();
const tenantId = process.env.TENANT_ID || "tnt_001";
const phone = "+233" + String(Date.now()).slice(-9);

const prisma = new PrismaClient({ datasourceUrl: url });

(async () => {
  try {
    const tenant = await prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, name: true, status: true }
    });
    console.log("Tenant:", tenant);

    const created = await prisma.member.create({
      data: {
        tenantId,
        firstName: "John",
        lastName: "Mensah",
        phone,
        status: "ACTIVE",
      },
      select: { id: true, firstName: true, lastName: true, phone: true, status: true, tenantId: true }
    });

    console.log("✅ Prisma create OK:", created);

    const list = await prisma.member.findMany({
      where: { tenantId },
      take: 5,
      orderBy: { createdAt: "desc" }
    });

    console.log("✅ Prisma list OK. Count:", list.length);
    console.log("Top:", list[0] ? { id: list[0].id, phone: list[0].phone, status: list[0].status } : null);
    console.log("PHONE_FOR_HTTP=" + phone);
  } catch (e) {
    console.error("❌ Prisma direct failed:");
    console.error(e);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
})();
NODE

echo ""
echo "🔎 2) HTTP smoke (uses cookie + guards)"
curl -fsS -X POST "$API/auth/session" \
  -H 'content-type: application/json' \
  -d '{"dev":true}' \
  -c /tmp/noxera.cookies >/dev/null

PHONE="+233$(date +%s | tail -c 10)"
BODY=$(printf '{"firstName":"John","lastName":"Mensah","phone":"%s","status":"ACTIVE"}' "$PHONE")

echo "▶ POST /members (phone=$PHONE)"
CODE="$(curl -sS -o /tmp/members_post.json -w '%{http_code}' \
  -X POST "$API/members" \
  -b /tmp/noxera.cookies \
  -H "content-type: application/json" \
  -H "x-tenant-id: $TENANT_ID" \
  -d "$BODY")"
echo "HTTP $CODE"
cat /tmp/members_post.json; echo
echo ""

echo "▶ GET /members"
CODE2="$(curl -sS -o /tmp/members_get.json -w '%{http_code}' \
  "$API/members?page=1&pageSize=20" \
  -b /tmp/noxera.cookies \
  -H "x-tenant-id: $TENANT_ID")"
echo "HTTP $CODE2"
cat /tmp/members_get.json; echo

echo ""
echo "✅ Done."
