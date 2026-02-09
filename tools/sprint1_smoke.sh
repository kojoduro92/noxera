#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000}"

echo "==> Health: $API/health"
if ! curl -fsS "$API/health" >/dev/null; then
  echo "❌ API not reachable at $API"
  echo "Start it with: pnpm -C apps/api dev"
  exit 1
fi
echo "✅ API reachable"

echo "==> Create dev session"
AUTH="$(curl -fsS -X POST "$API/auth/session" \
  -H "Content-Type: application/json" \
  -d '{"dev":true}')"

TOKEN="$(node -e 'const j=JSON.parse(process.argv[1]);process.stdout.write(j.token||"")' "$AUTH")"

if [ -z "$TOKEN" ]; then
  echo "❌ No token returned. Raw response:"
  echo "$AUTH"
  exit 2
fi

echo "✅ TOKEN_LEN=${#TOKEN}"

echo "==> Create tenant"
RESP="$(curl -fsS -X POST "$API/admin/tenants" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"New Hope Chapel"}')"

node -e 'const j=JSON.parse(process.argv[1]); console.log(JSON.stringify(j,null,2));' "$RESP"
echo "✅ Tenant created"
