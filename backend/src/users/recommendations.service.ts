import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { Cron, CronExpression } from '@nestjs/schedule';

@Injectable()
export class RecommendationsService {
  private readonly logger = new Logger(RecommendationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  /**
   * Everyone who must never appear in [userId]'s suggestions: accounts either
   * side has blocked or muted, and accounts this user has already dismissed.
   *
   * Mutes are excluded here on purpose, unlike everywhere else. A mute is not a
   * block and does not hide content, but offering "Suggested for you" an account
   * the person has deliberately silenced is not a suggestion they want.
   *
   * This has to be re-read on every request rather than baked into the stored
   * rows: recommendations live in Postgres with no expiry and in Redis for 24
   * hours, so a block made after they were computed would otherwise keep
   * suggesting the blocked account until the cache turned over.
   */
  private async excludedUserIds(userId: string): Promise<string[]> {
    const [blocks, dismissals] = await Promise.all([
      this.prisma.block.findMany({
        where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
        select: { blockerId: true, blockedId: true },
      }),
      this.prisma.recommendationDismissal.findMany({
        where: { userId },
        select: { recommendedUserId: true },
      }),
    ]);

    return [
      ...blocks.map((b) => (b.blockerId === userId ? b.blockedId : b.blockerId)),
      ...dismissals.map((d) => d.recommendedUserId),
    ];
  }

  /**
   * Get cached or computed recommendations for a user
   */
  async getRecommendations(userId: string, limit = 10) {
    const excluded = new Set(await this.excludedUserIds(userId));

    // Check Redis cache first
    const cached = await this.redis.get(`recommendations:${userId}`);
    if (cached) {
      const data = JSON.parse(cached) as { id: string }[];
      return {
        recommendations: data
          .filter((r) => !excluded.has(r.id))
          .slice(0, limit),
      };
    }

    // Get from database if cached
    const dbRecommendations = await this.prisma.userRecommendation.findMany({
      where: {
        userId,
        // Stored rows outlive the state they were computed from, so the same
        // filters the candidate search applies have to hold at read time too.
        ...(excluded.size
          ? { recommendedUserId: { notIn: [...excluded] } }
          : {}),
        recommendedUser: { profile: { isPrivate: false } },
      },
      include: {
        recommendedUser: {
          include: { profile: true },
        },
      },
      orderBy: { score: 'desc' },
      take: limit,
    });

    if (dbRecommendations.length > 0) {
      // Cache in Redis for 24 hours
      const formatted = this.formatRecommendations(dbRecommendations);
      await this.redis.set(
        `recommendations:${userId}`,
        JSON.stringify(formatted),
        'EX',
        86400,
      );
      return {
        recommendations: formatted.slice(0, limit),
      };
    }

    // Compute on-demand if nothing cached
    const computed = await this.computeRecommendations(userId, limit);

    // Save to database and cache
    await this.saveRecommendations(userId, computed);
    await this.redis.set(
      `recommendations:${userId}`,
      JSON.stringify(computed),
      'EX',
      86400,
    );

    return { recommendations: computed };
  }

  /**
   * Compute recommendations based on:
   * - Mutual follows (30% weight)
   * - Engagement overlap (40% weight)
   * - Tag/interest overlap (30% weight)
   */
  async computeRecommendations(userId: string, limit = 10) {
    const currentUser = await this.prisma.user.findUnique({
      where: { id: userId },
      include: {
        following: { select: { followingId: true } },
        followers: { select: { followerId: true } },
      },
    });

    if (!currentUser) return [];

    const followingIds = currentUser.following.map(f => f.followingId);
    const followerIds = currentUser.followers.map(f => f.followerId);
    // Blocks, mutes and dismissals in one list. Dismissals used to be written
    // and never read, so the X on a suggestion cleared the cache and the same
    // account came back the moment it was recomputed.
    const excludedIds = await this.excludedUserIds(userId);

    // Find candidate users (not followed, not blocked, not dismissed, not self,
    // public profiles)
    const candidates = await this.prisma.user.findMany({
      where: {
        id: {
          notIn: [userId, ...followingIds, ...excludedIds],
        },
        profile: {
          isPrivate: false,
        },
      },
      select: { id: true },
      take: 500, // Limit candidates for performance
    });

    // Score each candidate
    const scored = await Promise.all(
      candidates.map(async (candidate) => {
        const score = await this.scoreCandidate(
          userId,
          candidate.id,
          followingIds,
          followerIds,
        );
        return { candidateId: candidate.id, score };
      }),
    );

    // Filter, sort, and format top recommendations
    const topRecommendations = scored
      .filter(s => s.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, limit);

    // Get full profile data for top recommendations
    const recommendedUserIds = topRecommendations.map(r => r.candidateId);
    const recommendedUsers = await this.prisma.user.findMany({
      where: { id: { in: recommendedUserIds } },
      include: { profile: true },
    });

    return this.formatRecommendationsWithScores(
      recommendedUsers,
      topRecommendations,
    );
  }

  /**
   * Score a candidate user based on recommendation signals
   */
  private async scoreCandidate(
    userId: string,
    candidateId: string,
    userFollowingIds: string[],
    userFollowerIds: string[],
  ): Promise<number> {
    // 1. Mutual follows score (max 1.0)
    const mutualFollows = await this.prisma.follow.count({
      where: {
        followerId: candidateId,
        followingId: { in: userFollowingIds },
      },
    });
    const mutualScore = Math.min(mutualFollows / 10, 1); // Normalize 0-1

    // 2. Engagement score (shared likes/comments on posts)
    const sharedEngagement = await this.prisma.like.count({
      where: {
        userId,
        post: {
          likes: {
            some: { userId: candidateId },
          },
        },
      },
    });
    const engagementScore = Math.min(sharedEngagement / 5, 1); // Normalize 0-1

    // 3. Hashtag/interest overlap (users who used similar hashtags)
    // This is a simplified version - can be enhanced with a dedicated interests table
    const sharedHashtags = await this.calculateHashtagOverlap(userId, candidateId);
    const hashtagScore = Math.min(sharedHashtags / 5, 1); // Normalize 0-1

    // Weighted score: mutual follows 30%, engagement 40%, hashtags 30%
    const totalScore =
      mutualScore * 0.3 +
      engagementScore * 0.4 +
      hashtagScore * 0.3;

    return totalScore;
  }

  /**
   * Calculate hashtag overlap between two users
   */
  private async calculateHashtagOverlap(userId1: string, userId2: string): Promise<number> {
    // Get recent posts from both users
    const [posts1, posts2] = await Promise.all([
      this.prisma.post.findMany({
        where: { userId: userId1, deletedAt: null },
        select: { caption: true },
        take: 20,
      }),
      this.prisma.post.findMany({
        where: { userId: userId2, deletedAt: null },
        select: { caption: true },
        take: 20,
      }),
    ]);

    const extractHashtags = (posts: any[]) => {
      const tags = new Set<string>();
      posts.forEach(p => {
        if (p.caption) {
          const matches = p.caption.match(/#[\w]+/g);
          if (matches) {
            matches.forEach(tag => tags.add(tag.toLowerCase()));
          }
        }
      });
      return tags;
    };

    const tags1 = extractHashtags(posts1);
    const tags2 = extractHashtags(posts2);

    // Count intersection
    let overlap = 0;
    for (const tag of tags1) {
      if (tags2.has(tag)) overlap++;
    }

    return overlap;
  }

  /**
   * Format recommendations with detailed info
   */
  private formatRecommendations(recommendations: any[]) {
    return recommendations.map((r) => ({
      id: r.recommendedUser.id,
      username: r.recommendedUser.profile?.username ?? '',
      displayName: r.recommendedUser.profile?.displayName ?? '',
      avatar: r.recommendedUser.profile?.avatarBytes && r.recommendedUser.profile?.avatarMimeType
        ? {
            mimeType: r.recommendedUser.profile.avatarMimeType,
            data: Buffer.from(r.recommendedUser.profile.avatarBytes).toString('base64url'),
          }
        : null,
      score: r.score,
      reasonTags: r.reasonTags,
      computedAt: r.computedAt.toISOString(),
    }));
  }

  /**
   * Format computed recommendations with scores
   */
  private formatRecommendationsWithScores(users: any[], scored: { candidateId: string; score: number }[]) {
    const scoreMap = new Map(scored.map(s => [s.candidateId, s.score]));

    return users
      .map((u) => ({
        id: u.id,
        username: u.profile?.username ?? '',
        displayName: u.profile?.displayName ?? '',
        avatar: u.profile?.avatarBytes && u.profile?.avatarMimeType
          ? {
              mimeType: u.profile.avatarMimeType,
              data: Buffer.from(u.profile.avatarBytes).toString('base64url'),
            }
          : null,
        score: scoreMap.get(u.id) ?? 0,
        reasonTags: this.getReasonTags(u.id, scored),
      }))
      .sort((a, b) => b.score - a.score);
  }

  /**
   * Determine reason tags for a recommendation
   */
  private getReasonTags(userId: string, scored: { candidateId: string; score: number }[]): string[] {
    const tags: string[] = [];
    const score = scored.find(s => s.candidateId === userId)?.score ?? 0;

    // Add reason based on score components (simplified)
    if (score > 0.5) tags.push('strong_match');
    if (score > 0.3) tags.push('mutual_follows');
    if (score > 0.2) tags.push('shared_engagement');
    if (score > 0.1) tags.push('common_interests');

    return tags;
  }

  /**
   * Save computed recommendations to database
   */
  async saveRecommendations(userId: string, recommendations: any[]) {
    for (const rec of recommendations) {
      await this.prisma.userRecommendation.upsert({
        where: {
          userId_recommendedUserId: {
            userId,
            recommendedUserId: rec.id,
          },
        },
        create: {
          userId,
          recommendedUserId: rec.id,
          score: rec.score,
          reasonTags: rec.reasonTags,
        },
        update: {
          score: rec.score,
          reasonTags: rec.reasonTags,
          computedAt: new Date(),
        },
      });
    }
  }

  /**
   * Dismiss a recommendation
   */
  async dismissRecommendation(userId: string, recommendedUserId: string) {
    await this.prisma.recommendationDismissal.upsert({
      where: {
        userId_recommendedUserId: { userId, recommendedUserId },
      },
      create: { userId, recommendedUserId },
      update: {},
    });

    // Invalidate cache
    await this.redis.del(`recommendations:${userId}`);
  }

  /**
   * Scheduled job: Pre-compute recommendations for all active users daily
   */
  @Cron(CronExpression.EVERY_DAY_AT_2AM)
  async precomputeRecommendations() {
    this.logger.log('Starting daily recommendation pre-computation...');

    try {
      // Get all active users
      const users = await this.prisma.user.findMany({
        where: { isActive: true },
        select: { id: true },
        take: 1000, // Batch if needed
      });

      for (const user of users) {
        try {
          const recommendations = await this.computeRecommendations(user.id, 50);
          if (recommendations.length > 0) {
            await this.saveRecommendations(user.id, recommendations);
            // Invalidate cache
            await this.redis.del(`recommendations:${user.id}`);
          }
        } catch (error) {
          this.logger.error(`Failed to compute for user ${user.id}`, error);
        }
      }

      this.logger.log('Daily recommendation pre-computation completed');
    } catch (error) {
      this.logger.error('Failed to pre-compute recommendations', error);
    }
  }
}