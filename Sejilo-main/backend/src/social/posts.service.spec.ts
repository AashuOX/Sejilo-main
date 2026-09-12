import { Test, TestingModule } from '@nestjs/testing';
import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { PostsService } from './posts.service';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';
import { WebhooksService } from '../webhooks/webhooks.service';

const UUID = (n: string) =>
  `${n.repeat(8)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(12)}`;

const VIEWER = UUID('a');
const OWNER = UUID('b');

/// One row shaped the way `mapPost` expects to read it.
const makePostRow = (id: string, userId: string, username: string) => ({
  id,
  userId,
  caption: 'A photo',
  location: null,
  createdAt: new Date('2026-08-29T10:00:00.000Z'),
  user: { profile: { username, displayName: username, avatarBytes: null, avatarMimeType: null } },
  media: [{ mediaBytes: Buffer.from([1, 2, 3]), mimeType: 'image/jpeg' }],
  likes: [],
  savedBy: [],
  _count: { likes: 0, comments: 0 },
});

/// One row shaped the way the interaction guard expects to read it: the author
/// of the post, and whether their account is private.
const makeInteractionRow = (isPrivate = false, userId = OWNER) => ({
  id: 'p1',
  userId,
  user: { profile: { isPrivate } },
});

describe('PostsService — who is allowed to read posts', () => {
  let service: PostsService;
  let prisma: any;

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
      profile: { findUnique: jest.fn() },
      post: { findMany: jest.fn().mockResolvedValue([]), findFirst: jest.fn() },
      comment: { findMany: jest.fn().mockResolvedValue([]), create: jest.fn() },
      savedPost: { findMany: jest.fn().mockResolvedValue([]), upsert: jest.fn() },
      like: { upsert: jest.fn() },
      notification: { create: jest.fn().mockResolvedValue({}) },
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PostsService,
        // The real visibility service, driven by the same mocked Prisma: these
        // tests are about the queries the rule produces, so stubbing the rule
        // would leave nothing under test.
        ContentVisibilityService,
        { provide: PrismaService, useValue: prisma },
        {
          provide: WebhooksService,
          useValue: {
            onPostCreated: jest.fn(),
            onPostLiked: jest.fn(),
            onPostCommented: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<PostsService>(PostsService);
    // The default for every interaction and comment test: a post that exists and
    // belongs to a public account. Tests that need otherwise override it.
    prisma.post.findFirst.mockResolvedValue(makeInteractionRow());
  });

  describe('getUserPosts', () => {
    it('a public account is readable by a stranger, and by no one in particular', async () => {
      prisma.profile.findUnique.mockResolvedValue({ userId: OWNER, isPrivate: false });
      prisma.post.findMany.mockResolvedValue([makePostRow('p1', OWNER, 'bob')]);

      await expect(service.getUserPosts('bob', VIEWER)).resolves.toMatchObject({
        posts: [{ id: 'p1', username: 'bob' }],
      });
      // No token at all — the route is public.
      await expect(service.getUserPosts('bob')).resolves.toMatchObject({
        posts: [{ id: 'p1' }],
      });
    });

    it('a private account refuses a stranger', async () => {
      prisma.profile.findUnique.mockResolvedValue({ userId: OWNER, isPrivate: true });

      await expect(service.getUserPosts('bob', VIEWER)).rejects.toThrow(ForbiddenException);
      // Nothing was read out of the database before the refusal.
      expect(prisma.post.findMany).not.toHaveBeenCalled();
    });

    it('a private account refuses an anonymous caller', async () => {
      prisma.profile.findUnique.mockResolvedValue({ userId: OWNER, isPrivate: true });

      await expect(service.getUserPosts('bob')).rejects.toThrow(ForbiddenException);
      expect(prisma.post.findMany).not.toHaveBeenCalled();
    });

    it('a private account opens to an accepted follower', async () => {
      prisma.profile.findUnique.mockResolvedValue({ userId: OWNER, isPrivate: true });
      prisma.follow.findUnique.mockResolvedValue({ id: UUID('f') });
      prisma.post.findMany.mockResolvedValue([makePostRow('p1', OWNER, 'bob')]);

      await expect(service.getUserPosts('bob', VIEWER)).resolves.toMatchObject({
        posts: [{ id: 'p1' }],
      });
      expect(prisma.follow.findUnique).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            followerId_followingId: { followerId: VIEWER, followingId: OWNER },
          },
        }),
      );
    });

    it('the owner always sees their own private grid', async () => {
      prisma.profile.findUnique.mockResolvedValue({ userId: OWNER, isPrivate: true });
      prisma.post.findMany.mockResolvedValue([makePostRow('p1', OWNER, 'bob')]);

      await expect(service.getUserPosts('bob', OWNER)).resolves.toMatchObject({
        posts: [{ id: 'p1' }],
      });
      // Their own grid needs no follow edge and no block lookup.
      expect(prisma.block.findFirst).not.toHaveBeenCalled();
    });

    it('a block refuses the grid whichever side set it', async () => {
      prisma.profile.findUnique.mockResolvedValue({ userId: OWNER, isPrivate: false });
      prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

      await expect(service.getUserPosts('bob', VIEWER)).rejects.toThrow(ForbiddenException);
      expect(prisma.block.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ isMuted: false }),
        }),
      );
    });

    it('an unknown username is still a 404, not a 403', async () => {
      prisma.profile.findUnique.mockResolvedValue(null);

      await expect(service.getUserPosts('nobody', VIEWER)).rejects.toThrow(NotFoundException);
    });
  });

  describe('getExplore', () => {
    it('leaves out private accounts and blocked authors', async () => {
      prisma.block.findMany.mockResolvedValue([
        { blockerId: VIEWER, blockedId: OWNER },
        { blockerId: UUID('d'), blockedId: VIEWER },
      ]);

      await service.getExplore(VIEWER);

      const where = prisma.post.findMany.mock.calls[0][0].where;
      expect(where.user).toEqual({ profile: { isPrivate: false } });
      // Both directions of the block are excluded, named as the other party.
      expect(where.userId.notIn.sort()).toEqual([OWNER, UUID('d')].sort());
    });

    it('needs no block lookup for an anonymous caller, and still hides private accounts', async () => {
      await service.getExplore();

      expect(prisma.block.findMany).not.toHaveBeenCalled();
      const where = prisma.post.findMany.mock.calls[0][0].where;
      expect(where.user).toEqual({ profile: { isPrivate: false } });
      expect(where.userId).toBeUndefined();
    });

    it('a mute is not a block: a muted account stays in explore', async () => {
      await service.getExplore(VIEWER);

      // Muting shares the block table, so the query has to say so explicitly.
      expect(prisma.block.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ isMuted: false }),
        }),
      );
    });
  });

  describe('getFeed', () => {
    it('drops a blocked author even while the follow edge survives', async () => {
      prisma.follow.findMany.mockResolvedValue([
        { followingId: OWNER },
        { followingId: UUID('e') },
      ]);
      prisma.block.findMany.mockResolvedValue([{ blockerId: OWNER, blockedId: VIEWER }]);

      await service.getFeed(VIEWER);

      const where = prisma.post.findMany.mock.calls[0][0].where;
      expect(where.userId.in).toEqual([VIEWER, UUID('e')]);
    });
  });

  describe('getComments', () => {
    it('leaves out comments written by a blocked user', async () => {
      prisma.block.findMany.mockResolvedValue([{ blockerId: VIEWER, blockedId: OWNER }]);

      await service.getComments('p1', VIEWER);

      const where = prisma.comment.findMany.mock.calls[0][0].where;
      expect(where.userId).toEqual({ notIn: [OWNER] });
    });

    it('asks for nothing extra when the viewer has blocked no one', async () => {
      await service.getComments('p1', VIEWER);

      const where = prisma.comment.findMany.mock.calls[0][0].where;
      expect(where.userId).toBeUndefined();
      expect(where).toMatchObject({ postId: 'p1', deletedAt: null });
    });

    it('a private account keeps its comment thread to its followers', async () => {
      prisma.post.findFirst.mockResolvedValue(makeInteractionRow(true));

      await expect(service.getComments('p1', VIEWER)).rejects.toThrow(
        ForbiddenException,
      );
      // The route is public, so the anonymous caller is refused as well.
      await expect(service.getComments('p1')).rejects.toThrow(ForbiddenException);
      expect(prisma.comment.findMany).not.toHaveBeenCalled();
    });

    it('a deleted post has no comments to read', async () => {
      prisma.post.findFirst.mockResolvedValue(null);

      await expect(service.getComments('p1', VIEWER)).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('likes, comments and saves are gated too', () => {
    it('a blocked viewer cannot like, and no notification is written', async () => {
      prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

      await expect(service.likePost(VIEWER, 'p1')).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.like.upsert).not.toHaveBeenCalled();
      expect(prisma.notification.create).not.toHaveBeenCalled();
    });

    it('a blocked viewer cannot comment', async () => {
      prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

      await expect(service.addComment(VIEWER, 'p1', 'hi')).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.comment.create).not.toHaveBeenCalled();
    });

    it('a private account will not take a like from a stranger', async () => {
      prisma.post.findFirst.mockResolvedValue(makeInteractionRow(true));

      await expect(service.likePost(VIEWER, 'p1')).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.like.upsert).not.toHaveBeenCalled();
    });

    it('a private account takes a like from an accepted follower', async () => {
      prisma.post.findFirst.mockResolvedValue(makeInteractionRow(true));
      prisma.follow.findUnique.mockResolvedValue({ id: UUID('f') });

      await expect(service.likePost(VIEWER, 'p1')).resolves.toEqual({
        success: true,
      });
      expect(prisma.like.upsert).toHaveBeenCalled();
      expect(prisma.notification.create).toHaveBeenCalled();
    });

    it('a post that is gone cannot be saved', async () => {
      prisma.post.findFirst.mockResolvedValue(null);

      await expect(service.savePost(VIEWER, 'p1')).rejects.toThrow(
        NotFoundException,
      );
      expect(prisma.savedPost.upsert).not.toHaveBeenCalled();
    });

    it('liking your own post writes no notification to yourself', async () => {
      prisma.post.findFirst.mockResolvedValue(makeInteractionRow(true, VIEWER));

      await service.likePost(VIEWER, 'p1');

      expect(prisma.like.upsert).toHaveBeenCalled();
      expect(prisma.notification.create).not.toHaveBeenCalled();
      // Your own post needs no block lookup and no follow edge.
      expect(prisma.block.findFirst).not.toHaveBeenCalled();
      expect(prisma.follow.findUnique).not.toHaveBeenCalled();
    });
  });

  describe('getSavedPosts', () => {
    it('stops serving a bookmark once its author is blocked', async () => {
      prisma.block.findMany.mockResolvedValue([
        { blockerId: VIEWER, blockedId: OWNER },
      ]);

      await service.getSavedPosts(VIEWER);

      const where = prisma.savedPost.findMany.mock.calls[0][0].where;
      expect(where.userId).toEqual(VIEWER);
      expect(where.post).toEqual({
        deletedAt: null,
        userId: { notIn: [OWNER] },
      });
    });

    it('reads only the caller\'s own rows', async () => {
      await service.getSavedPosts(VIEWER);

      const where = prisma.savedPost.findMany.mock.calls[0][0].where;
      expect(where.userId).toEqual(VIEWER);
      expect(where.post).toEqual({ deletedAt: null });
    });
  });
});
