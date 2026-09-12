import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { MediaPayloadDto } from '../../common/dto/media-payload.dto';

export class UpdateProfileDto {
  @ApiProperty({ required: false, example: 'john_doe', description: 'Updated unique username' })
  @IsString()
  @MinLength(2)
  @MaxLength(30)
  @IsOptional()
  username?: string;

  @ApiProperty({ required: false, example: 'John Doe', description: 'Updated display name' })
  @IsString()
  @MaxLength(50)
  @IsOptional()
  displayName?: string;

  @ApiProperty({ required: false, example: 'Software engineer & privacy advocate', description: 'Updated bio' })
  @IsString()
  @MaxLength(500)
  @IsOptional()
  bio?: string;

  // Nullable on purpose: an explicit `null` clears the avatar, which is how the
  // client removes a profile picture. class-validator skips @IsOptional fields
  // for both undefined and null, so the nested rules only apply to real objects.
  @ApiProperty({ type: MediaPayloadDto, required: false, nullable: true, description: 'Updated avatar media, or null to remove it' })
  @IsOptional()
  @IsObject({ message: 'avatar must be an object with mimeType and data, or null.' })
  @ValidateNested()
  @Type(() => MediaPayloadDto)
  avatar?: MediaPayloadDto | null;

  @ApiProperty({ required: false, description: 'Whether the profile is private (only followers see content)' })
  @IsBoolean()
  @IsOptional()
  isPrivate?: boolean;

  @ApiProperty({ required: false, example: '1990-01-01', description: 'Updated birth date (YYYY-MM-DD)' })
  @IsString()
  @IsOptional()
  birthDate?: string;
}
