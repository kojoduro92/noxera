set -euo pipefail

API="apps/api"

echo "🔧 Installing Prisma v7 required deps (dotenv + mariadb adapter)..."
pnpm -C "$API" add dotenv mariadb @prisma/adapter-mariadb

echo "🧩 Writing apps/api/prisma.config.ts ..."
cat > "$API/prisma.config.ts" <<'TS'
import "dotenv/config";
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
    seed: "ts-node --transpile-only prisma/seed.ts",
  },
  datasource: {
    url: env("DATABASE_URL"),
  },
});
TS

echo "🧼 Removing datasource url from schema.prisma (Prisma v7 requirement)..."
node - <<'NODE'
const fs = require("fs");
const p = "apps/api/prisma/schema.prisma";
let s = fs.readFileSync(p, "utf8");

// Replace datasource db block with provider-only form
s = s.replace(/datasource\s+db\s*\{[\s\S]*?\}\s*/m, `datasource db {\n  provider = "mysql"\n}\n\n`);

fs.writeFileSync(p, s);
console.log("✅ Updated schema.prisma datasource block (provider only)");
NODE

echo "🌱 Fixing seed.ts to use PrismaMariaDb adapter (Prisma v7 requirement)..."
node - <<'NODE'
const fs = require("fs");
const p = "apps/api/prisma/seed.ts";
let s = fs.readFileSync(p, "utf8");

// Add dotenv + adapter imports + adapter PrismaClient init
// Replace the first PrismaClient init block safely.
s = s.replace(
  /import\s+\{\s*PrismaClient\s*\}\s+from\s+"@prisma\/client";\s*/m,
  `import "dotenv/config";\nimport { PrismaClient } from "@prisma/client";\nimport { PrismaMariaDb } from "@prisma/adapter-mariadb";\n`
);

// Replace `const prisma = new PrismaClient();` (if present)
s = s.replace(
  /const\s+prisma\s*=\s*new\s+PrismaClient\s*\(\s*\)\s*;\s*/m,
  `const databaseUrl = process.env.DATABASE_URL;\nif (!databaseUrl) throw new Error("Missing DATABASE_URL");\nconst prisma = new PrismaClient({ adapter: new PrismaMariaDb(databaseUrl) });\n`
);

fs.writeFileSync(p, s);
console.log("✅ Updated seed.ts to use adapter + dotenv");
NODE

echo "🧾 Cleaning Prisma v7-removed package.json prisma config (optional but recommended)..."
node - <<'NODE'
const fs = require("fs");
const p = "apps/api/package.json";
const j = JSON.parse(fs.readFileSync(p, "utf8"));

// Prisma v7 moved config to prisma.config.ts; remove old prisma block if it exists
if (j.prisma) delete j.prisma;

j.scripts ||= {};
j.scripts["db:generate"] = "prisma generate";
j.scripts["db:migrate"]  = "prisma migrate dev";
j.scripts["db:seed"]     = "prisma db seed";

fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
console.log("✅ Updated scripts + removed package.json prisma block");
NODE

echo "✅ Prisma v7 config patched. Now run migrate + seed."
