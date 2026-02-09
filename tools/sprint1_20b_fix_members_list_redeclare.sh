#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

SERVICE="apps/api/src/features/members/members.service.ts"
DTO="apps/api/src/features/members/dto/list-members.dto.ts"

node <<'NODE'
const fs = require("fs");

function patchService() {
  const file = "apps/api/src/features/members/members.service.ts";
  let s = fs.readFileSync(file, "utf8");

  // Remove the older duplicate pagination vars (keep the coercion block)
  s = s.replace(/^\s*const page\s*=\s*dto\.page\s*\?\?\s*1;\s*\n/gm, "");
  s = s.replace(/^\s*const pageSize\s*=\s*dto\.pageSize\s*\?\?\s*20;\s*\n/gm, "");
  s = s.replace(/^\s*const skip\s*=\s*\(page\s*-\s*1\)\s*\*\s*pageSize;\s*\n/gm, "");

  // If coercion block isn't present (should be), add it once near start of list()
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

  fs.writeFileSync(file, s);
  console.log("✅ Cleaned duplicates in", file);
}

function patchDto() {
  const file = "apps/api/src/features/members/dto/list-members.dto.ts";
  let s = fs.readFileSync(file, "utf8");

  // Ensure query string numbers become numbers (Nest query params are strings by default)
  // Insert @Type(() => Number) between @IsOptional() and @IsInt()
  s = s.replace(
    /@IsOptional\(\)\s*\n(\s*)@IsInt\(\)/g,
    `@IsOptional()\n$1@Type(() => Number)\n$1@IsInt()`
  );

  fs.writeFileSync(file, s);
  console.log("✅ Ensured numeric transform in", file);
}

patchService();
patchDto();
NODE

echo ""
echo "▶ Build"
pnpm --filter api build

echo ""
echo "✅ Done. Restart API and retest GET /members"
