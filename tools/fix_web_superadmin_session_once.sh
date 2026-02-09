#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "✅ Repo root: $ROOT"

py() { python3 - "$@"; }

patch_file() {
  local file="$1"
  [ -f "$file" ] || { echo "❌ Missing: $file"; exit 1; }
}

patch_file "apps/web-superadmin/lib/api.ts"
patch_file "apps/web-superadmin/app/churches/new/ui.tsx"
patch_file "apps/web-superadmin/app/login/page.tsx"

echo "🔧 Patching apps/web-superadmin/lib/api.ts (always send cookies)..."
py <<'PY'
from pathlib import Path
p = Path("apps/web-superadmin/lib/api.ts")
s = p.read_text(encoding="utf-8")

# Ensure apiFetch includes credentials: "include"
# Turn:
#   fetch(..., {
#     ...init,
# into:
#   fetch(..., {
#     credentials: "include",
#     ...init,
import re

pat = re.compile(r'(const\s+res\s*=\s*await\s*fetch\(\s*`?\$\{API_BASE\}\$\{path\}`?\s*,\s*{\s*)(\.\.\.init\s*,)', re.M)
if "credentials: \"include\"" not in s:
    s2, n = pat.subn(r'\1credentials: "include",\n    \2', s, count=1)
    if n == 0:
        # fallback: simple insert right after "{\n"
        s2 = re.sub(
            r'(const\s+res\s*=\s*await\s*fetch\([^\n]+,\s*{\s*\n)',
            r'\1    credentials: "include",\n',
            s,
            count=1,
            flags=re.M
        )
    s = s2

p.write_text(s, encoding="utf-8")
print("OK")
PY

echo "🔧 Patching client fetch() calls to include credentials (login + create)..."
py <<'PY'
from pathlib import Path
import re

targets = [
  Path("apps/web-superadmin/app/churches/new/ui.tsx"),
  Path("apps/web-superadmin/app/login/page.tsx"),
]

def add_credentials(text: str) -> str:
  # Add credentials: "include" to fetch calls that hit /auth/session or /admin/*
  # ONLY if the options object exists and credentials isn't already present.
  def repl(m: re.Match) -> str:
    head = m.group(1)
    body = m.group(2)
    if re.search(r'\bcredentials\s*:', body):
      return m.group(0)
    return f"{head}\n      credentials: \"include\",{body}"

  # Match: fetch(SOMETHING, {  ...  })
  # where SOMETHING contains /auth/session OR /admin/
  pattern = re.compile(
    r'(fetch\(\s*[^,]*?(?:/auth/session|/admin/)[^,]*?,\s*{\s*)([\s\S]*?\})',
    re.M
  )
  return pattern.sub(repl, text)

for p in targets:
  s = p.read_text(encoding="utf-8")
  s2 = add_credentials(s)
  if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print(f"patched: {p}")
  else:
    print(f"no change: {p}")
PY

echo ""
echo "✅ DONE."
echo ""
echo "NEXT:"
echo "  1) Restart API:        (Ctrl+C) then: pnpm --filter api dev"
echo "  2) Restart Web:        (Ctrl+C) then: pnpm --filter web-superadmin dev"
echo ""
echo "Quick test (browser should now work):"
echo "  Open: http://localhost:3001/churches   (or whatever port web-superadmin runs on)"
echo ""
echo "API test (still works):"
echo "  curl -i -X POST http://localhost:3000/auth/session -H 'content-type: application/json' -d '{\"dev\":true}' -c /tmp/noxera.cookies"
echo "  curl -i http://localhost:3000/admin/tenants -b /tmp/noxera.cookies"
