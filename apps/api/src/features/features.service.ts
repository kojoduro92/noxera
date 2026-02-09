import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { deepMerge, isPlainObject } from './feature-merge';

@Injectable()
export class FeaturesService {
  constructor(private readonly prisma: PrismaService) {}

  async getTenantEffectiveFeatures(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      include: { plan: true, overrides: true },
    });
    if (!tenant) throw new NotFoundException('Tenant not found');

    const planFeatures = (tenant.plan.features ?? {}) as any;
    const overrideFeatures = (tenant.overrides?.overrides ?? {}) as any;

    const base = isPlainObject(planFeatures) ? planFeatures : {};
    const over = isPlainObject(overrideFeatures) ? overrideFeatures : {};

    const effective = deepMerge(base, over);
    return {
      planFeatures: base,
      overrideFeatures: over,
      effectiveFeatures: effective,
    };
  }
}
