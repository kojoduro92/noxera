import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { PrismaService } from '../prisma/prisma.service';
import { FeaturesService } from '../features/features.service';
import { SessionGuard } from '../auth/session/session.guard';

const allowedStatus = new Set([
  'TRIAL',
  'ACTIVE',
  'PAST_DUE',
  'SUSPENDED',
  'CANCELLED',
]);

function slugify(v: string) {
  return v
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 40);
}

@Controller('admin/tenants')
@UseGuards(SessionGuard)
export class AdminTenantsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly features: FeaturesService,
  ) {}

  private assertSuperAdmin(req: Request & { user?: any }) {
    if (req.user?.role !== 'SUPER_ADMIN') {
      throw new ForbiddenException('SUPER_ADMIN only');
    }
  }

  @Post()
  async create(
    @Req() req: Request & { user?: any },
    @Body() body: Record<string, any>,
  ) {
    this.assertSuperAdmin(req);

    const name = String(body?.name ?? '').trim();
    if (!name) throw new BadRequestException('name is required');

    const rand = Math.random().toString(36).slice(2, 8);
    const slug = String(body?.slug ?? '').trim() || `${slugify(name)}-${rand}`;

    // Optional: allow passing planId OR planTier; otherwise pick the oldest plan.
    const planId = body?.planId ? String(body.planId) : null;
    const planTier = body?.planTier ? String(body.planTier) : null;

    const plan = planId
      ? await this.prisma.plan.findUnique({ where: { id: planId } })
      : planTier
        ? await this.prisma.plan.findFirst({
            where: { tier: planTier as any },
            orderBy: { createdAt: 'asc' },
          })
        : await this.prisma.plan.findFirst({ orderBy: { createdAt: 'asc' } });

    if (!plan) {
      throw new BadRequestException(
        'No plans exist. Run: node tools/seed_first_plan.mjs',
      );
    }

    const created = await this.prisma.tenant.create({
      data: {
        name,
        slug,
        plan: { connect: { id: plan.id } },
      },
      include: { plan: true },
    });

    await this.prisma.auditLog.create({
      data: {
        tenantId: created.id,
        actorType: 'SYSTEM',
        action: 'TENANT_CREATED',
        entityType: 'Tenant',
        entityId: created.id,
        success: true,
        metadata: { name: created.name, slug: created.slug, planId: plan.id },
      },
    });

    return created;
  }

  @Get()
  async list(
    @Req() req: Request & { user?: any },
    @Query('q') q?: string,
    @Query('status') status?: string,
    @Query('planTier') planTier?: string,
    @Query('page') pageStr?: string,
    @Query('pageSize') pageSizeStr?: string,
  ) {
    this.assertSuperAdmin(req);

    const page = Math.max(1, parseInt(pageStr || '1', 10) || 1);
    const pageSize = Math.min(
      100,
      Math.max(1, parseInt(pageSizeStr || '20', 10) || 20),
    );
    const skip = (page - 1) * pageSize;

    const where: any = {};
    if (q && q.trim()) {
      const s = q.trim();
      where.OR = [
        { name: { contains: s } },
        { slug: { contains: s } },
        { id: { contains: s } },
      ];
    }
    if (status) where.status = status;
    if (planTier) where.plan = { is: { tier: planTier as any } };

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

    const items = itemsRaw.map((t: any) => ({
      id: t.id,
      name: t.name,
      slug: t.slug,
      status: t.status,
      planTier: t.plan?.tier ?? null,
      seatsLimit: t.seatsLimit ?? null,
      seatsUsed: t.memberships?.length ?? 0,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    }));

    return { page, pageSize, total, items };
  }

  @Get(':id')
  async detail(@Req() req: Request & { user?: any }, @Param('id') id: string) {
    this.assertSuperAdmin(req);

    const t: any = await this.prisma.tenant.findUnique({
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
      planTier: t.plan?.tier ?? null,
      seatsLimit: t.seatsLimit ?? null,
      seatsUsed: t.memberships?.length ?? 0,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      features: fx,
    };
  }

  @Patch(':id/status')
  async setStatus(
    @Req() req: Request & { user?: any },
    @Param('id') id: string,
    @Body() body: any,
  ) {
    this.assertSuperAdmin(req);

    const nextStatus = body?.status;
    if (!allowedStatus.has(nextStatus))
      throw new BadRequestException('Invalid status');

    const tenant: any = await this.prisma.tenant.update({
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
