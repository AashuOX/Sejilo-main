import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { MeshRelayService, RelayEnvelope } from './mesh-relay.service';
import { RedisService } from '../redis/redis.service';
import { RelayMessageDto } from './dto/relay-message.dto';

/**
 * In-memory fake of the ioredis client surface used by MeshRelayService.
 * Using a real in-memory implementation (not permissive jest mocks) means the
 * service logic — dedup, TTL rejection, multi-hop, ack — is actually executed.
 */
function createFakeRedis() {
  const lists = new Map<string, string[]>();
  const kv = new Map<string, string>();
  const client: any = {
    set: jest.fn((key: string, value: string, _m: string, _t: number, nx?: string) => {
      if (nx === 'NX' && kv.has(key)) return null;
      kv.set(key, value);
      return 'OK';
    }),
    rpush: jest.fn((key: string, value: string) => {
      const arr = lists.get(key) ?? [];
      arr.push(value);
      lists.set(key, arr);
      return arr.length;
    }),
    expire: jest.fn(() => 1),
    lrange: jest.fn((key: string) => lists.get(key) ?? []),
    del: jest.fn((key: string) => {
      const had = lists.has(key);
      lists.delete(key);
      return had ? 1 : 0;
    }),
    lrem: jest.fn((key: string, _count: number, value: string) => {
      const arr = lists.get(key) ?? [];
      const idx = arr.indexOf(value);
      if (idx === -1) return 0;
      arr.splice(idx, 1);
      lists.set(key, arr);
      return 1;
    }),
    llen: jest.fn((key: string) => lists.get(key)?.length ?? 0),
  };
  return { client, lists, kv };
}

const baseDto = (overrides: Partial<RelayMessageDto> = {}): RelayMessageDto =>
  ({
    messageId: 'm1',
    destinationId: 'dest',
    hopCount: 0,
    maxHops: 5,
    ttl: 60,
    encryptedPayload: 'ciphertext',
    ...overrides,
  }) as RelayMessageDto;

describe('MeshRelayService', () => {
  let service: MeshRelayService;
  let redis: any;
  let fake: ReturnType<typeof createFakeRedis>;

  beforeEach(async () => {
    fake = createFakeRedis();
    redis = { getClient: jest.fn(() => fake.client) };
    const module: TestingModule = await Test.createTestingModule({
      providers: [MeshRelayService, { provide: RedisService, useValue: redis }],
    }).compile();
    service = module.get<MeshRelayService>(MeshRelayService);
  });

  it('1. queues a valid envelope and stores it in the destination inbox', async () => {
    const res = await service.relay('src', baseDto());
    expect(res.status).toBe('queued');
    expect(res.expiresAt).toBeGreaterThan(Date.now());

    const inbox = await service.fetchInbox('dest');
    expect(inbox).toHaveLength(1);
    expect(inbox[0].messageId).toBe('m1');
    expect(inbox[0].sourceId).toBe('src');
    expect(inbox[0].destinationId).toBe('dest');
  });

  it('2. deduplicates per destination so each message is delivered once', async () => {
    expect((await service.relay('src', baseDto())).status).toBe('queued');
    const second = await service.relay('src', baseDto());
    expect(second.status).toBe('duplicate');

    const inbox = await service.fetchInbox('dest');
    expect(inbox).toHaveLength(1);
  });

  it('3. rejects when the TTL has already expired', async () => {
    const res = await service.relay('src', baseDto({ expiresAt: Date.now() - 1000 }));
    expect(res.status).toBe('rejected');
    expect(res.reason).toBe('expired');
    expect(await service.getInboxCount('dest')).toBe(0);
  });

  it('4. rejects when hopCount >= maxHops', async () => {
    const res = await service.relay('src', baseDto({ hopCount: 5, maxHops: 5 }));
    expect(res.status).toBe('rejected');
    expect(res.reason).toBe('max hops exceeded');
  });

  it('5. throws BadRequest when Redis is offline (write path)', async () => {
    redis.getClient.mockReturnValue(null);
    await expect(service.relay('src', baseDto())).rejects.toThrow(BadRequestException);
  });

  it('6. fetchInbox returns and then clears the inbox', async () => {
    await service.relay('src', baseDto());
    expect((await service.fetchInbox('dest')).length).toBe(1);
    expect((await service.fetchInbox('dest')).length).toBe(0);
  });

  it('7. peekInbox / getInboxCount do not clear the inbox', async () => {
    await service.relay('src', baseDto());
    expect(await service.getInboxCount('dest')).toBe(1);
    expect((await service.peekInbox('dest')).length).toBe(1);
    expect(await service.getInboxCount('dest')).toBe(1);
  });

  it('8. acknowledge removes only the targeted message', async () => {
    await service.relay('src', baseDto({ messageId: 'a' }));
    await service.relay('src', baseDto({ messageId: 'b' }));

    const ack = await service.acknowledge('dest', 'a');
    expect(ack.removed).toBe(true);
    expect(await service.getInboxCount('dest')).toBe(1);

    const remaining = await service.fetchInbox('dest');
    expect(remaining.map((e) => e.messageId)).toEqual(['b']);
  });

  it('9. acknowledge returns removed=false for an unknown message', async () => {
    const ack = await service.acknowledge('dest', 'missing');
    expect(ack.removed).toBe(false);
  });

  it('10. relayHop forwards toward the next-hop peer with an incremented hop', async () => {
    // A cannot reach dest directly, so it relays to the next-hop peer B.
    await service.relay('A', baseDto({ messageId: 'multi', destinationId: 'B', hopCount: 0, maxHops: 3 }));
    const env = (await service.peekInbox('B'))[0] as RelayEnvelope;

    // B forwards toward C (the next hop on the path).
    const hop = await service.relayHop(env, 'C');
    expect(hop.status).toBe('queued');

    const forwarded = (await service.peekInbox('C'))[0] as RelayEnvelope;
    expect(forwarded.hopCount).toBe(1);
    expect(forwarded.destinationId).toBe('C');
  });

  it('11. relayHop rejects once the hop limit is reached', async () => {
    await service.relay('A', baseDto({ messageId: 'deep', destinationId: 'B', hopCount: 2, maxHops: 3 }));
    const env = (await service.peekInbox('B'))[0] as RelayEnvelope;

    const hop = await service.relayHop(env, 'C');
    expect(hop.status).toBe('rejected');
    expect(hop.reason).toBe('max hops exceeded');
  });

  it('12. read paths degrade gracefully when Redis is offline', async () => {
    redis.getClient.mockReturnValue(null);
    expect(await service.fetchInbox('dest')).toEqual([]);
    expect(await service.peekInbox('dest')).toEqual([]);
    expect(await service.getInboxCount('dest')).toBe(0);
    expect((await service.acknowledge('dest', 'x')).removed).toBe(false);
  });
});
