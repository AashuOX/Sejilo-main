import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { DeviceKeysService } from './device-keys.service';
import { RegisterDeviceKeyDto } from './dto/register-device-key.dto';

@ApiTags('Device Keys (Mesh E2EE)')
@Controller()
export class DeviceKeysController {
  constructor(private readonly deviceKeysService: DeviceKeysService) {}

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('v1/device-keys')
  @ApiOperation({ summary: 'Register or update your device X25519 key bundle' })
  async register(@CurrentUser('userId') userId: string, @Body() dto: RegisterDeviceKeyDto) {
    return this.deviceKeysService.register(userId, dto);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('v1/users/:userId/device-keys')
  @ApiOperation({ summary: 'Fetch a user\'s device key bundles for E2EE setup' })
  async listForUser(@Param('userId') userId: string) {
    return this.deviceKeysService.listForUser(userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('v1/device-keys/:deviceId')
  @ApiOperation({ summary: 'Remove your device key bundle' })
  async remove(@CurrentUser('userId') userId: string, @Param('deviceId') deviceId: string) {
    return this.deviceKeysService.remove(userId, deviceId);
  }
}