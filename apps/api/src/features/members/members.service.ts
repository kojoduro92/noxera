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
    
    // --- pagination coercion ---
    const page = Math.max(1, Number.parseInt(String(dto.page ?? 1), 10) || 1);
    const pageSize = Math.min(200, Math.max(1, Number.parseInt(String(dto.pageSize ?? 20), 10) || 20));
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
      } as any,
    });
  }
}
