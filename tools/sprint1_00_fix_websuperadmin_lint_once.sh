#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "✅ Repo root: $ROOT"

# -----------------------------
# 1) shared helper: errMsg()
# -----------------------------
mkdir -p apps/web-superadmin/lib
cat > apps/web-superadmin/lib/errors.ts <<'EOF'
export function errMsg(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (typeof e === "string") return e;
  try {
    return JSON.stringify(e);
  } catch {
    return String(e);
  }
}
EOF

# -----------------------------
# 2) web-superadmin API client (cookies + auto dev-session retry) — NO any
# -----------------------------
cat > apps/web-superadmin/lib/api.ts <<'EOF'
import { errMsg } from "@/lib/errors";

function apiBase(): string {
  const env = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "");
  if (env) return env;

  // Keep host consistent so cookies/CORS behave:
  // - If the browser is on 127.0.0.1:3001, call 127.0.0.1:3000
  // - If the browser is on localhost:3001, call localhost:3000
  if (typeof window !== "undefined") {
    const host = window.location.hostname === "127.0.0.1" ? "127.0.0.1" : "localhost";
    const proto = window.location.protocol || "http:";
    return `${proto}//${host}:3000`;
  }

  return "http://localhost:3000";
}

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
    planFeatures: unknown;
    overrideFeatures: unknown;
    effectiveFeatures: unknown;
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
  metadata: unknown;
};

export type AuditListResponse = {
  page: number;
  pageSize: number;
  total: number;
  items: AuditItem[];
};

let _didAutoDevSession = false;

async function ensureDevSessionOnce(base: string): Promise<void> {
  if (_didAutoDevSession) return;
  _didAutoDevSession = true;

  await fetch(`${base}/auth/session`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ dev: true }),
  });
}

async function apiFetch<T>(path: string, init?: RequestInit, retry = true): Promise<T> {
  const base = apiBase();

  const headers = new Headers(init?.headers);
  if (!headers.has("Content-Type")) headers.set("Content-Type", "application/json");

  const res = await fetch(`${base}${path}`, {
    ...init,
    headers,
    credentials: "include", // ✅ ALWAYS send cookies
  });

  // Auto dev-session on first 401, then retry once.
  if (res.status === 401 && retry) {
    await ensureDevSessionOnce(base);
    return apiFetch<T>(path, init, false);
  }

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

// optional helper if you ever want a safe error string in pages
export function apiErrorMessage(e: unknown): string {
  return errMsg(e);
}
EOF

# -----------------------------
# 3) MetaViewer — NO any
# -----------------------------
mkdir -p apps/web-superadmin/components/common
cat > apps/web-superadmin/components/common/MetaViewer.tsx <<'EOF'
"use client";

import * as React from "react";

function pretty(v: unknown): string {
  if (typeof v === "string") return v;
  try {
    return JSON.stringify(v, null, 2);
  } catch {
    return String(v);
  }
}

export default function MetaViewer(props: { title?: string; value: unknown }) {
  const { title = "Metadata", value } = props;
  const [open, setOpen] = React.useState(false);

  return (
    <div className="rounded-2xl border border-border/70 bg-muted/20 p-3">
      <button
        type="button"
        onClick={() => setOpen((s) => !s)}
        className="flex w-full items-center justify-between gap-3 text-left"
      >
        <div className="text-xs font-semibold">{title}</div>
        <div className="text-xs text-muted-foreground">{open ? "Hide" : "Show"}</div>
      </button>

      {open ? (
        <pre className="mt-3 max-h-80 overflow-auto rounded-xl border border-border/70 bg-background/60 p-3 text-xs">
          {pretty(value)}
        </pre>
      ) : null}
    </div>
  );
}
EOF

# -----------------------------
# 4) /login — NO any
# -----------------------------
mkdir -p apps/web-superadmin/app/login
cat > apps/web-superadmin/app/login/page.tsx <<'EOF'
"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { errMsg } from "@/lib/errors";

const API = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") || "http://localhost:3000";

export default function LoginPage() {
  const router = useRouter();
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function loginDev() {
    setBusy(true);
    setError(null);
    try {
      const r = await fetch(`${API}/auth/session`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ dev: true }),
      });
      if (!r.ok) throw new Error(await r.text());
      router.push("/churches");
    } catch (e: unknown) {
      setError(errMsg(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-md p-6 space-y-4">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">Super Admin Login</h1>
        <p className="text-sm text-muted-foreground">
          Dev mode creates a local session cookie for Sprint 0/1 testing.
        </p>
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-300 bg-rose-500/10 p-3 text-sm">
          {error}
        </div>
      ) : null}

      <button
        disabled={busy}
        onClick={loginDev}
        className="w-full rounded-xl border px-4 py-2 text-sm font-semibold disabled:opacity-50"
      >
        {busy ? "Signing in..." : "Continue (Dev Session)"}
      </button>
    </div>
  );
}
EOF

# -----------------------------
# 5) Create Church client — NO any
# -----------------------------
mkdir -p apps/web-superadmin/app/churches/new
cat > apps/web-superadmin/app/churches/new/ui.tsx <<'EOF'
"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { errMsg } from "@/lib/errors";

const API = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") || "http://localhost:3000";

type CreateTenantResponse = { id: string };

export default function NewChurchClient() {
  const router = useRouter();
  const [name, setName] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [err, setErr] = React.useState<string | null>(null);

  async function devToken(): Promise<string> {
    const r = await fetch(`${API}/auth/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ dev: true }),
    });
    if (!r.ok) throw new Error(await r.text());
    const j = (await r.json()) as { token: string };
    return j.token;
  }

  async function onCreate(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    setBusy(true);
    try {
      const token = await devToken();

      const r = await fetch(`${API}/admin/tenants`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        credentials: "include",
        body: JSON.stringify({ name }),
      });

      if (!r.ok) throw new Error(await r.text());

      const tenant = (await r.json()) as CreateTenantResponse;
      router.push(`/churches/${tenant.id}`);
    } catch (e: unknown) {
      setErr(errMsg(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-xl p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Create Church</h1>
        <p className="text-sm text-muted-foreground">Creates a new tenant (church workspace).</p>
      </div>

      <form onSubmit={onCreate} className="space-y-4">
        <div className="space-y-2">
          <label className="text-sm font-medium">Church name</label>
          <input
            className="w-full rounded-xl border px-3 py-2 bg-transparent"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. New Hope Chapel"
          />
        </div>

        {err ? (
          <div className="rounded-xl border border-rose-300 bg-rose-500/10 p-3 text-sm">
            {err}
          </div>
        ) : null}

        <button
          disabled={busy || !name.trim()}
          className="rounded-xl border px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          {busy ? "Creating..." : "Create"}
        </button>
      </form>
    </div>
  );
}
EOF

# -----------------------------
# 6) (sa)/churches list — NO any
# -----------------------------
mkdir -p "apps/web-superadmin/app/(sa)/churches"
cat > "apps/web-superadmin/app/(sa)/churches/page.tsx" <<'EOF'
"use client";

import * as React from "react";
import Link from "next/link";
import {
  Search,
  Eye,
  Ban,
  PlayCircle,
  Sparkles,
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  SectionHeader,
  Progress
} from "@noxera/ui";
import { errMsg } from "@/lib/errors";
import { listTenants, setTenantStatus, type TenantListItem, type TenantStatus } from "@/lib/api";

type StatusFilter = "ALL" | TenantStatus;

function statusBadgeVariant(status: TenantStatus) {
  switch (status) {
    case "ACTIVE":
      return "success";
    case "TRIAL":
      return "default";
    case "PAST_DUE":
      return "warning";
    case "SUSPENDED":
    case "CANCELLED":
      return "danger";
    default:
      return "outline";
  }
}

function StatCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className="overflow-hidden">
      <div className="h-1 w-full bg-gradient-to-r from-[hsl(var(--primary))] via-[hsl(200_95%_55%)] to-[hsl(140_70%_45%)]" />
      <CardContent className="pt-4">
        <div className="text-xs font-semibold text-muted-foreground">{label}</div>
        <div className="mt-1 text-2xl font-extrabold tracking-tight">{value}</div>
        {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
      </CardContent>
    </Card>
  );
}

function SkeletonRow() {
  return (
    <div className="animate-pulse border-t border-border/70 px-4 py-4">
      <div className="h-4 w-56 rounded bg-muted" />
      <div className="mt-2 h-3 w-72 rounded bg-muted/70" />
    </div>
  );
}

export default function ChurchesPage() {
  const [q, setQ] = React.useState("");
  const [status, setStatus] = React.useState<StatusFilter>("ALL");
  const [page, setPage] = React.useState(1);
  const pageSize = 20;

  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);
  const [data, setData] = React.useState<{ total: number; items: TenantListItem[] }>({ total: 0, items: [] });

  const fetchTenants = React.useCallback(
    async (nextPage: number) => {
      setLoading(true);
      setError(null);
      try {
        const res = await listTenants({
          q: q.trim() || undefined,
          status: status === "ALL" ? undefined : status,
          page: nextPage,
          pageSize,
        });
        setData({ total: res.total, items: res.items });
      } catch (e: unknown) {
        setError(errMsg(e));
      } finally {
        setLoading(false);
      }
    },
    [q, status, pageSize]
  );

  React.useEffect(() => {
    fetchTenants(page);
  }, [page, fetchTenants]);

  const stats = React.useMemo(() => {
    const items = data.items;
    const total = data.total;
    const active = items.filter((r) => r.status === "ACTIVE").length;
    const pastDue = items.filter((r) => r.status === "PAST_DUE").length;
    const suspended = items.filter((r) => r.status === "SUSPENDED").length;
    return { total, active, pastDue, suspended };
  }, [data]);

  async function onApplyFilters() {
    setPage(1);
    await fetchTenants(1);
  }

  async function toggleSuspend(t: TenantListItem) {
    const next: TenantStatus = t.status === "SUSPENDED" ? "ACTIVE" : "SUSPENDED";
    try {
      // optimistic
      setData((prev) => ({
        ...prev,
        items: prev.items.map((x) => (x.id === t.id ? { ...x, status: next } : x)),
      }));
      await setTenantStatus(t.id, next);
    } catch (e: unknown) {
      // revert
      setData((prev) => ({
        ...prev,
        items: prev.items.map((x) => (x.id === t.id ? { ...x, status: t.status } : x)),
      }));
      alert(errMsg(e));
    }
  }

  const totalPages = Math.max(1, Math.ceil(data.total / pageSize));

  return (
    <div className="space-y-5">
      <SectionHeader
        title="Church Directory"
        subtitle="Real-time tenants list (API). Suspend/resume access with audit logging."
        right={
          <div className="flex items-center gap-2">
            <Button variant="outline">Export</Button>
            <Link href="/churches/new">
              <Button>
                <Sparkles className="h-4 w-4" />
                Create tenant
              </Button>
            </Link>
          </div>
        }
      />

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Total churches" value={`${stats.total}`} />
        <StatCard label="Active (this page)" value={`${stats.active}`} />
        <StatCard label="Past Due (this page)" value={`${stats.pastDue}`} />
        <StatCard label="Suspended (this page)" value={`${stats.suspended}`} />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Filters</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="space-y-2">
              <Label htmlFor="q">Search</Label>
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 opacity-60" />
                <Input
                  id="q"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Name, slug, or tenant ID…"
                  className="pl-9"
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="status">Status</Label>
              <select
                id="status"
                value={status}
                onChange={(e) => setStatus(e.target.value as StatusFilter)}
                className="h-10 w-full rounded-xl border border-border/70 bg-background/60 px-3 text-sm backdrop-blur"
              >
                <option value="ALL">All</option>
                <option value="TRIAL">Trial</option>
                <option value="ACTIVE">Active</option>
                <option value="PAST_DUE">Past Due</option>
                <option value="SUSPENDED">Suspended</option>
                <option value="CANCELLED">Cancelled</option>
              </select>
            </div>

            <div className="space-y-2">
              <Label>Actions</Label>
              <div className="flex gap-2">
                <Button variant="outline" className="flex-1" onClick={onApplyFilters}>
                  Apply
                </Button>
                <Button
                  variant="secondary"
                  className="flex-1"
                  onClick={() => {
                    setQ("");
                    setStatus("ALL");
                    setPage(1);
                    setTimeout(() => void fetchTenants(1), 0);
                  }}
                >
                  Reset
                </Button>
              </div>
            </div>
          </div>

          {error ? (
            <div className="mt-4 rounded-xl border border-border/70 bg-rose-500/10 p-3 text-sm">
              <div className="font-semibold">Couldn’t load tenants</div>
              <div className="mt-1 text-muted-foreground">{error}</div>
              <div className="mt-3">
                <Button onClick={() => void fetchTenants(page)}>Retry</Button>
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>

      {/* Desktop table */}
      <div className="hidden md:block overflow-hidden rounded-2xl border border-border/70 bg-card/70 backdrop-blur">
        <div className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] bg-muted/30 px-4 py-3 text-xs font-extrabold uppercase tracking-wide">
          <div>Church</div>
          <div>Plan</div>
          <div>Status</div>
          <div>Usage</div>
          <div className="text-right">Actions</div>
        </div>

        {loading ? (
          <>
            <SkeletonRow />
            <SkeletonRow />
            <SkeletonRow />
          </>
        ) : data.items.length === 0 ? (
          <div className="p-6 text-sm text-muted-foreground">No churches match your filters.</div>
        ) : (
          data.items.map((t) => (
            <div
              key={t.id}
              className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] items-center border-t border-border/70 px-4 py-4 transition hover:bg-accent/40"
            >
              <div>
                <div className="font-bold">{t.name}</div>
                <div className="text-xs text-muted-foreground">
                  {t.id} • {t.slug}
                </div>
              </div>

              <div className="text-sm font-semibold">{t.planTier}</div>

              <div>
                <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
              </div>

              <div className="space-y-1">
                <div className="text-sm">
                  {t.seatsUsed}/{t.seatsLimit} seats
                </div>
                <Progress value={t.seatsUsed} max={t.seatsLimit} />
              </div>

              <div className="flex items-center justify-end gap-2">
                <Link href={`/churches/${t.id}`} className="inline-flex">
                  <Button variant="outline" size="sm">
                    <Eye className="h-4 w-4" />
                    View
                  </Button>
                </Link>

                {t.status === "SUSPENDED" ? (
                  <Button variant="secondary" size="sm" onClick={() => void toggleSuspend(t)}>
                    <PlayCircle className="h-4 w-4" />
                    Resume
                  </Button>
                ) : (
                  <Button variant="destructive" size="sm" onClick={() => void toggleSuspend(t)}>
                    <Ban className="h-4 w-4" />
                    Suspend
                  </Button>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* Mobile cards */}
      <div className="md:hidden space-y-3">
        {loading ? (
          <>
            <Card><CardContent className="pt-4"><div className="h-4 w-40 rounded bg-muted animate-pulse" /></CardContent></Card>
            <Card><CardContent className="pt-4"><div className="h-4 w-52 rounded bg-muted animate-pulse" /></CardContent></Card>
          </>
        ) : data.items.length === 0 ? (
          <Card>
            <CardContent className="pt-4 text-sm text-muted-foreground">
              No churches match your filters.
            </CardContent>
          </Card>
        ) : (
          data.items.map((t) => (
            <Card key={t.id} className="overflow-hidden">
              <CardContent className="pt-4 space-y-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="text-base font-extrabold">{t.name}</div>
                    <div className="text-xs text-muted-foreground">{t.id} • {t.slug}</div>
                  </div>
                  <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
                </div>

                <div className="flex items-center justify-between text-sm">
                  <div className="font-semibold">{t.planTier}</div>
                  <div>{t.seatsUsed}/{t.seatsLimit} seats</div>
                </div>

                <Progress value={t.seatsUsed} max={t.seatsLimit} />

                <div className="flex gap-2">
                  <Link href={`/churches/${t.id}`} className="flex-1">
                    <Button variant="outline" className="w-full">
                      <Eye className="h-4 w-4" />
                      View
                    </Button>
                  </Link>

                  {t.status === "SUSPENDED" ? (
                    <Button variant="secondary" className="flex-1" onClick={() => void toggleSuspend(t)}>
                      <PlayCircle className="h-4 w-4" />
                      Resume
                    </Button>
                  ) : (
                    <Button variant="destructive" className="flex-1" onClick={() => void toggleSuspend(t)}>
                      <Ban className="h-4 w-4" />
                      Suspend
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>

      <div className="flex items-center justify-between">
        <div className="text-xs text-muted-foreground">
          Page {page} of {totalPages} • Total {data.total}
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
EOF

# -----------------------------
# 7) (sa)/churches/[id] — NO any
# -----------------------------
mkdir -p "apps/web-superadmin/app/(sa)/churches/[id]"
cat > "apps/web-superadmin/app/(sa)/churches/[id]/page.tsx" <<'EOF'
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
import { errMsg } from "@/lib/errors";
import { getTenant, setTenantStatus, listAudit, type TenantDetailResponse, type AuditListResponse, type TenantStatus } from "@/lib/api";

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

function isRecord(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function flatten(obj: unknown, prefix = ""): Array<{ key: string; value: unknown }> {
  if (!isRecord(obj)) return [{ key: prefix || "value", value: obj }];

  const out: Array<{ key: string; value: unknown }> = [];
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    const key = prefix ? `${prefix}.${k}` : k;
    if (isRecord(v)) out.push(...flatten(v, key));
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
  const [tenant, setTenant] = React.useState<TenantDetailResponse | null>(null);
  const [audit, setAudit] = React.useState<AuditListResponse | null>(null);

  const load = React.useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      const t = await getTenant(id);
      setTenant(t);

      const a = await listAudit({ tenantId: id, page: 1, pageSize: 10 });
      setAudit(a);
    } catch (e: unknown) {
      setErr(errMsg(e));
    } finally {
      setLoading(false);
    }
  }, [id]);

  React.useEffect(() => {
    void load();
  }, [load]);

  async function changeStatus(next: TenantStatus) {
    if (!tenant) return;
    setSaving(true);
    const prev = tenant.status;
    setTenant({ ...tenant, status: next });
    try {
      await setTenantStatus(id, next);
      const a = await listAudit({ tenantId: id, page: 1, pageSize: 10 });
      setAudit(a);
    } catch (e: unknown) {
      setTenant({ ...tenant, status: prev });
      alert(errMsg(e));
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <div className="text-sm text-muted-foreground">Loading…</div>;

  if (err) {
    return (
      <div className="space-y-3">
        <div className="text-sm font-semibold">Couldn’t load tenant</div>
        <div className="text-sm text-muted-foreground">{err}</div>
        <div className="flex gap-2">
          <Button onClick={() => void load()}>Retry</Button>
          <Button variant="outline" onClick={() => router.push("/churches")}>Back</Button>
        </div>
      </div>
    );
  }

  if (!tenant) return null;

  const features = flatten(tenant.features?.effectiveFeatures ?? {});
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
                <Button disabled={saving} variant="secondary" onClick={() => void changeStatus("ACTIVE")}>
                  <PlayCircle className="h-4 w-4" />
                  Resume
                </Button>
              ) : (
                <Button disabled={saving} variant="destructive" onClick={() => void changeStatus("SUSPENDED")}>
                  <Ban className="h-4 w-4" />
                  Suspend
                </Button>
              )}
              <Button disabled={saving} variant="outline" onClick={() => void changeStatus("PAST_DUE")}>Mark Past Due</Button>
              <Button disabled={saving} variant="outline" onClick={() => void changeStatus("CANCELLED")}>Cancel</Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Feature Gates</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            <div className="text-xs text-muted-foreground">Effective (Plan + Overrides)</div>
            <div className="grid gap-2">
              {features.slice(0, 10).map((f) => (
                <div
                  key={f.key}
                  className="flex items-center justify-between gap-3 rounded-xl border border-border/70 bg-muted/20 px-3 py-2 text-xs"
                >
                  <div className="font-semibold">{f.key}</div>
                  <div className="text-muted-foreground">{String(f.value)}</div>
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
            audit.items.map((a) => (
              <div
                key={a.id}
                className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-border/70 bg-muted/20 px-3 py-2 text-xs"
              >
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
EOF

# -----------------------------
# 8) (sa)/audit-logs — NO any
# -----------------------------
mkdir -p "apps/web-superadmin/app/(sa)/audit-logs"
cat > "apps/web-superadmin/app/(sa)/audit-logs/page.tsx" <<'EOF'
"use client";

import * as React from "react";
import {
  Search,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  SectionHeader,
  Badge
} from "@noxera/ui";
import { useSearchParams } from "next/navigation";
import { errMsg } from "@/lib/errors";
import MetaViewer from "@/components/common/MetaViewer";
import { listAudit, type AuditItem } from "@/lib/api";

export default function AuditLogsPage() {
  const sp = useSearchParams();

  const [q, setQ] = React.useState("");
  const [tenantId, setTenantId] = React.useState(sp.get("tenantId") || "");
  const [action, setAction] = React.useState("");

  const [page, setPage] = React.useState(1);
  const pageSize = 20;

  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);
  const [items, setItems] = React.useState<AuditItem[]>([]);
  const [total, setTotal] = React.useState(0);

  const load = React.useCallback(async (nextPage: number) => {
    setLoading(true);
    setError(null);
    try {
      const res = await listAudit({
        q: q.trim() || undefined,
        tenantId: tenantId.trim() || undefined,
        action: action.trim() || undefined,
        page: nextPage,
        pageSize,
      });
      setItems(res.items);
      setTotal(res.total);
    } catch (e: unknown) {
      setError(errMsg(e));
    } finally {
      setLoading(false);
    }
  }, [q, tenantId, action]);

  React.useEffect(() => {
    void load(page);
  }, [page, load]);

  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  async function onApply() {
    setPage(1);
    await load(1);
  }

  return (
    <div className="space-y-5">
      <SectionHeader
        title="Audit Logs"
        subtitle="Track admin actions (status changes, access control, etc.)."
        right={<Badge variant="outline">Sprint 0</Badge>}
      />

      <Card>
        <CardHeader>
          <CardTitle>Filters</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="space-y-2">
              <Label>Search</Label>
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 opacity-60" />
                <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Action, entity, actor…" className="pl-9" />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Tenant ID</Label>
              <Input value={tenantId} onChange={(e) => setTenantId(e.target.value)} placeholder="e.g. tnt_001" />
            </div>

            <div className="space-y-2">
              <Label>Action</Label>
              <Input value={action} onChange={(e) => setAction(e.target.value)} placeholder='e.g. "TENANT_STATUS_CHANGED"' />
            </div>
          </div>

          <div className="mt-4 flex gap-2">
            <Button variant="outline" onClick={() => void onApply()}>Apply</Button>
            <Button
              variant="secondary"
              onClick={() => {
                setQ("");
                setTenantId("");
                setAction("");
                setPage(1);
                setTimeout(() => void load(1), 0);
              }}
            >
              Reset
            </Button>
          </div>

          {error ? (
            <div className="mt-4 rounded-xl border border-border/70 bg-rose-500/10 p-3 text-sm">
              <div className="font-semibold">Couldn’t load audit logs</div>
              <div className="mt-1 text-muted-foreground">{error}</div>
              <div className="mt-3">
                <Button onClick={() => void load(page)}>Retry</Button>
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>

      <div className="space-y-3">
        {loading ? (
          <Card><CardContent className="pt-4 text-sm text-muted-foreground">Loading…</CardContent></Card>
        ) : items.length === 0 ? (
          <Card><CardContent className="pt-4 text-sm text-muted-foreground">No audit entries match filters.</CardContent></Card>
        ) : (
          items.map((a) => (
            <Card key={a.id} className="overflow-hidden">
              <CardContent className="pt-4 space-y-2">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="text-sm font-extrabold">{a.action}</div>
                  <div className="text-xs text-muted-foreground">{new Date(a.createdAt).toLocaleString()}</div>
                </div>

                <div className="text-xs text-muted-foreground">
                  Tenant: {a.tenant ? `${a.tenant.name} (${a.tenant.id})` : "—"} • Actor: {a.actor?.email || a.actorType}
                </div>

                <div className="flex flex-wrap gap-2 text-xs">
                  <Badge variant="outline">{a.entityType}</Badge>
                  {a.entityId ? <Badge variant="outline">{a.entityId}</Badge> : null}
                  <Badge variant={a.success ? "success" : "danger"}>{a.success ? "Success" : "Failed"}</Badge>
                </div>

                {a.metadata ? <MetaViewer title="Metadata" value={a.metadata} /> : null}
              </CardContent>
            </Card>
          ))
        )}
      </div>

      <div className="flex items-center justify-between">
        <div className="text-xs text-muted-foreground">
          Page {page} of {totalPages} • Total {total}
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
EOF

echo "✅ web-superadmin lint/type-safety patch applied (no explicit any)."
echo "NEXT:"
echo "  pnpm -w -r lint"
echo "  pnpm -w -r --if-present typecheck || true"
echo "  pnpm --filter api dev"
echo "  pnpm --filter web-superadmin dev"
