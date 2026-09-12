import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';
import { CreateStoryDto } from './dto/create-story.dto';
import { AddStoryReactionDto } from './dto/add-story-reaction.dto';
import { WebhooksService } from '../webhooks/webhooks.service';

@Injectable()
export class StoriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly webhooks: WebhooksService,
    private readonly visibility: ContentVisibilityService,
  ) {}

  /// Loads a story [viewerId] is allowed to act on — mark viewed, react, or read
  /// the reactions of.
  ///
  /// Every one of those routes takes a story id straight from the client, and
  /// none of them used to check whose story it was: a blocked account could put
  /// itself in your viewers list and land an emoji next to its username on your
  /// story, and a story id belonging to a private account was readable by any
  /// signed-in caller.
  private async storyForInteraction(storyId: string, viewerId: string) {
    const story = await this.prisma.story.findFirst({
      where: { id: storyId, deletedAt: null },
      select: {
        id: true,
        userId: true,
        expiresAt: true,
        user: { select: { profile: { select: { isPrivate: true } } } },
      },
    });
    if (!story) throw new NotFoundException('Story not found');
    if (story.expiresAt < new Date()) {
      throw new ForbiddenException('Story has expired');
    }

    await this.visibility.assertMayReadContentOf(
      story.userId,
      story.user?.profile?.isPrivate ?? false,
      viewerId,
      'stories',
    );
    return story;
  }

  async createStory(userId: string, dto: CreateStoryDto) {
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
    let mediaBytes: any = undefined;
    let mimeType: string | undefined;

    if (dto.media) {
      mediaBytes = Buffer.from(dto.media.data, 'base64url');
      mimeType = dto.media.mimeType;
    }

    const story = await this.prisma.story.create({
      data: {
        userId,
        type: dto.type,
        mediaBytes,
        mimeType,
        textContent: dto.textContent?.trim(),
        backgroundStyle: dto.backgroundStyle?.trim(),
        expiresAt,
      },
    });

    // Fire webhook
    await this.webhooks.onStoryCreated({
      storyId: story.id,
      userId,
      mediaType: mimeType?.startsWith('video') ? 'video' : 'image',
      expiresAt: story.expiresAt.toISOString(),
      createdAt: story.createdAt.toISOString(),
    });

    return {
      id: story.id,
      createdAt: story.createdAt.toISOString(),
      expiresAt: story.expiresAt.toISOString(),
    };
  }

  async getStories(viewerId: string) {
    const [following, hiddenAuthors] = await Promise.all([
      this.prisma.follow.findMany({
        where: { followerId: viewerId },
        select: { followingId: true },
      }),
      this.visibility.hiddenAuthorIds(viewerId),
    ]);

    // A block ends the reading relationship even where the follow edge outlived
    // it, so blocked accounts come out of the list rather than being relied on
    // to have been unfollowed.
    const hidden = new Set(hiddenAuthors);
    const targetUserIds = [viewerId, ...following.map((f) => f.followingId)].filter(
      (id) => !hidden.has(id),
    );
    const now = new Date();

    const stories = await this.prisma.story.findMany({
      where: {
        userId: { in: targetUserIds },
        expiresAt: { gt: now },
        deletedAt: null,
      },
      orderBy: { createdAt: 'asc' },
      include: {
        user: { include: { profile: true } },
        views: true,
        reactions: {
          include: { user: { include: { profile: true } } },
        },
      },
    });

    // Get reactions for all stories in one query
    const storyIds = stories.map(s => s.id);
    const allReactions = await this.prisma.storyReaction.findMany({
      where: { storyId: { in: storyIds } },
      include: { user: { include: { profile: true } } },
    });

    // Group reactions by storyId
    const reactionsByStory = allReactions.reduce((acc, r) => {
      if (!acc[r.storyId]) {
        acc[r.storyId] = [];
      }
      acc[r.storyId].push(r);
      return acc;
    }, {} as Record<string, any[]>);

    // Helper to format reactions for a story
    const formatReactions = (storyReactions: any[]) => {
      return storyReactions.reduce((acc, r) => {
        const key = r.emoji;
        if (!acc[key]) {
          acc[key] = { emoji: key, count: 0, users: [] };
        }
        acc[key].count++;
        acc[key].users.push({
          userId: r.userId,
          username: r.user.profile?.username ?? '',
          displayName: r.user.profile?.displayName ?? '',
          avatar: r.user.profile?.avatarBytes && r.user.profile?.avatarMimeType
            ? {
                mimeType: r.user.profile.avatarMimeType,
                data: Buffer.from(r.user.profile.avatarBytes).toString('base64url'),
              }
            : null,
        });
        return acc;
      }, {} as Record<string, { emoji: string; count: number; users: any[] }>);
    };

    return {
      stories: stories.map((s) => ({
        id: s.id,
        userId: s.userId,
        username: s.user.profile?.username ?? '',
        displayName: s.user.profile?.displayName ?? '',
        avatar: s.user.profile?.avatarBytes && s.user.profile?.avatarMimeType
          ? {
              mimeType: s.user.profile.avatarMimeType,
              data: Buffer.from(s.user.profile.avatarBytes).toString('base64url'),
            }
          : null,
        type: s.type,
        media: s.mediaBytes && s.mimeType
          ? {
              mimeType: s.mimeType,
              data: Buffer.from(s.mediaBytes).toString('base64url'),
            }
          : null,
        textContent: s.textContent,
        backgroundStyle: s.backgroundStyle,
        createdAt: s.createdAt.toISOString(),
        expiresAt: s.expiresAt.toISOString(),
        viewedByMe: s.views.some((v) => v.viewerId === viewerId),
        viewsCount: s.views.length,
        reactions: formatReactions(reactionsByStory[s.id] || []),
        myReactions: s.reactions.filter(r => r.userId === viewerId).map(r => r.emoji),
      })),
    };
  }

  async markStoryViewed(viewerId: string, storyId: string) {
    const story = await this.storyForInteraction(storyId, viewerId);

    await this.prisma.storyView.upsert({
      where: { storyId_viewerId: { storyId, viewerId } },
      create: { storyId, viewerId },
      update: {},
    });

    // Fire webhook
    await this.webhooks.onStoryViewed({
      storyId,
      viewerId,
      ownerId: story.userId,
      createdAt: new Date().toISOString(),
    });

    return { success: true };
  }

  async getStoryViewers(userId: string, storyId: string) {
    const story = await this.prisma.story.findUnique({ where: { id: storyId } });
    if (!story) throw new NotFoundException('Story not found');
    if (story.userId !== userId) throw new ForbiddenException('Only owner can view story viewers');

    const views = await this.prisma.storyView.findMany({
      where: { storyId },
      orderBy: { viewedAt: 'desc' },
      include: { viewer: { include: { profile: true } } },
    });

    return {
      viewers: views.map((v) => ({
        userId: v.viewerId,
        username: v.viewer.profile?.username ?? '',
        displayName: v.viewer.profile?.displayName ?? '',
        avatar: v.viewer.profile?.avatarBytes && v.viewer.profile?.avatarMimeType
          ? {
              mimeType: v.viewer.profile.avatarMimeType,
              data: Buffer.from(v.viewer.profile.avatarBytes).toString('base64url'),
            }
          : null,
        viewedAt: v.viewedAt.toISOString(),
      })),
    };
  }

  async deleteStory(userId: string, storyId: string) {
    const story = await this.prisma.story.findUnique({ where: { id: storyId } });
    if (!story) throw new NotFoundException('Story not found');
    if (story.userId !== userId) throw new ForbiddenException('Cannot delete another user story');

    await this.prisma.story.update({
      where: { id: storyId },
      data: { deletedAt: new Date() },
    });

    return { success: true };
  }

  async addReaction(userId: string, storyId: string, dto: AddStoryReactionDto) {
    await this.storyForInteraction(storyId, userId);

    // Upsert reaction (unique constraint on storyId + userId)
    const reaction = await this.prisma.storyReaction.upsert({
      where: {
        storyId_userId: {
          storyId,
          userId,
        },
      },
      create: {
        storyId,
        userId,
        emoji: dto.emoji,
      },
      update: {
        emoji: dto.emoji,
        updatedAt: new Date(),
      },
      include: { user: { include: { profile: true } } },
    });

    // Get updated reaction counts
    const reactions = await this.formatStoryReactions(storyId);

    return {
      success: true,
      reaction: {
        emoji: reaction.emoji,
        userId: reaction.userId,
        username: reaction.user.email?.split('@')[0] ?? 'user',
      },
      reactions,
    };
  }

  async removeReaction(userId: string, storyId: string, emoji: string) {
    const story = await this.prisma.story.findUnique({
      where: { id: storyId },
      select: {
        userId: true,
        deletedAt: true,
        user: { select: { profile: { select: { isPrivate: true } } } },
      },
    });
    if (!story) throw new NotFoundException('Story not found');
    if (story.deletedAt) throw new ForbiddenException('Story is no longer available');
    // Expiry is not checked here on purpose: taking back a reaction you left
    // must keep working after the story has gone.
    await this.visibility.assertMayReadContentOf(
      story.userId,
      story.user?.profile?.isPrivate ?? false,
      userId,
      'stories',
    );

    await this.prisma.storyReaction.deleteMany({
      where: {
        storyId,
        userId,
        emoji,
      },
    });

    const reactions = await this.formatStoryReactions(storyId);

    return {
      success: true,
      reactions,
    };
  }

  /// The reaction list for one story, refused to anyone who may not read the
  /// story itself. `GET /v1/stories/:id/reactions` used to answer for any id a
  /// signed-in caller cared to try, which listed who had reacted to a private
  /// account's story.
  async getStoryReactions(viewerId: string, storyId: string) {
    await this.storyForInteraction(storyId, viewerId);
    return this.formatStoryReactions(storyId);
  }

  private async formatStoryReactions(storyId: string) {
    const reactions = await this.prisma.storyReaction.findMany({
      where: { storyId },
      include: { user: { include: { profile: true } } },
      orderBy: { createdAt: 'asc' },
    });

    // Group by emoji
    const grouped = reactions.reduce((acc, r) => {
      const key = r.emoji;
      if (!acc[key]) {
        acc[key] = { emoji: key, count: 0, users: [] };
      }
      acc[key].count++;
      acc[key].users.push({
        userId: r.userId,
        username: r.user.profile?.username ?? '',
        displayName: r.user.profile?.displayName ?? '',
        avatar: r.user.profile?.avatarBytes && r.user.profile?.avatarMimeType
          ? {
              mimeType: r.user.profile.avatarMimeType,
              data: Buffer.from(r.user.profile.avatarBytes).toString('base64url'),
            }
          : null,
      });
      return acc;
    }, {} as Record<string, { emoji: string; count: number; users: any[] }>);

    return Object.values(grouped);
  }
}
