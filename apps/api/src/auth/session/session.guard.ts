import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { SessionService } from './session.service';

@Injectable()
export class SessionGuard implements CanActivate {
  constructor(private readonly sessions: SessionService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<Request & { user?: any }>();
    const token = this.extractToken(req);
    if (!token) throw new UnauthorizedException('Missing session');
    req.user = await this.sessions.verify(token);
    return true;
  }

  private extractToken(req: Request): string | null {
    // 1) Authorization: Bearer <token>
    const auth = req.headers['authorization'];
    if (typeof auth === 'string') {
      const m = auth.match(/^Bearer\s+(.+)$/i);
      if (m?.[1]) return m[1].trim();
    }

    // 2) cookie-parser (if installed): req.cookies.noxera_session
    const anyReq: any = req as any;
    const c = anyReq?.cookies?.noxera_session;
    if (typeof c === 'string' && c.trim()) return c.trim();

    // 3) Raw cookie header fallback
    const cookieHeader = req.headers['cookie'];
    if (typeof cookieHeader === 'string') {
      const m2 = cookieHeader.match(/(?:^|;\s*)noxera_session=([^;]+)/);
      if (m2?.[1]) return decodeURIComponent(m2[1]);
    }

    return null;
  }
}
