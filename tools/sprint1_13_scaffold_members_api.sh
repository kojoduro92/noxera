#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
test -f package.json || { echo "Run from repo root"; exit 1; }

API="apps/api"
SRC="$API/src"
FEATURES="$SRC/features"
MODDIR="$FEATURES/members"

mkdir -p "$MODDIR/dto"

write_if_missing () {
  local path="$1"
  shift
  if [ -f "$path" ]; then
    echo "ℹ️  Exists, skipping: $path"
    return 0
  fi
  cat > "$path" <<'EOF'
'"$@"'
EOF
}

# 1) DTOs + types
if [ ! -f "$MODDIR/member-status.ts" ]; then
cat > "$MODDIR/member-status.ts" <<'EOF'
export const MEMBER_STATUSES = ["ACTIVE", "INACTIVE", "TRANSFERRED", "DECEASED"] as const;
export type MemberStatus = (typeof MEMBER_STATUSES)[number];
EOF
echo "✅ Wrote $MODDIR/member-status.ts"
fi

if [ ! -f "$MODDIR/dto/list-members.dto.ts" ]; then
cat > "$MODDIR/dto/list-members.dto.ts" <<'EOF'
import { IsIn, IsInt, IsOptional, IsString, Min } from "class-validator";
import { Type } from "class-transformer";
import { MEMBER_STATUSES } from "../member-status";

export class ListMembersDto {
  @IsOptional()
  @IsString()
  q?: string;

  @IsOptional()
  @IsIn(MEMBER_STATUSES as unknown as string[])
  status?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  pageSize?: number = 20;
}
EOF
echo "✅ Wrote $MODDIR/dto/list-members.dto.ts"
fi

if [ ! -f "$MODDIR/dto/create-member.dto.ts" ]; then
cat > "$MODDIR/dto/create-member.dto.ts" <<'EOF'
import { IsEmail, IsIn, IsOptional, IsString } from "class-validator";
import { MEMBER_STATUSES } from "../member-status";

export class CreateMemberDto {
  @IsString()
  firstName!: string;

  @IsString()
  lastName!: string;

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
  @IsIn(MEMBER_STATUSES as unknown as string[])
  status?: string; // ACTIVE/INACTIVE/TRANSFERRED/DECEASED

  @IsOptional()
  @IsString()
  branchId?: string;
}
EOF
echo "✅ Wrote $MODDIR/dto/create-member.dto.ts"
fi

if [ ! -f "$MODDIR/dto/update-member.dto.ts" ]; then
cat > "$MODDIR/dto/update-member.dto.ts" <<'EOF'
import { PartialType } from "@nestjs/mapped-types";
import { CreateMemberDto } from "./create-member.dto";

export class UpdateMemberDto extends PartialType(CreateMemberDto) {}
EOF
echo "✅ Wrote $MODDIR/dto/update-member.dto.ts"
fi

# 2) Service
if [ ! -f "$MODDIR/members.service.ts" ]; then
cat > "$MODDIR/members.service.ts" <<'EOF'
import { Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service";
import { CreateMemberDto } from "./dto/create-member.dto";
import { UpdateMemberDto } from "./dto/update-member.dto";
import { ListMembersDto } from "./dto/list-members.dto";

@Injectable()
export class MembersService {
  constructor(private readonly prisma: PrismaService) {}

  private tenantWhere(tenantId: string) {
    // We KNOW tenantId exists (your earlier Prisma error referenced it).
    return { tenantId } as const;
  }

  async list(tenantId: string, dto: ListMembersDto) {
    const page = dto.page ?? 1;
    const pageSize = dto.pageSize ?? 20;
    const skip = (page - 1) * pageSize;

    const q = dto.q?.trim();
    const status = dto.status?.trim();

    const where: any = {
      ...this.tenantWhere(tenantId),
    };

    if (status) where.status = status;

    if (q) {
      // Keep this conservative to avoid guessing schema fields.
      // If your Member model has these fields, it will work; if not, remove/adjust quickly.
      where.OR = [
        { firstName: { contains: q, mode: "insensitive" } },
        { lastName: { contains: q, mode: "insensitive" } },
        { phone: { contains: q, mode: "insensitive" } },
        { email: { contains: q, mode: "insensitive" } },
      ];
    }

    const [items, total] = await Promise.all([
      this.prisma.member.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip,
        take: pageSize,
      }),
      this.prisma.member.count({ where }),
    ]);

    return {
      page,
      pageSize,
      total,
      items,
    };
  }

  async get(tenantId: string, id: string) {
    const row = await this.prisma.member.findFirst({
      where: { ...this.tenantWhere(tenantId), id },
    });
    if (!row) throw new NotFoundException("Member not found");
    return row;
  }

  async create(tenantId: string, dto: CreateMemberDto) {
    return this.prisma.member.create({
      data: {
        tenantId,
        firstName: dto.firstName,
        lastName: dto.lastName,
        phone: dto.phone ?? null,
        email: dto.email ?? null,
        address: dto.address ?? null,
        status: dto.status ?? "ACTIVE",
        branchId: dto.branchId ?? null,
      } as any,
    });
  }

  async update(tenantId: string, id: string, dto: UpdateMemberDto) {
    // Ensure exists in tenant
    await this.get(tenantId, id);

    return this.prisma.member.update({
      where: { id } as any,
      data: {
        firstName: dto.firstName,
        lastName: dto.lastName,
        phone: dto.phone ?? undefined,
        email: dto.email ?? undefined,
        address: dto.address ?? undefined,
        status: dto.status ?? undefined,
        branchId: dto.branchId ?? undefined,
      } as any,
    });
  }
}
EOF
echo "✅ Wrote $MODDIR/members.service.ts"
fi

# 3) Controller
if [ ! -f "$MODDIR/members.controller.ts" ]; then
cat > "$MODDIR/members.controller.ts" <<'EOF'
import { Body, Controller, Get, Param, Patch, Post, Query, Req } from "@nestjs/common";
import { MembersService } from "./members.service";
import { ListMembersDto } from "./dto/list-members.dto";
import { CreateMemberDto } from "./dto/create-member.dto";
import { UpdateMemberDto } from "./dto/update-member.dto";

function resolveTenantId(req: any): string {
  // Prefer your real tenant context if it already exists
  if (req?.tenantId) return String(req.tenantId);

  // Temporary fallback for local testing
  const h = req?.headers?.["x-tenant-id"] ?? req?.headers?.["X-TENANT-ID"];
  if (h) return String(Array.isArray(h) ? h[0] : h);

  throw new Error("Tenant context missing. Provide x-tenant-id header (dev) or ensure tenant middleware is enabled.");
}

@Controller("members")
export class MembersController {
  constructor(private readonly members: MembersService) {}

  @Get()
  list(@Req() req: any, @Query() q: ListMembersDto) {
    const tenantId = resolveTenantId(req);
    return this.members.list(tenantId, q);
  }

  @Get(":id")
  get(@Req() req: any, @Param("id") id: string) {
    const tenantId = resolveTenantId(req);
    return this.members.get(tenantId, id);
  }

  @Post()
  create(@Req() req: any, @Body() dto: CreateMemberDto) {
    const tenantId = resolveTenantId(req);
    return this.members.create(tenantId, dto);
  }

  @Patch(":id")
  update(@Req() req: any, @Param("id") id: string, @Body() dto: UpdateMemberDto) {
    const tenantId = resolveTenantId(req);
    return this.members.update(tenantId, id, dto);
  }
}
EOF
echo "✅ Wrote $MODDIR/members.controller.ts"
fi

# 4) Module
if [ ! -f "$MODDIR/members.module.ts" ]; then
cat > "$MODDIR/members.module.ts" <<'EOF'
import { Module } from "@nestjs/common";
import { MembersController } from "./members.controller";
import { MembersService } from "./members.service";

@Module({
  controllers: [MembersController],
  providers: [MembersService],
  exports: [MembersService],
})
export class MembersModule {}
EOF
echo "✅ Wrote $MODDIR/members.module.ts"
fi

# 5) Wire into FeaturesModule or AppModule
PATCH_TARGET=""
REL_IMPORT=""

if [ -f "$FEATURES/features.module.ts" ]; then
  PATCH_TARGET="$FEATURES/features.module.ts"
  REL_IMPORT="./members/members.module"
else
  PATCH_TARGET="$SRC/app.module.ts"
  REL_IMPORT="./features/members/members.module"
fi

node - <<'NODE' "$PATCH_TARGET" "$REL_IMPORT"
const fs = require("fs");
const [file, rel] = process.argv.slice(1);
let s = fs.readFileSync(file, "utf8");

if (!s.includes("MembersModule")) {
  // Add import
  const importLine = `import { MembersModule } from "${rel}";\n`;
  // Put it after the last import
  const lastImportIdx = s.lastIndexOf("import ");
  const insertAt = s.indexOf("\n", lastImportIdx);
  s = s.slice(0, insertAt + 1) + importLine + s.slice(insertAt + 1);

  // Add to imports: [...]
  const m = s.match(/imports\s*:\s*\[/);
  if (m) {
    const idx = m.index + m[0].length;
    s = s.slice(0, idx) + "\n    MembersModule," + s.slice(idx);
  } else {
    console.warn("⚠️ Could not auto-insert MembersModule into imports[]. Please add it manually.");
  }

  fs.writeFileSync(file, s);
  console.log(`✅ Wired MembersModule into: ${file}`);
} else {
  console.log(`ℹ️ MembersModule already wired in: ${file}`);
}
NODE

echo ""
echo "NEXT:"
echo "  pnpm --filter api lint"
echo "  pnpm --filter api build"
