#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "✅ Repo root: $ROOT"

need=("@typescript-eslint/parser" "@typescript-eslint/eslint-plugin")
missing=()

for p in "${need[@]}"; do
  node -e "require.resolve('$p')" >/dev/null 2>&1 || missing+=("$p")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "📦 Installing missing dev deps at workspace root: ${missing[*]}"
  pnpm -w add -D "${missing[@]}"
else
  echo "✅ TypeScript ESLint deps already present."
fi

echo ""
echo "🔎 Verify API lint now runs:"
pnpm --filter api lint

echo ""
echo "✅ DONE."
echo "NEXT:"
echo "  pnpm -w -r lint"
