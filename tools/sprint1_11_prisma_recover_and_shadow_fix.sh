#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
test -f pnpm-workspace.yaml || { echo "❌ Run this from repo root (where pnpm-workspace.yaml is)."; exit 1; }

API_DIR="$ROOT/apps/api"
SCHEMA="$API_DIR/prisma/schema.prisma"
CFG="$API_DIR/prisma.config.ts"
ENVFILE="$API_DIR/.env"

test -f "$SCHEMA" || { echo "❌ Missing schema at: $SCHEMA"; exit 1; }
test -f "$CFG" || { echo "❌ Missing prisma.config.ts at: $CFG"; exit 1; }

echo "✅ Repo root: $ROOT"
echo "🔧 1) Remove unsupported shadowDatabaseUrl from schema.prisma (Prisma 7.3+)"
python3 - <<PY
from pathlib import Path
p = Path("$SCHEMA")
s = p.read_text()

# Remove any shadowDatabaseUrl line inside datasource blocks
lines = s.splitlines(True)
out = []
removed = 0
for ln in lines:
    if "shadowDatabaseUrl" in ln:
        removed += 1
        continue
    out.append(ln)
ns = "".join(out)
if ns != s:
    p.write_text(ns)
print(f"   - removed {removed} line(s) containing shadowDatabaseUrl")
PY

echo "🔧 2) Ensure Tenant has opposite relation field for Member (Tenant.members)"
python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/api/prisma/schema.prisma")
s = p.read_text()

m = re.search(r'\bmodel\s+Tenant\s*\{', s)
if not m:
    print("   - Tenant model not found (skipping)")
    raise SystemExit(0)

start = m.start()
end = s.find("\n}", start)
if end == -1:
    print("❌ Could not find end of Tenant model block")
    raise SystemExit(1)

block_end = s.find("}", start)
# safer: find the next standalone "}" that closes the model by scanning lines
lines = s.splitlines(True)
# find line index of model Tenant {
idx = next(i for i,l in enumerate(lines) if re.search(r'\bmodel\s+Tenant\s*\{', l))
# find closing brace line after it
j = None
for k in range(idx+1, len(lines)):
    if re.match(r'^\s*\}\s*$', lines[k]):
        j = k
        break
if j is None:
    print("❌ Could not locate closing brace for Tenant model")
    raise SystemExit(1)

tenant_block = "".join(lines[idx:j+1])
if re.search(r'^\s*members\s+Member\[\]\s*$', tenant_block, re.M):
    print("   - Tenant.members already present")
    raise SystemExit(0)

# Insert just before closing brace
insert_line = "  members Member[]\n"
lines.insert(j, insert_line)
p.write_text("".join(lines))
print("   - Added: Tenant.members Member[]")
PY

echo "🔧 3) Put shadowDatabaseUrl in prisma.config.ts datasource (NOT schema)"
python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/api/prisma.config.ts")
s = p.read_text()

# If already present, do nothing
if "shadowDatabaseUrl" in s:
    print("   - prisma.config.ts already has shadowDatabaseUrl")
    raise SystemExit(0)

# Find datasource block
m = re.search(r'(datasource\s*:\s*\{\s*)([\s\S]*?)(\}\s*,?)', s)
if not m:
    print("❌ Could not find `datasource: { ... }` in prisma.config.ts")
    raise SystemExit(1)

head, body, tail = m.group(1), m.group(2), m.group(3)

# Try to insert after url line if present
if re.search(r'url\s*:\s*', body):
    body2 = re.sub(r'(url\s*:\s*[^,\n]+,\s*)', r'\1    shadowDatabaseUrl: process.env["SHADOW_DATABASE_URL"],\n', body, count=1)
else:
    body2 = '    shadowDatabaseUrl: process.env["SHADOW_DATABASE_URL"],\n' + body

ns = s[:m.start()] + head + body2 + tail + s[m.end():]
p.write_text(ns)
print('   - Inserted: shadowDatabaseUrl: process.env["SHADOW_DATABASE_URL"]')
PY

echo "🔧 4) Ensure apps/api/.env has SHADOW_DATABASE_URL (derived from DATABASE_URL if possible)"
if [ ! -f "$ENVFILE" ]; then
  echo "DATABASE_URL=" > "$ENVFILE"
fi

python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/api/.env")
env = p.read_text()

def get(k):
    m = re.search(rf'^{k}=(.*)$', env, re.M)
    return m.group(1).strip() if m else ""

db = get("DATABASE_URL").strip('"').strip("'")
shadow = get("SHADOW_DATABASE_URL").strip('"').strip("'")

if shadow:
    print("   - SHADOW_DATABASE_URL already set")
    raise SystemExit(0)

# Try to derive from DATABASE_URL
# Replace trailing /dbname with /dbname_shadow
derived = ""
m = re.match(r'^(mysql:\/\/[^\/]+\/)([^?\n]+)(\?.*)?$', db)
if m:
    prefix, name, qs = m.group(1), m.group(2), m.group(3) or ""
    # Prefer explicit noxera_shadow if name is noxera
    if name == "noxera":
        name2 = "noxera_shadow"
    else:
        name2 = name + "_shadow"
    derived = prefix + name2 + qs

if not derived:
    derived = "mysql://USER:PASSWORD@127.0.0.1:3307/noxera_shadow"

p.write_text(env.rstrip() + "\nSHADOW_DATABASE_URL=\"" + derived + "\"\n")
print("   - Added SHADOW_DATABASE_URL")
print("   - Value:", derived)
PY

echo "🔎 5) Prisma validate + generate (should not error now)"
pnpm --filter api exec prisma format
pnpm --filter api exec prisma validate
pnpm --filter api db:generate

echo ""
echo "🐳 6) Try to create shadow DB in the MySQL/MariaDB container (best-effort)"
CID="$(docker ps --format '{{.ID}} {{.Image}} {{.Names}} {{.Ports}}' | grep -Ei 'mysql|mariadb' | head -n 1 | awk '{print $1}' || true)"
if [ -z "$CID" ]; then
  echo "   - ⚠️ Could not find a mysql/mariadb container. Skipping shadow DB creation."
  echo "   - If your DB runs elsewhere, create database `noxera_shadow` manually and grant privileges to user 'noxera'."
  exit 0
fi

echo "   - DB container: $CID"

ROOTPW="$(docker exec "$CID" sh -lc 'printenv MYSQL_ROOT_PASSWORD || true' | tr -d '\r' || true)"
if [ -z "$ROOTPW" ]; then
  ROOTPW="$(docker exec "$CID" sh -lc 'printenv MARIADB_ROOT_PASSWORD || true' | tr -d '\r' || true)"
fi

ALLOW_EMPTY="$(docker exec "$CID" sh -lc 'printenv MYSQL_ALLOW_EMPTY_PASSWORD || printenv MARIADB_ALLOW_EMPTY_ROOT_PASSWORD || true' | tr -d "\r" || true)"

DBCLI="$(docker exec "$CID" sh -lc 'command -v mysql || command -v mariadb || true' | tr -d "\r" || true)"
if [ -z "$DBCLI" ]; then
  echo "   - ⚠️ No mysql/mariadb client found in container. Skipping."
  exit 0
fi

if [ -n "$ROOTPW" ]; then
  echo "   - Using root password from container env."
  docker exec "$CID" sh -lc "$DBCLI -uroot -p\"$ROOTPW\" -e \"CREATE DATABASE IF NOT EXISTS \\\`noxera_shadow\\\`; GRANT ALL PRIVILEGES ON \\\`noxera_shadow\\\`.* TO 'noxera'@'%'; FLUSH PRIVILEGES;\""
  echo "   - ✅ Created noxera_shadow and granted privileges."
elif echo "$ALLOW_EMPTY" | grep -qi '^yes$\|^true$\|^1$'; then
  echo "   - Root allows empty password."
  docker exec "$CID" sh -lc "$DBCLI -uroot -e \"CREATE DATABASE IF NOT EXISTS \\\`noxera_shadow\\\`; GRANT ALL PRIVILEGES ON \\\`noxera_shadow\\\`.* TO 'noxera'@'%'; FLUSH PRIVILEGES;\""
  echo "   - ✅ Created noxera_shadow and granted privileges."
else
  echo "   - ⚠️ Could not read root password from container env."
  echo "     Find it in docker compose (.env / compose file), then run:"
  echo "     docker exec -it $CID sh -lc '$DBCLI -uroot -p<ROOTPW> -e \"CREATE DATABASE IF NOT EXISTS \\`noxera_shadow\\`; GRANT ALL PRIVILEGES ON \\`noxera_shadow\\`.* TO '\\''noxera'\\''@'\\''%'\\''; FLUSH PRIVILEGES;\"'"
fi

echo ""
echo "✅ Recovery done."
echo "NEXT:"
echo "  pnpm --filter api db:migrate -- --name sprint1_members"
