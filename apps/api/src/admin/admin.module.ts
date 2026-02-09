import { Module } from '@nestjs/common';
import { AdminTenantsController } from './admin-tenants.controller';
import { AdminAuditController } from './admin-audit.controller';
import { FeaturesService } from '../features/features.service';
import { SessionModule } from '../auth/session/session.module';

@Module({
  imports: [SessionModule],
  controllers: [AdminTenantsController, AdminAuditController],
  providers: [FeaturesService],
})
export class AdminModule {}
