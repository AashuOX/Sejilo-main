import { ApiProperty } from '@nestjs/swagger';
import { IsEmail } from 'class-validator';

export class PasswordResetRequestDto {
  @ApiProperty({ example: 'user@sejilo.app', description: 'Account email address' })
  @IsEmail()
  email: string;
}
