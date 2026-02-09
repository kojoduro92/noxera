import {
  BadRequestException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { FirebaseAdminService } from '../firebase/firebase-admin.service';

export type SessionUserRole = 'SUPER_ADMIN' | 'CHURCH_USER';
export type SessionUser = {
  userId: string;
  email: string | null;
  role: SessionUserRole;
};

@Injectable()
export class SessionService {
  constructor(
    private readonly jwt: JwtService,
    private readonly firebase: FirebaseAdminService,
  ) {}

  private jwtSecret(): string {
    const s = (process.env.JWT_SECRET || '').trim();
    if (s) return s;
    if (process.env.NODE_ENV === 'production') {
      throw new Error('Missing JWT_SECRET (required in production)');
    }
    // local/dev default to avoid runtime crash
    return 'dev-jwt-secret-change-me';
  }

  private async issue(user: SessionUser) {
    // IMPORTANT: do NOT put `sub` in payload; set it via `subject` option (fixes TS overload issues)
    const token = await this.jwt.signAsync(
      { email: user.email ?? undefined, role: user.role },
      { subject: user.userId, secret: this.jwtSecret(), expiresIn: '7d' },
    );
    return { token, user };
  }

  async createDevSession() {
    return this.issue({
      userId: 'dev-user',
      email: 'dev@noxera.local',
      role: 'SUPER_ADMIN',
    });
  }

  async createSessionFromFirebase(idToken: string) {
    const t = String(idToken || '').trim();
    if (!t) throw new BadRequestException('idToken is required');

    if (!this.firebase.isConfigured()) {
      throw new BadRequestException(
        'Firebase auth is not configured on API yet. Add service account JSON to apps/api/.secrets/firebase.serviceAccount.json and restart.',
      );
    }

    const decoded: any = await this.firebase.verifyIdToken(t);
    const userId = String(decoded?.uid || '').trim();
    if (!userId) throw new UnauthorizedException('Firebase token missing uid');

    const email = decoded?.email ? String(decoded.email) : null;

    // Prefer custom claim role; default to CHURCH_USER
    const role: SessionUserRole =
      decoded?.role === 'SUPER_ADMIN' ? 'SUPER_ADMIN' : 'CHURCH_USER';

    return this.issue({ userId, email, role });
  }

  async verify(token: string): Promise<SessionUser> {
    const t = String(token || '').trim();
    if (!t) throw new UnauthorizedException('Missing session token');

    try {
      const payload: any = await this.jwt.verifyAsync(t, {
        secret: this.jwtSecret(),
      });

      const userId = String(payload?.sub || '').trim();
      if (!userId)
        throw new UnauthorizedException('Invalid session token (no sub)');

      const role: SessionUserRole =
        payload?.role === 'SUPER_ADMIN' ? 'SUPER_ADMIN' : 'CHURCH_USER';

      const email = payload?.email ? String(payload.email) : null;

      return { userId, email, role };
    } catch {
      throw new UnauthorizedException('Invalid or expired session token');
    }
  }
}
