import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Sync (e2e)', () => {
  let app: INestApplication;
  let alice: string;
  let bobId: string;

  const stamp = Date.now();

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
    );
    await app.init();

    const a = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `s16a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `s16a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;

    const b = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `s16b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `s16b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bobId = b.body.profile.id as string;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('GET returns cursor; POST ingests pending message; GET returns it', async () => {
    const initial = await request(app.getHttpServer())
      .get('/v1/sync')
      .set(auth(alice))
      .expect(200);
    expect(initial.body.syncCursor).toBeDefined();
    expect(initial.body.messages).toEqual([]);

    const conv = await request(app.getHttpServer())
      .post('/v1/chat/conversations')
      .set(auth(alice))
      .send({ kind: 'direct', recipientUserId: bobId })
      .expect(201);
    const cid = conv.body.id as string;

    const push = await request(app.getHttpServer())
      .post('/v1/sync')
      .set(auth(alice))
      .send({
        lastSyncCursor: '0',
        pendingMessages: [
          {
            clientMessageId: `cli_${stamp}`,
            conversationId: cid,
            text: 'offline hello',
            createdAt: new Date().toISOString(),
          },
        ],
      })
      .expect(201);
    expect(push.body.acknowledgedMessageIds).toContain(`cli_${stamp}`);

    const after = await request(app.getHttpServer())
      .get('/v1/sync')
      .set(auth(alice))
      .expect(200);
    expect(after.body.messages.length).toBeGreaterThanOrEqual(1);
  });

  it('unauthenticated sync 401', async () => {
    await request(app.getHttpServer()).get('/v1/sync').expect(401);
  });

  it('conflict handling: Last-Write-Wins on updatedAt; deletion wins', async () => {
    const conv = await request(app.getHttpServer())
      .post('/v1/chat/conversations')
      .set(auth(alice))
      .send({ kind: 'direct', recipientUserId: bobId })
      .expect(201);
    const cid = conv.body.id as string;
    const cmid = `conflict_${stamp}`;

    const base = new Date(Date.now() - 10000).toISOString();

    // First write (v1)
    await request(app.getHttpServer())
      .post('/v1/sync')
      .set(auth(alice))
      .send({
        lastSyncCursor: '0',
        pendingMessages: [
          { clientMessageId: cmid, conversationId: cid, text: 'v1', createdAt: base, updatedAt: base },
        ],
      })
      .expect(201);

    // Capture a timestamp strictly after the first write's server updatedAt.
    const later = new Date().toISOString();

    // Newer edit (v2) should win
    await request(app.getHttpServer())
      .post('/v1/sync')
      .set(auth(alice))
      .send({
        lastSyncCursor: '0',
        pendingMessages: [
          { clientMessageId: cmid, conversationId: cid, text: 'v2', createdAt: base, updatedAt: later },
        ],
      })
      .expect(201);

    // Stale edit (v3, older timestamp) must be ignored
    await request(app.getHttpServer())
      .post('/v1/sync')
      .set(auth(alice))
      .send({
        lastSyncCursor: '0',
        pendingMessages: [
          { clientMessageId: cmid, conversationId: cid, text: 'v3', createdAt: base, updatedAt: base },
        ],
      })
      .expect(201);

    const after = await request(app.getHttpServer())
      .get('/v1/sync')
      .set(auth(alice))
      .expect(200);
    const texts = after.body.messages.map((m: any) => m.text);
    expect(texts.filter((t: string) => t === 'v2').length).toBeGreaterThanOrEqual(1);
    expect(texts.filter((t: string) => t === 'v1').length).toBe(0);
    expect(texts.filter((t: string) => t === 'v3').length).toBe(0);

    // Deletion intent wins regardless of timestamp
    await request(app.getHttpServer())
      .post('/v1/sync')
      .set(auth(alice))
      .send({
        lastSyncCursor: '0',
        pendingMessages: [
          { clientMessageId: cmid, conversationId: cid, text: 'v2', createdAt: base, updatedAt: base, deleted: true },
        ],
      })
      .expect(201);

    const deleted = await request(app.getHttpServer())
      .get('/v1/sync')
      .set(auth(alice))
      .expect(200);
    // Deleted messages are excluded from sync results
    expect(deleted.body.messages.filter((m: any) => m.text === 'v2').length).toBe(0);
  });
});
