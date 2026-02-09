import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { PrismaMariaDb } from "@prisma/adapter-mariadb";

function buildMariaDbAdapter(databaseUrl) {
  // Always parse into discrete fields (works for mysql:// and avoids adapter url quirks)
  const u = new URL(databaseUrl);

  const host = u.hostname || "127.0.0.1";
  const port = Number(u.port || "3306");
  const user = decodeURIComponent(u.username || "");
  const password = decodeURIComponent(u.password || "");
  const database = (u.pathname || "").replace(/^\//, "");
  const connectionLimit = Number(process.env.DB_POOL_SIZE || "5");

  if (!user) throw new Error("DATABASE_URL missing username");
  if (!database) throw new Error("DATABASE_URL missing database name");

  return new PrismaMariaDb({ host, port, user, password, database, connectionLimit });
}

const databaseUrl = (process.env.DATABASE_URL || "").trim();
if (!databaseUrl) throw new Error("Missing DATABASE_URL");

const prisma = new PrismaClient({ adapter: buildMariaDbAdapter(databaseUrl) });

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
        features: p.features
      },
      create: {
        tier: p.tier,
        name: p.name,
        monthlyPriceCents: p.monthlyPriceCents,
        seatsIncluded: p.seatsIncluded,
        features: p.features
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
    await prisma.permission.upsert({ where: { key }, update: {}, create: { key } });
  }

  const permIds = new Map();
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

  async function syncRolePerms(roleId, keys) {
    for (const k of keys) {
      const permissionId = permIds.get(k);
      if (!permissionId) throw new Error(`Missing permission id for ${k}`);
      await prisma.rolePermission.upsert({
        where: { roleId_permissionId: { roleId, permissionId } },
        update: {},
        create: { roleId, permissionId }
      });
    }
  }

  await syncRolePerms(superAdminRole.id, ["ADMIN_TENANT_READ","ADMIN_TENANT_WRITE","ADMIN_TENANT_SUSPEND","AUDIT_READ"]);
  await syncRolePerms(tenantAdminRole.id, ["TENANT_MEMBER_READ","TENANT_MEMBER_WRITE"]);

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

  // Tenants
  const tenants = [
    { id: "tnt_001", name: "Grace Chapel International", slug: "grace-chapel", status: "ACTIVE", planId: proPlan.id, seatsLimit: 15 },
    { id: "tnt_002", name: "House of Prayer Ministries", slug: "house-of-prayer", status: "PAST_DUE", planId: basicPlan.id, seatsLimit: 5 },
    { id: "tnt_003", name: "New Dawn Assembly", slug: "new-dawn", status: "TRIAL", planId: trialPlan.id, seatsLimit: 3 },
    { id: "tnt_004", name: "Living Waters Church", slug: "living-waters", status: "SUSPENDED", planId: proPlan.id, seatsLimit: 15 }
  ];

  for (const t of tenants) {
    await prisma.tenant.upsert({
      where: { id: t.id },
      update: {
        name: t.name,
        slug: t.slug,
        status: t.status,
        planId: t.planId,
        seatsLimit: t.seatsLimit
      },
      create: {
        id: t.id,
        name: t.name,
        slug: t.slug,
        status: t.status,
        planId: t.planId,
        seatsLimit: t.seatsLimit,
        trialEndsAt: t.status === "TRIAL" ? new Date(Date.now() + 1000 * 60 * 60 * 24 * 14) : null,
        suspendedAt: t.status === "SUSPENDED" ? new Date() : null
      }
    });
  }

  // Add 1 tenant admin per tenant
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
      update: { status: "ACTIVE" },
      create: { tenantId: t.id, userId: u.id, status: "ACTIVE" }
    });

    await prisma.membershipRole.upsert({
      where: { membershipId_roleId: { membershipId: m.id, roleId: tenantAdminRole.id } },
      update: {},
      create: { membershipId: m.id, roleId: tenantAdminRole.id }
    });
  }

  await prisma.auditLog.create({
    data: {
      actorType: "SYSTEM",
      action: "SEED_COMPLETED",
      entityType: "System",
      success: true,
      metadata: { note: "Initial Sprint 0 seed" }
    }
  });

  console.log("✅ Seed complete");
  console.log("  Super Admin email: admin@noxera.dev");
  console.log("  Tenants: tnt_001..tnt_004");
}

main()
  .catch((e) => { console.error("❌ Seed failed:", e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
