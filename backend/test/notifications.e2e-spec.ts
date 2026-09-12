import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Notifications (e2e)', () => {
  let app: INestApplication;
  let alice: string;
  let bob: string;

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
        email: `n13a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `n13a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;

    const b = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `n13b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `n13b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bob = b.body.token;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('follow generates a notification; GET list, PATCH single read, ownership 403', async () => {
    await request(app.getHttpServer())
      .post(`/v1/users/n13a_${stamp}/follow`)
      .set(auth(bob))
      .expect(201);

    const list = await request(app.getHttpServer())
      .get('/v1/notifications')
      .set(auth(alice))
      .expect(200);
    expect(list.body.unreadCount).toBe(1);
    const nid = list.body.notifications[0].id as string;

    // bob (non-owner) cannot mark alice's notification read
    await request(app.getHttpServer())
      .patch(`/v1/notifications/${nid}`)
      .set(auth(bob))
      .send({ read: true })
      .expect(403);

    // owner marks it read
    await request(app.getHttpServer())
      .patch(`/v1/notifications/${nid}`)
      .set(auth(alice))
      .send({ read: true })
      .expect(200);

    const after = await request(app.getHttpServer())
      .get('/v1/notifications')
      .set(auth(alice))
      .expect(200);
    expect(after.body.unreadCount).toBe(0);
  });

  it('mark all read 204; unauth 401; nonexistent PATCH 404', async () => {
    await request(app.getHttpServer())
      .post('/v1/notifications/read')
      .set(auth(alice))
      .expect(204);
    await request(app.getHttpServer()).get('/v1/notifications').expect(401);
    await request(app.getHttpServer())
      .patch('/v1/notifications/00000000-0000-0000-0000-000000000000')
      .set(auth(alice))
      .send({ read: true })
      .expect(404);
  });
});
