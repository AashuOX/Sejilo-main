import { IsString, IsOptional } from 'class-validator';

export class BlockUserDto {
  @IsString()
  @IsOptional()
  reason?: string;

  @IsString()
  @IsOptional()
  reportReason?: string;

  @IsString()
  @IsOptional()
  reportDetails?: string;
}
