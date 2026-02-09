set -euo pipefail

cd "$(pwd)"

echo "📍 Repo root: $(pwd)"

# 1) Ensure workspace definition exists (must be at repo root)
cat > pnpm-workspace.yaml <<'YAML'
packages:
  - "apps/*"
  - "packages/*"
YAML
echo "✅ pnpm-workspace.yaml ensured"

# 2) Ensure workspace linking behavior
cat > .npmrc <<'EOF'
shared-workspace-lockfile=true
link-workspace-packages=true
prefer-workspace-packages=true
auto-install-peers=true
EOF
echo "✅ .npmrc ensured"

# 3) Remove nested lockfiles (these often break workspace installs)
echo "🧹 Removing nested lockfiles..."
find apps packages -maxdepth 3 -type f \( -name "pnpm-lock.yaml" -o -name "package-lock.json" -o -name "yarn.lock" \) -print -delete || true

# 4) Remove node_modules everywhere + root lockfile (fresh, deterministic)
echo "🧹 Removing node_modules + root lockfile..."
rm -rf node_modules pnpm-lock.yaml
find apps packages -maxdepth 3 -type d -name "node_modules" -prune -exec rm -rf '{}' + || true

# 5) Ensure each app has its core deps (safety net)
ensure_dep () {
  local PKG="$1"
  local NAME="$2"
  local VALUE="$3"

  node - <<NODE
const fs = require("fs");
const p = "$PKG";
const name = "$NAME";
const value = "$VALUE";

const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.dependencies ||= {};
j.devDependencies ||= {};

if (!j.dependencies[name] && !j.devDependencies[name]) {
  j.dependencies[name] = value;
  fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
  console.log("🔧 Added", name, "->", value, "in", p);
}
NODE
}

# Next apps must have next/react/react-dom
for app in web-church web-superadmin web-public; do
  P="apps/$app/package.json"
  [ -f "$P" ] || { echo "❌ Missing $P"; exit 1; }
  ensure_dep "$P" "next" "latest"
  ensure_dep "$P" "react" "latest"
  ensure_dep "$P" "react-dom" "latest"

  # Ensure workspace protocol for local packages
  node - <<NODE
const fs = require("fs");
const p = "$P";
const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.dependencies ||= {};
j.dependencies["@noxera/ui"] = "workspace:*";
j.dependencies["@noxera/shared"] = "workspace:*";
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
console.log("✅ Set workspace deps in", p);
NODE
done

# Nest app should have @nestjs/cli in devDependencies (needed for `nest start --watch`)
API_P="apps/api/package.json"
if [ -f "$API_P" ]; then
  ensure_dep "$API_P" "@nestjs/cli" "^11.0.0"
else
  echo "❌ Missing apps/api/package.json"
  exit 1
fi

# 6) Install at workspace root (this should install ALL apps + packages)
echo "📦 Installing workspace deps (this should be a LOT more than +4 packages)..."
pnpm -w install

# 7) Verify binaries exist (hard check)
echo "🔎 Verifying binaries..."
pnpm -C apps/web-superadmin exec next --version
pnpm -C apps/api exec nest --version

echo "🎉 Workspace install fixed. Binaries resolved."
