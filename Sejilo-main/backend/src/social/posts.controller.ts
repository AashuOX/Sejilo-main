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
import { Public } from '../common/decorators/public.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CreateCommentDto } from './dto/create-comment.dto';
import { CreatePostDto } from './dto/create-post.dto';
import { PostsService } from './posts.service';

@ApiTags('Posts, Feeds & Comments')
@Controller('v1')
export class PostsController {
  constructor(private readonly postsService: PostsService) {}

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('feed')
  @ApiOperation({ summary: 'Get customized chronological feed for authenticated user' })
  @ApiQuery({ name: 'cursor', required: false, description: 'Cursor timestamp for pagination' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max items (default 20)' })
  async getFeed(
    @CurrentUser('userId') userId: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    return this.postsService.getFeed(userId, cursor, limit ? parseInt(limit, 10) : 20);
  }

  @Public()
  @Get('explore')
  @ApiOperation({ summary: 'Get global explore grid' })
  async getExplore(
    @CurrentUser('userId') viewerId?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    return this.postsService.getExplore(viewerId, cursor, limit ? parseInt(limit, 10) : 24);
  }

  @Public()
  @Get('users/:username/posts')
  @ApiOperation({ summary: 'Get posts published by a specific user' })
  async getUserPosts(
    @Param('username') username: string,
    @CurrentUser('userId') viewerId?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    return this.postsService.getUserPosts(username, viewerId, cursor, limit ? parseInt(limit, 10) : 20);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('posts')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create and publish a new post' })
  async createPost(@CurrentUser('userId') userId: string, @Body() dto: CreatePostDto) {
    return this.postsService.createPost(userId, dto);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('posts/:postId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete own post' })
  async deletePost(@CurrentUser('userId') userId: string, @Param('postId') postId: string) {
    await this.postsService.deletePost(userId, postId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('posts/:postId/likes')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Like a post' })
  async likePost(@CurrentUser('userId') userId: string, @Param('postId') postId: string) {
    await this.postsService.likePost(userId, postId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('posts/:postId/likes')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Unlike a post' })
  async unlikePost(@CurrentUser('userId') userId: string, @Param('postId') postId: string) {
    await this.postsService.unlikePost(userId, postId);
  }

  @Public()
  @Get('posts/:postId/comments')
  @ApiOperation({ summary: 'Get comments on a post' })
  async getComments(
    @Param('postId') postId: string,
    @CurrentUser('userId') viewerId?: string,
  ) {
    // The viewer is optional (the route is public) but is passed when present so
    // a blocked author's comments are left out of the reply.
    return this.postsService.getComments(postId, viewerId);
  }

  // ── Saved posts ───────────────────────────────────────────────────────────
  // These three answer the paths the app has always called. Until now none of
  // them existed: POST /v1/posts/:id/saves returned 404 and the client
  // swallowed it, so a bookmark never left the device and the Saved tab could
  // only ever show posts composed on that same phone.

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('posts/:postId/saves')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Save (bookmark) a post for the current user' })
  async savePost(
    @CurrentUser('userId') userId: string,
    @Param('postId') postId: string,
  ) {
    return this.postsService.savePost(userId, postId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('posts/:postId/saves')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Remove a post from the current user’s saves' })
  async unsavePost(
    @CurrentUser('userId') userId: string,
    @Param('postId') postId: string,
  ) {
    return this.postsService.unsavePost(userId, postId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('saved-posts')
  @ApiOperation({ summary: 'List the current user’s saved posts' })
  @ApiQuery({ name: 'cursor', required: false, description: 'Cursor timestamp for pagination' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max items (default 30)' })
  async getSavedPosts(
    @CurrentUser('userId') userId: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    return this.postsService.getSavedPosts(
      userId,
      cursor,
      limit ? parseInt(limit, 10) : 30,
    );
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('posts/:postId/comments')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Add a comment to a post' })
  async addComment(
    @CurrentUser('userId') userId: string,
    @Param('postId') postId: string,
    @Body() dto: CreateCommentDto,
  ) {
    return this.postsService.addComment(userId, postId, dto.text);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('comments/:commentId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete own comment' })
  async deleteComment(@CurrentUser('userId') userId: string, @Param('commentId') commentId: string) {
    await this.postsService.deleteComment(userId, commentId);
  }
}
