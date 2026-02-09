set -euo pipefail

echo "✅ Sprint 0 Step 4.5: features + audit + tenant detail..."

# -------------------------
# API: Feature merge helper
# -------------------------
mkdir -p apps/api/src/features

cat > apps/api/src/features/feature-merge.ts <<'TS'
export function isPlainObject(v: any): v is Record<string, any> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

export function deepMerge(base: any, override: any): any {
  if (override === undefined) return base;
  if (override === null) return null;

  if (Array.isArray(base) && Array.isArray(override)) return override; // override arrays
  if (isPlainObject(base) && isPlainObject(override)) {
    const out: Record<string, any> = { ...base };
    for (const k of Object.keys(override)) {
      out[k] = deepMerge(base[k], override[k]);
    }
    return out;
  }
  return override;
}
TS

cat > apps/api/src/features/features.service.ts <<'TS'
import { Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import { deepMerge, isPlainObject } from "./feature-merge";

@Injectable()
export class FeaturesService {
  constructor(private readonly prisma: PrismaService) {}

  async getTenantEffectiveFeatures(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      include: { plan: true, overrides: true },
    });
    if (!tenant) throw new NotFoundException("Tenant not found");

    const planFeatures = (tenant.plan.features ?? {}) as any;
    const overrideFeatures = (tenant.overrides?.overrides ?? {}) as any;

    const base = isPlainObject(planFeatures) ? planFeatures : {};
    const over = isPlainObject(overrideFeatures) ? overrideFeatures : {};

    const effective = deepMerge(base, over);
    return { planFeatures: base, overrideFeatures: over, effectiveFeatures: effective };
  }
}
TS

# -------------------------
# API: Admin endpoints
# - GET /admin/tenants/:id (detail + effective features)
# - GET /admin/audit (list)
# -------------------------
cat > apps/api/src/admin/admin-audit.controller.ts <<'TS'
import { Controller, Get, Query } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";

@Controller("admin/audit")
export class AdminAuditController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async list(
    @Query("q") q?: string,
    @Query("tenantId") tenantId?: string,
    @Query("action") action?: string,
    @Query("entityType") entityType?: string,
    @Query("entityId") entityId?: string,
    @Query("page") pageStr?: string,
    @Query("pageSize") pageSizeStr?: string
  ) {
    const page = Math.max(1, parseInt(pageStr || "1", 10) || 1);
    const pageSize = Math.min(100, Math.max(1, parseInt(pageSizeStr || "20", 10) || 20));
    const skip = (page - 1) * pageSize;

    const where: any = {};
    if (tenantId) where.tenantId = tenantId;
    if (action) where.action = action;
    if (entityType) where.entityType = entityType;
    if (entityId) where.entityId = entityId;

    if (q && q.trim()) {
      const s = q.trim();
      where.OR = [
        { action: { contains: s } },
        { entityType: { contains: s } },
        { entityId: { contains: s } },
      ];
    }

    const [total, items] = await Promise.all([
      this.prisma.auditLog.count({ where }),
      this.prisma.auditLog.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip,
        take: pageSize,
        include: {
          tenant: { select: { id: true, name: true, slug: true } },
          actor: { select: { id: true, email: true, displayName: true } },
        },
      }),
    ]);

    return {
      page,
      pageSize,
      total,
      items: items.map((a) => ({
        id: a.id,
        createdAt: a.createdAt,
        tenant: a.tenant ? { id: a.tenant.id, name: a.tenant.name, slug: a.tenant.slug } : null,
        actorType: a.actorType,
        actor: a.actor ? { id: a.actor.id, email: a.actor.email, displayName: a.actor.displayName } : null,
        action: a.action,
        entityType: a.entityType,
        entityId: a.entityId,
        success: a.success,
        metadata: a.metadata,
      })),
    };
  }
}
TS

# Patch AdminTenantsController to add GET /admin/tenants/:id
# (we keep your existing list + PATCH status exactly, and append the new handler)
TENANTS_CTL="apps/api/src/admin/admin-tenants.controller.ts"

node - <<'NODE'
const fs = require("fs");
const p = "apps/api/src/admin/admin-tenants.controller.ts";
let s = fs.readFileSync(p, "utf8");

if (!s.includes("FeaturesService")) {
  // add import
  s = s.replace(
    /import\s+\{\s*([\s\S]*?)\}\s+from\s+"@nestjs\/common";/m,
    (m, inner) => `import {\n  ${inner.trim()},\n  NotFoundException\n} from "@nestjs/common";`
  );

  // add service import
  if (!s.includes('from "../features/features.service"')) {
    s = s.replace(
      /from\s+"\.\.\/prisma\/prisma\.service";\n/m,
      `from "../prisma/prisma.service";\nimport { FeaturesService } from "../features/features.service";\n`
    );
  }

  // add to constructor
  s = s.replace(
    /constructor\(\s*private readonly prisma: PrismaService\s*\)\s*\{\}/m,
    "constructor(private readonly prisma: PrismaService, private readonly features: FeaturesService) {}"
  );
}

// append detail endpoint if missing
if (!s.includes("@Get(\":id\")")) {
  const insertBefore = /@Patch\(":id\/status"\)/m;
  s = s.replace(insertBefore, `@Get(":id")\n  async detail(@Param("id") id: string) {\n    const t = await this.prisma.tenant.findUnique({\n      where: { id },\n      include: {\n        plan: true,\n        overrides: true,\n        memberships: { where: { status: "ACTIVE" }, select: { id: true } },\n      },\n    });\n    if (!t) throw new NotFoundException("Tenant not found");\n\n    const fx = await this.features.getTenantEffectiveFeatures(t.id);\n\n    return {\n      id: t.id,\n      name: t.name,\n      slug: t.slug,\n      status: t.status,\n      planTier: t.plan.tier,\n      seatsLimit: t.seatsLimit,\n      seatsUsed: t.memberships.length,\n      createdAt: t.createdAt,\n      updatedAt: t.updatedAt,\n      features: fx,\n    };\n  }\n\n  @Patch(":id/status")`);
}

fs.writeFileSync(p, s);
console.log("✅ Updated AdminTenantsController with GET /admin/tenants/:id");
NODE

# Update AdminModule to include FeaturesService + AdminAuditController
cat > apps/api/src/admin/admin.module.ts <<'TS'
import { Module } from "@nestjs/common";
import { AdminTenantsController } from "./admin-tenants.controller";
import { AdminAuditController } from "./admin-audit.controller";
import { FeaturesService } from "../features/features.service";

@Module({
  controllers: [AdminTenantsController, AdminAuditController],
  providers: [FeaturesService],
})
export class AdminModule {}
TS

echo "✅ API: features helper + tenant detail + audit list endpoints added."

# -------------------------
# WEB: API client additions
# -------------------------
cat > apps/web-superadmin/lib/api.ts <<'TS'
export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") || "http://localhost:3000";

export type TenantStatus = "TRIAL" | "ACTIVE" | "PAST_DUE" | "SUSPENDED" | "CANCELLED";

export type TenantListItem = {
  id: string;
  name: string;
  slug: string;
  status: TenantStatus;
  planTier: string;
  seatsLimit: number;
  seatsUsed: number;
  createdAt: string;
  updatedAt: string;
};

export type TenantListResponse = {
  page: number;
  pageSize: number;
  total: number;
  items: TenantListItem[];
};

export type TenantDetailResponse = TenantListItem & {
  features: {
    planFeatures: any;
    overrideFeatures: any;
    effectiveFeatures: any;
  };
};

export type AuditItem = {
  id: string;
  createdAt: string;
  tenant: { id: string; name: string; slug: string } | null;
  actorType: "USER" | "SYSTEM";
  actor: { id: string; email: string | null; displayName: string | null } | null;
  action: string;
  entityType: string;
  entityId: string | null;
  success: boolean;
  metadata: any;
};

export type AuditListResponse = {
  page: number;
  pageSize: number;
  total: number;
  items: AuditItem[];
};

async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
  });

  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`API ${res.status}: ${txt || res.statusText}`);
  }
  return (await res.json()) as T;
}

export async function listTenants(params: {
  q?: string;
  status?: string;
  page?: number;
  pageSize?: number;
}) {
  const sp = new URLSearchParams();
  if (params.q) sp.set("q", params.q);
  if (params.status) sp.set("status", params.status);
  sp.set("page", String(params.page ?? 1));
  sp.set("pageSize", String(params.pageSize ?? 20));
  const qs = sp.toString();
  return apiFetch<TenantListResponse>(`/admin/tenants${qs ? `?${qs}` : ""}`);
}

export async function getTenant(tenantId: string) {
  return apiFetch<TenantDetailResponse>(`/admin/tenants/${tenantId}`);
}

export async function setTenantStatus(tenantId: string, status: TenantStatus) {
  return apiFetch<{ ok: true; tenantId: string; status: TenantStatus }>(
    `/admin/tenants/${tenantId}/status`,
    {
      method: "PATCH",
      body: JSON.stringify({ status }),
    }
  );
}

export async function listAudit(params: {
  q?: string;
  tenantId?: string;
  action?: string;
  page?: number;
  pageSize?: number;
}) {
  const sp = new URLSearchParams();
  if (params.q) sp.set("q", params.q);
  if (params.tenantId) sp.set("tenantId", params.tenantId);
  if (params.action) sp.set("action", params.action);
  sp.set("page", String(params.page ?? 1));
  sp.set("pageSize", String(params.pageSize ?? 20));
  const qs = sp.toString();
  return apiFetch<AuditListResponse>(`/admin/audit${qs ? `?${qs}` : ""}`);
}
TS

# -------------------------
# WEB: Tenant detail page
# -------------------------
mkdir -p "apps/web-superadmin/app/(sa)/churches/[id]"

cat > "apps/web-superadmin/app/(sa)/churches/[id]/page.tsx" <<'TSX'
"use client";

import * as React from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Progress,
  SectionHeader,
  ChevronLeft,
  Ban,
  PlayCircle
} from "@noxera/ui";
import { getTenant, setTenantStatus, listAudit, type TenantStatus } from "@/lib/api";

function badgeVariant(s: TenantStatus) {
  switch (s) {
    case "ACTIVE": return "success";
    case "TRIAL": return "default";
    case "PAST_DUE": return "warning";
    case "SUSPENDED":
    case "CANCELLED": return "danger";
    default: return "outline";
  }
}

function flatten(obj: any, prefix = ""): Array<{ key: string; value: any }> {
  const out: Array<{ key: string; value: any }> = [];
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return [{ key: prefix || "value", value: obj }];
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) out.push(...flatten(v, key));
    else out.push({ key, value: v });
  }
  return out;
}

export default function TenantDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id as string;
  const router = useRouter();

  const [loading, setLoading] = React.useState(true);
  const [saving, setSaving] = React.useState(false);
  const [err, setErr] = React.useState<string | null>(null);
  const [tenant, setTenant] = React.useState<any>(null);
  const [audit, setAudit] = React.useState<any>(null);

  async function load() {
    setLoading(true);
    setErr(null);
    try {
      const t = await getTenant(id);
      setTenant(t);

      const a = await listAudit({ tenantId: id, page: 1, pageSize: 10 });
      setAudit(a);
    } catch (e: any) {
      setErr(e?.message || "Failed to load tenant");
    } finally {
      setLoading(false);
    }
  }

  React.useEffect(() => { load(); /* eslint-disable-next-line */ }, [id]);

  async function changeStatus(next: TenantStatus) {
    if (!tenant) return;
    setSaving(true);
    const prev = tenant.status;
    setTenant({ ...tenant, status: next });
    try {
      await setTenantStatus(id, next);
      const a = await listAudit({ tenantId: id, page: 1, pageSize: 10 });
      setAudit(a);
    } catch (e: any) {
      setTenant({ ...tenant, status: prev });
      alert(e?.message || "Failed to update status");
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return <div className="text-sm text-muted-foreground">Loading…</div>;
  }

  if (err) {
    return (
      <div className="space-y-3">
        <div className="text-sm font-semibold">Couldn’t load tenant</div>
        <div className="text-sm text-muted-foreground">{err}</div>
        <div className="flex gap-2">
          <Button onClick={load}>Retry</Button>
          <Button variant="outline" onClick={() => router.push("/churches")}>Back</Button>
        </div>
      </div>
    );
  }

  const features = flatten(tenant?.features?.effectiveFeatures ?? {});
  const seatsUsed = tenant.seatsUsed ?? 0;
  const seatsLimit = tenant.seatsLimit ?? 0;

  return (
    <div className="space-y-5">
      <SectionHeader
        title={tenant.name}
        subtitle={`${tenant.id} • ${tenant.slug}`}
        right={
          <div className="flex items-center gap-2">
            <Link href="/churches">
              <Button variant="outline">
                <ChevronLeft className="h-4 w-4" />
                Back
              </Button>
            </Link>
            <Badge variant={badgeVariant(tenant.status)}>{tenant.status}</Badge>
          </div>
        }
      />

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>Plan</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            <div className="text-sm font-semibold">{tenant.planTier}</div>
            <div className="text-xs text-muted-foreground">Seats</div>
            <div className="text-sm">{seatsUsed}/{seatsLimit}</div>
            <Progress value={seatsUsed} max={seatsLimit} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Status</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <div className="text-sm">Current: <span className="font-semibold">{tenant.status}</span></div>
            <div className="flex flex-wrap gap-2">
              {tenant.status === "SUSPENDED" ? (
                <Button disabled={saving} variant="secondary" onClick={() => changeStatus("ACTIVE")}>
                  <PlayCircle className="h-4 w-4" />
                  Resume
                </Button>
              ) : (
                <Button disabled={saving} variant="destructive" onClick={() => changeStatus("SUSPENDED")}>
                  <Ban className="h-4 w-4" />
                  Suspend
                </Button>
              )}
              <Button disabled={saving} variant="outline" onClick={() => changeStatus("PAST_DUE")}>Mark Past Due</Button>
              <Button disabled={saving} variant="outline" onClick={() => changeStatus("CANCELLED")}>Cancel</Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Feature Gates</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            <div className="text-xs text-muted-foreground">Effective (Plan + Overrides)</div>
            <div className="grid gap-2">
              {features.slice(0, 10).map((f) => (
                <div key={f.key} className="flex items-center justify-between gap-3 rounded-xl border border-border/70 bg-muted/20 px-3 py-2 text-xs">
                  <div className="font-semibold">{f.key}</div>
                  <div>
                    {typeof f.value === "boolean" ? (
                      <Badge variant={f.value ? "success" : "outline"}>{f.value ? "Enabled" : "Off"}</Badge>
                    ) : (
                      <span className="text-muted-foreground">{String(f.value)}</span>
                    )}
                  </div>
                </div>
              ))}
              {features.length > 10 ? (
                <div className="text-xs text-muted-foreground">+ {features.length - 10} more… (we’ll expand in Sprint 1)</div>
              ) : null}
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent Audit Logs</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {audit?.items?.length ? (
            audit.items.map((a: any) => (
              <div key={a.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-border/70 bg-muted/20 px-3 py-2 text-xs">
                <div className="font-semibold">{a.action}</div>
                <div className="text-muted-foreground">{new Date(a.createdAt).toLocaleString()}</div>
              </div>
            ))
          ) : (
            <div className="text-sm text-muted-foreground">No audit entries yet.</div>
          )}
          <div className="pt-2">
            <Link href={`/audit-logs?tenantId=${encodeURIComponent(id)}`}>
              <Button variant="outline">View all audit logs</Button>
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
TSX

# -------------------------
# WEB: Audit logs page
# -------------------------
mkdir -p "apps/web-superadmin/app/(sa)/audit-logs"

cat > "apps/web-superadmin/app/(sa)/audit-logs/page.tsx" <<'TSX'
"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  SectionHeader
} from "@noxera/ui";
import { listAudit } from "@/lib/api";

export default function AuditLogsPage() {
  const sp = useSearchParams();
  const tenantIdFromUrl = sp.get("tenantId") || "";

  const [q, setQ] = React.useState("");
  const [tenantId, setTenantId] = React.useState(tenantIdFromUrl);
  const [action, setAction] = React.useState("");
  const [page, setPage] = React.useState(1);
  const pageSize = 20;

  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);
  const [data, setData] = React.useState<any>({ total: 0, items: [] });

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const res = await listAudit({
        q: q.trim() || undefined,
        tenantId: tenantId.trim() || undefined,
        action: action.trim() || undefined,
        page,
        pageSize,
      });
      setData(res);
    } catch (e: any) {
      setError(e?.message || "Failed to load audit logs");
    } finally {
      setLoading(false);
    }
  }

  React.useEffect(() => { load(); /* eslint-disable-next-line */ }, [page]);

  const totalPages = Math.max(1, Math.ceil((data.total || 0) / pageSize));

  return (
    <div className="space-y-5">
      <SectionHeader
        title="Audit Logs"
        subtitle="Search and review administrative actions (Sprint 0)."
        right={
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => { setQ(""); setTenantId(""); setAction(""); setPage(1); setTimeout(load, 0); }}>
              Reset
            </Button>
            <Button onClick={() => { setPage(1); load(); }}>Apply</Button>
          </div>
        }
      />

      <Card>
        <CardHeader><CardTitle>Filters</CardTitle></CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="space-y-2">
              <Label>Search</Label>
              <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Action / entityType / entityId…" />
            </div>
            <div className="space-y-2">
              <Label>Tenant ID</Label>
              <Input value={tenantId} onChange={(e) => setTenantId(e.target.value)} placeholder="tnt_001…" />
            </div>
            <div className="space-y-2">
              <Label>Action</Label>
              <Input value={action} onChange={(e) => setAction(e.target.value)} placeholder="TENANT_STATUS_CHANGED…" />
            </div>
          </div>

          {error ? (
            <div className="mt-4 rounded-xl border border-border/70 bg-rose-500/10 p-3 text-sm">
              <div className="font-semibold">Couldn’t load audit logs</div>
              <div className="mt-1 text-muted-foreground">{error}</div>
              <div className="mt-3">
                <Button onClick={load}>Retry</Button>
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>

      <div className="overflow-hidden rounded-2xl border border-border/70 bg-card/70 backdrop-blur">
        <div className="grid grid-cols-[1.2fr_1.2fr_1fr_1fr] bg-muted/30 px-4 py-3 text-xs font-extrabold uppercase tracking-wide">
          <div>Time</div>
          <div>Tenant</div>
          <div>Action</div>
          <div>Entity</div>
        </div>

        {loading ? (
          <div className="p-6 text-sm text-muted-foreground">Loading…</div>
        ) : data.items.length === 0 ? (
          <div className="p-6 text-sm text-muted-foreground">No audit logs found.</div>
        ) : (
          data.items.map((a: any) => (
            <div key={a.id} className="grid grid-cols-[1.2fr_1.2fr_1fr_1fr] items-center border-t border-border/70 px-4 py-3 text-sm">
              <div className="text-xs text-muted-foreground">{new Date(a.createdAt).toLocaleString()}</div>
              <div className="text-xs">
                {a.tenant ? (
                  <>
                    <div className="font-semibold">{a.tenant.name}</div>
                    <div className="text-muted-foreground">{a.tenant.id}</div>
                  </>
                ) : (
                  <span className="text-muted-foreground">—</span>
                )}
              </div>
              <div className="font-semibold">{a.action}</div>
              <div className="text-xs text-muted-foreground">
                {a.entityType}{a.entityId ? ` • ${a.entityId}` : ""}
              </div>
            </div>
          ))
        )}
      </div>

      <div className="flex items-center justify-between">
        <div className="text-xs text-muted-foreground">
          Page {page} of {totalPages} • Total {data.total || 0}
        </div>
        <div className="flex gap-2">
          <Button variant="outline" disabled={page <= 1 || loading} onClick={() => setPage((p) => Math.max(1, p - 1))}>
            Prev
          </Button>
          <Button variant="outline" disabled={page >= totalPages || loading} onClick={() => setPage((p) => Math.min(totalPages, p + 1))}>
            Next
          </Button>
        </div>
      </div>
    </div>
  );
}
TSX

# -------------------------
# WEB: Link "View audit logs" button + add nav item
# -------------------------
node - <<'NODE'
const fs = require("fs");
const p = "apps/web-superadmin/components/shell/SuperAdminShell.tsx";
let s = fs.readFileSync(p, "utf8");

// Add ScrollText icon to imports if not present
if (!s.includes("ScrollText")) {
  s = s.replace(
    /import\s+\{\s*([\s\S]*?)\s*\}\s+from\s+"@noxera\/ui";/m,
    (m, inner) => `import {\n${inner.trim()},\n  ScrollText\n} from "@noxera/ui";`
  );
}

// Add nav item (Audit Logs) if not present
if (!s.includes('label: "Audit Logs"')) {
  s = s.replace(
    /const nav: NavItem\[] = \[\n/m,
    'const nav: NavItem[] = [\n  { label: "Audit Logs", href: "/audit-logs", icon: ScrollText },\n'
  );
}

// Replace the button to link to /audit-logs (keep Button component)
s = s.replace(
  /<Button variant="outline" className="w-full">[\s\S]*?<\/Button>/m,
  `<Link href="/audit-logs" className="block">\n            <Button variant="outline" className="w-full">\n              View audit logs\n            </Button>\n          </Link>`
);

fs.writeFileSync(p, s);
console.log("✅ Updated SuperAdminShell: nav + audit logs link");
NODE

echo "🎉 Step 4.5 patch applied."
echo "Next:"
echo "  1) Restart API: pnpm -C apps/api start:dev"
echo "  2) Restart web: pnpm -C apps/web-superadmin dev"
echo "  3) Visit: /churches/tnt_001 and /audit-logs"
