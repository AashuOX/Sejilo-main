import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as admin from 'firebase-admin';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Firebase Cloud Messaging push delivery for offline chat members.
 *
 * Initializes the Firebase Admin SDK lazily only when FCM credentials are
 * present in the environment. Without credentials, pushes are logged (dev
 * mode) and the chat flow continues normally.
 */
@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);
  private readonly projectId: string;
  private readonly clientEmail: string;
  private readonly privateKey: string;
  private initialized = false;

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    this.projectId = this.config.get<string>('FCM_PROJECT_ID', '');
    this.clientEmail = this.config.get<string>('FCM_CLIENT_EMAIL', '');
    this.privateKey = this.config.get<string>('FCM_PRIVATE_KEY', '').replace(/\\n/g, '\n');
  }

  get isConfigured(): boolean {
    return Boolean(this.projectId && this.clientEmail && this.privateKey);
  }

  private init(): boolean {
    if (!this.isConfigured || this.initialized) {
      return this.initialized && this.isConfigured;
    }
    try {
      if (admin.apps.length === 0) {
        admin.initializeApp({
          credential: admin.credential.cert({
            projectId: this.projectId,
            clientEmail: this.clientEmail,
            privateKey: this.privateKey,
          }),
        });
      }
      this.initialized = true;
      this.logger.log('Firebase Cloud Messaging initialized');
    } catch (err) {
      this.logger.error(`FCM initialization failed: ${(err as Error).message}`);
    }
    return this.initialized;
  }

  /**
   * Send a push notification to all push-capable devices of the given users
   * that are currently offline. Failures are logged but never thrown so that
   * message delivery through Redis/WebSocket is unaffected.
   */
  async notifyOfflineUsers(userIds: string[], payload: {
    title: string;
    body: string;
    data?: Record<string, string>;
  }): Promise<void> {
    if (!this.init() || userIds.length === 0) return;

    const devices = await this.prisma.device.findMany({
      where: { userId: { in: userIds }, pushToken: { not: null } },
    });

    if (devices.length === 0) {
      this.logger.debug(`No push tokens for offline users`);
      return;
    }

    const tokens = devices
      .map((d) => d.pushToken)
      .filter((t): t is string => Boolean(t));

    const message = {
      notification: { title: payload.title, body: payload.body },
      data: payload.data ?? {},
      tokens,
    };

    try {
      const result = await admin.messaging().sendEachForMulticast(message);
      this.logger.log(
        `FCM sent: ${result.successCount} ok, ${result.failureCount} failed`,
      );
    } catch (err) {
      this.logger.error(`FCM send failed: ${(err as Error).message}`);
    }
  }
}