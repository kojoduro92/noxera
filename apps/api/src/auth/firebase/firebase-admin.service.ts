import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import * as admin from 'firebase-admin';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

@Injectable()
export class FirebaseAdminService {
  private readonly log = new Logger(FirebaseAdminService.name);
  private configured = false;

  constructor() {
    const fromEnv = (process.env.FIREBASE_SERVICE_ACCOUNT_PATH || '').trim();
    const defaultPath = join(
      process.cwd(),
      '.secrets',
      'firebase.serviceAccount.json',
    );
    const candidates = [fromEnv, defaultPath].filter(Boolean);

    const found = candidates.find((p) => {
      try {
        return existsSync(p) && readFileSync(p, 'utf8').trim().length > 0;
      } catch {
        return false;
      }
    });

    if (!found) {
      this.log.warn(
        `Firebase Admin NOT configured. Dev auth will still work.\n` +
          `To enable Firebase auth: put service account JSON at ${defaultPath}\n` +
          `or set FIREBASE_SERVICE_ACCOUNT_PATH=/abs/path/to/serviceAccount.json`,
      );
      return;
    }

    try {
      const raw = readFileSync(found, 'utf8');
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
    if (!this.configured)
      throw new UnauthorizedException('Firebase Admin not configured on API');
    try {
      return await admin.auth().verifyIdToken(idToken);
    } catch {
      throw new UnauthorizedException('Invalid Firebase ID token');
    }
  }
}
