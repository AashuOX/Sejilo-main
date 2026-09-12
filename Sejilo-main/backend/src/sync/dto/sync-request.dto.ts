import { ApiProperty } from '@nestjs/swagger';
import { IsArray, IsOptional, IsString } from 'class-validator';

export class SyncRequestDto {
  @ApiProperty({ required: false, example: '0', description: 'Cursor timestamp or sequence number' })
  @IsString()
  @IsOptional()
  lastSyncCursor?: string;

  @ApiProperty({ required: false, description: 'Pending offline messages to be committed to backend' })
  @IsArray()
  @IsOptional()
  pendingMessages?: Array<{
    clientMessageId: string;
    conversationId: string;
    text?: string;
    media?: any;
    replyToMessageId?: string;
    createdAt: string;
    updatedAt?: string;
    deleted?: boolean;
    expiresIn?: '1m' | '5m' | '1h' | '24h' | '7d';
  }>;

  @ApiProperty({ required: false, description: 'List of known message IDs already stored locally' })
  @IsArray()
  @IsOptional()
  knownMessageIds?: string[];
}
