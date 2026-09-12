import { Injectable, BadRequestException, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';
import { WebhooksService } from '../webhooks/webhooks.service';

@Injectable()
export class FollowsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly webhooks: WebhooksService,
    private readonly visibility: ContentVisibilityService,
  ) {}

  async follow(followerId: string, identifier: string, isFollow: boolean) {
    const targetUser = await this._findUserByIdOrUsername(identifier);

    if (!targetUser) {
      throw new NotFoundException('User to follow not found.');
    }

    if (targetUser.id === followerId) {
      throw new BadRequestException('Cannot follow yourself.');
    }

    // STEP 27 — Blocked users: a block ends the relationship in both
    // directions, so neither side can follow the other. Only the target's own
    // block used to be checked, which let you follow an account you had
    // blocked yourself — a follow edge to someone every feed query then
    // filtered back out.
    //
    // Only the follow direction is gated. Undoing a follow, or withdrawing a
    // pending request, has to keep working whatever the block state is,
    // otherwise a stale edge could never be cleared from the client.
    if (isFollow && (await this.visibility.isBlockedBetween(followerId, targetUser.id))) {
      throw new ForbiddenException('You cannot follow this user.');
    }

    if (isFollow) {
      const isPrivate = targetUser.profile?.isPrivate ?? false;
      const existingFollow = await this.prisma.follow.findUnique({
        where: {
          followerId_followingId: {
            followerId,
            followingId: targetUser.id,
          },
        },
      });

      if (existingFollow) {
        return this._getPublicProfile(targetUser.id, followerId);
      }

      const existingRequest = await this.prisma.followRequest.findUnique({
        where: {
          requesterId_targetId: {
            requesterId: followerId,
            targetId: targetUser.id,
          },
        },
      });

      if (isPrivate && !existingRequest) {
        const request = await this.prisma.followRequest.create({
          data: {
            requesterId: followerId,
            targetId: targetUser.id,
          },
        });

        await this.prisma.notification.create({
          data: {
            userId: targetUser.id,
            actorId: followerId,
            type: 'follow_request',
          },
        }).catch(() => {});

        await this.webhooks.onUserFollowed({
          followerId,
          followingId: targetUser.id,
          createdAt: request.createdAt.toISOString(),
        });

        return this._getPublicProfile(targetUser.id, followerId);
      }

      await this.prisma.follow.create({
        data: {
          followerId,
          followingId: targetUser.id,
        },
      });

      await this.prisma.notification.create({
        data: {
          userId: targetUser.id,
          actorId: followerId,
          type: 'follow',
        },
      }).catch(() => {});

      await this.webhooks.onUserFollowed({
        followerId,
        followingId: targetUser.id,
        createdAt: new Date().toISOString(),
      });
    } else {
      await this.prisma.follow.deleteMany({
        where: {
          followerId,
          followingId: targetUser.id,
        },
      });

      await this.prisma.followRequest.deleteMany({
        where: {
          requesterId: followerId,
          targetId: targetUser.id,
        },
      });

      await this.webhooks.onUserUnfollowed({
        followerId,
        followingId: targetUser.id,
        createdAt: new Date().toISOString(),
      });
    }

    return this._getPublicProfile(targetUser.id, followerId);
  }

  /// Who follows [identifier].
  ///
  /// A private account's follower list is part of what being private covers, so
  /// it answers only to the account itself and to its accepted followers. It
  /// used to answer any signed-in caller, which handed out the list of everyone
  /// following a private account to anyone who asked for it.
  ///
  /// Blocked accounts are dropped from the list whichever side set the block —
  /// the same rule the feed and search already apply.
  async getFollowers(identifier: string, viewerId?: string) {
    const user = await this._findUserByIdOrUsername(identifier);
    if (!user) throw new NotFoundException('User not found.');
    await this.visibility.assertMayReadContentOf(
      user.id,
      user.profile?.isPrivate ?? false,
      viewerId,
      'followers',
    );
    const hidden = await this.visibility.hiddenAuthorIds(viewerId);
    const follows = await this.prisma.follow.findMany({
      where: {
        followingId: user.id,
        ...(hidden.length ? { followerId: { notIn: hidden } } : {}),
      },
      include: { follower: { include: { profile: true } } },
    });

    return {
      users: follows.map((f) => ({
        id: f.follower.id,
        username: f.follower.profile?.username ?? '',
        displayName: f.follower.profile?.displayName ?? '',
        bio: f.follower.profile?.bio ?? '',
        avatar: f.follower.profile?.avatarBytes && f.follower.profile?.avatarMimeType
            ? {
                mimeType: f.follower.profile.avatarMimeType,
                data: Buffer.from(f.follower.profile.avatarBytes).toString('base64url'),
              }
            : null,
      })),
    };
  }

  /// Who [identifier] follows. Gated exactly as [getFollowers] is.
  async getFollowing(identifier: string, viewerId?: string) {
    const user = await this._findUserByIdOrUsername(identifier);
    if (!user) throw new NotFoundException('User not found.');
    await this.visibility.assertMayReadContentOf(
      user.id,
      user.profile?.isPrivate ?? false,
      viewerId,
      'following list',
    );
    const hidden = await this.visibility.hiddenAuthorIds(viewerId);
    const follows = await this.prisma.follow.findMany({
      where: {
        followerId: user.id,
        ...(hidden.length ? { followingId: { notIn: hidden } } : {}),
      },
      include: { following: { include: { profile: true } } },
    });

    return {
      users: follows.map((f) => ({
        id: f.following.id,
        username: f.following.profile?.username ?? '',
        displayName: f.following.profile?.displayName ?? '',
        bio: f.following.profile?.bio ?? '',
        avatar: f.following.profile?.avatarBytes && f.following.profile?.avatarMimeType
            ? {
                mimeType: f.following.profile.avatarMimeType,
                data: Buffer.from(f.following.profile.avatarBytes).toString('base64url'),
              }
            : null,
      })),
    };
  }

  async getFollowRequests(userId: string) {
    const requests = await this.prisma.followRequest.findMany({
      where: { targetId: userId, status: 'pending' },
      include: {
        requester: {
          include: {
            profile: true,
          },
        },
      },
    });

    return {
      requests: requests.map((r) => ({
        id: r.id,
        requesterId: r.requester.id,
        username: r.requester.profile?.username ?? '',
        displayName: r.requester.profile?.displayName ?? '',
        bio: r.requester.profile?.bio ?? '',
        avatar: r.requester.profile?.avatarBytes && r.requester.profile?.avatarMimeType
          ? {
              mimeType: r.requester.profile.avatarMimeType,
              data: Buffer.from(r.requester.profile.avatarBytes).toString('base64url'),
            }
          : null,
        createdAt: r.createdAt.toISOString(),
      })),
    };
  }

  async acceptFollowRequest(userId: string, requesterId: string) {
    const request = await this.prisma.followRequest.findUnique({
      where: {
        requesterId_targetId: {
          requesterId,
          targetId: userId,
        },
      },
    });

    if (!request || request.status !== 'pending') {
      throw new NotFoundException('Follow request not found.');
    }

    await this.prisma.$transaction([
      this.prisma.followRequest.update({
        where: { id: request.id },
        data: { status: 'accepted' },
      }),
      this.prisma.follow.create({
        data: {
          followerId: requesterId,
          followingId: userId,
        },
      }),
    ]);

    await this.prisma.notification.create({
      data: {
        userId: requesterId,
        actorId: userId,
        type: 'follow_accepted',
      },
    }).catch(() => {});

    await this.webhooks.onUserFollowed({
      followerId: requesterId,
      followingId: userId,
      createdAt: new Date().toISOString(),
    });

    return this._getPublicProfile(userId, requesterId);
  }

  async rejectFollowRequest(userId: string, requesterId: string) {
    const request = await this.prisma.followRequest.findUnique({
      where: {
        requesterId_targetId: {
          requesterId,
          targetId: userId,
        },
      },
    });

    if (!request || request.status !== 'pending') {
      throw new NotFoundException('Follow request not found.');
    }

    await this.prisma.followRequest.update({
      where: { id: request.id },
      data: { status: 'rejected' },
    });

    return { success: true };
  }

  private async _getPublicProfile(userId: string, viewerId?: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: {
        profile: true,
        _count: {
          select: {
            followers: true,
            following: true,
            posts: { where: { deletedAt: null } },
          },
        },
        followers: viewerId ? { where: { followerId: viewerId } } : false,
      },
    });

    if (!user || !user.profile) {
      throw new NotFoundException('User not found.');
    }

    const isFollowing = viewerId
      ? user.followers && user.followers.length > 0
      : false;

    // A follow of a private account creates a FollowRequest instead of a
    // Follow. Without this flag the response looked identical to "not
    // following", so the app dropped straight back to a Follow button and the
    // person could never see that their request was waiting.
    const pendingRequest =
      viewerId && viewerId !== user.id && !isFollowing
        ? await this.prisma.followRequest.findUnique({
            where: {
              requesterId_targetId: { requesterId: viewerId, targetId: user.id },
            },
            select: { status: true },
          })
        : null;

    // The viewer's own block row, so mute/block state survives a follow
    // toggle — this response replaces the profile the app is showing.
    const viewerBlock =
      viewerId && viewerId !== user.id
        ? await this.prisma.block.findUnique({
            where: {
              blockerId_blockedId: { blockerId: viewerId, blockedId: user.id },
            },
            select: { isMuted: true },
          })
        : null;

    return {
      profile: {
        id: user.id,
        username: user.profile.username,
        displayName: user.profile.displayName,
        bio: user.profile.bio ?? '',
        avatar: user.profile.avatarBytes && user.profile.avatarMimeType
          ? {
              mimeType: user.profile.avatarMimeType,
              data: Buffer.from(user.profile.avatarBytes).toString('base64url'),
            }
          : null,
        avatarUrl: user.profile.avatarUrl,
        isPrivate: user.profile.isPrivate,
        createdAt: user.createdAt.toISOString(),
        followersCount: user._count.followers,
        followingCount: user._count.following,
        postsCount: user._count.posts,
        followedByViewer: isFollowing,
        isFollowing,
        followRequestPending: pendingRequest?.status === 'pending',
        mutedByViewer: viewerBlock?.isMuted === true,
        blockedByViewer: viewerBlock != null && viewerBlock.isMuted !== true,
      },
    };
  }

  private async _findUserByIdOrUsername(identifier: string) {
    const isUuid =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        identifier,
      );
    return isUuid
      ? this.prisma.user.findUnique({
          where: { id: identifier },
          include: { profile: true },
        })
      : this.prisma.user.findFirst({
          where: { profile: { username: identifier.toLowerCase().trim() } },
          include: { profile: true },
        });
  }
}
