import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsString, IsDate } from 'class-validator';
import { Transform } from 'class-transformer';

/**
 * One of `idToken` or `accessToken` must be present: they are the only fields
 * the server derives identity from. `email` and `googleId` are accepted for
 * backwards compatibility with older clients and are ignored — trusting them
 * would let any caller sign in as any account.
 */
export class GoogleLoginDto {
  @ApiProperty({ required: false, description: 'Google ID token' })
  @IsString()
  @IsOptional()
  idToken?: string;

  @ApiProperty({ required: false, description: 'Google OAuth access token' })
  @IsString()
  @IsOptional()
  accessToken?: string;

  @ApiProperty({
    required: false,
    example: 'user@gmail.com',
    description: 'Ignored. The email is read from the verified token instead.',
  })
  @IsString()
  @IsOptional()
  email?: string;

  @ApiProperty({ required: false, example: 'John Doe', description: 'Google display name' })
  @IsString()
  @IsOptional()
  displayName?: string;

  @ApiProperty({
    required: false,
    description: 'Ignored. The subject is read from the verified token instead.',
  })
  @IsString()
  @IsOptional()
  googleId?: string;

  @ApiProperty({ required: false, description: 'Google avatar URL' })
  @IsString()
  @IsOptional()
  photoUrl?: string;

  @ApiProperty({ required: false, example: '1990-01-01', description: 'Date of birth (YYYY-MM-DD)' })
  @IsDate()
  @Transform(({ value }) => value ? new Date(value) : undefined)
  @IsOptional()
  dateOfBirth?: Date;
}
