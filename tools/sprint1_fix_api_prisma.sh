#!/usr/bin/env bash
set -euo pipefail

FILE="apps/api/src/admin/admin-tenants.controller.ts"

node - <<'NODE'
const fs=require('fs');
const p=process.env.FILE || "apps/api/src/admin/admin-tenants.controller.ts";
let s=fs.readFileSync(p,'utf8');

if (!s.includes("this.prisma")) {
  console.error("❌ this.prisma not found in controller. Your controller doesn't have injected prisma yet.");
  process.exit(1);
}

if (!s.includes("prisma.")) {
  console.log("✅ No prisma. references found. Nothing to patch.");
  process.exit(0);
}

// Replace ONLY the invalid variable usage
s = s.replace(/\bawait\s+prisma\./g, "await this.prisma.");
s = s.replace(/\bprisma\./g, "this.prisma.");

fs.writeFileSync(p, s);
console.log("✅ Patched prisma -> this.prisma in:", p);
NODE

# Add a "dev" script alias so you stop hitting "Missing script: dev"
node - <<'NODE'
const fs=require('fs');
const p="apps/api/package.json";
const j=JSON.parse(fs.readFileSync(p,'utf8'));
j.scripts ||= {};
if (!j.scripts.dev) j.scripts.dev = j.scripts["start:dev"] || "nest start --watch";
fs.writeFileSync(p, JSON.stringify(j,null,2) + "\n");
console.log("✅ Added scripts.dev to apps/api/package.json");
NODE

echo "✅ Done."
