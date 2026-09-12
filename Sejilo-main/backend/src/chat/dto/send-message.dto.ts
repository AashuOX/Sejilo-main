import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsString, IsEnum } from 'class-validator';

export class SendMessageDto {
  @ApiProperty({ required: false, example: 'Hello from SejiloChat!', description: 'Text message content' })
  @IsString()
  @IsOptional()
  text?: string;

  @ApiProperty({ required: false, description: 'Media attachment payload' })
  @IsOptional()
  media?: any;

  @ApiProperty({ required: false, description: 'ID of message being replied to' })
  @IsString()
  @IsOptional()
  replyToMessageId?: string;

  @ApiProperty({ required: false, description: 'Client-generated UUID for deduplication' })
  @IsString()
  @IsOptional()
  clientMessageId?: string;

  @ApiProperty({
    required: false,
    description: 'Message expiration time (disappears after specified duration)',
    enum: ['1m', '5m', '1h', '24h', '7d'],
  })
  @IsEnum(['1m', '5m', '1h', '24h', '7d'])
  @IsOptional()
  expiresIn?: string;
}

