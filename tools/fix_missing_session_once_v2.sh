#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "✅ Repo root: $ROOT"

py() { python3 - "$@"; }
need() { [ -f "$1" ] || { echo "❌ Missing file: $1"; exit 1; }; }

need "apps/api/src/main.ts"
need "apps/web-superadmin/lib/api.ts"

echo "🔧 Fix API CORS (allow localhost + 127.0.0.1)..."
py <<'PY'
from pathlib import Path

p = Path("apps/api/src/main.ts")
s = p.read_text(encoding="utf-8")

old1 = "origin: [/^http:\\/\\/localhost:\\d+$/],"
old2 = "origin: [/^http:\\/\\/localhost:\\d+$/]"
new1 = "origin: [/^http:\\/\\/localhost:\\d+$/, /^http:\\/\\/127\\.0\\.0\\.1:\\d+$/],"
new2 = "origin: [/^http:\\/\\/localhost:\\d+$/, /^http:\\/\\/127\\.0\\.0\\.1:\\d+$/]"

if "127\\.0\\.0\\.1" in s or "127.0.0.1" in s:
    print("✅ main.ts already allows 127.0.0.1")
else:
    if old1 in s:
        s = s.replace(old1, new1)
        p.write_text(s, encoding="utf-8")
        print("✅ Patched main.ts origin (with comma)")
    elif old2 in s:
        s = s.replace(old2, new2)
        p.write_text(s, encoding="utf-8")
        print("✅ Patched main.ts origin (no comma)")
    else:
        print("⚠️ Could not find the expected origin line in main.ts. Please open main.ts and paste the enableCors block here.")
PY

echo "🔧 Fix web-superadmin API_BASE to ALWAYS match page hostname (prevents SameSite cookie 401)..."
py <<'PY'
from pathlib import Path
import re

p = Path("apps/web-superadmin/lib/api.ts")
s = p.read_text(encoding="utf-8")

new_block = """export const API_BASE = (() => {
  const envBase = process.env.NEXT_PUBLIC_API_URL?.replace(/\\/$/, "");
  if (typeof window !== "undefined") {
    const winHost = window.location.hostname;
    // If envBase points to a different host, ignore it in the browser to avoid SameSite cookie issues.
    if (envBase) {
      try {
        const u = new URL(envBase);
        if (u.hostname === winHost) return envBase;
      } catch {}
    }
    return `http://${winHost}:3000`;
  }
  return envBase || "http://localhost:3000";
})();"""

# replace the whole API_BASE IIFE
s2, n = re.subn(
    r'export const API_BASE\s*=\s*\(\(\)\s*=>\s*\{[\s\S]*?\}\)\(\);\s*',
    new_block + "\n\n",
    s,
    count=1
)

if n == 0:
    # fallback: if formatting differs, just warn
    print("⚠️ Could not replace API_BASE block automatically. Paste the top of apps/web-superadmin/lib/api.ts here.")
else:
    p.write_text(s2, encoding="utf-8")
    print("✅ Patched apps/web-superadmin/lib/api.ts API_BASE")
PY

echo ""
echo "✅ DONE."
echo ""
echo "NOW:"
echo "  1) Restart API:  Ctrl+C then  pnpm --filter api dev"
echo "  2) Restart Web:  Ctrl+C then  pnpm --filter web-superadmin dev"
echo ""
echo "IMPORTANT: Open the web app on ONE hostname and keep it:"
echo "  - http://localhost:3001   (API becomes http://localhost:3000)"
echo "  - OR http://127.0.0.1:3001 (API becomes http://127.0.0.1:3000)"
echo ""
echo "Then go to /churches and it should load (no more Missing session 401)."
