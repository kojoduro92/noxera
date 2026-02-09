set -euo pipefail

echo "✨ Applying Sprint 0 polish pack..."

# -------------------------
# 1) Reusable UI helper for JSON + chips (in web-superadmin)
# -------------------------
mkdir -p apps/web-superadmin/components/common

cat > apps/web-superadmin/components/common/MetaViewer.tsx <<'TSX'
"use client";

import * as React from "react";
import { Badge, Button } from "@noxera/ui";

function tryStringify(v: any) {
  try {
    return JSON.stringify(v, null, 2);
  } catch {
    return String(v);
  }
}

function flatPairs(obj: any, prefix = ""): Array<{ k: string; v: any }> {
  const out: Array<{ k: string; v: any }> = [];
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    out.push({ k: prefix || "value", v: obj });
    return out;
  }
  for (const key of Object.keys(obj)) {
    const value = obj[key];
    const k = prefix ? `${prefix}.${key}` : key;
    if (value && typeof value === "object" && !Array.isArray(value)) out.push(...flatPairs(value, k));
    else out.push({ k, v: value });
  }
  return out;
}

export function MetaChips({ metadata }: { metadata: any }) {
  const pairs = React.useMemo(() => flatPairs(metadata).slice(0, 8), [metadata]);

  if (!pairs.length) return <span className="text-xs text-muted-foreground">—</span>;

  return (
    <div className="flex flex-wrap gap-1.5">
      {pairs.map((p) => (
        <Badge key={p.k} variant="outline" className="max-w-[260px] truncate">
          <span className="font-semibold">{p.k}:</span>&nbsp;{String(p.v)}
        </Badge>
      ))}
    </div>
  );
}

export function MetaJson({ metadata }: { metadata: any }) {
  const [open, setOpen] = React.useState(false);
  if (metadata == null) return <span className="text-xs text-muted-foreground">—</span>;

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <Button type="button" variant="outline" size="sm" onClick={() => setOpen((v) => !v)}>
          {open ? "Hide" : "Show"} JSON
        </Button>
        <span className="text-xs text-muted-foreground">Safe viewer (read-only)</span>
      </div>

      {open ? (
        <pre className="max-h-64 overflow-auto rounded-2xl border border-border/70 bg-muted/20 p-3 text-xs leading-relaxed">
{tryStringify(metadata)}
        </pre>
      ) : null}
    </div>
  );
}
TSX

# -------------------------
# 2) Improve Audit Logs page UI (metadata + success badge)
# -------------------------
AUDIT_PAGE="apps/web-superadmin/app/(sa)/audit-logs/page.tsx"
test -f "$AUDIT_PAGE" || { echo "❌ Missing $AUDIT_PAGE"; exit 1; }

node - <<'NODE'
const fs = require("fs");
const p = "apps/web-superadmin/app/(sa)/audit-logs/page.tsx";
let s = fs.readFileSync(p, "utf8");

if (!s.includes('MetaChips')) {
  s = s.replace(
    /import\s+\{\s*([\s\S]*?)\}\s+from\s+"@noxera\/ui";/m,
    (m, inner) => `import {\n  ${inner.trim()}\n} from "@noxera/ui";\nimport { MetaChips, MetaJson } from "@/components/common/MetaViewer";`
  );
}

// Expand columns to include Success + Metadata
s = s.replace(
  /grid-cols-\[1\.2fr_1\.2fr_1fr_1fr\]/g,
  "grid-cols-[1.1fr_1.1fr_1fr_1fr_.7fr_1.2fr]"
);

// Replace header row labels
s = s.replace(
  /<div>Time<\/div>\s*<div>Tenant<\/div>\s*<div>Action<\/div>\s*<div>Entity<\/div>/m,
  `<div>Time</div>\n          <div>Tenant</div>\n          <div>Action</div>\n          <div>Entity</div>\n          <div>OK</div>\n          <div>Metadata</div>`
);

// Replace row rendering to include success + metadata chips + expandable JSON
s = s.replace(
  /<div key=\{a\.id\} className="grid[\s\S]*?<\/div>\s*\)\)\s*\)\s*: \(/m,
  (match) => {
    // This is risky to regex-replace large blocks; do a safer targeted replacement below.
    return match;
  }
);

// Safer: insert new cells right before row closing for each item
s = s.replace(
  /<div className="text-xs text-muted-foreground">\s*\{a\.entityType\}\{a\.entityId \? ` • \$\{a\.entityId\}` : ""\}\s*<\/div>\s*<\/div>\s*\)\s*\)\s*\)\s*: \(/m,
  `<div className="text-xs text-muted-foreground">
                {a.entityType}{a.entityId ? \` • \${a.entityId}\` : ""}
              </div>
            </div>

            <div>
              <span className={a.success ? "text-xs font-semibold text-emerald-600" : "text-xs font-semibold text-rose-600"}>
                {a.success ? "Yes" : "No"}
              </span>
            </div>

            <div className="space-y-2">
              <MetaChips metadata={a.metadata} />
              <MetaJson metadata={a.metadata} />
            </div>
          </div>
        ))
      ) : (`
  );

fs.writeFileSync(p, s);
console.log("✅ Upgraded audit logs page (success + metadata viewer)");
NODE

# -------------------------
# 3) Tenant detail: add Plan change UI stub
# -------------------------
TENANT_PAGE="apps/web-superadmin/app/(sa)/churches/[id]/page.tsx"
test -f "$TENANT_PAGE" || { echo "❌ Missing $TENANT_PAGE"; exit 1; }

node - <<'NODE'
const fs = require("fs");
const p = "apps/web-superadmin/app/(sa)/churches/[id]/page.tsx";
let s = fs.readFileSync(p, "utf8");

// Add a plan-change section in the Plan card (disabled controls)
if (!s.includes("Plan change (Sprint 1)")) {
  s = s.replace(
    /<CardContent className="space-y-2">([\s\S]*?)<\/CardContent>/m,
    (m, inner) => {
      if (!m.includes("Plan</CardTitle>")) return m;
      return `<CardContent className="space-y-3">
            <div className="text-sm font-semibold">${'${tenant.planTier}'}</div>
            <div className="text-xs text-muted-foreground">Seats</div>
            <div className="text-sm">${'${seatsUsed}'}/${'${seatsLimit}'} seats</div>
            <Progress value={seatsUsed} max={seatsLimit} />

            <div className="pt-2">
              <div className="text-xs font-semibold">Plan change (Sprint 1)</div>
              <div className="mt-2 flex gap-2">
                <select
                  disabled
                  className="h-10 flex-1 rounded-xl border border-border/70 bg-background/60 px-3 text-sm opacity-60"
                  defaultValue={tenant.planTier}
                >
                  <option value="TRIAL">TRIAL</option>
                  <option value="BASIC">BASIC</option>
                  <option value="PRO">PRO</option>
                  <option value="ENTERPRISE">ENTERPRISE</option>
                </select>
                <Button disabled variant="outline">Save</Button>
              </div>
              <div className="mt-1 text-xs text-muted-foreground">
                Coming in Sprint 1: billing + proration + audit trail.
              </div>
            </div>
          </CardContent>`;
    }
  );
}

fs.writeFileSync(p, s);
console.log("✅ Added plan change stub (disabled) to tenant detail");
NODE

echo "🎉 Sprint 0 polish pack applied."
echo "Restart web-superadmin to see changes:"
echo "  pnpm -C apps/web-superadmin dev"
