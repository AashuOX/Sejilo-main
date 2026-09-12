import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { MeshRelayService } from '../mesh/mesh-relay.service';
import { FirebaseSyncService } from './firebase-sync.service';
import { SyncRequestDto } from './dto/sync-request.dto';
import { WebhooksService } from '../webhooks/webhooks.service';
import { ExpirationScheduler } from '../chat/expiration.scheduler';
import { ContentVisibilityService } from '../common/content-visibility.service';

@Injectable()
export class SyncService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly meshRelay: MeshRelayService,
    private readonly firebaseSync: FirebaseSyncService,
    private readonly webhooks: WebhooksService,
    private readonly visibility: ContentVisibilityService,
  ) {}

  async sync(userId: string, dto: SyncRequestDto) {
    const startedAt = Date.now();
    const acknowledgedMessageIds: string[] = [];

    // 1. Ingest any pending messages sent while offline
    if (dto.pendingMessages && dto.pendingMessages.length > 0) {
      for (const pending of dto.pendingMessages) {
        try {
          // Check membership
          const isMember = await this.prisma.conversationMember.findUnique({
            where: {
              conversationId_userId: {
                conversationId: pending.conversationId,
                userId,
              },
            },
            include: {
              conversation: {
                select: {
                  kind: true,
                  members: { where: { leftAt: null }, select: { userId: true } },
                },
              },
            },
          });
          if (!isMember) continue;

          // The offline queue is the other way into a conversation, so the block
          // has to hold here too — otherwise anything refused by
          // `POST /v1/chat/.../messages` arrives simply by being queued and
          // flushed. Skipped rather than thrown, and left unacknowledged, for
          // the same reason a non-member is: one bad row must not abort the
          // whole sync.
          if (isMember.conversation.kind === 'direct') {
            const other = isMember.conversation.members.find(
              (m) => m.userId !== userId,
            );
            if (
              other &&
              (await this.visibility.isBlockedBetween(userId, other.userId))
            ) {
              continue;
            }
          }

          let mediaBytes: any = undefined;
          let mediaMimeType: string | undefined;
          if (pending.media && pending.media.data && pending.media.mimeType) {
            mediaBytes = Buffer.from(pending.media.data, 'base64url');
            mediaMimeType = pending.media.mimeType;
          }

          const incomingUpdated = pending.updatedAt
            ? new Date(pending.updatedAt)
            : new Date(pending.createdAt);

          // Conflict handling: dedupe by clientMessageId, resolve with
          // Last-Write-Wins on updatedAt. A deletion intent always wins.
          const existing = await this.prisma.message.findUnique({
            where: { clientMessageId: pending.clientMessageId },
          });

          if (existing) {
            const existingUpdated =
              existing.updatedAt ?? existing.createdAt;
            const shouldApply =
              Boolean(pending.deleted) ||
              incomingUpdated.getTime() > existingUpdated.getTime();

            if (shouldApply) {
              await this.prisma.message.update({
                where: { id: existing.id },
                data: {
                  text: pending.deleted
                    ? existing.text
                    : pending.text?.trim() ?? null,
                  mediaBytes: pending.deleted
                    ? existing.mediaBytes
                    : mediaBytes,
                  mediaMimeType: pending.deleted
                    ? existing.mediaMimeType
                    : mediaMimeType,
                  deletedAt: pending.deleted ? new Date() : existing.deletedAt,
                },
              });
            }
            acknowledgedMessageIds.push(pending.clientMessageId);
            continue;
          }

          const msg = await this.prisma.message.create({
            data: {
              conversationId: pending.conversationId,
              senderId: userId,
              text: pending.text?.trim() ?? null,
              mediaBytes,
              mediaMimeType,
              replyToId: pending.replyToMessageId ?? null,
              clientMessageId: pending.clientMessageId,
              status: 'SENT',
              expiresAt: pending.expiresIn
                ? ExpirationScheduler.getExpirationTime(pending.expiresIn)
                : null,
              createdAt: new Date(pending.createdAt),
              deletedAt: pending.deleted ? new Date() : null,
            },
          });

          acknowledgedMessageIds.push(pending.clientMessageId);
        } catch (_) {}
      }
    }

    // Mirror ingested messages into Firebase (Firestore) when configured.
    if (dto.pendingMessages && dto.pendingMessages.length > 0) {
      await this.firebaseSync.mirrorPending(userId, dto.pendingMessages);
    }

    // 2. Fetch new messages in user's conversations created after lastSyncCursor
    const userConvs = await this.prisma.conversationMember.findMany({
      where: { userId, leftAt: null },
      select: { conversationId: true },
    });

    const convIds = userConvs.map((c) => c.conversationId);
    const cursorDate = dto.lastSyncCursor && !isNaN(Date.parse(dto.lastSyncCursor))
      ? new Date(dto.lastSyncCursor)
      : new Date(0);

    const newMessages = await this.prisma.message.findMany({
      where: {
        conversationId: { in: convIds },
        createdAt: { gt: cursorDate },
        deletedAt: null,
      },
      orderBy: { createdAt: 'asc' },
      take: 100,
      include: {
        sender: { include: { profile: true } },
        reactions: true,
      },
    });

    const currentCursor = new Date().toISOString();

    // Mesh -> Internet sync: pull relayed encrypted envelopes addressed to
    // this user (queued by peers while offline) and surface them in the same
    // sync response so a single call reconciles both channels.
    const meshEnvelopes = await this.meshRelay.fetchInbox(userId);

    await this.webhooks.onSyncCompleted({
      userId,
      syncedMessages: acknowledgedMessageIds.length + newMessages.length,
      syncedContacts: 0,
      syncType: 'internet',
      durationMs: Date.now() - startedAt,
      createdAt: new Date().toISOString(),
    });

    return {
      syncCursor: currentCursor,
      acknowledgedMessageIds,
      messages: newMessages.map((m: any) => ({
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
        reactions: m.reactions.map((r: any) => ({ userId: r.userId, emoji: r.emoji })),
      })),
      meshEnvelopes,
    };
  }
}
