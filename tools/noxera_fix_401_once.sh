#!/usr/bin/env bash
set -euo pipefail

# Find repo root (must contain apps/api)
ROOT="$PWD"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/apps/api" ]; do
  ROOT="$(dirname "$ROOT")"
done
[ -d "$ROOT/apps/api" ] || { echo "❌ Could not find repo root containing apps/api from: $PWD"; exit 1; }
cd "$ROOT"
echo "✅ Repo root: $ROOT"

PYBIN="python3"
command -v "$PYBIN" >/dev/null 2>&1 || PYBIN="python"
command -v "$PYBIN" >/dev/null 2>&1 || { echo "❌ Need python3 (or python)"; exit 1; }

# -----------------------------
# 1) API: install cookie-parser typings + patch main.ts for CORS credentials
# -----------------------------
echo "📦 Ensuring cookie-parser deps (api)..."
pnpm --filter api add cookie-parser >/dev/null 2>&1 || true
pnpm --filter api add -D @types/cookie-parser >/dev/null 2>&1 || true

# Find main.ts
MAIN_TS="$(grep -R --files-with-matches "NestFactory.create" apps/api/src 2>/dev/null | head -n 1 || true)"
[ -n "$MAIN_TS" ] || { echo "❌ Could not locate apps/api/src/**/main.ts (NestFactory.create)"; exit 1; }
echo "✅ Found main entry: $MAIN_TS"

$PYBIN - <<'PY'
from pathlib import Path
import re

p = Path("apps/api/src")
main = None
# Find file that contains NestFactory.create
for f in p.rglob("*.ts"):
    txt = f.read_text("utf-8", errors="ignore")
    if "NestFactory.create" in txt:
        main = f
        break
if not main:
    raise SystemExit("Could not find main.ts-like file")

txt = main.read_text("utf-8", errors="ignore")

# Add import cookie-parser if missing
if "cookie-parser" not in txt:
    # try to insert after the NestFactory import line
    lines = txt.splitlines()
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if (not inserted) and ("@nestjs/core" in line or "NestFactory" in line) and line.strip().startswith("import"):
            # insert next line if we later see first non-import; but safer: insert right after first import block
            pass
    # Insert after last import line
    last_import = 0
    for i,l in enumerate(lines):
        if l.strip().startswith("import "):
            last_import = i
    lines.insert(last_import+1, 'import cookieParser from "cookie-parser";')
    txt = "\n".join(lines)

# Ensure app.use(cookieParser()) exists
if "cookieParser()" not in txt and "app.use(cookieParser" not in txt:
    # insert right after app creation
    txt = re.sub(
        r"(const\s+app\s*=\s*await\s+NestFactory\.create\([^\)]*\);\s*)",
        r"\1\n  app.use(cookieParser());\n",
        txt,
        flags=re.M
    )

# Ensure CORS with credentials exists
if "enableCors" not in txt:
    # insert after cookie parser line (or after app creation if cookie parser didn't match)
    insert = """
  app.enableCors({
    // Allow local dev ports for web apps
    origin: [/^http:\\/\\/localhost:\\d+$/, /^http:\\/\\/127\\.0\\.0\\.1:\\d+$/],
    credentials: true,
  });
"""
    if "app.use(cookieParser());" in txt:
        txt = txt.replace("app.use(cookieParser());", "app.use(cookieParser());\n" + insert.strip("\n"))
    else:
        txt = re.sub(
            r"(const\s+app\s*=\s*await\s+NestFactory\.create\([^\)]*\);\s*)",
            r"\1\n" + insert.strip("\n") + "\n",
            txt,
            flags=re.M
        )
else:
    # If enableCors exists but credentials not present, do nothing automatically (avoid breaking custom config)
    pass

main.write_text(txt, "utf-8")
print(f"✅ Patched API CORS + cookieParser in: {main}")
PY

# -----------------------------
# 2) Web: create apiFetch helper that always sends cookies
#    and auto-replace fetch -> apiFetch for auth/session + admin/tenants calls
# -----------------------------
WEB_DIR=""
for d in apps/web-admin apps/admin-web apps/web apps/dashboard; do
  if [ -d "$d" ]; then WEB_DIR="$d"; break; fi
done

if [ -z "$WEB_DIR" ]; then
  echo "⚠️ Could not find a web app folder (looked for apps/web-admin, apps/admin-web, apps/web, apps/dashboard)."
  echo "   Skipping frontend patch. You'll still need credentials:'include' on fetch."
else
  echo "✅ Web app detected: $WEB_DIR"

  mkdir -p "$WEB_DIR/src/lib"

  if [ ! -f "$WEB_DIR/src/lib/apiFetch.ts" ]; then
    cat > "$WEB_DIR/src/lib/apiFetch.ts" <<'TS'
export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

/**
 * fetch wrapper that ALWAYS includes cookies for cross-port local dev.
 * Works with absolute URLs (http://...) or relative paths (/admin/tenants).
 */
export function apiFetch(input: RequestInfo | URL, init: RequestInit = {}) {
  const url =
    typeof input === "string" && input.startsWith("/")
      ? `${API_BASE}${input}`
      : input;

  return fetch(url, {
    ...init,
    credentials: "include",
  });
}
TS
    echo "✅ Created $WEB_DIR/src/lib/apiFetch.ts"
  else
    echo "✅ apiFetch helper already exists"
  fi

  echo "🔧 Patching web fetch calls for /auth/session and /admin/tenants..."
  $PYBIN - <<PY
from pathlib import Path
import re

web = Path("$WEB_DIR")
targets = []
for f in web.rglob("*"):
    if f.suffix not in (".ts", ".tsx", ".js", ".jsx"): 
        continue
    try:
        txt = f.read_text("utf-8", errors="ignore")
    except:
        continue
    if "/admin/tenants" in txt or "/auth/session" in txt:
        if "apiFetch(" in txt and 'from "@/lib/apiFetch"' in txt:
            continue
        targets.append(f)

def add_import(txt: str) -> str:
    if 'from "@/lib/apiFetch"' in txt or "from '@/lib/apiFetch'" in txt:
        return txt
    # insert after last import line
    lines = txt.splitlines()
    last_import = -1
    for i,l in enumerate(lines):
        if l.strip().startswith("import "):
            last_import = i
    if last_import >= 0:
        lines.insert(last_import+1, 'import { apiFetch } from "@/lib/apiFetch";')
        return "\n".join(lines)
    # no imports? prepend
    return 'import { apiFetch } from "@/lib/apiFetch";\n' + txt

patched = 0
for f in targets:
    txt = f.read_text("utf-8", errors="ignore")

    # Replace fetch( ... "/admin/tenants" ... ) with apiFetch(
    # Replace fetch( ... "/auth/session" ... ) with apiFetch(
    # (Only the calls that contain those substrings)
    def repl(match):
        inner = match.group(0)
        return inner.replace("fetch(", "apiFetch(", 1)

    new = txt

    # Match fetch( ... ) blocks in a loose way and only replace those containing target path
    # This is intentionally conservative.
    for needle in ("/admin/tenants", "/auth/session"):
        # Find occurrences of fetch( ...needle... )
        pattern = re.compile(r"fetch\([^;\n]*" + re.escape(needle) + r"[^;\n]*\)", re.M)
        new = pattern.sub(lambda m: m.group(0).replace("fetch(", "apiFetch(", 1), new)

    if new != txt:
        new = add_import(new)
        f.write_text(new, "utf-8")
        patched += 1

print(f"✅ Patched {patched} file(s) in web app.")
PY
fi

echo ""
echo "✅ DONE."
echo "Now restart API and Web:"
echo "  1) Stop API (Ctrl+C) and start it again"
echo "  2) Restart web-admin dev server too"
echo ""
echo "Test backend session + tenants (no browser involved):"
echo "  curl -i -X POST http://localhost:3000/auth/session -H 'content-type: application/json' -d '{\"dev\":true}' -c /tmp/noxera.cookies"
echo "  curl -i http://localhost:3000/admin/tenants -b /tmp/noxera.cookies"
