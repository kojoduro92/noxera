import { Controller, Get, Query } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Controller('admin/audit')
export class AdminAuditController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async list(
    @Query('q') q?: string,
    @Query('tenantId') tenantId?: string,
    @Query('action') action?: string,
    @Query('entityType') entityType?: string,
    @Query('entityId') entityId?: string,
    @Query('page') pageStr?: string,
    @Query('pageSize') pageSizeStr?: string,
  ) {
    const page = Math.max(1, parseInt(pageStr || '1', 10) || 1);
    const pageSize = Math.min(
      100,
      Math.max(1, parseInt(pageSizeStr || '20', 10) || 20),
    );
    const skip = (page - 1) * pageSize;

    const where: any = {};
    if (tenantId) where.tenantId = tenantId;
    if (action) where.action = action;
    if (entityType) where.entityType = entityType;
    if (entityId) where.entityId = entityId;

    if (q && q.trim()) {
      const s = q.trim();
      where.OR = [
        { action: { contains: s } },
        { entityType: { contains: s } },
        { entityId: { contains: s } },
      ];
    }

    const [total, items] = await Promise.all([
      this.prisma.auditLog.count({ where }),
      this.prisma.auditLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: pageSize,
        include: {
          tenant: { select: { id: true, name: true, slug: true } },
          actor: { select: { id: true, email: true, displayName: true } },
        },
      }),
    ]);

    return {
      page,
      pageSize,
      total,
      items: items.map((a) => ({
        id: a.id,
        createdAt: a.createdAt,
        tenant: a.tenant
          ? { id: a.tenant.id, name: a.tenant.name, slug: a.tenant.slug }
          : null,
        actorType: a.actorType,
        actor: a.actor
          ? {
              id: a.actor.id,
              email: a.actor.email,
              displayName: a.actor.displayName,
            }
          : null,
        action: a.action,
        entityType: a.entityType,
        entityId: a.entityId,
        success: a.success,
        metadata: a.metadata,
      })),
    };
  }
}
