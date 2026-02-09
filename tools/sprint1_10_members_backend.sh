#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEMA="apps/api/prisma/schema.prisma"
APP_MOD="apps/api/src/app.module.ts"

test -f "$SCHEMA" || { echo "❌ Missing $SCHEMA"; exit 1; }
test -f "$APP_MOD" || { echo "❌ Missing $APP_MOD"; exit 1; }

echo "✅ Repo root: $ROOT"

# --- 1) Patch Prisma schema: add enums + Member model (id type matches Tenant.id)
node <<'NODE'
const fs = require("fs");

const schemaPath = "apps/api/prisma/schema.prisma";
let s = fs.readFileSync(schemaPath, "utf8");

if (/model\s+Member\s*\{/.test(s)) {
  console.log("ℹ️ Prisma schema already has model Member; skipping schema patch.");
  process.exit(0);
}

const tenantMatch = s.match(/model\s+Tenant\s*\{[\s\S]*?\n\}/);
if (!tenantMatch) {
  console.error("❌ Could not find `model Tenant { ... }` in schema.prisma");
  process.exit(1);
}
const tenantBlock = tenantMatch[0];
const idLine = tenantBlock.split("\n").find(l => /^\s*id\s+/.test(l));
if (!idLine) {
  console.error("❌ Could not find `id ...` inside model Tenant");
  process.exit(1);
}
const idType = idLine.trim().split(/\s+/)[1]; // String / Int / BigInt etc
const isStringId = idType === "String";
const memberIdField = isStringId
  ? `  id        String   @id @default(cuid())`
  : `  id        Int      @id @default(autoincrement())`;

const tenantIdField = `  tenantId  ${idType}`;
const deletedByField = isStringId
  ? `  deletedByUserId String?`
  : `  deletedByUserId ${idType}?`;

const hasMemberStatus = /\benum\s+MemberStatus\b/.test(s);
const hasMemberGender = /\benum\s+MemberGender\b/.test(s);

let add = "\n\n// =============================================\n// Sprint 1: Members (Membership CRM foundation)\n// =============================================\n\n";
if (!hasMemberStatus) {
  add += `enum MemberStatus {\n  ACTIVE\n  INACTIVE\n  TRANSFERRED\n  DECEASED\n}\n\n`;
}
if (!hasMemberGender) {
  add += `enum MemberGender {\n  MALE\n  FEMALE\n  OTHER\n}\n\n`;
}

add += `model Member {\n`;
add += `${memberIdField}\n`;
add += `${tenantIdField}\n\n`;
add += `  firstName String\n  lastName  String\n  otherNames String?\n\n`;
add += `  gender   MemberGender?\n  status   MemberStatus  @default(ACTIVE)\n\n`;
add += `  dob      DateTime?\n  phone    String?\n  email    String?\n  address  String?\n\n`;
add += `  photoUrl String?\n  notes    String?\n  tagsCsv  String? // comma-separated tags (safe across Postgres/MySQL)\n\n`;
add += `  createdAt DateTime @default(now())\n  updatedAt DateTime @updatedAt\n\n`;
add += `  deletedAt DateTime?\n`;
add += `${deletedByField}\n\n`;
add += `  tenant   Tenant   @relation(fields: [tenantId], references: [id], onDelete: Cascade)\n\n`;
add += `  @@index([tenantId, status])\n  @@index([tenantId, lastName, firstName])\n  @@index([tenantId, createdAt])\n}\n`;

s = s.trimEnd() + add + "\n";
fs.writeFileSync(schemaPath, s, "utf8");
console.log("✅ Added Member model to prisma schema (id type:", idType + ")");
NODE

# --- 2) Migrate + generate Prisma client
echo ""
echo "▶ Prisma migrate (dev) + generate"
pnpm --filter api db:migrate -- --name sprint1_members
pnpm --filter api db:generate

# --- 3) Create Members module (NestJS)
mkdir -p apps/api/src/members/dto

cat > apps/api/src/members/dto/create-member.dto.ts <<'EOF'
import { IsDateString, IsEmail, IsEnum, IsOptional, IsString } from "class-validator";

export enum MemberStatus {
  ACTIVE = "ACTIVE",
  INACTIVE = "INACTIVE",
  TRANSFERRED = "TRANSFERRED",
  DECEASED = "DECEASED",
}

export enum MemberGender {
  MALE = "MALE",
  FEMALE = "FEMALE",
  OTHER = "OTHER",
}

export class CreateMemberDto {
  @IsString()
  firstName!: string;

  @IsString()
  lastName!: string;

  @IsOptional()
  @IsString()
  otherNames?: string;

  @IsOptional()
  @IsEnum(MemberGender)
  gender?: MemberGender;

  @IsOptional()
  @IsEnum(MemberStatus)
  status?: MemberStatus;

  @IsOptional()
  @IsDateString()
  dob?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsOptional()
  @IsString()
  photoUrl?: string;

  @IsOptional()
  @IsString()
  notes?: string;

  // comma-separated tags; e.g. "choir,leaders,new"
  @IsOptional()
  @IsString()
  tagsCsv?: string;
}
EOF

cat > apps/api/src/members/dto/update-member.dto.ts <<'EOF'
import { PartialType } from "@nestjs/mapped-types";
import { CreateMemberDto } from "./create-member.dto";

export class UpdateMemberDto extends PartialType(CreateMemberDto) {}
EOF

cat > apps/api/src/members/members.service.ts <<'EOF'
import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import type { Member, Prisma } from "@prisma/client";
import { CreateMemberDto, MemberStatus } from "./dto/create-member.dto";
import { UpdateMemberDto } from "./dto/update-member.dto";

type ListQuery = {
  q?: string;
  status?: string;
  page?: string | number;
  pageSize?: string | number;
  includeDeleted?: string;
  sort?: string; // e.g. "createdAt.desc"
};

function toInt(v: unknown, def: number) {
  const n = typeof v === "string" ? Number(v) : typeof v === "number" ? v : def;
  return Number.isFinite(n) ? n : def;
}

@Injectable()
export class MembersService {
  constructor(private readonly prisma: PrismaService) {}

  private pickTenantId(req: any): string {
    const fromUser = req?.user?.tenantId ?? req?.user?.tenant?.id;
    const fromHeader = req?.headers?.["x-tenant-id"];
    const tenantId = (fromUser ?? fromHeader ?? "").toString().trim();
    if (!tenantId) {
      throw new BadRequestException(
        "Missing tenantId. In dev you can pass x-tenant-id header, or ensure session provides req.user.tenantId."
      );
    }
    return tenantId;
  }

  private pickActorUserId(req: any): string | null {
    const v = req?.user?.id ?? req?.user?.userId ?? req?.user?.sub ?? req?.headers?.["x-user-id"];
    const s = v ? v.toString().trim() : "";
    return s || null;
  }

  private async audit(req: any, action: string, entityId: string, meta?: Record<string, unknown>) {
    // Keep audit best-effort so it never blocks core flows.
    const tenantId = this.pickTenantId(req);
    const actorUserId = this.pickActorUserId(req);
    try {
      await this.prisma.auditLog.create({
        data: {
          tenantId,
          action,
          entityType: "Member",
          entityId,
          actorUserId,
          metadata: meta ?? {},
        } as any,
      });
    } catch {
      // ignore
    }
  }

  async list(req: any, query: ListQuery) {
    const tenantId = this.pickTenantId(req);

    const page = Math.max(1, toInt(query.page, 1));
    const pageSize = Math.min(100, Math.max(1, toInt(query.pageSize, 20)));
    const skip = (page - 1) * pageSize;

    const includeDeleted = String(query.includeDeleted ?? "false") === "true";

    const where: Prisma.MemberWhereInput = {
      tenantId,
      ...(includeDeleted ? {} : { deletedAt: null }),
    };

    if (query.status) {
      // Prisma enum expects exact string; keep safe by validating known values
      const s = String(query.status).toUpperCase();
      if (Object.values(MemberStatus).includes(s as MemberStatus)) {
        where.status = s as any;
      }
    }

    const q = (query.q ?? "").toString().trim();
    if (q) {
      where.OR = [
        { firstName: { contains: q, mode: "insensitive" } },
        { lastName: { contains: q, mode: "insensitive" } },
        { otherNames: { contains: q, mode: "insensitive" } },
        { phone: { contains: q, mode: "insensitive" } },
        { email: { contains: q, mode: "insensitive" } },
      ];
    }

    // Sorting
    let orderBy: Prisma.MemberOrderByWithRelationInput = { createdAt: "desc" };
    const sort = (query.sort ?? "").toString().trim();
    if (sort) {
      const [field, dir] = sort.split(".");
      const direction = dir === "asc" ? "asc" : "desc";
      if (["createdAt", "updatedAt", "lastName", "firstName", "status"].includes(field)) {
        orderBy = { [field]: direction } as any;
      }
    }

    const [total, items] = await Promise.all([
      this.prisma.member.count({ where }),
      this.prisma.member.findMany({
        where,
        orderBy,
        skip,
        take: pageSize,
      }),
    ]);

    return { page, pageSize, total, items };
  }

  async get(req: any, id: string): Promise<Member> {
    const tenantId = this.pickTenantId(req);

    const found = await this.prisma.member.findFirst({
      where: { id, tenantId, deletedAt: null },
    });

    if (!found) throw new NotFoundException("Member not found");
    return found;
  }

  async create(req: any, dto: CreateMemberDto): Promise<Member> {
    const tenantId = this.pickTenantId(req);

    const created = await this.prisma.member.create({
      data: {
        tenantId,
        firstName: dto.firstName,
        lastName: dto.lastName,
        otherNames: dto.otherNames ?? null,
        gender: (dto.gender as any) ?? null,
        status: (dto.status as any) ?? undefined,
        dob: dto.dob ? new Date(dto.dob) : null,
        phone: dto.phone ?? null,
        email: dto.email ?? null,
        address: dto.address ?? null,
        photoUrl: dto.photoUrl ?? null,
        notes: dto.notes ?? null,
        tagsCsv: dto.tagsCsv ?? null,
      } as any,
    });

    await this.audit(req, "members.create", String(created.id), { name: `${created.firstName} ${created.lastName}` });
    return created;
  }

  async update(req: any, id: string, dto: UpdateMemberDto): Promise<Member> {
    const tenantId = this.pickTenantId(req);

    const existing = await this.prisma.member.findFirst({ where: { id, tenantId, deletedAt: null } });
    if (!existing) throw new NotFoundException("Member not found");

    const updated = await this.prisma.member.update({
      where: { id } as any,
      data: {
        firstName: dto.firstName ?? undefined,
        lastName: dto.lastName ?? undefined,
        otherNames: dto.otherNames ?? undefined,
        gender: (dto.gender as any) ?? undefined,
        status: (dto.status as any) ?? undefined,
        dob: dto.dob ? new Date(dto.dob) : undefined,
        phone: dto.phone ?? undefined,
        email: dto.email ?? undefined,
        address: dto.address ?? undefined,
        photoUrl: dto.photoUrl ?? undefined,
        notes: dto.notes ?? undefined,
        tagsCsv: dto.tagsCsv ?? undefined,
      } as any,
    });

    await this.audit(req, "members.update", String(updated.id));
    return updated;
  }

  async softDelete(req: any, id: string) {
    const tenantId = this.pickTenantId(req);

    const existing = await this.prisma.member.findFirst({ where: { id, tenantId, deletedAt: null } });
    if (!existing) throw new NotFoundException("Member not found");

    const actorUserId = this.pickActorUserId(req);

    const updated = await this.prisma.member.update({
      where: { id } as any,
      data: {
        deletedAt: new Date(),
        deletedByUserId: actorUserId as any,
      } as any,
    });

    await this.audit(req, "members.delete", String(updated.id));
    return { ok: true };
  }
}
EOF

cat > apps/api/src/members/members.controller.ts <<'EOF'
import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from "@nestjs/common";
import type { Request } from "express";
import { SessionGuard } from "../auth/session/session.guard";
import { CreateMemberDto } from "./dto/create-member.dto";
import { UpdateMemberDto } from "./dto/update-member.dto";
import { MembersService } from "./members.service";

@Controller("members")
@UseGuards(SessionGuard)
export class MembersController {
  constructor(private readonly svc: MembersService) {}

  @Get()
  list(@Req() req: Request, @Query() query: any) {
    return this.svc.list(req as any, query);
  }

  @Get(":id")
  get(@Req() req: Request, @Param("id") id: string) {
    return this.svc.get(req as any, id);
  }

  @Post()
  create(@Req() req: Request, @Body() dto: CreateMemberDto) {
    return this.svc.create(req as any, dto);
  }

  @Patch(":id")
  update(@Req() req: Request, @Param("id") id: string, @Body() dto: UpdateMemberDto) {
    return this.svc.update(req as any, id, dto);
  }

  @Delete(":id")
  remove(@Req() req: Request, @Param("id") id: string) {
    return this.svc.softDelete(req as any, id);
  }
}
EOF

cat > apps/api/src/members/members.module.ts <<'EOF'
import { Module } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import { MembersController } from "./members.controller";
import { MembersService } from "./members.service";

@Module({
  controllers: [MembersController],
  providers: [MembersService, PrismaService],
})
export class MembersModule {}
EOF

# --- 4) Patch AppModule to include MembersModule
node <<'NODE'
const fs = require("fs");

const p = "apps/api/src/app.module.ts";
let s = fs.readFileSync(p, "utf8");

if (!s.includes("MembersModule")) {
  // add import
  if (!s.includes(`from "./members/members.module"`)) {
    s = s.replace(
      /(import[\s\S]*?\n)(@Module\s*\()/m,
      (m, imports, moduleDec) => {
        return (
          imports +
          `import { MembersModule } from "./members/members.module";\n` +
          moduleDec
        );
      }
    );
  }

  // add to imports array
  s = s.replace(/imports\s*:\s*\[([\s\S]*?)\]/m, (m, inner) => {
    if (inner.includes("MembersModule")) return m;
    // Insert near the top of the imports list for clarity
    const trimmed = inner.trimEnd();
    return `imports: [\n    MembersModule,\n    ${trimmed.replace(/^\s+/, "")}\n  ]`;
  });

  fs.writeFileSync(p, s, "utf8");
  console.log("✅ Patched AppModule to include MembersModule");
} else {
  console.log("ℹ️ AppModule already includes MembersModule; skipping.");
}
NODE

echo ""
echo "▶ Build + lint API"
pnpm --filter api lint
pnpm --filter api build

echo ""
echo "✅ Sprint 1 Members backend ready."
echo "NEXT:"
echo "  pnpm --filter api dev"
echo "  # then test with curl (see instructions in chat)"
