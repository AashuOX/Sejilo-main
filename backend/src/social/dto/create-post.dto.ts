import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsNotEmpty, IsObject, IsOptional, IsString, ValidateNested } from 'class-validator';
import { MediaPayloadDto } from '../../common/dto/media-payload.dto';

export class CreatePostDto {
  @ApiProperty({ type: MediaPayloadDto, description: 'Media object containing base64url data and mimeType' })
  @IsNotEmpty()
  @IsObject({ message: 'media must be an object with mimeType and data.' })
  @ValidateNested()
  @Type(() => MediaPayloadDto)
  media: MediaPayloadDto;

  @ApiProperty({ required: false, example: 'A beautiful sunny day in the mountains!', description: 'Post caption' })
  @IsString()
  @IsOptional()
  caption?: string;

  @ApiProperty({ required: false, example: 'Kathmandu, Nepal', description: 'Location tag' })
  @IsString()
  @IsOptional()
  location?: string;
}
