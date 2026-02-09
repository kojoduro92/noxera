set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "📍 Repo root: $(pwd)"

# 1) Ensure pnpm-workspace.yaml exists and matches our structure
cat > pnpm-workspace.yaml <<'YAML'
packages:
  - "apps/*"
  - "packages/*"
YAML
echo "✅ pnpm-workspace.yaml ensured"

# 2) Ensure .npmrc has workspace linking (safe to overwrite)
cat > .npmrc <<'EOF'
shared-workspace-lockfile=true
link-workspace-packages=true
prefer-workspace-packages=true
auto-install-peers=true
EOF
echo "✅ .npmrc ensured"

# 3) Ensure each web app has next/react/react-dom (do NOT rely on old lockfiles)
ensure_next_deps () {
  local APP="$1"
  local P="apps/$APP/package.json"
  if [ ! -f "$P" ]; then
    echo "❌ Missing $P" >&2
    exit 1
  fi

  node - <<NODE
const fs = require("fs");
const p = "$P";
const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.dependencies ||= {};

const must = ["next","react","react-dom"];
let changed = false;

for (const k of must) {
  if (!j.dependencies[k] && !j.devDependencies?.[k]) {
    j.dependencies[k] = "latest";
    changed = true;
  }
}

j.dependencies["@noxera/ui"] = "workspace:*";
j.dependencies["@noxera/shared"] = "workspace:*";

if (changed) console.log("🔧 Added missing Next deps in", p);
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
NODE

  echo "✅ deps checked: $APP"
}

ensure_next_deps "web-church"
ensure_next_deps "web-superadmin"
ensure_next_deps "web-public"

# 4) Clean install (workspace-aware)
rm -rf node_modules pnpm-lock.yaml
rm -rf apps/web-church/node_modules apps/web-superadmin/node_modules apps/web-public/node_modules

echo "✅ Installing workspace dependencies..."
pnpm -w install

# 5) Verify next is resolvable
echo "✅ Verifying next binary..."
pnpm -C apps/web-superadmin exec next --version

echo "🎉 Fixed: Next is installed and resolvable."
