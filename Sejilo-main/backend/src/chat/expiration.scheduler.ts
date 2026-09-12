import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ExpirationScheduler {
  private readonly logger = new Logger(ExpirationScheduler.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Run every 5 minutes to clean up expired messages
   */
  @Cron(CronExpression.EVERY_5_MINUTES)
  async handleExpiredMessages() {
    try {
      const now = new Date();

      // Find and soft-delete expired messages
      const result = await this.prisma.message.updateMany({
        where: {
          expiresAt: {
            lt: now,
            not: null,
          },
          deletedAt: null,
          status: { not: 'EXPIRED' },
        },
        data: {
          status: 'EXPIRED',
          deletedAt: now,
        },
      });

      if (result.count > 0) {
        this.logger.log(`Cleaned up ${result.count} expired messages`);
      }
    } catch (error) {
      this.logger.error('Error cleaning up expired messages', error);
    }
  }

  /**
   * Calculate expiration time based on duration string
   */
  static getExpirationTime(expiresIn: string): Date | null {
    const now = new Date();
    const durations: Record<string, number> = {
      '1m': 1 * 60 * 1000,
      '5m': 5 * 60 * 1000,
      '1h': 60 * 60 * 1000,
      '24h': 24 * 60 * 60 * 1000,
      '7d': 7 * 24 * 60 * 60 * 1000,
    };

    const duration = durations[expiresIn];
    if (!duration) return null;

    return new Date(now.getTime() + duration);
  }

  /**
   * Get remaining time in milliseconds until message expires
   */
  static getRemainingTime(expiresAt: Date | null): number | null {
    if (!expiresAt) return null;
    const remaining = expiresAt.getTime() - Date.now();
    return remaining > 0 ? remaining : 0;
  }
}
