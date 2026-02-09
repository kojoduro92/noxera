set -euo pipefail

APP="apps/web-superadmin"
SHELL_DIR="$APP/components/shell"

mkdir -p "$SHELL_DIR"

# 1) Ensure SuperAdminShell exists (overwrite with a known-good file)
cat > "$SHELL_DIR/SuperAdminShell.tsx" <<'TSX'
import Link from "next/link";
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

# 2) GUARANTEE ./ui exists (both .ts and .tsx for any resolver edge case)
cat > "$SHELL_DIR/ui.tsx" <<'TSX'
export { default } from "./SuperAdminShell";
TSX

cat > "$SHELL_DIR/ui.ts" <<'TS'
export { default } from "./SuperAdminShell";
TS

# 3) Create a stable index.ts (some codebases import the folder)
cat > "$SHELL_DIR/index.ts" <<'TS'
export { default as SuperAdminShell } from "./SuperAdminShell";
export { default } from "./SuperAdminShell";
TS

# 4) Rewrite any imports inside shell folder that reference "./ui" -> "./SuperAdminShell"
perl -pi -e 's/from\s+["'\'']\.\/ui["'\'']/from "\.\/SuperAdminShell"/g' "$SHELL_DIR"/*.ts "$SHELL_DIR"/*.tsx 2>/dev/null || true

# 5) Rewrite any app-wide imports that reference the directory "@/components/shell"
#    to the explicit file "@/components/shell/SuperAdminShell"
grep -RIl --exclude-dir=node_modules --exclude-dir=.next 'from "@/components/shell"' "$APP" \
  | while read -r f; do
      perl -pi -e 's/from\s+"@\/components\/shell"/from "@\/components\/shell\/SuperAdminShell"/g' "$f"
    done || true

# 6) Clear Next cache (Turbopack is aggressive)
rm -rf "$APP/.next"

echo "✅ Fixed: components/shell ./ui resolved + imports stabilized + cache cleared."
