import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { WebhooksService } from '../webhooks/webhooks.service';
import { ContentVisibilityService } from '../common/content-visibility.service';

@Injectable()
export class MessageRequestsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly webhooks: WebhooksService,
    private readonly visibility: ContentVisibilityService,
  ) {}

  async getMessageRequests(userId: string) {
    const requests = await this.prisma.messageRequest.findMany({
      where: { recipientId: userId, status: 'pending' },
      include: {
        sender: {
          include: {
            profile: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return {
      requests: requests.map((r) => ({
        id: r.id,
        senderId: r.sender.id,
        username: r.sender.profile?.username ?? '',
        displayName: r.sender.profile?.displayName ?? '',
        bio: r.sender.profile?.bio ?? '',
        avatar: r.sender.profile?.avatarBytes && r.sender.profile?.avatarMimeType
          ? {
              mimeType: r.sender.profile.avatarMimeType,
              data: Buffer.from(r.sender.profile.avatarBytes).toString('base64url'),
            }
          : null,
        text: r.text,
        createdAt: r.createdAt.toISOString(),
      })),
    };
  }

  async sendMessageRequest(senderId: string, recipientId: string, text: string) {
    const recipient = await this.prisma.user.findUnique({
      where: { id: recipientId },
      include: { profile: true },
    });

    if (!recipient) {
      throw new NotFoundException('Recipient not found.');
    }

    if (recipient.id === senderId) {
      throw new ForbiddenException('Cannot send a message request to yourself.');
    }

    // A block has to cut messaging in both directions. ChatService checks this
    // for conversations and messages; without the same check here, blocking
    // somebody still left them a way to put text in front of you — the request
    // inbox — which is the one path that does not need an existing thread.
    if (await this.visibility.isBlockedBetween(senderId, recipientId)) {
      throw new ForbiddenException('This account is not available.');
    }

    const existingConversation = await this.prisma.conversationMember.findFirst({
      where: {
        userId: senderId,
        conversation: {
          members: {
            some: { userId: recipientId },
          },
        },
      },
      include: {
        conversation: true,
      },
    });

    if (existingConversation) {
      return { conversationId: existingConversation.conversationId, alreadyConnected: true };
    }

    const existingRequest = await this.prisma.messageRequest.findFirst({
      where: {
        OR: [
          { senderId, recipientId, status: 'pending' },
          { senderId: recipientId, recipientId: senderId, status: 'pending' },
        ],
      },
    });

    if (existingRequest) {
      return { requestId: existingRequest.id, alreadySent: true };
    }

    const request = await this.prisma.messageRequest.create({
      data: {
        senderId,
        recipientId,
        text,
      },
    });

    await this.prisma.notification.create({
      data: {
        userId: recipientId,
        actorId: senderId,
        type: 'message_request',
      },
    }).catch(() => {});

    await this.webhooks.onMessageSent({
      messageId: request.id,
      conversationId: '',
      senderId,
      text,
      hasMedia: false,
      createdAt: request.createdAt.toISOString(),
    });

    return { requestId: request.id };
  }

  async acceptMessageRequest(userId: string, requestId: string) {
    const request = await this.prisma.messageRequest.findUnique({
      where: { id: requestId },
    });

    if (!request || request.recipientId !== userId || request.status !== 'pending') {
      throw new NotFoundException('Message request not found.');
    }

    const conversation = await this.prisma.conversation.create({
      data: {
        kind: 'direct',
        members: {
          create: [
            { userId: request.senderId },
            { userId: request.recipientId },
          ],
        },
      },
    });

    await this.prisma.messageRequest.update({
      where: { id: requestId },
      data: { status: 'accepted' },
    });

    // The request text IS the stranger's first message. Creating an empty
    // conversation threw it away, so accepting a request opened a blank thread
    // and the message the recipient had just agreed to read was gone.
    if (request.text?.trim()) {
      await this.prisma.message.create({
        data: {
          conversationId: conversation.id,
          senderId: request.senderId,
          text: request.text.trim(),
          status: 'SENT',
          createdAt: request.createdAt,
        },
      });
      await this.prisma.conversation.update({
        where: { id: conversation.id },
        data: { lastMessageAt: request.createdAt },
      });
    }

    await this.webhooks.onConversationCreated({
      conversationId: conversation.id,
      type: 'direct',
      participants: [request.senderId, request.recipientId],
      createdBy: userId,
      createdAt: conversation.createdAt.toISOString(),
    });

    return { conversationId: conversation.id };
  }

  async rejectMessageRequest(userId: string, requestId: string) {
    const request = await this.prisma.messageRequest.findUnique({
      where: { id: requestId },
    });

    if (!request || request.recipientId !== userId || request.status !== 'pending') {
      throw new NotFoundException('Message request not found.');
    }

    await this.prisma.messageRequest.update({
      where: { id: requestId },
      data: { status: 'rejected' },
    });

    return { success: true };
  }
}
