set -euo pipefail

API="apps/api"
mkdir -p "$API/prisma"

# -----------------------------
# 1) schema.prisma (MySQL)
# -----------------------------
cat > "$API/prisma/schema.prisma" <<'PRISMA'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "mysql"
  url      = env("DATABASE_URL")
}

enum TenantStatus {
  TRIAL
  ACTIVE
  PAST_DUE
  SUSPENDED
  CANCELLED
}

enum UserStatus {
  ACTIVE
  SUSPENDED
  DISABLED
}

enum MembershipStatus {
  ACTIVE
  INVITED
  SUSPENDED
  REMOVED
}

enum RoleScope {
  GLOBAL
  TENANT
}

enum AuditActorType {
  USER
  SYSTEM
}

model Plan {
  id                String   @id @default(cuid())
  tier              String   @unique  // "TRIAL" | "BASIC" | "PRO" | "ENTERPRISE" (keep flexible)
  name              String
  monthlyPriceCents Int      @default(0)
  seatsIncluded     Int      @default(3)
  features          Json?
  createdAt         DateTime @default(now())
  updatedAt         DateTime @updatedAt

  tenants Tenant[]
}

model Tenant {
  id         String       @id @default(cuid())
  name       String
  slug       String       @unique
  status     TenantStatus @default(TRIAL)
  planId     String
  seatsLimit Int          @default(3)

  trialEndsAt    DateTime?
  suspendedAt    DateTime?
  cancelledAt    DateTime?

  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  plan        Plan         @relation(fields: [planId], references: [id])
  memberships Membership[]
  auditLogs   AuditLog[]
  overrides   TenantOverride?

  @@index([status])
  @@index([planId])
  @@index([createdAt])
}

model TenantOverride {
  id        String   @id @default(cuid())
  tenantId  String   @unique
  overrides Json?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  tenant Tenant @relation(fields: [tenantId], references: [id])
}

model User {
  id          String     @id @default(cuid())
  email       String?    @unique
  phone       String?    @unique
  displayName String?
  firebaseUid String?    @unique
  status      UserStatus @default(ACTIVE)

  lastLoginAt DateTime?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt

  memberships Membership[]
  globalRoles UserRole[]
  auditLogs   AuditLog[] @relation("AuditActor")

  @@index([status])
  @@index([createdAt])
}

model Membership {
  id        String           @id @default(cuid())
  tenantId  String
  userId    String
  status    MembershipStatus @default(ACTIVE)
  createdAt DateTime         @default(now())
  updatedAt DateTime         @updatedAt

  tenant Tenant @relation(fields: [tenantId], references: [id])
  user   User   @relation(fields: [userId], references: [id])

  roles MembershipRole[]

  @@unique([tenantId, userId])
  @@index([tenantId, status])
  @@index([userId])
}

model Role {
  id          String    @id @default(cuid())
  key         String    @unique // e.g. SUPER_ADMIN, TENANT_ADMIN
  name        String
  description String?
  scope       RoleScope @default(TENANT)

  // TENANT-scoped roles can optionally be created per-tenant later
  tenantId String?

  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  rolePermissions RolePermission[]
  membershipRoles MembershipRole[]
  userRoles       UserRole[]

  @@index([scope])
  @@index([tenantId])
}

model Permission {
  id          String @id @default(cuid())
  key         String @unique // e.g. ADMIN_TENANT_READ
  description String?

  rolePermissions RolePermission[]
}

model RolePermission {
  roleId       String
  permissionId String

  role       Role       @relation(fields: [roleId], references: [id], onDelete: Cascade)
  permission Permission @relation(fields: [permissionId], references: [id], onDelete: Cascade)

  @@id([roleId, permissionId])
}

model UserRole {
  userId String
  roleId String

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)
  role Role @relation(fields: [roleId], references: [id], onDelete: Cascade)

  @@id([userId, roleId])
}

model MembershipRole {
  membershipId String
  roleId       String

  membership Membership @relation(fields: [membershipId], references: [id], onDelete: Cascade)
  role       Role       @relation(fields: [roleId], references: [id], onDelete: Cascade)

  @@id([membershipId, roleId])
}

model AuditLog {
  id        String         @id @default(cuid())
  tenantId  String?
  actorType AuditActorType @default(USER)
  actorUserId String?
  action    String         // "TENANT_STATUS_CHANGED", etc.
  entityType String        // "Tenant", "User", ...
  entityId   String?
  success   Boolean        @default(true)

  ip        String?
  userAgent String?
  metadata  Json?

  createdAt DateTime @default(now())

  tenant Tenant? @relation(fields: [tenantId], references: [id])
  actor  User?   @relation("AuditActor", fields: [actorUserId], references: [id])

  @@index([tenantId, createdAt])
  @@index([actorUserId, createdAt])
  @@index([entityType, entityId])
}
PRISMA

# -----------------------------
# 2) seed.ts
# -----------------------------
cat > "$API/prisma/seed.ts" <<'TS'
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  // Plans (Sprint 0: simple + JSON features for gating)
  const plans = [
    {
      tier: "TRIAL",
      name: "Trial",
      monthlyPriceCents: 0,
      seatsIncluded: 3,
      features: { churches: true, members: true, finance: false, checkin: false }
    },
    {
      tier: "BASIC",
      name: "Basic",
      monthlyPriceCents: 2500,
      seatsIncluded: 5,
      features: { churches: true, members: true, finance: true, checkin: false }
    },
    {
      tier: "PRO",
      name: "Pro",
      monthlyPriceCents: 6500,
      seatsIncluded: 15,
      features: { churches: true, members: true, finance: true, checkin: true }
    },
    {
      tier: "ENTERPRISE",
      name: "Enterprise",
      monthlyPriceCents: 15000,
      seatsIncluded: 50,
      features: { churches: true, members: true, finance: true, checkin: true, sso: true }
    }
  ];

  for (const p of plans) {
    await prisma.plan.upsert({
      where: { tier: p.tier },
      update: {
        name: p.name,
        monthlyPriceCents: p.monthlyPriceCents,
        seatsIncluded: p.seatsIncluded,
        features: p.features as any
      },
      create: {
        tier: p.tier,
        name: p.name,
        monthlyPriceCents: p.monthlyPriceCents,
        seatsIncluded: p.seatsIncluded,
        features: p.features as any
      }
    });
  }

  const trialPlan = await prisma.plan.findUnique({ where: { tier: "TRIAL" } });
  const basicPlan = await prisma.plan.findUnique({ where: { tier: "BASIC" } });
  const proPlan = await prisma.plan.findUnique({ where: { tier: "PRO" } });

  if (!trialPlan || !basicPlan || !proPlan) throw new Error("Plans not created");

  // Permissions
  const perms = [
    "ADMIN_TENANT_READ",
    "ADMIN_TENANT_WRITE",
    "ADMIN_TENANT_SUSPEND",
    "AUDIT_READ",
    "TENANT_MEMBER_READ",
    "TENANT_MEMBER_WRITE"
  ];

  for (const key of perms) {
    await prisma.permission.upsert({
      where: { key },
      update: {},
      create: { key }
    });
  }

  const permIds = new Map<string, string>();
  for (const p of await prisma.permission.findMany()) permIds.set(p.key, p.id);

  // Roles
  const superAdminRole = await prisma.role.upsert({
    where: { key: "SUPER_ADMIN" },
    update: { name: "Super Admin", scope: "GLOBAL" },
    create: { key: "SUPER_ADMIN", name: "Super Admin", scope: "GLOBAL" }
  });

  const tenantAdminRole = await prisma.role.upsert({
    where: { key: "TENANT_ADMIN" },
    update: { name: "Tenant Admin", scope: "TENANT" },
    create: { key: "TENANT_ADMIN", name: "Tenant Admin", scope: "TENANT" }
  });

  // Role permissions
  const superAdminPerms = ["ADMIN_TENANT_READ", "ADMIN_TENANT_WRITE", "ADMIN_TENANT_SUSPEND", "AUDIT_READ"];
  const tenantAdminPerms = ["TENANT_MEMBER_READ", "TENANT_MEMBER_WRITE"];

  async function syncRolePerms(roleId: string, keys: string[]) {
    const pairs = keys.map((k) => ({ roleId, permissionId: permIds.get(k)! }));
    // ensure exist (idempotent)
    for (const pair of pairs) {
      await prisma.rolePermission.upsert({
        where: { roleId_permissionId: pair },
        update: {},
        create: pair
      });
    }
  }

  await syncRolePerms(superAdminRole.id, superAdminPerms);
  await syncRolePerms(tenantAdminRole.id, tenantAdminPerms);

  // Super admin user (dev)
  const admin = await prisma.user.upsert({
    where: { email: "admin@noxera.dev" },
    update: { displayName: "Noxera Admin" },
    create: {
      email: "admin@noxera.dev",
      displayName: "Noxera Admin",
      firebaseUid: "dev_admin_uid"
    }
  });

  await prisma.userRole.upsert({
    where: { userId_roleId: { userId: admin.id, roleId: superAdminRole.id } },
    update: {},
    create: { userId: admin.id, roleId: superAdminRole.id }
  });

  // Tenants (match your UI mock feel)
  const tenants = [
    { id: "tnt_001", name: "Grace Chapel International", slug: "grace-chapel", status: "ACTIVE", planId: proPlan.id, seatsLimit: 15 },
    { id: "tnt_002", name: "House of Prayer Ministries", slug: "house-of-prayer", status: "PAST_DUE", planId: basicPlan.id, seatsLimit: 5 },
    { id: "tnt_003", name: "New Dawn Assembly", slug: "new-dawn", status: "TRIAL", planId: trialPlan.id, seatsLimit: 3 },
    { id: "tnt_004", name: "Living Waters Church", slug: "living-waters", status: "SUSPENDED", planId: proPlan.id, seatsLimit: 15 }
  ] as const;

  for (const t of tenants) {
    await prisma.tenant.upsert({
      where: { id: t.id },
      update: {
        name: t.name,
        slug: t.slug,
        status: t.status as any,
        planId: t.planId,
        seatsLimit: t.seatsLimit
      },
      create: {
        id: t.id,
        name: t.name,
        slug: t.slug,
        status: t.status as any,
        planId: t.planId,
        seatsLimit: t.seatsLimit,
        trialEndsAt: t.status === "TRIAL" ? new Date(Date.now() + 1000 * 60 * 60 * 24 * 14) : null,
        suspendedAt: t.status === "SUSPENDED" ? new Date() : null
      }
    });
  }

  // Add 1 tenant admin per tenant (so seatsUsed can be computed later)
  for (const t of tenants) {
    const u = await prisma.user.upsert({
      where: { email: `admin@${t.slug}.dev` },
      update: {},
      create: {
        email: `admin@${t.slug}.dev`,
        displayName: `${t.name} Admin`,
        firebaseUid: `dev_${t.id}_admin_uid`
      }
    });

    const m = await prisma.membership.upsert({
      where: { tenantId_userId: { tenantId: t.id, userId: u.id } },
      update: { status: "ACTIVE" as any },
      create: { tenantId: t.id, userId: u.id, status: "ACTIVE" as any }
    });

    await prisma.membershipRole.upsert({
      where: { membershipId_roleId: { membershipId: m.id, roleId: tenantAdminRole.id } },
      update: {},
      create: { membershipId: m.id, roleId: tenantAdminRole.id }
    });
  }

  // Audit seed entry
  await prisma.auditLog.create({
    data: {
      actorType: "SYSTEM",
      action: "SEED_COMPLETED",
      entityType: "System",
      success: true,
      metadata: { note: "Initial Sprint 0 seed" }
    }
  });

  console.log("✅ Seed complete:");
  console.log("  Super Admin email: admin@noxera.dev (firebaseUid: dev_admin_uid)");
  console.log("  Tenants: tnt_001..tnt_004");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
TS

# -----------------------------
# 3) Enable prisma seed via package.json
# -----------------------------
node - <<'NODE'
const fs = require("fs");
const p = "apps/api/package.json";
const j = JSON.parse(fs.readFileSync(p, "utf8"));

j.scripts ||= {};
j.scripts["db:generate"] ||= "prisma generate";
j.scripts["db:migrate"] ||= "prisma migrate dev";
j.scripts["db:seed"] ||= "prisma db seed";

j.prisma ||= {};
j.prisma.seed = "ts-node --transpile-only prisma/seed.ts";

fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
console.log("✅ Updated apps/api/package.json (prisma.seed + db scripts)");
NODE

echo "🎉 Step 3 files written:"
echo "  - apps/api/prisma/schema.prisma"
echo "  - apps/api/prisma/seed.ts"
echo "  - apps/api/package.json updated"
