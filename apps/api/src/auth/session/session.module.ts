import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PrismaModule } from '../../prisma/prisma.module';
import { FirebaseAdminService } from '../firebase/firebase-admin.service';
import { SessionService } from './session.service';
import { SessionGuard } from './session.guard';

@Module({
  imports: [
    PrismaModule,
    JwtModule.register({
      secret: (process.env.JWT_SECRET || 'dev-jwt-secret-change-me').trim(),
      signOptions: { expiresIn: '7d' },
    }),
  ],
  providers: [FirebaseAdminService, SessionService, SessionGuard],
  exports: [SessionService, SessionGuard],
})
export class SessionModule {}
