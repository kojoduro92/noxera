set -euo pipefail

echo "🎨 Upgrading UI tokens + components + Super Admin screens..."

# ------------------------------------------------------------
# 1) UI TOKENS: colorful Material-ish palette (CSS variables)
# ------------------------------------------------------------
cat > packages/ui/styles/tokens.css <<'CSS'
:root {
  /* Core */
  --background: 240 20% 99%;
  --foreground: 240 10% 10%;

  --card: 0 0% 100%;
  --card-foreground: 240 10% 10%;

  --muted: 220 14% 96%;
  --muted-foreground: 240 4% 42%;

  --border: 220 13% 91%;
  --input: 220 13% 91%;

  /* Brand (violet/indigo) */
  --primary: 252 83% 58%;
  --primary-foreground: 0 0% 100%;

  --secondary: 220 14% 96%;
  --secondary-foreground: 240 10% 12%;

  --accent: 252 83% 96%;
  --accent-foreground: 252 50% 20%;

  --destructive: 0 84% 60%;
  --destructive-foreground: 0 0% 100%;

  --ring: 252 83% 58%;
  --radius: 1.25rem;
}

.dark {
  --background: 240 10% 6%;
  --foreground: 0 0% 98%;

  --card: 240 9% 9%;
  --card-foreground: 0 0% 98%;

  --muted: 240 6% 14%;
  --muted-foreground: 240 5% 70%;

  --border: 240 6% 16%;
  --input: 240 6% 16%;

  --primary: 252 93% 70%;
  --primary-foreground: 240 10% 10%;

  --secondary: 240 6% 14%;
  --secondary-foreground: 0 0% 98%;

  --accent: 252 28% 14%;
  --accent-foreground: 0 0% 98%;

  --destructive: 0 63% 35%;
  --destructive-foreground: 0 0% 98%;

  --ring: 252 93% 70%;
}
CSS

# ------------------------------------------------------------
# 2) UI BASE: background glow + better defaults
# ------------------------------------------------------------
cat > packages/ui/styles/base.css <<'CSS'
* { border-color: hsl(var(--border)); }

html, body { height: 100%; }

body {
  background: hsl(var(--background));
  color: hsl(var(--foreground));
}

/* Subtle “material” background glow */
body::before {
  content: "";
  position: fixed;
  inset: -20%;
  z-index: -1;
  pointer-events: none;
  background:
    radial-gradient(900px 450px at 15% 10%, hsl(var(--primary) / 0.14), transparent 60%),
    radial-gradient(700px 420px at 85% 20%, hsl(200 95% 55% / 0.10), transparent 60%),
    radial-gradient(900px 600px at 60% 100%, hsl(140 70% 45% / 0.07), transparent 60%);
  filter: blur(2px);
}

.dark body::before {
  background:
    radial-gradient(900px 450px at 15% 10%, hsl(var(--primary) / 0.18), transparent 60%),
    radial-gradient(700px 420px at 85% 20%, hsl(200 95% 55% / 0.12), transparent 60%),
    radial-gradient(900px 600px at 60% 100%, hsl(140 70% 45% / 0.10), transparent 60%);
  filter: blur(4px);
}
CSS

# ------------------------------------------------------------
# 3) UI COMPONENT POLISH: Card/Button/Badge + Progress
# ------------------------------------------------------------
cat > packages/ui/src/components/card.tsx <<'TSX'
import * as React from "react";
import { cn } from "../lib/cn";

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-2xl border border-border/70 bg-card text-card-foreground",
        "shadow-[0_10px_30px_-18px_rgba(0,0,0,0.35)]",
        "backdrop-blur supports-[backdrop-filter]:bg-card/90",
        className
      )}
      {...props}
    />
  );
}

export function CardHeader({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("p-5 pb-3", className)} {...props} />;
}

export function CardTitle({ className, ...props }: React.HTMLAttributes<HTMLHeadingElement>) {
  return <h3 className={cn("text-base font-semibold tracking-tight", className)} {...props} />;
}

export function CardDescription({ className, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn("text-sm text-muted-foreground", className)} {...props} />;
}

export function CardContent({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("p-5 pt-0", className)} {...props} />;
}
TSX

cat > packages/ui/src/components/button.tsx <<'TSX'
import * as React from "react";
import { cn } from "../lib/cn";

export type ButtonVariant = "default" | "secondary" | "outline" | "ghost" | "destructive";
export type ButtonSize = "sm" | "md" | "lg" | "icon";

const base =
  "inline-flex items-center justify-center gap-2 rounded-xl text-sm font-semibold transition-all " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 " +
  "disabled:pointer-events-none disabled:opacity-50 ring-offset-background " +
  "active:translate-y-[1px]";

const variants: Record<ButtonVariant, string> = {
  default:
    "bg-primary text-primary-foreground shadow-[0_12px_24px_-16px_hsl(var(--primary)/0.9)] hover:opacity-95",
  secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
  outline:
    "border border-border/70 bg-background/60 backdrop-blur hover:bg-accent hover:text-accent-foreground",
  ghost: "hover:bg-accent hover:text-accent-foreground",
  destructive:
    "bg-destructive text-destructive-foreground shadow-[0_12px_24px_-16px_hsl(var(--destructive)/0.8)] hover:opacity-95"
};

const sizes: Record<ButtonSize, string> = {
  sm: "h-9 px-3",
  md: "h-10 px-4",
  lg: "h-11 px-6 text-base",
  icon: "h-10 w-10"
};

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

export function Button({ className, variant = "default", size = "md", ...props }: ButtonProps) {
  return <button className={cn(base, variants[variant], sizes[size], className)} {...props} />;
}
TSX

cat > packages/ui/src/components/badge.tsx <<'TSX'
import * as React from "react";
import { cn } from "../lib/cn";

export type BadgeVariant = "default" | "success" | "warning" | "danger" | "outline";

const variants: Record<BadgeVariant, string> = {
  default: "bg-muted text-foreground",
  success: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border border-emerald-500/20",
  warning: "bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/20",
  danger: "bg-rose-500/15 text-rose-800 dark:text-rose-300 border border-rose-500/20",
  outline: "border border-border/70 text-foreground bg-background/40"
};

export function Badge({
  className,
  variant = "default",
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { variant?: BadgeVariant }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold",
        variants[variant],
        className
      )}
      {...props}
    />
  );
}
TSX

cat > packages/ui/src/components/progress.tsx <<'TSX'
import * as React from "react";
import { cn } from "../lib/cn";

export function Progress({
  value,
  max = 100,
  className
}: {
  value: number;
  max?: number;
  className?: string;
}) {
  const pct = max <= 0 ? 0 : Math.max(0, Math.min(100, (value / max) * 100));
  return (
    <div className={cn("h-2 w-full rounded-full bg-muted/70 overflow-hidden", className)}>
      <div
        className="h-full rounded-full bg-primary transition-all"
        style={{ width: `${pct}%` }}
      />
    </div>
  );
}
TSX

# Ensure index exports progress + lucide re-export stays
if ! grep -q 'export \* from "\.\/components\/progress"' packages/ui/src/index.ts; then
  echo '' >> packages/ui/src/index.ts
  echo 'export * from "./components/progress";' >> packages/ui/src/index.ts
fi

# ------------------------------------------------------------
# 4) SUPER ADMIN SHELL: responsive drawer + nicer nav
# ------------------------------------------------------------
cat > apps/web-superadmin/components/shell/SuperAdminShell.tsx <<'TSX'
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import * as React from "react";
import {
  LayoutDashboard,
  Building2,
  Shield,
  LifeBuoy,
  CreditCard,
  Flag,
  Settings,
  Menu,
  X,
  ThemeToggle,
  Button,
  cn
} from "@noxera/ui";

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

function SideNav({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname() || "/";
  return (
    <div className="h-full rounded-2xl border border-border/70 bg-card/80 backdrop-blur p-3 shadow-[0_18px_45px_-30px_rgba(0,0,0,0.45)]">
      <div className="flex items-center justify-between gap-3 px-2 py-2">
        <div className="flex items-center gap-2">
          <div className="relative grid h-9 w-9 place-items-center rounded-xl text-primary-foreground overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-br from-[hsl(var(--primary))] to-[hsl(200_95%_55%)]" />
            <div className="relative font-black">N</div>
          </div>
          <div className="leading-tight">
            <div className="text-sm font-extrabold tracking-tight">Noxera</div>
            <div className="text-xs text-muted-foreground">Super Admin</div>
          </div>
        </div>
        <ThemeToggle />
      </div>

      <nav className="mt-3 space-y-1">
        {nav.map((item) => {
          const Icon = item.icon;
          const active = pathname === item.href || (item.href !== "/" && pathname.startsWith(item.href));
          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onNavigate}
              className={cn(
                "group flex items-center gap-2 rounded-xl px-3 py-2 text-sm transition-all",
                active
                  ? "bg-gradient-to-r from-[hsl(var(--primary)/0.16)] to-transparent text-foreground"
                  : "text-foreground/80 hover:bg-accent/70 hover:text-accent-foreground"
              )}
            >
              <Icon className={cn("h-4 w-4 transition-transform", active ? "" : "group-hover:scale-110")} />
              <span className="font-semibold">{item.label}</span>
              {active ? (
                <span className="ml-auto h-2 w-2 rounded-full bg-[hsl(var(--primary))]" />
              ) : null}
            </Link>
          );
        })}
      </nav>

      <div className="mt-4 rounded-2xl border border-border/70 bg-muted/30 p-3">
        <div className="text-xs font-semibold">Sprint 0</div>
        <div className="mt-1 text-xs text-muted-foreground">
          UI is mock-safe. Next: real endpoints + audit logs.
        </div>
        <div className="mt-3">
          <Button variant="outline" className="w-full">
            View audit logs
          </Button>
        </div>
      </div>
    </div>
  );
}

export default function SuperAdminShell({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = React.useState(false);

  return (
    <div className="min-h-screen">
      {/* Mobile top bar */}
      <div className="sticky top-0 z-40 border-b border-border/70 bg-background/70 backdrop-blur md:hidden">
        <div className="mx-auto flex max-w-[1400px] items-center justify-between gap-3 p-3">
          <button
            className="inline-flex h-10 w-10 items-center justify-center rounded-xl border border-border/70 bg-background/60"
            onClick={() => setOpen(true)}
            aria-label="Open menu"
          >
            <Menu className="h-5 w-5" />
          </button>

          <div className="font-extrabold tracking-tight">Noxera</div>

          <div className="w-10" />
        </div>
      </div>

      {/* Mobile drawer */}
      {open ? (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-black/40" onClick={() => setOpen(false)} />
          <div className="absolute left-0 top-0 h-full w-[86%] max-w-[320px] p-3">
            <div className="mb-2 flex items-center justify-between">
              <div className="text-sm font-bold">Menu</div>
              <button
                className="inline-flex h-10 w-10 items-center justify-center rounded-xl border border-border/70 bg-background/60"
                onClick={() => setOpen(false)}
                aria-label="Close menu"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
            <SideNav onNavigate={() => setOpen(false)} />
          </div>
        </div>
      ) : null}

      <div className="mx-auto grid max-w-[1400px] grid-cols-1 gap-6 p-4 md:grid-cols-[280px_1fr] md:p-6">
        <aside className="hidden md:block">
          <SideNav />
        </aside>

        <main className="rounded-3xl border border-border/70 bg-card/80 backdrop-blur p-5 shadow-[0_18px_55px_-40px_rgba(0,0,0,0.55)]">
          {children}
        </main>
      </div>
    </div>
  );
}
TSX

# Route-group layout stays simple
cat > apps/web-superadmin/app/(sa)/layout.tsx <<'TSX'
import SuperAdminShell from "@/components/shell/SuperAdminShell";

export default function SuperAdminLayout({ children }: { children: React.ReactNode }) {
  return <SuperAdminShell>{children}</SuperAdminShell>;
}
TSX

# ------------------------------------------------------------
# 5) CHURCH DIRECTORY: KPI cards + progress + mobile card list
# ------------------------------------------------------------
cat > "apps/web-superadmin/app/(sa)/churches/page.tsx" <<'TSX'
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

export default function ChurchesPage() {
  const [rows, setRows] = React.useState<TenantRow[]>(mockTenants);
  const [q, setQ] = React.useState("");
  const [status, setStatus] = React.useState<StatusFilter>("All");

  const filtered = React.useMemo(() => {
    const query = q.trim().toLowerCase();
    return rows.filter((r) => {
      const okQ = !query || r.name.toLowerCase().includes(query) || r.id.toLowerCase().includes(query);
      const okS = status === "All" || r.status === status;
      return okQ && okS;
    });
  }, [rows, q, status]);

  const stats = React.useMemo(() => {
    const total = rows.length;
    const active = rows.filter((r) => r.status === "Active").length;
    const pastDue = rows.filter((r) => r.status === "Past Due").length;
    const suspended = rows.filter((r) => r.status === "Suspended").length;
    return { total, active, pastDue, suspended };
  }, [rows]);

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
            <Button>
              <Sparkles className="h-4 w-4" />
              Create tenant
            </Button>
          </div>
        }
      />

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Total churches" value={`${stats.total}`} />
        <StatCard label="Active" value={`${stats.active}`} hint="Healthy tenants" />
        <StatCard label="Past Due" value={`${stats.pastDue}`} hint="Needs billing follow-up" />
        <StatCard label="Suspended" value={`${stats.suspended}`} hint="Access blocked" />
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
                <Input id="q" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name or tenant ID…" className="pl-9" />
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
              <div className="flex h-10 items-center rounded-xl border border-border/70 bg-muted/30 px-3 text-sm">
                {filtered.length} church{filtered.length === 1 ? "" : "es"}
              </div>
            </div>
          </div>
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

        {filtered.length === 0 ? (
          <div className="p-6 text-sm text-muted-foreground">No churches match your filters.</div>
        ) : (
          filtered.map((t) => (
            <div
              key={t.id}
              className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] items-center border-t border-border/70 px-4 py-4 transition hover:bg-accent/40"
            >
              <div>
                <div className="font-bold">{t.name}</div>
                <div className="text-xs text-muted-foreground">{t.id} • last activity {formatRelative(t.lastActivityISO)}</div>
              </div>

              <div className="text-sm font-semibold">{t.plan}</div>

              <div>
                <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
              </div>

              <div className="space-y-1">
                <div className="text-sm">{t.seatsUsed}/{t.seatsLimit} seats</div>
                <Progress value={t.seatsUsed} max={t.seatsLimit} />
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

      {/* Mobile cards */}
      <div className="md:hidden space-y-3">
        {filtered.map((t) => (
          <Card key={t.id} className="overflow-hidden">
            <CardContent className="pt-4 space-y-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-base font-extrabold">{t.name}</div>
                  <div className="text-xs text-muted-foreground">{t.id} • {formatRelative(t.lastActivityISO)}</div>
                </div>
                <Badge variant={statusBadgeVariant(t.status)}>{t.status}</Badge>
              </div>

              <div className="flex items-center justify-between text-sm">
                <div className="font-semibold">{t.plan}</div>
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

                {t.status === "Suspended" ? (
                  <Button variant="secondary" className="flex-1" onClick={() => toggleSuspend(t.id)}>
                    <PlayCircle className="h-4 w-4" />
                    Resume
                  </Button>
                ) : (
                  <Button variant="destructive" className="flex-1" onClick={() => toggleSuspend(t.id)}>
                    <Ban className="h-4 w-4" />
                    Suspend
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
TSX

# Clear cache (helps Tailwind/Turbopack pick up style changes fast)
rm -rf apps/web-superadmin/.next || true
rm -rf apps/web-church/.next || true
rm -rf apps/web-public/.next || true

echo "✅ Material UI upgrade applied."
