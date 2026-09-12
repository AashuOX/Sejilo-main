import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerModule } from '@nestjs/throttler';
import { AuthModule } from './auth/auth.module';
import { ChatModule } from './chat/chat.module';
import { validate } from './common/config/env.validation';
import { ContentVisibilityModule } from './common/content-visibility.module';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { ProxyAwareThrottlerGuard } from './common/guards/proxy-throttler.guard';
import { DeviceKeysModule } from './device-keys/device-keys.module';
import { HealthModule } from './health/health.module';
import { MediaModule } from './media/media.module';
import { MeshModule } from './mesh/mesh.module';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './redis/redis.module';
import { ReportsModule } from './reports/reports.module';
import { SocialModule } from './social/social.module';
import { SyncModule } from './sync/sync.module';
import { UsersModule } from './users/users.module';
import { WebhooksModule } from './webhooks/webhooks.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate,
      envFilePath: ['.env', '.env.local'],
    }),
    ThrottlerModule.forRoot([
      {
        name: 'default',
        ttl: 60000,
        limit: 120,
      },
    ]),
    PrismaModule,
    RedisModule,
    ContentVisibilityModule,
    AuthModule,
    UsersModule,
    SocialModule,
    ReportsModule,
    ChatModule,
    MediaModule,
    MeshModule,
    DeviceKeysModule,
    SyncModule,
    HealthModule,
    WebhooksModule,
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },
    {
      provide: APP_GUARD,
      useClass: ProxyAwareThrottlerGuard,
    },
  ],
})
export class AppModule {}
