#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

FILE="apps/api/src/features/members/members.service.ts"

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/features/members/members.service.ts";
let s = fs.readFileSync(file, "utf8");

const marker = "// --- pagination coercion ---";
const pos = s.indexOf(marker);

if (pos === -1) {
  console.error("❌ Could not find pagination coercion marker in members.service.ts");
  process.exit(1);
}

// Find a small window after the marker (within list()) to insert skip if missing
const windowStart = pos + marker.length;
let windowEnd = s.indexOf("\n\n", windowStart);
if (windowEnd === -1) windowEnd = Math.min(s.length, windowStart + 800);

const block = s.slice(windowStart, windowEnd);

if (!block.includes("const skip")) {
  // insert skip after the pageSize line if present, else immediately after marker line
  const m = /const pageSize[^\n]*\n/.exec(block);
  const insertAt = m ? (windowStart + m.index + m[0].length) : windowStart;
  s = s.slice(0, insertAt) + "    const skip = (page - 1) * pageSize;\n" + s.slice(insertAt);
  console.log("✅ Inserted missing skip variable");
} else {
  console.log("ℹ️ skip already present");
}

// Ensure prisma uses pageSize as Int (safe even if dto is transformed)
s = s.replace(/take:\s*String\([^)]+\)/g, "take: pageSize");
s = s.replace(/take:\s*dto\.pageSize\b/g, "take: pageSize");

fs.writeFileSync(file, s);
console.log("✅ Patched", file);
NODE

echo ""
echo "▶ Build"
pnpm --filter api build

echo ""
echo "✅ Done. Restart API and retest GET /members"
