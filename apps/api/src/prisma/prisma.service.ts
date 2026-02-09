import 'dotenv/config';
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';

function buildMariaDbAdapter(databaseUrl: string) {
  // Try the "url" style first (some versions support it)
  try {
    const u = new URL(databaseUrl);
    const host = u.hostname;
    const port = Number(u.port || '3306');
    const user = decodeURIComponent(u.username || '');
    const password = decodeURIComponent(u.password || '');
    const database = (u.pathname || '').replace(/^\//, '');
    const connectionLimit = Number(process.env.DB_POOL_SIZE || '5');

    if (!user || !database) {
      throw new Error('DATABASE_URL missing username or database name');
    }

    return new PrismaMariaDb({
      host,
      port,
      user,
      password,
      database,
      connectionLimit,
    } as any);
  } catch {}

  // Fallback: parse DATABASE_URL into discrete fields
  try {
    const u = new URL(databaseUrl);
    const host = u.hostname;
    const port = Number(u.port || '3306');
    const user = decodeURIComponent(u.username || '');
    const password = decodeURIComponent(u.password || '');
    const database = (u.pathname || '').replace(/^\//, '');
    const connectionLimit = Number(process.env.DB_POOL_SIZE || '5');

    return new PrismaMariaDb({
      host,
      port,
      user,
      password,
      database,
      connectionLimit,
    } as any);
  } catch (e: any) {
    throw new Error(
      'Failed to init PrismaMariaDb adapter. Check DATABASE_URL format. ' +
        (e?.message ? `(${e.message})` : ''),
    );
  }
}

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor() {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error('Missing DATABASE_URL in apps/api/.env');

    // If adapter init fails for any reason, Prisma may still work with super()
    // but in Rust-free setups it needs an adapter.
    let adapter: any = null;
    try {
      adapter = buildMariaDbAdapter(url);
    } catch (e: any) {
      // Last resort: try Prisma default engine
      // (If you're using Rust-free Prisma, this will throw again and that's OK)
      super();
      return;
    }

    super({ adapter });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
