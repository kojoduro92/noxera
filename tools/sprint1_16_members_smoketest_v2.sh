#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

API="http://localhost:3000"

echo "✅ Repo root: $ROOT"

echo "🔎 Checking API..."
curl -fsS "$API/health" >/dev/null || { echo "❌ API not reachable at $API"; exit 1; }
echo "✅ API reachable"

echo "▶ Create dev session cookie..."
curl -fsS -X POST "$API/auth/session" \
  -H 'content-type: application/json' \
  -d '{"dev":true}' \
  -c /tmp/noxera.cookies >/dev/null

echo "▶ Fetch tenants..."
TENANTS_JSON="$(curl -fsS "$API/admin/tenants" -b /tmp/noxera.cookies)"

ACTIVE_ID="$(echo "$TENANTS_JSON" | jq -r '.items[] | select(.status=="ACTIVE") | .id' | head -n 1 || true)"
if [[ -z "${ACTIVE_ID:-}" || "${ACTIVE_ID:-}" == "null" ]]; then
  ACTIVE_ID="$(echo "$TENANTS_JSON" | jq -r '.items[0].id')"
  STATUS="$(echo "$TENANTS_JSON" | jq -r '.items[0].status')"
  echo "⚠️ No ACTIVE tenant found. Falling back to first tenant: $ACTIVE_ID (status=$STATUS)"
else
  NAME="$(echo "$TENANTS_JSON" | jq -r --arg id "$ACTIVE_ID" '.items[] | select(.id==$id) | .name')"
  echo "✅ Using ACTIVE tenant: $ACTIVE_ID ($NAME)"
fi

TENANT_ID="$ACTIVE_ID"

echo "▶ Members: create"
CREATE_BODY='{"firstName":"John","lastName":"Mensah","phone":"+233000000000","status":"ACTIVE"}'
CREATE_CODE="$(
  curl -sS -o /tmp/member_create.json -w '%{http_code}' \
    -X POST "$API/members" \
    -b /tmp/noxera.cookies \
    -H "content-type: application/json" \
    -H "x-tenant-id: $TENANT_ID" \
    -d "$CREATE_BODY"
)"
if [[ "$CREATE_CODE" -ge 400 ]]; then
  echo "❌ POST /members failed (HTTP $CREATE_CODE):"
  cat /tmp/member_create.json; echo
  exit 1
fi
cat /tmp/member_create.json | jq .

echo "▶ Members: list"
LIST_CODE="$(
  curl -sS -o /tmp/member_list.json -w '%{http_code}' \
    "$API/members?page=1&pageSize=20" \
    -b /tmp/noxera.cookies \
    -H "x-tenant-id: $TENANT_ID"
)"
if [[ "$LIST_CODE" -ge 400 ]]; then
  echo "❌ GET /members failed (HTTP $LIST_CODE):"
  cat /tmp/member_list.json; echo
  exit 1
fi
cat /tmp/member_list.json | jq .

echo ""
echo "✅ OK: Members endpoints working on tenant: $TENANT_ID"
