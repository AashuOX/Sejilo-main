import { Test, TestingModule } from '@nestjs/testing';
import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { StoriesService } from './stories.service';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';
import { WebhooksService } from '../webhooks/webhooks.service';

const UUID = (n: string) =>
  `${n.repeat(8)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(12)}`;

const VIEWER = UUID('a');
const OWNER = UUID('b');

/// A story row shaped the way the interaction guard reads it.
const makeStoryRow = ({
  isPrivate = false,
  userId = OWNER,
  expired = false,
} = {}) => ({
  id: 's1',
  userId,
  expiresAt: expired
    ? new Date(Date.now() - 60_000)
    : new Date(Date.now() + 60_000),
  deletedAt: null,
  user: { profile: { isPrivate } },
});

describe('StoriesService — who is allowed to see and touch a story', () => {
  let service: StoriesService;
  let prisma: any;
  let webhooks: any;

  beforeEach(async () => {
    prisma = {
      block: {
        findMany: jest.fn().mockResolvedValue([]),
        findFirst: jest.fn().mockResolvedValue(null),
      },
      follow: {
        findMany: jest.fn().mockResolvedValue([]),
        findUnique: jest.fn().mockResolvedValue(null),
      },
      story: {
        findMany: jest.fn().mockResolvedValue([]),
        findFirst: jest.fn(),
        findUnique: jest.fn(),
      },
      storyView: { upsert: jest.fn().mockResolvedValue({}) },
      storyReaction: {
        findMany: jest.fn().mockResolvedValue([]),
        upsert: jest.fn(),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    webhooks = { onStoryViewed: jest.fn(), onStoryCreated: jest.fn() };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StoriesService,
        ContentVisibilityService,
        { provide: PrismaService, useValue: prisma },
        { provide: WebhooksService, useValue: webhooks },
      ],
    }).compile();

    service = module.get<StoriesService>(StoriesService);
    prisma.story.findFirst.mockResolvedValue(makeStoryRow());
    prisma.story.findUnique.mockResolvedValue(makeStoryRow());
  });

  describe('getStories', () => {
    it('drops a blocked account even while the follow edge survives', async () => {
      prisma.follow.findMany.mockResolvedValue([
        { followingId: OWNER },
        { followingId: UUID('e') },
      ]);
      prisma.block.findMany.mockResolvedValue([
        { blockerId: OWNER, blockedId: VIEWER },
      ]);

      await service.getStories(VIEWER);

      const where = prisma.story.findMany.mock.calls[0][0].where;
      expect(where.userId.in).toEqual([VIEWER, UUID('e')]);
    });

    it('a mute is not a block: a muted account keeps its story in the tray', async () => {
      await service.getStories(VIEWER);

      expect(prisma.block.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ isMuted: false }),
        }),
      );
    });
  });

  describe('markStoryViewed', () => {
    it('a blocked viewer is not added to the owner\'s viewer list', async () => {
      prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

      await expect(service.markStoryViewed(VIEWER, 's1')).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.storyView.upsert).not.toHaveBeenCalled();
      expect(webhooks.onStoryViewed).not.toHaveBeenCalled();
    });

    it('a private account\'s story refuses a stranger', async () => {
      prisma.story.findFirst.mockResolvedValue(makeStoryRow({ isPrivate: true }));

      await expect(service.markStoryViewed(VIEWER, 's1')).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.storyView.upsert).not.toHaveBeenCalled();
    });

    it('a private account\'s story opens to an accepted follower', async () => {
      prisma.story.findFirst.mockResolvedValue(makeStoryRow({ isPrivate: true }));
      prisma.follow.findUnique.mockResolvedValue({ id: UUID('f') });

      await expect(service.markStoryViewed(VIEWER, 's1')).resolves.toEqual({
        success: true,
      });
      expect(prisma.storyView.upsert).toHaveBeenCalled();
    });

    it('an expired story cannot be viewed', async () => {
      prisma.story.findFirst.mockResolvedValue(makeStoryRow({ expired: true }));

      await expect(service.markStoryViewed(VIEWER, 's1')).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.storyView.upsert).not.toHaveBeenCalled();
    });

    it('a deleted story is a 404', async () => {
      // The query asks for `deletedAt: null`, so a deleted row simply is not
      // found — which is also what a wrong id looks like.
      prisma.story.findFirst.mockResolvedValue(null);

      await expect(service.markStoryViewed(VIEWER, 's1')).rejects.toThrow(
        NotFoundException,
      );
      expect(prisma.story.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 's1', deletedAt: null },
        }),
      );
    });

    it('the owner viewing their own story needs no block lookup', async () => {
      prisma.story.findFirst.mockResolvedValue(
        makeStoryRow({ isPrivate: true, userId: VIEWER }),
      );

      await service.markStoryViewed(VIEWER, 's1');

      expect(prisma.block.findFirst).not.toHaveBeenCalled();
      expect(prisma.follow.findUnique).not.toHaveBeenCalled();
    });
  });

  describe('reactions', () => {
    it('a blocked viewer cannot react', async () => {
      prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

      await expect(
        service.addReaction(VIEWER, 's1', { emoji: '🔥' } as any),
      ).rejects.toThrow(ForbiddenException);
      expect(prisma.storyReaction.upsert).not.toHaveBeenCalled();
    });

    it('a stranger cannot list who reacted to a private story', async () => {
      prisma.story.findFirst.mockResolvedValue(makeStoryRow({ isPrivate: true }));

      await expect(service.getStoryReactions(VIEWER, 's1')).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.storyReaction.findMany).not.toHaveBeenCalled();
    });

    it('taking back your own reaction still works after the story expired',
      async () => {
        prisma.story.findUnique.mockResolvedValue(
          makeStoryRow({ expired: true }),
        );

        await expect(
          service.removeReaction(VIEWER, 's1', '🔥'),
        ).resolves.toMatchObject({ success: true });
        expect(prisma.storyReaction.deleteMany).toHaveBeenCalledWith({
          where: { storyId: 's1', userId: VIEWER, emoji: '🔥' },
        });
      });

    it('a blocked viewer cannot remove a reaction either', async () => {
      prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

      await expect(
        service.removeReaction(VIEWER, 's1', '🔥'),
      ).rejects.toThrow(ForbiddenException);
      expect(prisma.storyReaction.deleteMany).not.toHaveBeenCalled();
    });
  });

  describe('getStoryViewers', () => {
    it('only the owner may read who watched', async () => {
      prisma.story.findUnique.mockResolvedValue({ id: 's1', userId: OWNER });

      await expect(service.getStoryViewers(VIEWER, 's1')).rejects.toThrow(
        ForbiddenException,
      );
    });
  });
});
