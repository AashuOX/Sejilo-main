import request from 'supertest';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppModule } from '../src/app.module';

/**
 * STEP 23/25 — Mesh relay.
 *
 * These endpoints depend on Redis (which lives inside Docker), so this spec
 * targets the running backend at BASE_URL (default http://localhost:8080),
 * mirroring chat-ws.e2e-spec.ts. Start the stack with `docker compose up -d`.
 */
const BASE = process.env.BASE_URL || 'http://localhost:8080';
const stamp = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;

describe('Mesh relay (e2e, STEP 23/25)', () => {
  let app: INestApplication; // only used for ValidationPipe parity; calls go to BASE.
  let aliceToken: string;
  let aliceId: string;
  let bobToken: string;
  let bobId: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
    );
    await app.init();

    const a = await request(BASE)
      .post('/v1/users')
      .send({
        email: `mesh_a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `mesh_a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    aliceToken = a.body.token;
    aliceId = a.body.id;

    const b = await request(BASE)
      .post('/v1/users')
      .send({
        email: `mesh_b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `mesh_b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bobToken = b.body.token;
    bobId = b.body.id;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('relays an envelope and the recipient can fetch it', async () => {
    await request(BASE)
      .post('/v1/mesh/relay')
      .set(auth(aliceToken))
      .send({
        messageId: `relay1_${stamp}`,
        destinationId: bobId,
        hopCount: 0,
        maxHops: 5,
        ttl: 300,
        encryptedPayload: 'enc-aaa',
      })
      .expect(201)
      .expect((res) => expect(res.body.status).toBe('queued'));

    const inbox = await request(BASE)
      .get('/v1/mesh/inbox')
      .set(auth(bobToken))
      .expect(200);
    expect(inbox.body.messages.length).toBe(1);
    expect(inbox.body.messages[0].encryptedPayload).toBe('enc-aaa');
    expect(inbox.body.messages[0].sourceId).toBe(aliceId);
  });

  it('deduplicates by messageId', async () => {
    await request(BASE)
      .post('/v1/mesh/relay')
      .set(auth(aliceToken))
      .send({
        messageId: `relay_dup_${stamp}`,
        destinationId: bobId,
        hopCount: 0,
        maxHops: 5,
        ttl: 300,
        encryptedPayload: 'x',
      })
      .expect(201);
    // same messageId again -> duplicate
    await request(BASE)
      .post('/v1/mesh/relay')
      .set(auth(aliceToken))
      .send({
        messageId: `relay_dup_${stamp}`,
        destinationId: bobId,
        hopCount: 0,
        maxHops: 5,
        ttl: 300,
        encryptedPayload: 'x',
      })
      .expect(201)
      .expect((res) => expect(res.body.status).toBe('duplicate'));
  });

  it('rejects when hopCount >= maxHops', async () => {
    await request(BASE)
      .post('/v1/mesh/relay')
      .set(auth(aliceToken))
      .send({
        messageId: `relay_hops_${stamp}`,
        destinationId: bobId,
        hopCount: 5,
        maxHops: 5,
        ttl: 300,
        encryptedPayload: 'y',
      })
      .expect(201)
      .expect((res) => {
        expect(res.body.status).toBe('rejected');
        expect(res.body.reason).toBe('max hops exceeded');
      });
  });

  it('requires authentication', async () => {
    await request(BASE).get('/v1/mesh/inbox').expect(401);
    await request(BASE)
      .post('/v1/mesh/relay')
      .send({
        messageId: `relay_noauth_${stamp}`,
        destinationId: bobId,
        hopCount: 0,
        maxHops: 5,
        ttl: 300,
        encryptedPayload: 'z',
      })
      .expect(401);
  });

  it('clears the inbox after fetch', async () => {
    const first = await request(BASE).get('/v1/mesh/inbox').set(auth(bobToken));
    expect(first.body.messages.length).toBeGreaterThan(0);
    const second = await request(BASE).get('/v1/mesh/inbox').set(auth(bobToken));
    expect(second.body.messages.length).toBe(0);
  });

  it('Mesh -> Internet sync: relayed envelope appears in GET /v1/sync', async () => {
    const mid = `sync_mesh_${stamp}`;
    await request(BASE)
      .post('/v1/mesh/relay')
      .set(auth(aliceToken))
      .send({
        messageId: mid,
        destinationId: bobId,
        hopCount: 0,
        maxHops: 5,
        ttl: 300,
        encryptedPayload: 'enc-sync',
      })
      .expect(201);

    const synced = await request(BASE).get('/v1/sync').set(auth(bobToken)).expect(200);
    expect(Array.isArray(synced.body.meshEnvelopes)).toBe(true);
    const env = synced.body.meshEnvelopes.find((e: any) => e.messageId === mid);
    expect(env).toBeDefined();
    expect(env.encryptedPayload).toBe('enc-sync');
    expect(env.sourceId).toBe(aliceId);
  });
});
