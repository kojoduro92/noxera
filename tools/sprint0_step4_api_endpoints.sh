set -euo pipefail
API="apps/api"

mkdir -p "$API/src/prisma" "$API/src/auth" "$API/src/admin" "$API/src/health"

# PrismaService (Prisma v7 + adapter)
cat > "$API/src/prisma/prisma.service.ts" <<'TS'
import "dotenv/config";
import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";
import { PrismaMariaDb } from "@prisma/adapter-mariadb";

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error("Missing DATABASE_URL");
    super({ adapter: new PrismaMariaDb(url) });
  }
  async onModuleInit() { await this.$connect(); }
  async onModuleDestroy() { await this.$disconnect(); }
}
TS

cat > "$API/src/prisma/prisma.module.ts" <<'TS'
import { Global, Module } from "@nestjs/common";
import { PrismaService } from "./prisma.service";

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
TS

# Health
cat > "$API/src/health/health.controller.ts" <<'TS'
import { Controller, Get } from "@nestjs/common";

@Controller("health")
export class HealthController {
  @Get()
  ok() {
    return { ok: true };
  }
}
TS

cat > "$API/src/health/health.module.ts" <<'TS'
import { Module } from "@nestjs/common";
import { HealthController } from "./health.controller";

@Module({ controllers: [HealthController] })
export class HealthModule {}
TS

# Auth (Sprint 0: dev token -> firebaseUid; later we wire real Firebase Admin)
cat > "$API/src/auth/auth.controller.ts" <<'TS'
import { Body, Controller, Post, UnauthorizedException } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";

@Controller("auth")
export class AuthController {
  constructor(private readonly prisma: PrismaService) {}

  @Post("session")
  async session(@Body() body: any) {
    const token: string | undefined = body?.token;
    if (!token) throw new UnauthorizedException("Missing token");

    // Sprint 0 dev-mode:
    // - token = firebaseUid (e.g. dev_admin_uid) from seed
    const user = await this.prisma.user.findFirst({
      where: { firebaseUid: token },
      include: {
        globalRoles: { include: { role: true } },
        memberships: {
          include: {
            tenant: { include: { plan: true } },
            roles: { include: { role: true } },
          },
        },
      },
    });

    if (!user) throw new UnauthorizedException("Invalid token");

    return {
      user: { id: user.id, email: user.email, phone: user.phone, displayName: user.displayName },
      globalRoles: user.globalRoles.map((r) => r.role.key),
      memberships: user.memberships.map((m) => ({
        tenant: {
          id: m.tenant.id,
          name: m.tenant.name,
          slug: m.tenant.slug,
          status: m.tenant.status,
          planTier: m.tenant.plan.tier,
          seatsLimit: m.tenant.seatsLimit,
        },
        roles: m.roles.map((mr) => mr.role.key),
        status: m.status,
      })),
    };
  }
}
TS

cat > "$API/src/auth/auth.module.ts" <<'TS'
import { Module } from "@nestjs/common";
import { AuthController } from "./auth.controller";

@Module({ controllers: [AuthController] })
export class AuthModule {}
TS

# Admin Tenants
cat > "$API/src/admin/admin-tenants.controller.ts" <<'TS'
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Query,
} from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";

const allowedStatus = new Set(["TRIAL", "ACTIVE", "PAST_DUE", "SUSPENDED", "CANCELLED"]);

@Controller("admin/tenants")
export class AdminTenantsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async list(
    @Query("q") q?: string,
    @Query("status") status?: string,
    @Query("planTier") planTier?: string,
    @Query("page") pageStr?: string,
    @Query("pageSize") pageSizeStr?: string
  ) {
    const page = Math.max(1, parseInt(pageStr || "1", 10) || 1);
    const pageSize = Math.min(100, Math.max(1, parseInt(pageSizeStr || "20", 10) || 20));
    const skip = (page - 1) * pageSize;

    const where: any = {};
    if (q && q.trim()) {
      const s = q.trim();
      where.OR = [
        { name: { contains: s } },
        { id: { contains: s } },
        { slug: { contains: s } },
      ];
    }
    if (status) where.status = status;
    if (planTier) where.plan = { tier: planTier };

    const [total, itemsRaw] = await Promise.all([
      this.prisma.tenant.count({ where }),
      this.prisma.tenant.findMany({
        where,
        include: {
          plan: true,
          memberships: { where: { status: "ACTIVE" }, select: { id: true } },
        },
        orderBy: { createdAt: "desc" },
        skip,
        take: pageSize,
      }),
    ]);

    const items = itemsRaw.map((t) => ({
      id: t.id,
      name: t.name,
      slug: t.slug,
      status: t.status,
      planTier: t.plan.tier,
      seatsLimit: t.seatsLimit,
      seatsUsed: t.memberships.length,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    }));

    return {
      page,
      pageSize,
      total,
      items,
    };
  }

  @Patch(":id/status")
  async setStatus(@Param("id") id: string, @Body() body: any) {
    const nextStatus = body?.status;
    if (!allowedStatus.has(nextStatus)) {
      throw new BadRequestException("Invalid status");
    }

    const tenant = await this.prisma.tenant.update({
      where: { id },
      data: {
        status: nextStatus,
        suspendedAt: nextStatus === "SUSPENDED" ? new Date() : null,
        cancelledAt: nextStatus === "CANCELLED" ? new Date() : null,
      },
    });

    await this.prisma.auditLog.create({
      data: {
        tenantId: tenant.id,
        actorType: "SYSTEM",
        action: "TENANT_STATUS_CHANGED",
        entityType: "Tenant",
        entityId: tenant.id,
        success: true,
        metadata: { status: nextStatus },
      },
    });

    return { ok: true, tenantId: tenant.id, status: tenant.status };
  }
}
TS

cat > "$API/src/admin/admin.module.ts" <<'TS'
import { Module } from "@nestjs/common";
import { AdminTenantsController } from "./admin-tenants.controller";

@Module({ controllers: [AdminTenantsController] })
export class AdminModule {}
TS

# Wire modules into AppModule
node - <<'NODE'
const fs = require("fs");
const p = "apps/api/src/app.module.ts";
let s = fs.readFileSync(p, "utf8");

function ensureImport(name, from) {
  if (!s.includes(`from "${from}"`)) {
    s = `import { ${name} } from "${from}";\n` + s;
  }
}

ensureImport("PrismaModule", "./prisma/prisma.module");
ensureImport("HealthModule", "./health/health.module");
ensureImport("AuthModule", "./auth/auth.module");
ensureImport("AdminModule", "./admin/admin.module");

if (!s.includes("imports:")) {
  throw new Error("Unexpected app.module.ts format: no imports: [] found");
}

s = s.replace(/imports:\s*\[([\s\S]*?)\]/m, (m, inner) => {
  const mods = ["PrismaModule", "HealthModule", "AuthModule", "AdminModule"];
  for (const mod of mods) {
    if (!inner.includes(mod)) inner = inner.trim() ? `${inner.trim()}\n    , ${mod}` : `\n    ${mod}`;
  }
  return `imports: [${inner}\n  ]`;
});

fs.writeFileSync(p, s);
console.log("✅ Updated apps/api/src/app.module.ts");
NODE

echo "🎉 Step 4 API endpoints scaffolded."
