import { IsOptional, IsString, IsDateString, IsUUID, IsBoolean, Min, Max } from 'class-validator';

export class SearchMessagesDto {
  @IsString()
  @IsOptional()
  query?: string; // Full-text search query

  @IsUUID()
  @IsOptional()
  conversationId?: string; // Filter by conversation

  @IsUUID()
  @IsOptional()
  senderId?: string; // Filter by sender

  @IsDateString()
  @IsOptional()
  dateFrom?: string; // Filter messages from this date

  @IsDateString()
  @IsOptional()
  dateTo?: string; // Filter messages until this date

  @IsBoolean()
  @IsOptional()
  hasMedia?: boolean; // Filter messages with media

  @IsBoolean()
  @IsOptional()
  hasReactions?: boolean; // Filter messages with reactions

  @IsString()
  @IsOptional()
  messageType?: string; // 'text', 'image', 'video', 'audio', 'file'

  @Min(1)
  @Max(100)
  @IsOptional()
  limit?: number; // Default 20, max 100

  @Min(0)
  @IsOptional()
  offset?: number; // Pagination offset, default 0
}
