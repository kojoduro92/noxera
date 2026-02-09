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
