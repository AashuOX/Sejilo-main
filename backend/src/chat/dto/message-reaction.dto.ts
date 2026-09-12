import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

export class MessageReactionDto {
  @ApiProperty({ example: '❤️', description: 'Emoji reaction character' })
  @IsString()
  @IsNotEmpty()
  emoji: string;
}
