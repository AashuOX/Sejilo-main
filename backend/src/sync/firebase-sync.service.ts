import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as admin from 'firebase-admin';

/**
 * Optional Firebase integration (STEP: Mesh -> Internet sync, Firebase layer).
 *
 * When FCM credentials are present, synced messages are mirrored into
 * Cloud Firestore (`messages/{clientMessageId}`) so a device can reconcile
 * chat state through Firebase as well as the primary PostgreSQL store. This
 * is additive: failures are swallowed and never break the main sync response.
 */
@Injectable()
export class FirebaseSyncService {
  private readonly logger = new Logger(FirebaseSyncService.name);
  private app?: admin.app.App;

  constructor(private readonly config: ConfigService) {}

  get isConfigured(): boolean {
    return Boolean(
      this.config.get<string>('FCM_PROJECT_ID') &&
        this.config.get<string>('FCM_CLIENT_EMAIL') &&
        this.config.get<string>('FCM_PRIVATE_KEY'),
    );
  }

  private get client(): admin.firestore.Firestore | null {
    if (!this.isConfigured) return null;
    try {
      if (!this.app) {
        const existing = admin.apps.find((a) => a?.name === 'firebase-sync');
        this.app = (existing as admin.app.App) ?? admin.initializeApp(
          {
            credential: admin.credential.cert({
              projectId: this.config.get<string>('FCM_PROJECT_ID'),
              clientEmail: this.config.get<string>('FCM_CLIENT_EMAIL'),
              privateKey: this.config
                .get<string>('FCM_PRIVATE_KEY', '')
                .replace(/\\n/g, '\n'),
            }),
          },
          'firebase-sync',
        );
      }
      return this.app.firestore();
    } catch (err) {
      this.logger.warn(`Firebase init failed: ${(err as Error).message}`);
      return null;
    }
  }

  async mirrorPending(
    userId: string,
    pending: Array<{
      clientMessageId: string;
      conversationId: string;
      text?: string;
      createdAt: string;
      updatedAt?: string;
      deleted?: boolean;
    }>,
  ): Promise<void> {
    const db = this.client;
    if (!db) return;
    try {
      const batch = db.batch();
      for (const p of pending) {
        const ref = db.collection('messages').doc(p.clientMessageId);
        batch.set(
          ref,
          {
            clientMessageId: p.clientMessageId,
            conversationId: p.conversationId,
            senderId: userId,
            text: p.text ?? null,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt ?? p.createdAt,
            deleted: Boolean(p.deleted),
            syncedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      await batch.commit();
    } catch (err) {
      this.logger.warn(`Firebase mirror failed: ${(err as Error).message}`);
    }
  }
}
