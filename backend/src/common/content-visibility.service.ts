import { ForbiddenException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * The one place that decides whether a viewer is allowed to read another
 * account's content.
 *
 * It lives on its own because the same two rules — "a block cuts reading in both
 * directions" and "a private account is open only to accepted followers" — have
 * to hold for posts, comments, stories and search alike. Written out separately
 * in each service they drift, and a rule that holds in three places out of four
 * is not a rule.
 *
 * Two things are deliberately *not* handled here:
 *
 * - A `Block` row with `isMuted: true` is a mute, not a block. The two share one
 *   table; a mute only silences notifications, so it must never hide content.
 * - A missing viewer (`undefined`) is an anonymous caller on a public route, not
 *   an error. Anonymous callers are refused private accounts and are subject to
 *   no blocks, because there is nobody to have blocked.
 */
@Injectable()
export class ContentVisibilityService {
  constructor(private readonly prisma: PrismaService) {}

  /// Users whose posts, comments and stories must not reach [viewerId]: the
  /// people they blocked, and the people who blocked them.
  async hiddenAuthorIds(viewerId?: string): Promise<string[]> {
    if (!viewerId) return [];
    const rows = await this.prisma.block.findMany({
      where: {
        isMuted: false,
        OR: [{ blockerId: viewerId }, { blockedId: viewerId }],
      },
      select: { blockerId: true, blockedId: true },
    });
    return rows.map((r) => (r.blockerId === viewerId ? r.blockedId : r.blockerId));
  }

  /// Whether either of [a] or [b] has blocked the other.
  async isBlockedBetween(a: string, b: string): Promise<boolean> {
    if (a === b) return false;
    const block = await this.prisma.block.findFirst({
      where: {
        isMuted: false,
        OR: [
          { blockerId: a, blockedId: b },
          { blockerId: b, blockedId: a },
        ],
      },
      select: { id: true },
    });
    return block !== null;
  }

  /// Whether [viewerId] may read [ownerId]'s content, and why not when they may
  /// not. The account owner always may; a block in either direction always
  /// refuses; a private account is open only to accepted followers.
  ///
  /// [subject] only shapes the sentence the caller sees ("…to see its posts").
  async assertMayReadContentOf(
    ownerId: string,
    isPrivate: boolean,
    viewerId?: string,
    subject = 'posts',
  ): Promise<void> {
    if (viewerId === ownerId) return;

    if (viewerId && (await this.isBlockedBetween(viewerId, ownerId))) {
      throw new ForbiddenException('This account is not available.');
    }

    if (!isPrivate) return;

    const follows = viewerId
      ? await this.prisma.follow.findUnique({
          where: {
            followerId_followingId: { followerId: viewerId, followingId: ownerId },
          },
          select: { id: true },
        })
      : null;

    if (!follows) {
      throw new ForbiddenException(
        `This account is private. Follow it to see its ${subject}.`,
      );
    }
  }

  /// [assertMayReadContentOf] for a caller that holds an owner id but has not
  /// read their privacy flag — one extra query, and the same refusals.
  async assertMayReadContentOfUser(
    ownerId: string,
    viewerId?: string,
    subject = 'posts',
  ): Promise<void> {
    if (viewerId === ownerId) return;
    const profile = await this.prisma.profile.findUnique({
      where: { userId: ownerId },
      select: { isPrivate: true },
    });
    await this.assertMayReadContentOf(
      ownerId,
      profile?.isPrivate ?? false,
      viewerId,
      subject,
    );
  }
}
