set -euo pipefail

fix_next_cache () {
  local d="$1"
  if [ -d "$d" ]; then
    chmod -R u+rwX "$d" 2>/dev/null || true
    rm -rf "$d" 2>/dev/null || true
  fi
}

# If permission is still wrong (common if it was created by another user), fix ownership.
# This may prompt for your password.
sudo_fix_owner () {
  local d="$1"
  if [ -d "$d" ]; then
    sudo chown -R "$USER":"$(id -gn)" "$d" || true
  fi
}

# 1) Rewrite globals.css for Tailwind v4 + UI styles
write_globals () {
  local app="$1"
  local f="$app/app/globals.css"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<'CSS'
@import "tailwindcss";
@import "@noxera/ui/styles/index.css";

/* App-level globals (keep minimal) */
html, body { height: 100%; }
:root { color-scheme: light; }
.dark { color-scheme: dark; }
CSS
  echo "✅ Rewrote $f"
}

write_globals "apps/web-superadmin"
write_globals "apps/web-church"
write_globals "apps/web-public"

# 2) Ensure PostCSS config uses Tailwind v4 plugin
write_postcss () {
  local app="$1"
  cat > "$app/postcss.config.mjs" <<'MJS'
export default {
  plugins: {
    "@tailwindcss/postcss": {}
  }
};
MJS
  echo "✅ Wrote $app/postcss.config.mjs"
}

write_postcss "apps/web-superadmin"
write_postcss "apps/web-church"
write_postcss "apps/web-public"

# 3) Clear .next caches (try normal; if denied, fix owner then retry)
for d in apps/web-superadmin/.next apps/web-church/.next apps/web-public/.next; do
  fix_next_cache "$d"
done

# If still exists, do sudo owner fix and retry
for d in apps/web-superadmin/.next apps/web-church/.next apps/web-public/.next; do
  if [ -d "$d" ]; then
    echo "⚠️  Still exists (permission). Fixing ownership: $d"
    sudo_fix_owner "$d"
    fix_next_cache "$d"
  fi
done

echo "🎉 CSS + PostCSS + .next cache fixed."
