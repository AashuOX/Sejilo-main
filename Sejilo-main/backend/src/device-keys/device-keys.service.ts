import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDeviceKeyDto } from './dto/register-device-key.dto';

const X25519_PUBLIC_KEY_LENGTH = 32;
const ED25519_SIGNATURE_LENGTH = 64;

export interface DeviceKeyBundle {
  id: string;
  deviceId: string;
  keyType: string;
  publicKey: string;
  signature: string;
  createdAt: Date;
}

function toBundle(row: {
  id: string;
  deviceId: string;
  keyType: string;
  publicKey: Uint8Array;
  signature: Uint8Array;
  createdAt: Date;
}): DeviceKeyBundle {
  return {
    id: row.id,
    deviceId: row.deviceId,
    keyType: row.keyType,
    publicKey: Buffer.from(row.publicKey).toString('base64'),
    signature: Buffer.from(row.signature).toString('base64'),
    createdAt: row.createdAt,
  };
}

@Injectable()
export class DeviceKeysService {
  constructor(private readonly prisma: PrismaService) {}

  async register(userId: string, dto: RegisterDeviceKeyDto) {
    const publicKey = Buffer.from(dto.publicKey, 'base64');
    const signature = Buffer.from(dto.signature, 'base64');

    if (publicKey.length !== X25519_PUBLIC_KEY_LENGTH) {
      throw new BadRequestException('Invalid public key length: expected 32 bytes for X25519.');
    }
    if (signature.length !== ED25519_SIGNATURE_LENGTH) {
      throw new BadRequestException('Invalid signature length: expected 64 bytes for Ed25519.');
    }

    const device = await this.prisma.device.upsert({
      where: { deviceId: dto.deviceId },
      update: { userId, platform: dto.platform, lastActiveAt: new Date() },
      create: {
        deviceId: dto.deviceId,
        platform: dto.platform,
        userId,
        lastActiveAt: new Date(),
      },
    });

    const row = await this.prisma.deviceKey.upsert({
      where: { deviceId: device.id },
      update: { userId, publicKey, signature, keyType: dto.keyType },
      create: {
        deviceId: device.id,
        userId,
        publicKey,
        signature,
        keyType: dto.keyType,
      },
    });

    return { key: toBundle(row) };
  }

  async listForUser(userId: string) {
    const rows = await this.prisma.deviceKey.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
    return { keys: rows.map(toBundle) };
  }

  async remove(userId: string, deviceId: string) {
    const device = await this.prisma.device.findUnique({ where: { deviceId } });
    if (!device || !device.userId) {
      throw new NotFoundException('Device not found.');
    }
    if (device.userId !== userId) {
      throw new NotFoundException('Device not found.');
    }
    await this.prisma.deviceKey.deleteMany({ where: { deviceId: device.id } });
    return { removed: true };
  }
}