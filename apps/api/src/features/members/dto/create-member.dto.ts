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

}
