set -euo pipefail

APP="apps/web-superadmin"
APP_DIR="$APP/app"

if [ ! -d "$APP_DIR" ]; then
  echo "❌ Expected $APP_DIR to exist, but it doesn't."
  exit 1
fi

echo "✅ Restoring Super Admin UI in: $APP_DIR"

# -----------------------------
# 1) Middleware (FIXED): inject x-pathname into REQUEST headers (not response)
# -----------------------------
cat > "$APP/middleware.ts" <<'TS'
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

export function middleware(req: NextRequest) {
  const requestHeaders = new Headers(req.headers);
  requestHeaders.set("x-pathname", req.nextUrl.pathname);

  return NextResponse.next({
    request: { headers: requestHeaders }
  });
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"]
};
TS

# -----------------------------
# 2) Super Admin Shell (components live at app root, so @/ works)
# -----------------------------
mkdir -p "$APP/components/shell"

cat > "$APP/components/shell/SuperAdminShell.tsx" <<'TSX'
import Link from "next/link";
import {
  LayoutDashboard,
  Building2,
  Shield,
  LifeBuoy,
  CreditCard,
  Flag,
  Settings
} from "lucide-react";
import { cn, ThemeToggle, Button } from "@noxera/ui";

type NavItem = {
  label: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
};

const nav: NavItem[] = [
  { label: "Overview", href: "/", icon: LayoutDashboard },
  { label: "Churches", href: "/churches", icon: Building2 },
  { label: "Billing", href: "/billing", icon: CreditCard },
  { label: "Support", href: "/support", icon: LifeBuoy },
  { label: "Security", href: "/security", icon: Shield },
  { label: "Feature Flags", href: "/flags", icon: Flag },
  { label: "System", href: "/system", icon: Settings }
];

export default function SuperAdminShell({
  children,
  activePath
}: {
  children: React.ReactNode;
  activePath: string;
}) {
  return (
    <div className="min-h-screen bg-background">
      <div className="mx-auto grid max-w-[1400px] grid-cols-1 gap-6 p-4 md:grid-cols-[260px_1fr] md:p-6">
        <aside className="rounded-2xl border border-border bg-card p-3">
          <div className="flex items-center justify-between gap-3 px-2 py-2">
            <div className="flex items-center gap-2">
              <div className="grid h-9 w-9 place-items-center rounded-xl bg-primary text-primary-foreground">
                N
              </div>
              <div className="leading-tight">
                <div className="text-sm font-semibold">Noxera</div>
                <div className="text-xs text-muted-foreground">Super Admin</div>
              </div>
            </div>
            <ThemeToggle />
          </div>

          <nav className="mt-3 space-y-1">
            {nav.map((item) => {
              const Icon = item.icon;
              const active =
                activePath === item.href ||
                (item.href !== "/" && activePath.startsWith(item.href));

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "flex items-center gap-2 rounded-xl px-3 py-2 text-sm transition-colors",
                    active
                      ? "bg-accent text-accent-foreground"
                      : "text-foreground/80 hover:bg-accent hover:text-accent-foreground"
                  )}
                >
                  <Icon className="h-4 w-4" />
                  {item.label}
                </Link>
              );
            })}
          </nav>

          <div className="mt-4 rounded-xl border border-border bg-muted/30 p-3">
            <div className="text-xs font-medium">Sprint 0</div>
            <div className="mt-1 text-xs text-muted-foreground">
              Directory UI is mock-safe. Next we wire GET /admin/tenants and status actions + audit logs.
            </div>
            <div className="mt-3">
              <Button variant="outline" className="w-full">
                View audit logs
              </Button>
            </div>
          </div>
        </aside>

        <main className="rounded-2xl border border-border bg-card p-5">{children}</main>
      </div>
    </div>
  );
}
TSX

# -----------------------------
# 3) Super Admin route-group layout
# -----------------------------
mkdir -p "$APP_DIR/(sa)"

cat > "$APP_DIR/(sa)/layout.tsx" <<'TSX'
import { headers } from "next/headers";
import SuperAdminShell from "@/components/shell/SuperAdminShell";

export default function SuperAdminLayout({ children }: { children: React.ReactNode }) {
  const h = headers();
  const path = h.get("x-pathname") ?? "/";

  return <SuperAdminShell activePath={path}>{children}</SuperAdminShell>;
}
TSX

# -----------------------------
# 4) Mock tenants data
# -----------------------------
mkdir -p "$APP/lib/mock"

cat > "$APP/lib/mock/tenants.ts" <<'TS'
export type TenantStatus = "Trial" | "Active" | "Past Due" | "Suspended" | "Cancelled";

export type TenantRow = {
  id: string;
  name: string;
  plan: "Trial" | "Basic" | "Pro" | "Enterprise";
  status: TenantStatus;
  seatsUsed: number;
  seatsLimit: number;
  lastActivityISO: string;
};

export const mockTenants: TenantRow[] = [
  {
    id: "tnt_001",
    name: "Grace Chapel International",
    plan: "Pro",
    status: "Active",
    seatsUsed: 12,
    seatsLimit: 15,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 18).toISOString()
  },
  {
    id: "tnt_002",
    name: "House of Prayer Ministries",
    plan: "Basic",
    status: "Past Due",
    seatsUsed: 4,
    seatsLimit: 5,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 60 * 26).toISOString()
  },
  {
    id: "tnt_003",
    name: "New Dawn Assembly",
    plan: "Trial",
    status: "Trial",
    seatsUsed: 2,
    seatsLimit: 3,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 60 * 6).toISOString()
  },
  {
    id: "tnt_004",
    name: "Living Waters Church",
    plan: "Pro",
    status: "Suspended",
    seatsUsed: 9,
    seatsLimit: 15,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 60 * 72).toISOString()
  }
];
TS

# -----------------------------
# 5) Churches routes + full UI
# -----------------------------
mkdir -p "$APP_DIR/(sa)/churches/[tenantId]"

cat > "$APP_DIR/(sa)/page.tsx" <<'TSX'
import { redirect } from "next/navigation";

export default function SuperAdminHome() {
  redirect("/churches");
}
TSX

cat > "$APP_DIR/(sa)/churches/page.tsx" <<'TSX'
import ChurchDirectoryClient from "./ui";

export default function ChurchesPage() {
  return <ChurchDirectoryClient />;
}
TSX

cat > "$APP_DIR/(sa)/churches/ui.tsx" <<'TSX'
"use client";

import * as React from "react";
import Link from "next/link";
import { Search, Eye, Ban, PlayCircle } from "lucide-react";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  SectionHeader
} from "@noxera/ui";
import { mockTenants, type TenantRow, type TenantStatus } from "@/lib/mock/tenants";

type StatusFilter = "All" | TenantStatus;

function formatRelative(iso: string) {
  const d = new Date(iso).getTime();
  const diff = Date.now() - d;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 48) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

function statusBadgeVariant(status: TenantStatus) {
  switch (status) {
    case "Active":
      return "success";
    case "Trial":
      return "default";
    case "Past Due":
      return "warning";
    case "Suspended":
    case "Cancelled":
      return "danger";
    default:
      return "outline";
  }
}

export default function ChurchDirectoryClient() {
  const [rows, setRows] = React.useState<TenantRow[]>(mockTenants);
  const [q, setQ] = React.useState("");
  const [status, setStatus] = React.useState<StatusFilter>("All");

  const filtered = React.useMemo(() => {
    const query = q.trim().toLowerCase();
    return rows.filter((r) => {
      const okQ =
        !query ||
        r.name.toLowerCase().includes(query) ||
        r.id.toLowerCase().includes(query);
      const okS = status === "All" || r.status === status;
      return okQ && okS;
    });
  }, [rows, q, status]);

  function toggleSuspend(id: string) {
    setRows((prev) =>
      prev.map((t) => {
        if (t.id !== id) return t;
        if (t.status === "Suspended") return { ...t, status: "Active" };
        return { ...t, status: "Suspended" };
      })
    );
  }

  return (
    <div className="space-y-5">
      <SectionHeader
        title="Church Directory"
        subtitle="Search churches, view status/plan/usage, and suspend/resume access."
        right={
          <div className="flex items-center gap-2">
            <Button variant="outline">Export</Button>
            <Button>Create tenant</Button>
          </div>
        }
      />

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Filters</CardTitle>
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
                  placeholder="Name or tenant ID…"
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
                className="h-10 w-full rounded-xl border border-border bg-background px-3 text-sm"
              >
                <option value="All">All</option>
                <option value="Trial">Trial</option>
                <option value="Active">Active</option>
                <option value="Past Due">Past Due</option>
                <option value="Suspended">Suspended</option>
                <option value="Cancelled">Cancelled</option>
              </select>
            </div>

            <div className="space-y-2">
              <Label>Results</Label>
              <div className="flex h-10 items-center rounded-xl border border-border bg-muted/30 px-3 text-sm">
                {filtered.length} church{filtered.length === 1 ? "" : "es"}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="overflow-hidden rounded-2xl border border-border">
        <div className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] bg-muted/40 px-4 py-3 text-xs font-semibold uppercase tracking-wide">
          <div>Church</div>
          <div>Plan</div>
          <div>Status</div>
          <div>Usage</div>
          <div className="text-right">Actions</div>
        </div>

        {filtered.length === 0 ? (
          <div className="p-6 text-sm text-muted-foreground">
            No churches match your filters.
          </div>
        ) : (
          filtered.map((t) => (
            <div
              key={t.id}
              className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] items-center border-t border-border px-4 py-4"
            >
              <div>
                <div className="font-medium">{t.name}</div>
                <div className="text-xs text-muted-foreground">
                  {t.id} • last activity {formatRelative(t.lastActivityISO)}
                </div>
              </div>

              <div className="text-sm">{t.plan}</div>

              <div>
                <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
              </div>

              <div className="text-sm">
                {t.seatsUsed}/{t.seatsLimit} seats
              </div>

              <div className="flex items-center justify-end gap-2">
                <Link href={`/churches/${t.id}`} className="inline-flex">
                  <Button variant="outline" size="sm">
                    <Eye className="h-4 w-4" />
                    View
                  </Button>
                </Link>

                {t.status === "Suspended" ? (
                  <Button variant="secondary" size="sm" onClick={() => toggleSuspend(t.id)}>
                    <PlayCircle className="h-4 w-4" />
                    Resume
                  </Button>
                ) : (
                  <Button variant="destructive" size="sm" onClick={() => toggleSuspend(t.id)}>
                    <Ban className="h-4 w-4" />
                    Suspend
                  </Button>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
TSX

cat > "$APP_DIR/(sa)/churches/[tenantId]/page.tsx" <<'TSX'
import Link from "next/link";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@noxera/ui";

export default async function TenantView({ params }: { params: Promise<{ tenantId: string }> }) {
  const { tenantId } = await params;

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between gap-4">
        <div>
          <div className="text-sm text-muted-foreground">Tenant</div>
          <h1 className="text-xl font-semibold tracking-tight">{tenantId}</h1>
        </div>
        <Link href="/churches">
          <Button variant="outline">Back to directory</Button>
        </Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Tenant Overview</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          Sprint 0 placeholder. Next we wire:
          <div className="mt-2 space-y-1">
            <div>• GET /admin/tenants/:id</div>
            <div>• PATCH /admin/tenants/:id/status (suspend/resume)</div>
            <div>• Audit logs for sensitive actions</div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
TSX

echo "🎉 Restored full Super Admin Church Directory UI."
