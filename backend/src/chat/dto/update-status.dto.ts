import { ApiProperty } from '@nestjs/swagger';
import { IsIn, IsString } from 'class-validator';

export class UpdateMessageStatusDto {
  @ApiProperty({ example: 'read', description: 'New message status: delivered, read' })
  @IsString()
  @IsIn(['delivered', 'read', 'DELIVERED', 'READ'])
  status: string;
}
