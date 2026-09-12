import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CreateStoryDto } from './dto/create-story.dto';
import { AddStoryReactionDto } from './dto/add-story-reaction.dto';
import { StoriesService } from './stories.service';

@ApiTags('Stories (24h Ephemeral)')
@Controller('v1/stories')
export class StoriesController {
  constructor(private readonly storiesService: StoriesService) {}

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Publish a 24h story' })
  async createStory(@CurrentUser('userId') userId: string, @Body() dto: CreateStoryDto) {
    return this.storiesService.createStory(userId, dto);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get()
  @ApiOperation({ summary: 'Get unexpired stories for active following users' })
  async getStories(@CurrentUser('userId') userId: string) {
    return this.storiesService.getStories(userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post(':storyId/views')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Mark a story as viewed' })
  async markStoryViewed(
    @CurrentUser('userId') viewerId: string,
    @Param('storyId') storyId: string,
  ) {
    await this.storiesService.markStoryViewed(viewerId, storyId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get(':storyId/views')
  @ApiOperation({ summary: 'Get viewers of own story' })
  async getStoryViewers(
    @CurrentUser('userId') userId: string,
    @Param('storyId') storyId: string,
  ) {
    return this.storiesService.getStoryViewers(userId, storyId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete(':storyId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete own story' })
  async deleteStory(
    @CurrentUser('userId') userId: string,
    @Param('storyId') storyId: string,
  ) {
    await this.storiesService.deleteStory(userId, storyId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post(':storyId/reactions')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Add or update a reaction to a story' })
  async addReaction(
    @CurrentUser('userId') userId: string,
    @Param('storyId') storyId: string,
    @Body() dto: AddStoryReactionDto,
  ) {
    return this.storiesService.addReaction(userId, storyId, dto);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete(':storyId/reactions/:emoji')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Remove a reaction from a story' })
  async removeReaction(
    @CurrentUser('userId') userId: string,
    @Param('storyId') storyId: string,
    @Param('emoji') emoji: string,
  ) {
    return this.storiesService.removeReaction(userId, storyId, emoji);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get(':storyId/reactions')
  @ApiOperation({ summary: 'Get all reactions for a story with viewer lists' })
  async getReactions(
    @CurrentUser('userId') userId: string,
    @Param('storyId') storyId: string,
  ) {
    return this.storiesService.getStoryReactions(userId, storyId);
  }
}
