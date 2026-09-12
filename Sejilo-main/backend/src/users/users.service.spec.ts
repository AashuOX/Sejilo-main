import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { UsersService } from './users.service';
import { PrismaService } from '../prisma/prisma.service';
import { ContentVisibilityService } from '../common/content-visibility.service';

const UUID = (n: string) =>
  `${n.repeat(8)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(12)}`;

const VIEWER = UUID('a');
const OTHER = UUID('b');

describe('UsersService — search visibility and the mute/block distinction', () => {
  let service: UsersService;
  let prisma: any;

  beforeEach(async () => {
    prisma = {
      block: {
        findMany: jest.fn().mockResolvedValue([]),
        findFirst: jest.fn().mockResolvedValue(null),
        findUnique: jest.fn().mockResolvedValue(null),
        upsert: jest.fn().mockResolvedValue({ isMuted: true }),
        delete: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      follow: {
        findUnique: jest.fn().mockResolvedValue(null),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      profile: {
        findMany: jest.fn().mockResolvedValue([]),
        findUnique: jest.fn().mockResolvedValue({ username: 'bob' }),
      },
      user: {
        findUnique: jest.fn().mockResolvedValue({ id: OTHER }),
        findFirst: jest.fn().mockResolvedValue({ id: OTHER }),
      },
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UsersService,
        // The real rule, driven by the mocked Prisma — the assertions below are
        // about the query the rule produces.
        ContentVisibilityService,
        { provide: PrismaService, useValue: prisma },
      ],
    }).compile();

    service = module.get<UsersService>(UsersService);
  });

  describe('searchUsers', () => {
    it('a blocked account is not findable, whichever side set the block', async () => {
      prisma.block.findMany.mockResolvedValue([
        { blockerId: VIEWER, blockedId: OTHER },
        { blockerId: UUID('d'), blockedId: VIEWER },
      ]);

      await service.searchUsers('bo', VIEWER);

      const where = prisma.profile.findMany.mock.calls[0][0].where;
      expect(where.userId.notIn.sort()).toEqual([OTHER, UUID('d')].sort());
    });

    it('a mute is not a block: a muted account stays findable', async () => {
      await service.searchUsers('bo', VIEWER);

      expect(prisma.block.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ isMuted: false }),
        }),
      );
    });

    it('an anonymous search needs no block lookup and excludes no one', async () => {
      await service.searchUsers('bo');

      expect(prisma.block.findMany).not.toHaveBeenCalled();
      const where = prisma.profile.findMany.mock.calls[0][0].where;
      expect(where.userId).toBeUndefined();
    });

    it('an empty query reads nothing at all', async () => {
      await expect(service.searchUsers('   ', VIEWER)).resolves.toEqual({
        users: [],
      });
      expect(prisma.profile.findMany).not.toHaveBeenCalled();
      expect(prisma.block.findMany).not.toHaveBeenCalled();
    });
  });

  describe('blockUser', () => {
    it('drops the follow edge in both directions and writes a full block', async () => {
      await service.blockUser(VIEWER, 'bob');

      expect(prisma.follow.deleteMany).toHaveBeenCalledWith({
        where: {
          OR: [
            { followerId: VIEWER, followingId: OTHER },
            { followerId: OTHER, followingId: VIEWER },
          ],
        },
      });
      // Blocking an account that was merely muted has to clear the mute flag,
      // or the row keeps reading as a mute and hides nothing.
      expect(prisma.block.upsert).toHaveBeenCalledWith(
        expect.objectContaining({ update: { isMuted: false } }),
      );
    });

    it('refuses to block yourself', async () => {
      prisma.user.findFirst.mockResolvedValue({ id: VIEWER });

      await expect(service.blockUser(VIEWER, 'me')).rejects.toThrow(
        BadRequestException,
      );
      expect(prisma.block.upsert).not.toHaveBeenCalled();
    });

    it('an unknown handle is a 404', async () => {
      prisma.user.findFirst.mockResolvedValue(null);

      await expect(service.blockUser(VIEWER, 'nobody')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('muteUser', () => {
    it('unmuting deletes the row rather than writing isMuted: false', async () => {
      // A row with isMuted: false *is* a block, so an unmute that wrote one
      // would silently block the account and cut off messaging.
      prisma.block.findUnique.mockResolvedValue({ isMuted: true });

      await expect(service.muteUser(VIEWER, 'bob', false)).resolves.toMatchObject(
        { isMuted: false, username: 'bob' },
      );
      expect(prisma.block.delete).toHaveBeenCalled();
      expect(prisma.block.upsert).not.toHaveBeenCalled();
    });

    it('unmuting an account that was never muted touches nothing', async () => {
      await expect(
        service.muteUser(VIEWER, 'bob', false),
      ).resolves.toMatchObject({ isMuted: false });
      expect(prisma.block.delete).not.toHaveBeenCalled();
      expect(prisma.block.upsert).not.toHaveBeenCalled();
    });

    it('muting a blocked account is refused instead of lifting the block', async () => {
      prisma.block.findUnique.mockResolvedValue({ isMuted: false });

      await expect(service.muteUser(VIEWER, 'bob', true)).rejects.toThrow(
        BadRequestException,
      );
      expect(prisma.block.upsert).not.toHaveBeenCalled();
    });

    it('the response carries the real username, not a guess from the email', async () => {
      prisma.profile.findUnique.mockResolvedValue({ username: 'bob' });

      await expect(service.muteUser(VIEWER, 'bob', true)).resolves.toMatchObject(
        { username: 'bob', isMuted: true },
      );
    });
  });

  describe('verifyUserNotBlocked', () => {
    it('a full block closes messaging', async () => {
      prisma.block.findUnique.mockResolvedValue({ isMuted: false });

      await expect(service.verifyUserNotBlocked(VIEWER, OTHER)).resolves.toBe(
        false,
      );
    });

    it('a mute leaves messaging open', async () => {
      prisma.block.findUnique.mockResolvedValue({ isMuted: true });

      await expect(service.verifyUserNotBlocked(VIEWER, OTHER)).resolves.toBe(
        true,
      );
    });
  });
});
