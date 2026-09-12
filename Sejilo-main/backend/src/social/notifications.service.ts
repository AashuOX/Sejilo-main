import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { WebhooksService } from '../webhooks/webhooks.service';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly webhooks: WebhooksService,
  ) {}

  async getNotifications(userId: string) {
    const notifications = await this.prisma.notification.findMany({
      where: { userId },
      take: 50,
      orderBy: { createdAt: 'desc' },
      include: {
        actor: { include: { profile: true } },
        post: { include: { media: { take: 1 } } },
      },
    });

    const unreadCount = notifications.filter((n) => !n.isRead).length;

    return {
      unreadCount,
      notifications: notifications.map((n) => {
        const postMedia = n.post?.media?.[0];
        return {
          id: n.id,
          type: n.type,
          postId: n.postId,
          isRead: n.isRead,
          createdAt: n.createdAt.toISOString(),
          actor: n.actor
            ? {
                id: n.actor.id,
                username: n.actor.profile?.username ?? '',
                displayName: n.actor.profile?.displayName ?? '',
                avatar: n.actor.profile?.avatarBytes && n.actor.profile?.avatarMimeType
                  ? {
                      mimeType: n.actor.profile.avatarMimeType,
                      data: Buffer.from(n.actor.profile.avatarBytes).toString('base64url'),
                    }
                  : null,
              }
            : null,
          postMedia: postMedia?.mediaBytes && postMedia?.mimeType
            ? {
                mimeType: postMedia.mimeType,
                data: Buffer.from(postMedia.mediaBytes).toString('base64url'),
              }
            : null,
        };
      }),
    };
  }

  async markAllRead(userId: string) {
    await this.prisma.notification.updateMany({
      where: { userId, isRead: false },
      data: { isRead: true, readAt: new Date() },
    });
    return { success: true };
  }

  async markRead(notificationId: string, userId: string) {
    const notification = await this.prisma.notification.findUnique({
      where: { id: notificationId },
    });
    if (!notification) throw new NotFoundException('Notification not found.');
    if (notification.userId !== userId) {
      throw new ForbiddenException('Cannot modify another user notification.');
    }
    await this.prisma.notification.update({
      where: { id: notificationId },
      data: { isRead: true, readAt: new Date() },
    });
    return { success: true };
  }

  async fireNotificationWebhook(data: {
    notificationId: string;
    userId: string;
    type: 'like' | 'comment' | 'follow' | 'message' | 'mention' | 'story_view' | 'system';
    actorId?: string;
    postId?: string;
    conversationId?: string;
    storyId?: string;
    title: string;
    body: string;
  }): Promise<void> {
    await this.webhooks.onNotificationCreated({
      ...data,
      createdAt: new Date().toISOString(),
    });
  }
}
