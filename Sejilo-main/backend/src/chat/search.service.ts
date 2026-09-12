import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { SearchMessagesDto } from './dto/search-messages.dto';
import { Prisma } from '@prisma/client';

@Injectable()
export class SearchService {
  constructor(private readonly prisma: PrismaService) {}

  async searchMessages(userId: string, dto: SearchMessagesDto) {
    const limit = Math.min(dto.limit || 20, 100);
    const offset = dto.offset || 0;

    // Build where clause with all filters
    const where: Prisma.MessageWhereInput = {
      deletedAt: null,
      conversation: {
        members: {
          some: {
            userId,
            leftAt: null,
          },
        },
      },
    };

    // Text search using PostgreSQL full-text search via gin_trgm_ops
    if (dto.query && dto.query.trim()) {
      where.text = {
        contains: dto.query.trim(),
        mode: 'insensitive',
      };
    }

    // Filter by conversation
    if (dto.conversationId) {
      where.conversationId = dto.conversationId;
    }

    // Filter by sender
    if (dto.senderId) {
      where.senderId = dto.senderId;
    }

    // Date range filters
    if (dto.dateFrom || dto.dateTo) {
      where.createdAt = {};
      if (dto.dateFrom) {
        where.createdAt = {
          ...where.createdAt,
          gte: new Date(dto.dateFrom),
        };
      }
      if (dto.dateTo) {
        where.createdAt = {
          ...where.createdAt,
          lte: new Date(dto.dateTo),
        };
      }
    }

    // Filter by media presence
    if (dto.hasMedia !== undefined) {
      if (dto.hasMedia) {
        where.OR = [
          { mediaBytes: { not: null } },
          { mediaUrl: { not: null } },
        ];
      } else {
        where.AND = [
          { mediaBytes: null },
          { mediaUrl: null },
        ];
      }
    }

    // Filter by reactions
    if (dto.hasReactions !== undefined) {
      if (dto.hasReactions) {
        where.reactions = {
          some: {},
        };
      } else {
        where.reactions = {
          none: {},
        };
      }
    }

    // Filter by message type
    if (dto.messageType) {
      where.messageType = dto.messageType;
    }

    // Execute search with pagination
    const [messages, total] = await Promise.all([
      this.prisma.message.findMany({
        where,
        include: {
          sender: { include: { profile: true } },
          reactions: {
            include: { user: { include: { profile: true } } },
          },
          conversation: true,
        },
        orderBy: { createdAt: 'desc' },
        take: limit,
        skip: offset,
      }),
      this.prisma.message.count({ where }),
    ]);

    return {
      data: messages.map((msg) => ({
        id: msg.id,
        conversationId: msg.conversationId,
        senderId: msg.senderId,
        senderUsername: msg.sender?.profile?.username ?? '',
        senderDisplayName: msg.sender?.profile?.displayName ?? '',
        text: msg.text ?? '',
        messageType: msg.messageType,
        hasMedia: !!(msg.mediaBytes || msg.mediaUrl),
        status: msg.status,
        reactionCount: msg.reactions.length,
        reactions: msg.reactions.map((r) => ({
          emoji: r.emoji,
          userId: r.userId,
          username: r.user?.profile?.username ?? '',
        })),
        createdAt: msg.createdAt.toISOString(),
      })),
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + limit < total,
      },
    };
  }

  async searchPosts(userId: string, query: string, limit = 20, offset = 0) {
    const trimmedQuery = query.trim();
    const maxLimit = Math.min(limit, 100);

    // Build where clause - search posts accessible to user
    const where: Prisma.PostWhereInput = {
      deletedAt: null,
      caption: {
        contains: trimmedQuery,
        mode: 'insensitive',
      },
      user: {
        OR: [
          { id: userId }, // User's own posts
          {
            followers: {
              some: { followerId: userId },
            },
          }, // Posts from followed users
          {
            profile: { isPrivate: false },
          }, // Public posts
        ],
      },
    };

    const [posts, total] = await Promise.all([
      this.prisma.post.findMany({
        where,
        include: {
          user: { include: { profile: true } },
          media: true,
          _count: {
            select: { likes: true, comments: true },
          },
        },
        orderBy: { createdAt: 'desc' },
        take: maxLimit,
        skip: offset,
      }),
      this.prisma.post.count({ where }),
    ]);

    return {
      data: posts.map((post) => ({
        id: post.id,
        userId: post.userId,
        username: post.user.profile?.username ?? '',
        displayName: post.user.profile?.displayName ?? '',
        caption: post.caption ?? '',
        mediaCount: post.media.length,
        likesCount: post._count.likes,
        commentsCount: post._count.comments,
        createdAt: post.createdAt.toISOString(),
      })),
      pagination: {
        total,
        limit: maxLimit,
        offset,
        hasMore: offset + maxLimit < total,
      },
    };
  }

  async searchHashtags(query: string, limit = 20, offset = 0) {
    const trimmedQuery = query.toLowerCase().trim();
    const maxLimit = Math.min(limit, 100);

    // Extract hashtags from posts (simple approach - can be optimized with a hashtag table)
    // For now, search post captions containing hashtags
    const posts = await this.prisma.post.findMany({
      where: {
        deletedAt: null,
        caption: {
          contains: `#${trimmedQuery}`,
          mode: 'insensitive',
        },
      },
      select: { caption: true },
      take: maxLimit * 2, // Get extra to extract unique hashtags
      skip: offset,
    });

    // Extract unique hashtags from captions
    const hashtags = new Set<string>();
    const hashtagRegex = /#[\w]+/g;

    posts.forEach((post) => {
      if (post.caption) {
        const matches = post.caption.match(hashtagRegex);
        if (matches) {
          matches.forEach((tag) => {
            const normalized = tag.toLowerCase();
            if (normalized.includes(trimmedQuery)) {
              hashtags.add(normalized);
            }
          });
        }
      }
    });

    // Count posts for each hashtag
    const hashtagStats = await Promise.all(
      Array.from(hashtags)
        .slice(0, maxLimit)
        .map(async (tag) => {
          const count = await this.prisma.post.count({
            where: {
              deletedAt: null,
              caption: {
                contains: tag,
                mode: 'insensitive',
              },
            },
          });
          return { tag, count };
        }),
    );

    return {
      data: hashtagStats.sort((a, b) => b.count - a.count),
      pagination: {
        limit: maxLimit,
        offset,
      },
    };
  }
}
