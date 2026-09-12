import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { BlockUserDto } from './dto/block-user.dto';
import { MuteUserDto } from './dto/mute-user.dto';
import { UsersService } from './users.service';
import { RecommendationsService } from './recommendations.service';

@ApiTags('Users & Profiles')
@Controller()
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly recommendationsService: RecommendationsService,
  ) {}

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('v1/me')
  @ApiOperation({ summary: 'Get current authenticated user profile' })
  async getMe(@CurrentUser('userId') userId: string) {
    return this.usersService.getMe(userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Patch('v1/me')
  @ApiOperation({ summary: 'Update current user profile' })
  async updateProfile(@CurrentUser('userId') userId: string, @Body() dto: UpdateProfileDto) {
    return { profile: await this.usersService.updateProfile(userId, dto) };
  }

  @Public()
  @Get('v1/users/search')
  @ApiOperation({ summary: 'Search users by username or display name' })
  @ApiQuery({ name: 'q', required: true, description: 'Search term' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max records (default 20)' })
  async searchUsers(
    @Query('q') query: string,
    @Query('limit') limit?: string,
    @CurrentUser('userId') viewerId?: string,
  ) {
    return this.usersService.searchUsers(query ?? '', viewerId, limit ? parseInt(limit, 10) : 20);
  }

  // ── Literal /v1/users/* GETs ──────────────────────────────────────────────
  // These must stay ABOVE `GET v1/users/:idOrUsername`. Nest registers routes
  // in declaration order, so while they sat below it every request to
  // /v1/users/muted or /v1/users/blocked was answered by the profile lookup
  // and came back 404 "User not found." — the muted and blocked lists in the
  // app could never load.

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('v1/users/muted')
  @ApiOperation({ summary: 'Get list of muted users' })
  async getMutedUsers(@CurrentUser('userId') userId: string) {
    return this.usersService.getMutedUsers(userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('v1/users/blocked')
  @ApiOperation({ summary: 'Get list of fully blocked users' })
  async getBlockedUsersList(@CurrentUser('userId') userId: string) {
    return this.usersService.getBlockedUsersList(userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('v1/users/blocks')
  @ApiOperation({ summary: 'List every block row, muted ones included' })
  async getBlockedUsers(@CurrentUser('userId') userId: string) {
    return this.usersService.getBlockedUsers(userId);
  }

  @Public()
  @Get('v1/users/:idOrUsername')
  @ApiOperation({ summary: 'Get public profile by id or username' })
  async getByIdOrUsername(
    @Param('idOrUsername') idOrUsername: string,
    @CurrentUser('userId') viewerId?: string,
  ) {
    const trimmed = idOrUsername.trim();
    // A UUID (user.id) routes to id lookup; anything else is a username.
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      trimmed,
    );
    if (isUuid) {
      return this.usersService.getById(trimmed, viewerId);
    }
    return this.usersService.getPublicProfile(trimmed, viewerId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('v1/me')
  @ApiOperation({ summary: 'Delete the authenticated account (cascades related data)' })
  async deleteAccount(@CurrentUser('userId') userId: string) {
    return this.usersService.deleteAccount(userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('v1/users/:idOrUsername/block')
  @ApiOperation({ summary: 'Block a user' })
  async blockUser(
    @CurrentUser('userId') userId: string,
    @Param('idOrUsername') idOrUsername: string,
  ) {
    return this.usersService.blockUser(userId, idOrUsername);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('v1/users/:idOrUsername/block')
  @ApiOperation({ summary: 'Unblock a user' })
  async unblockUser(
    @CurrentUser('userId') userId: string,
    @Param('idOrUsername') idOrUsername: string,
  ) {
    return this.usersService.unblockUser(userId, idOrUsername);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('v1/users/:idOrUsername/mute')
  @ApiOperation({ summary: 'Mute notifications from a user (not a full block)' })
  async muteUser(
    @CurrentUser('userId') userId: string,
    @Param('idOrUsername') idOrUsername: string,
    @Body() dto: MuteUserDto,
  ) {
    return this.usersService.muteUser(userId, idOrUsername, dto.isMuted);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('v1/users/:idOrUsername/block-with-report')
  @ApiOperation({ summary: 'Block a user and optionally report them' })
  async blockUserWithReport(
    @CurrentUser('userId') userId: string,
    @Param('idOrUsername') idOrUsername: string,
    @Body() dto: BlockUserDto,
  ) {
    return this.usersService.blockUserWithReport(userId, idOrUsername, dto);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('v1/recommendations/users')
  @ApiOperation({ summary: 'Get user recommendations (suggested for you)' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max results (default 10, max 50)' })
  async getRecommendations(
    @CurrentUser('userId') userId: string,
    @Query('limit') limit?: string,
  ) {
    const limitNum = Math.min(limit ? parseInt(limit, 10) : 10, 50);
    return this.recommendationsService.getRecommendations(userId, limitNum);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('v1/recommendations/:recommendedUserId/dismiss')
  @ApiOperation({ summary: 'Dismiss a user recommendation' })
  async dismissRecommendation(
    @CurrentUser('userId') userId: string,
    @Param('recommendedUserId') recommendedUserId: string,
  ) {
    return this.recommendationsService.dismissRecommendation(userId, recommendedUserId);
  }
}

