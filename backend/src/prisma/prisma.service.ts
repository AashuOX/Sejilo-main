import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/**
 * The application's only durable data access layer.
 *
 * A backend must never accept traffic without PostgreSQL: silently replacing
 * Prisma with an in-memory store makes authentication, messages, and social
 * data disappear on restart. Startup therefore fails when the configured
 * database cannot be reached.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  async onModuleInit(): Promise<void> {
    try {
      await this.$connect();
      this.logger.log('Connected to PostgreSQL via Prisma');
    } catch (error) {
      this.logger.error(
        'PostgreSQL connection failed. Refusing to start without durable storage.',
        error instanceof Error ? error.stack : String(error),
      );
      throw error;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
    this.logger.log('Disconnected from PostgreSQL');
  }
}
