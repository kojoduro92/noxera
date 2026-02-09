#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "✅ Repo root: $ROOT"
echo "🔧 Fixing postcss.config.mjs anonymous default export warnings..."

FILES=(
  "apps/web-church/postcss.config.mjs"
  "apps/web-public/postcss.config.mjs"
  "apps/web-superadmin/postcss.config.mjs"
)

node <<'NODE'
const fs = require("fs");

const files = [
  "apps/web-church/postcss.config.mjs",
  "apps/web-public/postcss.config.mjs",
  "apps/web-superadmin/postcss.config.mjs",
];

let changed = 0;

for (const f of files) {
  if (!fs.existsSync(f)) {
    console.log(`ℹ️  Skip (missing): ${f}`);
    continue;
  }

  const src = fs.readFileSync(f, "utf8");

  // already fixed
  if (src.includes("export default config")) {
    console.log(`✅ Already OK: ${f}`);
    continue;
  }

  // common shape: export default { ... }
  if (src.includes("export default {")) {
    let out = src.replace("export default {", "const config = {");

    // Ensure we end with export default config;
    if (!out.match(/\bexport\s+default\s+config\s*;?\s*$/m)) {
      out = out.replace(/\s*$/, "\n\nexport default config;\n");
    }

    fs.writeFileSync(f, out);
    console.log(`✅ Fixed: ${f}`);
    changed++;
    continue;
  }

  console.log(`⚠️  Could not auto-fix (unexpected format): ${f}`);
}

console.log(changed ? `\n✅ Updated ${changed} file(s).` : `\n✅ No changes needed.`);
NODE

echo ""
echo "NEXT:"
echo "  pnpm -w -r lint"
