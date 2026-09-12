import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { AuthModule } from '../auth/auth.module';
import { ChatController } from './chat.controller';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';
import { SearchService } from './search.service';
import { ExpirationScheduler } from './expiration.scheduler';
import { PushService } from './push.service';
import { MessageRequestsController } from './message-requests.controller';
import { MessageRequestsService } from './message-requests.service';
import { WebhooksModule } from '../webhooks/webhooks.module';

@Module({
  imports: [AuthModule, ScheduleModule.forRoot(), WebhooksModule],
  controllers: [ChatController, MessageRequestsController],
  providers: [ChatService, SearchService, ChatGateway, PushService, ExpirationScheduler, MessageRequestsService],
  exports: [ChatService, SearchService, ChatGateway, PushService, ExpirationScheduler],
})
export class ChatModule {}
