#!/usr/bin/env bash
set -euo pipefail

cd "$(pwd)"

# ----------------------------
# 1) Ensure api has a dev script (so pnpm -C apps/api dev works)
# ----------------------------
node <<'NODE'
const fs = require("fs");
const p = "apps/api/package.json";
const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.scripts ||= {};
if (!j.scripts.dev) j.scripts.dev = j.scripts["start:dev"] || "nest start --watch";
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
console.log("✅ ensured apps/api has script: dev");
NODE

mkdir -p apps/api/src/prisma
mkdir -p apps/api/src/auth/firebase
mkdir -p apps/api/src/auth/session
mkdir -p apps/api/src/admin

# ----------------------------
# 2) PrismaService: safe adapter initialization (won't crash with empty options)
# ----------------------------
cat > apps/api/src/prisma/prisma.service.ts <<'EOF'
import "dotenv/config";
import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";
import { PrismaMariaDb } from "@prisma/adapter-mariadb";

function buildMariaDbAdapter(databaseUrl: string) {
  // Try the "url" style first (some versions support it)
  try {
    return new PrismaMariaDb({ url: databaseUrl } as any);
  } catch {}

  // Fallback: parse DATABASE_URL into discrete fields
  try {
    const u = new URL(databaseUrl);
    const host = u.hostname;
    const port = Number(u.port || "3306");
    const user = decodeURIComponent(u.username || "");
    const password = decodeURIComponent(u.password || "");
    const database = (u.pathname || "").replace(/^\//, "");
    const connectionLimit = Number(process.env.DB_POOL_SIZE || "5");

    return new PrismaMariaDb(
      { host, port, user, password, database, connectionLimit } as any
    );
  } catch (e: any) {
    throw new Error(
      "Failed to init PrismaMariaDb adapter. Check DATABASE_URL format. " +
      (e?.message ? `(${e.message})` : "")
    );
  }
}

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error("Missing DATABASE_URL in apps/api/.env");

    // If adapter init fails for any reason, Prisma may still work with super()
    // but in Rust-free setups it needs an adapter.
    let adapter: any = null;
    try {
      adapter = buildMariaDbAdapter(url);
    } catch (e: any) {
      // Last resort: try Prisma default engine
      // (If you're using Rust-free Prisma, this will throw again and that's OK)
      super();
      return;
    }

    super({ adapter });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
EOF

# ----------------------------
# 3) FirebaseAdminService: NEVER crash if json is missing/empty; add isConfigured()
# ----------------------------
cat > apps/api/src/auth/firebase/firebase-admin.service.ts <<'EOF'
import { Injectable, Logger, UnauthorizedException } from "@nestjs/common";
import * as admin from "firebase-admin";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

@Injectable()
export class FirebaseAdminService {
  private readonly log = new Logger(FirebaseAdminService.name);
  private configured = false;

  constructor() {
    const fromEnv = (process.env.FIREBASE_SERVICE_ACCOUNT_PATH || "").trim();
    const defaultPath = join(process.cwd(), ".secrets", "firebase.serviceAccount.json");
    const candidates = [fromEnv, defaultPath].filter(Boolean);

    const found = candidates.find((p) => {
      try {
        return existsSync(p) && readFileSync(p, "utf8").trim().length > 0;
      } catch {
        return false;
      }
    });

    if (!found) {
      this.log.warn(
        `Firebase Admin NOT configured. Dev auth will still work.\n` +
          `To enable Firebase auth: put service account JSON at ${defaultPath}\n` +
          `or set FIREBASE_SERVICE_ACCOUNT_PATH=/abs/path/to/serviceAccount.json`
      );
      return;
    }

    try {
      const raw = readFileSync(found, "utf8");
      const serviceAccount = JSON.parse(raw);

      if (admin.apps.length === 0) {
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
        });
      }

      this.configured = true;
      this.log.log(`Firebase Admin configured using: ${found}`);
    } catch (e: any) {
      this.log.error(`Firebase Admin init failed: ${e?.message ?? e}`);
      this.configured = false;
    }
  }

  isConfigured() {
    return this.configured;
  }

  async verifyIdToken(idToken: string) {
    if (!this.configured) throw new UnauthorizedException("Firebase Admin not configured on API");
    try {
      return await admin.auth().verifyIdToken(idToken);
    } catch {
      throw new UnauthorizedException("Invalid Firebase ID token");
    }
  }
}
EOF

# ----------------------------
# 4) SessionService: fix JWT typing + add verify()
# ----------------------------
cat > apps/api/src/auth/session/session.service.ts <<'EOF'
import { BadRequestException, Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { FirebaseAdminService } from "../firebase/firebase-admin.service";

export type SessionUserRole = "SUPER_ADMIN" | "CHURCH_USER";
export type SessionUser = { userId: string; email: string | null; role: SessionUserRole };

@Injectable()
export class SessionService {
  constructor(
    private readonly jwt: JwtService,
    private readonly firebase: FirebaseAdminService
  ) {}

  private jwtSecret(): string {
    const s = (process.env.JWT_SECRET || "").trim();
    if (s) return s;
    if (process.env.NODE_ENV === "production") {
      throw new Error("Missing JWT_SECRET (required in production)");
    }
    // local/dev default to avoid runtime crash
    return "dev-jwt-secret-change-me";
  }

  private async issue(user: SessionUser) {
    // IMPORTANT: do NOT put `sub` in payload; set it via `subject` option (fixes TS overload issues)
    const token = await this.jwt.signAsync(
      { email: user.email ?? undefined, role: user.role },
      { subject: user.userId, secret: this.jwtSecret(), expiresIn: "7d" }
    );
    return { token, user };
  }

  async createDevSession() {
    return this.issue({
      userId: "dev-user",
      email: "dev@noxera.local",
      role: "SUPER_ADMIN",
    });
  }

  async createSessionFromFirebase(idToken: string) {
    const t = String(idToken || "").trim();
    if (!t) throw new BadRequestException("idToken is required");

    if (!this.firebase.isConfigured()) {
      throw new BadRequestException(
        "Firebase auth is not configured on API yet. Add service account JSON to apps/api/.secrets/firebase.serviceAccount.json and restart."
      );
    }

    const decoded: any = await this.firebase.verifyIdToken(t);
    const userId = String(decoded?.uid || "").trim();
    if (!userId) throw new UnauthorizedException("Firebase token missing uid");

    const email = decoded?.email ? String(decoded.email) : null;

    // Prefer custom claim role; default to CHURCH_USER
    const role: SessionUserRole =
      decoded?.role === "SUPER_ADMIN" ? "SUPER_ADMIN" : "CHURCH_USER";

    return this.issue({ userId, email, role });
  }

  async verify(token: string): Promise<SessionUser> {
    const t = String(token || "").trim();
    if (!t) throw new UnauthorizedException("Missing session token");

    try {
      const payload: any = await this.jwt.verifyAsync(t, { secret: this.jwtSecret() });

      const userId = String(payload?.sub || "").trim();
      if (!userId) throw new UnauthorizedException("Invalid session token (no sub)");

      const role: SessionUserRole =
        payload?.role === "SUPER_ADMIN" ? "SUPER_ADMIN" : "CHURCH_USER";

      const email = payload?.email ? String(payload.email) : null;

      return { userId, email, role };
    } catch {
      throw new UnauthorizedException("Invalid or expired session token");
   ਾ
    }
  }
}
EOF

# ----------------------------
# 5) SessionGuard: extract token from Authorization OR cookie; uses sessions.verify()
# ----------------------------
cat > apps/api/src/auth/session/session.guard.ts <<'EOF'
import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from "@nestjs/common";
import type { Request } from "express";
import { SessionService } from "./session.service";

@Injectable()
export class SessionGuard implements CanActivate {
  constructor(private readonly sessions: SessionService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<Request & { user?: any }>();
    const token = this.extractToken(req);
    if (!token) throw new UnauthorizedException("Missing session");
    req.user = await this.sessions.verify(token);
    return true;
  }

  private extractToken(req: Request): string | null {
    // 1) Authorization: Bearer <token>
    const auth = req.headers["authorization"];
    if (typeof auth === "string") {
      const m = auth.match(/^Bearer\s+(.+)$/i);
      if (m?.[1]) return m[1].trim();
    }

    // 2) cookie-parser (if installed): req.cookies.noxera_session
    const anyReq: any = req as any;
    const c = anyReq?.cookies?.noxera_session;
    if (typeof c === "string" && c.trim()) return c.trim();

    // 3) Raw cookie header fallback
    const cookieHeader = req.headers["cookie"];
    if (typeof cookieHeader === "string") {
      const m2 = cookieHeader.match(/(?:^|;\s*)noxera_session=([^;]+)/);
      if (m2?.[1]) return decodeURIComponent(m2[1]);
    }

    return null;
  }
}
EOF

# ----------------------------
# 6) AdminTenantsController: clean, single POST, correct Prisma import
# ----------------------------
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

function slugify(v: string) {
  return v
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
    .slice(0, 40);
}

@Controller("admin/tenants")
export class AdminTenantsController {
  constructor(private readonly prisma: PrismaService, private readonly features: FeaturesService) {}

  // Sprint 1: Create Tenant
  @Post()
  async createTenant(@Body() body: Record<string, any>) {
    const name = String(body?.name ?? "").trim();
    if (!name) throw new BadRequestException("name is required");

    const rand = Math.random().toString(36).slice(2, 8);
    const slug = String(body?.slug ?? "").trim() || `${slugify(name)}-${rand}`;

    // Your schema uses relation: tenant.plan (because list/detail do include: { plan: true })
    // Accept: planId OR planTier (or plan) OR fallback to the first plan in DB.
    const planId = typeof body?.planId === "string" ? body.planId.trim() : "";
    const planTier = typeof body?.planTier === "string"
      ? body.planTier.trim()
      : (typeof body?.plan === "string" ? body.plan.trim() : "");

    let planToConnect: { id: string } | null = null;

    if (planId) {
      const p = await this.prisma.plan.findUnique({ where: { id: planId } as any });
      if (!p) throw new BadRequestException(`Plan not found for planId=${planId}`);
      planToConnect = { id: (p as any).id };
    } else if (planTier) {
      const p = await this.prisma.plan.findFirst({ where: { tier: planTier as any } as any });
      if (!p) throw new BadRequestException(`Plan not found for planTier=${planTier}`);
      planToConnect = { id: (p as any).id };
    } else {
      const p = await this.prisma.plan.findFirst({ orderBy: { createdAt: "asc" } as any });
      if (!p) {
        throw new BadRequestException(
          "No plans exist in DB. Seed the Plan table first, OR pass planId/planTier."
        );
      }
      planToConnect = { id: (p as any).id };
    }

    try {
      const created = await this.prisma.tenant.create({
        data: {
          name,
          slug,
          plan: { connect: planToConnect },
        } as any,
        include: { plan: true },
      });

      await this.prisma.auditLog.create({
        data: {
          tenantId: created.id,
          actorType: "SYSTEM",
          action: "TENANT_CREATED",
          entityType: "Tenant",
          entityId: created.id,
          success: true,
          metadata: { name, slug, planId: planToConnect.id },
        } as any,
      });

      return {
        id: created.id,
        name: created.name,
        slug: created.slug,
        status: created.status,
        planTier: (created as any).plan?.tier ?? null,
        createdAt: created.createdAt,
        updatedAt: created.updatedAt,
      };
    } catch (e: any) {
      // Prisma unique constraint
      if (e?.code === "P2002") throw new BadRequestException("Tenant slug already exists");
      throw e;
    }
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
    const t: any = await this.prisma.tenant.findUnique({
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
      planTier: t.plan?.tier ?? null,
      seatsLimit: t.seatsLimit,
      seatsUsed: t.memberships.length,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      features: fx,
    };
  }

  @Patch(":id/status")
  async setStatus(@Param("id") id: string, @Body() body: any) {
    const nextStatus = body?.status;
    if (!allowedStatus.has(nextStatus)) throw new BadRequestException("Invalid status");

    const tenant: any = await this.prisma.tenant.update({
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
      } as any,
    });

    return { ok: true, tenantId: tenant.id, status: tenant.status };
  }
}
EOF

echo "✅ Sprint1 API hotfix applied (auth + prisma + create tenant)."
