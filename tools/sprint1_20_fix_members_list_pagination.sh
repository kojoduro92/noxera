#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FILE="apps/api/src/features/members/members.service.ts"

node <<'NODE'
const fs = require("fs");

const file = "apps/api/src/features/members/members.service.ts";
if (!fs.existsSync(file)) {
  console.error("❌ Missing:", file);
  process.exit(1);
}

let s = fs.readFileSync(file, "utf8");

// 1) Inject safe pagination coercion at start of list() (idempotent)
if (!s.includes("// --- pagination coercion ---")) {
  s = s.replace(
    /(async\s+list\s*\([^)]*\)\s*\{\s*)/,
    `$1
    // --- pagination coercion ---
    const page = Math.max(1, Number.parseInt(String(dto.page ?? 1), 10) || 1);
    const pageSize = Math.min(200, Math.max(1, Number.parseInt(String(dto.pageSize ?? 20), 10) || 20));
    const skip = (page - 1) * pageSize;

`
  );
}

// 2) Ensure findMany uses numeric take + our skip
// Replace any "skip: <expr>," with "skip,"
s = s.replace(/skip:\s*[^,\n]+,\s*/g, "skip,\n        ");

// Replace any "take: <expr>," with "take: pageSize,"
s = s.replace(/take:\s*[^,\n]+,\s*/g, "take: pageSize,\n        ");

// 3) Ensure response returns numeric page/pageSize (optional but nice)
s = s.replace(/\bpage:\s*dto\.page\b/g, "page");
s = s.replace(/\bpageSize:\s*dto\.pageSize\b/g, "pageSize");

fs.writeFileSync(file, s);
console.log("✅ Patched", file);
NODE

echo ""
echo "▶ Build"
pnpm --filter api build

echo ""
echo "✅ Done. Retest GET /members"
