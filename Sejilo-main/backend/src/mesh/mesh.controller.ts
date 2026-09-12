import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MeshRelayService } from './mesh-relay.service';
import { RelayMessageDto } from './dto/relay-message.dto';

@ApiTags('Mesh Relay')
@Controller('v1/mesh')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class MeshController {
  constructor(private readonly relay: MeshRelayService) {}

  @Post('relay')
  @ApiOperation({ summary: 'Relay an encrypted mesh envelope to a destination user' })
  async postRelay(
    @CurrentUser('userId') userId: string,
    @Body() dto: RelayMessageDto,
  ) {
    return this.relay.relay(userId, dto);
  }

  @Get('inbox')
  @ApiOperation({ summary: 'Fetch and clear relayed envelopes addressed to you' })
  async getInbox(@CurrentUser('userId') userId: string) {
    return { messages: await this.relay.fetchInbox(userId) };
  }

  @Get('inbox/peek')
  @ApiOperation({ summary: 'Peek at relayed envelopes without clearing the inbox' })
  async peekInbox(@CurrentUser('userId') userId: string) {
    return { messages: await this.relay.peekInbox(userId) };
  }

  @Get('inbox/count')
  @ApiOperation({ summary: 'Count relayed envelopes awaiting pickup' })
  async inboxCount(@CurrentUser('userId') userId: string) {
    return { count: await this.relay.getInboxCount(userId) };
  }

  @Delete('inbox/:messageId')
  @ApiOperation({ summary: 'Acknowledge receipt of a specific relayed message' })
  async ackInbox(
    @CurrentUser('userId') userId: string,
    @Param('messageId') messageId: string,
  ) {
    return this.relay.acknowledge(userId, messageId);
  }
}
