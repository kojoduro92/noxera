#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

API="http://localhost:3000"
TENANT_ID="tnt_001"

echo "✅ Repo root: $ROOT"
echo "✅ Using tenant: $TENANT_ID"
echo ""

echo "🔎 0) Health"
curl -fsS "$API/health" >/dev/null
echo "✅ API reachable"
echo ""

echo "🔎 1) Prisma direct smoke (bypasses HTTP/guards)"
node - <<'NODE'
const fs = require("fs");
const path = require("path");

function readEnv(file) {
  const p = path.resolve(file);
  const txt = fs.readFileSync(p, "utf8");
  const line = txt.split("\n").find(l => l.startsWith("DATABASE_URL="));
  if (!line) throw new Error("DATABASE_URL missing in " + p);
  let url = line.slice("DATABASE_URL=".length).trim();
  if ((url.startsWith('"') && url.endsWith('"')) || (url.startsWith("'") && url.endsWith("'"))) url = url.slice(1, -1);
  return url;
}

const { PrismaClient } = require("@prisma/client");

const url = readEnv("apps/api/.env");
const prisma = new PrismaClient({ datasourceUrl: url });

const tenantId = process.env.TENANT_ID || "tnt_001";
const phone = "+233" + String(Date.now()).slice(-9); // unique-ish

(async () => {
  try {
    const tenant = await prisma.tenant.findUnique({ where: { id: tenantId }, select: { id: true, status: true, name: true }});
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

PHONE="$(node -e 'const fs=require("fs"); const p="PHONE_FOR_HTTP="; const t=fs.readFileSync(0,"utf8"); const line=t.split("\n").find(l=>l.startsWith(p)); if(!line){process.exit(1)} console.log(line.slice(p.length))' < <(echo "PHONE_FOR_HTTP=") 2>/dev/null || true)"

# If the above didn't capture, re-derive a phone (still unique enough)
if [[ -z "${PHONE:-}" ]]; then
  PHONE="+233$(date +%s | tail -c 10)"
fi

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
echo "✅ Done. If HTTP is 500 while Prisma direct succeeded, the bug is in Nest guards/tenant-access pipeline."
