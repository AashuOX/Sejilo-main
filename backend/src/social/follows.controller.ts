import {
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Post,
  UseGuards,
  Body,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { FollowsService } from './follows.service';

@ApiTags('Social Follows')
@Controller('v1/users')
export class FollowsController {
  constructor(private readonly followsService: FollowsService) {}

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post(':idOrUsername/follow')
  @HttpCode(201)
  @ApiOperation({ summary: 'Follow a user by username or id' })
  async followUser(
    @CurrentUser('userId') followerId: string,
    @Param('idOrUsername') target: string,
  ) {
    return this.followsService.follow(followerId, target, true);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete(':idOrUsername/follow')
  // 200, not 204: the service answers with the updated profile and the app
  // needs it to redraw the follow button. A 204 discarded that body, so every
  // unfollow reached the client as an unparseable empty response.
  @HttpCode(200)
  @ApiOperation({ summary: 'Unfollow a user by username or id' })
  async unfollowUser(
    @CurrentUser('userId') followerId: string,
    @Param('idOrUsername') target: string,
  ) {
    return this.followsService.follow(followerId, target, false);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  // Two segments on purpose. `GET v1/users/follow-requests` was unreachable:
  // UsersModule is registered before SocialModule, so UsersController's
  // `GET v1/users/:idOrUsername` matched first and every call came back
  // 404 "User not found." A username cannot contain a slash, so this path
  // cannot be shadowed.
  @Get('follow-requests/pending')
  @ApiOperation({ summary: 'Get pending follow requests for current user' })
  async getFollowRequests(@CurrentUser('userId') userId: string) {
    return this.followsService.getFollowRequests(userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('follow-requests/:requesterId/accept')
  @HttpCode(200)
  @ApiOperation({ summary: 'Accept a follow request' })
  async acceptFollowRequest(
    @CurrentUser('userId') userId: string,
    @Param('requesterId') requesterId: string,
  ) {
    return this.followsService.acceptFollowRequest(userId, requesterId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('follow-requests/:requesterId/reject')
  @HttpCode(200)
  @ApiOperation({ summary: 'Reject a follow request' })
  async rejectFollowRequest(
    @CurrentUser('userId') userId: string,
    @Param('requesterId') requesterId: string,
  ) {
    return this.followsService.rejectFollowRequest(userId, requesterId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get(':idOrUsername/followers')
  @ApiOperation({ summary: 'Get followers of a user (by id or username)' })
  async getFollowers(
    @CurrentUser('userId') viewerId: string,
    @Param('idOrUsername') idOrUsername: string,
  ) {
    return this.followsService.getFollowers(idOrUsername, viewerId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get(':idOrUsername/following')
  @ApiOperation({ summary: 'Get users followed by a user (by id or username)' })
  async getFollowing(
    @CurrentUser('userId') viewerId: string,
    @Param('idOrUsername') idOrUsername: string,
  ) {
    return this.followsService.getFollowing(idOrUsername, viewerId);
  }
}
