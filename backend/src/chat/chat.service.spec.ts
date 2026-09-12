import { Test, TestingModule } from '@nestjs/testing';
import { ForbiddenException } from '@nestjs/common';
import { ChatService } from './chat.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { PushService } from './push.service';
import { WebhooksService } from '../webhooks/webhooks.service';
import { ContentVisibilityService } from '../common/content-visibility.service';

const UUID = (n: string) =>
  `${n.repeat(8)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(12)}`;

const ME = UUID('a');
const THEM = UUID('b');
const CONV = UUID('c');

/// Everything here is about one rule: a block cuts messaging in both
/// directions. Membership alone used to be the only check, so a thread opened
/// before a block — or opened outright by a blocked account — kept delivering.
describe('ChatService block enforcement', () => {
  let service: ChatService;
  let prisma: any;
  let visibility: { isBlockedBetween: jest.Mock };

  beforeEach(async () => {
    prisma = {
      conversation: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest
          .fn()
          .mockResolvedValue({ id: CONV, createdAt: new Date() }),
        update: jest.fn().mockResolvedValue({}),
      },
      conversationMember: {
        findUnique: jest.fn(),
        findMany: jest.fn().mockResolvedValue([{ userId: ME }]),
      },
      message: {
        create: jest.fn().mockResolvedValue({
          id: UUID('d'),
          text: 'hi',
          replyToId: null,
          createdAt: new Date(),
        }),
      },
    };
    visibility = { isBlockedBetween: jest.fn().mockResolvedValue(false) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatService,
        { provide: PrismaService, useValue: prisma },
        {
          provide: RedisService,
          useValue: {
            publish: jest.fn(),
            isUserOnline: jest.fn().mockResolvedValue(true),
          },
        },
        { provide: PushService, useValue: { notifyOfflineUsers: jest.fn() } },
        {
          provide: WebhooksService,
          useValue: {
            onConversationCreated: jest.fn(),
            onMessageSent: jest.fn(),
          },
        },
        { provide: ContentVisibilityService, useValue: visibility },
      ],
    }).compile();

    service = module.get<ChatService>(ChatService);
  });

  const directMembership = () => ({
    leftAt: null,
    user: { profile: { username: 'me', displayName: 'Me' } },
    conversation: {
      kind: 'direct',
      members: [{ userId: ME }, { userId: THEM }],
    },
  });

  describe('createConversation', () => {
    it('refuses a direct thread when either side has blocked the other', async () => {
      visibility.isBlockedBetween.mockResolvedValue(true);

      await expect(
        service.createConversation(ME, {
          kind: 'direct',
          recipientUserId: THEM,
        } as any),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(prisma.conversation.create).not.toHaveBeenCalled();
    });

    it('creates the direct thread when there is no block', async () => {
      const result = await service.createConversation(ME, {
        kind: 'direct',
        recipientUserId: THEM,
      } as any);

      expect(visibility.isBlockedBetween).toHaveBeenCalledWith(ME, THEM);
      expect(result).toEqual({ id: CONV, isExisting: false });
    });

    it('will not let a group be used to get around a direct block', async () => {
      visibility.isBlockedBetween.mockResolvedValue(true);

      await expect(
        service.createConversation(ME, {
          kind: 'group',
          memberUserIds: [THEM],
        } as any),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(prisma.conversation.create).not.toHaveBeenCalled();
    });
  });

  describe('sendMessage', () => {
    it('refuses when the other member of a direct thread is blocked', async () => {
      prisma.conversationMember.findUnique.mockResolvedValue(
        directMembership(),
      );
      visibility.isBlockedBetween.mockResolvedValue(true);

      await expect(
        service.sendMessage(ME, CONV, { text: 'hi' } as any),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(prisma.message.create).not.toHaveBeenCalled();
    });

    it('delivers when there is no block', async () => {
      prisma.conversationMember.findUnique.mockResolvedValue(
        directMembership(),
      );

      const payload = await service.sendMessage(ME, CONV, {
        text: 'hi',
      } as any);

      expect(visibility.isBlockedBetween).toHaveBeenCalledWith(ME, THEM);
      expect(prisma.message.create).toHaveBeenCalled();
      expect(payload.text).toBe('hi');
    });

    it('still refuses a non-member before looking at blocks', async () => {
      prisma.conversationMember.findUnique.mockResolvedValue(null);

      await expect(
        service.sendMessage(ME, CONV, { text: 'hi' } as any),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(visibility.isBlockedBetween).not.toHaveBeenCalled();
    });
  });
});

/// Both of these are reached by message id alone. Membership was never checked,
/// so any signed-in account could mark a stranger's message read — publishing a
/// forged receipt to the sender's event channel — or attach an emoji inside a
/// private thread it had no part in.
describe('ChatService message-id authorization', () => {
  const OUTSIDER = UUID('e');
  const MSG = UUID('f');
  let service: ChatService;
  let prisma: any;
  let redis: { publish: jest.Mock; isUserOnline: jest.Mock };

  beforeEach(async () => {
    prisma = {
      message: {
        findUnique: jest
          .fn()
          .mockResolvedValue({ id: MSG, conversationId: CONV, senderId: THEM }),
        update: jest.fn().mockResolvedValue({}),
      },
      messageReaction: { upsert: jest.fn().mockResolvedValue({}) },
      conversationMember: {
        findUnique: jest.fn().mockResolvedValue({ id: UUID('1'), leftAt: null }),
        findMany: jest.fn().mockResolvedValue([{ userId: ME }, { userId: THEM }]),
      },
    };
    redis = { publish: jest.fn(), isUserOnline: jest.fn() };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatService,
        { provide: PrismaService, useValue: prisma },
        { provide: RedisService, useValue: redis },
        { provide: PushService, useValue: { notifyOfflineUsers: jest.fn() } },
        {
          provide: WebhooksService,
          useValue: { onMessageReaction: jest.fn() },
        },
        {
          provide: ContentVisibilityService,
          useValue: { isBlockedBetween: jest.fn().mockResolvedValue(false) },
        },
      ],
    }).compile();

    service = module.get<ChatService>(ChatService);
  });

  describe('updateMessageStatus', () => {
    it('refuses an account that is not in the conversation', async () => {
      prisma.conversationMember.findUnique.mockResolvedValue(null);

      await expect(
        service.updateMessageStatus(OUTSIDER, MSG, 'read'),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(prisma.message.update).not.toHaveBeenCalled();
      expect(redis.publish).not.toHaveBeenCalled();
    });

    it('refuses a member who has left the conversation', async () => {
      prisma.conversationMember.findUnique.mockResolvedValue({
        id: UUID('1'),
        leftAt: new Date(),
      });

      await expect(
        service.updateMessageStatus(ME, MSG, 'read'),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(prisma.message.update).not.toHaveBeenCalled();
    });

    it('refuses the sender reporting a receipt for their own message', async () => {
      await expect(
        service.updateMessageStatus(THEM, MSG, 'read'),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(prisma.message.update).not.toHaveBeenCalled();
    });

    it('accepts a receipt from the recipient and tells the sender', async () => {
      await service.updateMessageStatus(ME, MSG, 'read');

      expect(prisma.message.update).toHaveBeenCalledWith({
        where: { id: MSG },
        data: { status: 'READ' },
      });
      expect(redis.publish).toHaveBeenCalledWith(
        `user:${THEM}:events`,
        expect.stringContaining('"status":"read"'),
      );
    });
  });

  describe('addReaction', () => {
    it('refuses an outsider reacting inside a private thread', async () => {
      prisma.conversationMember.findUnique.mockResolvedValue(null);

      await expect(
        service.addReaction(OUTSIDER, MSG, '🔥'),
      ).rejects.toBeInstanceOf(ForbiddenException);

      expect(prisma.messageReaction.upsert).not.toHaveBeenCalled();
      expect(redis.publish).not.toHaveBeenCalled();
    });

    it('lets a member react, and tells everyone still in the thread', async () => {
      await service.addReaction(ME, MSG, '🔥');

      expect(prisma.messageReaction.upsert).toHaveBeenCalled();
      expect(redis.publish).toHaveBeenCalledTimes(2);
    });
  });
});
