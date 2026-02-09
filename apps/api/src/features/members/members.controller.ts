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
