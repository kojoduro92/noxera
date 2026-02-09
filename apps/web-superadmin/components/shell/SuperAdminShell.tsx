"use client";

import Link from "next/link";
import {
usePathname } from "next/navigation";
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
  cn,
  ScrollText
} from "@noxera/ui";

type NavItem = {
  label: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
};

const nav: NavItem[] = [
  { label: "Audit Logs", href: "/audit-logs", icon: ScrollText },
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
              {active ? <span className="ml-auto h-2 w-2 rounded-full bg-[hsl(var(--primary))]" /> : null}
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
          <Link href="/audit-logs" className="block">
            <Button variant="outline" className="w-full">
              View audit logs
            </Button>
          </Link>
        </div>
      </div>
    </div>
  );
}

export default function SuperAdminShell({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = React.useState(false);

  return (
    <div className="min-h-screen">
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
