import { ApiProperty } from '@nestjs/swagger';
import { IsArray, IsEnum, IsNotEmpty, IsOptional, IsString } from 'class-validator';

export enum ConversationKind {
  Direct = 'direct',
  Group = 'group',
}

export class CreateConversationDto {
  @ApiProperty({ enum: ConversationKind, example: 'direct', description: 'Kind of conversation' })
  @IsEnum(ConversationKind)
  kind: ConversationKind;

  @ApiProperty({ required: false, description: 'Target user ID for direct 1-on-1 chat' })
  @IsString()
  @IsOptional()
  recipientUserId?: string;

  @ApiProperty({ required: false, example: 'Sejilo Core Team', description: 'Title for group conversation' })
  @IsString()
  @IsOptional()
  title?: string;

  @ApiProperty({ required: false, description: 'List of member user IDs for group chat' })
  @IsArray()
  @IsOptional()
  memberUserIds?: string[];
}
