import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';
import { CreatePostDto } from './dto/create-post.dto';
import { WebhooksService } from '../webhooks/webhooks.service';

@Injectable()
export class PostsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly webhooks: WebhooksService,
    private readonly visibility: ContentVisibilityService,
  ) {}

  private mapPost(post: any, viewerId?: string) {
    const primaryMedia = post.media?.[0];
    const isLiked = viewerId
      ? post.likes?.some((l: any) => l.userId === viewerId) ?? false
      : false;
    // `savedBy` is included scoped to the viewer, so any row present is theirs.
    // This used to be hardcoded false, which made every bookmark look unsaved
    // on a fresh install however many times it had been saved.
    const isSaved = viewerId
      ? post.savedBy?.some((s: any) => s.userId === viewerId) ?? false
      : false;

    return {
      id: post.id,
      userId: post.userId,
      username: post.user.profile?.username ?? '',
      displayName: post.user.profile?.displayName ?? '',
      caption: post.caption ?? '',
      location: post.location,
      avatar: post.user.profile?.avatarBytes && post.user.profile?.avatarMimeType
        ? {
            mimeType: post.user.profile.avatarMimeType,
            data: Buffer.from(post.user.profile.avatarBytes).toString('base64url'),
          }
        : null,
      media: primaryMedia?.mediaBytes && primaryMedia?.mimeType
        ? {
            mimeType: primaryMedia.mimeType,
            data: Buffer.from(primaryMedia.mediaBytes).toString('base64url'),
          }
        : { mimeType: 'image/jpeg', data: '' },
      createdAt: post.createdAt.toISOString(),
      likes: post._count?.likes ?? post.likes?.length ?? 0,
      comments: post._count?.comments ?? post.comments?.length ?? 0,
      liked: isLiked,
      saved: isSaved,
    };
  }

  /// Users whose posts and comments must not reach [viewerId]. See
  /// [ContentVisibilityService], which holds the rule for every surface that
  /// serves someone else's content.
  private hiddenAuthorIds(viewerId?: string): Promise<string[]> {
    return this.visibility.hiddenAuthorIds(viewerId);
  }

  /// Whether [viewerId] may read [ownerId]'s posts.
  ///
  /// The check is on the server rather than in the client because the client is
  /// not trustworthy: `GET /v1/users/:username/posts` is a public route, so
  /// before this existed a private account's photos were readable by anyone —
  /// with no token at all.
  private assertMayReadPostsOf(
    ownerId: string,
    isPrivate: boolean,
    viewerId?: string,
  ): Promise<void> {
    return this.visibility.assertMayReadContentOf(
      ownerId,
      isPrivate,
      viewerId,
      'posts',
    );
  }

  async getFeed(viewerId: string, cursor?: string, limit = 20) {
    const [following, hiddenAuthors] = await Promise.all([
      this.prisma.follow.findMany({
        where: { followerId: viewerId },
        select: { followingId: true },
      }),
      this.hiddenAuthorIds(viewerId),
    ]);

    // A block should end the reading relationship even if the follow edge
    // outlived it, so blocked authors come out of the list rather than being
    // relied on to have been unfollowed.
    const hidden = new Set(hiddenAuthors);
    const targetUserIds = [viewerId, ...following.map((f) => f.followingId)].filter(
      (id) => !hidden.has(id),
    );

    const posts = await this.prisma.post.findMany({
      where: {
        userId: { in: targetUserIds },
        deletedAt: null,
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      take: Math.min(limit, 50),
      orderBy: { createdAt: 'desc' },
      include: {
        user: { include: { profile: true } },
        media: { orderBy: { order: 'asc' } },
        likes: { where: { userId: viewerId } },
        savedBy: { where: { userId: viewerId } },
        _count: { select: { likes: true, comments: { where: { deletedAt: null } } } },
      },
    });

    return {
      posts: posts.map((p) => this.mapPost(p, viewerId)),
      nextCursor: posts.length === limit ? posts[posts.length - 1]?.createdAt.toISOString() : null,
    };
  }

  async getExplore(viewerId?: string, cursor?: string, limit = 24) {
    const hiddenAuthors = await this.hiddenAuthorIds(viewerId);

    const posts = await this.prisma.post.findMany({
      where: {
        deletedAt: null,
        // Explore is a public surface — it is served without a token — so a
        // private account's posts have no business here. They used to appear,
        // which made "Private account" a switch that only gated follow
        // requests while the photos stayed in everyone's grid.
        user: { profile: { isPrivate: false } },
        ...(hiddenAuthors.length ? { userId: { notIn: hiddenAuthors } } : {}),
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      take: Math.min(limit, 60),
      orderBy: { createdAt: 'desc' },
      include: {
        user: { include: { profile: true } },
        media: { orderBy: { order: 'asc' } },
        likes: viewerId ? { where: { userId: viewerId } } : false,
        savedBy: viewerId ? { where: { userId: viewerId } } : false,
        _count: { select: { likes: true, comments: { where: { deletedAt: null } } } },
      },
    });

    return {
      posts: posts.map((p) => this.mapPost(p, viewerId)),
      nextCursor: posts.length === limit ? posts[posts.length - 1]?.createdAt.toISOString() : null,
    };
  }

  async getUserPosts(username: string, viewerId?: string, cursor?: string, limit = 20) {
    const profile = await this.prisma.profile.findUnique({
      where: { username: username.toLowerCase().trim() },
    });

    if (!profile) {
      throw new NotFoundException('User not found.');
    }

    await this.assertMayReadPostsOf(profile.userId, profile.isPrivate, viewerId);

    const posts = await this.prisma.post.findMany({
      where: {
        userId: profile.userId,
        deletedAt: null,
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      take: Math.min(limit, 50),
      orderBy: { createdAt: 'desc' },
      include: {
        user: { include: { profile: true } },
        media: { orderBy: { order: 'asc' } },
        likes: viewerId ? { where: { userId: viewerId } } : false,
        savedBy: viewerId ? { where: { userId: viewerId } } : false,
        _count: { select: { likes: true, comments: { where: { deletedAt: null } } } },
      },
    });

    return {
      posts: posts.map((p) => this.mapPost(p, viewerId)),
      nextCursor: posts.length === limit ? posts[posts.length - 1]?.createdAt.toISOString() : null,
    };
  }

  async createPost(userId: string, dto: CreatePostDto) {
    const mediaBytes: any = Buffer.from(dto.media.data, 'base64url');

    const post = await this.prisma.post.create({
      data: {
        userId,
        caption: dto.caption?.trim() ?? '',
        location: dto.location?.trim() ?? null,
        media: {
          create: {
            mediaBytes,
            mimeType: dto.media.mimeType,
            type: dto.media.mimeType.startsWith('video') ? 'video' : 'image',
            order: 0,
          },
        },
      },
      include: { media: true },
    });

    // Fire webhook
    await this.webhooks.onPostCreated({
      postId: post.id,
      userId,
      caption: dto.caption?.trim() ?? '',
      location: dto.location?.trim() ?? null,
      mediaCount: 1,
      hasVideo: dto.media.mimeType.startsWith('video'),
      createdAt: post.createdAt.toISOString(),
    });

    return {
      id: post.id,
      createdAt: post.createdAt.toISOString(),
    };
  }

  async deletePost(userId: string, postId: string) {
    const post = await this.prisma.post.findUnique({ where: { id: postId } });
    if (!post || post.deletedAt) throw new NotFoundException('Post not found');
    if (post.userId !== userId) throw new ForbiddenException('Cannot delete another user post');

    await this.prisma.post.update({
      where: { id: postId },
      data: { deletedAt: new Date() },
    });

    // Fire webhook
    await this.webhooks.onPostDeleted({
      postId,
      userId,
      createdAt: new Date().toISOString(),
    });

    return { success: true };
  }

  /// Loads a post that [viewerId] is allowed to act on — like, comment or save.
  ///
  /// A post id is guessable and these routes take one straight from the client,
  /// so each has to answer the same question the read routes do. A blocked
  /// viewer must not be able to like or comment, because both reach the author
  /// as a notification, and a private account's posts are its followers' to
  /// interact with.
  private async postForInteraction(postId: string, viewerId: string) {
    const post = await this.prisma.post.findFirst({
      where: { id: postId, deletedAt: null },
      select: {
        id: true,
        userId: true,
        user: { select: { profile: { select: { isPrivate: true } } } },
      },
    });
    if (!post) throw new NotFoundException('Post not found.');

    await this.visibility.assertMayReadContentOf(
      post.userId,
      post.user?.profile?.isPrivate ?? false,
      viewerId,
      'posts',
    );
    return post;
  }

  async likePost(userId: string, postId: string) {
    const post = await this.postForInteraction(postId, userId);

    await this.prisma.like.upsert({
      where: { userId_postId: { userId, postId } },
      create: { userId, postId },
      update: {},
    });

    // Create notification
    if (post.userId !== userId) {
      await this.prisma.notification.create({
        data: {
          userId: post.userId,
          actorId: userId,
          type: 'like',
          postId,
        },
      }).catch(() => {});
    }

    // Fire webhook
    await this.webhooks.onPostLiked({
      postId,
      userId,
      postOwnerId: post.userId,
      createdAt: new Date().toISOString(),
    });

    return { success: true };
  }

  async unlikePost(userId: string, postId: string) {
    await this.prisma.like.deleteMany({
      where: { userId, postId },
    });
    return { success: true };
  }

  /**
   * Bookmarks a post for this user only.
   *
   * No notification and no published count: the author is never told, which is
   * what keeps a save different from a like. A deleted post cannot be saved,
   * and the unique (user, post) index makes a repeat save a no-op.
   */
  async savePost(userId: string, postId: string) {
    await this.postForInteraction(postId, userId);

    await this.prisma.savedPost.upsert({
      where: { userId_postId: { userId, postId } },
      create: { userId, postId },
      update: {},
    });
    return { success: true, saved: true };
  }

  async unsavePost(userId: string, postId: string) {
    await this.prisma.savedPost.deleteMany({ where: { userId, postId } });
    return { success: true, saved: false };
  }

  /**
   * The viewer's own saved posts, newest save first.
   *
   * Only ever reads rows belonging to [userId]; there is no route that lists
   * another account's saves. Posts deleted since being saved are skipped.
   */
  async getSavedPosts(userId: string, cursor?: string, limit = 30) {
    const hiddenAuthors = await this.hiddenAuthorIds(userId);

    const saves = await this.prisma.savedPost.findMany({
      where: {
        userId,
        post: {
          deletedAt: null,
          // A bookmark made before the block stays in the table, but it stops
          // being served: blocking someone should not leave their photo in your
          // Saved tab.
          ...(hiddenAuthors.length ? { userId: { notIn: hiddenAuthors } } : {}),
        },
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      take: Math.min(limit, 60),
      orderBy: { createdAt: 'desc' },
      include: {
        post: {
          include: {
            user: { include: { profile: true } },
            media: { orderBy: { order: 'asc' } },
            likes: { where: { userId } },
            savedBy: { where: { userId } },
            _count: {
              select: { likes: true, comments: { where: { deletedAt: null } } },
            },
          },
        },
      },
    });

    return {
      posts: saves.map((s) => this.mapPost(s.post, userId)),
      // Cursor over the save time, not the post time — the list is ordered by
      // when it was bookmarked.
      nextCursor:
        saves.length === limit
          ? saves[saves.length - 1]?.createdAt.toISOString()
          : null,
    };
  }

  async getComments(postId: string, viewerId?: string) {
    // The route is public, so the post's own audience has to be checked here
    // too: without this, a private account's comment thread was readable by
    // anyone holding a post id.
    const post = await this.prisma.post.findFirst({
      where: { id: postId, deletedAt: null },
      select: {
        userId: true,
        user: { select: { profile: { select: { isPrivate: true } } } },
      },
    });
    if (!post) throw new NotFoundException('Post not found.');
    await this.visibility.assertMayReadContentOf(
      post.userId,
      post.user?.profile?.isPrivate ?? false,
      viewerId,
      'posts',
    );

    const hiddenAuthors = await this.hiddenAuthorIds(viewerId);

    const comments = await this.prisma.comment.findMany({
      where: {
        postId,
        deletedAt: null,
        // Blocking someone hides what they wrote, in both directions. The row
        // stays — the comment is still there for everyone else, including its
        // author — it is simply not served to this reader.
        ...(hiddenAuthors.length ? { userId: { notIn: hiddenAuthors } } : {}),
      },
      orderBy: { createdAt: 'asc' },
      include: { user: { include: { profile: true } } },
    });

    return {
      comments: comments.map((c) => ({
        id: c.id,
        userId: c.userId,
        username: c.user.profile?.username ?? '',
        displayName: c.user.profile?.displayName ?? '',
        text: c.text,
        createdAt: c.createdAt.toISOString(),
        avatar: c.user.profile?.avatarBytes && c.user.profile?.avatarMimeType
          ? {
              mimeType: c.user.profile.avatarMimeType,
              data: Buffer.from(c.user.profile.avatarBytes).toString('base64url'),
            }
          : null,
      })),
    };
  }

  async addComment(userId: string, postId: string, text: string) {
    const post = await this.postForInteraction(postId, userId);

    const comment = await this.prisma.comment.create({
      data: {
        userId,
        postId,
        text: text.trim(),
      },
    });

    // Notify post owner
    if (post.userId !== userId) {
      await this.prisma.notification.create({
        data: {
          userId: post.userId,
          actorId: userId,
          type: 'comment',
          postId,
          commentId: comment.id,
        },
      }).catch(() => {});
    }

    // Fire webhook
    await this.webhooks.onPostCommented({
      postId,
      commentId: comment.id,
      userId,
      postOwnerId: post.userId,
      text: text.trim(),
      createdAt: comment.createdAt.toISOString(),
    });

    return {
      id: comment.id,
      createdAt: comment.createdAt.toISOString(),
    };
  }

  async deleteComment(userId: string, commentId: string) {
    const comment = await this.prisma.comment.findUnique({ where: { id: commentId } });
    if (!comment || comment.deletedAt) throw new NotFoundException('Comment not found');
    if (comment.userId !== userId) throw new ForbiddenException('Cannot delete another user comment');

    await this.prisma.comment.update({
      where: { id: commentId },
      data: { deletedAt: new Date() },
    });

    return { success: true };
  }
}
