import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

export class CreateCommentDto {
  @ApiProperty({ example: 'Great photo!', description: 'Comment text content' })
  @IsString()
  @IsNotEmpty()
  text: string;
}
