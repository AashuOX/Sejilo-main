import { ApiProperty } from '@nestjs/swagger';
import { IsEmail, IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class LoginDto {
  @ApiProperty({ example: 'user@sejilo.app', description: 'User email address or username' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(254)
  email: string;

  // Capped for the same reason as registration: bcrypt reads 72 bytes, so a
  // megabyte-long password is only ever a way to burn server CPU.
  @ApiProperty({ example: 'SecurePassword123!', maxLength: 128, description: 'User password' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  password: string;
}
