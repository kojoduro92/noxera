set -euo pipefail

mkdir -p apps packages tools

# -------------------------
# Root workspace config
# -------------------------
cat > pnpm-workspace.yaml <<'YAML'
packages:
  - "apps/*"
  - "packages/*"
YAML

cat > package.json <<'JSON'
{
  "name": "noxera",
  "private": true,
  "scripts": {
    "dev": "turbo run dev --parallel",
    "build": "turbo run build",
    "lint": "turbo run lint",
    "db:up": "docker compose up -d",
    "db:down": "docker compose down"
  },
  "devDependencies": {
    "turbo": "^2.0.0",
    "prettier": "^3.3.0",
    "typescript": "^5.7.0"
  }
}
JSON

cat > turbo.json <<'JSON'
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "dev": { "cache": false, "persistent": true },
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**", ".next/**"] },
    "lint": { "dependsOn": ["^lint"] }
  }
}
JSON

cat > .gitignore <<'TXT'
node_modules
.DS_Store
.env
.env.*
!.env.example
dist
.next
out
coverage
TXT

cat > .env.example <<'ENV'
# Local DB
DATABASE_URL=postgresql://noxera:noxera@localhost:5432/noxera?schema=public

# Redis (later: queues, jobs, rate limits)
REDIS_URL=redis://localhost:6379

# Auth (Sprint 0): Firebase Admin (set later)
FIREBASE_PROJECT_ID=
FIREBASE_CLIENT_EMAIL=
FIREBASE_PRIVATE_KEY=

# Dev-only shortcut (optional)
DEV_MASTER_TOKEN=dev-master-token
ENV

# -------------------------
# Local infrastructure (Postgres + Redis)
# -------------------------
cat > docker-compose.yml <<'YAML'
services:
  postgres:
    image: postgres:16
    container_name: noxera_postgres
    environment:
      POSTGRES_USER: noxera
      POSTGRES_PASSWORD: noxera
      POSTGRES_DB: noxera
    ports:
      - "5432:5432"
    volumes:
      - noxera_pg:/var/lib/postgresql/data

  redis:
    image: redis:7
    container_name: noxera_redis
    ports:
      - "6379:6379"

volumes:
  noxera_pg:
YAML

# -------------------------
# Shared package: permissions + constants (DRY)
# -------------------------
mkdir -p packages/shared/src/rbac

cat > packages/shared/package.json <<'JSON'
{
  "name": "@noxera/shared",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "main": "./src/index.ts"
}
JSON

cat > packages/shared/src/rbac/permissions.ts <<'TS'
/**
 * Permission keys follow the blueprint:
 * module.action.scope (e.g., members.view.any)
 */
export const PERMISSIONS = {
  // Members
  MEMBERS_VIEW_ANY: "members.view.any",
  MEMBERS_EDIT_ANY: "members.edit.any",
  MEMBERS_EXPORT_ANY: "members.export.any",

  // Attendance
  ATTENDANCE_CHECKIN: "attendance.checkin",
  ATTENDANCE_REPORTS_VIEW: "attendance.reports.view",

  // Giving
  GIVING_CREATE: "giving.create",
  GIVING_APPROVE: "giving.approve",
  GIVING_EXPORT: "giving.export",

  // Website
  WEBSITE_PAGES_EDIT: "website.pages.edit",
  WEBSITE_PUBLISH: "website.publish",
  WEBSITE_DOMAINS_MANAGE: "website.domains.manage",

  // Super Admin
  ADMIN_IMPERSONATE: "admin.impersonate"
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];
TS

cat > packages/shared/src/index.ts <<'TS'
export * from "./rbac/permissions";
TS

# -------------------------
# UI package placeholder (we’ll wire shadcn + theming next)
# -------------------------
mkdir -p packages/ui/src

cat > packages/ui/package.json <<'JSON'
{
  "name": "@noxera/ui",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "main": "./src/index.ts"
}
JSON

cat > packages/ui/src/index.ts <<'TS'
export {};
TS

echo "✅ Sprint 0 repo skeleton created."
echo "Next: pnpm install, docker compose up, then scaffold apps."
