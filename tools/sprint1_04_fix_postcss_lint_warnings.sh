#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require("fs");

const files = [
  "apps/web-church/postcss.config.mjs",
  "apps/web-public/postcss.config.mjs",
  "apps/web-superadmin/postcss.config.mjs",
];

for (const f of files) {
  if (!fs.existsSync(f)) continue;
  const s = fs.readFileSync(f, "utf8");

  // Only transform "export default { ... }" files.
  const m = s.match(/^\s*export\s+default\s+(\{[\s\S]*\})\s*;?\s*$/);
  if (!m) {
    // already fixed or different style; skip
    continue;
  }

  const obj = m[1];
  const out = `const config = ${obj};\n\nexport default config;\n`;
  fs.writeFileSync(f, out, "utf8");
  console.log("✅ Fixed:", f);
}
NODE

echo "✅ Done. Re-run: pnpm -w -r lint"
