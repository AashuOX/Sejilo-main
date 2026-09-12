import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { ChatService } from './chat.service';
import { SearchService } from './search.service';
import { CreateConversationDto } from './dto/create-conversation.dto';
import { MessageReactionDto } from './dto/message-reaction.dto';
import { SendMessageDto } from './dto/send-message.dto';
import { UpdateMessageStatusDto } from './dto/update-status.dto';
import { SearchMessagesDto } from './dto/search-messages.dto';

@ApiTags('Chat & Real-Time Messaging')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
@Controller('v1/chat')
export class ChatController {
  constructor(
    private readonly chatService: ChatService,
    private readonly searchService: SearchService,
  ) {}

  @Get('conversations')
  @ApiOperation({ summary: 'List all direct and group conversations for current user' })
  async getConversations(@CurrentUser('userId') userId: string) {
    return this.chatService.getConversations(userId);
  }

  @Post('conversations')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create or find an existing conversation' })
  async createConversation(
    @CurrentUser('userId') userId: string,
    @Body() dto: CreateConversationDto,
  ) {
    return this.chatService.createConversation(userId, dto);
  }

  @Get('conversations/:conversationId/messages')
  @ApiOperation({ summary: 'Get paginated message history for a conversation' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max messages to return (default 50)' })
  async getMessages(
    @CurrentUser('userId') userId: string,
    @Param('conversationId') conversationId: string,
    @Query('limit') limit?: string,
  ) {
    return this.chatService.getMessages(userId, conversationId, limit ? parseInt(limit, 10) : 50);
  }

  @Post('conversations/:conversationId/messages')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Send a message in a conversation' })
  async sendMessage(
    @CurrentUser('userId') userId: string,
    @Param('conversationId') conversationId: string,
    @Body() dto: SendMessageDto,
  ) {
    return this.chatService.sendMessage(userId, conversationId, dto);
  }

  @Post('messages/:messageId/status')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Update message delivery status (delivered, read)' })
  async updateMessageStatus(
    @CurrentUser('userId') userId: string,
    @Param('messageId') messageId: string,
    @Body() dto: UpdateMessageStatusDto,
  ) {
    await this.chatService.updateMessageStatus(userId, messageId, dto.status);
  }

  @Post('messages/:messageId/reactions')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Add or update an emoji reaction on a message' })
  async addReaction(
    @CurrentUser('userId') userId: string,
    @Param('messageId') messageId: string,
    @Body() dto: MessageReactionDto,
  ) {
    await this.chatService.addReaction(userId, messageId, dto.emoji);
  }

  @Delete('messages/:messageId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete own message' })
  async deleteMessage(
    @CurrentUser('userId') userId: string,
    @Param('messageId') messageId: string,
  ) {
    await this.chatService.deleteMessage(userId, messageId);
  }

  @Post('search/messages')
  @ApiOperation({ summary: 'Search messages with advanced filters (full-text search, date range, media, reactions)' })
  async searchMessages(
    @CurrentUser('userId') userId: string,
    @Body() dto: SearchMessagesDto,
  ) {
    return this.searchService.searchMessages(userId, dto);
  }

  @Get('search/posts')
  @ApiOperation({ summary: 'Search posts by caption/content' })
  @ApiQuery({ name: 'q', required: true, description: 'Search query' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max results (default 20, max 100)' })
  @ApiQuery({ name: 'offset', required: false, description: 'Pagination offset (default 0)' })
  async searchPosts(
    @CurrentUser('userId') userId: string,
    @Query('q') query: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
  ) {
    return this.searchService.searchPosts(
      userId,
      query,
      limit ? parseInt(limit, 10) : 20,
      offset ? parseInt(offset, 10) : 0,
    );
  }

  @Get('search/hashtags')
  @ApiOperation({ summary: 'Search hashtags by name' })
  @ApiQuery({ name: 'q', required: true, description: 'Hashtag search query (without #)' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max results (default 20, max 100)' })
  @ApiQuery({ name: 'offset', required: false, description: 'Pagination offset (default 0)' })
  async searchHashtags(
    @Query('q') query: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
  ) {
    return this.searchService.searchHashtags(
      query,
      limit ? parseInt(limit, 10) : 20,
      offset ? parseInt(offset, 10) : 0,
    );
  }
}
