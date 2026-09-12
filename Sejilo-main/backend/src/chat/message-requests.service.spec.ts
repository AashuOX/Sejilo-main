import { Test, TestingModule } from '@nestjs/testing';
import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { MessageRequestsService } from './message-requests.service';
import { PrismaService } from '../prisma/prisma.service';
import { WebhooksService } from '../webhooks/webhooks.service';
import { ContentVisibilityService } from '../common/content-visibility.service';

const UUID = (n: string) => `${n.repeat(8)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(12)}`;

const makeUser = (id: string, username = 'user') => ({
  id,
  profile: {
    username,
    displayName: username,
    bio: '',
    avatarBytes: null,
    avatarMimeType: null,
  },
});

describe('MessageRequestsService', () => {
  let service: MessageRequestsService;
  let prisma: any;
  let visibility: { isBlockedBetween: jest.Mock };

  beforeEach(async () => {
    prisma = {
      messageRequest: {
        findMany: jest.fn().mockResolvedValue([]),
        findFirst: jest.fn().mockResolvedValue(null),
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: UUID('req'), createdAt: new Date() }),
        update: jest.fn().mockResolvedValue({}),
      },
      conversation: {
        create: jest.fn().mockResolvedValue({ id: UUID('conv'), createdAt: new Date() }),
        update: jest.fn().mockResolvedValue({}),
      },
      conversationMember: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({}),
      },
      message: { create: jest.fn().mockResolvedValue({ id: UUID('msg') }) },
      notification: { create: jest.fn().mockResolvedValue({}) },
      user: {
        findUnique: jest.fn(),
      },
    };
    visibility = { isBlockedBetween: jest.fn().mockResolvedValue(false) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MessageRequestsService,
        { provide: PrismaService, useValue: prisma },
        { provide: WebhooksService, useValue: { onMessageSent: jest.fn(), onConversationCreated: jest.fn() } },
        { provide: ContentVisibilityService, useValue: visibility },
      ],
    }).compile();

    service = module.get<MessageRequestsService>(MessageRequestsService);
  });

  it('1. getMessageRequests returns pending requests', async () => {
    const userId = UUID('u');
    prisma.messageRequest.findMany.mockResolvedValue([
      {
        id: UUID('req'),
        text: 'Hello',
        createdAt: new Date(),
        sender: makeUser(UUID('s'), 'sender'),
      },
    ]);

    const res = await service.getMessageRequests(userId);

    expect(res.requests).toHaveLength(1);
    expect(res.requests[0].username).toBe('sender');
    expect(res.requests[0].text).toBe('Hello');
  });

  it('2. sendMessageRequest creates a request for non-connected users', async () => {
    const senderId = UUID('a');
    const recipientId = UUID('b');
    prisma.user.findUnique.mockResolvedValue(makeUser(recipientId, 'recipient'));
    prisma.conversationMember.findFirst.mockResolvedValue(null);
    prisma.messageRequest.findFirst.mockResolvedValue(null);

    const res = await service.sendMessageRequest(senderId, recipientId, 'Hi there');

    expect(prisma.messageRequest.create).toHaveBeenCalledWith({
      data: { senderId, recipientId, text: 'Hi there' },
    });
    expect(res.requestId).toBeDefined();
  });

  it('3. sendMessageRequest returns existing conversation if already connected', async () => {
    const senderId = UUID('a');
    const recipientId = UUID('b');
    prisma.user.findUnique.mockResolvedValue(makeUser(recipientId, 'recipient'));
    prisma.conversationMember.findFirst.mockResolvedValue({
      conversationId: UUID('conv'),
    });

    const res = await service.sendMessageRequest(senderId, recipientId, 'Hi');

    expect(res.alreadyConnected).toBe(true);
    expect(res.conversationId).toBe(UUID('conv'));
  });

  it('4. sendMessageRequest rejects self-message', async () => {
    const userId = UUID('a');
    prisma.user.findUnique.mockResolvedValue(makeUser(userId, 'me'));

    await expect(service.sendMessageRequest(userId, userId, 'Hi')).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('5. acceptMessageRequest creates conversation and marks request accepted', async () => {
    const userId = UUID('b');
    const requestId = UUID('req');
    prisma.messageRequest.findUnique.mockResolvedValue({
      id: requestId,
      senderId: UUID('a'),
      recipientId: userId,
      status: 'pending',
    });

    const res = await service.acceptMessageRequest(userId, requestId);

    expect(prisma.conversation.create).toHaveBeenCalled();
    expect(prisma.messageRequest.update).toHaveBeenCalledWith({
      where: { id: requestId },
      data: { status: 'accepted' },
    });
    expect(res.conversationId).toBeDefined();
  });

  it('6. rejectMessageRequest updates status to rejected', async () => {
    const userId = UUID('b');
    const requestId = UUID('req');
    prisma.messageRequest.findUnique.mockResolvedValue({
      id: requestId,
      senderId: UUID('a'),
      recipientId: userId,
      status: 'pending',
    });

    const res = await service.rejectMessageRequest(userId, requestId);

    expect(prisma.messageRequest.update).toHaveBeenCalledWith({
      where: { id: requestId },
      data: { status: 'rejected' },
    });
    expect(res.success).toBe(true);
  });

  /// A block has to cut messaging in both directions. The request inbox is the
  /// one path into somebody's attention that needs no existing thread, so
  /// without this check blocking an account still left it a way to reach you.
  it('7. sendMessageRequest refuses when either side has blocked the other', async () => {
    const senderId = UUID('a');
    const recipientId = UUID('b');
    prisma.user.findUnique.mockResolvedValue(makeUser(recipientId, 'recipient'));
    visibility.isBlockedBetween.mockResolvedValue(true);

    await expect(
      service.sendMessageRequest(senderId, recipientId, 'Hi'),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(visibility.isBlockedBetween).toHaveBeenCalledWith(senderId, recipientId);
    expect(prisma.messageRequest.create).not.toHaveBeenCalled();
    expect(prisma.notification.create).not.toHaveBeenCalled();
  });

  it('8. sendMessageRequest rejects an unknown recipient', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.sendMessageRequest(UUID('a'), UUID('b'), 'Hi'),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.messageRequest.create).not.toHaveBeenCalled();
  });

  /// The request text IS the stranger's first message. Accepting used to create
  /// an empty conversation, so the recipient agreed to read something and then
  /// opened a blank thread.
  it('9. acceptMessageRequest carries the request text in as the first message', async () => {
    const userId = UUID('b');
    const senderId = UUID('a');
    const requestId = UUID('req');
    const sentAt = new Date('2026-01-02T03:04:05.000Z');
    prisma.messageRequest.findUnique.mockResolvedValue({
      id: requestId,
      senderId,
      recipientId: userId,
      status: 'pending',
      text: '  Hey, is this you?  ',
      createdAt: sentAt,
    });

    await service.acceptMessageRequest(userId, requestId);

    expect(prisma.message.create).toHaveBeenCalledWith({
      data: {
        conversationId: UUID('conv'),
        senderId,
        text: 'Hey, is this you?',
        status: 'SENT',
        createdAt: sentAt,
      },
    });
    expect(prisma.conversation.update).toHaveBeenCalledWith({
      where: { id: UUID('conv') },
      data: { lastMessageAt: sentAt },
    });
  });

  it('10. acceptMessageRequest writes no message when the request had no text', async () => {
    const userId = UUID('b');
    const requestId = UUID('req');
    prisma.messageRequest.findUnique.mockResolvedValue({
      id: requestId,
      senderId: UUID('a'),
      recipientId: userId,
      status: 'pending',
      text: '   ',
      createdAt: new Date(),
    });

    await service.acceptMessageRequest(userId, requestId);

    expect(prisma.message.create).not.toHaveBeenCalled();
    expect(prisma.conversation.update).not.toHaveBeenCalled();
  });

  it('11. acceptMessageRequest refuses a request addressed to somebody else', async () => {
    const requestId = UUID('req');
    prisma.messageRequest.findUnique.mockResolvedValue({
      id: requestId,
      senderId: UUID('a'),
      recipientId: UUID('b'),
      status: 'pending',
      text: 'Hi',
      createdAt: new Date(),
    });

    await expect(
      service.acceptMessageRequest(UUID('e'), requestId),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.conversation.create).not.toHaveBeenCalled();
  });

  it('12. rejectMessageRequest refuses a request addressed to somebody else', async () => {
    const requestId = UUID('req');
    prisma.messageRequest.findUnique.mockResolvedValue({
      id: requestId,
      senderId: UUID('a'),
      recipientId: UUID('b'),
      status: 'pending',
    });

    await expect(
      service.rejectMessageRequest(UUID('e'), requestId),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.messageRequest.update).not.toHaveBeenCalled();
  });
});