import { Injectable, NotFoundException, BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly visibility: ContentVisibilityService,
  ) {}

  async getMe(userId: string) {
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
      },
    });

    if (!user || !user.profile) {
      throw new NotFoundException('User profile not found.');
    }

    return {
      profile: {
        id: user.id,
        email: user.email,
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
        isVerified: user.profile.isVerified,
        createdAt: user.createdAt.toISOString(),
        followersCount: user._count.followers,
        followingCount: user._count.following,
        postsCount: user._count.posts,
      },
    };
  }

  async updateProfile(userId: string, dto: UpdateProfileDto) {
    let avatarBytes: any = undefined;
    let avatarMimeType: string | undefined;

    if (dto.avatar) {
      avatarBytes = Buffer.from(dto.avatar.data, 'base64url');
      avatarMimeType = dto.avatar.mimeType;
    }

    const birthDate = dto.birthDate ? this.validateBirthDate(dto.birthDate) : undefined;
    const updatedProfile = await this.prisma.profile.update({
      where: { userId },
      data: {
        ...(dto.username ? { username: dto.username.toLowerCase().trim() } : {}),
        displayName: dto.displayName?.trim() || undefined,
        bio: dto.bio !== undefined ? dto.bio.trim() : undefined,
        avatarBytes,
        avatarMimeType,
        isPrivate: dto.isPrivate,
      },
    });

    if (birthDate) {
      await this.prisma.user.update({
        where: { id: userId },
        data: { birthDate },
      });
    }

    return {
      id: userId,
      username: updatedProfile.username,
      displayName: updatedProfile.displayName,
      bio: updatedProfile.bio ?? '',
      avatar: updatedProfile.avatarBytes && updatedProfile.avatarMimeType
        ? {
            mimeType: updatedProfile.avatarMimeType,
            data: Buffer.from(updatedProfile.avatarBytes).toString('base64url'),
          }
        : null,
      isPrivate: updatedProfile.isPrivate,
      createdAt: updatedProfile.createdAt.toISOString(),
    };
  }

  /** Birthday is private; it is used only for age and safety policy enforcement. */
  private validateBirthDate(value: string): Date {
    const birthDate = new Date(`${value}T00:00:00.000Z`);
    if (Number.isNaN(birthDate.getTime()) || birthDate > new Date()) {
      throw new BadRequestException('Enter a valid birth date.');
    }

    const today = new Date();
    let age = today.getUTCFullYear() - birthDate.getUTCFullYear();
    if (
      today.getUTCMonth() < birthDate.getUTCMonth() ||
      (today.getUTCMonth() === birthDate.getUTCMonth() && today.getUTCDate() < birthDate.getUTCDate())
    ) {
      age -= 1;
    }
    if (age < 13) {
      throw new BadRequestException('You must be at least 13 years old to use SejiloChat.');
    }
    return birthDate;
  }

  async getById(userId: string, viewerId?: string) {
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

    // Same viewer-scoped block row as getPublicProfile, so both shapes carry
    // the mute/block state the profile menu needs.
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
        avatar:
          user.profile.avatarUrl
            ? { avatarUrl: user.profile.avatarUrl }
            : user.profile.avatarBytes && user.profile.avatarMimeType
                ? {
                    mimeType: user.profile.avatarMimeType,
                    data: Buffer.from(user.profile.avatarBytes).toString(
                      'base64url',
                    ),
                  }
                : null,
        avatarUrl: user.profile.avatarUrl,
        isPrivate: user.profile.isPrivate,
        createdAt: user.createdAt.toISOString(),
        followersCount: user._count.followers,
        followingCount: user._count.following,
        postsCount: user._count.posts,
        followedByViewer: viewerId
          ? user.followers && user.followers.length > 0
          : false,
        isFollowing: viewerId
          ? user.followers && user.followers.length > 0
          : false,
        mutedByViewer: viewerBlock?.isMuted === true,
        blockedByViewer: viewerBlock != null && viewerBlock.isMuted !== true,
      },
    };
  }

  async getPublicProfile(username: string, viewerId?: string) {
    const profile = await this.prisma.profile.findUnique({
      where: { username: username.toLowerCase().trim() },
      include: {
        user: {
          include: {
            _count: {
              select: {
                followers: true,
                following: true,
                posts: { where: { deletedAt: null } },
              },
            },
            followers: viewerId ? { where: { followerId: viewerId } } : false,
          },
        },
      },
    });

    if (!profile) {
      throw new NotFoundException('User not found.');
    }

    const isFollowing = viewerId
      ? profile.user.followers && profile.user.followers.length > 0
      : false;

    // The viewer's own block row, so a profile can show "Unmute"/"Unblock"
    // instead of offering an action that is already in effect. Only ever the
    // row the viewer created — nobody learns that they have been blocked.
    const viewerBlock =
      viewerId && viewerId !== profile.userId
        ? await this.prisma.block.findUnique({
            where: {
              blockerId_blockedId: {
                blockerId: viewerId,
                blockedId: profile.userId,
              },
            },
            select: { isMuted: true },
          })
        : null;

    return {
      profile: {
        id: profile.userId,
        username: profile.username,
        displayName: profile.displayName,
        bio: profile.bio ?? '',
        avatar: profile.avatarBytes && profile.avatarMimeType
          ? {
              mimeType: profile.avatarMimeType,
              data: Buffer.from(profile.avatarBytes).toString('base64url'),
            }
          : null,
        avatarUrl: profile.avatarUrl,
        isPrivate: profile.isPrivate,
        isVerified: profile.isVerified,
        createdAt: profile.createdAt.toISOString(),
        followersCount: profile.user._count.followers,
        followingCount: profile.user._count.following,
        postsCount: profile.user._count.posts,
        followedByViewer: isFollowing,
        isFollowing,
        mutedByViewer: viewerBlock?.isMuted === true,
        blockedByViewer: viewerBlock != null && viewerBlock.isMuted !== true,
      },
    };
  }

  async searchUsers(query: string, viewerId?: string, limit = 20) {
    const q = query.trim().toLowerCase();
    if (!q) return { users: [] };

    // Blocking is symmetric here too: neither side finds the other by searching.
    // A mute is not a block, so a muted account stays findable.
    const hidden = await this.visibility.hiddenAuthorIds(viewerId);

    const profiles = await this.prisma.profile.findMany({
      where: {
        OR: [
          { username: { contains: q, mode: 'insensitive' } },
          { displayName: { contains: q, mode: 'insensitive' } },
        ],
        ...(hidden.length ? { userId: { notIn: hidden } } : {}),
      },
      take: Math.min(limit, 50),
      include: {
        user: {
          include: {
            followers: viewerId ? { where: { followerId: viewerId } } : false,
          },
        },
      },
    });

    return {
      users: profiles.map((p) => ({
        id: p.userId,
        username: p.username,
        displayName: p.displayName,
        bio: p.bio ?? '',
        avatar: p.avatarBytes && p.avatarMimeType
          ? {
              mimeType: p.avatarMimeType,
              data: Buffer.from(p.avatarBytes).toString('base64url'),
            }
          : null,
        followedByViewer: viewerId
          ? p.user.followers && p.user.followers.length > 0
          : false,
      })),
    };
  }

  // STEP 5 / STEP 27 — Account deletion (cascades to profile, sessions, posts, etc.)
  async deleteAccount(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found.');
    await this.prisma.user.delete({ where: { id: userId } });
    return { success: true };
  }

  // STEP 27 — Blocked users
  private async _resolveTarget(identifier: string) {
    const trimmed = identifier.trim();
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      trimmed,
    );
    return isUuid
      ? this.prisma.user.findUnique({ where: { id: trimmed } })
      : this.prisma.user.findFirst({
          where: { profile: { username: trimmed.toLowerCase() } },
        });
  }

  async blockUser(blockerId: string, identifier: string) {
    const target = await this._resolveTarget(identifier);
    if (!target) throw new NotFoundException('User to block not found.');
    if (target.id === blockerId) {
      throw new BadRequestException('Cannot block yourself.');
    }
    // Remove any prior follow relationship between the two.
    await this.prisma.follow
      .deleteMany({
        where: {
          OR: [
            { followerId: blockerId, followingId: target.id },
            { followerId: target.id, followingId: blockerId },
          ],
        },
      })
      .catch(() => {});
    await this.prisma.block.upsert({
      where: {
        blockerId_blockedId: { blockerId, blockedId: target.id },
      },
      create: { blockerId, blockedId: target.id },
      // isMuted: false is what makes the row a full block. Without it, blocking
      // an account that was only muted left the mute in place.
      update: { isMuted: false },
    });
    return { success: true, blockedId: target.id };
  }

  async unblockUser(blockerId: string, identifier: string) {
    const target = await this._resolveTarget(identifier);
    if (!target) throw new NotFoundException('User to unblock not found.');
    await this.prisma.block.deleteMany({
      where: { blockerId, blockedId: target.id },
    });
    return { success: true, unblockedId: target.id };
  }

  async getBlockedUsers(blockerId: string) {
    const blocks = await this.prisma.block.findMany({
      where: { blockerId },
      include: { blocked: { include: { profile: true } } },
    });
    return {
      users: blocks.map((b) => ({
        id: b.blocked.id,
        username: b.blocked.profile?.username ?? '',
        displayName: b.blocked.profile?.displayName ?? '',
        bio: b.blocked.profile?.bio ?? '',
        avatar:
          b.blocked.profile?.avatarBytes && b.blocked.profile?.avatarMimeType
            ? {
                mimeType: b.blocked.profile.avatarMimeType,
                data: Buffer.from(b.blocked.profile.avatarBytes).toString(
                  'base64url',
                ),
              }
            : null,
      })),
    };
  }

  async isBlocked(blockerId: string, blockedId: string) {
    const block = await this.prisma.block.findUnique({
      where: { blockerId_blockedId: { blockerId, blockedId } },
    });
    return !!block;
  }

  /**
   * Mutes or unmutes an account.
   *
   * A mute is a `Block` row with `isMuted: true`; a full block is the same row
   * with `isMuted: false`. Unmuting therefore has to DELETE the row — the
   * previous version upserted `isMuted: false`, which quietly turned every
   * unmute into a block (and cut off messaging via verifyUserNotBlocked).
   */
  async muteUser(userId: string, identifier: string, isMuted: boolean) {
    const target = await this._resolveTarget(identifier);
    if (!target) throw new NotFoundException('User to mute not found.');
    if (userId === target.id) throw new BadRequestException('Cannot mute yourself.');

    const username = await this._usernameOf(target.id);
    const key = {
      blockerId_blockedId: { blockerId: userId, blockedId: target.id },
    };
    const existing = await this.prisma.block.findUnique({ where: key });
    const isFullBlock = existing != null && !existing.isMuted;

    if (isFullBlock) {
      // Muting would rewrite the row and silently lift the block.
      throw new BadRequestException(
        'This account is blocked, which already hides it. Unblock them first.',
      );
    }

    if (!isMuted) {
      if (existing) await this.prisma.block.delete({ where: key });
      return { success: true, userId: target.id, username, isMuted: false };
    }

    const block = await this.prisma.block.upsert({
      where: key,
      create: { blockerId: userId, blockedId: target.id, isMuted: true },
      update: { isMuted: true },
    });

    return {
      success: true,
      userId: target.id,
      username,
      isMuted: block.isMuted,
    };
  }

  /** The account's real username. Responses used to guess it from the email. */
  private async _usernameOf(userId: string): Promise<string> {
    const profile = await this.prisma.profile.findUnique({
      where: { userId },
      select: { username: true },
    });
    return profile?.username ?? '';
  }

  async blockUserWithReport(userId: string, identifier: string, dto: any) {
    const target = await this._resolveTarget(identifier);
    if (!target) throw new NotFoundException('User to block not found.');
    if (userId === target.id) throw new BadRequestException('Cannot block yourself.');

    // Drop the follow in both directions, exactly as a plain block does — a
    // block that left their follow of you intact would still show them your
    // posts in their feed.
    await this.prisma.follow
      .deleteMany({
        where: {
          OR: [
            { followerId: userId, followingId: target.id },
            { followerId: target.id, followingId: userId },
          ],
        },
      })
      .catch(() => {});

    // Create or update block with report data
    await this.prisma.block.upsert({
      where: {
        blockerId_blockedId: { blockerId: userId, blockedId: target.id },
      },
      create: {
        blockerId: userId,
        blockedId: target.id,
        reason: dto.reason,
        reportReason: dto.reportReason,
        reportDetails: dto.reportDetails,
      },
      update: {
        isMuted: false,
        reason: dto.reason,
        reportReason: dto.reportReason,
        reportDetails: dto.reportDetails,
      },
    });

    return {
      success: true,
      blockedId: target.id,
      username: await this._usernameOf(target.id),
      reported: !!dto.reportReason,
    };
  }

  async getMutedUsers(userId: string) {
    const mutedBlocks = await this.prisma.block.findMany({
      where: {
        blockerId: userId,
        isMuted: true,
      },
      include: { blocked: { include: { profile: true } } },
    });

    return {
      mutedUsers: mutedBlocks.map((b) => ({
        id: b.blocked.id,
        username: b.blocked.profile?.username ?? '',
        displayName: b.blocked.profile?.displayName ?? '',
        avatar: b.blocked.profile?.avatarBytes && b.blocked.profile?.avatarMimeType
          ? {
              mimeType: b.blocked.profile.avatarMimeType,
              data: Buffer.from(b.blocked.profile.avatarBytes).toString('base64url'),
            }
          : null,
        mutedAt: b.createdAt.toISOString(),
      })),
    };
  }

  async getBlockedUsersList(blockerId: string) {
    const blocks = await this.prisma.block.findMany({
      where: {
        blockerId,
        isMuted: false, // Only show fully blocked users, not muted
      },
      include: { blocked: { include: { profile: true } } },
      orderBy: { createdAt: 'desc' },
    });

    return {
      blockedUsers: blocks.map((b) => ({
        id: b.blocked.id,
        username: b.blocked.profile?.username ?? '',
        displayName: b.blocked.profile?.displayName ?? '',
        avatar: b.blocked.profile?.avatarBytes && b.blocked.profile?.avatarMimeType
          ? {
              mimeType: b.blocked.profile.avatarMimeType,
              data: Buffer.from(b.blocked.profile.avatarBytes).toString('base64url'),
            }
          : null,
        reason: b.reason,
        reportReason: b.reportReason,
        blockedAt: b.createdAt.toISOString(),
      })),
    };
  }

  async verifyUserNotBlocked(userId: string, otherUserId: string) {
    // Check if either user has blocked the other
    const blockFromOther = await this.prisma.block.findUnique({
      where: {
        blockerId_blockedId: { blockerId: otherUserId, blockedId: userId },
      },
    });

    const blockFromUser = await this.prisma.block.findUnique({
      where: {
        blockerId_blockedId: { blockerId: userId, blockedId: otherUserId },
      },
    });

    // If fully blocked (not just muted), return false
    if (blockFromOther || blockFromUser) {
      const isFullBlock = (blockFromOther && !blockFromOther.isMuted) || (blockFromUser && !blockFromUser.isMuted);
      if (isFullBlock) {
        return false;
      }
    }

    return true;
  }
}
