#!/usr/bin/env bash

cd "$(dirname "$0")/.."

echo "==> Backing up current files..."
ts="$(date +%s)"
cp -f apps/api/src/admin/admin-tenants.controller.ts "apps/api/src/admin/admin-tenants.controller.ts.bak.$ts" 2>/dev/null || true
cp -f apps/api/src/auth/firebase/firebase-admin.service.ts "apps/api/src/auth/firebase/firebase-admin.service.ts.bak.$ts" 2>/dev/null || true

echo "==> Writing clean AdminTenantsController (single @Post, correct Prisma import)..."
cat > apps/api/src/admin/admin-tenants.controller.ts <<'EOF'
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
} from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import { FeaturesService } from "../features/features.service";

const allowedStatus = new Set(["TRIAL", "ACTIVE", "PAST_DUE", "SUSPENDED", "CANCELLED"]);

type CreateTenantBody = {
  name: string;
  slug?: string;
  planId?: string;     // optional (preferred if you have it)
  planTier?: string;   // optional (e.g. BASIC/TRIAL/etc)
};

@Controller("admin/tenants")
export class AdminTenantsController {
  constructor(private readonly prisma: PrismaService, private readonly features: FeaturesService) {}

  // ✅ Sprint 1: Create tenant (no duplicate routes)
  // Strategy:
  // - If planId provided -> connect to it
  // - Else if planTier provided -> infer a matching planId by finding any existing tenant with that plan tier
  // - Else -> default to the plan used by the most recent tenant
  @Post()
  async createTenant(@Body() body: CreateTenantBody) {
    const name = String(body?.name ?? "").trim();
    if (!name) throw new BadRequestException("name is required");

    const slug = String(body?.slug ?? "").trim() || this.makeSlug(name);

    const planIdFromBody = String((body as any)?.planId ?? "").trim() || null;
    const planTier = String((body as any)?.planTier ?? "").trim() || null;

    let resolvedPlanId: string | null = planIdFromBody;

    if (!resolvedPlanId) {
      // infer planId from existing data (uses ONLY prisma.tenant, so no guessing model names)
      const t = await this.prisma.tenant.findFirst({
        where: planTier ? { plan: { tier: planTier } } : undefined,
        orderBy: { createdAt: "desc" },
        include: { plan: { select: { id: true, tier: true } } },
      });

      resolvedPlanId = (t as any)?.plan?.id ?? null;

      if (!resolvedPlanId) {
        throw new BadRequestException(
          planTier
            ? `No plan could be inferred for planTier="${planTier}". Pass planId, or ensure at least one tenant exists with that plan tier.`
            : "No plan could be inferred. Pass planId, or ensure at least one tenant exists (so we can copy its plan)."
        );
      }
    }

    // Create with required relation connect
    const created = await this.prisma.tenant.create({
      data: {
        name,
        slug,
        plan: { connect: { id: resolvedPlanId } },
      } as any,
      include: { plan: true },
    });

    // Audit (keep same pattern as status change)
    await this.prisma.auditLog.create({
      data: {
        tenantId: created.id,
        actorType: "SYSTEM",
        action: "TENANT_CREATED",
        entityType: "Tenant",
        entityId: created.id,
        success: true,
        metadata: { planTier: (created as any)?.plan?.tier ?? null },
      } as any,
    });

    return created;
  }

  private makeSlug(name: string) {
    const rand = Math.random().toString(36).slice(2, 8);
    const base = name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "")
      .slice(0, 40);
    return `${base}-${rand}`;
  }

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
      where.OR = [{ name: { contains: s } }, { id: { contains: s } }, { slug: { contains: s } }];
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

    const items = itemsRaw.map((t: any) => ({
      id: t.id,
      name: t.name,
      slug: t.slug,
      status: t.status,
      planTier: t.plan?.tier ?? null,
      seatsLimit: t.seatsLimit,
      seatsUsed: t.memberships.length,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    }));

    return { page, pageSize, total, items };
  }

  @Get(":id")
  async detail(@Param("id") id: string) {
    const t = await this.prisma.tenant.findUnique({
      where: { id },
      include: {
        plan: true,
        overrides: true,
        memberships: { where: { status: "ACTIVE" }, select: { id: true } },
      },
    });
    if (!t) throw new NotFoundException("Tenant not found");

    const fx = await this.features.getTenantEffectiveFeatures(t.id);

    return {
      id: t.id,
      name: t.name,
      slug: t.slug,
      status: t.status,
      planTier: (t as any).plan?.tier ?? null,
      seatsLimit: (t as any).seatsLimit,
      seatsUsed: (t as any).memberships.length,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      features: fx,
    };
  }

  @Patch(":id/status")
  async setStatus(@Param("id") id: string, @Body() body: any) {
    const nextStatus = body?.status;
    if (!allowedStatus.has(nextStatus)) throw new BadRequestException("Invalid status");

    const tenant = await this.prisma.tenant.update({
      where: { id },
      data: {
        status: nextStatus,
        suspendedAt: nextStatus === "SUSPENDED" ? new Date() : null,
        cancelledAt: nextStatus === "CANCELLED" ? new Date() : null,
      } as any,
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
      } as any,
    });

    return { ok: true, tenantId: tenant.id, status: tenant.status };
  }
}
EOF

echo "==> Making Firebase admin lazy (won't crash if serviceAccount is missing/empty)..."
cat > apps/api/src/auth/firebase/firebase-admin.service.ts <<'EOF'
import { Injectable, InternalServerErrorException, UnauthorizedException } from "@nestjs/common";
import * as admin from "firebase-admin";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

@Injectable()
export class FirebaseAdminService {
  private ensured = false;

  private ensureInit() {
    if (this.ensured) return;
    this.ensured = true;

    if (admin.apps.length) return;

    // Prefer env JSON, fallback to file path candidates
    const jsonEnv = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
    let svc: any = null;

    if (jsonEnv) {
      try {
        svc = JSON.parse(jsonEnv);
      } catch {
        throw new InternalServerErrorException("FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON");
      }
    } else {
      const candidates = [
        process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim(),
        join(process.cwd(), "apps", "api", ".secrets", "firebase.serviceAccount.json"),
        join(process.cwd(), ".secrets", "firebase.serviceAccount.json"),
      ].filter(Boolean) as string[];

      const p = candidates.find((x) => existsSync(x));
      if (p) {
        const raw = readFileSync(p, "utf8").trim();
        if (raw) {
          try {
            svc = JSON.parse(raw);
          } catch {
            throw new InternalServerErrorException(`Firebase service account JSON is invalid at ${p}`);
          }
        }
      }
    }

    // If still missing, DO NOT crash app. We only need this for real Firebase sessions.
    if (!svc) return;

    admin.initializeApp({ credential: admin.credential.cert(svc) });
  }

  async verifyIdToken(idToken: string) {
    this.ensureInit();

    if (!admin.apps.length) {
      throw new InternalServerErrorException(
        "Firebase Admin not configured. Set FIREBASE_SERVICE_ACCOUNT_JSON or provide apps/api/.secrets/firebase.serviceAccount.json"
      );
    }

    try {
      return await admin.auth().verifyIdToken(idToken, true);
    } catch {
      throw new UnauthorizedException("Invalid Firebase idToken");
    }
  }
}
EOF

echo "==> Ensuring apps/api has a dev script alias..."
node - <<'NODE'
const fs = require("fs");
const p = "apps/api/package.json";
const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.scripts = j.scripts || {};
if (!j.scripts.dev) j.scripts.dev = "nest start --watch";
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
console.log("✅ apps/api dev script ensured");
NODE

echo "✅ FIX APPLIED."
echo "Now run: pnpm -C apps/api start:dev"
