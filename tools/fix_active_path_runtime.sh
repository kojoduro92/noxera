set -euo pipefail

APP="apps/web-superadmin"

# 1) Update SuperAdminShell to use usePathname()
cat > "$APP/components/shell/SuperAdminShell.tsx" <<'TSX'
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Building2,
  Shield,
  LifeBuoy,
  CreditCard,
  Flag,
  Settings,
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

export default function SuperAdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname() || "/";

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
                pathname === item.href || (item.href !== "/" && pathname.startsWith(item.href));

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
              Directory UI is mock-safe. Next we wire real endpoints + audit logs.
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

# 2) Update route-group layout to stop using headers()
mkdir -p "$APP/app/(sa)"
cat > "$APP/app/(sa)/layout.tsx" <<'TSX'
import SuperAdminShell from "@/components/shell/SuperAdminShell";

export default function SuperAdminLayout({ children }: { children: React.ReactNode }) {
  return <SuperAdminShell>{children}</SuperAdminShell>;
}
TSX

# 3) Remove middleware since we no longer need x-pathname (and it was causing warnings)
rm -f "$APP/middleware.ts" || true

# 4) Clear Next cache
rm -rf "$APP/.next"

echo "✅ Fixed: active nav now uses usePathname() (client). Removed headers() + middleware."
