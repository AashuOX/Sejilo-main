import { Module } from '@nestjs/common';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';
import { FirebaseSyncService } from './firebase-sync.service';
import { MeshModule } from '../mesh/mesh.module';
import { WebhooksModule } from '../webhooks/webhooks.module';

@Module({
  imports: [MeshModule, WebhooksModule],
  controllers: [SyncController],
  providers: [SyncService, FirebaseSyncService],
  exports: [SyncService, FirebaseSyncService],
})
export class SyncModule {}
