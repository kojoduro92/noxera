#!/usr/bin/env bash
set -euo pipefail

echo "==> [1/4] Ensure apps/api has a dev script alias"
node - <<'NODE'
const fs = require('fs');
const p = 'apps/api/package.json';
const j = JSON.parse(fs.readFileSync(p,'utf8'));
j.scripts ||= {};
if (!j.scripts.dev) j.scripts.dev = 'pnpm run start:dev';
fs.writeFileSync(p, JSON.stringify(j, null, 2) + '\n');
console.log('✅ Added apps/api script: dev -> start:dev');
NODE

echo "==> [2/4] Fix Firebase Admin service (adds isConfigured + correct path handling)"
cat > apps/api/src/auth/firebase/firebase-admin.service.ts <<'EOF'
import { Injectable, InternalServerErrorException, Logger } from '@nestjs/common';
import * as admin from 'firebase-admin';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

@Injectable()
export class FirebaseAdminService {
  private readonly log = new Logger(FirebaseAdminService.name);
  private initialized = false;

  /**
   * Returns true if Firebase Admin *can* be initialized (env JSON or non-empty serviceAccount file exists),
   * OR if it's already initialized.
   */
  isConfigured(): boolean {
    if (admin.apps.length > 0) return true;

    const jsonEnv = (process.env.FIREBASE_SERVICE_ACCOUNT_JSON ?? '').trim();
    if (jsonEnv) {
      try {
        JSON.parse(jsonEnv);
        return true;
      } catch {
        return false;
      }
    }

    const envPath = (process.env.FIREBASE_SERVICE_ACCOUNT_PATH ?? '').trim();

    // IMPORTANT: support both working directories:
    // - repo root (cwd = .../noxera)
    // - apps/api     (cwd = .../noxera/apps/api)
    const candidates = [
      envPath || null,
      join(process.cwd(), '.secrets', 'firebase.serviceAccount.json'),
      join(process.cwd(), 'apps', 'api', '.secrets', 'firebase.serviceAccount.json'),
    ].filter(Boolean) as string[];

    for (const p of candidates) {
      if (!existsSync(p)) continue;
      try {
        const raw = readFileSync(p, 'utf8').trim();
        if (!raw) return false; // file exists but empty
        JSON.parse(raw);
        return true;
      } catch {
        return false;
      }
    }

    return false;
  }

  private getServiceAccountJson(): string | null {
    const jsonEnv = (process.env.FIREBASE_SERVICE_ACCOUNT_JSON ?? '').trim();
    if (jsonEnv) return jsonEnv;

    const envPath = (process.env.FIREBASE_SERVICE_ACCOUNT_PATH ?? '').trim();

    const candidates = [
      envPath || null,
      join(process.cwd(), '.secrets', 'firebase.serviceAccount.json'),
      join(process.cwd(), 'apps', 'api', '.secrets', 'firebase.serviceAccount.json'),
    ].filter(Boolean) as string[];

    for (const p of candidates) {
      if (!existsSync(p)) continue;
      const raw = readFileSync(p, 'utf8').trim();
      if (!raw) return null;
      return raw;
    }

    return null;
  }

  private ensureInit(): void {
    if (this.initialized) return;
    this.initialized = true;

    if (admin.apps.length > 0) return;

    const raw = this.getServiceAccountJson();
    if (!raw) {
      this.log.warn('Firebase Admin not configured (no service account JSON found).');
      return;
    }

    try {
      const svc = JSON.parse(raw);
      admin.initializeApp({ credential: admin.credential.cert(svc) });
      this.log.log('Firebase Admin initialized.');
    } catch (e: any) {
      this.log.error(`Firebase Admin init failed: ${e?.message ?? e}`);
    }
  }

  async verifyIdToken(idToken: string) {
    this.ensureInit();
    if (admin.apps.length === 0) {
      throw new InternalServerErrorException(
        'Firebase Admin is not configured. Provide FIREBASE_SERVICE_ACCOUNT_JSON or a non-empty apps/api/.secrets/firebase.serviceAccount.json'
      );
    }
    return admin.auth().verifyIdToken(idToken);
  }
}
EOF

echo "==> [3/4] Fix SessionService (no 'sub' typing issues; uses subject option)"
cat > apps/api/src/auth/session/session.service.ts <<'EOF'
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { FirebaseAdminService } from '../firebase/firebase-admin.service';

export type AppRole = 'SUPER_ADMIN' | 'CHURCH_USER';

export type SessionUser = {
  userId: string;
  email?: string;
  role: AppRole;
};

export type SessionResult = {
  token: string;
  user: SessionUser;
};

@Injectable()
export class SessionService {
  constructor(private readonly jwt: JwtService, private readonly firebase: FirebaseAdminService) {}

  private jwtSecret(): string {
    return (process.env.JWT_SECRET ?? '').trim() || 'dev_jwt_secret_change_me';
  }

  private parseCsv(v: string | undefined): Set<string> {
    return new Set((v ?? '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean));
  }

  private isSuperAdminEmail(email?: string): boolean {
    if (!email) return false;
    const allow = this.parseCsv(process.env.NOXERA_SUPERADMIN_EMAILS);
    if (allow.size === 0) return false;
    return allow.has(email.toLowerCase());
  }

  async createDevSession(): Promise<SessionResult> {
    const user: SessionUser = {
      userId: 'dev-user',
      email: 'dev@noxera.local',
      role: 'SUPER_ADMIN',
    };

    const token = await this.jwt.signAsync(
      { email: user.email, role: user.role },
      { subject: user.userId, secret: this.jwtSecret(), expiresIn: '7d' }
    );

    return { token, user };
  }

  async createSessionFromFirebase(idToken: string): Promise<SessionResult> {
    if (!idToken || !idToken.trim()) throw new UnauthorizedException('idToken is required');

    // If not configured, fail cleanly (dev flow still works)
    if (!this.firebase.isConfigured()) {
      throw new UnauthorizedException(
        'Firebase Admin not configured. Add service account JSON to apps/api/.secrets/firebase.serviceAccount.json or set FIREBASE_SERVICE_ACCOUNT_JSON'
      );
    }

    const decoded = await this.firebase.verifyIdToken(idToken);
    const email = decoded.email ?? undefined;

    const user: SessionUser = {
      userId: decoded.uid,
      email,
      role: this.isSuperAdminEmail(email) ? 'SUPER_ADMIN' : 'CHURCH_USER',
    };

    const token = await this.jwt.signAsync(
      { email: user.email, role: user.role },
      { subject: user.userId, secret: this.jwtSecret(), expiresIn: '7d' }
    );

    return { token, user };
  }
}
EOF

echo "==> [4/4] Replace corrupted AdminTenantsController with a clean working version"
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
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FeaturesService } from '../features/features.service';

const allowedStatus = new Set(['TRIAL', 'ACTIVE', 'PAST_DUE', 'SUSPENDED', 'CANCELLED']);

function slugify(v: string) {
  return v
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 40);
}

@Controller('admin/tenants')
export class AdminTenantsController {
  constructor(private readonly prisma: PrismaService, private readonly features: FeaturesService) {}

  /**
   * Sprint 1: Create Tenant
   * Accepts: { name, slug?, planId?, planTier? }
   * Picks a plan in this order:
   *  - planId (exact)
   *  - planTier (first match)
   *  - BASIC tier (if exists)
   *  - any plan (first)
   */
  @Post()
  async createTenant(@Body() body: Record<string, any>) {
    const name = String(body?.name ?? '').trim();
    if (!name) throw new BadRequestException('name is required');

    const rand = Math.random().toString(36).slice(2, 8);
    const slug = String(body?.slug ?? '').trim() || `${slugify(name)}-${rand}`;

    let plan: any | null = null;

    const planId = String(body?.planId ?? '').trim();
    if (planId) {
      plan = await (this.prisma as any).plan.findUnique({ where: { id: planId } });
    }

    const planTier = String(body?.planTier ?? '').trim();
    if (!plan && planTier) {
      plan = await (this.prisma as any).plan.findFirst({ where: { tier: planTier as any } });
    }

    if (!plan) {
      plan = await (this.prisma as any).plan.findFirst({ where: { tier: 'BASIC' as any } });
    }

    if (!plan) {
      plan = await (this.prisma as any).plan.findFirst();
    }

    if (!plan) {
      throw new BadRequestException(
        'No subscription plans found. Seed a Plan first (e.g., BASIC) before creating tenants.'
      );
    }

    const created = await this.prisma.tenant.create({
      data: {
        name,
        slug,
        plan: { connect: { id: plan.id } },
      } as any,
      include: { plan: true },
    });

    return created;
  }

  @Get()
  async list(
    @Query('q') q?: string,
    @Query('status') status?: string,
    @Query('planTier') planTier?: string,
    @Query('page') pageStr?: string,
    @Query('pageSize') pageSizeStr?: string
  ) {
    const page = Math.max(1, parseInt(pageStr || '1', 10) || 1);
    const pageSize = Math.min(100, Math.max(1, parseInt(pageSizeStr || '20', 10) || 20));
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
          memberships: { where: { status: 'ACTIVE' }, select: { id: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip,
        take: pageSize,
      }),
    ]);

    const items = itemsRaw.map((t) => ({
      id: t.id,
      name: t.name,
      slug: t.slug,
      status: t.status,
      planTier: (t as any).plan?.tier,
      seatsLimit: t.seatsLimit,
      seatsUsed: (t as any).memberships?.length ?? 0,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    }));

    return { page, pageSize, total, items };
  }

  @Get(':id')
  async detail(@Param('id') id: string) {
    const t = await this.prisma.tenant.findUnique({
      where: { id },
      include: {
        plan: true,
        overrides: true,
        memberships: { where: { status: 'ACTIVE' }, select: { id: true } },
      },
    });
    if (!t) throw new NotFoundException('Tenant not found');

    const fx = await this.features.getTenantEffectiveFeatures(t.id);

    return {
      id: t.id,
      name: t.name,
      slug: t.slug,
      status: t.status,
      planTier: (t as any).plan?.tier,
      seatsLimit: t.seatsLimit,
      seatsUsed: (t as any).memberships?.length ?? 0,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      features: fx,
    };
  }

  @Patch(':id/status')
  async setStatus(@Param('id') id: string, @Body() body: any) {
    const nextStatus = body?.status;
    if (!allowedStatus.has(nextStatus)) throw new BadRequestException('Invalid status');

    const tenant = await this.prisma.tenant.update({
      where: { id },
      data: {
        status: nextStatus,
        suspendedAt: nextStatus === 'SUSPENDED' ? new Date() : null,
        cancelledAt: nextStatus === 'CANCELLED' ? new Date() : null,
      },
    });

    await this.prisma.auditLog.create({
      data: {
        tenantId: tenant.id,
        actorType: 'SYSTEM',
        action: 'TENANT_STATUS_CHANGED',
        entityType: 'Tenant',
        entityId: tenant.id,
        success: true,
        metadata: { status: nextStatus },
      },
    });

    return { ok: true, tenantId: tenant.id, status: tenant.status };
  }
}
EOF

echo "✅ Repair complete."
echo
echo "Next:"
echo "  1) Start API: pnpm -C apps/api start:dev   (or: pnpm -C apps/api dev)"
echo "  2) Test: curl -sS http://localhost:3000/health"
