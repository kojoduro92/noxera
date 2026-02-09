set -euo pipefail

echo "🧩 Fixing Step 4.5 errors (Next route slug + API TS + stable ports)..."

# -----------------------------
# 1) Fix API TS error: Query,,
# -----------------------------
API_FILE="apps/api/src/admin/admin-tenants.controller.ts"
if [ -f "$API_FILE" ]; then
  node - <<'NODE'
const fs = require("fs");
const p = "apps/api/src/admin/admin-tenants.controller.ts";
let s = fs.readFileSync(p, "utf8");

// Remove accidental double commas like "Query,,"
while (s.includes(",,")) s = s.replace(/,,/g, ",");

// Also fix patterns like "Query,," or "Query, ,"
s = s.replace(/,\s*,/g, ", ");

fs.writeFileSync(p, s);
console.log("✅ Fixed TS import commas in", p);
NODE
else
  echo "⚠️  $API_FILE not found (skipping TS fix)"
fi

# -----------------------------
# 2) Fix Next dynamic route slug conflict:
#    Keep /churches/[id] and remove/rename /churches/[tenantId]
# -----------------------------
BASE="apps/web-superadmin/app/(sa)/churches"

ID_DIR="$BASE/[id]"
TENANT_DIR="$BASE/[tenantId]"

if [ -d "$TENANT_DIR" ] && [ -d "$ID_DIR" ]; then
  echo "✅ Found both [id] and [tenantId]. Removing [tenantId] to resolve slug conflict..."
  rm -rf "$TENANT_DIR"
elif [ -d "$TENANT_DIR" ] && [ ! -d "$ID_DIR" ]; then
  echo "✅ Found only [tenantId]. Renaming to [id]..."
  mv "$TENANT_DIR" "$ID_DIR"
else
  echo "✅ No slug conflict folders found under $BASE (ok)."
fi

# -----------------------------
# 3) Stabilize dev ports so API stays on 3000, SuperAdmin on 3001
#    (prevents curl hitting Next HTML)
# -----------------------------
set_dev_port () {
  local pkg="$1"
  local port="$2"
  if [ -f "$pkg" ]; then
    node - <<NODE
const fs = require("fs");
const p = "$pkg";
const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.scripts ||= {};
j.scripts.dev = "next dev -p $port";
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\\n");
console.log("✅ Set dev script in", p, "-> next dev -p $port");
NODE
  fi
}

set_dev_port "apps/web-superadmin/package.json" 3001
set_dev_port "apps/web-church/package.json" 3002
set_dev_port "apps/web-public/package.json" 3003

# -----------------------------
# 4) Clear Next cache (avoid stale route map)
# -----------------------------
rm -rf apps/web-superadmin/.next || true

echo "🎉 Fix complete."
echo "Next run order:"
echo "  1) pnpm -C apps/api start:dev        # API on :3000"
echo "  2) pnpm -C apps/web-superadmin dev   # Super Admin on :3001"
