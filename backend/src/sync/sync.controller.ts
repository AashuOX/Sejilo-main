import {
  Body,
  Controller,
  Get,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { SyncRequestDto } from './dto/sync-request.dto';
import { SyncService } from './sync.service';

@ApiTags('Sync Engine (Offline-First)')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
@Controller('v1/sync')
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  @Get()
  @ApiOperation({ summary: 'Incremental sync of messages and state since last cursor' })
  async getSync(
    @CurrentUser('userId') userId: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.syncService.sync(userId, { lastSyncCursor: cursor });
  }

  @Post()
  @ApiOperation({ summary: 'Submit pending offline messages and receive incremental updates' })
  async postSync(
    @CurrentUser('userId') userId: string,
    @Body() dto: SyncRequestDto,
  ) {
    return this.syncService.sync(userId, dto);
  }
}
