import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { RedisService } from '../redis/redis.service';
import { RelayMessageDto } from './dto/relay-message.dto';

export interface RelayEnvelope {
  messageId: string;
  sourceId: string;
  destinationId: string;
  hopCount: number;
  maxHops: number;
  encryptedPayload: string;
  receivedAt: number;
  expiresAt: number;
}

export type RelayStatus = 'queued' | 'duplicate' | 'rejected';

export interface RelayResult {
  status: RelayStatus;
  reason?: string;
  expiresAt?: number;
}

/**
 * Server-side store-and-forward relay for offline/mesh messaging (STEP 23/25).
 *
 * Envelopes are transient and live in Redis only — they are encrypted end-to-end
 * by the clients, so the server never inspects payloads. Responsibilities:
 *  - enforce TTL and max-hop limits,
 *  - deduplicate per (destination, messageId) so a destination receives each
 *    unique message at most once regardless of which peer relayed it,
 *  - hold envelopes in the destination's inbox until pulled,
 *  - support multi-hop forwarding (a peer that picked up an envelope re-relays
 *    it toward the final destination, incrementing the hop counter).
 */
@Injectable()
export class MeshRelayService {
  private readonly logger = new Logger(MeshRelayService.name);

  constructor(private readonly redis: RedisService) {}

  private getClientOrNull() {
    return this.redis.getClient();
  }

  private requireClient() {
    const client = this.redis.getClient();
    if (!client) {
      throw new BadRequestException('Relay unavailable (Redis offline).');
    }
    return client;
  }

  async relay(
    senderId: string,
    dto: RelayMessageDto,
  ): Promise<RelayResult> {
    if (!dto.messageId || !dto.destinationId || !dto.encryptedPayload) {
      throw new BadRequestException(
        'messageId, destinationId and encryptedPayload are required.',
      );
    }

    const client = this.requireClient();
    const now = Date.now();
    const expiresAt = dto.expiresAt ?? now + dto.ttl * 1000;
    const ttlSeconds = Math.max(0, Math.floor((expiresAt - now) / 1000));

    if (ttlSeconds <= 0) {
      return { status: 'rejected', reason: 'expired' };
    }
    if (dto.hopCount >= dto.maxHops) {
      return { status: 'rejected', reason: 'max hops exceeded' };
    }

    // Deduplicate per destination: the destination receives each unique
    // messageId at most once, regardless of which peer forwarded it.
    const seenKey = `relay:seen:${dto.destinationId}:${dto.messageId}`;
    const accepted = await client.set(seenKey, '1', 'EX', ttlSeconds, 'NX');
    if (accepted === null) {
      return { status: 'duplicate' };
    }

    const envelope: RelayEnvelope = {
      messageId: dto.messageId,
      sourceId: senderId,
      destinationId: dto.destinationId,
      hopCount: dto.hopCount,
      maxHops: dto.maxHops,
      encryptedPayload: dto.encryptedPayload,
      receivedAt: now,
      expiresAt,
    };

    const inboxKey = `relay:inbox:${dto.destinationId}`;
    await client.rpush(inboxKey, JSON.stringify(envelope));
    await client.expire(inboxKey, ttlSeconds);

    this.logger.log(
      `Relayed ${dto.messageId} -> ${dto.destinationId} (hop ${dto.hopCount}/${dto.maxHops})`,
    );
    return { status: 'queued', expiresAt };
  }

  /**
   * Multi-hop store-and-forward. A peer that picked up an envelope re-relays it
   * to the *next-hop peer* (the envelope's `destinationId` becomes that peer),
   * incrementing the hop counter. The final recipient only receives the message
   * once the last hop targets it. Returns `duplicate` if the next hop already
   * holds the message (loop guard), or `rejected` if the hop limit is reached.
   */
  async relayHop(
    envelope: RelayEnvelope,
    nextHopPeerId: string,
  ): Promise<RelayResult> {
    const remainingTtlSeconds = Math.max(
      1,
      Math.ceil((envelope.expiresAt - Date.now()) / 1000),
    );
    return this.relay(nextHopPeerId, {
      messageId: envelope.messageId,
      destinationId: nextHopPeerId,
      hopCount: envelope.hopCount + 1,
      maxHops: envelope.maxHops,
      ttl: remainingTtlSeconds,
      expiresAt: envelope.expiresAt,
      encryptedPayload: envelope.encryptedPayload,
    } as RelayMessageDto);
  }

  /** Non-destructive read of the destination inbox (for counts/previews). */
  async peekInbox(userId: string): Promise<RelayEnvelope[]> {
    const client = this.getClientOrNull();
    if (!client) return [];
    const raw = await client.lrange(`relay:inbox:${userId}`, 0, -1);
    return raw.map((r) => JSON.parse(r) as RelayEnvelope);
  }

  async getInboxCount(userId: string): Promise<number> {
    const client = this.getClientOrNull();
    if (!client) return 0;
    return client.llen(`relay:inbox:${userId}`);
  }

  /** Fetch and clear the destination inbox. */
  async fetchInbox(userId: string): Promise<RelayEnvelope[]> {
    const client = this.getClientOrNull();
    if (!client) return [];
    const inboxKey = `relay:inbox:${userId}`;
    const raw = await client.lrange(inboxKey, 0, -1);
    if (raw.length > 0) {
      await client.del(inboxKey);
    }
    return raw.map((r) => JSON.parse(r) as RelayEnvelope);
  }

  /** Remove a specific message from the inbox once the client confirms receipt. */
  async acknowledge(
    userId: string,
    messageId: string,
  ): Promise<{ removed: boolean }> {
    const client = this.getClientOrNull();
    if (!client) return { removed: false };
    const inboxKey = `relay:inbox:${userId}`;
    const raw = await client.lrange(inboxKey, 0, -1);
    const match = raw.find(
      (r) => (JSON.parse(r) as RelayEnvelope).messageId === messageId,
    );
    if (match === undefined) return { removed: false };
    await client.lrem(inboxKey, 1, match);
    return { removed: true };
  }
}
