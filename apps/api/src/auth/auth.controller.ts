import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { SessionService } from './session/session.service';
import { SessionGuard } from './session/session.guard';

type SessionBody = { idToken: string } | { dev: true };

@Controller('auth')
export class AuthController {
  constructor(private readonly sessions: SessionService) {}

  @Post('session')
  async createSession(
    @Body() body: SessionBody,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result =
      'idToken' in body
        ? await this.sessions.createSessionFromFirebase(body.idToken)
        : await this.sessions.createDevSession();

    res.cookie('noxera_session', result.token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: false,
      path: '/',
      maxAge: 7 * 24 * 60 * 60 * 1000,
    });

    return result;
  }

  @UseGuards(SessionGuard)
  @Get('me')
  me(@Req() req: Request & { user?: any }) {
    return { user: req.user };
  }
}
