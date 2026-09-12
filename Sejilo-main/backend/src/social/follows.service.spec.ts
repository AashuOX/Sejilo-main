import { Test, TestingModule } from '@nestjs/testing';
import {
  BadRequestException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { FollowsService } from './follows.service';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';
import { WebhooksService } from '../webhooks/webhooks.service';

const UUID = (n: string) => `${n.repeat(8)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(12)}`;

const makeUser = (id: string, username = 'user', isPrivate = false) => ({
  id,
  profile: {
    username,
    displayName: username,
    bio: '',
    avatarBytes: null,
    avatarMimeType: null,
    isPrivate,
  },
  createdAt: new Date(),
});

const countsOf = (followers: number, following: number, posts: number) => ({
  followers,
  following,
  posts,
});

describe('FollowsService', () => {
  let service: FollowsService;
  let prisma: any;

  beforeEach(async () => {
    prisma = {
      block: {
        findUnique: jest.fn().mockResolvedValue(null),
        findFirst: jest.fn().mockResolvedValue(null),
        findMany: jest.fn().mockResolvedValue([]),
      },
      follow: {
        create: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({}),
        findMany: jest.fn().mockResolvedValue([]),
        findUnique: jest.fn().mockResolvedValue(null),
      },
      followRequest: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: UUID('req'), createdAt: new Date() }),
        deleteMany: jest.fn().mockResolvedValue({}),
        findMany: jest.fn().mockResolvedValue([]),
        update: jest.fn().mockResolvedValue({}),
      },
      notification: { create: jest.fn().mockResolvedValue({}) },
      user: {
        findUnique: jest.fn(),
        findFirst: jest.fn(),
      },
      $transaction: jest.fn().mockResolvedValue([{}, {}]),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FollowsService,
        ContentVisibilityService,
        { provide: PrismaService, useValue: prisma },
        { provide: WebhooksService, useValue: { onUserFollowed: jest.fn(), onUserUnfollowed: jest.fn() } },
      ],
    }).compile();

    service = module.get<FollowsService>(FollowsService);
  });

  it('1. follow by UUID: creates a follow edge and returns updated counts', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findUnique.mockResolvedValue({
      ...makeUser(target, 'bob', false),
      _count: countsOf(1, 2, 3),
      followers: [{ followerId: follower }],
    });

    const res = await service.follow(follower, target, true);

    expect(prisma.follow.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { followerId: follower, followingId: target },
      }),
    );
    expect(res.profile.username).toBe('bob');
    expect(res.profile.followersCount).toBe(1);
    expect(res.profile.isFollowing).toBe(true);
    expect(prisma.notification.create).toHaveBeenCalled();
  });

  it('2. cannot follow yourself', async () => {
    const self = UUID('a');
    prisma.user.findUnique.mockResolvedValue(makeUser(self, 'alice'));

    await expect(service.follow(self, self, true)).rejects.toThrow(
      BadRequestException,
    );
    expect(prisma.follow.create).not.toHaveBeenCalled();
  });

  it('3. cannot follow a user who blocked you (Forbidden)', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findUnique.mockResolvedValue(makeUser(target, 'bob'));
    prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

    await expect(service.follow(follower, target, true)).rejects.toThrow(
      ForbiddenException,
    );
    expect(prisma.follow.create).not.toHaveBeenCalled();
  });

  it('3b. cannot follow a user you blocked yourself', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findUnique.mockResolvedValue(makeUser(target, 'bob'));
    // The shared rule reads the block from either side, so the same row refuses
    // the follow whoever created it.
    prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

    await expect(service.follow(follower, target, true)).rejects.toThrow(
      ForbiddenException,
    );
    expect(prisma.block.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ isMuted: false }),
      }),
    );
    expect(prisma.followRequest.create).not.toHaveBeenCalled();
  });

  it('3c. a mute does not stand in the way of following', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findUnique.mockResolvedValue({
      ...makeUser(target, 'bob', false),
      _count: countsOf(1, 0, 0),
      followers: [{ followerId: follower }],
    });

    await service.follow(follower, target, true);

    expect(prisma.follow.create).toHaveBeenCalled();
  });

  it('3d. a blocked user can still undo a stale follow', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findUnique.mockResolvedValue({
      ...makeUser(target, 'bob', false),
      _count: countsOf(0, 0, 0),
      followers: [],
    });
    prisma.block.findFirst.mockResolvedValue({ id: UUID('c') });

    // Refusing the unfollow would leave an edge the client could never clear.
    await expect(service.follow(follower, target, false)).resolves.toBeDefined();
    expect(prisma.follow.deleteMany).toHaveBeenCalled();
  });

  it('4. unfollow (isFollow=false): removes the edge and reports isFollowing=false', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findUnique.mockResolvedValue({
      ...makeUser(target, 'bob', false),
      _count: countsOf(0, 0, 0),
      followers: [],
    });

    const res = await service.follow(follower, target, false);

    expect(prisma.follow.deleteMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { followerId: follower, followingId: target } }),
    );
    expect(res.profile.isFollowing).toBe(false);
    expect(prisma.follow.create).not.toHaveBeenCalled();
  });

  it('5. follow by username (non-UUID identifier) resolves via findFirst', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findFirst.mockResolvedValue(makeUser(target, 'bob', false));
    prisma.user.findUnique.mockResolvedValue({ ...makeUser(target, 'bob', false), _count: countsOf(5, 5, 5), followers: [] });

    const res = await service.follow(follower, 'bob', true);

    expect(prisma.user.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { profile: { username: 'bob' } },
        include: { profile: true },
      }),
    );
    expect(prisma.follow.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { followerId: follower, followingId: target },
      }),
    );
    expect(res.profile.username).toBe('bob');
  });

  it('6. following a non-existent user throws NotFound', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.follow(UUID('a'), UUID('z'), true)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('7. getFollowers returns mapped follower profiles', async () => {
    const owner = UUID('b');
    prisma.user.findUnique.mockResolvedValue(makeUser(owner, 'bob'));
    prisma.follow.findMany.mockResolvedValue([
      { follower: makeUser(UUID('f'), 'flora') },
    ]);

    const res = await service.getFollowers(owner);

    expect(prisma.follow.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { followingId: owner },
        include: { follower: { include: { profile: true } } },
      }),
    );
    expect(res.users).toHaveLength(1);
    expect(res.users[0].username).toBe('flora');
  });

  it('8. getFollowing returns mapped following profiles', async () => {
    const owner = UUID('b');
    prisma.user.findUnique.mockResolvedValue(makeUser(owner, 'bob'));
    prisma.follow.findMany.mockResolvedValue([
      { following: makeUser(UUID('f'), 'flora') },
    ]);

    const res = await service.getFollowing(owner);

    expect(prisma.follow.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { followerId: owner },
        include: { following: { include: { profile: true } } },
      }),
    );
    expect(res.users).toHaveLength(1);
    expect(res.users[0].username).toBe('flora');
  });

  it('9. private profile follow creates a follow request instead of direct follow', async () => {
    const target = UUID('b');
    const follower = UUID('a');
    prisma.user.findUnique
      .mockResolvedValueOnce(makeUser(target, 'bob', true))
      .mockResolvedValueOnce({ ...makeUser(target, 'bob', true), _count: countsOf(0, 0, 0), followers: [] });
    prisma.followRequest.findUnique.mockResolvedValue(null);

    const res = await service.follow(follower, target, true);

    expect(prisma.followRequest.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { requesterId: follower, targetId: target },
      }),
    );
    expect(prisma.follow.create).not.toHaveBeenCalled();
    expect(res.profile.isFollowing).toBe(false);
  });

  it('10. acceptFollowRequest creates follow and updates request status', async () => {
    const target = UUID('b');
    const requester = UUID('a');
    prisma.followRequest.findUnique.mockResolvedValue({
      id: UUID('req'),
      requesterId: requester,
      targetId: target,
      status: 'pending',
      createdAt: new Date(),
    });
    prisma.user.findUnique.mockResolvedValue({
      ...makeUser(target, 'bob'),
      _count: countsOf(1, 0, 0),
      followers: [{ followerId: requester }],
    });

    const res = await service.acceptFollowRequest(target, requester);

    expect(prisma.follow.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { followerId: requester, followingId: target },
      }),
    );
    expect(res.profile.isFollowing).toBe(true);
  });

  it('11. rejectFollowRequest updates request status to rejected', async () => {
    const target = UUID('b');
    const requester = UUID('a');
    prisma.followRequest.findUnique.mockResolvedValue({
      id: UUID('req'),
      requesterId: requester,
      targetId: target,
      status: 'pending',
    });

    const res = await service.rejectFollowRequest(target, requester);

    expect(prisma.followRequest.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: UUID('req') },
        data: { status: 'rejected' },
      }),
    );
    expect(res.success).toBe(true);
  });

  describe('a private account keeps its follower and following lists', () => {
    const OWNER = UUID('b');
    const VIEWER = UUID('a');

    beforeEach(() => {
      prisma.user.findUnique.mockResolvedValue(makeUser(OWNER, 'bob', true));
    });

    it('refuses a stranger the follower list', async () => {
      await expect(service.getFollowers(OWNER, VIEWER)).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.follow.findMany).not.toHaveBeenCalled();
    });

    it('refuses a stranger the following list', async () => {
      await expect(service.getFollowing(OWNER, VIEWER)).rejects.toThrow(
        ForbiddenException,
      );
      expect(prisma.follow.findMany).not.toHaveBeenCalled();
    });

    it('opens both lists to an accepted follower', async () => {
      prisma.follow.findUnique.mockResolvedValue({ id: UUID('f') });

      await expect(service.getFollowers(OWNER, VIEWER)).resolves.toEqual({
        users: [],
      });
      await expect(service.getFollowing(OWNER, VIEWER)).resolves.toEqual({
        users: [],
      });
    });

    it('the account always sees its own lists', async () => {
      await expect(service.getFollowers(OWNER, OWNER)).resolves.toEqual({
        users: [],
      });
      expect(prisma.block.findFirst).not.toHaveBeenCalled();
      expect(prisma.follow.findUnique).not.toHaveBeenCalled();
    });
  });

  describe('blocked accounts are dropped from the lists', () => {
    const OWNER = UUID('b');
    const VIEWER = UUID('a');
    const BLOCKED = UUID('d');

    it('a blocked account is not among the followers shown', async () => {
      prisma.user.findUnique.mockResolvedValue(makeUser(OWNER, 'bob'));
      prisma.block.findMany.mockResolvedValue([
        { blockerId: VIEWER, blockedId: BLOCKED },
      ]);

      await service.getFollowers(OWNER, VIEWER);

      const where = prisma.follow.findMany.mock.calls[0][0].where;
      expect(where).toEqual({
        followingId: OWNER,
        followerId: { notIn: [BLOCKED] },
      });
    });

    it('nor among the accounts they follow', async () => {
      prisma.user.findUnique.mockResolvedValue(makeUser(OWNER, 'bob'));
      prisma.block.findMany.mockResolvedValue([
        { blockerId: BLOCKED, blockedId: VIEWER },
      ]);

      await service.getFollowing(OWNER, VIEWER);

      const where = prisma.follow.findMany.mock.calls[0][0].where;
      expect(where).toEqual({
        followerId: OWNER,
        followingId: { notIn: [BLOCKED] },
      });
    });

    it('a mute is not a block: a muted account stays in the list', async () => {
      prisma.user.findUnique.mockResolvedValue(makeUser(OWNER, 'bob'));

      await service.getFollowers(OWNER, VIEWER);

      expect(prisma.block.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ isMuted: false }),
        }),
      );
    });

    it('an unknown handle is a 404 before anything is read', async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      await expect(service.getFollowers(UUID('z'), VIEWER)).rejects.toThrow(
        NotFoundException,
      );
      expect(prisma.follow.findMany).not.toHaveBeenCalled();
    });
  });
});