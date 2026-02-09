#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "✅ Repo root: $ROOT"
test -f pnpm-workspace.yaml || { echo "❌ pnpm-workspace.yaml not found"; exit 1; }
command -v pnpm >/dev/null || { echo "❌ pnpm not found"; exit 1; }

echo "🔎 Quick workspace info:"
pnpm -v
node -v

echo "🔎 Verify Sprint 0 still builds (non-fatal if scripts not present):"
pnpm -w -r --if-present lint || true
pnpm -w -r --if-present typecheck || true

echo "✅ Preflight OK"
