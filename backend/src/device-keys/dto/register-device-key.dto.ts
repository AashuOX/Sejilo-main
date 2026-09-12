import { ApiProperty } from '@nestjs/swagger';
import { IsBase64, IsIn, IsNotEmpty, IsString, Length } from 'class-validator';

export class RegisterDeviceKeyDto {
  @ApiProperty({
    example: 'windows-laptop-abc123',
    description: 'Client-generated device identifier (matches devices.device_id)',
  })
  @IsString()
  @IsNotEmpty()
  deviceId: string;

  @ApiProperty({ example: 'windows', enum: ['android', 'windows', 'web', 'ios', 'linux', 'macos'] })
  @IsIn(['android', 'windows', 'web', 'ios', 'linux', 'macos'])
  platform: string;

  @ApiProperty({ example: 'base64', description: 'Base64-encoded X25519 public key (32 bytes)' })
  @IsBase64()
  @IsNotEmpty()
  publicKey: string;

  @ApiProperty({ example: 'base64', description: 'Base64-encoded Ed25519 signature over the public key (64 bytes)' })
  @IsBase64()
  @IsNotEmpty()
  signature: string;

  @ApiProperty({ required: false, default: 'x25519' })
  @IsIn(['x25519'])
  @IsNotEmpty()
  keyType: string = 'x25519';
}