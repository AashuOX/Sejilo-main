import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface WebhookPayload {
  event: string;
  timestamp: string;
  data: Record<string, any>;
}

export interface WebhookConfig {
  chat: string;
  analytics: string;
  notifications: string;
  media: string;
  social: string;
  posts: string;
  btSync: string;
  auth: string;
}

@Injectable()
export class WebhooksService {
  private readonly logger = new Logger(WebhooksService.name);
  private readonly webhookUrls: WebhookConfig;
  private readonly enabled: boolean;
  private readonly secret: string;

  constructor(
    private readonly configService: ConfigService,
  ) {
    this.webhookUrls = {
      chat: this.configService.get<string>('WEBHOOK_CHAT_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/chat',
      analytics: this.configService.get<string>('WEBHOOK_ANALYTICS_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/analytics',
      notifications: this.configService.get<string>('WEBHOOK_NOTIFICATIONS_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/notifications',
      media: this.configService.get<string>('WEBHOOK_MEDIA_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/media',
      social: this.configService.get<string>('WEBHOOK_SOCIAL_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/social',
      posts: this.configService.get<string>('WEBHOOK_POSTS_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/posts',
      btSync: this.configService.get<string>('WEBHOOK_BT_SYNC_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/bt-sync',
      auth: this.configService.get<string>('WEBHOOK_AUTH_URL') || 'https://sejilochat.app.n8n.cloud/webhook-test/auth',
    };

    this.enabled = this.configService.get<string>('WEBHOOKS_ENABLED') === 'true';
    this.secret = this.configService.get<string>('WEBHOOK_SECRET', '');

    if (this.enabled) {
      this.logger.log('Webhooks service initialized with n8n endpoints');
    } else {
      this.logger.warn('Webhooks service is disabled. Set WEBHOOKS_ENABLED=true to enable.');
    }
  }

  private async fireWebhook(url: string, payload: WebhookPayload): Promise<void> {
    if (!this.enabled) {
      this.logger.debug(`Webhooks disabled, skipping event: ${payload.event}`);
      return;
    }

    try {
      await this.postWithRetry(url, payload);
      this.logger.debug(`Webhook fired successfully: ${payload.event} -> ${url}`);
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(`Failed to fire webhook ${payload.event} to ${url}: ${message}`);
    }
  }

  private async postWithRetry(url: string, payload: WebhookPayload, timeoutMs = 5000): Promise<void> {
    let lastError: unknown;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const response = await fetch(url, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            ...(this.secret ? { 'x-sejilo-webhook-secret': this.secret } : {}),
          },
          body: JSON.stringify(payload),
          signal: controller.signal,
        });
        if (!response.ok) {
          throw new Error(`Webhook responded with HTTP ${response.status}`);
        }
        return;
      } catch (error) {
        lastError = error;
      } finally {
        clearTimeout(timeoutId);
      }
    }
    throw lastError instanceof Error ? lastError : new Error(String(lastError));
  }

  // Chat events
  async onMessageSent(data: {
    messageId: string;
    conversationId: string;
    senderId: string;
    text?: string;
    hasMedia: boolean;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.chat, {
      event: 'message.sent',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onMessageReceived(data: {
    messageId: string;
    conversationId: string;
    senderId: string;
    recipientId: string;
    text?: string;
    hasMedia: boolean;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.chat, {
      event: 'message.received',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onConversationCreated(data: {
    conversationId: string;
    type: 'direct' | 'group';
    participants: string[];
    createdBy: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.chat, {
      event: 'conversation.created',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onMessageReaction(data: {
    messageId: string;
    conversationId: string;
    userId: string;
    emoji: string;
    action: 'added' | 'removed';
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.chat, {
      event: 'message.reaction',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Auth events
  async onUserRegistered(data: {
    userId: string;
    email?: string;
    username?: string;
    provider: 'email' | 'google' | 'phone';
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.auth, {
      event: 'user.registered',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onUserLoggedIn(data: {
    userId: string;
    provider: 'email' | 'google' | 'phone';
    deviceId?: string;
    ip?: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.auth, {
      event: 'user.logged_in',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onUserLoggedOut(data: {
    userId: string;
    deviceId?: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.auth, {
      event: 'user.logged_out',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Posts events
  async onPostCreated(data: {
    postId: string;
    userId: string;
    caption?: string;
    location?: string;
    mediaCount: number;
    hasVideo: boolean;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.posts, {
      event: 'post.created',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onPostDeleted(data: {
    postId: string;
    userId: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.posts, {
      event: 'post.deleted',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onPostLiked(data: {
    postId: string;
    userId: string;
    postOwnerId: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.posts, {
      event: 'post.liked',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onPostCommented(data: {
    postId: string;
    commentId: string;
    userId: string;
    postOwnerId: string;
    text: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.posts, {
      event: 'post.commented',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Social events (follows, stories)
  async onUserFollowed(data: {
    followerId: string;
    followingId: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.social, {
      event: 'user.followed',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onUserUnfollowed(data: {
    followerId: string;
    followingId: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.social, {
      event: 'user.unfollowed',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onStoryCreated(data: {
    storyId: string;
    userId: string;
    mediaType: 'image' | 'video';
    expiresAt: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.social, {
      event: 'story.created',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onStoryViewed(data: {
    storyId: string;
    viewerId: string;
    ownerId: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.social, {
      event: 'story.viewed',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Media events
  async onMediaUploaded(data: {
    mediaId: string;
    userId: string;
    type: 'image' | 'video' | 'audio' | 'document';
    size: number;
    mimeType: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.media, {
      event: 'media.uploaded',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onMediaDeleted(data: {
    mediaId: string;
    userId: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.media, {
      event: 'media.deleted',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Notifications events
  async onNotificationCreated(data: {
    notificationId: string;
    userId: string;
    type: 'like' | 'comment' | 'follow' | 'message' | 'mention' | 'story_view' | 'system';
    actorId?: string;
    postId?: string;
    conversationId?: string;
    storyId?: string;
    title: string;
    body: string;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.notifications, {
      event: 'notification.created',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Sync events (Bluetooth/mesh + offline sync)
  async onSyncCompleted(data: {
    userId: string;
    syncedMessages: number;
    syncedContacts: number;
    syncType: 'bluetooth' | 'internet' | 'hybrid';
    durationMs: number;
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.btSync, {
      event: 'sync.completed',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  async onSyncFailed(data: {
    userId: string;
    error: string;
    syncType: 'bluetooth' | 'internet' | 'hybrid';
    createdAt: string;
  }): Promise<void> {
    await this.fireWebhook(this.webhookUrls.btSync, {
      event: 'sync.failed',
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Analytics events (generic - for any custom analytics)
  async onAnalyticsEvent(eventName: string, data: Record<string, any>): Promise<void> {
    await this.fireWebhook(this.webhookUrls.analytics, {
      event: eventName,
      timestamp: new Date().toISOString(),
      data,
    });
  }

  // Health check - verify all webhooks are reachable
  async healthCheck(): Promise<Record<string, boolean>> {
    const results: Record<string, boolean> = {};

    for (const [name, url] of Object.entries(this.webhookUrls)) {
      try {
        await this.postWithRetry(url, {
          event: 'health.check',
          timestamp: new Date().toISOString(),
          data: { service: 'sejilo-backend' },
        }, 3000);
        results[name] = true;
      } catch {
        results[name] = false;
      }
    }

    return results;
  }
}
