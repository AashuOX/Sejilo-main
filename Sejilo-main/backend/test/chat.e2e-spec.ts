import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Chat (e2e)', () => {
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
        email: `c14a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `c14a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;

    const b = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `c14b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `c14b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bobId = b.body.profile.id as string;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('conversation + message lifecycle', async () => {
    const conv = await request(app.getHttpServer())
      .post('/v1/chat/conversations')
      .set(auth(alice))
      .send({ kind: 'direct', recipientUserId: bobId })
      .expect(201);
    const cid = conv.body.id as string;

    const list = await request(app.getHttpServer())
      .get('/v1/chat/conversations')
      .set(auth(alice))
      .expect(200);
    expect(Array.isArray(list.body.conversations ?? list.body)).toBe(true);

    const msg = await request(app.getHttpServer())
      .post(`/v1/chat/conversations/${cid}/messages`)
      .set(auth(alice))
      .send({ text: 'hello there', clientMessageId: `cli_${stamp}` })
      .expect(201);
    const mid = msg.body.id as string;

    await request(app.getHttpServer())
      .get(`/v1/chat/conversations/${cid}/messages`)
      .set(auth(alice))
      .expect(200);

    await request(app.getHttpServer())
      .post(`/v1/chat/messages/${mid}/status`)
      .set(auth(alice))
      .send({ status: 'read' })
      .expect(204);

    await request(app.getHttpServer())
      .post(`/v1/chat/messages/${mid}/reactions`)
      .set(auth(alice))
      .send({ emoji: 'like' })
      .expect(204);

    await request(app.getHttpServer())
      .delete(`/v1/chat/messages/${mid}`)
      .set(auth(alice))
      .expect(204);
  });

  it('unauthenticated chat access 401', async () => {
    await request(app.getHttpServer()).get('/v1/chat/conversations').expect(401);
  });
});
