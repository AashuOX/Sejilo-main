import { IsInt, IsNotEmpty, IsOptional, IsString, Min } from 'class-validator';

export class RelayMessageDto {
  @IsString()
  @IsNotEmpty()
  messageId: string;

  @IsString()
  @IsNotEmpty()
  destinationId: string;

  @IsInt()
  @Min(0)
  hopCount: number;

  @IsInt()
  @Min(1)
  maxHops: number;

  /** Seconds the relayed message may live in the inbox. */
  @IsInt()
  @Min(1)
  ttl: number;

  /** Optional absolute expiry as epoch milliseconds. */
  @IsOptional()
  @IsInt()
  expiresAt?: number;

  @IsString()
  @IsNotEmpty()
  encryptedPayload: string;
}
