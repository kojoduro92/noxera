set -euo pipefail

ROOT_DIR="$(pwd)"
echo "📍 Repo: $ROOT_DIR"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
appdir() {
  local APP_ROOT="$1"
  if [ -d "$APP_ROOT/src/app" ]; then
    echo "$APP_ROOT/src/app"
  elif [ -d "$APP_ROOT/app" ]; then
    echo "$APP_ROOT/app"
  else
    echo "ERROR: Could not find app directory in $APP_ROOT (expected src/app or app)" >&2
    exit 1
  fi
}

mkdir -p tools

# ------------------------------------------------------------
# 1) Make @noxera/shared + @noxera/ui proper workspace libs (exports)
# ------------------------------------------------------------
echo "✅ Updating workspace packages (shared/ui)..."

# shared package.json (exports)
cat > packages/shared/package.json <<'JSON'
{
  "name": "@noxera/shared",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts"
  }
}
JSON

# ui package.json (exports + deps)
cat > packages/ui/package.json <<'JSON'
{
  "name": "@noxera/ui",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./styles/*": "./styles/*"
  },
  "dependencies": {
    "clsx": "^2.1.1",
    "tailwind-merge": "^2.5.2",
    "lucide-react": "^0.468.0",
    "next-themes": "^0.4.4"
  }
}
JSON

mkdir -p packages/ui/src/lib packages/ui/src/components packages/ui/src/providers packages/ui/styles

cat > packages/ui/src/lib/cn.ts <<'TS'
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
TS

cat > packages/ui/src/providers/theme-provider.tsx <<'TS'
"use client";

import * as React from "react";
import { ThemeProvider as NextThemesProvider } from "next-themes";

export function ThemeProvider({
  children,
  ...props
}: React.ComponentProps<typeof NextThemesProvider>) {
  return <NextThemesProvider {...props}>{children}</NextThemesProvider>;
}
TS

cat > packages/ui/src/components/button.tsx <<'TS'
import * as React from "react";
import { cn } from "../lib/cn";

export type ButtonVariant = "default" | "secondary" | "outline" | "ghost" | "destructive";
export type ButtonSize = "sm" | "md" | "lg" | "icon";

const base =
  "inline-flex items-center justify-center gap-2 rounded-xl text-sm font-medium transition-colors " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 " +
  "disabled:pointer-events-none disabled:opacity-50 ring-offset-background";

const variants: Record<ButtonVariant, string> = {
  default: "bg-primary text-primary-foreground hover:opacity-90",
  secondary: "bg-secondary text-secondary-foreground hover:opacity-90",
  outline: "border border-border bg-background hover:bg-accent hover:text-accent-foreground",
  ghost: "hover:bg-accent hover:text-accent-foreground",
  destructive: "bg-destructive text-destructive-foreground hover:opacity-90"
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
TS

cat > packages/ui/src/components/badge.tsx <<'TS'
import * as React from "react";
import { cn } from "../lib/cn";

export type BadgeVariant = "default" | "success" | "warning" | "danger" | "outline";

const variants: Record<BadgeVariant, string> = {
  default: "bg-muted text-foreground",
  success: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
  warning: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
  danger: "bg-rose-500/15 text-rose-700 dark:text-rose-300",
  outline: "border border-border text-foreground"
};

export function Badge({
  className,
  variant = "default",
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { variant?: BadgeVariant }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium",
        variants[variant],
        className
      )}
      {...props}
    />
  );
}
TS

cat > packages/ui/src/components/card.tsx <<'TS'
import * as React from "react";
import { cn } from "../lib/cn";

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-2xl border border-border bg-card text-card-foreground shadow-sm",
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
  return <h3 className={cn("text-lg font-semibold leading-none tracking-tight", className)} {...props} />;
}

export function CardDescription({ className, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn("text-sm text-muted-foreground", className)} {...props} />;
}

export function CardContent({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("p-5 pt-0", className)} {...props} />;
}
TS

cat > packages/ui/src/components/input.tsx <<'TS'
import * as React from "react";
import { cn } from "../lib/cn";

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(function Input(
  { className, type, ...props },
  ref
) {
  return (
    <input
      ref={ref}
      type={type}
      className={cn(
        "h-10 w-full rounded-xl border border-border bg-background px-3 text-sm outline-none",
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 ring-offset-background",
        "disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      {...props}
    />
  );
});
TS

cat > packages/ui/src/components/label.tsx <<'TS'
import * as React from "react";
import { cn } from "../lib/cn";

export function Label({ className, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return <label className={cn("text-sm font-medium", className)} {...props} />;
}
TS

cat > packages/ui/src/components/section-header.tsx <<'TS'
import * as React from "react";
import { cn } from "../lib/cn";

export function SectionHeader({
  title,
  subtitle,
  right,
  className
}: {
  title: string;
  subtitle?: string;
  right?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex items-start justify-between gap-4", className)}>
      <div className="space-y-1">
        <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
        {subtitle ? <p className="text-sm text-muted-foreground">{subtitle}</p> : null}
      </div>
      {right ? <div className="shrink-0">{right}</div> : null}
    </div>
  );
}
TS

cat > packages/ui/src/components/theme-toggle.tsx <<'TS'
"use client";

import * as React from "react";
import { useTheme } from "next-themes";
import { Moon, Sun } from "lucide-react";
import { Button } from "./button";

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const isDark = theme === "dark";

  return (
    <Button
      variant="outline"
      size="icon"
      aria-label="Toggle theme"
      onClick={() => setTheme(isDark ? "light" : "dark")}
      title="Toggle theme"
    >
      {isDark ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
    </Button>
  );
}
TS

cat > packages/ui/src/index.ts <<'TS'
export * from "./lib/cn";
export * from "./providers/theme-provider";

export * from "./components/button";
export * from "./components/badge";
export * from "./components/card";
export * from "./components/input";
export * from "./components/label";
export * from "./components/section-header";
export * from "./components/theme-toggle";
TS

# Styles: tokens + base (apps import these)
cat > packages/ui/styles/tokens.css <<'CSS'
:root {
  --background: 0 0% 100%;
  --foreground: 240 10% 3.9%;

  --card: 0 0% 100%;
  --card-foreground: 240 10% 3.9%;

  --muted: 240 4.8% 95.9%;
  --muted-foreground: 240 3.8% 46.1%;

  --border: 240 5.9% 90%;
  --input: 240 5.9% 90%;

  --primary: 240 5.9% 10%;
  --primary-foreground: 0 0% 98%;

  --secondary: 240 4.8% 95.9%;
  --secondary-foreground: 240 5.9% 10%;

  --accent: 240 4.8% 95.9%;
  --accent-foreground: 240 5.9% 10%;

  --destructive: 0 84.2% 60.2%;
  --destructive-foreground: 0 0% 98%;

  --ring: 240 5.9% 10%;

  --radius: 1rem;
}

.dark {
  --background: 240 10% 3.9%;
  --foreground: 0 0% 98%;

  --card: 240 10% 3.9%;
  --card-foreground: 0 0% 98%;

  --muted: 240 3.7% 15.9%;
  --muted-foreground: 240 5% 64.9%;

  --border: 240 3.7% 15.9%;
  --input: 240 3.7% 15.9%;

  --primary: 0 0% 98%;
  --primary-foreground: 240 5.9% 10%;

  --secondary: 240 3.7% 15.9%;
  --secondary-foreground: 0 0% 98%;

  --accent: 240 3.7% 15.9%;
  --accent-foreground: 0 0% 98%;

  --destructive: 0 62.8% 30.6%;
  --destructive-foreground: 0 0% 98%;

  --ring: 240 4.9% 83.9%;
}
CSS

cat > packages/ui/styles/base.css <<'CSS'
* { border-color: hsl(var(--border)); }
html, body { height: 100%; }
body {
  background: hsl(var(--background));
  color: hsl(var(--foreground));
}
CSS

# ------------------------------------------------------------
# 2) Install workspace deps into apps (DRY wiring)
# ------------------------------------------------------------
echo "✅ Adding @noxera/ui + @noxera/shared to Next apps..."
pnpm -C apps/web-church add @noxera/ui @noxera/shared
pnpm -C apps/web-superadmin add @noxera/ui @noxera/shared
pnpm -C apps/web-public add @noxera/ui @noxera/shared

# ------------------------------------------------------------
# 3) Next.js: transpilePackages + externalDir (workspace TS + CSS)
# ------------------------------------------------------------
echo "✅ Patching Next configs (transpilePackages)..."

for APP in web-church web-superadmin web-public; do
  APP_ROOT="apps/$APP"
  cat > "$APP_ROOT/next.config.mjs" <<'MJS'
/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    externalDir: true
  },
  transpilePackages: ["@noxera/ui", "@noxera/shared"]
};

export default nextConfig;
MJS
done

# ------------------------------------------------------------
# 4) Tailwind: include ui package in content scanning
# ------------------------------------------------------------
echo "✅ Patching Tailwind configs..."

patch_tailwind() {
  local APP_ROOT="$1"
  local CFG_TS="$APP_ROOT/tailwind.config.ts"
  local CFG_JS="$APP_ROOT/tailwind.config.js"

  if [ -f "$CFG_TS" ]; then
    cat > "$CFG_TS" <<'TS'
import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: [
    "./app/**/*.{ts,tsx,mdx}",
    "./src/**/*.{ts,tsx,mdx}",
    "../../packages/ui/src/**/*.{ts,tsx}",
    "../../packages/ui/styles/**/*.{css}"
  ],
  theme: {
    extend: {
      borderRadius: {
        xl: "var(--radius)",
        "2xl": "calc(var(--radius) + 0.25rem)"
      },
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        card: "hsl(var(--card))",
        "card-foreground": "hsl(var(--card-foreground))",
        muted: "hsl(var(--muted))",
        "muted-foreground": "hsl(var(--muted-foreground))",
        primary: "hsl(var(--primary))",
        "primary-foreground": "hsl(var(--primary-foreground))",
        secondary: "hsl(var(--secondary))",
        "secondary-foreground": "hsl(var(--secondary-foreground))",
        accent: "hsl(var(--accent))",
        "accent-foreground": "hsl(var(--accent-foreground))",
        destructive: "hsl(var(--destructive))",
        "destructive-foreground": "hsl(var(--destructive-foreground))"
      }
    }
  },
  plugins: []
};

export default config;
TS
  elif [ -f "$CFG_JS" ]; then
    cat > "$CFG_JS" <<'JS'
/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: ["class"],
  content: [
    "./app/**/*.{ts,tsx,mdx}",
    "./src/**/*.{ts,tsx,mdx}",
    "../../packages/ui/src/**/*.{ts,tsx}",
    "../../packages/ui/styles/**/*.{css}"
  ],
  theme: {
    extend: {
      borderRadius: {
        xl: "var(--radius)",
        "2xl": "calc(var(--radius) + 0.25rem)"
      },
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        card: "hsl(var(--card))",
        "card-foreground": "hsl(var(--card-foreground))",
        muted: "hsl(var(--muted))",
        "muted-foreground": "hsl(var(--muted-foreground))",
        primary: "hsl(var(--primary))",
        "primary-foreground": "hsl(var(--primary-foreground))",
        secondary: "hsl(var(--secondary))",
        "secondary-foreground": "hsl(var(--secondary-foreground))",
        accent: "hsl(var(--accent))",
        "accent-foreground": "hsl(var(--accent-foreground))",
        destructive: "hsl(var(--destructive))",
        "destructive-foreground": "hsl(var(--destructive-foreground))"
      }
    }
  },
  plugins: []
};
JS
  else
    echo "WARN: No tailwind.config found in $APP_ROOT"
  fi
}

patch_tailwind "apps/web-church"
patch_tailwind "apps/web-superadmin"
patch_tailwind "apps/web-public"

# ------------------------------------------------------------
# 5) Global CSS: keep Tailwind directives in each app, import UI tokens/base
# ------------------------------------------------------------
echo "✅ Patching globals.css in each app..."

patch_globals() {
  local APP_ROOT="$1"
  local APP_DIR
  APP_DIR="$(appdir "$APP_ROOT")"
  local GLOBALS="$APP_DIR/globals.css"

  mkdir -p "$(dirname "$GLOBALS")"
  cat > "$GLOBALS" <<'CSS'
@tailwind base;
@tailwind components;
@tailwind utilities;

@import "@noxera/ui/styles/tokens.css";
@import "@noxera/ui/styles/base.css";
CSS
}

patch_globals "apps/web-church"
patch_globals "apps/web-superadmin"
patch_globals "apps/web-public"

# ------------------------------------------------------------
# 6) Root layouts: ThemeProvider wired once per app (no errors)
# ------------------------------------------------------------
echo "✅ Wiring ThemeProvider into root layouts..."

patch_root_layout() {
  local APP_ROOT="$1"
  local APP_DIR
  APP_DIR="$(appdir "$APP_ROOT")"
  local LAYOUT="$APP_DIR/layout.tsx"

  cat > "$LAYOUT" <<'TSX'
import type { Metadata } from "next";
import "./globals.css";
import { ThemeProvider } from "@noxera/ui";

export const metadata: Metadata = {
  title: "Noxera",
  description: "Noxera platform"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
TSX
}

patch_root_layout "apps/web-church"
patch_root_layout "apps/web-superadmin"
patch_root_layout "apps/web-public"

# ------------------------------------------------------------
# 7) Shells + navigation (Church Admin + Super Admin)
# ------------------------------------------------------------
echo "✅ Creating shells (sidebar + topbar) for Church Admin + Super Admin..."

make_shell_superadmin() {
  local APP_ROOT="apps/web-superadmin"
  local APP_DIR
  APP_DIR="$(appdir "$APP_ROOT")"
  local SRC_ROOT
  if [ -d "$APP_ROOT/src" ]; then SRC_ROOT="$APP_ROOT/src"; else SRC_ROOT="$APP_ROOT"; fi

  mkdir -p "$SRC_ROOT/components/shell" "$APP_DIR/(sa)"

  cat > "$SRC_ROOT/components/shell/SuperAdminShell.tsx" <<'TSX'
import Link from "next/link";
import { LayoutDashboard, Building2, Shield, LifeBuoy, CreditCard, Flag, Settings } from "lucide-react";
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
              const active = activePath === item.href || (item.href !== "/" && activePath.startsWith(item.href));
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
            <div className="text-xs font-medium">Dev mode</div>
            <div className="mt-1 text-xs text-muted-foreground">
              API wiring comes next. For Sprint 0, UI uses safe mock data.
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

  cat > "$APP_DIR/(sa)/layout.tsx" <<'TSX'
import { headers } from "next/headers";
import SuperAdminShell from "@/components/shell/SuperAdminShell";

export default function SuperAdminLayout({ children }: { children: React.ReactNode }) {
  const h = headers();
  const path = h.get("x-pathname") ?? "/";
  return <SuperAdminShell activePath={path}>{children}</SuperAdminShell>;
}
TSX

  # Middleware to inject pathname header (safe, no runtime errors)
  cat > "$APP_ROOT/middleware.ts" <<'TS'
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

export function middleware(req: NextRequest) {
  const res = NextResponse.next();
  res.headers.set("x-pathname", req.nextUrl.pathname);
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"]
};
TS
}

make_shell_church() {
  local APP_ROOT="apps/web-church"
  local APP_DIR
  APP_DIR="$(appdir "$APP_ROOT")"
  local SRC_ROOT
  if [ -d "$APP_ROOT/src" ]; then SRC_ROOT="$APP_ROOT/src"; else SRC_ROOT="$APP_ROOT"; fi

  mkdir -p "$SRC_ROOT/components/shell" "$APP_DIR/(app)"

  cat > "$SRC_ROOT/components/shell/ChurchAdminShell.tsx" <<'TSX'
import Link from "next/link";
import { LayoutDashboard, Users, Calendar, Banknote, Megaphone, Globe, Settings } from "lucide-react";
import { cn, ThemeToggle } from "@noxera/ui";

type NavItem = {
  label: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
};

const nav: NavItem[] = [
  { label: "Dashboard", href: "/dashboard", icon: LayoutDashboard },
  { label: "Members", href: "/members", icon: Users },
  { label: "Events", href: "/events", icon: Calendar },
  { label: "Giving", href: "/giving", icon: Banknote },
  { label: "Communication", href: "/comms", icon: Megaphone },
  { label: "Website", href: "/website", icon: Globe },
  { label: "Settings", href: "/settings", icon: Settings }
];

export default function ChurchAdminShell({
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
                <div className="text-xs text-muted-foreground">Church Admin</div>
              </div>
            </div>
            <ThemeToggle />
          </div>

          <nav className="mt-3 space-y-1">
            {nav.map((item) => {
              const Icon = item.icon;
              const active = activePath === item.href || activePath.startsWith(item.href + "/");
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
        </aside>

        <main className="rounded-2xl border border-border bg-card p-5">{children}</main>
      </div>
    </div>
  );
}
TSX

  cat > "$APP_DIR/(app)/layout.tsx" <<'TSX'
import { headers } from "next/headers";
import ChurchAdminShell from "@/components/shell/ChurchAdminShell";

export default function ChurchAdminLayout({ children }: { children: React.ReactNode }) {
  const h = headers();
  const path = h.get("x-pathname") ?? "/";
  return <ChurchAdminShell activePath={path}>{children}</ChurchAdminShell>;
}
TSX

  # reuse middleware if app doesn't already have it
  if [ ! -f "$APP_ROOT/middleware.ts" ]; then
    cat > "$APP_ROOT/middleware.ts" <<'TS'
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

export function middleware(req: NextRequest) {
  const res = NextResponse.next();
  res.headers.set("x-pathname", req.nextUrl.pathname);
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"]
};
TS
  fi
}

make_shell_superadmin
make_shell_church

# ------------------------------------------------------------
# 8) Super Admin: Church Directory screen + tenant view + suspend/resume (mock-safe)
# ------------------------------------------------------------
echo "✅ Creating Super Admin Church Directory (Sprint 0)..."

SA_ROOT="apps/web-superadmin"
SA_APP_DIR="$(appdir "$SA_ROOT")"
SA_SRC_ROOT="$SA_ROOT"
if [ -d "$SA_ROOT/src" ]; then SA_SRC_ROOT="$SA_ROOT/src"; fi

mkdir -p "$SA_SRC_ROOT/lib/mock" "$SA_APP_DIR/(sa)/churches" "$SA_APP_DIR/(sa)/churches/[tenantId]"

cat > "$SA_SRC_ROOT/lib/mock/tenants.ts" <<'TS'
export type TenantStatus = "Trial" | "Active" | "Past Due" | "Suspended" | "Cancelled";

export type TenantRow = {
  id: string;
  name: string;
  plan: "Trial" | "Basic" | "Pro" | "Enterprise";
  status: TenantStatus;
  seatsUsed: number;
  seatsLimit: number;
  lastActivityISO: string; // ISO string
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

cat > "$SA_APP_DIR/(sa)/page.tsx" <<'TSX'
import { redirect } from "next/navigation";

export default function SuperAdminHome() {
  redirect("/churches");
}
TSX

cat > "$SA_APP_DIR/(sa)/churches/page.tsx" <<'TSX'
import ChurchDirectoryClient from "./ui";

export default function ChurchesPage() {
  return <ChurchDirectoryClient />;
}
TSX

cat > "$SA_APP_DIR/(sa)/churches/ui.tsx" <<'TSX'
"use client";

import * as React from "react";
import Link from "next/link";
import { Search, Eye, Ban, PlayCircle } from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, Label, SectionHeader } from "@noxera/ui";
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
      const okQ = !query || r.name.toLowerCase().includes(query) || r.id.toLowerCase().includes(query);
      const okS = status === "All" || r.status === status;
      return okQ && okS;
    });
  }, [rows, q, status]);

  function toggleSuspend(id: string) {
    setRows((prev) =>
      prev.map((t) => {
        if (t.id !== id) return t;
        if (t.status === "Suspended") {
          return { ...t, status: "Active" };
        }
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
              <div className="h-10 rounded-xl border border-border bg-muted/30 px-3 text-sm flex items-center">
                {filtered.length} church{filtered.length === 1 ? "" : "es"}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="rounded-2xl border border-border overflow-hidden">
        <div className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] gap-0 bg-muted/40 px-4 py-3 text-xs font-semibold uppercase tracking-wide">
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
              className="grid grid-cols-[2fr_1fr_1fr_1fr_1fr] items-center gap-0 border-t border-border px-4 py-4"
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
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => toggleSuspend(t.id)}
                    title="Resume tenant"
                  >
                    <PlayCircle className="h-4 w-4" />
                    Resume
                  </Button>
                ) : (
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => toggleSuspend(t.id)}
                    title="Suspend tenant"
                  >
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

cat > "$SA_APP_DIR/(sa)/churches/[tenantId]/page.tsx" <<'TSX'
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
          Sprint 0 placeholder. Next we will wire this to:
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

# ------------------------------------------------------------
# 9) Church Admin starter pages (safe, minimal)
# ------------------------------------------------------------
echo "✅ Adding Church Admin starter routes..."

CA_ROOT="apps/web-church"
CA_APP_DIR="$(appdir "$CA_ROOT")"

mkdir -p "$CA_APP_DIR/(app)/dashboard"

cat > "$CA_APP_DIR/page.tsx" <<'TSX'
import { redirect } from "next/navigation";

export default function Home() {
  redirect("/dashboard");
}
TSX

cat > "$CA_APP_DIR/(app)/dashboard/page.tsx" <<'TSX'
import { Card, CardContent, CardHeader, CardTitle } from "@noxera/ui";

export default function DashboardPage() {
  return (
    <div className="space-y-5">
      <h1 className="text-xl font-semibold tracking-tight">Dashboard</h1>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Sprint 0</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          Shell + theming is ready. Next we wire auth (Firebase session endpoint), tenant selection, RBAC, and audit logs.
        </CardContent>
      </Card>
    </div>
  );
}
TSX

# ------------------------------------------------------------
# 10) Install root deps (lockfile sync)
# ------------------------------------------------------------
echo "✅ Installing workspace deps..."
pnpm -w install

echo "🎉 Patch complete."
echo ""
echo "Next commands:"
echo "  pnpm -C apps/web-superadmin dev"
echo "  pnpm -C apps/web-church dev"
echo "  pnpm -C apps/web-public dev"
