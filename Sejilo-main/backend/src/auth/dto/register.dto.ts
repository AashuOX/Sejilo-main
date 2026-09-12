import { ApiProperty } from '@nestjs/swagger';
import { IsEmail, IsNotEmpty, IsOptional, IsString, IsDate, Matches, MaxLength, MinLength } from 'class-validator';
import { Transform } from 'class-transformer';

export class RegisterDto {
  @ApiProperty({ example: 'user@sejilo.app', description: 'User email address' })
  @IsEmail()
  @MaxLength(254)
  email: string;

  // bcrypt only reads the first 72 bytes, so a longer password buys no security
  // while an unbounded one lets a caller spend server CPU on hashing at will.
  @ApiProperty({ example: 'SecurePassword123!', minLength: 8, maxLength: 128, description: 'User password' })
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password: string;

  // Only enforced on new signups. Existing accounts predate this rule and must
  // stay able to edit their profile, so UpdateProfileDto caps length without
  // imposing a character set.
  @ApiProperty({ example: 'johndoe', description: 'Unique username' })
  @IsString()
  @IsNotEmpty()
  @MinLength(2)
  @MaxLength(30)
  @Matches(/^[A-Za-z0-9._]+$/, {
    message: 'Username may only contain letters, numbers, dots and underscores.',
  })
  username: string;

  @ApiProperty({ example: 'John Doe', description: 'Display name' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  displayName: string;

  @ApiProperty({ required: false, example: 'Hello world!', description: 'Bio description' })
  @IsString()
  @MaxLength(500)
  @IsOptional()
  bio?: string;

  @ApiProperty({ required: false, example: '1990-01-01', description: 'Date of birth (YYYY-MM-DD)' })
  @IsDate()
  @Transform(({ value }) => value ? new Date(value) : undefined)
  @IsOptional()
  dateOfBirth?: Date;
}
