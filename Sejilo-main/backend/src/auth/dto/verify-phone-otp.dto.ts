import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString, Matches, MaxLength, MinLength, IsDate } from 'class-validator';
import { Transform } from 'class-transformer';

export class VerifyPhoneOtpDto {
  @IsNotEmpty({ message: 'Phone number is required.' })
  @Matches(/^\+[1-9]\d{7,14}$/, {
    message: 'Phone number must be in E.164 format (e.g. +1234567890).',
  })
  phoneNumber: string;

  @IsNotEmpty({ message: 'Verification code is required.' })
  @Matches(/^\d{4,6}$/, { message: 'Code must be a 4-6 digit number.' })
  code: string;

  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(20)
  username?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(50)
  displayName?: string;

  @ApiProperty({ required: false, example: '1990-01-01', description: 'Date of birth (YYYY-MM-DD)' })
  @IsDate()
  @Transform(({ value }) => value ? new Date(value) : undefined)
  @IsOptional()
  dateOfBirth?: Date;
}