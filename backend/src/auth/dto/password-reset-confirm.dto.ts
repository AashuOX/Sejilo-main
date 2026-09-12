import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

export class PasswordResetConfirmDto {
  @ApiProperty({ description: 'Password reset token received via email' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(256)
  token: string;

  @ApiProperty({ example: 'NewSecurePassword123!', minLength: 8, maxLength: 128, description: 'New password' })
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  newPassword: string;
}
