#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEMA="apps/api/prisma/schema.prisma"
test -f "$SCHEMA" || { echo "❌ Missing $SCHEMA"; exit 1; }

echo "✅ Repo root: $ROOT"
echo "🔧 Ensuring Prisma uses SHADOW_DATABASE_URL..."

node <<'NODE'
const fs = require("fs");

const schemaPath = "apps/api/prisma/schema.prisma";
let s = fs.readFileSync(schemaPath, "utf8");

// 1) Ensure datasource db has shadowDatabaseUrl
const dsMatch = s.match(/datasource\s+db\s*\{[\s\S]*?\n\}/);
if (!dsMatch) {
  console.error("❌ Could not find `datasource db { ... }` in schema.prisma");
  process.exit(1);
}
const block = dsMatch[0];

if (!/shadowDatabaseUrl\s*=/.test(block)) {
  const urlLine = block.match(/^\s*url\s*=\s*env\("DATABASE_URL"\)\s*$/m);
  let patched = block;
  if (urlLine) {
    patched = block.replace(
      urlLine[0],
      `${urlLine[0]}\n  shadowDatabaseUrl = env("SHADOW_DATABASE_URL")`
    );
  } else {
    patched = block.replace(/\{\s*\n/, '{\n  shadowDatabaseUrl = env("SHADOW_DATABASE_URL")\n');
  }
  s = s.replace(block, patched);
  fs.writeFileSync(schemaPath, s, "utf8");
  console.log('✅ Added shadowDatabaseUrl to datasource db');
} else {
  console.log("ℹ️ schema already has shadowDatabaseUrl");
}

// 2) Find env file that contains DATABASE_URL
const candidates = ["apps/api/.env", "apps/api/.env.local", ".env", ".env.local"];
function read(p) { return fs.existsSync(p) ? fs.readFileSync(p, "utf8") : null; }
function getVar(content, key) {
  const re = new RegExp(`^\\s*${key}\\s*=\\s*(.*)\\s*$`, "m");
  const m = content.match(re);
  if (!m) return null;
  let v = m[1].trim();
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
  return v;
}

let envPath = null;
let envText = null;
for (const p of candidates) {
  const t = read(p);
  if (!t) continue;
  if (getVar(t, "DATABASE_URL")) { envPath = p; envText = t; break; }
}

if (!envPath) {
  console.error("❌ Could not find DATABASE_URL in apps/api/.env, apps/api/.env.local, .env, or .env.local");
  process.exit(1);
}

const dbUrl = getVar(envText, "DATABASE_URL");
const u = new URL(dbUrl);
const dbName = u.pathname.replace(/^\//, "");
const shadowDb = `${dbName}_shadow`;
u.pathname = `/${shadowDb}`;
const shadowUrl = u.toString();
const info = {
  shadowDb,
  shadowUrl,
  user: decodeURIComponent(u.username || ""),
  pass: decodeURIComponent(u.password || ""),
};

function setVar(content, key, value) {
  const line = `${key}="${value}"`;
  const re = new RegExp(`^\\s*${key}\\s*=.*$`, "m");
  if (re.test(content)) return content.replace(re, line);
  const sep = content.endsWith("\n") ? "" : "\n";
  return content + sep + line + "\n";
}

// Write into the env file we found
fs.writeFileSync(envPath, setVar(envText, "SHADOW_DATABASE_URL", shadowUrl), "utf8");
console.log(`✅ Set SHADOW_DATABASE_URL in ${envPath}`);

// Also ensure apps/api/.env has it (helps runtime consistency)
const apiEnv = "apps/api/.env";
const apiEnvText = fs.existsSync(apiEnv) ? fs.readFileSync(apiEnv, "utf8") : "";
fs.writeFileSync(apiEnv, setVar(apiEnvText, "SHADOW_DATABASE_URL", shadowUrl), "utf8");
console.log("✅ Ensured apps/api/.env also has SHADOW_DATABASE_URL");

fs.writeFileSync("tools/.shadowdb.json", JSON.stringify(info, null, 2));
console.log(`ℹ️ Shadow DB will be: ${shadowDb}`);
NODE

echo ""
echo "🧹 Prisma format (best effort)..."
pnpm --filter api exec prisma format || true

echo ""
echo "🐳 Creating shadow DB in MySQL container (port 3307) + granting privileges..."

CID="$(docker ps --format '{{.ID}} {{.Ports}}' | grep -E '(:|0\.0\.0\.0:|127\.0\.0\.1:)3307->3306' | head -n1 | awk '{print $1}')"
if [ -z "${CID:-}" ]; then
  echo "⚠️ Could not auto-detect a MySQL container exposing 3307->3306."
  echo "   Create the shadow DB manually, then run migrate."
  echo "   Shadow DB name is in tools/.shadowdb.json"
  echo "   NEXT: pnpm --filter api db:migrate -- --name sprint1_members"
  exit 0
fi

MYSQL_BIN="$(docker exec "$CID" sh -lc 'command -v mysql || command -v mariadb || true')"
if [ -z "${MYSQL_BIN:-}" ]; then
  echo "❌ mysql client not found inside container $CID"
  exit 1
fi

SHADOW_DB="$(node -p 'require("./tools/.shadowdb.json").shadowDb')"
APP_USER="$(node -p 'require("./tools/.shadowdb.json").user')"

SQL="CREATE DATABASE IF NOT EXISTS \`${SHADOW_DB}\`; GRANT ALL PRIVILEGES ON \`${SHADOW_DB}\`.* TO '${APP_USER}'@'%'; FLUSH PRIVILEGES;"

ROOT_PW="$(docker exec "$CID" sh -lc 'printenv MYSQL_ROOT_PASSWORD 2>/dev/null || true')"
ALLOW_EMPTY="$(docker exec "$CID" sh -lc 'printenv MYSQL_ALLOW_EMPTY_PASSWORD 2>/dev/null || true')"

if [ -n "${ROOT_PW:-}" ]; then
  echo "✅ Found MYSQL_ROOT_PASSWORD in container env."
  docker exec -i "$CID" sh -lc "MYSQL_PWD='$ROOT_PW' ${MYSQL_BIN} -uroot -e \"$SQL\""
elif [ "${ALLOW_EMPTY:-}" = "yes" ] || [ "${ALLOW_EMPTY:-}" = "true" ]; then
  echo "✅ MYSQL_ALLOW_EMPTY_PASSWORD is set; using empty root password."
  docker exec -i "$CID" sh -lc "${MYSQL_BIN} -uroot -e \"$SQL\""
else
  echo "⚠️ Could not read MYSQL_ROOT_PASSWORD from the container."
  echo "   Run this ONCE (replace <ROOT_PASSWORD>):"
  echo "   docker exec -it $CID sh -lc 'MYSQL_PWD=<ROOT_PASSWORD> ${MYSQL_BIN} -uroot -e \"$SQL\"'"
  echo ""
  echo "✅ After that, run:"
  echo "  pnpm --filter api db:migrate -- --name sprint1_members"
  exit 0
fi

echo ""
echo "✅ Shadow DB ready."
echo "NEXT:"
echo "  pnpm --filter api db:migrate -- --name sprint1_members"
