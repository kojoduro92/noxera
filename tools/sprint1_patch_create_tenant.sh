#!/usr/bin/env bash
set -euo pipefail

FILE="apps/api/src/admin/admin-tenants.controller.ts"
[ -f "$FILE" ] || { echo "❌ Missing $FILE"; exit 1; }

node - <<'NODE'
const fs = require("fs");
const path = require("path");

const file = "apps/api/src/admin/admin-tenants.controller.ts";
let s = fs.readFileSync(file, "utf8");

const MARK = "// SPRINT1_CREATE_TENANT";
if (s.includes(MARK)) {
  console.log("✅ Create tenant patch already present.");
  process.exit(0);
}

// Ensure @nestjs/common import includes Post, Body, BadRequestException
function ensureNestCommon(names) {
  const re = /^import\s+\{\s*([^}]+)\s*\}\s+from\s+['"]@nestjs\/common['"];\s*$/m;
  const m = s.match(re);
  if (!m) {
    s = `import { ${names.join(", ")} } from "@nestjs/common";\n` + s;
    return;
  }
  const existing = m[1].split(",").map(x => x.trim()).filter(Boolean);
  const set = new Set(existing);
  for (const n of names) set.add(n);
  const next = Array.from(set).sort().join(", ");
  s = s.replace(re, `import { ${next} } from "@nestjs/common";`);
}
ensureNestCommon(["BadRequestException", "Body", "Post"]);

// Detect the Prisma accessor already used by this controller (we won't import PrismaClient or PrismaService)
let prismaBase = null;

// Prefer something like this.prisma.tenant.findMany / this.db.tenant...
let m = s.match(/\b(this\.\w+)\.tenant\./);
if (m) prismaBase = m[1];

// If file uses plain "prisma.tenant", use that
if (!prismaBase) {
  m = s.match(/\b(prisma)\.tenant\./);
  if (m) prismaBase = m[1];
}

// If still not found, fail loudly (but this should not happen in your Sprint 0 file)
if (!prismaBase) {
  console.error("❌ Could not detect Prisma accessor in controller. Expected something like this.prisma.tenant.*");
  process.exit(1);
}

// Insert method right after class opening brace
const classRe = /export\s+class\s+\w+\s*\{\s*\n/;
const classMatch = s.match(classRe);
if (!classMatch) {
  console.error("❌ Could not find controller class declaration.");
  process.exit(1);
}

const method = `
  ${MARK}
  @Post()
  async createTenant(@Body() body: Record<string, any>) {
    const name = String(body?.name ?? "").trim();
    if (!name) throw new BadRequestException("name is required");

    const rand = Math.random().toString(36).slice(2, 8);
    const slugify = (v: string) =>
      v
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/(^-|-$)/g, "")
        .slice(0, 40);

    const slug = String(body?.slug ?? "").trim() || \`\${slugify(name)}-\${rand}\`;

    // plan is required in your Prisma types (name, slug, plan). We'll infer default from schema if not provided.
    const plan = String(body?.plan ?? "").trim() || this.inferDefaultTenantPlan();
    if (!plan) throw new BadRequestException("plan is required");

    const created = await ${prismaBase}.tenant.create({
      data: { name, slug, plan } as any,
    });

    return created;
  }

  private inferDefaultTenantPlan(): string | null {
    try {
      const fs2 = require("node:fs");
      const path2 = require("node:path");

      // Support both: running with cwd=apps/api OR running from repo root
      const candidates = [
        path2.join(process.cwd(), "prisma", "schema.prisma"),
        path2.join(process.cwd(), "apps", "api", "prisma", "schema.prisma"),
      ];

      const schemaPath = candidates.find((p: string) => fs2.existsSync(p));
      if (!schemaPath) return null;

      const schema = fs2.readFileSync(schemaPath, "utf8");

      // Find Tenant model block
      const model = schema.match(/model\\s+Tenant\\s*\\{([\\s\\S]*?)\\n\\}/m);
      if (!model) return null;

      const lines = model[1]
        .split("\\n")
        .map((l: string) => l.trim())
        .filter((l: string) => l && !l.startsWith("//"));

      // Find plan line like: plan Plan @default(BASIC)
      const planLine = lines.find((l: string) => l.startsWith("plan "));
      if (!planLine) return null;

      // If @default(X) exists, use it
      const def = planLine.match(/@default\\(([^)]+)\\)/);
      if (def) return def[1].trim();

      // Otherwise infer enum type name (2nd token)
      const parts = planLine.split(/\\s+/);
      const planType = (parts[1] || "").replace("?", "");
      if (!planType) return null;

      const builtins = new Set(["String","Int","BigInt","Boolean","DateTime","Float","Decimal","Json"]);
      if (builtins.has(planType)) return null;

      // Find enum block and pick first value
      const reEnum = new RegExp("enum\\\\s+" + planType + "\\\\s*\\\\{([\\\\s\\\\S]*?)\\\\n\\\\}", "m");
      const em = schema.match(reEnum);
      if (!em) return null;

      const vals = em[1]
        .split("\\n")
        .map((x: string) => x.trim())
        .filter((x: string) => x && !x.startsWith("//"))
        .map((x: string) => x.split(/\\s+/)[0]);

      return vals[0] || null;
    } catch {
      return null;
    }
  }
`;

s = s.replace(classRe, (m) => m + method + "\n");
fs.writeFileSync(file, s);
console.log("✅ Patched Create Tenant into:", file);
console.log("✅ Prisma accessor used:", prismaBase);
NODE
