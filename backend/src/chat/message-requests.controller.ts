import {
  Controller,
  Get,
  Param,
  Post,
  Body,
  UseGuards,
  HttpCode,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MessageRequestsService } from './message-requests.service';

@ApiTags('Chat & Real-Time Messaging')
@Controller('v1/message-requests')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class MessageRequestsController {
  constructor(private readonly messageRequestsService: MessageRequestsService) {}

  @Get()
  @ApiOperation({ summary: 'Get pending message requests for current user' })
  async getMessageRequests(@CurrentUser('userId') userId: string) {
    return this.messageRequestsService.getMessageRequests(userId);
  }

  @Post('send')
  @HttpCode(201)
  @ApiOperation({ summary: 'Send a message request to another user' })
  async sendMessageRequest(
    @CurrentUser('userId') senderId: string,
    @Body('recipientId') recipientId: string,
    @Body('text') text: string,
  ) {
    return this.messageRequestsService.sendMessageRequest(senderId, recipientId, text);
  }

  @Post(':requestId/accept')
  @HttpCode(200)
  @ApiOperation({ summary: 'Accept a message request and create conversation' })
  async acceptMessageRequest(
    @CurrentUser('userId') userId: string,
    @Param('requestId') requestId: string,
  ) {
    return this.messageRequestsService.acceptMessageRequest(userId, requestId);
  }

  @Post(':requestId/reject')
  @HttpCode(200)
  @ApiOperation({ summary: 'Reject a message request' })
  async rejectMessageRequest(
    @CurrentUser('userId') userId: string,
    @Param('requestId') requestId: string,
  ) {
    return this.messageRequestsService.rejectMessageRequest(userId, requestId);
  }
}
