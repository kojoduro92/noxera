#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
echo "✅ Repo root: $ROOT"

echo ""
echo "📦 Install missing Nest DTO/runtime deps into apps/api..."
pnpm --filter api add class-validator class-transformer @nestjs/mapped-types dotenv >/dev/null

echo ""
echo "🔧 Ensure MembersModule is wired into Nest module graph..."
TARGET=""
IMPORT_PATH=""
if [ -f "apps/api/src/app.module.ts" ]; then
  TARGET="apps/api/src/app.module.ts"
  IMPORT_PATH="./features/members/members.module"
elif [ -f "apps/api/src/features/features.module.ts" ]; then
  TARGET="apps/api/src/features/features.module.ts"
  IMPORT_PATH="./members/members.module"
else
  echo "❌ Could not find apps/api/src/app.module.ts (or features.module.ts)."
  echo "   Please confirm where your Nest root module is."
  exit 1
fi

node - "$TARGET" "$IMPORT_PATH" "MembersModule" <<'NODE'
const fs = require("fs");

const [file, importPath, symbol] = process.argv.slice(2);
let s = fs.readFileSync(file, "utf8");

const importLine = `import { ${symbol} } from "${importPath}";`;
if (!s.includes(importLine)) {
  // insert after last import
  const re = /^import .*;[ \t]*$/gm;
  let last = 0, m;
  while ((m = re.exec(s))) last = re.lastIndex;
  if (last > 0) s = s.slice(0, last) + "\n" + importLine + s.slice(last);
  else s = importLine + "\n" + s;
}

// add to @Module({ imports: [...] })
const hasInImports = new RegExp(`imports:\\s*\\[[^\\]]*\\b${symbol}\\b`, "s").test(s);
if (!hasInImports) {
  if (/imports:\s*\[/.test(s)) {
    s = s.replace(/imports:\s*\[/, (m) => `${m}\n    ${symbol},`);
  } else {
    console.log("⚠️ Could not find 'imports: [' in module file; skipped auto-insert.");
  }
}

fs.writeFileSync(file, s);
console.log(`✅ Wired ${symbol} in ${file}`);
NODE

echo ""
echo "🔎 Verify API builds..."
pnpm --filter api lint >/dev/null
pnpm --filter api build

echo ""
echo "✅ Members backend compiles now."
echo "NEXT:"
echo "  pnpm --filter api dev"
