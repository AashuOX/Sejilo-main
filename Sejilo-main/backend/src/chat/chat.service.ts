import { Injectable, ForbiddenException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { PushService } from './push.service';
import { ExpirationScheduler } from './expiration.scheduler';
import { CreateConversationDto } from './dto/create-conversation.dto';
import { SendMessageDto } from './dto/send-message.dto';
import { WebhooksService } from '../webhooks/webhooks.service';
import { ContentVisibilityService } from '../common/content-visibility.service';

@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly push: PushService,
    private readonly webhooks: WebhooksService,
    private readonly visibility: ContentVisibilityService,
  ) {}

  async getConversations(userId: string) {
    const memberships = await this.prisma.conversationMember.findMany({
      where: { userId, leftAt: null },
      orderBy: { conversation: { updatedAt: 'desc' } },
      include: {
        conversation: {
          include: {
            members: {
              where: { leftAt: null },
              include: { user: { include: { profile: true } } },
            },
            messages: {
              where: { deletedAt: null },
              orderBy: { createdAt: 'desc' },
              take: 1,
              include: { sender: { include: { profile: true } } },
            },
          },
        },
      },
    });

    const conversations = await Promise.all(
      memberships.map(async (m) => {
        const conv = m.conversation;
        const otherMembers = conv.members.filter((mem) => mem.userId !== userId);
        const primaryOther = otherMembers[0]?.user;
        const lastMsg = conv.messages[0] as any;

        // Unread messages count since lastReadAt
        const unreadCount = await this.prisma.message.count({
          where: {
            conversationId: conv.id,
            senderId: { not: userId },
            createdAt: { gt: m.lastReadAt },
            deletedAt: null,
          },
        });

        const isOnline = primaryOther
          ? await this.redis.isUserOnline(primaryOther.id)
          : false;

        return {
          id: conv.id,
          kind: conv.kind,
          title: conv.title,
          updatedAt: conv.updatedAt.toISOString(),
          unreadCount,
          participant: primaryOther
            ? {
                id: primaryOther.id,
                username: primaryOther.profile?.username ?? '',
                displayName: primaryOther.profile?.displayName ?? '',
                avatar: primaryOther.profile?.avatarBytes && primaryOther.profile?.avatarMimeType
                  ? {
                      mimeType: primaryOther.profile.avatarMimeType,
                      data: Buffer.from(primaryOther.profile.avatarBytes).toString('base64url'),
                    }
                  : null,
                isOnline,
              }
            : null,
          lastMessage: lastMsg
            ? {
                id: lastMsg.id,
                conversationId: conv.id,
                senderId: lastMsg.senderId,
                senderUsername: lastMsg.sender?.profile?.username ?? '',
                senderDisplayName: lastMsg.sender?.profile?.displayName ?? '',
                text: lastMsg.text ?? '',
                media: lastMsg.mediaBytes && lastMsg.mediaMimeType
                  ? {
                      mimeType: lastMsg.mediaMimeType,
                      data: Buffer.from(lastMsg.mediaBytes).toString('base64url'),
                    }
                  : null,
                status: lastMsg.status.toLowerCase(),
                createdAt: lastMsg.createdAt.toISOString(),
              }
            : null,
        };
      }),
    );

    return { conversations };
  }

  async createConversation(userId: string, dto: CreateConversationDto) {
    if (dto.kind === 'direct') {
      const recipientId = dto.recipientUserId;
      if (!recipientId) {
        throw new NotFoundException('Recipient user ID required for direct conversation.');
      }

      // A block has to cut messaging, not only reading. Without this a blocked
      // account can open a thread and keep writing into the other inbox, which
      // is exactly what the person who blocked them asked not to happen. The
      // wording matches the posts and stories refusal so that neither side can
      // tell which direction the block runs in.
      if (await this.visibility.isBlockedBetween(userId, recipientId)) {
        throw new ForbiddenException('This account is not available.');
      }

      // Check if direct conversation already exists between both users
      const existing = await this.prisma.conversation.findFirst({
        where: {
          kind: 'direct',
          AND: [
            { members: { some: { userId } } },
            { members: { some: { userId: recipientId } } },
          ],
        },
      });

      if (existing) {
        return { id: existing.id, isExisting: true };
      }

      const conv = await this.prisma.conversation.create({
        data: {
          kind: 'direct',
          createdById: userId,
          members: {
            create: [
              { userId, role: 'owner' },
              { userId: recipientId, role: 'member' },
            ],
          },
        },
      });

      // Fire webhook
      await this.webhooks.onConversationCreated({
        conversationId: conv.id,
        type: 'direct',
        participants: [userId, recipientId],
        createdBy: userId,
        createdAt: conv.createdAt.toISOString(),
      });

      return { id: conv.id, isExisting: false };
    } else {
      // Group conversation
      const memberIds = Array.from(new Set([userId, ...(dto.memberUserIds ?? [])]));

      // Otherwise a group is a way around a direct block: invite the account
      // that blocked you and write to them there.
      const others = memberIds.filter((id) => id !== userId);
      const blocked = await Promise.all(
        others.map((id) => this.visibility.isBlockedBetween(userId, id)),
      );
      if (blocked.some(Boolean)) {
        throw new ForbiddenException('One of those accounts is not available.');
      }

      const conv = await this.prisma.conversation.create({
        data: {
          kind: 'group',
          title: dto.title?.trim() || 'Group Chat',
          createdById: userId,
          members: {
            create: memberIds.map((mId) => ({
              userId: mId,
              role: mId === userId ? 'owner' : 'member',
            })),
          },
        },
      });

      // Fire webhook
      await this.webhooks.onConversationCreated({
        conversationId: conv.id,
        type: 'group',
        participants: memberIds,
        createdBy: userId,
        createdAt: conv.createdAt.toISOString(),
      });

      return { id: conv.id, isExisting: false };
    }
  }

  async getMessages(userId: string, conversationId: string, limit = 50) {
    const membership = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    });

    if (!membership || membership.leftAt) {
      throw new ForbiddenException('You are not a member of this conversation.');
    }

    // Mark last read
    await this.prisma.conversationMember.update({
      where: { id: membership.id },
      data: { lastReadAt: new Date() },
    });

    const messages = await this.prisma.message.findMany({
      where: { conversationId, deletedAt: null },
      take: Math.min(limit, 100),
      orderBy: { createdAt: 'asc' },
      include: {
        sender: { include: { profile: true } },
        reactions: true,
      },
    });

    return {
      messages: messages.map((m: any) => ({
        id: m.id,
        conversationId: m.conversationId,
        senderId: m.senderId,
        senderUsername: m.sender?.profile?.username ?? '',
        senderDisplayName: m.sender?.profile?.displayName ?? '',
        avatar: m.sender?.profile?.avatarBytes && m.sender?.profile?.avatarMimeType
          ? {
              mimeType: m.sender.profile.avatarMimeType,
              data: Buffer.from(m.sender.profile.avatarBytes).toString('base64url'),
            }
          : null,
        text: m.text ?? '',
        media: m.mediaBytes && m.mediaMimeType
          ? {
              mimeType: m.mediaMimeType,
              data: Buffer.from(m.mediaBytes).toString('base64url'),
            }
          : null,
        replyToMessageId: m.replyToId,
        status: m.status.toLowerCase(),
        createdAt: m.createdAt.toISOString(),
        expiresAt: m.expiresAt?.toISOString() ?? null,
        remainingMs: m.expiresAt ? ExpirationScheduler.getRemainingTime(m.expiresAt) : null,
        reactions: m.reactions.map((r: any) => ({ userId: r.userId, emoji: r.emoji })),
      })),
    };
  }

  async sendMessage(userId: string, conversationId: string, dto: SendMessageDto) {
    const membership = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
      include: {
        user: { include: { profile: true } },
        conversation: {
          select: {
            kind: true,
            members: { where: { leftAt: null }, select: { userId: true } },
          },
        },
      },
    });

    if (!membership || membership.leftAt) {
      throw new ForbiddenException('You are not a member of this conversation.');
    }

    // Membership on its own does not say whether the two are still on speaking
    // terms: a thread opened before the block still lists both people, so the
    // block is re-checked on every send rather than only when the thread is
    // created.
    if (membership.conversation.kind === 'direct') {
      const other = membership.conversation.members.find((m) => m.userId !== userId);
      if (other && (await this.visibility.isBlockedBetween(userId, other.userId))) {
        throw new ForbiddenException('This account is not available.');
      }
    }

    let mediaBytes: any = undefined;
    let mediaMimeType: string | undefined;

    if (dto.media && dto.media.data && dto.media.mimeType) {
      mediaBytes = Buffer.from(dto.media.data, 'base64url');
      mediaMimeType = dto.media.mimeType;
    }

    // Calculate expiration time if provided
    let expiresAt: Date | null = null;
    if (dto.expiresIn) {
      expiresAt = ExpirationScheduler.getExpirationTime(dto.expiresIn);
    }

    const message = await this.prisma.message.create({
      data: {
        conversationId,
        senderId: userId,
        text: dto.text?.trim() ?? null,
        mediaBytes,
        mediaMimeType,
        replyToId: dto.replyToMessageId ?? null,
        clientMessageId: dto.clientMessageId ?? null,
        status: 'SENT',
        expiresAt,
      },
    });

    // Update conversation updatedAt
    await this.prisma.conversation.update({
      where: { id: conversationId },
      data: { updatedAt: new Date(), lastMessageAt: new Date() },
    });

    // Format message payload using membership.user
    const senderProfile = membership.user?.profile;
    const remainingMs = expiresAt ? ExpirationScheduler.getRemainingTime(expiresAt) : null;
    const payload = {
      id: message.id,
      conversationId,
      senderId: userId,
      senderUsername: senderProfile?.username ?? '',
      senderDisplayName: senderProfile?.displayName ?? '',
      avatar: senderProfile?.avatarBytes && senderProfile?.avatarMimeType
        ? {
            mimeType: senderProfile.avatarMimeType,
            data: Buffer.from(senderProfile.avatarBytes).toString('base64url'),
          }
        : null,
      text: message.text ?? '',
      media: dto.media ?? null,
      replyToMessageId: message.replyToId,
      status: 'sent',
      createdAt: message.createdAt.toISOString(),
      expiresAt: expiresAt?.toISOString() ?? null,
      expiresIn: dto.expiresIn ?? null,
      remainingMs,
      reactions: [],
    };

    // Broadcast via Redis
    const allMembers = await this.prisma.conversationMember.findMany({
      where: { conversationId, leftAt: null },
      select: { userId: true },
    });

    for (const m of allMembers) {
      if (m.userId !== userId) {
        await this.redis.publish(`user:${m.userId}:events`, JSON.stringify({
          type: 'message:new',
          message: payload,
        }));
      }
    }

    // Push notifications to offline members with registered devices
    const offlineMembers = await Promise.all(
      allMembers
        .filter((m) => m.userId !== userId)
        .map(async (m) => {
          const online = await this.redis.isUserOnline(m.userId);
          return online ? null : m.userId;
        }),
    );
    const offlineIds = offlineMembers.filter((id): id is string => id !== null);
    if (offlineIds.length > 0) {
      await this.push.notifyOfflineUsers(offlineIds, {
        title: senderProfile?.displayName ?? 'SejiloChat',
        body: dto.text?.trim() || 'Sent you a message',
        data: {
          type: 'message',
          conversationId,
          messageId: message.id,
        },
      });
    }

    await this.webhooks.onMessageSent({
      messageId: message.id,
      conversationId,
      senderId: userId,
      text: dto.text?.trim(),
      hasMedia: !!dto.media,
      createdAt: message.createdAt.toISOString(),
    });

    return payload;
  }

  /// Throws unless [userId] is a current member of [conversationId].
  ///
  /// Anything reached by message id needs this: the id is the only thing the
  /// caller supplies, so without it a member of no conversation at all can act
  /// on a message inside someone else's private thread.
  private async assertMember(conversationId: string, userId: string) {
    const membership = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    });
    if (!membership || membership.leftAt) {
      throw new ForbiddenException('You are not a member of this conversation.');
    }
  }

  async updateMessageStatus(userId: string, messageId: string, status: string) {
    const msg = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!msg) throw new NotFoundException('Message not found.');
    await this.assertMember(msg.conversationId, userId);
    // A receipt is a claim about the reader, so the sender cannot issue one for
    // their own message. The client already skips its own messages here
    // (OnlineMessagingController.markAsRead), so this only rejects forgeries.
    if (msg.senderId === userId) {
      throw new ForbiddenException(
        'Cannot report delivery status for your own message.',
      );
    }

    const normalizedStatus = status.toUpperCase();
    await this.prisma.message.update({
      where: { id: messageId },
      data: { status: normalizedStatus },
    });

    // Notify sender via Redis
    await this.redis.publish(`user:${msg.senderId}:events`, JSON.stringify({
      type: 'message:status',
      messageId,
      conversationId: msg.conversationId,
      status: status.toLowerCase(),
    }));

    return { success: true };
  }

  async addReaction(userId: string, messageId: string, emoji: string) {
    const msg = await this.prisma.message.findUnique({ where: { id: messageId } });
    if (!msg) throw new NotFoundException('Message not found.');
    await this.assertMember(msg.conversationId, userId);

    await this.prisma.messageReaction.upsert({
      where: { messageId_userId: { messageId, userId } },
      create: { messageId, userId, emoji },
      update: { emoji },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId: msg.conversationId, leftAt: null },
      select: { userId: true },
    });

    for (const m of members) {
      await this.redis.publish(`user:${m.userId}:events`, JSON.stringify({
        type: 'message:reaction',
        messageId,
        conversationId: msg.conversationId,
        userId,
        emoji,
      }));
    }

    // Fire webhook
    await this.webhooks.onMessageReaction({
      messageId,
      conversationId: msg.conversationId,
      userId,
      emoji,
      action: 'added',
      createdAt: new Date().toISOString(),
    });

    return { success: true };
  }

  async deleteMessage(userId: string, messageId: string) {
    const msg = await this.prisma.message.findUnique({ where: { id: messageId } });
    if (!msg) throw new NotFoundException('Message not found.');
    if (msg.senderId !== userId) throw new ForbiddenException('Cannot delete another user message.');

    await this.prisma.message.update({
      where: { id: messageId },
      data: { deletedAt: new Date() },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId: msg.conversationId, leftAt: null },
      select: { userId: true },
    });

    for (const m of members) {
      await this.redis.publish(`user:${m.userId}:events`, JSON.stringify({
        type: 'message:deleted',
        messageId,
        conversationId: msg.conversationId,
      }));
    }

    return { success: true };
  }
}
