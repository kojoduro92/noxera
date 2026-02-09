#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000}"
NAME="${1:-New Hope Chapel}"

echo "==> Health check: $API/health"
HEALTH="$(curl -sS "$API/health" || true)"
if [ -z "$HEALTH" ]; then
  echo "❌ Empty response from /health. Is the API running? Start with: pnpm -C apps/api start:dev" >&2
  exit 1
fi
echo "$HEALTH"
echo

echo "==> Create dev session: POST $API/auth/session"
AUTH_BODY="$(curl -sS -X POST "$API/auth/session" -H 'Content-Type: application/json' -d '{"dev":true}' || true)"
if [ -z "$AUTH_BODY" ]; then
  echo "❌ Empty response from /auth/session (API not reachable or crashed)." >&2
  exit 1
fi

TOKEN="$(printf '%s' "$AUTH_BODY" | node - <<'NODE'
const fs=require('fs');
const raw=fs.readFileSync(0,'utf8');
try {
  const j=JSON.parse(raw);
  if (!j.token) throw new Error('token missing');
  process.stdout.write(j.token);
} catch (e) {
  console.error('❌ /auth/session did not return JSON with token. Raw response:\n' + raw);
  process.exit(2);
}
NODE
)"
echo "✅ Token OK (len=${#TOKEN})"
echo

echo "==> Create tenant: POST $API/admin/tenants"
TENANT_BODY="$(curl -sS -X POST "$API/admin/tenants" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "$(node -e "console.log(JSON.stringify({name: process.argv[1]}))" "$NAME")" || true)"

if [ -z "$TENANT_BODY" ]; then
  echo "❌ Empty response from POST /admin/tenants" >&2
  exit 1
fi

printf '%s\n' "$TENANT_BODY" | node - <<'NODE'
const fs=require('fs');
const raw=fs.readFileSync(0,'utf8');
try {
  console.log(JSON.stringify(JSON.parse(raw), null, 2));
} catch (e) {
  console.error('❌ Non-JSON response from POST /admin/tenants:\n' + raw);
  process.exit(2);
}
NODE
