import { Module } from '@nestjs/common';
import { FollowsController } from './follows.controller';
import { FollowsService } from './follows.service';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { PostsController } from './posts.controller';
import { PostsService } from './posts.service';
import { StoriesController } from './stories.controller';
import { StoriesService } from './stories.service';
import { WebhooksModule } from '../webhooks/webhooks.module';

@Module({
  imports: [WebhooksModule],
  controllers: [
    PostsController,
    FollowsController,
    StoriesController,
    NotificationsController,
  ],
  providers: [
    PostsService,
    FollowsService,
    StoriesService,
    NotificationsService,
  ],
  exports: [
    PostsService,
    FollowsService,
    StoriesService,
    NotificationsService,
  ],
})
export class SocialModule {}
