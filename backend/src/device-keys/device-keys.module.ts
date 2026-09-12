import { Module } from '@nestjs/common';
import { DeviceKeysController } from './device-keys.controller';
import { DeviceKeysService } from './device-keys.service';

@Module({
  controllers: [DeviceKeysController],
  providers: [DeviceKeysService],
  exports: [DeviceKeysService],
})
export class DeviceKeysModule {}