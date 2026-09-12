import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsObject, IsOptional, IsString, ValidateNested } from 'class-validator';
import { MediaPayloadDto } from '../../common/dto/media-payload.dto';

export class CreateStoryDto {
  @ApiProperty({ example: 'image', description: 'Story type: image, video or text' })
  @IsString()
  @IsIn(['image', 'video', 'text'], {
    message: 'type must be one of: image, video, text.',
  })
  type: string;

  @ApiProperty({ type: MediaPayloadDto, required: false, description: 'Story media object' })
  @IsOptional()
  @IsObject({ message: 'media must be an object with mimeType and data.' })
  @ValidateNested()
  @Type(() => MediaPayloadDto)
  media?: MediaPayloadDto;

  @ApiProperty({ required: false, example: 'Today is a great day!', description: 'Text story content' })
  @IsString()
  @IsOptional()
  textContent?: string;

  @ApiProperty({ required: false, example: 'linear-gradient(135deg, #833AB4, #E1306C)', description: 'Background gradient CSS' })
  @IsString()
  @IsOptional()
  backgroundStyle?: string;
}
