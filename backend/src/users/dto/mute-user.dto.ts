import { IsBoolean, IsOptional } from 'class-validator';

export class MuteUserDto {
  @IsBoolean()
  isMuted: boolean;
}
