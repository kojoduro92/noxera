#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SERVICE="apps/api/src/features/members/members.service.ts"
DTO_CREATE="apps/api/src/features/members/dto/create-member.dto.ts"
DTO_UPDATE="apps/api/src/features/members/dto/update-member.dto.ts"
DTO_LIST="apps/api/src/features/members/dto/list-members.dto.ts"

node <<'NODE'
const fs = require("fs");

function patchFile(path, fn) {
  if (!fs.existsSync(path)) return;
  const before = fs.readFileSync(path, "utf8");
  const after = fn(before);
  if (after !== before) fs.writeFileSync(path, after, "utf8");
  console.log("✅ Patched", path);
}

function removeBranchIdLines(text) {
  // Remove any single line containing "branchId" (covers prisma create/update + where filters)
  return text.replace(/^[^\n]*\bbranchId\b[^\n]*\n/gm, "");
}

function removeBranchIdDtoBlock(text) {
  // Remove decorators + property for branchId (covers DTOs)
  // Example removed block:
  //   @IsOptional()
  //   @IsString()
  //   branchId?: string;
  return text.replace(/(?:^[ \t]*@.*\n)*^[ \t]*branchId[^\n]*\n/gm, "");
}

patchFile("apps/api/src/features/members/members.service.ts", (t) => {
  let out = removeBranchIdLines(t);
  // Also remove any leftover dto.branchId usage if it appears inline
  out = out.replace(/\bdto\.branchId\b/g, "undefined");
  return out;
});

patchFile("apps/api/src/features/members/dto/create-member.dto.ts", (t) => removeBranchIdDtoBlock(t));
patchFile("apps/api/src/features/members/dto/update-member.dto.ts", (t) => removeBranchIdDtoBlock(t));
patchFile("apps/api/src/features/members/dto/list-members.dto.ts", (t) => removeBranchIdDtoBlock(t));

NODE

echo ""
echo "▶ Lint + build"
pnpm --filter api lint >/dev/null
pnpm --filter api build

echo ""
echo "✅ Done. Restart API and retest POST /members."
