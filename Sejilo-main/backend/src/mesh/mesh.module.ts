import { Module } from '@nestjs/common';
import { MeshController } from './mesh.controller';
import { MeshRelayService } from './mesh-relay.service';

@Module({
  controllers: [MeshController],
  providers: [MeshRelayService],
  exports: [MeshRelayService],
})
export class MeshModule {}
