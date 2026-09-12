import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Redis } from 'ioredis';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private client: Redis | null = null;
  private pubClient: Redis | null = null;
  private subClient: Redis | null = null;

  constructor(private readonly config: ConfigService) {}

  onModuleInit() {
    const redisUrl = this.config.get<string>('REDIS_URL', 'redis://localhost:6379');
    try {
      this.client = new Redis(redisUrl, { lazyConnect: true, maxRetriesPerRequest: 1 });
      this.pubClient = new Redis(redisUrl, { lazyConnect: true, maxRetriesPerRequest: 1 });
      this.subClient = new Redis(redisUrl, { lazyConnect: true, maxRetriesPerRequest: 1 });

      // Attach error handlers so a failed/unreachable Redis degrades gracefully
      // instead of emitting an unhandled 'error' event that would crash the process.
      this.client.on('error', (err) => this.logger.warn(`Redis client error: ${err.message}`));
      this.pubClient.on('error', (err) => this.logger.warn(`Redis pub client error: ${err.message}`));
      this.subClient.on('error', (err) => this.logger.warn(`Redis sub client error: ${err.message}`));

      this.client.connect().then(() => {
        this.logger.log('Connected to Redis');
      }).catch((err) => {
        this.logger.warn(`Redis connection deferred: ${err.message}`);
      });
    } catch (err) {
      this.logger.warn(`Redis initialization warning: ${(err as Error).message}`);
    }
  }

  async onModuleDestroy() {
    await this.client?.quit().catch(() => {});
    await this.pubClient?.quit().catch(() => {});
    await this.subClient?.quit().catch(() => {});
  }

  getClient(): Redis | null {
    return this.client;
  }

  // ── Generic Key-Value Operations ──
  async get(key: string): Promise<string | null> {
    if (!this.client) return null;
    try {
      return await this.client.get(key);
    } catch (_) {
      return null;
    }
  }

  async set(key: string, value: string, ...args: any[]): Promise<void> {
    if (!this.client) return;
    try {
      await this.client.set(key, value, ...args);
    } catch (_) {}
  }

  async del(key: string): Promise<void> {
    if (!this.client) return;
    try {
      await this.client.del(key);
    } catch (_) {}
  }

  // ── Online Presence ──
  async setUserOnline(userId: string, ttlSeconds = 60): Promise<void> {
    if (!this.client) return;
    try {
      await this.client.set(`presence:user:${userId}`, 'online', 'EX', ttlSeconds);
    } catch (_) {}
  }

  async isUserOnline(userId: string): Promise<boolean> {
    if (!this.client) return false;
    try {
      const res = await this.client.get(`presence:user:${userId}`);
      return res === 'online';
    } catch (_) {
      return false;
    }
  }

  async setUserOffline(userId: string): Promise<void> {
    if (!this.client) return;
    try {
      await this.client.del(`presence:user:${userId}`);
    } catch (_) {}
  }

  // ── Typing Indicator ──
  async setTyping(conversationId: string, userId: string, ttlSeconds = 5): Promise<void> {
    if (!this.client) return;
    try {
      await this.client.set(`typing:${conversationId}:${userId}`, '1', 'EX', ttlSeconds);
    } catch (_) {}
  }

  async isTyping(conversationId: string, userId: string): Promise<boolean> {
    if (!this.client) return false;
    try {
      const res = await this.client.get(`typing:${conversationId}:${userId}`);
      return res === '1';
    } catch (_) {
      return false;
    }
  }

  // ── Pub/Sub ──
  async publish(channel: string, message: string): Promise<void> {
    if (!this.pubClient) return;
    try {
      await this.pubClient.publish(channel, message);
    } catch (_) {}
  }

  subscribe(channel: string, callback: (message: string) => void): void {
    if (!this.subClient) return;
    try {
      this.subClient.subscribe(channel, (err) => {
        if (err) this.logger.warn(`Failed to subscribe to channel ${channel}`);
      });
      this.subClient.on('message', (chan, msg) => {
        if (chan === channel) callback(msg);
      });
    } catch (_) {}
  }
}
