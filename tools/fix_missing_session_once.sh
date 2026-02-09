#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "✅ Repo root: $ROOT"

py() { python3 - "$@"; }

need() { [ -f "$1" ] || { echo "❌ Missing file: $1"; exit 1; }; }

need "apps/web-superadmin/lib/api.ts"
need "apps/api/src/main.ts"

# optional files (patch if present)
LOGIN="apps/web-superadmin/app/login/page.tsx"
NEWCHURCH="apps/web-superadmin/app/churches/new/ui.tsx"

echo "🔧 Patch web-superadmin API base + auto dev session retry..."
py <<'PY'
from pathlib import Path
import re

p = Path("apps/web-superadmin/lib/api.ts")
s = p.read_text(encoding="utf-8")

# 1) Make API_BASE follow the same hostname as the page (fix localhost vs 127.0.0.1 cookie/site mismatch)
api_base_block = """export const API_BASE = (() => {
  const envBase = process.env.NEXT_PUBLIC_API_URL?.replace(/\\/$/, "");
  if (envBase) return envBase;
  // In dev, make API hostname match the page hostname to avoid SameSite/host mismatches
  if (typeof window !== "undefined") return `http://${window.location.hostname}:3000`;
  return "http://localhost:3000";
})();"""

s = re.sub(
  r'export const API_BASE\s*=\s*[\s\S]*?;\s*',
  api_base_block + "\n\n",
  s,
  count=1
)

# 2) Inject ensureDevSession helper if missing
if "__devSessionPromise" not in s:
  helper = """let __devSessionPromise: Promise<void> | null = null;

async function ensureDevSession(): Promise<void> {
  if (typeof window === "undefined") return;
  // Only auto-session in local dev
  const host = window.location.hostname;
  const isLocal = host === "localhost" || host === "127.0.0.1";
  if (!isLocal) return;

  if (__devSessionPromise) return __devSessionPromise;

  __devSessionPromise = (async () => {
    const r = await fetch(`${API_BASE}/auth/session`, {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dev: true }),
    });
    if (!r.ok) {
      const t = await r.text().catch(() => "");
      __devSessionPromise = null;
      throw new Error(t || "Failed to create dev session");
    }
  })();

  return __devSessionPromise;
}

"""
  # insert right before apiFetch
  s = re.sub(r'\nasync function apiFetch<', "\n" + helper + "async function apiFetch<", s, count=1)

# 3) Replace apiFetch with a robust version:
#    - always credentials: include
#    - on 401 Missing session in browser: create dev session then retry once
def replace_api_fetch(src: str) -> str:
  start = src.find("async function apiFetch<")
  if start == -1:
    raise SystemExit("Could not find apiFetch() to patch")

  # find function end by brace matching
  i = src.find("{", start)
  if i == -1:
    raise SystemExit("Could not parse apiFetch()")

  depth = 0
  j = i
  while j < len(src):
    if src[j] == "{": depth += 1
    elif src[j] == "}":
      depth -= 1
      if depth == 0:
        end = j + 1
        break
    j += 1
  else:
    raise SystemExit("Could not find end of apiFetch()")

  new_fn = """async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const doFetch = (extra?: RequestInit) =>
    fetch(`${API_BASE}${path}`, {
      credentials: "include",
      ...init,
      ...extra,
      headers: {
        "Content-Type": "application/json",
        ...(init?.headers || {}),
        ...(extra?.headers || {}),
      },
    });

  let res = await doFetch();

  if (!res.ok) {
    const txt = await res.text().catch(() => "");

    // Auto-fix: if we have no cookie session yet in local dev, create it and retry once.
    if (
      res.status === 401 &&
      typeof window !== "undefined" &&
      (txt.includes("Missing session") || txt.includes("Unauthorized"))
    ) {
      await ensureDevSession();
      res = await doFetch();
      if (!res.ok) {
        const txt2 = await res.text().catch(() => "");
        throw new Error(`API ${res.status}: ${txt2 || res.statusText}`);
      }
      return (await res.json()) as T;
    }

    throw new Error(`API ${res.status}: ${txt || res.statusText}`);
  }

  return (await res.json()) as T;
}"""
  return src[:start] + new_fn + src[end:]

s2 = replace_api_fetch(s)
p.write_text(s2, encoding="utf-8")
print("✅ Patched apps/web-superadmin/lib/api.ts")
PY

echo "🔧 Patch API CORS to allow localhost + 127.0.0.1..."
py <<'PY'
from pathlib import Path
import re

p = Path("apps/api/src/main.ts")
s = p.read_text(encoding="utf-8")

# Replace origin regex array if it only allows localhost
# Make it allow both localhost and 127.0.0.1
if "enableCors" in s:
  s2 = re.sub(
    r'origin:\s*\[\s*/\^http:\\/\\/localhost:\\\\d\+\$\/\s*\]\s*,',
    'origin: [/^http:\\/\\/localhost:\\d+$/, /^http:\\/\\/127\\.0\\.0\\.1:\\d+$/],',
    s
  )
  # If not found, try a more general patch to insert 127.0.0.1 alongside localhost regex
  if s2 == s and "origin:" in s and "localhost" in s:
    s2 = re.sub(
      r'origin:\s*\[\s*/\^http:\\/\\/localhost:\\\\d\+\$\/\s*,?\s*\]\s*,',
      'origin: [/^http:\\/\\/localhost:\\d+$/, /^http:\\/\\/127\\.0\\.0\\.1:\\d+$/],',
      s
    )
  s = s2

p.write_text(s, encoding="utf-8")
print("✅ Patched apps/api/src/main.ts")
PY

# 4) Optional: make sure login + new church dev session calls store cookie
for f in "$LOGIN" "$NEWCHURCH"; do
  if [ -f "$f" ]; then
    echo "🔧 Ensuring credentials: include in $f ..."
    py <<PY
from pathlib import Path
import re

p = Path("$f")
s = p.read_text(encoding="utf-8")

def patch_fetch(text: str) -> str:
  # Add credentials: "include" into fetch options for /auth/session and /admin/ calls if missing.
  # Pattern: fetch(..., { ... })
  def repl(m):
    block = m.group(0)
    if re.search(r'\\bcredentials\\s*:', block):
      return block
    # insert after opening "{"
    return block.replace("{", "{\n      credentials: \"include\",", 1)

  pat = re.compile(r'fetch\\(\\s*[^,]*?(?:/auth/session|/admin/)[^,]*?,\\s*\\{[\\s\\S]*?\\}\\s*\\)', re.M)
  return pat.sub(repl, text)

s2 = patch_fetch(s)
p.write_text(s2, encoding="utf-8")
print("✅ Patched", p)
PY
  fi
done

echo ""
echo "✅ ALL DONE."
echo ""
echo "NOW RESTART:"
echo "  1) API:  Ctrl+C then   pnpm --filter api dev"
echo "  2) WEB:  Ctrl+C then   pnpm --filter web-superadmin dev"
echo ""
echo "IMPORTANT:"
echo "  Open the web app on the SAME hostname:"
echo "   - If you open http://localhost:3001 -> it will call http://localhost:3000"
echo "   - If you open http://127.0.0.1:3001 -> it will call http://127.0.0.1:3000"
echo ""
echo "Browser quick test:"
echo "  Go to /churches and hit Retry once. It should auto-create a dev session and load tenants."
