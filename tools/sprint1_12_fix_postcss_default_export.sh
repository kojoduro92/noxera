#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
test -f package.json || { echo "Run from repo root"; exit 1; }

fix_file () {
  local f="$1"
  test -f "$f" || return 0

  node - <<'NODE' "$f"
const fs = require("fs");
const path = process.argv[1];
let s = fs.readFileSync(path, "utf8");

// If it's already using a named const export, skip.
if (/const\s+\w+\s*=\s*\{[\s\S]*\}\s*;\s*export\s+default\s+\w+\s*;/.test(s)) process.exit(0);

// Replace: export default { ... }
// With:   const config = { ... }; export default config;
const m = s.match(/export\s+default\s+(\{[\s\S]*\})\s*;?\s*$/);
if (!m) process.exit(0);

const obj = m[1];
s = s.replace(/export\s+default\s+\{[\s\S]*\}\s*;?\s*$/, `const config = ${obj};\n\nexport default config;\n`);
fs.writeFileSync(path, s);
NODE

  echo "✅ Fixed: $f"
}

fix_file "apps/web-church/postcss.config.mjs"
fix_file "apps/web-public/postcss.config.mjs"
fix_file "apps/web-superadmin/postcss.config.mjs"

echo ""
echo "NEXT:"
echo "  pnpm -w -r lint"
