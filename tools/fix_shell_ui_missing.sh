set -euo pipefail

APP="apps/web-superadmin"
DIR="$APP/components/shell"

mkdir -p "$DIR"

# 1) Ensure SuperAdminShell exists (fail fast if not)
if [ ! -f "$DIR/SuperAdminShell.tsx" ]; then
  echo "❌ Missing $DIR/SuperAdminShell.tsx"
  echo "   Create/restore SuperAdminShell.tsx first, then rerun this script."
  exit 1
fi

# 2) Create ui.tsx as a compatibility layer (fixes 'Can't resolve ./ui' immediately)
cat > "$DIR/ui.tsx" <<'TSX'
export { default } from "./SuperAdminShell";
TSX

# 3) Create a clean index.ts (so imports from "@/components/shell" work too)
cat > "$DIR/index.ts" <<'TS'
export { default as SuperAdminShell } from "./SuperAdminShell";
export { default } from "./SuperAdminShell";
TS

# 4) Optional: if any file still imports "./ui", point it directly to "./SuperAdminShell"
# (Keeping ui.tsx means either way works; this just reduces confusion)
if command -v rg >/dev/null 2>&1; then
  rg -n --hidden --no-ignore-vcs 'from\s+["'\''"]\./ui["'\''"]' "$DIR" || true
fi

# replace in folder only (safe)
perl -pi -e 's/from\s+["'\'']\.\/ui["'\'']/from "\.\/SuperAdminShell"/g' "$DIR"/*.ts "$DIR"/*.tsx 2>/dev/null || true

# 5) Clear Next cache for this app (important with Turbopack)
rm -rf "$APP/.next"

echo "✅ Fixed: created components/shell/ui.tsx + index.ts and cleared .next cache."
